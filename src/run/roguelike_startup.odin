package run

import "core:fmt"
import app "../engine/app"
import game "../game"
import render "../render"

// Session preparation and GPU attachment. The host is created
// between prepare and attach; destroy accepts any partially initialized session.

Session_Start :: enum u8 {
	Ready,
	// A headless or self-looping smoke already ran to completion.
	Finished,
	Failed,
}

roguelike_session_new :: proc(options: Options = DEFAULT_OPTIONS) -> ^Roguelike_Session {
	rs := new(Roguelike_Session)
	rs.options = options
	rs.actions = default_run_actions()
	rs.reward_hovered_index = -1
	rs.shop_render_state = {hovered_offer_index = -1}
	return rs
}

roguelike_prepare :: proc(rs: ^Roguelike_Session, configure_room: bool = true) -> Session_Start {
	rs.procedural_rooms = rs.options.procedural_rooms && !rs.options.spell_lab && !rs.options.mechanics_lab
	rs.run_seed = rs.options.seed
	run_ok: bool
	rs.run_state, run_ok = game.create_run(DEMO_PLAYER_STATS, DEMO_RUN_CONFIG, rs.run_seed,
		rs.options.procedural_rooms && !rs.options.spell_lab && !rs.options.mechanics_lab)
	if !run_ok {
		return .Failed}
	rs.run_created = true
	if roguelike_profile_enabled(rs) {
		rs.run_state.player.m8_profile, rs.player_activities.save_enabled = load_m8_profile(M8_PROFILE_PATH)
		if !rs.player_activities.save_enabled { fmt.eprintln("Profilo M8 non leggibile: file preservato, salvataggio disabilitato.") }
	}
	if !configure_demo_tactical_player(&rs.run_state.player, rs.options.tactical) { return .Failed}
	if !replace_current_demo_room(&rs.level_data, &rs.run_state, &rs.room, rs.procedural_rooms) {
		return .Failed}
	rs.room_created = true
	if rs.options.spell_lab && !prepare_spell_lab(&rs.room, rs.options.dice_lab) { fmt.eprintln("could not prepare card practice"); return .Failed}
	if rs.options.mechanics_lab && !prepare_mechanics_lab(rs) { fmt.eprintln("could not prepare the mechanics lab"); return .Failed}
	// Practice labs configure their own fogless arenas.
	if configure_room && !rs.options.mechanics_lab && !rs.options.spell_lab {
		configured := game.configure_tactical_room(&rs.room, rs.options.tactical)
		assert(configured)
	}

	return .Ready
}

roguelike_window_config :: proc(rs: ^Roguelike_Session) -> app.Window_Config {
	return app.Window_Config{
		title = "Odin PP 0.5 / M9",
		initial_width = 1280,
		initial_height = 720,
		canvas_width = 960,
		canvas_height = 540,
		minimum_window_width = 640,
		minimum_window_height = 360,
		target_fps = 60,
		initial_scale_mode = .Fit,
		pixel_art = true,
	}
}

roguelike_attach :: proc(rs: ^Roguelike_Session, window: ^app.Window) -> Session_Start {
	rs.window = window
	rs.attached = true
	if !render.create_dice_renderer(&rs.dice_renderer) { fmt.eprintln("3D dice unavailable; using 2D die") }
	rs.playtest_report_written = false
	if rs.options.playtest_report && !game.run_has_relic_choice(&rs.run_state) {
		if !begin_playtest_run(&rs.playtest_session, rs.run_seed, &rs.run_state, &rs.room) {
			fmt.eprintln("failed to start playtest telemetry")
			return .Failed
		}
		rs.playtest_session_ptr = &rs.playtest_session
	}

	rs.iso_renderer = render.create(rs.window.config.canvas_width, rs.window.config.canvas_height)
	rs.iso_renderer.tactical.perspective = rs.options.perspective
	render.create_tactical_assets(&rs.iso_renderer, rs.window.canvas)
	rs.dice_renderer.theme = &rs.iso_renderer
	sprite_manifest := rs.options.sprite_manifest
	if len(sprite_manifest) == 0 { sprite_manifest = "assets/sprites.json" }
	sprite_report := render.load_sprite_assets(&rs.iso_renderer.sprite_assets, sprite_manifest)
	rs.sprites_loaded = true
	if sprite_report.rejected > 0 || (sprite_report.manifest_found && len(sprite_report.message) > 0) ||
	   (len(rs.options.sprite_manifest) > 0 && !sprite_report.manifest_found) {
		fmt.eprintf("Sprites: %s (%d loaded, %d rejected); using built-in graphics where needed.\n",
			sprite_report.message, sprite_report.loaded, sprite_report.rejected)
	}
	render.set_renderer_playback_speed(&rs.iso_renderer, rs.options.animation_speed)
	rs.show_route_map = false
	rs.reward_hovered_index = -1
	rs.reward_skip_hovered = false
	rs.shop_render_state = render.Shop_Render_State{hovered_offer_index = -1}
	return .Ready
}

roguelike_profile_enabled :: proc(rs: ^Roguelike_Session) -> bool {
	return rs.options.persist_profile && !rs.options.spell_lab && !rs.options.mechanics_lab
}
