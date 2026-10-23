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
