package integration
import activities "../activities"


import "core:testing"
import engine "../engine"
import shooter "../shooter"

@(test)
test_m9_short_fire_click_survives_zero_tick_frame_once :: proc(t: ^testing.T) {
	s: activities.Free_Mode_Session
	activities.begin_free_mode_session(&s, .FPS, true, true)
	defer activities.destroy_free_mode_session(&s)
	activities.step_free_mode_session(&s, 0, {focused = true, control = .Pause})
	activities.step_free_mode_session(&s, 0, {focused = true, fps = {fire_held = true}})
	testing.expect_value(t, s.fps.shots_fired, 0)
	// The mouse is already released when the first fixed step becomes due.
	activities.step_free_mode_session(&s, f32(engine.FIXED_DT), {focused = true})
	testing.expect_value(t, s.fps.shots_fired, 1)
	testing.expect_value(t, s.fps.player.ammo, shooter.MAGAZINE_SIZE-1)
	testing.expect(t, !s.pending.fps.fire_held)
	for _ in 0..<45 { activities.step_free_mode_session(&s, f32(engine.FIXED_DT), {focused = true}) }
	testing.expect_value(t, s.fps.shots_fired, 1)
}

@(test)
test_m9_replay_end_counts_only_executed_catchup_ticks :: proc(t: ^testing.T) {
	s: activities.Free_Mode_Session
	activities.begin_free_mode_session(&s, .Arena, true, true)
	defer activities.destroy_free_mode_session(&s)
	activities.step_free_mode_session(&s, 0, {focused = true, control = .Record})
	activities.step_free_mode_session(&s, f32(engine.FIXED_DT), {focused = true, ring = {move = {1, 0, 0}}})
	activities.step_free_mode_session(&s, 0, {focused = true, control = .Record})
	expected := s.ring
	testing.expect_value(t, len(s.record), 1)
	activities.step_free_mode_session(&s, 0, {focused = true, control = .Replay})
	activities.step_free_mode_session(&s, f32(engine.FIXED_DT*8), {focused = true, ring = {grab = true}})
	testing.expect(t, s.paused && !s.replaying)
	testing.expect_value(t, s.ring, expected)
	testing.expect_value(t, s.clock.ticks, u64(1))
	testing.expect_value(t, s.clock.accumulator, f64(0))
}
