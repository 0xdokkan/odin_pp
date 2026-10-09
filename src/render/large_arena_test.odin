package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"
import game "../game"
import grid "../grid"
import level "../level"

@(test)
test_large_hologram_fits_board_and_sprites_at_every_orbit :: proc(t: ^testing.T) {
	renderer := new(Renderer)
	defer free(renderer)
	renderer.canvas_width, renderer.canvas_height = 960, 540
	viewport := tactical_map_drag_bounds(renderer)
	for dimensions in ([4]grid.Position{{17, 11}, {45, 31}, {31, 45}, {63, 17}}) {
		for pitch in ([3]f32{0.3, 0.68, 1.45}) {
			for step in 0..<8 {
				orbit := Tactical_Orbit{yaw = f32(step)*math.PI/4, pitch = pitch, distance = 12.5, initialized = true}
				camera := tactical_hologram_camera(renderer, dimensions.x, dimensions.y, orbit)
				minimum, maximum := rl.Vector2{1e30, 1e30}, rl.Vector2{-1e30, -1e30}
				for x in ([2]f32{0, f32(dimensions.x)}) {
					for y in ([2]f32{0, 1.8}) {
						for z in ([2]f32{0, f32(dimensions.y)}) {
							point := rl.GetWorldToScreenEx({x, y, z}, camera, 960, 540)
							minimum.x, minimum.y = min(minimum.x, point.x), min(minimum.y, point.y)
							maximum.x, maximum.y = max(maximum.x, point.x), max(maximum.y, point.y)
							testing.expect(t, point.x >= viewport.x+10 && point.x <= viewport.x+viewport.width-10)
							testing.expect(t, point.y >= viewport.y+10 && point.y <= viewport.y+viewport.height-10)
						}
					}
				}
				// The overview must make useful use of the available space;
				// keeping the aim at the board center left the far side tiny.
				testing.expect(t, (maximum.x-minimum.x)/viewport.width > 0.8 || (maximum.y-minimum.y)/viewport.height > 0.8)
				// Zoom remains user controlled: inspection can get closer than
				// the overview, and zooming out keeps the same aim and orbit.
				near_orbit, far_orbit := orbit, orbit
				near_orbit.distance, far_orbit.distance = 7, 24
				near_camera := tactical_hologram_camera(renderer, dimensions.x, dimensions.y, near_orbit)
				far_camera := tactical_hologram_camera(renderer, dimensions.x, dimensions.y, far_orbit)
				testing.expect_value(t, near_camera.target, camera.target)
				testing.expect_value(t, far_camera.target, camera.target)
				base_distance := rl.Vector3Length(camera.position-camera.target)
				testing.expect(t, abs(rl.Vector3Length(near_camera.position-camera.target)/base_distance-7.0/12.5) < 0.0001)
				testing.expect(t, abs(rl.Vector3Length(far_camera.position-camera.target)/base_distance-24.0/12.5) < 0.0001)
			}
		}
	}
}

@(test)
test_large_arena_culling_keeps_projected_geometry_and_grid_picking :: proc(t: ^testing.T) {
	renderer := new(Renderer)
	defer free(renderer)
	renderer.canvas_width, renderer.canvas_height = 960, 540
	renderer.tactical.scene_3d = true
	for perspective in ([2]bool{false, true}) {
		for target in ([3]rl.Vector3{{3.5, 0, 3.5}, {22.5, 0, 15.5}, {41.5, 0, 27.5}}) {
			for step in 0..<8 {
				orbit := Tactical_Orbit{yaw = f32(step)*math.PI/4, pitch = 0.68, distance = 12.5}
				camera := tactical_orbit_camera(orbit, target, perspective)
				renderer.tactical.camera = camera
				renderer.tactical.draw_frustum = tactical_draw_frustum(camera, 960, 540)
				accepted := 0
				for y in 0..<31 { for x in 0..<45 {
					cell := grid.Position{x, y}
					visible := tactical_cell_on_screen(renderer, cell)
					if visible { accepted += 1 }
					if !visible {
						// A wall's upper cap may be on screen even if its floor is
						// outside. No rejected cell may project any volume corner.
						for offset_x in ([2]f32{0, 1}) { for offset_z in ([2]f32{0, 1}) { for height in ([2]f32{-0.3, 1.8}) {
							world := rl.Vector3{f32(x)+offset_x, height, f32(y)+offset_z}
							if rl.Vector3DotProduct(world-camera.position, camera.target-camera.position) <= 0 { continue }
							point := rl.GetWorldToScreenEx(world, camera, 960, 540)
							testing.expect(t, point.x < 0 || point.x >= 960 || point.y < 0 || point.y >= 540)
						} } }
					}
					for height in ([3]f32{-0.3, 0, 1.8}) {
						world := rl.Vector3{f32(x)+0.5, height, f32(y)+0.5}
						if rl.Vector3DotProduct(world-camera.position, camera.target-camera.position) <= 0 { continue }
						point := rl.GetWorldToScreenEx(world, camera, 960, 540)
						if point.x < 0 || point.x >= 960 || point.y < 0 || point.y >= 540 { continue }
						testing.expect(t, visible)
						if height == 0 {
							ray := rl.GetScreenToWorldRayEx(point, camera, 960, 540)
							hit := ray.position-ray.direction*(ray.position.y/ray.direction.y)
							testing.expect(t, int(math.floor(hit.x)) == x && int(math.floor(hit.z)) == y)
						}
					}
				} }
				// The late arena is nearly 1,400 cells; close combat should not
				// submit that entire board just because it is cleared or fogged.
				testing.expect(t, accepted > 0 && accepted < 700)
			}
		}
	}
}

@(test)
test_large_arena_alpha_buffer_grows_without_truncating_walls_or_actors :: proc(t: ^testing.T) {
	data, made := level.create(45, 31, {kind = .Floor})
	testing.expect(t, made)
	defer level.destroy(&data)
	walls := 0
	for y in 1..<30 { for x in 1..<44 {
		if (x+y)%5 != 0 { continue }
		testing.expect(t, level.set_tile(&data, {x, y}, {kind = .Wall}))
		walls += 1
	} }
	room := game.Room{level_data = &data}
	renderer := new(Renderer)
	defer free(renderer)
	defer destroy_tactical_translucents(renderer)
	snapshot := Room_Presentation{valid = true, enemy_count = game.MAX_ENEMIES_PER_ROOM}
	snapshot.player = {visible = true, position = {22, 15}, opacity = 1}
	for &enemy, i in snapshot.enemies[:snapshot.enemy_count] {
		enemy = {visible = true, position = {f32(i+1), 5}, opacity = 1}
	}
	renderer.tactical = {enabled = true, no_fog = true, snapshot = &snapshot,
		camera = {position = {40, 30, 40}, target = {22, 0, 15}}}
	entries := collect_tactical_translucents(renderer, &room)
	testing.expect(t, walls > 128)
	testing.expect_value(t, len(entries), walls+game.MAX_ENEMIES_PER_ROOM+1)
	for i in 1..<len(entries) { testing.expect(t, entries[i-1].depth >= entries[i].depth) }
	capacity := cap(renderer.tactical.translucents.entries)
	for _ in 0..<3 {
		entries = collect_tactical_translucents(renderer, &room)
		testing.expect_value(t, len(entries), walls+game.MAX_ENEMIES_PER_ROOM+1)
		testing.expect_value(t, cap(renderer.tactical.translucents.entries), capacity)
	}
	// The hologram must draw every actor, independently of combat frustum/fog.
	entries = collect_tactical_translucents(renderer)
	testing.expect_value(t, len(entries), game.MAX_ENEMIES_PER_ROOM+1)
}

@(test)
test_large_arena_culling_never_changes_fog_or_clear_room_light :: proc(t: ^testing.T) {
	data, made := level.create(45, 31, {kind = .Floor})
	testing.expect(t, made)
	defer level.destroy(&data)
	data.player_spawn, data.has_player_spawn = {22, 15}, true
	testing.expect(t, level.set_tile(&data, data.player_spawn, {kind = .Player_Spawn}))
	testing.expect(t, level.set_tile(&data, {42, 28}, {kind = .Exit}))
	player, player_made := game.create_player({max_health = 20, attack = 2})
	testing.expect(t, player_made)
	testing.expect(t, game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
	enemies := [?]game.Enemy_Spawn{{position = {40, 25}, health = 3, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	renderer := new(Renderer)
	defer free(renderer)
	renderer^ = create(960, 540, &data)
	snapshot: Room_Presentation
	renderer.tactical = {enabled = true, scene_3d = true, perspective = true, snapshot = &snapshot}
	update_tactical_view(renderer, &room, {}, false)
	testing.expect(t, tactical_render_visible(renderer, player.position))
	testing.expect(t, !tactical_render_visible(renderer, room.exit_position))
	old_position := player.position
	player.position = {35, 22}
	update_tactical_view(renderer, &room, {}, false)
	testing.expect(t, !tactical_render_visible(renderer, old_position))
	testing.expect(t, tactical_render_visible(renderer, player.position))
	game.kill_enemy(&room, 0)
	game.finish_player_combat_command(&room)
	update_tactical_view(renderer, &room, {}, false)
	update_tactical_atmosphere(renderer, TACTICAL_CLEAR_SECONDS)
	testing.expect(t, renderer.tactical.no_fog)
	testing.expect_value(t, renderer.tactical.clear_light, f32(1))
	testing.expect(t, tactical_render_visible(renderer, room.exit_position))
	testing.expect(t, tactical_render_visible(renderer, old_position))
	// Distant terrain remains known in loot even while it is outside the view.
	testing.expect(t, !tactical_cell_on_screen(renderer, {1, 28}))
}
