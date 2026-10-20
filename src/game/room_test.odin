package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

create_test_level :: proc(t: ^testing.T) -> level.Level {
	rows := [?]string{
		"#######",
		"#@....#",
		"#..>..#",
		"#.....#",
		"#######",
	}
	result, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	return result
}

create_test_player :: proc(t: ^testing.T) -> Player {
	result, ok := create_player({
		max_health = 10,
		attack = 2,
		defense = 1,
	})
	testing.expect(t, ok)
	result.tactical.config.vision_size = 0
	return result
}

@(test)
test_rooms_own_independent_event_storage_through_teardown_and_failed_creation :: proc(t: ^testing.T) {
	data := create_test_level(t)
	defer level.destroy(&data)
	first_player, second_player := create_test_player(t), create_test_player(t)
	first, first_ok := create_room(&data, &first_player, {})
	second, second_ok := create_room(&data, &second_player, {})
	defer destroy_room(&first)
	defer destroy_room(&second)
	if !testing.expect(t, first_ok && second_ok) { return }
	testing.expect(t, first.recent_events != nil && second.recent_events != nil && first.recent_events != second.recent_events)
	testing.expect(t, record_event(first.recent_events, {kind = .Gold_Gained, amount = 7}))
	testing.expect(t, record_event(second.recent_events, {kind = .Card_Drawn, card_id = 42}))
	destroy_room(&first)
	testing.expect(t, first.recent_events == nil)
	testing.expect_value(t, second.recent_events.count, 1)
	testing.expect_value(t, second.recent_events.events[0].card_id, u32(42))
	// Rejected content fails after storage is allocated; the test allocator
	// also checks that this path releases it together with the room arrays.
	bad_obstacles := [?]grid.Position{data.player_spawn}
	failed, ok := create_room(&data, &first_player, {obstacles = bad_obstacles[:]})
	testing.expect(t, !ok && failed.recent_events == nil)
}

@(test)
test_create_room_rejects_traps_beyond_presentation_capacity :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	trap_spawns: [MAX_TRAPS_PER_ROOM+1]Trap_Spawn

	_, ok := create_room(&level_data, &player, {traps = trap_spawns[:]})

	testing.expect(t, !ok)
}

@(test)
test_combat_move_charges_time_but_blocked_move_does_not :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 4, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	result := try_move_player(&room, .South)
	testing.expect_value(t, result, Action_Result.Moved)
	testing.expect_value(t, player.position, grid.Position{x = 1, y = 2})
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect_value(t, player.tactical.clock_fraction, TACTICAL_MOVE_SECONDS)
	clock_before := player.tactical

	enemy_before := room.enemies[0].position
	result = try_move_player(&room, .West)
	testing.expect_value(t, result, Action_Result.Blocked)
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect_value(t, player.tactical, clock_before)
	testing.expect_value(t, room.enemies[0].position, enemy_before)
}

@(test)
test_last_enemy_transitions_to_loot_and_drops_gold :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 2, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	result := try_move_player(&room, .East)
	testing.expect_value(t, result, Action_Result.Combat_Ended)
	testing.expect_value(t, room.phase, Room_Phase.Loot)
	testing.expect_value(t, len(room.enemies), 0)
	testing.expect_value(t, len(room.loot), 0)
	testing.expect_value(t, player.gold, i32(1))
	testing.expect(t, !player.deck.combat_active)
	testing.expect_value(t, player.deck.hand_count, 0)

	result = try_move_player(&room, .East)
	testing.expect_value(t, result, Action_Result.Moved)
	testing.expect_value(t, player.gold, i32(1))
	testing.expect_value(t, len(room.loot), 0)
}

@(test)
test_loot_magnet_uses_three_cell_chebyshev_range :: proc(t: ^testing.T) {
	testing.expect(t, loot_is_in_magnet_range({x = 0, y = 0}, {x = 3, y = 3}))
	testing.expect(t, !loot_is_in_magnet_range({x = 0, y = 0}, {x = 4, y = 3}))
}

@(test)
test_loot_magnet_collects_from_an_armed_trap_without_triggering_it :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	traps := [?]Trap_Spawn{{position = {x = 4, y = 2}, damage = 4}}
	room, ok := create_room(&level_data, &player, {traps = traps[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	append(&room.loot, Loot{position = room.traps[0].position, kind = .Gold, amount = 3})

	collected := collect_loot_in_magnet_range(&room)

	testing.expect_value(t, collected, 1)
	testing.expect_value(t, player.gold, i32(3))
	testing.expect_value(t, player.health, i32(10))
	testing.expect(t, room.traps[0].armed)
	testing.expect_value(t, len(room.loot), 0)
}

@(test)
test_loot_magnet_collects_enemy_drop_while_combat_continues :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{
		{position = {x = 2, y = 1}, health = 2, attack = 1},
		{position = {x = 5, y = 3}, health = 8, attack = 1},
	}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	result := try_move_player(&room, .East)

	testing.expect_value(t, result, Action_Result.Attacked)
	testing.expect_value(t, room.phase, Room_Phase.Combat)
	testing.expect_value(t, len(room.enemies), 1)
	testing.expect_value(t, len(room.loot), 0)
	testing.expect_value(t, player.gold, i32(1))
		testing.expect(t, room.recent_events.count >= 5)
		drop := room.recent_events.events[2]
		testing.expect_value(t, drop.kind, Game_Event_Kind.Loot_Dropped)
		testing.expect_value(t, drop.source, enemy_entity(1))
		testing.expect_value(t, drop.loot_kind, Loot_Kind.Gold)
		testing.expect_value(t, drop.from_position, grid.Position{x = 2, y = 1})
		pickup := room.recent_events.events[3]
	testing.expect_value(t, pickup.kind, Game_Event_Kind.Loot_Collected)
	testing.expect_value(t, pickup.loot_kind, Loot_Kind.Gold)
	testing.expect_value(t, pickup.amount, i32(1))
	testing.expect_value(t, pickup.from_position, grid.Position{x = 2, y = 1})
	testing.expect_value(t, pickup.to_position, player.position)
		testing.expect_value(t, room.recent_events.events[4].kind, Game_Event_Kind.Gold_Gained)
}

@(test)
test_combat_movement_collects_existing_loot_after_entering_range :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 1}, health = 8, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	append(&room.loot, Loot{position = {x = 5, y = 3}, kind = .Gold, amount = 2})

	testing.expect_value(t, try_move_player(&room, .South), Action_Result.Moved)
	testing.expect_value(t, player.gold, i32(0))
	testing.expect_value(t, len(room.loot), 1)

	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, try_move_player(&room, .East), Action_Result.Moved)
	testing.expect_value(t, room.phase, Room_Phase.Combat)
	testing.expect_value(t, player.gold, i32(2))
	testing.expect_value(t, len(room.loot), 0)
}

@(test)
test_loot_outside_magnet_range_is_collected_after_approaching :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	room, ok := create_room(&level_data, &player, {})
	testing.expect(t, ok)
	defer destroy_room(&room)
	append(&room.loot, Loot{position = {x = 5, y = 3}, kind = .Gold, amount = 2})

	testing.expect_value(t, try_move_player(&room, .South), Action_Result.Moved)
	testing.expect_value(t, player.gold, i32(0))
	testing.expect_value(t, len(room.loot), 1)

	testing.expect_value(t, try_move_player(&room, .East), Action_Result.Moved)
	testing.expect_value(t, player.gold, i32(2))
	testing.expect_value(t, len(room.loot), 0)
}

@(test)
test_exit_completes_room_only_after_combat :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	room, ok := create_room(&level_data, &player, {})
	testing.expect(t, ok)
	defer destroy_room(&room)
	testing.expect_value(t, room.phase, Room_Phase.Loot)

	testing.expect_value(t, try_move_player(&room, .East), Action_Result.Moved)
	testing.expect_value(t, try_move_player(&room, .East), Action_Result.Moved)
	result := try_move_player(&room, .South)

	testing.expect_value(t, result, Action_Result.Room_Completed)
	testing.expect_value(t, room.phase, Room_Phase.Complete)
}

@(test)
test_trap_is_single_use_and_respects_defense :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 8, attack = 1}}
	trap_spawns := [?]Trap_Spawn{{position = {x = 1, y = 2}, damage = 4}}
	room, ok := create_room(&level_data, &player, {
		enemies = enemy_spawns[:],
		traps = trap_spawns[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)

	try_move_player(&room, .South)
	testing.expect_value(t, player.health, i32(7))
	testing.expect(t, !room.traps[0].armed)

	try_move_player(&room, .North)
	try_move_player(&room, .South)
	testing.expect_value(t, player.health, i32(7))
}

@(test)
test_obstacle_blocks_movement :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 8, attack = 1}}
	obstacles := [?]grid.Position{{x = 2, y = 1}}
	room, ok := create_room(&level_data, &player, {
		enemies = enemy_spawns[:],
		obstacles = obstacles[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)

	result := try_move_player(&room, .East)
	testing.expect_value(t, result, Action_Result.Blocked)
	testing.expect_value(t, player.position, grid.Position{x = 1, y = 1})
}

@(test)
test_wait_lets_adjacent_enemy_attack :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 8, attack = 3}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	advance_enemy_rework_seconds(t, &room, 3)
	testing.expect_value(t, player.health, i32(8))
	testing.expect_value(t, room.enemies[0].position, grid.Position{x = 2, y = 1})
}

@(test)
test_adjacent_bump_attack_charges_time_without_moving_player :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 4, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	result := try_move_player(&room, .East)
	testing.expect_value(t, result, Action_Result.Attacked)
	testing.expect_value(t, room.enemies[0].health, i32(2))
	testing.expect_value(t, player.position, grid.Position{x = 1, y = 1})
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect_value(t, player.tactical.queued_beats, 1)
}

@(test)
test_loot_movement_never_advances_combat_pulse :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	room, ok := create_room(&level_data, &player, {})
	testing.expect(t, ok)
	defer destroy_room(&room)
	testing.expect_value(t, room.phase, Room_Phase.Loot)

	for step in 0..<32 {
		direction := Move_Direction.South if step%2 == 0 else .North
		result := try_move_player(&room, direction)

		testing.expect_value(t, result, Action_Result.Moved)
		testing.expect_value(t, room.pulse_count, u64(0))
	}
}

@(test)
test_room_creation_failure_from_active_deck_preserves_entire_player :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	player.position = {x = 4, y = 3}
	player.statuses.items[0] = {kind = .Shield, potency = 2, remaining_pulses = 3}
	player.statuses.count = 1
	testing.expect(t, begin_deck_combat(&player.deck))
	before := player
	enemies := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 4, attack = 1}}

	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})

	testing.expect(t, !ok)
	destroy_room(&room)
	testing.expect_value(t, player, before)
}

@(test)
test_enemy_can_defeat_player :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	player.health = 2
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 8, attack = 4}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	advance_enemy_rework_seconds(t, &room, 3)
	testing.expect_value(t, room.phase, Room_Phase.Defeat)
	testing.expect_value(t, player.health, i32(0))
	testing.expect(t, !player.deck.combat_active)
}

@(test)
test_room_rejects_overlapping_entities :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	position_before := player.position
	deck_before := player.deck
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 4, y = 2}, health = 4, attack = 1}}
	trap_spawns := [?]Trap_Spawn{{position = {x = 4, y = 2}, damage = 3}}

	room, ok := create_room(&level_data, &player, {
		enemies = enemy_spawns[:],
		traps = trap_spawns[:],
	})

	testing.expect(t, !ok)
	testing.expect_value(t, player.position, position_before)
	testing.expect_value(t, player.deck, deck_before)
	// A failed constructor must leave an object that is safe to destroy.
	destroy_room(&room)
}
