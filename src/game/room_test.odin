package game

import "core:testing"
import grid "../grid"
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
	return result
}

@(test)
test_combat_move_advances_pulse_but_blocked_move_does_not :: proc(t: ^testing.T) {
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
	testing.expect_value(t, room.pulse_count, u64(1))

	enemy_before := room.enemies[0].position
	result = try_move_player(&room, .West)
	testing.expect_value(t, result, Action_Result.Blocked)
	testing.expect_value(t, room.pulse_count, u64(1))
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
		testing.expect(t, room.recent_events.count >= 6)
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

	wait_player_turn(&room)
	testing.expect_value(t, player.health, i32(8))
	testing.expect_value(t, room.enemies[0].position, grid.Position{x = 2, y = 1})
}

@(test)
test_adjacent_bump_attack_does_not_move_player_and_advances_pulse :: proc(t: ^testing.T) {
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
	testing.expect_value(t, room.pulse_count, u64(1))
}

@(test)
test_combat_movement_never_exhausts_and_advances_one_pulse_per_step :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 8, attack = 1}}
	obstacles := [?]grid.Position{{x = 4, y = 3}, {x = 5, y = 2}}
	room, ok := create_room(&level_data, &player, {
		enemies = enemy_spawns[:],
		obstacles = obstacles[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)
	enemy_position := room.enemies[0].position

	for step in 0..<32 {
		direction := Move_Direction.South if step%2 == 0 else .North
		result := try_move_player(&room, direction)

		testing.expect_value(t, result, Action_Result.Moved)
		expected_y := 2 if step%2 == 0 else 1
		testing.expect_value(t, player.position, grid.Position{x = 1, y = expected_y})
		testing.expect_value(t, room.pulse_count, u64(step+1))
		testing.expect_value(t, room.enemies[0].position, enemy_position)
	}
	testing.expect(t, validate_enemy_intents(&room))
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
test_enemy_can_defeat_player :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	player.health = 2
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 8, attack = 4}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	result := wait_player_turn(&room)
	testing.expect_value(t, result, Action_Result.Player_Defeated)
	testing.expect_value(t, room.phase, Room_Phase.Defeat)
	testing.expect_value(t, player.health, i32(0))
	testing.expect(t, !player.deck.combat_active)
}

@(test)
test_non_card_pulse_regenerates_deck_energy :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 8, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	player.deck.energy = 0

	result := try_move_player(&room, .South)

	testing.expect_value(t, result, Action_Result.Moved)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect_value(t, player.deck.energy, i32(1))
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
