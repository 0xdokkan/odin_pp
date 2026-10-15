package main

import "core:fmt"
import "core:os"
import app "app"
import game "game"
import render "render"

// CLI validation, headless preparation and GPU attachment. The host is created
// between prepare and attach; destroy accepts any partially initialized session.

Session_Start :: enum u8 {
	Ready,
	// A headless or self-looping smoke already ran to completion.
	Finished,
	Failed,
}

roguelike_session_new :: proc() -> ^Roguelike_Session {
	rs := new(Roguelike_Session)
	rs.options = DEFAULT_RUNTIME_OPTIONS
	rs.smoke_family = .Scattered
	rs.reward_hovered_index = -1
	rs.shop_render_state = {hovered_offer_index = -1}
	return rs
}

// Command-line options of the roguelike; exits on invalid combinations, as
// the original entry point did.
roguelike_parse_arguments :: proc(rs: ^Roguelike_Session, args: []string) {
	for argument in args {
		handled, valid := apply_runtime_option(&rs.options, argument)
		if !valid {
			fmt.eprintf("invalid option: %s\n", argument)
			os.exit(2)
		}
		if handled {
			continue
		}
		if argument == "--playtest-report" {
			rs.playtest_report = true
		} else if argument == "--smoke-playtest" {
			rs.smoke_test = true
			rs.smoke_playtest = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke" {
			rs.smoke_test = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-generation" {
			rs.smoke_test = true
			rs.smoke_generation = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-map" {
			rs.smoke_test = true
			rs.smoke_map = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-status" {
			rs.smoke_test = true
			rs.smoke_status = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-loot" {
			rs.smoke_test = true
			rs.smoke_loot = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-card" {
			rs.smoke_test = true
			rs.smoke_card = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-targeting" {
			rs.smoke_test = true
			rs.smoke_targeting = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-spatial" {
			rs.smoke_test = true
			rs.smoke_spatial = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-object" {
			rs.smoke_test = true
			rs.smoke_object = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-fire" {
			rs.smoke_test = true
			rs.smoke_fire = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-content" {
			rs.smoke_test = true
			rs.smoke_content = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-movement" {
			rs.smoke_test = true
			rs.smoke_movement = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-timeline" {
			rs.smoke_test = true
			rs.smoke_timeline = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-deck-flow" {
			rs.smoke_test = true
			rs.smoke_deck_flow = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-refocus" {
			rs.smoke_test = true
			rs.smoke_refocus = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-reward" {
			rs.smoke_test = true
			rs.smoke_reward = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-shop" {
			rs.smoke_test = true
			rs.smoke_shop = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-rest" {
			rs.smoke_test = true
			rs.smoke_rest = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-event" {
			rs.smoke_test = true
			rs.smoke_event = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-treasure" {
			rs.smoke_test = true
			rs.smoke_treasure = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-special-result" {
			rs.smoke_test = true
			rs.smoke_special_result = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-intents" {
			rs.smoke_test = true
			rs.smoke_intents = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-archetypes" {
			rs.smoke_test = true
			rs.smoke_archetypes = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-tactics" {
			rs.smoke_test = true
			rs.smoke_tactics = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-defeat" {
			rs.smoke_test = true
			rs.smoke_defeat = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-encounters" {
			rs.smoke_test = true
			rs.smoke_encounters = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-miniboss" {
			rs.smoke_test = true
			rs.smoke_miniboss = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-furnace" {
			rs.smoke_test = true
			rs.smoke_furnace = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-relics" {
			rs.smoke_test = true
			rs.smoke_relics = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-relic-combat" {
			rs.smoke_test = true
			rs.smoke_relic_combat = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-firebomb-spell" || argument == "--smoke-dice" || argument == "--smoke-dice-pool" ||
		          argument == "--smoke-chain" || argument == "--smoke-spell-preview" || argument == "--smoke-sunder-preview" ||
		          argument == "--smoke-barrage" || argument == "--smoke-twin-venom" {
			rs.smoke_test = true
			rs.smoke_mode_count += 1
			switch argument {
			case "--smoke-firebomb-spell": rs.spell_smoke = .Firebomb
			case "--smoke-dice": rs.spell_smoke = .Dice
			case "--smoke-dice-pool": rs.spell_smoke = .Dice_Pool
			case "--smoke-chain": rs.spell_smoke = .Chain
			case "--smoke-spell-preview": rs.spell_smoke = .Preview
			case "--smoke-sunder-preview": rs.spell_smoke = .Sunder_Preview
			case "--smoke-barrage": rs.spell_smoke = .Barrage
			case "--smoke-twin-venom": rs.spell_smoke = .Venom
			}
		} else if argument == "--smoke-sprites" {
			rs.smoke_test = true
			rs.smoke_sprites = true
			rs.smoke_mode_count += 1
		} else if argument == "--smoke-family=pillars" || argument == "--smoke-family=ring" ||
		          argument == "--smoke-family=courts" || argument == "--smoke-family=cover" {
			rs.smoke_test = true
			rs.smoke_mode_count += 1
			switch argument {
			case "--smoke-family=pillars": rs.smoke_family = .Pillars
			case "--smoke-family=ring": rs.smoke_family = .Ring
			case "--smoke-family=courts": rs.smoke_family = .Twin_Courts
			case "--smoke-family=cover": rs.smoke_family = .Asymmetric
			}
		} else {
			fmt.eprintf("unknown option: %s\n", argument)
			os.exit(2)
		}
	}
	if rs.options.m7_smoke { rs.smoke_mode_count += 1 }
	if rs.options.m7_view_smoke { rs.smoke_mode_count += 1 }
	if rs.options.m8_view_smoke { rs.smoke_mode_count += 1 }
	if rs.options.western_smoke { rs.smoke_mode_count += 1 }
	if rs.options.mechanics_lab_smoke { rs.smoke_mode_count += 1 }
	if rs.options.effect_window_smoke { rs.smoke_mode_count += 1 }
	if rs.options.arena_view_smoke { rs.smoke_mode_count += 1 }
	if rs.options.dice_set_smoke { rs.smoke_mode_count += 1 }
	if rs.options.m9_smoke { rs.smoke_mode_count += 1 }
	if rs.options.m9_lab != .None || rs.options.m9_smoke {
		if !rs.options.tactical.enabled || rs.options.spell_lab || rs.options.dice_set_lab || rs.options.dice_set_smoke ||
		   (rs.options.m9_lab != .None && rs.smoke_mode_count > 0) || rs.playtest_report || len(rs.options.playtest_output) > 0 {
			fmt.eprintln("M9 labs require tactical assets and cannot be combined with other labs, reports or smoke modes")
			os.exit(2)
		}
	}
	if (rs.options.dice_set_lab || rs.options.dice_set_smoke) &&
	   (!rs.options.tactical.enabled || rs.options.spell_lab || (rs.options.dice_set_lab && rs.smoke_mode_count > 0)) {
		fmt.eprintln("dice set lab requires tactical mode and cannot be combined with another lab or smoke")
		os.exit(2)
	}
	if rs.options.mechanics_lab && (!rs.options.tactical.enabled || rs.options.spell_lab || rs.options.dice_set_lab ||
	   rs.options.m9_lab != .None || rs.smoke_mode_count > 0 || rs.playtest_report) {
		fmt.eprintln("the mechanics lab requires tactical mode and cannot be combined with another lab, report or smoke")
		os.exit(2)
	}
	if (rs.options.m7_view_smoke || rs.options.m8_view_smoke || rs.options.arena_view_smoke || rs.options.western_smoke ||
	    rs.options.mechanics_lab_smoke || rs.options.effect_window_smoke) && !rs.options.tactical.enabled {
		fmt.eprintln("tactical view smoke requires tactical mode; omit --classic")
		os.exit(2)
	}
	if rs.smoke_mode_count > 1 {
		fmt.eprintln("choose exactly one --smoke* mode")
		os.exit(2)
	}
	if len(rs.options.playtest_output) > 0 && !rs.smoke_playtest {
		rs.playtest_report = true
	}
	if rs.playtest_report && rs.smoke_test {
		fmt.eprintln("--playtest-report is interactive; use --smoke-playtest for headless telemetry")
		os.exit(2)
	}
	if rs.options.spell_lab && (rs.smoke_test || rs.playtest_report) {
		fmt.eprintln("--spell-lab is a standalone practice arena; run it without smoke or report options")
		os.exit(2)
	}

}

// Smoke, lab and report modes run the roguelike directly, without the menu.
roguelike_requires_direct_start :: proc(rs: ^Roguelike_Session) -> bool {
	return rs.smoke_mode_count > 0 || rs.options.spell_lab || rs.options.dice_set_lab ||
	       rs.options.m9_lab != .None || rs.playtest_report || rs.options.mechanics_lab
}

// Labs and captures never read or write persistent progression.
roguelike_profile_enabled :: proc(rs: ^Roguelike_Session) -> bool {
	return rs.smoke_mode_count == 0 && !rs.smoke_test && !rs.options.spell_lab && !rs.options.mechanics_lab &&
	       !rs.options.dice_set_lab && !rs.options.dice_set_smoke &&
	       rs.options.m9_lab == .None && !rs.options.m9_smoke
}

roguelike_prepare :: proc(rs: ^Roguelike_Session) -> Session_Start {
	rs.procedural_rooms = (!rs.smoke_test && !rs.options.spell_lab && !rs.options.mechanics_lab) || rs.smoke_generation || rs.smoke_family != .Scattered || rs.smoke_relics


	rs.run_seed = rs.options.seed
	// MOSTRA EFFETTO's smoke goes from the first room to a shop as well.
	if rs.smoke_shop || rs.smoke_rest || rs.smoke_event || rs.smoke_treasure || rs.smoke_special_result || rs.options.effect_window_smoke {
		desired_kind := game.Node_Kind.Shop
		if rs.smoke_rest {
			desired_kind = .Rest
		} else if rs.smoke_event {
			desired_kind = .Event
		} else if rs.smoke_treasure || rs.smoke_special_result {
			desired_kind = .Treasure
		}
		found_seed: bool
		rs.run_seed, found_seed = demo_seed_with_first_special(rs.run_seed, desired_kind)
		if !found_seed {
			return .Failed}
	}
	if rs.smoke_family != .Scattered {
		selected, found := demo_seed_with_room_family(rs.run_seed, rs.smoke_family)
		if !found { fmt.eprintln("could not find a room-family smoke seed"); return .Failed}
		rs.run_seed = selected
	}
	run_ok: bool
	rs.run_state, run_ok = game.create_run(DEMO_PLAYER_STATS, DEMO_RUN_CONFIG, rs.run_seed,
		(!rs.smoke_test && !rs.options.spell_lab && !rs.options.mechanics_lab) || rs.smoke_relics)
	if !run_ok {
		return .Failed}
	rs.run_created = true
	if roguelike_profile_enabled(rs) {
		rs.run_state.player.m8_profile, rs.m8_session.save_enabled = load_m8_profile(M8_PROFILE_PATH)
		if !rs.m8_session.save_enabled { fmt.eprintln("Profilo M8 non leggibile: file preservato, salvataggio disabilitato.") }
	}
	if rs.smoke_test || rs.options.spell_lab { rs.options.tactical.enabled = false; rs.options.scene_3d = false }
	if rs.options.tactical.enabled && !configure_demo_tactical_player(&rs.run_state.player, rs.options.tactical) { return .Failed}
	if !replace_current_demo_room(&rs.level_data, &rs.run_state, &rs.room, rs.procedural_rooms) {
		return .Failed}
	rs.room_created = true
	if rs.options.spell_lab && !prepare_spell_lab(&rs.room, rs.options.dice_lab) { fmt.eprintln("could not prepare card practice"); return .Failed}
	if rs.options.mechanics_lab && !prepare_mechanics_lab(rs) { fmt.eprintln("could not prepare the mechanics lab"); return .Failed}
	if rs.smoke_playtest {
		if !run_headless_playtest_smoke(&rs.run_state, &rs.room, rs.run_seed, rs.options.playtest_output) {
			fmt.eprintln("failed to write headless playtest report")
			os.exit(2)
		}
		fmt.println("wrote headless playtest report")
		return .Finished
	}

	if rs.options.m7_smoke {
		if !run_m7_headless_smoke() { os.exit(2) }
		return .Finished
	}
	if rs.smoke_test || rs.options.spell_lab { rs.options.tactical.enabled = false; rs.options.scene_3d = false }
	// The mechanics lab configured its own fogless arena.
	if rs.options.tactical.enabled && !rs.options.mechanics_lab {
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
		pixel_art = rs.options.tactical.enabled,
	}
}

roguelike_attach :: proc(rs: ^Roguelike_Session, window: ^app.Window) -> Session_Start {
	rs.window = window
	rs.attached = true
	if !render.create_dice_renderer(&rs.dice_renderer) { fmt.eprintln("3D dice unavailable; using 2D die") }
	rs.playtest_report_written = false
	if rs.playtest_report && !game.run_has_relic_choice(&rs.run_state) {
		if !begin_playtest_run(&rs.playtest_session, rs.run_seed, &rs.run_state, &rs.room) {
			fmt.eprintln("failed to start playtest telemetry")
			return .Failed
		}
		rs.playtest_session_ptr = &rs.playtest_session
	}

	rs.iso_renderer = render.create(rs.window.config.canvas_width, rs.window.config.canvas_height, &rs.level_data)
	rs.iso_renderer.tactical.enabled = rs.options.tactical.enabled
	rs.iso_renderer.tactical.scene_3d = rs.options.scene_3d
	rs.iso_renderer.tactical.perspective = rs.options.perspective
	if rs.options.tactical.enabled { render.create_tactical_assets(&rs.iso_renderer, rs.window.canvas) }
	if rs.options.tactical.enabled { rs.dice_renderer.theme = &rs.iso_renderer }
	if rs.options.m7_view_smoke {
		game.skip_run_relic(&rs.run_state)
		if !prepare_m7_view_room(&rs.level_data, &rs.run_state, &rs.room) { fmt.eprintln("M7 view setup failed"); os.exit(2) }
	}
	sprite_manifest := rs.options.sprite_manifest
	if len(sprite_manifest) == 0 { sprite_manifest = "assets/sprites.json" }
	sprite_report := render.load_sprite_assets(&rs.iso_renderer.sprite_assets, sprite_manifest)
	rs.sprites_loaded = true
	if sprite_report.rejected > 0 || (sprite_report.manifest_found && len(sprite_report.message) > 0) ||
	   (len(rs.options.sprite_manifest) > 0 && !sprite_report.manifest_found) {
		fmt.eprintf("Sprites: %s (%d loaded, %d rejected); using built-in graphics where needed.\n",
			sprite_report.message, sprite_report.loaded, sprite_report.rejected)
	}
	if !rs.smoke_test {
		render.set_renderer_playback_speed(&rs.iso_renderer, rs.options.animation_speed)
	}
	rs.show_route_map = false
	rs.reward_hovered_index = -1
	rs.reward_skip_hovered = false
	rs.shop_render_state = render.Shop_Render_State{hovered_offer_index = -1}
	rs.smoke_frame_count = 0
	return roguelike_attach_smoke(rs)
}
