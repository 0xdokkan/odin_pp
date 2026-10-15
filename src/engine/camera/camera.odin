// Cameras for 2D and 3D minigames. State and motion are plain math; the
// `*_to_raylib` procedures produce the raylib camera for drawing.
package camera

import "core:math"
import rl "vendor:raylib"
import tween "../tween"

Vec2 :: [2]f32
Vec3 :: [3]f32

// Screen shake driven by "trauma" in [0, 1]: impulses add trauma, it decays
// linearly, and the offset grows with trauma squared so small hits stay calm.
Shake :: struct {
	trauma:      f32,
	decay:       f32, // trauma lost per second
	max_offset:  f32, // pixels (2D) or world units (3D) at full trauma
	max_roll:    f32, // radians at full trauma
	time:        f32,
	seed:        f32,
}

shake_default :: proc(max_offset: f32 = 10) -> Shake {
	return Shake{decay = 1.6, max_offset = max_offset, max_roll = 0.03, seed = 17.3}
}

add_trauma :: proc(s: ^Shake, amount: f32) {
	s.trauma = clamp(s.trauma+amount, 0, 1)
}

shake_update :: proc(s: ^Shake, dt: f32) {
	s.time += dt
	s.trauma = max(s.trauma-s.decay*dt, 0)
}

// Smooth pseudo-noise: deterministic, no RNG state to carry around.
@(private)
wobble :: proc "contextless" (t, seed: f32) -> f32 {
	return math.sin(t*23.1+seed)*0.5 + math.sin(t*37.7+seed*2.3)*0.3 + math.sin(t*61.3+seed*0.7)*0.2
}

shake_offset :: proc(s: Shake) -> (offset: Vec2, roll: f32) {
	k := s.trauma * s.trauma
	offset = Vec2{wobble(s.time, s.seed), wobble(s.time, s.seed+40)} * (s.max_offset * k)
	roll = wobble(s.time, s.seed+80) * s.max_roll * k
	return
}

// Follows a target with a dead zone and exponential smoothing, clamped to the
// level bounds. `position` is the world point shown at the canvas centre.
Camera2 :: struct {
	position:  Vec2,
	zoom:      f32,
	deadzone:  Vec2, // half-size of the rectangle the target may move in freely
	smoothing: f32,  // higher is snappier; 0 snaps instantly
	// Level area in world units; zero size disables clamping.
	bounds_min, bounds_max: Vec2,
	// Extra offset toward where the target is heading.
	lookahead: Vec2,
	shake:     Shake,
}

camera2_create :: proc(position: Vec2, zoom: f32 = 1) -> Camera2 {
	return Camera2{position = position, zoom = zoom, deadzone = {24, 16}, smoothing = 8, shake = shake_default()}
}

camera2_update :: proc(c: ^Camera2, target: Vec2, view_size: Vec2, dt: f32) {
	goal := c.position
	focus := target + c.lookahead
	for axis in 0..<2 {
		d := focus[axis] - c.position[axis]
		if d > c.deadzone[axis] {
			goal[axis] = focus[axis] - c.deadzone[axis]
		} else if d < -c.deadzone[axis] {
			goal[axis] = focus[axis] + c.deadzone[axis]
		}
	}
	if c.smoothing <= 0 {
		c.position = goal
	} else {
		c.position = tween.damp(c.position, goal, c.smoothing, dt)
	}
	camera2_clamp(c, view_size)
	shake_update(&c.shake, dt)
}

camera2_clamp :: proc(c: ^Camera2, view_size: Vec2) {
	if c.bounds_max.x <= c.bounds_min.x || c.bounds_max.y <= c.bounds_min.y {
		return
	}
	half := view_size * 0.5 / max(c.zoom, 0.01)
	for axis in 0..<2 {
		lo := c.bounds_min[axis] + half[axis]
		hi := c.bounds_max[axis] - half[axis]
		if lo > hi {
			c.position[axis] = (c.bounds_min[axis] + c.bounds_max[axis]) * 0.5
		} else {
			c.position[axis] = clamp(c.position[axis], lo, hi)
		}
	}
}

camera2_to_raylib :: proc(c: Camera2, view_size: Vec2) -> rl.Camera2D {
	offset, roll := shake_offset(c.shake)
	return rl.Camera2D{
		offset   = view_size*0.5 + offset,
		target   = {math.round(c.position.x), math.round(c.position.y)},
		rotation = roll * 180 / math.PI,
		zoom     = c.zoom,
	}
}

screen_to_world2 :: proc(c: Camera2, view_size: Vec2, screen: Vec2) -> Vec2 {
	return (screen - view_size*0.5) / max(c.zoom, 0.01) + c.position
}

// First-person view: yaw around +y (0 looks toward +z), pitch up positive.
Fps_Camera :: struct {
	position:    Vec3,
	yaw, pitch:  f32,
	fov:         f32,
	sensitivity: f32, // radians per mouse pixel
	bob_time:    f32,
	bob_amount:  f32,
	shake:       Shake,
}

fps_create :: proc(position: Vec3, yaw: f32 = 0) -> Fps_Camera {
	s := shake_default(0.08)
	s.max_roll = 0.02
	return Fps_Camera{position = position, yaw = yaw, fov = 75, sensitivity = 0.0025, shake = s}
}

fps_look :: proc(c: ^Fps_Camera, mouse_delta: Vec2) {
	c.yaw -= mouse_delta.x * c.sensitivity
	c.pitch = clamp(c.pitch-mouse_delta.y*c.sensitivity, -1.45, 1.45)
}

fps_forward :: proc "contextless" (c: Fps_Camera) -> Vec3 {
	cp := math.cos(c.pitch)
	return Vec3{math.sin(c.yaw) * cp, math.sin(c.pitch), math.cos(c.yaw) * cp}
}

// Horizontal basis for movement: forward on the ground plane and right.
fps_ground_basis :: proc "contextless" (yaw: f32) -> (forward, right: Vec2) {
	forward = Vec2{math.sin(yaw), math.cos(yaw)}
	right = Vec2{-forward.y, forward.x}
	return
}

fps_update :: proc(c: ^Fps_Camera, moving_speed: f32, dt: f32) {
	if moving_speed > 0.5 {
		c.bob_time += dt * (6 + moving_speed*0.6)
		c.bob_amount = min(c.bob_amount+dt*4, 1)
	} else {
		c.bob_amount = max(c.bob_amount-dt*4, 0)
	}
	shake_update(&c.shake, dt)
}

fps_to_raylib :: proc(c: Fps_Camera) -> rl.Camera3D {
	offset, roll := shake_offset(c.shake)
	bob := math.sin(c.bob_time) * 0.04 * c.bob_amount
	eye := c.position + Vec3{0, bob + offset.y, 0}
	fwd := fps_forward(c)
	right := Vec3{-math.cos(c.yaw), 0, math.sin(c.yaw)}
	eye += right * offset.x
	up := Vec3{0, 1, 0} + right*math.sin(roll)
	return rl.Camera3D{position = eye, target = eye + fwd, up = up, fovy = c.fov, projection = .PERSPECTIVE}
}

// Third-person orbit that trails a target, used by 3D platforming. yaw 0 puts
// the camera on -z looking toward +z.
Orbit_Camera :: struct {
	target:     Vec3,
	yaw, pitch: f32,
	distance:   f32,
	height:     f32, // look-at point above the target
	smoothing:  f32,
	fov:        f32,
	focus:      Vec3,
	shake:      Shake,
}

orbit_create :: proc(target: Vec3) -> Orbit_Camera {
	return Orbit_Camera{target = target, focus = target, pitch = 0.45, distance = 9, height = 1.2,
		smoothing = 10, fov = 55, shake = shake_default(0.15)}
}

orbit_rotate :: proc(c: ^Orbit_Camera, delta_yaw, delta_pitch: f32) {
	c.yaw += delta_yaw
	c.pitch = clamp(c.pitch+delta_pitch, 0.08, 1.35)
}

orbit_update :: proc(c: ^Orbit_Camera, target: Vec3, dt: f32) {
	c.target = target
	k := 1 - math.exp(-c.smoothing*dt) if c.smoothing > 0 else 1
	c.focus += (target - c.focus) * k
	shake_update(&c.shake, dt)
}

orbit_eye :: proc "contextless" (c: Orbit_Camera) -> Vec3 {
	look := c.focus + Vec3{0, c.height, 0}
	cp := math.cos(c.pitch)
	return look + Vec3{-math.sin(c.yaw) * cp, math.sin(c.pitch), -math.cos(c.yaw) * cp} * c.distance
}

// Camera-relative movement basis on the ground plane. `right` is screen-right:
// looking toward +z (yaw 0) with +y up, that is -x in raylib's right-handed space.
orbit_ground_basis :: proc "contextless" (c: Orbit_Camera) -> (forward, right: Vec2) {
	forward = Vec2{math.sin(c.yaw), math.cos(c.yaw)}
	right = Vec2{-forward.y, forward.x}
	return
}

orbit_to_raylib :: proc(c: Orbit_Camera) -> rl.Camera3D {
	offset, _ := shake_offset(c.shake)
	look := c.focus + Vec3{0, c.height, 0}
	eye := orbit_eye(c) + Vec3{offset.x, offset.y, 0}
	return rl.Camera3D{position = eye, target = look, up = {0, 1, 0}, fovy = c.fov, projection = .PERSPECTIVE}
}
