package grid

import "core:encoding/json"
import "core:testing"

coordinate_value :: proc(position: Position) -> i32 {
	return cast(i32)(position.y*10 + position.x)
}

@(test)
test_create_uses_row_major_storage :: proc(t: ^testing.T) {
	g, ok := create(i32, 3, 2, -1)
	testing.expect(t, ok, "a positive grid size should be valid")
	defer destroy(&g)

	testing.expect_value(t, len(g.cells), 6)
	testing.expect(t, set(&g, {x = 2, y = 1}, 42))
	testing.expect_value(t, g.cells[5], 42)

	position, found := position_of(&g, 5)
	testing.expect(t, found)
	testing.expect_value(t, position, Position{x = 2, y = 1})
}

@(test)
test_bounds_are_checked :: proc(t: ^testing.T) {
	g, ok := create(i32, 2, 2, 0)
	testing.expect(t, ok)
	defer destroy(&g)

	testing.expect(t, contains(&g, {x = 0, y = 0}))
	testing.expect(t, contains(&g, {x = 1, y = 1}))
	testing.expect(t, !contains(&g, {x = -1, y = 0}))
	testing.expect(t, !contains(&g, {x = 2, y = 1}))

	_, found := get(&g, {x = 4, y = 4})
	testing.expect(t, !found)
	testing.expect(t, !set(&g, {x = 4, y = 4}, 10))
}

@(test)
test_generate_visits_every_coordinate :: proc(t: ^testing.T) {
	g, ok := create(i32, 3, 2, 0)
	testing.expect(t, ok)
	defer destroy(&g)

	generate(&g, coordinate_value)

	expected := [?]i32{0, 1, 2, 10, 11, 12}
	for value, index in g.cells {
		testing.expect_value(t, value, expected[index])
	}
}

@(test)
test_rejects_empty_dimensions :: proc(t: ^testing.T) {
	_, width_ok := create(i32, 0, 10, 0)
	_, height_ok := create(i32, 10, -1, 0)

	testing.expect(t, !width_ok)
	testing.expect(t, !height_ok)
}

// A Grid has one layer, the ground: a position on another layer is not in it, even with the x and y of one of its
// cells (docs/piano-profondita.md).
@(test)
test_a_grid_holds_the_ground_layer_only :: proc(t: ^testing.T) {
	g, ok := create(i32, 3, 3, 7)
	testing.expect(t, ok)
	defer destroy(&g)
	below := Position{x = 1, y = 1, layer = -1}
	testing.expect(t, !contains(&g, below))
	_, found := index_of(&g, below)
	testing.expect(t, !found)
	_, got := get(&g, below)
	testing.expect(t, !got)
	testing.expect(t, !set(&g, Position{x = 1, y = 1, layer = 1}, 9))
	testing.expect_value(t, g.cells[4], i32(7))
	testing.expect(t, contains(&g, {x = 1, y = 1}))
	_, inside := cell_index(below, 3, 3)
	testing.expect(t, !inside)
	index, ground := cell_index({x = 2, y = 1}, 3, 3)
	testing.expect(t, ground && index == 5)
}

// A neighbour keeps the layer of the cell it is next to.
@(test)
test_offset_keeps_the_layer :: proc(t: ^testing.T) {
	testing.expect_value(t, offset({x = 4, y = 5, layer = -2}, 1, -1), Position{x = 5, y = 4, layer = -2})
	testing.expect_value(t, offset({x = 4, y = 5}, -1, 0), Position{x = 3, y = 5})
}

// A position saved before the layers came has no "layer" key: it loads on the ground.
@(test)
test_a_position_saved_without_a_layer_loads_on_the_ground :: proc(t: ^testing.T) {
	p: Position
	testing.expect(t, json.unmarshal_string(`{"x":3,"y":4}`, &p) == nil)
	testing.expect_value(t, p, Position{x = 3, y = 4})
	data, err := json.marshal(Position{x = 1, y = 2, layer = -1}, allocator = context.temp_allocator)
	testing.expect(t, err == nil)
	back: Position
	testing.expect(t, json.unmarshal(data, &back) == nil)
	testing.expect_value(t, back, Position{x = 1, y = 2, layer = -1})
}
