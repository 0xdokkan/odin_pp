package render

import "core:math"
import "core:fmt"
import "core:testing"
import rl "vendor:raylib"
import game "../game"
import world "../expedition"
import level "../level"
import grid "../engine/grid"

@(test)
test_expedition_combat_camera_keeps_near_fighters_above_hand_and_pickable :: proc(t: ^testing.T) {
	r := new(Renderer); defer free(r)
	orbit := Tactical_Orbit{yaw = math.PI/4, pitch = .68, distance = 27.5}
	axis := rl.Vector3{math.cos(orbit.yaw), 0, math.sin(orbit.yaw)}
	target := (rl.Vector3{.5, 0, .5})+axis*1.21
	points := [?]rl.Vector3{{.5, -.15, .5}, {.5, 2.2, .5}, {6.5, -.15, 6.5}, {6.5, 2.2, 6.5}, {7.5, -.15, 6.5}, {7.5, 2.2, 6.5}}
	for dimensions in ([3]rl.Vector2{{960, 540}, {1280, 720}, {1024, 768}}) {
		r.canvas_width, r.canvas_height = dimensions.x, dimensions.y
		bounds := tactical_world_bounds(r)
		for perspective in ([2]bool{true, false}) {
			original := tactical_orbit_camera(orbit, target, perspective)
			shift := expedition_combat_frame_shift(original, dimensions.y, bounds, points[:])
			testing.expect(t, shift >= 0 && shift <= EXPEDITION_COMBAT_FRAME_LIMIT)
			camera := tactical_orbit_camera(orbit, target+axis*shift, perspective)
			testing.expect_value(t, camera.fovy, original.fovy)
			testing.expect(t, rl.Vector3Distance(camera.position-camera.target, original.position-original.target) < .0001)
			for point in points {
				screen := rl.GetWorldToScreenEx(point, camera, i32(dimensions.x), i32(dimensions.y))
				testing.expect(t, screen.y >= bounds.y+11.9 && screen.y <= bounds.y+bounds.height-11.9,
					fmt.tprintf("viewport %v perspective %v point %v screen %v shift %.4f", dimensions, perspective, point, screen, shift))
				if point.y > 0 { continue }
				floor := point; floor.y = 0
				screen = rl.GetWorldToScreenEx(floor, camera, i32(dimensions.x), i32(dimensions.y))
				ray := rl.GetScreenToWorldRayEx(screen, camera, i32(dimensions.x), i32(dimensions.y))
				hit := ray.position-ray.direction*(ray.position.y/ray.direction.y)
				// A screen-to-world round trip in 32-bit floats is off by up to ~0.0025
				// cells (a tenth of a pixel) on Windows: tighter than the float noise.
				error := rl.Vector3Distance(hit, floor)
				testing.expectf(t, error < .005, "viewport %v perspective %v point %v: the floor is picked %.5f cells away", dimensions, perspective, point, error)
			}
		}
	}
}

@(test)
test_expedition_combat_framing_is_bounded_and_exploration_is_unchanged :: proc(t: ^testing.T) {
	r := new(Renderer); defer free(r)
	s := new(Room_Presentation); defer free(s)
	r.canvas_width, r.canvas_height = 960, 540
	r.tactical.snapshot = s
	r.tactical.expedition = true
	r.tactical.perspective = true
	r.tactical.expedition_player_offset = {.2, -.1}
	s.player = {entity = game.PLAYER_ENTITY, position = {0, 0}, visible = true, health = 10}
	s.phase = .Combat; s.enemy_count = 1
	s.enemies[0] = {entity = game.enemy_entity(1), position = {8, 7}, visible = true, health = 5, archetype = .Brute}
	orbit := Tactical_Orbit{yaw = math.PI/4, pitch = .68, distance = 27.5}
	target := rl.Vector3{1.35, 0, 1.35}
	framed := expedition_combat_camera_target(r, orbit, target)
	testing.expect(t, rl.Vector3Distance(framed, target) > .5)
	testing.expect(t, rl.Vector3Distance(framed, target) <= EXPEDITION_COMBAT_FRAME_LIMIT+.0001)
	s.enemies[0].position = {1, 1}
	testing.expect_value(t, expedition_combat_camera_target(r, orbit, target), target)
	s.enemies[0].position = {8, 7}
	r.tactical.expedition_free = true
	testing.expect_value(t, expedition_combat_camera_target(r, orbit, target), target)
	r.tactical.expedition_free = false; s.phase = .Loot
	testing.expect_value(t, expedition_combat_camera_target(r, orbit, target), target)
	s.phase = .Combat; s.enemies[0].visible = false
	testing.expect_value(t, expedition_combat_camera_target(r, orbit, target), target)
	s.enemies[0].visible = true; s.enemies[0].health = 0
	testing.expect_value(t, expedition_combat_camera_target(r, orbit, target), target)
	s.enemies[0].health = 5; s.enemies[0].position = {100, 100}
	testing.expect_value(t, expedition_combat_camera_target(r, orbit, target), target)
	// An encounter wider than the fixed view may not fit, but the robot must
	// remain between HUD and hand and the camera may not chase a distant foe.
	points := [?]rl.Vector3{{.5, -.15, .5}, {.5, 2.2, .5}, {40, 0, 40}, {-40, 2.2, -40}}
	camera := tactical_orbit_camera(orbit, target, true)
	shift := expedition_combat_frame_shift(camera, 540, tactical_world_bounds(r), points[:])
	testing.expect(t, !math.is_nan(shift) && abs(shift) <= EXPEDITION_COMBAT_FRAME_LIMIT)
	axis := rl.Vector3{math.cos(orbit.yaw), 0, math.sin(orbit.yaw)}
	camera = tactical_orbit_camera(orbit, target+axis*shift, true)
	for point in points[:2] {
		screen := rl.GetWorldToScreenEx(point, camera, 960, 540)
		bounds := tactical_world_bounds(r)
		testing.expect(t, screen.y >= bounds.y+11.9 && screen.y <= bounds.y+bounds.height-11.9)
	}
}

@(test)
test_an_expedition_camera_jump_takes_the_new_floor_at_once :: proc(t: ^testing.T) {
	// On a board with layers the camera eases to a new floor, a part of the way at each update; a jump (a new map, a
	// robot set down elsewhere, as the smoke does) takes the floor's height at once (Fase 7 of docs/piano-profondita.md).
	w := new(world.World); defer free(w)
	data: level.Level
	testing.expect(t, world.generate(w, &data, .Cyber, 0xC0FFEE)); defer level.destroy(&data)
	player, made := game.create_player({max_health = 32, attack = 2, defense = 1})
	testing.expect(t, made)
	room, ready := game.create_room(&data, &player, {room_seed = 0xC0FFEE})
	testing.expect(t, ready); defer game.destroy_room(&room)
	testing.expect(t, game.configure_expedition_combat(&room))
	game.end_expedition_encounter(&room)
	world.prepare_room(w, &room)
	r := new(Renderer); defer free(r)
	r^ = create(960, 540)
	s := new(Room_Presentation); defer free(s)
	r.tactical.snapshot = s
	r.tactical.perspective, r.tactical.living = true, true
	r.tactical.flipbook.loaded, r.tactical.living_assets.loaded = true, true
	set_expedition_walker(r, false, {}, {}, 0, 1.0/60)
	update_tactical_view(r, &room, {}, false)
	testing.expect(t, board_view.layered)
	start, low := player.position, r.tactical.camera_ground
	// The top of the complex's block, 14 steps up.
	top: grid.Position
	found := false
	for y in 0..<data.tiles.height {
		for x in 0..<data.tiles.width {
			p := grid.Position{x = x, y = y}
			tile, ok := level.tile_at(&data, p)
			if ok && tile.kind == .Floor && level.height_at(&data, p) >= 14 { top, found = p, true; break }
		}
		if found { break }
	}
	testing.expect(t, found)
	player.position = top
	r.tactical.expedition_follow_ready = false
	update_tactical_view(r, &room, {}, false)
	high := r.tactical.camera_ground
	testing.expectf(t, abs(high-board_drawn(f32(level.height_at(&data, top)))) < .001, "set down on %v: the camera is at %.3f", top, high)
	// Walking off it, the camera eases down a part of the way.
	player.position = start
	update_tactical_view(r, &room, {}, false)
	eased := r.tactical.camera_ground
	testing.expectf(t, eased < high-.01 && eased > low+.01, "from %.3f to %.3f the camera is at %.3f", high, low, eased)
}

@(test)
test_expedition_combat_smoke_fixture_frames_and_picks_actual_fighters :: proc(t: ^testing.T) {
	// Exact default-seed Cyber fixture from campaign_smoke stage 5. Exercise
	// both normal frame updates and the capture driver's refresh-only draw.
	for refresh_only in ([2]bool{false, true}) {
		w := new(world.World); defer free(w)
		data: level.Level
		testing.expect(t, world.generate(w, &data, .Cyber, 0xC0FFEE)); defer level.destroy(&data)
		player, made := game.create_player({max_health = 32, attack = 2, defense = 1})
		testing.expect(t, made)
		room, ready := game.create_room(&data, &player, {room_seed = 0xC0FFEE})
		testing.expect(t, ready); defer game.destroy_room(&room)
		testing.expect(t, game.configure_expedition_combat(&room))
		game.end_expedition_encounter(&room)
		world.prepare_room(w, &room)
		r := new(Renderer); defer free(r)
		r^ = create(960, 540)
		s := new(Room_Presentation); defer free(s)
		r.tactical.snapshot = s
		r.tactical.perspective, r.tactical.living = true, true
		// Geometry uses the authored living-sheet dimensions; GPU textures and
		// alpha masks are unnecessary for camera and center-of-body ray tests.
		r.tactical.flipbook.loaded, r.tactical.living_assets.loaded = true, true
		set_expedition_walker(r, false, {}, {}, 0, 1.0/60)
		update_tactical_view(r, &room, {}, false)
		player.position = world.site_world(&w.sites[w.groups[0].site], {x = -4, y = 0})
		testing.expect(t, world.engage(w, &room, 0))
		testing.expect_value(t, len(room.enemies), 2)
		for _ in 0..<35 {
			r.sprite_assets.elapsed += 1.0/60
			update_tactical_atmosphere(r, 1.0/60)
			update_renderer_frame_timeline(r, 1.0/60)
			update_tactical_view(r, &room, {}, false, refresh_only)
		}
		bounds := tactical_world_bounds(r)
		nearby := 0
		for actor in s.enemies[:s.enemy_count] {
			if !actor.visible || actor.health <= 0 { continue }
			delta := actor.position-s.player.position
			testing.expect(t, delta.x*delta.x+delta.y*delta.y <= EXPEDITION_COMBAT_FRAME_RADIUS*EXPEDITION_COMBAT_FRAME_RADIUS)
			nearby += 1
			key := sprite_key_for_enemy(actor.archetype)
			quad := tactical_billboard_geometry(r, key, actor.position, true, actor.entity)
			testing.expect(t, quad.living)
			for point in quad.card_points {
				screen := rl.GetWorldToScreenEx(point, r.tactical.camera, 960, 540)
				testing.expect(t, point_in_rectangle({screen.x, screen.y}, bounds),
					fmt.tprintf("refresh %v actor %v cell %v screen %v viewport %v", refresh_only, actor.entity, actor.position, screen, bounds))
			}
			body := (quad.points[0]+quad.points[1]+quad.points[2]+quad.points[3])*.25
			mouse := rl.GetWorldToScreenEx(body, r.tactical.camera, 960, 540)
			ray := rl.GetScreenToWorldRayEx(mouse, r.tactical.camera, 960, 540)
			_, hit := tactical_billboard_hit(r, key, actor.position, ray, actor.entity)
			testing.expect(t, hit && point_in_rectangle({mouse.x, mouse.y}, bounds))
			update_tactical_view(r, &room, {mouse.x, mouse.y}, true)
			testing.expect(t, r.has_hovered_cell)
			testing.expect_value(t, r.hovered_cell, (grid.Position{x = int(actor.position.x), y = int(actor.position.y)}))
		}
		testing.expect_value(t, nearby, 2)
		for height in ([2]f32{0, 2.2}) {
			p := rl.Vector3{f32(player.position.x)+.5, height, f32(player.position.y)+.5}
			screen := rl.GetWorldToScreenEx(p, r.tactical.camera, 960, 540)
			testing.expect(t, point_in_rectangle({screen.x, screen.y}, bounds))
		}
	}
}
