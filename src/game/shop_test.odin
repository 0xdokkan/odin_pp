package game

import "core:testing"

SHOP_TEST_RUN_CONFIG :: Run_Map_Config{
	layer_count = 5,
	min_nodes_per_middle_layer = 2,
	max_nodes_per_middle_layer = 3,
}

SHOP_TEST_PLAYER_STATS :: Player_Stats{
	max_health = 10,
	attack = 2,
	defense = 1,
}

Shop_Test_Snapshot :: struct {
	player:               Player,
	phase:                Run_Phase,
	current_node:         Node_Id,
	cleared_count:        int,
	seed:                 u64,
	card_reward:          Card_Reward_State,
	reward_random_state:  u64,
	shop:                 Shop_State,
	shop_random_state:    u64,
	rest:                 Rest_Node_State,
	route_event:          Route_Event_State,
	treasure:             Treasure_Node_State,
	current_node_entered: bool,
	current_node_cleared: bool,
}

capture_shop_test_snapshot :: proc(run: ^Run_State) -> Shop_Test_Snapshot {
	if run == nil {
		return {}
	}
	result := Shop_Test_Snapshot{
		player = run.player,
		phase = run.phase,
		current_node = run.current_node,
		cleared_count = run.cleared_count,
		seed = run.seed,
		card_reward = run.card_reward,
		reward_random_state = run.reward_random_state,
		shop = run.shop,
		shop_random_state = run.shop_random_state,
		rest = run.rest,
		route_event = run.route_event,
		treasure = run.treasure,
	}
	node, found := current_run_node(run)
	if found {
		result.current_node_entered = node.entered
		result.current_node_cleared = node.cleared
	}
	return result
}

expect_shop_test_snapshot :: proc(t: ^testing.T, run: ^Run_State, expected: Shop_Test_Snapshot) {
	testing.expect(t, capture_shop_test_snapshot(run) == expected)
}

create_shop_test_source :: proc(t: ^testing.T, seed: u64) -> (Run_State, Node_Id) {
	for offset in u64(0)..<u64(512) {
		run, ok := create_run(SHOP_TEST_PLAYER_STATS, SHOP_TEST_RUN_CONFIG, seed+offset)
		if !ok {
			continue
		}
		node, found := current_run_node(&run)
		if found {
			for index in 0..<node.outgoing_count {
				candidate_id := node.outgoing[index]
				candidate, candidate_found := node_at(&run, candidate_id)
				if candidate_found && candidate.kind == .Shop {
					return run, candidate_id
				}
			}
		}
		destroy_run(&run)
	}
	testing.expect(t, false)
	return {}, INVALID_NODE_ID
}

create_shop_test_run :: proc(t: ^testing.T, seed: u64 = 0x5A0F) -> Run_State {
	run, shop_node := create_shop_test_source(t, seed)
	if shop_node == INVALID_NODE_ID {
		return run
	}
	run.player.gold = 100
	transition := finish_room(&run, .Complete)
	testing.expect_value(t, transition, Run_Transition.Reward)
	if transition != .Reward {
		return run
	}
	result := skip_card_reward(&run)
	testing.expect_value(t, result, Card_Reward_Result.Skipped)
	testing.expect_value(t, run.phase, Run_Phase.Choose_Path)
	testing.expect_value(t, enter_node(&run, shop_node), Node_Entry_Result.Shop)
	testing.expect_value(t, run.phase, Run_Phase.Shop)
	testing.expect(t, validate_shop_state(&run))
	testing.expect(t, validate_run_state(&run))
	return run
}

@(test)
test_shop_offers_are_deterministic_distinct_priced_and_do_not_allocate_ids :: proc(t: ^testing.T) {
	first := create_shop_test_run(t, 0x51A0)
	defer destroy_run(&first)
	second := create_shop_test_run(t, 0x51A0)
	defer destroy_run(&second)

	testing.expect_value(t, first.shop, second.shop)
	testing.expect_value(t, first.shop_random_state, second.shop_random_state)
	testing.expect_value(t, first.player.deck.next_card_id, u32(11))
	testing.expect_value(t, second.player.deck.next_card_id, u32(11))
	testing.expect_value(t, first.player.gold, i32(100))
	testing.expect_value(t, second.player.gold, i32(100))
	offers := available_shop_offers(&first)
	testing.expect_value(t, len(offers), SHOP_CARD_OFFER_COUNT)
	node, node_found := current_run_node(&first)
	testing.expect(t, node_found)
	for offer, index in offers {
		definition, definition_found := card_definition_by_id(offer.definition_id)
		testing.expect(t, definition_found)
		price, price_ok := shop_card_price(definition, node.depth)
		testing.expect(t, price_ok)
		testing.expect_value(t, offer.price, price)
		testing.expect(t, !offer.sold)
		for previous in 0..<index {
			testing.expect(t, offer.definition_id != offers[previous].definition_id)
		}
	}

	independent_first, first_shop := create_shop_test_source(t, 0x9911)
	defer destroy_run(&independent_first)
	independent_second, second_shop := create_shop_test_source(t, 0x9911)
	defer destroy_run(&independent_second)
	testing.expect_value(t, independent_first.seed, independent_second.seed)
	testing.expect_value(t, first_shop, second_shop)
	independent_first.player.deck.random_state = 0x1111
	independent_second.player.deck.random_state = 0xEEEE
	independent_first.reward_random_state = 0x2222
	independent_second.reward_random_state = 0xDDDD
	testing.expect_value(t, finish_room(&independent_first, .Complete), Run_Transition.Reward)
	testing.expect_value(t, finish_room(&independent_second, .Complete), Run_Transition.Reward)
	testing.expect_value(t, skip_card_reward(&independent_first), Card_Reward_Result.Skipped)
	testing.expect_value(t, skip_card_reward(&independent_second), Card_Reward_Result.Skipped)
	testing.expect_value(t, enter_node(&independent_first, first_shop), Node_Entry_Result.Shop)
	testing.expect_value(t, enter_node(&independent_second, second_shop), Node_Entry_Result.Shop)
	testing.expect_value(t, independent_first.shop, independent_second.shop)
	testing.expect_value(t, independent_first.shop_random_state, independent_second.shop_random_state)
}

@(test)
test_shop_prices_follow_metadata_depth_rarity_and_upgrade_level :: proc(t: ^testing.T) {
	strike, strike_found := card_definition_by_id(.Strike)
	testing.expect(t, strike_found)
	price, price_ok := shop_card_price(strike, 0)
	testing.expect(t, price_ok)
	testing.expect_value(t, price, strike.shop_base_price)
	price, price_ok = shop_card_price(strike, 3)
	testing.expect(t, price_ok)
	testing.expect_value(t, price, strike.shop_base_price+1)
	price, price_ok = shop_card_price(strike, MAX_CARD_OFFER_DEPTH+100)
	testing.expect(t, price_ok)
	testing.expect_value(t, price, strike.shop_base_price+MAX_CARD_OFFER_DEPTH/3)

	invalid_definition := strike
	invalid_definition.shop_base_price = 0
	_, price_ok = shop_card_price(invalid_definition, 0)
	testing.expect(t, !price_ok)
	_, price_ok = shop_card_price(strike, -1)
	testing.expect(t, !price_ok)

	run := create_shop_test_run(t, 0xC057)
	defer destroy_run(&run)
	strike_id := run.player.deck.owned[0].id
	upgrade_price, upgrade_ok := shop_upgrade_price(&run, strike_id)
	testing.expect(t, upgrade_ok)
	testing.expect_value(t, upgrade_price, i32(2))
	run.player.deck.owned[0].upgrade_level = 1
	upgrade_price, upgrade_ok = shop_upgrade_price(&run, strike_id)
	testing.expect(t, upgrade_ok)
	testing.expect_value(t, upgrade_price, i32(4))
	run.player.deck.owned[0].upgrade_level = MAX_CARD_UPGRADE_LEVEL
	_, upgrade_ok = shop_upgrade_price(&run, strike_id)
	testing.expect(t, !upgrade_ok)
	removal_price, removal_ok := shop_removal_price(&run)
	testing.expect(t, removal_ok)
	testing.expect_value(t, removal_price, i32(4))

	node, node_found := current_run_node(&run)
	testing.expect(t, node_found)
	if node_found {
		depth_before := node.depth
		node.depth = -1
		_, upgrade_ok = shop_upgrade_price(&run, strike_id)
		testing.expect(t, !upgrade_ok)
		_, removal_ok = shop_removal_price(&run)
		testing.expect(t, !removal_ok)
		node.depth = depth_before
	}
}

@(test)
test_shop_lifecycle_preserves_payload_until_path_choice :: proc(t: ^testing.T) {
	run := create_shop_test_run(t, 0x11FE)
	defer destroy_run(&run)
	shop_before := run.shop
	shop_rng_before := run.shop_random_state
	cleared_before := run.cleared_count

	testing.expect_value(t, leave_shop(&run), Shop_Result.Left)
	testing.expect_value(t, run.phase, Run_Phase.Choose_Path)
	testing.expect_value(t, run.cleared_count, cleared_before+1)
	testing.expect_value(t, run.shop, shop_before)
	testing.expect_value(t, run.shop_random_state, shop_rng_before)
	testing.expect_value(t, len(available_shop_offers(&run)), 0)
	testing.expect(t, validate_shop_state(&run))

	before_invalid_leave := capture_shop_test_snapshot(&run)
	testing.expect_value(t, leave_shop(&run), Shop_Result.Invalid)
	expect_shop_test_snapshot(t, &run, before_invalid_leave)

	testing.expect_value(t, open_shop(&run), Shop_Result.Opened)
	testing.expect_value(t, run.phase, Run_Phase.Shop)
	testing.expect_value(t, run.shop, shop_before)
	testing.expect_value(t, run.shop_random_state, shop_rng_before)
	before_invalid_open := capture_shop_test_snapshot(&run)
	testing.expect_value(t, open_shop(&run), Shop_Result.Invalid)
	expect_shop_test_snapshot(t, &run, before_invalid_open)

	testing.expect_value(t, leave_shop(&run), Shop_Result.Left)
	testing.expect_value(t, run.cleared_count, cleared_before+1)
	choices := available_nodes(&run)
	testing.expect(t, len(choices) > 0)
	if len(choices) > 0 {
		room_choice := INVALID_NODE_ID
		for choice in choices {
			candidate, found := node_at(&run, choice)
			if found && node_kind_has_room(candidate.kind) {
				room_choice = choice
				break
			}
		}
		testing.expect(t, room_choice != INVALID_NODE_ID)
		testing.expect(t, choose_node(&run, room_choice))
		testing.expect_value(t, run.phase, Run_Phase.In_Room)
		testing.expect_value(t, run.shop, Shop_State{})
		testing.expect(t, validate_shop_state(&run))
	}
}

@(test)
test_shop_purchase_commits_exact_gold_id_offer_and_deck_delta :: proc(t: ^testing.T) {
	run := create_shop_test_run(t, 0xB0A7)
	defer destroy_run(&run)
	offer_index := 0
	offer := run.shop.offers[offer_index]
	run.player.gold = offer.price
	testing.expect(t, shop_offer_can_be_bought(&run, offer_index))

	before := capture_shop_test_snapshot(&run)
	expected := before
	new_card_index := expected.player.deck.owned_count
	expected.player.deck.owned[new_card_index] = {
		id = expected.player.deck.next_card_id,
		definition_id = offer.definition_id,
	}
	expected.player.deck.owned_count += 1
	expected.player.deck.next_card_id += 1
	expected.player.gold -= offer.price
	expected.shop.offers[offer_index].sold = true
	testing.expect_value(t, buy_shop_card(&run, offer_index), Shop_Result.Purchased)
	expect_shop_test_snapshot(t, &run, expected)
	testing.expect(t, validate_shop_state(&run))
	testing.expect(t, !shop_offer_can_be_bought(&run, offer_index))

	after_purchase := capture_shop_test_snapshot(&run)
	testing.expect_value(t, buy_shop_card(&run, offer_index), Shop_Result.Already_Sold)
	expect_shop_test_snapshot(t, &run, after_purchase)
}

@(test)
test_shop_purchase_failures_preserve_gold_ids_rng_and_payload :: proc(t: ^testing.T) {
	run := create_shop_test_run(t, 0xFA11)
	defer destroy_run(&run)
	offer := run.shop.offers[0]

	before := capture_shop_test_snapshot(&run)
	testing.expect_value(t, buy_shop_card(&run, -1), Shop_Result.Invalid)
	expect_shop_test_snapshot(t, &run, before)
	testing.expect_value(t, buy_shop_card(&run, run.shop.offer_count), Shop_Result.Invalid)
	expect_shop_test_snapshot(t, &run, before)

	run.player.gold = offer.price-1
	before = capture_shop_test_snapshot(&run)
	testing.expect(t, !shop_offer_can_be_bought(&run, 0))
	testing.expect_value(t, buy_shop_card(&run, 0), Shop_Result.Not_Enough_Gold)
	expect_shop_test_snapshot(t, &run, before)

	run.player.gold = offer.price
	run.player.deck.next_card_id = max(u32)
	testing.expect(t, validate_shop_state(&run))
	before = capture_shop_test_snapshot(&run)
	testing.expect(t, !shop_offer_can_be_bought(&run, 0))
	testing.expect_value(t, buy_shop_card(&run, 0), Shop_Result.Invalid)
	expect_shop_test_snapshot(t, &run, before)

	testing.expect_value(t, leave_shop(&run), Shop_Result.Left)
	before = capture_shop_test_snapshot(&run)
	testing.expect_value(t, buy_shop_card(&run, 0), Shop_Result.Invalid)
	expect_shop_test_snapshot(t, &run, before)
	testing.expect_value(t, buy_shop_card(nil, 0), Shop_Result.Invalid)
}

@(test)
test_full_deck_purchase_failure_is_atomic_but_services_remain_available :: proc(t: ^testing.T) {
	run := create_shop_test_run(t, 0xF011)
	defer destroy_run(&run)
	for run.player.deck.owned_count < MAX_OWNED_CARDS {
		_, added := add_owned_card(&run.player.deck, .Strike)
		testing.expect(t, added)
	}
	run.player.gold = 100
	testing.expect(t, validate_shop_state(&run))
	before := capture_shop_test_snapshot(&run)
	testing.expect(t, !shop_offer_can_be_bought(&run, 0))
	testing.expect_value(t, buy_shop_card(&run, 0), Shop_Result.Deck_Full)
	expect_shop_test_snapshot(t, &run, before)
	testing.expect(t, shop_upgrade_can_be_bought(&run, run.player.deck.owned[0].id))
	testing.expect(t, shop_removal_can_be_bought(&run, run.player.deck.owned[0].id))
}

@(test)
test_shop_upgrade_targets_duplicate_instance_and_commits_only_expected_delta :: proc(t: ^testing.T) {
	run := create_shop_test_run(t, 0xA66)
	defer destroy_run(&run)
	duplicate, added := add_owned_card(&run.player.deck, .Strike)
	testing.expect(t, added)
	target_index, found := owned_card_index_by_id(&run.player.deck, duplicate.id)
	testing.expect(t, found)
	original_strike := run.player.deck.owned[0]
	price, price_ok := shop_upgrade_price(&run, duplicate.id)
	testing.expect(t, price_ok)
	testing.expect(t, shop_upgrade_can_be_bought(&run, duplicate.id))

	before := capture_shop_test_snapshot(&run)
	expected := before
	expected.player.deck.owned[target_index].upgrade_level += 1
	expected.player.gold -= price
	expected.shop.upgrade_used = true
	testing.expect_value(t, buy_shop_upgrade(&run, duplicate.id), Shop_Result.Upgraded)
	expect_shop_test_snapshot(t, &run, expected)
	testing.expect_value(t, run.player.deck.owned[0], original_strike)
	testing.expect(t, validate_shop_state(&run))

	after_upgrade := capture_shop_test_snapshot(&run)
	testing.expect_value(t, buy_shop_upgrade(&run, original_strike.id), Shop_Result.Service_Used)
	expect_shop_test_snapshot(t, &run, after_upgrade)
}

@(test)
test_shop_upgrade_failures_preserve_the_complete_economy_state :: proc(t: ^testing.T) {
	run := create_shop_test_run(t, 0xA66BAD)
	defer destroy_run(&run)
	target_id := run.player.deck.owned[0].id

	before := capture_shop_test_snapshot(&run)
	testing.expect_value(t, buy_shop_upgrade(&run, run.player.deck.next_card_id+100), Shop_Result.Card_Not_Found)
	expect_shop_test_snapshot(t, &run, before)

	run.player.deck.owned[0].upgrade_level = MAX_CARD_UPGRADE_LEVEL
	before = capture_shop_test_snapshot(&run)
	testing.expect(t, !shop_upgrade_can_be_bought(&run, target_id))
	testing.expect_value(t, buy_shop_upgrade(&run, target_id), Shop_Result.Maximum_Upgrade)
	expect_shop_test_snapshot(t, &run, before)

	run.player.deck.owned[0].upgrade_level = 0
	price, price_ok := shop_upgrade_price(&run, target_id)
	testing.expect(t, price_ok)
	run.player.gold = price-1
	before = capture_shop_test_snapshot(&run)
	testing.expect(t, !shop_upgrade_can_be_bought(&run, target_id))
	testing.expect_value(t, buy_shop_upgrade(&run, target_id), Shop_Result.Not_Enough_Gold)
	expect_shop_test_snapshot(t, &run, before)

	run.player.gold = 100
	testing.expect_value(t, leave_shop(&run), Shop_Result.Left)
	before = capture_shop_test_snapshot(&run)
	testing.expect_value(t, buy_shop_upgrade(&run, target_id), Shop_Result.Invalid)
	expect_shop_test_snapshot(t, &run, before)
	testing.expect_value(t, buy_shop_upgrade(nil, target_id), Shop_Result.Invalid)
}

@(test)
test_shop_removal_targets_duplicate_instance_preserves_order_and_never_recycles_id :: proc(t: ^testing.T) {
	run := create_shop_test_run(t, 0xAE10)
	defer destroy_run(&run)
	duplicate, added := add_owned_card(&run.player.deck, .Strike)
	testing.expect(t, added)
	target := run.player.deck.owned[0]
	target_index, found := owned_card_index_by_id(&run.player.deck, target.id)
	testing.expect(t, found)
	price, price_ok := shop_removal_price(&run)
	testing.expect(t, price_ok)
	old_next_card_id := run.player.deck.next_card_id

	before := capture_shop_test_snapshot(&run)
	expected := before
	for index in target_index..<expected.player.deck.owned_count-1 {
		expected.player.deck.owned[index] = expected.player.deck.owned[index+1]
	}
	expected.player.deck.owned_count -= 1
	expected.player.deck.owned[expected.player.deck.owned_count] = {}
	expected.player.gold -= price
	expected.shop.removal_used = true
	testing.expect_value(t, buy_shop_removal(&run, target.id), Shop_Result.Removed)
	expect_shop_test_snapshot(t, &run, expected)
	_, target_present := owned_card_index_by_id(&run.player.deck, target.id)
	_, duplicate_present := owned_card_index_by_id(&run.player.deck, duplicate.id)
	testing.expect(t, !target_present)
	testing.expect(t, duplicate_present)
	testing.expect_value(t, run.player.deck.next_card_id, old_next_card_id)

	offer_index := 0
	new_card_index := run.player.deck.owned_count
	testing.expect_value(t, buy_shop_card(&run, offer_index), Shop_Result.Purchased)
	testing.expect_value(t, run.player.deck.owned[new_card_index].id, old_next_card_id)
	after_purchase := capture_shop_test_snapshot(&run)
	testing.expect_value(t, buy_shop_removal(&run, duplicate.id), Shop_Result.Service_Used)
	expect_shop_test_snapshot(t, &run, after_purchase)
}

@(test)
test_shop_removal_failures_preserve_the_complete_economy_state :: proc(t: ^testing.T) {
	run := create_shop_test_run(t, 0xAE10BAD)
	defer destroy_run(&run)
	target_id := run.player.deck.owned[0].id

	before := capture_shop_test_snapshot(&run)
	testing.expect_value(t, buy_shop_removal(&run, run.player.deck.next_card_id+100), Shop_Result.Card_Not_Found)
	expect_shop_test_snapshot(t, &run, before)

	price, price_ok := shop_removal_price(&run)
	testing.expect(t, price_ok)
	run.player.gold = price-1
	before = capture_shop_test_snapshot(&run)
	testing.expect(t, !shop_removal_can_be_bought(&run, target_id))
	testing.expect_value(t, buy_shop_removal(&run, target_id), Shop_Result.Not_Enough_Gold)
	expect_shop_test_snapshot(t, &run, before)

	run.player.gold = 100
	for run.player.deck.owned_count > MIN_OWNED_CARDS {
		result := remove_owned_card(
			&run.player.deck,
			run.player.deck.owned[run.player.deck.owned_count-1].id,
		)
		testing.expect_value(t, result, Deck_Mutation_Result.Removed)
	}
	before = capture_shop_test_snapshot(&run)
	testing.expect(t, !shop_removal_can_be_bought(&run, run.player.deck.owned[0].id))
	testing.expect_value(t, buy_shop_removal(&run, run.player.deck.owned[0].id), Shop_Result.Minimum_Deck_Size)
	expect_shop_test_snapshot(t, &run, before)

	testing.expect_value(t, leave_shop(&run), Shop_Result.Left)
	before = capture_shop_test_snapshot(&run)
	testing.expect_value(t, buy_shop_removal(&run, run.player.deck.owned[0].id), Shop_Result.Invalid)
	expect_shop_test_snapshot(t, &run, before)
	testing.expect_value(t, buy_shop_removal(nil, target_id), Shop_Result.Invalid)
}
