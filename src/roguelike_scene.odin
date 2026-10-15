package main

import "core:fmt"
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
// Startup (roguelike_startup.odin) is split around the window; lifecycle
// transitions and teardown live in roguelike_lifecycle.odin. This scene owns
// frame ordering, focus, menus and host activity handoffs.
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
	reward_hovered_index:    int,
	reward_skip_hovered:     bool,
	shop_render_state:       render.Shop_Render_State,
	special_render_state:    render.Special_Node_Render_State,
	// MOSTRA EFFETTO (effect_window.odin): open, it owns the frame.
	effect_window:           Effect_Window,
	smoke_frame_count:       int,
	smoke_fire_entity:       game.Entity_Ref,

	// The mechanics lab's sounds (render/lab_sounds.odin).
	lab_bank:                audio.Lab_Bank,

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
	defeat_hovered:          render.Defeat_Choice,
	pause_hovered:           render.Pause_Choice,
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
	// PROVA MECCANICHE: the endless arena's arrivals.
	sandbox:                 game.Sandbox_State,

	// Minigame challenge feedback shown after returning to the run.
	challenge_message:       string,
	challenge_message_ttl:   f32,
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
	// The view behind the player's eyes gives the mouse back.
	if rs.attached && rs.options.tactical.enabled { release_first_person_mouse(&rs.tactical_controller, &rs.room) }
	// The room's ambience waits for the scene to come back.
	audio.lab_ambience(&rs.lab_bank, false)
}

// The mechanics lab's sounds: what the board pass queued, and the room's
// ambience, at the player's effects volume (and silent when muted).
roguelike_lab_sounds :: proc(rs: ^Roguelike_Session, hf: ^host.Frame) {
	bank := hf.audio
	if bank == nil || !bank.ready || bank.muted || !audio.lab_bank_load(&rs.lab_bank) {
		render.play_lab_sounds(&rs.iso_renderer, nil, 0)
		audio.lab_ambience(&rs.lab_bank, false)
		return
	}
	render.play_lab_sounds(&rs.iso_renderer, &rs.lab_bank, bank.sfx_volume)
	audio.lab_ambience(&rs.lab_bank, rs.run_state.phase == .In_Room, .Amb_Crypt_Loop, bank.sfx_volume)
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
	// MOSTRA EFFETTO: while it is open the frame is its own. Nothing below reads
	// a key or a click, and none of the run's clocks, timelines and arrivals runs.
	if rs.effect_window.open {
		update_effect_window_in_run(rs, hf)
		return
	}
	if rs.from_launcher && hf.focused && rl.IsKeyPressed(.F10) {
		host.pop(hf)
		return
	}
	// The pause menu: resume, or back to the main menu.
	rs.pause_hovered = .None
	if rs.tactical_controller.paused && hf.mouse_inside {
		rs.pause_hovered = render.pause_choice_at_point(&rs.iso_renderer, {hf.mouse.x, hf.mouse.y}, rs.from_launcher)
	}
	if rs.pause_hovered != .None && hf.focused && rl.IsMouseButtonPressed(.LEFT) {
		if rs.pause_hovered == .Menu { host.pop(hf); return }
		rs.tactical_controller.paused = false
		rs.iso_renderer.frame_clock_valid = false
		rs.pause_hovered = .None
	}
	rs.iso_renderer.tactical.pause_hovered, rs.iso_renderer.tactical.pause_menu = rs.pause_hovered, rs.from_launcher
	if !rs.smoke_test && rl.IsKeyPressed(.F4) {
		speed := f32(1) if rs.iso_renderer.playback_speed >= 4 else min(f32(4), rs.iso_renderer.playback_speed*2)
		render.set_renderer_playback_speed(&rs.iso_renderer, speed)
	}
	rs.frame_time = (f32(1.0/60.0) if rs.options.m7_view_smoke else hf.dt)
	rs.m8_modal = false
	m8_mouse, m8_mouse_inside := view.Vec2{hf.mouse.x,hf.mouse.y}, hf.mouse_inside
	// FIRST PERSON SHOOTER: behind the player's eyes the mouse is the view's
	// (first_person_input.odin); its hidden pointer reaches nothing on the
	// board, the hand or the HUD.
	if rs.options.tactical.enabled && render.first_person_owns_pointer(&rs.iso_renderer, &rs.room) { m8_mouse_inside = false }
	if !rs.smoke_test && !rs.options.m7_view_smoke && rs.options.tactical.enabled {
		rs.m8_modal = update_m8_session(&rs.m8_session, &rs.room, &rs.iso_renderer, &rs.tactical_controller,
			&rs.card_interaction, &rs.gameplay_buffer, rs.run_state.phase == .In_Room &&
			!rs.show_route_map && !game.run_has_relic_choice(&rs.run_state), rs.frame_time, m8_mouse, m8_mouse_inside)
	}
	// MOSTRA EFFETTO asked from the sheet or the card inspector: the frame is
	// the window's.
	if roguelike_take_effect_request(rs) { return }
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
	if !rs.m8_modal && !first_person_pause_pressed(&rs.room) && !rs.smoke_furnace && rs.spell_smoke == .None &&
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
	rs.defeat_hovered = .None
	if rs.run_state.phase == .Defeat && rs.mouse_inside {
		rs.defeat_hovered = render.defeat_choice_at_point(f32(rs.window.config.canvas_width),
			f32(rs.window.config.canvas_height), rs.mouse_canvas, rs.from_launcher)
	}
	// After a defeat: back to the main menu, or out of the game.
	if !rs.m8_modal && rl.IsMouseButtonPressed(.LEFT) {
		if rs.defeat_hovered == .Menu { host.pop(hf); return }
		if rs.defeat_hovered == .Quit { host.quit(hf); return }
	}
	restart_requested := !rs.m8_modal && (rl.IsKeyPressed(.F5) ||
		(rs.run_state.phase == .Defeat && rl.IsKeyPressed(.ENTER)) ||
		(rs.defeat_hovered == .Restart && rl.IsMouseButtonPressed(.LEFT)))
	if restart_requested && !roguelike_restart(rs, hf) { return }

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
		// A flat board stands in 3D behind the player's eyes (first_person.odin).
		render.sync_first_person_board(&rs.iso_renderer, &rs.room, rs.options.scene_3d, rs.window.canvas)
		// The view never under the HUD's controls; MOSTRA EFFETTO's buttons light
		// under the mouse wherever they are (roguelike_pointer_inside).
		view_inside, hud_inside := roguelike_pointer_inside(rs, rl.IsWindowFocused())
		render.update_tactical_view(&rs.iso_renderer, &rs.room, rs.mouse_canvas, view_inside)
		render.tactical_hud_pointer(&rs.iso_renderer, rs.mouse_canvas, hud_inside)
		render.update_tactical_atmosphere(&rs.iso_renderer, rs.frame_time if rs.options.m7_view_smoke || (!rs.tactical_controller.paused && rl.IsWindowFocused()) else 0)
		if !rs.options.m7_view_smoke && !rs.m8_modal { tactical_input_blocked = update_tactical_controller(&rs.tactical_controller, &rs.room, &rs.iso_renderer,
			&rs.card_interaction, &rs.gameplay_buffer, rs.frame_time,
			rs.run_state.phase == .In_Room && !relic_visible && !rs.route_visible && !rs.options.m7_view_smoke,
			rs.mouse_canvas, rs.mouse_inside, rs.playtest_session_ptr, hf.profile.settings.mouse_sensitivity if hf.profile != nil else 1) } else {
			tactical_input_blocked = true
			// A modal over the board: the view gives the mouse back.
			release_first_person_mouse(&rs.tactical_controller, &rs.room)
		}
		// A tick move waiting for its diagonal partner never outlives a frame in
		// which the player's lane is not free.
		if tactical_input_blocked { clear_gameplay_command_buffer(&rs.gameplay_buffer) }
	}
	// The board's characters are living cards, wherever the board is 3D (a flat
	// one too, while the player is behind his eyes).
	render.set_living_cards(&rs.iso_renderer, rs.iso_renderer.tactical.scene_3d if rs.options.tactical.enabled else rs.options.scene_3d)
	render.set_mechanics_lab(&rs.iso_renderer, rs.options.mechanics_lab, rs.from_launcher)
	// The game shows seals and ground; the lab compares the displays with F6.
	if !rs.options.mechanics_lab { rs.iso_renderer.tactical.intent_display = .Both }
	else if hf.focused && rl.IsKeyPressed(.F6) { render.cycle_intent_display(&rs.iso_renderer) }
	// F7: the arena cleared for the Canna da Pesca (mechanics_lab_begin_fishing).
	if rs.options.mechanics_lab && hf.focused && !rs.m8_modal && rl.IsKeyPressed(.F7) { _ = mechanics_lab_begin_fishing(rs) }
	// Arrivals follow the running board: never paused, in a modal or mid-animation.
	if rs.options.mechanics_lab && !rs.m8_modal && !rs.tactical_controller.paused && rl.IsWindowFocused() &&
	   rs.run_state.phase == .In_Room && !render.renderer_timeline_is_busy(&rs.iso_renderer) {
		_, _ = game.sandbox_tick(&rs.room, &rs.sandbox, rs.frame_time)
	}
	if rs.options.mechanics_lab { roguelike_lab_sounds(rs, hf) }

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

		// MOSTRA EFFETTO under a card, or I on the card under the mouse: never a
		// choice as well.
		if roguelike_effect_entry(rs, rs.mouse_inside && rl.IsMouseButtonPressed(.LEFT), rs.mouse_canvas, rl.IsKeyPressed(.I)) { return }
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
			// MOSTRA EFFETTO of an offer or of the owned card chosen (or I): never
			// a purchase, a page or a way out as well.
			if roguelike_effect_entry(rs, rs.mouse_inside && rl.IsMouseButtonPressed(.LEFT), rs.mouse_canvas, rl.IsKeyPressed(.I)) { return }
			input := Run_Menu_Input{
				choice_index = pressed_hand_slot(), previous_page = rl.IsKeyPressed(.LEFT), next_page = rl.IsKeyPressed(.RIGHT),
				upgrade = rl.IsKeyPressed(.U), remove = rl.IsKeyPressed(.R),
				confirm = rl.IsKeyPressed(.ENTER), cancel = rl.IsKeyPressed(.ESCAPE),
				clicked = rs.mouse_inside && rl.IsMouseButtonPressed(.LEFT),
			}
			if step_shop_menu(&rs.run_state, &rs.shop_render_state, input, shop_hit) {
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
			// MOSTRA EFFETTO of the rest's owned card chosen (or I): never a
			// choice as well.
			if roguelike_effect_entry(rs, rs.mouse_inside && rl.IsMouseButtonPressed(.LEFT), rs.mouse_canvas, rl.IsKeyPressed(.I)) { return }
			input := Run_Menu_Input{
				choice_index = pressed_hand_slot(), previous_page = rl.IsKeyPressed(.LEFT), next_page = rl.IsKeyPressed(.RIGHT),
				upgrade = rl.IsKeyPressed(.U), leave = rl.IsKeyPressed(.L), confirm = rl.IsKeyPressed(.ENTER),
				clicked = rs.mouse_inside && rl.IsMouseButtonPressed(.LEFT),
			}
			if step_special_node_menu(&rs.run_state, &rs.special_render_state, input, special_hit) {
				rs.special_visible = false
				rs.route_visible = true
				rs.show_route_map = true
			}
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
			if selected { roguelike_enter_node(rs, selected_node) }
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
			// The player's own action, its animation or its timed seconds, owns
			// the input lane: a command pressed now is dropped, never kept for when
			// the action ends. Only a press made after it acts.
			rs.timeline_busy = render.renderer_blocks_player_input(&rs.iso_renderer) || game.tactical_player_busy(&rs.room)
			command, has_command := poll_gameplay_command(
				&rs.room,
				&rs.iso_renderer,
				&rs.card_interaction,
				rs.mouse_canvas,
				rs.mouse_inside,
				!rs.timeline_busy,
				rs.options.debug_abilities,
			)
			if ready, has_ready := route_gameplay_command(&rs.gameplay_buffer, &rs.room, rs.timeline_busy,
				command, has_command, rs.frame_time, render.first_person_keys(&rs.iso_renderer)); has_ready {
				commit_gameplay_command(
					&rs.room,
					&rs.iso_renderer,
					&rs.card_interaction,
					ready,
					rs.playtest_session_ptr,
				)
			}
		}
		roguelike_finish_room(rs)
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
	// MOSTRA EFFETTO: the frozen run as it was last drawn, under the window.
	if rs.effect_window.open && rs.effect_window.backdrop_ready {
		draw_effect_window_backdrop(&rs.effect_window, hf.canvas.width, hf.canvas.height)
		draw_effect_window(&rs.effect_window, &rs.iso_renderer, hf.canvas.width, hf.canvas.height)
		return
	}
	defer if rs.challenge_message_ttl > 0 && !rs.effect_window.open {
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
			// FERETRO's aim shows while a click would loose an arrow.
			rs.iso_renderer.tactical.arrow_aim = arrows_aiming(&rs.room) && !rs.m8_modal && !rs.timeline_busy &&
				game.tactical_allows_action(&rs.room) && !game.tactical_player_busy(&rs.room)
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
		if rs.options.mechanics_lab { render.draw_mechanics_lab_banner(&rs.iso_renderer, &rs.room) }
		if rs.options.spell_lab {
			label: cstring = "DICE PRACTICE / F5 RESTART" if rs.options.dice_lab else "SPELL PRACTICE / F5 RESTART"
			rl.DrawText(label, 265, 106, 11, rl.Color{172, 219, 222, 255})
		}
		if rs.defeat_visible {
			render.draw_defeat_overlay(
				&rs.run_state,
				f32(rs.window.config.canvas_width),
				f32(rs.window.config.canvas_height),
				rs.defeat_hovered,
				rs.from_launcher,
				theme = &rs.iso_renderer,
			)
		}
	}
	if rs.m8_session.ranch.active {
		render.draw_western_bubble(&rs.iso_renderer, &rs.room, &rs.m8_session.ranch.state, rs.m8_session.ranch.card_from)
	}
	if rs.m8_session.character_open { render.draw_m8_character_panel(&rs.iso_renderer, &rs.room, rs.m8_session.sheet) }
	// MOSTRA EFFETTO over everything (no backdrop: the run drawn as it is).
	if rs.effect_window.open { draw_effect_window(&rs.effect_window, &rs.iso_renderer, hf.canvas.width, hf.canvas.height) }
}

roguelike_draw_window :: proc(data: rawptr, hf: ^host.Frame) {
	rs := cast(^Roguelike_Session)data
	// MOSTRA EFFETTO: its stage on the window's own pixels; the run's dice wait.
	if rs.effect_window.open {
		draw_window_effect_stage(rs.window, &rs.effect_window)
		return
	}
	if !rs.m8_session.ring_pending && rs.overlay != nil {
		rs.overlay(rs.window, &rs.overlay_data)
	}
}
