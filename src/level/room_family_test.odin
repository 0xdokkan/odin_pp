package level

import "core:testing"
import grid "../engine/grid"

family_test_config :: proc(family: Room_Family, width, height: int) -> Room_Generation_Config {
	config := default_room_generation_config(width, height)
	config.family = family
	config.exit_center_radius = width/2
	config.min_walkable_percent = 68
	return config
}

family_interior_wall_components :: proc(data: ^Level) -> (components, count: int) {
	visited := make([]bool, len(data.tiles.cells))
	queue := make([]grid.Position, len(data.tiles.cells))
	defer delete(visited)
	defer delete(queue)
	for tile, index in data.tiles.cells {
		position, _ := grid.position_of(&data.tiles, index)
		if tile.kind != .Wall || is_border_position(position, data.tiles.width, data.tiles.height) { continue }
		count += 1
		if visited[index] { continue }
		components += 1
		visited[index] = true
		queue[0] = position
		head, tail := 0, 1
		for head < tail {
			current := queue[head]
			head += 1
			for direction in CARDINAL_OFFSETS {
				next := grid.Position{current.x+direction.x, current.y+direction.y}
				if is_border_position(next, data.tiles.width, data.tiles.height) { continue }
				next_index, found := grid.index_of(&data.tiles, next)
				if !found || visited[next_index] || data.tiles.cells[next_index].kind != .Wall { continue }
				visited[next_index] = true
				queue[tail] = next
				tail += 1
			}
		}
	}
	return
}

@(test)
test_tactical_families_keep_distinct_shapes_and_safe_anchors :: proc(t: ^testing.T) {
	families := [4]Room_Family{.Pillars, .Ring, .Twin_Courts, .Asymmetric}
	for family in families {
		for seed in u64(1)..=128 {
			for size in 0..<3 {
				config := family_test_config(family, 15+size*2, 9+size)
				data, err := generate_room(config, seed)
				testing.expectf(t, err == .None, "family=%v seed=%v size=%v error=%v", family, seed, size, err)
				if err != .None { continue }
				testing.expect_value(t, validate_generated_room(&data, config).error, Room_Validation_Error.None)
				components, walls := family_interior_wall_components(&data)
				switch family {
				case .Scattered: unreachable()
				case .Pillars:
					testing.expect_value(t, components, 4)
					testing.expect(t, walls >= 4 && walls <= 8)
				case .Ring:
					testing.expect_value(t, components, 1)
					testing.expect(t, walls == 9 || walls == 15)
				case .Twin_Courts:
					testing.expect_value(t, components, 3)
					testing.expect_value(t, walls, config.height-4)
					gates := 0
					for y in 1..<config.height-1 {
						tile, _ := tile_at(&data, {config.width/2, y})
						if is_walkable(tile.kind) { gates += 1 }
					}
					testing.expect_value(t, gates, 2)
				case .Asymmetric:
					testing.expect_value(t, components, 2)
					testing.expect(t, walls >= config.height-2)
				}
				destroy(&data)
			}
		}
	}
}

@(test)
test_tactical_family_generation_is_reproducible_and_varies_with_seed :: proc(t: ^testing.T) {
	families := [4]Room_Family{.Pillars, .Ring, .Twin_Courts, .Asymmetric}
	for family in families {
		config := family_test_config(family, 15, 9)
		first, first_error := generate_room(config, 77)
		second, second_error := generate_room(config, 77)
		testing.expect_value(t, first_error, Room_Generation_Error.None)
		testing.expect_value(t, second_error, Room_Generation_Error.None)
		testing.expect(t, generated_levels_are_equal(&first, &second))
		varied := false
		for seed in u64(78)..=90 {
			candidate, err := generate_room(config, seed)
			testing.expect_value(t, err, Room_Generation_Error.None)
			varied = varied || !generated_levels_are_equal(&first, &candidate)
			destroy(&candidate)
		}
		testing.expect(t, varied)
		destroy(&first)
		destroy(&second)
	}
}

@(test)
test_tactical_family_rejects_too_small_config_without_scattered_fallback :: proc(t: ^testing.T) {
	config := family_test_config(.Ring, 9, 7)
	data, err := generate_room(config, 22)
	testing.expect_value(t, err, Room_Generation_Error.Invalid_Config)
	testing.expect_value(t, len(data.tiles.cells), 0)
	destroy(&data)
}
