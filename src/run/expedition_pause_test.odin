package run

import "core:testing"
import game "../game"

@(test)
test_expedition_pause_drops_buffered_step_before_resume :: proc(t: ^testing.T) {
	// Only input/session ownership is needed. No map generation, GPU or window.
	e := new(Expedition_Session)
	defer free(e)
	e.rs = new(Roguelike_Session)
	defer free(e.rs)
	rs := e.rs
	rs.room = {phase = .Combat, player = &rs.run_state.player}
	rs.run_state.player.position = {x = 4, y = 4}
	rs.run_state.player.health = 19
	rs.run_state.player.tactical.cast_remaining = 0.4
	rs.run_state.player.tactical.clock_fraction = 0.25
	rs.card_interaction = {selected_card_id = 2, dragged_card_id = 2}
	queued := Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .East}
	_, emitted := route_gameplay_command(&rs.gameplay_buffer, &rs.room, true, queued, true, 1.0/60)
	testing.expect(t, !emitted && rs.gameplay_buffer.has_pending)
	testing.expect(t, rs.gameplay_buffer.walk != 0)
	player_before := rs.run_state.player
	expedition_toggle_pause(e)
	testing.expect(t, e.paused)
	testing.expect_value(t, rs.card_interaction, Card_Interaction_State{})
	testing.expect_value(t, rs.gameplay_buffer, Buffered_Gameplay_Command{})
	// Resume without any new key. The original action may finish normally,
	// but its pre-pause pending step must never reach the command executor.
	expedition_toggle_pause(e)
	testing.expect(t, !e.paused)
	_, emitted = route_gameplay_command(&rs.gameplay_buffer, &rs.room, false, {}, false, 1.0/60)
	testing.expect(t, !emitted, "resuming the expedition replayed a step pressed before pause")
	testing.expect_value(t, rs.run_state.player, player_before)
	testing.expect_value(t, rs.room.phase, game.Room_Phase.Combat)
	// A genuinely new press still uses the unchanged real command lane.
	ready, accepted := route_gameplay_command(&rs.gameplay_buffer, &rs.room, false, queued, true, 1.0/60)
	testing.expect(t, accepted && ready.kind == .Move && ready.direction == .East)
}
