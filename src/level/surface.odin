package level

import "core:math"

// THE SCULPTED SURFACE (Fase 1 of docs/piano-profondita.md): the drawn shape of the ground, a pure function of the
// heights and the tiles. Every cell has a vertex in its middle, at its own height, and one at each corner. A corner
// is the mean of the cells round it that are linked to the cell: two cells side by side are linked when both have
// ground and they are at most SURFACE_LINK_STEPS apart, the step a walker takes. So a stair of steps becomes a ramp
// and a hill of terraces a hill, while a cliff keeps its edge, with a wall of rock under it. The rules still count
// each cell's own height, and the middle is drawn exactly there.
//
//   corner 0 (x, y) +-------+ corner 1 (x+1, y)
//                   | \ N / |      four triangles round the middle: north (corners 0 and 1),
//                   | W o E |      east (1, 2), south (2, 3) and west (3, 0)
//                   | / S \ |
//   corner 3 (x, y+1) +-------+ corner 2 (x+1, y+1)

// Two cells side by side share their edge when they are at most this many steps apart (game.HEIGHT_MAX_STEP).
SURFACE_LINK_STEPS :: 1

// What the surface reads of a map: the heights in steps (empty: all at 0) and the tiles, both row by row.
Surface_Map :: struct {
	heights:       []u8,
	tiles:         []Tile,
	width, height: int,
}

// A cell's surface, in steps: the height of its middle and of its corners (0 north-west, 1 north-east,
// 2 south-east, 3 south-west).
Surface_Cell :: struct {
	center:  f32,
	corners: [4]f32,
}

surface_map :: proc(data: ^Level) -> Surface_Map {
	if data == nil { return {} }
	return {heights = data.heights[:], tiles = data.tiles.cells[:], width = data.tiles.width, height = data.tiles.height}
}

// Whether the cell at (x, y) has ground: on the map and not Void.
surface_ground :: proc(m: ^Surface_Map, x, y: int) -> bool {
	if m == nil || x < 0 || y < 0 || x >= m.width || y >= m.height { return false }
	index := y*m.width+x
	return index < len(m.tiles) && m.tiles[index].kind != .Void
}

// The height of the cell at (x, y) in steps: 0 off the map or on a flat map.
surface_steps :: proc(m: ^Surface_Map, x, y: int) -> int {
	if m == nil || x < 0 || y < 0 || x >= m.width || y >= m.height { return 0 }
	index := y*m.width+x
	return int(m.heights[index]) if index < len(m.heights) else 0
}

// Whether two cells side by side share their edge on the surface: both have ground and they are a step apart at most.
surface_linked :: proc(m: ^Surface_Map, a, b: [2]int) -> bool {
	if !surface_ground(m, a.x, a.y) || !surface_ground(m, b.x, b.y) { return false }
	return abs(surface_steps(m, a.x, a.y)-surface_steps(m, b.x, b.y)) <= SURFACE_LINK_STEPS
}

// The height of one corner of the cell at (x, y), in steps: the mean of the cells round the corner that the cell
// reaches through linked edges. The cell must have ground.
surface_corner :: proc(m: ^Surface_Map, x, y, corner: int) -> f32 {
	offsets := [4][2]int{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
	point := [2]int{x, y}+offsets[corner]
	// The four cells round the point: north-west, north-east, south-east and south-west of it. Their shared edges
	// make a ring (0-1, 1-2, 2-3, 3-0); the cell itself is the one across from its corner.
	block := [4][2]int{point+{-1, -1}, point+{0, -1}, point, point+{-1, 0}}
	reached: [4]bool
	reached[(corner+2)%4] = true
	// The far way round the ring is three edges long, and each turn goes one way: three turns reach every cell
	// linked to the cell.
	for _ in 0..<3 {
		for i in 0..<4 {
			j := (i+1)%4
			if reached[i] != reached[j] && surface_linked(m, block[i], block[j]) { reached[i], reached[j] = true, true }
		}
	}
	total, count := 0, 0
	for cell, i in block {
		if !reached[i] { continue }
		total += surface_steps(m, cell.x, cell.y)
		count += 1
	}
	return f32(total)/f32(count)
}

// The surface of the cell at (x, y); `ok` is false where the cell has no ground.
surface_cell :: proc(m: ^Surface_Map, x, y: int) -> (cell: Surface_Cell, ok: bool) {
	if !surface_ground(m, x, y) { return }
	cell.center = f32(surface_steps(m, x, y))
	for corner in 0..<4 { cell.corners[corner] = surface_corner(m, x, y, corner) }
	return cell, true
}

// Whether the cell's surface is level at its own height.
surface_flat :: proc(cell: Surface_Cell) -> bool {
	for corner in cell.corners { if corner != cell.center { return false } }
	return true
}

// The highest point of the cell's surface, in steps: what is laid flat on the cell goes over it.
surface_top :: proc(cell: Surface_Cell) -> f32 {
	top := cell.center
	for corner in cell.corners { top = max(top, corner) }
	return top
}

// The height of the surface in steps at a point in cell units (the cell (x, y) spans [x, x+1) by [y, y+1)), on the
// cell's triangle under the point. Off the map or over a Void cell it is 0, the board's plane.
surface_height_at :: proc(m: ^Surface_Map, px, pz: f32) -> f32 {
	x, y := int(math.floor(px)), int(math.floor(pz))
	cell, ok := surface_cell(m, x, y)
	if !ok { return 0 }
	return surface_cell_height_at(cell, px-f32(x), pz-f32(y))
}

// The height of a cell's surface at (u, v) inside the cell, both in 0..1 from its north-west corner.
surface_cell_height_at :: proc(cell: Surface_Cell, u, v: f32) -> f32 {
	// The corners' places relative to the middle; the point lies in the triangle of the side it is nearest to.
	places := [4][2]f32{{-0.5, -0.5}, {0.5, -0.5}, {0.5, 0.5}, {-0.5, 0.5}}
	p := [2]f32{u-0.5, v-0.5}
	a, b: int
	if abs(p.y) >= abs(p.x) {
		a, b = 0, 1
		if p.y > 0 { a, b = 2, 3 }
	} else {
		a, b = 1, 2
		if p.x < 0 { a, b = 3, 0 }
	}
	// p = wa*A + wb*B with the middle at the origin.
	pa, pb := places[a], places[b]
	det := pa.x*pb.y-pb.x*pa.y
	wa := (p.x*pb.y-pb.x*p.y)/det
	wb := (pa.x*p.y-p.x*pa.y)/det
	return cell.center+wa*(cell.corners[a]-cell.center)+wb*(cell.corners[b]-cell.center)
}
