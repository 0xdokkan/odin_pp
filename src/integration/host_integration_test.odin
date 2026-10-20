package integration
import run_session "../run"

import "core:testing"
import game "../game"


host_run_fixture :: proc(t: ^testing.T) -> ^run_session.Roguelike_Session {
	rs := run_session.roguelike_session_new()
	ok: bool
	rs.run_state, ok = game.create_run(run_session.DEMO_PLAYER_STATS, run_session.DEMO_RUN_CONFIG, 0xC0FFEE)
	testing.expect(t, ok)
	rs.run_created = true
	rs.level_data = create_gameplay_command_test_level(t)
	rs.room, ok = game.create_room(&rs.level_data, &rs.run_state.player, {})
	testing.expect(t, ok)
	rs.room_created = true
	rs.run_state.phase = .In_Room
	node, found := game.current_run_node(&rs.run_state)
	testing.expect(t, found)
	node.kind = .Combat
	rs.iso_renderer.canvas_width, rs.iso_renderer.canvas_height = 960, 540
	return rs
}


@(test)
test_host_suspension_clears_run_input_without_advancing_gameplay :: proc(t: ^testing.T) {
    rs := host_run_fixture(t)
    defer run_session.roguelike_destroy(rs)
    before := rs.run_state.player
    pulse := rs.room.pulse_count
    rs.card_interaction.selected_card_id=42
    rs.gameplay_buffer.chord.active=true
    rs.iso_renderer.frame_clock_valid=true
    rs.iso_renderer.tactical.world_orbit.dragging=true
    rs.iso_renderer.tactical.hologram_orbit.dragging=true
    run_session.roguelike_suspend_input(rs)
    testing.expect(t,rs.card_interaction.selected_card_id==0 && !rs.gameplay_buffer.chord.active)
    testing.expect(t,!rs.iso_renderer.frame_clock_valid && !rs.tactical_controller.was_focused)
    testing.expect(t,!rs.iso_renderer.tactical.world_orbit.dragging && !rs.iso_renderer.tactical.hologram_orbit.dragging)
    testing.expect_value(t,rs.run_state.player,before)
    testing.expect_value(t,rs.room.pulse_count,pulse)
}
