package render

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "../game"
import grid "../engine/grid"
import level "../level"

// THE RELIEF OF THE EXPEDITIONS' FLOOR (Fase 3 of docs/piano-griglia.md). The floor is one plane at
// the board's level and one texture of the map (expedition_floor.odin); a cell with a height is a
// terrace on it: its top at its height in steps (game.HEIGHT_STEP_DRAWN of a cell each), drawn by the
// same floor program so the tiles, the terrains and the warnings read on the heights too, and its
// sides, down to the neighbour that is lower, in dark rock. The terraces are kept as vertices in
// blocks of 8 by 8 cells, rebuilt when the map's geometry changes, and only the blocks in view are
// submitted. Cells at the board's level stay on the plane as before, so a flat biome costs nothing.

EXPEDITION_TERRAIN_CHUNK :: 8

Expedition_Terrain_Chunk :: struct {
	vertices: []Expedition_Baked_Vertex,
	center:   rl.Vector3,
	radius:   f32,
	ready:    bool,
	// Every cell of the block is raised (or void): the plane under it is never seen, so it is not drawn.
	covered:  bool,
}

Expedition_Terrain_Cache :: struct {
	chunks:               []Expedition_Terrain_Chunk,
	geometry_id, revision: u64,
	columns, rows:        int,
	ready:                bool,
	rebuilds:             u64,
}

@(private)
destroy_expedition_terrain :: proc(cache: ^Expedition_Terrain_Cache) {
	for &chunk in cache.chunks { delete(chunk.vertices) }
	delete(cache.chunks)
	cache^ = {}
}

@(private = "file")
terrace_quad :: proc(vertices: ^[dynamic]Expedition_Baked_Vertex, a, b, c, d: rl.Vector3, normal: rl.Vector3) {
	color := rl.Color{255, 255, 255, 255}
	for p in ([6]rl.Vector3{a, b, c, a, c, d}) { append(vertices, Expedition_Baked_Vertex{p, normal, color}) }
}

// The terraces of the cells in one block: a top at each raised cell, and a side wherever a neighbour
// is lower (down to that neighbour, or to the plane at the edge of the map).
@(private = "file")
build_terrain_chunk :: proc(data: ^level.Level, origin: grid.Position, chunk: ^Expedition_Terrain_Chunk) {
	vertices := make([dynamic]Expedition_Baked_Vertex, 0, 512, context.temp_allocator)
	step := game.HEIGHT_STEP_DRAWN
	width, height := data.tiles.width, data.tiles.height
	steps_at :: proc(data: ^level.Level, x, y: int) -> int {
		if x < 0 || y < 0 || x >= data.tiles.width || y >= data.tiles.height { return 0 }
		return int(level.height_at(data, {x, y}))
	}
	low, high := rl.Vector3{1e9, 1e9, 1e9}, rl.Vector3{-1e9, -1e9, -1e9}
	chunk.covered = true
	for y in origin.y..<min(origin.y+EXPEDITION_TERRAIN_CHUNK, height) {
		for x in origin.x..<min(origin.x+EXPEDITION_TERRAIN_CHUNK, width) {
			here := steps_at(data, x, y)
			if data.tiles.cells[y*width+x].kind == .Void { continue }
			if here == 0 { chunk.covered = false; continue }
			top := f32(here)*step
			x0, z0 := f32(x), f32(y)
			terrace_quad(&vertices, {x0, top, z0}, {x0, top, z0+1}, {x0+1, top, z0+1}, {x0+1, top, z0}, {0, 1, 0})
			for side in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
				below := steps_at(data, x+side.x, y+side.y)
				if below >= here { continue }
				foot := f32(below)*step
				// The side's two ends along the shared edge.
				a := rl.Vector3{x0+0.5+f32(side.x)*0.5-f32(side.y)*0.5, 0, z0+0.5+f32(side.y)*0.5-f32(side.x)*0.5}
				b := rl.Vector3{x0+0.5+f32(side.x)*0.5+f32(side.y)*0.5, 0, z0+0.5+f32(side.y)*0.5+f32(side.x)*0.5}
				normal := rl.Vector3{f32(side.x), 0, f32(side.y)}
				terrace_quad(&vertices, {a.x, foot, a.z}, {b.x, foot, b.z}, {b.x, top, b.z}, {a.x, top, a.z}, normal)
			}
			low = {min(low.x, x0), 0, min(low.z, z0)}
			high = {max(high.x, x0+1), max(high.y, top), max(high.z, z0+1)}
		}
	}
	delete(chunk.vertices)
	chunk.vertices = nil
	if len(vertices) > 0 {
		chunk.vertices = make([]Expedition_Baked_Vertex, len(vertices))
		copy(chunk.vertices, vertices[:])
		chunk.center = (low+high)*0.5
		chunk.radius = rl.Vector3Distance(low, high)*0.5+0.1
	} else {
		chunk.center = {f32(origin.x)+4, 0, f32(origin.y)+4}
		chunk.radius = 0
	}
	chunk.ready = true
}

// Submits the terraces in view, with the floor program already bound. The caller has set its
// uniforms; the vertices carry no colour of their own.
@(private)
draw_expedition_terrain :: proc(renderer: ^Renderer, room: ^game.Room) {
	data := room.level_data
	if data == nil || !level.has_heights(data) { return }
	f := renderer.tactical.expedition_floor
	cache := &f.terrain
	prepare_expedition_terrain(cache, data)
	p := room.player.position
	low := grid.Position{max(0, p.x-26)/EXPEDITION_TERRAIN_CHUNK, max(0, p.y-26)/EXPEDITION_TERRAIN_CHUNK}
	high := grid.Position{min(cache.columns-1, (p.x+26)/EXPEDITION_TERRAIN_CHUNK), min(cache.rows-1, (p.y+26)/EXPEDITION_TERRAIN_CHUNK)}
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

// Builds the terraces of every block when the map's geometry is new.
@(private = "file")
prepare_expedition_terrain :: proc(cache: ^Expedition_Terrain_Cache, data: ^level.Level) {
	if !cache.ready || cache.geometry_id != data.geometry_id || cache.revision != data.geometry_revision {
		rebuilds := cache.rebuilds
		destroy_expedition_terrain(cache)
		cache.geometry_id, cache.revision, cache.rebuilds = data.geometry_id, data.geometry_revision, rebuilds+1
		cache.columns = (data.tiles.width+EXPEDITION_TERRAIN_CHUNK-1)/EXPEDITION_TERRAIN_CHUNK
		cache.rows = (data.tiles.height+EXPEDITION_TERRAIN_CHUNK-1)/EXPEDITION_TERRAIN_CHUNK
		cache.chunks = make([]Expedition_Terrain_Chunk, cache.columns*cache.rows)
		for cy in 0..<cache.rows {
			for cx in 0..<cache.columns { build_terrain_chunk(data, {cx*EXPEDITION_TERRAIN_CHUNK, cy*EXPEDITION_TERRAIN_CHUNK}, &cache.chunks[cy*cache.columns+cx]) }
		}
		cache.ready = true
	}
}

// The plane of the floor: one quad for a flat map. For a map with relief, only where it is seen: a few big
// quads beyond the cells near the player, and in that window one quad if little of it is raised, else a
// quad for every run of cells at the board's level along a row (the terraces over the rest would hide
// the plane there, and the floor program is dear to run twice).
@(private)
draw_expedition_floor_plane :: proc(renderer: ^Renderer, room: ^game.Room, dimensions: rl.Vector2) {
	data := room.level_data
	if data == nil || !level.has_heights(data) {
		rl.DrawPlane({dimensions.x*.5, -.01, dimensions.y*.5}, dimensions, rl.WHITE)
		return
	}
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
	for row in z0..<z1 { for column in x0..<x1 { if data.heights[row*width+column] != 0 { raised += 1 } } }
	if raised*100 < (x1-x0)*(z1-z0)*8 {
		quad(x0, z0, x1-x0, z1-z0)
		return
	}
	for row in z0..<z1 {
		column := x0
		for column < x1 {
			if data.heights[row*width+column] != 0 { column += 1; continue }
			start := column
			for column < x1 && data.heights[row*width+column] == 0 { column += 1 }
			quad(start, row, column-start, 1)
		}
	}
}
