package main

import "core:testing"
import combatdebug "combatdebug"
import game "game"
import grid "grid"
import level "level"

create_gameplay_command_test_level :: proc(t: ^testing.T) -> level.Level {
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

create_gameplay_command_test_player :: proc(t: ^testing.T) -> game.Player {
	result, ok := game.create_player({
		max_health = 10,
		attack = 2,
		defense = 1,
	})
	testing.expect(t, ok)
	return result
}

configure_single_card_test_deck :: proc(
	t: ^testing.T,
	player: ^game.Player,
	definition_id: game.Card_Id,
) {
	testing.expect(t, player != nil)
	testing.expect(t, game.initialize_empty_deck(&player.deck, {
		hand_size = 1,
		max_energy = 3,
		energy_regen_per_pulse = 1,
	}, 99))
	_, added := game.add_owned_card(&player.deck, definition_id)
	testing.expect(t, added)
}

@(test)
test_execute_gameplay_command_commits_only_a_successful_move :: proc(t: ^testing.T) {
	level_data := create_gameplay_command_test_level(t)
	defer level.destroy(&level_data)
	player := create_gameplay_command_test_player(t)
	room, ok := game.create_room(&level_data, &player, {})
	testing.expect(t, ok)
	defer game.destroy_room(&room)

	moved := execute_gameplay_command(&room, {
		kind = .Move,
		origin_phase = .Loot,
		direction = .South,
	})
	testing.expect(t, moved.committed)
	testing.expect(t, !moved.clears_card_interaction)
	testing.expect_value(t, player.position, grid.Position{x = 1, y = 2})

	position_before_blocked_move := player.position
	blocked := execute_gameplay_command(&room, {
		kind = .Move,
		origin_phase = .Loot,
		direction = .West,
	})
	testing.expect(t, !blocked.committed)
	testing.expect(t, !blocked.clears_card_interaction)
	testing.expect_value(t, player.position, position_before_blocked_move)
}

@(test)
test_execute_gameplay_command_commits_a_successful_wait_with_none_outcome :: proc(t: ^testing.T) {
	level_data := create_gameplay_command_test_level(t)
	defer level.destroy(&level_data)
	player := create_gameplay_command_test_player(t)
	enemies := [?]game.Enemy_Spawn{{
		position = {x = 5, y = 3},
		health = 8,
		attack = 1,
	}}
	room, ok := game.create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer game.destroy_room(&room)

	execution := execute_gameplay_command(&room, {kind = .Wait, origin_phase = .Combat})

	testing.expect(t, execution.committed)
	testing.expect(t, !execution.clears_card_interaction)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect_value(t, room.phase, game.Room_Phase.Combat)
}

@(test)
test_execute_gameplay_command_distinguishes_valid_and_invalid_card_plays :: proc(t: ^testing.T) {
	level_data := create_gameplay_command_test_level(t)
	defer level.destroy(&level_data)
	player := create_gameplay_command_test_player(t)
	configure_single_card_test_deck(t, &player, .Guard)
	enemies := [?]game.Enemy_Spawn{{
		position = {x = 5, y = 3},
		health = 8,
		attack = 1,
	}}
	room, ok := game.create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	card_id := player.deck.hand[0].id

	invalid := execute_gameplay_command(&room, {
		kind = .Play_Card,
		origin_phase = .Combat,
		card_id = card_id+1000,
		target = game.entity_target(game.PLAYER_ENTITY),
	})
	testing.expect(t, !invalid.committed)
	testing.expect(t, !invalid.clears_card_interaction)
	testing.expect_value(t, room.pulse_count, u64(0))

	valid := execute_gameplay_command(&room, {
		kind = .Play_Card,
		origin_phase = .Combat,
		card_id = card_id,
		target = game.entity_target(game.PLAYER_ENTITY),
	})
	testing.expect(t, valid.committed)
	testing.expect(t, valid.clears_card_interaction)
	testing.expect_value(t, room.pulse_count, u64(1))
}

@(test)
test_execute_gameplay_command_commits_refocus_and_clears_card_interaction :: proc(t: ^testing.T) {
	level_data := create_gameplay_command_test_level(t)
	defer level.destroy(&level_data)
	player := create_gameplay_command_test_player(t)
	configure_single_card_test_deck(t, &player, .Guard)
	enemies := [?]game.Enemy_Spawn{{
		position = {x = 5, y = 3},
		health = 8,
		attack = 1,
	}}
	room, ok := game.create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer game.destroy_room(&room)

	execution := execute_gameplay_command(&room, {
		kind = .Refocus,
		origin_phase = .Combat,
	})

	testing.expect(t, execution.committed)
	testing.expect(t, execution.clears_card_interaction)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect(t, room.recent_events.count > 0)
	testing.expect_value(t, room.recent_events.events[0].kind, game.Game_Event_Kind.Hand_Refocused)
}

@(test)
test_execute_gameplay_command_rejects_a_buffered_command_after_phase_change :: proc(t: ^testing.T) {
	level_data := create_gameplay_command_test_level(t)
	defer level.destroy(&level_data)
	player := create_gameplay_command_test_player(t)
	room, ok := game.create_room(&level_data, &player, {})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	testing.expect_value(t, room.phase, game.Room_Phase.Loot)
	position_before := player.position

	execution := execute_gameplay_command(&room, {
		kind = .Move,
		origin_phase = .Combat,
		direction = .South,
	})

	testing.expect(t, !execution.committed)
	testing.expect_value(t, player.position, position_before)
	testing.expect_value(t, room.recent_events.count, 0)
}

@(test)
test_execute_gameplay_command_rejects_an_invalid_command_without_mutation :: proc(t: ^testing.T) {
	level_data := create_gameplay_command_test_level(t)
	defer level.destroy(&level_data)
	player := create_gameplay_command_test_player(t)
	room, ok := game.create_room(&level_data, &player, {})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	position_before := player.position
	phase_before := room.phase

	execution := execute_gameplay_command(&room, {})

	testing.expect_value(t, execution, Gameplay_Command_Execution{})
	testing.expect_value(t, player.position, position_before)
	testing.expect_value(t, room.phase, phase_before)
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect_value(t, room.recent_events.count, 0)
}

@(test)
test_observed_terminal_bump_keeps_kind_and_finalizes_combat_room :: proc(t: ^testing.T) {
	level_data := create_gameplay_command_test_level(t)
	defer level.destroy(&level_data)
	player := create_gameplay_command_test_player(t)
	enemies := [?]game.Enemy_Spawn{{
		position = {x = 2, y = 1},
		health = player.stats.attack,
		attack = 1,
	}}
	room, room_ok := game.create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, room_ok)
	defer game.destroy_room(&room)
	session: combatdebug.Playtest_Session
	testing.expect(t, combatdebug.begin_playtest_session(&session, 17))
	defer combatdebug.destroy_playtest_session(&session)
	testing.expect(t, combatdebug.begin_playtest_room(&session, {
		node_id = 0,
		node_kind = .Combat,
		depth = 0,
		room_seed = 99,
	}, &room))

	execution := execute_observed_gameplay_command(&room, {
		kind = .Move,
		origin_phase = .Combat,
		direction = .East,
	}, &session)

	testing.expect(t, execution.committed)
	testing.expect_value(t, room.phase, game.Room_Phase.Loot)
	testing.expect(t, !session.room_active)
	testing.expect_value(t, len(session.rooms), 1)
	testing.expect_value(t, len(session.commands), 1)
	testing.expect_value(
		t,
		session.commands[0].sample.kind,
		combatdebug.Command_Kind.Bump_Attack,
	)
	testing.expect_value(t, session.commands[0].sample.player_damage_to_enemies, i64(2))
	testing.expect_value(
		t,
		session.aggregate.commands_committed[int(combatdebug.Command_Kind.Bump_Attack)],
		u64(1),
	)
}
