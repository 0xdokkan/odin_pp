package render

import "core:fmt"
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

// One allocator for health, intent and bomb labels. Small fixed storage keeps
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
	if !v.scene_3d || !actor.visible || actor.opacity <= 0 || v.labels.actor_count >= len(v.labels.actor_bounds) { return }
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
	v.labels.actor_bounds[v.labels.actor_count] = {left, top, right-left, bottom-top}
	v.labels.actor_count += 1
}

draw_tactical_label :: proc(renderer: ^Renderer, anchor: view.Vec2, first, second: cstring,
	color: rl.Color, health: f32 = -1, icon: Intent_Icon = .None, alarm: bool = false, seed: int = 0) {
	viewport := tactical_world_bounds(renderer)
	if !point_in_rectangle(anchor, {viewport.x-30, viewport.y-35, viewport.width+60, viewport.height+80}) { return }
	// The intent sticker sits at the label's left, top-left of the enemy.
	inset := f32(26) if icon != .None else 0
	width := max(gothic_text_width(renderer, first, 11), gothic_text_width(renderer, second, 10))+12+inset
	height := f32(17) if second == "" else f32(30)
	if health >= 0 { height += 4 }
	bounds, placed := place_tactical_label(renderer.tactical.labels, anchor, {width, height}, viewport)
	if !placed { return }
	bottom := rl.Vector2{bounds.x+bounds.width/2, bounds.y+bounds.height}
	if abs(bottom.x-anchor.x) > 4 || abs(bottom.y-anchor.y) > 8 {
		rl.DrawLineEx(bottom, to_raylib(anchor), 1, color_with_opacity(color, 0.5))
	}
	rl.DrawRectangleRec(bounds, GOTHIC_INK)
	rl.DrawRectangleRec({bounds.x, bounds.y, 2, bounds.height}, color)
	gothic_text(renderer, first, bounds.x+6+inset, bounds.y+1, 11, GOTHIC_PAPER)
	if second != "" { gothic_text(renderer, second, bounds.x+6+inset, bounds.y+14, 10, color) }
	if health >= 0 {
		rl.DrawRectangleRec({bounds.x+5+inset, bounds.y+bounds.height-4, bounds.width-9-inset, 2}, GOTHIC_DARK_RED)
		rl.DrawRectangleRec({bounds.x+5+inset, bounds.y+bounds.height-4, (bounds.width-9-inset)*clamp(health, f32(0), f32(1)), 2}, color)
	}
	if icon != .None {
		draw_intent_sticker({bounds.x+5, bounds.y+bounds.height*0.5}, icon, alarm, renderer.sprite_assets.elapsed, seed)
	}
}

// The health labels of a living board: larger type with the maximum, a bar
// with one notch per point so the health can be counted at a glance, and a
// label that never leaves an enemy on screen (behind the top panel it waits
// just below it; in a crowd it still shows, over the others).
LIVING_HEALTH_COLOR :: rl.Color{224, 78, 88, 255}

living_health_text :: proc(health, max_health, shield: i32) -> cstring {
	if shield > 0 { return fmt.ctprintf("HP %d/%d / SC %d", health, max_health, shield) }
	return fmt.ctprintf("HP %d/%d", health, max_health)
}

// One notch per point of health; one every five for large pools.
living_health_step :: proc(max_health: i32) -> i32 { return 1 if max_health <= 30 else 5 }

// Where a kept label sits: inside the board's area, never behind the panels.
living_label_anchor :: proc(viewport: rl.Rectangle, anchor: view.Vec2, size: view.Vec2) -> view.Vec2 {
	return {clamp(anchor.x, viewport.x+size.x*0.5, viewport.x+viewport.width-size.x*0.5),
		clamp(anchor.y, viewport.y+size.y+2, viewport.y+viewport.height)}
}

draw_living_health_label :: proc(renderer: ^Renderer, anchor: view.Vec2, first, second: cstring, color: rl.Color,
	health, max_health: i32, icon: Intent_Icon, alarm: bool, seed: int) {
	viewport := tactical_world_bounds(renderer)
	inset := f32(26) if icon != .None else 0
	bar := clamp(f32(max(max_health, 1))*3, 48, 120)
	width := max(gothic_text_width(renderer, first, 14), gothic_text_width(renderer, second, 12), bar)+12+inset
	height := f32(29) if second == "" else f32(44)
	at := living_label_anchor(viewport, anchor, {width, height})
	bounds, placed := place_tactical_label(renderer.tactical.labels, at, {width, height}, viewport)
	if !placed { bounds = {at.x-width*0.5, at.y-height, width, height} }
	bottom := rl.Vector2{bounds.x+bounds.width/2, bounds.y+bounds.height}
	if abs(bottom.x-anchor.x) > 4 || abs(bottom.y-anchor.y) > 8 {
		rl.DrawLineEx(bottom, to_raylib(anchor), 1, color_with_opacity(color, 0.6))
	}
	rl.DrawRectangleRec(bounds, GOTHIC_INK)
	rl.DrawRectangleRec({bounds.x, bounds.y, 3, bounds.height}, color)
	gothic_text(renderer, first, bounds.x+7+inset, bounds.y+3, 14, GOTHIC_PAPER)
	if second != "" { gothic_text(renderer, second, bounds.x+7+inset, bounds.y+19, 12, color) }
	x, y, w := bounds.x+7+inset, bounds.y+bounds.height-9, bounds.width-12-inset
	rl.DrawRectangleRec({x, y, w, 5}, GOTHIC_DARK_RED)
	rl.DrawRectangleRec({x, y, w*clamp(f32(health)/f32(max(max_health, 1)), 0, 1), 5}, LIVING_HEALTH_COLOR)
	step := living_health_step(max_health)
	for point := step; point < max_health; point += step {
		rl.DrawRectangleRec({math.floor(x+w*f32(point)/f32(max_health)), y, 1, 5}, GOTHIC_INK)
	}
	if icon != .None {
		draw_intent_sticker({bounds.x+5, bounds.y+bounds.height*0.5}, icon, alarm, renderer.sprite_assets.elapsed, seed)
	}
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
	// Existing status glyphs retain their ground lane; text badges avoid it.
	for &actor in v.snapshot.enemies[:v.snapshot.enemy_count] {
		cell := grid.Position{int(math.round(actor.position.x)), int(math.round(actor.position.y))}
		if !actor.visible || actor.statuses.count == 0 || !tactical_render_visible(renderer, cell) { continue }
		p := tactical_project(renderer, {actor.position.x+0.5, actor.position.y+0.5})
		draw_status_set(renderer, &actor.statuses, p, 14, actor.opacity)
		if v.labels.count < len(v.labels.bounds) { v.labels.bounds[v.labels.count] = {p.x-30, p.y-18, 60, 36}; v.labels.count += 1 }
	}
	if v.snapshot.player.visible && v.snapshot.player.statuses.count > 0 {
		p := tactical_project(renderer, {v.snapshot.player.position.x+0.5, v.snapshot.player.position.y+0.5})
		draw_status_set(renderer, &v.snapshot.player.statuses, p, 14, v.snapshot.player.opacity)
		if v.labels.count < len(v.labels.bounds) { v.labels.bounds[v.labels.count] = {p.x-30, p.y-18, 60, 36}; v.labels.count += 1 }
	}
	// Critical fuse labels reserve space before actors and their ordinary intents.
	draw_voxel_fuse_labels(renderer, room)
	for &actor in v.snapshot.enemies[:v.snapshot.enemy_count] {
		cell := grid.Position{int(math.round(actor.position.x)), int(math.round(actor.position.y))}
		if !actor.visible || !tactical_render_visible(renderer, cell) { continue }
		anchor := tactical_project(renderer, {actor.position.x+0.5, actor.position.y+0.5}, 1.48)
		if v.scene_3d {
			quad := tactical_billboard_geometry(renderer, sprite_key_for_enemy(actor.archetype), actor.position)
			top := (quad.points[0]+quad.points[3])*0.5
			anchor = tactical_project(renderer, {top.x, top.z}, top.y+0.13)
		}
		first := fmt.ctprintf("HP %d", actor.health)
		if i, shielded := game.status_index(&actor.statuses, .Shield); shielded { first = fmt.ctprintf("HP %d / SC %d", actor.health, actor.statuses.items[i].potency) }
		intent: cstring = ""
		color := rl.Color{187, 106, 109, 255}
		icon := Intent_Icon.None
		alarm := false
		// Enemies keep their own clock: their intent stays on screen while the
		// player's move or cast plays, and only leaves with the enemy itself.
		if v.enabled || tactical_telegraphs_are_visible(renderer, room) {
			if i, found := game.enemy_index_by_id(room, actor.entity.id); found {
				enemy := &room.enemies[i]
				intent = tactical_intent_label(enemy.intent)
				icon, alarm = remembered_intent_icon(renderer, enemy.id, tactical_intent_icon(room, enemy), enemy.intent.windup)
				if enemy.intent.windup { color = {218, 169, 90, 255} }
				if enemy.intent.kind == .Recover { intent = fmt.ctprintf("RECUPERO %ds", enemy.recovery_pulses); color = {124, 164, 190, 255} }
				if enemy.intent.kind == .Attack && !enemy.intent.windup { intent = fmt.ctprintf("%s %d", intent, enemy.intent.damage) }
				if enemy.intent.kind != .Recover { intent = fmt.ctprintf("%s / %.1fs", intent, game.tactical_enemy_seconds(room, enemy)) }
				if game.enemy_is_staggered(room, enemy) { intent = "INTERROTTO"; color = GOTHIC_PAPER }
			}
		}
		if v.living {
			// A living board: the health of every enemy on screen stays shown.
			feet := tactical_project(renderer, {actor.position.x+0.5, actor.position.y+0.5})
			if feet.x < 0 || feet.y < 0 || feet.x > renderer.canvas_width || feet.y > renderer.canvas_height { continue }
			shield := i32(0)
			if i, shielded := game.status_index(&actor.statuses, .Shield); shielded { shield = actor.statuses.items[i].potency }
			// With the lab's seals the pictogram is on the card, not in the label.
			if intent_seals_on(renderer) { icon = .None }
			draw_living_health_label(renderer, anchor, living_health_text(actor.health, actor.max_health, shield), intent, color,
				actor.health, actor.max_health, icon, alarm, int(actor.entity.id))
			continue
		}
		draw_tactical_label(renderer, anchor, first, intent, color, f32(actor.health)/f32(max(i32(1), actor.max_health)),
			icon, alarm, int(actor.entity.id))
	}
	if tactical_room_is_clear(v.snapshot.phase) {
		p := room.exit_position
		draw_tactical_label(renderer, tactical_project(renderer, {f32(p.x)+0.5, f32(p.y)+0.5}, 1.3), "USCITA", "", {124, 199, 215, 255})
	}
}
