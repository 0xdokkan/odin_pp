package render

import "core:math"
import rl "vendor:raylib"
import game "../game"
import grid "../grid"
import view "../view"

Tactical_Label_Layout :: struct {
	bounds: [96]rl.Rectangle,
	count: int,
	actor_bounds: [game.MAX_ENEMIES_PER_ROOM+1]rl.Rectangle,
	actor_count: int,
	// Each enemy's heart as placed this frame (draw_living_hearts), for the
	// tags drawn after them that keep clear of it (the Dado del Destino's die).
	hearts: [game.MAX_ENEMIES_PER_ROOM]rl.Rectangle,
	heart_ids: [game.MAX_ENEMIES_PER_ROOM]u32,
	heart_count: int,
}

// Where the heart of enemy `id` stands this frame, when it is shown.
tactical_label_heart :: proc(layout: ^Tactical_Label_Layout, id: u32) -> (bounds: rl.Rectangle, found: bool) {
	if layout == nil { return }
	for heart_id, index in layout.heart_ids[:layout.heart_count] {
		if heart_id == id { return layout.hearts[index], true }
	}
	return
}

tactical_label_candidate_is_clear :: proc(layout: ^Tactical_Label_Layout, candidate: rl.Rectangle) -> bool {
	for occupied in layout.bounds[:layout.count] {
		padded := rl.Rectangle{occupied.x-3, occupied.y-3, occupied.width+6, occupied.height+6}
		if rl.CheckCollisionRecs(candidate, padded) { return false }
	}
	for actor in layout.actor_bounds[:layout.actor_count] {
		padded := rl.Rectangle{actor.x-2, actor.y-2, actor.width+4, actor.height+4}
		if rl.CheckCollisionRecs(candidate, padded) { return false }
	}
	return true
}

// One allocator for bomb labels and feedback badges (the hearts over the heads
// and the seals keep their places in it too). Small fixed storage keeps
// frame cost bounded. Prefer above the anchor, then a nearby side column.
place_tactical_label :: proc(layout: ^Tactical_Label_Layout, anchor: view.Vec2,
	size: view.Vec2, viewport: rl.Rectangle) -> (result: rl.Rectangle, ok: bool) {
	if size.x > viewport.width || size.y > viewport.height || layout.count >= len(layout.bounds) { return }
	for row in 0..<12 {
		for column in ([5]int{0, -1, 1, -2, 2}) {
			candidate := rl.Rectangle{
				clamp(anchor.x-size.x/2+f32(column)*(size.x+5), viewport.x, viewport.x+viewport.width-size.x),
				clamp(anchor.y-size.y-f32(row)*13, viewport.y, viewport.y+viewport.height-size.y), size.x, size.y}
			if !tactical_label_candidate_is_clear(layout, candidate) { continue }
			layout.bounds[layout.count] = candidate
			layout.count += 1
			return candidate, true
		}
	}
	// Dense groups can fill every preferred lane above an actor. Search a
	// bounded wider/below neighborhood only then, retaining the nearest free
	// label center so readable health does not require crossing the whole room.
	best_distance := f32(1e30)
	for row in -11..=11 {
		for column in -4..=4 {
			candidate := rl.Rectangle{
				clamp(anchor.x-size.x/2+f32(column)*(size.x+5), viewport.x, viewport.x+viewport.width-size.x),
				clamp(anchor.y-size.y+f32(row)*13, viewport.y, viewport.y+viewport.height-size.y), size.x, size.y}
			if !tactical_label_candidate_is_clear(layout, candidate) { continue }
			dx, dy := candidate.x+size.x/2-anchor.x, candidate.y+size.y-anchor.y
			distance := dx*dx+dy*dy
			if distance >= best_distance { continue }
			result, ok, best_distance = candidate, true, distance
		}
	}
	if ok { layout.bounds[layout.count] = result; layout.count += 1 }
	return
}

// Use the drawn quad, including actor-specific height and the current cue pose.
// Body occupancy is separate from labels so a full encounter keeps its existing
// fuse/status/QTE budget. Only 3D billboards participate in this reservation.
reserve_tactical_actor_label_bounds :: proc(renderer: ^Renderer, actor: ^Presentation_Actor) {
	v := &renderer.tactical
	if v.labels.actor_count >= len(v.labels.actor_bounds) { return }
	// Down in his shadow the player's card is no standing figure but a dark
	// hood in its pool: labels and badges may lie over it (the CRITICO of a
	// diagonal step just over the pool, a bomb's label by its cell).
	if actor.entity == game.PLAYER_ENTITY && tactical_shadow_depth(renderer, game.PLAYER_ENTITY) > 0 { return }
	bounds, ok := tactical_actor_screen_bounds(renderer, actor)
	if !ok { return }
	v.labels.actor_bounds[v.labels.actor_count] = bounds
	v.labels.actor_count += 1
}

// A 3D actor's drawn quad on screen; false on the flat board or out of sight.
tactical_actor_screen_bounds :: proc(renderer: ^Renderer, actor: ^Presentation_Actor) -> (bounds: rl.Rectangle, ok: bool) {
	v := &renderer.tactical
	if !v.scene_3d || !actor.visible || actor.opacity <= 0 { return }
	cell := grid.Position{int(math.round(actor.position.x)), int(math.round(actor.position.y))}
	if !tactical_render_visible(renderer, cell) { return }
	key := Sprite_Key.Player if actor.entity == game.PLAYER_ENTITY else sprite_key_for_enemy(actor.archetype)
	quad := tactical_billboard_geometry(renderer, key, actor.position)
	point := quad.points[0]
	first := tactical_project(renderer, {point.x, point.z}, point.y)
	left, top, right, bottom := first.x, first.y, first.x, first.y
	for corner in quad.points[1:] {
		projected := tactical_project(renderer, {corner.x, corner.z}, corner.y)
		left, top = min(left, projected.x), min(top, projected.y)
		right, bottom = max(right, projected.x), max(bottom, projected.y)
	}
	return {left, top, right-left, bottom-top}, true
}

// The bomb, fuse and exit labels. (Enemy health is a paper heart over the
// head, living_heart.odin.)
draw_tactical_label :: proc(renderer: ^Renderer, anchor: view.Vec2, first, second: cstring, color: rl.Color) {
	viewport := tactical_world_bounds(renderer)
	if !point_in_rectangle(anchor, {viewport.x-30, viewport.y-35, viewport.width+60, viewport.height+80}) { return }
	width := max(gothic_text_width(renderer, first, 11), gothic_text_width(renderer, second, 10))+12
	height := f32(17) if second == "" else f32(30)
	bounds, placed := place_tactical_label(renderer.tactical.labels, anchor, {width, height}, viewport)
	if !placed { return }
	bottom := rl.Vector2{bounds.x+bounds.width/2, bounds.y+bounds.height}
	if abs(bottom.x-anchor.x) > 4 || abs(bottom.y-anchor.y) > 8 {
		rl.DrawLineEx(bottom, to_raylib(anchor), 1, color_with_opacity(color, 0.5))
	}
	rl.DrawRectangleRec(bounds, GOTHIC_INK)
	rl.DrawRectangleRec({bounds.x, bounds.y, 2, bounds.height}, color)
	gothic_text(renderer, first, bounds.x+6, bounds.y+1, 11, GOTHIC_PAPER)
	if second != "" { gothic_text(renderer, second, bounds.x+6, bounds.y+14, 10, color) }
}

draw_tactical_annotations :: proc(renderer: ^Renderer, room: ^game.Room) {
	v := &renderer.tactical
	v.labels^ = {}
	reserve_tactical_actor_label_bounds(renderer, &v.snapshot.player)
	for &actor in v.snapshot.enemies[:v.snapshot.enemy_count] {
		reserve_tactical_actor_label_bounds(renderer, &actor)
	}
	if room.qte.kind != .None { v.labels.bounds[0] = {14, TACTICAL_HUD_HEIGHT+13, 237, 143}; v.labels.count = 1 }
	if v.mechanics_lab {
		// The mechanics lab's banner is drawn over the board: labels keep clear.
		v.labels.bounds[v.labels.count] = mechanics_lab_banner_bounds(renderer, "PROVA MECCANICHE",
			"NEMICI 0/0  /  F5 RICOMINCIA  /  F6 INTENTI: SIGILLI + TERRENO  /  F10 MENU")
		v.labels.count += 1
	}
	// Existing status glyphs retain their ground lane, the paper tags under
	// them included; text badges avoid it.
	for &actor in v.snapshot.enemies[:v.snapshot.enemy_count] {
		cell := grid.Position{int(math.round(actor.position.x)), int(math.round(actor.position.y))}
		if !actor.visible || actor.statuses.count == 0 || !tactical_render_visible(renderer, cell) { continue }
		p := tactical_project(renderer, {actor.position.x+0.5, actor.position.y+0.5})
		tags := draw_status_set(renderer, &actor.statuses, p, 14, actor.opacity, tactical_status_tag_pixel(renderer, actor.position))
		if v.labels.count < len(v.labels.bounds) { v.labels.bounds[v.labels.count] = tactical_status_lane(p, tags); v.labels.count += 1 }
	}
	if v.snapshot.player.visible && v.snapshot.player.statuses.count > 0 {
		player := &v.snapshot.player
		p := tactical_project(renderer, {player.position.x+0.5, player.position.y+0.5})
		tags := draw_status_set(renderer, &player.statuses, p, 14, player.opacity, tactical_status_tag_pixel(renderer, player.position))
		if v.labels.count < len(v.labels.bounds) { v.labels.bounds[v.labels.count] = tactical_status_lane(p, tags); v.labels.count += 1 }
	}
	// Critical fuse labels reserve space before actors and their ordinary intents.
	draw_voxel_fuse_labels(renderer, room)
	// Enemies keep their own clock: their health and intent stay on screen
	// while the player's move or cast plays, and only leave with the enemy.
	draw_living_hearts(renderer, room)
	if tactical_room_is_clear(v.snapshot.phase) {
		p := room.exit_position
		draw_tactical_label(renderer, tactical_project(renderer, {f32(p.x)+0.5, f32(p.y)+0.5}, 1.3), "USCITA", "", {124, 199, 215, 255})
	}
}
