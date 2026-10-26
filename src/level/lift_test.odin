package level

import "core:testing"
import grid "../engine/grid"

// A hill 14 steps high (x 3..7) over a hall on layer -1 at 0 (x 4..6, y 4), shut in the rock: no way down to it but a
// shaft at (5, 4).
@(private = "file")
shaft_level :: proc(t: ^testing.T) -> Level {
	data, ok := create(10, 8, {kind = .Floor})
	testing.expect(t, ok)
	for y in 0..<8 { for x in 3..=7 { testing.expect(t, set_height(&data, {x = x, y = y}, 14)) } }
	for x in 4..=6 { testing.expect(t, set_tile(&data, {x = x, y = 4, layer = -1}, {kind = .Floor})) }
	return data
}

// A lift joins two landings of one column on two layers, never two columns nor a cell to itself.
@(test)
test_a_lift_joins_two_layers_of_one_column :: proc(t: ^testing.T) {
	data := shaft_level(t)
	defer destroy(&data)
	testing.expect(t, !add_lift(&data, {x = 5, y = 4}, {x = 5, y = 4}))
	testing.expect(t, !add_lift(&data, {x = 5, y = 4}, {x = 6, y = 4, layer = -1}))
	testing.expect(t, add_lift(&data, {x = 5, y = 4}, {x = 5, y = 4, layer = -1}))
	index, end, found := lift_at(&data, {x = 5, y = 4, layer = -1})
	testing.expect(t, found && index == 0 && end == 1)
	_, _, found = lift_at(&data, {x = 4, y = 4, layer = -1})
	testing.expect(t, !found)
	error, _ := check_layers(&data)
	testing.expect_value(t, error, Layer_Error.None)
}

// check_layers refuses a lift to a cell without a floor and two lifts with a landing in common; a lift up the hill's
// west cliff, to a landing on the layer over its foot, is whole.
@(test)
test_check_layers_refuses_a_broken_lift :: proc(t: ^testing.T) {
	data := shaft_level(t)
	defer destroy(&data)
	testing.expect(t, add_lift(&data, {x = 5, y = 3}, {x = 5, y = 3, layer = -1}))
	error, bad := check_layers(&data)
	testing.expect(t, error == .Lift_Invalid && bad == grid.Position{x = 5, y = 3, layer = -1})
	clear(&data.lifts)
	top := grid.Position{x = 2, y = 1, layer = 1}
	testing.expect(t, set_tile(&data, top, {kind = .Floor}))
	testing.expect(t, set_height(&data, top, 14))
	testing.expect(t, add_lift(&data, {x = 2, y = 1}, top))
	error, _ = check_layers(&data)
	testing.expect_value(t, error, Layer_Error.None)
	clear(&data.lifts)
	testing.expect(t, add_lift(&data, {x = 5, y = 4}, {x = 5, y = 4, layer = -1}))
	testing.expect(t, add_lift(&data, {x = 5, y = 4}, {x = 5, y = 4, layer = -1}))
	error, _ = check_layers(&data)
	testing.expect_value(t, error, Layer_Error.Lift_Invalid)
}

// From the hill's top a walker gets to the hall only down the shaft, and back up it.
@(test)
test_a_walker_reaches_the_hall_down_the_shaft :: proc(t: ^testing.T) {
	data := shaft_level(t)
	defer destroy(&data)
	top, hall := grid.Position{x = 4, y = 0}, grid.Position{x = 6, y = 4, layer = -1}
	seen := layer_reach(&data, top, context.temp_allocator)
	testing.expect(t, !seen[layer_reach_index(&data, hall)], "no way down without the shaft")
	testing.expect(t, add_lift(&data, {x = 5, y = 4}, {x = 5, y = 4, layer = -1}))
	seen = layer_reach(&data, top, context.temp_allocator)
	testing.expect(t, seen[layer_reach_index(&data, hall)])
	back := layer_reach(&data, hall, context.temp_allocator)
	testing.expect(t, back[layer_reach_index(&data, top)])
}

// A gate shuts a passage until it is opened: its cell is bars (a Fence) that stop a walker, then a floor.
@(test)
test_a_gate_shuts_a_passage_until_it_is_opened :: proc(t: ^testing.T) {
	data, ok := create(9, 3, {kind = .Floor})
	testing.expect(t, ok)
	defer destroy(&data)
	// A corridor along y = 1, walled above and below, with a gate at (4, 1) opened from the west.
	for x in 0..<9 { for y in ([2]int{0, 2}) { testing.expect(t, set_tile(&data, {x = x, y = y}, {kind = .Wall})) } }
	testing.expect(t, !add_gate(&data, {x = 4, y = 1}, {x = 6, y = 1}), "a lever not beside the gate")
	testing.expect(t, !add_gate(&data, {x = 4, y = 1}, {x = 4, y = 0}), "a lever in the wall")
	testing.expect(t, add_gate(&data, {x = 4, y = 1}, {x = 3, y = 1}))
	index, open, found := gate_at(&data, {x = 4, y = 1})
	testing.expect(t, found && index == 0 && !open)
	seen := layer_reach(&data, {x = 0, y = 1}, context.temp_allocator)
	testing.expect(t, !seen[layer_reach_index(&data, {x = 8, y = 1})], "the gate shut stops the walk")
	testing.expect(t, open_gate(&data, 0))
	testing.expect(t, !open_gate(&data, 0), "it is open already")
	_, open, _ = gate_at(&data, {x = 4, y = 1})
	testing.expect(t, open)
	seen = layer_reach(&data, {x = 0, y = 1}, context.temp_allocator)
	testing.expect(t, seen[layer_reach_index(&data, {x = 8, y = 1})])
}
