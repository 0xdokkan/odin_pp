package game

import grid "../grid"

GENERATED_OBJECT_KINDS :: [?]Grid_Object_Kind{.Barrel, .Ice_Block, .Fire}

generated_object_kind :: proc(blueprint: ^Room_Blueprint, index: int) -> Grid_Object_Kind {
	if blueprint.encounter_kind == .Powder_Keg {
		kinds := [?]Grid_Object_Kind{.Barrel, .Barrel, .Ice_Block, .Fire}
		return kinds[index%len(kinds)]
	}
	kinds := GENERATED_OBJECT_KINDS
	return kinds[index%len(kinds)]
}

object_preserves_encounter_link :: proc(blueprint: ^Room_Blueprint, candidate: grid.Position) -> bool {
	if blueprint.encounter_kind != .Escort || len(blueprint.enemies) < 2 { return true }
	a, b := blueprint.enemies[0].position, blueprint.enemies[1].position
	return candidate != (grid.Position{(a.x+b.x)/2, (a.y+b.y)/2})
}

generate_blueprint_objects :: proc(blueprint: ^Room_Blueprint, candidates: []grid.Position) -> bool {
	blockers: [MAX_GENERATED_OBSTACLES+MAX_GRID_OBJECTS_PER_ROOM]grid.Position
	count := len(blueprint.obstacles)
	copy(blockers[:], blueprint.obstacles[:])
	// Prefer explosives near the encounter; the second pass fills any remaining slots safely.
	for priority in 0..<2 {
	for candidate in candidates {
		if len(blueprint.objects) == blueprint.profile.encounter_config.object_count {
			break
		}
		if position_in_list(blockers[:count], candidate) || !object_preserves_encounter_link(blueprint, candidate) { continue }
		if priority == 0 && (generated_object_kind(blueprint, len(blueprint.objects)) != .Barrel ||
		   grid_distance(candidate, blueprint.enemies[0].position) > 2) { continue }
		// Treat Fire as blocked here so a route without fire damage remains available.
		if !all_unblocked_walkable_cells_are_connected(&blueprint.level_data, blockers[:count], candidate, true) {
			continue
		}
		append(&blueprint.objects, Grid_Object_Spawn{
			kind = generated_object_kind(blueprint, len(blueprint.objects)), position = candidate,
		})
		blockers[count] = candidate
		count += 1
	}
	}
	return len(blueprint.objects) == blueprint.profile.encounter_config.object_count
}

validate_blueprint_objects :: proc(blueprint: ^Room_Blueprint) -> bool {
	config := blueprint.profile.encounter_config
	if len(blueprint.objects) != config.object_count {
		return false
	}
	blockers: [MAX_GENERATED_OBSTACLES+MAX_GRID_OBJECTS_PER_ROOM]grid.Position
	count := len(blueprint.obstacles)
	copy(blockers[:], blueprint.obstacles[:])
	for object, index in blueprint.objects {
		if object.kind != generated_object_kind(blueprint, index) ||
		   !cell_is_walkable(&blueprint.level_data, object.position) ||
		   !position_is_safe_from_room_anchors(object.position, blueprint.level_data.player_spawn,
			blueprint.exit_position, config) || position_in_list(blockers[:count], object.position) {
			return false
		}
		for enemy in blueprint.enemies {
			if object.position == enemy.position {
				return false
			}
		}
		for trap in blueprint.traps {
			if object.position == trap.position {
				return false
			}
		}
		blockers[count] = object.position
		count += 1
	}
	return all_unblocked_walkable_cells_are_connected(&blueprint.level_data, blockers[:count])
}
