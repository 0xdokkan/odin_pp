package grid

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
