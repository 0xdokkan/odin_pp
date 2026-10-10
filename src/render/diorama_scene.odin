package render

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import grid "../grid"
import level "../level"
import tween "../engine/tween"

DIORAMA_EDGE :: rl.Color{55, 73, 96, 255}
DIORAMA_INK :: rl.Color{9, 16, 27, 255}
DIORAMA_GLOW :: rl.Color{98, 192, 229, 255}
DIORAMA_WALL_HEIGHT :: f32(1.58)
DIORAMA_CUTAWAY_HEIGHT :: f32(0.5)

diorama_interior_wall :: proc(room: ^game.Room, cell: grid.Position) -> bool {
	tile, found := level.tile_at(room.level_data, cell)
	return found && tile.kind == .Wall &&
		!level.is_border_position(cell, room.level_data.tiles.width, room.level_data.tiles.height)
}

// Decorations fit the original tile volume. They do not add colliders, hide
// walkable cells, consume RNG or consult terrain beyond current visibility.
diorama_wall_height :: proc(renderer: ^Renderer, room: ^game.Room, cell: grid.Position) -> f32 {
	w, h := room.level_data.tiles.width, room.level_data.tiles.height
	if !level.is_border_position(cell, w, h) { return DIORAMA_WALL_HEIGHT }
	direction := renderer.tactical.camera.position-renderer.tactical.camera.target
	direction.y = 0
	direction = rl.Vector3Normalize(direction)
	// Only the two perimeter faces looking toward the camera can retract.
	// A narrow angular blend prevents a whole edge popping during orbit; the
	// hero's location, camera pan and zoom do not change the cutaway sides.
	facing: f32
	if cell.x == 0 { facing = max(facing, -direction.x) }
	if cell.x == w-1 { facing = max(facing, direction.x) }
	if cell.y == 0 { facing = max(facing, -direction.z) }
	if cell.y == h-1 { facing = max(facing, direction.z) }
	t := clamp(facing/0.35, f32(0), f32(1))
	return DIORAMA_WALL_HEIGHT+(DIORAMA_CUTAWAY_HEIGHT-DIORAMA_WALL_HEIGHT)*tween.smoothstep(t)
}

diorama_wall_face :: proc(room: ^game.Room, cell, offset: grid.Position) -> bool {
	tile, found := level.tile_at(room.level_data, {cell.x+offset.x, cell.y+offset.y})
	return found && level.is_walkable(tile.kind)
}

diorama_lamp :: proc(renderer: ^Renderer, room: ^game.Room, cell: grid.Position) -> (position: rl.Vector3, ok: bool) {
	if !tactical_render_visible(renderer, cell) || gothic_hash(cell.x, cell.y)%3 != 0 { return }
	tile, found := level.tile_at(room.level_data, cell)
	if !found || tile.kind != .Wall { return }
	for offset in ([4]grid.Position{{0, 1}, {1, 0}, {0, -1}, {-1, 0}}) {
		if !tactical_render_visible(renderer, {cell.x+offset.x, cell.y+offset.y}) || !diorama_wall_face(room, cell, offset) { continue }
		return {f32(cell.x)+0.5+f32(offset.x)*0.47, diorama_wall_height(renderer, room, cell)*0.58, f32(cell.y)+0.5+f32(offset.y)*0.47}, true
	}
	return
}

prepare_diorama_lights :: proc(renderer: ^Renderer, room: ^game.Room) -> (lights: [4]rl.Vector4) {
	v := &renderer.tactical
	distances := [4]f32{1e10, 1e10, 1e10, 1e10}
	hero := rl.Vector3{v.snapshot.player.position.x+0.5, 0, v.snapshot.player.position.y+0.5}
	for y in 0..<room.level_data.tiles.height { for x in 0..<room.level_data.tiles.width {
		position, found := diorama_lamp(renderer, room, {x, y})
		if !found { continue }
		distance := rl.Vector3LengthSqr(position-hero)
		for index in 0..<4 {
			if distance >= distances[index] { continue }
			for back := 3; back > index; back -= 1 {
				distances[back], lights[back] = distances[back-1], lights[back-1]
			}
			distances[index] = distance
			lights[index] = {position.x, position.y, position.z, 1}
			break
		}
	} }
	return
}

// Axis-aligned carved face details use simple boxes rather than bevel meshes.
draw_diorama_wall_face :: proc(center, normal: rl.Vector3, height: f32, variant: u32, transparent: bool) {
	ink := rl.Color{22, 41, 64, 35} if transparent else DIORAMA_INK
	edge := rl.Color{92, 142, 171, 62} if transparent else DIORAMA_EDGE
	trace := rl.Color{72, 126, 166, 64} if transparent else rl.Color{36, 55, 82, 255}
	tangent := rl.Vector3{normal.z, 0, -normal.x}
	base := center+normal*0.474
	depth := rl.Vector3{abs(normal.x), 0, abs(normal.z)}
	width := rl.Vector3{abs(tangent.x), 0, abs(tangent.z)}
	panel := width*0.43+depth*0.015+rl.Vector3{0, height*0.62, 0}
	rl.DrawCubeV(base+rl.Vector3{0, height*0.49, 0}, panel, ink)
	for sign in ([2]f32{-1, 1}) {
		rl.DrawCubeV(base+tangent*(sign*0.29)+rl.Vector3{0, height*0.48, 0}, width*0.07+depth*0.035+rl.Vector3{0, height*0.69, 0}, edge)
		for step in 0..<3 {
			p := base+tangent*(sign*(0.21-f32(step)*0.075))+rl.Vector3{0, height*(0.77+f32(step)*0.055), 0}
			rl.DrawCubeV(p, width*0.12+depth*0.04+rl.Vector3{0, height*0.085, 0}, edge)
		}
	}
	if variant%2 == 0 {
		// Narrow tracery in the recess: the cold recess stays darker than threats.
		rl.DrawCubeV(base+normal*0.015+rl.Vector3{0, height*0.49, 0}, width*0.025+depth*0.018+rl.Vector3{0, height*0.44, 0}, trace)
		rl.DrawCubeV(base+normal*0.016+rl.Vector3{0, height*0.55, 0}, width*0.23+depth*0.018+rl.Vector3{0, height*0.023, 0}, trace)
	}
}

// Internal walls keep their complete silhouette. Only their low plinth is
// opaque; the upper body is submitted with actors in the sorted alpha pass.
draw_diorama_wall :: proc(renderer: ^Renderer, room: ^game.Room, cell: grid.Position) {
	if renderer.tactical.kit.loaded { draw_diorama_kit_wall(renderer, room, cell); return }
	p := rl.Vector3{f32(cell.x)+0.5, 0, f32(cell.y)+0.5}
	n := gothic_hash(cell.x, cell.y)
	h := diorama_wall_height(renderer, room, cell)
	transparent := diorama_interior_wall(room, cell)
	edge := rl.Color{92, 142, 171, 62} if transparent else DIORAMA_EDGE
	ink := rl.Color{22, 41, 64, 35} if transparent else DIORAMA_INK
	core := rl.Color{58, 91, 118, 46} if transparent else RESIN_WALL
	cap := rl.Color{93, 137, 170, 40} if transparent else RESIN_CAP
	draw_resin_cube(renderer, p+rl.Vector3{0, h*0.5, 0}, 0.91, h, 0.91, core)
	rl.DrawCube(p+rl.Vector3{0, h*0.40, 0}, 0.925, 0.035, 0.925, ink)
	draw_resin_cube(renderer, p+rl.Vector3{0, h-0.04, 0}, 0.97, 0.12, 0.97, edge)
	draw_resin_cube(renderer, p+rl.Vector3{0, h+0.065, 0}, 0.88, 0.11, 0.88, cap)
	rl.DrawCube(p+rl.Vector3{0, h+0.122, 0}, 0.59, 0.008, 0.59, ink if transparent else rl.Color{38, 52, 72, 255})
	rl.DrawCube(p+rl.Vector3{0, h+0.129, 0}, 0.065, 0.006, 0.21, edge if transparent else rl.Color{78, 115, 140, 255})
	for offset in ([4]grid.Position{{0, 1}, {1, 0}, {0, -1}, {-1, 0}}) {
		normal := rl.Vector3{f32(offset.x), 0, f32(offset.y)}
		// Back-face ornament layers would unnecessarily darken the translucent
		// shell. Keep the camera-facing relief, just as on the opaque surface.
		if transparent && rl.Vector3DotProduct(normal, renderer.tactical.camera.position-p-normal*0.474) <= 0 { continue }
		if tactical_render_visible(renderer, {cell.x+offset.x, cell.y+offset.y}) && diorama_wall_face(room, cell, offset) {
			draw_diorama_wall_face(p, normal, h, n, transparent)
		}
	}
	if lamp, found := diorama_lamp(renderer, room, cell); found {
		draw_resin_cube(renderer, lamp, 0.17, 0.24, 0.17, ink)
		rl.DrawCube(lamp+rl.Vector3{0, -0.14, 0}, 0.21, 0.04, 0.21, edge)
		rl.DrawCube(lamp+rl.Vector3{0, 0.14, 0}, 0.16, 0.04, 0.16, edge)
		if transparent { draw_diorama_lamp_glow(renderer, lamp, cell, 0.25) }
	}
}

draw_tactical_tile :: proc(renderer: ^Renderer, room: ^game.Room, tile: level.Tile, cell: grid.Position) {
	if tile.kind == .Void { return }
	p := rl.Vector3{f32(cell.x)+0.5, 0, f32(cell.y)+0.5}
	n := gothic_hash(cell.x, cell.y)
	shade := u8(n%11)
	floor := rl.Color{43+shade, 52+shade, 65+shade, 255}
	if renderer.tactical.snapshot.family == .Twin_Courts { floor = {38+shade, 51+shade, 69+shade, 255} }
	draw_resin_cube(renderer, p+rl.Vector3{0, -0.155, 0}, 0.99, 0.31, 0.99, RESIN_DARK)
	draw_resin_cube(renderer, p+rl.Vector3{0, -0.05, 0}, 0.945, 0.135, 0.945, floor)
	if tile.kind == .Wall {
		draw_resin_cube(renderer, p+rl.Vector3{0, 0.10, 0}, 0.98, 0.16, 0.98, DIORAMA_EDGE)
		if !diorama_interior_wall(room, cell) { draw_diorama_wall(renderer, room, cell) }
		return
	}
	// Slim inset corner fittings and occasional engraving preserve empty centers.
	for sign in ([2]f32{-1, 1}) {
		rl.DrawCube(p+rl.Vector3{sign*0.35, 0.02, sign*0.40}, 0.17, 0.006, 0.018, {28, 40, 57, 255})
		rl.DrawCube(p+rl.Vector3{sign*0.40, 0.02, sign*0.35}, 0.018, 0.006, 0.17, {28, 40, 57, 255})
	}
	if n%7 == 0 && tile.kind != .Exit {
		for i in 0..<4 {
			angle := f32(i)*math.PI/2
			a := p+rl.Vector3{math.cos(angle)*0.22, 0.021, math.sin(angle)*0.22}
			b := p+rl.Vector3{math.cos(angle+math.PI/2)*0.22, 0.021, math.sin(angle+math.PI/2)*0.22}
			rl.DrawLine3D(a, b, {33, 57, 78, 255})
		}
		rl.DrawCube(p+rl.Vector3{0, 0.022, 0}, 0.055, 0.01, 0.055, {53, 79, 100, 255})
	} else if n%5 == 0 {
		rl.DrawCube(p+rl.Vector3{0.19, 0.02, 0.11}, 0.26, 0.006, 0.012, {26, 36, 51, 255})
		rl.DrawCube(p+rl.Vector3{0.08, 0.02, 0.06}, 0.012, 0.006, 0.10, {26, 36, 51, 255})
	}
	if tile.kind == .Exit {
		draw_resin_cube(renderer, p+rl.Vector3{0, 0.055, 0}, 0.8, 0.09, 0.8, DIORAMA_INK)
		rl.DrawCubeWires(p+rl.Vector3{0, 0.105, 0}, 0.70, 0.01, 0.70, DIORAMA_EDGE)
		draw_voxel_exit(renderer, cell)
	}
}

draw_diorama_lamp_glow :: proc(renderer: ^Renderer, lamp: rl.Vector3, cell: grid.Position, opacity: f32 = 1) {
	time := f32(renderer.sprite_assets.elapsed)
	flicker := f32(0.86+0.14*math.sin(time*2.6+f32(cell.x+cell.y)))
	core := DIORAMA_GLOW
	core.a = u8(255*opacity)
	rl.DrawCube(lamp, 0.087, 0.15*flicker, 0.087, core)
	rl.DrawCube(lamp+rl.Vector3{0, 0.035, 0}, 0.035, 0.06, 0.035, {217, 246, 245, u8(255*opacity)})
	for layer in 0..<2 {
		size := f32(0.13)+f32(layer)*0.10
		rl.DrawCube(lamp, size, 0.20+f32(layer)*0.11, size, {63, 150, 206, u8(f32(20-layer*9)*opacity)})
	}
}

// Sparse luminous pixels stay inside the current visible footprint. No memory.
draw_diorama_accents :: proc(renderer: ^Renderer, room: ^game.Room) {
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableDepthMask() }
	time := f32(renderer.sprite_assets.elapsed)
	for y in 0..<room.level_data.tiles.height { for x in 0..<room.level_data.tiles.width {
		cell := grid.Position{x, y}
		if !tactical_cell_on_screen(renderer, cell) || !tactical_render_visible(renderer, cell) { continue }
		if !diorama_interior_wall(room, cell) {
			if lamp, found := diorama_lamp(renderer, room, cell); found { draw_diorama_lamp_glow(renderer, lamp, cell) }
		}
		tile, _ := level.tile_at(room.level_data, cell)
		n := gothic_hash(x, y)
		if tile.kind != .Floor || n%13 != 0 { continue }
		phase := math.mod(time*0.14+f32(n%29)/29, f32(1))
		p := rl.Vector3{f32(x)+0.5+math.sin(time*0.5+f32(n%9))*0.17, 0.14+phase*0.9, f32(y)+0.5}
		alpha := u8(math.sin(phase*math.PI)*65)
		rl.DrawCube(p, 0.024, 0.024, 0.024, {128, 177, 214, alpha})
	} }
}
