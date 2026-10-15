package game

import "core:testing"
import level "../level"

// Runs the current window out, then lets its recovery or stun pass with the
// clock; returns how long the stun was (0: an ordinary recovery).
run_out_tactical_window :: proc(t: ^testing.T, room: ^Room) -> (stun: f32) {
	s := &room.player.tactical
	s.remaining = 0
	testing.expect(t, tactical_expire_window(room))
	if s.phase == .Stunned { stun = s.remaining }
	for _ in 0..<400 {
		if s.phase == .Decision { return }
		tactical_tick(room, 0.25, true, false)
		drain_tactical_test_pulse(t, room, false)
	}
	testing.expect(t, false, "the window never came back")
	return
}

@(test)
test_tactical_window_shrinks_to_a_stun_that_grows :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	s := &player.tactical
	s.config.shrinking_window = true
	s.config.timer_seconds, s.budget, s.remaining = 3, 3, 3
	// Each window that runs out leaves the next a second shorter.
	testing.expect_value(t, run_out_tactical_window(t, &room), f32(0))
	testing.expect(t, s.budget == 2 && s.remaining == 2)
	testing.expect_value(t, run_out_tactical_window(t, &room), f32(0))
	testing.expect_value(t, s.budget, 1)
	// Not a second left: stunned, with only cards to play.
	s.remaining = 0
	testing.expect(t, tactical_expire_window(&room))
	testing.expect(t, tactical_is_stunned(&room) && !tactical_is_recovering(&room))
	testing.expect_value(t, s.remaining, f32(1))
	testing.expect(t, tactical_allows_cards(&room) && !tactical_allows_action(&room) && !tactical_allows_movement(&room))
	testing.expect_value(t, try_move_player(&room, .West), Action_Result.Invalid_Phase)
	for _ in 0..<400 {
		if s.phase == .Decision { break }
		tactical_tick(&room, 0.25, true, false)
		drain_tactical_test_pulse(t, &room, false)
	}
	// Then the whole window again; the room's next stun lasts a second longer.
	testing.expect(t, s.budget == 3 && s.remaining == 3)
	testing.expect_value(t, run_out_tactical_window(t, &room), f32(0))
	testing.expect_value(t, run_out_tactical_window(t, &room), f32(0))
	testing.expect_value(t, run_out_tactical_window(t, &room), f32(2))
	testing.expect_value(t, s.budget, 3)
	// A new room starts afresh.
	s.cards_toward_second = 4
	begin_tactical_room(&room)
	testing.expect(t, s.budget == 3 && s.stuns == 0 && s.cards_toward_second == 0 && s.won_seconds == 0)
}

// Six cards forgive the next drop and win a second, never past the window the
// room started with: at 18 they bring the next window to 19.
@(test)
test_tactical_six_cards_win_the_window_back :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	s := &player.tactical
	s.config.shrinking_window = true
	run_out_tactical_window(t, &room)
	run_out_tactical_window(t, &room)
	testing.expect_value(t, s.budget, 18)
	for _ in 0..<5 { tactical_count_card(&room) }
	testing.expect(t, s.cards_toward_second == 5 && s.won_seconds == 0)
	tactical_count_card(&room)
	testing.expect(t, s.cards_toward_second == 0 && s.won_seconds == 1)
	run_out_tactical_window(t, &room)
	testing.expect_value(t, s.budget, 19)
	testing.expect_value(t, s.won_seconds, 0)
	for _ in 0..<12 { tactical_count_card(&room) }
	run_out_tactical_window(t, &room)
	testing.expect_value(t, s.budget, 20)
	// Without cards the drop comes back.
	run_out_tactical_window(t, &room)
	testing.expect_value(t, s.budget, 19)
	// The bare rules keep every window whole.
	s.config.shrinking_window = false
	run_out_tactical_window(t, &room)
	testing.expect_value(t, s.budget, 20)
}

@(test)
test_tactical_stunned_player_has_no_defence :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	enemy := &room.enemies[0]
	enemy.intent = {kind = .Attack, origin = enemy.position, threatened_cell_count = 1}
	enemy.intent.threatened_cells[0] = player.position
	testing.expect(t, offer_defense_qte(&room, enemy))
	room.qte = {}
	player.tactical.phase = .Stunned
	player.tactical.remaining = 1
	testing.expect(t, !offer_defense_qte(&room, enemy))
	testing.expect_value(t, room.qte.kind, QTE_Kind.None)
}
