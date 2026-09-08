package render

import "core:c"
import "core:fmt"
import rl "vendor:raylib"
import game "../game"
import grid "../grid"
import view "../view"

// Match the visible silhouettes, including the raised part above the floor tile.
// These tests use canvas coordinates so panning and zooming preserve picking.
object_body_contains_point :: proc(kind: game.Grid_Object_Kind, center, point: view.Vec2, zoom: f32) -> bool {
	dx, dy := abs(point.x-center.x), point.y-center.y
	switch kind {
	case .Barrel:
		radius := max(f32(8), 12*zoom)
		return dx <= radius && dy >= -radius*1.7 && dy <= radius*0.3
	case .Bomb:
		radius := max(f32(8), 12*zoom)
		return dx*dx+(dy+radius*0.35)*(dy+radius*0.35) <= radius*radius
	case .Ice_Block:
		half_width := max(f32(9), 17*zoom)
		half_depth := max(f32(4.5), 8*zoom)
		height := max(f32(13), 23*zoom)
		if dx > half_width {
			return false
		}
		// The six outer edges of the extruded diamond form this silhouette.
		inset := half_depth*dx/half_width
		return dy >= -height-half_depth+inset && dy <= half_depth-inset
	case .Fire:
		half_width := max(f32(7), 11*zoom)
		base_y := max(f32(2), 3*zoom)
		height := max(f32(16), 27*zoom)
		return dy >= base_y-height && dy <= base_y+half_width*0.62 && dx <= half_width*1.22
	case .Count:
		return false
	}
	return false
}

body_circle_contains_point :: proc(center, point: view.Vec2, radius: f32) -> bool {
	dx, dy := point.x-center.x, point.y-center.y
	return dx*dx+dy*dy <= radius*radius
}

enemy_body_contains_point :: proc(renderer: ^Renderer, enemy: game.Enemy, center, point: view.Vec2) -> bool {
	if hit, configured := sprite_asset_contains_point(&renderer.sprite_assets, sprite_key_for_enemy(enemy.archetype), center, point, renderer.camera.zoom); configured {
		return hit
	}
	radius := enemy_draw_radius(renderer, enemy)
	dx, dy := point.x-center.x, point.y-center.y
	switch enemy.archetype {
	case .Brute:
		// draw_enemy_body rasterizes the Brute rectangle with integer coordinates.
		return point_in_rectangle(point, {
			x = f32(c.int(center.x-radius)), y = f32(c.int(center.y-radius)),
			width = f32(c.int(radius*2)), height = f32(c.int(radius*2)),
		})
	case .Demolitionist:
		if abs(dx) <= radius && abs(dy) <= radius {
			return true
		}
		for side in -1..=1 {
			if side != 0 && body_circle_contains_point(
				{center.x+f32(side)*radius*0.85, center.y-radius*0.65}, point, radius*0.43,
			) {
				return true
			}
		}
		return false
	case .Custodian:
		if body_circle_contains_point(center, point, radius) {
			return true
		}
		if dy < -radius*1.25 || dy > radius*0.9 {
			return false
		}
		shield_half_width := radius*0.8*(dy+radius*1.25)/(radius*0.85) if dy < -radius*0.4 else
		                     radius*0.8*(radius*0.9-dy)/(radius*1.3)
		return abs(dx) <= shield_half_width
	case .Bomber:
		return body_circle_contains_point(center, point, radius) ||
		       body_circle_contains_point({center.x+radius*0.55, center.y-radius*0.5}, point, radius*0.45) ||
		       body_circle_contains_point({center.x+radius*0.75, center.y-radius}, point, max(f32(2), radius*0.18))
	case .Chaser, .Archer:
		return body_circle_contains_point(center, point, radius)
	case .Count:
		return false
	}
	return false
}

actor_body_cell_at_point :: proc(renderer: ^Renderer, room: ^game.Room, point: view.Vec2) -> (position: grid.Position, found: bool) {
	if renderer == nil || room == nil {
		return
	}
	// The player is painted last. Otherwise the last enemy in paint order wins.
	if room.player != nil {
		center := cell_center(renderer, room.player.position)
		radius := max(f32(8), 13*renderer.camera.zoom)
		hit, configured := sprite_asset_contains_point(&renderer.sprite_assets, .Player, center, point, renderer.camera.zoom)
		if hit || (!configured && body_circle_contains_point(center, point, radius)) {
			return room.player.position, true
		}
	}
	for enemy in room.enemies {
		center := cell_center(renderer, enemy.position)
		if enemy_body_contains_point(renderer, enemy, center, point) {
			position, found = enemy.position, true
		}
	}
	return
}

actor_body_at_point :: proc(renderer: ^Renderer, room: ^game.Room, point: view.Vec2) -> bool {
	_, found := actor_body_cell_at_point(renderer, room, point)
	return found
}

grid_object_at_canvas_point :: proc(renderer: ^Renderer, room: ^game.Room, point: view.Vec2) -> (index: int, found: bool) {
	if renderer == nil || room == nil || renderer.camera.zoom <= 0 ||
	   !view.projection_is_valid(&renderer.projection) || renderer_timeline_is_busy(renderer) {
		return
	}
	// Actors are drawn after objects. A bomb beneath an enemy must not steal its click.
	if actor_body_at_point(renderer, room, point) {
		return
	}
	for object, object_index in room.objects {
		center := cell_center(renderer, object.position)
		hit, configured := sprite_asset_contains_point(&renderer.sprite_assets, sprite_key_for_object(object.kind), center, point, renderer.camera.zoom)
		if hit || (!configured && object_body_contains_point(object.kind, center, point, renderer.camera.zoom)) {
			// Objects are painted in array order, so the last visible hit wins.
			index, found = object_index, true
		}
	}
	return
}

object_aware_card_target_cell :: proc(
	renderer: ^Renderer,
	room: ^game.Room,
	card: game.Card_Instance,
	point: view.Vec2,
	floor_cell: grid.Position,
) -> grid.Position {
	definition, valid := game.card_definition_by_id(card.definition_id)
	if !valid || renderer == nil || room == nil || definition.targeting.shape != .Single ||
	   renderer_timeline_is_busy(renderer) {
		return floor_cell
	}
	if definition.targeting.rule != .Opponent && definition.targeting.rule != .Opponent_Or_Object &&
	   definition.targeting.rule != .Adjacent_Opponent {
		return floor_cell
	}
	// A visible actor corner may project onto a different floor cell at low
	// zoom. Merely vetoing the object hit would still target that floor object.
	if position, found := actor_body_cell_at_point(renderer, room, point); found {
		return position
	}
	if definition.targeting.rule != .Opponent_Or_Object {
		return floor_cell
	}
	if index, found := grid_object_at_canvas_point(renderer, room, point); found {
		object := room.objects[index]
		if game.entity_is_targetable_object(room, game.object_entity(object.id)) {
			return object.position
		}
	}
	return floor_cell
}

// Run after camera input, and again after changing the selected/dragged card.
// Always start from the floor projection: switching to Dash or an AoE restores
// their exact cell geometry instead of retaining an object anchor from Shove.
update_object_target_hover :: proc(renderer: ^Renderer, room: ^game.Room, point: view.Vec2, card_id: u32) {
	if renderer == nil || room == nil || room.player == nil || room.level_data == nil ||
	   renderer.camera.zoom <= 0 || !view.projection_is_valid(&renderer.projection) ||
	   renderer_timeline_is_busy(renderer) || !card_drop_area_contains(renderer, point) {
		return
	}
	position := view.canvas_to_cell(&renderer.camera, &renderer.projection, point)
	if index, found := game.hand_card_index_by_id(&room.player.deck, card_id); found {
		position = object_aware_card_target_cell(renderer, room, room.player.deck.hand[index], point, position)
	}
	renderer.hovered_cell = position
	renderer.has_hovered_cell = grid.contains(&room.level_data.tiles, position)
}

Object_Shove_Hint :: struct {
	object: game.Grid_Object,
	shove_in_hand, selected, affordable: bool,
	distance: int,
	remaining_pulses: int,
	evaluation: game.Card_Target_Evaluation,
	targets_object, can_push, breaks_before_push: bool,
}

object_shove_hint :: proc(room: ^game.Room, object_id, active_card_id: u32) -> (hint: Object_Shove_Hint, found: bool) {
	if room == nil || room.player == nil {
		return
	}
	index, exists := game.object_index_by_id(room, object_id)
	if !exists {
		return
	}
	hint.object = room.objects[index]
	hint.distance = abs(hint.object.position.x-room.player.position.x)+abs(hint.object.position.y-room.player.position.y)
	hint.remaining_pulses = game.explosive_pulses_remaining(hint.object.detonation_pulse, room.pulse_count)
	// Evaluate the same movement rule even when Shove is not drawn, so help can
	// explain the required position without granting a card or altering the deck.
	card := game.Card_Instance{id = 1, definition_id = .Shove}
	for instance in room.player.deck.hand[:room.player.deck.hand_count] {
		if instance.definition_id == .Shove {
			card = instance
			hint.shove_in_hand = true
			if instance.id == active_card_id {
				hint.selected = true
				break
			}
		}
	}
	definition, _ := game.card_definition_by_id(.Shove)
	hint.affordable = room.player.deck.energy >= definition.cost
	hint.evaluation = game.evaluate_card_targeting(room, card, game.card_target_request_at(definition, hint.object.position))
	hint.targets_object = hint.evaluation.query.has_primary_target &&
	                      hint.evaluation.query.primary_target == game.entity_target(game.object_entity(object_id))
	object_definition, _ := game.grid_object_definition(hint.object.kind)
	hint.breaks_before_push = object_definition.damageable && !object_definition.explosive &&
	                          hint.object.health <= 1+card.upgrade_level
	hint.can_push = hint.targets_object && hint.evaluation.error == .None &&
	                hint.evaluation.has_movement && !hint.breaks_before_push &&
	                game.movement_query_is_clear(&hint.evaluation.movement)
	return hint, true
}

draw_object_interaction_ground :: proc(renderer: ^Renderer, room: ^game.Room, active_card_id: u32) {
	if renderer == nil || room == nil || !renderer.has_hovered_cell || renderer_timeline_is_busy(renderer) {
		return
	}
	index, found := game.object_index_at(room, renderer.hovered_cell)
	if !found {
		return
	}
	hint, valid := object_shove_hint(room, room.objects[index].id, active_card_id)
	if !valid || !hint.selected || !hint.targets_object || !hint.evaluation.has_movement {
		return
	}
	color := rl.Color{113, 231, 210, 230}
	label: cstring = "PUSH 1"
	if !hint.can_push {
		color = {255, 112, 102, 235}
		label = "BLOCKED"
		if hint.breaks_before_push {
			label = "BREAKS"
		}
	}
	origin := cell_center(renderer, hint.object.position)
	destination := cell_center(renderer, hint.evaluation.movement.destination)
	rl.DrawLineEx(to_raylib(origin), to_raylib(destination), 3, color)
	step_x, step_y := destination.x-origin.x, destination.y-origin.y
	wing_a := view.Vec2{destination.x-step_x*0.25-step_y*0.2, destination.y-step_y*0.25+step_x*0.2}
	wing_b := view.Vec2{destination.x-step_x*0.25+step_y*0.2, destination.y-step_y*0.25-step_x*0.2}
	rl.DrawLineEx(to_raylib(wing_a), to_raylib(destination), 3, color)
	rl.DrawLineEx(to_raylib(wing_b), to_raylib(destination), 3, color)
	rl.DrawText(label, c.int(destination.x)-rl.MeasureText(label, 10)/2, c.int(destination.y)+7, 10, color)
}

draw_object_interaction_help :: proc(renderer: ^Renderer, room: ^game.Room, point: view.Vec2, active_card_id: u32) {
	if renderer == nil || room == nil || room.player == nil || room.phase != .Combat ||
	   renderer_timeline_is_busy(renderer) {
		return
	}
	selected_shove := false
	if card_index, found := game.hand_card_index_by_id(&room.player.deck, active_card_id); found {
		selected_shove = room.player.deck.hand[card_index].definition_id == .Shove
	}
	index, found := grid_object_at_canvas_point(renderer, room, point)
	if !found && renderer.has_hovered_cell && card_drop_area_contains(renderer, point) &&
	   !actor_body_at_point(renderer, room, point) {
		index, found = game.object_index_at(room, renderer.hovered_cell)
	}
	if !found && !selected_shove {
		return
	}
	// Fixed compact panel below the status bar; the hand is drawn afterward.
	x, y: c.int = 14, 130
	for enemy in room.enemies {
		if enemy.archetype == .Demolitionist {
			y = 192
			break
		}
	}
	width: c.int = 350
	rl.DrawRectangle(x, y, width, 100, rl.Color{12, 15, 18, 238})
	title: cstring = "SHOVE: MOVE OBJECTS"
	line_one: cstring = "Stand beside the target, not diagonally."
	line_two: cstring = "Drag Shove onto it, or select its slot + click."
	line_three: cstring = "Pushes 1 cell away; destination must be empty."
	line_four: cstring = "Barrels ignite on hit: blast after 2 more actions."
	accent := rl.Color{113, 231, 210, 255}
	if found {
		hint, valid := object_shove_hint(room, room.objects[index].id, active_card_id)
		if !valid {
			return
		}
		definition, _ := game.grid_object_definition(hint.object.kind)
		title = fmt.ctprintf("%s  |  SHOVE: RANGE 1", definition.name)
		if hint.object.kind == .Fire {
			title = "FIRE: PERSISTENT HAZARD"
			line_one = "Deals 2 damage whenever an actor enters."
			line_two = "Cannot be pushed or extinguished with Shove."
			line_three = "Push enemies into it, or move around it."
			line_four = "Moving a barrel beside fire lights its fuse."
		} else {
			if hint.distance != 1 {
				line_one = fmt.ctprintf("Out of range (%d): stand beside this object.", hint.distance)
				accent = {255, 185, 105, 255}
			} else if !hint.targets_object {
				line_one = "Shared cell: Shove targets the enemy standing here."
			} else if hint.breaks_before_push {
				line_one = "Shove breaks this ice before it can move."
			} else if !hint.can_push {
				line_one = "BLOCKED: the cell beyond the object is occupied."
				accent = {255, 112, 102, 255}
			} else {
				line_one = fmt.ctprintf("Push destination: (%d, %d), one cell away.", hint.evaluation.movement.destination.x, hint.evaluation.movement.destination.y)
			}
			if !hint.shove_in_hand {
				line_two = "Draw Shove to move it. Walking into it won't push."
			} else if !hint.affordable {
				line_two = "Shove needs 1 energy. Move or wait to recover it."
			}
			if hint.object.kind == .Ice_Block {
				line_three = "Shove deals damage, then pushes surviving ice."
				line_four = "Blocks movement and line of sight."
			} else if hint.object.detonation_pulse != 0 {
				line_three = fmt.ctprintf("FUSE: %d actions left. Pushing does not reset it.", hint.remaining_pulses)
				line_four = "BLAST: 4 damage / 3x3 / hits you and enemies."
			} else {
				line_three = "Shove lights the fuse, even if the push is blocked."
				line_four = "BLAST: after 2 more actions / 4 damage / 3x3."
			}
		}
	}
	rl.DrawRectangleLines(x, y, width, 100, accent)
	rl.DrawText(title, x+10, y+9, 12, accent)
	lines := [?]cstring{line_one, line_two, line_three, line_four}
	for line, line_index in lines {
		rl.DrawText(line, x+10, y+29+c.int(line_index)*15, 10, rl.Color{216, 221, 214, 255})
	}
}
