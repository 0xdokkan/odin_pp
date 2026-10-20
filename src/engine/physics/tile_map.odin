package physics

import "core:math"
import grid "../grid"

Tile_Shape :: enum u8 {
	Empty,
	Solid,
	// Collides only from above, and only when not dropping through.
	One_Way,
}

// Collision layer of a 2D level: y grows downward, cell (0,0) is top-left.
Tile_Map :: struct {
	cells:     grid.Grid(Tile_Shape),
	tile_size: f32,
	// What lies outside the map: Solid for closed rooms, Empty for pits.
	outside:   Tile_Shape,
}

tile_map_create :: proc(width, height: int, tile_size: f32, outside := Tile_Shape.Solid,
	allocator := context.allocator) -> (Tile_Map, bool) {
	if tile_size <= 0 {
		return {}, false
	}
	context.allocator = allocator
	cells, ok := grid.create(Tile_Shape, width, height, Tile_Shape.Empty)
	if !ok {
		return {}, false
	}
	return Tile_Map{cells = cells, tile_size = tile_size, outside = outside}, true
}

tile_map_destroy :: proc(m: ^Tile_Map) {
	grid.destroy(&m.cells)
	m^ = {}
}

tile_at :: proc(m: ^Tile_Map, x, y: int) -> Tile_Shape {
	value, ok := grid.get(&m.cells, grid.Position{x, y})
	return value if ok else m.outside
}

set_tile :: proc(m: ^Tile_Map, x, y: int, shape: Tile_Shape) -> bool {
	return grid.set(&m.cells, grid.Position{x, y}, shape)
}

cell_of :: proc(m: ^Tile_Map, p: Vec2) -> grid.Position {
	return grid.Position{int(math.floor(p.x / m.tile_size)), int(math.floor(p.y / m.tile_size))}
}

cell_rect :: proc(m: ^Tile_Map, x, y: int) -> Rect {
	s := m.tile_size
	return Rect{f32(x) * s, f32(y) * s, s, s}
}

world_size :: proc(m: ^Tile_Map) -> Vec2 {
	return Vec2{f32(m.cells.width) * m.tile_size, f32(m.cells.height) * m.tile_size}
}

// Cells overlapped by a rectangle; edges exactly on a boundary do not count.
@(private)
cell_span :: proc(m: ^Tile_Map, low, size: f32) -> (first, last: int) {
	first = int(math.floor(low / m.tile_size))
	last = int(math.floor((low + size - EPSILON) / m.tile_size))
	return
}

rect_hits_solid :: proc(m: ^Tile_Map, r: Rect) -> bool {
	x0, x1 := cell_span(m, r.x, r.width)
	y0, y1 := cell_span(m, r.y, r.height)
	for y in y0..=y1 {
		for x in x0..=x1 {
			if tile_at(m, x, y) == .Solid {
				return true
			}
		}
	}
	return false
}

// Builds a map from rows of characters. `shape_of` decides each cell's shape.
// All rows must have the same length.
tile_map_from_rows :: proc(rows: []string, tile_size: f32, shape_of: proc(ch: u8) -> Tile_Shape,
	outside := Tile_Shape.Solid, allocator := context.allocator) -> (Tile_Map, bool) {
	if len(rows) == 0 || len(rows[0]) == 0 {
		return {}, false
	}
	width := len(rows[0])
	for row in rows {
		if len(row) != width {
			return {}, false
		}
	}
	m, ok := tile_map_create(width, len(rows), tile_size, outside, allocator)
	if !ok {
		return {}, false
	}
	for row, y in rows {
		for x in 0..<width {
			set_tile(&m, x, y, shape_of(row[x]))
		}
	}
	return m, true
}

Ray_Hit2 :: struct {
	hit:      bool,
	point:    Vec2,
	normal:   Vec2,
	cell:     grid.Position,
	distance: f32,
}

// Grid traversal (Amanatides-Woo) up to max_distance; only Solid cells stop it.
raycast_tiles :: proc(m: ^Tile_Map, origin, direction: Vec2, max_distance: f32) -> Ray_Hit2 {
	dir := normalize2(direction)
	if dir == {} || max_distance <= 0 {
		return {}
	}
	cell := cell_of(m, origin)
	if tile_at(m, cell.x, cell.y) == .Solid {
		return Ray_Hit2{hit = true, point = origin, cell = cell}
	}
	step := [2]int{1 if dir.x > 0 else -1, 1 if dir.y > 0 else -1}
	s := m.tile_size
	t_max, t_delta: Vec2
	for axis in 0..<2 {
		if abs(dir[axis]) < EPSILON {
			t_max[axis] = max(f32)
			t_delta[axis] = max(f32)
			continue
		}
		cell_index := cell.x if axis == 0 else cell.y
		boundary := f32(cell_index+1)*s if step[axis] > 0 else f32(cell_index)*s
		t_max[axis] = (boundary - origin[axis]) / dir[axis]
		t_delta[axis] = s / abs(dir[axis])
	}
	for {
		normal: Vec2
		t: f32
		if t_max.x < t_max.y {
			t = t_max.x
			t_max.x += t_delta.x
			cell.x += step.x
			normal = Vec2{f32(-step.x), 0}
		} else {
			t = t_max.y
			t_max.y += t_delta.y
			cell.y += step.y
			normal = Vec2{0, f32(-step.y)}
		}
		if t > max_distance {
			return {}
		}
		if tile_at(m, cell.x, cell.y) == .Solid {
			return Ray_Hit2{hit = true, point = origin + dir*t, normal = normal, cell = cell, distance = t}
		}
		// An open map can be entered from outside. Stop only when an outside
		// axis cannot approach it, including rays parallel to that axis.
		if !grid.contains(&m.cells, cell) && m.outside != .Solid {
			if (cell.x < 0 && dir.x <= 0) || (cell.x >= m.cells.width && dir.x >= 0) ||
			   (cell.y < 0 && dir.y <= 0) || (cell.y >= m.cells.height && dir.y >= 0) {
				return {}
			}
		}
	}
}

line_of_sight :: proc(m: ^Tile_Map, from, to: Vec2) -> bool {
	d := to - from
	dist := length2(d)
	if dist < EPSILON {
		return true
	}
	return !raycast_tiles(m, from, d, dist).hit
}
