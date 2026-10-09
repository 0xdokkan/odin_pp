package physics

import "core:math"

// Third-person 3D platforming on a Voxel_Map. Shares the tuning struct with
// the 2D controller; wall jumps and one-way platforms are 2D-only.
Platformer3_Input :: struct {
	// Desired horizontal direction in world space (x, z), length <= 1.
	move:         Vec2,
	jump_pressed: bool,
	jump_held:    bool,
	dash_pressed: bool,
}

Platformer3 :: struct {
	body:           Body3,
	grounded:       bool,
	coyote:         f32,
	jump_buffer:    f32,
	air_jumps_left: int,
	// Facing angle around +y, radians; 0 faces +z.
	yaw:            f32,
	dash_remaining: f32,
	dash_cooldown:  f32,
	jump_cut_used:  bool,
}

platformer3_create :: proc(feet, size: Vec3) -> Platformer3 {
	return Platformer3{body = Body3{position = feet - Vec3{size.x * 0.5, 0, size.z * 0.5}, size = size}}
}

// Physics constants are per voxel unit (1 voxel = 1 metre-ish).
DEFAULT_PLATFORMER3 :: Platformer_Params{
	max_speed          = 6,
	ground_accel       = 60,
	ground_decel       = 70,
	air_accel          = 35,
	air_decel          = 12,
	gravity            = 30,
	fall_gravity_scale = 1.5,
	max_fall_speed     = 30,
	jump_speed         = 11,
	jump_cut           = 0.5,
	coyote_time        = 0.1,
	jump_buffer_time   = 0.12,
	air_jumps          = 1,
	dash_speed         = 14,
	dash_time          = 0.16,
	dash_cooldown      = 0.6,
}

platformer3_step :: proc(p: ^Platformer3, params: Platformer_Params, input: Platformer3_Input,
	m: ^Voxel_Map, dt: f32) -> (Move_Result3, Platformer_Events) {
	events: Platformer_Events
	move := clamp_length2(input.move, 1)
	if length2(move) > 0.1 {
		p.yaw = math.atan2(move.x, move.y)
	}

	if p.grounded {
		p.coyote = params.coyote_time
		p.air_jumps_left = params.air_jumps
	} else {
		p.coyote = max(p.coyote-dt, 0)
	}
	p.jump_buffer = params.jump_buffer_time if input.jump_pressed else max(p.jump_buffer-dt, 0)
	p.dash_cooldown = max(p.dash_cooldown-dt, 0)

	if input.dash_pressed && params.dash_speed > 0 && p.dash_cooldown <= 0 && p.dash_remaining <= 0 {
		p.dash_remaining = params.dash_time
		p.dash_cooldown = params.dash_cooldown
		events.dashed = true
	}

	if p.dash_remaining > 0 {
		p.dash_remaining = max(p.dash_remaining-dt, 0)
		forward := Vec2{math.sin(p.yaw), math.cos(p.yaw)}
		p.body.velocity = Vec3{forward.x * params.dash_speed, 0, forward.y * params.dash_speed}
	} else {
		target := move * params.max_speed
		current := Vec2{p.body.velocity.x, p.body.velocity.z}
		accel: f32
		if p.grounded {
			accel = params.ground_accel if length2(target) > EPSILON else params.ground_decel
		} else {
			accel = params.air_accel if length2(target) > EPSILON else params.air_decel
		}
		gap := target - current
		step := accel * dt
		if length2(gap) <= step {
			current = target
		} else {
			current += normalize2(gap) * step
		}
		p.body.velocity.x = current.x
		p.body.velocity.z = current.y

		if p.jump_buffer > 0 {
			if p.coyote > 0 {
				p.body.velocity.y = params.jump_speed
				events.jumped = true
			} else if p.air_jumps_left > 0 {
				p.air_jumps_left -= 1
				p.body.velocity.y = params.jump_speed * 0.9
				events.air_jumped = true
			}
			if events.jumped || events.air_jumped {
				p.jump_buffer = 0
				p.coyote = 0
				p.jump_cut_used = false
			}
		}
		if !input.jump_held && p.body.velocity.y > 0 && !p.jump_cut_used {
			p.body.velocity.y *= params.jump_cut
			p.jump_cut_used = true
		}
		gravity := params.gravity
		if p.body.velocity.y < 0 {
			gravity *= params.fall_gravity_scale
		}
		p.body.velocity.y = max(p.body.velocity.y-gravity*dt, -params.max_fall_speed)
	}

	falling := -p.body.velocity.y
	was_grounded := p.grounded
	result := move_body3(m, &p.body, p.body.velocity*dt)
	p.grounded = result.on_ground
	if p.grounded && !was_grounded {
		events.landed = true
		events.landing_speed = max(falling, 0)
	}
	return result, events
}
