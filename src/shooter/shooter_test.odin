package shooter

import "core:math"
import "core:testing"
import "../engine"

quiet_fixture :: proc(count: int = 1) -> State {
	state := create()
	state.world = {}
	state.player.position = {0, 0, -5}
	state.enemy_count = count
	for &enemy, index in state.enemies[:count] {
		enemy = {position = {0, 0, f32(index)*3}, health = 30, phase = .Recovery,
			phase_remaining = 1000}
	}
	sync_bodies(&state)
	return state
}

@(test)
test_fps_world_cover_occludes_hitscan_and_only_nearest_enemy_is_hit :: proc(t: ^testing.T) {
	state := quiet_fixture(2)
	engine.add_solid(&state.world, {{-1, 0, -3}, {1, 3, -2}}, 100)
	step(&state, {fire_held = true})
	testing.expect_value(t, state.enemies[0].health, 30)
	testing.expect_value(t, state.enemies[1].health, 30)
	testing.expect(t, state.shots[0].end.z < -2)
	testing.expect(t, !state.shots[0].hit)
	state.world.solid_count = 0
	for _ in 0..<15 { step(&state, {fire_held = true}) }
	testing.expect_value(t, state.enemies[0].health, 18)
	testing.expect_value(t, state.enemies[1].health, 30)
	testing.expect(t, state.shots[0].hit && state.hit_marker > 0)
}

@(test)
test_fps_pitch_matters_and_dead_bodies_do_not_block_later_shots :: proc(t: ^testing.T) {
	state := quiet_fixture(2)
	step(&state, {look_pitch = 1, fire_held = true})
	testing.expect_value(t, state.enemies[0].health, 30)
	state.player.pitch = 0
	state.enemies[0].health = WEAPON_DAMAGE
	for _ in 0..<15 { step(&state, {fire_held = true}) }
	testing.expect_value(t, state.enemies[0].phase, Enemy_Phase.Dead)
	testing.expect_value(t, state.kills, 1)
	testing.expect_value(t, state.world.actor_count, 2)
	for _ in 0..<15 { step(&state, {fire_held = true}) }
	testing.expect_value(t, state.enemies[1].health, 18)
}

@(test)
test_fps_held_fire_obeys_magazine_cooldown_and_reload_is_finite :: proc(t: ^testing.T) {
	state := quiet_fixture()
	state.player.yaw = math.PI/2
	for _ in 0..<180 { step(&state, {fire_held = true}) }
	testing.expect_value(t, state.shots_fired, MAGAZINE_SIZE)
	testing.expect_value(t, state.player.ammo, 0)
	step(&state, {reload_pressed = true, fire_held = true})
	testing.expect(t, state.player.reload_remaining > 0)
	for _ in 0..<60 { step(&state, {fire_held = true}) }
	testing.expect_value(t, state.shots_fired, MAGAZINE_SIZE)
	for _ in 0..<15 { step(&state, {}) }
	testing.expect_value(t, state.player.ammo, MAGAZINE_SIZE)
	testing.expect_value(t, state.player.reserve, 24)
	step(&state, {fire_held = true})
	testing.expect_value(t, state.shots_fired, MAGAZINE_SIZE+1)
	for _ in 0..<10 { step(&state, {fire_held = true}) }
	testing.expect_value(t, state.shots_fired, MAGAZINE_SIZE+1)
	// A repeated reload edge while the animation is running cannot restart it.
	state.player.cooldown = 0
	step(&state, {reload_pressed = true})
	for _ in 0..<80 { step(&state, {reload_pressed = true}) }
	testing.expect_value(t, state.player.ammo, MAGAZINE_SIZE)
	testing.expect_value(t, state.player.reserve, 23)
	testing.expect_value(t, state.player.reload_remaining, f32(0))
}

@(test)
test_fps_input_is_bounded_and_movement_hits_walls_and_actors :: proc(t: ^testing.T) {
	state := quiet_fixture()
	engine.add_solid(&state.world, {{-5, 0, -2}, {5, 3, -1.95}}, 100)
	for _ in 0..<120 { step(&state, {move_forward = 1e20}) }
	testing.expect(t, state.player.position.z <= -2-PLAYER_RADIUS+0.001)
	before := state.player.position
	step(&state, {move_forward = math.nan_f32(), move_right = math.inf_f32(1),
		look_yaw = math.nan_f32(), look_pitch = math.inf_f32(-1)})
	testing.expect_value(t, state.player.position, before)
	testing.expect(t, engine.finite_vec(state.player.position))
	state.world.solid_count = 0
	for _ in 0..<120 { step(&state, {move_forward = 1}) }
	testing.expect(t, state.player.position.z <= -PLAYER_RADIUS-ENEMY_RADIUS+0.002)
	state = quiet_fixture()
	for _ in 0..<60 { step(&state, {move_forward = 1, move_right = 1}) }
	distance := engine.vec_length(engine.vec_sub(state.player.position, {0, 0, -5}))
	testing.expect(t, math.abs(distance-4.3) < 0.005, "diagonals must not increase movement speed")
}

@(test)
test_fps_enemy_windup_locks_aim_and_cover_blocks_enemy_fire :: proc(t: ^testing.T) {
	state := quiet_fixture()
	state.enemies[0].phase = .Hunt
	step(&state, {})
	testing.expect_value(t, state.enemies[0].phase, Enemy_Phase.Windup)
	locked := state.enemies[0].aim_target
	for _ in 0..<55 { step(&state, {move_right = 1}) }
	testing.expect_value(t, state.enemies[0].aim_target, locked)
	testing.expect_value(t, state.player.health, 100)
	testing.expect_value(t, state.enemies[0].phase, Enemy_Phase.Recovery)
	state = quiet_fixture()
	state.enemies[0].phase = .Hunt
	step(&state, {})
	engine.add_solid(&state.world, {{-1, 0, -3}, {1, 3, -2}}, 100)
	for _ in 0..<55 { step(&state, {}) }
	testing.expect_value(t, state.player.health, 100)
	state = quiet_fixture()
	state.enemies[0].phase = .Hunt
	step(&state, {})
	for _ in 0..<55 { step(&state, {}) }
	testing.expect_value(t, state.player.health, 100-ENEMY_DAMAGE)
}

@(test)
test_fps_win_loss_reset_and_level_selection_are_deterministic :: proc(t: ^testing.T) {
	state := quiet_fixture()
	for _ in 0..<32 { step(&state, {fire_held = true}) }
	testing.expect_value(t, state.phase, Phase.Won)
	testing.expect_value(t, state.kills, 1)
	won_ticks := state.ticks
	step(&state, {fire_held = true, move_forward = 1})
	testing.expect_value(t, state.ticks, won_ticks)
	reset(&state, 1)
	testing.expect_value(t, state.phase, Phase.Active)
	testing.expect_value(t, state.level_index, 1)
	testing.expect_value(t, state.player.health, 100)
	testing.expect_value(t, state.player.ammo, MAGAZINE_SIZE)
	testing.expect_value(t, state.world.actor_count, MAX_ENEMIES+1)
	other := create(1)
	for tick in 0..<240 {
		input := Input{move_right = 0.3, move_forward = 0.2, look_yaw = 0.001,
			fire_held = tick%30 < 4, reload_pressed = tick == 150}
		step(&state, input)
		step(&other, input)
	}
	testing.expect_value(t, state, other)
	state = quiet_fixture()
	state.player.health = ENEMY_DAMAGE
	state.enemies[0].phase = .Hunt
	for _ in 0..<60 { step(&state, {}) }
	testing.expect_value(t, state.phase, Phase.Lost)
	testing.expect_value(t, state.player.health, 0)
	reset(&state, -1)
	testing.expect_value(t, state.level_index, 1)
}

@(test)
test_fps_both_rooms_complete_through_public_controls :: proc(t: ^testing.T) {
	for level in 0..<level_count() {
		state := create(level)
		for _ in 0..<1200 {
			if state.phase != .Active { break }
			input := Input{fire_held = true, reload_pressed = state.player.ammo == 0}
			for enemy in state.enemies[:state.enemy_count] {
				if enemy.health <= 0 { continue }
				target := engine.vec_add(enemy.position, {0, 1.2, 0})
				direction := engine.vec_sub(target, eye_position(&state))
				desired_yaw := math.atan2(direction.x, direction.z)
				desired_pitch := math.atan2(direction.y,
					math.sqrt(direction.x*direction.x+direction.z*direction.z))
				input.look_yaw = desired_yaw-state.player.yaw
				input.look_pitch = desired_pitch-state.player.pitch
				break
			}
			step(&state, input)
		}
		testing.expect(t, state.phase == .Won, "a complete wave must be reachable without state edits")
		testing.expect_value(t, state.kills, MAX_ENEMIES)
		testing.expect(t, state.shots_fired >= 9 && state.shots_fired <= MAGAZINE_SIZE+30)
		testing.expect(t, state.player.reserve < 30, "a real reload is required to finish the wave")
	}
}

@(test)
test_fps_strafe_right_matches_camera_handedness_at_every_heading :: proc(t: ^testing.T) {
	for yaw in ([4]f32{0,math.PI/2,math.PI,-math.PI/2}) {
		state:=quiet_fixture()
		state.player.yaw=yaw
		before:=state.player.position
		forward:=look_direction(yaw,0)
		// cross(forward, {0,1,0}) is the camera's screen-right direction.
		screen_right:=engine.Vec3{-forward.z,0,forward.x}
		step(&state,{move_right=1})
		delta:=engine.vec_sub(state.player.position,before)
		testing.expect(t,engine.vec_dot(delta,screen_right)>0.071)
		testing.expect(t,abs(engine.vec_dot(delta,forward))<0.00001)
	}
}
