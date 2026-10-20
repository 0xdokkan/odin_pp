package level

import "core:testing"
import grid "../engine/grid"

@(test)
test_central_spawn_selects_nearest_clear_cell_without_carving_room_shapes :: proc(t: ^testing.T) {
	for family in ([?]Room_Family{.Scattered, .Pillars, .Ring, .Twin_Courts, .Asymmetric}) {
		for seed in u64(1)..=24 {
			for size in 0..<3 {
				config := family_test_config(family, 17+size*2, 11+size)
				config.central_spawn = true
				config.spawn_clearance_radius = 2 if size == 2 else 1
				config.min_spawn_exit_distance = 7+size
				data, err := generate_room(config, seed)
				testing.expectf(t, err == .None, "family=%v seed=%v size=%v error=%v", family, seed, size, err)
				if err != .None { continue }
				testing.expect_value(t, validate_generated_room(&data, config).error, Room_Validation_Error.None)
				testing.expect(t, !is_interior_corner(data.player_spawn, config.width, config.height))
				// There must not be a closer clear spawn with any valid exit.
				// This catches a silent fallback to corners or biased candidate order.
				chosen_distance := spawn_center_distance_squared(config, data.player_spawn)
				minimum, maximum := exit_candidate_bounds(config)
				for y in 1+config.spawn_clearance_radius..<config.height-1-config.spawn_clearance_radius {
					for x in 1+config.spawn_clearance_radius..<config.width-1-config.spawn_clearance_radius {
						candidate := grid.Position{x, y}
						if spawn_center_distance_squared(config, candidate) >= chosen_distance ||
						   !clearance_is_walkable(&data, candidate, config.spawn_clearance_radius) { continue }
						for exit_y in minimum.y..=maximum.y {
							for exit_x in minimum.x..=maximum.x {
								exit_position := grid.Position{exit_x, exit_y}
								testing.expect(t, !anchor_pair_is_valid(config, candidate, exit_position) ||
									!clearance_is_walkable(&data, exit_position, config.exit_clearance_radius))
							}
						}
					}
				}
				components, walls := family_interior_wall_components(&data)
				switch family {
				case .Scattered:
				case .Pillars: testing.expect_value(t, components, 4)
				case .Ring:
					testing.expect_value(t, components, 1)
					testing.expect(t, walls == 9 || walls == 15)
				case .Twin_Courts:
					testing.expect_value(t, components, 3)
					testing.expect_value(t, walls, config.height-4)
				case .Asymmetric: testing.expect_value(t, components, 2)
				}
				again, again_error := generate_room(config, seed)
				testing.expect_value(t, again_error, Room_Generation_Error.None)
				testing.expect(t, generated_levels_are_equal(&data, &again))
				destroy(&again)
				destroy(&data)
			}
		}
	}
}

@(test)
test_central_spawn_config_rejects_missing_clearance_or_impossible_exit_distance :: proc(t: ^testing.T) {
	config := family_test_config(.Pillars, 17, 11)
	config.central_spawn = true
	config.spawn_clearance_radius = 5
	expect_invalid_generation_config(t, config)
	config.spawn_clearance_radius = 1
	config.min_spawn_exit_distance = 20
	expect_invalid_generation_config(t, config)
}
