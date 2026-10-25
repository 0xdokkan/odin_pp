package render

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import gfx "../engine/gfx"
import game "../game"
import grid "../engine/grid"
import view "../engine/view"

// An enemy's health on the board: a little paper tag over its head, cut and
// inked like the damage tokens (living_token.odin), with a red pixel heart and
// the health left over the maximum in the same pixel figures. A seven-pixel
// intent lives inside the same tag, after the figures: one compact, stable
// label per enemy, with no floating badge or separate countdown ring.

// 7 pixels wide, rows top to bottom, bit 6 the leftmost column.
@(rodata)
LIVING_HEART_GLYPH := [7]u8{0b0110110, 0b1111111, 0b1111111, 0b1111111, 0b0111110, 0b0011100, 0b0001000}
LIVING_HEART_WIDTH :: 7
// The tag's pixel doubles once a world unit is this wide on screen at the head.
LIVING_HEART_DOUBLE :: f32(96)
@(private)
living_heart_text :: proc(health, max_health: i32) -> string {
	// Reserve the current-HP field from the maximum: damage across a digit
	// boundary must not recenter the paper or move its intent symbol.
	digits := len(fmt.tprintf("%d", max(max_health, 1)))
	current := fmt.tprintf("%d", max(health, 0))
	return fmt.tprintf("%*s/%d", digits, current, max(max_health, 1))
}

// In tag pixels: the heart, a pixel of paper, the figures; paper, ink line and
// cut edge as a token's (living_token_size).
@(private)
living_heart_size :: proc(text: string, with_intent := false) -> (width, height: int) {
	return LIVING_HEART_WIDTH+1+len(text)*6-1+4+2+1+(INTENT_GLYPH_SIZE+4 if with_intent else 0), 7+4+2+1
}

// One row of a pixel figure as runs of lit pixels; bit `width-1` is the leftmost.
@(private)
draw_pixel_row :: proc(bits: u8, width: int, x, y, pixel: f32, color: rl.Color) {
	column := 0
	for column < width {
		if bits&(u8(1)<<u8(width-1-column)) == 0 { column += 1; continue }
		start := column
		for column < width && bits&(u8(1)<<u8(width-1-column)) != 0 { column += 1 }
		rl.DrawRectangleRec({x+f32(start)*pixel, y, f32(column-start)*pixel, pixel}, color)
	}
}

// A tag's paper, `w` by `h` tag pixels with its top left at `at` (whole
// screen pixels), `pixel` screen pixels to a tag pixel: living_token_texture's
// picture, drawn in place with pieces that never overlap, so a fading tag
// stays even. Its ink, for the figures drawn on it.
@(private)
draw_paper_tag :: proc(at: rl.Vector2, w, h: int, pixel: f32, alpha: f32 = 1) -> (ink: rl.Color) {
	pw, ph := f32(w-1), f32(h-1)
	box :: proc(at: rl.Vector2, pixel, x, y, w, h: f32, color: rl.Color) {
		rl.DrawRectangleRec({at.x+x*pixel, at.y+y*pixel, w*pixel, h*pixel}, color)
	}
	ink = color_with_opacity(LIVING_TOKEN_INK, alpha)
	// The paper's ink line, three corners cut by hand...
	box(at, pixel, 1, 0, pw-2, 1, ink)
	box(at, pixel, 0, 1, 1, ph-2, ink)
	box(at, pixel, pw-1, 1, 1, ph-2, ink)
	box(at, pixel, 1, ph-1, pw-1, 1, ink)
	// ...the cut edge one pixel down and right, its far corner cut...
	box(at, pixel, pw, 1, 1, ph-1, ink)
	box(at, pixel, 1, ph, pw-1, 1, ink)
	// ...and the paper.
	box(at, pixel, 1, 1, pw-2, ph-2, color_with_opacity(LIVING_TOKEN_PAPER, alpha))
	return
}

// A tag's pixel figures, from tag pixel column `left` on its text row.
@(private)
draw_paper_tag_text :: proc(at: rl.Vector2, left: f32, text: string, pixel: f32, ink: rl.Color) {
	for index in 0..<len(text) {
		glyph, ok := living_token_glyph(text[index])
		if !ok { continue }
		for row in 0..<7 {
			draw_pixel_row(LIVING_TOKEN_GLYPHS[glyph][row], 5, at.x+(left+f32(index*6))*pixel, at.y+f32(3+row)*pixel, pixel, ink)
		}
	}
}

// The heart's tag with its top left at `at`.
@(private = "file")
draw_living_heart :: proc(at: rl.Vector2, text: string, pixel: f32, icon: Intent_Icon, alarm: bool, alpha: f32 = 1) {
	w, h := living_heart_size(text, true)
	ink := draw_paper_tag(at, w, h, pixel, alpha)
	red := color_with_opacity(LIVING_TOKEN_DAMAGE, alpha)
	for row in 0..<7 {
		draw_pixel_row(LIVING_HEART_GLYPH[row], LIVING_HEART_WIDTH, at.x+3*pixel, at.y+f32(3+row)*pixel, pixel, red)
	}
	draw_paper_tag_text(at, f32(3+LIVING_HEART_WIDTH+1), text, pixel, ink)
	left, _ := living_heart_size(text)
	rl.DrawRectangleRec({at.x+f32(left-2)*pixel, at.y+3*pixel, pixel, 7*pixel}, color_with_opacity(LIVING_TOKEN_EDGE, alpha))
	draw_compact_intent({at.x+f32(left)*pixel, at.y+3*pixel}, icon, pixel, alarm, alpha)
}

// The top of a living figure's head (world): `rest_height` above its feet,
// on the card as it stands now (slid, hopping or toppling). The still card's
// quad, not the print's, so a trembling figure does not shake its tag.
@(private = "file")
living_head_point :: proc(renderer: ^Renderer, character: gfx.Flipbook_Character, key: Sprite_Key, position: view.Vec2,
	entity: game.Entity_Ref) -> rl.Vector3 {
	sheet := &gfx.LIVING_SHEETS[character]
	p := living_billboard_geometry(renderer, character, key, position, true, entity).card_points
	bottom, top := (p[1]+p[2])*0.5, (p[0]+p[3])*0.5
	margin := f32(sheet.card_margin)
	k := (margin+f32(sheet.cell.y)-sheet.feet.y+sheet.rest_height)/max(f32(sheet.cell.y)+2*margin, 1)
	return bottom+(top-bottom)*k
}

// Where an enemy's tag sits on screen, just over its head, and the size of
// its pixel. False when off the canvas.
@(private = "file")
tactical_enemy_head :: proc(renderer: ^Renderer, actor: ^Presentation_Actor) -> (head: view.Vec2, pixel: f32, ok: bool) {
	v := &renderer.tactical
	feet := tactical_project(renderer, {actor.position.x+0.5, actor.position.y+0.5})
	if feet.x < 0 || feet.y < 0 || feet.x > renderer.canvas_width || feet.y > renderer.canvas_height { return }
	pixel = 1

	key := sprite_key_for_enemy(actor.archetype)
	top: rl.Vector3
	if character, found := flipbook_character(key); found && v.living && living_cards_ready(renderer) {
		top = living_head_point(renderer, character, key, actor.position, actor.entity)+{0, 0.06, 0}
	} else {
		quad := tactical_billboard_geometry(renderer, key, actor.position, true, actor.entity)
		top = (quad.points[0]+quad.points[3])*0.5+{0, 0.05, 0}
	}
	right := flipbook_camera_right(renderer)*0.5
	a := tactical_project(renderer, {top.x-right.x, top.z-right.z}, top.y)
	b := tactical_project(renderer, {top.x+right.x, top.z+right.z}, top.y)
	if math.hypot(b.x-a.x, b.y-a.y) >= LIVING_HEART_DOUBLE { pixel = 2 }
	return tactical_project(renderer, {top.x, top.z}, top.y), pixel, true
}

// Secondary annotations (the Pinball's warning) avoid the fixed hearts.
@(private)
living_heart_is_clear :: proc(layout: ^Tactical_Label_Layout, candidate: rl.Rectangle) -> bool {
	for occupied in layout.bounds[:layout.count] {
		padded := rl.Rectangle{occupied.x-2, occupied.y-2, occupied.width+4, occupied.height+4}
		if rl.CheckCollisionRecs(candidate, padded) { return false }
	}
	return true
}

// A fixed attachment to the presented card, not a free-floating HUD label.
// Never search other rows/columns or clamp it away from its owner at a screen
// edge. HUD panels cover it along with the enemy; secondary labels avoid it.
@(private)
place_living_heart :: proc(layout: ^Tactical_Label_Layout, head: view.Vec2, size: view.Vec2) -> rl.Rectangle {
	result := rl.Rectangle{math.round(head.x-size.x*0.5), math.round(head.y-size.y), size.x, size.y}
	if layout.count < len(layout.bounds) { layout.bounds[layout.count] = result; layout.count += 1 }
	return result
}

// Every enemy's health and current intent share one tag. Its whole rectangle
// participates in the label layout, including the icon and divider.
@(private)
draw_living_hearts :: proc(renderer: ^Renderer, room: ^game.Room) {
	v := &renderer.tactical
	for &actor in v.snapshot.enemies[:v.snapshot.enemy_count] {
		if !living_heart_shown(renderer, actor) { continue }
		head, pixel, on_board := tactical_enemy_head(renderer, &actor)
		if !on_board { continue }
		icon := Intent_Icon.None
		alarm := false
		if i, found := game.enemy_index_by_id(room, actor.entity.id); found {
			enemy := &room.enemies[i]
			icon, alarm = tactical_intent_icon(room, enemy), enemy.intent.windup
		}
		text := living_heart_text(actor.health, actor.max_health)
		w, h := living_heart_size(text, true)
		size := view.Vec2{f32(w)*pixel, f32(h)*pixel}
		bounds := place_living_heart(v.labels, head, size)
		if v.labels.heart_count < len(v.labels.hearts) {
			v.labels.hearts[v.labels.heart_count], v.labels.heart_ids[v.labels.heart_count] = bounds, actor.entity.id
			v.labels.heart_count += 1
		}
		draw_living_heart({bounds.x, bounds.y}, text, pixel, icon, alarm, actor.opacity)
	}
}

// A living, visible enemy in sight (never the Pinball's ball: pinball.odin).
@(private)
living_heart_shown :: proc(renderer: ^Renderer, actor: Presentation_Actor) -> bool {
	cell := grid.Position{x = int(math.round(actor.position.x)), y = int(math.round(actor.position.y))}
	return actor.visible && actor.health > 0 && tactical_overlay_visible(renderer, cell) && !tactical_pinball_holds(renderer, actor.entity)
}
