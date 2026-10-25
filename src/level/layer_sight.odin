package level

import grid "../engine/grid"

// A view of a map's layers for the rules that read a whole column at once (a line of sight, a fall): the
// slices of a level's own tables, or of the copy the renderer keeps. A layer without tiles has no cells.
Layer_Map :: struct {
	width, height: int,
	tiles:   [LAYER_COUNT][]Tile,
	heights: [LAYER_COUNT][]u8,
}

layer_map :: proc(level: ^Level) -> (m: Layer_Map) {
	if level == nil { return }
	m.width, m.height = level.tiles.width, level.tiles.height
	ground := layer_slot(grid.GROUND_LAYER)
	m.tiles[ground], m.heights[ground] = level.tiles.cells[:], level.heights[:]
	for &plane, slot in level.planes {
		if slot != ground { m.tiles[slot], m.heights[slot] = plane.tiles[:], plane.heights[:] }
	}
	return
}

// The kind of `p`'s tile in `m`: Void off the map, or where its layer has no cell.
map_tile :: proc(m: ^Layer_Map, p: grid.Position) -> Tile_Kind {
	if m == nil || !layer_in_range(p.layer) || p.x < 0 || p.y < 0 || p.x >= m.width || p.y >= m.height { return .Void }
	tiles := m.tiles[layer_slot(p.layer)]
	index := p.y*m.width+p.x
	return tiles[index].kind if index < len(tiles) else .Void
}

// The height of `p` in `m`, in steps (0 where its layer has no heights).
map_height :: proc(m: ^Layer_Map, p: grid.Position) -> i32 {
	if m == nil || !layer_in_range(p.layer) || p.x < 0 || p.y < 0 || p.x >= m.width || p.y >= m.height { return 0 }
	heights := m.heights[layer_slot(p.layer)]
	index := p.y*m.width+p.x
	return i32(heights[index]) if index < len(heights) else 0
}

// Farther than any height: the end of a solid with no end.
COLUMN_FAR :: i32(1 << 20)

Column_Span :: struct {
	bottom, top: i32,
}

// A column (layers.odin) as the rules see it: its floors, bottom to top, and its solid parts, [bottom, top)
// each, bottom to top. The ground's floor is solid under it; a cave's floor is solid under it, with
// LAYER_CLEARANCE free over it carved out of the rock; a bridge's floor is a deck LAYER_THICKNESS thick. A
// Wall on the ground, or a Void ground with no floor over or under it, fills the whole column.
Column :: struct {
	floors:        [LAYER_COUNT]grid.Position,
	floor_heights: [LAYER_COUNT]i32,
	floor_count:   int,
	solids:        [LAYER_COUNT*2]Column_Span,
	solid_count:   int,
}

@(private = "file")
column_add :: proc(c: ^Column, bottom, top: i32) {
	if bottom >= top { return }
	out: [LAYER_COUNT*2]Column_Span
	count := 0
	merged := Column_Span{bottom, top}
	placed := false
	for span in c.solids[:c.solid_count] {
		switch {
		case span.top < merged.bottom:
			out[count] = span; count += 1
		case span.bottom > merged.top:
			if !placed { out[count] = merged; count += 1; placed = true }
			out[count] = span; count += 1
		case:
			merged = {min(merged.bottom, span.bottom), max(merged.top, span.top)}
		}
	}
	if !placed { out[count] = merged; count += 1 }
	c.solids, c.solid_count = out, count
}

@(private = "file")
column_carve :: proc(c: ^Column, bottom, top: i32) {
	out: [LAYER_COUNT*2]Column_Span
	count := 0
	for span in c.solids[:c.solid_count] {
		if span.top <= bottom || span.bottom >= top { out[count] = span; count += 1; continue }
		if span.bottom < bottom { out[count] = {span.bottom, bottom}; count += 1 }
		if span.top > top { out[count] = {top, span.top}; count += 1 }
	}
	c.solids, c.solid_count = out, count
}

column_of :: proc(m: ^Layer_Map, x, y: int) -> (c: Column) {
	ground := grid.Position{x = x, y = y}
	ground_kind := map_tile(m, ground)
	for layer in grid.LOWEST_LAYER..=grid.HIGHEST_LAYER {
		p := grid.Position{x = x, y = y, layer = i8(layer)}
		if !kind_has_floor(map_tile(m, p)) { continue }
		c.floors[c.floor_count], c.floor_heights[c.floor_count] = p, map_height(m, p)
		c.floor_count += 1
	}
	if ground_kind == .Wall || ground_kind == .Void && c.floor_count == 0 {
		column_add(&c, -COLUMN_FAR, COLUMN_FAR)
		return
	}
	if kind_has_floor(ground_kind) { column_add(&c, -COLUMN_FAR, map_height(m, ground)) }
	for floor, i in c.floors[:c.floor_count] {
		if floor.layer < grid.GROUND_LAYER { column_add(&c, -COLUMN_FAR, c.floor_heights[i]) }
	}
	for floor, i in c.floors[:c.floor_count] {
		if floor.layer < grid.GROUND_LAYER { column_carve(&c, c.floor_heights[i], c.floor_heights[i]+LAYER_CLEARANCE) }
	}
	for floor, i in c.floors[:c.floor_count] {
		if floor.layer > grid.GROUND_LAYER { column_add(&c, c.floor_heights[i]-LAYER_THICKNESS, c.floor_heights[i]) }
	}
	return
}

// Whether the first solid has no bottom: the ground (or the rock under the lowest floor), whose top only
// the middle of a line's cell is measured against, as on a map without layers.
@(private = "file")
column_has_base :: proc(c: ^Column) -> bool {
	return c.solid_count > 0 && c.solids[0].bottom == -COLUMN_FAR
}

// The floor whose room holds the height `z` (scaled by `scale`): the highest floor not above it; the lowest
// floor when `z` is under all of them. `found` is false in a column with no floor.
column_floor_at :: proc(c: ^Column, z: i64, scale: i64) -> (floor: grid.Position, found: bool) {
	if c.floor_count == 0 { return }
	floor, found = c.floors[0], true
	for i in 0..<c.floor_count {
		if i64(c.floor_heights[i])*scale <= z { floor = c.floors[i] }
	}
	return
}

// The lowest solid bottom above `height`: how high the room over a floor at `height` goes.
column_room_top :: proc(c: ^Column, height: i32) -> i32 {
	for span in c.solids[:c.solid_count] {
		if span.bottom >= height { return span.bottom }
	}
	return COLUMN_FAR
}

// Whether the heights from `low` to `high` (scaled by `scale`) touch a solid of `c`, the base too or not.
@(private = "file")
column_touches :: proc(c: ^Column, low, high: i64, scale: i64, base: bool) -> bool {
	for span, i in c.solids[:c.solid_count] {
		if i == 0 && !base && column_has_base(c) { continue }
		if low < i64(span.top)*scale && high > i64(span.bottom)*scale { return true }
	}
	return false
}

// Whether the height `z` (scaled) is inside a solid of `c`.
column_holds :: proc(c: ^Column, z: i64, scale: i64) -> bool {
	for span in c.solids[:c.solid_count] {
		if i64(span.bottom)*scale <= z && z < i64(span.top)*scale { return true }
	}
	return false
}

// Whether the floor `p` would stop a line: a wall, an obstacle, an object (the room's rules).
Line_Opaque :: proc(data: rawptr, p: grid.Position) -> bool

// LINES OF SIGHT THROUGH THE LAYERS. The line goes from the eye, `eye_steps` over `origin`'s floor, to
// `aim_steps` over `destination`'s, cell by cell as the ground's lines do (Bresenham, `count` cells). At each
// cell between the ends:
// - its height at the cell's middle must be out of the column's solids (on the ground alone, the rule of
//   game.height_hides);
// - across the whole cell it must not touch a solid other than the base: a bridge's deck, the rock over a
//   cave. The two ends are measured this way too, from their middles to their sides;
// - the floor whose room it crosses must not be `opaque`, nor, where it cuts a corner, both side columns.
// `destination` is opaque to it only with `check_destination`. Between two layers of one column, the line
// goes straight up or down and must cross no solid. `blocker` is the cell that stopped it.
layer_line_blocker :: proc(m: ^Layer_Map, origin, destination: grid.Position, eye_steps, aim_steps: i32,
	opaque: Line_Opaque, data: rawptr, check_destination := false) -> (blocker: grid.Position, blocked: bool) {
	eye := i64(map_height(m, origin)+eye_steps)
	aim := i64(map_height(m, destination)+aim_steps)
	dx, dy := abs(destination.x-origin.x), abs(destination.y-origin.y)
	count := max(dx, dy)
	if count == 0 {
		c := column_of(m, origin.x, origin.y)
		if origin != destination && column_touches(&c, min(eye, aim), max(eye, aim), 1, true) { return destination, true }
		return
	}
	scale := i64(2*count)
	// The line's height at `u` half-cells from the origin, scaled.
	z :: proc(eye, aim: i64, scale: i64, u: int) -> i64 { return eye*scale+(aim-eye)*i64(u) }
	start := column_of(m, origin.x, origin.y)
	if column_touches(&start, min(z(eye, aim, scale, 0), z(eye, aim, scale, 1)), max(z(eye, aim, scale, 0), z(eye, aim, scale, 1)), scale, false) {
		return origin, true
	}
	sx := 1 if destination.x > origin.x else -1
	sy := 1 if destination.y > origin.y else -1
	error := dx-dy
	x, y := origin.x, origin.y
	for index in 1..=count {
		nx, ny := x, y
		twice := 2*error
		if twice > -dy { error -= dy; nx += sx }
		if twice < dx { error += dx; ny += sy }
		if nx != x && ny != y {
			corner := z(eye, aim, scale, 2*index-1)
			side_x := column_of(m, nx, y)
			side_y := column_of(m, x, ny)
			if side_blocks(&side_x, corner, scale, opaque, data) && side_blocks(&side_y, corner, scale, opaque, data) {
				floor, _ := column_floor_at(&side_x, corner, scale)
				return {x = nx, y = y, layer = floor.layer}, true
			}
		}
		c := column_of(m, nx, ny)
		if index == count {
			low, high := z(eye, aim, scale, 2*count-1), z(eye, aim, scale, 2*count)
			if column_touches(&c, min(low, high), max(low, high), scale, false) { return destination, true }
			if check_destination && opaque != nil && opaque(data, destination) { return destination, true }
			break
		}
		middle := z(eye, aim, scale, 2*index)
		floor, has_floor := column_floor_at(&c, middle, scale)
		cell := grid.Position{x = nx, y = ny, layer = floor.layer if has_floor else grid.GROUND_LAYER}
		if column_holds(&c, middle, scale) { return cell, true }
		low, high := z(eye, aim, scale, 2*index-1), z(eye, aim, scale, 2*index+1)
		if column_touches(&c, min(low, high), max(low, high), scale, false) { return cell, true }
		if has_floor && opaque != nil && opaque(data, floor) { return cell, true }
		x, y = nx, ny
	}
	return
}

// Whether a column beside a cut corner stops the line at the corner's height (scaled): a solid other than
// the base there, a column that is solid all through, or an opaque floor (the lowest one under the line's
// height, as on a map without layers, where the corner's rule does not look at heights).
@(private = "file")
side_blocks :: proc(c: ^Column, z: i64, scale: i64, opaque: Line_Opaque, data: rawptr) -> bool {
	if c.floor_count == 0 { return c.solid_count > 0 }
	if column_touches(c, z, z+1, scale, false) { return true }
	floor, _ := column_floor_at(c, z, scale)
	return opaque != nil && opaque(data, floor)
}

// The floor the line from `origin` to `destination` passes over at its `index`th cell (1-based, of `count`):
// whose room holds the line's height at that cell's middle. The ends are themselves.
layer_line_cell :: proc(m: ^Layer_Map, origin, destination: grid.Position, eye_steps, aim_steps: i32, cell: grid.Position, index, count: int) -> grid.Position {
	if index <= 0 { return origin }
	if index >= count { return destination }
	eye := i64(map_height(m, origin)+eye_steps)
	aim := i64(map_height(m, destination)+aim_steps)
	scale := i64(2*count)
	c := column_of(m, cell.x, cell.y)
	floor, found := column_floor_at(&c, eye*scale+(aim-eye)*i64(2*index), scale)
	return floor if found else {x = cell.x, y = cell.y}
}

// Where something that moves into column (x, y) from `height` lands (a push, a pull, a fall off a bridge):
// the highest floor of the column at most `rise` steps over `height` whose room reaches over `height`.
// `found` is false when none does.
column_landing :: proc(m: ^Layer_Map, x, y: int, height, rise: i32) -> (cell: grid.Position, found: bool) {
	c := column_of(m, x, y)
	for i := c.floor_count-1; i >= 0; i -= 1 {
		floor_height := c.floor_heights[i]
		if floor_height > height+rise || column_room_top(&c, floor_height) <= height { continue }
		return c.floors[i], true
	}
	return
}
