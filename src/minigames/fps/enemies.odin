package fps

import "core:math"
import physics "../../engine/physics"
import rng "../../engine/rng"

Enemy_Params :: struct {
	hp:        f32,
	speed:     f32,
	height:    f32, // hit box height
	hover:     f32, // hit box lift above the floor
	sight:     f32,
	reach:     f32, // distance that starts an attack
	windup:    f32, // telegraph before the attack lands
	recover:   f32,
	damage:    f32,
	knockback: f32,
	score:     int,
}

// Ghouls shamble in and claw after a long, readable wind-up; wraiths are
// fast and lunge from mid range; cultists keep their distance and throw slow
// bolts that can be dodged or shot down.
enemy_params :: proc "contextless" (kind: Enemy_Kind) -> Enemy_Params {
	switch kind {
	case .Ghoul:
		return {hp = 60, speed = 2.6, height = 1.6, hover = 0, sight = 12, reach = 1.6, windup = 0.55,
			recover = 0.75, damage = 15, knockback = 2.5, score = 100}
	case .Wraith:
		return {hp = 35, speed = 3.7, height = 1.35, hover = 0.35, sight = 15, reach = 5.5, windup = 0.45,
			recover = 0.9, damage = 12, knockback = 4.5, score = 150}
	case .Cultist:
		return {hp = 45, speed = 2.3, height = 1.7, hover = 0, sight = 17, reach = 15, windup = 0.8,
			recover = 1.6, damage = 13, knockback = 3, score = 200}
	}
	return {}
}

enemy_kind_name :: proc "contextless" (kind: Enemy_Kind) -> string {
	switch kind {
	case .Ghoul:
		return "Ghoul"
	case .Wraith:
		return "Spettro"
	case .Cultist:
		return "Cultista"
	}
	return ""
}

enemy_feet :: proc "contextless" (e: Enemy) -> Vec3 {
	return physics.body3_feet(e.body)
}

enemy_eye :: proc "contextless" (e: Enemy) -> Vec3 {
	params := enemy_params(e.kind)
	return enemy_feet(e) + Vec3{0, params.hover + params.height*0.85, 0}
}

LUNGE_SPEED :: f32(9.5)
LUNGE_TIME :: f32(0.38)
PROJECTILE_SPEED :: f32(7)
PROJECTILE_LIFE :: f32(4.5)
// Cultists are comfortable between these distances from the player.
CULTIST_NEAR :: f32(5)
CULTIST_FAR :: f32(9)

enemy_alert :: proc(w: ^World, index: int, quiet := false) {
	e := &w.enemies[index]
	if e.state == .Dead || e.alerted {
		return
	}
	e.alerted = true
	e.lost_time = 0
	if e.state == .Idle {
		e.state = .Chase
		e.state_time = 0
	}
	// A short grace before the first attack, so being noticed is a warning.
	e.attack_cd = max(e.attack_cd, 0.4)
	if !quiet {
		emit_event(w, Event{kind = .Enemy_Alert, position = enemy_eye(e^), enemy = e.kind, index = index})
	}
}

damage_enemy :: proc(w: ^World, index: int, amount: f32, dir: Vec3, point: Vec3) {
	e := &w.enemies[index]
	if e.state == .Dead {
		return
	}
	params := enemy_params(e.kind)
	e.hp -= amount
	e.hurt_time = 0.14
	e.push += physics.normalize2(Vec2{dir.x, dir.z}) * params.knockback
	enemy_alert(w, index, quiet = true)
	if e.hp > 0 {
		// A wraith hit while winding up is knocked out of its lunge.
		if e.kind == .Wraith && e.state == .Windup {
			set_state(e, .Recover)
		}
		emit_event(w, Event{kind = .Enemy_Hit, position = point, normal = dir, enemy = e.kind, index = index})
		return
	}
	e.hp = 0
	set_state(e, .Dead)
	w.stats.kills += 1
	w.stats.kill_score += params.score
	feet := enemy_feet(e^)
	emit_event(w, Event{kind = .Enemy_Killed, position = feet + Vec3{0, params.hover + params.height*0.5, 0},
		normal = dir, value = f32(params.score), enemy = e.kind, index = index})
	roll := rng.float01(&w.rng)
	if roll < 0.2 {
		add_pickup(w, .Health, feet, &w.rng)
	} else if roll < 0.5 {
		add_pickup(w, .Mana, feet, &w.rng)
	}
}

@(private)
set_state :: proc "contextless" (e: ^Enemy, state: Enemy_State) {
	e.state = state
	e.state_time = 0
}

@(private)
enemies_update :: proc(w: ^World, dt: f32) {
	p := &w.player
	player_at := player_feet(p^)
	eye := player_eye(p^)
	for i in 0..<w.enemy_count {
		e := &w.enemies[i]
		e.prev_feet = enemy_feet(e^)
		e.state_time += dt
		if e.state == .Dead {
			continue
		}
		params := enemy_params(e.kind)
		speed := params.speed * w.tuning.speed_scale
		e.hurt_time = max(e.hurt_time-dt, 0)
		e.attack_cd = max(e.attack_cd-dt, 0)
		feet := enemy_feet(e^)
		to := Vec2{player_at.x - feet.x, player_at.z - feet.z}
		dist := physics.length2(to)
		dir := physics.normalize2(to)

		// Line of sight is expensive-ish, so each enemy looks every 1/8 s,
		// staggered across the pack.
		if (w.steps+u64(i)*5)%15 == 0 {
			e.sees = dist < params.sight && physics.voxel_line_of_sight(&w.voxels, enemy_eye(e^), eye)
			if e.sees {
				e.lost_time = 0
			} else if e.alerted {
				e.lost_time += 15 * dt
			}
		}
		if !e.alerted && (e.sees || dist < 2.2) {
			enemy_alert(w, i)
		}
		// Out of sight for long and far away along the corridors: give up.
		col := column_of(w, feet)
		if e.alerted && e.lost_time > 12 && col >= 0 && w.flow[col] > 30 {
			e.alerted = false
			set_state(e, .Idle)
		}

		desired: Vec2
		switch e.state {
		case .Idle:
			desired = wander(w, e, speed, dt)
		case .Chase:
			desired = chase(w, e, dir, dist, speed, dt)
			if e.attack_cd <= 0 && e.sees && dist < params.reach {
				set_state(e, .Windup)
				e.facing = dir
				emit_event(w, Event{kind = .Enemy_Windup, position = enemy_eye(e^), enemy = e.kind, index = i})
			}
		case .Windup:
			e.facing = dir
			if e.kind == .Cultist {
				// Casting while sidestepping keeps cultists hard to pin down.
				desired = Vec2{-dir.y, dir.x} * e.strafe * speed * 0.35
			}
			if e.state_time >= params.windup {
				release_attack(w, i, dir, dist)
			}
		case .Strike:
			desired = e.lunge * LUNGE_SPEED
			if !e.lunge_hit && dist < 1.2 {
				e.lunge_hit = true
				hurt_player(w, params.damage, enemy_eye(e^))
			}
			if e.state_time >= LUNGE_TIME {
				set_state(e, .Recover)
			}
		case .Recover:
			switch e.kind {
			case .Ghoul:
				desired = dir * speed * 0.25
			case .Wraith:
				desired = -dir * speed * 0.4
			case .Cultist:
				desired = cultist_move(w, e, dir, dist, speed, dt)
			}
			if e.state_time >= params.recover {
				set_state(e, .Chase if e.alerted else .Idle)
			}
		case .Dead:
		}
		if physics.length2(desired) > 0.1 && e.state != .Strike {
			e.facing = physics.normalize2(desired)
		}
		velocity := desired + e.push
		e.push *= max(1-7*dt, 0)
		e.body.velocity.y = max(e.body.velocity.y-GRAVITY*dt, -20)
		before := enemy_feet(e^)
		result := physics.move_body3(&w.voxels, &e.body, Vec3{velocity.x * dt, e.body.velocity.y * dt, velocity.y * dt})
		if result.hit_wall && e.state == .Idle {
			e.wander_time = 0
		}
		after := enemy_feet(e^)
		e.anim += physics.length2(Vec2{after.x - before.x, after.z - before.z})
		keep_off_player(w, e)
	}
	separate_enemies(w)
}

@(private)
wander :: proc(w: ^World, e: ^Enemy, speed, dt: f32) -> Vec2 {
	e.wander_time -= dt
	if e.wander_time <= 0 {
		e.wander_time = rng.float_range(&w.rng, 1, 2.6)
		if rng.chance(&w.rng, 0.4) {
			e.wander_dir = {}
		} else {
			a := rng.float01(&w.rng) * math.TAU
			e.wander_dir = Vec2{math.cos(a), math.sin(a)}
		}
	}
	scale := f32(0.45) if e.kind == .Wraith else f32(0.3)
	return e.wander_dir * speed * scale
}

@(private)
chase :: proc(w: ^World, e: ^Enemy, dir: Vec2, dist, speed, dt: f32) -> Vec2 {
	if e.kind == .Cultist && e.sees {
		return cultist_move(w, e, dir, dist, speed, dt)
	}
	if e.sees && dist < 6 {
		return dir * speed
	}
	feet := enemy_feet(e^)
	target, ok := flow_step(w, &w.flow, feet)
	if !ok {
		return {}
	}
	step := physics.normalize2(Vec2{target.x - feet.x, target.z - feet.z})
	return step * speed
}

@(private)
cultist_move :: proc(w: ^World, e: ^Enemy, dir: Vec2, dist, speed, dt: f32) -> Vec2 {
	e.strafe_time -= dt
	if e.strafe_time <= 0 {
		e.strafe_time = rng.float_range(&w.rng, 1.2, 2.6)
		e.strafe = -e.strafe
	}
	side := Vec2{-dir.y, dir.x} * e.strafe
	if dist < CULTIST_NEAR {
		return (-dir*0.8 + side*0.4) * speed
	}
	if dist > CULTIST_FAR || !e.sees {
		feet := enemy_feet(e^)
		target, ok := flow_step(w, &w.flow, feet)
		if !ok {
			return {}
		}
		return physics.normalize2(Vec2{target.x - feet.x, target.z - feet.z}) * speed
	}
	return side * speed * 0.7
}

@(private)
release_attack :: proc(w: ^World, index: int, dir: Vec2, dist: f32) {
	e := &w.enemies[index]
	params := enemy_params(e.kind)
	switch e.kind {
	case .Ghoul:
		// The claw lands only if the player is still in reach: backing off
		// during the wind-up is the counterplay.
		emit_event(w, Event{kind = .Enemy_Strike, position = enemy_eye(e^), enemy = e.kind, index = index})
		if dist < params.reach+0.4 && physics.voxel_line_of_sight(&w.voxels, enemy_eye(e^), player_eye(w.player)) {
			hurt_player(w, params.damage, enemy_eye(e^))
		}
		set_state(e, .Recover)
		e.attack_cd = 0.35
	case .Wraith:
		e.lunge = dir
		e.lunge_hit = false
		set_state(e, .Strike)
		e.attack_cd = 1.2
		emit_event(w, Event{kind = .Enemy_Strike, position = enemy_eye(e^), enemy = e.kind, index = index})
	case .Cultist:
		if e.sees {
			from := enemy_eye(e^) - Vec3{0, 0.25, 0} + Vec3{dir.x, 0, dir.y} * 0.45
			target := physics.body3_center(w.player.body)
			time := physics.length3(target-from) / PROJECTILE_SPEED
			v := w.player.body.velocity
			target += Vec3{v.x, 0, v.z} * time * w.tuning.lead
			spawn_projectile(w, from, target, params.damage)
			emit_event(w, Event{kind = .Enemy_Cast, position = from, enemy = e.kind, index = index})
		}
		set_state(e, .Recover)
		e.attack_cd = params.recover + rng.float_range(&w.rng, 0, 0.9)
	}
}

spawn_projectile :: proc(w: ^World, from, target: Vec3, damage: f32) -> bool {
	for &pr in w.projectiles {
		if pr.alive {
			continue
		}
		dir := physics.normalize3(target - from)
		if dir == {} {
			dir = {0, 0, 1}
		}
		pr = Projectile{alive = true, position = from, previous = from, velocity = dir * PROJECTILE_SPEED,
			life = PROJECTILE_LIFE, damage = damage}
		return true
	}
	return false
}

@(private)
projectiles_update :: proc(w: ^World, dt: f32) {
	feet := player_feet(w.player)
	for &pr in w.projectiles {
		if !pr.alive {
			continue
		}
		pr.previous = pr.position
		pr.life -= dt
		if pr.life <= 0 {
			pr.alive = false
			continue
		}
		delta := pr.velocity * dt
		step := physics.length3(delta)
		wall := physics.raycast_voxels(&w.voxels, pr.position, pr.velocity, step)
		if wall.hit {
			pr.alive = false
			emit_event(w, Event{kind = .Projectile_Burst, position = wall.point, normal = wall.normal})
			continue
		}
		pr.position += delta
		// Distance to the player's vertical segment (ankles to head).
		lo, hi := feet.y+0.3, feet.y+1.5
		closest := Vec3{feet.x, clamp(pr.position.y, lo, hi), feet.z}
		if physics.length3(pr.position-closest) < 0.5 {
			pr.alive = false
			hurt_player(w, pr.damage, pr.position)
			emit_event(w, Event{kind = .Projectile_Burst, position = pr.position, normal = -physics.normalize3(pr.velocity)})
		}
	}
}

// Enemies never stand inside the player; only the enemy is moved, so the
// player is never shoved into a wall.
@(private)
keep_off_player :: proc(w: ^World, e: ^Enemy) {
	a := player_feet(w.player)
	b := enemy_feet(e^)
	push := physics.circle_push(Vec2{a.x, a.z}, 0.45, Vec2{b.x, b.z}, 0.55)
	if push != {} {
		physics.move_body3(&w.voxels, &e.body, Vec3{push.x, 0, push.y})
	}
}

@(private)
separate_enemies :: proc(w: ^World) {
	for i in 0..<w.enemy_count {
		a := &w.enemies[i]
		if a.state == .Dead {
			continue
		}
		for j in i+1..<w.enemy_count {
			b := &w.enemies[j]
			if b.state == .Dead {
				continue
			}
			fa, fb := enemy_feet(a^), enemy_feet(b^)
			push := physics.circle_push(Vec2{fa.x, fa.z}, 0.4, Vec2{fb.x, fb.z}, 0.4)
			if push == {} {
				continue
			}
			half := push * 0.5
			physics.move_body3(&w.voxels, &b.body, Vec3{half.x, 0, half.y})
			physics.move_body3(&w.voxels, &a.body, Vec3{-half.x, 0, -half.y})
		}
	}
}
