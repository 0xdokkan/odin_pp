package render

import "core:testing"
import rl "vendor:raylib"
import game "../game"
import view "../view"

SHOP_RENDER_TEST_PLAYER_STATS :: game.Player_Stats{
	max_health = 10,
	attack = 2,
	defense = 1,
}

SHOP_RENDER_TEST_RUN_CONFIG :: game.Run_Map_Config{
	layer_count = 5,
	min_nodes_per_middle_layer = 2,
	max_nodes_per_middle_layer = 3,
}

create_shop_render_test_run :: proc(t: ^testing.T, fill_deck: bool = false) -> game.Run_State {
	run: game.Run_State
	shop_node := game.INVALID_NODE_ID
	for offset in u64(0)..<u64(512) {
		candidate, ok := game.create_run(
			SHOP_RENDER_TEST_PLAYER_STATS,
			SHOP_RENDER_TEST_RUN_CONFIG,
			0x5A0F+offset,
		)
		if !ok {
			continue
		}
		current, found := game.current_run_node(&candidate)
		if found {
			for index in 0..<current.outgoing_count {
				candidate_id := current.outgoing[index]
				node, node_found := game.node_at(&candidate, candidate_id)
				if node_found && node.kind == .Shop {
					run = candidate
					shop_node = candidate_id
					break
				}
			}
		}
		if shop_node != game.INVALID_NODE_ID {
			break
		}
		game.destroy_run(&candidate)
	}
	testing.expect(t, shop_node != game.INVALID_NODE_ID)
	if shop_node == game.INVALID_NODE_ID {
		return {}
	}
	if fill_deck {
		for run.player.deck.owned_count < game.MAX_OWNED_CARDS {
			definition_id := game.Card_Id(run.player.deck.owned_count%int(game.Card_Id.Count))
			definition, found := game.card_definition_by_id(definition_id)
			if !found || definition.temporary_only {
				definition_id = .Strike
			}
			_, added := game.add_owned_card(&run.player.deck, definition_id)
			testing.expect(t, added)
			if !added {
				break
			}
		}
	}
	run.player.gold = 100
	transition := game.finish_room(&run, .Complete)
	testing.expect_value(t, transition, game.Run_Transition.Reward)
	result := game.skip_card_reward(&run)
	testing.expect_value(t, result, game.Card_Reward_Result.Skipped)
	testing.expect_value(t, game.enter_node(&run, shop_node), game.Node_Entry_Result.Shop)
	testing.expect_value(t, run.phase, game.Run_Phase.Shop)
	testing.expect(t, game.validate_shop_state(&run))
	return run
}

rectangle_center :: proc(bounds: rl.Rectangle) -> view.Vec2 {
	return {x = bounds.x+bounds.width*0.5, y = bounds.y+bounds.height*0.5}
}

rectangles_overlap :: proc(first, second: rl.Rectangle) -> bool {
	return first.x < second.x+second.width && first.x+first.width > second.x &&
	       first.y < second.y+second.height && first.y+first.height > second.y
}

@(test)
test_shop_offer_cards_and_prices_are_non_overlapping_and_hittable :: proc(t: ^testing.T) {
	run := create_shop_render_test_run(t)
	defer game.destroy_run(&run)
	offers := game.available_shop_offers(&run)
	testing.expect_value(t, len(offers), game.SHOP_CARD_OFFER_COUNT)

	previous_right: f32
	for index in 0..<len(offers) {
		card := shop_offer_bounds(960, 540, index)
		price := shop_offer_price_bounds(960, 540, index)
		testing.expect(t, card.x >= 0 && card.y >= SHOP_HEADER_HEIGHT)
		testing.expect(t, card.x+card.width <= 960 && card.y+card.height <= 540)
		testing.expect(t, price.x == card.x && price.width == card.width)
		testing.expect(t, price.y > card.y+card.height)
		testing.expect(t, price.y+price.height < SHOP_OWNED_CARD_TOP)
		if index > 0 {
			testing.expect(t, card.x > previous_right)
		}
		previous_right = card.x+card.width

		card_index, card_found := shop_offer_at_point(&run, 960, 540, rectangle_center(card))
		testing.expect(t, card_found)
		testing.expect_value(t, card_index, index)
		price_index, price_found := shop_offer_at_point(&run, 960, 540, rectangle_center(price))
		testing.expect(t, price_found)
		testing.expect_value(t, price_index, index)
	}

	raised := shop_offer_bounds(960, 540, 1, true)
	raised_only_point := view.Vec2{x = raised.x+raised.width*0.5, y = raised.y+2}
	_, found_without_raise := shop_offer_at_point(&run, 960, 540, raised_only_point)
	testing.expect(t, !found_without_raise)
	index, found := shop_offer_at_point(&run, 960, 540, raised_only_point, 1)
	testing.expect(t, found)
	testing.expect_value(t, index, 1)
	_, found = shop_offer_at_point(&run, 960, 540, {x = 10, y = 10})
	testing.expect(t, !found)
}

@(test)
test_shop_owned_deck_pages_return_instance_ids :: proc(t: ^testing.T) {
	run := create_shop_render_test_run(t)
	defer game.destroy_run(&run)
	deck := &run.player.deck
	page_count := shop_deck_page_count(deck)
	testing.expect_value(
		t,
		page_count,
		(deck.owned_count+SHOP_DECK_CARDS_PER_PAGE-1)/SHOP_DECK_CARDS_PER_PAGE,
	)
	testing.expect_value(t, shop_clamp_deck_page(deck, -4), 0)
	testing.expect_value(t, shop_clamp_deck_page(deck, page_count+4), page_count-1)

	for page in 0..<page_count {
		start, valid := shop_deck_page_start(deck, page)
		testing.expect(t, valid)
		visible_count := shop_deck_cards_on_page(deck, page)
		testing.expect(t, visible_count > 0 && visible_count <= SHOP_DECK_CARDS_PER_PAGE)
		previous_right: f32
		for slot in 0..<visible_count {
			bounds := shop_owned_card_bounds(960, 540, slot)
			testing.expect(t, bounds.x >= 0 && bounds.x+bounds.width <= 960)
			testing.expect(t, bounds.y >= SHOP_OWNED_CARD_TOP)
			testing.expect(t, bounds.y+bounds.height < shop_continue_bounds(960, 540).y)
			if slot > 0 {
				testing.expect(t, bounds.x > previous_right)
			}
			previous_right = bounds.x+bounds.width
			card_id, found := shop_owned_card_at_point(
				&run,
				960,
				540,
				page,
				rectangle_center(bounds),
			)
			testing.expect(t, found)
			testing.expect_value(t, card_id, deck.owned[start+slot].id)
		}
	}

	raised_card_id := deck.owned[1].id
	raised := shop_owned_card_bounds(960, 540, 1, true)
	raised_only_point := view.Vec2{x = raised.x+raised.width*0.5, y = raised.y+2}
	_, found_without_raise := shop_owned_card_at_point(&run, 960, 540, 0, raised_only_point)
	testing.expect(t, !found_without_raise)
	card_id, found := shop_owned_card_at_point(
		&run,
		960,
		540,
		0,
		raised_only_point,
		raised_card_id,
	)
	testing.expect(t, found)
	testing.expect_value(t, card_id, raised_card_id)
	_, found = shop_owned_card_at_point(&run, 960, 540, page_count, {x = 480, y = 360})
	testing.expect(t, !found)
}

@(test)
test_shop_maximum_deck_uses_four_complete_pages :: proc(t: ^testing.T) {
	run := create_shop_render_test_run(t, true)
	defer game.destroy_run(&run)
	deck := &run.player.deck
	testing.expect_value(t, deck.owned_count, game.MAX_OWNED_CARDS)
	testing.expect_value(t, shop_deck_page_count(deck), 4)

	seen: [game.MAX_OWNED_CARDS]bool
	for page in 0..<shop_deck_page_count(deck) {
		start, valid := shop_deck_page_start(deck, page)
		testing.expect(t, valid)
		testing.expect_value(t, shop_deck_cards_on_page(deck, page), SHOP_DECK_CARDS_PER_PAGE)
		for slot in 0..<SHOP_DECK_CARDS_PER_PAGE {
			card_id, found := shop_owned_card_at_point(
				&run,
				960,
				540,
				page,
				rectangle_center(shop_owned_card_bounds(960, 540, slot)),
			)
			testing.expect(t, found)
			testing.expect_value(t, card_id, deck.owned[start+slot].id)
			seen[start+slot] = found
		}
	}
	for was_seen in seen {
		testing.expect(t, was_seen)
	}
}

@(test)
test_shop_controls_are_disjoint_and_have_stable_hit_targets :: proc(t: ^testing.T) {
	run := create_shop_render_test_run(t)
	defer game.destroy_run(&run)
	controls := [?]rl.Rectangle{
		shop_previous_page_bounds(960, 540),
		shop_next_page_bounds(960, 540),
		shop_upgrade_bounds(960, 540),
		shop_remove_bounds(960, 540),
		shop_continue_bounds(960, 540),
	}
	for bounds, index in controls {
		testing.expect(t, bounds.x >= 0 && bounds.y >= 0)
		testing.expect(t, bounds.x+bounds.width <= 960 && bounds.y+bounds.height <= 540)
		for previous in 0..<index {
			testing.expect(t, !rectangles_overlap(bounds, controls[previous]))
		}
	}

	testing.expect(t, shop_previous_page_at_point(960, 540, rectangle_center(controls[0])))
	testing.expect(t, shop_next_page_at_point(960, 540, rectangle_center(controls[1])))
	testing.expect(t, shop_upgrade_at_point(960, 540, rectangle_center(controls[2])))
	testing.expect(t, shop_remove_at_point(960, 540, rectangle_center(controls[3])))
	testing.expect(t, shop_continue_at_point(960, 540, rectangle_center(controls[4])))

	expected_kinds := [?]Shop_Hit_Kind{
		.Previous_Page,
		.Next_Page,
		.Upgrade,
		.Remove,
		.Continue,
	}
	pages := [?]int{1, 0, 0, 0, 0}
	for bounds, index in controls {
		hit := shop_hit_test(&run, 960, 540, pages[index], rectangle_center(bounds))
		testing.expect_value(t, hit.kind, expected_kinds[index])
	}

	offer_hit := shop_hit_test(
		&run,
		960,
		540,
		0,
		rectangle_center(shop_offer_bounds(960, 540, 2)),
	)
	testing.expect_value(t, offer_hit.kind, Shop_Hit_Kind.Offer)
	testing.expect_value(t, offer_hit.offer_index, 2)
	owned_hit := shop_hit_test(
		&run,
		960,
		540,
		0,
		rectangle_center(shop_owned_card_bounds(960, 540, 3)),
	)
	testing.expect_value(t, owned_hit.kind, Shop_Hit_Kind.Owned_Card)
	testing.expect_value(t, owned_hit.card_id, run.player.deck.owned[3].id)
	testing.expect_value(t, shop_hit_test(&run, 960, 540, 0, {x = 10, y = 280}).kind, Shop_Hit_Kind.None)
}

@(test)
test_shop_geometry_rejects_unsupported_canvas_and_invalid_state :: proc(t: ^testing.T) {
	testing.expect(t, !shop_canvas_is_supported(899, 540))
	testing.expect(t, !shop_canvas_is_supported(960, 519))
	testing.expect(t, shop_offer_bounds(899, 540, 0) == rl.Rectangle{})
	testing.expect(t, shop_owned_card_bounds(960, 519, 0) == rl.Rectangle{})
	testing.expect(t, shop_continue_bounds(899, 519) == rl.Rectangle{})
	testing.expect(t, !shop_offer_contains(899, 540, 0, {}))
	testing.expect(t, !shop_previous_page_at_point(899, 540, {}))
	testing.expect(t, !shop_continue_at_point(960, 519, {}))
	_, offer_found := shop_offer_at_point(nil, 960, 540, {x = 480, y = 180})
	testing.expect(t, !offer_found)
	_, card_found := shop_owned_card_at_point(nil, 960, 540, 0, {x = 480, y = 360})
	testing.expect(t, !card_found)
	run := create_shop_render_test_run(t)
	defer game.destroy_run(&run)
	testing.expect_value(t, shop_hit_test(&run, 899, 540, 0, {}).kind, Shop_Hit_Kind.None)
}
