package mapeditor

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import gfx "../engine/gfx"
import grid "../engine/grid"
import game "../game"
import level "../level"

// THE EDITOR'S VIEW: every layer of the map as lit meshes in blocks of EDITOR_CHUNK cells, the sculpted surface of its
// cells (level/surface.odin) with their kinds in colour, a block of rock on a Wall, a wall of rock down every cliff. A
// block is built again when a brush changes a cell of it or next to it (mark_dirty).

EDITOR_CHUNK :: 16

Editor_Chunk :: struct {
	model:        rl.Model,
	loaded, dirty: bool,
}

Editor_View :: struct {
	columns, rows: int,
	chunks:        [level.LAYER_COUNT][]Editor_Chunk,
	lighting:      gfx.Lighting,
	ready:         bool,
}

@(private = "file")
Mesh_Builder :: struct {
	positions, normals: [dynamic]f32,
	colors:             [dynamic]u8,
}

@(private = "file")
builder_triangle :: proc(b: ^Mesh_Builder, p, q, r: rl.Vector3, color: rl.Color, facing: rl.Vector3) {
	normal := rl.Vector3CrossProduct(q-p, r-p)
	if rl.Vector3LengthSqr(normal) < 1e-12 { return }
	normal = rl.Vector3Normalize(normal)
	if rl.Vector3DotProduct(normal, facing) < 0 { normal = -normal }
	for v in ([3]rl.Vector3{p, q, r}) {
		append(&b.positions, v.x, v.y, v.z)
		append(&b.normals, normal.x, normal.y, normal.z)
		append(&b.colors, color.r, color.g, color.b, color.a)
	}
}

// The colour of a cell's top: its kind's, lighter the higher it is, a shade apart every other cell.
@(private = "file")
cell_color :: proc(kind: level.Tile_Kind, layer: i8, steps: f32, x, y: int) -> rl.Color {
	t := clamp(steps/40, 0, 1)
	low, high := rl.Color{86, 104, 92, 255}, rl.Color{196, 198, 176, 255}
	if layer < grid.GROUND_LAYER { low, high = {112, 88, 66, 255}, {196, 160, 120, 255} }
	if layer > grid.GROUND_LAYER { low, high = {96, 112, 160, 255}, {170, 186, 226, 255} }
	color := rl.ColorLerp(low, high, t)
	#partial switch kind {
	case .Wall: color = {122, 80, 50, 255}
	case .Fence: color = {214, 178, 62, 255}
	case .Player_Spawn: color = {72, 122, 240, 255}
	case .Exit: color = {190, 72, 210, 255}
	case .Door: color = {84, 150, 220, 255}
	}
	if (x+y)%2 == 1 { color = {u8(f32(color.r)*.93), u8(f32(color.g)*.93), u8(f32(color.b)*.93), 255} }
	return color
}

// The surface `layer` has: the ground's tables, or its plane's.
layer_surface :: proc(data: ^level.Level, layer: i8) -> level.Surface_Map {
	if layer == grid.GROUND_LAYER { return level.surface_map(data) }
	plane := &data.planes[level.layer_slot(layer)]
	return {heights = plane.heights[:], tiles = plane.tiles[:], width = data.tiles.width, height = data.tiles.height}
}

// How far over its ground a kind is drawn, in steps: a Wall as a block of rock, a Fence as a low wall.
@(private = "file")
kind_lift :: proc(kind: level.Tile_Kind) -> f32 {
	#partial switch kind {
	case .Wall: return 6
	case .Fence: return 1.5
	}
	return 0
}

@(private = "file")
CORNERS :: [4][2]f32{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
@(private = "file")
SIDES :: [4][2]int{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}

// The cells of one block of one layer.
@(private = "file")
build_chunk :: proc(data: ^level.Level, layer: i8, cx, cy: int, b: ^Mesh_Builder) {
	m := layer_surface(data, layer)
	if len(m.tiles) == 0 { return }
	step := game.HEIGHT_STEP_DRAWN
	sides := SIDES
	up := rl.Vector3{0, 1, 0}
	// Where a cliff's wall ends where there is no ground: under the board, or a deck's thickness under a layer's floor.
	floor_base := f32(-0.3) if layer == grid.GROUND_LAYER else f32(-level.LAYER_THICKNESS)
	for y in cy*EDITOR_CHUNK..<min((cy+1)*EDITOR_CHUNK, m.height) {
		for x in cx*EDITOR_CHUNK..<min((cx+1)*EDITOR_CHUNK, m.width) {
			cell, ok := level.surface_cell(&m, x, y)
			if !ok { continue }
			kind := m.tiles[y*m.width+x].kind
			color := cell_color(kind, layer, cell.center, x, y)
			lift := kind_lift(kind)
			point :: proc(x, y, corner: int, steps: f32) -> rl.Vector3 {
				c := CORNERS
				return {f32(x)+c[corner].x, steps*game.HEIGHT_STEP_DRAWN, f32(y)+c[corner].y}
			}
			middle := rl.Vector3{f32(x)+.5, (cell.center+lift)*step, f32(y)+.5}
			for side in 0..<4 {
				a, c := side, (side+1)%4
				builder_triangle(b, middle, point(x, y, a, cell.corners[a]+lift), point(x, y, c, cell.corners[c]+lift), color, up)
			}
			// The walls: down to the neighbour where it is lower (or has no ground), and round a raised block.
			rock := rl.Color{u8(f32(color.r)*.55), u8(f32(color.g)*.55), u8(f32(color.b)*.55), 255}
			for side in 0..<4 {
				a, c := side, (side+1)%4
				next := [2]int{x+sides[side].x, y+sides[side].y}
				top := [2]f32{cell.corners[a]+lift, cell.corners[c]+lift}
				low := [2]f32{floor_base, floor_base}
				if neighbour, has := level.surface_cell(&m, next.x, next.y); has {
					if lift == 0 && level.surface_linked(&m, {x, y}, next) { continue }
					facing_a, facing_c := 3-a, 3-c
					if side%2 == 1 { facing_a, facing_c = (5-a)%4, (5-c)%4 }
					low = {neighbour.corners[facing_a], neighbour.corners[facing_c]}
					if lift > 0 { low = {min(low[0], cell.corners[a]), min(low[1], cell.corners[c])} }
				}
				if top[0] <= low[0]+0.01 && top[1] <= low[1]+0.01 { continue }
				outward := rl.Vector3{f32(sides[side].x), 0, f32(sides[side].y)}
				pa, pc := point(x, y, a, top[0]), point(x, y, c, top[1])
				qa, qc := point(x, y, a, min(low[0], top[0])), point(x, y, c, min(low[1], top[1]))
				builder_triangle(b, pa, pc, qc, rock, outward)
				builder_triangle(b, pa, qc, qa, rock, outward)
			}
		}
	}
}

@(private = "file")
release_chunk :: proc(chunk: ^Editor_Chunk) {
	if chunk.loaded { gfx.unload_lit_model(&chunk.model) }
	chunk.model, chunk.loaded = {}, false
}

// Builds a block again from the map.
@(private = "file")
refresh_chunk :: proc(v: ^Editor_View, data: ^level.Level, slot, cx, cy: int) {
	chunk := &v.chunks[slot][cy*v.columns+cx]
	release_chunk(chunk)
	chunk.dirty = false
	b: Mesh_Builder
	defer { delete(b.positions); delete(b.normals); delete(b.colors) }
	build_chunk(data, i8(slot+grid.LOWEST_LAYER), cx, cy, &b)
	count := len(b.positions)/3
	if count == 0 { return }
	mesh: rl.Mesh
	mesh.vertexCount = i32(count)
	mesh.triangleCount = i32(count/3)
	mesh.vertices = ([^]f32)(rl.MemAlloc(u32(len(b.positions)*size_of(f32))))
	mesh.normals = ([^]f32)(rl.MemAlloc(u32(len(b.normals)*size_of(f32))))
	mesh.colors = ([^]u8)(rl.MemAlloc(u32(len(b.colors))))
	copy(mesh.vertices[:len(b.positions)], b.positions[:])
	copy(mesh.normals[:len(b.normals)], b.normals[:])
	copy(mesh.colors[:len(b.colors)], b.colors[:])
	rl.UploadMesh(&mesh, false)
	chunk.model = rl.LoadModelFromMesh(mesh)
	gfx.lighting_apply_to_model(&v.lighting, &chunk.model)
	chunk.loaded = true
}

// Every block of a map new to the view.
view_open :: proc(v: ^Editor_View, data: ^level.Level) {
	view_release(v)
	if !v.ready {
		v.lighting = gfx.lighting_create()
		// A whole map in view: no fog.
		v.lighting.fog_near, v.lighting.fog_far = 2000, 4000
		v.ready = true
	}
	v.columns = (data.tiles.width+EDITOR_CHUNK-1)/EDITOR_CHUNK
	v.rows = (data.tiles.height+EDITOR_CHUNK-1)/EDITOR_CHUNK
	for slot in 0..<level.LAYER_COUNT {
		v.chunks[slot] = make([]Editor_Chunk, v.columns*v.rows)
		for &chunk in v.chunks[slot] { chunk.dirty = true }
	}
}

view_release :: proc(v: ^Editor_View) {
	for slot in 0..<level.LAYER_COUNT {
		for &chunk in v.chunks[slot] { release_chunk(&chunk) }
		delete(v.chunks[slot])
		v.chunks[slot] = nil
	}
}

view_destroy :: proc(v: ^Editor_View) {
	view_release(v)
	if v.ready { gfx.lighting_destroy(&v.lighting) }
	v^ = {}
}

// The blocks of `layer` round the cells from `low` to `high` are to be built again (a cell's corners read its
// neighbours: one cell more each way).
mark_dirty :: proc(v: ^Editor_View, layer: i8, low, high: grid.Position) {
	if v.columns == 0 { return }
	slot := level.layer_slot(layer)
	x0, y0 := max(low.x-1, 0)/EDITOR_CHUNK, max(low.y-1, 0)/EDITOR_CHUNK
	x1, y1 := min((high.x+1)/EDITOR_CHUNK, v.columns-1), min((high.y+1)/EDITOR_CHUNK, v.rows-1)
	for cy in y0..=y1 { for cx in x0..=x1 { v.chunks[slot][cy*v.columns+cx].dirty = true } }
}

// Draws the map: the active layer and the ones under it whole (those under darker), the ones over it as ghosts.
view_draw :: proc(v: ^Editor_View, data: ^level.Level, active: i8, camera: rl.Camera3D) {
	for slot in 0..<level.LAYER_COUNT {
		for cy in 0..<v.rows { for cx in 0..<v.columns { if v.chunks[slot][cy*v.columns+cx].dirty { refresh_chunk(v, data, slot, cx, cy) } } }
	}
	gfx.lighting_update(&v.lighting, camera.position)
	rlgl.DisableBackfaceCulling()
	defer rlgl.EnableBackfaceCulling()
	for slot in 0..<level.LAYER_COUNT {
		if i8(slot+grid.LOWEST_LAYER) > active { continue }
		for &chunk in v.chunks[slot] { if chunk.loaded { rl.DrawModel(chunk.model, {}, 1, rl.WHITE) } }
	}
	// Over the active layer: the default program, which takes the tint's transparency, without writing the depth.
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	defer { rlgl.DrawRenderBatchActive(); rlgl.EnableDepthMask() }
	plain := rl.Shader{id = rlgl.GetShaderIdDefault(), locs = rlgl.GetShaderLocsDefault()}
	for slot in 0..<level.LAYER_COUNT {
		if i8(slot+grid.LOWEST_LAYER) <= active { continue }
		for &chunk in v.chunks[slot] {
			if !chunk.loaded { continue }
			lit := chunk.model.materials[0].shader
			chunk.model.materials[0].shader = plain
			rl.DrawModel(chunk.model, {}, 1, {255, 255, 255, 56})
			chunk.model.materials[0].shader = lit
		}
	}
}

// The cell of `layer` under the mouse: the first one whose surface the ray from the camera goes under; where the layer
// has no cell, the ray's point at its own height (the ground's plane, or a deck's over it).
view_pick :: proc(data: ^level.Level, layer: i8, camera: rl.Camera3D, mouse: [2]f32, width, height: f32) -> (cell: grid.Position, ok: bool) {
	ray := rl.GetScreenToWorldRayEx(mouse, camera, i32(width), i32(height))
	m := layer_surface(data, layer)
	step := game.HEIGHT_STEP_DRAWN
	plane := f32(level.LAYER_SPACING)*step if layer > grid.GROUND_LAYER else 0
	if ray.direction.y > -0.0001 { return }
	top := f32(0)
	for h in m.heights { top = max(top, f32(h)) }
	top = max(top*step+1, plane+0.1)
	start := max((top-ray.position.y)/ray.direction.y, 0)
	end := (plane-ray.position.y)/ray.direction.y
	for t := start; t <= end+0.05; t += 0.05 {
		p := ray.position+ray.direction*t
		x, y := int(math.floor(p.x)), int(math.floor(p.z))
		if x < 0 || y < 0 || x >= data.tiles.width || y >= data.tiles.height { continue }
		if level.surface_ground(&m, x, y) {
			if p.y <= level.surface_height_at(&m, p.x, p.z)*step+0.01 { return {x = x, y = y, layer = layer}, true }
		} else if p.y <= plane+0.01 {
			return {x = x, y = y, layer = layer}, true
		}
	}
	p := ray.position+ray.direction*end
	x, y := int(math.floor(p.x)), int(math.floor(p.z))
	if x < 0 || y < 0 || x >= data.tiles.width || y >= data.tiles.height { return }
	return {x = x, y = y, layer = layer}, true
}

// The height a mark on `cell` is drawn at: the top of what is drawn there (its surface, a Wall's block, a Fence), or
// its layer's plane.
cell_top :: proc(data: ^level.Level, cell: grid.Position) -> f32 {
	m := layer_surface(data, cell.layer)
	if surface, ok := level.surface_cell(&m, cell.x, cell.y); ok {
		return (level.surface_top(surface)+kind_lift(m.tiles[cell.y*m.width+cell.x].kind))*game.HEIGHT_STEP_DRAWN
	}
	return f32(level.LAYER_SPACING)*game.HEIGHT_STEP_DRAWN if cell.layer > grid.GROUND_LAYER else 0
}
