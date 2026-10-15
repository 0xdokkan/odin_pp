package main

import game "game"
import render "render"

// A frame of menu input, sampled after MOSTRA EFFETTO has had first refusal.
// A negative choice_index means no number key. clicked includes canvas bounds;
// a click on empty space still overrides a special node's keyboard choice.
Run_Menu_Input :: struct {
	choice_index: int,
	previous_page, next_page, upgrade, remove: bool,
	confirm, cancel, leave, clicked: bool,
}

change_owned_deck_page :: proc(deck: ^game.Deck_State, page: ^int, selected: ^u32, step: int) {
	if step < 0 { page^ = max(0, page^-1) }
	else { page^ = min(render.shop_deck_page_count(deck)-1, page^+1) }
	selected^ = 0
}

// Keyboard and mouse dispatch the same transaction. The caller retains their
// order: numbered offer, page, upgrade/removal, mouse, then leave the shop.
apply_shop_menu_action :: proc(run: ^game.Run_State, state: ^render.Shop_Render_State, action: render.Shop_Hit) -> (leave: bool) {
	switch action.kind {
	case .None:
	case .Offer:
		game.buy_shop_card(run, action.offer_index)
	case .Owned_Card:
		state.selected_card_id = action.card_id
	case .Previous_Page:
		change_owned_deck_page(&run.player.deck, &state.page, &state.selected_card_id, -1)
	case .Next_Page:
		change_owned_deck_page(&run.player.deck, &state.page, &state.selected_card_id, 1)
	case .Upgrade:
		if state.selected_card_id != 0 { game.buy_shop_upgrade(run, state.selected_card_id) }
	case .Remove:
		if state.selected_card_id != 0 && game.buy_shop_removal(run, state.selected_card_id) == .Removed {
			state.selected_card_id = 0
		}
	case .Continue:
		return true
	}
	return false
}

step_shop_menu :: proc(run: ^game.Run_State, state: ^render.Shop_Render_State,
	input: Run_Menu_Input, hit: render.Shop_Hit = {}) -> (left: bool) {
	if input.choice_index >= 0 && input.choice_index < game.SHOP_CARD_OFFER_COUNT {
		apply_shop_menu_action(run, state, {kind = .Offer, offer_index = input.choice_index})
	}
	if input.previous_page { apply_shop_menu_action(run, state, {kind = .Previous_Page}) }
	else if input.next_page { apply_shop_menu_action(run, state, {kind = .Next_Page}) }
	if input.upgrade && state.selected_card_id != 0 { apply_shop_menu_action(run, state, {kind = .Upgrade}) }
	else if input.remove && state.selected_card_id != 0 { apply_shop_menu_action(run, state, {kind = .Remove}) }
	leave := input.confirm || input.cancel
	if input.clicked {
		mouse_leave := apply_shop_menu_action(run, state, hit)
		leave = leave || mouse_leave
	}
	state.page = render.shop_clamp_deck_page(&run.player.deck, state.page)
	return leave && game.leave_shop(run) == .Left
}

// Special nodes choose one action per frame. Unlike Shop, a mouse click
// replaces the keyboard choice; paging still clears selection before the
// enabled checks, including when an upgrade key is pressed on the same frame.
step_special_node_menu :: proc(run: ^game.Run_State, state: ^render.Special_Node_Render_State,
	input: Run_Menu_Input, hit: render.Special_Node_Hit = {}) -> (continued: bool) {
	requested := render.Special_Node_Hit{}
	if game.special_node_can_continue(run) {
		if input.confirm { requested.kind = .Continue }
	} else {
		if input.choice_index == 0 { requested.kind = .Primary }
		else if input.choice_index == 1 { requested.kind = .Secondary }
		if input.leave { requested.kind = .Leave }
		else if run.phase == .Rest && input.upgrade { requested.kind = .Secondary }
	}
	if run.phase == .Rest {
		if input.previous_page { change_owned_deck_page(&run.player.deck, &state.page, &state.selected_card_id, -1) }
		else if input.next_page { change_owned_deck_page(&run.player.deck, &state.page, &state.selected_card_id, 1) }
	}
	if input.clicked { requested = hit }
	if requested.kind == .Primary && !game.special_node_primary_is_enabled(run) {
		requested.kind = .None
	} else if requested.kind == .Secondary && !game.special_node_secondary_is_enabled(run, state.selected_card_id) {
		requested.kind = .None
	}
	switch requested.kind {
	case .None:
	case .Owned_Card:
		state.selected_card_id = requested.card_id
	case .Previous_Page:
		change_owned_deck_page(&run.player.deck, &state.page, &state.selected_card_id, -1)
	case .Next_Page:
		change_owned_deck_page(&run.player.deck, &state.page, &state.selected_card_id, 1)
	case .Primary:
		switch run.phase {
		case .Rest:
			game.use_rest_recovery(run)
		case .Event:
			game.resolve_route_event(run, .Primary)
		case .Treasure:
			game.claim_treasure(run)
		case .In_Room, .Reward, .Shop, .Choose_Path, .Victory, .Defeat:
		}
	case .Secondary:
		if run.phase == .Rest { game.use_rest_upgrade(run, state.selected_card_id) }
		else if run.phase == .Event { game.resolve_route_event(run, .Secondary) }
	case .Leave:
		game.leave_special_node(run)
	case .Continue:
		continued = game.continue_special_node(run) == .Continued
		if continued { state^ = {} }
	}
	state.page = render.special_node_clamp_deck_page(&run.player.deck, state.page)
	return
}
