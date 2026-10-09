package fx

import "core:testing"
import rng "../rng"

@(test)
test_particles_expire_and_reuse_slots :: proc(t: ^testing.T) {
	p: Particles(8)
	r := rng.create(1)
	emit(&p, BURST, {}, 20, &r)
	testing.expect_value(t, p.count, 8)
	for _ in 0..<120 {
		update(&p, 1.0/60)
	}
	testing.expect_value(t, p.count, 0)
}

@(test)
test_emission_is_deterministic_for_a_seed :: proc(t: ^testing.T) {
	a, b: Particles(16)
	ra := rng.create(4)
	rb := rng.create(4)
	emit(&a, SPARKS, {10, 10, 0}, 10, &ra)
	emit(&b, SPARKS, {10, 10, 0}, 10, &rb)
	for i in 0..<10 {
		testing.expect_value(t, a.items[i].velocity, b.items[i].velocity)
	}
}

@(test)
test_3d_cone_respects_direction :: proc(t: ^testing.T) {
	p: Particles(64)
	r := rng.create(8)
	e := BURST
	e.three_d = true
	e.direction = {0, 1, 0}
	e.spread = 0.3
	emit(&p, e, {}, 64, &r)
	for i in 0..<p.count {
		testing.expect(t, p.items[i].velocity.y > 0)
	}
}

@(test)
test_hit_stop_freezes_then_releases_leftover :: proc(t: ^testing.T) {
	h: Hit_Stop
	hit_stop(&h, 0.05)
	testing.expect_value(t, hit_stop_filter(&h, 0.03), f32(0))
	left := hit_stop_filter(&h, 0.03)
	testing.expect(t, abs(left-0.01) < 1e-5)
	testing.expect_value(t, hit_stop_filter(&h, 0.02), f32(0.02))
}

@(test)
test_popups_rise_and_expire :: proc(t: ^testing.T) {
	p: Popups(2)
	popup(&p, {0, 100}, "+1", {}, 0.5)
	popup(&p, {0, 100}, "+2", {}, 1)
	popup(&p, {0, 100}, "+3", {}, 1)
	testing.expect_value(t, p.count, 2)
	testing.expect_value(t, p.items[0].text, "+2")
	popups_update(&p, 0.6)
	testing.expect(t, p.items[0].position.y < 100)
	popups_update(&p, 0.6)
	testing.expect_value(t, p.count, 0)
}
