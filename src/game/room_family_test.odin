package game

import "core:testing"
import grid "../grid"
import level "../level"

@(test)
test_room_families_avoid_previous_room_and_validate_history :: proc(t: ^testing.T) {
	previous := level.Room_Family.Scattered
	seen: [5]bool
	for index in 0..<64 {
		node := test_generation_node(index, .Combat, 1+index%8, 0xFACE)
		blueprint, err := generate_room_blueprint(&node, previous)
		testing.expectf(t, err == .None, "room=%v previous=%v error=%v", index, previous, err)
		if err != .None { continue }
		family := blueprint.profile.level_config.family
		testing.expect(t, family != previous && family != .Scattered)
		testing.expect(t, validate_room_blueprint(&blueprint))
		seen[int(family)] = true
		if index == 0 {
			repeated, repeated_error := generate_room_blueprint(&node, previous)
			testing.expect_value(t, repeated_error, Room_Blueprint_Error.None)
			expect_blueprints_equal(t, &blueprint, &repeated)
			destroy_room_blueprint(&repeated)
			blueprint.previous_family = family
			testing.expect(t, !validate_room_blueprint(&blueprint))
			blueprint.previous_family = previous
		}
		content := room_blueprint_content(&blueprint)
		testing.expect_value(t, content.family, family)
		previous = family
		destroy_room_blueprint(&blueprint)
	}
	for index in 1..<len(seen) { testing.expect(t, seen[index]) }
}

@(test)
test_generated_rooms_preserve_flanking_gates_and_usable_barrels :: proc(t: ^testing.T) {
	court_rooms, archers, covered_archers, chargers, barrels := 0, 0, 0, 0, 0
	for seed in u64(1)..=192 {
		node := test_generation_node(int(seed), .Elite, 5, seed)
		blueprint, err := generate_room_blueprint(&node)
		testing.expectf(t, err == .None, "seed=%v error=%v", seed, err)
		if err != .None { continue }
		blockers: [MAX_GENERATED_OBSTACLES+MAX_GRID_OBJECTS_PER_ROOM]grid.Position
		count := len(blueprint.obstacles)
		copy(blockers[:], blueprint.obstacles[:])
		for object in blueprint.objects {
			blockers[count] = object.position
			count += 1
			if object.kind == .Barrel {
				barrels += 1
				testing.expectf(t, generated_barrel_has_push_lane(&blueprint, object.position), "barrel seed=%v", seed)
			}
		}
		for enemy in blueprint.enemies {
			neighbors, lane, cover := encounter_position_lanes(&blueprint, enemy.position)
			if enemy.archetype == .Archer {
				archers += 1
				if cover > 0 { covered_archers += 1 }
				testing.expectf(t, neighbors >= 2, "archer trapped seed=%v", seed)
			}
			if enemy.archetype == .Brute {
				chargers += 1
				testing.expectf(t, lane >= 3, "brute lane seed=%v", seed)
			}
		}
		if blueprint.profile.level_config.family == .Twin_Courts {
			court_rooms += 1
			for y in 1..<blueprint.level_data.tiles.height-1 {
				gate := grid.Position{blueprint.level_data.tiles.width/2, y}
				if !cell_is_walkable(&blueprint.level_data, gate) { continue }
				testing.expectf(t, all_unblocked_walkable_cells_are_connected(&blueprint.level_data, blockers[:count], gate, true),
					"second court gate must remain usable seed=%v closed=%v", seed, gate)
			}
		}
		destroy_room_blueprint(&blueprint)
	}
	testing.expect(t, court_rooms > 0 && archers > 0 && chargers > 0 && barrels > 0)
	testing.expectf(t, covered_archers*100 >= archers*75, "covered=%v total=%v", covered_archers, archers)
}
