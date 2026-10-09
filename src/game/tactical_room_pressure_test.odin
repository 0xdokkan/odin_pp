package game

import "core:testing"
import level "../level"

@(test)
test_room_pressure_reset_is_committed_only_for_a_valid_tactical_room :: proc(t: ^testing.T) {
	data := create_test_level(t)
	defer level.destroy(&data)
	for tactical in ([2]bool{false, true}) {
		player := create_test_player(t)
		if tactical {
			testing.expect(t, configure_tactical(&player, DEFAULT_TACTICAL_CONFIG))
			player.tactical.phase = .Preparation
			player.tactical.cycle = 3
			player.tactical.budget = 0
			player.tactical.remaining = 4
			player.tactical.skipped_remaining = 5
			player.tactical.dodge_recovery = 2
			player.tactical.metrics.forced_pulses = 4
		}
		before := player.tactical
		invalid := [?]Enemy_Spawn{{position = data.player_spawn, health = 3, attack = 1}}
		rejected, invalid_ok := create_room(&data, &player, {enemies = invalid[:]})
		testing.expect(t, !invalid_ok)
		destroy_room(&rejected)
		testing.expect_value(t, player.tactical, before)
		valid := [?]Enemy_Spawn{{position = {5, 3}, health = 3, attack = 1}}
		room, built := create_room(&data, &player, {enemies = valid[:]})
		testing.expect(t, built)
		if tactical {
			testing.expect_value(t, player.tactical.phase, Tactical_Phase.Decision)
			testing.expect_value(t, player.tactical.cycle, 0)
			testing.expect_value(t, player.tactical.budget, before.config.timer_seconds)
			testing.expect_value(t, player.tactical.remaining, f32(before.config.timer_seconds))
			testing.expect_value(t, player.tactical.skipped_remaining, 0)
			testing.expect_value(t, player.tactical.dodge_recovery, 0)
			testing.expect_value(t, player.tactical.metrics, before.metrics)
		} else {
			testing.expect_value(t, player.tactical, before)
		}
		destroy_room(&room)
	}
}
