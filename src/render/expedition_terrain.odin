package render

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import grid "../engine/grid"
import level "../level"

// THE RELIEF OF THE EXPEDITIONS' FLOOR (Fase 3 of docs/piano-griglia.md, sculpted in Fase 1 of
// docs/piano-profondita.md). The floor is one plane at the board's level and one texture of the map
// (expedition_floor.odin); the relief is the sculpted surface over it (level/surface.odin), drawn by the same floor
// program so the tiles, the terrains and the warnings read on it too:
//
// - a raised or sloping cell is four triangles round its middle, with the light smoothed across the ramps and hills
//   (a level cell without a cliff on its sides is two);
// - where a neighbour is a cliff lower, a wall of faceted rock goes down to it (to the plane at the map's edge or
//   over the void), and the top of the cliff glows faintly in the biome's colour: the alpha of the top's vertices
//   tells the floor program how near such an edge a point is (0 on it).
//
// The surface is kept as vertices in blocks of 8 by 8 cells, rebuilt when the map's geometry changes, and only the
// blocks in view are submitted. Cells level at the board's height stay on the plane, so a flat biome costs nothing.

EXPEDITION_TERRAIN_CHUNK :: 8

Expedition_Terrain_Chunk :: struct {
	vertices: []Expedition_Baked_Vertex,
	center:   rl.Vector3,
	radius:   f32,
	ready:    bool,
	// The height of the tallest cell in the block, in steps.
	tallest:  u8,
	// Whether a cell's ground in the block dips under the map's base (a stair's pit down to a network): the plane must
	// not cover it.
	sunk:     bool,
}

// From this many steps a terrace is tall enough to hide an actor behind it, and the floor thins it out: a cave's massif,
// a complex's block (expedition/complex.odin).
EXPEDITION_TERRAIN_TALL :: 14

Expedition_Terrain_Cache :: struct {
	chunks:               []Expedition_Terrain_Chunk,
	// For every cell, whether the relief draws over it: the plane under it is never seen.
	raised:               []bool,
	geometry_id, revision: u64,
	columns, rows:        int,
	ready:                bool,
	rebuilds:             u64,
}

@(private)
destroy_expedition_terrain :: proc(cache: ^Expedition_Terrain_Cache) {
	for &chunk in cache.chunks { delete(chunk.vertices) }
	delete(cache.chunks)
	delete(cache.raised)
	cache^ = {}
}

// The corners' places in a cell, from its north-west corner: 0 north-west, 1 north-east, 2 south-east, 3 south-west.
@(private = "file")
TERRAIN_CORNERS :: [4][2]f32{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
// The neighbour across each side: 0 north (corners 0, 1), 1 east (1, 2), 2 south (2, 3), 3 west (3, 0).
@(private = "file")
TERRAIN_SIDES :: [4][2]int{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}

// The surfaces of a block's cells and of the ring of cells round it, which the smoothed light and the walls read.
@(private = "file")
TERRAIN_SPAN :: EXPEDITION_TERRAIN_CHUNK+2

@(private = "file")
Terrain_Block :: struct {
	cells:   [TERRAIN_SPAN*TERRAIN_SPAN]level.Surface_Cell,
	ground:  [TERRAIN_SPAN*TERRAIN_SPAN]bool,
	// Each cell's four triangles' normals: north, east, south and west.
	normals: [TERRAIN_SPAN*TERRAIN_SPAN][4]rl.Vector3,
	origin:  grid.Position,
	// The map's base (level.Level.base): the height drawn at the board's plane.
	base:    f32,
}

@(private = "file")
terrain_point :: proc(x, y: int, corner: int, steps, base: f32) -> rl.Vector3 {
	places := TERRAIN_CORNERS
	return {f32(x)+places[corner].x, (steps-base)*game.HEIGHT_STEP_DRAWN, f32(y)+places[corner].y}
}

@(private = "file")
terrain_slot :: proc(block: ^Terrain_Block, x, y: int) -> (slot: int, ok: bool) {
	lx, ly := x-block.origin.x+1, y-block.origin.y+1
	if lx < 0 || ly < 0 || lx >= TERRAIN_SPAN || ly >= TERRAIN_SPAN { return }
	return ly*TERRAIN_SPAN+lx, true
}

@(private = "file")
terrain_face_normal :: proc(a, b, c: rl.Vector3) -> rl.Vector3 {
	return rl.Vector3Normalize(rl.Vector3CrossProduct(b-a, c-a))
}

// The smoothed normal at corner `corner` of the cell at (x, y): the triangles that touch the corner, in the cell and
// in the cells round the corner whose surface meets it there (the same ramp, never the other side of a cliff).
@(private = "file")
terrain_corner_normal :: proc(block: ^Terrain_Block, x, y, corner: int) -> rl.Vector3 {
	offsets := [4][2]int{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
	point := [2]int{x, y}+offsets[corner]
	own, _ := terrain_slot(block, x, y)
	height := block.cells[own].corners[corner]
	sum: rl.Vector3
	// The cells round the point: north-west, north-east, south-east and south-west of it; the point is their
	// corner (b+2)%4, which the cell's triangles (b+1)%4 and (b+2)%4 touch.
	round := [4][2]int{point+{-1, -1}, point+{0, -1}, point, point+{-1, 0}}
	for cell, b in round {
		slot, inside := terrain_slot(block, cell.x, cell.y)
		if !inside || !block.ground[slot] { continue }
		at := (b+2)%4
		if abs(block.cells[slot].corners[at]-height) > 0.0001 { continue }
		sum += block.normals[slot][(at+3)%4]+block.normals[slot][at]
	}
	return rl.Vector3Normalize(sum)
}

@(private = "file")
terrain_vertex :: proc(vertices: ^[dynamic]Expedition_Baked_Vertex, p, normal: rl.Vector3, edge: u8 = 255) {
	append(vertices, Expedition_Baked_Vertex{p, normal, {255, 255, 255, edge}})
}

// A triangle of rock, lit flat: its own normal, turned to face `outward`.
@(private = "file")
terrain_rock :: proc(vertices: ^[dynamic]Expedition_Baked_Vertex, a, b, c, outward: rl.Vector3) {
	normal := terrain_face_normal(a, b, c)
	if rl.Vector3DotProduct(normal, outward) < 0 { normal = -normal }
	for p in ([3]rl.Vector3{a, b, c}) { terrain_vertex(vertices, p, normal) }
}

@(private = "file")
terrain_hash :: proc(x, y, salt: int) -> f32 {
	h := u32(x)*0x8DA6B343+u32(y)*0xD8163841+u32(salt)*0xCB1AB31F
	h ~= h >> 13
	h *= 0x5BD1E995
	h ~= h >> 15
	return f32(h & 0xFFFF)/65535
}

// The wall of rock on side `side` of the cell at (x, y), from its top edge down to the neighbour's edge (`low`, one
// height per end). Only the parts where this cell is the higher are drawn; the neighbour draws the rest. The middle
// of the wall is pushed a little into the rock, so it breaks into facets; the top edge, where one walks, stays exact.
@(private = "file")
terrain_wall :: proc(vertices: ^[dynamic]Expedition_Baked_Vertex, x, y, side: int, top, low: [2]f32, base: f32) -> bool {
	sides := TERRAIN_SIDES
	a, b := side, (side+1)%4
	bottom := [2]f32{min(low[0], top[0]), min(low[1], top[1])}
	drop := max(top[0]-bottom[0], top[1]-bottom[1])
	if drop*game.HEIGHT_STEP_DRAWN < 0.005 { return false }
	outward := rl.Vector3{f32(sides[side].x), 0, f32(sides[side].y)}
	top_a, top_b := terrain_point(x, y, a, top[0], base), terrain_point(x, y, b, top[1], base)
	low_a, low_b := terrain_point(x, y, a, bottom[0], base), terrain_point(x, y, b, bottom[1], base)
	mid_a, mid_b := (top_a+low_a)*0.5, (top_b+low_b)*0.5
	top_m, low_m := (top_a+top_b)*0.5, (low_a+low_b)*0.5
	// The push grows with the wall's height, so a low wall's facets stay steep (rock, never ground).
	tall := ((top[0]-bottom[0])+(top[1]-bottom[1]))*0.5*game.HEIGHT_STEP_DRAWN
	push := min(f32(0.06), tall*0.3)*(0.4+0.6*terrain_hash(x, y, side))
	mid_m := (top_m+low_m)*0.5-outward*push
	terrain_rock(vertices, top_a, top_m, mid_m, outward)
	terrain_rock(vertices, top_a, mid_m, mid_a, outward)
	terrain_rock(vertices, top_m, top_b, mid_b, outward)
	terrain_rock(vertices, top_m, mid_b, mid_m, outward)
	terrain_rock(vertices, mid_a, mid_m, low_m, outward)
	terrain_rock(vertices, mid_a, low_m, low_a, outward)
	terrain_rock(vertices, mid_m, mid_b, low_b, outward)
	terrain_rock(vertices, mid_m, low_b, low_m, outward)
	return true
}

// The relief of the cells in one block: each raised or sloping cell's top, and the walls of rock on its sides that
// look down on a cliff, the map's edge or the void. `vertices` and `block` are scratch space the caller reuses.
// A cave's mouth in the side of its rock (Fase 5 of docs/piano-profondita.md): where the column (x, y) holds a floor
// under the ground and a step from it toward `next` lands on a floor (the open ground in front of the mouth), the wall
// facing `next` opens over that floor up to the room's top; the height it starts at then, in steps.
@(private)
terrain_opening :: proc(layers: ^level.Layer_Map, x, y: int, next: [2]int) -> (bottom: f32, open: bool) {
	if layers == nil { return }
	for layer in grid.LOWEST_LAYER..<grid.GROUND_LAYER {
		cell := grid.Position{x = x, y = y, layer = i8(layer)}
		if !level.kind_has_floor(level.map_tile(layers, cell)) { continue }
		floor := level.map_height(layers, cell)
		if _, lands := level.column_landing(layers, next.x, next.y, floor, game.HEIGHT_MAX_STEP); lands {
			return f32(floor+level.LAYER_CLEARANCE), true
		}
	}
	return
}

@(private = "file")
build_terrain_chunk :: proc(m: ^level.Surface_Map, origin: grid.Position, chunk: ^Expedition_Terrain_Chunk, raised: []bool,
	vertices: ^[dynamic]Expedition_Baked_Vertex, block: ^Terrain_Block, layers: ^level.Layer_Map = nil, base: i32 = 0) {
	clear(vertices)
	block^ = {}
	block.origin, block.base = origin, f32(base)
	for ly in 0..<TERRAIN_SPAN {
		for lx in 0..<TERRAIN_SPAN {
			x, y := origin.x+lx-1, origin.y+ly-1
			slot := ly*TERRAIN_SPAN+lx
			block.cells[slot], block.ground[slot] = level.surface_cell(m, x, y)
			if !block.ground[slot] { continue }
			cell := block.cells[slot]
			middle := rl.Vector3{f32(x)+0.5, (cell.center-block.base)*game.HEIGHT_STEP_DRAWN, f32(y)+0.5}
			for side in 0..<4 {
				a, b := side, (side+1)%4
				block.normals[slot][side] = terrain_face_normal(middle, terrain_point(x, y, b, cell.corners[b], block.base), terrain_point(x, y, a, cell.corners[a], block.base))
			}
		}
	}
	sides := TERRAIN_SIDES
	low, high := rl.Vector3{1e9, 1e9, 1e9}, rl.Vector3{-1e9, -1e9, -1e9}
	chunk.tallest, chunk.sunk = 0, false
	// Whether a ground cell dips under the base (a pit): the cells round it are drawn, for their walls down into it.
	dips :: proc(block: ^Terrain_Block, x, y: int) -> bool {
		slot, inside := terrain_slot(block, x, y)
		if !inside || !block.ground[slot] { return false }
		for corner in block.cells[slot].corners { if corner < block.base { return true } }
		return block.cells[slot].center < block.base
	}
	for y in origin.y..<min(origin.y+EXPEDITION_TERRAIN_CHUNK, m.height) {
		for x in origin.x..<min(origin.x+EXPEDITION_TERRAIN_CHUNK, m.width) {
			slot, _ := terrain_slot(block, x, y)
			// Over the map's base: the level ground of a raised map stays on the plane, and is no terrace.
			chunk.tallest = max(chunk.tallest, u8(clamp(level.surface_steps(m, x, y)-int(block.base), 0, 255)))
			if !block.ground[slot] { continue }
			cell := block.cells[slot]
			if dips(block, x, y) { chunk.sunk = true }
			beside_pit := dips(block, x-1, y) || dips(block, x+1, y) || dips(block, x, y-1) || dips(block, x, y+1)
			if level.surface_flat(cell) && cell.center == block.base && !beside_pit { continue }
			start := len(vertices^)
			// The walls first: which sides have one decides where the top glows.
			cliff: [4]bool
			for side in 0..<4 {
				next := [2]int{x+sides[side].x, y+sides[side].y}
				if level.surface_linked(m, {x, y}, next) { continue }
				a, b := side, (side+1)%4
				// The neighbour's corners on the shared edge, or the plane where it has no ground.
				across := [2]f32{}
				ground := level.surface_ground(m, next.x, next.y)
				if ground {
					neighbour, _ := terrain_slot(block, next.x, next.y)
					// The neighbour's corners at the same two points: across a north or south side corner c is 3-c,
					// across an east or west side (5-c)%4.
					facing_a, facing_b := 3-a, 3-b
					if side%2 == 1 { facing_a, facing_b = (5-a)%4, (5-b)%4 }
					across = {block.cells[neighbour].corners[facing_a], block.cells[neighbour].corners[facing_b]}
				}
				// Over a cave's mouth the wall opens down to the room's top (expedition_layers.odin draws the room).
				if bottom, open := terrain_opening(layers, x, y, next); open { across = {max(across[0], bottom), max(across[1], bottom)} }
				walled := terrain_wall(vertices, x, y, side, {cell.corners[a], cell.corners[b]}, across, block.base)
				cliff[side] = walled && ground
			}
			// The top: two triangles for a level cell with no cliff to glow on, else four round the middle.
			normals: [4]rl.Vector3
			for corner in 0..<4 { normals[corner] = terrain_corner_normal(block, x, y, corner) }
			points: [4]rl.Vector3
			for corner in 0..<4 { points[corner] = terrain_point(x, y, corner, cell.corners[corner], block.base) }
			if level.surface_flat(cell) && !cliff[0] && !cliff[1] && !cliff[2] && !cliff[3] {
				for corner in ([6]int{0, 2, 1, 0, 3, 2}) { terrain_vertex(vertices, points[corner], normals[corner]) }
			} else {
				middle := rl.Vector3{f32(x)+0.5, (cell.center-block.base)*game.HEIGHT_STEP_DRAWN, f32(y)+0.5}
				up := rl.Vector3Normalize(block.normals[slot][0]+block.normals[slot][1]+block.normals[slot][2]+block.normals[slot][3])
				for side in 0..<4 {
					a, b := side, (side+1)%4
					edge := u8(0) if cliff[side] else 255
					terrain_vertex(vertices, middle, up)
					terrain_vertex(vertices, points[b], normals[b], edge)
					terrain_vertex(vertices, points[a], normals[a], edge)
				}
			}
			raised[y*m.width+x] = true
			for v in vertices^[start:] {
				low = {min(low.x, v.position.x), min(low.y, v.position.y), min(low.z, v.position.z)}
				high = {max(high.x, v.position.x), max(high.y, v.position.y), max(high.z, v.position.z)}
			}
		}
	}
	delete(chunk.vertices)
	chunk.vertices = nil
	if len(vertices^) > 0 {
		chunk.vertices = make([]Expedition_Baked_Vertex, len(vertices^))
		copy(chunk.vertices, vertices^[:])
		chunk.center = (low+high)*0.5
		chunk.radius = rl.Vector3Distance(low, high)*0.5+0.1
	} else {
		chunk.center = {f32(origin.x)+4, 0, f32(origin.y)+4}
		chunk.radius = 0
	}
	chunk.ready = true
}

// Submits the relief in view, with the floor program already bound. The caller has set its uniforms; the vertices
// carry no colour of their own, only how near a cliff's edge they are.
@(private)
draw_expedition_terrain :: proc(renderer: ^Renderer, room: ^game.Room) {
	data := room.level_data
	if data == nil || !level.has_heights(data) { return }
	f := renderer.tactical.expedition_floor
	cache := &f.terrain
	prepare_expedition_terrain(cache, data)
	p := room.player.position
	low := grid.Position{x = max(0, p.x-26)/EXPEDITION_TERRAIN_CHUNK, y = max(0, p.y-26)/EXPEDITION_TERRAIN_CHUNK}
	high := grid.Position{x = min(cache.columns-1, (p.x+26)/EXPEDITION_TERRAIN_CHUNK), y = min(cache.rows-1, (p.y+26)/EXPEDITION_TERRAIN_CHUNK)}
	rlgl.DisableBackfaceCulling()
	defer rlgl.EnableBackfaceCulling()
	reflection := false
	if m := renderer.tactical.expedition_material; m != nil { reflection = m.reflection_pass }
	for cy in low.y..=high.y {
		for cx in low.x..=high.x {
			chunk := &cache.chunks[cy*cache.columns+cx]
			if len(chunk.vertices) == 0 { continue }
			chunk_for_view := Expedition_Geometry_Chunk{center = chunk.center, radius = chunk.radius}
			if !expedition_chunk_visible(&renderer.tactical.draw_frustum, &chunk_for_view, reflection) { continue }
			_ = rlgl.CheckRenderBatchLimit(i32(len(chunk.vertices)))
			rlgl.Begin(rlgl.TRIANGLES)
			for v in chunk.vertices {
				rlgl.Color4ub(v.color.r, v.color.g, v.color.b, v.color.a)
				rlgl.Normal3f(v.normal.x, v.normal.y, v.normal.z)
				rlgl.Vertex3f(v.position.x, v.position.y, v.position.z)
			}
			rlgl.End()
		}
	}
}

// Whether a block in the view round the player holds a terrace tall enough to hide an actor.
@(private)
expedition_terrain_tall_in_view :: proc(renderer: ^Renderer, room: ^game.Room) -> bool {
	data := room.level_data
	if data == nil || !level.has_heights(data) { return false }
	cache := &renderer.tactical.expedition_floor.terrain
	prepare_expedition_terrain(cache, data)
	p := room.player.position
	low := grid.Position{x = max(0, p.x-26)/EXPEDITION_TERRAIN_CHUNK, y = max(0, p.y-26)/EXPEDITION_TERRAIN_CHUNK}
	high := grid.Position{x = min(cache.columns-1, (p.x+26)/EXPEDITION_TERRAIN_CHUNK), y = min(cache.rows-1, (p.y+26)/EXPEDITION_TERRAIN_CHUNK)}
	for cy in low.y..=high.y {
		for cx in low.x..=high.x {
			if cache.chunks[cy*cache.columns+cx].tallest >= EXPEDITION_TERRAIN_TALL { return true }
		}
	}
	return false
}

// Builds the relief of every block when the map's geometry is new.
@(private = "file")
prepare_expedition_terrain :: proc(cache: ^Expedition_Terrain_Cache, data: ^level.Level) {
	if !cache.ready || cache.geometry_id != data.geometry_id || cache.revision != data.geometry_revision {
		rebuilds := cache.rebuilds
		destroy_expedition_terrain(cache)
		cache.geometry_id, cache.revision, cache.rebuilds = data.geometry_id, data.geometry_revision, rebuilds+1
		cache.columns = (data.tiles.width+EXPEDITION_TERRAIN_CHUNK-1)/EXPEDITION_TERRAIN_CHUNK
		cache.rows = (data.tiles.height+EXPEDITION_TERRAIN_CHUNK-1)/EXPEDITION_TERRAIN_CHUNK
		cache.chunks = make([]Expedition_Terrain_Chunk, cache.columns*cache.rows)
		cache.raised = make([]bool, data.tiles.width*data.tiles.height)
		m := level.surface_map(data)
		// The layers, for the caves' mouths in the rock's sides.
		layers: level.Layer_Map
		layered := level.has_layers(data)
		if layered { layers = level.layer_map(data) }
		// One scratch buffer and block for all the blocks, so a big map does not pile up temporary memory.
		scratch := make([dynamic]Expedition_Baked_Vertex, 0, 4096)
		defer delete(scratch)
		block := new(Terrain_Block)
		defer free(block)
		for cy in 0..<cache.rows {
			for cx in 0..<cache.columns {
				build_terrain_chunk(&m, {x = cx*EXPEDITION_TERRAIN_CHUNK, y = cy*EXPEDITION_TERRAIN_CHUNK}, &cache.chunks[cy*cache.columns+cx], cache.raised, &scratch, block, &layers if layered else nil, data.base)
			}
		}
		cache.ready = true
	}
}

// The plane of the floor: one quad for a flat map. For a map with relief, only where it is seen: a few big
// quads beyond the cells near the player, and in that window one quad if little of it is raised, else a
// quad for every run of cells at the board's level along a row (the relief over the rest would hide
// the plane there, and the floor program is dear to run twice).
@(private)
draw_expedition_floor_plane :: proc(renderer: ^Renderer, room: ^game.Room, dimensions: rl.Vector2) {
	data := room.level_data
	if data == nil || !level.has_heights(data) {
		rl.DrawPlane({dimensions.x*.5, -.01, dimensions.y*.5}, dimensions, rl.WHITE)
		return
	}
	cache := &renderer.tactical.expedition_floor.terrain
	prepare_expedition_terrain(cache, data)
	width, depth := data.tiles.width, data.tiles.height
	p := room.player.position
	x0, x1 := max(0, p.x-27), min(width, p.x+28)
	z0, z1 := max(0, p.y-27), min(depth, p.y+28)
	quad :: proc(x, z, w, d: int) {
		if w <= 0 || d <= 0 { return }
		rl.DrawPlane({f32(x)+f32(w)*.5, -.01, f32(z)+f32(d)*.5}, {f32(w), f32(d)}, rl.WHITE)
	}
	// Outside the window: above it, below it, and to each side of it.
	quad(0, 0, width, z0)
	quad(0, z1, width, depth-z1)
	quad(0, z0, x0, z1-z0)
	quad(x1, z0, width-x1, z1-z0)
	raised := 0
	for row in z0..<z1 { for column in x0..<x1 { if cache.raised[row*width+column] { raised += 1 } } }
	// A pit under the plane in the window: the plane leaves it open (and every other cell the relief draws).
	sunk := false
	for cy in z0/EXPEDITION_TERRAIN_CHUNK..=(z1-1)/EXPEDITION_TERRAIN_CHUNK {
		for cx in x0/EXPEDITION_TERRAIN_CHUNK..=(x1-1)/EXPEDITION_TERRAIN_CHUNK { sunk = sunk || cache.chunks[cy*cache.columns+cx].sunk }
	}
	if raised*100 < (x1-x0)*(z1-z0)*8 && !sunk {
		quad(x0, z0, x1-x0, z1-z0)
		return
	}
	for row in z0..<z1 {
		column := x0
		for column < x1 {
			if cache.raised[row*width+column] { column += 1; continue }
			start := column
			for column < x1 && !cache.raised[row*width+column] { column += 1 }
			quad(start, row, column-start, 1)
		}
	}
}
