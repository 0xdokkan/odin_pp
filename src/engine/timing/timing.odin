// Frame-rate independent time keeping: a fixed-step accumulator for
// deterministic simulations, plus small countdown helpers.
package timing

// Largest frame delta accepted, so a debugger pause or a window drag does not
// make a simulation try to catch up on seconds of missed steps.
MAX_FRAME_DELTA :: f32(0.25)

// Runs a simulation at a constant step whatever the display rate. The same
// sequence of steps always produces the same result, so fixed-step games are
// reproducible from their input log alone.
Fixed_Step :: struct {
	step:        f32,
	max_steps:   int,
	accumulator: f32,
	// Fraction of a step left over after the last advance, for interpolation.
	alpha:       f32,
	total_steps: u64,
}

fixed_step :: proc(hz: f32, max_steps := 8) -> Fixed_Step {
	assert(hz > 0 && max_steps > 0)
	return Fixed_Step{step = 1 / hz, max_steps = max_steps}
}

// Adds a frame and returns how many simulation steps to run now. Steps beyond
// `max_steps` are dropped instead of accumulating (no spiral of death).
fixed_step_advance :: proc(fs: ^Fixed_Step, frame_dt: f32) -> int {
	assert(fs != nil && fs.step > 0)
	dt := clamp(frame_dt, 0, MAX_FRAME_DELTA)
	fs.accumulator += dt
	steps := 0
	for fs.accumulator >= fs.step && steps < fs.max_steps {
		fs.accumulator -= fs.step
		steps += 1
	}
	if steps == fs.max_steps && fs.accumulator >= fs.step {
		fs.accumulator = 0
	}
	fs.alpha = fs.accumulator / fs.step
	fs.total_steps += u64(steps)
	return steps
}

fixed_step_reset :: proc(fs: ^Fixed_Step) {
	fs.accumulator = 0
	fs.alpha = 0
	fs.total_steps = 0
}

// Counts down from `duration`; `done` once it reaches zero.
Timer :: struct {
	duration:  f32,
	remaining: f32,
}

timer :: proc(duration: f32) -> Timer {
	return Timer{duration = duration, remaining = duration}
}

timer_restart :: proc(t: ^Timer) {
	t.remaining = t.duration
}

// Returns true only on the step that crosses zero.
timer_tick :: proc(t: ^Timer, dt: f32) -> bool {
	if t.remaining <= 0 {
		return false
	}
	t.remaining -= dt
	if t.remaining <= 0 {
		t.remaining = 0
		return true
	}
	return false
}

timer_done :: proc(t: Timer) -> bool {
	return t.remaining <= 0
}

// 0 at start, 1 when done. A zero-length timer is always complete.
timer_progress :: proc(t: Timer) -> f32 {
	if t.duration <= 0 {
		return 1
	}
	return clamp(1 - t.remaining/t.duration, 0, 1)
}

// A cooldown is ready when its timer is done; triggering restarts it.
cooldown_try :: proc(t: ^Timer) -> bool {
	if !timer_done(t^) {
		return false
	}
	timer_restart(t)
	return true
}
