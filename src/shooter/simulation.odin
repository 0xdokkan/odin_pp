package shooter

import "core:math"
import "../engine"

step :: proc(state: ^State, input: Input) {
	if state == nil || state.phase != .Active { return }
	state.ticks += 1
	state.elapsed = f32(state.ticks)*FIXED_DT
	state.hit_marker = max(0, state.hit_marker-FIXED_DT)
	for &shot in state.shots { shot.remaining = max(0, shot.remaining-FIXED_DT) }
	player := &state.player
	player.cooldown = max(0, player.cooldown-FIXED_DT)
	player.recoil = max(0, player.recoil-FIXED_DT*5)
	player.damage_flash = max(0, player.damage_flash-FIXED_DT)
	player.yaw += finite_look(input.look_yaw)
	if player.yaw > math.PI { player.yaw -= 2*math.PI }
	if player.yaw < -math.PI { player.yaw += 2*math.PI }
	player.pitch = clamp(player.pitch+finite_look(input.look_pitch), -f32(1.3), f32(1.3))
	move_player(state, input)
	if player.reload_remaining > 0 {
		player.reload_remaining = max(0, player.reload_remaining-FIXED_DT)
		if player.reload_remaining == 0 {
			transfer := min(MAGAZINE_SIZE-player.ammo, player.reserve)
			player.ammo += transfer
			player.reserve -= transfer
		}
	}
	if input.reload_pressed && player.reload_remaining == 0 && player.ammo < MAGAZINE_SIZE && player.reserve > 0 {
		player.reload_remaining = RELOAD_DURATION
	}
	if input.fire_held && player.reload_remaining == 0 && player.cooldown == 0 && player.ammo > 0 {
		fire_weapon(state)
	}
	if living_enemies(state) == 0 {
		state.phase = .Won
		return
	}
	for index in 0..<state.enemy_count {
		step_enemy(state, index)
		if state.player.health <= 0 {
			state.phase = .Lost
			return
		}
	}
}

move_player :: proc(state: ^State, input: Input) {
	forward := finite_axis(input.move_forward)
	right := finite_axis(input.move_right)
	length := math.sqrt(forward*forward+right*right)
	if length > 1 { forward /= length; right /= length }
	yaw := state.player.yaw
	// Right is cross(camera forward, world up): looking along +Z puts -X
	// on the right side of a conventional right-handed perspective camera.
	delta := engine.Vec3{math.sin(yaw)*forward-math.cos(yaw)*right, 0,
		math.cos(yaw)*forward+math.sin(yaw)*right}
	body := player_body(state)
	engine.move_character(&state.world, &body, engine.vec_scale(delta, 4.3*FIXED_DT))
	state.player.position = body.position
}

fire_weapon :: proc(state: ^State) {
	player := &state.player
	start := eye_position(state)
	direction := look_direction(player.yaw, player.pitch)
	hit := engine.raycast(&state.world, start, direction, WEAPON_RANGE, {.World, .Actor}, 1)
	end := engine.vec_add(start, engine.vec_scale(direction, WEAPON_RANGE))
	if hit.hit { end = hit.position }
	damaged := false
	if hit.hit && hit.layer == .Actor && hit.id >= 2 && hit.id < u32(state.enemy_count+2) {
		enemy := &state.enemies[int(hit.id)-2]
		if enemy.health > 0 {
			enemy.health = max(0, enemy.health-WEAPON_DAMAGE)
			enemy.damage_flash = 0.15
			damaged = true
			state.hit_marker = 0.2
			if enemy.health == 0 {
				enemy.phase = .Dead
				enemy.phase_remaining = 0
				state.kills += 1
				sync_bodies(state)
			}
		}
	}
	state.shots[0] = {start = start, end = end, remaining = 0.10, hit = damaged}
	player.ammo -= 1
	player.cooldown = WEAPON_COOLDOWN
	player.recoil = 1
	state.shots_fired += 1
}

enemy_eye :: proc(enemy: ^Enemy) -> engine.Vec3 {
	return engine.vec_add(enemy.position, {0, 1.35, 0})
}

step_enemy :: proc(state: ^State, index: int) {
	enemy := &state.enemies[index]
	if enemy.health <= 0 { return }
	enemy.damage_flash = max(0, enemy.damage_flash-FIXED_DT)
	switch enemy.phase {
	case .Dead:
		return
	case .Recovery:
		enemy.phase_remaining = max(0, enemy.phase_remaining-FIXED_DT)
		if enemy.phase_remaining == 0 { enemy.phase = .Hunt }
	case .Windup:
		enemy.phase_remaining = max(0, enemy.phase_remaining-FIXED_DT)
		if enemy.phase_remaining == 0 {
			fire_enemy(state, index)
			enemy.phase = .Recovery
			enemy.phase_remaining = ENEMY_RECOVERY
		}
	case .Hunt:
		to_player := engine.vec_sub(state.player.position, enemy.position)
		enemy.yaw = math.atan2(to_player.x, to_player.z)
		distance := engine.vec_length(to_player)
		start, target := enemy_eye(enemy), eye_position(state)
		to_target := engine.vec_sub(target, start)
		obstacle := engine.raycast(&state.world, start, to_target, engine.vec_length(to_target), {.World})
		if distance <= 11 && !obstacle.hit {
			enemy.phase = .Windup
			enemy.phase_remaining = ENEMY_WINDUP
			// Lock aim when the tell starts. Strafing can dodge the eventual shot.
			enemy.aim_target = target
		} else {
			move_enemy(state, index, to_player)
		}
	}
}

move_enemy :: proc(state: ^State, index: int, direction: engine.Vec3) {
	normal := engine.vec_normalize({direction.x, 0, direction.z})
	body := enemy_body(state, index)
	start := body.position
	delta := engine.vec_scale(normal, 1.8*FIXED_DT)
	result := engine.move_character(&state.world, &body, delta)
	if result.collided && engine.vec_length(engine.vec_sub(body.position, start)) < 0.006 {
		// A deterministic local sidestep gets sentries around the small covers.
		// This is deliberately a local steering rule, not a navigation mesh.
		sign := f32(1) if index%2 == 0 else f32(-1)
		side := engine.Vec3{-normal.z*sign, 0, normal.x*sign}
		engine.move_character(&state.world, &body, engine.vec_scale(side, 1.8*FIXED_DT))
	}
	state.enemies[index].position = body.position
}

fire_enemy :: proc(state: ^State, index: int) {
	enemy := &state.enemies[index]
	start := enemy_eye(enemy)
	direction := engine.vec_normalize(engine.vec_sub(enemy.aim_target, start))
	hit := engine.raycast(&state.world, start, direction, WEAPON_RANGE, {.World, .Actor}, u32(index+2))
	end := engine.vec_add(start, engine.vec_scale(direction, WEAPON_RANGE))
	if hit.hit { end = hit.position }
	damaged := hit.hit && hit.layer == .Actor && hit.id == 1
	if damaged {
		state.player.health = max(0, state.player.health-ENEMY_DAMAGE)
		state.player.damage_flash = 0.25
	}
	state.shots[index+1] = {start = start, end = end, remaining = 0.15, enemy = true, hit = damaged}
}
