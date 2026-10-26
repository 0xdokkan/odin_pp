package render

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import world "../expedition"
import game "../game"
import grid "../engine/grid"
import level "../level"

// THE LAYER OVER THE GROUND IN THE EXPEDITIONS (Fase 7 of docs/piano-profondita.md): a complex's bridges and walkways
// (expedition/complex.odin), drawn by the floor program in a pass of their own (floorLayer 2, expedition_floor.odin):
//
// - every floor of the layer over the ground, its top at its height (the vertices' red at 255; their green says the
//   way the bridge runs, 255 along x; their blue whether the cell is on its edge, 0, or in its middle, 255), in four
//   triangles round its middle where a side is open, whose corners there carry 0 in their alpha: the floor program
//   draws the biome's railing there (neon, a beam, a vine);
// - on every open side its edge, down to its underside LAYER_THICKNESS steps lower, and the underside (red at 0);
// - in the Far West the trestles of the train's bridge: posts from its underside down to the ground every third column.
//
// A side is open where the next column holds no floor within a step of the deck's height (a block's top it joins). A deck
// over the robot's eyes fades round him (Fase 4's rule, game.layer_cover_opacity): the tall program's cover, as in a cave.
// Kept in blocks of 8 by 8 cells like the relief, rebuilt when the map's geometry changes.

@(private = "file")
deck_vertex :: proc(vertices: ^[dynamic]Expedition_Baked_Vertex, p, normal: rl.Vector3, color: rl.Color) {
	append(vertices, Expedition_Baked_Vertex{p, normal, color})
}

// A quad of the deck's frame (red 0), lit flat: its corners in order round it, its normal turned to `outward`.
@(private = "file")
deck_frame :: proc(vertices: ^[dynamic]Expedition_Baked_Vertex, quad: [4]rl.Vector3, outward: rl.Vector3) {
	for i in ([6]int{0, 1, 2, 0, 2, 3}) { deck_vertex(vertices, quad[i], outward, {0, 0, 0, 255}) }
}

// Whether the side of the deck at `floor` steps toward column (x, y) is open: no floor there within a step of its height.
@(private = "file")
deck_open :: proc(m: ^level.Layer_Map, x, y: int, floor: i32) -> bool {
	for layer in grid.LOWEST_LAYER..=grid.HIGHEST_LAYER {
		p := grid.Position{x = x, y = y, layer = i8(layer)}
		if level.kind_has_floor(level.map_tile(m, p)) && abs(level.map_height(m, p)-floor) <= game.HEIGHT_MAX_STEP { return false }
	}
	return true
}

// A trestle's post: a square of `half` a side round (x, z), from `top` down to `bottom` (drawn units).
@(private = "file")
deck_post :: proc(vertices: ^[dynamic]Expedition_Baked_Vertex, x, z, half, top, bottom: f32) {
	corners := [4][2]f32{{-half, -half}, {half, -half}, {half, half}, {-half, half}}
	outwards := [4]rl.Vector3{{0, 0, -1}, {1, 0, 0}, {0, 0, 1}, {-1, 0, 0}}
	for side in 0..<4 {
		a, b := corners[side], corners[(side+1)%4]
		deck_frame(vertices, {{x+a.x, top, z+a.y}, {x+b.x, top, z+b.y}, {x+b.x, bottom, z+b.y}, {x+a.x, bottom, z+a.y}}, outwards[side])
	}
}

// The decks of the layer over the ground in one block.
@(private = "file")
build_deck_chunk :: proc(m: ^level.Layer_Map, origin: grid.Position, trestles: bool, chunk: ^Expedition_Terrain_Chunk,
	vertices: ^[dynamic]Expedition_Baked_Vertex, base: i32) {
	clear(vertices)
	step := game.HEIGHT_STEP_DRAWN
	up, down := rl.Vector3{0, 1, 0}, rl.Vector3{0, -1, 0}
	corners := [4][2]int{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
	sides := [4][2]int{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}
	for layer in grid.GROUND_LAYER+1..=grid.HIGHEST_LAYER {
		if len(m.tiles[level.layer_slot(i8(layer))]) == 0 { continue }
		for y in origin.y..<min(origin.y+EXPEDITION_TERRAIN_CHUNK, m.height) {
			for x in origin.x..<min(origin.x+EXPEDITION_TERRAIN_CHUNK, m.width) {
				cell := grid.Position{x = x, y = y, layer = i8(layer)}
				if !level.kind_has_floor(level.map_tile(m, cell)) { continue }
				floor := level.map_height(m, cell)
				// Drawn from the map's base (board_drawn's rule).
				top, bottom := f32(floor-base)*step+0.004, f32(floor-base-level.LAYER_THICKNESS)*step
				open: [4]bool
				for side, i in sides { open[i] = deck_open(m, x+side.x, y+side.y, floor) }
				// Along x when a side across x (north or south) is open; on its edge when a side across its way is.
				along_x := open[0] || open[2] || !(open[1] || open[3])
				edge := (open[0] || open[2]) if along_x else (open[1] || open[3])
				color := rl.Color{255, 255 if along_x else 0, 0 if edge else 255, 255}
				points: [4]rl.Vector3
				for corner, i in corners { points[i] = {f32(x+corner.x), top, f32(y+corner.y)} }
				if !open[0] && !open[1] && !open[2] && !open[3] {
					for i in ([6]int{0, 2, 1, 0, 3, 2}) { deck_vertex(vertices, points[i], up, color) }
				} else {
					middle := rl.Vector3{f32(x)+0.5, top, f32(y)+0.5}
					for side in 0..<4 {
						a, b := side, (side+1)%4
						rim := color
						if open[side] { rim.a = 0 }
						deck_vertex(vertices, middle, up, color)
						deck_vertex(vertices, points[b], up, rim)
						deck_vertex(vertices, points[a], up, rim)
					}
				}
				// The edge on every open side, and the underside.
				for side, i in sides {
					if !open[i] { continue }
					a, b := corners[i], corners[(i+1)%4]
					outward := rl.Vector3{f32(side.x), 0, f32(side.y)}
					deck_frame(vertices, {{f32(x+a.x), top, f32(y+a.y)}, {f32(x+b.x), top, f32(y+b.y)}, {f32(x+b.x), bottom, f32(y+b.y)}, {f32(x+a.x), bottom, f32(y+a.y)}}, outward)
				}
				deck_frame(vertices, {{f32(x), bottom, f32(y)}, {f32(x+1), bottom, f32(y)}, {f32(x+1), bottom, f32(y+1)}, {f32(x), bottom, f32(y+1)}}, down)
				// A trestle's posts under the bridge's edges, every third column along it, down to the ground.
				if trestles && edge && (x if along_x else y)%3 == 0 {
					ground := f32(level.map_height(m, {x = x, y = y})-base)*step
					for side, i in sides {
						if !open[i] || (along_x && i%2 == 1) || (!along_x && i%2 == 0) { continue }
						deck_post(vertices, f32(x)+0.5+f32(side.x)*0.32, f32(y)+0.5+f32(side.y)*0.32, 0.07, bottom, ground)
					}
				}
			}
		}
	}
	delete(chunk.vertices)
	chunk.vertices = nil
	chunk.ready = true
	if len(vertices^) == 0 { chunk.center, chunk.radius = {f32(origin.x)+4, 0, f32(origin.y)+4}, 0; return }
	chunk.vertices = make([]Expedition_Baked_Vertex, len(vertices^))
	copy(chunk.vertices, vertices^[:])
	low, high := rl.Vector3{1e9, 1e9, 1e9}, rl.Vector3{-1e9, -1e9, -1e9}
	for v in chunk.vertices {
		low = {min(low.x, v.position.x), min(low.y, v.position.y), min(low.z, v.position.z)}
		high = {max(high.x, v.position.x), max(high.y, v.position.y), max(high.z, v.position.z)}
	}
	chunk.center = (low+high)*0.5
	chunk.radius = rl.Vector3Distance(low, high)*0.5+0.1
}

// Whether the map has floors on a layer over the ground.
@(private)
expedition_has_decks :: proc(data: ^level.Level) -> bool {
	if data == nil { return false }
	for layer in grid.GROUND_LAYER+1..=grid.HIGHEST_LAYER {
		if len(data.planes[level.layer_slot(i8(layer))].tiles) > 0 { return true }
	}
	return false
}

// Builds every block when the map's geometry is new.
@(private = "file")
prepare_expedition_decks :: proc(cache: ^Expedition_Under_Cache, data: ^level.Level, trestles: bool) {
	if cache.ready && cache.geometry_id == data.geometry_id && cache.revision == data.geometry_revision { return }
	destroy_expedition_under(cache)
	cache.geometry_id, cache.revision = data.geometry_id, data.geometry_revision
	cache.columns = (data.tiles.width+EXPEDITION_TERRAIN_CHUNK-1)/EXPEDITION_TERRAIN_CHUNK
	cache.rows = (data.tiles.height+EXPEDITION_TERRAIN_CHUNK-1)/EXPEDITION_TERRAIN_CHUNK
	cache.chunks = make([]Expedition_Terrain_Chunk, cache.columns*cache.rows)
	cache.ready = true
	if !expedition_has_decks(data) { return }
	m := level.layer_map(data)
	scratch := make([dynamic]Expedition_Baked_Vertex, 0, 4096)
	defer delete(scratch)
	for cy in 0..<cache.rows {
		for cx in 0..<cache.columns {
			build_deck_chunk(&m, {x = cx*EXPEDITION_TERRAIN_CHUNK, y = cy*EXPEDITION_TERRAIN_CHUNK}, trestles, &cache.chunks[cy*cache.columns+cx], &scratch, data.base)
		}
	}
}

// Whether a deck stands within the view round the robot.
@(private)
expedition_decks_in_view :: proc(renderer: ^Renderer, room: ^game.Room, w: ^world.World) -> bool {
	data := room.level_data
	f := renderer.tactical.expedition_floor
	if data == nil || f == nil || !expedition_has_decks(data) { return false }
	cache := &f.decks
	prepare_expedition_decks(cache, data, w.biome == .West)
	p := room.player.position
	low := grid.Position{x = max(0, p.x-26)/EXPEDITION_TERRAIN_CHUNK, y = max(0, p.y-26)/EXPEDITION_TERRAIN_CHUNK}
	high := grid.Position{x = min(cache.columns-1, (p.x+26)/EXPEDITION_TERRAIN_CHUNK), y = min(cache.rows-1, (p.y+26)/EXPEDITION_TERRAIN_CHUNK)}
	for cy in low.y..=high.y {
		for cx in low.x..=high.x { if len(cache.chunks[cy*cache.columns+cx].vertices) > 0 { return true } }
	}
	return false
}

// Submits the decks in view, with the floor program already bound (floorLayer 2).
@(private)
draw_expedition_decks :: proc(renderer: ^Renderer, room: ^game.Room, w: ^world.World) {
	data := room.level_data
	f := renderer.tactical.expedition_floor
	if data == nil || f == nil || !expedition_has_decks(data) { return }
	cache := &f.decks
	prepare_expedition_decks(cache, data, w.biome == .West)
	p := room.player.position
	low := grid.Position{x = max(0, p.x-26)/EXPEDITION_TERRAIN_CHUNK, y = max(0, p.y-26)/EXPEDITION_TERRAIN_CHUNK}
	high := grid.Position{x = min(cache.columns-1, (p.x+26)/EXPEDITION_TERRAIN_CHUNK), y = min(cache.rows-1, (p.y+26)/EXPEDITION_TERRAIN_CHUNK)}
	reflection := false
	if m := renderer.tactical.expedition_material; m != nil { reflection = m.reflection_pass }
	rlgl.DisableBackfaceCulling()
	defer rlgl.EnableBackfaceCulling()
	for cy in low.y..=high.y {
		for cx in low.x..=high.x {
			chunk := &cache.chunks[cy*cache.columns+cx]
			if len(chunk.vertices) == 0 { continue }
			view := Expedition_Geometry_Chunk{center = chunk.center, radius = chunk.radius}
			if !expedition_chunk_visible(&renderer.tactical.draw_frustum, &view, reflection) { continue }
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
