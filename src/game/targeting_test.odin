package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

create_targeting_test_level :: proc(t: ^testing.T) -> level.Level {
	rows := [?]string{
		"#########",
		"#@......#",
		"#.......#",
		"#.......#",
		"#.......#",
		"#.......#",
		"#.......#",
		"#......>#",
		"#########",
	}
	result, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	return result
}

create_targeting_clip_test_level :: proc(t: ^testing.T) -> level.Level {
	rows := [?]string{
		"@...>",
		".....",
		".....",
		".....",
	}
	result, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	return result
}

expect_targeting_cells :: proc(
	t: ^testing.T,
	set: ^Target_Cell_Set,
	expected: []grid.Position,
) {
	testing.expect(t, set != nil)
	if set == nil {
		return
	}
	testing.expect_value(t, set.count, len(expected))
	for position, index in expected {
		if index >= set.count {
			break
		}
		testing.expect_value(t, set.cells[index], position)
	}
}

@(test)
test_targeting_single_resolves_primary_target_and_affected_enemy :: proc(t: ^testing.T) {
	level_data := create_targeting_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 3, y = 1}, health = 6, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	enemy_id := room.enemies[0].id
	spec := Targeting_Spec{
		rule = .Opponent,
		cast_range = {.Chebyshev, 1, 4},
		shape = .Single,
	}

	result := evaluate_target_query(&room, PLAYER_ENTITY, spec, {
		anchor = room.enemies[0].position,
		has_anchor = true,
	})

	testing.expect_value(t, result.error, Target_Query_Error.None)
	testing.expect(t, result.anchor_reachable)
	testing.expect(t, result.has_primary_target)
	testing.expect_value(t, result.primary_target, entity_target(enemy_entity(enemy_id)))
	expected := [?]grid.Position{{x = 3, y = 1}}
	expect_targeting_cells(t, &result.affected, expected[:])
	testing.expect_value(t, result.enemy_count, 1)
	testing.expect_value(t, result.enemy_ids[0], enemy_id)
}

@(test)
test_targeting_line_supports_all_eight_directions_and_rejects_other_slopes :: proc(t: ^testing.T) {
	level_data := create_targeting_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 4, y = 4}, health = 6, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	source := enemy_entity(room.enemies[0].id)
	origin := room.enemies[0].position
	spec := Targeting_Spec{
		rule = .Cell,
		cast_range = {.Chebyshev, 1, 3},
		shape = .Line,
	}
	directions := [?]grid.Position{
		{x = 0, y = -1},
		{x = 1, y = -1},
		{x = 1, y = 0},
		{x = 1, y = 1},
		{x = 0, y = 1},
		{x = -1, y = 1},
		{x = -1, y = 0},
		{x = -1, y = -1},
	}

	for direction in directions {
		midpoint := grid.Position{x = origin.x+direction.x, y = origin.y+direction.y}
		anchor := grid.Position{x = origin.x+direction.x*2, y = origin.y+direction.y*2}
		result := evaluate_target_query(&room, source, spec, {
			anchor = anchor,
			has_anchor = true,
		})

		testing.expect_value(t, result.error, Target_Query_Error.None)
		testing.expect_value(t, result.path_count, 2)
		testing.expect_value(t, result.path[0], midpoint)
		testing.expect_value(t, result.path[1], anchor)
		expected := [?]grid.Position{midpoint, anchor}
		expect_targeting_cells(t, &result.affected, expected[:])
	}

	non_aligned := evaluate_target_query(&room, source, spec, {
		anchor = {x = origin.x+2, y = origin.y+1},
		has_anchor = true,
	})
	testing.expect_value(t, non_aligned.error, Target_Query_Error.Shape_Not_Aligned)
	testing.expect_value(t, non_aligned.path_count, 0)
	testing.expect_value(t, non_aligned.affected.count, 0)
}

@(test)
test_targeting_cast_range_includes_origin_and_exact_minimum_and_maximum :: proc(t: ^testing.T) {
	level_data := create_targeting_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	room, ok := create_room(&level_data, &player, {})
	testing.expect(t, ok)
	defer destroy_room(&room)
	Case :: struct {
		range: Targeting_Range,
		anchor: grid.Position,
		error: Target_Query_Error,
		path_count: int,
	}
	cases := [?]Case{
		{range = {.Manhattan, 0, 2}, anchor = {1, 1}, error = .None},
		{range = {.Manhattan, 2, 4}, anchor = {3, 1}, error = .None, path_count = 2},
		{range = {.Manhattan, 2, 4}, anchor = {5, 1}, error = .None, path_count = 4},
		{range = {.Manhattan, 2, 4}, anchor = {2, 1}, error = .Anchor_Out_Of_Range},
		{range = {.Manhattan, 2, 4}, anchor = {6, 1}, error = .Anchor_Out_Of_Range},
	}
	for c in cases {
		spec := Targeting_Spec{rule = .Cell, cast_range = c.range, shape = .Single}
		result := evaluate_target_query(&room, PLAYER_ENTITY, spec, {anchor = c.anchor, has_anchor = true})
		testing.expect_value(t, result.error, c.error)
		testing.expect_value(t, targeting_range_contains(c.range, player.position, c.anchor), c.error == .None)
		if c.error == .None {
			testing.expect_value(t, result.path_count, c.path_count)
			expected := [?]grid.Position{c.anchor}
			expect_targeting_cells(t, &result.affected, expected[:])
		} else {
			testing.expect_value(t, result.affected.count, 0)
		}
	}
}

@(test)
test_targeting_cross_builds_center_and_arms :: proc(t: ^testing.T) {
	level_data := create_targeting_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	room, ok := create_room(&level_data, &player, {})
	testing.expect(t, ok)
	defer destroy_room(&room)
	spec := Targeting_Spec{
		rule = .Cell,
		cast_range = {.Chebyshev, 1, 6},
		shape = .Cross,
		radius = 2,
	}

	result := evaluate_target_query(&room, PLAYER_ENTITY, spec, {
		anchor = {x = 4, y = 4},
		has_anchor = true,
	})

	testing.expect_value(t, result.error, Target_Query_Error.None)
	expected := [?]grid.Position{
		{x = 4, y = 2},
		{x = 4, y = 3},
		{x = 2, y = 4},
		{x = 3, y = 4},
		{x = 4, y = 4},
		{x = 5, y = 4},
		{x = 6, y = 4},
		{x = 4, y = 5},
		{x = 4, y = 6},
	}
	expect_targeting_cells(t, &result.affected, expected[:])
}

@(test)
test_targeting_cross_clips_at_bounds_and_stops_a_blocked_branch :: proc(t: ^testing.T) {
	clip_level := create_targeting_clip_test_level(t)
	player := create_test_player(t)
	clip_room, clip_ok := create_room(&clip_level, &player, {})
	testing.expect(t, clip_ok)
	clip_spec := Targeting_Spec{
		rule = .Cell,
		cast_range = {.Chebyshev, 1, 4},
		shape = .Cross,
		radius = 2,
	}
	clipped := evaluate_target_query(&clip_room, PLAYER_ENTITY, clip_spec, {
		anchor = {x = 0, y = 2},
		has_anchor = true,
	})
	testing.expect_value(t, clipped.error, Target_Query_Error.None)
	clipped_expected := [?]grid.Position{
		{x = 0, y = 0},
		{x = 0, y = 1},
		{x = 0, y = 2},
		{x = 1, y = 2},
		{x = 2, y = 2},
		{x = 0, y = 3},
	}
	expect_targeting_cells(t, &clipped.affected, clipped_expected[:])
	destroy_room(&clip_room)
	level.destroy(&clip_level)

	level_data := create_targeting_test_level(t)
	defer level.destroy(&level_data)
	player = create_test_player(t)
	obstacles := [?]grid.Position{{x = 5, y = 4}}
	room, ok := create_room(&level_data, &player, {obstacles = obstacles[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	blocked_spec := Targeting_Spec{
		rule = .Cell,
		cast_range = {.Chebyshev, 1, 6},
		shape = .Cross,
		radius = 2,
		stops_on_wall = true,
	}
	blocked := evaluate_target_query(&room, PLAYER_ENTITY, blocked_spec, {
		anchor = {x = 4, y = 4},
		has_anchor = true,
	})

	testing.expect_value(t, blocked.error, Target_Query_Error.None)
	testing.expect_value(t, blocked.affected.count, 7)
	testing.expect(t, !target_cell_set_contains(&blocked.affected, {x = 5, y = 4}))
	testing.expect(t, !target_cell_set_contains(&blocked.affected, {x = 6, y = 4}))
	testing.expect(t, target_cell_set_contains(&blocked.affected, {x = 2, y = 4}))
}

@(test)
test_targeting_square_builds_three_by_three_and_clips_at_bounds :: proc(t: ^testing.T) {
	level_data := create_targeting_test_level(t)
	player := create_test_player(t)
	room, ok := create_room(&level_data, &player, {})
	testing.expect(t, ok)
	spec := Targeting_Spec{
		rule = .Cell,
		cast_range = {.Chebyshev, 1, 6},
		shape = .Square,
		radius = 1,
	}
	centered := evaluate_target_query(&room, PLAYER_ENTITY, spec, {
		anchor = {x = 4, y = 4},
		has_anchor = true,
	})
	testing.expect_value(t, centered.error, Target_Query_Error.None)
	centered_expected := [?]grid.Position{
		{x = 3, y = 3}, {x = 4, y = 3}, {x = 5, y = 3},
		{x = 3, y = 4}, {x = 4, y = 4}, {x = 5, y = 4},
		{x = 3, y = 5}, {x = 4, y = 5}, {x = 5, y = 5},
	}
	expect_targeting_cells(t, &centered.affected, centered_expected[:])
	destroy_room(&room)
	level.destroy(&level_data)

	clip_level := create_targeting_clip_test_level(t)
	defer level.destroy(&clip_level)
	player = create_test_player(t)
	clip_room, clip_ok := create_room(&clip_level, &player, {})
	testing.expect(t, clip_ok)
	defer destroy_room(&clip_room)
	clip_spec := Targeting_Spec{
		rule = .Cell,
		cast_range = {.Chebyshev, 1, 4},
		shape = .Square,
		radius = 1,
	}
	clipped := evaluate_target_query(&clip_room, PLAYER_ENTITY, clip_spec, {
		anchor = {x = 0, y = 2},
		has_anchor = true,
	})
	testing.expect_value(t, clipped.error, Target_Query_Error.None)
	clipped_expected := [?]grid.Position{
		{x = 0, y = 1}, {x = 1, y = 1},
		{x = 0, y = 2}, {x = 1, y = 2},
		{x = 0, y = 3}, {x = 1, y = 3},
	}
	expect_targeting_cells(t, &clipped.affected, clipped_expected[:])
}

@(test)
test_targeting_line_of_sight_is_blocked_by_wall_and_obstacle :: proc(t: ^testing.T) {
	spec := Targeting_Spec{
		rule = .Cell,
		cast_range = {.Chebyshev, 1, 6},
		shape = .Single,
		requires_line_of_sight = true,
	}

	wall_level := create_targeting_test_level(t)
	testing.expect(t, level.set_tile(&wall_level, {x = 3, y = 1}, {kind = .Wall}))
	player := create_test_player(t)
	wall_room, wall_ok := create_room(&wall_level, &player, {})
	testing.expect(t, wall_ok)
	wall_result := evaluate_target_query(&wall_room, PLAYER_ENTITY, spec, {
		anchor = {x = 5, y = 1},
		has_anchor = true,
	})
	testing.expect_value(t, wall_result.error, Target_Query_Error.Line_Of_Sight_Blocked)
	testing.expect(t, wall_result.has_blocker)
	testing.expect_value(t, wall_result.blocker, grid.Position{x = 3, y = 1})
	destroy_room(&wall_room)
	level.destroy(&wall_level)

	obstacle_level := create_targeting_test_level(t)
	defer level.destroy(&obstacle_level)
	player = create_test_player(t)
	obstacles := [?]grid.Position{{x = 3, y = 1}}
	obstacle_room, obstacle_ok := create_room(&obstacle_level, &player, {
		obstacles = obstacles[:],
	})
	testing.expect(t, obstacle_ok)
	defer destroy_room(&obstacle_room)
	obstacle_result := evaluate_target_query(&obstacle_room, PLAYER_ENTITY, spec, {
		anchor = {x = 5, y = 1},
		has_anchor = true,
	})
	testing.expect_value(t, obstacle_result.error, Target_Query_Error.Line_Of_Sight_Blocked)
	testing.expect(t, obstacle_result.has_blocker)
	testing.expect_value(t, obstacle_result.blocker, grid.Position{x = 3, y = 1})
}

@(test)
test_targeting_line_of_sight_rejects_diagonal_corner_squeeze :: proc(t: ^testing.T) {
	level_data := create_targeting_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	obstacles := [?]grid.Position{{x = 2, y = 1}, {x = 1, y = 2}}
	room, ok := create_room(&level_data, &player, {obstacles = obstacles[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	spec := Targeting_Spec{
		rule = .Cell,
		cast_range = {.Chebyshev, 1, 3},
		shape = .Single,
		requires_line_of_sight = true,
	}

	result := evaluate_target_query(&room, PLAYER_ENTITY, spec, {
		anchor = {x = 2, y = 2},
		has_anchor = true,
	})

	testing.expect_value(t, result.error, Target_Query_Error.Line_Of_Sight_Blocked)
	testing.expect(t, result.has_blocker)
	testing.expect_value(t, result.blocker, grid.Position{x = 2, y = 1})
}

@(test)
test_targeting_actors_are_transparent_unless_line_stops_on_actor :: proc(t: ^testing.T) {
	level_data := create_targeting_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{
		{position = {x = 3, y = 1}, health = 6, attack = 1},
		{position = {x = 5, y = 1}, health = 6, attack = 1},
	}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	spec := Targeting_Spec{
		rule = .Cell,
		cast_range = {.Chebyshev, 1, 6},
		shape = .Line,
		requires_line_of_sight = true,
	}
	request := Target_Request{anchor = {x = 7, y = 1}, has_anchor = true}

	transparent := evaluate_target_query(&room, PLAYER_ENTITY, spec, request)
	testing.expect_value(t, transparent.error, Target_Query_Error.None)
	testing.expect_value(t, transparent.affected.count, 6)
	testing.expect_value(t, transparent.enemy_count, 2)
	testing.expect_value(t, transparent.enemy_ids[0], room.enemies[0].id)
	testing.expect_value(t, transparent.enemy_ids[1], room.enemies[1].id)

	spec.stops_on_actor = true
	stopped := evaluate_target_query(&room, PLAYER_ENTITY, spec, request)
	testing.expect_value(t, stopped.error, Target_Query_Error.None)
	stopped_expected := [?]grid.Position{{x = 2, y = 1}, {x = 3, y = 1}}
	expect_targeting_cells(t, &stopped.affected, stopped_expected[:])
	testing.expect_value(t, stopped.enemy_count, 1)
	testing.expect_value(t, stopped.enemy_ids[0], room.enemies[0].id)
}

@(test)
test_targeting_collects_affected_enemy_ids_in_stable_id_order :: proc(t: ^testing.T) {
	level_data := create_targeting_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{
		{position = {x = 5, y = 5}, health = 6, attack = 1},
		{position = {x = 3, y = 3}, health = 6, attack = 1},
		{position = {x = 4, y = 5}, health = 6, attack = 1},
	}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	first_id := room.enemies[0].id
	second_id := room.enemies[1].id
	third_id := room.enemies[2].id
	room.enemies[0], room.enemies[2] = room.enemies[2], room.enemies[0]
	testing.expect_value(t, room.enemies[0].id, third_id)
	spec := Targeting_Spec{
		rule = .Cell,
		cast_range = {.Chebyshev, 1, 6},
		shape = .Square,
		radius = 2,
	}

	result := evaluate_target_query(&room, PLAYER_ENTITY, spec, {
		anchor = {x = 4, y = 4},
		has_anchor = true,
	})

	testing.expect_value(t, result.error, Target_Query_Error.None)
	testing.expect_value(t, result.enemy_count, 3)
	testing.expect_value(t, result.enemy_ids[0], first_id)
	testing.expect_value(t, result.enemy_ids[1], second_id)
	testing.expect_value(t, result.enemy_ids[2], third_id)
}

@(test)
test_target_query_is_deterministic_and_does_not_mutate_room :: proc(t: ^testing.T) {
	level_data := create_targeting_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{
		{position = {x = 3, y = 3}, health = 6, attack = 1},
		{position = {x = 5, y = 4}, health = 6, attack = 1},
	}
	obstacles := [?]grid.Position{{x = 6, y = 4}}
	room, ok := create_room(&level_data, &player, {
		enemies = enemies[:],
		obstacles = obstacles[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)
	player_before := player
	enemies_before: [MAX_ENEMIES_PER_ROOM]Enemy
	for enemy, index in room.enemies {
		enemies_before[index] = enemy
	}
	phase_before := room.phase
	pulse_before := room.pulse_count
	events_before := room.recent_events^
	spec := Targeting_Spec{
		rule = .Cell,
		cast_range = {.Chebyshev, 1, 6},
		shape = .Cross,
		radius = 2,
	}
	request := Target_Request{anchor = {x = 4, y = 4}, has_anchor = true}

	first := evaluate_target_query(&room, PLAYER_ENTITY, spec, request)
	second := evaluate_target_query(&room, PLAYER_ENTITY, spec, request)

	testing.expect_value(t, first, second)
	testing.expect_value(t, player, player_before)
	testing.expect_value(t, room.phase, phase_before)
	testing.expect_value(t, room.pulse_count, pulse_before)
	testing.expect_value(t, room.recent_events^, events_before)
	testing.expect_value(t, len(room.enemies), len(enemies))
	for enemy, index in room.enemies {
		testing.expect_value(t, enemy, enemies_before[index])
	}
	testing.expect_value(t, len(room.obstacles), len(obstacles))
	testing.expect_value(t, room.obstacles[0].position, obstacles[0])
}
