package render

import "core:testing"
import rl "vendor:raylib"
import game "../game"
import grid "../engine/grid"
import level "../level"

@(test)
test_diorama_cutaway_only_lowers_camera_facing_perimeter :: proc(t: ^testing.T) {
	rows := [?]string{"#########", "#@......#", "##......#", "#...#...#", "#.......#", "#......>#", "#########"}
	data, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	defer level.destroy(&data)
	room := game.Room{level_data = &data}
	renderer := new(Renderer)
	defer free(renderer)
	for x in ([2]f32{-1, 1}) { for z in ([2]f32{-1, 1}) {
		renderer.tactical.camera = {position = {x*10, 8, z*10}}
		for side in ([4]struct {cell: grid.Position, near: bool}{
			{{x = 0, y = 3}, x < 0}, {{x = 8, y = 3}, x > 0},
			{{x = 4, y = 0}, z < 0}, {{x = 4, y = 6}, z > 0},
		}) {
			expected := DIORAMA_CUTAWAY_HEIGHT if side.near else DIORAMA_WALL_HEIGHT
			testing.expect_value(t, diorama_wall_height(renderer, &room, side.cell), expected)
			testing.expect(t, !diorama_interior_wall(&room, side.cell))
		}
		// A pillar and a wall attached to the outer border are both interior
		// cells. Neither may shrink when the camera crosses the player.
		for cell in ([2]grid.Position{{x = 4, y = 3}, {x = 1, y = 2}}) {
			testing.expect(t, diorama_interior_wall(&room, cell))
			testing.expect_value(t, diorama_wall_height(renderer, &room, cell), DIORAMA_WALL_HEIGHT)
		}
	} }
	for cell in ([4]grid.Position{{x = 1, y = 1}, {x = 3, y = 3}, {x = 7, y = 5}, {x = -1, y = 3}}) {
		testing.expect(t, !diorama_interior_wall(&room, cell))
	}
}

@(test)
test_diorama_cutaway_ignores_player_and_camera_translation :: proc(t: ^testing.T) {
	rows := [?]string{"#######", "#@....#", "#..#..#", "#....>#", "#######"}
	data, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	defer level.destroy(&data)
	room := game.Room{level_data = &data}
	renderer := new(Renderer)
	defer free(renderer)
	snapshot: Room_Presentation
	renderer.tactical.snapshot = &snapshot
	for direction in ([4]rl.Vector3{{8, 9, 8}, {-8, 9, 8}, {-8, 9, -8}, {8, 9, -8}}) {
		for cell in ([5]grid.Position{{x = 0, y = 2}, {x = 6, y = 2}, {x = 3, y = 0}, {x = 3, y = 4}, {x = 3, y = 2}}) {
			renderer.tactical.camera = {position = direction}
			snapshot.player.position = {1, 1}
			expected := diorama_wall_height(renderer, &room, cell)
			for target in ([3]rl.Vector3{{3.5, 0, 2.5}, {-25, 3, 40}, {15, -2, -19}}) {
				for distance_scale in ([3]f32{0.5, 1, 2}) {
					renderer.tactical.camera.position = target+direction*distance_scale
					renderer.tactical.camera.target = target
					snapshot.player.position = {5, 3}
					testing.expect_value(t, diorama_wall_height(renderer, &room, cell), expected)
				}
			}
		}
	}
}

@(test)
test_diorama_cutaway_changes_continuously_across_camera_axis :: proc(t: ^testing.T) {
	rows := [?]string{"#######", "#@....#", "#..#..#", "#....>#", "#######"}
	data, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	defer level.destroy(&data)
	room := game.Room{level_data = &data}
	renderer := new(Renderer)
	defer free(renderer)
	previous_west, previous_east := DIORAMA_CUTAWAY_HEIGHT, DIORAMA_WALL_HEIGHT
	for step in -40..=40 {
		renderer.tactical.camera = {position = {f32(step)*0.1, 8, 10}}
		west := diorama_wall_height(renderer, &room, {x = 0, y = 2})
		east := diorama_wall_height(renderer, &room, {x = 6, y = 2})
		testing.expect(t, west >= previous_west && east <= previous_east)
		if step > -40 {
			testing.expect(t, abs(west-previous_west) < 0.06)
			testing.expect(t, abs(east-previous_east) < 0.06)
		}
		testing.expect_value(t, diorama_wall_height(renderer, &room, {x = 3, y = 4}), DIORAMA_CUTAWAY_HEIGHT)
		testing.expect_value(t, diorama_wall_height(renderer, &room, {x = 3, y = 0}), DIORAMA_WALL_HEIGHT)
		if step == 0 {
			testing.expect_value(t, west, DIORAMA_WALL_HEIGHT)
			testing.expect_value(t, east, DIORAMA_WALL_HEIGHT)
		}
		previous_west, previous_east = west, east
	}
	renderer.tactical.camera = {position = {0, 8, 0}}
	testing.expect_value(t, diorama_wall_height(renderer, &room, {x = 0, y = 2}), DIORAMA_WALL_HEIGHT)
}

@(test)
test_diorama_transparent_interior_wall_preserves_collision_sight_and_fog :: proc(t: ^testing.T) {
	rows := [?]string{"#########", "#.......#", "#.......#", "#..@#...#", "#.......#", "#......>#", "#########"}
	data, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	defer level.destroy(&data)
	player, made := game.create_player({max_health = 20, attack = 2})
	testing.expect(t, made)
	testing.expect(t, game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
	player.tactical.facing = .East
	enemies := [?]game.Enemy_Spawn{{position = {x = 6, y = 3}, health = 5, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	renderer := new(Renderer)
	defer free(renderer)
	renderer^ = create(960, 540)
	snapshot: Room_Presentation
	renderer.tactical = {snapshot = &snapshot}
	update_tactical_view(renderer, &room, {}, false)
	for direction in ([4]rl.Vector3{{8, 9, 8}, {-8, 9, 8}, {-8, 9, -8}, {8, 9, -8}}) {
		renderer.tactical.camera = {position = direction}
		testing.expect(t, diorama_interior_wall(&room, {x = 4, y = 3}))
		testing.expect_value(t, diorama_wall_height(renderer, &room, {x = 4, y = 3}), DIORAMA_WALL_HEIGHT)
		testing.expect(t, game.cell_blocks_movement(&room, {x = 4, y = 3}))
		testing.expect(t, game.cell_blocks_line_of_sight(&room, {x = 4, y = 3}))
		testing.expect(t, tactical_render_visible(renderer, {x = 4, y = 3}))
		testing.expect(t, !game.tactical_cell_visible(&room, {x = 6, y = 3}))
		testing.expect(t, !tactical_render_visible(renderer, {x = 6, y = 3}))
		testing.expect_value(t, game.try_move_player(&room, .East), game.Action_Result.Blocked)
		testing.expect_value(t, player.position, grid.Position{x = 3, y = 3})
	}
}

@(test)
test_diorama_translucents_share_actor_depth_order_and_obey_visibility :: proc(t: ^testing.T) {
	rows := [?]string{"#########", "#@......#", "#.......#", "#...#...#", "#.......#", "#......>#", "#########"}
	data, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	defer level.destroy(&data)
	room := game.Room{level_data = &data}
	renderer := new(Renderer)
	defer free(renderer)
	defer destroy_tactical_translucents(renderer)
	snapshot := Room_Presentation{valid = true, enemy_count = 2}
	snapshot.player = {position = {5, 4}, visible = true, opacity = 1}
	snapshot.enemies[0] = {position = {3, 2}, visible = true, opacity = 1}
	snapshot.enemies[1] = {position = {6, 3}, visible = false, opacity = 1}
	renderer.tactical = {no_fog = true, snapshot = &snapshot}
	for sign in ([2]f32{1, -1}) {
		renderer.tactical.camera = {position = {sign*10, 8, sign*10}}
		entries := collect_tactical_translucents(renderer, &room)
		testing.expect_value(t, len(entries), 3)
		if len(entries) != 3 { continue }
		testing.expect(t, entries[1].kind == .Wall)
		testing.expect(t, entries[0].depth > entries[1].depth && entries[1].depth > entries[2].depth)
		near_index := 2 if sign > 0 else 0
		testing.expect_value(t, entries[near_index].key, Sprite_Key.Player)
		testing.expect_value(t, entries[near_index].position, snapshot.player.position)
		testing.expect_value(t, entries[2-near_index].position, snapshot.enemies[0].position)
	}
	// The same pass must neither reveal an enemy behind fog nor submit a wall
	// outside current visibility. Perimeter walls never enter the alpha pass.
	renderer.tactical.no_fog = false
	renderer.tactical.visible_count = 1
	renderer.tactical.visible[0] = {x = 4, y = 3}
	entries := collect_tactical_translucents(renderer, &room)
	testing.expect_value(t, len(entries), 2)
	for entry in entries {
		testing.expect(t, entry.kind == .Wall || entry.key == .Player)
	}
	renderer.tactical.visible[0] = {x = 3, y = 2}
	entries = collect_tactical_translucents(renderer, &room)
	testing.expect_value(t, len(entries), 2)
	for entry in entries { testing.expect(t, entry.kind == .Sprite) }
	// The hologram supplies no room and keeps its own miniature wall pass.
	renderer.tactical.no_fog = true
	entries = collect_tactical_translucents(renderer)
	testing.expect_value(t, len(entries), 2)
	for entry in entries { testing.expect(t, entry.kind == .Sprite) }
}
