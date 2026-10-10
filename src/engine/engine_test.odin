package engine

import "core:math"
import "core:testing"

test_body :: proc(position: Vec3 = {}, id: u32 = 1) -> Body {
	return {position = position, radius = 0.4, height = 1.8, id = id, layer = .Actor}
}
near :: proc(a, b: f32, epsilon: f32 = 0.001) -> bool { return math.abs(a-b) <= epsilon }

@(test)
test_clock_framerate_partitions_and_pause_discard :: proc(t: ^testing.T) {
	rates := [?]int{30, 60, 144, 240}
	for rate in rates {
		clock: Fixed_Clock
		steps := 0
		for _ in 0..<rate*3 { steps += advance_clock(&clock, 1/f64(rate)) }
		testing.expect_value(t, steps, 180)
		testing.expect_value(t, clock.ticks, 180)
		testing.expect(t, clock_alpha(&clock) < 0.0001)
	}
	clock: Fixed_Clock
	testing.expect_value(t, advance_clock(&clock, FIXED_DT*0.75), 0)
	testing.expect_value(t, advance_clock(&clock, 8, true), 0)
	testing.expect_value(t, advance_clock(&clock, FIXED_DT*0.5), 0)
	testing.expect_value(t, advance_clock(&clock, FIXED_DT*0.5), 1)
	testing.expect_value(t, clock.ticks, 1)
}

@(test)
test_clock_stalls_and_invalid_delta_are_bounded :: proc(t: ^testing.T) {
	clock: Fixed_Clock
	testing.expect_value(t, advance_clock(&clock, 10), MAX_CATCHUP_STEPS)
	testing.expect(t, clock.dropped_seconds > 9.8)
	testing.expect_value(t, advance_clock(&clock, 0), 0)
	testing.expect_value(t, advance_clock(&clock, -1), 0)
	testing.expect_value(t, advance_clock(&clock, transmute(f64)u64(0x7ff8000000000000)), 0)
	testing.expect_value(t, advance_clock(&clock, transmute(f64)u64(0x7ff0000000000000)), 0)
	testing.expect_value(t, clock.ticks, u64(MAX_CATCHUP_STEPS))
}

@(test)
test_high_speed_wall_sweep_and_slide :: proc(t: ^testing.T) {
	world: World
	testing.expect(t, add_solid(&world, {{2, 0, -5}, {2.05, 3, 5}}, 99))
	body := test_body()
	testing.expect(t, add_actor(&world, body))
	result := move_character(&world, &body, {100, 0, 3})
	testing.expect(t, result.valid && result.collided)
	testing.expect(t, near(body.position.x, 1.6))
	testing.expect(t, near(body.position.z, 3))
	testing.expect(t, !body_overlaps(&world, body))
	testing.expect_value(t, result.hit_id, 99)
	testing.expect_value(t, world.actors[0].position, body.position)
	// A new press moving away from the contact must be accepted immediately.
	result = move_character(&world, &body, {-1, 0, 0})
	testing.expect(t, result.valid && !result.collided)
	testing.expect(t, near(body.position.x, 0.6))
}

@(test)
test_inside_corner_slide_is_bounded :: proc(t: ^testing.T) {
	world: World
	add_solid(&world, {{2, 0, -5}, {3, 3, 3}}, 1)
	add_solid(&world, {{-5, 0, 2}, {3, 3, 3}}, 2)
	body := test_body()
	for _ in 0..<60 {
		result := move_character(&world, &body, {5, 0, 5})
		testing.expect(t, result.valid)
		testing.expect(t, !body_overlaps(&world, body))
	}
	testing.expect(t, near(body.position.x, 1.6) && near(body.position.z, 1.6))
	result := move_character(&world, &body, {-2, 0, -2})
	testing.expect(t, result.valid && !result.collided)
	testing.expect(t, body.position.x < 0 && body.position.z < 0)
}

@(test)
test_rounded_corner_does_not_use_square_padding :: proc(t: ^testing.T) {
	world: World
	add_solid(&world, {{0, 0, 0}, {1, 2, 1}})
	body := test_body({-0.35, 0, -0.35})
	// Both coordinates lie inside a square expansion but are outside the round corner.
	testing.expect(t, !body_overlaps(&world, body))
	result := move_character(&world, &body, {-0.1, 0, 0.05})
	testing.expect(t, result.valid && !result.collided && !result.depenetrated)
	testing.expect(t, near(body.position.x, -0.45) && near(body.position.z, -0.3))
}

@(test)
test_actor_sweep_blocks_tunneling_and_removal_releases_path :: proc(t: ^testing.T) {
	world: World
	body := test_body()
	other := test_body({3, 0, 0}, 2)
	add_actor(&world, body)
	add_actor(&world, other)
	result := move_character(&world, &body, {100, 0, 0})
	testing.expect(t, result.collided && result.hit_id == 2)
	testing.expect(t, near(body.position.x, 2.2))
	testing.expect_value(t, world.actors[1], other)
	testing.expect(t, remove_actor(&world, 2))
	testing.expect(t, !remove_actor(&world, 2))
	result = move_character(&world, &body, {10, 0, 0})
	testing.expect(t, !result.collided && near(body.position.x, 12.2))
}

@(test)
test_long_sweep_preserves_small_actor_radius :: proc(t: ^testing.T) {
	world: World
	add_actor(&world, test_body({}, 2))
	body := test_body({-10000, 0, 0})
	result := move_character(&world, &body, {20000, 0, 0})
	testing.expect(t, result.collided)
	testing.expect(t, body.position.x <= -0.79 && body.position.x >= -0.81)
	testing.expect(t, !body_overlaps(&world, body))
	hit := raycast(&world, {-10000, 1, 0}, {1, 0, 0}, 20000)
	testing.expect(t, hit.hit && near(hit.distance, 9999.6, 0.01))
}

@(test)
test_initial_overlap_resolves_and_impossible_corridor_does_not_escape :: proc(t: ^testing.T) {
	world: World
	add_solid(&world, {{0, 0, -2}, {1, 2, 2}})
	body := test_body({-0.2, 0, 0})
	result := move_character(&world, &body, {})
	testing.expect(t, result.valid && result.depenetrated && !result.blocked)
	testing.expect(t, !body_overlaps(&world, body))
	testing.expect(t, body.position.x <= -0.4)
	// A gap smaller than the diameter is unresolved; preserve the original state.
	world = {}
	add_solid(&world, {{-4, 0, -4}, {-0.1, 3, 4}})
	add_solid(&world, {{0.1, 0, -4}, {4, 3, 4}})
	body = test_body()
	original := body
	result = move_character(&world, &body, {0, 0, 1})
	testing.expect(t, result.blocked)
	testing.expect_value(t, body, original)
}

@(test)
test_actor_overlap_and_vertical_filtering :: proc(t: ^testing.T) {
	world: World
	body := test_body()
	add_actor(&world, body)
	add_actor(&world, test_body({}, 2))
	result := move_character(&world, &body, {})
	testing.expect(t, result.valid && result.depenetrated)
	testing.expect(t, !body_overlaps(&world, body))
	world = {}
	add_solid(&world, {{-1, 2.5, -1}, {1, 3, 1}})
	add_actor(&world, test_body({0, 3, 0}, 2))
	body = test_body({-2, 0, 0})
	result = move_character(&world, &body, {4, 0, 0})
	testing.expect(t, !result.collided && near(body.position.x, 2))
}

@(test)
test_invalid_move_never_mutates_body :: proc(t: ^testing.T) {
	world: World
	body := test_body()
	original := body
	deltas := [?]Vec3{{transmute(f32)u32(0x7fc00000), 0, 0}, {transmute(f32)u32(0x7f800000), 0, 0}, {0, 1, 0}}
	for delta in deltas {
		result := move_character(&world, &body, delta)
		testing.expect(t, !result.valid)
		testing.expect_value(t, body, original)
	}
	world.solid_count = MAX_SOLIDS+1
	testing.expect(t, !move_character(&world, &body, {1, 0, 0}).valid)
	testing.expect_value(t, body, original)
}

@(test)
test_layers_and_triggers_do_not_block_character :: proc(t: ^testing.T) {
	world: World
	add_trigger(&world, {{1, 0, -1}, {3, 2, 1}}, 7)
	body := test_body()
	result := move_character(&world, &body, {2, 0, 0})
	testing.expect(t, !result.collided && body_in_trigger(body, world.triggers[0]))
	testing.expect(t, !raycast(&world, {0, 1, 0}, {1, 0, 0}, 10).hit)
	testing.expect_value(t, raycast(&world, {0, 1, 0}, {1, 0, 0}, 10, {.Trigger}).id, 7)
	add_solid(&world, {{4, 0, -1}, {5, 2, 1}})
	result = move_character(&world, &body, {10, 0, 0}, {.Actor})
	testing.expect(t, !result.collided && near(body.position.x, 12))
}

@(test)
test_raycast_nearest_wall_occludes_actor_and_honors_masks :: proc(t: ^testing.T) {
	world: World
	add_solid(&world, {{2, 0, -1}, {2.1, 3, 1}}, 99)
	add_actor(&world, test_body({4, 0, 0}, 2))
	hit := raycast(&world, {0, 1, 0}, {2, 0, 0}, 10)
	testing.expect(t, hit.hit && hit.id == 99 && hit.layer == .World)
	testing.expect(t, near(hit.distance, 2))
	hit = raycast(&world, {0, 1, 0}, {2, 0, 0}, 10, {.Actor})
	testing.expect(t, hit.hit && hit.id == 2 && near(hit.distance, 3.6))
	testing.expect(t, !raycast(&world, {0, 1, 0}, {1, 0, 0}, 10, {.Actor}, 2).hit)
	testing.expect(t, !raycast(&world, {0, 1, 0}, {1, 0, 0}, 1).hit)
}

@(test)
test_capsule_caps_parallel_rays_and_start_inside :: proc(t: ^testing.T) {
	body := test_body()
	hit := ray_capsule({0, 4, 0}, {0, -1, 0}, body, 10)
	testing.expect(t, hit.hit && near(hit.distance, 2.2))
	testing.expect(t, near(hit.normal.y, 1))
	hit = ray_capsule({0, 1, 0}, {1, 0, 0}, body, 10)
	testing.expect(t, hit.hit && hit.distance == 0)
	testing.expect(t, !ray_capsule({0.5, 4, 0}, {0, -1, 0}, body, 10).hit)
	testing.expect(t, !ray_capsule({0, 4, 0}, {}, body, 10).hit)
	box := AABB{{-1, 0, -1}, {1, 2, 1}}
	testing.expect(t, ray_aabb({0, 1, 0}, {0, 0, 1}, box, 10).hit)
	testing.expect(t, !ray_aabb({2, 1, 0}, {0, 0, 1}, box, 10).hit)
}

@(test)
test_authored_levels_validate_and_invalid_spawns_fail :: proc(t: ^testing.T) {
	levels := [?]Level{create_ring_level(), create_courtyard_level(), create_gallery_level()}
	for &level in levels { testing.expect(t, validate_level(&level)) }
	bad := create_ring_level()
	bad.spawns[0] = {4.4, 0, 0}
	testing.expect(t, !validate_level(&bad))
	bad = create_ring_level()
	bad.spawns[1] = bad.spawns[0]
	testing.expect(t, !validate_level(&bad))
	bad = create_gallery_level()
	bad.world.solids[0].bounds.min.x = transmute(f32)u32(0x7fc00000)
	testing.expect(t, !validate_level(&bad))
}

@(test)
test_world_capacities_and_actor_identity :: proc(t: ^testing.T) {
	world: World
	for index in 0..<MAX_ACTORS { testing.expect(t, add_actor(&world, test_body({f32(index), 0, 0}, u32(index+1)))) }
	testing.expect(t, !add_actor(&world, test_body({}, 99)))
	testing.expect(t, !add_actor(&world, test_body({}, 1)))
	for _ in 0..<MAX_SOLIDS { testing.expect(t, add_solid(&world, {{0, 0, 0}, {1, 1, 1}})) }
	testing.expect(t, !add_solid(&world, {{0, 0, 0}, {1, 1, 1}}))
	testing.expect(t, !add_solid(&world, {{1, 0, 0}, {0, 1, 1}}))
	for _ in 0..<MAX_TRIGGERS { testing.expect(t, add_trigger(&world, {{0, 0, 0}, {1, 1, 1}}, 1)) }
	testing.expect(t, !add_trigger(&world, {{0, 0, 0}, {1, 1, 1}}, 1))
}

@(test)
test_controller_replay_is_deterministic_across_render_rates :: proc(t: ^testing.T) {
	positions: [2]Vec3
	rates := [2]int{30, 144}
	for rate, index in rates {
		level := create_ring_level()
		body := test_body()
		clock: Fixed_Clock
		for _ in 0..<rate*2 {
			steps := advance_clock(&clock, 1/f64(rate))
			for _ in 0..<steps { move_character(&level.world, &body, {f32(FIXED_DT)*4, 0, f32(FIXED_DT)*2}) }
		}
		positions[index] = body.position
	}
	testing.expect_value(t, positions[0], positions[1])
	testing.expect(t, near(positions[0].x, 4.1) && near(positions[0].z, 4))
}
