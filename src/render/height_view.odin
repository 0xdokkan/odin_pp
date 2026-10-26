package render

import "base:runtime"
import "core:math"
import rl "vendor:raylib"
import game "../game"
import grid "../engine/grid"
import level "../level"
import view "../engine/view"

// HEIGHTS ON THE BOARD (game/height.odin). The board is drawn on a flat plane;
// a cell with a height is lifted by its steps (game.HEIGHT_STEP_DRAWN of a cell
// each), and whatever stands or is drawn on it with it. The ground between the
// cells' middles is the sculpted surface (level/surface.odin): ramps where the
// cells are a step apart, an edge where they are a cliff apart.
//
// Most of what is drawn on the ground does not take the renderer (a marker, an
// intent cell), so the heights the board shows are kept here, set once a frame by
// update_tactical_view and draw_tactical_world: one renderer draws at a time. It is
// a copy of the level's tables, refreshed when the level's geometry changes, and
// never a pointer to the level: a level destroyed under it cannot be read.
@(private)
Board_Heights :: struct {
	cells: [dynamic]u8,
	// The tiles too, which the surface reads: a Void cell has no ground.
	tiles: [dynamic]level.Tile,
	// The other layers' tables (level/layers.odin), by level.layer_slot: empty where the map has none.
	plane_cells: [level.LAYER_COUNT][dynamic]u8,
	plane_tiles: [level.LAYER_COUNT][dynamic]level.Tile,
	layered: bool,
	// The highest floor of any layer, in steps (pick_ground_cell starts its ray there).
	top: u8,
	// For every column, whether a layer other than the ground has a floor in it (board_column_layered).
	layered_columns: [dynamic]bool,
	width, height: int,
	id, revision: u64,
}

@(private)
board_heights: Board_Heights

// Where each actor of the room stands this frame (the room's own cells, on their layers): on a map with layers
// a figure is drawn on its own layer's floor (entity_point_ground).
@(private)
Board_Actor :: struct {
	entity: game.Entity_Ref,
	cell:   grid.Position,
}

@(private)
board_actors: [dynamic]Board_Actor

// The figures riding a lift's platform this frame, and the platform's height (lift_view.odin): each is drawn on it.
@(private)
Board_Lift_Rider :: struct {
	entity: game.Entity_Ref,
	ground: f32,
}

@(private)
board_lift_riders: [dynamic]Board_Lift_Rider

// The level whose heights the next drawing uses (nil: flat).
@(private)
set_board_level :: proc(data: ^level.Level) {
	b := &board_heights
	layered := data != nil && level.has_layers(data)
	if data == nil || !level.has_heights(data) && !layered {
		if len(b.cells) > 0 { clear(&b.cells) }
		if len(b.tiles) > 0 { clear(&b.tiles) }
		for slot in 0..<level.LAYER_COUNT {
			if len(b.plane_cells[slot]) > 0 { clear(&b.plane_cells[slot]) }
			if len(b.plane_tiles[slot]) > 0 { clear(&b.plane_tiles[slot]) }
		}
		b.id, b.revision, b.width, b.height, b.layered, b.top = 0, 0, 0, 0, false, 0
		return
	}
	if b.id == data.geometry_id && b.revision == data.geometry_revision && len(b.cells) == len(data.heights) && b.layered == layered { return }
	// Kept off the test runner's per-test allocator: it outlives any one test.
	if b.cells.allocator.procedure == nil { b.cells = make([dynamic]u8, runtime.heap_allocator()) }
	if b.tiles.allocator.procedure == nil { b.tiles = make([dynamic]level.Tile, runtime.heap_allocator()) }
	clear(&b.cells)
	append(&b.cells, ..data.heights[:])
	clear(&b.tiles)
	append(&b.tiles, ..data.tiles.cells[:])
	for slot in 0..<level.LAYER_COUNT {
		if b.plane_cells[slot].allocator.procedure == nil { b.plane_cells[slot] = make([dynamic]u8, runtime.heap_allocator()) }
		if b.plane_tiles[slot].allocator.procedure == nil { b.plane_tiles[slot] = make([dynamic]level.Tile, runtime.heap_allocator()) }
		clear(&b.plane_cells[slot])
		clear(&b.plane_tiles[slot])
		plane := &data.planes[slot]
		if !layered || len(plane.tiles) == 0 { continue }
		append(&b.plane_tiles[slot], ..plane.tiles[:])
		append(&b.plane_cells[slot], ..plane.heights[:])
	}
	b.layered = layered
	b.top = 0
	for height in b.cells { b.top = max(b.top, height) }
	for cells in b.plane_cells { for height in cells { b.top = max(b.top, height) } }
	if b.layered_columns.allocator.procedure == nil { b.layered_columns = make([dynamic]bool, runtime.heap_allocator()) }
	clear(&b.layered_columns)
	if layered {
		resize(&b.layered_columns, len(data.tiles.cells))
		for tiles in b.plane_tiles {
			for tile, index in tiles { if level.kind_has_floor(tile.kind) { b.layered_columns[index] = true } }
		}
	}
	b.width, b.height = data.tiles.width, data.tiles.height
	b.id, b.revision = data.geometry_id, data.geometry_revision
}

// Where the room's actors stand this frame, on a map with layers (nothing to keep without).
@(private)
set_board_actors :: proc(room: ^game.Room) {
	if board_actors.allocator.procedure == nil { board_actors = make([dynamic]Board_Actor, runtime.heap_allocator()) }
	clear(&board_actors)
	if board_lift_riders.allocator.procedure == nil { board_lift_riders = make([dynamic]Board_Lift_Rider, runtime.heap_allocator()) }
	clear(&board_lift_riders)
	if room == nil || room.player == nil || !board_heights.layered { return }
	for i in 0..<room.lifts.count {
		platform := room.lifts.platforms[i]
		if !platform.moving || !platform.has_rider { continue }
		ground, _ := lift_platform_ground(room, i)
		append(&board_lift_riders, Board_Lift_Rider{platform.rider, ground})
	}
	append(&board_actors, Board_Actor{game.PLAYER_ENTITY, room.player.position})
	for enemy in room.enemies { append(&board_actors, Board_Actor{game.enemy_entity(enemy.id), enemy.position}) }
	for object in room.objects { append(&board_actors, Board_Actor{game.object_entity(object.id), object.position}) }
}

// One more figure standing on `cell` this frame (an expedition's sleeping foe: expedition_member_entity), after the
// room's own: drawn on its layer's floor too.
@(private)
add_board_actor :: proc(entity: game.Entity_Ref, cell: grid.Position) {
	if !board_heights.layered || board_actors.allocator.procedure == nil { return }
	append(&board_actors, Board_Actor{entity, cell})
}

// The board's tables as the surface reads them: the ground's, or `layer`'s.
@(private)
board_surface_map :: proc(layer := i8(grid.GROUND_LAYER)) -> level.Surface_Map {
	b := &board_heights
	if layer == grid.GROUND_LAYER || !level.layer_in_range(layer) {
		return {heights = b.cells[:], tiles = b.tiles[:], width = b.width, height = b.height}
	}
	slot := level.layer_slot(layer)
	return {heights = b.plane_cells[slot][:], tiles = b.plane_tiles[slot][:], width = b.width, height = b.height}
}

// The board's tables as the rules of the layers read them (level/layer_sight.odin).
@(private)
board_layer_map :: proc() -> (m: level.Layer_Map) {
	b := &board_heights
	m.width, m.height = b.width, b.height
	for slot in 0..<level.LAYER_COUNT {
		if slot == level.layer_slot(grid.GROUND_LAYER) {
			m.tiles[slot], m.heights[slot] = b.tiles[:], b.cells[:]
		} else {
			m.tiles[slot], m.heights[slot] = b.plane_tiles[slot][:], b.plane_cells[slot][:]
		}
	}
	return
}

// Whether a layer other than the ground has a floor in the column of `cell`.
@(private)
board_column_layered :: proc(cell: grid.Position) -> bool {
	b := &board_heights
	if !b.layered || cell.x < 0 || cell.y < 0 || cell.x >= b.width || cell.y >= b.height { return false }
	index := cell.y*b.width+cell.x
	return index < len(b.layered_columns) && b.layered_columns[index]
}

// The sculpted surface of `cell` on its layer, in steps; `ok` is false off the board, on a Void cell or on a flat board.
@(private)
cell_surface :: proc(cell: grid.Position) -> (surface: level.Surface_Cell, ok: bool) {
	if cell.layer == grid.GROUND_LAYER && !board_has_heights() { return }
	if cell.layer != grid.GROUND_LAYER && !board_heights.layered { return }
	m := board_surface_map(cell.layer)
	return level.surface_cell(&m, cell.x, cell.y)
}

// How high something laid flat on `cell` goes so the ground does not cover it: the top of the cell's surface.
@(private)
cell_overlay_ground :: proc(cell: grid.Position) -> f32 {
	surface, ok := cell_surface(cell)
	if !ok { return cell_ground(cell) }
	return level.surface_top(surface)*game.HEIGHT_STEP_DRAWN
}

@(private)
board_has_heights :: proc() -> bool {
	return len(board_heights.cells) > 0
}

// How high `cell`'s floor stands over the board's plane, on its layer.
@(private)
cell_ground :: proc(cell: grid.Position) -> f32 {
	b := &board_heights
	if cell.x < 0 || cell.y < 0 || cell.x >= b.width || cell.y >= b.height { return 0 }
	cells := b.cells[:]
	if cell.layer != grid.GROUND_LAYER {
		if !b.layered || !level.layer_in_range(cell.layer) { return 0 }
		cells = b.plane_cells[level.layer_slot(cell.layer)][:]
	}
	index := cell.y*b.width+cell.x
	return f32(cells[index])*game.HEIGHT_STEP_DRAWN if index < len(cells) else 0
}

// The floor's height under a point in cell coordinates (a cell's centre is its
// own coordinates plus a half): the sculpted surface there, so a figure walks up
// a ramp as it is drawn, and stands at its cell's own height in the middle.
@(private)
point_ground :: proc(at: view.Vec2) -> f32 {
	if !board_has_heights() { return 0 }
	m := board_surface_map()
	return level.surface_height_at(&m, at.x+0.5, at.y+0.5)*game.HEIGHT_STEP_DRAWN
}

// The highest ground under a disc of `radius` round `at` (its middle and four points of its rim): a stand or a
// shadow laid flat there is never covered by a slope. With `entity`, the floor of its own layer.
@(private)
rim_ground :: proc(at: view.Vec2, radius: f32, entity := game.Entity_Ref{}) -> f32 {
	ground := entity_point_ground(entity, at)
	for offset in ([4]view.Vec2{{radius, 0}, {-radius, 0}, {0, radius}, {0, -radius}}) { ground = max(ground, entity_point_ground(entity, at+offset)) }
	return ground
}

// The kind of `cell`'s tile in the board's copy, on its layer.
@(private)
board_tile :: proc(cell: grid.Position) -> level.Tile_Kind {
	m := board_layer_map()
	return level.map_tile(&m, cell)
}

// Where the dark column under `cell`'s floor starts, over the board's plane: under the board, or at the top of
// the room over the floor under it (the cave the ground's column stands over); a bridge's floor is a deck
// LAYER_THICKNESS steps thick.
@(private)
cell_base :: proc(cell: grid.Position) -> f32 {
	BOARD_BASE :: f32(-0.31)
	if !board_heights.layered { return BOARD_BASE }
	step := game.HEIGHT_STEP_DRAWN
	if cell.layer > grid.GROUND_LAYER { return cell_ground(cell)-f32(level.LAYER_THICKNESS)*step }
	base := BOARD_BASE
	for layer in grid.LOWEST_LAYER..<int(cell.layer) {
		under := grid.Position{x = cell.x, y = cell.y, layer = i8(layer)}
		if level.kind_has_floor(board_tile(under)) { base = max(base, cell_ground(under)+f32(level.LAYER_CLEARANCE)*step) }
	}
	return base
}

// THE LAYERS ROUND THE ROBOT (Fase 4 of docs/piano-profondita.md; the rules are game/layer_view.odin): where he
// stands this frame, for what fades over him, what is darker and who is hidden. Set once a frame with the board.
@(private)
Board_View :: struct {
	layered: bool,
	viewer:  game.Layer_Viewer,
	// Under a vault (in a cave): the outside is darker and the sky's light falls.
	vault:   bool,
}

@(private)
board_view: Board_View

@(private)
set_board_view :: proc(renderer: ^Renderer, room: ^game.Room) {
	board_view = {}
	if room == nil || room.player == nil || !board_heights.layered { return }
	// His point as the board shows him (sliding between cells), his cell as the rules have it.
	p := renderer.tactical.snapshot.player.position if renderer != nil && renderer.tactical.snapshot != nil else view.Vec2{f32(room.player.position.x), f32(room.player.position.y)}
	m := board_layer_map()
	viewer := game.Layer_Viewer{point = {p.x+0.5, p.y+0.5}, cell = room.player.position}
	board_view = {layered = true, viewer = viewer, vault = game.layer_viewer_in_vault(&m, viewer)}
}

// How whole `cell` is drawn (1 whole: always, on a board without layers).
@(private)
cell_cover_opacity :: proc(cell: grid.Position) -> f32 {
	if !board_view.layered { return 1 }
	m := board_layer_map()
	return game.layer_cover_opacity(&m, board_view.viewer, cell)
}

// How much darker `cell` is drawn (0: not at all, on a board without layers).
@(private)
cell_dim :: proc(cell: grid.Position) -> f32 {
	if !board_view.layered { return 0 }
	m := board_layer_map()
	return game.layer_cell_dim(&m, board_view.viewer, cell)
}

// The cell `entity` stands on this frame, on its layer (found false off a map with layers).
@(private)
board_actor_cell :: proc(entity: game.Entity_Ref) -> (cell: grid.Position, found: bool) {
	for actor in board_actors { if actor.entity == entity { return actor.cell, true } }
	return
}

// The floor under a point that `entity` stands on: on a map with layers, of the layers that have a floor
// under the point, the one nearest in height to the cell the actor stands on (so a figure crossing a mouth or
// a bridge's head goes from one floor to the other without a drop); else the ground's (point_ground).
@(private)
entity_point_ground :: proc(entity: game.Entity_Ref, at: view.Vec2) -> f32 {
	if !board_heights.layered || entity == {} { return point_ground(at) }
	// On a lift's platform, on its way (lift_view.odin).
	for rider in board_lift_riders { if rider.entity == entity { return rider.ground } }
	standing, found := board_actor_cell(entity)
	if !found { return point_ground(at) }
	x, y := int(math.floor(at.x+0.5)), int(math.floor(at.y+0.5))
	// Where no column round has a floor off the ground, the ground's is the only one.
	if standing.layer == grid.GROUND_LAYER && !board_column_layered(standing) && !board_column_layered({x = x, y = y}) { return point_ground(at) }
	target := cell_ground(standing)
	best, best_distance := point_ground(at), max(f32)
	for layer in grid.LOWEST_LAYER..=grid.HIGHEST_LAYER {
		m := board_surface_map(i8(layer))
		if !level.surface_ground(&m, x, y) { continue }
		height := level.surface_height_at(&m, at.x+0.5, at.y+0.5)*game.HEIGHT_STEP_DRAWN
		if distance := abs(height-target); distance < best_distance { best, best_distance = height, distance }
	}
	return best
}

// The cell under the ray the pointer casts: the first one whose floor is above
// the ray as it goes down, so a plateau's top and a cliff's face are what the
// pointer picks, not the flat ground behind them. `ok` is false off the board.
@(private)
pick_ground_cell :: proc(origin, direction: [3]f32) -> (cell: grid.Position, ok: bool) {
	if direction.y > -0.0001 { return }
	if !board_has_heights() && !board_heights.layered {
		t := -origin.y/direction.y
		if t <= 0 { return }
		return {x = int(math.floor(origin.x+direction.x*t)), y = int(math.floor(origin.z+direction.z*t))}, true
	}
	top := f32(board_heights.top)*game.HEIGHT_STEP_DRAWN+0.1
	// Where another layer has a floor, the column's solids (level.column_of): the ray stops in the first one it
	// enters, on the floor that stands on it (a bridge's deck, a cave's floor through its mouth, the hill's top).
	layers: level.Layer_Map
	if board_heights.layered { layers = board_layer_map() }
	// From the height of the tallest cell down to the plane, in small steps.
	start := (top-origin.y)/direction.y
	end := -origin.y/direction.y
	if end <= 0 { return }
	start = max(start, 0)
	STEP :: f32(0.04)
	m := board_surface_map()
	for t := start; t <= end+STEP; t += STEP {
		x, y, z := origin.x+direction.x*t, origin.y+direction.y*t, origin.z+direction.z*t
		probe := grid.Position{x = int(math.floor(x)), y = int(math.floor(z))}
		if probe.x < 0 || probe.y < 0 || probe.x >= board_heights.width || probe.y >= board_heights.height { continue }
		if board_column_layered(probe) {
			// A piece faded enough over the robot (a bridge's deck, a hill's rock) lets the ray through (Fase 4).
			owner, inside := game.layer_solid_owner(&layers, probe.x, probe.y, (y-0.02)/game.HEIGHT_STEP_DRAWN)
			if inside && cell_cover_opacity(owner) > game.LAYER_PICK_THROUGH { return owner, true }
			continue
		}
		if y <= level.surface_height_at(&m, x, z)*game.HEIGHT_STEP_DRAWN+0.02 { return probe, true }
	}
	// Nothing above the plane was hit: the ray meets the plane itself.
	t := end
	return {x = int(math.floor(origin.x+direction.x*t)), y = int(math.floor(origin.z+direction.z*t))}, true
}

// Whether the ground between the camera and an actor standing at `at` (its cell's corner) hides the actor: the
// line from the camera to the actor's chest passes under the top of a cell on the way. A hill or a mountain in front
// of an actor hides it; an actor on the same ground, or on a slope that opens to the camera, is seen. With layers
// (`entity` says where it stands) the line goes through them: the rock over a cave hides what is in it, but where it
// fades over the robot (game.layer_figure_hidden).
@(private)
terrain_hides_actor :: proc(renderer: ^Renderer, at: view.Vec2, entity := game.Entity_Ref{}) -> bool {
	if !board_has_heights() { return false }
	standing, found := board_actor_cell(entity)
	if !found { standing = {x = int(math.floor(at.x+0.5)), y = int(math.floor(at.y+0.5))} }
	// The rule of the layers where they matter: the robot or the actor off the ground; else the ground's, which is cheaper.
	if board_view.layered && (standing.layer != grid.GROUND_LAYER || board_view.viewer.cell.layer != grid.GROUND_LAYER) {
		m := board_layer_map()
		eye := renderer.tactical.camera.position
		target := [3]f32{at.x+0.5, entity_point_ground(entity, at)+0.5, at.y+0.5}
		return game.layer_figure_hidden(&m, board_view.viewer, {eye.x, eye.y, eye.z}, target, standing)
	}
	target := rl.Vector3{at.x+0.5, point_ground(at)+0.5, at.y+0.5}
	eye := renderer.tactical.camera.position
	delta := target-eye
	length := math.sqrt(delta.x*delta.x+delta.z*delta.z)
	steps := int(length/0.35)
	target_cell := grid.Position{x = int(math.floor(target.x)), y = int(math.floor(target.z))}
	for i in 1..<steps {
		t := f32(i)/f32(steps)
		cell := grid.Position{x = int(math.floor(eye.x+delta.x*t)), y = int(math.floor(eye.z+delta.z*t))}
		if cell == target_cell { continue }
		if cell_ground(cell) > eye.y+delta.y*t+0.02 { return true }
	}
	return false
}
