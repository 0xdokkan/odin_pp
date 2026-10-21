package run
import activities "../activities"

import "core:fmt"
import rl "vendor:raylib"
import app "../engine/app"
import audio "../engine/audio"
import combatdebug "../combatdebug"
import host "../engine/host"
import input "../engine/input"
import ui "../engine/ui"
import game "../game"
import level "../level"
import render "../render"
import view "../engine/view"

// The roguelike run as a host scene. Everything `main` used to keep in locals
// lives here on the heap. Room owns a separate log; the renderer keeps its
// large timeline. Stable ownership preserves borrowed assets and activity links.
// Startup (roguelike_startup.odin) is split around the window; lifecycle
// transitions and teardown live in roguelike_lifecycle.odin. This scene owns
// frame ordering, focus, menus and host activity handoffs.
Roguelike_Session :: struct {
	window:                  ^app.Window,
	options:                 Options,
	actions:                 input.Action_Map(Run_Action),
	diagnostics:             Run_Diagnostics,
	frame_input:             Run_Input,
	input_history:           Run_Input_History,
	procedural_rooms:        bool,
	level_data:              level.Level,
	run_seed:                u64,
	run_state:               game.Run_State,
	player_activities:              Player_Activities,
	room:                    game.Room,
	dice_renderer:           render.Dice_Renderer,
	playtest_session:        combatdebug.Playtest_Session,
	playtest_session_ptr:    ^combatdebug.Playtest_Session,
	playtest_report_written: bool,
	iso_renderer:            render.Renderer,
	tactical_controller:     Tactical_Controller,
	show_route_map:          bool,
	card_interaction:        Card_Interaction_State,
	gameplay_buffer:         Buffered_Gameplay_Command,
	reward_hovered_index:    int,
	reward_skip_hovered:     bool,
	shop_render_state:       render.Shop_Render_State,
	special_render_state:    render.Special_Node_Render_State,
	// MOSTRA EFFETTO (effect_window.odin): open, it owns the frame.
	effect_window:           Effect_Window,

	// The mechanics lab's sounds (render/lab_sounds.odin).
	lab_bank:                audio.Lab_Bank,

	// Which resources exist, so destroy mirrors the old deferred cleanup.
	run_created:             bool,
	room_created:            bool,
	attached:                bool,
	sprites_loaded:          bool,

	// Values computed by update and consumed by draw in the same frame.
	frame_time:              f32,
	activity_modal:                bool,
	mouse_canvas:            view.Vec2,
	mouse_inside:            bool,
	defeat_hovered:          render.Defeat_Choice,
	pause_hovered:           render.Pause_Choice,
	timeline_busy:           bool,
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
	rs.input_history = {}
	clear_card_interaction(&rs.card_interaction)
	clear_gameplay_command_buffer(&rs.gameplay_buffer)
	rs.mouse_inside = false
	rs.tactical_controller.was_focused = false
	rs.iso_renderer.frame_clock_valid = false
	rs.iso_renderer.tactical.world_orbit.dragging = false
	rs.iso_renderer.tactical.hologram_orbit.dragging = false
	// The view behind the player's eyes gives the mouse back.
	if rs.attached { release_first_person_mouse(&rs.tactical_controller, &rs.room) }
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
	rs.frame_input = map_run_input(&rs.actions, hf.devices, hf.focused && hf.window_focused, &rs.input_history)
	if !rs.diagnostics.scripted && (!hf.focused || !hf.window_focused) {
		roguelike_suspend_input(rs)
		return
	}
	// MOSTRA EFFETTO: while it is open the frame is its own. Nothing below reads
	// a key or a click, and none of the run's clocks, timelines and arrivals runs.
	if rs.effect_window.open {
		update_effect_window_in_run(rs, hf)
		return
	}
	if update_run_session_controls(rs, hf) { return }
	if update_run_activity_overlay(rs, hf) { return }
	rs.timeline_busy = render.renderer_timeline_is_busy(&rs.iso_renderer)
	if !rs.activity_modal && rs.room.phase != .Combat && !game.run_has_relic_choice(&rs.run_state) && run_pressed(rs.frame_input, .Route_Map) && route_map_toggle_is_allowed(&rs.run_state, &rs.room, &rs.iso_renderer) {
		rs.show_route_map = !rs.show_route_map
		if rs.show_route_map {
			clear_card_interaction(&rs.card_interaction)
			clear_gameplay_command_buffer(&rs.gameplay_buffer)
		}
	}
	screen := run_screen(&rs.run_state, rs.show_route_map)
	tactical_input_blocked := update_run_board_view(rs, hf, screen)
	if screen != .Board {
		if update_run_screen(rs, screen) { return }
	} else {
		update_run_board_commands(rs, tactical_input_blocked)
	}
	update_run_dice_overlay(rs)
	rs.challenge_message_ttl = max(rs.challenge_message_ttl-hf.dt, 0)
}

// Return true when a host transition or modal consumes the rest of the frame.
@(private = "file")
update_run_session_controls :: proc(rs: ^Roguelike_Session, hf: ^host.Frame) -> bool {
	if rs.from_launcher && hf.focused && run_pressed(rs.frame_input, .Main_Menu) {
		host.pop(hf)
		return true
	}
	// The pause menu: resume, or back to the main menu.
	rs.pause_hovered = .None
	if rs.tactical_controller.paused && hf.mouse_inside {
		rs.pause_hovered = render.pause_choice_at_point(&rs.iso_renderer, {hf.mouse.x, hf.mouse.y}, rs.from_launcher)
	}
	if rs.pause_hovered != .None && hf.focused && rs.frame_input.left_pressed {
		if rs.pause_hovered == .Menu { host.pop(hf); return true }
		rs.tactical_controller.paused = false
		rs.iso_renderer.frame_clock_valid = false
		rs.pause_hovered = .None
	}
	rs.iso_renderer.tactical.pause_hovered, rs.iso_renderer.tactical.pause_menu = rs.pause_hovered, rs.from_launcher
	if run_pressed(rs.frame_input, .Animation_Speed) {
		speed := f32(1) if rs.iso_renderer.playback_speed >= 4 else min(f32(4), rs.iso_renderer.playback_speed*2)
		render.set_renderer_playback_speed(&rs.iso_renderer, speed)
	}
	return false
}

@(private = "file")
update_run_activity_overlay :: proc(rs: ^Roguelike_Session, hf: ^host.Frame) -> bool {
	rs.frame_time = (f32(1.0/60.0) if rs.diagnostics.scripted else hf.dt)
	rs.activity_modal = false
	m8_mouse, m8_mouse_inside := view.Vec2{hf.mouse.x,hf.mouse.y}, hf.mouse_inside
	// FIRST PERSON SHOOTER: behind the player's eyes the mouse is the view's
	// (first_person_input.odin); its hidden pointer reaches nothing on the
	// board, the hand or the HUD.
	if render.first_person_owns_pointer(&rs.iso_renderer, &rs.room) { m8_mouse_inside = false }
	if !rs.diagnostics.scripted {
		rs.activity_modal = update_player_activities(&rs.player_activities, &rs.room, &rs.iso_renderer, &rs.tactical_controller,
			&rs.card_interaction, &rs.gameplay_buffer, rs.run_state.phase == .In_Room &&
			!rs.show_route_map && !game.run_has_relic_choice(&rs.run_state), rs.frame_time, m8_mouse, m8_mouse_inside, rs.frame_input)
	}
	// MOSTRA EFFETTO asked from the sheet or the card inspector: the frame is
	// the window's.
	if roguelike_take_effect_request(rs) { return true }
	roguelike_ranch_feedback(rs, hf)
	if roguelike_open_activity(rs,hf) {
		rs.overlay = nil
		rs.overlay_data = {}
		return true
	}
	if run_pressed(rs.frame_input, .Diagnostics) && rs.diagnostics.capture_input != nil {
		rs.diagnostics.capture_input(rs, hf)
	}
	if render.presentation_time_policy(&rs.iso_renderer.timeline) != .Cinematic {
		render.advance_sprite_assets(&rs.iso_renderer.sprite_assets, rs.frame_time)
	}
	if !rs.activity_modal && !first_person_pause_pressed(&rs.room, rs.frame_input) &&
	   (rs.diagnostics.scripted || (!rs.tactical_controller.paused && rs.tactical_controller.was_focused && rs.frame_input.focused)) {
		render.update_renderer_frame_timeline(&rs.iso_renderer, rs.frame_time)
	}
	rs.mouse_canvas, rs.mouse_inside = m8_mouse, m8_mouse_inside
	rs.defeat_hovered = .None
	if rs.run_state.phase == .Defeat && rs.mouse_inside {
		rs.defeat_hovered = render.defeat_choice_at_point(f32(rs.window.config.canvas_width),
			f32(rs.window.config.canvas_height), rs.mouse_canvas, rs.from_launcher)
	}
	// After a defeat: back to the main menu, or out of the game.
	if !rs.activity_modal && rs.frame_input.left_pressed {
		if rs.defeat_hovered == .Menu { host.pop(hf); return true }
		if rs.defeat_hovered == .Quit { host.quit(hf); return true }
	}
	restart_requested := !rs.activity_modal && (run_pressed(rs.frame_input, .Restart) ||
		(rs.run_state.phase == .Defeat && run_pressed(rs.frame_input, .Confirm)) ||
		(rs.defeat_hovered == .Restart && rs.frame_input.left_pressed))
	if restart_requested && !roguelike_restart(rs, hf) { return true }

	return false
}

@(private = "file")
update_run_board_view :: proc(rs: ^Roguelike_Session, hf: ^host.Frame, screen: Run_Screen) -> bool {
	rs.hovered_node = game.INVALID_NODE_ID
	rs.shop_button_hovered = false
	rs.relic_hovered = -1
	rs.relic_skip_hovered = false
	tactical_input_blocked := false
	// The view never under the HUD's controls; MOSTRA EFFETTO's buttons light
	// under the mouse wherever they are (roguelike_pointer_inside).
	view_inside, hud_inside := roguelike_pointer_inside(rs, rs.frame_input.focused)
	render.update_tactical_view(&rs.iso_renderer, &rs.room, rs.mouse_canvas, view_inside, input = {
		orbit_pressed = rs.frame_input.middle_pressed, orbit_down = rs.frame_input.middle_down,
		// The wheel turns INONDAZIONE's wave while the card is aimed.
		wheel = 0 if render.flood_aim_active(&rs.iso_renderer) else rs.frame_input.wheel,
		window_mouse = {rs.frame_input.mouse_window.x, rs.frame_input.mouse_window.y},
	})
	render.tactical_hud_pointer(&rs.iso_renderer, rs.mouse_canvas, hud_inside)
	render.update_tactical_atmosphere(&rs.iso_renderer, rs.frame_time if rs.diagnostics.scripted || (!rs.tactical_controller.paused && rs.frame_input.focused) else 0)
	if !rs.diagnostics.scripted && !rs.activity_modal { tactical_input_blocked = update_tactical_controller(&rs.tactical_controller, &rs.room, &rs.iso_renderer,
		&rs.card_interaction, &rs.gameplay_buffer, rs.frame_time,
		screen == .Board && !rs.diagnostics.scripted,
		rs.mouse_canvas, rs.mouse_inside, rs.playtest_session_ptr, rs.frame_input, hf.profile.settings.mouse_sensitivity if hf.profile != nil else 1) } else {
		tactical_input_blocked = true
		// A modal over the board: the view gives the mouse back.
		release_first_person_mouse(&rs.tactical_controller, &rs.room)
	}
	// A tick move waiting for its diagonal partner never outlives a frame in
	// which the player's lane is not free.
	if tactical_input_blocked { clear_gameplay_command_buffer(&rs.gameplay_buffer) }
	// The board's characters are living cards.
	render.set_living_cards(&rs.iso_renderer, true)
	render.set_mechanics_lab(&rs.iso_renderer, rs.options.mechanics_lab, rs.from_launcher)
	// The game shows seals and ground; the lab compares the displays with F6.
	if !rs.options.mechanics_lab { rs.iso_renderer.tactical.intent_display = .Both }
	else if hf.focused && run_pressed(rs.frame_input, .Intent_Display) { render.cycle_intent_display(&rs.iso_renderer) }
	// F7: the arena cleared for the Canna da Pesca (mechanics_lab_begin_fishing).
	if rs.options.mechanics_lab && hf.focused && !rs.activity_modal && run_pressed(rs.frame_input, .Clear_Lab) { _ = mechanics_lab_begin_fishing(rs) }
	// Arrivals follow the running board: never paused, in a modal or mid-animation.
	if rs.options.mechanics_lab && !rs.activity_modal && !rs.tactical_controller.paused && rs.frame_input.focused &&
	   rs.run_state.phase == .In_Room && !render.renderer_timeline_is_busy(&rs.iso_renderer) {
		_, _ = game.sandbox_tick(&rs.room, &rs.sandbox, rs.frame_time)
	}
	if rs.options.mechanics_lab { roguelike_lab_sounds(rs, hf) }
	return tactical_input_blocked
}

@(private = "file")
update_run_board_commands :: proc(rs: ^Roguelike_Session, tactical_input_blocked: bool) {
	if !tactical_input_blocked {
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
			rs.frame_input,
		)
		if ready, has_ready := route_gameplay_command(&rs.gameplay_buffer, &rs.room, rs.timeline_busy,
			command, has_command, rs.frame_time, render.first_person_keys(&rs.iso_renderer), rs.frame_input); has_ready {
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

@(private = "file")
update_run_dice_overlay :: proc(rs: ^Roguelike_Session) {
	dice_cue, has_dice_cue := render.active_presentation_cue(&rs.iso_renderer.timeline)
	dice_visible := has_dice_cue && dice_cue.started && dice_cue.kind == .Dice_Rolled
	rs.overlay = nil
	rs.overlay_data = {}
	if dice_visible {
		rs.overlay = draw_window_dice_overlay
		rs.overlay_data = {renderer = &rs.dice_renderer, roll = dice_cue.event.dice_roll,
			progress = render.presentation_cue_progress(dice_cue), seed = dice_event_visual_seed(dice_cue.event),
			card = dice_cue.event.card_definition, outcome = render.dice_presentation_outcome(&rs.iso_renderer.timeline)}
		update_window_dice_overlay(rs.window, &rs.overlay_data)
	}

}

// A square of Tesla coils around enemies hands the duel to the catalog ring
// scene. The run waits, frozen, until roguelike_resume settles the result.
roguelike_open_activity :: proc(rs: ^Roguelike_Session, hf: ^host.Frame) -> bool {
	if !rs.room.tesla_ring.pending || rs.player_activities.ring_pending {return false}
	info, found := activities.minigame_info(activities.minigame_index_by_id("ring"))
	if !found {
		// Without a ring the spent coils simply fizzle.
		rs.room.tesla_ring={}
		return false
	}
	rs.player_activities.ring_pending=true
	rs.player_activities.ring_link=tesla_ring_link(&rs.room)
	rs.player_activities.report={}
	clear_card_interaction(&rs.card_interaction)
	clear_gameplay_command_buffer(&rs.gameplay_buffer)
	audio.play(hf.audio,.Confirm)
	host.push(hf,info.create({seed=rs.run_seed, challenge=true, payload=&rs.player_activities.ring_link}))
	return true
}

// Sounds of the ranch duel and its verdict, once per step.
roguelike_ranch_feedback :: proc(rs: ^Roguelike_Session, hf: ^host.Frame) {
	ranch := &rs.player_activities.ranch
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
	if !settle_m8_host_activity(&rs.player_activities,&rs.room,from,result) {return}
	// The board shows the duel's toll: knockouts fall and drop their loot.
	after := render.capture_room_presentation(&rs.room)
	if rs.room.recent_events.count > 0 {
		if render.renderer_blocks_player_input(&rs.iso_renderer) {render.clear_event_animations(&rs.iso_renderer)}
		_ = render.begin_renderer_event_timeline(&rs.iso_renderer,before,rs.room.recent_events,&after)
	}
	if rs.room.phase != .Combat {clear_card_interaction(&rs.card_interaction)}
	delete(rs.challenge_message)
	report := rs.player_activities.report
	reward := report.reward
	switch {
	case len(rs.player_activities.status)>0:
		rs.challenge_message=fmt.aprintf("%s",rs.player_activities.status)
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
	if !draw_run_screen(rs) {
		rs.timeline_busy = render.renderer_blocks_player_input(&rs.iso_renderer)
		active_card_id := active_targeting_card_id(rs.card_interaction)
		if rs.timeline_busy {
			active_card_id = 0
		}
		// FERETRO's aim shows while a click would loose an arrow.
		rs.iso_renderer.tactical.arrow_aim = arrows_aiming(&rs.room, rs.frame_input) && !rs.activity_modal && !rs.timeline_busy &&
			game.tactical_allows_action(&rs.room) && !game.tactical_player_busy(&rs.room)
		render.update_tactical_view(&rs.iso_renderer, &rs.room, rs.mouse_canvas, false, true)
		render.draw_tactical_world(&rs.iso_renderer, &rs.room, active_card_id)
		render.draw_status(&rs.iso_renderer, &rs.room, rs.window.scale_mode)
		render.draw_relic_bar(&rs.iso_renderer, &rs.room, rs.mouse_canvas, rs.mouse_inside,
			rs.card_interaction.hovered_card_id if rs.card_interaction.hovered_card_id != 0 else rs.card_interaction.selected_card_id)
		draw_mouse_canvas := rs.mouse_canvas
		render.draw_hand(
			&rs.iso_renderer,
			&rs.room,
			rs.card_interaction.hovered_card_id,
			rs.card_interaction.selected_card_id,
			rs.card_interaction.dragged_card_id,
			draw_mouse_canvas,
		)
		if rs.tactical_controller.hologram { render.draw_hologram(&rs.iso_renderer, &rs.room) }
		render.draw_tactical_hud(&rs.iso_renderer, &rs.room, !rs.diagnostics.scripted && (rs.tactical_controller.paused || !rs.frame_input.focused), rs.tactical_controller.hologram)
		if rs.options.mechanics_lab { render.draw_mechanics_lab_banner(&rs.iso_renderer, &rs.room) }
		if rs.options.spell_lab {
			label: cstring = "DICE PRACTICE / F5 RESTART" if rs.options.dice_lab else "SPELL PRACTICE / F5 RESTART"
			rl.DrawText(label, 265, 106, 11, rl.Color{172, 219, 222, 255})
		}
		if run_screen(&rs.run_state, rs.show_route_map) == .Defeat {
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
	if rs.player_activities.ranch.active {
		render.draw_western_bubble(&rs.iso_renderer, &rs.room, &rs.player_activities.ranch.state, rs.player_activities.ranch.card_from)
	}
	if rs.player_activities.character_open { render.draw_m8_character_panel(&rs.iso_renderer, &rs.room, rs.player_activities.sheet) }
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
	if !rs.player_activities.ring_pending && rs.overlay != nil {
		rs.overlay(rs.window, &rs.overlay_data)
	}
}
