package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

create_enemy_intent_reservation_level :: proc(t: ^testing.T) -> level.Level {
	rows := [?]string{
		"#########",
		"#@......#",
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

enemy_intent_test_event :: proc(
	log: ^Event_Log,
	kind: Game_Event_Kind,
) -> (Game_Event, bool) {
	if log == nil {
		return {}, false
	}
	for index in 0..<log.count {
		if log.events[index].kind == kind {
			return log.events[index], true
		}
	}
	return {}, false
}

@(test)
test_room_creation_plans_initial_attack_and_move_intents :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{
		{position = {x = 2, y = 1}, health = 6, attack = 3},
		{position = {x = 5, y = 3}, health = 6, attack = 2},
	}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	testing.expect(t, validate_enemy_intents(&room))
	attack := room.enemies[0].intent
	testing.expect_value(t, attack.kind, Enemy_Intent_Kind.Attack)
	testing.expect_value(t, attack.origin, grid.Position{x = 2, y = 1})
	testing.expect_value(t, attack.destination, attack.origin)
	testing.expect_value(t, attack.damage, i32(3))
	testing.expect_value(t, attack.threatened_cell_count, 1)
	testing.expect_value(t, attack.threatened_cells[0], player.position)
	testing.expect_value(t, attack.planned_pulse, u64(1))

	move := room.enemies[1].intent
	testing.expect_value(t, move.kind, Enemy_Intent_Kind.Move)
	testing.expect_value(t, move.origin, grid.Position{x = 5, y = 3})
	testing.expect_value(t, move.destination, grid.Position{x = 4, y = 3})
	testing.expect_value(t, move.path_count, 1)
	testing.expect_value(t, move.path[0], move.destination)
	testing.expect_value(t, move.planned_pulse, u64(1))
}

@(test)
test_move_intent_prefers_dominant_axis_and_falls_back_around_obstacle :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)

	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 4, y = 3}, health = 6, attack = 2}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	testing.expect_value(t, room.enemies[0].intent.destination, grid.Position{x = 3, y = 3})
	destroy_room(&room)

	player = create_test_player(t)
	obstacles := [?]grid.Position{{x = 3, y = 3}}
	room, ok = create_room(&level_data, &player, {
		enemies = enemies[:],
		obstacles = obstacles[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Move)
	testing.expect_value(t, room.enemies[0].intent.destination, grid.Position{x = 4, y = 2})
}

@(test)
test_move_intent_reservations_prevent_destination_collisions :: proc(t: ^testing.T) {
	level_data := create_enemy_intent_reservation_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{
		{position = {x = 4, y = 3}, health = 6, attack = 2},
		{position = {x = 3, y = 4}, health = 6, attack = 2},
	}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	first := room.enemies[0].intent
	second := room.enemies[1].intent
	testing.expect_value(t, first.kind, Enemy_Intent_Kind.Move)
	testing.expect_value(t, first.destination, grid.Position{x = 3, y = 3})
	testing.expect_value(t, second.kind, Enemy_Intent_Kind.Move)
	testing.expect_value(t, second.destination, grid.Position{x = 2, y = 4})
	testing.expect(t, first.destination != second.destination)
}

@(test)
test_player_can_evade_a_telegraphed_attack :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 6, attack = 3}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	enemy_id := room.enemies[0].id
	health_before := player.health

	result := try_move_player(&room, .South)
	pulse := advance_combat_pulse(&room)
	room.recent_events^ = pulse.events

	testing.expect_value(t, result, Action_Result.Moved)
	testing.expect_value(t, player.health, health_before)
	testing.expect_value(t, room.pulse_count, u64(1))
	miss, found := enemy_intent_test_event(room.recent_events, .Attack_Missed)
	testing.expect(t, found)
	testing.expect_value(t, miss.source, enemy_entity(enemy_id))
	testing.expect_value(t, miss.target, PLAYER_ENTITY)
	testing.expect_value(t, miss.from_position, grid.Position{x = 2, y = 1})
	testing.expect_value(t, miss.to_position, grid.Position{x = 1, y = 1})
}

@(test)
test_move_intent_reports_block_when_player_occupies_its_destination :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 3, y = 1}, health = 6, attack = 2}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	enemy_id := room.enemies[0].id
	testing.expect_value(t, room.enemies[0].intent.destination, grid.Position{x = 2, y = 1})

	result := try_move_player(&room, .East)
	pulse := advance_combat_pulse(&room)
	room.recent_events^ = pulse.events

	testing.expect_value(t, result, Action_Result.Moved)
	testing.expect_value(t, player.position, grid.Position{x = 2, y = 1})
	testing.expect_value(t, room.enemies[0].position, grid.Position{x = 3, y = 1})
	blocked, found := enemy_intent_test_event(room.recent_events, .Move_Blocked)
	testing.expect(t, found)
	testing.expect_value(t, blocked.source, enemy_entity(enemy_id))
	testing.expect_value(t, blocked.target, enemy_entity(enemy_id))
	testing.expect_value(t, blocked.from_position, grid.Position{x = 3, y = 1})
	testing.expect_value(t, blocked.to_position, grid.Position{x = 2, y = 1})
}

@(test)
test_invalid_player_action_does_not_consume_or_replan_intent :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 3, y = 1}, health = 6, attack = 2}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	intent_before := room.enemies[0].intent

	result := try_move_player(&room, .West)

	testing.expect_value(t, result, Action_Result.Blocked)
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect_value(t, room.enemies[0].intent, intent_before)
	testing.expect_value(t, room.recent_events.count, 0)
}

@(test)
test_enemy_deaths_during_resolution_preserve_snapshot_id_order :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{
		{position = {x = 2, y = 1}, health = 1, attack = 2},
		{position = {x = 1, y = 2}, health = 1, attack = 2},
	}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	first_id := room.enemies[0].id
	second_id := room.enemies[1].id
	apply_status(&room, PLAYER_ENTITY, .Thorns, 1, 3)

	pulse := advance_combat_pulse(&room)
	room.recent_events^ = pulse.events

	testing.expect(t, pulse.combat_ended)
	testing.expect_value(t, room.phase, Room_Phase.Loot)
	testing.expect_value(t, len(room.enemies), 0)
	testing.expect_value(t, player.health, i32(8))
	testing.expect_value(t, room.pulse_count, u64(1))
	damage_sources: [2]Entity_Ref
	damage_count := 0
	for index in 0..<room.recent_events.count {
		event := room.recent_events.events[index]
		if event.kind == .Damaged && event.target == PLAYER_ENTITY {
			damage_sources[damage_count] = event.source
			damage_count += 1
		}
	}
	testing.expect_value(t, damage_count, 2)
	testing.expect_value(t, damage_sources[0], enemy_entity(first_id))
	testing.expect_value(t, damage_sources[1], enemy_entity(second_id))
}

@(test)
test_enemy_intents_replan_for_the_next_pulse :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 6, attack = 2}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	testing.expect_value(t, room.enemies[0].intent.planned_pulse, u64(1))

	first_pulse := advance_combat_pulse(&room)
	testing.expect(t, first_pulse.advanced)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect_value(t, room.enemies[0].position, grid.Position{x = 4, y = 3})
	testing.expect_value(t, room.enemies[0].intent.origin, room.enemies[0].position)
	testing.expect_value(t, room.enemies[0].intent.destination, grid.Position{x = 3, y = 3})
	testing.expect_value(t, room.enemies[0].intent.planned_pulse, u64(2))
	testing.expect(t, validate_enemy_intents(&room))

	second_pulse := advance_combat_pulse(&room)
	testing.expect(t, second_pulse.advanced)
	testing.expect_value(t, room.pulse_count, u64(2))
	testing.expect_value(t, room.enemies[0].position, grid.Position{x = 3, y = 3})
	testing.expect_value(t, room.enemies[0].intent.planned_pulse, u64(3))
	testing.expect(t, validate_enemy_intents(&room))
}
