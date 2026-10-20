package integration
import run_session "../run"

import "core:testing"
import input "../engine/input"
import game "../game"

// The same remapped controls feed the discrete walk and its on-beat chord;
// no second query of the physical WASD keys may leak into either path.
@(test)
test_run_snapshot_remapping_preserves_press_vs_held_and_tick_chords :: proc(t: ^testing.T) {
	actions := run_session.default_run_actions()
	testing.expect(t, input.rebind(&actions, .East, 0, input.key(.RIGHT)))
	devices := input.Device_Snapshot{focused = true}
	devices.keys_pressed[.RIGHT] = true
	devices.keys_down[.W] = true
	controls := run_session.map_run_input(&actions, &devices, true)
	command, pressed := run_session.poll_walk_command(.Combat, controls)
	testing.expect(t, pressed && command.kind == .Move)
	testing.expect_value(t, command.direction, game.MOVEMENT_KEY_DIRECTIONS[1])
	testing.expect(t, !run_session.run_down(controls, .East), "a completed tap is still a discrete press")
	offset, diagonal := run_session.beat_chord_offset(command.direction, controls = controls)
	testing.expect(t, diagonal)
	expected := game.add_position(game.direction_offset(command.direction), game.direction_offset(game.MOVEMENT_KEY_DIRECTIONS[0]))
	testing.expect_value(t, offset, expected)
	// Holding the rebound key never manufactures another discrete step.
	devices.keys_pressed[.RIGHT] = false
	devices.keys_down[.RIGHT] = true
	_, pressed = run_session.poll_walk_command(.Combat, run_session.map_run_input(&actions, &devices, true))
	testing.expect(t, !pressed)
	devices.keys_pressed[.D] = true
	_, pressed = run_session.poll_walk_command(.Combat, run_session.map_run_input(&actions, &devices, true))
	testing.expect(t, !pressed, "the old binding must not remain in gameplay")
	// Native mouse controls and focus are retained as values when the host's
	// temporary frame goes away or a modal scene takes ownership.
	devices.buttons_pressed[.LEFT] = true
	devices.mouse_motion = {7, -3}
	controls = run_session.map_run_input(&actions, &devices, false)
	devices = {}
	testing.expect(t, !controls.focused && controls.left_pressed && controls.mouse_motion.x == 7)
}

@(test)
test_run_axis_and_wheel_bindings_emit_discrete_edges_without_resume_actions :: proc(t: ^testing.T) {
	actions := run_session.default_run_actions()
	testing.expect(t, input.bind(&actions, .Refocus, input.pad_axis(.LEFT_X, true)))
	testing.expect(t, input.rebind(&actions, .Map, 0, input.wheel(true)))
	devices := input.Device_Snapshot{focused = true}
	devices.gamepads[0].available = true
	history: run_session.Run_Input_History
	controls := run_session.map_run_input(&actions, &devices, true, &history)
	testing.expect(t, !run_session.run_pressed(controls, .Refocus))
	devices.gamepads[0].axes[.LEFT_X] = 0.75
	controls = run_session.map_run_input(&actions, &devices, true, &history)
	testing.expect(t, run_session.run_pressed(controls, .Refocus) && run_session.run_down(controls, .Refocus))
	controls = run_session.map_run_input(&actions, &devices, true, &history)
	testing.expect(t, !run_session.run_pressed(controls, .Refocus), "holding an axis never repeats a discrete action")
	// A native tap is still an edge even with another binding held down.
	devices.keys_pressed[.F] = true
	controls = run_session.map_run_input(&actions, &devices, true, &history)
	testing.expect(t, run_session.run_pressed(controls, .Refocus))
	devices.keys_pressed[.F] = false
	_ = run_session.map_run_input(&actions, &devices, false, &history)
	controls = run_session.map_run_input(&actions, &devices, true, &history)
	testing.expect(t, !run_session.run_pressed(controls, .Refocus), "a held stick cannot act when focus returns")
	devices.gamepads[0].axes[.LEFT_X] = 0
	controls = run_session.map_run_input(&actions, &devices, true, &history)
	testing.expect(t, .Refocus in controls.actions.released)
	devices.gamepads[0].axes[.LEFT_X] = 0.75
	controls = run_session.map_run_input(&actions, &devices, true, &history)
	testing.expect(t, run_session.run_pressed(controls, .Refocus), "release and cross the threshold to act again")
	for wheel in ([4]f32{1, 1, 0, -1}) {
		devices.wheel = wheel
		controls = run_session.map_run_input(&actions, &devices, true, &history)
		testing.expect_value(t, run_session.run_pressed(controls, .Map), wheel > 0)
	}
}

@(test)
test_run_screen_phase_wins_over_a_stale_map_toggle :: proc(t: ^testing.T) {
	run: game.Run_State
	rows := [?]struct {phase: game.Run_Phase, screen: run_session.Run_Screen}{
		{.Reward, .Reward}, {.Shop, .Shop}, {.Rest, .Special}, {.Event, .Special}, {.Treasure, .Special},
		{.Choose_Path, .Route}, {.Victory, .Route}, {.Defeat, .Defeat},
	}
	for row in rows {
		run.phase = row.phase
		testing.expect_value(t, run_session.run_screen(&run, false), row.screen)
		testing.expect_value(t, run_session.run_screen(&run, true), row.screen)
	}
	run.phase = .In_Room
	testing.expect_value(t, run_session.run_screen(&run, false), run_session.Run_Screen.Board)
	testing.expect_value(t, run_session.run_screen(&run, true), run_session.Run_Screen.Route)
	// Treasure/reward relic choices take the menu until their transaction
	// clears the choice; the underlying phase then becomes visible at once.
	run.phase, run.relic_reward.origin = .Treasure, .Treasure
	testing.expect_value(t, run_session.run_screen(&run, true), run_session.Run_Screen.Relic)
	run.relic_reward = {}
	testing.expect_value(t, run_session.run_screen(&run, true), run_session.Run_Screen.Special)
}
