package game

import "core:testing"
import grid "../engine/grid"

// Deliberately simple O(cells²) oracle: guards cost direction, unreachable cells
// and every goal kind while the production solver changes its frontier data.
reference_tactical_enemy_distances :: proc(room: ^Room, distances: []int, goal: Enemy_Path_Goal) {
	visited := make([]bool, len(distances))
	costs := make([]int, len(distances))
	defer delete(visited)
	defer delete(costs)
	tiles := &room.level_data.tiles
	for &distance, i in distances {
		cell := grid.Position{x = i%tiles.width, y = i/tiles.width}
		distance = -1
		if cell_blocks_movement(room, cell) { visited[i] = true; continue }
		costs[i] = 1+enemy_terrain_danger(room, cell)
		if enemy_position_is_goal(room, cell, goal) { distance = 0 }
	}
	for _ in 0..<len(distances) {
		best, score := -1, max(int)
		for distance, i in distances {
			if !visited[i] && distance >= 0 && distance < score { best, score = i, distance }
		}
		if best < 0 { break }
		visited[best] = true
		cell := grid.Position{x = best%tiles.width, y = best/tiles.width}
		for step in ([?]grid.Position{{x = 0, y = -1}, {x = 1, y = 0}, {x = 0, y = 1}, {x = -1, y = 0}}) {
			i, ok := grid.index_of(tiles, add_position(cell, step))
			if !ok || visited[i] { continue }
			candidate := score+costs[best]
			if distances[i] < 0 || candidate < distances[i] { distances[i] = candidate }
		}
	}
}


@(test)
test_arena_weighted_paths_match_scan_solver :: proc(t: ^testing.T) {
	for depth in ([?]int{0, 2, 4, 6}) {
		for seed in ([?]u64{17, 94}) {
			node := test_generation_node(1, .Boss, depth, seed)
			blueprint, error := generate_room_blueprint(&node, .Scattered)
			testing.expect_value(t, error, Room_Blueprint_Error.None)
			if error != .None { continue }
			player := create_test_player(t)
			testing.expect(t, configure_tactical(&player, DEFAULT_TACTICAL_CONFIG))
			room, ok := create_room(&blueprint.level_data, &player, {
				enemies = blueprint.enemies[:], traps = blueprint.traps[:],
				obstacles = blueprint.obstacles[:], objects = blueprint.objects[:]})
			testing.expect(t, ok)
			if ok {
				// Armed explosion adds weighted danger on top of existing fire/traps.
				for &object in room.objects { if object.kind == .Barrel { object.detonation_pulse = room.pulse_count+1; break } }
				actual := make([]int, len(room.level_data.tiles.cells))
				expected := make([]int, len(actual))
				for goal in Enemy_Path_Goal {
					reference_tactical_enemy_distances(&room, expected, goal)
					rebuild_tactical_enemy_distances(&room, actual, goal)
					for value, index in actual { testing.expect_value(t, value, expected[index]) }
				}
				delete(actual); delete(expected)
				destroy_room(&room)
			}
			destroy_room_blueprint(&blueprint)
		}
	}
}
