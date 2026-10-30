package game

import grid "../engine/grid"
import level "../level"

// LAYERS IN PLAY (docs/piano-profondita.md, 2.5; level/layers.odin). A map may have cells over the ground (a
// bridge) and under it (a cave); every walkable cell of every layer is a cell of the grid, and the fight
// stays on the grid across them. The rules, as the user chose them in the Fase 3:
// - a step goes into the neighbour column, onto its floor a step from the walker's height at most, on any
//   layer (a ramp onto a bridge, a cave's mouth); a ladder joins two cells over a cliff;
// - a push or a pull goes onto the floor whose room it enters, and off a bridge's open edge falls onto the
//   layer under it, with the fall's damage of today;
// - a line of sight goes through the layers (level.layer_line_blocker): from the bridge one sees and hits
//   the road, and back; the rock over a cave hides it;
// - an area takes the anchor's layer, else the walkable cell nearest in height within two steps;
// - melee on one layer as ever, between two only a step apart at most;
// - the cards that act on the whole board, or with a shape of their own, act on their user's layer as
//   ever and on the other layers only on what their user sees.
// Without layers every one of these is the ground's own rule of before.

// How far in height an area reaches onto another layer (the user's choice: two steps).
AREA_LAYER_REACH :: i32(2)

// Whether the room's map has cells on a layer other than the ground.
room_has_layers :: proc(room: ^Room) -> bool {
	return room != nil && level.has_layers(room.level_data)
}

// The cell one reaches going `step` (a neighbour's offset) from `from`: in the neighbour column, the floor
// one lands on from `from`'s height (level.column_landing: up a step at most, down any drop); with `climb`,
// first the other end of a ladder from `from` toward that column (`ladder` true). Without a floor there it
// is the neighbour cell on `from`'s layer, which the movement's rules then refuse (a wall, a cliff, none).
layer_step :: proc(room: ^Room, from, step: grid.Position, climb := false) -> (cell: grid.Position, ladder: bool) {
	next := grid.offset(from, step.x, step.y)
	if room == nil || room.level_data == nil { return next, false }
	if climb && len(room.level_data.ladders) > 0 {
		if end, found := level.ladder_end(room.level_data, from, step); found { return end, true }
	}
	if !level.has_layers(room.level_data) { return next, false }
	m := level.layer_map(room.level_data)
	if landing, found := level.column_landing(&m, next.x, next.y, cell_height(room, from), HEIGHT_MAX_STEP); found { return landing, false }
	return next, false
}

// The cell a walker reaches going `step` from `from`, ladders included (layer_step).
walk_step :: proc(room: ^Room, from, step: grid.Position) -> grid.Position {
	cell, _ := layer_step(room, from, step, true)
	return cell
}

// Whether going from `from` to `to` is a climb up or down a ladder.
is_ladder_move :: proc(room: ^Room, from, to: grid.Position) -> bool {
	if room == nil || room.level_data == nil || abs(from.x-to.x)+abs(from.y-to.y) != 1 { return false }
	end, found := level.ladder_end(room.level_data, from, {x = to.x-from.x, y = to.y-from.y})
	return found && end == to
}

// Whether two neighbours meet in melee: on one layer as ever (over a cliff too), on two layers only a step
// apart at most (the user's rule: at a ramp onto a bridge, at a cave's mouth).
melee_layers_meet :: proc(room: ^Room, a, b: grid.Position) -> bool {
	return a.layer == b.layer || abs(cell_height(room, a)-cell_height(room, b)) <= HEIGHT_MAX_STEP
}

// The cell a bump going `step` from `from` strikes: a foe on the cell the step lands on, on another layer
// a step away in height at most; else the neighbour cell on `from`'s own layer, over a cliff too, as ever.
bump_cell :: proc(room: ^Room, from, step: grid.Position) -> grid.Position {
	same := grid.offset(from, step.x, step.y)
	if !room_has_layers(room) { return same }
	landing, _ := layer_step(room, from, step)
	if landing != same && melee_layers_meet(room, from, landing) {
		if _, found := enemy_index_at(room, landing); found { return landing }
	}
	return same
}

// The cell an area anchored on `anchor` takes in column (x, y): the anchor's layer where that layer has a cell
// there (the ground always has one), else the walkable cell nearest in height to the anchor within
// AREA_LAYER_REACH steps, on any layer; none where neither is: a bridge or the rock over a cave stops it.
area_cell :: proc(room: ^Room, anchor: grid.Position, x, y: int) -> (cell: grid.Position, ok: bool) {
	cell = {x = x, y = y, layer = anchor.layer}
	if anchor.layer == grid.GROUND_LAYER || !room_has_layers(room) { return cell, true }
	if tile, found := level.tile_at(room.level_data, cell); found && tile.kind != .Void { return cell, true }
	return level.column_walkable_near(room.level_data, x, y, cell_height(room, anchor), AREA_LAYER_REACH)
}

// Whether `cell` is the one an area anchored on `anchor` takes in its column (always, without layers).
area_takes :: proc(room: ^Room, anchor, cell: grid.Position) -> bool {
	taken, ok := area_cell(room, anchor, cell.x, cell.y)
	return ok && taken == cell
}

@(private = "file")
room_line_opaque :: proc(data: rawptr, p: grid.Position) -> bool {
	return cell_blocks_line_of_sight(cast(^Room)data, p)
}

// The line of sight from the eye over `origin` to the middle of `destination`, through the layers, with the
// room's own opaque cells (walls, cover, blocking objects); `destination` itself stops it only with
// `check_destination`.
room_line_blocker :: proc(room: ^Room, origin, destination: grid.Position, check_destination := false) -> (blocker: grid.Position, blocked: bool) {
	if room == nil || room.level_data == nil { return {}, true }
	m := level.layer_map(room.level_data)
	return level.layer_line_blocker(&m, origin, destination, HEIGHT_EYE_STEPS, HEIGHT_TARGET_STEPS, room_line_opaque, room, check_destination)
}

// The room's layers for a line of sight (tactical_line_visible): nil without layers, where the ground's own
// rule holds. `m` is the caller's, which the pointer points into.
room_line_layers :: proc(room: ^Room, m: ^level.Layer_Map) -> ^level.Layer_Map {
	if !room_has_layers(room) || m == nil { return nil }
	m^ = level.layer_map(room.level_data)
	return m
}

// Whether a special card played from `origin` acts on `target` (the user's rule for the cards that act on
// the whole board or with a shape of their own): on `origin`'s layer as ever, on another layer only if the
// line of sight from `origin` reaches it.
effect_reaches :: proc(room: ^Room, origin, target: grid.Position) -> bool {
	if origin.layer == target.layer { return true }
	_, blocked := room_line_blocker(room, origin, target)
	return !blocked
}

// What a ray at `height` steps (a fraction) meets in the column of `cell`: the floor whose room holds it
// (the cell itself without layers), and whether it is inside the column's solids instead (the ground, the
// rock over a cave, a bridge's deck, a wall).
layer_ray_cell :: proc(room: ^Room, cell: grid.Position, height: f32) -> (floor: grid.Position, inside: bool) {
	if !room_has_layers(room) { return cell, false }
	SCALE :: 64
	m := level.layer_map(room.level_data)
	c := level.column_of(&m, cell.x, cell.y)
	z := i64(height*SCALE)
	found: bool
	floor, found = level.column_floor_at(&c, z, SCALE)
	if !found { floor = {x = cell.x, y = cell.y} }
	return floor, level.column_holds(&c, z, SCALE)
}

// How many cells the room's per-cell tables hold (the foes' distances, the pools): the ground's, and as many
// again for each other layer when the map has layers.
room_table_cells :: proc(data: ^level.Level) -> int {
	if data == nil { return 0 }
	cells := len(data.tiles.cells)
	return cells*level.LAYER_COUNT if level.has_layers(data) else cells
}

// The room's tables keep the ground first, at its own index, then the other layers, lowest first: a layer's
// place among them, and the layer at a place.
room_layer_slot :: proc(layer: i8) -> int {
	if layer == grid.GROUND_LAYER { return 0 }
	return level.layer_slot(layer)+1 if layer < grid.GROUND_LAYER else level.layer_slot(layer)
}

room_slot_layer :: proc(slot: int) -> i8 {
	if slot == 0 { return grid.GROUND_LAYER }
	return i8(slot+grid.LOWEST_LAYER-1) if slot <= -grid.LOWEST_LAYER else i8(slot+grid.LOWEST_LAYER)
}

// The cell kept at `index` of the room's per-cell tables (room_table_index's inverse).
room_table_cell :: proc(room: ^Room, index: int) -> grid.Position {
	tiles := &room.level_data.tiles
	cells := len(tiles.cells)
	at := index%cells
	return {x = at%tiles.width, y = at/tiles.width, layer = room_slot_layer(index/cells)}
}

// Where `position` is kept in the room's per-cell tables.
room_table_index :: proc(room: ^Room, position: grid.Position) -> (index: int, ok: bool) {
	if room == nil || room.level_data == nil || !level.layer_contains(room.level_data, position) { return }
	tiles := &room.level_data.tiles
	index = position.y*tiles.width+position.x
	if position.layer == grid.GROUND_LAYER { return index, true }
	if !level.has_layers(room.level_data) { return }
	return index+room_layer_slot(position.layer)*len(tiles.cells), true
}
