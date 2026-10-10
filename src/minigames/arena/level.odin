// Seeded arena layout (walls, mirrored pillars, spawn runes) and the flow
// field that steers enemies around obstacles.
package arena

import physics "../../engine/physics"
import rng "../../engine/rng"

FLOW_UNREACHED :: u16(0xFFFF)

// Cells kept open around the player's start, so the round opens calmly.
CLEAR_MIN :: [2]int{13, 7}
CLEAR_MAX :: [2]int{22, 13}

// Spawn runes along the inner walls, in tile units (centres may sit on edges).
PORTAL_SPOTS :: [MAX_PORTALS]Vec2{
	{5.5, 2.5},
	{30.5, 2.5},
	{18, 2.5},
	{2.5, 10.5},
	{33.5, 10.5},
	{5.5, 18.5},
	{30.5, 18.5},
	{18, 18.5},
}

NEIGHBORS4 :: [4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
NEIGHBORS8 :: [8][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, 1}, {1, -1}, {-1, -1}}

MAX_SHAPE_CELLS :: 5

@(private)
Shape :: struct {
	cells: [MAX_SHAPE_CELLS][2]int,
	count: int,
}

// Obstacle stamps: pillars, short walls, an L and a cross.
@(private)
shape_of :: proc "contextless" (index: int) -> Shape {
	switch index {
	case 0:
		return {cells = {{0, 0}, {}, {}, {}, {}}, count = 1}
	case 1:
		return {cells = {{0, 0}, {1, 0}, {0, 1}, {1, 1}, {}}, count = 4}
	case 2:
		return {cells = {{0, 0}, {1, 0}, {2, 0}, {}, {}}, count = 3}
	case 3:
		return {cells = {{0, 0}, {0, 1}, {0, 2}, {}, {}}, count = 3}
	case 4:
		return {cells = {{0, 0}, {1, 0}, {0, 1}, {}, {}}, count = 3}
	case 5:
		return {cells = {{1, 0}, {0, 1}, {1, 1}, {2, 1}, {1, 2}}, count = 5}
	}
	return {cells = {{0, 0}, {1, 0}, {}, {}, {}}, count = 2}
}

@(private)
reserved_cell :: proc(w: ^World, x, y: int) -> bool {
	lo := CLEAR_MIN
	hi := CLEAR_MAX
	if x >= lo.x && x <= hi.x && y >= lo.y && y <= hi.y {
		return true
	}
	for i in 0..<w.portal_count {
		c := physics.cell_of(&w.tiles, w.portals[i])
		// Edge-centred runes span two cells; keep both and their ring free.
		if x >= c.x-2 && x <= c.x+1 && y >= c.y-1 && y <= c.y+1 {
			return true
		}
	}
	return false
}

// Walls on the border, then 2-4 mirrored stamps. Every stamp keeps a two-cell
// corridor to anything already solid, so the big enemies can always pass.
generate_level :: proc(w: ^World, r: ^rng.Rng) {
	m := &w.tiles
	for y in 0..<MAP_H {
		for x in 0..<MAP_W {
			border := x == 0 || y == 0 || x == MAP_W-1 || y == MAP_H-1
			physics.set_tile(m, x, y, .Solid if border else .Empty)
		}
	}
	spots := PORTAL_SPOTS
	w.portal_count = MAX_PORTALS
	for i in 0..<MAX_PORTALS {
		w.portals[i] = spots[i] * TILE
	}
	four_fold := rng.chance(r, 0.6)
	target := rng.int_range(r, 2, 4) if four_fold else rng.int_range(r, 3, 6)
	placed := 0
	for attempt := 0; attempt < 200 && placed < target; attempt += 1 {
		shape := shape_of(rng.int_range(r, 0, 5))
		ox := rng.int_range(r, 3, 17)
		oy := rng.int_range(r, 3, 10) if four_fold else rng.int_range(r, 3, MAP_H-4)
		copies: [4]Shape
		copy_count := 4 if four_fold else 2
		for c in 0..<copy_count {
			copies[c].count = shape.count
			for i in 0..<shape.count {
				x := ox + shape.cells[i].x
				y := oy + shape.cells[i].y
				if c == 1 || c == 3 {
					x = MAP_W - 1 - x
				}
				if c >= 2 {
					y = MAP_H - 1 - y
				}
				copies[c].cells[i] = {x, y}
			}
		}
		if stamp_fits(w, copies[:copy_count]) {
			for c in 0..<copy_count {
				for i in 0..<copies[c].count {
					cell := copies[c].cells[i]
					physics.set_tile(m, cell.x, cell.y, .Solid)
				}
			}
			placed += 1
		}
	}
	seal_unreachable(w)
	w.obstacle_cells = 0
	for y in 1..<MAP_H-1 {
		for x in 1..<MAP_W-1 {
			if !open_cell(w, x, y) {
				w.obstacle_cells += 1
			}
		}
	}
}

@(private)
stamp_fits :: proc(w: ^World, copies: []Shape) -> bool {
	for &a, ai in copies {
		for i in 0..<a.count {
			cell := a.cells[i]
			if cell.x < 3 || cell.y < 3 || cell.x > MAP_W-4 || cell.y > MAP_H-4 {
				return false
			}
			if reserved_cell(w, cell.x, cell.y) {
				return false
			}
			// Two free cells to anything solid that is not part of this stamp.
			for dy in -2..=2 {
				for dx in -2..=2 {
					if !open_cell(w, cell.x+dx, cell.y+dy) && !stamp_has(copies, {cell.x + dx, cell.y + dy}) {
						return false
					}
				}
			}
			// Mirrored copies either merge or leave a corridor of two cells.
			for &b, bi in copies {
				if bi == ai {
					continue
				}
				for j in 0..<b.count {
					d := chebyshev(cell, b.cells[j])
					if d == 2 {
						return false
					}
				}
			}
		}
	}
	return true
}

@(private)
stamp_has :: proc(copies: []Shape, cell: [2]int) -> bool {
	for &s in copies {
		for i in 0..<s.count {
			if s.cells[i] == cell {
				return true
			}
		}
	}
	return false
}

@(private)
chebyshev :: proc "contextless" (a, b: [2]int) -> int {
	return max(abs(a.x-b.x), abs(a.y-b.y))
}

// Floods from the start; any open pocket the flood misses becomes wall, so
// nothing can ever spawn or get pushed somewhere unreachable.
@(private)
seal_unreachable :: proc(w: ^World) {
	start := physics.cell_of(&w.tiles, player_start())
	reached := flood_from(w, {start.x, start.y})
	for y in 0..<MAP_H {
		for x in 0..<MAP_W {
			if open_cell(w, x, y) && !reached[y*MAP_W+x] {
				physics.set_tile(&w.tiles, x, y, .Solid)
			}
		}
	}
}

flood_from :: proc(w: ^World, start: [2]int) -> [MAP_W * MAP_H]bool {
	reached: [MAP_W * MAP_H]bool
	if !open_cell(w, start.x, start.y) {
		return reached
	}
	queue: [MAP_W * MAP_H]u16
	head, tail := 0, 0
	reached[start.y*MAP_W+start.x] = true
	queue[tail] = u16(start.y*MAP_W + start.x)
	tail += 1
	n4 := NEIGHBORS4
	for head < tail {
		i := int(queue[head])
		head += 1
		x, y := i % MAP_W, i / MAP_W
		for d in n4 {
			nx, ny := x+d.x, y+d.y
			if !open_cell(w, nx, ny) || reached[ny*MAP_W+nx] {
				continue
			}
			reached[ny*MAP_W+nx] = true
			queue[tail] = u16(ny*MAP_W + nx)
			tail += 1
		}
	}
	return reached
}

// Recomputed only when the player changes cell.
flow_update :: proc(w: ^World) {
	c := physics.cell_of(&w.tiles, w.player.pos)
	cell := [2]int{c.x, c.y}
	if w.flow_ready && cell == w.flow_cell {
		return
	}
	w.flow_cell = cell
	w.flow_ready = true
	for &d in w.flow {
		d = FLOW_UNREACHED
	}
	if !open_cell(w, cell.x, cell.y) {
		return
	}
	queue: [MAP_W * MAP_H]u16
	head, tail := 0, 0
	w.flow[cell.y*MAP_W+cell.x] = 0
	queue[tail] = u16(cell.y*MAP_W + cell.x)
	tail += 1
	n4 := NEIGHBORS4
	for head < tail {
		i := int(queue[head])
		head += 1
		x, y := i % MAP_W, i / MAP_W
		next := w.flow[i] + 1
		for d in n4 {
			nx, ny := x+d.x, y+d.y
			if !open_cell(w, nx, ny) || w.flow[ny*MAP_W+nx] != FLOW_UNREACHED {
				continue
			}
			w.flow[ny*MAP_W+nx] = next
			queue[tail] = u16(ny*MAP_W + nx)
			tail += 1
		}
	}
}

// Direction toward the neighbouring cell closest to the player. Diagonals
// are taken only when both side cells are open, so bodies do not snag corners.
flow_direction :: proc(w: ^World, pos: Vec2) -> Vec2 {
	c := physics.cell_of(&w.tiles, pos)
	if c.x < 0 || c.y < 0 || c.x >= MAP_W || c.y >= MAP_H {
		return {}
	}
	best := w.flow[c.y*MAP_W+c.x]
	target: Vec2
	found := false
	n8 := NEIGHBORS8
	for d in n8 {
		nx, ny := c.x+d.x, c.y+d.y
		if !open_cell(w, nx, ny) {
			continue
		}
		if d.x != 0 && d.y != 0 && (!open_cell(w, c.x+d.x, c.y) || !open_cell(w, c.x, c.y+d.y)) {
			continue
		}
		v := w.flow[ny*MAP_W+nx]
		if v < best {
			best = v
			target = cell_center(nx, ny)
			found = true
		}
	}
	if !found {
		return {}
	}
	return physics.normalize2(target - pos)
}
