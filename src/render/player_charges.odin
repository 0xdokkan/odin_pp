package render

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import game "../game"
import grid "../grid"

// The player's charges on the board (game/player_charges.odin): the foes
// FERETRO's arrows reach while Ctrl is held, and the die of the DADO DEL
// DESTINO at the struck card. Its die is a little paper tag cut and inked like
// the damage tokens (living_token.odin): the die's own pixel outline (one for
// each die of the ladder) and the face rolled in the colour of what it did. It
// pops out of the card's left side as the blow lands (its right side is the
// damage token's), hangs a moment and drops away; the outcome is said in
// Italian over the card (fate_outcome_label).

LIVING_MAX_FATES :: 6
LIVING_FATE_SECONDS :: f64(1.2)
// A die already shown is never shown again for as long as its cue could last.
LIVING_FATE_SEEN :: 12
LIVING_FATE_SEEN_SECONDS :: f64(4)

Living_Fate :: struct {
	used: bool,
	event: game.Game_Event,
	born: f64,
	// The card's chest and its half width on screen, while it is on the board.
	at: rl.Vector3,
	half: f32,
}

// A die shown: its event and the command that rolled it (Presentation_Cue.batch).
// Two bumps in a row from the same cell on the same foe that roll the same face
// have the same event: each is its own die all the same.
Living_Fate_Seen :: struct {
	event: game.Game_Event,
	batch: u32,
	at: f64,
}

Living_Fates :: struct {
	tokens: [LIVING_MAX_FATES]Living_Fate,
	seen: [LIVING_FATE_SEEN]Living_Fate_Seen,
	seen_next: int,
}

// 7 pixels wide, rows top to bottom, bit 6 the leftmost column: the outline
// of each die of the ladder (d4, d6, d8, d10, d12, d20).
@(rodata)
FATE_DIE_GLYPHS := [6][7]u8{
	{0b0001000, 0b0010100, 0b0010100, 0b0100010, 0b0100010, 0b1000001, 0b1111111},
	{0b1111111, 0b1000001, 0b1010001, 0b1000001, 0b1000101, 0b1000001, 0b1111111},
	{0b0001000, 0b0010100, 0b0100010, 0b1000001, 0b0100010, 0b0010100, 0b0001000},
	{0b0001000, 0b0010100, 0b0100010, 0b1000001, 0b1100011, 0b0011100, 0b0000000},
	{0b0001000, 0b0110110, 0b1000001, 0b1000001, 0b0100010, 0b0100010, 0b0111110},
	{0b0011100, 0b0100010, 0b1001001, 0b1010101, 0b1111111, 0b0100010, 0b0011100},
}

fate_die_glyph :: proc(sides: i32) -> int {
	ladder := game.DICE_LADDER
	for step, index in ladder { if step == sides { return index } }
	return 0
}

// The ink of what a face did: venom, ember, frost, a cure, gold, blood.
fate_outcome_ink :: proc(outcome: game.Fate_Outcome) -> rl.Color {
	switch outcome {
	case .Poison: return {40, 128, 70, 255}
	case .Burn: return STATUS_TAG_EMBER
	case .Slow: return STATUS_TAG_FROST
	case .Lifesteal: return LIVING_TOKEN_HEAL
	case .Critical: return {176, 122, 20, 255}
	case .Lethal: return LIVING_TOKEN_DAMAGE
	}
	return LIVING_TOKEN_INK
}

// What the Dado del Destino's face did, in Italian (VELENO 1, BRUCIATURA 2,
// RALLENTAMENTO 3, RUBA VITA +2, CRITICO, LETALE), after the die and its face
// (d8 4 / ...) where no paper token shows them.
fate_outcome_label :: proc(event: game.Game_Event, with_die: bool) -> (label: cstring, color: rl.Color) {
	text: string
	switch game.Fate_Outcome(event.duration) {
	case .Poison: text, color = fmt.tprintf("VELENO %d", event.amount), rl.Color{126, 211, 174, 255}
	case .Burn: text, color = fmt.tprintf("BRUCIATURA %d", event.amount), rl.Color{244, 157, 104, 255}
	case .Slow: text, color = fmt.tprintf("RALLENTAMENTO %d", event.amount), HUD_FROST
	case .Lifesteal: text, color = fmt.tprintf("RUBA VITA +%d", event.amount), rl.Color{128, 220, 190, 255}
	case .Critical: text, color = "CRITICO", TACTICAL_FEEDBACK_CRITICAL
	case .Lethal: text, color = "LETALE", TACTICAL_FEEDBACK_HIT
	}
	if with_die { return fmt.ctprintf("%s %d / %s", die_label(event.dice_roll.sides), event.dice_roll.total, text), color }
	return fmt.ctprintf("%s", text), color
}

// The tag's size in tag pixels: the die, a pixel of paper, the face's figures.
fate_token_size :: proc(face: i32) -> (width, height: int) {
	return living_heart_size(fmt.tprintf("%d", max(face, 0)))
}

// How far left of the struck card's chest (`base`, the card `half` wide on
// each side) the tag of w x h tag pixels hangs once it has popped out (two
// screen pixels to a tag pixel, its bottom 10 over the chest): just out of the
// card's left side, or out past the card's own heart (`heart`, when shown)
// where it would cover it, as a narrow card's heart reaches past that side.
fate_tag_reach :: proc(base: rl.Vector2, half: f32, w, h: int, heart: rl.Rectangle, hearted: bool) -> (reach: f32) {
	reach = half*0.9+8
	if !hearted { return }
	rest := rl.Rectangle{base.x-reach-f32(w), base.y-10-f32(h)*2, f32(w)*2, f32(h)*2}
	if rl.CheckCollisionRecs(rest, fate_heart_keep(heart)) {
		reach += rest.x+rest.width-(heart.x-3)
	}
	return
}

// The heart's tag and the two pixels around it that the die's tag never takes.
fate_heart_keep :: proc(heart: rl.Rectangle) -> rl.Rectangle {
	return {heart.x-2, heart.y-2, heart.width+4, heart.height+4}
}

// The tag `t` seconds after it is born: its top left (whole screen pixels),
// its pixel and its opacity. It comes out of the card's left side with a pop
// on the pixel grid (a pixel of one screen pixel, then three, then two), hangs
// and drops away. While the struck card's heart shows, no frame of it takes
// the heart's place, the pop's larger pixels included: where it would, the tag
// stands just short of the heart's left side.
fate_tag_place :: proc(base: rl.Vector2, half: f32, w, h: int, t: f32, heart: rl.Rectangle, hearted: bool) -> (at: rl.Vector2, pixel, alpha: f32) {
	pixel = 2
	if t < 0.05 { pixel = 1 } else if t < 0.12 { pixel = 3 }
	out := 1-math.pow(1-min(t/0.2, 1), 3)
	x := -fate_tag_reach(base, half, w, h, heart, hearted)*out
	y := -10*out-4*t
	alpha = 1
	if t > 0.9 {
		fall := (t-0.9)/f32(LIVING_FATE_SECONDS-0.9)
		y += 30*fall*fall
		alpha = clamp(1-fall, 0, 1)
	}
	size := rl.Vector2{f32(w)*pixel, f32(h)*pixel}
	at = {math.round(base.x+x-size.x*0.5), math.round(base.y+y-size.y)}
	if hearted && rl.CheckCollisionRecs({at.x, at.y, size.x, size.y}, fate_heart_keep(heart)) {
		at.x = math.floor(heart.x-3-size.x)
	}
	return
}

// Once per frame with the living cards: a token for each die now showing,
// once however long its cue lasts.
update_fate_tokens :: proc(renderer: ^Renderer, now: f64) {
	state := renderer.tactical.living_state
	if state == nil { return }
	fates := &state.fates
	for &token in fates.tokens {
		if token.used && now-token.born > LIVING_FATE_SECONDS { token = {} }
	}
	for offset in 0..<renderer_active_cue_count(renderer) {
		cue, found := renderer_active_cue_at(renderer, offset)
		if !found || !cue.started || cue.kind != .Fate_Rolled { continue }
		if _, actor := presentation_actor_in_view(renderer.tactical.snapshot, cue.event.target); !actor { continue }
		landing, _ := attack_fx_landing_in(renderer, cue.event.target, now, game.PLAYER_ENTITY)
		living_fate_spawn(fates, cue.event, now+landing, cue.batch)
	}
}

// A token for `event`, rolled by command `batch`, born at `born`, unless that
// die already showed.
living_fate_spawn :: proc(fates: ^Living_Fates, event: game.Game_Event, born: f64, batch := u32(0)) -> bool {
	for seen in fates.seen {
		if seen.at > 0 && born-seen.at < LIVING_FATE_SEEN_SECONDS && seen.batch == batch && seen.event == event { return false }
	}
	fates.seen[fates.seen_next] = {event = event, batch = batch, at = born}
	fates.seen_next = (fates.seen_next+1)%len(fates.seen)
	slot := &fates.tokens[0]
	for &token in fates.tokens {
		if !token.used { slot = &token; break }
		if token.born < slot.born { slot = &token }
	}
	slot^ = {used = true, event = event, born = born}
	return true
}

// The tag with its top left at `at` (whole screen pixels).
draw_fate_tag :: proc(at: rl.Vector2, sides, face: i32, outcome: game.Fate_Outcome, pixel: f32, alpha: f32 = 1) {
	text := fmt.tprintf("%d", max(face, 0))
	w, h := living_heart_size(text)
	ink := draw_paper_tag(at, w, h, pixel, alpha)
	glyph := FATE_DIE_GLYPHS[fate_die_glyph(sides)]
	for row in 0..<7 {
		draw_pixel_row(glyph[row], LIVING_HEART_WIDTH, at.x+3*pixel, at.y+f32(3+row)*pixel, pixel, ink)
	}
	draw_paper_tag_text(at, f32(3+LIVING_HEART_WIDTH+1), text, pixel, color_with_opacity(fate_outcome_ink(outcome), alpha))
}

draw_fate_tokens :: proc(renderer: ^Renderer) {
	v := &renderer.tactical
	if !v.living || v.living_state == nil || v.snapshot == nil || !living_cards_ready(renderer) { return }
	now := renderer.sprite_assets.elapsed
	for &token in v.living_state.fates.tokens {
		if !token.used || now < token.born { continue }
		entity := token.event.target
		// Follow the card while it is on the board; a fallen foe keeps its spot.
		if actor, found := presentation_actor_in_view(v.snapshot, entity); found && actor.visible {
			cell := grid.Position{int(math.round(actor.position.x)), int(math.round(actor.position.y))}
			if !tactical_overlay_visible(renderer, cell) { continue }
			key := sprite_key_for_enemy(actor.archetype)
			if character, ok := flipbook_character(key); ok {
				p := living_billboard_geometry(renderer, character, key, actor.position, true, entity).card_points
				bottom, top := (p[1]+p[2])*0.5, (p[0]+p[3])*0.5
				token.at = bottom+(top-bottom)*0.5
				left := tactical_project(renderer, {p[0].x, p[0].z}, p[0].y)
				right := tactical_project(renderer, {p[3].x, p[3].z}, p[3].y)
				token.half = abs(right.x-left.x)*0.5
			}
		}
		if token.at == {} { continue }
		w, h := fate_token_size(token.event.dice_roll.total)
		base := tactical_project(renderer, {token.at.x, token.at.z}, token.at.y)
		// Out of the card's left side, clear of the heart over its head.
		heart, hearted := tactical_label_heart(v.labels, entity.id)
		at, pixel, alpha := fate_tag_place({base.x, base.y}, token.half, w, h, f32(now-token.born), heart, hearted)
		draw_fate_tag(at, token.event.dice_roll.sides, token.event.dice_roll.total, game.Fate_Outcome(token.event.duration), pixel, alpha)
	}
}

FERETRO_AIM_FILL :: rl.Color{226, 186, 120, 70}
FERETRO_AIM_LINE :: rl.Color{246, 214, 150, 230}
FERETRO_AIM_HOT :: rl.Color{255, 236, 170, 255}

// A ring on the floor around `cell` (screen lines over the board), cut by
// four ticks: the mark of a foe the arrows reach.
draw_aim_reticle :: proc(renderer: ^Renderer, cell: grid.Position, radius, thick: f32, color: rl.Color) {
	center := rl.Vector2{f32(cell.x)+0.5, f32(cell.y)+0.5}
	at :: proc(renderer: ^Renderer, center: rl.Vector2, angle, radius: f32) -> rl.Vector2 {
		p := tactical_project(renderer, {center.x+math.cos(angle)*radius, center.y+math.sin(angle)*radius}, 0.03)
		return {p.x, p.y}
	}
	SEGMENTS :: 28
	for index in 0..<SEGMENTS {
		a, b := f32(index)*math.TAU/SEGMENTS, f32(index+1)*math.TAU/SEGMENTS
		// The gaps where the ticks cross the ring.
		if index%7 == 0 { continue }
		rl.DrawLineEx(at(renderer, center, a, radius), at(renderer, center, b, radius), thick, color)
	}
	for quarter in 0..<4 {
		angle := f32(quarter)*math.PI*0.5+math.TAU/SEGMENTS*0.5
		rl.DrawLineEx(at(renderer, center, angle, radius*0.72), at(renderer, center, angle, radius*1.18), thick, color)
	}
}

// FERETRO while Ctrl is held (Tactical_View.arrow_aim): every foe the arrows
// reach marked on its cell and by a ring at its feet, the one under the mouse
// brighter, with the line its arrow would fly.
draw_arrow_aim :: proc(renderer: ^Renderer, room: ^game.Room) {
	if renderer == nil || room == nil || room.player == nil || !renderer.tactical.arrow_aim || game.player_charges(room, .Arrows) <= 0 { return }
	hovered: grid.Position
	has_hovered := false
	for enemy in room.enemies {
		foe := game.enemy_entity(enemy.id)
		if !game.player_arrow_target_is_valid(room, foe) || !tactical_render_visible(renderer, enemy.position) { continue }
		if renderer.has_hovered_cell && renderer.hovered_cell == enemy.position { hovered, has_hovered = enemy.position, true; continue }
		draw_card_range_cell(renderer, enemy.position, FERETRO_AIM_FILL, FERETRO_AIM_LINE)
		draw_aim_reticle(renderer, enemy.position, 0.46, 2, FERETRO_AIM_LINE)
	}
	if !has_hovered { return }
	path: [game.MAX_TARGETING_PATH_CELLS]grid.Position
	count, traced := game.trace_targeting_line(room.player.position, hovered, &path)
	if traced {
		for cell in path[:max(count-1, 0)] { draw_card_range_cell(renderer, cell, {238, 174, 73, 26}, {238, 174, 73, 120}) }
	}
	draw_card_range_cell(renderer, hovered, {246, 207, 92, 120}, FERETRO_AIM_HOT)
	draw_aim_reticle(renderer, hovered, 0.5, 3, FERETRO_AIM_HOT)
}
