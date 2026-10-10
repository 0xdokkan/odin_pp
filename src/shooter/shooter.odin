// Package shooter owns a small continuous-space FPS simulation. It has no
// renderer, input-device, tactical-grid or save dependencies.
package shooter

import "core:math"
import "../engine"

FIXED_DT :: f32(engine.FIXED_DT)
MAX_ENEMIES :: 3
PLAYER_RADIUS :: f32(0.32)
PLAYER_HEIGHT :: f32(1.75)
EYE_HEIGHT :: f32(1.48)
ENEMY_RADIUS :: f32(0.38)
ENEMY_HEIGHT :: f32(1.8)
MAGAZINE_SIZE :: 6
WEAPON_DAMAGE :: 12
WEAPON_COOLDOWN :: f32(0.24)
RELOAD_DURATION :: f32(1.2)
WEAPON_RANGE :: f32(40)
ENEMY_WINDUP :: f32(0.85)
ENEMY_RECOVERY :: f32(1.65)
ENEMY_DAMAGE :: 8

Phase :: enum { Active, Won, Lost }
Enemy_Phase :: enum { Hunt, Windup, Recovery, Dead }

// Look values are radians of relative rotation, consumed exactly once by the
// caller. Forward is +Z at yaw=0; positive yaw looks toward +X. Positive pitch
// looks upward. move_right is camera-relative (cross(forward, world up)).
// Reload is an edge, fire is held/autofire.
Input :: struct {
	move_forward, move_right: f32,
	look_yaw, look_pitch:     f32,
	fire_held:                bool,
	reload_pressed:           bool,
}

Player :: struct {
	position:                                  engine.Vec3,
	yaw, pitch:                                f32,
	health, ammo, reserve:                      int,
	reload_remaining, cooldown, recoil:         f32,
	damage_flash:                              f32,
}

Enemy :: struct {
	position, aim_target: engine.Vec3,
	yaw:                  f32,
	health:               int,
	phase:                Enemy_Phase,
	phase_remaining:      f32,
	damage_flash:         f32,
}

Shot_Trace :: struct {
	start, end: engine.Vec3,
	remaining:  f32,
	enemy, hit: bool,
}

State :: struct {
	world:          engine.World,
	player:         Player,
	enemies:        [MAX_ENEMIES]Enemy,
	enemy_count:    int,
	shots:          [MAX_ENEMIES+1]Shot_Trace,
	phase:          Phase,
	level_index:    int,
	ticks:          u64,
	elapsed:        f32,
	hit_marker:     f32,
	shots_fired:    int,
	kills:          int,
}

level_count :: proc() -> int { return 2 }

level_name :: proc(index: int) -> string {
	return "NAVATA" if index%2 == 0 else "CORTILE"
}

create :: proc(level_index: int = 0) -> State {
	state: State
	reset(&state, level_index)
	return state
}

finite_axis :: proc(value: f32) -> f32 {
	if math.is_nan(value) || math.is_inf(value) { return 0 }
	return clamp(value, -1, 1)
}

finite_look :: proc(value: f32) -> f32 {
	if math.is_nan(value) || math.is_inf(value) { return 0 }
	return clamp(value, -f32(math.PI), f32(math.PI))
}

look_direction :: proc(yaw, pitch: f32) -> engine.Vec3 {
	return {math.sin(yaw)*math.cos(pitch), math.sin(pitch), math.cos(yaw)*math.cos(pitch)}
}

eye_position :: proc(state: ^State) -> engine.Vec3 {
	if state == nil { return {} }
	return engine.vec_add(state.player.position, {0, EYE_HEIGHT, 0})
}

living_enemies :: proc(state: ^State) -> int {
	if state == nil { return 0 }
	count := 0
	for enemy in state.enemies[:state.enemy_count] {
		if enemy.health > 0 { count += 1 }
	}
	return count
}
