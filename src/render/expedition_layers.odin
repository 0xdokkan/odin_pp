package render

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import world "../expedition"
import game "../game"
import grid "../engine/grid"
import level "../level"

// THE LAYERS UNDER THE GROUND IN THE EXPEDITIONS (Fase 5 of docs/piano-profondita.md): a cave's rooms under its massif
// (expedition/cave.odin), drawn by the floor program in a pass of their own (floorLayer 1, expedition_floor.odin):
//
// - every floor of a layer under the ground, a quad at its height, darker by the rock round it (the vertices' green);
// - round each floor, a wall of faceted rock up to the room's top where the next cell is rock; none where a step leads
//   out onto another floor (the mouth, whose opening the relief leaves in the massif's side: expedition_terrain.odin);
// - over the rock near the rooms, the cut of the rock at the rooms' top (the vertices' red at 0), so that what fades
//   over the robot (the massif's top, Fase 4's rule) opens on rooms carved in solid rock.
//
// Kept in blocks of 8 by 8 cells like the relief, rebuilt when the map's geometry changes; a map without layers has none.

// How far from a room the cut of the rock is drawn: past the fade's reach round the robot (game.LAYER_FADE_FAR).
EXPEDITION_UNDER_REACH :: 7

Expedition_Under_Cache :: struct {
	chunks:                []Expedition_Terrain_Chunk,
	geometry_id, revision: u64,
	columns, rows:         int,
	ready:                 bool,
}

@(private)
destroy_expedition_under :: proc(cache: ^Expedition_Under_Cache) {
	for &chunk in cache.chunks { delete(chunk.vertices) }
	delete(cache.chunks)
	cache^ = {}
}

// The figures of a sleeping group are not the room's actors: each card has an entity of its own for the board's view of
// the layers (height_view.odin), of the system's kind with an id past zero.
@(private)
expedition_member_entity :: proc(group, member: int) -> game.Entity_Ref {
	return {kind = .System, id = u32(1+group*world.MAX_MEMBERS+member)}
}

// The sleeping members off the ground, on their layers, after the room's actors (set_board_actors): a foe asleep in a
// cave stands on the cave's floor, not on the rock over it. One on the ground needs none: the ground is its floor.
@(private)
set_expedition_board_actors :: proc(w: ^world.World) {
	if !board_heights.layered || w == nil { return }
	for &group, g in w.groups[:w.group_count] {
		for member, i in group.members[:group.count] {
			if member.alive && !member.deployed && member.enemy.position.layer != grid.GROUND_LAYER {
				add_board_actor(expedition_member_entity(g, i), member.enemy.position)
			}
		}
	}
}

// The cave the robot is in, if any, the tunnel under a complex's block, or, anywhere else under rock, the network of a
// raised biome round him (expedition/network.odin): outside it everything is darker, and the robot's lamp lights it.
@(private)
set_expedition_cave_view :: proc(renderer: ^Renderer, room: ^game.Room, w: ^world.World) {
	v := &renderer.tactical
	v.expedition_in_cave = false
	if room == nil || room.player == nil || w == nil { return }
	if low, high, under := world.complex_tunnel_block(w, room.player.position); under {
		v.expedition_in_cave = true
		v.expedition_cave_box = {f32(low.x), f32(low.y), f32(high.x+1), f32(high.y+1)}
		return
	}
	index := world.cave_at(w, room.player.position)
	if index <= 0 {
		// The box is the few cells round him: everything else, over him and round him, is darker.
		if p := room.player.position; p.layer < grid.GROUND_LAYER && board_view.vault {
			v.expedition_in_cave = true
			v.expedition_cave_box = {f32(p.x-2), f32(p.y-2), f32(p.x+3), f32(p.y+3)}
		}
		return
	}
	place := w.caves[index-1].place
	v.expedition_in_cave = true
	v.expedition_cave_box = {f32(place.origin.x-1), f32(place.origin.y-1), f32(place.origin.x+place.width+1), f32(place.origin.y+place.height+1)}
}

@(private = "file")
under_vertex :: proc(vertices: ^[dynamic]Expedition_Baked_Vertex, p, normal: rl.Vector3, color: rl.Color) {
	append(vertices, Expedition_Baked_Vertex{p, normal, color})
}

// A wall of rock on side `side` of the floor cell at (x, y) (TERRAIN_SIDES' order: north, east, south, west), from
// `low` up to `high` (drawn units), facing into the room; its middle pushed a little into the rock so it breaks into
// facets, as the relief's cliffs do.
@(private = "file")
under_wall :: proc(vertices: ^[dynamic]Expedition_Baked_Vertex, x, y, side: int, low, high: f32) {
	corners := [4][2]f32{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
	sides := [4][2]f32{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}
	a, b := corners[side], corners[(side+1)%4]
	into := rl.Vector3{sides[side].x, 0, sides[side].y}
	point :: proc(x, y: int, corner: [2]f32, height: f32) -> rl.Vector3 { return {f32(x)+corner.x, height, f32(y)+corner.y} }
	top_a, top_b := point(x, y, a, high), point(x, y, b, high)
	low_a, low_b := point(x, y, a, low), point(x, y, b, low)
	mid_a, mid_b := (top_a+low_a)*0.5, (top_b+low_b)*0.5
	push := f32(0.05)*(0.4+0.6*f32((x*7+y*13+side*5)%11)/10)
	mid_m := (top_a+top_b+low_a+low_b)*0.25+into*push
	top_m, low_m := (top_a+top_b)*0.5, (low_a+low_b)*0.5
	facet :: proc(vertices: ^[dynamic]Expedition_Baked_Vertex, p, q, r, inward: rl.Vector3) {
		normal := rl.Vector3Normalize(rl.Vector3CrossProduct(q-p, r-p))
		if rl.Vector3DotProduct(normal, inward) < 0 { normal = -normal }
		for v in ([3]rl.Vector3{p, q, r}) { under_vertex(vertices, v, normal, {255, 255, 255, 255}) }
	}
	inward := -into
	facet(vertices, top_a, top_m, mid_m, inward)
	facet(vertices, top_a, mid_m, mid_a, inward)
	facet(vertices, top_m, top_b, mid_b, inward)
	facet(vertices, top_m, mid_b, mid_m, inward)
	facet(vertices, mid_a, mid_m, low_m, inward)
	facet(vertices, mid_a, low_m, low_a, inward)
	facet(vertices, mid_m, mid_b, low_b, inward)
	facet(vertices, mid_m, low_b, low_m, inward)
}

// For every cell, the height of the nearest floor of `layer` within EXPEDITION_UNDER_REACH cells (-1: none), by a search
// from all of them at once.
@(private = "file")
under_near_floors :: proc(m: ^level.Layer_Map, layer: i8, near: []i32) {
	distance := make([]u8, len(near), context.temp_allocator)
	queue := make([dynamic]int, 0, 1024, context.temp_allocator)
	for &value in near { value = -1 }
	for y in 0..<m.height {
		for x in 0..<m.width {
			p := grid.Position{x = x, y = y, layer = layer}
			if !level.kind_has_floor(level.map_tile(m, p)) { continue }
			at := y*m.width+x
			near[at] = level.map_height(m, p)
			append(&queue, at)
		}
	}
	for head := 0; head < len(queue); head += 1 {
		at := queue[head]
		if int(distance[at]) >= EXPEDITION_UNDER_REACH { continue }
		x, y := at%m.width, at/m.width
		for dy in -1..=1 {
			for dx in -1..=1 {
				nx, ny := x+dx, y+dy
				if nx < 0 || ny < 0 || nx >= m.width || ny >= m.height { continue }
				next := ny*m.width+nx
				if near[next] >= 0 { continue }
				near[next], distance[next] = near[at], distance[at]+1
				append(&queue, next)
			}
		}
	}
}

// The rooms of the layers under the ground in one block: floors, walls and the cut of the rock round them.
@(private = "file")
build_under_chunk :: proc(m: ^level.Layer_Map, near: [][]i32, origin: grid.Position, chunk: ^Expedition_Terrain_Chunk,
	vertices: ^[dynamic]Expedition_Baked_Vertex, base: i32) {
	clear(vertices)
	// Heights are drawn from the map's base (board_drawn's rule).
	drawn :: proc(steps, base: i32) -> f32 { return f32(steps-base)*game.HEIGHT_STEP_DRAWN }
	up := rl.Vector3{0, 1, 0}
	for layer in grid.LOWEST_LAYER..<grid.GROUND_LAYER {
		slot := level.layer_slot(i8(layer))
		if len(m.tiles[slot]) == 0 { continue }
		for y in origin.y..<min(origin.y+EXPEDITION_TERRAIN_CHUNK, m.height) {
			for x in origin.x..<min(origin.x+EXPEDITION_TERRAIN_CHUNK, m.width) {
				cell := grid.Position{x = x, y = y, layer = i8(layer)}
				if level.kind_has_floor(level.map_tile(m, cell)) {
					floor := level.map_height(m, cell)
					// The floor, darker at a corner for every cell of rock round it.
					solid :: proc(m: ^level.Layer_Map, x, y: int, layer: i8) -> bool {
						return !level.kind_has_floor(level.map_tile(m, {x = x, y = y, layer = layer}))
					}
					corners := [4][2]int{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
					points: [4]rl.Vector3
					colors: [4]rl.Color
					for corner, i in corners {
						points[i] = {f32(x+corner.x), drawn(floor, base)+0.004, f32(y+corner.y)}
						sx, sy := x+corner.x*2-1, y+corner.y*2-1
						rock := int(solid(m, sx, y, cell.layer))+int(solid(m, x, sy, cell.layer))+int(solid(m, sx, sy, cell.layer))
						colors[i] = {255, u8(255-rock*40), 255, 255}
					}
					for i in ([6]int{0, 2, 1, 0, 3, 2}) { under_vertex(vertices, points[i], up, colors[i]) }
					// The walls where the next cell is rock: none where a step goes out onto another floor (a mouth).
					sides := [4][2]int{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}
					for side, i in sides {
						nx, ny := x+side.x, y+side.y
						if !solid(m, nx, ny, cell.layer) { continue }
						if _, open := level.column_landing(m, nx, ny, floor, game.HEIGHT_MAX_STEP); open { continue }
						under_wall(vertices, x, y, i, drawn(floor, base), drawn(floor+level.LAYER_CLEARANCE, base))
					}
					continue
				}
				// The cut of the rock at the rooms' top, where the rock is deep enough to hold them.
				reach := near[slot][y*m.width+x]
				if reach < 0 { continue }
				ground := grid.Position{x = x, y = y}
				if !level.kind_has_floor(level.map_tile(m, ground)) || level.map_height(m, ground) < reach+level.LAYER_SPACING { continue }
				top := drawn(reach+level.LAYER_CLEARANCE, base)
				// Kept inside the rock's sides, whose facets go into it a little (expedition_terrain.odin).
				inset :: proc(m: ^level.Layer_Map, x, y: int, reach: i32, layer: i8) -> f32 {
					next := grid.Position{x = x, y = y}
					if level.kind_has_floor(level.map_tile(m, {x = x, y = y, layer = layer})) { return 0 }
					if level.kind_has_floor(level.map_tile(m, next)) && level.map_height(m, next) >= reach+level.LAYER_SPACING { return 0 }
					return 0.08
				}
				west, east := f32(x)+inset(m, x-1, y, reach, cell.layer), f32(x+1)-inset(m, x+1, y, reach, cell.layer)
				north, south := f32(y)+inset(m, x, y-1, reach, cell.layer), f32(y+1)-inset(m, x, y+1, reach, cell.layer)
				quad := [4]rl.Vector3{{west, top, north}, {east, top, north}, {east, top, south}, {west, top, south}}
				for i in ([6]int{0, 2, 1, 0, 3, 2}) { under_vertex(vertices, quad[i], up, {0, 255, 255, 255}) }
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

// Builds every block when the map's geometry is new.
@(private)
prepare_expedition_under :: proc(cache: ^Expedition_Under_Cache, data: ^level.Level) {
	if cache.ready && cache.geometry_id == data.geometry_id && cache.revision == data.geometry_revision { return }
	destroy_expedition_under(cache)
	cache.geometry_id, cache.revision = data.geometry_id, data.geometry_revision
	cache.columns = (data.tiles.width+EXPEDITION_TERRAIN_CHUNK-1)/EXPEDITION_TERRAIN_CHUNK
	cache.rows = (data.tiles.height+EXPEDITION_TERRAIN_CHUNK-1)/EXPEDITION_TERRAIN_CHUNK
	cache.chunks = make([]Expedition_Terrain_Chunk, cache.columns*cache.rows)
	cache.ready = true
	if !level.has_layers(data) { return }
	m := level.layer_map(data)
	near: [level.LAYER_COUNT][]i32
	for layer in grid.LOWEST_LAYER..<grid.GROUND_LAYER {
		slot := level.layer_slot(i8(layer))
		if len(m.tiles[slot]) == 0 { continue }
		near[slot] = make([]i32, data.tiles.width*data.tiles.height, context.temp_allocator)
		under_near_floors(&m, i8(layer), near[slot])
	}
	scratch := make([dynamic]Expedition_Baked_Vertex, 0, 4096)
	defer delete(scratch)
	for cy in 0..<cache.rows {
		for cx in 0..<cache.columns {
			build_under_chunk(&m, near[:], {x = cx*EXPEDITION_TERRAIN_CHUNK, y = cy*EXPEDITION_TERRAIN_CHUNK}, &cache.chunks[cy*cache.columns+cx], &scratch, data.base)
		}
	}
}

// Submits the rooms under the ground in view, with the floor program already bound (floorLayer 1). Out of a cave only
// the blocks round the robot's: what the window cut round him in the rock and a mouth near him show (from farther a
// mouth is a dark opening).
@(private)
draw_expedition_under :: proc(renderer: ^Renderer, room: ^game.Room) {
	data := room.level_data
	f := renderer.tactical.expedition_floor
	if data == nil || f == nil || !level.has_layers(data) { return }
	cache := &f.under
	prepare_expedition_under(cache, data)
	p := room.player.position
	reach := 26 if board_view.vault else EXPEDITION_TERRAIN_CHUNK
	low := grid.Position{x = max(0, p.x-reach)/EXPEDITION_TERRAIN_CHUNK, y = max(0, p.y-reach)/EXPEDITION_TERRAIN_CHUNK}
	high := grid.Position{x = min(cache.columns-1, (p.x+reach)/EXPEDITION_TERRAIN_CHUNK), y = min(cache.rows-1, (p.y+reach)/EXPEDITION_TERRAIN_CHUNK)}
	rlgl.DisableBackfaceCulling()
	defer rlgl.EnableBackfaceCulling()
	for cy in low.y..=high.y {
		for cx in low.x..=high.x {
			chunk := &cache.chunks[cy*cache.columns+cx]
			if len(chunk.vertices) == 0 { continue }
			view := Expedition_Geometry_Chunk{center = chunk.center, radius = chunk.radius}
			if !expedition_chunk_visible(&renderer.tactical.draw_frustum, &view, false) { continue }
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
