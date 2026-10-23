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
// each), and whatever stands or is drawn on it with it.
//
// Most of what is drawn on the ground does not take the renderer (a marker, an
// intent cell), so the heights the board shows are kept here, set once a frame by
// update_tactical_view and draw_tactical_world: one renderer draws at a time. It is
// a copy of the level's table, refreshed when the level's geometry changes, and
// never a pointer to the level: a level destroyed under it cannot be read.
@(private)
Board_Heights :: struct {
	cells: [dynamic]u8,
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
		b.id, b.revision, b.width, b.height = 0, 0, 0, 0
		return
	}
	if b.id == data.geometry_id && b.revision == data.geometry_revision && len(b.cells) == len(data.heights) { return }
	// Kept off the test runner's per-test allocator: it outlives any one test.
	if b.cells.allocator.procedure == nil { b.cells = make([dynamic]u8, runtime.heap_allocator()) }
	clear(&b.cells)
	append(&b.cells, ..data.heights[:])
	b.width, b.height = data.tiles.width, data.tiles.height
	b.id, b.revision = data.geometry_id, data.geometry_revision
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
// own coordinates plus a half): the four cells round it blended, so a figure
// sliding from a cell to the next climbs the step smoothly instead of jumping.
@(private)
point_ground :: proc(at: view.Vec2) -> f32 {
	if !board_has_heights() { return 0 }
	x0, y0 := int(math.floor(at.x)), int(math.floor(at.y))
	tx, ty := at.x-f32(x0), at.y-f32(y0)
	a, b := cell_ground({x0, y0}), cell_ground({x0+1, y0})
	c, d := cell_ground({x0, y0+1}), cell_ground({x0+1, y0+1})
	return (a*(1-tx)+b*tx)*(1-ty)+(c*(1-tx)+d*tx)*ty
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
		return {int(math.floor(origin.x+direction.x*t)), int(math.floor(origin.z+direction.z*t))}, true
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
	for t := start; t <= end+STEP; t += STEP {
		x, y, z := origin.x+direction.x*t, origin.y+direction.y*t, origin.z+direction.z*t
		probe := grid.Position{int(math.floor(x)), int(math.floor(z))}
		if probe.x < 0 || probe.y < 0 || probe.x >= board_heights.width || probe.y >= board_heights.height { continue }
		if y <= cell_ground(probe)+0.02 { return probe, true }
	}
	// Nothing above the plane was hit: the ray meets the plane itself.
	t := end
	return {int(math.floor(origin.x+direction.x*t)), int(math.floor(origin.z+direction.z*t))}, true
}

// The steps of a cliff or a stair drawn on the sides of a raised cell that face
// a lower one: a thin edge line at every step of the drop, so a wall of ten
// steps reads as ten and a stair as a stair.
@(private)
draw_height_steps :: proc(renderer: ^Renderer, cell: grid.Position, p: [3]f32, rise: f32) {
	sides := [4]grid.Position{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}
	for side in sides {
		next := grid.Position{cell.x+side.x, cell.y+side.y}
		if next.x < 0 || next.y < 0 || next.x >= board_heights.width || next.y >= board_heights.height { continue }
		drop := rise-cell_ground(next)
		if drop <= 0.001 { continue }
		count := int(drop/game.HEIGHT_STEP_DRAWN+0.5)
		normal := [3]f32{f32(side.x), 0, f32(side.y)}
		across := [3]f32{0.97 if side.x == 0 else 0.012, 0.012, 0.97 if side.y == 0 else 0.012}
		for step in 1..=count {
			y := -f32(step)*game.HEIGHT_STEP_DRAWN
			// The top edge a little darker than the lines below it.
			shade := u8(95-min(step, 9)*4)
			draw_height_edge({p.x+normal.x*0.496, p.y+y, p.z+normal.z*0.496}, across, {shade-20, shade, shade+30, 255})
		}
	}
}

@(private = "file")
draw_height_edge :: proc(at, size: [3]f32, color: rl.Color) {
	rl.DrawCubeV(at, size, color)
}
