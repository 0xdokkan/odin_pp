package level

import "core:testing"
import grid "../engine/grid"

// A bridge over a road: the road runs along y = 2 on the ground (flat, 0), the bridge's deck (layer +1,
// 12 steps) crosses it along x = 3, from y 0 to 4. A 7x5 map of floor.
@(private = "file")
bridge_map :: proc() -> Level {
	data, _ := create(7, 5, Tile{kind = .Floor})
	for y in 0..<5 {
		p := grid.Position{x = 3, y = y, layer = 1}
		set_tile(&data, p, {kind = .Floor})
		set_height(&data, p, LAYER_SPACING)
	}
	return data
}

// A hill of 14 steps over x 2..4 with a tunnel through it on layer -1, at 0, along y = 2: the mouths open
// on the flat ground at (1,2) and (5,2). A 7x5 map of floor.
@(private = "file")
hill_map :: proc() -> Level {
	data, _ := create(7, 5, Tile{kind = .Floor})
	for y in 0..<5 { for x in 2..=4 { set_height(&data, {x = x, y = y}, 14) } }
	for x in 2..=4 { set_tile(&data, {x = x, y = 2, layer = -1}, {kind = .Floor}) }
	return data
}

@(private = "file")
nothing_opaque :: proc(data: rawptr, p: grid.Position) -> bool { return false }

// A layer's cells are kept apart from the ground's: a plane is made by its first cell, an empty cell of it is
// Void, and a change on it changes the geometry like the ground's.
@(test)
test_a_layer_keeps_its_own_cells_and_heights :: proc(t: ^testing.T) {
	data, _ := create(4, 3, Tile{kind = .Floor})
	defer destroy(&data)
	testing.expect(t, !has_layers(&data))
	above := grid.Position{x = 1, y = 1, layer = 1}
	tile, found := tile_at(&data, above)
	testing.expect(t, found && tile.kind == .Void)
	revision := data.geometry_revision
	testing.expect(t, set_tile(&data, above, {kind = .Floor}))
	testing.expect(t, set_height(&data, above, 12))
	testing.expect(t, has_layers(&data) && data.geometry_revision > revision)
	tile, _ = tile_at(&data, above)
	testing.expect_value(t, tile.kind, Tile_Kind.Floor)
	testing.expect_value(t, height_at(&data, above), i32(12))
	// The ground under it is untouched, and the other cells of the layer are none.
	testing.expect_value(t, height_at(&data, {x = 1, y = 1}), i32(0))
	tile, _ = tile_at(&data, {x = 2, y = 1, layer = 1})
	testing.expect_value(t, tile.kind, Tile_Kind.Void)
	// Off the layers or off the map there is no cell.
	_, found = tile_at(&data, {x = 1, y = 1, layer = 2})
	testing.expect(t, !found)
	testing.expect(t, !set_tile(&data, {x = 4, y = 1, layer = -1}, {kind = .Floor}))
	testing.expect(t, layer_contains(&data, {x = 3, y = 2, layer = -2}) && !layer_contains(&data, {x = 3, y = 3, layer = -2}))
}

// Two floors of a column closer than the clearance and the thickness are refused, and so is a higher layer's
// floor under a lower one's; a bridge LAYER_SPACING over the road is accepted.
@(test)
test_a_column_with_floors_too_close_is_refused :: proc(t: ^testing.T) {
	data := bridge_map()
	defer destroy(&data)
	error, _ := check_layers(&data)
	testing.expect_value(t, error, Layer_Error.None)
	set_height(&data, {x = 3, y = 1, layer = 1}, LAYER_SPACING-1)
	bad: grid.Position
	error, bad = check_layers(&data)
	testing.expect_value(t, error, Layer_Error.Column_Too_Close)
	testing.expect_value(t, bad, grid.Position{x = 3, y = 1, layer = 1})
	// A cave's floor over the ground's, in the same column: the order of the layers is broken.
	cave := hill_map()
	defer destroy(&cave)
	error, _ = check_layers(&cave)
	testing.expect_value(t, error, Layer_Error.None)
	set_height(&cave, {x = 3, y = 2, layer = -1}, 30)
	error, _ = check_layers(&cave)
	testing.expect_value(t, error, Layer_Error.Column_Too_Close)
}

// A ladder joins walkable cells of neighbour columns, from either end; one that does not is refused.
@(test)
test_a_ladder_joins_two_neighbour_cells :: proc(t: ^testing.T) {
	data := hill_map()
	defer destroy(&data)
	foot, top := grid.Position{x = 1, y = 0}, grid.Position{x = 2, y = 0}
	testing.expect(t, add_ladder(&data, foot, top))
	error, _ := check_layers(&data)
	testing.expect_value(t, error, Layer_Error.None)
	end, found := ladder_end(&data, foot, {x = 1, y = 0})
	testing.expect(t, found && end == top)
	end, found = ladder_end(&data, top, {x = -1, y = 0})
	testing.expect(t, found && end == foot)
	_, found = ladder_end(&data, foot, {x = 0, y = 1})
	testing.expect(t, !found)
	testing.expect(t, !add_ladder(&data, foot, {x = 3, y = 0}))
	// An end on no floor (the tunnel's layer has none at (2,0)).
	testing.expect(t, add_ladder(&data, foot, {x = 2, y = 0, layer = -1}))
	error, _ = check_layers(&data)
	testing.expect_value(t, error, Layer_Error.Ladder_Invalid)
}

// In a neighbour column the walkable cell near a height is found on whichever layer holds it: the road under
// the bridge from the road, the deck from the deck, the tunnel from the mouth.
@(test)
test_the_walkable_cell_near_a_height_is_found_on_any_layer :: proc(t: ^testing.T) {
	data := bridge_map()
	defer destroy(&data)
	cell, found := column_walkable_near(&data, 3, 2, 0, 1)
	testing.expect(t, found && cell == grid.Position{x = 3, y = 2})
	cell, found = column_walkable_near(&data, 3, 2, LAYER_SPACING-1, 1)
	testing.expect(t, found && cell == grid.Position{x = 3, y = 2, layer = 1})
	_, found = column_walkable_near(&data, 3, 2, 6, 1)
	testing.expect(t, !found)
	hill := hill_map()
	defer destroy(&hill)
	cell, found = column_walkable_near(&hill, 2, 2, 0, 1)
	testing.expect(t, found && cell == grid.Position{x = 2, y = 2, layer = -1})
	cell, found = column_walkable_near(&hill, 2, 2, 14, 1)
	testing.expect(t, found && cell == grid.Position{x = 2, y = 2})
}

// A column's solids: the ground under its floor, a deck under the bridge, the rock over a tunnel with the
// tunnel's room carved out of it.
@(test)
test_a_column_knows_its_solids :: proc(t: ^testing.T) {
	data := bridge_map()
	defer destroy(&data)
	m := layer_map(&data)
	c := column_of(&m, 3, 2)
	testing.expect_value(t, c.floor_count, 2)
	testing.expect_value(t, c.solid_count, 2)
	testing.expect_value(t, c.solids[0], Column_Span{-COLUMN_FAR, 0})
	testing.expect_value(t, c.solids[1], Column_Span{LAYER_CLEARANCE, LAYER_SPACING})
	testing.expect_value(t, column_room_top(&c, 0), LAYER_CLEARANCE)
	hill := hill_map()
	defer destroy(&hill)
	hm := layer_map(&hill)
	c = column_of(&hm, 3, 2)
	testing.expect_value(t, c.solid_count, 2)
	testing.expect_value(t, c.solids[0], Column_Span{-COLUMN_FAR, 0})
	testing.expect_value(t, c.solids[1], Column_Span{LAYER_CLEARANCE, 14})
	// Off the tunnel the hill is solid up to its top; a wall fills the whole column.
	c = column_of(&hm, 3, 0)
	testing.expect_value(t, c.solid_count, 1)
	testing.expect_value(t, c.solids[0], Column_Span{-COLUMN_FAR, 14})
	set_tile(&hill, {x = 0, y = 0}, {kind = .Wall})
	hm = layer_map(&hill)
	c = column_of(&hm, 0, 0)
	testing.expect_value(t, c.solids[0], Column_Span{-COLUMN_FAR, COLUMN_FAR})
}

// From the bridge one sees the road beside it, but not the road just under it, where the deck is in the way;
// from the road one sees along under the bridge, and the bridge's top only from far enough.
@(test)
test_lines_of_sight_pass_over_and_under_a_bridge :: proc(t: ^testing.T) {
	data := bridge_map()
	defer destroy(&data)
	m := layer_map(&data)
	deck := grid.Position{x = 3, y = 0, layer = 1}
	_, blocked := layer_line_blocker(&m, deck, {x = 5, y = 0}, 6, 4, nothing_opaque, nil)
	testing.expect(t, !blocked)
	// Straight down through the deck, and down at a steep slope under the deck next to it.
	_, blocked = layer_line_blocker(&m, {x = 3, y = 1, layer = 1}, {x = 3, y = 1}, 6, 4, nothing_opaque, nil)
	testing.expect(t, blocked)
	_, blocked = layer_line_blocker(&m, deck, {x = 3, y = 2}, 6, 4, nothing_opaque, nil)
	testing.expect(t, blocked)
	// Along the road, under the deck.
	_, blocked = layer_line_blocker(&m, {x = 0, y = 2}, {x = 6, y = 2}, 6, 4, nothing_opaque, nil)
	testing.expect(t, !blocked)
	// From the road under the bridge up to the deck next door: the deck over the eye is in the way.
	_, blocked = layer_line_blocker(&m, {x = 3, y = 2}, {x = 3, y = 3, layer = 1}, 6, 4, nothing_opaque, nil)
	testing.expect(t, blocked)
	// From the road off the bridge the deck is in sight.
	_, blocked = layer_line_blocker(&m, {x = 0, y = 2}, {x = 3, y = 2, layer = 1}, 6, 4, nothing_opaque, nil)
	testing.expect(t, !blocked)
}

// One sees into the tunnel through its mouth, not through the hill: from the hill's top the rock over the
// tunnel is in the way, at every slope.
@(test)
test_lines_of_sight_enter_a_tunnel_only_through_its_mouth :: proc(t: ^testing.T) {
	data := hill_map()
	defer destroy(&data)
	m := layer_map(&data)
	inside := grid.Position{x = 3, y = 2, layer = -1}
	_, blocked := layer_line_blocker(&m, {x = 0, y = 2}, inside, 6, 4, nothing_opaque, nil)
	testing.expect(t, !blocked)
	_, blocked = layer_line_blocker(&m, inside, {x = 6, y = 2}, 6, 4, nothing_opaque, nil)
	testing.expect(t, !blocked)
	for from in ([3]grid.Position{{x = 3, y = 0}, {x = 2, y = 4}, {x = 3, y = 2}}) {
		_, blocked = layer_line_blocker(&m, from, inside, 6, 4, nothing_opaque, nil)
		testing.expect(t, blocked)
	}
	// Off the mouth's row the hill is solid: no line from the open ground reaches the tunnel.
	_, blocked = layer_line_blocker(&m, {x = 0, y = 0}, inside, 6, 4, nothing_opaque, nil)
	testing.expect(t, blocked)
}

// On a map without layers the line keeps the ground's rule: a cell above the line at its middle hides what
// is behind it, a cell under the line does not, and an opaque floor stops it.
@(test)
test_a_line_on_the_ground_alone_keeps_the_ground_rule :: proc(t: ^testing.T) {
	data, _ := create(7, 1, Tile{kind = .Floor})
	defer destroy(&data)
	set_height(&data, {x = 3, y = 0}, 8)
	m := layer_map(&data)
	_, blocked := layer_line_blocker(&m, {x = 0, y = 0}, {x = 6, y = 0}, 6, 4, nothing_opaque, nil)
	testing.expect(t, blocked)
	set_height(&data, {x = 3, y = 0}, 5)
	m = layer_map(&data)
	_, blocked = layer_line_blocker(&m, {x = 0, y = 0}, {x = 6, y = 0}, 6, 4, nothing_opaque, nil)
	testing.expect(t, !blocked)
	opaque_middle :: proc(data: rawptr, p: grid.Position) -> bool { return p.x == 3 }
	blocker: grid.Position
	blocker, blocked = layer_line_blocker(&m, {x = 0, y = 0}, {x = 6, y = 0}, 6, 4, opaque_middle, nil)
	testing.expect(t, blocked && blocker == grid.Position{x = 3, y = 0})
}

// Pushed off the bridge's edge one lands on the road under it; pushed into the hill at the mouth one goes into
// the tunnel; pushed along the deck one stays on it; into the hill's side one does not go at all.
@(test)
test_a_push_lands_on_the_floor_whose_room_it_enters :: proc(t: ^testing.T) {
	data := bridge_map()
	defer destroy(&data)
	m := layer_map(&data)
	cell, found := column_landing(&m, 4, 2, LAYER_SPACING, 1)
	testing.expect(t, found && cell == grid.Position{x = 4, y = 2})
	cell, found = column_landing(&m, 3, 3, LAYER_SPACING, 1)
	testing.expect(t, found && cell == grid.Position{x = 3, y = 3, layer = 1})
	cell, found = column_landing(&m, 3, 2, 0, 1)
	testing.expect(t, found && cell == grid.Position{x = 3, y = 2})
	hill := hill_map()
	defer destroy(&hill)
	hm := layer_map(&hill)
	cell, found = column_landing(&hm, 2, 2, 0, 1)
	testing.expect(t, found && cell == grid.Position{x = 2, y = 2, layer = -1})
	cell, found = column_landing(&hm, 2, 1, 0, 1)
	testing.expect(t, !found)
	// From the hill's top over the tunnel one stays on the top.
	cell, found = column_landing(&hm, 3, 2, 14, 1)
	testing.expect(t, found && cell == grid.Position{x = 3, y = 2})
}
