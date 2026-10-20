package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

create_enemy_archetype_test_level :: proc(t: ^testing.T) -> level.Level {
	rows := [?]string{
		"##########",
		"#@.......#",
		"#........#",
		"#.......>#",
		"#........#",
		"##########",
	}
	result, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	return result
}

enemy_archetype_test_event_index :: proc(
	log: ^Event_Log,
	kind: Game_Event_Kind,
	source, target: Entity_Ref,
) -> (int, bool) {
	if log == nil {
		return 0, false
	}
	for index in 0..<log.count {
		event := log.events[index]
		if event.kind == kind && event.source == source && event.target == target {
			return index, true
		}
	}
	return 0, false
}

@(test)
test_archer_attacks_at_both_range_limits :: proc(t: ^testing.T) {
	level_data := create_enemy_archetype_test_level(t)
	defer level.destroy(&level_data)

	range_limit_xs := [?]int{3, 6}
	for x in range_limit_xs {
		player := create_test_player(t)
		enemies := [?]Enemy_Spawn{{
			position = {x = x, y = 1},
			health = 6,
			attack = 2,
			archetype = .Archer,
		}}
		room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
		testing.expect(t, ok)

		intent := room.enemies[0].intent
		testing.expect_value(t, intent.kind, Enemy_Intent_Kind.Attack)
		testing.expect_value(t, intent.origin, grid.Position{x = x, y = 1})
		testing.expect_value(t, intent.threatened_cell_count, 1)
		testing.expect_value(t, intent.threatened_cells[0], player.position)
		testing.expect_value(t, intent.damage, i32(2))
		testing.expect(t, validate_enemy_intent(&room, &room.enemies[0]))

		destroy_room(&room)
	}
}

@(test)
test_archer_beyond_maximum_range_advances :: proc(t: ^testing.T) {
	level_data := create_enemy_archetype_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{
		position = {x = 7, y = 1},
		health = 6,
		attack = 2,
		archetype = .Archer,
	}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	intent := room.enemies[0].intent
	testing.expect_value(t, intent.kind, Enemy_Intent_Kind.Move)
	testing.expect_value(t, intent.destination, grid.Position{x = 6, y = 1})
}

@(test)
test_archer_does_not_shoot_through_an_obstacle :: proc(t: ^testing.T) {
	level_data := create_enemy_archetype_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{
		position = {x = 6, y = 1},
		health = 6,
		attack = 2,
		archetype = .Archer,
	}}
	obstacles := [?]grid.Position{{x = 4, y = 1}}
	room, ok := create_room(&level_data, &player, {
		enemies = enemies[:],
		obstacles = obstacles[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)

	intent := room.enemies[0].intent
	testing.expect_value(t, intent.kind, Enemy_Intent_Kind.Move)
	testing.expect_value(t, intent.destination, grid.Position{x = 6, y = 2})
}

@(test)
test_adjacent_archer_retreats_when_possible_and_attacks_when_trapped :: proc(t: ^testing.T) {
	level_data := create_enemy_archetype_test_level(t)
	defer level.destroy(&level_data)
	enemies := [?]Enemy_Spawn{{
		position = {x = 2, y = 1},
		health = 6,
		attack = 2,
		archetype = .Archer,
	}}

	player := create_test_player(t)
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Move)
	testing.expect_value(t, room.enemies[0].intent.destination, grid.Position{x = 3, y = 1})
	destroy_room(&room)

	player = create_test_player(t)
	obstacles := [?]grid.Position{{x = 3, y = 1}, {x = 2, y = 2}}
	room, ok = create_room(&level_data, &player, {
		enemies = enemies[:],
		obstacles = obstacles[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Attack)
	testing.expect_value(t, room.enemies[0].intent.threatened_cells[0], player.position)
}

@(test)
test_player_can_dodge_archer_committed_target :: proc(t: ^testing.T) {
	level_data := create_enemy_archetype_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{
		position = {x = 3, y = 1},
		health = 6,
		attack = 3,
		archetype = .Archer,
	}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	enemy_id := room.enemies[0].id
	health_before := player.health

	advance_combat_pulse(&room) // Complete the aim before evading the committed shot.
	result := try_move_player(&room, .South)
	pulse := advance_combat_pulse(&room)
	room.recent_events^ = pulse.events

	testing.expect_value(t, result, Action_Result.Moved)
	testing.expect_value(t, player.health, health_before)
	miss_index, found := enemy_archetype_test_event_index(
		room.recent_events,
		.Attack_Missed,
		enemy_entity(enemy_id),
		PLAYER_ENTITY,
	)
	testing.expect(t, found)
	if found {
		testing.expect_value(t, room.recent_events.events[miss_index].to_position, grid.Position{x = 1, y = 1})
	}
}

@(test)
test_brute_charges_at_minimum_range :: proc(t: ^testing.T) {
	level_data := create_enemy_archetype_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{
		position = {x = 3, y = 1},
		health = 10,
		attack = 2,
		archetype = .Brute,
	}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	intent := room.enemies[0].intent
	testing.expect_value(t, intent.kind, Enemy_Intent_Kind.Charge)
	testing.expect_value(t, intent.path_count, 1)
	testing.expect_value(t, intent.path[0], grid.Position{x = 2, y = 1})
	testing.expect_value(t, intent.destination, intent.path[0])
	testing.expect_value(t, intent.threatened_cells[0], player.position)
}

@(test)
test_brute_plans_charge_path_destination_threat_and_damage :: proc(t: ^testing.T) {
	level_data := create_enemy_archetype_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{
		position = {x = 5, y = 1},
		health = 10,
		attack = 2,
		archetype = .Brute,
	}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	intent := room.enemies[0].intent
	testing.expect_value(t, intent.kind, Enemy_Intent_Kind.Charge)
	testing.expect_value(t, intent.path_count, 3)
	testing.expect_value(t, intent.path[0], grid.Position{x = 4, y = 1})
	testing.expect_value(t, intent.path[1], grid.Position{x = 3, y = 1})
	testing.expect_value(t, intent.path[2], grid.Position{x = 2, y = 1})
	testing.expect_value(t, intent.destination, grid.Position{x = 2, y = 1})
	testing.expect_value(t, intent.threatened_cell_count, 1)
	testing.expect_value(t, intent.threatened_cells[0], grid.Position{x = 1, y = 1})
	testing.expect_value(t, intent.damage, i32(4))
	testing.expect(t, validate_enemy_intent(&room, &room.enemies[0]))
}

@(test)
test_obstacle_or_enemy_in_corridor_prevents_brute_charge :: proc(t: ^testing.T) {
	level_data := create_enemy_archetype_test_level(t)
	defer level.destroy(&level_data)
	brute := Enemy_Spawn{
		position = {x = 5, y = 1},
		health = 10,
		attack = 2,
		archetype = .Brute,
	}

	player := create_test_player(t)
	obstacles := [?]grid.Position{{x = 3, y = 1}}
	room, ok := create_room(&level_data, &player, {
		enemies = []Enemy_Spawn{brute},
		obstacles = obstacles[:],
	})
	testing.expect(t, ok)
	testing.expect(t, room.enemies[0].intent.kind != .Charge)
	destroy_room(&room)

	player = create_test_player(t)
	enemies := [?]Enemy_Spawn{
		brute,
		{position = {x = 3, y = 1}, health = 6, attack = 1},
	}
	room, ok = create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	testing.expect(t, room.enemies[0].intent.kind != .Charge)
}

@(test)
test_brute_charge_hits_after_moving :: proc(t: ^testing.T) {
	level_data := create_enemy_archetype_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{
		position = {x = 5, y = 1},
		health = 10,
		attack = 2,
		archetype = .Brute,
	}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	enemy_id := room.enemies[0].id

	pulse := advance_combat_pulse(&room)
	room.recent_events^ = pulse.events

	testing.expect(t, pulse.advanced)
	testing.expect_value(t, room.enemies[0].position, grid.Position{x = 2, y = 1})
	testing.expect_value(t, player.health, i32(7))
	moved_index, moved := enemy_archetype_test_event_index(
		room.recent_events,
		.Moved,
		enemy_entity(enemy_id),
		enemy_entity(enemy_id),
	)
	damaged_index, damaged := enemy_archetype_test_event_index(
		room.recent_events,
		.Damaged,
		enemy_entity(enemy_id),
		PLAYER_ENTITY,
	)
	testing.expect(t, moved)
	testing.expect(t, damaged)
	if moved && damaged {
		testing.expect(t, moved_index < damaged_index)
		testing.expect_value(t, room.recent_events.events[damaged_index].amount, i32(3))
	}
}

@(test)
test_dodged_brute_charge_moves_then_misses :: proc(t: ^testing.T) {
	level_data := create_enemy_archetype_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{
		position = {x = 5, y = 1},
		health = 10,
		attack = 2,
		archetype = .Brute,
	}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	enemy_id := room.enemies[0].id
	health_before := player.health

	result := try_move_player(&room, .South)
	pulse := advance_combat_pulse(&room)
	room.recent_events^ = pulse.events

	testing.expect_value(t, result, Action_Result.Moved)
	testing.expect_value(t, room.enemies[0].position, grid.Position{x = 2, y = 1})
	testing.expect_value(t, player.health, health_before)
	moved_index, moved := enemy_archetype_test_event_index(
		room.recent_events,
		.Moved,
		enemy_entity(enemy_id),
		enemy_entity(enemy_id),
	)
	miss_index, missed := enemy_archetype_test_event_index(
		room.recent_events,
		.Attack_Missed,
		enemy_entity(enemy_id),
		PLAYER_ENTITY,
	)
	testing.expect(t, moved)
	testing.expect(t, missed)
	if moved && missed {
		testing.expect(t, moved_index < miss_index)
	}
}

@(test)
test_player_entering_charge_path_blocks_the_whole_charge :: proc(t: ^testing.T) {
	level_data := create_enemy_archetype_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{
		position = {x = 5, y = 1},
		health = 10,
		attack = 2,
		archetype = .Brute,
	}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	enemy_id := room.enemies[0].id
	health_before := player.health

	result := try_move_player(&room, .East)
	pulse := advance_combat_pulse(&room)
	room.recent_events^ = pulse.events

	testing.expect_value(t, result, Action_Result.Moved)
	testing.expect_value(t, player.position, grid.Position{x = 2, y = 1})
	testing.expect_value(t, room.enemies[0].position, grid.Position{x = 5, y = 1})
	testing.expect_value(t, player.health, health_before)
	_, blocked := enemy_archetype_test_event_index(
		room.recent_events,
		.Move_Blocked,
		enemy_entity(enemy_id),
		enemy_entity(enemy_id),
	)
	testing.expect(t, blocked)
	_, damaged := enemy_archetype_test_event_index(
		room.recent_events,
		.Damaged,
		enemy_entity(enemy_id),
		PLAYER_ENTITY,
	)
	testing.expect(t, !damaged)
}

@(test)
test_charge_validator_rejects_inconsistent_geometry :: proc(t: ^testing.T) {
	level_data := create_enemy_archetype_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{
		position = {x = 5, y = 1},
		health = 10,
		attack = 2,
		archetype = .Brute,
	}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	original := room.enemies[0].intent
	testing.expect(t, validate_enemy_intent(&room, &room.enemies[0]))

	room.enemies[0].intent.destination = {x = 3, y = 1}
	testing.expect(t, !validate_enemy_intent(&room, &room.enemies[0]))

	room.enemies[0].intent = original
	room.enemies[0].intent.path[1] = {x = 4, y = 2}
	testing.expect(t, !validate_enemy_intent(&room, &room.enemies[0]))

	room.enemies[0].intent = original
	room.enemies[0].intent.path[1] = room.enemies[0].intent.path[0]
	testing.expect(t, !validate_enemy_intent(&room, &room.enemies[0]))

	room.enemies[0].intent = original
	room.enemies[0].intent.threatened_cells[0] = {x = -1, y = 1}
	testing.expect(t, !validate_enemy_intent(&room, &room.enemies[0]))
}

@(test)
test_room_rejects_count_enemy_archetype :: proc(t: ^testing.T) {
	level_data := create_enemy_archetype_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	player_before := player
	enemies := [?]Enemy_Spawn{{
		position = {x = 3, y = 1},
		health = 6,
		attack = 2,
		archetype = .Count,
	}}

	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, !ok)
	testing.expect_value(t, player, player_before)
	destroy_room(&room)
}
