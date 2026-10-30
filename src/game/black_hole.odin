package game

import grid "../engine/grid"

// BUCO NERO. The card opens a black hole on a free cell for BLACK_HOLE_SECONDS
// world beats. Its centre is the cell; its damage area is the square of
// `radius` cells round it (3x3 for a radius of 1) and its pull area the square
// one cell wider (5x5). Each beat, in turn:
//
//   - every foe in the pull area but outside the damage area, bosses and
//     minibosses excepted, is drawn one cell toward the centre (a diagonal step
//     where it may, else along the longer axis, else the other), under the
//     game's movement rules: a wall, a body or an object stops it, and a pool,
//     a trap or a fire acts on the cell it enters; a foe inside the damage area
//     stays where it stands;
//   - then every foe in the damage area takes `power` damage, boss and miniboss
//     included; a foe that falls to it is swallowed (Black_Hole_Swallowed
//     precedes its fall: the board spins it down the hole).
//
// Upgrades (+1 damage each) widen the hole: the radius is 1 + upgrade/2 (3x3
// to 7x7 at +4) and the pull one more. It closes after its last beat.

BLACK_HOLE_SECONDS :: i32(8)
BLACK_HOLE_BASE_DAMAGE :: i32(4)
BLACK_HOLE_MAX_UPGRADE_LEVEL :: i32(4)
// The events of one beat's pulls are shown together (Game_Event.visual_group).
BLACK_HOLE_VISUAL_GROUP :: u32(0x4248_0001)

black_hole_radius :: proc(upgrade_level: i32) -> i32 {
	return 1+max(i32(0), upgrade_level)/2
}

@(private)
open_black_hole_effect :: proc(damage, seconds, radius: i32) -> Effect {
	return {kind = .Open_Black_Hole, target = PLAYER_ENTITY, amount = damage, duration = seconds, charges = radius, card_definition = .Devouring_Hole}
}

// How far a cell is from the hole's centre, as the square's radius.
black_hole_distance :: proc(centre, cell: grid.Position) -> i32 {
	return i32(max(abs(cell.x-centre.x), abs(cell.y-centre.y)))
}

// The cell a foe at `from` is drawn to: the first step toward `centre` the
// movement rules allow (diagonal, then the longer axis, then the other).
@(private = "file")
black_hole_pull_step :: proc(room: ^Room, id: u32, from, centre: grid.Position) -> (to: grid.Position, ok: bool) {
	dx, dy := sign(centre.x-from.x), sign(centre.y-from.y)
	options: [3]grid.Position
	count := 0
	if dx != 0 && dy != 0 { options[count] = grid.offset(from, dx, dy); count += 1 }
	longer_x := abs(centre.x-from.x) >= abs(centre.y-from.y)
	first, second := grid.offset(from, dx, 0), grid.offset(from, 0, dy)
	if longer_x {
		if dx != 0 { options[count] = first; count += 1 }
		if dy != 0 { options[count] = second; count += 1 }
	} else {
		if dy != 0 { options[count] = second; count += 1 }
		if dx != 0 { options[count] = first; count += 1 }
	}
	for option in options[:count] {
		query := query_entity_movement(room, enemy_entity(id), option)
		if movement_query_is_clear(&query) { return option, true }
	}
	return
}

@(private)
black_hole_beat :: proc(room: ^Room, pulse: ^Pulse_Report) {
	ids: [MAX_GRID_OBJECTS_PER_ROOM]u32
	count := 0
	for object in room.objects { if object.kind == .Devouring_Hole && count < len(ids) { ids[count] = object.id; count += 1 } }
	for hole_id in ids[:count] {
		if room.phase != .Combat { return }
		index, found := object_index_by_id(room, hole_id)
		if !found { continue }
		hole := room.objects[index]
		record_event(&pulse.events, {kind = .Black_Hole_Tick, source = object_entity(hole_id), target = object_entity(hole_id), object_kind = .Devouring_Hole,
			from_position = hole.position, to_position = hole.position, amount = hole.life, duration = hole.radius, card_definition = .Devouring_Hole})
		foes, foe_count := emplacement_foe_ids(room)
		// The pull: one cell toward the centre for each foe outside the damage area,
		// the heavy ones left where they stand.
		for id in foes[:foe_count] {
			enemy_index, present := enemy_index_by_id(room, id)
			if !present || room.phase != .Combat { continue }
			enemy := room.enemies[enemy_index]
			distance := black_hole_distance(hole.position, enemy.position)
			if distance <= hole.radius || distance > hole.radius+1 || enemy_is_boss(enemy.archetype) { continue }
			// With layers, the foes on the hole's layer and those in its sight (layers.odin).
			if !effect_reaches(room, hole.position, enemy.position) { continue }
			to, ok := black_hole_pull_step(room, id, enemy.position, hole.position)
			if !ok { continue }
			report: Action_Report
			report.accepted = true
			apply_movement_effect(room, object_entity(hole_id), move_effect(enemy_entity(id), to), &report)
			for &event in report.events.events[:report.events.count] {
				if event.kind == .Moved || event.kind == .Movement_Step {
					event.card_definition = .Devouring_Hole
					event.visual_group = BLACK_HOLE_VISUAL_GROUP
				}
			}
			merge_action_report(pulse, &report)
		}
		// The damage: every foe in the damage area; those it kills are swallowed.
		foes, foe_count = emplacement_foe_ids(room)
		struck: [MAX_ENEMIES_PER_ROOM]u32
		struck_count := 0
		for id in foes[:foe_count] {
			enemy_index, present := enemy_index_by_id(room, id)
			if !present { continue }
			enemy := room.enemies[enemy_index]
			if black_hole_distance(hole.position, enemy.position) > hole.radius || !effect_reaches(room, hole.position, enemy.position) { continue }
			struck[struck_count] = id
			struck_count += 1
			guard: i32
			if shield, shielded := status_for_entity(room, enemy_entity(id), .Shield); shielded { guard = shield.potency }
			if enemy.health+guard <= hole.power {
				record_event(&pulse.events, {kind = .Black_Hole_Swallowed, source = object_entity(hole_id), target = enemy_entity(id),
					from_position = enemy.position, to_position = hole.position, amount = hole.power, card_definition = .Devouring_Hole})
			}
		}
		if struck_count > 0 {
			action := make_action(.Trigger, object_entity(hole_id))
			for id in struck[:struck_count] {
				added := add_effect(&action, damage_effect(enemy_entity(id), hole.power))
				assert(added)
			}
			report := resolve_action(room, &action)
			merge_action_report(pulse, &report)
		}
		if room.phase != .Combat { return }
		index, found = object_index_by_id(room, hole_id)
		if !found { continue }
		room.objects[index].life -= 1
		if room.objects[index].life <= 0 {
			record_event(&pulse.events, {kind = .Black_Hole_Closed, source = SYSTEM_ENTITY, target = object_entity(hole_id), object_kind = .Devouring_Hole,
				from_position = hole.position, to_position = hole.position, amount = hole.power, duration = hole.radius, card_definition = .Devouring_Hole})
			remove_grid_object(room, index)
		}
	}
}
