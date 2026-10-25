package render

import "core:math"
import rl "vendor:raylib"
import game "../game"
import grid "../engine/grid"
import level "../level"

TACTICAL_CLEAR_SECONDS :: f32(1.2)

@(private)
tactical_room_is_clear :: proc(phase: game.Room_Phase) -> bool {
	return phase == .Loot || phase == .Complete
}

// A cleared room's exit is open: its portal and its USCITA show. The
// mechanics sandbox cleared for the rod (F7) keeps it shut, as
// try_move_player does.
tactical_exit_is_open :: proc(room: ^game.Room, phase: game.Room_Phase) -> bool {
	return room != nil && tactical_room_is_clear(phase) && !room.endless
}

// Presentation owns this fade: killing the final enemy must still play its hit
// before revealing the room. Combat always resets it, including a reused Room.
update_tactical_atmosphere :: proc(renderer: ^Renderer, dt: f32) {
	v := &renderer.tactical
	if v.snapshot == nil { return }
	if !tactical_room_is_clear(v.snapshot.phase) { v.clear_light = 0; return }
	if dt > 0 && dt < max(f32) { v.clear_light = min(f32(1), v.clear_light+dt/TACTICAL_CLEAR_SECONDS) }
}

// Bounded, terrain-clipped contact shadows; no extra render target or shadow map.
// The key light comes from -X/-Z, so the short wall shadows fall toward +X/+Z.
@(private)
draw_tactical_ground_shadows :: proc(renderer: ^Renderer, room: ^game.Room) {
	for y in 0..<room.level_data.tiles.height {
		for x in 0..<room.level_data.tiles.width {
			cell := grid.Position{x = x, y = y}
			if !tactical_cell_on_screen(renderer, cell) || !tactical_render_visible(renderer, cell) { continue }
			tile, _ := level.tile_at(room.level_data, cell)
			if tile.kind != .Floor && tile.kind != .Exit { continue }
			for offset in ([2]grid.Position{{x = -1, y = 0}, {x = 0, y = -1}}) {
				neighbor := grid.Position{x = x+offset.x, y = y+offset.y}
				wall, found := level.tile_at(room.level_data, neighbor)
				if !found || wall.kind != .Wall || !tactical_render_visible(renderer, neighbor) { continue }
				for layer in 0..<3 {
					width := 0.16+f32(layer)*0.12
					p := rl.Vector3{f32(x)+0.5+f32(offset.x)*(0.47-width/2), 0.022+f32(3-layer)*0.001, f32(y)+0.5+f32(offset.y)*(0.47-width/2)}
					size := rl.Vector2{width, 0.92} if offset.x != 0 else rl.Vector2{0.92, width}
					rl.DrawPlane(p, size, {3, 8, 17, u8(32-layer*7)})
				}
			}
		}
	}
}

@(private)
draw_tactical_loot :: proc(renderer: ^Renderer, item: Presentation_Loot) {
	p := rl.Vector3{f32(item.position.x)+0.5, 0.13, f32(item.position.y)+0.5}
	if item.kind == .Weapon {
		draw_resin_cube(renderer,p+rl.Vector3{0,0.11,0},0.09,0.40,0.09,RESIN_WALL)
		draw_resin_cube(renderer,p+rl.Vector3{0.12,0.34,0},0.35,0.22,0.08,GOTHIC_BLUE)
		return
	}
	tint := rl.Color{210, 174, 79, 255} if item.kind == .Gold else rl.Color{112, 198, 177, 255}
	draw_resin_cube(renderer, p, 0.23, 0.16, 0.23, tint)
	draw_resin_cube(renderer, p+rl.Vector3{0, 0.1, 0}, 0.12, 0.06, 0.12, GOTHIC_PAPER)
}

@(private)
draw_tactical_clear_markers :: proc(renderer: ^Renderer, room: ^game.Room) {
	v := &renderer.tactical
	if !tactical_room_is_clear(v.snapshot.phase) { return }
	alpha := 0.4+v.clear_light*0.6
	color := color_with_opacity(rl.Color{124, 199, 215, 255}, alpha)
	// The mechanics sandbox cleared for the rod keeps its exit shut: no portal.
	if tactical_exit_is_open(room, v.snapshot.phase) {
		exit := room.exit_position
		p := rl.Vector3{f32(exit.x)+0.5, 0.06, f32(exit.y)+0.5}
		rl.DrawCubeWires(p, 0.91, 0.02, 0.91, color)
		// Low, open portal rails keep the actor and walkable tile unobscured.
		for sign in ([2]f32{-1, 1}) {
			rl.DrawCube(p+rl.Vector3{sign*0.34, 0.42, 0.16}, 0.035, 0.8, 0.04, color)
		}
	}
	for item in v.snapshot.loot[:v.snapshot.loot_count] {
		if !item.visible { continue }
		center := rl.Vector3{f32(item.position.x)+0.5, 0.052, f32(item.position.y)+0.5}
		rl.DrawCircle3D(center, 0.27, {1, 0, 0}, 90, color_with_opacity(rl.GOLD, alpha))
	}
	if v.clear_light > 0 && v.clear_light < 1 {
		player := v.snapshot.player.position
		radius := v.clear_light*8
		rl.DrawCircle3D({player.x+0.5, 0.055, player.y+0.5}, radius, {1, 0, 0}, 90,
			color_with_opacity(color, math.sin(v.clear_light*math.PI)*0.35))
	}
}
