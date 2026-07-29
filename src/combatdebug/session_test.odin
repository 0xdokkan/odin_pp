package combatdebug

import "core:bytes"
import "core:strings"
import "core:testing"

import game "../game"

playtest_test_room :: proc(t: ^testing.T) -> (room: game.Room, player: game.Player) {
	player_ok: bool
	player, player_ok = game.create_player({max_health = 40, attack = 2, defense = 1})
	testing.expect(t, player_ok)
	player.deck.energy = 2
	room = {
		phase = .Combat,
		pulse_count = 4,
		player = &player,
	}
	return
}

@(test)
test_playtest_session_finalizes_each_room_exactly_once_and_aggregates :: proc(t: ^testing.T) {
	room, player := playtest_test_room(t)
	// Returning a Room that points at the returned Player would leave a pointer
	// to the callee's copy. Keep the synthetic room explicitly tied to this copy.
	room.player = &player
	session: Playtest_Session
	testing.expect(t, begin_playtest_session(&session, 0xC0FFEE))
	defer destroy_playtest_session(&session)

	first := Playtest_Room_Metadata{
		node_id = 0,
		node_kind = .Combat,
		depth = 0,
		room_seed = 101,
	}
	testing.expect(t, begin_playtest_room(&session, first, &room))
	metrics, metrics_ok := playtest_room_metrics(&session)
	testing.expect(t, metrics_ok)
	metrics.commands_attempted[int(Command_Kind.Move)] = 3
	metrics.commands_committed[int(Command_Kind.Move)] = 2
	metrics.commands_rejected[int(Command_Kind.Move)] = 1
	metrics.pulses = 2
	metrics.direct_player_damage_to_enemies = 4
	metrics.card_committed[int(game.Card_Id.Shove)] = 1
	metrics.card_movement_cells[int(game.Card_Id.Shove)] = 1
	metrics.card_trap_triggers_on_enemies[int(game.Card_Id.Shove)] = 1
	metrics.forced_enemy_movement_cells = 1
	metrics.trap_triggers_on_enemies = 1
	metrics.object_hazard_triggers_on_player = 1
	metrics.object_hazard_damage_to_player = 2
	metrics.maximum_no_damage_streak = 2
	metrics.has_distance_sample = true
	metrics.minimum_enemy_distance = 2
	metrics.maximum_enemy_distance = 5

	room.pulse_count = 6
	room.phase = .Loot
	room.player.health = 37
	room.player.deck.energy = 1
	testing.expect(t, finish_playtest_room(&session, &room))
	testing.expect(t, !finish_playtest_room(&session, &room))
	testing.expect_value(t, len(session.rooms), 1)
	testing.expect_value(t, session.rooms[0].room_index, 0)
	testing.expect(t, session.rooms[0].combat_finished)
	testing.expect(t, session.rooms[0].integrity_complete)
	testing.expect_value(t, session.aggregate.pulses, u64(2))
	testing.expect_value(t, session.aggregate.minimum_enemy_distance, 2)
	testing.expect_value(t, session.aggregate.maximum_enemy_distance, 5)

	room.phase = .Combat
	room.pulse_count = 10
	room.player.health = 35
	room.player.deck.energy = 3
	second := Playtest_Room_Metadata{
		node_id = 4,
		node_kind = .Elite,
		depth = 2,
		room_seed = 202,
	}
	testing.expect(t, begin_playtest_room(&session, second, &room))
	second_metrics, second_metrics_ok := playtest_room_metrics(&session)
	testing.expect(t, second_metrics_ok)
	second_metrics.commands_attempted[int(Command_Kind.Play_Card)] = 2
	second_metrics.commands_committed[int(Command_Kind.Play_Card)] = 2
	second_metrics.pulses = 2
	second_metrics.cards_played = 2
	second_metrics.card_committed[int(game.Card_Id.Caustic_Bloom)] = 2
	second_metrics.card_poison_applications[int(game.Card_Id.Caustic_Bloom)] = 4
	second_metrics.poison_applications = 4
	second_metrics.poison_ticks = 4
	second_metrics.object_hazard_triggers_on_enemies = 2
	second_metrics.object_hazard_damage_to_enemies = 4
	second_metrics.events_dropped = 1
	second_metrics.has_distance_sample = true
	second_metrics.minimum_enemy_distance = 1
	second_metrics.maximum_enemy_distance = 3

	room.phase = .Defeat
	room.pulse_count = 12
	room.player.health = 0
	testing.expect(t, finish_playtest_session(&session, .Defeat, &room))
	testing.expect(t, !finish_playtest_session(&session, .Defeat))
	testing.expect_value(t, len(session.rooms), 2)
	testing.expect_value(t, session.aggregate.pulses, u64(4))
	testing.expect_value(t, session.aggregate.cards_played, u64(2))
	testing.expect_value(t, session.aggregate.events_dropped, u64(1))
	testing.expect_value(
		t,
		session.aggregate.card_movement_cells[int(game.Card_Id.Shove)],
		u64(1),
	)
	testing.expect_value(
		t,
		session.aggregate.card_poison_applications[int(game.Card_Id.Caustic_Bloom)],
		u64(4),
	)
	testing.expect_value(t, session.aggregate.forced_enemy_movement_cells, u64(1))
	testing.expect_value(t, session.aggregate.poison_ticks, u64(4))
	testing.expect_value(t, session.aggregate.object_hazard_triggers_on_player, u64(1))
	testing.expect_value(t, session.aggregate.object_hazard_triggers_on_enemies, u64(2))
	testing.expect_value(t, session.aggregate.object_hazard_damage_to_player, i64(2))
	testing.expect_value(t, session.aggregate.object_hazard_damage_to_enemies, i64(4))
	testing.expect_value(t, session.aggregate.minimum_enemy_distance, 1)
	testing.expect_value(t, session.aggregate.maximum_enemy_distance, 5)
	testing.expect(t, session.finalized)
	testing.expect_value(t, session.outcome, Playtest_Run_Outcome.Defeat)
}

@(test)
test_playtest_report_is_named_and_deterministic :: proc(t: ^testing.T) {
	room, player := playtest_test_room(t)
	room.player = &player
	session: Playtest_Session
	testing.expect(t, begin_playtest_session(&session, 77))
	defer destroy_playtest_session(&session)
	testing.expect(t, begin_playtest_room(&session, {
		node_id = 2,
		node_kind = .Boss,
		depth = 3,
		room_seed = 999,
	}, &room))
	metrics, metrics_ok := playtest_room_metrics(&session)
	testing.expect(t, metrics_ok)
	metrics.commands_attempted[int(Command_Kind.Bump_Attack)] = 1
	metrics.commands_committed[int(Command_Kind.Bump_Attack)] = 1
	metrics.direct_damage_by_command[int(Command_Kind.Bump_Attack)] = 2
	metrics.card_attempted[int(game.Card_Id.Strike)] = 1
	metrics.card_committed[int(game.Card_Id.Strike)] = 1
	metrics.card_damage_to_enemies[int(game.Card_Id.Strike)] = 3
	metrics.object_hazard_triggers_on_player = 1
	metrics.object_hazard_triggers_on_enemies = 2
	metrics.object_hazard_damage_to_player = 3
	metrics.object_hazard_damage_to_enemies = 4
	metrics.pulses = 1
	testing.expect(t, observe_playtest_sample(&session, {
		valid = true,
		kind = .Bump_Attack,
		committed = true,
		complete = true,
		pulse_delta = 1,
		player_damage_to_enemies = 2,
		object_hazard_triggers_on_player = 1,
		object_hazard_damage_to_player = 3,
	}))
	room.phase = .Loot
	room.pulse_count += 1
	testing.expect(t, finish_playtest_session(&session, .Victory, &room))

	report, built := build_playtest_report(&session)
	testing.expect(t, built)
	defer destroy_playtest_report(&report)
	testing.expect_value(t, report.schema_version, PLAYTEST_REPORT_SCHEMA_VERSION)
	testing.expect_value(t, report.outcome, "Victory")
	testing.expect_value(t, len(report.rooms), 1)
	testing.expect_value(t, len(report.commands), 1)
	testing.expect_value(t, report.commands[0].kind, "Bump_Attack")
	testing.expect_value(t, report.metrics.cards[int(game.Card_Id.Strike)].name, "Strike")
	testing.expect_value(
		t,
		report.metrics.cards[int(game.Card_Id.Strike)].damage_to_enemies,
		i64(3),
	)
	testing.expect_value(t, report.rooms[0].node_kind, "Boss")
	testing.expect_value(t, report.metrics.object_hazard_triggers_on_player, u64(1))
	testing.expect_value(t, report.metrics.object_hazard_triggers_on_enemies, u64(2))
	testing.expect_value(t, report.metrics.object_hazard_damage_to_player, i64(3))
	testing.expect_value(t, report.metrics.object_hazard_damage_to_enemies, i64(4))
	testing.expect_value(t, report.commands[0].object_hazard_triggers_on_player, u64(1))
	testing.expect_value(t, report.commands[0].object_hazard_damage_to_player, i64(3))
	testing.expect_value(
		t,
		report.metrics.commands[int(Command_Kind.Bump_Attack)].kind,
		"Bump_Attack",
	)

	first, first_ok := marshal_playtest_report(&session)
	testing.expect(t, first_ok)
	defer delete(first)
	second, second_ok := marshal_playtest_report(&session)
	testing.expect(t, second_ok)
	defer delete(second)
	testing.expect(t, bytes.equal(first, second))
	json_text := string(first)
	testing.expect(t, strings.contains(json_text, `"schema_version": 1`))
	testing.expect(t, strings.contains(json_text, `"kind": "Bump_Attack"`))
	testing.expect(t, strings.contains(json_text, `"node_kind": "Boss"`))
	testing.expect(t, strings.contains(json_text, `"object_hazard_triggers_on_player": 1`))
	testing.expect(t, strings.contains(json_text, `"object_hazard_damage_to_enemies": 4`))
}
