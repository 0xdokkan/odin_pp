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
	width, height: int,
	id, revision: u64,
}

@(private)
board_heights: Board_Heights

// The level whose heights the next drawing uses (nil: flat).
@(private)
set_board_level :: proc(data: ^level.Level) {
	b := &board_heights
	if data == nil || !level.has_heights(data) {
		if len(b.cells) > 0 { clear(&b.cells) }
		if len(b.tiles) > 0 { clear(&b.tiles) }
		b.id, b.revision, b.width, b.height = 0, 0, 0, 0
		return
	}
	if b.id == data.geometry_id && b.revision == data.geometry_revision && len(b.cells) == len(data.heights) { return }
	// Kept off the test runner's per-test allocator: it outlives any one test.
	if b.cells.allocator.procedure == nil { b.cells = make([dynamic]u8, runtime.heap_allocator()) }
	if b.tiles.allocator.procedure == nil { b.tiles = make([dynamic]level.Tile, runtime.heap_allocator()) }
	clear(&b.cells)
	append(&b.cells, ..data.heights[:])
	clear(&b.tiles)
	append(&b.tiles, ..data.tiles.cells[:])
	b.width, b.height = data.tiles.width, data.tiles.height
	b.id, b.revision = data.geometry_id, data.geometry_revision
}

// The board's tables as the surface reads them.
@(private)
board_surface_map :: proc() -> level.Surface_Map {
	b := &board_heights
	return {heights = b.cells[:], tiles = b.tiles[:], width = b.width, height = b.height}
}

// The sculpted surface of `cell`, in steps; `ok` is false off the board, on a Void cell or on a flat board.
@(private)
cell_surface :: proc(cell: grid.Position) -> (surface: level.Surface_Cell, ok: bool) {
	if !board_has_heights() { return }
	m := board_surface_map()
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

// How high `cell`'s floor stands over the board's plane.
@(private)
cell_ground :: proc(cell: grid.Position) -> f32 {
	b := &board_heights
	if len(b.cells) == 0 || cell.x < 0 || cell.y < 0 || cell.x >= b.width || cell.y >= b.height { return 0 }
	return f32(b.cells[cell.y*b.width+cell.x])*game.HEIGHT_STEP_DRAWN
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
// shadow laid flat there is never covered by a slope.
@(private)
rim_ground :: proc(at: view.Vec2, radius: f32) -> f32 {
	ground := point_ground(at)
	for offset in ([4]view.Vec2{{radius, 0}, {-radius, 0}, {0, radius}, {0, -radius}}) { ground = max(ground, point_ground(at+offset)) }
	return ground
}

// The cell under the ray the pointer casts: the first one whose floor is above
// the ray as it goes down, so a plateau's top and a cliff's face are what the
// pointer picks, not the flat ground behind them. `ok` is false off the board.
@(private)
pick_ground_cell :: proc(origin, direction: [3]f32) -> (cell: grid.Position, ok: bool) {
	if direction.y > -0.0001 { return }
	if !board_has_heights() {
		t := -origin.y/direction.y
		if t <= 0 { return }
		return {x = int(math.floor(origin.x+direction.x*t)), y = int(math.floor(origin.z+direction.z*t))}, true
	}
	top := f32(0)
	for height in board_heights.cells { top = max(top, f32(height)) }
	top = top*game.HEIGHT_STEP_DRAWN+0.1
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
		if y <= level.surface_height_at(&m, x, z)*game.HEIGHT_STEP_DRAWN+0.02 { return probe, true }
	}
	// Nothing above the plane was hit: the ray meets the plane itself.
	t := end
	return {x = int(math.floor(origin.x+direction.x*t)), y = int(math.floor(origin.z+direction.z*t))}, true
}

// Whether the ground between the camera and an actor standing at `at` (its cell's corner) hides the actor: the
// line from the camera to the actor's chest passes under the top of a cell on the way. A hill or a mountain in front
// of an actor hides it; an actor on the same ground, or on a slope that opens to the camera, is seen.
@(private)
terrain_hides_actor :: proc(renderer: ^Renderer, at: view.Vec2) -> bool {
	if !board_has_heights() { return false }
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
