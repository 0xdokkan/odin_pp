package level

import "core:testing"
import grid "../engine/grid"

// A map of open floor `width` by `height` inside a wall, with the spawn at (1, 1).
@(private = "file")
open_map :: proc(width, height: int) -> Level {
	data, _ := create(width, height, Tile{kind = .Floor})
	for x in 0..<width { _ = set_tile(&data, {x = x, y = 0}, {kind = .Wall}); _ = set_tile(&data, {x = x, y = height-1}, {kind = .Wall}) }
	for y in 0..<height { _ = set_tile(&data, {x = 0, y = y}, {kind = .Wall}); _ = set_tile(&data, {x = width-1, y = y}, {kind = .Wall}) }
	_ = set_tile(&data, {x = 1, y = 1}, {kind = .Player_Spawn})
	data.player_spawn, data.has_player_spawn = {x = 1, y = 1}, true
	return data
}

@(test)
test_fence_stops_the_step_but_is_a_tile_of_its_own :: proc(t: ^testing.T) {
	testing.expect(t, !is_walkable(.Fence))
	tile, ok := tile_from_symbol('=')
	testing.expect(t, ok && tile.kind == .Fence)
	testing.expect_value(t, tile_symbol(.Fence), "=")
}

@(test)
test_every_structure_of_the_catalog_has_a_valid_plan :: proc(t: ^testing.T) {
	for id in Structure_Id.Cottage..<Structure_Id.Count {
		definition := structure_definition(id)
		testing.expect(t, definition.name != "")
		_, err := parse_plan(definition.rows, definition.kind)
		testing.expectf(t, err == .None, "%v: %s", id, plan_error_text(err))
		testing.expect(t, definition.rotations != {}, "may be placed in some turn")
	}
	// The sizes the plan asked for.
	size :: proc(id: Structure_Id) -> [2]int {
		d := structure_definition(id)
		p, _ := parse_plan(d.rows, d.kind)
		return {p.width, p.height}
	}
	testing.expect_value(t, size(.Cottage), [2]int{4, 3})
	testing.expect_value(t, size(.Hut), [2]int{5, 4})
	testing.expect_value(t, size(.Temple), [2]int{7, 7})
	testing.expect_value(t, size(.Cart), [2]int{2, 1})
	testing.expect_value(t, size(.Fountain), [2]int{2, 2})
	testing.expect_value(t, size(.Statue), [2]int{2, 2})
	testing.expect_value(t, size(.Machine), [2]int{3, 2})
	testing.expect_value(t, size(.Ruin), [2]int{3, 3})
	// The three buildings are buildings; the rest are not.
	for id in Structure_Id.Cottage..<Structure_Id.Count {
		testing.expect_value(t, structure_is_building(id), id == .Cottage || id == .Hut || id == .Temple)
	}
}

// Four quarter turns bring a plan back; the cells and the doors are kept; a mirror twice
// is the plan; and every allowed turn of every plan still satisfies the plan's rules.
@(test)
test_four_quarter_turns_bring_a_plan_back_and_every_turn_stays_valid :: proc(t: ^testing.T) {
	for id in Structure_Id.Cottage..<Structure_Id.Count {
		definition := structure_definition(id)
		plan, _ := parse_plan(definition.rows, definition.kind)
		turned := plan
		for _ in 0..<4 { turned = rotate_plan(turned) }
		testing.expect_value(t, turned.width, plan.width)
		testing.expect_value(t, turned.height, plan.height)
		for i in 0..<plan.width*plan.height { testing.expect_value(t, turned.cells[i], plan.cells[i]) }
		twice := mirror_plan(mirror_plan(plan))
		for i in 0..<plan.width*plan.height { testing.expect_value(t, twice.cells[i], plan.cells[i]) }
		for rotation in u8(0)..<4 {
			for mirror in ([2]bool{false, true}) {
				moved := transform_plan(plan, rotation, mirror)
				testing.expect_value(t, plan_footprint_count(&moved), plan_footprint_count(&plan))
				// A quarter turn swaps the sides.
				if rotation%2 == 1 { testing.expect_value(t, moved.width, plan.height) } else { testing.expect_value(t, moved.width, plan.width) }
				testing.expectf(t, plan_problem(&moved, definition.kind) == .None, "%v turned %d mirrored %v", id, rotation, mirror)
				for cell in Plan_Cell {
					count_before, count_after := 0, 0
					for i in 0..<plan.width*plan.height { if plan.cells[i] == cell { count_before += 1 } }
					for i in 0..<moved.width*moved.height { if moved.cells[i] == cell { count_after += 1 } }
					testing.expect_value(t, count_after, count_before)
				}
			}
		}
	}
}

@(test)
test_a_plan_with_a_fault_is_refused_with_a_clear_error :: proc(t: ^testing.T) {
	_, err := parse_plan({}, .Object)
	testing.expect_value(t, err, Plan_Error.Empty)
	_, err = parse_plan({"###", "##"}, .Object)
	testing.expect_value(t, err, Plan_Error.Inconsistent_Row_Width)
	_, err = parse_plan({"#x#"}, .Object)
	testing.expect_value(t, err, Plan_Error.Unknown_Symbol)
	_, err = parse_plan({"###", "#+#", "###"}, .Building)
	testing.expect_value(t, err, Plan_Error.Door_Not_On_Edge)
	_, err = parse_plan({"####", "#..#", "####"}, .Building)
	testing.expect_value(t, err, Plan_Error.Building_Without_Door)
	// The right-hand room cannot be reached from the door.
	_, err = parse_plan({"#####", "#.#.#", "##+##"}, .Building)
	testing.expect_value(t, err, Plan_Error.Floor_Not_Connected)
	_, err = parse_plan({"#############", "#############"}, .Object)
	testing.expect_value(t, err, Plan_Error.Too_Big)
	// An object with no door and no floor is fine.
	_, err = parse_plan({"##", "##"}, .Object)
	testing.expect_value(t, err, Plan_Error.None)
	testing.expect(t, plan_error_text(.Floor_Not_Connected) != "")
}

// Placing writes every cell of the footprint as an ordinary tile, in every turn, and the
// cells outside the footprint keep the ground they had.
@(test)
test_a_structure_writes_its_whole_footprint_in_every_turn :: proc(t: ^testing.T) {
	for id in Structure_Id.Cottage..<Structure_Id.Count {
		for rotation in u8(0)..<4 {
			data := open_map(24, 24)
			defer destroy(&data)
			index, err := place_structure(&data, id, {x = 8, y = 8}, rotation, false)
			testing.expectf(t, err == .None, "%v turned %d: %s", id, rotation, placement_error_text(err))
			if err != .None { continue }
			plan := data.structure_plans[index]
			covered := 0
			for y in 0..<24 {
				for x in 0..<24 {
					inside := x >= 8 && y >= 8 && x < 8+plan.width && y < 8+plan.height
					cell := plan_at(&plan, x-8, y-8) if inside else Plan_Cell.Outside
					tile, _ := tile_at(&data, {x = x, y = y})
					if cell == .Outside {
						if !(x == 0 || y == 0 || x == 23 || y == 23 || (x == 1 && y == 1)) { testing.expect_value(t, tile.kind, Tile_Kind.Floor) }
						_, owned := structure_index_at(&data, {x = x, y = y})
						testing.expect(t, !owned, "outside the footprint belongs to nobody")
						continue
					}
					covered += 1
					expected, _ := plan_tile(cell)
					testing.expect_value(t, tile.kind, expected.kind)
					owner, owned := structure_index_at(&data, {x = x, y = y})
					testing.expect(t, owned && owner == index)
				}
			}
			testing.expect_value(t, covered, plan_footprint_count(&plan))
			testing.expect_value(t, structure_count(&data), 1)
		}
	}
}

// Every cell counts: a statue (2 by 2) takes and blocks four cells, not one; a cart
// stops the step on both of its cells but not the sight.
@(test)
test_every_cell_of_a_complex_object_counts :: proc(t: ^testing.T) {
	data := open_map(16, 16)
	defer destroy(&data)
	_, err := place_structure(&data, .Statue, {x = 5, y = 5}, 0, false)
	testing.expect_value(t, err, Placement_Error.None)
	for cell in ([4]grid.Position{{x = 5, y = 5}, {x = 6, y = 5}, {x = 5, y = 6}, {x = 6, y = 6}}) {
		tile, _ := tile_at(&data, cell)
		testing.expect_value(t, tile.kind, Tile_Kind.Wall)
		testing.expect(t, !is_walkable(tile.kind))
	}
	_, err = place_structure(&data, .Cart, {x = 9, y = 9}, 0, false)
	testing.expect_value(t, err, Placement_Error.None)
	for cell in ([2]grid.Position{{x = 9, y = 9}, {x = 10, y = 9}}) {
		tile, _ := tile_at(&data, cell)
		testing.expect_value(t, tile.kind, Tile_Kind.Fence)
		testing.expect(t, !is_walkable(tile.kind))
	}
}

@(test)
test_placement_is_refused_outside_the_map_over_something_or_next_to_another :: proc(t: ^testing.T) {
	data := open_map(20, 20)
	defer destroy(&data)
	// Off the map, and on the border.
	testing.expect_value(t, place_check(&data, .Hut, {x = 17, y = 5}, 0, false), Placement_Error.Out_Of_Map)
	testing.expect_value(t, place_check(&data, .Hut, {x = -2, y = 5}, 0, false), Placement_Error.Out_Of_Map)
	testing.expect_value(t, place_check(&data, .Hut, {x = 0, y = 5}, 0, false), Placement_Error.Out_Of_Map)
	// On another layer than the ground (docs/piano-profondita.md), where a structure fits on the ground.
	testing.expect_value(t, place_check(&data, .Statue, {x = 5, y = 5}, 0, false), Placement_Error.None)
	testing.expect_value(t, place_check(&data, .Statue, {x = 5, y = 5, layer = -1}, 0, false), Placement_Error.Out_Of_Map)
	// Over the spawn, and over a wall.
	testing.expect_value(t, place_check(&data, .Cottage, {x = 1, y = 1}, 0, false), Placement_Error.Not_Free)
	_ = set_tile(&data, {x = 12, y = 12}, {kind = .Wall})
	testing.expect_value(t, place_check(&data, .Statue, {x = 11, y = 11}, 0, false), Placement_Error.Not_Free)
	// Over another structure, and touching one.
	_, err := place_structure(&data, .Machine, {x = 4, y = 8}, 0, false)
	testing.expect_value(t, err, Placement_Error.None)
	testing.expect_value(t, place_check(&data, .Statue, {x = 5, y = 8}, 0, false), Placement_Error.Overlap)
	testing.expect_value(t, place_check(&data, .Statue, {x = 7, y = 8}, 0, false), Placement_Error.Too_Close)
	testing.expect_value(t, place_check(&data, .Statue, {x = 8, y = 8}, 0, false), Placement_Error.None)
	// What the caller says must stay clear.
	clear_at_seven :: proc(user: rawptr, cell: grid.Position) -> bool { return cell.x == 14 }
	testing.expect_value(t, place_check(&data, .Statue, {x = 13, y = 3}, 0, false, clear_at_seven), Placement_Error.Keep_Clear)
	// A turn or a mirror the definition does not allow.
	testing.expect_value(t, place_check(&data, .Fountain, {x = 3, y = 15}, 0, true), Placement_Error.Mirror_Not_Allowed)
	// A refused placement changes nothing.
	testing.expect_value(t, structure_count(&data), 1)
}

// A door must open onto walkable ground: a cottage whose door faces a wall is refused.
@(test)
test_a_door_that_opens_onto_a_blocked_cell_is_refused :: proc(t: ^testing.T) {
	data := open_map(20, 20)
	defer destroy(&data)
	// The cottage's door is at its bottom, at (x+2, y+2) = (10, 13); the cell below it is a wall.
	_ = set_tile(&data, {x = 10, y = 14}, {kind = .Wall})
	testing.expect_value(t, place_check(&data, .Cottage, {x = 8, y = 11}, 0, false), Placement_Error.Entrance_Blocked)
	// Turned so that its door faces another way, it can stand there.
	testing.expect_value(t, place_check(&data, .Cottage, {x = 8, y = 11}, 2, false), Placement_Error.None)
}

// A structure that would shut a part of a whole map off is refused.
@(test)
test_a_structure_that_would_close_a_pocket_is_refused :: proc(t: ^testing.T) {
	// A corridor two cells high; the spawn is at its left.
	data := open_map(12, 4)
	defer destroy(&data)
	testing.expect_value(t, place_check(&data, .Fountain, {x = 5, y = 1}, 0, false), Placement_Error.Pocket)
	// A statue on one side of a three-wide corridor leaves the way open.
	wide := open_map(12, 5)
	defer destroy(&wide)
	testing.expect_value(t, place_check(&wide, .Statue, {x = 5, y = 1}, 0, false), Placement_Error.None)
	// A building with a door seals nothing: its inside is reached through the door.
	room := open_map(20, 20)
	defer destroy(&room)
	_, err := place_structure(&room, .Hut, {x = 8, y = 8}, 0, false)
	testing.expect_value(t, err, Placement_Error.None)
	reached, total := reachable_walkable(&room, room.tiles.cells[:], 20, 20, {x = 1, y = 1})
	testing.expect_value(t, reached, total)
}

@(test)
test_the_structures_are_restored_from_a_saved_list :: proc(t: ^testing.T) {
	data := open_map(30, 30)
	defer destroy(&data)
	_, _ = place_structure(&data, .Temple, {x = 10, y = 10}, 1, true)
	_, _ = place_structure(&data, .Cart, {x = 20, y = 20}, 3, false)
	saved := make([dynamic]Placed_Structure)
	defer delete(saved)
	append(&saved, ..data.structures[:])
	other := open_map(30, 30)
	defer destroy(&other)
	copy(other.tiles.cells[:], data.tiles.cells[:])
	testing.expect(t, set_structures(&other, saved[:]))
	testing.expect_value(t, structure_count(&other), 2)
	for cell, i in data.structure_cells { testing.expect_value(t, other.structure_cells[i], cell) }
	for y in 0..<30 {
		for x in 0..<30 {
			first, inside_first := structure_index_at(&data, {x = x, y = y})
			second, inside_second := structure_index_at(&other, {x = x, y = y})
			testing.expect(t, first == second && inside_first == inside_second)
			testing.expect_value(t, structure_plan_cell(&other, 0, {x = x, y = y}), structure_plan_cell(&data, 0, {x = x, y = y}))
		}
	}
	// A record that does not fit is refused.
	bad := [1]Placed_Structure{{id = .Hut, origin = {x = 28, y = 28}}}
	testing.expect(t, !set_structures(&other, bad[:]))
	bad_turn := [1]Placed_Structure{{id = .Hut, origin = {x = 5, y = 5}, rotation = 9}}
	testing.expect(t, !set_structures(&other, bad_turn[:]))
	// An empty list is the old save: no structures.
	testing.expect(t, set_structures(&other, nil))
	testing.expect_value(t, structure_count(&other), 0)
}

// On a map with heights a structure needs level ground, and a door needs a step the robot can take.
@(test)
test_a_structure_needs_level_ground_and_a_door_a_step_to_climb :: proc(t: ^testing.T) {
	data := open_map(20, 20)
	defer destroy(&data)
	_ = set_height(&data, {x = 9, y = 9}, 2)
	testing.expect_value(t, place_check(&data, .Cottage, {x = 8, y = 8}, 0, false), Placement_Error.Not_Flat)
	// The same cottage on a level plateau of its own is fine, but a cliff in front of its door is not.
	for y in 8..<14 { for x in 8..<14 { _ = set_height(&data, {x = x, y = y}, 3) } }
	for y in 8..<14 { for x in 8..<14 { if y == 13 { _ = set_height(&data, {x = x, y = y}, 0) } } }
	// The cottage at (8, 10) has its door at (10, 12); below it (10, 13) is at 0, three steps down.
	testing.expect_value(t, place_check(&data, .Cottage, {x = 8, y = 10}, 0, false), Placement_Error.Entrance_Blocked)
	// Lowering that cell to two steps down is still a cliff; one step is a stair.
	_ = set_height(&data, {x = 10, y = 13}, 2)
	testing.expect_value(t, place_check(&data, .Cottage, {x = 8, y = 10}, 0, false), Placement_Error.None)
}

// Only the objects and the pens the player sets down fall apart; they take the damage they are dealt, and when their health is gone
// their cells are open floor again and they leave the list (the others move up).
@(test)
test_an_object_falls_apart_when_hurt_enough_and_a_building_never_does :: proc(t: ^testing.T) {
	data := open_map(40, 30)
	defer destroy(&data)
	testing.expect_value(t, structure_max_health(.Cottage), i16(0))
	testing.expect_value(t, structure_max_health(.Temple), i16(0))
	for id in Structure_Id {
		if id == .Count { continue }
		definition := structure_definition(id)
		if definition.kind == .Building { testing.expect_value(t, structure_max_health(id), i16(0)) } else { testing.expect(t, structure_max_health(id) > 0) }
	}
	building, _ := place_structure(&data, .Cottage, {x = 4, y = 4}, 0, false)
	cart, _ := place_structure(&data, .Cart, {x = 14, y = 4}, 0, false)
	pen, _ := place_structure(&data, .Pen, {x = 24, y = 12}, 0, false)
	testing.expect(t, building >= 0 && cart >= 0 && pen >= 0)
	data.structures[cart].health = structure_max_health(.Cart)
	data.structures[pen].health = structure_max_health(.Pen)
	// A building and the map's own (health 0) take no harm.
	testing.expect(t, !damage_structure(&data, building, 99))
	testing.expect_value(t, structure_count(&data), 3)
	// The cart takes a few blows before it falls.
	before := data.geometry_revision
	testing.expect(t, !damage_structure(&data, cart, 2))
	testing.expect_value(t, data.structures[cart].health, structure_max_health(.Cart)-2)
	testing.expect(t, data.geometry_revision != before, "a hurt structure is drawn again")
	testing.expect(t, !damage_structure(&data, cart, 0) && !damage_structure(&data, cart, -3))
	cart_cell := data.structures[cart].origin
	tile, _ := tile_at(&data, cart_cell)
	solid := !is_walkable(tile.kind)
	testing.expect(t, damage_structure(&data, cart, 99))
	testing.expect_value(t, structure_count(&data), 2)
	if solid {
		tile, _ = tile_at(&data, cart_cell)
		testing.expect_value(t, tile.kind, Tile_Kind.Floor)
	}
	// Where the cart stood there is no structure now, and the pen moved up to index 1 with its health intact.
	_, found := structure_index_at(&data, cart_cell)
	testing.expect(t, !found)
	index, at_pen := structure_index_at(&data, data.structures[1].origin)
	testing.expect(t, at_pen && index == 1 && data.structures[1].id == .Pen && data.structures[1].health == structure_max_health(.Pen))
	// The pen's fences are gone with it.
	pen_origin := data.structures[1].origin
	testing.expect(t, damage_structure(&data, 1, 99))
	for dy in 0..<4 { for dx in 0..<5 {
		cell, _ := tile_at(&data, grid.offset(pen_origin, dx, dy))
		testing.expect(t, cell.kind == .Floor, "the pen is cleared")
	}}
	testing.expect(t, !remove_structure(&data, 9) && !remove_structure(&data, -1))
}
