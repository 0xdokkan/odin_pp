package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

// STRUCTURES IN THE RULES (Fase 6): walking, sight and the enemies' way round them
// come from the tiles a structure writes, with no rule of their own. A wall stops the
// step and the sight, a fence only the step, a door lets both pass.

@(private = "file")
structure_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, rows: []string) -> (room: Room) {
	parsed: level.Parse_Error
	data^, parsed, _ = level.from_ascii(rows)
	testing.expect_value(t, parsed, level.Parse_Error.None)
	player^ = create_test_player(t)
	made: bool
	room, made = create_room(data, player, {})
	testing.expect(t, made)
	return
}

@(test)
test_a_fence_stops_the_step_but_not_the_sight_and_a_wall_stops_both :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := structure_room(t, &data, &player, {
		"#########",
		"#@..=..>#",
		"#...#...#",
		"#########",
	})
	defer level.destroy(&data)
	defer destroy_room(&room)
	fence, wall, floor := grid.Position{4, 1}, grid.Position{4, 2}, grid.Position{3, 1}
	testing.expect(t, !base_cell_is_walkable(&room, fence))
	testing.expect(t, cell_blocks_movement(&room, fence))
	testing.expect(t, !cell_blocks_line_of_sight(&room, fence), "the sight passes over a fence")
	testing.expect(t, cell_blocks_movement(&room, wall) && cell_blocks_line_of_sight(&room, wall))
	testing.expect(t, !cell_blocks_movement(&room, floor) && !cell_blocks_line_of_sight(&room, floor))
	// A line of sight through the fence is clear, and through the wall it is not.
	blocks :: proc(data: rawptr, cell: grid.Position) -> bool { return cell_blocks_line_of_sight(cast(^Room)data, cell) }
	testing.expect(t, tactical_line_visible({1, 1}, {6, 1}, blocks, &room), "over the fence")
	testing.expect(t, !tactical_line_visible({1, 2}, {6, 2}, blocks, &room), "through the wall")
	// The player cannot step onto the fence.
	room.player.position = {3, 1}
	testing.expect_value(t, try_move_player(&room, .East), Action_Result.Blocked)
	testing.expect_value(t, room.player.position, grid.Position{3, 1})
}

// A building's walls stop the step and the sight, its door lets both pass.
@(test)
test_a_building_stops_the_step_and_the_sight_except_through_its_door :: proc(t: ^testing.T) {
	data, _ := level.create(24, 24, level.Tile{kind = .Floor})
	defer level.destroy(&data)
	for i in 0..<24 {
		_ = level.set_tile(&data, {i, 0}, {kind = .Wall}); _ = level.set_tile(&data, {i, 23}, {kind = .Wall})
		_ = level.set_tile(&data, {0, i}, {kind = .Wall}); _ = level.set_tile(&data, {23, i}, {kind = .Wall})
	}
	_ = level.set_tile(&data, {1, 1}, {kind = .Player_Spawn})
	data.player_spawn, data.has_player_spawn = {1, 1}, true
	_ = level.set_tile(&data, {22, 22}, {kind = .Exit})
	index, err := level.place_structure(&data, .Hut, {8, 8}, 0, false)
	testing.expect_value(t, err, level.Placement_Error.None)
	player := create_test_player(t)
	room, made := create_room(&data, &player, {})
	testing.expect(t, made)
	defer destroy_room(&room)
	// The hut is 5 by 4 at (8, 8): walls on its top and sides, a door at (10, 11), floor inside.
	plan := data.structure_plans[index]
	for y in 0..<plan.height {
		for x in 0..<plan.width {
			cell := grid.Position{8+x, 8+y}
			switch level.plan_at(&plan, x, y) {
			case .Wall:
				testing.expect(t, cell_blocks_movement(&room, cell) && cell_blocks_line_of_sight(&room, cell))
			case .Door, .Floor, .Use:
				testing.expect(t, !cell_blocks_movement(&room, cell) && !cell_blocks_line_of_sight(&room, cell))
			case .Fence, .Outside:
			}
		}
	}
	blocks :: proc(data: rawptr, cell: grid.Position) -> bool { return cell_blocks_line_of_sight(cast(^Room)data, cell) }
	// From outside to the middle of the room: through the wall it is blocked, through the door it is clear.
	testing.expect(t, !tactical_line_visible({10, 6}, {10, 9}, blocks, &room), "the wall hides the inside")
	testing.expect(t, tactical_line_visible({10, 13}, {10, 9}, blocks, &room), "the door shows the inside")
}

// An enemy's blow breaks the object the player set down in its reach or beside the one who strikes it, once however many of its cells
// are hit, and never a building; a blow far from it does nothing.
@(test)
test_an_enemy_blow_breaks_a_placed_object_in_reach_and_never_a_building :: proc(t: ^testing.T) {
	rows := make([]string, 16, context.temp_allocator)
	for y in 0..<16 {
		row := make([]u8, 30, context.temp_allocator)
		for x in 0..<30 { row[x] = '#' if x == 0 || y == 0 || x == 29 || y == 15 else '.' }
		if y == 1 { row[1] = '@' }
		if y == 14 { row[28] = '>' }
		rows[y] = string(row)
	}
	data: level.Level
	player: Player
	room := structure_room(t, &data, &player, rows)
	defer level.destroy(&data)
	defer destroy_room(&room)
	cart, _ := level.place_structure(&data, .Cart, {10, 6}, 0, false)
	cottage, _ := level.place_structure(&data, .Cottage, {18, 4}, 0, false)
	testing.expect(t, cart >= 0 && cottage >= 0)
	data.structures[cart].health = level.structure_max_health(.Cart)
	cart_origin := data.structures[cart].origin
	// Far from both: nothing.
	testing.expect_value(t, strike_structures(&room, {3, 3}, {{4, 3}, {5, 3}}, 5), 0)
	testing.expect_value(t, data.structures[cart].health, level.structure_max_health(.Cart))
	// A threatened cell on the cart: it takes the damage once, though two of its cells are threatened.
	testing.expect_value(t, strike_structures(&room, {7, 7}, {cart_origin, {cart_origin.x+1, cart_origin.y}}, 2), 0)
	testing.expect_value(t, data.structures[cart].health, level.structure_max_health(.Cart)-2)
	// Beside the one who strikes, with no cell of the blow on it.
	testing.expect_value(t, strike_structures(&room, {cart_origin.x-1, cart_origin.y}, {{cart_origin.x-3, cart_origin.y}}, 1), 0)
	testing.expect_value(t, data.structures[cart].health, level.structure_max_health(.Cart)-3)
	// The cottage takes nothing, however hard the blow.
	testing.expect_value(t, strike_structures(&room, {17, 5}, {{18, 5}, {19, 5}}, 50), 0)
	testing.expect_value(t, level.structure_count(&data), 2)
	// Enough damage brings the cart down and takes it off the map.
	testing.expect_value(t, strike_structures(&room, {cart_origin.x-1, cart_origin.y}, {cart_origin}, 50), 1)
	testing.expect_value(t, level.structure_count(&data), 1)
	testing.expect_value(t, data.structures[0].id, level.Structure_Id.Cottage)
	// No damage, no blow.
	testing.expect_value(t, strike_structures(&room, {17, 5}, {{18, 5}}, 0), 0)
}
