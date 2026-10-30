package level

import grid "../engine/grid"

// LAYERS (docs/piano-profondita.md, 2.4). The ground is the map of today; a map may also have cells on
// the layers under it (caves, down to grid.LOWEST_LAYER) and over it (bridges, up to grid.HIGHEST_LAYER).
// Each of those is a plane the size of the ground, empty until one of its cells is set; an empty plane,
// or a Void cell of one, is no cell at all. Heights count from the same zero on every layer.
//
// A column is the cells with the same x and y on every layer. Two floors of one column (cells one walks
// on, or a fence stands on) are LAYER_SPACING steps apart at least, the higher layer higher: over every
// floor LAYER_CLEARANCE steps are free for a figure, and a bridge's deck or the rock over a cave is
// LAYER_THICKNESS thick. So a neighbour column holds one walkable cell at most within two steps of any
// height, and a step never chooses a layer (check_layers refuses a map that breaks it).

LAYER_CLEARANCE :: i32(10)
LAYER_THICKNESS :: i32(2)
LAYER_SPACING :: LAYER_CLEARANCE+LAYER_THICKNESS
LAYER_COUNT :: grid.HIGHEST_LAYER-grid.LOWEST_LAYER+1

// The cells of one layer other than the ground, row-major as the ground's tiles (empty: none).
Layer_Plane :: struct {
	tiles:   [dynamic]Tile,
	heights: [dynamic]u8,
}

// A ladder up a cliff between two cells of neighbour columns: a walker on either end steps to the other.
Ladder :: struct {
	low, high: grid.Position,
}

// A lift (Fase 7 of docs/piano-profondita.md): a platform that goes up and down a shaft between two landings, walkable
// cells of one column on two layers: down into a cave's hall, or up a cliff to a landing on the layer over its foot,
// one step from the top. The map has the shaft; where the platform is, and who rides it, is the game's (it moves in
// play).
Lift :: struct {
	ends: [2]grid.Position,
	// The end where the platform waits when the map is made.
	rest: u8,
}

// A shortcut's gate (Fase 7 of docs/piano-profondita.md): bars across a passage, which one sees through but does not
// pass, until someone on `lever` (the cell beside it on its side) opens it. Shut, its cell is a Fence; open, a Floor.
// The map is made with every gate shut, so every run finds them shut; an expedition saved keeps them as they are
// (their cells' kinds).
Gate :: struct {
	cell, lever: grid.Position,
}

// Where a layer's plane is kept in Level.planes (the ground's slot stays empty: its cells are Level.tiles).
layer_slot :: proc(layer: i8) -> int {
	return int(layer)-grid.LOWEST_LAYER
}

layer_in_range :: proc(layer: i8) -> bool {
	return layer >= grid.LOWEST_LAYER && layer <= grid.HIGHEST_LAYER
}

// Whether `position` is a cell of the map: within the ground's bounds, on one of the layers.
layer_contains :: proc(level: ^Level, position: grid.Position) -> bool {
	return level != nil && layer_in_range(position.layer) && position.x >= 0 && position.y >= 0 &&
		position.x < level.tiles.width && position.y < level.tiles.height
}

// Whether the map has a cell on a layer other than the ground. Without one, every rule is the ground's.
has_layers :: proc(level: ^Level) -> bool {
	if level == nil { return false }
	for plane in level.planes { if len(plane.tiles) > 0 { return true } }
	return false
}

// Whether a cell of `kind` has a floor: one walks on it, or a fence stands on it.
kind_has_floor :: proc(kind: Tile_Kind) -> bool {
	return is_walkable(kind) || kind == .Fence
}

@(private)
plane_tile :: proc(level: ^Level, position: grid.Position) -> (Tile, bool) {
	if !layer_contains(level, position) { return {}, false }
	plane := &level.planes[layer_slot(position.layer)]
	if len(plane.tiles) == 0 { return {kind = .Void}, true }
	return plane.tiles[position.y*level.tiles.width+position.x], true
}

@(private)
plane_height :: proc(level: ^Level, position: grid.Position) -> i32 {
	if !layer_contains(level, position) { return 0 }
	plane := &level.planes[layer_slot(position.layer)]
	if len(plane.heights) == 0 { return 0 }
	return i32(plane.heights[position.y*level.tiles.width+position.x])
}

@(private)
set_plane_tile :: proc(level: ^Level, position: grid.Position, tile: Tile) -> bool {
	if !layer_contains(level, position) { return false }
	plane := &level.planes[layer_slot(position.layer)]
	if len(plane.tiles) == 0 {
		if tile.kind == .Void { return true }
		resize(&plane.tiles, len(level.tiles.cells))
	}
	index := position.y*level.tiles.width+position.x
	if plane.tiles[index] == tile { return true }
	plane.tiles[index] = tile
	mark_geometry_changed(level)
	return true
}

@(private)
set_plane_height :: proc(level: ^Level, position: grid.Position, steps: i32) -> bool {
	if !layer_contains(level, position) { return false }
	plane := &level.planes[layer_slot(position.layer)]
	if len(plane.heights) == 0 {
		if steps == 0 { return true }
		resize(&plane.heights, len(level.tiles.cells))
	}
	index := position.y*level.tiles.width+position.x
	if i32(plane.heights[index]) == steps { return true }
	plane.heights[index] = u8(steps)
	mark_geometry_changed(level)
	return true
}

@(private)
destroy_layers :: proc(level: ^Level) {
	for &plane in level.planes {
		delete(plane.tiles)
		delete(plane.heights)
	}
	delete(level.ladders)
	delete(level.lifts)
	delete(level.gates)
}

// Adds a ladder between two walkable cells of neighbour columns (check_layers checks it again).
add_ladder :: proc(level: ^Level, low, high: grid.Position) -> bool {
	if !layer_contains(level, low) || !layer_contains(level, high) || abs(low.x-high.x)+abs(low.y-high.y) != 1 { return false }
	append(&level.ladders, Ladder{low = low, high = high})
	mark_geometry_changed(level)
	return true
}

// The other end of a ladder that starts on `from` and goes to the column `step` away (none: `found` false).
ladder_end :: proc(level: ^Level, from, step: grid.Position) -> (end: grid.Position, found: bool) {
	if level == nil { return }
	for ladder in level.ladders {
		if ladder.low == from && ladder.high.x == from.x+step.x && ladder.high.y == from.y+step.y { return ladder.high, true }
		if ladder.high == from && ladder.low.x == from.x+step.x && ladder.low.y == from.y+step.y { return ladder.low, true }
	}
	return
}

// Adds a lift between two landings of one column on two layers, its platform waiting at end `rest` (0: `a`, 1: `b`);
// check_layers checks them again.
add_lift :: proc(level: ^Level, a, b: grid.Position, rest := 0) -> bool {
	if !layer_contains(level, a) || !layer_contains(level, b) || a.x != b.x || a.y != b.y || a.layer == b.layer || rest < 0 || rest > 1 { return false }
	append(&level.lifts, Lift{ends = {a, b}, rest = u8(rest)})
	mark_geometry_changed(level)
	return true
}

// Adds a gate, shut, on `cell`, opened from `lever` beside it (a walkable cell of the same layer).
add_gate :: proc(level: ^Level, cell, lever: grid.Position) -> bool {
	if !layer_contains(level, cell) || !layer_contains(level, lever) || cell.layer != lever.layer || abs(cell.x-lever.x)+abs(cell.y-lever.y) != 1 { return false }
	if tile, _ := tile_at(level, lever); !is_walkable(tile.kind) { return false }
	if !set_tile(level, cell, {kind = .Fence}) { return false }
	append(&level.gates, Gate{cell = cell, lever = lever})
	return true
}

// The gate on `cell` (none: `found` false), and whether it is open.
gate_at :: proc(level: ^Level, cell: grid.Position) -> (index: int, open, found: bool) {
	if level == nil { return }
	for gate, i in level.gates {
		if gate.cell != cell { continue }
		tile, _ := tile_at(level, cell)
		return i, tile.kind != .Fence, true
	}
	return
}

// Opens gate `index`: its bars go and its cell is a floor. False if it was open already.
open_gate :: proc(level: ^Level, index: int) -> bool {
	if level == nil || index < 0 || index >= len(level.gates) { return false }
	cell := level.gates[index].cell
	if tile, _ := tile_at(level, cell); tile.kind != .Fence { return false }
	return set_tile(level, cell, {kind = .Floor})
}

// The lift with a landing on `cell`, and which of its two ends that is (none: `found` false).
lift_at :: proc(level: ^Level, cell: grid.Position) -> (index, end: int, found: bool) {
	if level == nil { return }
	for lift, i in level.lifts {
		for landing, k in lift.ends { if landing == cell { return i, k, true } }
	}
	return
}

// The walkable cell of column (x, y), on any layer, at most `reach` steps from `height`: the nearest, the
// lower layer on a tie. A map check_layers accepts holds one at most within two steps.
column_walkable_near :: proc(level: ^Level, x, y: int, height, reach: i32) -> (cell: grid.Position, found: bool) {
	best := reach+1
	for layer in grid.LOWEST_LAYER..=grid.HIGHEST_LAYER {
		p := grid.Position{x = x, y = y, layer = i8(layer)}
		tile, ok := tile_at(level, p)
		if !ok || !is_walkable(tile.kind) { continue }
		distance := abs(height_at(level, p)-height)
		if distance < best { best, cell, found = distance, p, true }
	}
	return
}

Layer_Error :: enum {
	None,
	// Two floors of a column are closer than LAYER_SPACING, or a higher layer's is the lower one.
	Column_Too_Close,
	// A ladder's ends are not walkable cells of neighbour columns.
	Ladder_Invalid,
	// A lift's landings are not walkable cells of one column on two layers, or a cell is the landing of two lifts.
	Lift_Invalid,
}

// Whether the map's layers keep the column's rule (two floors of a column LAYER_SPACING apart at least,
// in the layers' order), its ladders join walkable cells of neighbour columns and its lifts are whole (Lift);
// `bad` is a cell at fault.
check_layers :: proc(level: ^Level) -> (error: Layer_Error, bad: grid.Position) {
	if level == nil || !has_layers(level) && len(level.ladders) == 0 && len(level.lifts) == 0 { return }
	for y in 0..<level.tiles.height {
		for x in 0..<level.tiles.width {
			below_height: i32
			has_below := false
			for layer in grid.LOWEST_LAYER..=grid.HIGHEST_LAYER {
				p := grid.Position{x = x, y = y, layer = i8(layer)}
				tile, _ := tile_at(level, p)
				if !kind_has_floor(tile.kind) { continue }
				height := height_at(level, p)
				if has_below && height-below_height < LAYER_SPACING { return .Column_Too_Close, p }
				below_height, has_below = height, true
			}
		}
	}
	for ladder in level.ladders {
		for end in ([2]grid.Position{ladder.low, ladder.high}) {
			tile, ok := tile_at(level, end)
			if !ok || !is_walkable(tile.kind) { return .Ladder_Invalid, end }
		}
		if abs(ladder.low.x-ladder.high.x)+abs(ladder.low.y-ladder.high.y) != 1 { return .Ladder_Invalid, ladder.low }
	}
	for lift, i in level.lifts {
		for landing in lift.ends {
			tile, ok := tile_at(level, landing)
			if !ok || !is_walkable(tile.kind) { return .Lift_Invalid, landing }
			if other, _, _ := lift_at(level, landing); other != i { return .Lift_Invalid, landing }
		}
		a, b := lift.ends[0], lift.ends[1]
		if a.x != b.x || a.y != b.y || a.layer == b.layer { return .Lift_Invalid, a }
	}
	return
}
