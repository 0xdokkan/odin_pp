package render

import rl "vendor:raylib"
import gfx "../engine/gfx"
import view "../view"

// MOSTRA EFFETTO (src/effect_window.odin): the card's film is a second board,
// drawn by the game's own renderer code into the window's stage. Its renderer
// owns what it shows: the view's state, its timeline and world playback, its
// snapshot, labels and actors, its board surface (made on the stage) and the
// prints its views make the first time they need them (the rope's, the ball's,
// the AK's). What it draws with is the main renderer's: every texture, shader,
// font, mesh and model create_tactical_assets made, and the sprites, borrowed
// and never unloaded here (destroy_borrowed_renderer). The main renderer
// outlives it. A film, not a game: its view is a showcase (Tactical_View).

// The GPU handles under the borrowed renderer that are its own: made by its
// views when they first need them and freed by destroy_borrowed_renderer.
// Every other texture, shader, font, mesh or model of a Tactical_View and of
// the sprites is the main renderer's, borrowed (borrow_renderer_assets);
// effect_stage_test.odin walks them all, so that a new one is never forgotten.
BORROWED_RENDERER_OWN_HANDLES :: [?]string{
	"tactical.lasso.rope_texture",
	"tactical.lasso.ring_texture",
	"tactical.pinball.texture",
	"tactical.first_person.ak_texture",
	"tactical.first_person.tracer_texture",
	"tactical.first_person.flash_textures[0]",
	"tactical.first_person.flash_textures[1]",
}

// A renderer for a board of `canvas_width` by `canvas_height` drawn into
// `stage` (its 2x board surface's parent: end_tactical_surface binds it again).
// Headless (no window, no stage) it runs without any render target.
create_borrowed_renderer :: proc(main: ^Renderer, canvas_width, canvas_height: int, stage: rl.RenderTexture2D) -> ^Renderer {
	if main == nil || !main.tactical.enabled || canvas_width <= 0 || canvas_height <= 0 { return nil }
	m := &main.tactical
	// The living cards' prints load on the main renderer the first time a
	// board needs them (living_cards_ready): the borrowed board takes them from
	// there, and never loads a copy of its own it would not free.
	if rl.IsWindowReady() && !m.living_assets.loaded && !m.living_assets.failed { gfx.create_living_assets(&m.living_assets) }
	r := new(Renderer)
	r.projection = {tile_width = 64, tile_height = 32}
	r.camera = view.make_camera()
	r.canvas_width, r.canvas_height = f32(canvas_width), f32(canvas_height)
	// The film plays at the game's own pace, whatever the run's playback.
	r.playback_speed = 1
	v := &r.tactical
	v.enabled, v.scene_3d, v.perspective = true, m.scene_3d, m.perspective
	v.living = m.living
	v.mechanics_lab, v.mechanics_lab_menu = m.mechanics_lab, m.mechanics_lab_menu
	v.intent_display = m.intent_display
	v.showcase = true
	borrow_renderer_assets(r, main)
	v.snapshot = new(Room_Presentation)
	v.labels = new(Tactical_Label_Layout)
	v.flipbook_state = new(Flipbook_State)
	// The board's 2x surface on the stage, flat board or 3D: a flat one turns
	// 3D behind the player's eyes (sync_first_person_board finds it made).
	if stage.id != 0 {
		board_3d := v.scene_3d
		v.scene_3d = true
		create_tactical_surface(r, stage)
		v.scene_3d = board_3d
	}
	return r
}

// The main renderer's assets, as they are now (the window borrows them afresh
// at every opening: the main renderer may have made more since). A living
// card's prints the main renderer has not got (headless) are marked failed,
// so that the borrowed board never makes them itself.
borrow_renderer_assets :: proc(r, main: ^Renderer) {
	if r == nil || main == nil { return }
	v, m := &r.tactical, &main.tactical
	v.art = m.art
	v.light_shader = m.light_shader
	v.light_position_location, v.light_hologram_location, v.light_eye_location = m.light_position_location, m.light_hologram_location, m.light_eye_location
	v.light_clear_location, v.light_accents_location = m.light_clear_location, m.light_accents_location
	v.outline_shader = m.outline_shader
	v.outline_bounds_location, v.outline_texel_location, v.outline_radius_location = m.outline_bounds_location, m.outline_texel_location, m.outline_radius_location
	v.block_mesh = m.block_mesh
	v.fallback = m.fallback
	v.flipbook = m.flipbook
	v.living_assets = m.living_assets
	if !v.living_assets.loaded { v.living_assets.failed = true }
	v.attack_props = m.attack_props
	v.kit = m.kit
	v.pilgrim = m.pilgrim
	// The sprites' textures and pixels are the main renderer's; the clock is
	// the film's own.
	r.sprite_assets = main.sprite_assets
	r.sprite_assets.elapsed = 0
}

// Frees what the borrowed board made for itself, and nothing it borrowed.
destroy_borrowed_renderer :: proc(r: ^Renderer) {
	if r == nil { return }
	v := &r.tactical
	destroy_renderer_world_playback(r)
	destroy_tactical_translucents(r)
	destroy_tactical_surface(r)
	forget_attack_fx(r)
	if v.living_state != nil {
		living_tokens_free(v.living_state)
		free(v.living_state)
		v.living_state = nil
	}
	destroy_lab_sounds(r)
	destroy_ground_fx(r)
	destroy_lasso_view(r)
	destroy_fishing_view(r)
	destroy_pinball_view(r)
	destroy_first_person_view(r)
	if v.flipbook_state != nil { free(v.flipbook_state); v.flipbook_state = nil }
	if v.labels != nil { free(v.labels); v.labels = nil }
	if v.snapshot != nil { free(v.snapshot); v.snapshot = nil }
	free(r)
}
