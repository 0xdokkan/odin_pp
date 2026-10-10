package physics

import "core:math"

// Tuning for a side-view character. Zero disables the optional moves
// (air jumps, wall slide/jump, dash).
Platformer_Params :: struct {
	max_speed:          f32,
	ground_accel:       f32,
	ground_decel:       f32,
	air_accel:          f32,
	air_decel:          f32,
	gravity:            f32,
	// Heavier fall makes jumps feel snappy instead of floaty.
	fall_gravity_scale: f32,
	max_fall_speed:     f32,
	jump_speed:         f32,
	// Upward velocity is multiplied by this when jump is released early.
	jump_cut:           f32,
	coyote_time:        f32,
	jump_buffer_time:   f32,
	air_jumps:          int,
	wall_slide_speed:   f32,
	wall_jump_speed:    Vec2,
	dash_speed:         f32,
	dash_time:          f32,
	dash_cooldown:      f32,
	// Dashes allowed per airtime (refilled on ground and walls); 0 = no limit.
	air_dashes:         int,
}

// Defaults tuned for 16-pixel tiles at a 960x540 canvas.
DEFAULT_PLATFORMER :: Platformer_Params{
	max_speed          = 150,
	ground_accel       = 1400,
	ground_decel       = 1800,
	air_accel          = 900,
	air_decel          = 600,
	gravity            = 1100,
	fall_gravity_scale = 1.6,
	max_fall_speed     = 420,
	jump_speed         = 330,
	jump_cut           = 0.45,
	coyote_time        = 0.1,
	jump_buffer_time   = 0.12,
	air_jumps          = 1,
	wall_slide_speed   = 70,
	wall_jump_speed    = {190, 300},
	dash_speed         = 330,
	dash_time          = 0.14,
	dash_cooldown      = 0.5,
	air_dashes         = 1,
}

Platformer_Input :: struct {
	move:         f32, // -1..1
	jump_pressed: bool,
	jump_held:    bool,
	drop_through: bool,
	dash_pressed: bool,
}

Platformer_Events :: struct {
	jumped, air_jumped, wall_jumped, dashed, landed: bool,
	// Downward speed at the moment of landing, for squash and dust.
	landing_speed: f32,
}

Platformer :: struct {
	body:            Body2,
	grounded:        bool,
	coyote:          f32,
	jump_buffer:     f32,
	air_jumps_left:  int,
	facing:          f32,
	wall_side:       f32, // -1 wall on the left, +1 on the right, 0 none
	dash_remaining:  f32,
	dash_cooldown:   f32,
	air_dashes_used: int,
	jump_cut_used:   bool,
}

platformer_create :: proc(position, size: Vec2) -> Platformer {
	return Platformer{body = Body2{position = position, size = size}, facing = 1}
}

// One fixed simulation step. Pure function of state, input and map.
platformer_step :: proc(p: ^Platformer, params: Platformer_Params, input: Platformer_Input,
	m: ^Tile_Map, dt: f32) -> (Move_Result2, Platformer_Events) {
	events: Platformer_Events
	move := clamp(input.move, -1, 1)
	if abs(move) > 0.1 {
		p.facing = math.sign(move)
	}

	// Timers: coyote keeps the jump available briefly after leaving a ledge,
	// the buffer remembers a jump pressed just before landing.
	if p.grounded {
		p.coyote = params.coyote_time
		p.air_jumps_left = params.air_jumps
	} else {
		p.coyote = max(p.coyote-dt, 0)
	}
	if p.grounded || p.wall_side != 0 {
		p.air_dashes_used = 0
	}
	p.jump_buffer = params.jump_buffer_time if input.jump_pressed else max(p.jump_buffer-dt, 0)
	p.dash_cooldown = max(p.dash_cooldown-dt, 0)

	air_dash_ok := p.grounded || params.air_dashes <= 0 || p.air_dashes_used < params.air_dashes
	if input.dash_pressed && params.dash_speed > 0 && p.dash_cooldown <= 0 && p.dash_remaining <= 0 && air_dash_ok {
		p.dash_remaining = params.dash_time
		p.dash_cooldown = params.dash_cooldown
		if !p.grounded && params.air_dashes > 0 {
			p.air_dashes_used += 1
		}
		events.dashed = true
	}

	if p.dash_remaining > 0 {
		p.dash_remaining = max(p.dash_remaining-dt, 0)
		p.body.velocity = Vec2{p.facing * params.dash_speed, 0}
	} else {
		// Horizontal: accelerate toward the target speed, brake harder.
		target := move * params.max_speed
		accel: f32
		if p.grounded {
			accel = params.ground_accel if abs(target) > EPSILON else params.ground_decel
		} else {
			accel = params.air_accel if abs(target) > EPSILON else params.air_decel
		}
		v := p.body.velocity.x
		if v < target {
			v = min(v+accel*dt, target)
		} else {
			v = max(v-accel*dt, target)
		}
		p.body.velocity.x = v

		// Jumps, by priority: ground (or coyote), wall, air.
		if p.jump_buffer > 0 {
			if p.coyote > 0 {
				p.body.velocity.y = -params.jump_speed
				events.jumped = true
			} else if p.wall_side != 0 && params.wall_jump_speed.y > 0 {
				p.body.velocity = Vec2{-p.wall_side * params.wall_jump_speed.x, -params.wall_jump_speed.y}
				p.facing = -p.wall_side
				events.wall_jumped = true
			} else if p.air_jumps_left > 0 {
				p.air_jumps_left -= 1
				p.body.velocity.y = -params.jump_speed * 0.9
				events.air_jumped = true
			}
			if events.jumped || events.wall_jumped || events.air_jumped {
				p.jump_buffer = 0
				p.coyote = 0
				p.jump_cut_used = false
			}
		}

		// Variable height: releasing jump while rising cuts the ascent once.
		if !input.jump_held && p.body.velocity.y < 0 && !p.jump_cut_used {
			p.body.velocity.y *= params.jump_cut
			p.jump_cut_used = true
		}

		gravity := params.gravity
		if p.body.velocity.y > 0 {
			gravity *= params.fall_gravity_scale
		}
		p.body.velocity.y = min(p.body.velocity.y+gravity*dt, params.max_fall_speed)

		// Wall slide: pressing into a wall while falling caps the fall speed.
		if p.wall_side != 0 && !p.grounded && p.body.velocity.y > 0 && params.wall_slide_speed > 0 &&
		   math.sign(move) == p.wall_side {
			p.body.velocity.y = min(p.body.velocity.y, params.wall_slide_speed)
		}
	}

	falling_speed := p.body.velocity.y
	was_grounded := p.grounded
	result := move_body2(m, &p.body, p.body.velocity*dt, input.drop_through)
	p.grounded = result.on_ground
	if p.grounded && !was_grounded {
		events.landed = true
		events.landing_speed = max(falling_speed, 0)
	}
	p.wall_side = 0
	if !p.grounded {
		if touching_wall(m, p.body, 1) {
			p.wall_side = 1
		} else if touching_wall(m, p.body, -1) {
			p.wall_side = -1
		}
	}
	return result, events
}

@(private)
touching_wall :: proc(m: ^Tile_Map, body: Body2, side: f32) -> bool {
	probe := body2_rect(body)
	probe.x += side * 1
	probe.y += 2
	probe.height = max(probe.height-4, 1)
	return rect_hits_solid(m, probe)
}
