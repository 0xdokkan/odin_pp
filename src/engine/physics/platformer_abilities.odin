package physics

// Both controllers refresh ability timers before integrating motion. The 2D
// controller also replenishes air dashes on walls; wall contact is not a 3D
// movement ability. Keep this helper restricted to these two controller types.
@(private)
platformer_begin_abilities :: proc(p: ^$P, params: Platformer_Params,
	jump_pressed, dash_pressed: bool, dt: f32) -> bool where P == Platformer || P == Platformer3 {
	if p.grounded {
		p.coyote = params.coyote_time
		p.air_jumps_left = params.air_jumps
	} else {
		p.coyote = max(p.coyote-dt, 0)
	}
	refill_dashes := p.grounded
	when P == Platformer {
		refill_dashes = refill_dashes || p.wall_side != 0
	}
	if refill_dashes {
		p.air_dashes_used = 0
	}
	p.jump_buffer = params.jump_buffer_time if jump_pressed else max(p.jump_buffer-dt, 0)
	p.dash_cooldown = max(p.dash_cooldown-dt, 0)

	air_dash_ok := p.grounded || params.air_dashes <= 0 || p.air_dashes_used < params.air_dashes
	if dash_pressed && params.dash_speed > 0 && p.dash_cooldown <= 0 && p.dash_remaining <= 0 && air_dash_ok {
		p.dash_remaining = params.dash_time
		p.dash_cooldown = params.dash_cooldown
		if !p.grounded && params.air_dashes > 0 {
			p.air_dashes_used += 1
		}
		return true
	}
	return false
}
