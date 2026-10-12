package main

import "core:fmt"
import "core:os"
import rl "vendor:raylib"
import app "app"
import audio "engine/audio"
import combatdebug "combatdebug"
import host "engine/host"
import ui "engine/ui"
import game "game"
import level "level"
import render "render"
import view "view"

// The roguelike run as a host scene. Everything `main` used to keep in locals
// lives here on the heap: Room, the renderer and the reports they embed reserve
// hundreds of KiB, which overflowed Windows' 1 MiB main-thread stack.
// Setup is split around the window: `roguelike_prepare` builds the run and
// handles headless smokes, `roguelike_attach` creates GPU resources.
Roguelike_Session :: struct {
	window:                  ^app.Window,
	options:                 Runtime_Options,
	playtest_report:         bool,
	smoke_test:              bool,
	smoke_playtest:          bool,
	smoke_generation:        bool,
	smoke_map:               bool,
	smoke_status:            bool,
	smoke_loot:              bool,
	smoke_card:              bool,
	smoke_targeting:         bool,
	smoke_spatial:           bool,
	smoke_object:            bool,
	smoke_fire:              bool,
	smoke_content:           bool,
	smoke_movement:          bool,
	smoke_timeline:          bool,
	smoke_deck_flow:         bool,
	smoke_refocus:           bool,
	smoke_reward:            bool,
	smoke_shop:              bool,
	smoke_rest:              bool,
	smoke_event:             bool,
	smoke_treasure:          bool,
	smoke_special_result:    bool,
	smoke_intents:           bool,
	smoke_archetypes:        bool,
	smoke_tactics:           bool,
	smoke_encounters:        bool,
	smoke_miniboss:          bool,
	smoke_furnace:           bool,
	smoke_relics:            bool,
	smoke_relic_combat:      bool,
	smoke_sprites:           bool,
	spell_smoke:             Spell_Smoke,
	smoke_family:            level.Room_Family,
	smoke_defeat:            bool,
	smoke_mode_count:        int,
	procedural_rooms:        bool,
	level_data:              level.Level,
	run_seed:                u64,
	run_state:               game.Run_State,
	m8_session:              M8_Session,
	room:                    game.Room,
	dice_renderer:           render.Dice_Renderer,
	playtest_session:        combatdebug.Playtest_Session,
	playtest_session_ptr:    ^combatdebug.Playtest_Session,
	playtest_report_written: bool,
	iso_renderer:            render.Renderer,
	tactical_controller:     Tactical_Controller,
	m7_view_state:           M7_View_Smoke,
	show_route_map:          bool,
	card_interaction:        Card_Interaction_State,
	gameplay_buffer:         Buffered_Gameplay_Command,
	beat_chord:              Beat_Chord,
	reward_hovered_index:    int,
	reward_skip_hovered:     bool,
	shop_render_state:       render.Shop_Render_State,
	special_render_state:    render.Special_Node_Render_State,
	smoke_frame_count:       int,
	smoke_fire_entity:       game.Entity_Ref,

	// Which resources exist, so destroy mirrors the old deferred cleanup.
	run_created:             bool,
	room_created:            bool,
	attached:                bool,
	sprites_loaded:          bool,

	// Values computed by update and consumed by draw in the same frame.
	frame_time:              f32,
	m8_modal:                bool,
	mouse_canvas:            view.Vec2,
	mouse_inside:            bool,
	defeat_restart_hovered:  bool,
	timeline_busy:           bool,
	defeat_visible:          bool,
	reward_visible:          bool,
	shop_visible:            bool,
	special_visible:         bool,
	route_visible:           bool,
	hovered_node:            game.Node_Id,
	shop_button_hovered:     bool,
	relic_hovered:           int,
	relic_skip_hovered:      bool,
	overlay:                 app.Window_Overlay,
	overlay_data:            Dice_Window_Overlay,

	// Launched from the menu: F10 returns there instead of quitting.
	from_launcher:           bool,

	// Minigame challenge feedback shown after returning to the run.
	challenge_message:       string,
	challenge_message_ttl:   f32,
}

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
	if (rs.options.m7_view_smoke || rs.options.m8_view_smoke || rs.options.arena_view_smoke || rs.options.western_smoke) && !rs.options.tactical.enabled {
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
	       rs.options.m9_lab != .None || rs.playtest_report
}

// Labs and captures never read or write persistent progression.
roguelike_profile_enabled :: proc(rs: ^Roguelike_Session) -> bool {
	return rs.smoke_mode_count == 0 && !rs.smoke_test && !rs.options.spell_lab &&
	       !rs.options.dice_set_lab && !rs.options.dice_set_smoke &&
	       rs.options.m9_lab == .None && !rs.options.m9_smoke
}

roguelike_prepare :: proc(rs: ^Roguelike_Session) -> Session_Start {
	rs.procedural_rooms = (!rs.smoke_test && !rs.options.spell_lab) || rs.smoke_generation || rs.smoke_family != .Scattered || rs.smoke_relics


	rs.run_seed = rs.options.seed
	if rs.smoke_shop || rs.smoke_rest || rs.smoke_event || rs.smoke_treasure || rs.smoke_special_result {
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
	rs.run_state, run_ok = game.create_run(DEMO_PLAYER_STATS, DEMO_RUN_CONFIG, rs.run_seed, (!rs.smoke_test && !rs.options.spell_lab) || rs.smoke_relics)
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
	if rs.options.tactical.enabled {
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
	if rs.spell_smoke != .None {
		if !prepare_spell_smoke(&rs.room, &rs.iso_renderer, rs.spell_smoke) { fmt.eprintln("spell smoke setup failed"); os.exit(2) }
		if spell_smoke_is_preview(rs.spell_smoke) {
			index := 3 if rs.spell_smoke == .Sunder_Preview else 2
			rs.card_interaction.selected_card_id = rs.room.player.deck.hand[index].id
			rs.iso_renderer.hovered_cell = rs.room.enemies[0].position
			rs.iso_renderer.has_hovered_cell = true
		}
	} else if rs.smoke_map {
		rs.room.phase = .Complete
		transition := game.finish_room(&rs.run_state, rs.room.phase)
		assert(transition == .Reward)
		reward_skipped := game.skip_card_reward(&rs.run_state) == .Skipped
		assert(reward_skipped)
		rs.show_route_map = true
	} else if rs.smoke_reward {
		rs.room.phase = .Complete
		transition := game.finish_room(&rs.run_state, rs.room.phase)
		assert(transition == .Reward)
		rs.reward_hovered_index = 1
	} else if rs.smoke_shop || rs.smoke_rest || rs.smoke_event || rs.smoke_treasure || rs.smoke_special_result {
		rs.room.phase = .Complete
		transition := game.finish_room(&rs.run_state, rs.room.phase)
		assert(transition == .Reward)
		reward_skipped := game.skip_card_reward(&rs.run_state) == .Skipped
		assert(reward_skipped)
		desired_kind := game.Node_Kind.Shop
		if rs.smoke_rest {
			desired_kind = .Rest
			rs.run_state.player.health = rs.run_state.player.stats.max_health/2
		} else if rs.smoke_event {
			desired_kind = .Event
		} else if rs.smoke_treasure || rs.smoke_special_result {
			desired_kind = .Treasure
		}
		if rs.smoke_shop {
			rs.run_state.player.gold = 20
		}
		special_node := available_node_of_kind(&rs.run_state, desired_kind)
		assert(special_node != game.INVALID_NODE_ID)
		node_entered := enter_demo_node(
			&rs.level_data,
			&rs.run_state,
			&rs.room,
			special_node,
			rs.procedural_rooms,
		)
		assert(node_entered)
		if rs.smoke_shop {
			rs.shop_render_state.has_hovered_offer = true
			rs.shop_render_state.hovered_offer_index = 1
			rs.shop_render_state.selected_card_id = rs.run_state.player.deck.owned[0].id
		} else if rs.smoke_rest {
			rs.special_render_state.selected_card_id = rs.run_state.player.deck.owned[0].id
			rs.special_render_state.secondary_hovered = true
		} else {
			rs.special_render_state.primary_hovered = true
		}
		if rs.smoke_special_result {
			treasure_claimed := game.claim_treasure(&rs.run_state) == .Treasure_Claimed
			assert(treasure_claimed)
			rs.special_render_state.primary_hovered = false
			rs.special_render_state.continue_hovered = true
		}
	} else if rs.smoke_tactics {
		prepared := prepare_tactics_smoke(&rs.room)
		assert(prepared)
	} else if rs.smoke_sprites {
		prepared := prepare_tactics_smoke(&rs.room) && prepare_sprite_smoke(&rs.iso_renderer)
		assert(prepared)
		for &object in rs.room.objects {
			if object.kind == .Ice_Block { object.health = 2 }
		}
	} else if rs.smoke_relic_combat {
		prepared := prepare_tactics_smoke(&rs.room)
		assert(prepared)
		for definition in game.RELIC_DEFINITIONS {
			added := game.acquire_relic(rs.room.player, definition.id)
			assert(added)
		}
		game.begin_room_relics(&rs.room)
	} else if rs.smoke_encounters || rs.smoke_miniboss || rs.smoke_furnace {
		kind: Encounter_Smoke = .Escort
		if rs.smoke_miniboss { kind = .Miniboss }
		if rs.smoke_furnace { kind = .Furnace }
		card_id, prepared := prepare_encounter_smoke(&rs.room, &rs.iso_renderer, kind)
		assert(prepared)
		rs.card_interaction.selected_card_id = card_id
	} else if rs.smoke_intents {
		rs.room.enemies[0].position = {x = 2, y = 1}
		rs.room.enemies[1].position = {x = 7, y = 1}
		rs.room.enemies[2].position = {x = 4, y = 6}
		game.plan_enemy_intents(&rs.room)
	} else if rs.smoke_archetypes {
		rs.room.enemies[0].archetype = .Chaser
		rs.room.enemies[0].position = {x = 4, y = 6}
		rs.room.enemies[1].archetype = .Archer
		rs.room.enemies[1].position = {x = 5, y = 1}
		rs.room.enemies[2].archetype = .Brute
		rs.room.enemies[2].position = {x = 1, y = 4}
		game.plan_enemy_intents(&rs.room)
	} else if rs.smoke_defeat {
		rs.room.player.health = 1
		rs.room.enemies[0].archetype = .Chaser
		rs.room.enemies[0].position = {x = 2, y = 1}
		game.plan_enemy_intents(&rs.room)
		before := render.capture_room_presentation(&rs.room)
		result := game.wait_player_turn(&rs.room)
		assert(result == .Player_Defeated)
		timeline_started := render.begin_renderer_event_timeline(&rs.iso_renderer, before, &rs.room.recent_events)
		assert(timeline_started)
		timeline_finished := render.update_renderer_event_timeline(&rs.iso_renderer, 1000)
		assert(timeline_finished)
		assert(!render.renderer_timeline_is_busy(&rs.iso_renderer))
	} else if rs.smoke_status {
		game.use_player_ability(&rs.room, .Toxic_Wave)
		game.use_player_ability(&rs.room, .Guard)
		game.use_player_ability(&rs.room, .Thorn_Coat)
		game.use_player_ability(&rs.room, .Afterimage)
	} else if rs.smoke_loot {
		rs.room.player.position = {x = 10, y = 2}
		rs.room.enemies[0].health = rs.room.player.stats.attack
		before := render.capture_room_presentation(&rs.room)
		result := game.try_move_player(&rs.room, .East)
		assert(result == .Attacked && rs.room.phase == .Combat)
		timeline_started := render.begin_renderer_event_timeline(&rs.iso_renderer, before, &rs.room.recent_events)
		assert(timeline_started)
		render.update_renderer_event_timeline(
			&rs.iso_renderer,
			render.PRESENTATION_DAMAGE_DURATION+
				render.PRESENTATION_DEFEAT_DURATION+
				render.PRESENTATION_NOTICE_DURATION+
				render.PRESENTATION_LOOT_DURATION*0.45,
		)
		cue, active := render.active_presentation_cue(&rs.iso_renderer.timeline)
		assert(active && cue.kind == .Loot)
	} else if rs.smoke_card {
		rs.card_interaction.dragged_card_id = prepare_smoke_card_drag(&rs.room, .Arc_Bolt)
		rs.room.enemies[0].position = {x = 4, y = 1}
		game.plan_enemy_intents(&rs.room)
	} else if rs.smoke_targeting {
		rs.card_interaction.dragged_card_id = prepare_smoke_card_drag(&rs.room, .Firebomb)
		rs.room.enemies[0].position = {x = 3, y = 1}
		rs.room.enemies[1].position = {x = 4, y = 2}
		rs.room.enemies[2].position = {x = 3, y = 3}
		game.plan_enemy_intents(&rs.room)
	} else if rs.smoke_spatial {
		card, created := game.create_temporary_card(&rs.room.player.deck, .Dash)
		assert(created && len(rs.room.traps) > 0)
		rs.card_interaction.dragged_card_id = card.id
		rs.room.traps[0].position = {x = 3, y = 1}
		rs.room.traps[0].armed = true
		game.plan_enemy_intents(&rs.room)
	} else if rs.smoke_object {
		assert(len(rs.room.objects) >= 2)
		rs.room.objects[0].position = {x = 2, y = 1}
		rs.room.objects[1].position = {x = 4, y = 2}
		shove, created := game.create_temporary_card(&rs.room.player.deck, .Shove)
		assert(created)
		rs.card_interaction.dragged_card_id = shove.id
		game.plan_enemy_intents(&rs.room)
	} else if rs.smoke_fire {
		fire_index := -1
		for object, index in rs.room.objects {
			if object.kind == .Fire {
				fire_index = index
				break
			}
		}
		assert(fire_index >= 0)
		rs.room.player.position = {x = 6, y = 5}
		rs.room.objects[fire_index].position = {x = 7, y = 5}
		rs.smoke_fire_entity = game.object_entity(rs.room.objects[fire_index].id)
		game.plan_enemy_intents(&rs.room)
		before := render.capture_room_presentation(&rs.room)
		result := game.try_move_player(&rs.room, .East)
		assert(result == .Moved)
		after := render.capture_room_presentation(&rs.room)
		timeline_started := render.begin_renderer_event_timeline(
			&rs.iso_renderer,
			before,
			&rs.room.recent_events,
			&after,
		)
		assert(timeline_started)
		render.update_renderer_event_timeline(
			&rs.iso_renderer,
			render.PRESENTATION_PLAYER_MOVE_DURATION+
				render.PRESENTATION_NOTICE_DURATION*0.25,
		)
		cue, active := render.active_presentation_cue(&rs.iso_renderer.timeline)
		assert(active && cue.kind == .Hazard_Triggered)
		presentation_fire, fire_visible := render.presentation_grid_object(
			&rs.iso_renderer.timeline,
			rs.smoke_fire_entity,
		)
		assert(fire_visible && presentation_fire.visible && presentation_fire.kind == .Fire)
	} else if rs.smoke_content {
		game.finish_deck_combat(&rs.room.player.deck)
		deck_initialized := game.initialize_empty_deck(
			&rs.room.player.deck,
			game.DEFAULT_DECK_RULES,
			0xC017E17,
		)
		assert(deck_initialized)
		content_cards := [?]game.Card_Id{
			.Heavy_Blow,
			.Venom_Needle,
			.Caustic_Bloom,
			.Purifying_Guard,
			.Volatile_Study,
		}
		for definition_id in content_cards {
			_, added := game.add_owned_card(&rs.room.player.deck, definition_id)
			assert(added)
		}
		combat_started := game.begin_deck_combat(&rs.room.player.deck)
		assert(combat_started)
		rs.card_interaction.dragged_card_id = prepare_smoke_card_drag(&rs.room, .Caustic_Bloom)
		rs.card_interaction.hovered_card_id = prepare_smoke_card_drag(&rs.room, .Volatile_Study)
		rs.room.enemies[0].position = {x = 3, y = 1}
		rs.room.enemies[1].position = {x = 4, y = 2}
		rs.room.enemies[2].position = {x = 3, y = 3}
		game.clear_enemy_intents(&rs.room)
	} else if rs.smoke_timeline {
		card_id := prepare_smoke_card_drag(&rs.room, .Guard)
		before := render.capture_room_presentation(&rs.room)
		play := game.play_card(&rs.room, card_id, game.entity_target(game.PLAYER_ENTITY))
		assert(game.card_play_was_committed(play.result))
		timeline_started := render.begin_renderer_event_timeline(&rs.iso_renderer, before, &rs.room.recent_events)
		assert(timeline_started)
		render.update_renderer_event_timeline(
			&rs.iso_renderer,
			render.PRESENTATION_CARD_PLAY_DURATION*0.45,
		)
		cue, active := render.active_presentation_cue(&rs.iso_renderer.timeline)
		assert(active && cue.kind == .Card_Played)
	} else if rs.smoke_deck_flow {
		forge, created := game.create_temporary_card(&rs.room.player.deck, .Spark_Forge)
		assert(created)
		before := render.capture_room_presentation(&rs.room)
		play := game.play_card(&rs.room, forge.id, game.entity_target(game.PLAYER_ENTITY))
		assert(game.card_play_was_committed(play.result))
		after := render.capture_room_presentation(&rs.room)
		timeline_started := render.begin_renderer_event_timeline(
			&rs.iso_renderer,
			before,
			&rs.room.recent_events,
			&after,
		)
		assert(timeline_started)
		render.update_renderer_event_timeline(
			&rs.iso_renderer,
			render.PRESENTATION_CARD_PLAY_DURATION+
				render.PRESENTATION_CARD_CREATE_DURATION+
				render.PRESENTATION_CARD_MOVE_DURATION*0.45,
		)
		cue, active := render.active_presentation_cue(&rs.iso_renderer.timeline)
		assert(active && cue.kind == .Card_Moved && cue.event.to_card_zone == .Exhaust)
	} else if rs.smoke_refocus {
		_, counter_created := game.create_temporary_card(&rs.room.player.deck, .Counter_Rune)
		_, focus_created := game.create_temporary_card(&rs.room.player.deck, .Battle_Focus)
		assert(counter_created && focus_created)
		before := render.capture_room_presentation(&rs.room)
		refocus := game.refocus_player_hand(&rs.room)
		assert(game.refocus_was_committed(refocus.result))
		after := render.capture_room_presentation(&rs.room)
		timeline_started := render.begin_renderer_event_timeline(
			&rs.iso_renderer,
			before,
			&rs.room.recent_events,
			&after,
		)
		assert(timeline_started)
		render.update_renderer_event_timeline(
			&rs.iso_renderer,
			render.PRESENTATION_REFOCUS_DURATION*0.45,
		)
		cue, active := render.active_presentation_cue(&rs.iso_renderer.timeline)
		assert(active && cue.kind == .Refocus)
	} else if rs.smoke_movement {
		before := render.capture_room_presentation(&rs.room)
		result := game.wait_player_turn(&rs.room)
		assert(result != .Invalid_Phase)
		timeline_started := render.begin_renderer_event_timeline(&rs.iso_renderer, before, &rs.room.recent_events)
		assert(timeline_started)
		render.update_renderer_event_timeline(
			&rs.iso_renderer,
			render.PRESENTATION_ENEMY_MOVE_DURATION*0.5,
		)
		cue, active := render.active_presentation_cue(&rs.iso_renderer.timeline)
		assert(active && cue.kind == .Move)
	}

	if rs.options.m8_view_smoke {
		if !run_m8_view_smoke(rs.window, &rs.iso_renderer, &rs.dice_renderer) { fmt.eprintln("M8 native smoke failed"); os.exit(2) }
		return .Finished
	}
	if rs.options.western_smoke {
		if !run_western_smoke(rs.window, &rs.iso_renderer, &rs.dice_renderer) { fmt.eprintln("6 RANCH 7 smoke failed"); os.exit(2) }
		return .Finished
	}
	if rs.options.m9_lab != .None {
		run_m9_lab(rs.window, &rs.iso_renderer, rs.options.m9_lab)
		return .Finished
	}
	if rs.options.m9_smoke {
		if !run_m9_view_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M9 native smoke failed"); os.exit(2) }
		return .Finished
	}
	if rs.options.dice_set_lab || rs.options.dice_set_smoke {
		if !run_dice_set_lab(rs.window, &rs.iso_renderer, &rs.dice_renderer, rs.options.dice_set_smoke) {
			fmt.eprintln("Dice set lab failed")
			os.exit(2)
		}
		return .Finished
	}
	if rs.options.arena_view_smoke {
		if !run_arena_view_smoke(rs.window, &rs.iso_renderer, &rs.dice_renderer) { fmt.eprintln("Arena native smoke failed"); os.exit(2) }
		return .Finished
	}

	return .Ready
}

roguelike_scene :: proc(rs: ^Roguelike_Session) -> host.Scene {
	return host.Scene{
		name          = "roguelike",
		data          = rs,
		opaque        = true,
		modal         = true,
		clear_color   = render.CANVAS_BACKGROUND,
		update        = roguelike_update,
		draw          = roguelike_draw,
		draw_window   = roguelike_draw_window,
		after_present = roguelike_after_present,
		suspend       = roguelike_suspend,
		resume        = roguelike_resume,
		destroy       = roguelike_destroy,
	}
}

// Host focus is the ownership boundary, including non-modal overlays. Never
// sample raw gameplay controls after a different scene has taken ownership.
roguelike_suspend_input :: proc(rs: ^Roguelike_Session) {
	clear_card_interaction(&rs.card_interaction)
	clear_gameplay_command_buffer(&rs.gameplay_buffer)
	rs.mouse_inside = false
	rs.tactical_controller.was_focused = false
	rs.iso_renderer.frame_clock_valid = false
	rs.iso_renderer.tactical.world_orbit.dragging = false
	rs.iso_renderer.tactical.hologram_orbit.dragging = false
}

roguelike_suspend :: proc(data: rawptr) {
	rs := cast(^Roguelike_Session)data
	roguelike_suspend_input(rs)
}

roguelike_update :: proc(data: rawptr, hf: ^host.Frame) {
	rs := cast(^Roguelike_Session)data
	if rs.smoke_mode_count == 0 && !rs.smoke_test && (!hf.focused || !hf.window_focused) {
		roguelike_suspend_input(rs)
		return
	}
	if rs.from_launcher && hf.focused && rl.IsKeyPressed(.F10) {
		host.pop(hf)
		return
	}
	if !rs.smoke_test && rl.IsKeyPressed(.F4) {
		speed := f32(1) if rs.iso_renderer.playback_speed >= 4 else min(f32(4), rs.iso_renderer.playback_speed*2)
		render.set_renderer_playback_speed(&rs.iso_renderer, speed)
	}
	rs.frame_time = (f32(1.0/60.0) if rs.options.m7_view_smoke else hf.dt)
	rs.m8_modal = false
	m8_mouse, m8_mouse_inside := view.Vec2{hf.mouse.x,hf.mouse.y}, hf.mouse_inside
	if !rs.smoke_test && !rs.options.m7_view_smoke && rs.options.tactical.enabled {
		rs.m8_modal = update_m8_session(&rs.m8_session, &rs.room, &rs.iso_renderer, &rs.tactical_controller,
			&rs.card_interaction, &rs.gameplay_buffer, rs.run_state.phase == .In_Room &&
			!rs.show_route_map && !game.run_has_relic_choice(&rs.run_state), rs.frame_time, m8_mouse, m8_mouse_inside)
	}
	roguelike_ranch_feedback(rs, hf)
	if roguelike_open_activity(rs,hf) {
        rs.overlay=nil
        rs.overlay_data={}
        return
    }
	if rl.IsKeyPressed(.F8) {
		frame := Input_Diagnostic_Frame{dt = rs.frame_time, focused = rl.IsWindowFocused(),
			route_map = rs.show_route_map, scripted = rs.smoke_test, mouse_left = rl.IsMouseButtonDown(.LEFT),
			shift = rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)}
		for key, index in ([?]rl.KeyboardKey{.W, .D, .S, .A}) { frame.wasd_down[index] = rl.IsKeyDown(key) }
		path, saved := write_input_diagnostic(&rs.run_state, &rs.room, &rs.iso_renderer, &rs.tactical_controller,
			&rs.card_interaction, &rs.gameplay_buffer, frame)
		if saved { fmt.printf("Input snapshot saved: %s\n", path); delete(path) }
		else { fmt.eprintln("Could not save input snapshot (write error or 256 captures already present)") }
	}
	if render.presentation_time_policy(&rs.iso_renderer.timeline) != .Cinematic {
		render.advance_sprite_assets(&rs.iso_renderer.sprite_assets, rs.frame_time if !rs.smoke_test else f32(1.0/60.0))
	}
	if !rs.m8_modal && !rl.IsKeyPressed(.P) && !rs.smoke_furnace && rs.spell_smoke == .None &&
	   (!rs.options.tactical.enabled || rs.options.m7_view_smoke || (!rs.tactical_controller.paused && rs.tactical_controller.was_focused && rl.IsWindowFocused())) {
		render.update_renderer_frame_timeline(&rs.iso_renderer, rs.frame_time)
	}
	rs.mouse_canvas, rs.mouse_inside = m8_mouse, m8_mouse_inside
	if spell_smoke_is_preview(rs.spell_smoke) {
		rs.mouse_canvas = render.cell_center(&rs.iso_renderer, rs.room.enemies[0].position)
		rs.mouse_inside = true
	}
	if rs.smoke_encounters {
		rs.mouse_canvas = render.cell_center(&rs.iso_renderer, rs.room.objects[0].position)
		rs.mouse_canvas.y -= max(f32(8), 12*rs.iso_renderer.camera.zoom)*1.4
		rs.mouse_inside = true
		render.update_object_target_hover(&rs.iso_renderer, &rs.room, rs.mouse_canvas, rs.card_interaction.selected_card_id)
	}
	mouse_delta := app.mouse_canvas_delta(rs.window)
	rs.defeat_restart_hovered = rs.run_state.phase == .Defeat && rs.mouse_inside &&
		render.defeat_restart_at_point(
			f32(rs.window.config.canvas_width),
			f32(rs.window.config.canvas_height),
			rs.mouse_canvas,
		)
	restart_requested := !rs.m8_modal && (rl.IsKeyPressed(.F5) ||
		(rs.run_state.phase == .Defeat && rl.IsKeyPressed(.ENTER)) ||
		(rs.defeat_restart_hovered && rl.IsMouseButtonPressed(.LEFT)))
	if restart_requested {
		if rs.playtest_session_ptr != nil {
			if !rs.playtest_report_written {
				rs.playtest_report_written = finish_seed_playtest_report(
					rs.playtest_session_ptr,
					rs.run_seed,
					rs.options.playtest_output,
					playtest_outcome_for_state(&rs.run_state, &rs.room),
					&rs.room,
				)
				if !rs.playtest_report_written {
					fmt.eprintln("failed to write playtest report before restart")
					return
				}
			}
			combatdebug.destroy_playtest_session(rs.playtest_session_ptr)
			rs.playtest_session_ptr = nil
		}
		if rs.playtest_report && !write_m7_metrics(&rs.run_state.player, rs.run_seed, rs.options.playtest_output) {
			fmt.eprintln("failed to write M7 metrics before restart")
			return
		}
		rs.run_seed += 1
		m8_profile := rs.run_state.player.m8_profile
		restarted := restart_demo_session(
			&rs.level_data,
			&rs.run_state,
			&rs.room,
			rs.run_seed,
			rs.procedural_rooms,
		)
		assert(restarted)
		rs.run_state.player.m8_profile = m8_profile
		rs.m8_session.character_open = false
		if rs.options.tactical.enabled {
			configured := game.configure_tactical_room(&rs.room, rs.options.tactical)
			assert(configured)
			rs.tactical_controller = {}
		}
		if rs.options.spell_lab {
			if !prepare_spell_lab(&rs.room, rs.options.dice_lab) { fmt.eprintln("could not reset card practice"); host.quit(hf); return }
		}
		if rs.playtest_report && !game.run_has_relic_choice(&rs.run_state) {
			playtest_started := begin_playtest_run(&rs.playtest_session, rs.run_seed, &rs.run_state, &rs.room)
			assert(playtest_started)
			rs.playtest_session_ptr = &rs.playtest_session
			rs.playtest_report_written = false
		}
		rs.show_route_map = false
		clear_card_interaction(&rs.card_interaction)
		clear_gameplay_command_buffer(&rs.gameplay_buffer)
		rs.reward_hovered_index = -1
		rs.reward_skip_hovered = false
		rs.shop_render_state = {hovered_offer_index = -1}
		rs.special_render_state = {}
		rs.defeat_restart_hovered = false
		render.frame_level(&rs.iso_renderer, &rs.level_data)
		render.clear_event_animations(&rs.iso_renderer)
	}

	rs.timeline_busy = render.renderer_timeline_is_busy(&rs.iso_renderer)
	if !rs.m8_modal && (!rs.options.tactical.enabled || rs.room.phase != .Combat) && !game.run_has_relic_choice(&rs.run_state) && rl.IsKeyPressed(.M) && route_map_toggle_is_allowed(&rs.run_state, &rs.room, &rs.iso_renderer) {
		rs.show_route_map = !rs.show_route_map
		if rs.show_route_map {
			clear_card_interaction(&rs.card_interaction)
			clear_gameplay_command_buffer(&rs.gameplay_buffer)
		}
	}
	rs.defeat_visible = rs.run_state.phase == .Defeat
	rs.reward_visible = rs.run_state.phase == .Reward
	rs.shop_visible = rs.run_state.phase == .Shop
	rs.special_visible = rs.run_state.phase == .Rest || rs.run_state.phase == .Event ||
	                   rs.run_state.phase == .Treasure
	rs.route_visible = !rs.reward_visible && !rs.shop_visible && !rs.special_visible &&
	                 (rs.show_route_map || rs.run_state.phase == .Choose_Path || rs.run_state.phase == .Victory)
	rs.hovered_node = game.INVALID_NODE_ID
	rs.shop_button_hovered = false
	relic_visible := game.run_has_relic_choice(&rs.run_state)
	rs.relic_hovered = -1
	rs.relic_skip_hovered = false
	tactical_input_blocked := false
	if rs.options.tactical.enabled {
		render.update_tactical_view(&rs.iso_renderer, &rs.room, rs.mouse_canvas, rs.mouse_inside && !rs.m8_modal &&
			!render.m8_hud_contains_point(&rs.iso_renderer, &rs.room, rs.mouse_canvas) &&
			!rs.tactical_controller.hologram && !rs.tactical_controller.paused && rl.IsWindowFocused())
		render.update_tactical_atmosphere(&rs.iso_renderer, rs.frame_time if rs.options.m7_view_smoke || (!rs.tactical_controller.paused && rl.IsWindowFocused()) else 0)
		if !rs.options.m7_view_smoke && !rs.m8_modal { tactical_input_blocked = update_tactical_controller(&rs.tactical_controller, &rs.room, &rs.iso_renderer,
			&rs.card_interaction, &rs.gameplay_buffer, rs.frame_time,
			rs.run_state.phase == .In_Room && !relic_visible && !rs.route_visible && !rs.options.m7_view_smoke,
			rs.mouse_canvas, rs.mouse_inside, rs.playtest_session_ptr) } else { tactical_input_blocked = true }
	}

	if relic_visible {
		clear_card_interaction(&rs.card_interaction)
		clear_gameplay_command_buffer(&rs.gameplay_buffer)
		if rs.mouse_inside {
			rs.relic_hovered = render.relic_choice_at_point(&rs.run_state,
				f32(rs.window.config.canvas_width), f32(rs.window.config.canvas_height), rs.mouse_canvas)
			rs.relic_skip_hovered = render.reward_skip_at_point(f32(rs.window.config.canvas_width),
				f32(rs.window.config.canvas_height), rs.mouse_canvas)
		}
		if rs.smoke_relics { rs.relic_hovered = 1 }
		choice := pressed_hand_slot()
		skip := rl.IsKeyPressed(.S)
		if rs.mouse_inside && rl.IsMouseButtonPressed(.LEFT) {
			if rs.relic_hovered >= 0 { choice = rs.relic_hovered }
			if rs.relic_skip_hovered { skip = true }
		}
		if !rs.smoke_test && resolve_demo_relic_choice(&rs.run_state, &rs.room, choice, skip) {
			relic_visible = false
			if rs.playtest_report && rs.playtest_session_ptr == nil {
				started := begin_playtest_run(&rs.playtest_session, rs.run_seed, &rs.run_state, &rs.room)
				assert(started)
				rs.playtest_session_ptr = &rs.playtest_session
				rs.playtest_report_written = false
			}
		}
	} else if rs.defeat_visible {
		clear_card_interaction(&rs.card_interaction)
		clear_gameplay_command_buffer(&rs.gameplay_buffer)
	} else if rs.reward_visible {
		clear_gameplay_command_buffer(&rs.gameplay_buffer)
		previous_hovered_index := rs.reward_hovered_index
		rs.reward_hovered_index = -1
		rs.reward_skip_hovered = false
		if rs.smoke_reward {
			rs.reward_hovered_index = 1
		} else if rs.mouse_inside {
			if hovered_index, found := render.reward_card_at_point(
				&rs.run_state,
				f32(rs.window.config.canvas_width),
				f32(rs.window.config.canvas_height),
				rs.mouse_canvas,
				previous_hovered_index,
			); found {
				rs.reward_hovered_index = hovered_index
			} else {
				rs.reward_skip_hovered = render.reward_skip_at_point(
					f32(rs.window.config.canvas_width),
					f32(rs.window.config.canvas_height),
					rs.mouse_canvas,
				)
			}
		}

		choice_index := pressed_hand_slot()
		choice_requested := choice_index >= 0 && choice_index < game.CARD_REWARD_CHOICE_COUNT
		skip_requested := rl.IsKeyPressed(.S)
		if rs.mouse_inside && rl.IsMouseButtonPressed(.LEFT) {
			if rs.reward_hovered_index >= 0 {
				choice_index = rs.reward_hovered_index
				choice_requested = true
			} else if rs.reward_skip_hovered {
				skip_requested = true
			}
		}

		resolved := false
		if choice_requested {
			result := game.choose_card_reward(&rs.run_state, choice_index)
			resolved = result == .Added
		} else if skip_requested {
			result := game.skip_card_reward(&rs.run_state)
			resolved = result == .Skipped
		}
		if resolved {
			rs.reward_visible = false
			rs.shop_visible = false
			rs.route_visible = true
			rs.show_route_map = true
			rs.reward_hovered_index = -1
			rs.reward_skip_hovered = false
		}
	} else if rs.shop_visible {
		clear_card_interaction(&rs.card_interaction)
		clear_gameplay_command_buffer(&rs.gameplay_buffer)
		rs.shop_render_state.page = render.shop_clamp_deck_page(
			&rs.run_state.player.deck,
			rs.shop_render_state.page,
		)
		previous_hovered_offer := -1
		if rs.shop_render_state.has_hovered_offer {
			previous_hovered_offer = rs.shop_render_state.hovered_offer_index
		}
		previous_hovered_card := rs.shop_render_state.hovered_card_id
		rs.shop_render_state.has_hovered_offer = false
		rs.shop_render_state.hovered_offer_index = 0
		rs.shop_render_state.hovered_card_id = 0
		rs.shop_render_state.previous_page_hovered = false
		rs.shop_render_state.next_page_hovered = false
		rs.shop_render_state.upgrade_hovered = false
		rs.shop_render_state.remove_hovered = false
		rs.shop_render_state.continue_hovered = false

		shop_hit: render.Shop_Hit
		if rs.smoke_shop {
			rs.shop_render_state.has_hovered_offer = true
			rs.shop_render_state.hovered_offer_index = 1
		} else if rs.mouse_inside {
			shop_hit = render.shop_hit_test(
				&rs.run_state,
				f32(rs.window.config.canvas_width),
				f32(rs.window.config.canvas_height),
				rs.shop_render_state.page,
				rs.mouse_canvas,
				previous_hovered_offer,
				previous_hovered_card,
			)
			switch shop_hit.kind {
			case .None:
			case .Offer:
				rs.shop_render_state.has_hovered_offer = true
				rs.shop_render_state.hovered_offer_index = shop_hit.offer_index
			case .Owned_Card:
				rs.shop_render_state.hovered_card_id = shop_hit.card_id
			case .Previous_Page:
				rs.shop_render_state.previous_page_hovered = true
			case .Next_Page:
				rs.shop_render_state.next_page_hovered = true
			case .Upgrade:
				rs.shop_render_state.upgrade_hovered = true
			case .Remove:
				rs.shop_render_state.remove_hovered = true
			case .Continue:
				rs.shop_render_state.continue_hovered = true
			}
		}

		if !rs.smoke_shop {
			offer_index := pressed_hand_slot()
			if offer_index >= 0 && offer_index < game.SHOP_CARD_OFFER_COUNT {
				game.buy_shop_card(&rs.run_state, offer_index)
			}
			if rl.IsKeyPressed(.LEFT) {
				rs.shop_render_state.page = max(0, rs.shop_render_state.page-1)
				rs.shop_render_state.selected_card_id = 0
			} else if rl.IsKeyPressed(.RIGHT) {
				rs.shop_render_state.page = min(
					render.shop_deck_page_count(&rs.run_state.player.deck)-1,
					rs.shop_render_state.page+1,
				)
				rs.shop_render_state.selected_card_id = 0
			}
			if rl.IsKeyPressed(.U) && rs.shop_render_state.selected_card_id != 0 {
				game.buy_shop_upgrade(&rs.run_state, rs.shop_render_state.selected_card_id)
			} else if rl.IsKeyPressed(.R) && rs.shop_render_state.selected_card_id != 0 {
				result := game.buy_shop_removal(&rs.run_state, rs.shop_render_state.selected_card_id)
				if result == .Removed {
					rs.shop_render_state.selected_card_id = 0
				}
			}

			leave_requested := rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.ESCAPE)
			if rs.mouse_inside && rl.IsMouseButtonPressed(.LEFT) {
				switch shop_hit.kind {
				case .None:
				case .Offer:
					game.buy_shop_card(&rs.run_state, shop_hit.offer_index)
				case .Owned_Card:
					rs.shop_render_state.selected_card_id = shop_hit.card_id
				case .Previous_Page:
					rs.shop_render_state.page = max(0, rs.shop_render_state.page-1)
					rs.shop_render_state.selected_card_id = 0
				case .Next_Page:
					rs.shop_render_state.page = min(
						render.shop_deck_page_count(&rs.run_state.player.deck)-1,
						rs.shop_render_state.page+1,
					)
					rs.shop_render_state.selected_card_id = 0
				case .Upgrade:
					if rs.shop_render_state.selected_card_id != 0 {
						game.buy_shop_upgrade(&rs.run_state, rs.shop_render_state.selected_card_id)
					}
				case .Remove:
					if rs.shop_render_state.selected_card_id != 0 {
						result := game.buy_shop_removal(
							&rs.run_state,
							rs.shop_render_state.selected_card_id,
						)
						if result == .Removed {
							rs.shop_render_state.selected_card_id = 0
						}
					}
				case .Continue:
					leave_requested = true
				}
			}
			rs.shop_render_state.page = render.shop_clamp_deck_page(
				&rs.run_state.player.deck,
				rs.shop_render_state.page,
			)
			if leave_requested && game.leave_shop(&rs.run_state) == .Left {
				rs.shop_visible = false
				rs.route_visible = true
				rs.show_route_map = true
				rs.shop_render_state = {}
			}
		}
	} else if rs.special_visible {
		clear_card_interaction(&rs.card_interaction)
		clear_gameplay_command_buffer(&rs.gameplay_buffer)
		rs.special_render_state.page = render.special_node_clamp_deck_page(
			&rs.run_state.player.deck,
			rs.special_render_state.page,
		)
		previous_hovered_card := rs.special_render_state.hovered_card_id
		rs.special_render_state.hovered_card_id = 0
		rs.special_render_state.previous_page_hovered = false
		rs.special_render_state.next_page_hovered = false
		rs.special_render_state.primary_hovered = false
		rs.special_render_state.secondary_hovered = false
		rs.special_render_state.leave_hovered = false
		rs.special_render_state.continue_hovered = false

		special_hit: render.Special_Node_Hit
		special_smoke := rs.smoke_rest || rs.smoke_event || rs.smoke_treasure || rs.smoke_special_result
		if special_smoke {
			if rs.smoke_special_result {
				rs.special_render_state.continue_hovered = true
			} else if rs.smoke_rest {
				rs.special_render_state.secondary_hovered = true
			} else {
				rs.special_render_state.primary_hovered = true
			}
		} else if rs.mouse_inside {
			special_hit = render.special_node_hit_test(
				&rs.run_state,
				f32(rs.window.config.canvas_width),
				f32(rs.window.config.canvas_height),
				rs.special_render_state.page,
				rs.mouse_canvas,
				previous_hovered_card,
				rs.special_render_state.selected_card_id,
			)
			switch special_hit.kind {
			case .None:
			case .Primary:
				rs.special_render_state.primary_hovered = true
			case .Secondary:
				rs.special_render_state.secondary_hovered = true
			case .Leave:
				rs.special_render_state.leave_hovered = true
			case .Owned_Card:
				rs.special_render_state.hovered_card_id = special_hit.card_id
			case .Previous_Page:
				rs.special_render_state.previous_page_hovered = true
			case .Next_Page:
				rs.special_render_state.next_page_hovered = true
			case .Continue:
				rs.special_render_state.continue_hovered = true
			}
		}

		if !special_smoke {
			requested := render.Special_Node_Hit{kind = .None}
			if game.special_node_can_continue(&rs.run_state) {
				if rl.IsKeyPressed(.ENTER) {
					requested.kind = .Continue
				}
			} else {
				choice_index := pressed_hand_slot()
				if choice_index == 0 {
					requested.kind = .Primary
				} else if choice_index == 1 {
					requested.kind = .Secondary
				}
				if rl.IsKeyPressed(.L) {
					requested.kind = .Leave
				} else if rs.run_state.phase == .Rest && rl.IsKeyPressed(.U) {
					requested.kind = .Secondary
				}
			}
			if rs.run_state.phase == .Rest && rl.IsKeyPressed(.LEFT) {
				rs.special_render_state.page = max(0, rs.special_render_state.page-1)
				rs.special_render_state.selected_card_id = 0
			} else if rs.run_state.phase == .Rest && rl.IsKeyPressed(.RIGHT) {
				rs.special_render_state.page = min(
					render.special_node_deck_page_count(&rs.run_state.player.deck)-1,
					rs.special_render_state.page+1,
				)
				rs.special_render_state.selected_card_id = 0
			}
			if rs.mouse_inside && rl.IsMouseButtonPressed(.LEFT) {
				requested = special_hit
			}
			primary_enabled := render.special_node_primary_is_enabled(&rs.run_state)
			secondary_enabled := render.special_node_secondary_is_enabled(
				&rs.run_state,
				rs.special_render_state.selected_card_id,
			)
			if requested.kind == .Primary && !primary_enabled {
				requested.kind = .None
			} else if requested.kind == .Secondary && !secondary_enabled {
				requested.kind = .None
			}

			switch requested.kind {
			case .None:
			case .Owned_Card:
				rs.special_render_state.selected_card_id = requested.card_id
			case .Previous_Page:
				rs.special_render_state.page = max(0, rs.special_render_state.page-1)
				rs.special_render_state.selected_card_id = 0
			case .Next_Page:
				rs.special_render_state.page = min(
					render.special_node_deck_page_count(&rs.run_state.player.deck)-1,
					rs.special_render_state.page+1,
				)
				rs.special_render_state.selected_card_id = 0
			case .Primary:
				switch rs.run_state.phase {
				case .Rest:
					game.use_rest_recovery(&rs.run_state)
				case .Event:
					game.resolve_route_event(&rs.run_state, .Primary)
				case .Treasure:
					game.claim_treasure(&rs.run_state)
				case .In_Room, .Reward, .Shop, .Choose_Path, .Victory, .Defeat:
				}
			case .Secondary:
				if rs.run_state.phase == .Rest {
					game.use_rest_upgrade(
						&rs.run_state,
						rs.special_render_state.selected_card_id,
					)
				} else if rs.run_state.phase == .Event {
					game.resolve_route_event(&rs.run_state, .Secondary)
				}
			case .Leave:
				game.leave_special_node(&rs.run_state)
			case .Continue:
				if game.continue_special_node(&rs.run_state) == .Continued {
					rs.special_visible = false
					rs.route_visible = true
					rs.show_route_map = true
					rs.special_render_state = {}
				}
			}
			rs.special_render_state.page = render.special_node_clamp_deck_page(
				&rs.run_state.player.deck,
				rs.special_render_state.page,
			)
		}
	} else if rs.route_visible {
		if rs.mouse_inside {
			rs.shop_button_hovered = rs.run_state.phase == .Choose_Path &&
				rs.run_state.shop.offer_count > 0 && render.run_shop_button_at_point(
					f32(rs.window.config.canvas_width),
					f32(rs.window.config.canvas_height),
					rs.mouse_canvas,
				)
			if !rs.shop_button_hovered {
				if hovered, found := render.run_node_at_point(
				&rs.run_state,
				f32(rs.window.config.canvas_width),
				f32(rs.window.config.canvas_height),
				rs.mouse_canvas,
			); found {
				rs.hovered_node = hovered
				}
			}
		}

		if rs.run_state.phase == .Choose_Path {
			shop_requested := rs.shop_button_hovered && rl.IsMouseButtonPressed(.LEFT)
			if shop_requested && game.open_shop(&rs.run_state) == .Opened {
				rs.shop_visible = true
				rs.route_visible = false
				rs.show_route_map = false
				rs.shop_render_state = {}
			}
			selected_node, selected := keyboard_route_choice(&rs.run_state)
			if rs.mouse_inside && rl.IsMouseButtonPressed(.LEFT) && rs.hovered_node != game.INVALID_NODE_ID {
				selected_node = rs.hovered_node
				selected = true
			}
			if selected && enter_demo_node(
				&rs.level_data,
				&rs.run_state,
				&rs.room,
				selected_node,
				rs.procedural_rooms,
			) {
				rs.show_route_map = false
				rs.route_visible = false
				rs.shop_visible = rs.run_state.phase == .Shop
				rs.special_visible = rs.run_state.phase == .Rest || rs.run_state.phase == .Event ||
				                  rs.run_state.phase == .Treasure
				clear_card_interaction(&rs.card_interaction)
				clear_gameplay_command_buffer(&rs.gameplay_buffer)
				rs.reward_hovered_index = -1
				rs.reward_skip_hovered = false
				rs.shop_render_state = {}
				rs.special_render_state = {}
				if rs.run_state.phase == .In_Room {
					if rs.playtest_session_ptr != nil {
						playtest_room_started := begin_current_playtest_room(
							rs.playtest_session_ptr,
							&rs.run_state,
							&rs.room,
						)
						assert(playtest_room_started)
					}
					render.frame_level(&rs.iso_renderer, &rs.level_data)
				}
				render.clear_event_animations(&rs.iso_renderer)
			}
		}
	} else {
		if !rs.options.tactical.enabled { render.update_camera(
			&rs.iso_renderer,
			&rs.level_data,
			rs.mouse_canvas,
			rs.mouse_inside,
			mouse_delta,
			rs.frame_time,
		) }
		if !rs.options.tactical.enabled && rs.mouse_inside && !rs.smoke_test && !render.renderer_timeline_is_busy(&rs.iso_renderer) {
			render.update_object_target_hover(
				&rs.iso_renderer, &rs.room, rs.mouse_canvas, active_targeting_card_id(rs.card_interaction),
			)
		}
		if !tactical_input_blocked && !rs.smoke_card && !rs.smoke_targeting && !rs.smoke_spatial && !rs.smoke_object && !rs.smoke_content &&
		   !rs.smoke_encounters && !rs.smoke_miniboss && !rs.smoke_furnace && rs.spell_smoke == .None {
			rs.timeline_busy = render.renderer_blocks_player_input(&rs.iso_renderer)
			command, has_command := poll_gameplay_command(
				&rs.room,
				&rs.iso_renderer,
				&rs.card_interaction,
				rs.mouse_canvas,
				rs.mouse_inside,
				!rs.timeline_busy && !rs.gameplay_buffer.occupied,
				rs.options.debug_abilities,
			)
			if rs.room.phase == .Complete || rs.room.phase == .Defeat {
				clear_gameplay_command_buffer(&rs.gameplay_buffer)
				rs.beat_chord = {}
			} else if rs.timeline_busy {
				if has_command {
					beat_stamp(&rs.room, &command)
					offer_gameplay_command(&rs.gameplay_buffer, command)
				}
			} else if buffered, has_buffered := take_gameplay_command(&rs.gameplay_buffer); has_buffered {
				if has_command {
					offer_gameplay_command(&rs.gameplay_buffer, command)
				}
				commit_gameplay_command(
					&rs.room,
					&rs.iso_renderer,
					&rs.card_interaction,
					buffered,
					rs.playtest_session_ptr,
				)
			} else if ready, has_ready := beat_input_command(&rs.beat_chord, &rs.room, command, has_command, rs.frame_time); has_ready {
				commit_gameplay_command(
					&rs.room,
					&rs.iso_renderer,
					&rs.card_interaction,
					ready,
					rs.playtest_session_ptr,
				)
			}
		}
		if room_transition_is_ready(&rs.run_state, &rs.room, &rs.iso_renderer) {
			transition := game.finish_room(&rs.run_state, rs.room.phase)
			if rs.playtest_session_ptr != nil &&
			   (transition == .Victory || transition == .Defeat) &&
			   !rs.playtest_report_written {
				rs.playtest_report_written = finish_seed_playtest_report(
					rs.playtest_session_ptr,
					rs.run_seed,
					rs.options.playtest_output,
					playtest_outcome_for_state(&rs.run_state, &rs.room),
					&rs.room,
				)
				if !rs.playtest_report_written {
					fmt.eprintln("failed to write completed playtest report")
				}
			}
			if transition == .Reward {
				rs.show_route_map = false
				rs.reward_visible = true
				rs.route_visible = false
				clear_card_interaction(&rs.card_interaction)
				clear_gameplay_command_buffer(&rs.gameplay_buffer)
				render.clear_event_animations(&rs.iso_renderer)
			} else if transition == .Victory {
				rs.show_route_map = true
				rs.route_visible = true
				clear_card_interaction(&rs.card_interaction)
				clear_gameplay_command_buffer(&rs.gameplay_buffer)
			} else if transition == .Defeat {
				rs.defeat_visible = true
				clear_card_interaction(&rs.card_interaction)
				clear_gameplay_command_buffer(&rs.gameplay_buffer)
				render.clear_event_animations(&rs.iso_renderer)
			}
		}
	}
	dice_cue, has_dice_cue := render.active_presentation_cue(&rs.iso_renderer.timeline)
	dice_visible := has_dice_cue && dice_cue.started && dice_cue.kind == .Dice_Rolled
	rs.overlay = nil
	rs.overlay_data = {}
	if dice_visible {
		rs.overlay = draw_window_dice_overlay
		rs.overlay_data = {renderer = &rs.dice_renderer, roll = dice_cue.event.dice_roll,
			progress = render.presentation_cue_progress(dice_cue), seed = dice_event_visual_seed(dice_cue.event),
			card = dice_cue.event.card_definition}
		update_window_dice_overlay(rs.window, &rs.overlay_data)
	}

	rs.challenge_message_ttl = max(rs.challenge_message_ttl-hf.dt, 0)
}

// A square of Tesla coils around enemies hands the duel to the catalog ring
// scene. The run waits, frozen, until roguelike_resume settles the result.
roguelike_open_activity :: proc(rs: ^Roguelike_Session, hf: ^host.Frame) -> bool {
    if !rs.room.tesla_ring.pending || rs.m8_session.ring_pending {return false}
    info, found := minigame_info(minigame_index_by_id("ring"))
    if !found {
        // Without a ring the spent coils simply fizzle.
        rs.room.tesla_ring={}
        return false
    }
    rs.m8_session.ring_pending=true
    rs.m8_session.ring_link=tesla_ring_link(&rs.room)
    rs.m8_session.report={}
    clear_card_interaction(&rs.card_interaction)
    clear_gameplay_command_buffer(&rs.gameplay_buffer)
    audio.play(hf.audio,.Confirm)
    host.push(hf,info.create({seed=rs.run_seed, challenge=true, payload=&rs.m8_session.ring_link}))
    return true
}

// Sounds of the ranch duel and its verdict, once per step.
roguelike_ranch_feedback :: proc(rs: ^Roguelike_Session, hf: ^host.Frame) {
	ranch := &rs.m8_session.ranch
	if !ranch.active && !ranch.finished {return}
	cues := ranch.state.cues
	if .Card_Slot in cues {audio.play(hf.audio,.Confirm)}
	if .Gate in cues {audio.play(hf.audio,.Push)}
	if .Tick in cues {audio.play(hf.audio,.Blip)}
	if .Press in cues {audio.play(hf.audio,.Step)}
	if .Coin_Player in cues {audio.play(hf.audio,.Coin)}
	if .Coin_Rival in cues {audio.play(hf.audio,.Hurt,0.6)}
	if .Win in cues {audio.play(hf.audio,.Win)}
	if .Lose in cues {audio.play(hf.audio,.Lose)}
	if !ranch.finished {return}
	delete(rs.challenge_message)
	if ranch.reward.won {
		rs.challenge_message=fmt.aprintf("6 RANCH 7: vita piena e +%d oro!",ranch.reward.gold)
	} else {
		rs.challenge_message=fmt.aprintf("%s","6 RANCH 7: il cowboy vince, nessuna perdita")
	}
	rs.challenge_message_ttl=5
}

roguelike_resume :: proc(data: rawptr, hf: ^host.Frame, from: string, result: Maybe(host.Result)) {
	rs := cast(^Roguelike_Session)data
	roguelike_suspend_input(rs)
	audio.stop_music(hf.audio)
	host.persist_profile(hf)
	before := render.capture_room_presentation(&rs.room)
	if !settle_m8_host_activity(&rs.m8_session,&rs.room,from,result) {return}
	// The board shows the duel's toll: knockouts fall and drop their loot.
	after := render.capture_room_presentation(&rs.room)
	if rs.room.recent_events.count > 0 {
		if render.renderer_blocks_player_input(&rs.iso_renderer) {render.clear_event_animations(&rs.iso_renderer)}
		_ = render.begin_renderer_event_timeline(&rs.iso_renderer,before,&rs.room.recent_events,&after)
	}
	if rs.room.phase != .Combat {clear_card_interaction(&rs.card_interaction)}
	delete(rs.challenge_message)
	report := rs.m8_session.report
	reward := report.reward
	switch {
	case len(rs.m8_session.status)>0:
		rs.challenge_message=fmt.aprintf("%s",rs.m8_session.status)
	case reward.has_unlock:
		title := "Titan Grip" if reward.unlocked == .Titan_Grip else "Storm Crown"
		rs.challenge_message=fmt.aprintf("Ring vinto / carta sbloccata: %s%s",title,"" if reward.card_added else " (disponibile nelle ricompense)")
	case report.won:
		rs.challenge_message=fmt.aprintf("%s","Ring vinto: sfidante sconfitto" if report.defeated == 1 else "Ring vinto: sfidanti sconfitti")
	case report.defeated > 0:
		rs.challenge_message=fmt.aprintf("Ring perso: -%d vita / %d al tappeto",report.player_damage,report.defeated)
	case:
		rs.challenge_message=fmt.aprintf("Ring perso: -%d vita",report.player_damage)
	}
	rs.challenge_message_ttl=5
}

roguelike_draw :: proc(data: rawptr, hf: ^host.Frame) {
	rs := cast(^Roguelike_Session)data
	defer if rs.challenge_message_ttl > 0 {
		alpha := min(rs.challenge_message_ttl, 1)
		ui.draw_text_centered(hf.theme, rs.challenge_message, {hf.canvas.width * 0.5, 88}, .Body,
			ui.with_alpha(rl.Color{232, 196, 112, 255}, alpha))
	}
	if game.run_has_relic_choice(&rs.run_state) {
		render.draw_relic_reward_screen(&rs.run_state, f32(rs.window.config.canvas_width),
			f32(rs.window.config.canvas_height), rs.relic_hovered, rs.relic_skip_hovered, theme = &rs.iso_renderer)
	} else if rs.reward_visible {
		render.draw_reward_screen(
			&rs.run_state,
			f32(rs.window.config.canvas_width),
			f32(rs.window.config.canvas_height),
			rs.reward_hovered_index,
			rs.reward_skip_hovered,
			theme = &rs.iso_renderer,
		)
	} else if rs.shop_visible {
		render.draw_shop_screen(
			&rs.run_state,
			f32(rs.window.config.canvas_width),
			f32(rs.window.config.canvas_height),
			rs.shop_render_state,
			theme = &rs.iso_renderer,
		)
	} else if rs.special_visible {
		render.draw_special_node_screen(
			&rs.run_state,
			f32(rs.window.config.canvas_width),
			f32(rs.window.config.canvas_height),
			rs.special_render_state,
			theme = &rs.iso_renderer,
		)
	} else if rs.route_visible {
		render.draw_run_map(
			&rs.run_state,
			f32(rs.window.config.canvas_width),
			f32(rs.window.config.canvas_height),
			rs.hovered_node,
			rs.shop_button_hovered,
			theme = &rs.iso_renderer,
		)
	} else {
		if rs.smoke_card || rs.smoke_targeting || rs.smoke_spatial || rs.smoke_object || rs.smoke_content {
			rs.iso_renderer.hovered_cell = {x = 4, y = 1}
			if rs.smoke_targeting || rs.smoke_content {
				rs.iso_renderer.hovered_cell = {x = 4, y = 2}
			} else if rs.smoke_object {
				rs.iso_renderer.hovered_cell = {x = 2, y = 1}
			}
			rs.iso_renderer.has_hovered_cell = true
		}
		rs.timeline_busy = render.renderer_blocks_player_input(&rs.iso_renderer)
		active_card_id := active_targeting_card_id(rs.card_interaction)
		if rs.timeline_busy {
			active_card_id = 0
		}
		if !rs.options.tactical.enabled && rs.mouse_inside && !rs.smoke_test && !rs.timeline_busy {
			render.update_object_target_hover(&rs.iso_renderer, &rs.room, rs.mouse_canvas, active_card_id)
		}
		if rs.smoke_encounters {
			render.update_object_target_hover(&rs.iso_renderer, &rs.room, rs.mouse_canvas, active_card_id)
		}
		if rs.options.tactical.enabled {
			render.update_tactical_view(&rs.iso_renderer, &rs.room, rs.mouse_canvas, false, true)
			render.draw_tactical_world(&rs.iso_renderer, &rs.room, active_card_id)
		} else {
		render.draw_level(&rs.iso_renderer, &rs.level_data)
		if !rs.timeline_busy {
			render.draw_enemy_intent_ground(
				&rs.iso_renderer,
				&rs.room,
				active_card_id != 0,
			)
			render.draw_card_target_range(
				&rs.iso_renderer,
				&rs.room,
				active_card_id,
			)
			render.draw_object_interaction_ground(&rs.iso_renderer, &rs.room, active_card_id)
		}
		render.draw_room(&rs.iso_renderer, &rs.room)
		if !rs.timeline_busy { render.draw_spell_path_preview(&rs.iso_renderer, &rs.room, active_card_id) }
		if !rs.timeline_busy {
			render.draw_enemy_intent_badges(&rs.iso_renderer, &rs.room)
		}
		}
		render.draw_status(&rs.iso_renderer, &rs.room, rs.window.scale_mode)
		render.draw_relic_bar(&rs.iso_renderer, &rs.room, rs.mouse_canvas, rs.mouse_inside,
			rs.card_interaction.hovered_card_id if rs.card_interaction.hovered_card_id != 0 else rs.card_interaction.selected_card_id)
		if !rs.options.tactical.enabled && (rs.mouse_inside || active_card_id != 0) {
			render.draw_object_interaction_help(&rs.iso_renderer, &rs.room, rs.mouse_canvas, active_card_id)
		}
		draw_mouse_canvas := rs.mouse_canvas
		if rs.smoke_card || rs.smoke_targeting || rs.smoke_spatial || rs.smoke_object || rs.smoke_content {
			draw_mouse_canvas = {x = 520, y = 165}
		}
		render.draw_hand(
			&rs.iso_renderer,
			&rs.room,
			rs.card_interaction.hovered_card_id,
			rs.card_interaction.selected_card_id,
			rs.card_interaction.dragged_card_id,
			draw_mouse_canvas,
		)
		if rs.options.tactical.enabled {
			if rs.tactical_controller.hologram { render.draw_hologram(&rs.iso_renderer, &rs.room) }
			render.draw_tactical_hud(&rs.iso_renderer, &rs.room, !rs.options.m7_view_smoke && (rs.tactical_controller.paused || !rl.IsWindowFocused()), rs.tactical_controller.hologram)
		}
		if rs.options.spell_lab {
			label: cstring = "DICE PRACTICE / F5 RESTART" if rs.options.dice_lab else "SPELL PRACTICE / F5 RESTART"
			rl.DrawText(label, 265, 106, 11, rl.Color{172, 219, 222, 255})
		}
		if rs.defeat_visible {
			render.draw_defeat_overlay(
				&rs.run_state,
				f32(rs.window.config.canvas_width),
				f32(rs.window.config.canvas_height),
				rs.defeat_restart_hovered,
				theme = &rs.iso_renderer,
			)
		}
	}
	if rs.m8_session.ranch.active {
		render.draw_western_bubble(&rs.iso_renderer, &rs.room, &rs.m8_session.ranch.state, rs.m8_session.ranch.card_from)
	}
	if rs.m8_session.character_open { render.draw_m8_character_panel(&rs.iso_renderer, &rs.room) }

}

roguelike_draw_window :: proc(data: rawptr, hf: ^host.Frame) {
	rs := cast(^Roguelike_Session)data
	if !rs.m8_session.ring_pending && rs.overlay != nil {
		rs.overlay(rs.window, &rs.overlay_data)
	}
}

roguelike_after_present :: proc(data: rawptr, hf: ^host.Frame) {
	rs := cast(^Roguelike_Session)data
	if rs.options.m7_view_smoke {
		done, valid := step_m7_view_smoke(&rs.m7_view_state, &rs.tactical_controller, &rs.room, &rs.iso_renderer, &rs.card_interaction)
		if done {
			if !valid { fmt.eprintln("M7 view playback regression failed"); os.exit(2) }
			fmt.println("M7 view: diagonal + defensive QTE completed; one pulse per response; timeline synchronized")
			if !run_m7_voxel_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 voxel smoke failed"); os.exit(2) }
			if !run_m7_resin_smoke(rs.window, &rs.iso_renderer, &rs.dice_renderer) { fmt.eprintln("M7 resin/dice smoke failed"); os.exit(2) }
			if !run_m7_rework_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 cards/enemies rework smoke failed"); os.exit(2) }
			if !run_m7_timed_pulse_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 timed pulse smoke failed"); os.exit(2) }
			if !run_m7_independent_world_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 independent world smoke failed"); os.exit(2) }
			if !run_m7_recovery_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 recovery smoke failed"); os.exit(2) }
			if !run_m7_polish_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 polish flow smoke failed"); os.exit(2) }
			if !run_m7_visual_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 visual feedback smoke failed"); os.exit(2) }
			if !run_m7_room_refresh_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 room refresh smoke failed"); os.exit(2) }
			if !run_m7_wall_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 wall visibility smoke failed"); os.exit(2) }
			if !run_m7_menu_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 menu smoke failed"); os.exit(2) }
			fmt.println("M7 UI: relic, reward, route, shop, rest, event, treasure and terminal screens captured")
			host.quit(hf)
			return
		}
	}
	if rs.smoke_test {
		rs.smoke_frame_count += 1
		if rs.smoke_frame_count >= 3 {
			if rs.spell_smoke != .None {
				switch rs.spell_smoke {
				case .Firebomb: rl.TakeScreenshot("odin_pp_firebomb_spell.png")
				case .Dice: rl.TakeScreenshot("odin_pp_dice.png")
				case .Dice_Pool: rl.TakeScreenshot("odin_pp_dice_pool.png")
				case .Chain: rl.TakeScreenshot("odin_pp_chain.png")
				case .Preview: rl.TakeScreenshot("odin_pp_spell_preview.png")
				case .Sunder_Preview: rl.TakeScreenshot("odin_pp_sunder_preview.png")
				case .Barrage: rl.TakeScreenshot("odin_pp_barrage.png")
				case .Venom: rl.TakeScreenshot("odin_pp_twin_venom.png")
				case .None:
				}
				if !spell_smoke_is_preview(rs.spell_smoke) && !finish_spell_smoke(&rs.room, &rs.iso_renderer) {
					fmt.eprintln("spell replay failed"); os.exit(2)
				}
			} else if rs.smoke_family != .Scattered {
				switch rs.smoke_family {
				case .Pillars: rl.TakeScreenshot("odin_pp_pillars.png")
				case .Ring: rl.TakeScreenshot("odin_pp_ring.png")
				case .Twin_Courts: rl.TakeScreenshot("odin_pp_courts.png")
				case .Asymmetric: rl.TakeScreenshot("odin_pp_cover.png")
				case .Scattered:
				}
			} else if rs.smoke_relics {
				rl.TakeScreenshot("odin_pp_relics.png")
			} else if rs.smoke_relic_combat {
				rl.TakeScreenshot("odin_pp_relic_combat.png")
			} else if rs.smoke_sprites {
				rl.TakeScreenshot("odin_pp_sprites.png")
			} else if rs.smoke_generation {
				rl.TakeScreenshot("odin_pp_procedural_room.png")
			} else if rs.smoke_map {
				rl.TakeScreenshot("odin_pp_route.png")
			} else if rs.smoke_status {
				rl.TakeScreenshot("odin_pp_status.png")
			} else if rs.smoke_loot {
				rl.TakeScreenshot("odin_pp_loot.png")
			} else if rs.smoke_card {
				rl.TakeScreenshot("odin_pp_card_drag.png")
			} else if rs.smoke_targeting {
				rl.TakeScreenshot("odin_pp_advanced_targeting.png")
			} else if rs.smoke_spatial {
				rl.TakeScreenshot("odin_pp_spatial_targeting.png")
			} else if rs.smoke_object {
				rl.TakeScreenshot("odin_pp_ice_block.png")
			} else if rs.smoke_fire {
				rl.TakeScreenshot("odin_pp_fire.png")
				timeline_finished := render.update_renderer_event_timeline(&rs.iso_renderer, 1000)
				assert(timeline_finished)
				assert(!render.renderer_timeline_is_busy(&rs.iso_renderer))
				assert(rs.iso_renderer.timeline.update_failures == 0)
				assert(game.entity_exists(&rs.room, rs.smoke_fire_entity))
				presentation_fire, fire_visible := render.presentation_grid_object(
					&rs.iso_renderer.timeline,
					rs.smoke_fire_entity,
				)
				assert(fire_visible && presentation_fire.visible &&
				       presentation_fire.kind == .Fire)
			} else if rs.smoke_content {
				rl.TakeScreenshot("odin_pp_content_pass.png")
			} else if rs.smoke_movement {
				rl.TakeScreenshot("odin_pp_enemy_movement.png")
			} else if rs.smoke_timeline {
				rl.TakeScreenshot("odin_pp_timeline.png")
			} else if rs.smoke_deck_flow {
				rl.TakeScreenshot("odin_pp_deck_flow.png")
			} else if rs.smoke_refocus {
				rl.TakeScreenshot("odin_pp_refocus.png")
			} else if rs.smoke_reward {
				rl.TakeScreenshot("odin_pp_reward.png")
			} else if rs.smoke_shop {
				rl.TakeScreenshot("odin_pp_shop.png")
			} else if rs.smoke_rest {
				rl.TakeScreenshot("odin_pp_rest.png")
			} else if rs.smoke_event {
				rl.TakeScreenshot("odin_pp_event.png")
			} else if rs.smoke_treasure {
				rl.TakeScreenshot("odin_pp_treasure.png")
			} else if rs.smoke_special_result {
				rl.TakeScreenshot("odin_pp_special_result.png")
			} else if rs.smoke_intents {
				rl.TakeScreenshot("odin_pp_enemy_intents.png")
			} else if rs.smoke_tactics {
				rl.TakeScreenshot("odin_pp_tactics.png")
			} else if rs.smoke_encounters {
				rl.TakeScreenshot("odin_pp_encounters.png")
			} else if rs.smoke_miniboss {
				rl.TakeScreenshot("odin_pp_miniboss.png")
			} else if rs.smoke_furnace {
				rl.TakeScreenshot("odin_pp_furnace.png")
				finished := render.update_renderer_event_timeline(&rs.iso_renderer, 1000)
				assert(finished && rs.iso_renderer.timeline.update_failures == 0)
			} else if rs.smoke_archetypes {
				rl.TakeScreenshot("odin_pp_enemy_archetypes.png")
			} else if rs.smoke_defeat {
				rl.TakeScreenshot("odin_pp_defeat.png")
			} else {
				rl.TakeScreenshot("odin_pp_isometric.png")
			}
			host.quit(hf)
			return
		}
	}

}

roguelike_destroy :: proc(data: rawptr) {
	rs := cast(^Roguelike_Session)data
	if rs.attached {
		rl.EnableCursor()
		if rs.playtest_session_ptr != nil && !rs.playtest_report_written {
			rs.playtest_report_written = finish_seed_playtest_report(
				rs.playtest_session_ptr,
				rs.run_seed,
				rs.options.playtest_output,
				playtest_outcome_for_state(&rs.run_state, &rs.room),
				&rs.room,
			)
			if !rs.playtest_report_written {
				fmt.eprintln("failed to write playtest report on exit")
			}
		}

		if rs.sprites_loaded {
			render.unload_sprite_assets(&rs.iso_renderer.sprite_assets)
		}
		if rs.playtest_report && !write_m7_metrics(&rs.run_state.player, rs.run_seed, rs.options.playtest_output) {
			fmt.eprintln("failed to write M7 metrics")
		}
		render.destroy_tactical_assets(&rs.iso_renderer)
		combatdebug.destroy_playtest_session(&rs.playtest_session)
		render.destroy_dice_renderer(&rs.dice_renderer)
	}
	if rs.room_created {
		game.destroy_room(&rs.room)
	}
	if rs.run_created {
		game.destroy_run(&rs.run_state)
	}
	level.destroy(&rs.level_data)
	delete(rs.challenge_message)
	free(rs)
}
