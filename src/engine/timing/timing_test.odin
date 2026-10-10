package timing

import "core:testing"
import "core:math"

@(test)
test_nonfinite_delta_does_not_poison_later_ticks :: proc(t: ^testing.T) {
	fs := fixed_step(100)
	testing.expect_value(t, fixed_step_advance(&fs, 0.005), 0)
	for invalid in ([?]f32{math.nan_f32(), math.inf_f32(1), math.inf_f32(-1)}) {
		testing.expect_value(t, fixed_step_advance(&fs, invalid), 0)
		testing.expect(t, !math.is_nan(fs.alpha) && !math.is_inf(fs.alpha))
	}
	testing.expect_value(t, fixed_step_advance(&fs, 0.005), 1)
}

@(test)
test_pause_discards_fraction_without_erasing_completed_ticks :: proc(t: ^testing.T) {
	fs := fixed_step(100)
	testing.expect_value(t, fixed_step_advance(&fs, 0.015), 1)
	testing.expect_value(t, fixed_step_advance(&fs, 20, paused = true), 0)
	testing.expect_value(t, fs.total_steps, u64(1))
	testing.expect_value(t, fs.alpha, f32(0))
	testing.expect_value(t, fixed_step_advance(&fs, 0.006), 0)
	testing.expect_value(t, fs.dropped_seconds, f64(0))
	fixed_step_advance(&fs, 2)
	testing.expect(t, fs.dropped_seconds > 1.9)
}

@(test)
test_fixed_step_counts_whole_steps_and_keeps_remainder :: proc(t: ^testing.T) {
	fs := fixed_step(100)
	testing.expect_value(t, fixed_step_advance(&fs, 0.025), 2)
	testing.expect(t, fs.alpha > 0.49 && fs.alpha < 0.51)
	testing.expect_value(t, fixed_step_advance(&fs, 0.005), 1)
	testing.expect_value(t, fs.total_steps, u64(3))
}

@(test)
test_fixed_step_caps_catch_up :: proc(t: ^testing.T) {
	fs := fixed_step(120, 4)
	testing.expect_value(t, fixed_step_advance(&fs, 10), 4)
	testing.expect_value(t, fs.accumulator, f32(0))
	testing.expect_value(t, fixed_step_advance(&fs, -1), 0)
}

@(test)
test_timer_fires_once_when_crossing_zero :: proc(t: ^testing.T) {
	tm := timer(0.3)
	testing.expect(t, !timer_tick(&tm, 0.2))
	testing.expect(t, timer_tick(&tm, 0.2))
	testing.expect(t, !timer_tick(&tm, 0.2))
	testing.expect(t, timer_done(tm))
	testing.expect_value(t, timer_progress(tm), f32(1))
}

@(test)
test_cooldown_restarts_on_use :: proc(t: ^testing.T) {
	cd := Timer{duration = 1}
	testing.expect(t, cooldown_try(&cd))
	testing.expect(t, !cooldown_try(&cd))
	timer_tick(&cd, 1)
	testing.expect(t, cooldown_try(&cd))
}
