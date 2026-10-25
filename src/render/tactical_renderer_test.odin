package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"
import game "../game"
import grid "../engine/grid"
import level "../level"

@(test)
test_tactical_visibility_uses_presented_snapshot_and_matches_game :: proc(t: ^testing.T) {
	rows := [?]string{"#######", "#@....#", "#..>..#", "#.....#", "#######"}
	data, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	defer level.destroy(&data)
	player, ok := game.create_player({max_health = 20, attack = 2})
	testing.expect(t, ok)
	testing.expect(t, game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
	enemies := [?]game.Enemy_Spawn{{position = {x = 4, y = 3}, health = 8, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	renderer := new_clone(create(960, 540))
	defer free(renderer)
	snapshot: Room_Presentation
	renderer.tactical = {snapshot = &snapshot}
	for size in ([?]int{2, 3, 5, 7, 9}) {
		player.tactical.config.vision_size = size
		update_tactical_view(renderer, &room, {}, false)
		for y in 0..<data.tiles.height {
			for x in 0..<data.tiles.width {
				cell := grid.Position{x = x, y = y}
				testing.expect_value(t, tactical_render_visible(renderer, cell), game.tactical_cell_visible(&room, cell))
			}
		}
	}
	player.tactical.config.vision_size = 3
	update_tactical_view(renderer, &room, {}, false)
	renderer.timeline.view = snapshot
	renderer.timeline.count = 1
	renderer.timeline.cues[0] = {kind = .Move, duration = 1}
	player.position = {x = 5, y = 3}
	update_tactical_view(renderer, &room, {}, false)
	testing.expect(t, tactical_render_visible(renderer, {x = 1, y = 1}))
	testing.expect(t, !tactical_render_visible(renderer, {x = 5, y = 3}))
	renderer.timeline.count = 0
	update_tactical_view(renderer, &room, {}, false)
	testing.expect(t, !tactical_render_visible(renderer, {x = 1, y = 1}))
	testing.expect(t, tactical_render_visible(renderer, {x = 5, y = 3}))
}

@(test)
test_tactical_orbit_clamps_and_keeps_rotated_grid_pickable :: proc(t: ^testing.T) {
	orbit: Tactical_Orbit
	adjust_tactical_orbit(&orbit, {10000, 10000}, 1000)
	testing.expect_value(t, orbit.pitch, f32(1.45))
	testing.expect_value(t, orbit.distance, f32(7))
	adjust_tactical_orbit(&orbit, {-170, -10000}, -1000)
	testing.expect_value(t, orbit.pitch, f32(0.3))
	testing.expect_value(t, orbit.distance, f32(24))
	for mode in 0..<2 {
		for step in 0..<8 {
			orbit.yaw, orbit.pitch, orbit.distance = f32(step)*math.PI/4, 0.8, 12.5
			camera := tactical_orbit_camera(orbit, {4.5, 0, 4.5}, mode == 0)
			point := rl.GetWorldToScreenEx({3.5, 0, 5.5}, camera, 960, 540)
			ray := rl.GetScreenToWorldRayEx(point, camera, 960, 540)
			hit := ray.position-ray.direction*(ray.position.y/ray.direction.y)
			testing.expect(t, abs(hit.x-3.5) < 0.001 && abs(hit.z-5.5) < 0.001)
		}
	}
}

@(test)
test_tactical_camera_grid_round_trip_orthographic_and_perspective :: proc(t: ^testing.T) {
	renderer := new(Renderer)
	defer free(renderer)
	renderer.canvas_width, renderer.canvas_height = 960, 540

	for mode in 0..<2 {
		renderer.tactical.camera = {position = {10, 9, 10}, target = {3, 0, 3}, up = {0, 1, 0},
			fovy = (f32(38) if mode == 1 else 7), projection = (.PERSPECTIVE if mode == 1 else .ORTHOGRAPHIC)}
		for y in 1..=4 {
			for x in 1..=4 {
				point := tactical_project(renderer, {f32(x)+0.5, f32(y)+0.5})
				ray := rl.GetScreenToWorldRayEx({point.x, point.y}, renderer.tactical.camera, 960, 540)
				hit := ray.position-ray.direction*(ray.position.y/ray.direction.y)
				testing.expect_value(t, int(math.floor(hit.x)), x)
				testing.expect_value(t, int(math.floor(hit.z)), y)
			}
		}
	}
}

@(test)
test_tactical_billboard_picker_obeys_texture_alpha_and_custom_anchor :: proc(t: ^testing.T) {
	renderer := new(Renderer)
	defer free(renderer)
	renderer.tactical.camera = {position = {9, 8, 9}, target = {2, 0, 2}, up = {0, 1, 0}, fovy = 7}
	alpha := [1]u8{0}
	renderer.sprite_assets.texture_count = 1
	renderer.sprite_assets.textures[0] = {texture = {width = 1, height = 1}, alpha = alpha[:]}
	renderer.sprite_assets.sprites[int(Sprite_Key.Player)] = {configured = true, columns = 1, frames = 1,
		frame_width = 1, frame_height = 1, width = 64, height = 80, anchor = {0.2, 0.8}}
	quad := tactical_billboard_geometry(renderer, .Player, {2, 2})
	center := (quad.points[0]+quad.points[2])*0.5
	front := rl.Vector3Normalize(rl.Vector3{1, 0, 1})
	ray := rl.Ray{center+front*10, -front}
	_, hit := tactical_billboard_hit(renderer, .Player, {2, 2}, ray)
	testing.expect(t, !hit)
	alpha[0] = 255
	distance, visible := tactical_billboard_hit(renderer, .Player, {2, 2}, ray)
	testing.expect(t, visible && abs(distance-10) < 0.001)
}

@(test)
test_tactical_billboard_uses_player_event_clip_frame :: proc(t: ^testing.T) {
	renderer := new(Renderer)
	defer free(renderer)
	renderer.tactical.camera = {position = {9, 8, 9}, target = {2, 0, 2}, up = {0, 1, 0}, fovy = 7}
	renderer.sprite_assets.texture_count = 1
	renderer.sprite_assets.textures[0].texture = {width = 4, height = 1}
	renderer.sprite_assets.sprites[int(Sprite_Key.Player_Cast)] = {configured = true, columns = 4, frames = 4,
		frame_width = 1, frame_height = 1, width = 64, height = 80, anchor = {0.5, 1}}
	renderer.timeline.count = 1
	renderer.timeline.cues[0] = {kind = .Card_Played, started = true, elapsed = 0.5, duration = 1}
	quad := tactical_billboard_geometry(renderer, .Player, {2, 2})
	testing.expect_value(t, quad.key, Sprite_Key.Player_Cast)
	testing.expect_value(t, quad.source.x, f32(2))
	renderer.timeline.count = 0
	quad = tactical_billboard_geometry(renderer, .Player, {2, 2})
	testing.expect_value(t, quad.key, Sprite_Key.Player)
}

@(test)
test_tactical_simultaneous_cues_filter_each_hidden_target :: proc(t: ^testing.T) {
	renderer := new(Renderer)
	defer free(renderer)
	snapshot := Room_Presentation{valid = true, enemy_count = 2}
	snapshot.enemies[0] = {entity = game.enemy_entity(1), position = {2, 2}, visible = true}
	snapshot.enemies[1] = {entity = game.enemy_entity(2), position = {6, 6}, visible = true}
	renderer.tactical = {snapshot = &snapshot, visible_count = 1}
	renderer.tactical.visible[0] = {x = 2, y = 2}
	visible := Presentation_Cue{kind = .Damage, event = {target = game.enemy_entity(1)}}
	hidden := Presentation_Cue{kind = .Damage, event = {target = game.enemy_entity(2)}}
	testing.expect(t, tactical_cue_visible(renderer, &visible))
	testing.expect(t, !tactical_cue_visible(renderer, &hidden))
}

@(test)
test_tactical_voxel_props_are_pickable_after_orbit_but_not_through_fog :: proc(t: ^testing.T) {
	renderer := new(Renderer)
	defer free(renderer)
	renderer.canvas_width, renderer.canvas_height = 960, 540
	snapshot := Room_Presentation{valid = true, object_count = 1}
	snapshot.objects[0] = {position = {3, 3}, visible = true}
	renderer.tactical = {snapshot = &snapshot, visible_count = 1}
	renderer.tactical.visible[0] = {x = 3, y = 3}
	for kind in ([?]game.Grid_Object_Kind{.Ice_Block, .Barrel, .Bomb, .Fire}) {
		snapshot.objects[0].kind = kind
		for perspective in ([?]bool{false, true}) {
			for step in 0..<8 {
				orbit := Tactical_Orbit{yaw = f32(step)*math.PI/4, pitch = 0.8, distance = 12.5}
				renderer.tactical.camera = tactical_orbit_camera(orbit, {3.5, 0, 3.5}, perspective)
				point := rl.GetWorldToScreenEx({3.5, 0.2, 3.5}, renderer.tactical.camera, 960, 540)
				for visible in ([?]bool{true, false}) {
					renderer.tactical.visible_count = 1 if visible else 0
					renderer.has_hovered_cell = false
					update_tactical_body_hover(renderer, {point.x, point.y})
					testing.expect_value(t, renderer.has_hovered_cell, visible)
					if visible { testing.expect_value(t, renderer.hovered_cell, grid.Position{x = 3, y = 3}) }
				}
			}
		}
	}
}
