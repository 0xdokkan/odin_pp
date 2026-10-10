package main

import "core:testing"
import engine "engine"
import render "render"

@(test)
test_m9_fps_center_resume_click_starts_without_firing :: proc(t: ^testing.T) {
	renderer := render.Renderer{canvas_width = 960, canvas_height = 540}
	for tools in ([2]bool{false, true}) {
		s: M9_Session
		begin_m9_session(&s, .FPS, true, tools)
		defer destroy_m9_session(&s)
		testing.expect(t, s.paused)
		// Follow the actual pointer hit test instead of supplying Pause directly.
		// The visible central prompt previously had no clickable control here.
		control := render.m9_control_at_point(&renderer, m9_view(&s), {480, 240})
		testing.expect_value(t, control, render.M9_Control.Resume_FPS)
		step_m9_session(&s, f32(engine.FIXED_DT), {focused = true, control = control})
		testing.expect(t, !s.paused)
		testing.expect_value(t, s.clock.ticks, u64(0))
		testing.expect_value(t, s.fps.shots_fired, 0)
		testing.expect_value(t, s.pending, M9_Tick_Input{})
		step_m9_session(&s, f32(engine.FIXED_DT), {focused = true})
		testing.expect_value(t, s.clock.ticks, u64(1))
		testing.expect_value(t, s.fps.shots_fired, 0)
	}
}

@(test)
test_m9_fps_center_resume_is_inert_outside_active_paused_session :: proc(t: ^testing.T) {
	renderer := render.Renderer{canvas_width = 960, canvas_height = 540}
	s: M9_Session
	begin_m9_session(&s, .FPS, true, true)
	defer destroy_m9_session(&s)
	ready := m9_view(&s)
	testing.expect(t, render.m9_control_enabled(ready, .Resume_FPS))
	for case_index in 0..<6 {
		inactive := ready
		switch case_index {
		case 0: inactive.kind = .Arena
		case 1: inactive.kind = .Ring
		case 2: inactive.paused = false
		case 3: inactive.fps_active = false
		case 4: inactive.replaying = true
		case 5: inactive.captured = true
		}
		testing.expect(t, !render.m9_control_enabled(inactive, .Resume_FPS))
		testing.expect_value(t, render.m9_control_at_point(&renderer, inactive, {480, 240}), render.M9_Control.None)
	}
	// A stale/double delivery cannot toggle a running FPS back into pause.
	step_m9_session(&s, 0, {focused = true, control = .Resume_FPS})
	step_m9_session(&s, 0, {focused = true, control = .Resume_FPS})
	testing.expect(t, !s.paused)
	for terminal in ([2]bool{false, true}) {
		begin_m9_session(&s, .FPS, true, true)
		s.fps.phase = .Won if terminal else .Lost
		step_m9_session(&s, f32(engine.FIXED_DT), {focused = true, control = .Resume_FPS})
		testing.expect(t, s.paused)
		testing.expect_value(t, s.clock.ticks, u64(0))
	}
}
