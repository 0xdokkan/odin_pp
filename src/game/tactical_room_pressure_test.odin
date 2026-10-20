package game

import "core:testing"
import level "../level"

@(test)
test_room_pressure_reset_is_committed_only_for_a_valid_tactical_room :: proc(t: ^testing.T) {
	data := create_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	testing.expect(t, configure_tactical(&player, DEFAULT_TACTICAL_CONFIG))
	player.tactical.phase = .Recovery
	player.tactical.cycle = 3
	player.tactical.budget = 0
	player.tactical.remaining = 4
	player.tactical.dodge_recovery = 2
	player.tactical.clock_fraction = 0.5
	player.tactical.queued_beats = 9
	player.tactical.metrics.forced_pulses = 4
	before := player.tactical
	invalid := [?]Enemy_Spawn{{position = data.player_spawn, health = 3, attack = 1}}
	rejected, invalid_ok := create_room(&data, &player, {enemies = invalid[:]})
	testing.expect(t, !invalid_ok)
	destroy_room(&rejected)
	testing.expect_value(t, player.tactical, before)
	valid := [?]Enemy_Spawn{{position = {5, 3}, health = 3, attack = 1}}
	room, built := create_room(&data, &player, {enemies = valid[:]})
	testing.expect(t, built)
	testing.expect_value(t, player.tactical.phase, Tactical_Phase.Decision)
	testing.expect_value(t, player.tactical.cycle, 0)
	testing.expect_value(t, player.tactical.budget, before.config.timer_seconds)
	testing.expect_value(t, player.tactical.remaining, f32(before.config.timer_seconds))
	testing.expect_value(t, player.tactical.dodge_recovery, 0)
	testing.expect_value(t, player.tactical.clock_fraction, f32(0))
	testing.expect_value(t, player.tactical.queued_beats, 0)
	testing.expect_value(t, player.tactical.metrics, before.metrics)
	destroy_room(&room)
}

@(test)
test_room_rejects_invalid_clock_configuration_without_changing_player :: proc(t: ^testing.T) {
	invalid_room := Room{phase = .Combat, lasso = {active = true}, pinball = {active = true}}
	testing.expect(t, !tactical_lasso_due(&invalid_room))
	testing.expect(t, !tactical_pinball_due(&invalid_room))
	data := create_test_level(t)
	defer level.destroy(&data)
	for invalid in 0..<4 {
		player := create_test_player(t)
		switch invalid {
		case 0: player.tactical.config = {}
		case 1: player.tactical.config.timer_seconds = 61
		case 2: player.tactical.config.vision_size = -1
		case 3: player.tactical.config.qte_seconds = 0
		}
		before := player
		testing.expect(t, !configure_tactical(&player, player.tactical.config))
		room, built := create_room(&data, &player, {})
		testing.expect(t, !built)
		testing.expect_value(t, player, before)
		destroy_room(&room)
	}
}
