package main

import "core:testing"
import game "game"
import render "render"

@(test)
test_shop_menu_preserves_transaction_order_and_failed_selection :: proc(t: ^testing.T) {
	rs := effect_test_stop(t, .Shop)
	defer roguelike_destroy(rs)
	run, state := &rs.run_state, &rs.shop_render_state
	selected := run.player.deck.owned[0].id
	state.selected_card_id = selected
	run.player.gold = 0
	before := run.player.deck
	testing.expect(t, !step_shop_menu(run, state, {choice_index = -1, remove = true}))
	testing.expect(t, state.selected_card_id == selected, "failed removal retains selection")
	testing.expect_value(t, run.player.deck, before)

	run.player.gold = 100
	testing.expect(t, !step_shop_menu(run, state, {choice_index = -1, previous_page = true, upgrade = true}))
	testing.expect(t, state.selected_card_id == 0 && !run.shop.upgrade_used, "paging clears selection before the upgrade key")
	state.selected_card_id = selected
	testing.expect(t, !step_shop_menu(run, state, {choice_index = -1, upgrade = true, remove = true}))
	testing.expect(t, run.shop.upgrade_used && !run.shop.removal_used, "upgrade has priority over removal")
	testing.expect(t, !step_shop_menu(run, state, {choice_index = -1, clicked = true}, {kind = .Remove}))
	testing.expect(t, run.shop.removal_used && state.selected_card_id == 0)

	gold, count := run.player.gold, run.player.deck.owned_count
	price := run.shop.offers[0].price+run.shop.offers[1].price
	testing.expect(t, step_shop_menu(run, state, {choice_index = 0, confirm = true, clicked = true}, {kind = .Offer, offer_index = 1}))
	testing.expect(t, run.shop.offers[0].sold && run.shop.offers[1].sold, "both transactions occur before leaving, including the mouse after Enter")
	testing.expect_value(t, run.player.gold, gold-price)
	testing.expect_value(t, run.player.deck.owned_count, count+2)
	testing.expect_value(t, run.phase, game.Run_Phase.Choose_Path)
}

@(test)
test_special_node_menu_preserves_click_override_and_continue_boundary :: proc(t: ^testing.T) {
	for kind in ([3]game.Node_Kind{.Rest, .Event, .Treasure}) {
		rs := effect_test_stop(t, kind)
		defer roguelike_destroy(rs)
		run, state := &rs.run_state, &rs.special_render_state
		before := run.player
		testing.expect(t, !step_special_node_menu(run, state, {choice_index = 0, clicked = true}))
		testing.expect(t, !game.special_node_can_continue(run), "an empty mouse click cancels the numbered choice")
		testing.expect_value(t, run.player, before)
		if kind == .Rest {
			state.selected_card_id = run.player.deck.owned[0].id
			testing.expect(t, !step_special_node_menu(run, state, {choice_index = -1, previous_page = true, upgrade = true}))
			testing.expect(t, state.selected_card_id == 0 && !run.rest.resolved)
			testing.expect(t, !step_special_node_menu(run, state, {choice_index = -1, clicked = true},
				{kind = .Owned_Card, card_id = run.player.deck.owned[0].id}))
			testing.expect(t, !step_special_node_menu(run, state, {choice_index = 0, clicked = true}, {kind = .Secondary}))
			testing.expect(t, run.rest.outcome == .Upgraded, "mouse upgrade replaces keyboard recovery")
		} else {
			testing.expect(t, !step_special_node_menu(run, state, {choice_index = 0, clicked = true}, {kind = .Leave}))
			testing.expect(t, run.player == before, "mouse leave replaces the keyboard reward")
		}
		testing.expect(t, game.special_node_can_continue(run))
		cleared := run.cleared_count
		testing.expect(t, !step_special_node_menu(run, state, {choice_index = -1, confirm = true, clicked = true}))
		testing.expect(t, run.cleared_count == cleared, "an empty click also cancels Enter")
		testing.expect(t, step_special_node_menu(run, state, {choice_index = -1, confirm = true}))
		testing.expect_value(t, run.phase, game.Run_Phase.Choose_Path)
		testing.expect_value(t, run.cleared_count, cleared+1)
		testing.expect_value(t, state^, render.Special_Node_Render_State{})
		testing.expect(t, !step_special_node_menu(run, state, {choice_index = -1, confirm = true}))
		testing.expect(t, run.cleared_count == cleared+1, "the transition can only commit once")
	}
}
