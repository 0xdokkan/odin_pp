package engine

import "core:math"

FIXED_DT :: f64(1.0/60.0)
MAX_CATCHUP_STEPS :: 8
Fixed_Clock :: struct {
	accumulator: f64,
	ticks: u64,
	dropped_seconds: f64,
}

// Menus/cinematics discard fractional time too: resuming cannot release queued ticks.
// Long stalls are bounded and observable; no unbounded catch-up loop is possible.
advance_clock :: proc(clock: ^Fixed_Clock, elapsed: f64, paused: bool = false) -> int {
	if clock == nil { return 0 }
	if paused { clock.accumulator = 0; return 0 }
	if math.is_nan(elapsed) || math.is_inf(elapsed) || elapsed < 0 { return 0 }
	if math.is_nan(clock.accumulator) || math.is_inf(clock.accumulator) || clock.accumulator < 0 {
		clock.accumulator = 0
	}
	accepted := min(elapsed, FIXED_DT*f64(MAX_CATCHUP_STEPS))
	clock.dropped_seconds += elapsed-accepted
	clock.accumulator += accepted
	steps := min(MAX_CATCHUP_STEPS, int((clock.accumulator+1e-10)/FIXED_DT))
	clock.accumulator = max(0, clock.accumulator-f64(steps)*FIXED_DT)
	clock.ticks += u64(steps)
	return steps
}

clock_alpha :: proc(clock: ^Fixed_Clock) -> f32 {
	if clock == nil || math.is_nan(clock.accumulator) || math.is_inf(clock.accumulator) { return 0 }
	return f32(clamp(clock.accumulator/FIXED_DT, 0, 1))
}
