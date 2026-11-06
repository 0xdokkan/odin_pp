package run

import "core:math"
import "core:mem"
import "core:testing"
import rl "vendor:raylib"
import game "../game"
import level "../level"
import render "../render"

@(test)
test_page_lab_fixture_owns_and_releases_its_room_and_camera :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	tracking.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	{
		context.allocator = mem.tracking_allocator(&tracking)
		testing.expect(t, page_lab_fixture_create(0, 540) == nil)
		testing.expect(t, page_lab_fixture_create(960, -1) == nil)
		for _ in 0..<3 {
			f := page_lab_fixture_create(960, 540)
			if !testing.expect(t, f != nil) { continue }
			testing.expect(t, f.data.tiles.width == 16 && f.data.tiles.height == 12)
			testing.expect(t, f.room.player == &f.player && f.room.level_data == &f.data)
			testing.expect(t, f.player.tactical.config.expedition && len(f.room.enemies) == 1)
			testing.expect(t, f.renderer.tactical.snapshot != nil && f.renderer.tactical.surface == nil)
			_ = page_lab_fixture_camera(f, {}, .02, false)
			_ = page_lab_fixture_camera(f, {act = .Climb, time = 2}, .02, true)
			_ = page_lab_fixture_camera(f, {}, .02, false)
			page_lab_fixture_destroy(f)
		}
	}
	// Per-thread board caches use the renderer's process allocator by design;
	// every allocation owned by this fixture is nevertheless released here.
	testing.expect_value(t, tracking.current_memory_allocated, 0)
	testing.expect_value(t, len(tracking.allocation_map), 0)
	testing.expect_value(t, len(tracking.bad_free_array), 0)
}

@(test)
test_page_lab_camera_uses_the_expedition_projection_and_orbit :: proc(t: ^testing.T) {
	f := page_lab_fixture_create(1280, 720)
	if !testing.expect(t, f != nil) { return }
	defer page_lab_fixture_destroy(f)
	camera := page_lab_fixture_camera(f, {}, 1.0/60, false)
	offset := camera.position-camera.target
	way := rl.Vector3Normalize(offset)
	testing.expect_value(t, camera.projection, rl.CameraProjection.PERSPECTIVE)
	testing.expect_value(t, camera.fovy, f32(40))
	testing.expect(t, abs(math.atan2(way.z, way.x)-render.EXPEDITION_CAMERA_YAW) < .0001)
	testing.expect(t, abs(math.asin(way.y)-render.EXPEDITION_CAMERA_PITCH) < .0001)
	testing.expect(t, abs(rl.Vector3Length(offset)-21*1.1) < .0001)
	anchor := render.page_lab_hero_anchor({})
	testing.expect_value(t, f.renderer.tactical.snapshot.player.position.x, anchor.x-.5)
	testing.expect_value(t, f.renderer.tactical.snapshot.player.position.y, anchor.z-.5)
}

@(test)
test_page_lab_first_person_reaches_the_real_eye_and_returns_to_the_board :: proc(t: ^testing.T) {
	f := page_lab_fixture_create(960, 540)
	if !testing.expect(t, f != nil) { return }
	defer page_lab_fixture_destroy(f)
	orbit := page_lab_fixture_camera(f, {}, .02, false)
	camera: rl.Camera3D
	for _ in 0..<45 { camera = page_lab_fixture_camera(f, {}, .02, true, .25, .15) }
	anchor := render.page_lab_hero_anchor({})
	testing.expect(t, game.tactical_first_person_active(&f.room))
	testing.expect_value(t, render.first_person_amount(&f.renderer), f32(1))
	testing.expect(t, rl.Vector3Distance(camera.position, anchor+rl.Vector3{0, game.FIRST_PERSON_EYE_HEIGHT, 0}) < .0001)
	testing.expect_value(t, camera.fovy, render.FIRST_PERSON_FOV)
	look := rl.Vector3Normalize(camera.target-camera.position)
	testing.expect(t, abs(math.atan2(look.z, look.x)-.25) < .0001 && abs(math.asin(look.y)-.15) < .0001)
	for _ in 0..<45 { camera = page_lab_fixture_camera(f, {}, .02, false) }
	testing.expect(t, !game.tactical_first_person_active(&f.room))
	testing.expect_value(t, render.first_person_amount(&f.renderer), f32(0))
	testing.expect(t, rl.Vector3Distance(camera.position, orbit.position) < .0001)
	testing.expect(t, rl.Vector3Distance(camera.target, orbit.target) < .0001)
	testing.expect_value(t, camera.fovy, orbit.fovy)
}

@(test)
test_page_lab_climb_eye_uses_the_same_real_surface_as_the_sheet :: proc(t: ^testing.T) {
	f := page_lab_fixture_create(960, 540)
	if !testing.expect(t, f != nil) { return }
	defer page_lab_fixture_destroy(f)
	pose := render.Page_Lab_Pose{act = .Climb, time = 2}
	camera: rl.Camera3D
	for _ in 0..<45 { camera = page_lab_fixture_camera(f, pose, .02, true) }
	anchor := render.page_lab_hero_anchor(pose)
	surface := level.surface_map(&f.data)
	ground := level.surface_height_at(&surface, anchor.x, anchor.z)*game.HEIGHT_STEP_DRAWN
	testing.expect(t, ground > 0 && abs(ground-anchor.y) < .0001)
	testing.expect(t, abs(camera.position.y-ground-game.FIRST_PERSON_EYE_HEIGHT) < .0001)
	revision := f.data.geometry_revision
	_ = page_lab_fixture_camera(f, pose, .02, true)
	testing.expect_value(t, f.data.geometry_revision, revision)
	_ = page_lab_fixture_camera(f, {}, .02, false)
	for height in f.data.heights { testing.expect_value(t, height, u8(0)) }
}
