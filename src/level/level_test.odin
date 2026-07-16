package level

import "core:testing"
import grid "../grid"

@(test)
test_ascii_map_parses_tiles_and_spawn :: proc(t: ^testing.T) {
	rows := [?]string{
		"#####",
		"#@..#",
		"#.+>#",
		"#####",
	}

	level, err, _ := from_ascii(rows[:])
	testing.expect_value(t, err, Parse_Error.None)
	defer destroy(&level)

	testing.expect_value(t, level.tiles.width, 5)
	testing.expect_value(t, level.tiles.height, 4)
	testing.expect_value(t, level.player_spawn, grid.Position{x = 1, y = 1})

	door, found := tile_at(&level, {x = 2, y = 2})
	testing.expect(t, found)
	testing.expect_value(t, door.kind, Tile_Kind.Door)
	testing.expect(t, is_walkable(door.kind))
}

@(test)
test_ascii_map_rejects_invalid_shapes_and_symbols :: proc(t: ^testing.T) {
	uneven := [?]string{"####", "#@#"}
	_, shape_err, shape_at := from_ascii(uneven[:])
	testing.expect_value(t, shape_err, Parse_Error.Inconsistent_Row_Width)
	testing.expect_value(t, shape_at, grid.Position{x = 3, y = 1})

	unknown := [?]string{"###", "#@!", "###"}
	_, symbol_err, symbol_at := from_ascii(unknown[:])
	testing.expect_value(t, symbol_err, Parse_Error.Unknown_Symbol)
	testing.expect_value(t, symbol_at, grid.Position{x = 2, y = 1})
}

@(test)
test_ascii_map_requires_one_spawn :: proc(t: ^testing.T) {
	missing := [?]string{"###", "#.#", "###"}
	_, missing_err, _ := from_ascii(missing[:])
	testing.expect_value(t, missing_err, Parse_Error.Missing_Player_Spawn)

	multiple := [?]string{"#####", "#@.@#", "#####"}
	_, multiple_err, multiple_at := from_ascii(multiple[:])
	testing.expect_value(t, multiple_err, Parse_Error.Multiple_Player_Spawns)
	testing.expect_value(t, multiple_at, grid.Position{x = 3, y = 1})
}

@(test)
test_generated_room_has_solid_border_and_walkable_spawn :: proc(t: ^testing.T) {
	config := default_room_generation_config(15, 9)
	level, err := generate_room(config, 0xC0FFEE)
	testing.expect_value(t, err, Room_Generation_Error.None)
	defer destroy(&level)
	report := validate_generated_room(&level, config)
	testing.expect_value(t, report.error, Room_Validation_Error.None)

	for y in 0..<level.tiles.height {
		for x in 0..<level.tiles.width {
			is_border := x == 0 || y == 0 || x == level.tiles.width-1 || y == level.tiles.height-1
			if !is_border {
				continue
			}
			tile, found := tile_at(&level, {x = x, y = y})
			testing.expect(t, found)
			testing.expect_value(t, tile.kind, Tile_Kind.Wall)
		}
	}

	spawn, found := tile_at(&level, level.player_spawn)
	testing.expect(t, found)
	testing.expect(t, is_walkable(spawn.kind))
	testing.expect(t, abs(report.exit_position.x-config.width/2) <= config.exit_center_radius)
	testing.expect(t, abs(report.exit_position.y-config.height/2) <= config.exit_center_radius)
	testing.expect(t, report.spawn_exit_distance >= config.min_spawn_exit_distance)
}

generated_levels_are_equal :: proc(first, second: ^Level) -> bool {
	if first == nil || second == nil || first.player_spawn != second.player_spawn ||
	   first.has_player_spawn != second.has_player_spawn ||
	   first.tiles.width != second.tiles.width || first.tiles.height != second.tiles.height ||
	   len(first.tiles.cells) != len(second.tiles.cells) {
		return false
	}
	for tile, index in first.tiles.cells {
		if tile != second.tiles.cells[index] {
			return false
		}
	}
	return true
}

@(test)
test_generated_room_is_deterministic_and_seed_sensitive :: proc(t: ^testing.T) {
	config := default_room_generation_config(15, 9)
	first, first_error := generate_room(config, 77)
	testing.expect_value(t, first_error, Room_Generation_Error.None)
	defer destroy(&first)
	second, second_error := generate_room(config, 77)
	testing.expect_value(t, second_error, Room_Generation_Error.None)
	defer destroy(&second)
	testing.expect(t, generated_levels_are_equal(&first, &second))

	found_different_layout := false
	for seed in u64(78)..=u64(96) {
		candidate, candidate_error := generate_room(config, seed)
		testing.expect_value(t, candidate_error, Room_Generation_Error.None)
		if candidate_error == .None {
			found_different_layout = found_different_layout ||
			                         !generated_levels_are_equal(&first, &candidate)
		}
		destroy(&candidate)
	}
	testing.expect(t, found_different_layout)
}

expect_invalid_generation_config :: proc(t: ^testing.T, config: Room_Generation_Config) {
	testing.expect(t, !generation_config_is_valid(config))
	generated, err := generate_room(config, 1)
	testing.expect_value(t, err, Room_Generation_Error.Invalid_Config)
	destroy(&generated)
}

@(test)
test_room_generation_rejects_invalid_configs_and_bounds_attempts :: proc(t: ^testing.T) {
	base := default_room_generation_config(15, 9)

	invalid := base
	invalid.width = 4
	expect_invalid_generation_config(t, invalid)
	invalid = base
	invalid.wall_density_percent = 101
	expect_invalid_generation_config(t, invalid)
	invalid = base
	invalid.spawn_clearance_radius = -1
	expect_invalid_generation_config(t, invalid)
	invalid = base
	invalid.exit_center_radius = -1
	expect_invalid_generation_config(t, invalid)
	invalid = base
	invalid.min_walkable_percent = 0
	expect_invalid_generation_config(t, invalid)
	invalid = base
	invalid.max_attempts = 0
	expect_invalid_generation_config(t, invalid)
	invalid = base
	invalid.width = MAX_GENERATED_ROOM_DIMENSION+1
	expect_invalid_generation_config(t, invalid)
	invalid = base
	invalid.max_attempts = MAX_ROOM_GENERATION_ATTEMPTS+1
	expect_invalid_generation_config(t, invalid)
	invalid = base
	invalid.min_spawn_exit_distance = 100
	expect_invalid_generation_config(t, invalid)

	exhausted := base
	exhausted.wall_density_percent = 100
	exhausted.min_walkable_percent = 90
	exhausted.max_attempts = 1
	testing.expect(t, generation_config_is_valid(exhausted))
	generated, err := generate_room(exhausted, 9)
	testing.expect_value(t, err, Room_Generation_Error.Attempts_Exhausted)
	destroy(&generated)
}

@(test)
test_room_generation_accepts_minimum_and_maximum_dimensions :: proc(t: ^testing.T) {
	dimensions := [?]int{MIN_GENERATED_ROOM_DIMENSION, MAX_GENERATED_ROOM_DIMENSION}
	for dimension in dimensions {
		config := default_room_generation_config(dimension, dimension)
		config.wall_density_percent = 0
		config.max_attempts = 1
		testing.expect(t, generation_config_is_valid(config))

		generated, err := generate_room(config, u64(dimension))
		testing.expect_value(t, err, Room_Generation_Error.None)
		if err != .None {
			continue
		}
		report := validate_generated_room(&generated, config)
		testing.expect_value(t, report.error, Room_Validation_Error.None)
		testing.expect_value(t, generated.tiles.width, dimension)
		testing.expect_value(t, generated.tiles.height, dimension)
		destroy(&generated)
	}
}

@(test)
test_generated_room_validator_reports_structural_damage :: proc(t: ^testing.T) {
	config := default_room_generation_config(15, 9)
	config.wall_density_percent = 0
	level, err := generate_room(config, 123)
	testing.expect_value(t, err, Room_Generation_Error.None)
	defer destroy(&level)

	assert(set_tile(&level, {x = 0, y = 0}, Tile{kind = .Floor}))
	report := validate_generated_room(&level, config)
	testing.expect_value(t, report.error, Room_Validation_Error.Border_Not_Solid)
	assert(set_tile(&level, {x = 0, y = 0}, Tile{kind = .Wall}))

	report = validate_generated_room(&level, config)
	exit_position := report.exit_position
	assert(set_tile(&level, exit_position, Tile{kind = .Floor}))
	report = validate_generated_room(&level, config)
	testing.expect_value(t, report.error, Room_Validation_Error.Missing_Exit)
	assert(set_tile(&level, exit_position, Tile{kind = .Exit}))

	extra_exit := grid.Position{x = 2, y = 2}
	if extra_exit == level.player_spawn {
		extra_exit.x += 1
	}
	assert(set_tile(&level, extra_exit, Tile{kind = .Exit}))
	report = validate_generated_room(&level, config)
	testing.expect_value(t, report.error, Room_Validation_Error.Multiple_Exits)
}

@(test)
test_generated_room_validator_detects_unreachable_exit :: proc(t: ^testing.T) {
	config := default_room_generation_config(15, 9)
	config.wall_density_percent = 0
	level, err := generate_room(config, 456)
	testing.expect_value(t, err, Room_Generation_Error.None)
	defer destroy(&level)
	report := validate_generated_room(&level, config)
	testing.expect_value(t, report.error, Room_Validation_Error.None)

	for y in report.exit_position.y-2..=report.exit_position.y+2 {
		for x in report.exit_position.x-2..=report.exit_position.x+2 {
			if max(abs(x-report.exit_position.x), abs(y-report.exit_position.y)) == 2 {
				assert(set_tile(&level, {x = x, y = y}, Tile{kind = .Wall}))
			}
		}
	}
	report = validate_generated_room(&level, config)
	testing.expect_value(t, report.error, Room_Validation_Error.Exit_Unreachable)
}

@(test)
test_generated_room_validator_enforces_full_exit_clearance :: proc(t: ^testing.T) {
	config := default_room_generation_config(15, 9)
	config.wall_density_percent = 0
	config.exit_center_radius = config.width
	level, err := generate_room(config, 789)
	testing.expect_value(t, err, Room_Generation_Error.None)
	defer destroy(&level)
	report := validate_generated_room(&level, config)
	testing.expect_value(t, report.error, Room_Validation_Error.None)
	assert(set_tile(&level, report.exit_position, Tile{kind = .Floor}))
	assert(set_tile(&level, {x = 1, y = config.height/2}, Tile{kind = .Exit}))

	report = validate_generated_room(&level, config)
	testing.expect_value(t, report.error, Room_Validation_Error.Exit_Clearance_Blocked)
}

@(test)
test_generated_room_validator_uses_geometric_anchor_distance :: proc(t: ^testing.T) {
	config := default_room_generation_config(15, 9)
	config.wall_density_percent = 0
	config.exit_center_radius = config.width
	level, err := generate_room(config, 987)
	testing.expect_value(t, err, Room_Generation_Error.None)
	defer destroy(&level)
	report := validate_generated_room(&level, config)
	testing.expect_value(t, report.error, Room_Validation_Error.None)
	assert(set_tile(&level, report.exit_position, Tile{kind = .Floor}))

	close_exit := grid.Position{x = 3, y = 3}
	if level.player_spawn.x > config.width/2 {
		close_exit.x = config.width-4
	}
	if level.player_spawn.y > config.height/2 {
		close_exit.y = config.height-4
	}
	assert(set_tile(&level, close_exit, Tile{kind = .Exit}))
	report = validate_generated_room(&level, config)
	testing.expect_value(t, report.error, Room_Validation_Error.Spawn_Exit_Too_Close)
}

@(test)
test_generated_room_validator_distinguishes_disconnected_and_sparse_layouts :: proc(t: ^testing.T) {
	config := default_room_generation_config(15, 9)
	config.wall_density_percent = 0
	level, err := generate_room(config, 654)
	testing.expect_value(t, err, Room_Generation_Error.None)
	defer destroy(&level)
	report := validate_generated_room(&level, config)
	testing.expect_value(t, report.error, Room_Validation_Error.None)

	pocket: grid.Position
	pocket_found := false
	for y in 2..<config.height-2 {
		for x in 2..<config.width-2 {
			candidate := grid.Position{x = x, y = y}
			spawn_distance := max(abs(candidate.x-level.player_spawn.x), abs(candidate.y-level.player_spawn.y))
			exit_distance := max(abs(candidate.x-report.exit_position.x), abs(candidate.y-report.exit_position.y))
			if spawn_distance > 2 && exit_distance > 2 {
				pocket = candidate
				pocket_found = true
				break
			}
		}
		if pocket_found {
			break
		}
	}
	testing.expect(t, pocket_found)
	if pocket_found {
		for offset in CARDINAL_OFFSETS {
			assert(set_tile(
				&level,
				{x = pocket.x+offset.x, y = pocket.y+offset.y},
				Tile{kind = .Wall},
			))
		}
		report = validate_generated_room(&level, config)
		testing.expect_value(t, report.error, Room_Validation_Error.Disconnected_Walkable_Area)
	}

	sparse_config := config
	sparse_config.min_walkable_percent = 100
	sparse, sparse_error := generate_room(sparse_config, 321)
	testing.expect_value(t, sparse_error, Room_Generation_Error.None)
	defer destroy(&sparse)
	sparse_report := validate_generated_room(&sparse, sparse_config)
	testing.expect_value(t, sparse_report.error, Room_Validation_Error.None)
	wall_position: grid.Position
	wall_found := false
	for y in 2..<sparse_config.height-2 {
		for x in 2..<sparse_config.width-2 {
			candidate := grid.Position{x = x, y = y}
			spawn_distance := max(abs(candidate.x-sparse.player_spawn.x), abs(candidate.y-sparse.player_spawn.y))
			exit_distance := max(
				abs(candidate.x-sparse_report.exit_position.x),
				abs(candidate.y-sparse_report.exit_position.y),
			)
			if spawn_distance > 2 && exit_distance > 2 {
				wall_position = candidate
				wall_found = true
				break
			}
		}
		if wall_found {
			break
		}
	}
	testing.expect(t, wall_found)
	if wall_found {
		assert(set_tile(&sparse, wall_position, Tile{kind = .Wall}))
		sparse_report = validate_generated_room(&sparse, sparse_config)
		testing.expect_value(t, sparse_report.error, Room_Validation_Error.Too_Few_Walkable_Cells)
	}
}
