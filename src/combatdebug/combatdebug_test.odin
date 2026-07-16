package combatdebug

import "core:testing"
import game "../game"
import grid "../grid"
import level "../level"

debug_test_level :: proc(t: ^testing.T, rows: []string) -> level.Level {
	result, parse_error, _ := level.from_ascii(rows)
	testing.expect_value(t, parse_error, level.Parse_Error.None)
	return result
}

debug_test_player :: proc(t: ^testing.T) -> game.Player {
	result, ok := game.create_player({max_health = 50, attack = 2, defense = 1})
	testing.expect(t, ok)
	return result
}

debug_test_single_card_deck :: proc(t: ^testing.T, player: ^game.Player, card: game.Card_Id) {
	testing.expect(t, player != nil)
	testing.expect(t, game.initialize_empty_deck(&player.deck, {
		hand_size = 1,
		max_energy = 3,
		energy_regen_per_pulse = 1,
	}, 41))
	_, added := game.add_owned_card(&player.deck, card)
	testing.expect(t, added)
}

@(test)
test_observer_classifies_bump_damage_and_full_energy_waste :: proc(t: ^testing.T) {
	rows := [?]string{
		"#######",
		"#@....#",
		"#..>..#",
		"#.....#",
		"#######",
	}
	level_data := debug_test_level(t, rows[:])
	defer level.destroy(&level_data)
	player := debug_test_player(t)
	enemies := [?]game.Enemy_Spawn{{
		position = {x = 2, y = 1},
		health = 8,
		attack = 1,
		archetype = .Chaser,
	}}
	room, room_ok := game.create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, room_ok)
	defer game.destroy_room(&room)

	snapshot, captured := capture_command_snapshot(&room)
	testing.expect(t, captured)
	result := game.try_move_player(&room, .East)
	testing.expect_value(t, result, game.Action_Result.Attacked)
	metrics: Combat_Metrics
	testing.expect(t, observe_command(&metrics, snapshot, .Bump_Attack, true, &room))

	testing.expect_value(t, metrics.commands_attempted[int(Command_Kind.Bump_Attack)], u64(1))
	testing.expect_value(t, metrics.commands_committed[int(Command_Kind.Bump_Attack)], u64(1))
	testing.expect_value(t, metrics.direct_player_damage_to_enemies, i64(2))
	testing.expect_value(
		t,
		metrics.direct_damage_by_command[int(Command_Kind.Bump_Attack)],
		i64(2),
	)
	testing.expect_value(t, metrics.damage_taken, i64(1))
	testing.expect_value(t, metrics.damage_taken_by_command[int(Command_Kind.Bump_Attack)], i64(1))
	testing.expect_value(t, metrics.pulses, u64(1))
	testing.expect_value(t, metrics.energy_spent, i64(0))
	testing.expect_value(t, metrics.pulse_events, u64(1))
	testing.expect_value(t, metrics.energy_restored, i64(0))
	testing.expect_value(t, metrics.energy_wasted, i64(1))
	testing.expect_value(t, metrics.integrity_mismatches, u64(0))
}

@(test)
test_terminal_bump_keeps_its_command_kind_when_result_reports_combat_end :: proc(
	t: ^testing.T,
) {
	rows := [?]string{
		"#######",
		"#@....#",
		"#..>..#",
		"#.....#",
		"#######",
	}
	level_data := debug_test_level(t, rows[:])
	defer level.destroy(&level_data)
	player := debug_test_player(t)
	enemies := [?]game.Enemy_Spawn{{position = {x = 2, y = 1}, health = 2, attack = 1}}
	room, room_ok := game.create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, room_ok)
	defer game.destroy_room(&room)

	resolved_kind, classified := command_kind_for_move(&room, .East)
	testing.expect(t, classified)
	testing.expect_value(t, resolved_kind, Command_Kind.Bump_Attack)
	snapshot, captured := capture_command_snapshot(&room)
	testing.expect(t, captured)
	result := game.try_move_player(&room, .East)
	testing.expect_value(t, result, game.Action_Result.Combat_Ended)
	testing.expect(t, move_result_was_committed(result))
	metrics: Combat_Metrics
	testing.expect(t, observe_command(&metrics, snapshot, resolved_kind, true, &room))

	testing.expect_value(t, metrics.commands_committed[int(Command_Kind.Bump_Attack)], u64(1))
	testing.expect_value(t, metrics.commands_committed[int(Command_Kind.Move)], u64(0))
	testing.expect_value(t, metrics.direct_player_damage_to_enemies, i64(2))
	testing.expect_value(
		t,
		metrics.direct_damage_by_command[int(Command_Kind.Bump_Attack)],
		i64(2),
	)
	testing.expect_value(t, metrics.pulses, u64(0))
	testing.expect_value(t, room.phase, game.Room_Phase.Loot)
}

@(test)
test_observer_keeps_card_damage_and_energy_in_the_card_bucket :: proc(t: ^testing.T) {
	rows := [?]string{
		"#######",
		"#@....#",
		"#..>..#",
		"#.....#",
		"#######",
	}
	level_data := debug_test_level(t, rows[:])
	defer level.destroy(&level_data)
	player := debug_test_player(t)
	debug_test_single_card_deck(t, &player, .Strike)
	enemies := [?]game.Enemy_Spawn{{position = {x = 2, y = 1}, health = 8, attack = 1}}
	room, room_ok := game.create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, room_ok)
	defer game.destroy_room(&room)

	snapshot, captured := capture_command_snapshot(&room)
	testing.expect(t, captured)
	card := player.deck.hand[0]
	play := game.play_card(
		&room,
		card.id,
		game.entity_target(game.enemy_entity(room.enemies[0].id)),
	)
	testing.expect(t, game.card_play_was_committed(play.result))
	metrics: Combat_Metrics
	testing.expect(t, observe_command(&metrics, snapshot, .Play_Card, true, &room))

	testing.expect_value(t, metrics.commands_committed[int(Command_Kind.Play_Card)], u64(1))
	testing.expect_value(t, metrics.commands_committed[int(Command_Kind.Bump_Attack)], u64(0))
	testing.expect_value(t, metrics.cards_played, u64(1))
	testing.expect_value(t, metrics.direct_player_damage_to_enemies, i64(3))
	testing.expect_value(t, metrics.direct_damage_by_command[int(Command_Kind.Play_Card)], i64(3))
	testing.expect_value(t, metrics.energy_spent, i64(1))
	testing.expect_value(t, metrics.energy_spent_by_command[int(Command_Kind.Play_Card)], i64(1))
	testing.expect_value(t, metrics.pulses, u64(1))
	testing.expect_value(t, metrics.energy_restored, i64(1))
	testing.expect_value(t, metrics.energy_wasted, i64(0))
}

@(test)
test_observer_counts_refocus_and_enemy_misses_without_guessing_commands :: proc(t: ^testing.T) {
	rows := [?]string{
		"########",
		"#@.....#",
		"#...>..#",
		"#......#",
		"########",
	}
	level_data := debug_test_level(t, rows[:])
	defer level.destroy(&level_data)
	player := debug_test_player(t)
	debug_test_single_card_deck(t, &player, .Guard)
	enemies := [?]game.Enemy_Spawn{{
		position = {x = 4, y = 1},
		health = 8,
		attack = 2,
		archetype = .Archer,
	}}
	room, room_ok := game.create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, room_ok)
	defer game.destroy_room(&room)

	metrics: Combat_Metrics
	refocus_before, captured := capture_command_snapshot(&room)
	testing.expect(t, captured)
	refocus := game.refocus_player_hand(&room)
	testing.expect(t, game.refocus_was_committed(refocus.result))
	testing.expect(t, observe_command(&metrics, refocus_before, .Refocus, true, &room))
	testing.expect_value(t, metrics.refocuses, u64(1))
	testing.expect_value(t, metrics.energy_wasted, i64(1))
	testing.expect_value(t, metrics.energy_wasted_by_command[int(Command_Kind.Refocus)], i64(1))

	damage_before_move := metrics.damage_taken
	move_before, move_captured := capture_command_snapshot(&room)
	testing.expect(t, move_captured)
	move := game.try_move_player(&room, .South)
	testing.expect_value(t, move, game.Action_Result.Moved)
	testing.expect(t, observe_command(&metrics, move_before, .Move, true, &room))
	testing.expect_value(t, metrics.enemy_attack_misses, u64(1))
	testing.expect_value(t, metrics.misses_by_command[int(Command_Kind.Move)], u64(1))
	testing.expect_value(t, metrics.damage_taken, damage_before_move)
	testing.expect_value(t, metrics.player_moves, u64(1))
}

@(test)
test_rejected_observation_does_not_consume_a_stale_event_log :: proc(t: ^testing.T) {
	rows := [?]string{
		"#######",
		"#@....#",
		"#..>..#",
		"#.....#",
		"#######",
	}
	level_data := debug_test_level(t, rows[:])
	defer level.destroy(&level_data)
	player := debug_test_player(t)
	enemies := [?]game.Enemy_Spawn{{position = {x = 5, y = 3}, health = 8, attack = 1}}
	room, room_ok := game.create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, room_ok)
	defer game.destroy_room(&room)
	room.recent_events.count = 1
	room.recent_events.events[0] = {
		kind = .Damaged,
		source = game.enemy_entity(999),
		target = game.PLAYER_ENTITY,
		amount = 9,
	}
	room.recent_events.dropped_count = 3

	snapshot, captured := capture_command_snapshot(&room)
	testing.expect(t, captured)
	metrics: Combat_Metrics
	testing.expect(t, observe_command(&metrics, snapshot, .Wait, false, &room))

	testing.expect_value(t, metrics.commands_attempted[int(Command_Kind.Wait)], u64(1))
	testing.expect_value(t, metrics.commands_rejected[int(Command_Kind.Wait)], u64(1))
	testing.expect_value(t, metrics.events_observed, u64(0))
	testing.expect_value(t, metrics.events_dropped, u64(0))
	testing.expect_value(t, metrics.damage_taken, i64(0))
}

@(test)
test_max_distance_policy_is_deterministic_and_prefers_safety :: proc(t: ^testing.T) {
	rows := [?]string{
		"#######",
		"#@....#",
		"#..>..#",
		"#.....#",
		"#######",
	}
	level_data := debug_test_level(t, rows[:])
	defer level.destroy(&level_data)
	player := debug_test_player(t)
	enemies := [?]game.Enemy_Spawn{{position = {x = 3, y = 1}, health = 8, attack = 1}}
	room, room_ok := game.create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, room_ok)
	defer game.destroy_room(&room)

	state: Max_Distance_Policy_State
	first := choose_max_distance_command(&room, &state)
	second := choose_max_distance_command(&room, &state)
	testing.expect_value(t, first, second)
	testing.expect(t, first.valid)
	testing.expect_value(t, first.kind, Command_Kind.Move)
	testing.expect_value(t, first.direction, game.Move_Direction.South)

	room.enemies[0].intent.threatened_cells[0] = {x = 1, y = 2}
	room.enemies[0].intent.threatened_cell_count = 1
	safe := choose_max_distance_command(&room, &state)
	testing.expect(t, safe.valid)
	testing.expect_value(t, safe.kind, Command_Kind.Wait)
}

create_ring_scenario :: proc(t: ^testing.T, level_data: ^level.Level, player: ^game.Player) -> (
	room: game.Room,
	ok: bool,
) {
	rows := [?]string{
		"#########",
		"#@......#",
		"#.#####.#",
		"#.#####.#",
		"#.#####.#",
		"#......>#",
		"#########",
	}
	level_data^ = debug_test_level(t, rows[:])
	player^ = debug_test_player(t)
	enemies := [?]game.Enemy_Spawn{{
		position = {x = 1, y = 4},
		health = 100,
		attack = 2,
		archetype = .Chaser,
	}}
	return game.create_room(level_data, player, {enemies = enemies[:]})
}

@(test)
test_headless_kiting_scenario_repeats_the_same_integer_report :: proc(t: ^testing.T) {
	first_level, second_level: level.Level
	first_player, second_player: game.Player
	first_room, first_ok := create_ring_scenario(t, &first_level, &first_player)
	testing.expect(t, first_ok)
	defer level.destroy(&first_level)
	defer game.destroy_room(&first_room)
	second_room, second_ok := create_ring_scenario(t, &second_level, &second_player)
	testing.expect(t, second_ok)
	defer level.destroy(&second_level)
	defer game.destroy_room(&second_room)

	first := run_max_distance_scenario(&first_room, 20)
	second := run_max_distance_scenario(&second_room, 20)

	testing.expect_value(t, first, second)
	testing.expect(t, first.valid)
	testing.expect_value(t, first.termination, Scenario_Termination.Pulse_Budget)
	testing.expect_value(t, first.commands_executed, u64(20))
	testing.expect_value(t, first.final_pulse-first.initial_pulse, u64(20))
	testing.expect_value(t, first.metrics.damage_taken, i64(0))
	testing.expect(t, first.metrics.maximum_no_damage_streak >= 20)
	testing.expect_value(t, first.metrics.integrity_mismatches, u64(0))
	testing.expect(t, first.final_position != grid.Position{})
}
