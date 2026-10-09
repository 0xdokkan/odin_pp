package camera

import "core:math"
import "core:testing"

@(test)
test_deadzone_keeps_camera_still_for_small_moves :: proc(t: ^testing.T) {
	c := camera2_create({100, 100})
	c.smoothing = 0
	camera2_update(&c, {110, 105}, {320, 180}, 0.016)
	testing.expect_value(t, c.position, Vec2{100, 100})
	camera2_update(&c, {200, 100}, {320, 180}, 0.016)
	testing.expect_value(t, c.position.x, f32(200-24))
}

@(test)
test_bounds_clamp_and_center_small_levels :: proc(t: ^testing.T) {
	c := camera2_create({0, 0})
	c.smoothing = 0
	c.bounds_min = {0, 0}
	c.bounds_max = {1000, 100}
	camera2_update(&c, {-500, 50}, {320, 180}, 0.016)
	testing.expect_value(t, c.position.x, f32(160))
	// Level shorter than the view: centred vertically.
	testing.expect_value(t, c.position.y, f32(50))
}

@(test)
test_shake_decays_to_zero :: proc(t: ^testing.T) {
	s := shake_default()
	add_trauma(&s, 0.8)
	offset, _ := shake_offset(s)
	_ = offset
	for _ in 0..<120 {
		shake_update(&s, 1.0/60)
	}
	testing.expect_value(t, s.trauma, f32(0))
	o, roll := shake_offset(s)
	testing.expect_value(t, o, Vec2{})
	testing.expect_value(t, roll, f32(0))
}

@(test)
test_fps_pitch_is_clamped_and_basis_is_orthogonal :: proc(t: ^testing.T) {
	c := fps_create({0, 1, 0})
	fps_look(&c, {0, -100000})
	testing.expect(t, c.pitch <= 1.45)
	f, r := fps_ground_basis(0.7)
	testing.expect(t, abs(f.x*r.x+f.y*r.y) < 1e-5)
	fwd := fps_forward(fps_create({}, 0))
	testing.expect(t, abs(fwd.z-1) < 1e-5)
}

@(test)
test_orbit_eye_sits_behind_target :: proc(t: ^testing.T) {
	c := orbit_create({0, 0, 0})
	c.pitch = 0
	eye := orbit_eye(c)
	testing.expect(t, eye.z < 0)
	testing.expect(t, abs(math.sqrt(eye.x*eye.x+eye.z*eye.z)-c.distance) < 1e-4)
}
