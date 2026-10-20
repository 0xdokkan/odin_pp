package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

create_movement_test_level :: proc(t: ^testing.T) -> level.Level {
	rows := [?]string{
		"########",
		"#@.....#",
		"#......#",
		"#.....>#",
		"########",
	}
	result, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	return result
}

movement_test_event_count :: proc(log: ^Event_Log, kind: Game_Event_Kind) -> int {
	if log == nil {
		return 0
	}
	count := 0
	for event in log.events[:log.count] {
		if event.kind == kind {
			count += 1
		}
	}
	return count
}

@(test)
test_movement_query_reports_actor_blocker_without_mutating_room :: proc(t: ^testing.T) {
	level_data := create_movement_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 4, y = 1}, health = 8, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	position_before := player.position

	query := query_entity_movement(&room, PLAYER_ENTITY, {x = 5, y = 1})

	testing.expect_value(t, query.error, Movement_Error.Actor_Blocker)
	testing.expect(t, query.has_blocker)
	testing.expect_value(t, query.blocker, grid.Position{x = 4, y = 1})
	testing.expect_value(t, query.count, 4)
	testing.expect_value(t, player.position, position_before)
}

@(test)
test_enemy_traverse_can_cross_traps_but_not_other_actors :: proc(t: ^testing.T) {
	level_data := create_movement_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{
		{position = {x = 5, y = 1}, health = 8, attack = 1},
		{position = {x = 2, y = 1}, health = 8, attack = 1},
	}
	traps := [?]Trap_Spawn{{position = {x = 4, y = 1}, damage = 2}}
	room, ok := create_room(&level_data, &player, {
		enemies = enemies[:],
		traps = traps[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)
	mover := enemy_entity(room.enemies[0].id)

	blocked := query_entity_movement(&room, mover, {x = 2, y = 1})
	testing.expect_value(t, blocked.error, Movement_Error.Actor_Blocker)
	testing.expect_value(t, blocked.blocker, grid.Position{x = 2, y = 1})

	clear := query_entity_movement(&room, mover, {x = 3, y = 1})
	testing.expect(t, movement_query_is_clear(&clear))
	testing.expect_value(t, clear.count, 2)
	testing.expect_value(t, clear.cells[0], grid.Position{x = 4, y = 1})
	testing.expect_value(t, clear.cells[1], grid.Position{x = 3, y = 1})
}

@(test)
test_diagonal_traverse_rejects_a_closed_static_corner :: proc(t: ^testing.T) {
	level_data := create_movement_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 6, y = 2}, health = 8, attack = 1}}
	obstacles := [?]grid.Position{{x = 2, y = 1}, {x = 1, y = 2}}
	room, ok := create_room(&level_data, &player, {
		enemies = enemies[:],
		obstacles = obstacles[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)

	query := query_entity_movement(&room, PLAYER_ENTITY, {x = 2, y = 2})

	testing.expect_value(t, query.error, Movement_Error.Static_Blocker)
	testing.expect(t, query.has_blocker)
}

@(test)
test_teleport_ignores_intermediate_cells_but_validates_landing :: proc(t: ^testing.T) {
	level_data := create_movement_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 6, y = 2}, health = 8, attack = 1}}
	obstacles := [?]grid.Position{{x = 2, y = 1}}
	room, ok := create_room(&level_data, &player, {
		enemies = enemies[:],
		obstacles = obstacles[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)

	traverse := query_entity_movement(&room, PLAYER_ENTITY, {x = 3, y = 1})
	testing.expect_value(t, traverse.error, Movement_Error.Static_Blocker)
	teleport := query_entity_movement(&room, PLAYER_ENTITY, {x = 3, y = 1}, .Teleport)
	testing.expect(t, movement_query_is_clear(&teleport))
	testing.expect_value(t, teleport.count, 1)
	testing.expect_value(t, teleport.cells[0], grid.Position{x = 3, y = 1})
}

@(test)
test_maximum_traverse_hazard_envelope_fits_without_event_drops :: proc(t: ^testing.T) {
	rows := [?]string{
		"################",
		"#@............>#",
		"#..............#",
		"################",
	}
	level_data, parse_error, _ := level.from_ascii(rows[:])
	testing.expect_value(t, parse_error, level.Parse_Error.None)
	defer level.destroy(&level_data)
	player, player_ok := create_player({max_health = 100, attack = 2, defense = 1})
	testing.expect(t, player_ok)
	enemies := [?]Enemy_Spawn{{position = {x = 1, y = 2}, health = 8, attack = 1}}
	traps: [MAX_MOVEMENT_PATH_CELLS]Trap_Spawn
	for index in 0..<len(traps) {
		traps[index] = {position = {x = index+2, y = 1}, damage = 2}
	}
	room, room_ok := create_room(&level_data, &player, {
		enemies = enemies[:],
		traps = traps[:],
	})
	testing.expect(t, room_ok)
	defer destroy_room(&room)
	action := make_action(.Move, PLAYER_ENTITY, cell_target({x = 13, y = 1}), .Walkable_Cell)
	testing.expect(t, add_effect(&action, move_effect(PLAYER_ENTITY, {x = 13, y = 1})))

	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	testing.expect_value(t, player.position, grid.Position{x = 13, y = 1})
	testing.expect_value(t, player.health, i32(88))
	testing.expect_value(t, movement_test_event_count(&report.events, .Movement_Step), 11)
	testing.expect_value(t, movement_test_event_count(&report.events, .Moved), 1)
	testing.expect_value(t, movement_test_event_count(&report.events, .Trap_Triggered), 12)
	testing.expect_value(t, movement_test_event_count(&report.events, .Damaged), 12)
	testing.expect_value(t, report.events.count, 36)
	testing.expect_value(t, report.events.dropped_count, 0)
}

@(test)
test_mover_death_stops_the_remaining_effects_from_its_action :: proc(t: ^testing.T) {
	level_data := create_movement_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{
		{position = {x = 2, y = 1}, health = 1, attack = 3},
		{position = {x = 6, y = 2}, health = 8, attack = 1},
	}
	traps := [?]Trap_Spawn{{position = {x = 3, y = 1}, damage = 2}}
	room, ok := create_room(&level_data, &player, {
		enemies = enemies[:],
		traps = traps[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)
	source := enemy_entity(room.enemies[0].id)
	action := make_action(.Move, source, cell_target({x = 3, y = 1}), .Walkable_Cell)
	testing.expect(t, add_effect(&action, move_effect(source, {x = 3, y = 1})))
	testing.expect(t, add_effect(&action, damage_effect(PLAYER_ENTITY, 3)))
	health_before := player.health

	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	testing.expect(t, !entity_exists(&room, source))
	testing.expect_value(t, player.health, health_before)
	testing.expect_value(t, report.applied_effects, 1)
	testing.expect_value(t, report.skipped_effects, 1)
}
