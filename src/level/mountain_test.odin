package level

import "core:math"
import "core:testing"
import grid "../engine/grid"

// The shortest walk from the edge of the mountain's square to every cell inside it, a step of one
// height at a time (-1: a cell no walk reaches).
@(private = "file")
mountain_walk :: proc(diagonals: bool) -> (distances: []int, side: int) {
	side = 2*MOUNTAIN_HALF+3
	half := side/2
	distances = make([]int, side*side, context.temp_allocator)
	for i in 0..<side*side { distances[i] = -1 }
	queue := make([dynamic]grid.Position, context.temp_allocator)
	for y in -half..=half {
		for x in -half..=half {
			if abs(x) == half || abs(y) == half {
				append(&queue, grid.Position{x = x, y = y})
				distances[(y+half)*side+x+half] = 0
			}
		}
	}
	for head := 0; head < len(queue); head += 1 {
		cell := queue[head]
		for oy in -1..=1 {
			for ox in -1..=1 {
				if (ox == 0 && oy == 0) || (!diagonals && ox != 0 && oy != 0) { continue }
				next := grid.offset(cell, ox, oy)
				if abs(next.x) > half || abs(next.y) > half { continue }
				if abs(mountain_height(next)-mountain_height(cell)) > 1 { continue }
				at := (next.y+half)*side+next.x+half
				if distances[at] >= 0 { continue }
				distances[at] = distances[(cell.y+half)*side+cell.x+half]+1
				append(&queue, next)
			}
		}
	}
	return
}

@(test)
test_the_mountain_stands_in_its_square_and_has_a_flat_summit :: proc(t: ^testing.T) {
	// The summit's height is the whole path's length.
	testing.expect_value(t, int(mountain_path_length(MOUNTAIN_LAPS)), MOUNTAIN_TOP)
	tallest, summit_cells := 0, 0
	for y in -MOUNTAIN_HALF-2..=MOUNTAIN_HALF+2 {
		for x in -MOUNTAIN_HALF-2..=MOUNTAIN_HALF+2 {
			h := mountain_height({x = x, y = y})
			tallest = max(tallest, h)
			if h == MOUNTAIN_TOP { summit_cells += 1 }
			if abs(x) > MOUNTAIN_HALF || abs(y) > MOUNTAIN_HALF { testing.expect_value(t, h, 0) }
		}
	}
	testing.expect_value(t, tallest, MOUNTAIN_TOP)
	testing.expectf(t, summit_cells >= 9, "the summit has %d cells", summit_cells)
	summit := mountain_summit()
	testing.expect_value(t, mountain_height(summit), MOUNTAIN_TOP)
	testing.expect_value(t, mountain_height({x = MOUNTAIN_HALF+3, y = 0}), 0)
}

// The way up is the path: a walk climbing a step at a time reaches the summit, and it is a long one, three
// laps and not a short cut up the side.
@(test)
test_the_summit_is_reached_by_a_long_winding_walk_and_no_short_cut :: proc(t: ^testing.T) {
	summit := mountain_summit()
	for diagonals in ([2]bool{false, true}) {
		distances, side := mountain_walk(diagonals)
		half := side/2
		walk := distances[(summit.y+half)*side+summit.x+half]
		testing.expectf(t, walk >= 0, "the summit cannot be walked to (diagonals %v)", diagonals)
		// Three laps of a circle between 2 and 8 cells in radius: ~100 cells; straight up from the
		// edge it would be 10.
		minimum := 80 if diagonals else 100
		testing.expectf(t, walk >= minimum, "the walk to the summit is only %d cells (diagonals %v)", walk, diagonals)
	}
}

// Between one lap and the next there is a cliff, and the path is two cells wide: most cells have a
// neighbour two steps or more away only across a lap, never within one.
@(test)
test_the_laps_are_divided_by_cliffs_and_the_ground_rises_along_the_path :: proc(t: ^testing.T) {
	cliffs, steps := 0, 0
	for y in -MOUNTAIN_HALF..=MOUNTAIN_HALF {
		for x in -MOUNTAIN_HALF..=MOUNTAIN_HALF {
			here := mountain_height({x = x, y = y})
			for step in ([2][2]int{{1, 0}, {0, 1}}) {
				there := mountain_height({x = x+step.x, y = y+step.y})
				if abs(here-there) >= 2 { cliffs += 1 }
				if abs(here-there) == 1 { steps += 1 }
			}
		}
	}
	testing.expectf(t, cliffs >= 60, "only %d cliff edges", cliffs)
	testing.expectf(t, steps >= 30, "only %d single steps", steps)
}

// Most of the mountain can be walked to, and the reachable part includes the halfway cell (where the
// patrol waits).
@(test)
test_most_of_the_mountain_is_walkable_and_the_halfway_cell_is_halfway_up :: proc(t: ^testing.T) {
	distances, side := mountain_walk(false)
	half := side/2
	inside, reached := 0, 0
	for y in -MOUNTAIN_HALF..=MOUNTAIN_HALF {
		for x in -MOUNTAIN_HALF..=MOUNTAIN_HALF {
			if _, in_mountain := mountain_progress({x = x, y = y}); !in_mountain || mountain_height({x = x, y = y}) == 0 { continue }
			inside += 1
			if distances[(y+half)*side+x+half] >= 0 { reached += 1 }
		}
	}
	testing.expectf(t, reached*100 >= inside*85, "only %d of %d raised cells can be walked to", reached, inside)
	middle := mountain_midway()
	height := mountain_height(middle)
	testing.expectf(t, height >= MOUNTAIN_TOP*4/10 && height <= MOUNTAIN_TOP*75/100, "the halfway cell %v is %d steps high", middle, height)
	testing.expect(t, distances[(middle.y+half)*side+middle.x+half] >= 0, "the halfway cell can be walked to")
}

// The ice lies on the path in two stretches and never on the ground or the summit.
@(test)
test_the_ice_is_in_two_stretches_on_the_path :: proc(t: ^testing.T) {
	icy := 0
	for y in -MOUNTAIN_HALF-2..=MOUNTAIN_HALF+2 {
		for x in -MOUNTAIN_HALF-2..=MOUNTAIN_HALF+2 {
			if !mountain_icy({x = x, y = y}) { continue }
			icy += 1
			h := mountain_height({x = x, y = y})
			testing.expectf(t, h > 0 && h < MOUNTAIN_TOP, "ice at %v, %d steps high", grid.Position{x = x, y = y}, h)
		}
	}
	testing.expectf(t, icy >= 12 && icy <= 80, "%d icy cells", icy)
}

// Walking up the path, the ground rises a step at a time: the cells of the path's middle are never more than
// two steps apart from one tenth of a lap to the next, and across its width (the same angle) the height is
// nearly the same.
@(test)
test_the_path_rises_one_step_at_a_time_and_is_level_across :: proc(t: ^testing.T) {
	previous := 0
	for hundredth in 8..<MOUNTAIN_LAPS*100 {
		laps := f32(hundredth)/100
		cell := mountain_path_cell(laps)
		height := mountain_height(cell)
		testing.expectf(t, height > 0, "the path at %.2f laps, %v, is on the ground", laps, cell)
		if hundredth > 8 { testing.expectf(t, abs(height-previous) <= 3, "a jump of %d at %.2f laps", height-previous, laps) }
		previous = height
	}
	// Level across: a cell half a cell further out along the radius and one half a cell further in.
	level_across, samples := 0, 0
	for hundredth in 20..<MOUNTAIN_LAPS*100-20 {
		laps := f32(hundredth)/100
		angle := 2*math.PI*(laps-math.floor(laps))
		radius := MOUNTAIN_START-laps*f32(MOUNTAIN_PATH)
		samples += 1
		if abs(mountain_height(ring_cell(radius+0.5, angle))-mountain_height(ring_cell(radius-0.5, angle))) <= 4 { level_across += 1 }
	}
	testing.expectf(t, level_across*100 >= samples*90, "only %d of %d samples are level across", level_across, samples)
}

@(private = "file")
ring_cell :: proc(radius, angle: f32) -> grid.Position {
	return {x = int(math.round(radius*math.cos(angle))), y = int(math.round(radius*math.sin(angle)))}
}
