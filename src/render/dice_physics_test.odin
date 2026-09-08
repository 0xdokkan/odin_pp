package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"

@(test)
test_dice_physics_collision_impulses_change_translation_and_rotation :: proc(t: ^testing.T) {
	bodies := [2]Dice_Physics_Body{
		{position = {-0.48, 2, 0}, orientation = rl.Quaternion(1), velocity = {2, 0, 0}},
		{position = {0.48, 2.32, 0.12}, orientation = rl.QuaternionFromEuler(0.1, 0.12, 0), velocity = {-2, 0, 0}},
	}
	pairs, _ := dice_physics_step(bodies[:])
	testing.expect(t, pairs > 0)
	testing.expect(t, bodies[0].velocity.x < 1 && bodies[1].velocity.x > -1,
		"cubes must exchange a physical collision impulse")
	testing.expect(t, rl.Vector3Length(bodies[0].angular_velocity)+rl.Vector3Length(bodies[1].angular_velocity) > 0.1,
		"off-center impacts must impart angular momentum")
	testing.expect(t, abs(bodies[0].velocity.x+bodies[1].velocity.x) < 0.0001)
}

@(test)
test_dice_physics_plane_bounces_and_friction_dissipates_motion :: proc(t: ^testing.T) {
	bodies := [1]Dice_Physics_Body{{position = {0, 0.51, 0}, orientation = rl.Quaternion(1), velocity = {3, -5, 1}}}
	_, ground := dice_physics_step(bodies[:])
	testing.expect(t, ground)
	testing.expect(t, bodies[0].velocity.y > 0, "a falling die must bounce through an upward contact impulse")
	testing.expect(t, abs(bodies[0].velocity.x) < 3 && abs(bodies[0].velocity.z) < 1)
	testing.expect(t, bodies[0].position.y-dice_physics_support_height(&bodies[0]) > -0.001)
}

@(test)
test_dice_physics_floor_kick_requires_a_fresh_falling_contact :: proc(t: ^testing.T) {
	body := Dice_Physics_Body{orientation = rl.Quaternion(1), velocity = {2, 3, 1}, angular_velocity = {0.2, 0.4, -0.1}}
	dice_physics_apply_floor_kick(&body, true, -5)
	testing.expect_value(t, body.floor_kicks, 1)
	testing.expect_value(t, body.velocity, rl.Vector3{2, 12, 1})
	testing.expect(t, rl.Vector3Length(body.angular_velocity) > 1 && rl.Vector3Length(body.angular_velocity) <= 4)
	first_spin := body.angular_velocity
	// A constrained die can keep touching the plane while other contacts push it
	// down. Persistent contact must never spend its second impulse or add energy.
	body.velocity.y = 0.2
	for _ in 0..<120 { dice_physics_apply_floor_kick(&body, true, -5) }
	testing.expect_value(t, body.floor_kicks, 1)
	testing.expect_value(t, body.velocity.y, f32(0.2))
	testing.expect_value(t, body.angular_velocity, first_spin)
	dice_physics_apply_floor_kick(&body, false, 0)
	dice_physics_apply_floor_kick(&body, true, -0.5)
	testing.expect(t, body.floor_kicks == 1, "a slow graze is not a new falling impact")
	dice_physics_apply_floor_kick(&body, false, -3)
	dice_physics_apply_floor_kick(&body, true, -3)
	testing.expect_value(t, body.floor_kicks, 2)
	testing.expect_value(t, body.velocity.y, f32(9))
	second_spin := body.angular_velocity
	testing.expect(t, second_spin != first_spin && rl.Vector3Length(second_spin) <= 4.00001)
	body.velocity.y = 1.25
	dice_physics_apply_floor_kick(&body, false, -8)
	dice_physics_apply_floor_kick(&body, true, -8)
	testing.expect_value(t, body.floor_kicks, 2)
	testing.expect(t, body.velocity.y == 1.25, "later bounces use the ordinary solver only")
	testing.expect_value(t, body.angular_velocity, second_spin)
}

@(test)
test_dice_physics_two_arcade_impulses_then_natural_dissipation :: proc(t: ^testing.T) {
	bodies := dice_physics_initial_bodies(1, 123, 7, true)
	previous_kicks := 0
	natural_landing := false
	for _ in 1..<DICE_THROW_FRAME_COUNT {
		_, ground := dice_physics_step(bodies[:1])
		body := &bodies[0]
		if body.floor_kicks != previous_kicks {
			testing.expect(t, ground && body.floor_kicks == previous_kicks+1)
			testing.expect(t, body.velocity.y >= (12 if previous_kicks == 0 else 9))
			previous_kicks = body.floor_kicks
		} else if ground && body.floor_kicks == 2 && body.velocity.y > 1 && body.velocity.y < 9 {
			natural_landing = true
		}
		if body.asleep { break }
	}
	testing.expect_value(t, previous_kicks, 2)
	testing.expect(t, natural_landing, "after two boosted landings the remaining bounces must dissipate")
	testing.expect(t, bodies[0].asleep && abs(bodies[0].position.y-0.5) < 0.003,
		"the physical throw must still settle within six seconds")
}

@(test)
test_dice_physics_throws_finish_separated_flat_and_settled :: proc(t: ^testing.T) {
	throw := new(Dice_Throw)
	defer free(throw)
	for count in 1..=3 {
		for seed in u64(1)..=64 {
			build_dice_throw(throw, count, seed, 7 if seed%3 == 0 else 14.39 if seed%3 == 1 else 24)
			testing.expectf(t, throw.settled, "not settled count=%v seed=%v", count, seed)
			testing.expectf(t, test_dice_physics_strong_bounces(throw),
				"weak physical rebounds count=%v seed=%v", count, seed)
			testing.expect(t, throw.first_impact_frame > 0 && throw.first_impact_frame < DICE_THROW_FRAME_COUNT-1)
			if count > 1 { testing.expectf(t, throw.contact_count > 0, "no dice collision count=%v seed=%v", count, seed) }
			final := sample_dice_throw(throw, 1)
			for index in 0..<count {
				body := Dice_Physics_Body{position = final.positions[index], orientation = final.orientations[index]}
				axes := dice_physics_axes(&body)
				up := max(abs(axes[0].y), abs(axes[1].y), abs(axes[2].y))
				testing.expectf(t, up > 0.9999, "not flat count=%v seed=%v die=%v up=%v pos=%v", count, seed, index, up, body.position)
				testing.expectf(t, abs(body.position.y-0.5) < 0.003, "not on floor count=%v seed=%v die=%v pos=%v", count, seed, index, body.position)
				testing.expect(t, abs(body.position.x) <= 2.4 && abs(body.position.z) <= 1.2)
				for other in index+1..<count {
					other_body := Dice_Physics_Body{position = final.positions[other], orientation = final.orientations[other]}
					sat := dice_physics_sat(&body, &other_body)
					testing.expectf(t, !sat.overlaps || sat.depth <= 0.002, "overlap count=%v seed=%v pair=%v/%v depth=%v", count, seed, index, other, sat.depth)
				}
			}
		}
	}
}

@(test)
test_dice_physics_bake_and_sampling_are_deterministic_and_frame_rate_independent :: proc(t: ^testing.T) {
	first, second := new(Dice_Throw), new(Dice_Throw)
	defer free(first)
	defer free(second)
	build_dice_throw(first, 3, 0xC001, 12)
	build_dice_throw(second, 3, 0xC001, 12)
	testing.expect_value(t, first^, second^)
	for step in 0..=120 {
		progress := f32(step)/120
		frame := sample_dice_throw(first, progress)
		// Random-order queries and different caller update steps never integrate extra time.
		sample_dice_throw(second, 1-progress)
		testing.expect_value(t, frame, sample_dice_throw(second, progress))
		for index in 0..<first.count {
			length := abs(frame.orientations[index])
			testing.expect(t, abs(length-1) < 0.00001)
			for coordinate in frame.positions[index] { testing.expect(t, !math.is_nan(coordinate) && !math.is_inf(coordinate)) }
		}
	}
	testing.expect_value(t, sample_dice_throw(first, DICE_PHYSICS_IMPACT_PROGRESS), first.frames[first.first_impact_frame])
	testing.expect_value(t, sample_dice_throw(first, DICE_PHYSICS_REVEAL_PROGRESS), sample_dice_throw(first, 1))
	testing.expect_value(t, sample_dice_throw(first, -1), sample_dice_throw(first, 0))
	testing.expect_value(t, sample_dice_throw(first, 2), sample_dice_throw(first, 1))
	build_dice_throw(second, 0, 7)
	testing.expect_value(t, second.count, 0)
}

@(test)
test_dice_physics_sat_rejects_aabb_corner_overlap_without_cube_contact :: proc(t: ^testing.T) {
	a := Dice_Physics_Body{position = {0, 2, 0}, orientation = rl.Quaternion(1)}
	b := Dice_Physics_Body{position = {1.18, 2, 1.18}, orientation = rl.QuaternionFromEuler(0, math.PI/4, 0)}
	testing.expect(t, !dice_physics_sat(&a, &b).overlaps,
		"overlapping AABBs alone must not collide diagonally separated rotated cubes")
	b.position = {0.7, 2, 0.5}
	sat := dice_physics_sat(&a, &b)
	testing.expect(t, sat.overlaps && sat.depth > 0)
	testing.expect(t, abs(rl.Vector3Length(sat.normal)-1) < 0.00001)
}

@(test)
test_dice_physics_failed_attempt_tail_never_contains_a_previous_attempt :: proc(t: ^testing.T) {
	throw := new(Dice_Throw)
	defer free(throw)
	throw.count = 1
	throw.first_impact_frame = 3
	for &frame in throw.frames {
		frame.positions[0] = {999, 999, 999}
		frame.orientations[0] = rl.Quaternion(1)
	}
	for index in 0..=6 { throw.frames[index].positions[0] = {0.2, 4-f32(index)*0.5, 0.3} }
	dice_physics_hold_tail(throw, 6)
	testing.expect_value(t, throw.last_motion_frame, 6)
	for frame in throw.frames[6:] { testing.expect_value(t, frame, throw.frames[6]) }
	for step in 0..=60 {
		frame := sample_dice_throw(throw, f32(step)/60)
		testing.expect(t, frame.positions[0].y >= 1 && frame.positions[0].y <= 4)
	}
	testing.expect_value(t, sample_dice_throw(throw, 1), throw.frames[6])
}

@(test)
test_dice_physics_controlled_final_release_still_collides_and_settles :: proc(t: ^testing.T) {
	heights := [5]f32{7, 12, 14.39, 18, 24}
	throw := new(Dice_Throw)
	defer free(throw)
	for count in 1..=3 {
		for height in heights {
			throw^ = {count = count}
			bodies := dice_physics_initial_bodies(count, 123, height, true)
			throw.frames[0] = dice_physics_frame(bodies[:count])
			contacts := 0
			settled := false
			for frame in 1..<DICE_THROW_FRAME_COUNT {
				pairs, ground := dice_physics_step(bodies[:count])
				contacts += pairs
				throw.contact_count += pairs
				if ground && throw.first_impact_frame == 0 { throw.first_impact_frame = frame }
				throw.frames[frame] = dice_physics_frame(bodies[:count])
				settled = true
				for body in bodies[:count] { settled = settled && body.asleep }
				if settled {
					throw.settled = dice_physics_finish_quiet_tail(throw, bodies[:count], frame)
					break
				}
			}
			testing.expectf(t, settled, "controlled release count=%v height=%v", count, height)
			if count > 1 { testing.expect(t, contacts > 0) }
			for body in bodies[:count] {
				testing.expect(t, abs(body.position.y-0.5) < 0.005)
				testing.expect(t, abs(body.position.x) <= 2.4 && abs(body.position.z) <= 1.2)
			}
			prepare_dice_playback(throw)
			testing.expectf(t, throw.settled && test_dice_physics_strong_bounces(throw) && test_dice_physics_two_visible_bounces(throw),
				"controlled release must visibly rebound twice pool=%v height=%v", count, height)
		}
	}
}

// Measure the lowest of all eight rotated vertices independently of the SAT
// support-radius helper: rocking on an edge is not a visible airborne bounce.
test_dice_physics_clearance :: proc(frame: Dice_Physics_Frame, die: int) -> f32 {
	lowest := f32(math.F32_MAX)
	for x in 0..<2 { for y in 0..<2 { for z in 0..<2 {
		vertex := rl.Vector3{f32(x)-0.5, f32(y)-0.5, f32(z)-0.5}
		world := frame.positions[die]+rl.Vector3RotateByQuaternion(vertex, frame.orientations[die])
		lowest = min(lowest, world.y)
	} } }
	return lowest
}

test_dice_physics_strong_bounces :: proc(throw: ^Dice_Throw) -> bool {
	for die in 0..<throw.count {
		touched_ground, first_rebound := false, false
		peak: f32
		for frame in throw.frames[:throw.last_motion_frame+1] {
			clearance := test_dice_physics_clearance(frame, die)
			if clearance <= 0.012 {
				if touched_ground {
					if first_rebound && peak >= 1.5 { return true }
					if peak >= 3 { first_rebound = true }
				}
				touched_ground, peak = true, 0
			} else if touched_ground { peak = max(peak, clearance) }
		}
	}
	return false
}

test_dice_physics_tumbles_through_both_bounces :: proc(throw: ^Dice_Throw) -> bool {
	for die in 0..<throw.count {
		touched, first_tumbled := false, false
		origin := rl.Quaternion(1)
		peak, minimum_up_dot := f32(0), f32(1)
		for frame in throw.frames[:throw.last_motion_frame+1] {
			clearance := test_dice_physics_clearance(frame, die)
			if clearance <= 0.012 {
				if touched {
					if first_tumbled && peak >= 1.5 && minimum_up_dot < 0.866 { return true }
					if peak >= 3 && minimum_up_dot < 0.866 { first_tumbled = true }
				}
				touched, peak, minimum_up_dot = true, 0, 1
				origin = frame.orientations[die]
			} else if touched {
				peak = max(peak, clearance)
				// Relative orientation rotates world-up only when the actual cube
				// tips on X/Z. A yaw-only spin cannot satisfy either flight.
				relative := frame.orientations[die]*(1/origin)
				up := rl.Vector3RotateByQuaternion({0, 1, 0}, relative)
				minimum_up_dot = min(minimum_up_dot, up.y)
			}
		}
	}
	return false
}

test_dice_physics_dice_tumble_differently :: proc(throw: ^Dice_Throw) -> bool {
	if throw.count < 2 { return true }
	for frame in throw.frames[throw.first_impact_frame:throw.rebound_frames[0]] {
		for a in 0..<throw.count { for b in a+1..<throw.count {
			if test_dice_physics_clearance(frame, a) < 0.1 || test_dice_physics_clearance(frame, b) < 0.1 { continue }
			up_a := rl.Vector3RotateByQuaternion({0, 1, 0}, frame.orientations[a])
			up_b := rl.Vector3RotateByQuaternion({0, 1, 0}, frame.orientations[b])
			if rl.Vector3DotProduct(up_a, up_b) < 0.7 { return true }
		} }
	}
	return false
}

test_dice_physics_two_visible_bounces :: proc(throw: ^Dice_Throw) -> bool {
	// Sample the first 1.3 real seconds at 60 Hz, keeping the approved fall and
	// two rebounds under test independently of the extra settling duration.
	frames: [79]Dice_Physics_Frame
	for &frame, index in frames { frame = sample_dice_throw(throw, f32(index)/(60*DICE_CUE_DURATION)) }
	for die in 0..<throw.count {
		clearance: [79]f32
		for frame, index in frames { clearance[index] = test_dice_physics_clearance(frame, die) }
		first_peak := -1
		for index in 40..<74 {
			height := clearance[index]
			if height <= clearance[index-1] || height < clearance[index+1] { continue }
			if first_peak < 0 {
				if height >= 3 { first_peak = index }
				continue
			}
			if height < 1.5 || index-first_peak < 4 { continue }
			valley := clearance[first_peak]
			for between in first_peak+1..<index { valley = min(valley, clearance[between]) }
			if valley > height*0.6 { continue }
			// A rotating corner can move the clearance apex away from the center's
			// apex. Require both a visible gap and a rise/fall of the center nearby.
			if clearance[index-1] < 0.8 || clearance[index+1] < 0.8 { continue }
			center_peak := frames[index].positions[die].y
			for near in index-3..=index+3 { center_peak = max(center_peak, frames[near].positions[die].y) }
			if center_peak <= frames[index-5].positions[die].y+0.02 ||
			   center_peak <= frames[index+5].positions[die].y+0.02 { continue }
			return true
		}
	}
	return false
}

@(test)
test_dice_physics_arcade_throws_keep_two_visible_bounces_and_real_tumbling :: proc(t: ^testing.T) {
	throw, previous := new(Dice_Throw), new(Dice_Throw)
	defer free(throw)
	defer free(previous)
	seeds := [2]u64{7167, 0x0C1E37E209629011} // second: committed pool 2, faces 4 + 5.
	for seed in seeds { for height in ([3]f32{7, 14.39, 24}) { for count in 1..=3 {
		build_dice_throw(throw, count, seed, height)
		testing.expectf(t, throw.settled && test_dice_physics_strong_bounces(throw) && test_dice_physics_two_visible_bounces(throw),
			"missing visible rebound seed=%v height=%v pool=%v", seed, height, count)
		testing.expectf(t, test_dice_physics_tumbles_through_both_bounces(throw),
			"missing X/Z angular excursion in a rebound seed=%v height=%v pool=%v", seed, height, count)
		testing.expectf(t, test_dice_physics_dice_tumble_differently(throw),
			"dice must not share one identical tumbling motion seed=%v height=%v pool=%v", seed, height, count)
		testing.expect(t, throw.attempts < 4, "ordinary fixture must retain the varied tumbling release")
		// Preserve the same 72 ms and 504 ms fall samples when the tail changes.
		first := sample_dice_throw(throw, 0.072/DICE_CUE_DURATION)
		falling := sample_dice_throw(throw, 0.504/DICE_CUE_DURATION)
		first_up := rl.Vector3RotateByQuaternion({0, 1, 0}, first.orientations[0])
		falling_up := rl.Vector3RotateByQuaternion({0, 1, 0}, falling.orientations[0])
		testing.expect(t, rl.Vector3DotProduct(first_up, falling_up) < 0.9,
			"fall must retain a real X/Z tumble, not only a yaw spin")
		testing.expect_value(t, sample_dice_throw(throw, DICE_PHYSICS_REVEAL_PROGRESS), sample_dice_throw(throw, 1))
		if seed == seeds[0] && count == 2 && height == 14.39 { previous^ = throw^ }
		if seed == seeds[1] && count == 2 && height == 14.39 {
			testing.expect(t, throw.frames[0] != previous.frames[0] && sample_dice_throw(throw, 1) != sample_dice_throw(previous, 1),
				"different cosmetic seeds must retain distinct release and resting poses")
		}
	} } }
}

@(test)
test_dice_physics_intermediate_letterbox_height_settles_after_bounded_retries :: proc(t: ^testing.T) {
	throw := new(Dice_Throw)
	defer free(throw)
	for count in 1..=3 {
		build_dice_throw(throw, count, 7167, 14.39)
		testing.expectf(t, throw.settled, "letterbox regression pool=%v attempts=%v", count, throw.attempts)
		testing.expect(t, throw.attempts <= 4)
		if count > 1 { testing.expect(t, throw.contact_count > 0) }
		final := sample_dice_throw(throw, 1)
		for index in 0..<count { testing.expect(t, abs(final.positions[index].y-0.5) < 0.003) }
	}
}
