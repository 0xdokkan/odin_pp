package run

import game "../game"
import render "../render"

// Derived every time from the run's authoritative phase. The map toggle only
// overlays a living room; it can never hide a reward, a shop or a defeat.
Run_Screen :: enum { Board, Defeat, Relic, Reward, Shop, Special, Route }

run_screen :: proc(run: ^game.Run_State, show_route_map: bool) -> Run_Screen {
	if game.run_has_relic_choice(run) { return .Relic }
	switch run.phase {
	case .Defeat: return .Defeat
	case .Reward: return .Reward
	case .Shop: return .Shop
	case .Rest, .Event, .Treasure: return .Special
	case .Choose_Path, .Victory: return .Route
	case .In_Room: return .Route if show_route_map else .Board
	}
	return .Board
}

// True means a modal took ownership of the rest of this frame. Screen changes
// themselves are game transactions; there are no parallel visibility flags.
update_run_screen :: proc(rs: ^Roguelike_Session, screen: Run_Screen) -> bool {
	width, height := f32(rs.window.config.canvas_width), f32(rs.window.config.canvas_height)
	switch screen {
	case .Board:
		return false
	case .Relic:
		clear_card_interaction(&rs.card_interaction)
		clear_gameplay_command_buffer(&rs.gameplay_buffer)
		if rs.mouse_inside {
			rs.relic_hovered = render.relic_choice_at_point(&rs.run_state,
				width, height, rs.mouse_canvas)
			rs.relic_skip_hovered = render.reward_skip_at_point(width,
				height, rs.mouse_canvas)
		}
		choice := pressed_hand_slot(rs.frame_input)
		skip := run_pressed(rs.frame_input, .Skip)
		if rs.mouse_inside && rs.frame_input.left_pressed {
			if rs.relic_hovered >= 0 { choice = rs.relic_hovered }
			if rs.relic_skip_hovered { skip = true }
		}
		if resolve_demo_relic_choice(&rs.run_state, &rs.room, choice, skip) {
			if rs.options.playtest_report && rs.playtest_session_ptr == nil {
				started := begin_playtest_run(&rs.playtest_session, rs.run_seed, &rs.run_state, &rs.room)
				assert(started)
				rs.playtest_session_ptr = &rs.playtest_session
				rs.playtest_report_written = false
			}
		}
	case .Defeat:
		clear_card_interaction(&rs.card_interaction)
		clear_gameplay_command_buffer(&rs.gameplay_buffer)
	case .Reward:
		clear_gameplay_command_buffer(&rs.gameplay_buffer)
		previous_hovered_index := rs.reward_hovered_index
		rs.reward_hovered_index = -1
		rs.reward_skip_hovered = false
		if rs.mouse_inside {
			if hovered_index, found := render.reward_card_at_point(
				&rs.run_state,
				width,
				height,
				rs.mouse_canvas,
				previous_hovered_index,
			); found {
				rs.reward_hovered_index = hovered_index
			} else {
				rs.reward_skip_hovered = render.reward_skip_at_point(
					width,
					height,
					rs.mouse_canvas,
				)
			}
		}

		// MOSTRA EFFETTO under a card, or I on the card under the mouse: never a
		// choice as well.
		if roguelike_effect_entry(rs, rs.mouse_inside && rs.frame_input.left_pressed, rs.mouse_canvas, run_pressed(rs.frame_input, .Inspect)) { return true }
		choice_index := pressed_hand_slot(rs.frame_input)
		choice_requested := choice_index >= 0 && choice_index < game.CARD_REWARD_CHOICE_COUNT
		skip_requested := run_pressed(rs.frame_input, .Skip)
		if rs.mouse_inside && rs.frame_input.left_pressed {
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
			rs.show_route_map = true
			rs.reward_hovered_index = -1
			rs.reward_skip_hovered = false
		}
	case .Shop:
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
		if rs.mouse_inside {
			shop_hit = render.shop_hit_test(
				&rs.run_state,
				width,
				height,
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

		// MOSTRA EFFETTO of an offer or of the owned card chosen (or I): never
		// a purchase, a page or a way out as well.
		if roguelike_effect_entry(rs, rs.mouse_inside && rs.frame_input.left_pressed, rs.mouse_canvas, run_pressed(rs.frame_input, .Inspect)) { return true }
		input := Run_Menu_Input{
			choice_index = pressed_hand_slot(rs.frame_input), previous_page = run_pressed(rs.frame_input, .Previous_Page), next_page = run_pressed(rs.frame_input, .Next_Page),
			upgrade = run_pressed(rs.frame_input, .Upgrade), remove = run_pressed(rs.frame_input, .Remove),
			confirm = run_pressed(rs.frame_input, .Confirm), cancel = run_pressed(rs.frame_input, .Cancel),
			clicked = rs.mouse_inside && rs.frame_input.left_pressed,
		}
		if step_shop_menu(&rs.run_state, &rs.shop_render_state, input, shop_hit) {
			rs.show_route_map = true
			rs.shop_render_state = {}
		}
	case .Special:
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
		if rs.mouse_inside {
			special_hit = render.special_node_hit_test(
				&rs.run_state,
				width,
				height,
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

		// MOSTRA EFFETTO of the rest's owned card chosen (or I): never a
		// choice as well.
		if roguelike_effect_entry(rs, rs.mouse_inside && rs.frame_input.left_pressed, rs.mouse_canvas, run_pressed(rs.frame_input, .Inspect)) { return true }
		input := Run_Menu_Input{
			choice_index = pressed_hand_slot(rs.frame_input), previous_page = run_pressed(rs.frame_input, .Previous_Page), next_page = run_pressed(rs.frame_input, .Next_Page),
			upgrade = run_pressed(rs.frame_input, .Upgrade), leave = run_pressed(rs.frame_input, .Leave), confirm = run_pressed(rs.frame_input, .Confirm),
			clicked = rs.mouse_inside && rs.frame_input.left_pressed,
		}
		if step_special_node_menu(&rs.run_state, &rs.special_render_state, input, special_hit) {
			rs.show_route_map = true
		}
	case .Route:
		if rs.mouse_inside {
			rs.shop_button_hovered = rs.run_state.phase == .Choose_Path &&
				rs.run_state.shop.offer_count > 0 && render.run_shop_button_at_point(
					width,
					height,
					rs.mouse_canvas,
				)
			if !rs.shop_button_hovered {
				if hovered, found := render.run_node_at_point(
				&rs.run_state,
				width,
				height,
				rs.mouse_canvas,
			); found {
				rs.hovered_node = hovered
				}
			}
		}

		if rs.run_state.phase == .Choose_Path {
			shop_requested := rs.shop_button_hovered && rs.frame_input.left_pressed
			if shop_requested && game.open_shop(&rs.run_state) == .Opened {
				rs.show_route_map = false
				rs.shop_render_state = {}
			}
			selected_node, selected := keyboard_route_choice(&rs.run_state, rs.frame_input)
			if rs.mouse_inside && rs.frame_input.left_pressed && rs.hovered_node != game.INVALID_NODE_ID {
				selected_node = rs.hovered_node
				selected = true
			}
			if selected { roguelike_enter_node(rs, selected_node) }
		}

	}
	return false
}

// Board and defeat keep the 3D world behind their HUD/overlay.
draw_run_screen :: proc(rs: ^Roguelike_Session) -> bool {
	width, height := f32(rs.window.config.canvas_width), f32(rs.window.config.canvas_height)
	switch run_screen(&rs.run_state, rs.show_route_map) {
	case .Board, .Defeat: return false
	case .Relic:
		render.draw_relic_reward_screen(&rs.run_state, width,
			height, rs.relic_hovered, rs.relic_skip_hovered, theme = &rs.iso_renderer)
	case .Reward:
		render.draw_reward_screen(
			&rs.run_state,
			width,
			height,
			rs.reward_hovered_index,
			rs.reward_skip_hovered,
			theme = &rs.iso_renderer,
		)
	case .Shop:
		render.draw_shop_screen(
			&rs.run_state,
			width,
			height,
			rs.shop_render_state,
			theme = &rs.iso_renderer,
		)
	case .Special:
		render.draw_special_node_screen(
			&rs.run_state,
			width,
			height,
			rs.special_render_state,
			theme = &rs.iso_renderer,
		)
	case .Route:
		render.draw_run_map(
			&rs.run_state,
			width,
			height,
			rs.hovered_node,
			rs.shop_button_hovered,
			theme = &rs.iso_renderer,
		)

	}
	return true
}
