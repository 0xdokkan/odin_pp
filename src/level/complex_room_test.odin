package level

import "core:testing"
import grid "../engine/grid"

complex_room_test_config :: proc(family: Room_Family, tier, extra_width, extra_height: int) -> Room_Generation_Config {
	config := family_test_config(family, 17+tier*8+extra_width, 11+tier*6+extra_height)
	config.central_spawn = true
	config.complexity = tier
	config.spawn_clearance_radius = 2
	config.min_spawn_exit_distance = 7+tier*3
	return config
}

// A floor articulation would leave only a one-cell route between two regions.
// Tarjan's traversal checks every cell in linear time, including the gates.
complex_test_visit_floor :: proc(data: ^Level, index, parent: int, discovery, low: []int, sequence: ^int) -> (articulations: int) {
	sequence^ += 1
	discovery[index], low[index] = sequence^, sequence^
	position, _ := grid.position_of(&data.tiles, index)
	children, separating_child := 0, false
	for direction in CARDINAL_OFFSETS {
		next := grid.offset(position, direction.x, direction.y)
		next_index, found := grid.index_of(&data.tiles, next)
		if !found || !is_walkable(data.tiles.cells[next_index].kind) { continue }
		if discovery[next_index] == 0 {
			children += 1
			articulations += complex_test_visit_floor(data, next_index, index, discovery, low, sequence)
			low[index] = min(low[index], low[next_index])
			if low[next_index] >= discovery[index] { separating_child = true }
		} else if next_index != parent {
			low[index] = min(low[index], discovery[next_index])
		}
	}
	if (parent == -1 && children > 1) || (parent != -1 && separating_child) { articulations += 1 }
	return
}

complex_test_articulation_count :: proc(data: ^Level) -> int {
	discovery, low := make([]int, len(data.tiles.cells)), make([]int, len(data.tiles.cells))
	defer delete(discovery)
	defer delete(low)
	sequence := 0
	start, found := grid.index_of(&data.tiles, data.player_spawn)
	assert(found)
	return complex_test_visit_floor(data, start, -1, discovery, low, &sequence)
}

@(test)
test_complex_arenas_preserve_connected_wide_routes_and_clear_central_anchors :: proc(t: ^testing.T) {
	for family in ([4]Room_Family{.Pillars, .Ring, .Twin_Courts, .Asymmetric}) {
		for tier in 1..=3 {
			for variant in 0..<3 {
				config := complex_room_test_config(family, tier, variant*2, variant)
				for seed in u64(1)..=24 {
					data, err := generate_room(config, seed)
					testing.expectf(t, err == .None, "family=%v tier=%v variant=%v seed=%v error=%v", family, tier, variant, seed, err)
					if err != .None { continue }
					testing.expect_value(t, validate_generated_room(&data, config).error, Room_Validation_Error.None)
					testing.expect_value(t, data.layout_complexity, tier)
					testing.expectf(t, complex_test_articulation_count(&data) == 0, "one-cell choke family=%v tier=%v variant=%v seed=%v", family, tier, variant, seed)
					testing.expect(t, spawn_center_distance_squared(config, data.player_spawn) <= 16)
					for y in 1..<config.height-1 {
						for x in 1..<config.width-1 {
							position := grid.Position{x = x, y = y}
							if !complex_room_crossing_is_reserved(config.width, config.height, position) { continue }
							tile, _ := tile_at(&data, position)
							testing.expect(t, is_walkable(tile.kind))
							testing.expect(t, room_family_cell_is_reserved(&data, family, position))
						}
					}
					destroy(&data)
				}
			}
		}
	}
}

@(test)
test_complex_court_gates_preserve_approaches_for_generated_objects :: proc(t: ^testing.T) {
	for tier in 1..=3 {
		config := complex_room_test_config(.Twin_Courts, tier, 4, 2)
		data, err := generate_room(config, 71)
		testing.expect_value(t, err, Room_Generation_Error.None)
		if err != .None { continue }
		for partition in 1..=tier+1 {
			x := complex_court_partition_x(config.width, tier, partition)
			walls, gate_width := 0, 0
			for y in 1..<config.height-1 {
				tile, _ := tile_at(&data, {x = x, y = y})
				if !is_walkable(tile.kind) {
					walls += 1
					testing.expect(t, gate_width == 0 || gate_width >= 2)
					gate_width = 0
					continue
				}
				gate_width += 1
				for dx in -1..=1 { testing.expect(t, room_family_cell_is_reserved(&data, .Twin_Courts, {x = x+dx, y = y})) }
			}
			testing.expect(t, gate_width >= 2)
			testing.expect(t, walls >= 2, "a reserved route erased a court partition")
		}
		destroy(&data)
	}
}

@(test)
test_complex_family_cover_scales_and_generation_is_deterministic :: proc(t: ^testing.T) {
	for family in ([4]Room_Family{.Pillars, .Ring, .Twin_Courts, .Asymmetric}) {
		previous_walls := 0
		for tier in 1..=3 {
			config := complex_room_test_config(family, tier, 0, 0)
			first, first_error := generate_room(config, 311)
			second, second_error := generate_room(config, 311)
			testing.expect_value(t, first_error, Room_Generation_Error.None)
			testing.expect_value(t, second_error, Room_Generation_Error.None)
			testing.expect(t, generated_levels_are_equal(&first, &second))
			components, walls := family_interior_wall_components(&first)
			testing.expectf(t, walls > previous_walls, "cover did not grow family=%v tier=%v walls=%v previous=%v", family, tier, walls, previous_walls)
			testing.expectf(t, components >= 4, "family=%v tier=%v components=%v walls=%v", family, tier, components, walls)
			previous_walls = walls
			destroy(&first)
			destroy(&second)
		}
	}
}

@(test)
test_complexity_validation_rejects_unsupported_tiers :: proc(t: ^testing.T) {
	config := complex_room_test_config(.Pillars, 1, 0, 0)
	config.complexity = -1
	expect_invalid_generation_config(t, config)
	config.complexity = 4
	expect_invalid_generation_config(t, config)
}
