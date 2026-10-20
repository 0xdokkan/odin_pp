package devtools
import run_session "../run"

import "core:fmt"
import "core:os"
import host "../engine/host"
import game "../game"

// Scripted fixtures and capture dispatch. These hooks run at the same attach
// and after-present boundaries as the interactive scene, preserving smoke order.

prepare_smoke_card_drag :: proc(room: ^game.Room, definition_id: game.Card_Id) -> u32 {
	assert(room != nil && room.player != nil)
	deck := &room.player.deck
	for index in 0..<deck.hand_count {
		if deck.hand[index].definition_id == definition_id {
			return deck.hand[index].id
		}
	}
	for index in 0..<deck.draw_count {
		if deck.draw_pile[index].definition_id == definition_id {
			deck.hand[0], deck.draw_pile[index] = deck.draw_pile[index], deck.hand[0]
			assert(game.validate_deck_state(deck))
			return deck.hand[0].id
		}
	}
	panic("smoke card definition is missing from hand and draw pile")
}

available_node_of_kind :: proc(run: ^game.Run_State, kind: game.Node_Kind) -> game.Node_Id {
	for choice in game.available_nodes(run) {
		node, found := game.node_at(run, choice)
		if found && node.kind == kind {
			return choice
		}
	}
	return game.INVALID_NODE_ID
}

demo_seed_with_first_special :: proc(start_seed: u64, kind: game.Node_Kind) -> (u64, bool) {
	if !game.node_kind_is_special(kind) {
		return 0, false
	}
	for offset in u64(0)..<u64(512) {
		seed := start_seed+offset
		route_map, ok := game.generate_run_map(run_session.DEMO_RUN_CONFIG, seed)
		if !ok {
			continue
		}
		found := false
		root := &route_map.nodes[0]
		for index in 0..<root.outgoing_count {
			if route_map.nodes[int(root.outgoing[index])].kind == kind {
				found = true
				break
			}
		}
		game.destroy_run_map(&route_map)
		if found {
			return seed, true
		}
	}
	return 0, false
}

run_attached :: proc(rs: ^run_session.Roguelike_Session, options: Tool_Options) -> run_session.Session_Start {
	if options.m7_view_smoke {
		game.skip_run_relic(&rs.run_state)
		if !prepare_tactical_view_room(&rs.level_data, &rs.run_state, &rs.room) { return .Failed }
	}

	if options.m8_view_smoke {
		if !run_m8_view_smoke(rs.window, &rs.iso_renderer, &rs.dice_renderer) { fmt.eprintln("M8 native smoke failed"); os.exit(2) }
		return .Finished
	}
	if options.western_smoke {
		if !run_western_smoke(rs.window, &rs.iso_renderer, &rs.dice_renderer) { fmt.eprintln("6 RANCH 7 smoke failed"); os.exit(2) }
		return .Finished
	}
	if options.mechanics_lab_smoke {
		if !run_mechanics_lab_smoke(rs.window, &rs.iso_renderer, &rs.dice_renderer) { fmt.eprintln("mechanics lab smoke failed"); os.exit(2) }
		return .Finished
	}
	if options.effect_window_smoke {
		if !run_effect_window_smoke(rs) { fmt.eprintln("effect window smoke failed"); os.exit(2) }
		return .Finished
	}
	if options.m9_lab != .None {
		run_m9_lab(rs.window, &rs.iso_renderer, options.m9_lab)
		return .Finished
	}
	if options.m9_smoke {
		if !run_m9_view_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M9 native smoke failed"); os.exit(2) }
		return .Finished
	}
	if options.dice_set_lab || options.dice_set_smoke {
		if !run_dice_set_lab(rs.window, &rs.iso_renderer, &rs.dice_renderer, options.dice_set_smoke) {
			fmt.eprintln("Dice set lab failed")
			os.exit(2)
		}
		return .Finished
	}
	if options.arena_view_smoke {
		if !run_arena_view_smoke(rs.window, &rs.iso_renderer, &rs.dice_renderer) { fmt.eprintln("Arena native smoke failed"); os.exit(2) }
		return .Finished
	}

	return .Ready
}

scripted_after_present :: proc(rs: ^run_session.Roguelike_Session, hf: ^host.Frame) {
	if rs.diagnostics.scripted {
		done, valid := step_tactical_view_smoke(cast(^Tactical_View_Smoke)rs.diagnostics.data, &rs.tactical_controller, &rs.room, &rs.iso_renderer, &rs.card_interaction)
		if done {
			if !valid { fmt.eprintln("M7 view playback regression failed"); os.exit(2) }
			fmt.println("M7 view: diagonal + defensive QTE completed; one pulse per response; timeline synchronized")
			if !run_tactical_voxel_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 voxel smoke failed"); os.exit(2) }
			if !run_tactical_resin_smoke(rs.window, &rs.iso_renderer, &rs.dice_renderer) { fmt.eprintln("M7 resin/dice smoke failed"); os.exit(2) }
			if !run_tactical_rework_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 cards/enemies rework smoke failed"); os.exit(2) }
			if !run_tactical_timed_pulse_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 timed pulse smoke failed"); os.exit(2) }
			if !run_tactical_independent_world_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 independent world smoke failed"); os.exit(2) }
			if !run_tactical_recovery_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 recovery smoke failed"); os.exit(2) }
			if !run_tactical_polish_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 polish flow smoke failed"); os.exit(2) }
			if !run_tactical_visual_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 visual feedback smoke failed"); os.exit(2) }
			if !run_tactical_room_refresh_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 room refresh smoke failed"); os.exit(2) }
			if !run_tactical_wall_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 wall visibility smoke failed"); os.exit(2) }
			if !run_tactical_menu_smoke(rs.window, &rs.iso_renderer) { fmt.eprintln("M7 menu smoke failed"); os.exit(2) }
			fmt.println("M7 UI: relic, reward, route, shop, rest, event, treasure and terminal screens captured")
			host.quit(hf)
			return
		}
	}
}

configure :: proc(rs: ^run_session.Roguelike_Session, options: Tool_Options) -> bool {
	rs.options.persist_profile = rs.options.persist_profile && options.smoke_mode_count == 0 && !options.dice_set_lab && options.m9_lab == .None
	rs.options.procedural_rooms = rs.options.procedural_rooms && !options.smoke_playtest
	rs.diagnostics.capture_input = capture_input
	if options.effect_window_smoke {
		seed, found := demo_seed_with_first_special(rs.options.seed, .Shop)
		if !found { return false }
		rs.options.seed = seed
	}
	if options.m7_view_smoke {
		rs.diagnostics.scripted = true
		rs.diagnostics.data = new(Tactical_View_Smoke)
		rs.diagnostics.after_present = scripted_after_present
		rs.diagnostics.destroy = proc(data: rawptr) { free(cast(^Tactical_View_Smoke)data) }
	}
	return true
}
run_headless :: proc(rs: ^run_session.Roguelike_Session, options: Tool_Options) -> run_session.Session_Start {
	if options.smoke_playtest {
		if !run_headless_playtest_smoke(&rs.run_state, &rs.room, rs.run_seed, rs.options.playtest_output) { return .Failed }
		fmt.println("wrote headless playtest report")
		return .Finished
	}
	if options.m7_smoke {
		return .Finished if run_tactical_headless_smoke() else .Failed
	}
	return .Ready
}
capture_input :: proc(rs: ^run_session.Roguelike_Session, hf: ^host.Frame) {
		frame := Input_Diagnostic_Frame{dt = rs.frame_time, focused = rs.frame_input.focused,
			route_map = rs.show_route_map, scripted = rs.diagnostics.scripted, mouse_left = rs.frame_input.left_down,
			shift = run_session.run_down(rs.frame_input, .Dodge_Modifier)}
		for action, index in run_session.RUN_WALK_ACTIONS { frame.wasd_down[index] = run_session.run_down(rs.frame_input, action) }
		path, saved := write_input_diagnostic(&rs.run_state, &rs.room, &rs.iso_renderer, &rs.tactical_controller,
			&rs.card_interaction, &rs.gameplay_buffer, frame)
		if saved { fmt.printf("Input snapshot saved: %s\n", path); delete(path) }
		else { fmt.eprintln("Could not save input snapshot (write error or 256 captures already present)") }
}
