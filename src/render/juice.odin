package render

import "core:math"
import "core:math/noise"
import rl "vendor:raylib"

// THE JUICE OF THE BLOWS (docs/piano-succo.md, Fase 1): the board's camera
// shakes and the pictures hold a moment when a blow lands.
//
// The shake follows Squirrel Eiserloh's «trauma»: every event adds trauma
// (0..1), the shake is trauma², it moves along a smooth noise rather than at
// random, and the trauma wears away on its own. It moves only the picture:
// the aim (the cell under the mouse, the free walk's directions) reads the
// camera before it shakes, and its forward never turns.
//
// The hit-stop holds the pictures for a few hundredths of a second. It is a
// cinematic moment, as a die's throw is (cast_playback.odin): the world gains
// no time from it and the rules never see it; the shake goes on through it
// (the user's choice). The profile's «Scuotimento» scales both (0: none).

// The user's numbers of 2026-11-01: 0.12 cells, 0.8°, gone in 0.35 s.
JUICE_SHAKE_OFFSET :: f32(0.12)
JUICE_SHAKE_ROLL_DEGREES :: f32(0.8)
JUICE_TRAUMA_SECONDS :: f32(0.35)
// How quickly the shake's noise turns (samples a second).
JUICE_SHAKE_FREQUENCY :: f32(22)
// Never more than one hit-stop in this many seconds: a volley does not jam.
JUICE_HIT_STOP_GAP :: f32(0.15)
// The longest hit-stop asked for (the strongest blows' 100 ms, with a margin).
JUICE_HIT_STOP_MAX :: f32(0.12)
@(private = "file")
JUICE_SEED :: i64(0x51CC0)

Juice_State :: struct {
	trauma: f32,
	// The shake's own seconds: they run through a hit-stop.
	clock: f64,
	// Seconds of hit-stop left, and seconds since the last one began (if one has).
	hold, since_hold: f32,
	stopped: bool,
	// The profile's «Scuotimento» (0..1), once a scene has set it.
	strength: f32,
	strength_set: bool,
}

// The strength the scene reads from the profile each frame (0 turns the juice off).
set_renderer_juice_strength :: proc(renderer: ^Renderer, strength: f32) {
	if renderer == nil { return }
	renderer.juice.strength = clamp(strength, 0, 1) if !math.is_nan(strength) else 1
	renderer.juice.strength_set = true
}

@(private)
juice_strength :: proc(renderer: ^Renderer) -> f32 {
	return renderer.juice.strength if renderer.juice.strength_set else 1
}

// Adds `trauma` (0..1) to the camera's shake, at the profile's strength.
juice_shake :: proc(renderer: ^Renderer, trauma: f32) {
	if renderer == nil || !(trauma > 0) { return }
	j := &renderer.juice
	j.trauma = clamp(j.trauma+trauma*juice_strength(renderer), 0, 1)
}

// Holds the pictures `seconds` (at the profile's strength), unless one began
// less than JUICE_HIT_STOP_GAP ago. Whether it began.
juice_hit_stop :: proc(renderer: ^Renderer, seconds: f32) -> bool {
	if renderer == nil || !(seconds > 0) { return false }
	j := &renderer.juice
	held := min(seconds, JUICE_HIT_STOP_MAX)*juice_strength(renderer)
	if held <= 0 || j.hold > 0 || (j.stopped && j.since_hold < JUICE_HIT_STOP_GAP) { return false }
	j.hold, j.since_hold, j.stopped = held, 0, true
	return true
}

// Whether the pictures are held this moment (a hit-stop runs): what a scene
// asks before it updates the frame's timeline.
renderer_hit_stopped :: proc(renderer: ^Renderer) -> bool {
	return renderer != nil && renderer.juice.hold > 0
}

// Whether the frame just updated (update_renderer_frame_timeline) was held,
// its last held frame included: what a scene asks after that update.
renderer_frame_held :: proc(renderer: ^Renderer) -> bool {
	return renderer != nil && renderer.frame_had_hit_stop
}

// The frame's seconds: the trauma wears away and the shake's clock runs, a
// hit-stop or not; a hit-stop takes what it still holds. Whether this frame
// was held.
@(private)
update_juice :: proc(renderer: ^Renderer, dt: f32) -> (held: bool) {
	j := &renderer.juice
	if !(dt > 0 && dt < max(f32)) { return j.hold > 0 }
	j.trauma = max(0, j.trauma-dt/JUICE_TRAUMA_SECONDS)
	j.clock += f64(dt)
	if j.hold > 0 {
		j.hold = max(0, j.hold-dt)
		if j.hold < 0.00001 { j.hold = 0 }
		held = true
	}
	j.since_hold = min(j.since_hold+dt, 1000)
	return
}

// The camera as the board draws it: shaken by the trauma's square, along the
// noise, its forward unchanged (position and target move together; the roll
// turns only its up).
juice_camera :: proc(camera: rl.Camera3D, trauma: f32, clock: f64) -> rl.Camera3D {
	shake := trauma*trauma
	if shake <= 0 { return camera }
	t := f32(clock)*JUICE_SHAKE_FREQUENCY
	sample :: proc(k: f32, t: f32) -> f32 { return noise.noise_2d(JUICE_SEED, {f64(t), f64(k*17.3)}) }
	forward := rl.Vector3Normalize(camera.target-camera.position)
	right := rl.Vector3Normalize(rl.Vector3CrossProduct(forward, camera.up))
	up := rl.Vector3CrossProduct(right, forward)
	offset := (right*sample(1, t)+up*sample(2, t))*(JUICE_SHAKE_OFFSET*shake)
	roll := sample(3, t)*JUICE_SHAKE_ROLL_DEGREES*shake*math.RAD_PER_DEG
	shaken := camera
	shaken.position += offset
	shaken.target += offset
	shaken.up = up*math.cos(roll)+right*math.sin(roll)
	return shaken
}

// Shakes the board's camera for the drawings, after the aim has read it.
// Behind the player's eyes the view has its own shake (first_person.odin).
@(private)
juice_shake_board_camera :: proc(renderer: ^Renderer) {
	v := &renderer.tactical
	if renderer.juice.trauma <= 0 || first_person_amount(renderer) > 0 { return }
	v.camera = juice_camera(v.camera, renderer.juice.trauma, renderer.juice.clock)
}
