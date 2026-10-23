package render

import "core:testing"
import grid "../engine/grid"
import level "../level"

@(test)
test_the_ground_under_a_point_blends_the_cells_round_it :: proc(t: ^testing.T) {
	data, _ := level.create(6, 6, level.Tile{kind = .Floor})
	defer level.destroy(&data)
	defer set_board_level(nil)
	set_board_level(&data)
	// A flat board is at 0 everywhere.
	testing.expect_value(t, point_ground({2.5, 3.2}), f32(0))
	level.set_height(&data, {2, 2}, 4)
	// The view takes the table again when the geometry has changed.
	set_board_level(&data)
	step := f32(0.12)
	// On the cell's own coordinates: exactly its height; halfway to a flat cell: half.
	testing.expect(t, abs(point_ground({2, 2})-4*step) < 0.0001)
	testing.expect(t, abs(point_ground({1.5, 2})-2*step) < 0.0001)
	testing.expect(t, abs(point_ground({2, 2.5})-2*step) < 0.0001)
	testing.expect(t, abs(point_ground({1.5, 1.5})-step) < 0.0001)
	// Off the raised cell's four neighbours it is flat again.
	testing.expect_value(t, point_ground({4, 4}), f32(0))
	testing.expect(t, abs(cell_ground({2, 2})-4*step) < 0.0001)
	testing.expect_value(t, cell_ground({0, 0}), f32(0))
}

@(test)
test_the_pointer_picks_the_cell_whose_floor_it_reaches_first :: proc(t: ^testing.T) {
	data, _ := level.create(10, 10, level.Tile{kind = .Floor})
	defer level.destroy(&data)
	defer set_board_level(nil)
	set_board_level(&data)
	// A steep ray going north (towards smaller z) over cell (4,4).
	origin := [3]f32{4.5, 3, 9.5}
	direction := [3]f32{0, -1.5, -3}
	// On a flat board the ray reaches the plane at z=3.5: the cell (4,3).
	cell, ok := pick_ground_cell(origin, direction)
	testing.expect(t, ok)
	testing.expect_value(t, cell, grid.Position{4, 3})
	// With a plateau of six steps (0.72) at (4,4) the ray meets its top at z=4.9
	// first: the plateau's cell is the one under the pointer, not the ground behind it.
	level.set_height(&data, {4, 4}, 6)
	set_board_level(&data)
	cell, ok = pick_ground_cell(origin, direction)
	testing.expect(t, ok)
	testing.expect_value(t, cell, grid.Position{4, 4})
	// A ray going up, or flat, picks nothing.
	_, ok = pick_ground_cell(origin, {0, 1, -1})
	testing.expect(t, !ok)
	_, ok = pick_ground_cell(origin, {0, 0, -1})
	testing.expect(t, !ok)
	// A ray straight down over a cell picks it, raised or not.
	cell, ok = pick_ground_cell({7.5, 5, 7.5}, {0, -1, 0})
	testing.expect(t, ok)
	testing.expect_value(t, cell, grid.Position{7, 7})
	cell, ok = pick_ground_cell({4.5, 5, 4.5}, {0, -1, 0})
	testing.expect(t, ok)
	testing.expect_value(t, cell, grid.Position{4, 4})
}
