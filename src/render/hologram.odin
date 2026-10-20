package render

import "core:fmt"
import "core:c"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import grid "../engine/grid"
import level "../level"

HOLOGRAM_EDGE :: rl.Color{58, 108, 140, 255}
HOLOGRAM_GLOW :: rl.Color{113, 207, 230, 255}

@(private = "file")
draw_hologram_table :: proc(renderer: ^Renderer, room: ^game.Room) {
	w, h := f32(room.level_data.tiles.width), f32(room.level_data.tiles.height)
	draw_resin_cube(renderer, {w*0.5, -0.13, h*0.5}, w+0.24, 0.08, h+0.24, {8, 17, 28, 255})
	draw_resin_cube(renderer, {w*0.5, -0.095, h*0.5}, w+0.13, 0.035, h+0.13, {27, 57, 77, 255})
	for y in 0..<room.level_data.tiles.height {
		for x in 0..<room.level_data.tiles.width {
			tile, _ := level.tile_at(room.level_data, {x, y})
			if tile.kind == .Void { continue }
			color := rl.Color{13, 25, 39, 255}
			if (x+y)%2 == 0 { color = {16, 30, 45, 255} }
			p := rl.Vector3{f32(x)+0.5, -0.025, f32(y)+0.5}
			draw_resin_cube(renderer, p, 0.97, 0.09, 0.97, color)
			if tile.kind == .Wall {
				height := f32(0.055) if level.is_border_position({x, y}, int(w), int(h)) else 0.46
				draw_resin_cube(renderer, {p.x, height*0.5, p.z}, 0.93, height, 0.93, {18, 33, 49, 255})
				draw_resin_cube(renderer, {p.x, height+0.015, p.z}, 0.88, 0.035, 0.88, {27, 48, 68, 255})
			}
			if tile.kind == .Exit { draw_voxel_exit(renderer, {x, y}) }
		}
	}
	for obstacle in room.obstacles {
		p := rl.Vector3{f32(obstacle.position.x)+0.5, 0.17, f32(obstacle.position.y)+0.5}
		draw_resin_cube(renderer, p, 0.67, 0.34, 0.67, {26, 48, 68, 255})
		draw_resin_cube(renderer, p+rl.Vector3{0, 0.18, 0}, 0.7, 0.06, 0.7, {39, 66, 86, 255})
	}
	snapshot := renderer.tactical.snapshot
	for object in snapshot.objects[:snapshot.object_count] {
		if object.visible { draw_voxel_object(renderer, object) }
	}
}

@(private = "file")
draw_hologram_threat :: proc(room: ^game.Room, cell: grid.Position) {
	tile, found := level.tile_at(room.level_data, cell)
	if !found || !level.is_walkable(tile.kind) { return }
	p := rl.Vector3{f32(cell.x)+0.5, 0.044, f32(cell.y)+0.5}
	rl.DrawPlane(p, {0.88, 0.88}, {210, 48, 72, 42})
	rl.DrawCubeWires(p, 0.88, 0.006, 0.88, {221, 74, 89, 225})
}

@(private = "file")
draw_hologram_projection :: proc(renderer: ^Renderer, room: ^game.Room) {
	w, h := f32(room.level_data.tiles.width), f32(room.level_data.tiles.height)
	rl.DrawCubeWires({w*0.5, -0.064, h*0.5}, w+0.14, 0.026, h+0.14, HOLOGRAM_GLOW)
	for y in 0..<room.level_data.tiles.height {
		for x in 0..<room.level_data.tiles.width {
			tile, _ := level.tile_at(room.level_data, {x, y})
			p := rl.Vector3{f32(x)+0.5, 0.029, f32(y)+0.5}
			if level.is_walkable(tile.kind) {
				// Narrow emissive rails survive the scene downsample more cleanly
				// than hairline wireframes, without lighting the entire cell.
				for sign in ([2]f32{-1, 1}) {
					rl.DrawCube(p+rl.Vector3{sign*0.475, 0, 0}, 0.022, 0.004, 0.972, {68, 141, 172, 215})
					rl.DrawCube(p+rl.Vector3{0, 0, sign*0.475}, 0.972, 0.004, 0.022, {68, 141, 172, 215})
				}
			} else if tile.kind == .Wall {
				border := level.is_border_position({x, y}, int(w), int(h))
				height := f32(0.091) if border else 0.496
				rl.DrawCubeWires({p.x, height*0.5, p.z}, 0.935, height, 0.935, {57, 114, 143, 205} if border else HOLOGRAM_GLOW)
			}
			if tile.kind == .Exit {
				for sign in ([2]f32{-1, 1}) {
					rl.DrawLine3D({p.x+sign*0.34, 0.06, p.z-0.16}, {p.x+sign*0.34, 0.91, p.z-0.16}, HOLOGRAM_GLOW)
					rl.DrawLine3D({p.x+sign*0.34, 0.91, p.z-0.16}, {p.x, 1.29, p.z-0.16}, HOLOGRAM_GLOW)
				}
			}
		}
	}
	for obstacle in room.obstacles {
		rl.DrawCubeWires({f32(obstacle.position.x)+0.5, 0.20, f32(obstacle.position.y)+0.5}, 0.71, 0.42, 0.71, HOLOGRAM_GLOW)
	}
	for x in 0..=room.level_data.tiles.width {
		if x%2 != 0 { continue }
		for z in ([2]f32{-0.10, h+0.10}) { rl.DrawCube({f32(x), -0.062, z}, 0.025, 0.015, 0.11, HOLOGRAM_GLOW) }
	}
	for y in 0..=room.level_data.tiles.height {
		if y%2 != 0 { continue }
		for x in ([2]f32{-0.10, w+0.10}) { rl.DrawCube({x, -0.062, f32(y)}, 0.11, 0.015, 0.025, HOLOGRAM_GLOW) }
	}
	// A faint scan crosses only the floor; the depth buffer keeps it behind cover.
	scan := f32(math.mod(renderer.sprite_assets.elapsed*0.65, f64(max(f32(1), h-2))))+1
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	rl.DrawCube({w*0.5, 0.033, scan}, w-2, 0.002, 0.055, {100, 202, 230, 90})
	if tactical_telegraphs_are_visible(renderer, room) {
		for &enemy in room.enemies {
			if game.enemy_is_staggered(room, &enemy) { continue }
			for cell in enemy.intent.threatened_cells[:enemy.intent.threatened_cell_count] { draw_hologram_threat(room, cell) }
			if enemy.intent.kind == .Charge {
				for cell in enemy.intent.path[:enemy.intent.path_count] { draw_hologram_threat(room, cell) }
			}
		}
	}
	snapshot := renderer.tactical.snapshot
	for object in snapshot.objects[:snapshot.object_count] {
		if !object.visible || object.detonation_pulse == 0 { continue }
		center := grid.Position{int(object.position.x), int(object.position.y)}
		for y in center.y-1..=center.y+1 { for x in center.x-1..=center.x+1 {
			if game.explosion_contains_cell(room, center, {x, y}) { draw_hologram_threat(room, {x, y}) }
		} }
	}
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
	draw_tactical_actor_bases(renderer)
}

@(private = "file")
draw_hologram_chrome :: proc(renderer: ^Renderer, room: ^game.Room) {
	tactical_hud_panel({14, 12, 270, 57}, HOLOGRAM_GLOW)
	gothic_text(renderer, "MAPPA OLOGRAFICA", 26, 19, 20, GOTHIC_PAPER)
	gothic_text_fit(renderer, fmt.ctprintf("%s / %s", level.room_family_name(room.family), game.encounter_kind_name(room.encounter_kind)),
		{26, 47, 246, 16}, 12, GOTHIC_MUTED)
	y := renderer.canvas_height-62
	tactical_hud_panel({14, y, renderer.canvas_width-28, 48}, HOLOGRAM_EDGE)
	p := renderer.tactical.snapshot.player.position
	gothic_text_fit(renderer, fmt.ctprintf("POS %d,%d / %dx%d", int(p.x), int(p.y), room.level_data.tiles.width, room.level_data.tiles.height),
		{26, y+9, 152, 16}, 12, GOTHIC_PAPER)
	gothic_text(renderer, "TRASCINA / ZOOM", 26, y+28, 10, GOTHIC_MUTED)
	rl.DrawRectangleRec({188, y+9, 1, 30}, {51, 69, 88, 180})
	labels := [?]cstring{"TU", "MELEE", "RANGED", "MINIBOSS", "BOSS", "USCITA"}
	figures := [?]int{0, 1, 2, 5, 6, 7}
	for label, i in labels {
		x := f32(200+i*97)
		gothic_atlas_icon(renderer.tactical.art.figures, renderer.tactical.art.figure_sources[figures[i]], {x, y+5, 30, 38})
		gothic_text_fit(renderer, label, {x+36, y+18, 57, 15}, 10, GOTHIC_PAPER if i == 0 else GOTHIC_MUTED)
	}
	gothic_button(renderer, tactical_map_reset_bounds(), "R", "RICENTRA")
}

draw_hologram :: proc(renderer: ^Renderer, room: ^game.Room) {
	rlgl.DrawRenderBatchActive()
	surface := begin_tactical_surface(renderer)
	if surface { rl.BeginMode2D({zoom = 2}) }
	draw_tactical_backdrop(renderer)
	if surface { rl.EndMode2D() }
	orbit := &renderer.tactical.hologram_orbit
	if !orbit.initialized { reset_tactical_orbit(orbit) }
	camera := tactical_hologram_camera(renderer, room.level_data.tiles.width, room.level_data.tiles.height, orbit^)
	// Reuse the actual actor art and alpha sorting with the map camera. These
	// view-only overrides must never leak into world picking or combat fog.
	previous_camera, previous_no_fog := renderer.tactical.camera, renderer.tactical.no_fog
	previous_outline := renderer.tactical.outline_mode
	renderer.tactical.outline_mode = .Hologram
	renderer.tactical.camera, renderer.tactical.no_fog = camera, true
	defer {
		renderer.tactical.camera, renderer.tactical.no_fog = previous_camera, previous_no_fog
		renderer.tactical.outline_mode = previous_outline
	}
	viewport := tactical_map_drag_bounds(renderer)
	if surface { viewport.x *= 2; viewport.y *= 2; viewport.width *= 2; viewport.height *= 2 }
	rl.BeginScissorMode(c.int(viewport.x), c.int(viewport.y), c.int(viewport.width), c.int(viewport.height))
	rl.BeginMode3D(camera)
	begin_tactical_lighting(renderer, true)
	draw_hologram_table(renderer, room)
	rl.EndShaderMode()
	draw_hologram_projection(renderer, room)
	draw_tactical_billboards(renderer)
	rl.EndMode3D()
	rl.EndScissorMode()
	end_tactical_surface(renderer, surface)
	draw_hologram_chrome(renderer, room)
}
