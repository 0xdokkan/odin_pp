package render

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import gfx "../engine/gfx"
import game "../game"
import grid "../grid"
import view "../view"

// An enemy's health on the board: a little paper tag over its head, cut and
// inked like the damage tokens (living_token.odin), with a red pixel heart and
// the health left over the maximum in the same pixel figures. The intent seal
// keeps the card's top right corner (it is drawn after, over everything), so
// the tag stays clear of it; on a board without seals the intent's sticker
// rides beside the heart instead.

// 7 pixels wide, rows top to bottom, bit 6 the leftmost column.
@(rodata)
LIVING_HEART_GLYPH := [7]u8{0b0110110, 0b1111111, 0b1111111, 0b1111111, 0b0111110, 0b0011100, 0b0001000}
LIVING_HEART_WIDTH :: 7
// Half the side of the square kept for a seal: its loudest outer ring
// (radius 13+4+1.5, rings 3+4+4) and a pixel more.
LIVING_HEART_SEAL_KEEP :: f32(30)
// The tag's pixel doubles once a world unit is this wide on screen at the head.
LIVING_HEART_DOUBLE :: f32(96)
// How many rows a tag climbs past the tags and seals already placed.
LIVING_HEART_ROWS :: 4
// In a crowd, how far around its first place a tag still looks for a free
// one (rows up and down, tag widths left and right): near enough to be read
// as its enemy's.
LIVING_HEART_NEAR_ROWS :: 6
LIVING_HEART_NEAR_COLUMNS :: 2

living_heart_text :: proc(health, max_health: i32) -> string {
	return fmt.tprintf("%d/%d", max(health, 0), max(max_health, 1))
}

// In tag pixels: the heart, a pixel of paper, the figures; paper, ink line and
// cut edge as a token's (living_token_size).
living_heart_size :: proc(text: string) -> (width, height: int) {
	return LIVING_HEART_WIDTH+1+len(text)*6-1+4+2+1, 7+4+2+1
}

// One row of a pixel figure as runs of lit pixels; bit `width-1` is the leftmost.
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
draw_living_heart :: proc(at: rl.Vector2, text: string, pixel: f32, alpha: f32 = 1) {
	w, h := living_heart_size(text)
	ink := draw_paper_tag(at, w, h, pixel, alpha)
	red := color_with_opacity(LIVING_TOKEN_DAMAGE, alpha)
	for row in 0..<7 {
		draw_pixel_row(LIVING_HEART_GLYPH[row], LIVING_HEART_WIDTH, at.x+3*pixel, at.y+f32(3+row)*pixel, pixel, red)
	}
	draw_paper_tag_text(at, f32(3+LIVING_HEART_WIDTH+1), text, pixel, ink)
}

// The top of a living figure's head (world): `rest_height` above its feet,
// on the card as it stands now (slid, hopping or toppling). The still card's
// quad, not the print's, so a trembling figure does not shake its tag.
living_head_point :: proc(renderer: ^Renderer, character: gfx.Flipbook_Character, key: Sprite_Key, position: view.Vec2,
	entity: game.Entity_Ref) -> rl.Vector3 {
	sheet := &gfx.LIVING_SHEETS[character]
	p := living_billboard_geometry(renderer, character, key, position, true, entity).card_points
	bottom, top := (p[1]+p[2])*0.5, (p[0]+p[3])*0.5
	margin := f32(sheet.card_margin)
	k := (margin+f32(sheet.cell.y)-sheet.feet.y+sheet.rest_height)/max(f32(sheet.cell.y)+2*margin, 1)
	return bottom+(top-bottom)*k
}

// Where an enemy's tag sits on screen: just over its head (3D) or its body
// (the flat board), and how large its pixel is. False when off the canvas.
tactical_enemy_head :: proc(renderer: ^Renderer, actor: ^Presentation_Actor) -> (head: view.Vec2, pixel: f32, ok: bool) {
	v := &renderer.tactical
	feet := tactical_project(renderer, {actor.position.x+0.5, actor.position.y+0.5})
	if feet.x < 0 || feet.y < 0 || feet.x > renderer.canvas_width || feet.y > renderer.canvas_height { return }
	pixel = 1
	if !v.scene_3d {
		radius := max(enemy_draw_radius(renderer, {archetype = actor.archetype}), 14*renderer.camera.zoom)
		return {feet.x, feet.y-radius-3}, pixel, true
	}
	key := sprite_key_for_enemy(actor.archetype)
	top: rl.Vector3
	if character, found := flipbook_character(key); found && v.living && living_cards_ready(renderer) {
		top = living_head_point(renderer, character, key, actor.position, actor.entity)+{0, 0.06, 0}
	} else {
		quad := tactical_billboard_geometry(renderer, key, actor.position)
		top = (quad.points[0]+quad.points[3])*0.5+{0, 0.05, 0}
	}
	right := flipbook_camera_right(renderer)*0.5
	a := tactical_project(renderer, {top.x-right.x, top.z-right.z}, top.y)
	b := tactical_project(renderer, {top.x+right.x, top.z+right.z}, top.y)
	if math.hypot(b.x-a.x, b.y-a.y) >= LIVING_HEART_DOUBLE { pixel = 2 }
	return tactical_project(renderer, {top.x, top.z}, top.y), pixel, true
}

// Clear of the labels and seals already placed (the layout's first `count`
// places; all of them when negative), and of `avoid` (the player's figure;
// empty for none).
living_heart_is_clear :: proc(layout: ^Tactical_Label_Layout, candidate: rl.Rectangle, avoid: rl.Rectangle = {}, count := -1) -> bool {
	if avoid.width > 0 && rl.CheckCollisionRecs(candidate, avoid) { return false }
	for occupied in layout.bounds[:layout.count if count < 0 else min(count, layout.count)] {
		padded := rl.Rectangle{occupied.x-2, occupied.y-2, occupied.width+4, occupied.height+4}
		if rl.CheckCollisionRecs(candidate, padded) { return false }
	}
	return true
}

// A tag at (x, y), pulled whole into the board's area, on whole pixels.
living_heart_spot :: proc(viewport: rl.Rectangle, x, y: f32, size: view.Vec2) -> rl.Rectangle {
	return {math.round(clamp(x, viewport.x, viewport.x+viewport.width-size.x)),
		math.round(clamp(y, viewport.y, viewport.y+viewport.height-size.y)), size.x, size.y}
}

// A tag's place: its bottom on `head`, centred, left of the enemy's own seal
// (`seal`, when `sealed`), clear of the labels and seals already placed and of
// `avoid`. Tried in turn: lifted a row at a time over the head; beside it,
// left then right; down a row at a time, over its own enemy and never past
// `floor` (its feet), so a head behind the top panel or the lab's banner
// shows its tag just under them when its feet are lower still; then, in a
// crowd, the nearest free place around the first. A crowd that leaves none
// still shows it: when the layout's places from `tags` on are the other tags,
// where it hides the least of them, never under a seal, a panel or a label;
// else in its first place. Kept in the layout for the labels and badges
// placed after.
place_living_heart :: proc(layout: ^Tactical_Label_Layout, head: view.Vec2, size: view.Vec2, seal: rl.Vector2, sealed: bool,
	viewport: rl.Rectangle, avoid: rl.Rectangle = {}, floor: f32 = 1e9, tags := -1) -> rl.Rectangle {
	x := head.x-size.x*0.5
	if sealed { x = min(x, seal.x-LIVING_HEART_SEAL_KEEP-3-size.x) }
	top := head.y-size.y
	result, found := living_heart_search(layout, x, top, size, viewport, avoid, floor)
	if !found && tags >= 0 && tags < layout.count {
		result, found = living_heart_least_covering(layout, x, top, size, viewport, avoid, floor, tags)
	}
	if !found { result = living_heart_spot(viewport, x, top, size) }
	if layout.count < len(layout.bounds) { layout.bounds[layout.count] = result; layout.count += 1 }
	return result
}

living_heart_search :: proc(layout: ^Tactical_Label_Layout, x, top: f32, size: view.Vec2, viewport, avoid: rl.Rectangle,
	floor: f32) -> (result: rl.Rectangle, found: bool) {
	step := size.y+2
	for row in 0..<LIVING_HEART_ROWS {
		candidate := living_heart_spot(viewport, x, top-f32(row)*step, size)
		if living_heart_is_clear(layout, candidate, avoid) { return candidate, true }
	}
	// Beside: a tag's width away, or past the whole figure it must not cover
	// when that figure is what stands over its head.
	left, right := x-(size.x+4), x+(size.x+4)
	column := rl.Rectangle{x, top-f32(LIVING_HEART_ROWS-1)*step, size.x, size.y+f32(LIVING_HEART_ROWS-1)*step}
	if avoid.width > 0 && rl.CheckCollisionRecs(column, avoid) {
		left, right = min(left, avoid.x-size.x-3), max(right, avoid.x+avoid.width+3)
	}
	for row in 0..<LIVING_HEART_ROWS {
		for side in ([2]f32{left, right}) {
			candidate := living_heart_spot(viewport, side, top-f32(row)*step, size)
			if living_heart_is_clear(layout, candidate, avoid) { return candidate, true }
		}
	}
	// Then down a row at a time from where it would sit: over its own enemy,
	// rather than lost under another tag or a panel.
	below := max(top, viewport.y)
	for row in 1..=LIVING_HEART_ROWS*3 {
		candidate := living_heart_spot(viewport, x, below+f32(row)*step, size)
		if candidate.y+candidate.height > floor { break }
		if living_heart_is_clear(layout, candidate, avoid) { return candidate, true }
	}
	// Last, as the bomb labels do in a crowd, the nearest free place in a
	// bounded neighbourhood of the first, never below the enemy's feet.
	nearest := f32(1e30)
	for row in -LIVING_HEART_NEAR_ROWS..=LIVING_HEART_NEAR_ROWS {
		for column in -LIVING_HEART_NEAR_COLUMNS..=LIVING_HEART_NEAR_COLUMNS {
			candidate := living_heart_spot(viewport, x+f32(column)*(size.x+4), top+f32(row)*step, size)
			if row > 0 && candidate.y+candidate.height > floor { continue }
			if !living_heart_is_clear(layout, candidate, avoid) { continue }
			dx, dy := candidate.x-x, candidate.y-top
			if distance := dx*dx+dy*dy; distance < nearest { result, found, nearest = candidate, true, distance }
		}
	}
	return
}

// In a crowd with no free place: in the same neighbourhood, the place clear
// of the layout's places before `tags` (seals, panels, labels) and of `avoid`
// that hides the least of the other tags, the nearest of those.
living_heart_least_covering :: proc(layout: ^Tactical_Label_Layout, x, top: f32, size: view.Vec2, viewport, avoid: rl.Rectangle,
	floor: f32, tags: int) -> (result: rl.Rectangle, found: bool) {
	step := size.y+2
	least, nearest := f32(1e30), f32(1e30)
	for row in -LIVING_HEART_NEAR_ROWS..=LIVING_HEART_NEAR_ROWS {
		for column in -LIVING_HEART_NEAR_COLUMNS..=LIVING_HEART_NEAR_COLUMNS {
			candidate := living_heart_spot(viewport, x+f32(column)*(size.x+4), top+f32(row)*step, size)
			if row > 0 && candidate.y+candidate.height > floor { continue }
			if !living_heart_is_clear(layout, candidate, avoid, tags) { continue }
			covered := f32(0)
			for tag in layout.bounds[tags:layout.count] {
				overlap := rl.GetCollisionRec(candidate, tag)
				covered += overlap.width*overlap.height
			}
			dx, dy := candidate.x-x, candidate.y-top
			distance := dx*dx+dy*dy
			if covered < least || (covered == least && distance < nearest) {
				result, found, least, nearest = candidate, true, covered, distance
			}
		}
	}
	return
}

// The square a seal keeps for itself, so the tags go around it.
living_heart_seal_bounds :: proc(center: rl.Vector2) -> rl.Rectangle {
	return {center.x-LIVING_HEART_SEAL_KEEP, center.y-LIVING_HEART_SEAL_KEEP, LIVING_HEART_SEAL_KEEP*2, LIVING_HEART_SEAL_KEEP*2}
}

// Every enemy's heart over its head, after the fuse labels and before the
// exit's. Each seal keeps its square first, so no tag goes under one.
draw_living_hearts :: proc(renderer: ^Renderer, room: ^game.Room) {
	v := &renderer.tactical
	seals := intent_seals_on(renderer) && living_cards_ready(renderer)
	seal_at: [game.MAX_ENEMIES_PER_ROOM]rl.Vector2
	sealed: [game.MAX_ENEMIES_PER_ROOM]bool
	for actor, index in v.snapshot.enemies[:v.snapshot.enemy_count] {
		if !seals || !living_heart_shown(renderer, actor) { continue }
		center, ok := intent_seal_center(renderer, actor)
		if !ok { continue }
		seal_at[index], sealed[index] = center, true
		if v.labels.count < len(v.labels.bounds) {
			v.labels.bounds[v.labels.count] = living_heart_seal_bounds(center)
			v.labels.count += 1
		}
	}
	// The player's own figure stays in sight: no tag goes over it (while it
	// is up on the board).
	avoid: rl.Rectangle
	if player, ok := tactical_actor_screen_bounds(renderer, &v.snapshot.player); ok && !tactical_shadow_showing(renderer) {
		avoid = player
	}
	// From here on the layout gains the tags themselves.
	tags := v.labels.count
	for &actor, index in v.snapshot.enemies[:v.snapshot.enemy_count] {
		if !living_heart_shown(renderer, actor) { continue }
		head, pixel, on_board := tactical_enemy_head(renderer, &actor)
		if !on_board { continue }
		// Without seals the intent's paper sticker rides beside the heart.
		icon := Intent_Icon.None
		alarm := false
		if !seals && (v.enabled || tactical_telegraphs_are_visible(renderer, room)) {
			if i, found := game.enemy_index_by_id(room, actor.entity.id); found {
				enemy := &room.enemies[i]
				icon, alarm = remembered_intent_icon(renderer, enemy.id, tactical_intent_icon(room, enemy), enemy.intent.windup)
			}
		}
		text := living_heart_text(actor.health, actor.max_health)
		w, h := living_heart_size(text)
		size := view.Vec2{f32(w)*pixel, f32(h)*pixel}
		radius := 7*pixel+4
		sticker := radius*2+2 if icon != .None else 0
		feet := tactical_project(renderer, {actor.position.x+0.5, actor.position.y+0.5})
		bounds := place_living_heart(v.labels, {head.x-sticker*0.5, head.y}, {size.x+sticker, size.y},
			seal_at[index], sealed[index], tactical_world_bounds(renderer), avoid, feet.y, tags)
		draw_living_heart({bounds.x+sticker, bounds.y}, text, pixel, actor.opacity)
		if icon != .None {
			draw_intent_sticker({bounds.x+radius, bounds.y+bounds.height*0.5}, icon, alarm, tactical_world_time(renderer),
				int(actor.entity.id), radius)
		}
	}
}

// A living, visible enemy in sight.
living_heart_shown :: proc(renderer: ^Renderer, actor: Presentation_Actor) -> bool {
	cell := grid.Position{int(math.round(actor.position.x)), int(math.round(actor.position.y))}
	return actor.visible && actor.health > 0 && tactical_render_visible(renderer, cell)
}
