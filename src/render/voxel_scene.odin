package render

import rl "vendor:raylib"
import "core:fmt"
import "core:math"
import game "../game"
import grid "../engine/grid"
import view "../engine/view"

@(private = "file")
draw_voxel_marker :: proc(cell: grid.Position, color: rl.Color) {
	p := rl.Vector3{f32(cell.x)+0.5, 0.043, f32(cell.y)+0.5}
	rl.DrawPlane(p, {0.87, 0.87}, {color.r, color.g, color.b, 45})
	rl.DrawCubeWires(p, 0.87, 0.005, 0.87, color)
}

// Recovery remains a movement window: choosing a safe cell requires the
// same current telegraphs while a player's recovery step is animating.
@(private)
tactical_telegraphs_are_visible :: proc(renderer: ^Renderer, room: ^game.Room) -> bool {
	return !renderer_blocks_player_input(renderer) || game.tactical_is_recovering(room)
}

@(private)
draw_voxel_threats :: proc(renderer: ^Renderer, room: ^game.Room) {
	// The lab's ground display draws the enemies' threats its own way.
	if tactical_telegraphs_are_visible(renderer, room) && !intent_ground_on(renderer) {
		for &enemy in room.enemies {
			if game.enemy_is_staggered(room, &enemy) { continue }
			color := GOTHIC_RED
			if enemy.intent.windup { color = {184, 130, 56, 255} }
			for cell in enemy.intent.threatened_cells[:enemy.intent.threatened_cell_count] {
				if tactical_render_visible(renderer, cell) { draw_voxel_marker(cell, color) }
			}
			if enemy.intent.kind == .Charge {
				for cell in enemy.intent.path[:enemy.intent.path_count] {
					if tactical_render_visible(renderer, cell) { draw_voxel_marker(cell, GOTHIC_RED) }
				}
			}
		}
	}
	for object in renderer.tactical.snapshot.objects[:renderer.tactical.snapshot.object_count] {
		if !object.visible || object.detonation_pulse == 0 { continue }
		center := grid.Position{int(object.position.x), int(object.position.y)}
		if !tactical_render_visible(renderer, center) { continue }
		for y in center.y-1..=center.y+1 { for x in center.x-1..=center.x+1 {
			if tactical_render_visible(renderer, {x, y}) && game.explosion_contains_cell(room, center, {x, y}) {
				draw_voxel_marker({x, y}, {220, 115, 49, 255})
			}
		} }
	}
}

@(private)
draw_voxel_fuse_labels :: proc(renderer: ^Renderer, room: ^game.Room) {
	snapshot := renderer.tactical.snapshot
	if tactical_telegraphs_are_visible(renderer, room) {
		for &enemy in room.enemies {
			if game.enemy_is_staggered(room, &enemy) { continue }
			if enemy.intent.kind != .Bombard || !tactical_render_visible(renderer, enemy.intent.destination) { continue }
			cell := enemy.intent.destination
			p := tactical_project(renderer, {f32(cell.x)+0.5, f32(cell.y)+0.5}, 0.05)
			label: cstring = "BOMBA: PREPARA" if enemy.intent.windup else "BOMBA: IN ARRIVO"
			draw_tactical_label(renderer, {p.x, p.y+23}, label, "", {215, 166, 88, 255})
		}
	}
	for object in snapshot.objects[:snapshot.object_count] {
		cell := grid.Position{int(object.position.x), int(object.position.y)}
		if !object.visible || object.detonation_pulse == 0 || !tactical_render_visible(renderer, cell) { continue }
		remaining := game.explosive_pulses_remaining(object.detonation_pulse, snapshot.pulse_count, object.fuse_pulses)
		p := tactical_project(renderer, {object.position.x+0.5, object.position.y+0.5}, 0.85)
		label := fmt.ctprintf("MICCIA %ds", remaining)
		draw_tactical_label(renderer, p, label, "", GOTHIC_RED if remaining <= 1 else GOTHIC_PAPER)
	}
	draw_emplacement_labels(renderer, room)
}

@(private)
tactical_intent_label :: proc(intent: game.Enemy_Intent) -> cstring {
	switch intent.kind {
	case .Attack:
		if intent.windup { return "MIRA" }
		if intent.threatened_cell_count > 1 { return "FENDENTE" }
		if intent.target_object != 0 { return "ACCENDE" }
		return "SPINTA" if intent.push else "ATTACCO"
	case .Charge: return "CARICA"
	case .Bombard: return "PREPARA" if intent.windup else "LANCIA"
	case .Recover: return "RECUPERO"
	case .Protect: return "PROTEGGE"
	case .Move: return "MUOVE"
	case .None, .Wait: return "ATTENDE"
	}
	return ""
}

// All environmental props have volume. The same extents drive their ray pick.
@(private)
voxel_object_bounds :: proc(kind: game.Grid_Object_Kind, position: view.Vec2) -> rl.BoundingBox {
	width, height := f32(0.68), f32(0.72)
	switch kind {
	case .Ice_Block: width, height = 0.82, 0.94
	case .Barrel: width, height = 0.64, 0.76
	case .Bomb: width, height = 0.46, 0.46
	case .Fire: width, height = 0.64, 0.7
	case .Shock_Floor: width, height = 0.88, 0.12
	case .Tesla_Coil: width, height = 0.64, 1.18
	// CANNONE on its stand; the hole is a dark disc with a sphere in it.
	case .Cannon: width, height = 0.72, 0.86
	case .Black_Hole: width, height = 0.9, 0.5
	case .Count:
	}
	p := rl.Vector3{position.x+0.5, 0.035, position.y+0.5}
	return {p-rl.Vector3{width/2, 0, width/2}, p+rl.Vector3{width/2, height, width/2}}
}

@(private)
draw_voxel_object :: proc(renderer: ^Renderer, object: Presentation_Grid_Object) {
	bounds := voxel_object_bounds(object.kind, object.position)
	p := (bounds.min+bounds.max)*0.5
	size := bounds.max-bounds.min
	tint := GOTHIC_MUTED
	switch object.kind {
	case .Shock_Floor, .Tesla_Coil: draw_m8_device_object(renderer, object)
	case .Cannon: draw_cannon_object(renderer, object, p)
	// The hole has its own pass: the floor and the sphere (arsenal.odin).
	case .Black_Hole:
	case .Ice_Block:
		tint = {102, 151, 162, 255}
		draw_resin_cube_v(renderer, p, size, tint)
		draw_resin_cube_v(renderer, p+rl.Vector3{-0.06, size.y*0.32, -0.06}, size*rl.Vector3{0.92, 0.25, 0.92}, {173, 201, 196, 255})
		for i in 0..<4 { draw_resin_cube(renderer, p+rl.Vector3{-0.25+f32(i)*0.09, 0.22-f32(i)*0.12, size.z/2+0.005}, 0.06, 0.13, 0.02, {52, 91, 111, 255}) }
	case .Barrel:
		draw_resin_cube_v(renderer, p, size, {99, 58, 38, 255})
		for y in ([?]f32{-0.23, 0.23}) {
			draw_resin_cube_v(renderer, p+rl.Vector3{0, y, 0}, {size.x+0.025, 0.09, size.z+0.025}, DIORAMA_EDGE)
			for x in ([2]f32{-0.23, 0.23}) { rl.DrawCube(p+rl.Vector3{x, y, size.z/2+0.02}, 0.028, 0.028, 0.015, GOTHIC_PAPER) }
		}
		for x in ([?]f32{-0.2, 0, 0.2}) { draw_resin_cube(renderer, p+rl.Vector3{x, 0, size.z/2+0.005}, 0.02, 0.7, 0.015, {52, 34, 30, 255}) }
		draw_resin_cube(renderer, p+rl.Vector3{0, 0, size.z/2+0.02}, 0.18, 0.23, 0.025, GOTHIC_RED)
	case .Bomb:
		draw_resin_cube_v(renderer, p, size, {37, 35, 42, 255})
		draw_resin_cube_v(renderer, p+rl.Vector3{0, 0.1, 0}, {size.x+0.03, 0.06, size.z+0.03}, GOTHIC_MUTED)
		draw_resin_cube(renderer, p+rl.Vector3{0, 0.28, 0}, 0.06, 0.18, 0.06, RESIN_CAP)
		draw_resin_cube(renderer, p+rl.Vector3{0.03, 0.37, 0}, 0.09, 0.08, 0.09, {237, 136, 51, 255})
	case .Fire:
		draw_resin_cube(renderer, {p.x, 0.05, p.z}, 0.68, 0.08, 0.68, {40, 24, 27, 255})
		for i in 0..<5 {
			x, z := f32(i%3-1)*0.18, f32(i/3)*0.23-0.12
			h := (f32(0.25)+f32(i%3)*0.15)*(0.91+0.09*math.sin(f32(tactical_world_time(renderer))*7+f32(i)*1.7))
			draw_resin_cube(renderer, {p.x+x, h/2+0.08, p.z+z}, 0.17, h, 0.17, GOTHIC_RED)
			draw_resin_cube(renderer, {p.x+x, h*0.3+0.1, p.z+z+0.04}, 0.09, h*0.6, 0.12, {222, 132, 54, 255})
		}
	case .Count:
	}
}

@(private)
draw_voxel_cover :: proc(renderer: ^Renderer, cell: grid.Position) {
	if neon_active(renderer) { draw_neon_rock(renderer, cell); return }
	p := rl.Vector3{f32(cell.x)+0.5, 0.2, f32(cell.y)+0.5}
	draw_resin_cube(renderer, p, 0.72, 0.4, 0.72, RESIN_WALL)
	draw_resin_cube(renderer, p+rl.Vector3{0.03, 0.23, -0.02}, 0.76, 0.12, 0.76, RESIN_CAP)
	draw_resin_cube(renderer, p+rl.Vector3{-0.13, 0.31, 0.05}, 0.33, 0.11, 0.4, rl.Color{62, 79, 100, 255})
}

@(private)
draw_voxel_trap :: proc(renderer: ^Renderer, trap: game.Trap) {
	p := rl.Vector3{f32(trap.position.x)+0.5, 0.06, f32(trap.position.y)+0.5}
	draw_resin_cube(renderer, p, 0.7, 0.06, 0.7, {44, 36, 39, 255})
	for i in 0..<9 {
		draw_resin_cube(renderer, p+rl.Vector3{f32(i%3-1)*0.21, 0.08, f32(i/3-1)*0.21}, 0.07, 0.16, 0.07, RESIN_CAP)
	}
}

@(private)
draw_voxel_exit :: proc(renderer: ^Renderer, cell: grid.Position) {
	p := rl.Vector3{f32(cell.x)+0.5, 0, f32(cell.y)+0.5}
	for sign in ([?]f32{-1, 1}) {
		draw_resin_cube(renderer, p+rl.Vector3{sign*0.34, 0.46, 0}, 0.18, 0.92, 0.28, RESIN_WALL)
		for z in ([2]f32{-0.15, 0.15}) {
			rl.DrawCube(p+rl.Vector3{sign*0.34, 0.46, z}, 0.055, 0.73, 0.025, DIORAMA_EDGE)
		}
		for y in ([3]f32{0.10, 0.74, 0.88}) {
			draw_resin_cube(renderer, p+rl.Vector3{sign*0.34, y, 0}, 0.24, 0.075, 0.36, RESIN_CAP)
		}
		for i in 0..<3 {
			draw_resin_cube(renderer, p+rl.Vector3{sign*(0.27-f32(i)*0.1), 0.96+f32(i)*0.09, 0}, 0.19, 0.17, 0.28, RESIN_CAP)
		}
	}
	draw_resin_cube(renderer, p+rl.Vector3{0, 1.23, 0}, 0.12, 0.19, 0.34, DIORAMA_EDGE)
	for z in ([2]f32{-0.18, 0.18}) {
		rl.DrawCube(p+rl.Vector3{0, 1.23, z}, 0.05, 0.11, 0.025, DIORAMA_GLOW)
	}
}

// Unknown cells share identical, opaque 3D fog blocks: neither wall height,
// props nor visited terrain can be inferred from them. No exploration memory.
@(private)
draw_voxel_fog :: proc(renderer: ^Renderer, room: ^game.Room) {
	if renderer.tactical.no_fog { return }
	neon := neon_active(renderer)
	time := f32(tactical_world_time(renderer))
	for y in 0..<room.level_data.tiles.height {
		for x in 0..<room.level_data.tiles.width {
			if !tactical_cell_on_screen(renderer, {x, y}) { continue }
			if tactical_render_visible(renderer, {x, y}) { continue }
			// No wall round the board in the neon world: no fog over its ring.
			if neon && neon_is_border(room, {x, y}) { continue }
			if neon { draw_neon_fog_block(renderer, x, y, time); continue }
			p := rl.Vector3{f32(x)+0.5, 0, f32(y)+0.5}
			rl.DrawCube(p+rl.Vector3{0, -0.15, 0}, 1, 0.3, 1, {7, 10, 16, 255})
			for layer in 0..<2 {
				n := gothic_hash(x*3+layer, y*3+layer)
				height := 0.20+f32(n%4)*0.06
				shade := u8(11+n%4)
				rl.DrawCube(p+rl.Vector3{f32(i32(n%3)-1)*0.17, height/2+f32(layer)*0.06, 0}, 0.96-f32(layer)*0.17, height, 0.96, {shade, shade+3, shade+9, 255})
			}
		}
	}
}

