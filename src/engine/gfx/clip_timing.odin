package gfx

// Variable-duration drawings use milliseconds in both paper atlases. Keep
// loop normalization in their adapters: modulo and repeated subtraction have
// different floating-point boundary behaviour.
@(private)
clip_duration_seconds :: proc(durations: []u16, first: i32 = 0) -> f64 {
	total: f64
	for index in max(first, 0)..<i32(len(durations)) { total += f64(durations[index]) }
	return total/1000
}

// Scan a non-empty clip. Exact boundaries advance to the next drawing; a
// completed scan holds the last one. Loop adapters discard `finished`.
@(private)
clip_frame_at_ms :: proc(durations: []u16, elapsed_ms: f64, first: i32 = 0) -> (frame: i32, finished: bool) {
	t := elapsed_ms
	count := i32(len(durations))
	for index in clamp(first, 0, count-1)..<count {
		duration := f64(durations[index])
		if t < duration { return index, false }
		t -= duration
	}
	return count-1, true
}
