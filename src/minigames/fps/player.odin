package fps

import "core:math"
import camera "../../engine/camera"
import physics "../../engine/physics"

WALK_SPEED :: f32(4.4)
SPRINT_SPEED :: f32(6.9)
GROUND_ACCEL :: f32(60)
AIR_ACCEL :: f32(16)
GRAVITY :: f32(22)
JUMP_SPEED :: f32(6.4)
PITCH_LIMIT :: f32(1.35)

// Runic staff: hitscan bolts fed by regenerating mana.
FIRE_INTERVAL :: f32(0.2)
SHOT_COST :: f32(8)
MANA_REGEN :: f32(16)
MANA_REGEN_DELAY :: f32(0.45)
BOLT_DAMAGE :: f32(25)
SHOT_RANGE :: f32(40)
// Firing is loud: sleeping enemies this close wake up even without sight.
SHOT_NOISE_RADIUS :: f32(9)

HEALTH_PACK :: f32(30)
MANA_PACK :: f32(45)
PICKUP_RADIUS :: f32(0.9)
PARRY_SCORE :: 25

player_feet :: proc "contextless" (p: Player) -> Vec3 {
	return physics.body3_feet(p.body)
}

player_eye :: proc "contextless" (p: Player) -> Vec3 {
	return player_feet(p) + Vec3{0, EYE_HEIGHT, 0}
}

player_forward :: proc "contextless" (p: Player) -> Vec3 {
	return camera.fps_forward(camera.Fps_Camera{yaw = p.yaw, pitch = p.pitch})
}

// Applies a look delta. Separate from the step so the host can keep mouse
// look responsive during hit-stop frames, when no step runs.
world_look :: proc(w: ^World, look: Vec2) {
	p := &w.player
	p.yaw = math.mod(p.yaw+look.x, math.TAU)
	p.pitch = clamp(p.pitch+look.y, -PITCH_LIMIT, PITCH_LIMIT)
}

@(private)
player_update :: proc(w: ^World, input: Player_Input, dt: f32) {
	p := &w.player
	p.prev_eye = player_eye(p^)
	world_look(w, input.look)
	p.invuln = max(p.invuln-dt, 0)

	forward, right := camera.fps_ground_basis(p.yaw)
	move := physics.clamp_length2(input.move, 1)
	wish := forward*move.y + right*move.x
	// Firing raises the staff and cancels the sprint.
	p.sprinting = input.sprint && move.y > 0.3 && !input.fire
	speed := SPRINT_SPEED if p.sprinting else WALK_SPEED
	target := wish * speed
	current := Vec2{p.body.velocity.x, p.body.velocity.z}
	accel := GROUND_ACCEL if p.grounded else AIR_ACCEL
	gap := target - current
	step := accel * dt
	if physics.length2(gap) <= step {
		current = target
	} else {
		current += physics.normalize2(gap) * step
	}
	p.body.velocity.x = current.x
	p.body.velocity.z = current.y

	p.jump_buffer = 0.12 if input.jump else max(p.jump_buffer-dt, 0)
	if p.jump_buffer > 0 && p.grounded {
		p.body.velocity.y = JUMP_SPEED
		p.jump_buffer = 0
		p.grounded = false
		emit_event(w, Event{kind = .Jump, position = player_feet(p^)})
	}
	p.body.velocity.y = max(p.body.velocity.y-GRAVITY*dt, -30)
	falling := -p.body.velocity.y
	result := physics.move_body3(&w.voxels, &p.body, p.body.velocity*dt)
	was_grounded := p.grounded
	p.grounded = result.on_ground
	if p.grounded && !was_grounded && falling > 3 {
		emit_event(w, Event{kind = .Land, position = player_feet(p^), value = falling})
	}
	p.speed = physics.length2(Vec2{p.body.velocity.x, p.body.velocity.z})
	if p.grounded && p.speed > 0.5 {
		p.stride += p.speed * dt
		stride_length := f32(2.6) if p.sprinting else f32(2.1)
		if p.stride >= stride_length {
			p.stride -= stride_length
			emit_event(w, Event{kind = .Footstep, position = player_feet(p^), value = p.speed})
		}
	}
}

Hit_Kind :: enum u8 {
	None,
	Wall,
	Enemy,
	Projectile,
}

Shot_Hit :: struct {
	kind:     Hit_Kind,
	point:    Vec3,
	normal:   Vec3,
	distance: f32,
	index:    int,
}

ENEMY_HALF_WIDTH :: f32(0.4)
PROJECTILE_HIT_RADIUS :: f32(0.35)

// Hit box of an enemy, lifted for floating wraiths.
enemy_box :: proc "contextless" (e: Enemy) -> (lo, hi: Vec3) {
	feet := physics.body3_feet(e.body)
	params := enemy_params(e.kind)
	base := feet + Vec3{0, params.hover, 0}
	return base - Vec3{ENEMY_HALF_WIDTH, 0, ENEMY_HALF_WIDTH}, base + Vec3{ENEMY_HALF_WIDTH, params.height, ENEMY_HALF_WIDTH}
}

// Nearest thing a ray hits: wall, living enemy or enemy projectile. Walls
// are found first, so anything behind one is never hit.
hitscan :: proc(w: ^World, origin, direction: Vec3, range: f32) -> Shot_Hit {
	dir := physics.normalize3(direction)
	result := Shot_Hit{kind = .None, point = origin + dir*range, distance = range, index = -1}
	if dir == {} {
		return result
	}
	wall := physics.raycast_voxels(&w.voxels, origin, dir, range)
	if wall.hit {
		result = Shot_Hit{kind = .Wall, point = wall.point, normal = wall.normal, distance = wall.distance, index = -1}
	}
	for i in 0..<w.enemy_count {
		e := w.enemies[i]
		if e.state == .Dead {
			continue
		}
		lo, hi := enemy_box(e)
		t, ok := physics.ray_aabb3(origin, dir, lo, hi)
		if ok && t < result.distance {
			result = Shot_Hit{kind = .Enemy, point = origin + dir*t, normal = -dir, distance = t, index = i}
		}
	}
	for i in 0..<MAX_PROJECTILES {
		pr := w.projectiles[i]
		if !pr.alive {
			continue
		}
		t, ok := physics.ray_sphere(origin, dir, pr.position, PROJECTILE_HIT_RADIUS)
		if ok && t < result.distance {
			result = Shot_Hit{kind = .Projectile, point = origin + dir*t, normal = -dir, distance = t, index = i}
		}
	}
	return result
}

@(private)
weapon_update :: proc(w: ^World, input: Player_Input, dt: f32) {
	p := &w.player
	p.fire_cd = max(p.fire_cd-dt, 0)
	if p.mana_delay > 0 {
		p.mana_delay = max(p.mana_delay-dt, 0)
	} else {
		p.mana = min(p.mana+MANA_REGEN*dt, MAX_MANA)
	}
	if !input.fire || p.fire_cd > 0 {
		return
	}
	if p.mana < SHOT_COST {
		p.fire_cd = 0.3
		emit_event(w, Event{kind = .Dry_Fire, position = player_eye(p^)})
		return
	}
	p.mana -= SHOT_COST
	p.fire_cd = FIRE_INTERVAL
	p.mana_delay = MANA_REGEN_DELAY
	w.stats.shots += 1
	origin := player_eye(p^)
	dir := player_forward(p^)
	hit := hitscan(w, origin, dir, SHOT_RANGE)
	emit_event(w, Event{kind = .Shot, position = hit.point, normal = dir, value = f32(hit.kind)})
	switch hit.kind {
	case .None:
	case .Wall:
		emit_event(w, Event{kind = .Wall_Hit, position = hit.point, normal = hit.normal})
	case .Enemy:
		w.stats.hits += 1
		damage_enemy(w, hit.index, BOLT_DAMAGE, dir, hit.point)
	case .Projectile:
		w.stats.hits += 1
		w.stats.parries += 1
		w.stats.kill_score += PARRY_SCORE
		w.projectiles[hit.index].alive = false
		emit_event(w, Event{kind = .Projectile_Shot_Down, position = hit.point})
	}
	feet := player_feet(p^)
	for i in 0..<w.enemy_count {
		e := &w.enemies[i]
		if e.state == .Dead || e.alerted {
			continue
		}
		d := physics.body3_feet(e.body) - feet
		if d.x*d.x+d.z*d.z < SHOT_NOISE_RADIUS*SHOT_NOISE_RADIUS {
			enemy_alert(w, i)
		}
	}
}

// Damage from any source; brief invulnerability stops a pack of ghouls from
// landing every claw on the same frame.
hurt_player :: proc(w: ^World, amount: f32, source: Vec3) {
	p := &w.player
	if p.invuln > 0 || w.status != .Playing || p.hp <= 0 {
		return
	}
	damage := amount * w.tuning.damage_scale
	p.hp = max(p.hp-damage, 0)
	p.invuln = 0.3
	w.stats.damage_taken += damage
	emit_event(w, Event{kind = .Player_Hurt, position = source, value = damage})
	if p.hp <= 0 {
		w.status = .Lost
		emit_event(w, Event{kind = .Died, position = player_feet(p^)})
	}
}
