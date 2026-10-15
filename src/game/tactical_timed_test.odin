package game

import "core:testing"
import level "../level"

timed_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player) -> Room {
	room := tactical_clock_test_room(t, data, player)
	player.tactical.config.timed_actions = true
	return room
}

@(test)
test_timed_actions_last_their_cost_in_real_time :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := timed_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	// The step is taken at once but the second is not burnt: it is lived.
	testing.expect_value(t, try_move_player(&room, .West), Action_Result.Moved)
	testing.expect_value(t, player.tactical.remaining, f32(20))
	testing.expect_value(t, player.tactical.action_remaining, f32(1))
	testing.expect(t, tactical_player_busy(&room) && !room.tactical_pulse.pending)
	// Nothing else can start while it runs.
	testing.expect_value(t, try_move_player(&room, .West), Action_Result.Invalid_Phase)
	testing.expect(t, !tactical_allows_action(&room) && tactical_allows_action(&room, true))
	// The window and the world run through that second as usual: one beat.
	testing.expect(t, !tactical_tick(&room, 0.6, true, false))
	testing.expect(t, tactical_player_busy(&room))
	testing.expect(t, !tactical_tick(&room, 0.4, true, false))
	testing.expect(t, room.tactical_pulse.pending)
	drain_tactical_test_pulse(t, &room, false)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect(t, abs(player.tactical.remaining-19) < 0.001)
	testing.expect(t, !tactical_player_busy(&room))
	testing.expect_value(t, try_move_player(&room, .West), Action_Result.Moved)
	// Without timed actions the same step burns its second at once.
	player.tactical.action_remaining = 0
	player.tactical.config.timed_actions = false
	testing.expect_value(t, try_move_player(&room, .East), Action_Result.Moved)
	drain_tactical_test_pulse(t, &room, false)
	testing.expect(t, abs(player.tactical.remaining-18) < 0.001)
	testing.expect(t, !tactical_player_busy(&room))
}

@(test)
test_timed_actions_a_dodge_cuts_the_wait_and_the_window_ends_it :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := timed_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, try_move_player(&room, .West), Action_Result.Moved)
	testing.expect(t, tactical_player_busy(&room))
	// A dodge answers at once and starts its own second.
	testing.expect(t, tactical_dodge_ready(&room))
	testing.expect(t, try_dodge_player(&room, .North))
	testing.expect_value(t, player.tactical.action_remaining, TACTICAL_DODGE_SECONDS)
	// The end of the window also ends a timed action still running.
	player.tactical.action_remaining = 0
	player.tactical.remaining = 0.5
	testing.expect_value(t, try_move_player(&room, .South), Action_Result.Moved)
	testing.expect(t, tactical_tick(&room, 0.5, true, false))
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, player.tactical.phase, Tactical_Phase.Recovery)
	testing.expect(t, !tactical_player_busy(&room))
	// Recovery walks take their time too.
	testing.expect(t, tactical_allows_movement(&room))
	testing.expect_value(t, try_move_player(&room, .South), Action_Result.Moved)
	testing.expect(t, tactical_player_busy(&room) && !tactical_allows_movement(&room) && tactical_allows_movement(&room, true))
}
