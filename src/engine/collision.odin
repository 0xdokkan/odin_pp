package engine

import "core:math"

CONTACT_EPSILON :: f32(0.0001)
MAX_MOVE_ITERATIONS :: 8

vertical_overlap :: proc(body: Body, bounds: AABB) -> bool {
	return body.position.y+body.height > bounds.min.y+CONTACT_EPSILON &&
		body.position.y < bounds.max.y-CONTACT_EPSILON
}
actors_vertical_overlap :: proc(a, b: Body) -> bool {
	return a.position.y+a.height > b.position.y+CONTACT_EPSILON &&
		a.position.y < b.position.y+b.height-CONTACT_EPSILON
}

circle_box_overlap :: proc(body: Body, bounds: AABB) -> (offset: Vec3, overlaps: bool) {
	if !vertical_overlap(body, bounds) { return {}, false }
	closest := Vec3{clamp(body.position.x, bounds.min.x, bounds.max.x), body.position.y,
		clamp(body.position.z, bounds.min.z, bounds.max.z)}
	difference := vec_sub(body.position, closest)
	distance_squared := vec_dot(difference, difference)
	if distance_squared >= body.radius*body.radius { return {}, false }
	if distance_squared > 0.00000001 {
		distance := math.sqrt(distance_squared)
		return vec_scale(difference, (body.radius-distance+CONTACT_EPSILON)/distance), true
	}
	// Inside a solid: resolve through the nearest surface, deterministically on ties.
	distances := [4]f32{body.position.x-bounds.min.x, bounds.max.x-body.position.x,
		body.position.z-bounds.min.z, bounds.max.z-body.position.z}
	normals := [4]Vec3{{-1, 0, 0}, {1, 0, 0}, {0, 0, -1}, {0, 0, 1}}
	nearest := 0
	for index in 1..<4 { if distances[index] < distances[nearest] { nearest = index } }
	return vec_scale(normals[nearest], distances[nearest]+body.radius+CONTACT_EPSILON), true
}

circle_actor_overlap :: proc(body, other: Body) -> (offset: Vec3, overlaps: bool) {
	if body.id == other.id || !actors_vertical_overlap(body, other) { return {}, false }
	difference := vec_sub(body.position, other.position)
	difference.y = 0
	radius := body.radius+other.radius
	distance_squared := vec_dot(difference, difference)
	if distance_squared >= radius*radius { return {}, false }
	if distance_squared < 0.00000001 {
		return {radius+CONTACT_EPSILON if body.id > other.id else -radius-CONTACT_EPSILON, 0, 0}, true
	}
	distance := math.sqrt(distance_squared)
	return vec_scale(difference, (radius-distance+CONTACT_EPSILON)/distance), true
}

body_overlaps :: proc(world: ^World, body: Body, mask: Layers = {.World, .Actor}) -> bool {
	if !valid_world(world) || !valid_body(body) { return true }
	if .World in mask {
		for solid in world.solids[:world.solid_count] {
			_, overlaps := circle_box_overlap(body, solid.bounds)
			if overlaps { return true }
		}
	}
	if .Actor in mask {
		for other in world.actors[:world.actor_count] {
			_, overlaps := circle_actor_overlap(body, other)
			if overlaps { return true }
		}
	}
	return false
}

// Continuous circle/circle cast in the horizontal plane. A touching circle only
// blocks inward motion; tangent/outward motion must not trap the controller.
sweep_circle :: proc(origin, delta, center: Vec3, radius: f32) -> (time: f32, normal: Vec3, hit: bool) {
	separation := Vec3{origin.x-center.x, 0, origin.z-center.z}
	velocity := Vec3{delta.x, 0, delta.z}
	// Double precision preserves the radius term on long casts; in f32 a
	// distant tiny target can otherwise collapse to a tangent and be skipped.
	a := f64(velocity.x)*f64(velocity.x)+f64(velocity.z)*f64(velocity.z)
	b := f64(separation.x)*f64(velocity.x)+f64(separation.z)*f64(velocity.z)
	c := f64(separation.x)*f64(separation.x)+f64(separation.z)*f64(separation.z)-f64(radius)*f64(radius)
	if a < 1e-12 || b >= 0 { return 0, {}, false }
	discriminant := b*b-a*c
	if discriminant < 0 { return 0, {}, false }
	time = f32(max(0, c/(-b+math.sqrt(discriminant))))
	if time > 1 { return 0, {}, false }
	normal = vec_normalize(vec_add(separation, vec_scale(velocity, time)))
	return time, normal, vec_dot(velocity, normal) < -1e-7
}

// Exact rounded rectangle: four offset surfaces and four circular corners.
// Unlike an expanded AABB this allows a round body to glide around a corner.
sweep_box :: proc(body: Body, delta: Vec3, bounds: AABB) -> (time: f32, normal: Vec3, hit: bool) {
	if !vertical_overlap(body, bounds) { return 0, {}, false }
	time = 2
	if math.abs(delta.x) > 1e-8 {
		surface := bounds.min.x-body.radius if delta.x > 0 else bounds.max.x+body.radius
		candidate := (surface-body.position.x)/delta.x
		z := body.position.z+candidate*delta.z
		if candidate >= -1e-6 && candidate <= 1 && z >= bounds.min.z && z <= bounds.max.z {
			time = max(0, candidate)
			normal = {-1 if delta.x > 0 else 1, 0, 0}
		}
	}
	if math.abs(delta.z) > 1e-8 {
		surface := bounds.min.z-body.radius if delta.z > 0 else bounds.max.z+body.radius
		candidate := (surface-body.position.z)/delta.z
		x := body.position.x+candidate*delta.x
		if candidate >= -1e-6 && candidate < time && candidate <= 1 && x >= bounds.min.x && x <= bounds.max.x {
			time = max(0, candidate)
			normal = {0, 0, -1 if delta.z > 0 else 1}
		}
	}
	corners := [4]Vec3{{bounds.min.x, 0, bounds.min.z}, {bounds.max.x, 0, bounds.min.z},
		{bounds.min.x, 0, bounds.max.z}, {bounds.max.x, 0, bounds.max.z}}
	for corner in corners {
		candidate, candidate_normal, found := sweep_circle(body.position, delta, corner, body.radius)
		if found && candidate < time { time = candidate; normal = candidate_normal }
	}
	return time, normal, time <= 1
}

// First blocking contact along a horizontal segment. This query does not move
// or depenetrate the body; callers choose whether to stop or slide at contact.
// As with sweep_box/sweep_circle, inputs must be valid and initially separated.
// Equal-time contacts preserve solid-before-actor and storage ordering.
sweep_body :: proc(world: ^World, body: Body, delta: Vec3, mask: Layers = {.World, .Actor}) ->
	(time: f32, normal: Vec3, hit_id: u32, hit: bool) {
	time = 2
	if .World in mask {
		for solid in world.solids[:world.solid_count] {
			candidate, contact, found := sweep_box(body, delta, solid.bounds)
			if found && candidate < time { time = candidate; normal = contact; hit_id = solid.id }
		}
	}
	if .Actor in mask {
		for other in world.actors[:world.actor_count] {
			if other.id == body.id || !actors_vertical_overlap(body, other) { continue }
			candidate, contact, found := sweep_circle(body.position, delta, other.position, body.radius+other.radius)
			if found && candidate < time { time = candidate; normal = contact; hit_id = other.id }
		}
	}
	return time, normal, hit_id, time <= 1
}

// Flat-ground upright controller. Vertical motion, stairs and slopes deliberately
// require another controller: rejecting nonzero Y avoids pretending to support them.
move_character :: proc(world: ^World, body: ^Body, delta: Vec3, mask: Layers = {.World, .Actor}) -> Move_Result {
	result: Move_Result
	if !valid_world(world) || body == nil || !valid_body(body^) || !finite_vec(delta) ||
		math.abs(delta.y) > 1e-7 || !finite(vec_dot(delta, delta)) { return result }
	result.valid = true
	start := body.position
	staged := body^
	for _ in 0..<MAX_MOVE_ITERATIONS {
		resolved := true
		if .World in mask {
			for solid in world.solids[:world.solid_count] {
				offset, overlaps := circle_box_overlap(staged, solid.bounds)
				if !overlaps { continue }
				staged.position = vec_add(staged.position, offset)
				result.depenetrated = true
				resolved = false
			}
		}
		if .Actor in mask {
			for other in world.actors[:world.actor_count] {
				offset, overlaps := circle_actor_overlap(staged, other)
				if !overlaps { continue }
				staged.position = vec_add(staged.position, offset)
				result.depenetrated = true
				resolved = false
			}
		}
		if resolved { break }
	}
	if body_overlaps(world, staged, mask) {
		result.blocked = true
		return result
	}
	remaining := delta
	for _ in 0..<MAX_MOVE_ITERATIONS {
		if vec_dot(remaining, remaining) <= 1e-12 { break }
		closest, normal, hit_id, hit := sweep_body(world, staged, remaining, mask)
		if !hit {
			staged.position = vec_add(staged.position, remaining)
			remaining = {}
			break
		}
		result.collided = true
		result.normal = normal
		result.hit_id = hit_id
		// A relative safety margin survives f32 cancellation on very long sweeps.
		// Without it, adding a 10 km delta can round the contact just inside a body.
		length := vec_length(remaining)
		coordinate_scale := max(math.abs(staged.position.x), math.abs(staged.position.z))
		skin := max(CONTACT_EPSILON, max(length, coordinate_scale)*0.0000002)
		travel := max(0, closest-skin/max(length, CONTACT_EPSILON))
		staged.position = vec_add(staged.position, vec_scale(remaining, travel))
		remaining = vec_scale(remaining, 1-travel)
		inward := vec_dot(remaining, normal)
		if inward < 0 { remaining = vec_sub(remaining, vec_scale(normal, inward)) }
	}
	result.blocked = vec_dot(remaining, remaining) > 1e-10
	result.applied = vec_sub(staged.position, start)
	body^ = staged
	sync_actor(world, staged)
	return result
}

body_in_trigger :: proc(body: Body, trigger: Trigger) -> bool {
	if !valid_body(body) || !valid_bounds(trigger.bounds) { return false }
	_, overlaps := circle_box_overlap(body, trigger.bounds)
	return overlaps
}
