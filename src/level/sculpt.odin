package level

import "core:math"
import grid "../engine/grid"

// SCULPTING (Fase 6 of docs/piano-profondita.md): the brushes of the map editor (src/mapeditor), pure changes of a
// map's tiles and heights on one layer. Every change keeps what the cell was before, so a stroke (the brush held down)
// is undone and done again as a whole (Sculpt_History). Only cells are sculpted: the surface's corners follow from
// them (surface.odin), so what is drawn is what the rules count. A building's cells are the building's: no brush
// touches them. The start, the exit and the doors are the code's: a brush moves their ground, but never takes one away
// nor makes a new one.

Sculpt_Brush :: enum u8 { Raise, Lower, Smooth, Flatten, Paint, Ramp, Copy, Paste, Noise }

// The biggest brush: its radius in cells.
SCULPT_MAX_RADIUS :: 12

Sculpt_Cell :: struct {
	kind:   Tile_Kind,
	height: u8,
}

Sculpt_Change :: struct {
	cell:          grid.Position,
	before, after: Sculpt_Cell,
}

// One stroke: each cell it changed once, what it was before the stroke and what it is after.
Sculpt_Stroke :: struct {
	changes: [dynamic]Sculpt_Change,
	index:   map[grid.Position]int,
}

// The strokes made, the first `done` of them done; the ones past it are undone, and done again in order.
Sculpt_History :: struct {
	strokes: [dynamic]Sculpt_Stroke,
	done:    int,
}

// A piece of a layer copied: its cells row by row, `width` by `height`.
Sculpt_Clip :: struct {
	width, height: int,
	cells:         [dynamic]Sculpt_Cell,
}

sculpt_stroke_destroy :: proc(stroke: ^Sculpt_Stroke) {
	delete(stroke.changes)
	delete(stroke.index)
	stroke^ = {}
}

sculpt_history_destroy :: proc(history: ^Sculpt_History) {
	for &stroke in history.strokes { sculpt_stroke_destroy(&stroke) }
	delete(history.strokes)
	history^ = {}
}

// A new stroke at the end of what is done: the strokes undone are forgotten.
sculpt_begin :: proc(history: ^Sculpt_History) -> ^Sculpt_Stroke {
	for len(history.strokes) > history.done {
		sculpt_stroke_destroy(&history.strokes[len(history.strokes)-1])
		pop(&history.strokes)
	}
	append(&history.strokes, Sculpt_Stroke{})
	return &history.strokes[len(history.strokes)-1]
}

// The stroke begun is done; one that changed nothing is not kept.
sculpt_end :: proc(history: ^Sculpt_History) {
	if len(history.strokes) <= history.done { return }
	last := &history.strokes[len(history.strokes)-1]
	if len(last.changes) == 0 {
		sculpt_stroke_destroy(last)
		pop(&history.strokes)
		return
	}
	history.done = len(history.strokes)
}

@(private = "file")
sculpt_put :: proc(data: ^Level, cell: grid.Position, value: Sculpt_Cell) {
	_ = set_tile(data, cell, {kind = value.kind})
	_ = set_height(data, cell, i32(value.height))
}

// Takes back the last stroke done (false: none).
sculpt_undo :: proc(data: ^Level, history: ^Sculpt_History) -> bool {
	if history.done <= 0 { return false }
	history.done -= 1
	stroke := &history.strokes[history.done]
	#reverse for change in stroke.changes { sculpt_put(data, change.cell, change.before) }
	return true
}

// Does again the first stroke undone (false: none).
sculpt_redo :: proc(data: ^Level, history: ^Sculpt_History) -> bool {
	if history.done >= len(history.strokes) { return false }
	stroke := &history.strokes[history.done]
	for change in stroke.changes { sculpt_put(data, change.cell, change.after) }
	history.done += 1
	return true
}

// What the cell is now.
sculpt_cell :: proc(data: ^Level, cell: grid.Position) -> Sculpt_Cell {
	tile, _ := tile_at(data, cell)
	return {kind = tile.kind, height = u8(clamp(height_at(data, cell), 0, MAX_CELL_HEIGHT))}
}

// Whether a brush may change the cell: on the map, and not a building's.
sculpt_free :: proc(data: ^Level, cell: grid.Position) -> bool {
	if !layer_contains(data, cell) { return false }
	if cell.layer == grid.GROUND_LAYER {
		if _, owned := structure_index_at(data, cell); owned { return false }
	}
	return true
}

// Whether `kind` is one the code places and no brush makes or takes away: the start, the exit, a door.
sculpt_marker :: proc(kind: Tile_Kind) -> bool {
	return kind == .Player_Spawn || kind == .Exit || kind == .Door
}

// Whether the cell has ground a brush shapes: on the ground any cell but Void, on another layer a floor.
sculpt_has_ground :: proc(data: ^Level, cell: grid.Position) -> bool {
	tile, found := tile_at(data, cell)
	if !found || tile.kind == .Void { return false }
	return cell.layer == grid.GROUND_LAYER || kind_has_floor(tile.kind)
}

// Changes the cell to `after` and keeps the change in `stroke` (what it was before the stroke the first time). A
// marker (sculpt_marker) keeps its kind, and where there is none a marker painted or pasted is a floor.
sculpt_set :: proc(data: ^Level, stroke: ^Sculpt_Stroke, cell: grid.Position, after: Sculpt_Cell) -> bool {
	if !sculpt_free(data, cell) { return false }
	before := sculpt_cell(data, cell)
	after := after
	if sculpt_marker(before.kind) { after.kind = before.kind } else if sculpt_marker(after.kind) { after.kind = .Floor }
	if before == after { return false }
	sculpt_put(data, cell, after)
	if at, found := stroke.index[cell]; found {
		stroke.changes[at].after = after
		return true
	}
	stroke.index[cell] = len(stroke.changes)
	append(&stroke.changes, Sculpt_Change{cell = cell, before = before, after = after})
	return true
}

// The cells of a round brush of `radius` round `center`, on its layer (radius 0: the cell alone).
sculpt_footprint :: proc(center: grid.Position, radius: int, out: ^[dynamic]grid.Position) {
	clear(out)
	r := clamp(radius, 0, SCULPT_MAX_RADIUS)
	for dy in -r..=r {
		for dx in -r..=r {
			if dx*dx+dy*dy > r*r+r { continue }
			append(out, grid.offset(center, dx, dy))
		}
	}
}

// Raises (`steps` 1) or lowers (-1) the ground of every cell under the brush.
sculpt_raise :: proc(data: ^Level, stroke: ^Sculpt_Stroke, center: grid.Position, radius, steps: int) {
	cells := make([dynamic]grid.Position, context.temp_allocator)
	sculpt_footprint(center, radius, &cells)
	for cell in cells {
		if !sculpt_has_ground(data, cell) { continue }
		value := sculpt_cell(data, cell)
		value.height = u8(clamp(int(value.height)+steps, 0, MAX_CELL_HEIGHT))
		_ = sculpt_set(data, stroke, cell, value)
	}
}

// Smooths the ground under the brush: every cell takes the mean of its own and its neighbours' heights, as they were
// before this pass, among those of its layer that have ground.
sculpt_smooth :: proc(data: ^Level, stroke: ^Sculpt_Stroke, center: grid.Position, radius: int) {
	cells := make([dynamic]grid.Position, context.temp_allocator)
	sculpt_footprint(center, radius, &cells)
	heights := make([]u8, len(cells), context.temp_allocator)
	for cell, i in cells {
		heights[i] = sculpt_cell(data, cell).height
		if !sculpt_has_ground(data, cell) { continue }
		total, count := 0, 0
		for dy in -1..=1 {
			for dx in -1..=1 {
				next := grid.offset(cell, dx, dy)
				if !sculpt_has_ground(data, next) { continue }
				total += int(height_at(data, next))
				count += 1
			}
		}
		heights[i] = u8(int(math.round(f32(total)/f32(count))))
	}
	for cell, i in cells {
		if !sculpt_has_ground(data, cell) { continue }
		value := sculpt_cell(data, cell)
		value.height = heights[i]
		_ = sculpt_set(data, stroke, cell, value)
	}
}

// Brings the ground under the brush to `height` steps.
sculpt_flatten :: proc(data: ^Level, stroke: ^Sculpt_Stroke, center: grid.Position, radius: int, height: u8) {
	cells := make([dynamic]grid.Position, context.temp_allocator)
	sculpt_footprint(center, radius, &cells)
	for cell in cells {
		if !sculpt_has_ground(data, cell) { continue }
		value := sculpt_cell(data, cell)
		value.height = height
		_ = sculpt_set(data, stroke, cell, value)
	}
}

// Paints the cells under the brush with `kind` (on a layer over or under the ground, Void takes the cell away).
sculpt_paint :: proc(data: ^Level, stroke: ^Sculpt_Stroke, center: grid.Position, radius: int, kind: Tile_Kind) {
	cells := make([dynamic]grid.Position, context.temp_allocator)
	sculpt_footprint(center, radius, &cells)
	for cell in cells {
		if !layer_contains(data, cell) { continue }
		value := sculpt_cell(data, cell)
		value.kind = kind
		_ = sculpt_set(data, stroke, cell, value)
	}
}

// A ramp from `from` to `to` (on `from`'s layer), `radius` cells to each side of the line between them: every cell
// with ground there takes the height between the two ends' heights, as far along as it lies.
sculpt_ramp :: proc(data: ^Level, stroke: ^Sculpt_Stroke, from, to: grid.Position, radius: int) {
	start, end := f32(height_at(data, from)), f32(height_at(data, {x = to.x, y = to.y, layer = from.layer}))
	ax, ay := f32(from.x), f32(from.y)
	bx, by := f32(to.x)-ax, f32(to.y)-ay
	length2 := bx*bx+by*by
	reach := f32(clamp(radius, 0, SCULPT_MAX_RADIUS))+0.5
	low := grid.Position{x = min(from.x, to.x)-radius-1, y = min(from.y, to.y)-radius-1}
	high := grid.Position{x = max(from.x, to.x)+radius+1, y = max(from.y, to.y)+radius+1}
	for y in low.y..=high.y {
		for x in low.x..=high.x {
			cell := grid.Position{x = x, y = y, layer = from.layer}
			if !sculpt_has_ground(data, cell) { continue }
			px, py := f32(x)-ax, f32(y)-ay
			t := clamp((px*bx+py*by)/length2, 0, 1) if length2 > 0 else 0
			dx, dy := px-bx*t, py-by*t
			if dx*dx+dy*dy > reach*reach { continue }
			value := sculpt_cell(data, cell)
			value.height = u8(clamp(int(math.round(start+(end-start)*t)), 0, MAX_CELL_HEIGHT))
			_ = sculpt_set(data, stroke, cell, value)
		}
	}
}

// Copies the cells of the rectangle between `a` and `b` (both corners in), on `a`'s layer.
sculpt_copy :: proc(data: ^Level, a, b: grid.Position, clip: ^Sculpt_Clip) {
	low := grid.Position{x = min(a.x, b.x), y = min(a.y, b.y), layer = a.layer}
	high := grid.Position{x = max(a.x, b.x), y = max(a.y, b.y), layer = a.layer}
	clip.width, clip.height = high.x-low.x+1, high.y-low.y+1
	clear(&clip.cells)
	for y in low.y..=high.y {
		for x in low.x..=high.x { append(&clip.cells, sculpt_cell(data, {x = x, y = y, layer = a.layer})) }
	}
}

// Pastes `clip` with its north-west corner on `origin`, on `origin`'s layer.
sculpt_paste :: proc(data: ^Level, stroke: ^Sculpt_Stroke, clip: ^Sculpt_Clip, origin: grid.Position) {
	for y in 0..<clip.height {
		for x in 0..<clip.width { _ = sculpt_set(data, stroke, grid.offset(origin, x, y), clip.cells[y*clip.width+x]) }
	}
}

// Roughens the ground under the brush: every cell a step up, a step down or as it is, by a fixed hash of the cell and
// of `seed` (the same stroke gives the same ground).
sculpt_noise :: proc(data: ^Level, stroke: ^Sculpt_Stroke, center: grid.Position, radius: int, seed: u32) {
	cells := make([dynamic]grid.Position, context.temp_allocator)
	sculpt_footprint(center, radius, &cells)
	for cell in cells {
		if !sculpt_has_ground(data, cell) { continue }
		h := u32(cell.x+7919)*0x9e3779b9 ~ u32(cell.y+104729)*0x85ebca6b ~ seed*0xc2b2ae35
		h ~= h >> 15
		h *= 0x2c1b3c6d
		h ~= h >> 12
		value := sculpt_cell(data, cell)
		value.height = u8(clamp(int(value.height)+int(h%3)-1, 0, MAX_CELL_HEIGHT))
		_ = sculpt_set(data, stroke, cell, value)
	}
}
