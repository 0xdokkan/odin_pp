package level

import "core:testing"

@(private = "file")
near :: proc(a, b: f32) -> bool { return abs(a-b) < 0.0001 }

// A flat map has a flat surface: every corner of every cell at 0, so nothing is drawn over the plane.
@(test)
test_a_flat_map_has_a_flat_surface :: proc(t: ^testing.T) {
	data, _ := create(5, 4, Tile{kind = .Floor})
	defer destroy(&data)
	m := surface_map(&data)
	for y in 0..<4 {
		for x in 0..<5 {
			cell, ok := surface_cell(&m, x, y)
			testing.expect(t, ok && surface_flat(cell) && cell.center == 0)
		}
	}
	testing.expect_value(t, surface_height_at(&m, 2.3, 1.7), f32(0))
}

// A stair of steps along x becomes a ramp: two cells side by side share the corners of their edge, so the
// surface has no crack, and every cell's middle stays at its own height.
@(test)
test_a_stair_becomes_a_ramp_without_cracks :: proc(t: ^testing.T) {
	data, _ := create(6, 4, Tile{kind = .Floor})
	defer destroy(&data)
	for y in 0..<4 { for x in 0..<6 { set_height(&data, {x, y}, i32(x)) } }
	m := surface_map(&data)
	for x in 0..<5 {
		a, _ := surface_cell(&m, x, 1)
		b, _ := surface_cell(&m, x+1, 1)
		// The east edge of a is the west edge of b.
		testing.expect(t, near(a.corners[1], b.corners[0]) && near(a.corners[2], b.corners[3]))
		// Halfway up the step.
		testing.expect(t, near(a.corners[1], f32(x)+0.5))
		testing.expect(t, near(surface_height_at(&m, f32(x)+0.5, 1.5), f32(x)))
	}
	// Across the shared edge the height does not jump, and it grows steadily up the ramp.
	for x in 1..<6 {
		left := surface_height_at(&m, f32(x)-0.001, 1.5)
		right := surface_height_at(&m, f32(x)+0.001, 1.5)
		testing.expect(t, abs(left-right) < 0.01)
	}
	last := f32(-1)
	for i in 0..=50 {
		h := surface_height_at(&m, 0.5+f32(i)*0.1, 2.5)
		testing.expect(t, h >= last-0.0001)
		last = h
	}
}

// A cell four steps over its neighbours is a cliff all round: its top stays flat to the edge, and the ground
// round it stays flat too. The wall in between is drawn by the renderer.
@(test)
test_a_cliff_keeps_its_edge :: proc(t: ^testing.T) {
	data, _ := create(5, 5, Tile{kind = .Floor})
	defer destroy(&data)
	set_height(&data, {2, 2}, 4)
	m := surface_map(&data)
	top, _ := surface_cell(&m, 2, 2)
	testing.expect(t, surface_flat(top) && top.center == 4)
	beside, _ := surface_cell(&m, 1, 2)
	testing.expect(t, surface_flat(beside) && beside.center == 0)
	testing.expect(t, !surface_linked(&m, {1, 2}, {2, 2}))
	testing.expect(t, near(surface_height_at(&m, 2.01, 2.5), 4))
	testing.expect(t, near(surface_height_at(&m, 1.99, 2.5), 0))
	testing.expect(t, near(surface_top(top), 4))
}

// Where the ground goes round the end of a cliff, the cells meet at the same corner: the cliff fades out there.
// Here the cells 5 and 2 are a cliff apart, but 5-4-3-2 goes round through the other two cells of the corner.
@(test)
test_a_cliff_fades_where_the_ground_goes_round_it :: proc(t: ^testing.T) {
	data, _ := create(2, 2, Tile{kind = .Floor})
	defer destroy(&data)
	apply_height_rows(&data, {"52", "43"})
	m := surface_map(&data)
	high, _ := surface_cell(&m, 0, 0)
	low, _ := surface_cell(&m, 1, 0)
	// The south-east corner of the high cell is the south-west corner of the low one: the mean of all four.
	testing.expect(t, near(high.corners[2], 3.5) && near(low.corners[3], 3.5))
	// Their other shared corner, on the map's edge, belongs to the two cells alone: the cliff is there.
	testing.expect(t, near(high.corners[1], 5) && near(low.corners[0], 2))
}

// A Void cell has no surface and pulls no corner: a raised cell beside the void keeps its corners.
@(test)
test_the_void_has_no_surface :: proc(t: ^testing.T) {
	data, _ := create(4, 3, Tile{kind = .Floor})
	defer destroy(&data)
	set_tile(&data, {2, 1}, {kind = .Void})
	set_height(&data, {1, 1}, 1)
	m := surface_map(&data)
	_, ok := surface_cell(&m, 2, 1)
	testing.expect(t, !ok)
	testing.expect_value(t, surface_height_at(&m, 2.5, 1.5), f32(0))
	cell, _ := surface_cell(&m, 1, 1)
	// Each east corner takes the cell and the two cells at 0 on its side of the void: a third. With ground in the
	// void cell too it would be a quarter.
	testing.expect(t, near(cell.corners[1], 1.0/3) && near(cell.corners[2], 1.0/3))
	testing.expect(t, near(cell.center, 1))
}

// Whatever the heights, a cell's middle is at its own height: the rules' height and the drawn one agree there.
@(test)
test_every_middle_is_at_its_own_height :: proc(t: ^testing.T) {
	data, _ := create(7, 7, Tile{kind = .Floor})
	defer destroy(&data)
	for y in 0..<7 { for x in 0..<7 { set_height(&data, {x, y}, i32((x*7+y*13)%5)) } }
	m := surface_map(&data)
	for y in 0..<7 {
		for x in 0..<7 {
			testing.expect(t, near(surface_height_at(&m, f32(x)+0.5, f32(y)+0.5), f32(height_at(&data, {x, y}))))
		}
	}
}
