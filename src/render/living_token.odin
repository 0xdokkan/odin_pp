package render

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import game "../game"
import grid "../grid"

// Damage and healing tokens of a living board: little paper cards, cut and
// inked like the standees, that flick out of a card when it is struck or
// healed and carry the amount in pixel figures, red for a blow and green for a
// cure. They pop out with the hurt drawing's impact and slide out of the
// card's side (clear of the heart above it), hang a moment and drop
// away. A token outlives the cue that spawned it,
// so it lives in the living state; its picture is made the first time it is
// drawn.

LIVING_MAX_TOKENS :: 16
LIVING_MAX_BLOWS :: LIVING_MAX_TOKENS*2
LIVING_TOKEN_SECONDS :: f64(1.15)
// The hurt drawings land their blow ~0.1 s into the cue.
LIVING_TOKEN_DELAY :: f64(0.1)

LIVING_TOKEN_PAPER :: rl.Color{241, 239, 230, 255}
LIVING_TOKEN_INK :: rl.Color{13, 20, 30, 255}
LIVING_TOKEN_EDGE :: rl.Color{164, 152, 131, 255}
LIVING_TOKEN_DAMAGE :: rl.Color{200, 38, 44, 255}
LIVING_TOKEN_HEAL :: rl.Color{40, 150, 76, 255}

Living_Token :: struct {
	used, heal: bool,
	amount: i32,
	// What makes a blow this one: one token per blow, however long its cue,
	// and the command it came with (Presentation_Cue.batch): two bumps of the
	// same damage on the same foe a second apart are two blows.
	entity, source: game.Entity_Ref,
	pulse: u64,
	group: u32,
	batch: u32,
	born: f64,
	// Earlier tokens still showing on the same card: this one goes beside them.
	stack: int,
	// The card's chest and its half width on screen, while it is on the board.
	at: rl.Vector3,
	half: f32,
	texture: rl.Texture2D,
}

// A blow already given its token, on the world's clock (tactical_world_time):
// a cue held while the player is in his shadow never gives a second one, even
// once the first token has dropped away.
Living_Blow :: struct {
	used, heal: bool,
	amount: i32,
	entity, source: game.Entity_Ref,
	pulse: u64,
	group, batch: u32,
	at: f64,
}

// 5x7 pixel figures, rows top to bottom, bit 4 the leftmost column.
@(rodata)
LIVING_TOKEN_GLYPHS := [13][7]u8{
	{0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110}, // 0
	{0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110}, // 1
	{0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111}, // 2
	{0b11110, 0b00001, 0b00001, 0b01110, 0b00001, 0b00001, 0b11110}, // 3
	{0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010}, // 4
	{0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110}, // 5
	{0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110}, // 6
	{0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000}, // 7
	{0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110}, // 8
	{0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100}, // 9
	{0b00000, 0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0b00000}, // +
	{0b00000, 0b00000, 0b00000, 0b11111, 0b00000, 0b00000, 0b00000}, // -
	{0b00001, 0b00010, 0b00010, 0b00100, 0b01000, 0b01000, 0b10000}, // /
}

living_token_glyph :: proc(r: u8) -> (index: int, ok: bool) {
	switch r {
	case '0'..='9': return int(r-'0'), true
	case '+': return 10, true
	case '-': return 11, true
	case '/': return 12, true
	}
	return
}

living_token_text :: proc(amount: i32, heal: bool) -> string {
	return fmt.tprintf("+%d" if heal else "-%d", amount)
}

// The token's picture in pixels: the paper with its ink line, the cut edge
// one pixel down and right, and the figures with two pixels of paper around.
living_token_size :: proc(text: string) -> (width, height: int) {
	return len(text)*6-1+4+2+1, 7+4+2+1
}

// Whether a blow is already showing: one token per blow, however many frames
// its cue lasts. `world` is the world's clock (the sprite clock when left out);
// `landing` the seconds until the blow lands (a bolt still flying to the card);
// `batch` the command whose cue it is.
living_token_spawn :: proc(state: ^Living_State, event: game.Game_Event, heal: bool, now: f64, world := f64(-1), landing := f64(0),
	batch := u32(0)) -> bool {
	world := world if world >= 0 else now
	for blow in state.blows {
		if blow.used && world-blow.at <= LIVING_TOKEN_SECONDS && blow.entity == event.target && blow.source == event.source &&
		   blow.amount == event.amount && blow.pulse == event.pulse_count && blow.group == event.visual_group && blow.heal == heal &&
		   blow.batch == batch { return false }
	}
	stack := 0
	for &token in state.tokens {
		if !token.used { continue }
		if token.entity == event.target && token.source == event.source && token.amount == event.amount &&
		   token.pulse == event.pulse_count && token.group == event.visual_group && token.heal == heal && token.batch == batch { return false }
		if token.entity == event.target { stack += 1 }
	}
	state.blows[state.blow_next] = {used = true, heal = heal, amount = event.amount, entity = event.target, source = event.source,
		pulse = event.pulse_count, group = event.visual_group, batch = batch, at = world}
	state.blow_next = (state.blow_next+1)%len(state.blows)
	slot: ^Living_Token
	for &token in state.tokens { if !token.used { slot = &token; break } }
	if slot == nil {
		slot = &state.tokens[0]
		for &token in state.tokens { if token.born < slot.born { slot = &token } }
		living_token_free(slot)
	}
	slot^ = {used = true, heal = heal, amount = event.amount, entity = event.target, source = event.source,
		pulse = event.pulse_count, group = event.visual_group, batch = batch, born = now+max(LIVING_TOKEN_DELAY, landing), stack = stack}
	return true
}

living_token_free :: proc(token: ^Living_Token) {
	if token.texture.id != 0 { rl.UnloadTexture(token.texture) }
	token^ = {}
}

living_tokens_free :: proc(state: ^Living_State) {
	if state == nil { return }
	for &token in state.tokens { if token.used { living_token_free(&token) } }
}

// Once per frame with the actors: a token for every blow and cure now playing.
// The tokens keep the sprite clock; `world` is the world's (tactical_world_time).
update_living_tokens :: proc(renderer: ^Renderer, now, world: f64) {
	state := renderer.tactical.living_state
	for &token in state.tokens {
		if token.used && now-token.born > LIVING_TOKEN_SECONDS { living_token_free(&token) }
	}
	for offset in 0..<renderer_active_cue_count(renderer) {
		cue, found := renderer_active_cue_at(renderer, offset)
		if !found || !cue.started { continue }
		heal := cue.kind == .Heal
		if (cue.kind != .Damage && !heal) || cue.event.amount <= 0 { continue }
		if _, actor := presentation_actor_in_view(renderer.tactical.snapshot, cue.event.target); !actor { continue }
		landing, _ := attack_fx_landing_in(renderer, cue.event.target, now, cue.event.source)
		living_token_spawn(state, cue.event, heal, now, world, landing, cue.batch)
	}
}

living_token_texture :: proc(text: string, heal: bool) -> rl.Texture2D {
	width, height := living_token_size(text)
	image := rl.GenImageColor(i32(width), i32(height), rl.BLANK)
	defer rl.UnloadImage(image)
	pw, ph := i32(width-1), i32(height-1)
	// The cut edge behind, then the paper over it.
	rl.ImageDrawRectangle(&image, 1, 1, pw, ph, LIVING_TOKEN_INK)
	rl.ImageDrawRectangle(&image, 2, 2, pw-2, ph-2, LIVING_TOKEN_EDGE)
	rl.ImageDrawRectangle(&image, 0, 0, pw, ph, LIVING_TOKEN_INK)
	rl.ImageDrawRectangle(&image, 1, 1, pw-2, ph-2, LIVING_TOKEN_PAPER)
	// Corners cut by hand.
	for corner in ([4][2]i32{{0, 0}, {pw-1, 0}, {0, ph-1}, {pw, ph}}) { rl.ImageDrawPixel(&image, corner.x, corner.y, rl.BLANK) }
	ink := LIVING_TOKEN_HEAL if heal else LIVING_TOKEN_DAMAGE
	for index in 0..<len(text) {
		glyph, ok := living_token_glyph(text[index])
		if !ok { continue }
		for row in 0..<7 { for column in 0..<5 {
			if LIVING_TOKEN_GLYPHS[glyph][row]&(0b10000>>u8(column)) != 0 {
				rl.ImageDrawPixel(&image, i32(3+index*6+column), i32(3+row), ink)
			}
		} }
	}
	texture := rl.LoadTextureFromImage(image)
	rl.SetTextureFilter(texture, .POINT)
	return texture
}

draw_living_tokens :: proc(renderer: ^Renderer) {
	v := &renderer.tactical
	if !v.living || v.living_state == nil || v.snapshot == nil || !living_cards_ready(renderer) { return }
	now := renderer.sprite_assets.elapsed
	for &token in v.living_state.tokens {
		if !token.used || now < token.born { continue }
		// Follow the card while it is on the board; a fallen foe keeps its
		// spot, and so does the player's card gone into its shadow.
		sunk := token.entity == game.PLAYER_ENTITY && tactical_shadow_showing(renderer) && token.at != {}
		if actor, found := presentation_actor_in_view(v.snapshot, token.entity); found && actor.visible && !sunk {
			cell := grid.Position{int(math.round(actor.position.x)), int(math.round(actor.position.y))}
			if !tactical_render_visible(renderer, cell) { continue }
			key := Sprite_Key.Player if token.entity == game.PLAYER_ENTITY else sprite_key_for_enemy(actor.archetype)
			if character, ok := flipbook_character(key); ok {
				p := living_billboard_geometry(renderer, character, key, actor.position, true, token.entity).card_points
				bottom, top := (p[1]+p[2])*0.5, (p[0]+p[3])*0.5
				token.at = bottom+(top-bottom)*0.55
				left := tactical_project(renderer, {p[0].x, p[0].z}, p[0].y)
				right := tactical_project(renderer, {p[3].x, p[3].z}, p[3].y)
				token.half = abs(right.x-left.x)*0.5
			}
		}
		if token.at == {} { continue }
		if token.texture.id == 0 { token.texture = living_token_texture(living_token_text(token.amount, token.heal), token.heal) }
		t := f32(now-token.born)
		// Flicked out of the figure's chest (a small pop on the pixel grid) to
		// just past the paper's side, a moment's hang, then it drops away.
		scale := f32(2)
		if t < 0.05 { scale = 1 } else if t < 0.11 { scale = 3 }
		out := 1-math.pow(1-min(t/0.2, 1), 3)
		side := f32(1) if token.stack%2 == 0 else -1
		x := side*(token.half*0.85+f32(token.stack/2)*10)*out
		y := -10*out-5*t-f32(token.stack/2)*20
		alpha := f32(1)
		if t > 0.85 {
			fall := (t-0.85)/f32(LIVING_TOKEN_SECONDS-0.85)
			y += 36*fall*fall
			alpha = clamp(1-fall, 0, 1)
		}
		base := tactical_project(renderer, {token.at.x, token.at.z}, token.at.y)
		w, h := f32(token.texture.width)*scale, f32(token.texture.height)*scale
		position := rl.Vector2{math.round(base.x+x-w*0.5), math.round(base.y+y-h)}
		rl.DrawTextureEx(token.texture, position, 0, scale, {255, 255, 255, u8(alpha*255)})
	}
}
