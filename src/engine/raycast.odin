package engine

import "core:math"

ray_aabb :: proc(origin, direction: Vec3, bounds: AABB, max_distance: f32) -> Ray_Hit {
	result: Ray_Hit
	if !finite_vec(origin) || !finite_vec(direction) || !valid_bounds(bounds) || !finite(max_distance) || max_distance < 0 { return result }
	normalized := vec_normalize(direction)
	if vec_dot(normalized, normalized) < 0.5 { return result }
	starts := [3]f32{origin.x, origin.y, origin.z}
	deltas := [3]f32{normalized.x, normalized.y, normalized.z}
	lows := [3]f32{bounds.min.x, bounds.min.y, bounds.min.z}
	highs := [3]f32{bounds.max.x, bounds.max.y, bounds.max.z}
	axes := [3]Vec3{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}
	near: f32 = 0
	far := max_distance
	normal := vec_scale(normalized, -1)
	for axis in 0..<3 {
		if math.abs(deltas[axis]) < 1e-8 {
			if starts[axis] < lows[axis] || starts[axis] > highs[axis] { return result }
			continue
		}
		entry := (lows[axis]-starts[axis])/deltas[axis]
		exit := (highs[axis]-starts[axis])/deltas[axis]
		surface_normal := vec_scale(axes[axis], -1)
		if entry > exit { entry, exit = exit, entry; surface_normal = axes[axis] }
		if entry > near { near = entry; normal = surface_normal }
		far = min(far, exit)
		if near > far { return result }
	}
	if far < 0 || near > max_distance { return result }
	return {hit = true, distance = near, position = vec_add(origin, vec_scale(normalized, near)), normal = normal, layer = .World}
}

ray_sphere :: proc(origin, direction, center: Vec3, radius, max_distance: f32) -> Ray_Hit {
	result: Ray_Hit
	if !finite_vec(origin) || !finite_vec(direction) || !finite_vec(center) ||
		!finite(radius) || radius <= 0 || !finite(max_distance) || max_distance < 0 { return result }
	normalized := vec_normalize(direction)
	if vec_dot(normalized, normalized) < 0.5 { return result }
	offset := vec_sub(origin, center)
	a := f64(normalized.x)*f64(normalized.x)+f64(normalized.y)*f64(normalized.y)+f64(normalized.z)*f64(normalized.z)
	b := f64(offset.x)*f64(normalized.x)+f64(offset.y)*f64(normalized.y)+f64(offset.z)*f64(normalized.z)
	c := f64(offset.x)*f64(offset.x)+f64(offset.y)*f64(offset.y)+f64(offset.z)*f64(offset.z)-f64(radius)*f64(radius)
	if c <= 0 { return {hit = true, distance = 0, position = origin, normal = vec_scale(normalized, -1), layer = .Actor} }
	discriminant := b*b-a*c
	if discriminant < 0 || b >= 0 { return result }
	distance := f32(c/(-b+math.sqrt(discriminant)))
	if distance < 0 || distance > max_distance { return result }
	position := vec_add(origin, vec_scale(normalized, distance))
	return {hit = true, distance = distance, position = position, normal = vec_normalize(vec_sub(position, center)), layer = .Actor}
}

ray_capsule :: proc(origin, direction: Vec3, body: Body, max_distance: f32) -> Ray_Hit {
	result: Ray_Hit
	if !valid_body(body) || !finite_vec(origin) || !finite_vec(direction) || !finite(max_distance) || max_distance < 0 { return result }
	normalized := vec_normalize(direction)
	if vec_dot(normalized, normalized) < 0.5 { return result }
	bottom := vec_add(body.position, {0, body.radius, 0})
	top := vec_add(body.position, {0, body.height-body.radius, 0})
	closest := Vec3{body.position.x, clamp(origin.y, bottom.y, top.y), body.position.z}
	if vec_dot(vec_sub(origin, closest), vec_sub(origin, closest)) <= body.radius*body.radius {
		return {hit = true, distance = 0, position = origin, normal = vec_scale(normalized, -1), id = body.id, layer = .Actor}
	}
	result = ray_sphere(origin, normalized, bottom, body.radius, max_distance)
	cap := ray_sphere(origin, normalized, top, body.radius, max_distance)
	if cap.hit && (!result.hit || cap.distance < result.distance) { result = cap }
	difference := vec_sub(origin, body.position)
	a := f64(normalized.x)*f64(normalized.x)+f64(normalized.z)*f64(normalized.z)
	b := f64(difference.x)*f64(normalized.x)+f64(difference.z)*f64(normalized.z)
	c := f64(difference.x)*f64(difference.x)+f64(difference.z)*f64(difference.z)-f64(body.radius)*f64(body.radius)
	discriminant := b*b-a*c
	if a > 1e-10 && discriminant >= 0 {
		distance := f32((-b-math.sqrt(discriminant))/a)
		y := origin.y+distance*normalized.y
		if distance >= 0 && distance <= max_distance && y >= bottom.y && y <= top.y &&
			(!result.hit || distance < result.distance) {
			position := vec_add(origin, vec_scale(normalized, distance))
			result = {hit = true, distance = distance, position = position,
				normal = vec_normalize({position.x-body.position.x, 0, position.z-body.position.z})}
		}
	}
	if result.hit { result.id = body.id; result.layer = .Actor }
	return result
}

// World is visited first so an equal-depth solid wins an actor tie: hitscan
// cannot damage a character through an exactly coplanar blocking wall.
raycast :: proc(world: ^World, origin, direction: Vec3, max_distance: f32,
	mask: Layers = {.World, .Actor}, ignore_id: u32 = 0) -> Ray_Hit {
	result: Ray_Hit
	if !valid_world(world) { return result }
	if .World in mask {
		for solid in world.solids[:world.solid_count] {
			hit := ray_aabb(origin, direction, solid.bounds, max_distance)
			if hit.hit && (!result.hit || hit.distance < result.distance) {
				result = hit
				result.id = solid.id
			}
		}
	}
	if .Actor in mask {
		for actor in world.actors[:world.actor_count] {
			if actor.id == ignore_id { continue }
			hit := ray_capsule(origin, direction, actor, max_distance)
			if hit.hit && (!result.hit || hit.distance < result.distance) { result = hit }
		}
	}
	if .Trigger in mask {
		for trigger in world.triggers[:world.trigger_count] {
			hit := ray_aabb(origin, direction, trigger.bounds, max_distance)
			if hit.hit && (!result.hit || hit.distance < result.distance) {
				result = hit
				result.id = trigger.id
				result.layer = .Trigger
			}
		}
	}
	return result
}
