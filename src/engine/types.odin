package engine

import "core:math"
import "core:math/linalg"

// The same native vector representation used by physics, cameras and raylib.
Vec3 :: [3]f32
vec_add :: proc(a, b: Vec3) -> Vec3 { return a+b }
vec_sub :: proc(a, b: Vec3) -> Vec3 { return a-b }
vec_scale :: proc(a: Vec3, scale: f32) -> Vec3 { return a*scale }
vec_dot :: linalg.dot
vec_length :: linalg.length
vec_normalize :: proc(a: Vec3) -> Vec3 {
	length := vec_length(a)
	if length <= 0.000001 || !finite(length) { return {} }
	// Preserve the collision policy and its reciprocal multiplication: the
	// physics and particle normalizers intentionally use different cutoffs.
	return a*(1/length)
}
finite :: proc(value: f32) -> bool { return !math.is_nan(value) && !math.is_inf(value) }
finite_vec :: proc(value: Vec3) -> bool { return finite(value.x) && finite(value.y) && finite(value.z) }

Layer :: enum {World, Actor, Trigger}
Layers :: bit_set[Layer]
AABB :: struct {min, max: Vec3}
Solid :: struct {bounds: AABB, id: u32, layer: Layer}
Body :: struct {
	position: Vec3, // Foot position; the upright capsule occupies [y, y+height].
	radius, height: f32,
	id: u32,
	layer: Layer,
}
Trigger :: struct {bounds: AABB, id: u32}
MAX_SOLIDS :: 64
MAX_ACTORS :: 16
MAX_TRIGGERS :: 16
World :: struct {
	solids: [MAX_SOLIDS]Solid,
	solid_count: int,
	actors: [MAX_ACTORS]Body,
	actor_count: int,
	triggers: [MAX_TRIGGERS]Trigger,
	trigger_count: int,
}
Move_Result :: struct {
	applied: Vec3,
	normal: Vec3,
	collided, depenetrated, blocked, valid: bool,
	hit_id: u32,
}
Ray_Hit :: struct {
	hit: bool,
	distance: f32,
	position, normal: Vec3,
	id: u32,
	layer: Layer,
}

valid_bounds :: proc(bounds: AABB) -> bool {
	return finite_vec(bounds.min) && finite_vec(bounds.max) &&
		bounds.min.x < bounds.max.x && bounds.min.y < bounds.max.y && bounds.min.z < bounds.max.z
}
valid_body :: proc(body: Body) -> bool {
	return finite_vec(body.position) && finite(body.radius) && finite(body.height) &&
		body.radius > 0 && body.height >= 2*body.radius && body.id > 0
}
valid_world :: proc(world: ^World) -> bool {
	return world != nil && world.solid_count >= 0 && world.solid_count <= MAX_SOLIDS &&
		world.actor_count >= 0 && world.actor_count <= MAX_ACTORS &&
		world.trigger_count >= 0 && world.trigger_count <= MAX_TRIGGERS
}
add_solid :: proc(world: ^World, bounds: AABB, id: u32 = 0) -> bool {
	if !valid_world(world) || !valid_bounds(bounds) || world.solid_count == MAX_SOLIDS { return false }
	world.solids[world.solid_count] = {bounds = bounds, id = id, layer = .World}
	world.solid_count += 1
	return true
}
add_actor :: proc(world: ^World, body: Body) -> bool {
	if !valid_world(world) || !valid_body(body) || world.actor_count == MAX_ACTORS { return false }
	for actor in world.actors[:world.actor_count] { if actor.id == body.id { return false } }
	world.actors[world.actor_count] = body
	world.actors[world.actor_count].layer = .Actor
	world.actor_count += 1
	return true
}
sync_actor :: proc(world: ^World, body: Body) -> bool {
	if !valid_world(world) || !valid_body(body) { return false }
	for &actor in world.actors[:world.actor_count] {
		if actor.id == body.id { actor = body; actor.layer = .Actor; return true }
	}
	return false
}
remove_actor :: proc(world: ^World, id: u32) -> bool {
	if !valid_world(world) { return false }
	for actor, index in world.actors[:world.actor_count] {
		if actor.id != id { continue }
		for offset in index..<world.actor_count-1 { world.actors[offset] = world.actors[offset+1] }
		world.actor_count -= 1
		world.actors[world.actor_count] = {}
		return true
	}
	return false
}
add_trigger :: proc(world: ^World, bounds: AABB, id: u32) -> bool {
	if !valid_world(world) || !valid_bounds(bounds) || world.trigger_count == MAX_TRIGGERS { return false }
	world.triggers[world.trigger_count] = {bounds = bounds, id = id}
	world.trigger_count += 1
	return true
}
