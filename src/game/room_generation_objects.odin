package game

import grid "../engine/grid"
import level "../level"

GENERATED_OBJECT_KINDS :: [?]Grid_Object_Kind{.Barrel, .Ice_Block, .Fire}

@(private = "file")
generated_object_kind :: proc(blueprint: ^Room_Blueprint, index: int) -> Grid_Object_Kind {
	if blueprint.encounter_kind == .Powder_Keg {
		kinds := [?]Grid_Object_Kind{.Barrel, .Barrel, .Ice_Block, .Fire}
		return kinds[index%len(kinds)]
	}
	kinds := GENERATED_OBJECT_KINDS
	return kinds[index%len(kinds)]
}

@(private = "file")
object_preserves_encounter_link :: proc(blueprint: ^Room_Blueprint, candidate: grid.Position) -> bool {
	if blueprint.encounter_kind != .Escort || len(blueprint.enemies) < 2 { return true }
	a, b := blueprint.enemies[0].position, blueprint.enemies[1].position
	return candidate != (grid.Position{x = (a.x+b.x)/2, y = (a.y+b.y)/2})
}

@(private)
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
		if position_in_list(blockers[:count], candidate) || !object_preserves_encounter_link(blueprint, candidate) ||
		   level.room_family_cell_is_reserved(&blueprint.level_data, blueprint.profile.level_config.family, candidate) ||
		   !object_preserves_enemy_lanes(blueprint, candidate) || !object_preserves_barrel_lanes(blueprint, candidate) { continue }
		if generated_object_kind(blueprint, len(blueprint.objects)) == .Barrel &&
		   !generated_barrel_has_push_lane(blueprint, candidate) { continue }
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

@(private)
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
		   level.room_family_cell_is_reserved(&blueprint.level_data, blueprint.profile.level_config.family, object.position) ||
		   !cell_is_walkable(&blueprint.level_data, object.position) ||
		   !position_is_safe_from_room_anchors(object.position, blueprint.level_data.player_spawn,
			blueprint.exit_position, config) || position_in_list(blockers[:count], object.position) {
			return false
		}
		if object.kind == .Barrel && !generated_barrel_has_push_lane(blueprint, object.position) { return false }
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
	return object_preserves_enemy_lanes(blueprint, {x = -1, y = -1}) &&
	       all_unblocked_walkable_cells_are_connected(&blueprint.level_data, blockers[:count])
}

@(private = "file")
generated_barrel_lane_cell_open :: proc(blueprint: ^Room_Blueprint, position, extra_blocker: grid.Position) -> bool {
	if !encounter_position_open(blueprint, position, extra_blocker) { return false }
	for trap in blueprint.traps { if trap.position == position { return false } }
	for enemy in blueprint.enemies { if enemy.position == position { return false } }
	return true
}

// Require a reachable stance and a free destination on opposite sides of every barrel.
@(private)
generated_barrel_has_push_lane :: proc(blueprint: ^Room_Blueprint, position: grid.Position, extra_blocker: grid.Position = {x = -1, y = -1}) -> bool {
	directions := [2]grid.Position{{x = 1, y = 0}, {x = 0, y = 1}}
	for direction in directions {
		a := grid.offset(position, direction.x, direction.y)
		b := grid.offset(position, -direction.x, -direction.y)
		if generated_barrel_lane_cell_open(blueprint, a, extra_blocker) &&
		   generated_barrel_lane_cell_open(blueprint, b, extra_blocker) { return true }
	}
	return false
}

@(private = "file")
object_preserves_barrel_lanes :: proc(blueprint: ^Room_Blueprint, candidate: grid.Position) -> bool {
	for object in blueprint.objects {
		if object.kind == .Barrel && !generated_barrel_has_push_lane(blueprint, object.position, candidate) { return false }
	}
	return true
}
