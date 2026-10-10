package tween

import "core:math"
import "core:testing"

@(test)
test_every_curve_starts_at_zero_and_ends_at_one :: proc(t: ^testing.T) {
	for kind in Ease {
		testing.expectf(t, abs(ease(kind, 0)) < 1e-5, "%v(0) = %v", kind, ease(kind, 0))
		testing.expectf(t, abs(ease(kind, 1)-1) < 1e-4, "%v(1) = %v", kind, ease(kind, 1))
		testing.expect(t, ease(kind, -3) == ease(kind, 0))
		testing.expect(t, ease(kind, 9) == ease(kind, 1))
	}
}

@(test)
test_damp_is_frame_rate_independent :: proc(t: ^testing.T) {
	slow := f32(0)
	for _ in 0..<30 {
		slow = damp(slow, f32(10), 4, 1.0/30)
	}
	fast := f32(0)
	for _ in 0..<240 {
		fast = damp(fast, f32(10), 4, 1.0/240)
	}
	testing.expect(t, math.abs(slow-fast) < 0.01)
}

@(test)
test_approach_never_overshoots :: proc(t: ^testing.T) {
	testing.expect_value(t, approach(0, 1, 5), f32(1))
	testing.expect_value(t, approach(3, 1, 0.5), f32(2.5))
}

@(test)
test_tween_reaches_target_on_vectors :: proc(t: ^testing.T) {
	tw := make_tween([2]f32{0, 0}, [2]f32{4, -2}, 0.5, .Linear)
	mid := tween_update(&tw, 0.25)
	testing.expect_value(t, mid, [2]f32{2, -1})
	end := tween_update(&tw, 5)
	testing.expect_value(t, end, [2]f32{4, -2})
	testing.expect(t, tween_done(tw))
}

@(test)
test_remap_maps_ranges :: proc(t: ^testing.T) {
	testing.expect_value(t, remap(5, 0, 10, 100, 200), f32(150))
	testing.expect_value(t, inverse_lerp(2, 2, 7), f32(0))
}
