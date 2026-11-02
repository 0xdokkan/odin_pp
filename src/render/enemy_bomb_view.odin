package render

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import grid "../engine/grid"
import view "../engine/view"

// THE BOMBERS' BOMBS IN FLIGHT (game/enemy_bomb.odin, docs/piano-succo.md,
// Fase 5), as the board shows them. The user's choices of 2026-11-02: the
// bomb in the air is the very resin bomb that lands (draw_voxel_bomb), its
// fuse alight, tumbling along its arc, its shadow growing under it as it
// falls; the blast's 3×3 cells are marked from the throw, and over them a
// ring closes in on the bomb as its fuse burns (the MICCIA label stays).

// The arc: the hand's height, the top's height (more for a longer throw).
ENEMY_BOMB_HAND :: f32(0.55)
ENEMY_BOMB_APEX :: f32(0.9)
ENEMY_BOMB_APEX_PER_CELL :: f32(0.12)
// Turns in the air.
ENEMY_BOMB_TURNS :: f32(1.5)
// The ring: from around the 3×3 cells to the bomb's own cell; its width;
// red and flickering in the last second.
ENEMY_BOMB_RING_OUTER :: f32(1.5)
ENEMY_BOMB_RING_INNER :: f32(0.3)
ENEMY_BOMB_RING_WIDTH :: f32(0.07)
ENEMY_BOMB_RING_COLOR :: rl.Color{220, 115, 49, 255}
ENEMY_BOMB_RING_LAST :: f32(1)
ENEMY_BOMB_SEGMENTS :: 48

// The landed bomb's body centre over `cell` (voxel_object_bounds).
@(private = "file")
enemy_bomb_rest :: proc(cell: grid.Position) -> rl.Vector3 {
	_, height := game.grid_object_size(.Bomb)
	at := view.Vec2{f32(cell.x), f32(cell.y)}
	return {at.x+0.5, 0.035+point_ground(at)+height*0.5, at.y+0.5}
}

// Where a bomb `u` (0..1) along its arc from `origin` to `target` is, how
// high over the floor under it, and the way it flies on the floor.
enemy_bomb_arc :: proc(origin, target: grid.Position, u: f32) -> (at: rl.Vector3, lift: f32, way: rl.Vector3) {
	from := rl.Vector3{f32(origin.x)+0.5, point_ground({f32(origin.x), f32(origin.y)})+ENEMY_BOMB_HAND, f32(origin.y)+0.5}
	to := enemy_bomb_rest(target)
	cells := rl.Vector2Length({to.x-from.x, to.z-from.z})
	apex := ENEMY_BOMB_APEX+ENEMY_BOMB_APEX_PER_CELL*cells
	at = from+(to-from)*u+rl.Vector3{0, apex*4*u*(1-u), 0}
	ground := point_ground({at.x-0.5, at.z-0.5})
	lift = max(at.y-ground, 0)
	way = rl.Vector3{to.x-from.x, 0, to.z-from.z}
	if rl.Vector3Length(way) > 0.0001 { way = rl.Vector3Normalize(way) } else { way = {1, 0, 0} }
	return
}

// The ring's radius and whether it is in its last second, for a bomb whose
// blast is `left` world seconds away out of `fuse` from its landing.
enemy_bomb_ring :: proc(left, fuse: f32) -> (radius: f32, last: bool) {
	burnt := clamp(1-left/max(fuse, 0.001), 0, 1)
	return ENEMY_BOMB_RING_OUTER+(ENEMY_BOMB_RING_INNER-ENEMY_BOMB_RING_OUTER)*burnt, left <= ENEMY_BOMB_RING_LAST
}

// World seconds until a bomb's blast (game.resolve_due_explosives: on the beat
// whose count is one short of its detonation_pulse).
enemy_bomb_seconds_left :: proc(room: ^game.Room, detonation: u64) -> f32 {
	if room == nil || room.player == nil || detonation <= room.pulse_count { return 0 }
	return max(f32(detonation-room.pulse_count)-room.player.tactical.clock_fraction, 0)
}

// A flat ring on the floor round `centre`.
@(private = "file")
draw_enemy_bomb_ring :: proc(centre: rl.Vector3, radius: f32, color: rl.Color) {
	inner, outer := max(radius-ENEMY_BOMB_RING_WIDTH*0.5, 0), radius+ENEMY_BOMB_RING_WIDTH*0.5
	rlgl.Begin(rlgl.TRIANGLES)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	for index in 0..<ENEMY_BOMB_SEGMENTS {
		a0 := f32(index)/ENEMY_BOMB_SEGMENTS*math.TAU
		a1 := f32(index+1)/ENEMY_BOMB_SEGMENTS*math.TAU
		c0, s0, c1, s1 := math.cos(a0), math.sin(a0), math.cos(a1), math.sin(a1)
		p0 := centre+rl.Vector3{c0*inner, 0, s0*inner}
		p1 := centre+rl.Vector3{c0*outer, 0, s0*outer}
		p2 := centre+rl.Vector3{c1*outer, 0, s1*outer}
		p3 := centre+rl.Vector3{c1*inner, 0, s1*inner}
		rlgl.Vertex3f(p0.x, p0.y, p0.z); rlgl.Vertex3f(p1.x, p1.y, p1.z); rlgl.Vertex3f(p2.x, p2.y, p2.z)
		rlgl.Vertex3f(p0.x, p0.y, p0.z); rlgl.Vertex3f(p2.x, p2.y, p2.z); rlgl.Vertex3f(p3.x, p3.y, p3.z)
	}
	rlgl.End()
}

// The blast's 3×3 cells around `centre`, marked as a lit bomb's are.
@(private = "file")
draw_enemy_bomb_cells :: proc(renderer: ^Renderer, room: ^game.Room, centre: grid.Position, alpha: f32) {
	for y in centre.y-1..=centre.y+1 { for x in centre.x-1..=centre.x+1 {
		cell := grid.Position{x = x, y = y, layer = centre.layer}
		if tactical_render_visible(renderer, cell) && game.explosion_contains_cell(room, centre, cell) {
			draw_intent_cell(cell, 1, ENEMY_BOMB_RING_COLOR, alpha)
		}
	} }
}

// In the ground pass: for each bomb in the air its blast's cells and the ring
// round them, pulsing; for each lit bomb on the board its ring closing in.
@(private)
draw_enemy_bomb_floor :: proc(renderer: ^Renderer, room: ^game.Room) {
	if room == nil || room.phase != .Combat { return }
	now := f32(tactical_world_time(renderer))
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableBackfaceCulling() }
	for bomb in room.bombs.items[:room.bombs.count] {
		target := game.enemy_bomb_target(bomb)
		if !tactical_render_visible(renderer, target) { continue }
		pulse := 0.5+0.5*math.sin(now*14)
		draw_enemy_bomb_cells(renderer, room, target, 0.18+0.12*pulse)
		centre := rl.Vector3{f32(target.x)+0.5, 0.06+cell_overlay_ground(target), f32(target.y)+0.5}
		draw_enemy_bomb_ring(centre, ENEMY_BOMB_RING_OUTER, color_with_opacity(ENEMY_BOMB_RING_COLOR, 0.55+0.35*pulse))
	}
	for object in renderer.tactical.snapshot.objects[:renderer.tactical.snapshot.object_count] {
		if !object.visible || object.kind != .Bomb || object.detonation_pulse == 0 { continue }
		cell := grid.Position{x = int(math.round(object.position.x)), y = int(math.round(object.position.y))}
		if !tactical_render_visible(renderer, cell) { continue }
		left := enemy_bomb_seconds_left(room, object.detonation_pulse)
		radius, last := enemy_bomb_ring(left, f32(object.fuse_pulses)-game.ENEMY_BOMB_FLIGHT)
		color := GOTHIC_RED if last else ENEMY_BOMB_RING_COLOR
		lit := intent_flicker(left, f64(now), 0.3) if last else 1
		centre := rl.Vector3{object.position.x+0.5, 0.06+cell_overlay_ground(cell), object.position.y+0.5}
		draw_enemy_bomb_ring(centre, radius, color_with_opacity(color, 0.85*lit))
	}
}

// In the paper pass: each bomb in the air, tumbling along its arc, its fuse
// alight, its shadow under it growing as it falls.
@(private)
draw_enemy_bombs :: proc(renderer: ^Renderer, room: ^game.Room) {
	if room == nil || room.bombs.count == 0 { return }
	size, _ := game.grid_object_size(.Bomb)
	for bomb in room.bombs.items[:room.bombs.count] {
		u := game.enemy_bomb_progress(room, bomb)
		at, lift, way := enemy_bomb_arc(game.enemy_bomb_origin(bomb), game.enemy_bomb_target(bomb), u)
		cell := grid.Position{x = int(math.floor(at.x)), y = int(math.floor(at.z)), layer = i8(bomb.target.z)}
		if !tactical_render_visible(renderer, cell) { continue }
		// The shadow: small and faint high up, full as it lands.
		near := clamp(1-lift/(ENEMY_BOMB_APEX+0.5), 0, 1)
		ground := at.y-lift
		rl.DrawCircle3D({at.x, ground+0.03, at.z}, 0.1+0.16*near, {1, 0, 0}, 90, {0, 0, 0, u8(40+80*near)})
		if renderer.tactical.light_shader.id != 0 { begin_tactical_lighting(renderer) }
		rlgl.PushMatrix()
		rlgl.Translatef(at.x, at.y, at.z)
		// Tumbling forward, round the axis across its flight.
		rlgl.Rotatef(u*ENEMY_BOMB_TURNS*360, way.z, 0, -way.x)
		draw_voxel_bomb(renderer, {}, {size, size, size})
		rlgl.PopMatrix()
		rlgl.DrawRenderBatchActive()
		if renderer.tactical.light_shader.id != 0 { rl.EndShaderMode() }
	}
}
