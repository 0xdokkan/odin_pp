package main

import "core:testing"
import game "game"
import level "level"

tactical_pressure_drain :: proc(t: ^testing.T, room: ^game.Room) {
	for _ in 0..<256 {
		if room.qte.kind != .None { testing.expect(t, game.resolve_qte(room, false)) }
		if !room.tactical_pulse.pending {
			if room.phase == .Combat && room.player.tactical.phase == .Decision && room.player.tactical.remaining <= 0 {
				testing.expect(t, game.tactical_expire_window(room))
			}
			return
		}
		testing.expect(t, game.continue_tactical_pulse(room))
	}
	testing.expect(t, false, "tactical pulse did not finish")
}

@(test)
test_tactical_fixed_recovery_and_cycle_restart_after_reward_and_next_room :: proc(t: ^testing.T) {
	run, created := game.create_run({max_health = 1000, attack = 2, defense = 1}, DEMO_RUN_CONFIG, 0x7AC71C)
	testing.expect(t, created)
	defer game.destroy_run(&run)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.timer_seconds = 2
	testing.expect(t, game.configure_tactical(&run.player, config))
	testing.expect(t, game.initialize_empty_deck(&run.player.deck, game.DEFAULT_DECK_RULES, 77))
	for definition in ([?]game.Card_Id{.Heavy_Blow, .Guard, .Guard, .Guard, .Guard}) {
		_, added := game.add_owned_card(&run.player.deck, definition)
		testing.expect(t, added)
	}
	rows := [?]string{"#########", "#.......#", "#.......#", "#...@...#", "#.......#", "#.....>.#", "#########"}
	data, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	defer level.destroy(&data)
	enemies := [?]game.Enemy_Spawn{{position = {3, 3}, health = 3, attack = 1}}
	room, built := game.create_room(&data, &run.player, {enemies = enemies[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)

	// Reach two deadlines; every recovery is exactly one supplied second.
	for cycle in 1..=2 {
		for _ in 0..<config.timer_seconds {
			testing.expect(t, game.wait_player_turn(&room) != .Invalid_Phase)
			tactical_pressure_drain(t, &room)
		}
		testing.expect_value(t, run.player.tactical.cycle, cycle)
		testing.expect_value(t, run.player.tactical.phase, game.Tactical_Phase.Recovery)
		testing.expect_value(t, run.player.tactical.remaining, game.TACTICAL_RECOVERY_SECONDS)
		testing.expect(t, !game.tactical_tick(&room, game.TACTICAL_RECOVERY_SECONDS, true, false))
		tactical_pressure_drain(t, &room)
	}
	testing.expect_value(t, run.player.tactical.phase, game.Tactical_Phase.Decision)
	heavy: u32
	for card in run.player.deck.hand[:run.player.deck.hand_count] {
		if card.definition_id == .Heavy_Blow { heavy = card.id }
	}
	testing.expect(t, heavy != 0)
	play := game.play_card(&room, heavy, game.entity_target(game.enemy_entity(room.enemies[0].id)))
	testing.expect_value(t, play.result, game.Card_Play_Result.Combat_Ended)
	testing.expect_value(t, room.phase, game.Room_Phase.Loot)
	testing.expect_value(t, run.player.tactical.cycle, 2)
	metrics := run.player.tactical.metrics
	testing.expect_value(t, metrics.forced_pulses, u64(2))
	for _ in 0..<32 {
		if room.phase != .Loot { break }
		direction, found := m7_route_move(&room)
		testing.expect(t, found)
		if !found { return }
		testing.expect(t, game.try_move_player(&room, direction) != .Blocked)
	}
	testing.expect_value(t, room.phase, game.Room_Phase.Complete)
	testing.expect_value(t, game.finish_room(&run, room.phase), game.Run_Transition.Reward)
	testing.expect_value(t, game.skip_card_reward(&run), game.Card_Reward_Result.Skipped)
	next := first_available_room_node(&run)
	testing.expect(t, next != game.INVALID_NODE_ID)

	// Preview/build is transactional: it must not reset the active player.
	node, found := game.node_at(&run, next)
	testing.expect(t, found)
	if !found { return }
	prepared: Prepared_Demo_Room
	defer destroy_prepared_demo_room(&prepared)
	before := run.player.tactical
	invalid := node^
	invalid.room_seed = 0
	testing.expect(t, !prepare_demo_room(&prepared, &run, &invalid, true))
	testing.expect_value(t, run.player.tactical, before)
	testing.expect(t, prepare_demo_room(&prepared, &run, node, true))
	testing.expect_value(t, run.player.tactical, before)
	testing.expect_value(t, prepared.player.tactical.cycle, 0)
	testing.expect_value(t, prepared.player.tactical.metrics, metrics)

	testing.expect(t, enter_demo_node(&data, &run, &room, next, true))
	testing.expect_value(t, run.player.tactical.cycle, 0)
	testing.expect_value(t, run.player.tactical.budget, config.timer_seconds)
	testing.expect_value(t, run.player.tactical.remaining, f32(config.timer_seconds))
	testing.expect_value(t, run.player.tactical.metrics, metrics)
	testing.expect_value(t, run.player.tactical.config, config)
	testing.expect_value(t, room.pulse_count, u64(0))
	for _ in 0..<config.timer_seconds {
		testing.expect(t, game.wait_player_turn(&room) != .Invalid_Phase)
		tactical_pressure_drain(t, &room)
	}
	testing.expect_value(t, run.player.tactical.phase, game.Tactical_Phase.Recovery)
	testing.expect_value(t, run.player.tactical.cycle, 1)
	testing.expect_value(t, run.player.tactical.remaining, game.TACTICAL_RECOVERY_SECONDS)
	testing.expect_value(t, run.player.tactical.metrics.pauses, metrics.pauses+1)
	testing.expect_value(t, run.player.tactical.metrics.forced_pulses, metrics.forced_pulses)
}
