package render

import "core:c"
import "core:math"
import rl "vendor:raylib"
import game "../game"
import grid "../engine/grid"
import view "../engine/view"

Tactical_Visibility_Context :: struct {renderer: ^Renderer, room: ^game.Room}
@(private)
tactical_snapshot_opaque :: proc(data: rawptr, position: grid.Position) -> bool {
	state := cast(^Tactical_Visibility_Context)data
	return tactical_presentation_opaque(state.renderer, state.room, position)
}

@(private)
tactical_snapshot_height :: proc(data: rawptr, position: grid.Position) -> i32 {
	state := cast(^Tactical_Visibility_Context)data
	return game.cell_height(state.room, position)
}

Tactical_Orbit :: struct {
	yaw, pitch, distance: f32,
	initialized, dragging: bool,
	last_mouse: view.Vec2,
}
reset_tactical_orbit :: proc(orbit: ^Tactical_Orbit) {
	orbit^ = {yaw = math.PI/4, pitch = 0.68, distance = 12.5, initialized = true}
}
adjust_tactical_orbit :: proc(orbit: ^Tactical_Orbit, delta: view.Vec2, wheel: f32) {
	if !orbit.initialized { reset_tactical_orbit(orbit) }
	orbit.yaw = math.mod(orbit.yaw-delta.x*0.009, f32(math.PI*2))
	orbit.pitch = clamp(orbit.pitch+delta.y*0.007, f32(0.3), f32(1.45))
	orbit.distance = clamp(orbit.distance-wheel*0.7, f32(7), f32(24))
}
update_tactical_orbit_pointer :: proc(orbit: ^Tactical_Orbit, mouse: view.Vec2, inside, pressed, down: bool, wheel: f32) {
	if !orbit.initialized { reset_tactical_orbit(orbit) }
	if !down { orbit.dragging = false }
	if inside && pressed && down { orbit.dragging = true; orbit.last_mouse = mouse }
	if orbit.dragging {
		adjust_tactical_orbit(orbit, {mouse.x-orbit.last_mouse.x, mouse.y-orbit.last_mouse.y}, 0)
		orbit.last_mouse = mouse
	}
	if inside { adjust_tactical_orbit(orbit, {}, wheel) }
}
@(private)
tactical_orbit_camera :: proc(orbit: Tactical_Orbit, target: rl.Vector3, perspective: bool) -> rl.Camera3D {
	distance := orbit.distance
	return {position = target+rl.Vector3{math.cos(orbit.yaw)*math.cos(orbit.pitch), math.sin(orbit.pitch),
		math.sin(orbit.yaw)*math.cos(orbit.pitch)}*distance,
		target = target, up = {0, 1, 0}, fovy = (f32(40) if perspective else distance*0.65),
		projection = (.PERSPECTIVE if perspective else .ORTHOGRAPHIC)}
}

tactical_world_bounds :: proc(renderer: ^Renderer) -> rl.Rectangle {
	return {12, TACTICAL_HUD_HEIGHT, renderer.canvas_width-24, renderer.canvas_height-TACTICAL_HUD_HEIGHT-TACTICAL_HAND_HEIGHT-8}
}
tactical_map_button_bounds :: proc(renderer: ^Renderer) -> rl.Rectangle {
	return tactical_map_controls_bounds(renderer)
}
tactical_map_reset_bounds :: proc() -> rl.Rectangle { return {809, 486, 137, 25} }
tactical_map_drag_bounds :: proc(renderer: ^Renderer) -> rl.Rectangle {
	return {14, TACTICAL_HUD_HEIGHT, renderer.canvas_width-28, renderer.canvas_height-TACTICAL_HUD_HEIGHT-78}
}
@(private = "file")
draw_tactical_button :: proc(bounds: rl.Rectangle, label: cstring, color: rl.Color) {
	rl.DrawRectangleRec(bounds, rl.Color{18, 39, 54, 255})
	rl.DrawRectangleLinesEx(bounds, 1, color)
	rl.DrawText(label, c.int(bounds.x+10), c.int(bounds.y+10), 12, color)
}

// Raylib's OpenGL 3.3 renderer supplies real perspective, normals and depth.
// These vertices are world-space immediate geometry; actors keep their 2D art.
@(private)
create_tactical_lighting :: proc(renderer: ^Renderer) {
	v := &renderer.tactical
	v.light_shader = rl.LoadShaderFromMemory(TACTICAL_LIGHT_VERTEX, TACTICAL_LIGHT_FRAGMENT)
	v.light_position_location = rl.GetShaderLocation(v.light_shader, "lantern")
	v.light_hologram_location = rl.GetShaderLocation(v.light_shader, "hologram")
	v.light_eye_location = rl.GetShaderLocation(v.light_shader, "eye")
	v.light_clear_location = rl.GetShaderLocation(v.light_shader, "roomClear")
	v.light_accents_location = rl.GetShaderLocation(v.light_shader, "accentLights[0]")
}
@(private)
begin_tactical_lighting :: proc(renderer: ^Renderer, hologram: bool = false, accents: [4]rl.Vector4 = {}) {
	v := &renderer.tactical
	p := v.snapshot.player.position
	begin_resin_lighting(renderer, {
		eye = v.camera.position, lantern = {p.x+0.5, 2.8, p.y+0.5},
		mode = .Hologram if hologram else .Board, clear = v.clear_light, accents = accents,
	})
}
@(private)
draw_tactical_actor_bases :: proc(renderer: ^Renderer) {
	snapshot := renderer.tactical.snapshot
	// The Pinball's ball has its own shadow, and no stand (pinball.odin).
	draw_pinball_shadow(renderer)
	for actor in snapshot.enemies[:snapshot.enemy_count] {
		cell := grid.Position{int(math.round(actor.position.x)), int(math.round(actor.position.y))}
		if !actor.visible || !tactical_render_visible(renderer, cell) || tactical_pinball_holds(renderer, actor.entity) { continue }
		key := sprite_key_for_enemy(actor.archetype)
		at, _ := living_card_position(renderer, actor.entity, key, actor.position)
		ground := rim_ground(at, 0.32)
		p := rl.Vector3{at.x+0.5, 0.048+ground, at.y+0.5}
		draw_tactical_actor_shadow(p, ground)
		// Up on the Lazzo's rope: its shadow on the floor, and the stand it
		// carries (lasso.odin).
		if tactical_lasso_holds(renderer, actor.entity) {
			if renderer.tactical.flipbook.loaded { draw_flipbook_stand(renderer, key, actor.position, GOTHIC_RED, actor.entity) }
			continue
		}
		rl.DrawCylinder(p, 0.3, 0.3, 0.01, 24, GOTHIC_INK)
		rl.DrawCircle3D(p+rl.Vector3{0, 0.01, 0}, 0.32, {1, 0, 0}, 90, GOTHIC_RED)
		if renderer.tactical.flipbook.loaded { draw_flipbook_stand(renderer, key, actor.position, GOTHIC_RED, actor.entity) }
	}
	// Behind his eyes the player stands on no stand of his own.
	if !snapshot.player.visible || first_person_hides_player(renderer) { return }
	// In the shadow the pool takes the stand's place while the card is under
	// the floor; out of it (casting before it sinks, or sprung out at the end
	// of the rise) the card keeps its stand.
	if tactical_shadow_showing(renderer) {
		draw_tactical_shadow_pool(renderer)
		if tactical_shadow_depth(renderer, game.PLAYER_ENTITY) > 0 { return }
	}
	at, _ := living_card_position(renderer, game.PLAYER_ENTITY, .Player, snapshot.player.position)
	ground := rim_ground(at, 0.34)
	p := rl.Vector3{at.x+0.5, 0.05+ground, at.y+0.5}
	draw_tactical_actor_shadow(p, ground)
	rl.DrawCylinder(p, 0.32, 0.32, 0.01, 24, GOTHIC_INK)
	rl.DrawCircle3D(p+rl.Vector3{0, 0.01, 0}, 0.34, {1, 0, 0}, 90, GOTHIC_PAPER)
	if renderer.tactical.flipbook.loaded { draw_flipbook_stand(renderer, .Player, snapshot.player.position, GOTHIC_PAPER, game.PLAYER_ENTITY) }
}

@(private = "file")
draw_tactical_actor_shadow :: proc(position: rl.Vector3, ground: f32) {
	// Nested low-opacity discs give the sprite a soft contact edge, contained
	// within its tile and independent of animation duration or gameplay state.
	// They lie on the ground the stand stands on.
	for layer in 0..<4 {
		radius := f32(0.44)-f32(layer)*0.045
		rl.DrawCylinder({position.x, ground+0.024+f32(layer)*0.001, position.z}, radius, radius, 0.001, 24, {1, 5, 12, u8(7+layer*4)})
	}
}
