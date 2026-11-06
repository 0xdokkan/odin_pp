package run

import "core:math"
import rl "vendor:raylib"
import game "../game"
import level "../level"
import render "../render"

// An owned, ordinary room for the visual workshop's real camera. It never
// advances enemy combat or saves progress; its first-person effect uses the
// existing game's entry, timer and view. No textures or GPU handles are made.
@(private)
Page_Lab_Fixture :: struct {
	data: level.Level,
	player: game.Player,
	room: game.Room,
	renderer: render.Renderer,
	climb: bool,
}

// width/height are canvas pixels. The authored sample itself is always 16x12.
@(private)
page_lab_fixture_create :: proc(width, height: int) -> ^Page_Lab_Fixture {
	if width <= 0 || height <= 0 { return nil }
	f := new(Page_Lab_Fixture)
	ready := false
	defer { if !ready { page_lab_fixture_destroy(f) } }
	created: bool
	f.data, created = level.create(16, 12, {kind = .Floor})
	if !created { return nil }
	f.data.player_spawn = {x = 6, y = 5}
	f.data.has_player_spawn = true
	if !level.set_tile(&f.data, {x = 14, y = 10}, {kind = .Exit}) { return nil }
	f.player, created = game.create_player({max_health = 100, attack = 5, defense = 0})
	if !created { return nil }
	foes := [1]game.Enemy_Spawn{{position = {x = int(render.PAGE_LAB_ENEMY_ORIGIN.x), y = int(render.PAGE_LAB_ENEMY_ORIGIN.z)}, health = 20, attack = 1}}
	f.room, created = game.create_room(&f.data, &f.player, {enemies = foes[:], room_seed = 42})
	if !created || !game.configure_expedition_combat(&f.room) { return nil }
	f.renderer = render.create(width, height)
	f.renderer.tactical.snapshot = new(render.Room_Presentation)
	f.renderer.tactical.perspective = true
	ready = true
	return f
}

@(private)
page_lab_fixture_destroy :: proc(f: ^Page_Lab_Fixture) {
	if f == nil { return }
	// The camera path normally creates no playback; release it explicitly so
	// adding a real presentation cue to the fixture cannot leak its storage.
	render.destroy_renderer_world_playback(&f.renderer)
	if f.renderer.tactical.snapshot != nil { free(f.renderer.tactical.snapshot) }
	game.destroy_room(&f.room)
	level.destroy(&f.data)
	free(f)
}

@(private = "file")
page_lab_fixture_ground :: proc(f: ^Page_Lab_Fixture, climb: bool) {
	if climb == f.climb { return }
	for y in 0..<f.data.tiles.height {
		for x in 0..<f.data.tiles.width {
			// Real terrain: cell centres carry steps, and level.surface_height_at
			// interpolates them. Across the sample this is exactly
			// clamp(world_x-4.5, 0, 5)*HEIGHT_STEP_DRAWN, the sheet's Climb.
			height := clamp(x-4, 0, 5) if climb else 0
			changed := level.set_height(&f.data, {x = x, y = y}, i32(height))
			assert(changed, "the page laboratory's height fixture must be in bounds")
		}
	}
	f.climb = climb
}

@(private)
page_lab_fixture_camera :: proc(f: ^Page_Lab_Fixture, pose: render.Page_Lab_Pose, dt: f32,
	first_person: bool, yaw: f32 = -1.5707963, pitch: f32 = 0) -> rl.Camera3D {
	if f == nil { return {} }
	page_lab_fixture_ground(f, pose.act == .Climb)
	anchor := render.page_lab_hero_anchor(pose)
	f.player.position = {x = int(math.floor(anchor.x)), y = int(math.floor(anchor.z))}
	seconds := dt if dt > 0 && !math.is_nan(dt) && !math.is_inf(dt) else 0
	// The inspector can remain open across more than one ordinary effect. On
	// expiry its requested view starts another instance, using the real duration.
	if game.tactical_first_person_active(&f.room) {
		game.tactical_first_person_tick(&f.room, seconds if first_person else f.room.first_person.remaining)
	}
	if first_person && !game.tactical_first_person_active(&f.room) {
		began := game.tactical_begin_first_person(&f.room, f32(game.FIRST_PERSON_SECONDS))
		assert(began, "the isolated page fixture must permit its first-person effect")
	}
	r := &f.renderer
	render.advance_sprite_assets(&r.sprite_assets, seconds)
	_ = render.update_renderer_frame_timeline(r, seconds)
	render.set_expedition_walker(r, true, {anchor.x-.5, anchor.z-.5}, {}, 0, seconds)
	render.update_tactical_view(r, &f.room, {}, false)
	if first_person {
		// Entry first aligns the real view to a grid direction. Apply the
		// inspector's absolute look through the normal view's clamped turn API,
		// then refresh without advancing time or the follow camera twice.
		render.turn_first_person_view(r, yaw-r.tactical.first_person.yaw, pitch-r.tactical.first_person.pitch)
		render.update_tactical_view(r, &f.room, {}, false, true)
	}
	return r.tactical.camera
}
