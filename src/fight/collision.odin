package fight

import engine "../engine"

init_world :: proc(state: ^State) {
	state.world = engine.create_ring_level().world
	for i in 0..<len(state.fighters) { engine.add_actor(&state.world, collision_body(state, i)) }
}

collision_body :: proc(state: ^State, index: int) -> engine.Body {
	position := state.fighters[index].position
	// Throw lift is a presentation offset. The collision body stays on the
	// ground; its landing is swept before the choreography starts.
	position.y = 0
	return {position = position, radius = BODY_RADIUS, height = BODY_HEIGHT, id = u32(index+1), layer = .Actor}
}

sync_fighters :: proc(state: ^State) {
	for i in 0..<len(state.fighters) { engine.sync_actor(&state.world, collision_body(state, i)) }
}

move_fighter :: proc(state: ^State, index: int, delta: engine.Vec3) {
	body := collision_body(state, index)
	result := engine.move_character(&state.world, &body, delta)
	if result.valid { state.fighters[index].position = body.position }
}

sweep_position :: proc(state: ^State, index: int, delta: engine.Vec3) -> engine.Vec3 {
	body := collision_body(state, index)
	if engine.body_overlaps(&state.world, body) { return body.position }
	// A throw follows one straight segment, so it stops at the first contact.
	// Using the sliding movement controller's final position here would make
	// the animated segment cut across a corner that locomotion walked around.
	travel := f32(1)
	contact := false
	for solid in state.world.solids[:state.world.solid_count] {
		time, _, hit := engine.sweep_box(body, delta, solid.bounds)
		if hit && time <= travel { travel, contact = time, true }
	}
	for other in state.world.actors[:state.world.actor_count] {
		if other.id == body.id || !engine.actors_vertical_overlap(body, other) { continue }
		time, _, hit := engine.sweep_circle(body.position, delta, other.position, body.radius+other.radius)
		if hit && time <= travel { travel, contact = time, true }
	}
	if contact {
		travel = max(f32(0), travel-engine.CONTACT_EPSILON/max(engine.vec_length(delta), engine.CONTACT_EPSILON))
	}
	return engine.vec_add(body.position, engine.vec_scale(delta, travel))
}
