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
	// The step is taken at once; its shorter cost, at the player's pace (half
	// its first 0.8 s), is lived in real time.
	testing.expect_value(t, try_move_player(&room, .West), Action_Result.Moved)
	testing.expect_value(t, player.tactical.remaining, f32(20))
	testing.expect_value(t, player.tactical.action_remaining, f32(0.4))
	testing.expect(t, tactical_player_busy(&room) && !room.tactical_pulse.pending)
	// Nothing else can start while it runs.
	testing.expect_value(t, try_move_player(&room, .West), Action_Result.Invalid_Phase)
	testing.expect(t, !tactical_allows_action(&room) && tactical_allows_action(&room, true))
	// Walking becomes available again before the world's next beat. Moving
	// faster neither speeds that beat up nor waits for it to release input.
	testing.expect(t, !tactical_tick(&room, 0.3, true, false))
	testing.expect(t, tactical_player_busy(&room))
	testing.expect(t, !tactical_tick(&room, 0.1, true, false))
	testing.expect(t, !tactical_player_busy(&room) && tactical_allows_movement(&room))
	testing.expect(t, !room.tactical_pulse.pending)
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect(t, abs(player.tactical.remaining-19.6) < 0.001)
	testing.expect(t, !tactical_tick(&room, 0.6, true, false))
	testing.expect(t, room.tactical_pulse.pending)
	drain_tactical_test_pulse(t, &room, false)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect(t, abs(player.tactical.remaining-19) < 0.001)
	testing.expect(t, !tactical_player_busy(&room))
	testing.expect_value(t, try_move_player(&room, .West), Action_Result.Moved)
	// Without timed actions (the bare rules) the same step spends its first
	// price at once.
	player.tactical.action_remaining = 0
	player.tactical.config.timed_actions = false
	testing.expect_value(t, try_move_player(&room, .East), Action_Result.Moved)
	drain_tactical_test_pulse(t, &room, false)
	testing.expect(t, abs(player.tactical.remaining-18.2) < 0.001)
	testing.expect(t, !tactical_player_busy(&room))
}

@(test)
test_faster_walks_keep_diagonal_steps_equal_and_bump_attacks_unchanged :: proc(t: ^testing.T) {
	for diagonal in ([?]bool{false, true}) {
		data: level.Level
		player: Player
		room := timed_test_room(t, &data, &player)
		defer level.destroy(&data)
		defer destroy_room(&room)
		result := try_move_player_diagonal(&room, {x = -1, y = -1}) if diagonal else try_move_player(&room, .West)
		testing.expect_value(t, result, Action_Result.Moved)
		// Both at the player's pace: half their first prices (0.8 s, 1 s).
		testing.expect_value(t, player.tactical.action_duration, f32(0.4))
		tactical_tick(&room, 0.4, true, false)
		testing.expect(t, tactical_allows_movement(&room))
		room.enemies[0].position = add_position(player.position, {x = 1, y = 1} if diagonal else {x = 1, y = 0})
		result = try_move_player_diagonal(&room, {x = 1, y = 1}) if diagonal else try_move_player(&room, .East)
		testing.expect_value(t, result, Action_Result.Attacked)
		testing.expect_value(t, player.tactical.action_duration, f32(0.5))
		testing.expect_value(t, player.tactical.action_remaining, f32(0.5))
	}
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
	testing.expect_value(t, player.tactical.action_remaining, TACTICAL_DODGE_SECONDS/TACTICAL_PLAYER_PACE)
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

// The player's pace (tactical_action_cost.odin): the game as it is played
// halves his prices, the bare rules keep the first ones, and behind the eyes
// only the sword's and the bow's steps go at it.
@(test)
test_timed_actions_go_at_the_players_pace :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := timed_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, tactical_player_pace(&room), TACTICAL_PLAYER_PACE)
	testing.expect_value(t, tactical_paced_seconds(&room, TACTICAL_REFOCUS_SECONDS), f32(1))
	// A card's cast: its first price, at the pace.
	tactical_begin_card_cast(&room, tactical_card_time_cost(.Guard))
	testing.expect_value(t, player.tactical.cast_duration, tactical_card_time_cost(.Guard)/TACTICAL_PLAYER_PACE)
	player.tactical.cast_remaining, player.tactical.cast_duration = 0, 0
	// Behind the eyes: the AK's and the fists' prices are their first ones,
	// the sword's and the bow's steps go at the pace (their other prices not).
	room.first_person.active = true
	for weapon in First_Person_Weapon {
		room.first_person.weapon = weapon
		quick := weapon == .Sword || weapon == .Bow
		testing.expectf(t, tactical_player_pace(&room, step = true) == (TACTICAL_PLAYER_PACE if quick else 1), "%v's step", weapon)
		testing.expectf(t, tactical_player_pace(&room) == 1, "%v's other prices", weapon)
	}
	room.first_person.active = false
	// The bare rules.
	player.tactical.config.timed_actions = false
	testing.expect_value(t, tactical_player_pace(&room, step = true), f32(1))
}
