package render

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import canvas_target "../engine/canvas"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import grid "../engine/grid"
import level "../level"

HOLOGRAM_EDGE :: rl.Color{58, 108, 140, 255}
HOLOGRAM_GLOW :: rl.Color{113, 207, 230, 255}
HOLOGRAM_DECK :: rl.Color{24, 45, 64, 255}

// THE ROOM'S RELIEF (Fase 8 of docs/piano-profondita.md): every cell of the table stands as high as its floor on the
// board (cell_ground), and the decks over the ground (a bridge, a walkway) are slabs at their height, so that the
// figures, drawn where they stand, stand on them. A flat room is drawn as before.

// The decks over the ground: each cell with a floor on a layer over it, and its height on the board.
@(private = "file")
Hologram_Deck :: struct { cell: grid.Position, kind: level.Tile_Kind, ground: f32 }

@(private = "file")
hologram_decks :: proc(room: ^game.Room) -> [dynamic]Hologram_Deck {
	decks := make([dynamic]Hologram_Deck, context.temp_allocator)
	width := room.level_data.tiles.width
	for layer in grid.GROUND_LAYER+1..=grid.HIGHEST_LAYER {
		for tile, index in room.level_data.planes[level.layer_slot(i8(layer))].tiles {
			if !level.kind_has_floor(tile.kind) { continue }
			cell := grid.Position{x = index%width, y = index/width, layer = i8(layer)}
			append(&decks, Hologram_Deck{cell, tile.kind, cell_ground(cell)})
		}
	}
	return decks
}

@(private = "file")
draw_hologram_table :: proc(renderer: ^Renderer, room: ^game.Room) {
	w, h := f32(room.level_data.tiles.width), f32(room.level_data.tiles.height)
	draw_resin_cube(renderer, {w*0.5, -0.13, h*0.5}, w+0.24, 0.08, h+0.24, {8, 17, 28, 255})
	draw_resin_cube(renderer, {w*0.5, -0.095, h*0.5}, w+0.13, 0.035, h+0.13, {27, 57, 77, 255})
	for y in 0..<room.level_data.tiles.height {
		for x in 0..<room.level_data.tiles.width {
			tile, _ := level.tile_at(room.level_data, {x = x, y = y})
			if tile.kind == .Void { continue }
			color := rl.Color{13, 25, 39, 255}
			if (x+y)%2 == 0 { color = {16, 30, 45, 255} }
			// A raised cell is a column from the table up to its floor.
			ground := cell_ground({x = x, y = y})
			p := rl.Vector3{f32(x)+0.5, -0.025, f32(y)+0.5}
			draw_resin_cube(renderer, p+rl.Vector3{0, ground*0.5, 0}, 0.97, 0.09+ground, 0.97, color)
			if tile.kind == .Wall {
				height := f32(0.055) if level.is_border_position({x = x, y = y}, int(w), int(h)) else 0.46
				draw_resin_cube(renderer, {p.x, ground+height*0.5, p.z}, 0.93, height, 0.93, {18, 33, 49, 255})
				draw_resin_cube(renderer, {p.x, ground+height+0.015, p.z}, 0.88, 0.035, 0.88, {27, 48, 68, 255})
			}
			if tile.kind == .Exit {
				if ground != 0 { rlgl.PushMatrix(); rlgl.Translatef(0, ground, 0) }
				draw_voxel_exit(renderer, {x = x, y = y})
				if ground != 0 { rlgl.PopMatrix() }
			}
		}
	}
	for deck in hologram_decks(room) {
		draw_resin_cube(renderer, {f32(deck.cell.x)+0.5, deck.ground-0.025, f32(deck.cell.y)+0.5}, 0.97, 0.09, 0.97, HOLOGRAM_DECK)
	}
	for obstacle in room.obstacles {
		p := rl.Vector3{f32(obstacle.position.x)+0.5, 0.17+cell_ground(obstacle.position), f32(obstacle.position.y)+0.5}
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
	p := rl.Vector3{f32(cell.x)+0.5, 0.044+cell_ground(cell), f32(cell.y)+0.5}
	rl.DrawPlane(p, {0.88, 0.88}, {210, 48, 72, 42})
	rl.DrawCubeWires(p, 0.88, 0.006, 0.88, {221, 74, 89, 225})
}

// Narrow emissive rails survive the scene downsample more cleanly than hairline
// wireframes, without lighting the entire cell.
@(private = "file")
hologram_rails :: proc(p: rl.Vector3) {
	for sign in ([2]f32{-1, 1}) {
		rl.DrawCube(p+rl.Vector3{sign*0.475, 0, 0}, 0.022, 0.004, 0.972, {68, 141, 172, 215})
		rl.DrawCube(p+rl.Vector3{0, 0, sign*0.475}, 0.972, 0.004, 0.022, {68, 141, 172, 215})
	}
}

@(private = "file")
draw_hologram_projection :: proc(renderer: ^Renderer, room: ^game.Room) {
	w, h := f32(room.level_data.tiles.width), f32(room.level_data.tiles.height)
	rl.DrawCubeWires({w*0.5, -0.064, h*0.5}, w+0.14, 0.026, h+0.14, HOLOGRAM_GLOW)
	for y in 0..<room.level_data.tiles.height {
		for x in 0..<room.level_data.tiles.width {
			tile, _ := level.tile_at(room.level_data, {x = x, y = y})
			ground := cell_ground({x = x, y = y})
			p := rl.Vector3{f32(x)+0.5, 0.029+ground, f32(y)+0.5}
			if level.is_walkable(tile.kind) {
				hologram_rails(p)
			} else if tile.kind == .Wall {
				border := level.is_border_position({x = x, y = y}, int(w), int(h))
				height := f32(0.091) if border else 0.496
				rl.DrawCubeWires({p.x, ground+height*0.5, p.z}, 0.935, height, 0.935, {57, 114, 143, 205} if border else HOLOGRAM_GLOW)
			}
			if tile.kind == .Exit {
				for sign in ([2]f32{-1, 1}) {
					rl.DrawLine3D({p.x+sign*0.34, ground+0.06, p.z-0.16}, {p.x+sign*0.34, ground+0.91, p.z-0.16}, HOLOGRAM_GLOW)
					rl.DrawLine3D({p.x+sign*0.34, ground+0.91, p.z-0.16}, {p.x, ground+1.29, p.z-0.16}, HOLOGRAM_GLOW)
				}
			}
		}
	}
	for deck in hologram_decks(room) {
		if level.is_walkable(deck.kind) { hologram_rails({f32(deck.cell.x)+0.5, 0.029+deck.ground, f32(deck.cell.y)+0.5}) }
	}
	for obstacle in room.obstacles {
		rl.DrawCubeWires({f32(obstacle.position.x)+0.5, 0.20+cell_ground(obstacle.position), f32(obstacle.position.y)+0.5}, 0.71, 0.42, 0.71, HOLOGRAM_GLOW)
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
	if !board_has_heights() { rl.DrawCube({w*0.5, 0.033, scan}, w-2, 0.002, 0.055, {100, 202, 230, 90}) }
	else {
		// Over the relief the scan climbs each cell it crosses.
		row := int(scan)
		for x in 1..<room.level_data.tiles.width-1 {
			rl.DrawCube({f32(x)+0.5, 0.033+cell_ground({x = x, y = row}), scan}, 1, 0.002, 0.055, {100, 202, 230, 90})
		}
	}
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
		center := grid.Position{x = int(object.position.x), y = int(object.position.y)}
		for y in center.y-1..=center.y+1 { for x in center.x-1..=center.x+1 {
			if game.explosion_contains_cell(room, center, {x = x, y = y}) { draw_hologram_threat(room, {x = x, y = y}) }
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
	// The board's heights, who stands where and what covers whom, as the world's
	// drawing has them, even on a frame the world is not drawn: the table and the
	// figures agree.
	set_board_level(room.level_data)
	set_board_actors(room)
	set_board_view(renderer, room)
	// The surface draws in logical units at its own resolution.
	surface := begin_tactical_surface(renderer)
	draw_tactical_backdrop(renderer)
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
	canvas_target.begin_scissor(viewport.x, viewport.y, viewport.width, viewport.height)
	rl.BeginMode3D(camera)
	begin_tactical_lighting(renderer, true)
	draw_hologram_table(renderer, room)
	rl.EndShaderMode()
	draw_hologram_projection(renderer, room)
	draw_tactical_billboards(renderer)
	// Who is under a deck or in the rock shows its outline, as on the board (layer_outline.odin).
	draw_hidden_outlines(renderer, room)
	rl.EndMode3D()
	rl.EndScissorMode()
	end_tactical_surface(renderer, surface)
	draw_hologram_chrome(renderer, room)
}
