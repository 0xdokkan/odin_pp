package fight

import "core:math"
import "core:testing"
import engine "../engine"

close_pair :: proc(state: ^State, distance: f32 = 1) {
	state.fighters[0].position = {-distance/2, 0, 0}
	state.fighters[1].position = {distance/2, 0, 0}
	for &fighter in state.fighters { fighter.previous = fighter.position }
	sync_fighters(state)
}

steps :: proc(state: ^State, count: int, input: Input = {}) {
	for _ in 0..<count { tick(state, input) }
}

@(test)
test_ring_attack_startup_active_recovery_and_one_hit_per_move :: proc(t: ^testing.T) {
	state := begin(false, true)
	close_pair(&state)
	tick(&state, {jab = true})
	testing.expect_value(t, state.fighters[0].action, Action.Jab)
	steps(&state, 6)
	testing.expect_value(t, state.fighters[1].health, i32(12))
	_, active := hitbox(&state, 0)
	testing.expect(t, !active)
	tick(&state, {})
	testing.expect_value(t, state.fighters[1].health, i32(11))
	testing.expect_value(t, state.fighters[0].action_tick, 8)
	steps(&state, 60)
	testing.expect_value(t, state.fighters[1].health, i32(11))
	testing.expect_value(t, state.landed_hits[0], 1)
	testing.expect_value(t, state.fighters[0].action, Action.Idle)
	testing.expect_value(t, state.fighters[1].action, Action.Idle)
}

@(test)
test_ring_guard_is_frontal_and_does_not_destroy_hurtboxes :: proc(t: ^testing.T) {
	state := begin(false, true)
	close_pair(&state)
	testing.expect(t, start_action(&state, 1, .Heavy, {}))
	steps(&state, state.moves[.Heavy].startup, {guard = true})
	testing.expect_value(t, state.fighters[0].health, i32(8))
	testing.expect_value(t, state.blocked_hits[1], 1)
	testing.expect(t, hurtbox(&state, 0).radius > 0)
	state = begin(false, true)
	close_pair(&state)
	state.fighters[0].action = .Guard
	state.fighters[0].facing = {-1, 0, 0}
	testing.expect(t, start_action(&state, 1, .Heavy, {}))
	steps(&state, state.moves[.Heavy].startup, {guard = true})
	testing.expect_value(t, state.fighters[0].health, i32(6))
	testing.expect_value(t, state.landed_hits[1], 1)
}

@(test)
test_ring_dodge_only_invulnerable_during_defined_active_window :: proc(t: ^testing.T) {
	state := begin(false, true)
	tick(&state, {dodge = true, move = {0, 0, 1}})
	testing.expect(t, !invulnerable(&state.fighters[0]))
	steps(&state, 2)
	testing.expect(t, invulnerable(&state.fighters[0]))
	steps(&state, 12)
	testing.expect(t, !invulnerable(&state.fighters[0]))
	testing.expect(t, state.fighters[0].position.z > 1)
	steps(&state, 20)
	testing.expect_value(t, state.fighters[0].action, Action.Idle)
}

@(test)
test_ring_hitstop_stops_combat_but_retains_a_cancel_press :: proc(t: ^testing.T) {
	state := begin(false, true)
	close_pair(&state)
	tick(&state, {jab = true})
	steps(&state, 7)
	testing.expect(t, state.hitstop_ticks > 0)
	before_tick := state.combat_ticks
	before_action_tick := state.fighters[0].action_tick
	tick(&state, {heavy = true})
	testing.expect_value(t, state.combat_ticks, before_tick)
	testing.expect_value(t, state.fighters[0].action_tick, before_action_tick)
	testing.expect_value(t, state.fighters[0].buffered_action, Action.Heavy)
	for _ in 0..<20 {
		if state.fighters[0].action == .Heavy { break }
		tick(&state, {})
	}
	testing.expect_value(t, state.fighters[0].action, Action.Heavy)
	testing.expect_value(t, state.fighters[0].move_serial, u32(2))
}

@(test)
test_ring_whiff_cannot_cancel_and_press_buffer_expires :: proc(t: ^testing.T) {
	state := begin(false, true)
	tick(&state, {jab = true})
	steps(&state, 12)
	tick(&state, {heavy = true})
	steps(&state, 40)
	testing.expect_value(t, state.fighters[0].move_serial, u32(1))
	testing.expect_value(t, state.fighters[0].action, Action.Idle)
	testing.expect_value(t, state.landed_hits[0], 0)
}

@(test)
test_ring_throw_has_four_poses_one_impact_and_wall_safe_landing :: proc(t: ^testing.T) {
	state := begin(false, true)
	state.fighters[0].position = {2.8, 0, 0}
	state.fighters[1].position = {3.8, 0, 0}
	sync_fighters(&state)
	tick(&state, {grab = true})
	steps(&state, 9)
	testing.expect(t, state.throw_active)
	testing.expect_value(t, throw_pose(&state), 0)
	player_position := state.fighters[0].position
	seen: [4]bool
	seen[0] = true
	for _ in 0..<120 {
		if !state.throw_active { break }
		seen[throw_pose(&state)] = true
		tick(&state, {move = {-1, 0, 1}, jab = true, heavy = true, dodge = true})
		testing.expect_value(t, state.fighters[0].position, player_position)
	}
	for pose_seen in seen { testing.expect(t, pose_seen) }
	testing.expect(t, !state.throw_active)
	testing.expect_value(t, state.successful_throws, 1)
	testing.expect_value(t, state.fighters[1].health, i32(9))
	testing.expect(t, state.fighters[1].position.x <= RING_EXTENT-BODY_RADIUS+0.0001)
	testing.expect_value(t, state.fighters[1].position.y, f32(0))
	testing.expect_value(t, state.fighters[0].action, Action.Idle)
	testing.expect_value(t, state.fighters[1].action, Action.Hurt)
	steps(&state, 50)
	testing.expect_value(t, state.successful_throws, 1)
	testing.expect_value(t, state.fighters[0].move_serial, u32(1))
}

@(test)
test_ring_throw_ko_settles_only_after_all_four_poses :: proc(t: ^testing.T) {
	state := begin(false, true)
	close_pair(&state)
	state.fighters[1].health = 3
	tick(&state, {grab = true})
	steps(&state, 9)
	for _ in 0..<100 {
		if state.throw_landed { break }
		tick(&state, {})
	}
	testing.expect(t, state.throw_landed)
	testing.expect_value(t, state.result, Result.Active)
	testing.expect_value(t, state.fighters[1].health, i32(0))
	steps(&state, 50)
	testing.expect_value(t, state.result, Result.Won)
	testing.expect(t, !state.throw_active)
	before := state
	tick(&state, {jab = true})
	testing.expect_value(t, state, before)
}

@(test)
test_ring_continuous_motion_collides_with_fighter_and_all_walls :: proc(t: ^testing.T) {
	state := begin(true, true)
	steps(&state, 180, {move = {1, 0, 0}})
	testing.expect(t, state.fighters[0].position.x < state.fighters[1].position.x)
	testing.expect(t, distance_squared(state.fighters[0].position, state.fighters[1].position) >= 4*BODY_RADIUS*BODY_RADIUS-0.001)
	directions := [4]engine.Vec3{{0, 0, 1}, {1, 0, 0}, {0, 0, -1}, {-1, 0, 0}}
	for direction in directions {
		steps(&state, 300, {move = direction})
		position := state.fighters[0].position
		testing.expect(t, abs(position.x) <= RING_EXTENT-BODY_RADIUS+0.001)
		testing.expect(t, abs(position.z) <= RING_EXTENT-BODY_RADIUS+0.001)
	}
}

@(test)
test_ring_fixed_clock_matches_at_30_60_144_frames_per_second :: proc(t: ^testing.T) {
	baseline: State
	frame_rates := [3]int{30, 60, 144}
	for fps, index in frame_rates {
		state := begin(true, true)
		clock: engine.Fixed_Clock
		for _ in 0..<fps*3 {
			step_count := engine.advance_clock(&clock, 1/f64(fps))
			for _ in 0..<step_count {
				tick(&state, {move = {0, 0, 1}, dodge = state.ticks == 60, jab = state.ticks == 120})
			}
		}
		testing.expect_value(t, state.ticks, u64(180))
		if index == 0 { baseline = state }
		else { testing.expect_value(t, state, baseline) }
	}
}

@(test)
test_ring_move_tuning_is_validated_and_inflight_move_is_snapshot :: proc(t: ^testing.T) {
	state := begin(false, true)
	for action in Action { if is_move(action) { testing.expect(t, move_valid(state.moves[action])) } }
	close_pair(&state)
	tick(&state, {jab = true})
	new_move := state.moves[.Jab]
	new_move.damage = 5
	testing.expect(t, set_move(&state, .Jab, new_move))
	steps(&state, 7)
	testing.expect_value(t, state.fighters[1].health, i32(11))
	before := state.moves[.Jab]
	new_move.radius = transmute(f32)u32(0x7fc00000)
	testing.expect(t, !set_move(&state, .Jab, new_move))
	testing.expect_value(t, state.moves[.Jab], before)
	testing.expect(t, !set_move(&state, .Hurt, before))
	reset(&state)
	testing.expect_value(t, state.moves[.Jab].damage, i32(5))
	testing.expect_value(t, state.fighters[1].health, i32(12))
}

@(test)
test_ring_invalid_movement_is_ignored_and_diagonal_speed_is_bounded :: proc(t: ^testing.T) {
	state := begin(false, true)
	before := state.fighters[0].position
	tick(&state, {move = {transmute(f32)u32(0x7fc00000), 0, 1}})
	testing.expect_value(t, state.fighters[0].position, before)
	tick(&state, {move = {max(f32), 0, max(f32)}})
	testing.expect_value(t, state.fighters[0].position, before)
	tick(&state, {move = {1, 0, 1}})
	moved := math.sqrt(distance_squared(state.fighters[0].position, before))
	testing.expect(t, abs(moved-PLAYER_SPEED*FIXED_DT) < 0.00001)
}

@(test)
test_ring_ai_is_telegraphed_lethal_and_practice_never_settles :: proc(t: ^testing.T) {
	state := begin()
	steps(&state, 45)
	testing.expect_value(t, state.fighters[0].health, i32(8))
	steps(&state, 3600)
	testing.expect_value(t, state.result, Result.Lost)
	practice := begin(true)
	steps(&practice, 3600)
	testing.expect_value(t, practice.result, Result.Active)
	testing.expect(t, practice.fighters[0].health > 0)
	testing.expect(t, practice.landed_hits[1] > 4)
}

@(test)
test_ring_player_can_defeat_ai_with_approach_and_timed_jabs :: proc(t: ^testing.T) {
	state := begin()
	for _ in 0..<1800 {
		if state.result != .Active { break }
		distance := distance_squared(state.fighters[0].position, state.fighters[1].position)
		direction := engine.vec_sub(state.fighters[1].position, state.fighters[0].position)
		tick(&state, {move = direction, jab = distance < 1.2*1.2 && state.fighters[0].action == .Idle})
	}
	testing.expect_value(t, state.result, Result.Won)
	testing.expect(t, state.fighters[0].health > 0)
	testing.expect_value(t, state.fighters[1].health, i32(0))
}

@(test)
test_ring_zero_startup_single_frame_move_does_not_skip_contact :: proc(t: ^testing.T) {
	state := begin(false, true)
	close_pair(&state)
	move := state.moves[.Heavy]
	move.startup, move.active = 0, 1
	testing.expect(t, set_move(&state, .Heavy, move))
	tick(&state, {heavy = true})
	testing.expect_value(t, state.fighters[1].health, i32(10))
	steps(&state, 60)
	testing.expect_value(t, state.landed_hits[0], 1)
}

@(test)
test_ring_strikes_cannot_hit_through_thin_walls_even_with_tuned_reach :: proc(t: ^testing.T) {
	for action in ([2]Action{.Jab, .Heavy}) {
		state := begin(false, true)
		close_pair(&state, 2.4 if action == .Heavy else 1)
		if action == .Heavy {
			move := state.moves[.Heavy]
			move.reach = 1.8
			testing.expect(t, set_move(&state, .Heavy, move))
		}
		testing.expect(t, engine.add_solid(&state.world, {{-0.04,0,-1}, {0.04,2,1}}, 201))
		tick(&state, {jab = action == .Jab, heavy = action == .Heavy})
		steps(&state, 70)
		testing.expect_value(t, state.fighters[1].health, i32(12))
		testing.expect_value(t, state.landed_hits[0], 0)
		testing.expect_value(t, state.fighters[0].action, Action.Idle)
	}
}

@(test)
test_ring_free_strike_beside_a_wall_still_connects :: proc(t: ^testing.T) {
	state := begin(false, true)
	close_pair(&state)
	for &fighter in state.fighters { fighter.position.z = 1.5; fighter.previous = fighter.position }
	sync_fighters(&state)
	testing.expect(t, engine.add_solid(&state.world, {{-0.04,0,-1}, {0.04,2,1}}, 201))
	tick(&state, {jab = true})
	steps(&state, 7)
	testing.expect_value(t, state.fighters[1].health, i32(11))
	testing.expect_value(t, state.landed_hits[0], 1)
}

@(test)
test_ring_grab_cannot_lock_a_victim_through_a_wall :: proc(t: ^testing.T) {
	state := begin(false, true)
	close_pair(&state)
	testing.expect(t, engine.add_solid(&state.world, {{-0.04,0,-1}, {0.04,2,1}}, 201))
	tick(&state, {grab = true})
	steps(&state, 70)
	testing.expect(t, !state.throw_active)
	testing.expect_value(t, state.successful_throws, 0)
	testing.expect_value(t, state.fighters[1].health, i32(12))
	testing.expect_value(t, state.fighters[1].action, Action.Idle)
}

@(test)
test_ring_throw_stops_before_pillar_instead_of_cutting_a_sliding_corner :: proc(t: ^testing.T) {
	state := begin(false, true)
	state.fighters[0].position = {-1.3,0,-0.7}
	state.fighters[1].position = {-0.5,0,-0.1}
	sync_fighters(&state)
	testing.expect(t, engine.add_solid(&state.world, {{0.4,0,0.2}, {1.1,3,1.2}}, 201))
	tick(&state, {grab = true})
	steps(&state, 9)
	testing.expect(t, state.throw_active)
	testing.expect(t, state.throw_landing.x < 0.4)
	testing.expect(t, engine.vec_length(engine.vec_sub(state.throw_landing, state.throw_start)) < 0.9,
		"The throw ends at the first impact; it does not slide along the pillar")
	for _ in 0..<100 {
		if !state.throw_active { break }
		tick(&state, {})
		body := collision_body(&state, 1)
		testing.expect(t, !engine.body_overlaps(&state.world, body, {.World}))
	}
	testing.expect_value(t, state.successful_throws, 1)
	testing.expect_value(t, state.fighters[1].health, i32(9))
	testing.expect_value(t, state.fighters[1].position.y, f32(0))
}
