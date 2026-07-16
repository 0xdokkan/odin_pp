package game

import "core:testing"

SPECIAL_NODE_BEHAVIOR_TEST_CONFIG :: Run_Map_Config{
	layer_count = 3,
	min_nodes_per_middle_layer = 2,
	max_nodes_per_middle_layer = 2,
}

SPECIAL_NODE_TEST_PLAYER_STATS :: Player_Stats{
	max_health = 100,
	attack = 2,
	defense = 1,
}

Special_Node_Test_Snapshot :: struct {
	player:               Player,
	phase:                Run_Phase,
	current_node:         Node_Id,
	cleared_count:        int,
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

capture_special_node_test_snapshot :: proc(run: ^Run_State) -> Special_Node_Test_Snapshot {
	if run == nil {
		return {}
	}
	result := Special_Node_Test_Snapshot{
		player = run.player,
		phase = run.phase,
		current_node = run.current_node,
		cleared_count = run.cleared_count,
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

expect_special_node_test_snapshot :: proc(
	t: ^testing.T,
	run: ^Run_State,
	expected: Special_Node_Test_Snapshot,
) {
	testing.expect(t, capture_special_node_test_snapshot(run) == expected)
}

find_special_node_test_seed :: proc(
	kind: Node_Kind,
	event_kind: Route_Event_Kind = .Count,
) -> (u64, bool) {
	player, player_ok := create_player(SPECIAL_NODE_TEST_PLAYER_STATS)
	if !player_ok {
		return 0, false
	}
	for seed := u64(1); seed < u64(16_384); seed += 1 {
		route_map, map_ok := generate_run_map(SPECIAL_NODE_BEHAVIOR_TEST_CONFIG, seed)
		if !map_ok {
			continue
		}
		matches := false
		for node_index in 0..<len(route_map.nodes) {
			node := &route_map.nodes[node_index]
			if node.kind != kind {
				continue
			}
			matches = true
			if kind == .Event && event_kind != .Count {
				state, state_ok := build_route_event_state(&player, node)
				matches = state_ok && state.kind == event_kind
			}
			break
		}
		destroy_run_map(&route_map)
		if matches {
			return seed, true
		}
	}
	return 0, false
}

create_special_node_test_run :: proc(
	t: ^testing.T,
	kind: Node_Kind,
	event_kind: Route_Event_Kind = .Count,
) -> Run_State {
	seed, seed_found := find_special_node_test_seed(kind, event_kind)
	testing.expect(t, seed_found)
	if !seed_found {
		return {}
	}
	run, run_ok := create_run(
		SPECIAL_NODE_TEST_PLAYER_STATS,
		SPECIAL_NODE_BEHAVIOR_TEST_CONFIG,
		seed,
	)
	testing.expect(t, run_ok)
	if !run_ok {
		return run
	}
	testing.expect_value(t, finish_room(&run, .Complete), Run_Transition.Reward)
	testing.expect_value(t, skip_card_reward(&run), Card_Reward_Result.Skipped)
	testing.expect_value(t, run.phase, Run_Phase.Choose_Path)

	target := INVALID_NODE_ID
	for id in available_nodes(&run) {
		node, found := node_at(&run, id)
		if found && node.kind == kind {
			target = id
			break
		}
	}
	testing.expect(t, target != INVALID_NODE_ID)
	if target == INVALID_NODE_ID {
		return run
	}

	entry := enter_node(&run, target)
	switch kind {
	case .Rest:
		testing.expect_value(t, entry, Node_Entry_Result.Rest)
	case .Event:
		testing.expect_value(t, entry, Node_Entry_Result.Event)
		if event_kind != .Count {
			testing.expect_value(t, run.route_event.kind, event_kind)
		}
	case .Treasure:
		testing.expect_value(t, entry, Node_Entry_Result.Treasure)
	case .Combat, .Elite, .Boss, .Shop, .Count:
		testing.expect_value(t, entry, Node_Entry_Result.Invalid)
	}
	testing.expect(t, validate_run_state(&run))
	return run
}

@(test)
test_special_node_builders_are_deterministic_and_match_entered_payloads :: proc(t: ^testing.T) {
	rest_run := create_special_node_test_run(t, .Rest)
	defer destroy_run(&rest_run)
	rest_node, rest_node_found := current_run_node(&rest_run)
	testing.expect(t, rest_node_found)
	first_rest, first_rest_ok := build_rest_node_state(&rest_run.player, rest_node)
	second_rest, second_rest_ok := build_rest_node_state(&rest_run.player, rest_node)
	testing.expect(t, first_rest_ok && second_rest_ok)
	testing.expect_value(t, first_rest, second_rest)
	testing.expect_value(t, first_rest, rest_run.rest)
	testing.expect_value(t, first_rest.heal_amount, i32(30))

	event_kinds := [?]Route_Event_Kind{
		.Blood_Offering,
		.Healing_Spring,
		.Forgotten_Armory,
	}
	for event_kind in event_kinds {
		event_run := create_special_node_test_run(t, .Event, event_kind)
		event_node, event_node_found := current_run_node(&event_run)
		testing.expect(t, event_node_found)
		first_event, first_event_ok := build_route_event_state(&event_run.player, event_node)
		second_event, second_event_ok := build_route_event_state(&event_run.player, event_node)
		testing.expect(t, first_event_ok && second_event_ok)
		testing.expect_value(t, first_event, second_event)
		testing.expect_value(t, first_event, event_run.route_event)
		testing.expect_value(t, first_event.kind, event_kind)
		destroy_run(&event_run)
	}

	treasure_run := create_special_node_test_run(t, .Treasure)
	defer destroy_run(&treasure_run)
	treasure_node, treasure_node_found := current_run_node(&treasure_run)
	testing.expect(t, treasure_node_found)
	first_treasure, first_treasure_ok := build_treasure_node_state(treasure_node)
	second_treasure, second_treasure_ok := build_treasure_node_state(treasure_node)
	testing.expect(t, first_treasure_ok && second_treasure_ok)
	testing.expect_value(t, first_treasure, second_treasure)
	testing.expect_value(t, first_treasure, treasure_run.treasure)

	_, rest_nil_ok := build_rest_node_state(nil, rest_node)
	_, event_nil_ok := build_route_event_state(nil, rest_node)
	_, treasure_nil_ok := build_treasure_node_state(nil)
	testing.expect(t, !rest_nil_ok && !event_nil_ok && !treasure_nil_ok)
}

@(test)
test_rest_recovery_clamps_to_maximum_and_can_resolve_at_full_health :: proc(t: ^testing.T) {
	clamped := create_special_node_test_run(t, .Rest)
	defer destroy_run(&clamped)
	clamped.player.health = 91
	testing.expect(t, validate_run_state(&clamped))
	testing.expect_value(t, use_rest_recovery(&clamped), Special_Node_Result.Recovered)
	testing.expect_value(t, clamped.player.health, clamped.player.stats.max_health)
	testing.expect_value(t, clamped.rest.applied_amount, i32(9))
	testing.expect_value(t, clamped.rest.outcome, Special_Node_Outcome.Recovered)
	testing.expect(t, clamped.rest.resolved)
	testing.expect(t, special_node_can_continue(&clamped))

	resolved_before := capture_special_node_test_snapshot(&clamped)
	testing.expect_value(t, use_rest_recovery(&clamped), Special_Node_Result.Already_Resolved)
	expect_special_node_test_snapshot(t, &clamped, resolved_before)

	full := create_special_node_test_run(t, .Rest)
	defer destroy_run(&full)
	testing.expect_value(t, full.player.health, full.player.stats.max_health)
	testing.expect_value(t, use_rest_recovery(&full), Special_Node_Result.Recovered)
	testing.expect_value(t, full.player.health, full.player.stats.max_health)
	testing.expect_value(t, full.rest.applied_amount, i32(0))
	testing.expect(t, validate_run_state(&full))
}

@(test)
test_rest_upgrade_targets_instance_id_and_only_mutates_that_card :: proc(t: ^testing.T) {
	run := create_special_node_test_run(t, .Rest)
	defer destroy_run(&run)
	original := run.player.deck.owned[0]
	duplicate, added := add_owned_card(&run.player.deck, original.definition_id)
	testing.expect(t, added)
	duplicate_index, duplicate_found := owned_card_index_by_id(&run.player.deck, duplicate.id)
	testing.expect(t, duplicate_found)
	expected_deck := run.player.deck
	expected_deck.owned[duplicate_index].upgrade_level += 1

	testing.expect_value(t, use_rest_upgrade(&run, duplicate.id), Special_Node_Result.Upgraded)
	testing.expect(t, run.player.deck == expected_deck)
	testing.expect_value(t, run.player.deck.owned[0], original)
	testing.expect_value(t, run.rest.target_card_id, duplicate.id)
	testing.expect_value(t, run.rest.outcome, Special_Node_Outcome.Upgraded)
	testing.expect(t, special_node_can_continue(&run))

	resolved_before := capture_special_node_test_snapshot(&run)
	testing.expect_value(t, use_rest_upgrade(&run, original.id), Special_Node_Result.Already_Resolved)
	expect_special_node_test_snapshot(t, &run, resolved_before)
}

@(test)
test_rest_upgrade_invalid_and_maximum_failures_are_atomic :: proc(t: ^testing.T) {
	run := create_special_node_test_run(t, .Rest)
	defer destroy_run(&run)

	before := capture_special_node_test_snapshot(&run)
	testing.expect_value(t, use_rest_upgrade(&run, 0), Special_Node_Result.Card_Not_Found)
	expect_special_node_test_snapshot(t, &run, before)
	testing.expect_value(
		t,
		use_rest_upgrade(&run, run.player.deck.next_card_id+100),
		Special_Node_Result.Card_Not_Found,
	)
	expect_special_node_test_snapshot(t, &run, before)

	target_id := run.player.deck.owned[0].id
	run.player.deck.owned[0].upgrade_level = MAX_CARD_UPGRADE_LEVEL
	testing.expect(t, validate_run_state(&run))
	before = capture_special_node_test_snapshot(&run)
	testing.expect_value(t, use_rest_upgrade(&run, target_id), Special_Node_Result.Maximum_Upgrade)
	expect_special_node_test_snapshot(t, &run, before)
	testing.expect_value(t, use_rest_upgrade(nil, target_id), Special_Node_Result.Invalid)
}

@(test)
test_blood_offering_resolves_both_choices_with_exact_deltas :: proc(t: ^testing.T) {
	primary := create_special_node_test_run(t, .Event, .Blood_Offering)
	defer destroy_run(&primary)
	primary.player.health = 80
	primary.player.gold = 3
	health_before := primary.player.health
	gold_before := primary.player.gold
	testing.expect_value(
		t,
		resolve_route_event(&primary, .Primary),
		Special_Node_Result.Event_Resolved,
	)
	testing.expect_value(
		t,
		primary.player.health,
		health_before-primary.route_event.health_cost,
	)
	testing.expect_value(
		t,
		primary.player.gold,
		gold_before+primary.route_event.primary_gold,
	)
	testing.expect_value(t, primary.route_event.outcome, Special_Node_Outcome.Event_Primary)
	testing.expect_value(
		t,
		primary.route_event.applied_amount,
		primary.route_event.primary_gold,
	)
	resolved_before := capture_special_node_test_snapshot(&primary)
	testing.expect_value(
		t,
		resolve_route_event(&primary, .Secondary),
		Special_Node_Result.Already_Resolved,
	)
	expect_special_node_test_snapshot(t, &primary, resolved_before)

	secondary := create_special_node_test_run(t, .Event, .Blood_Offering)
	defer destroy_run(&secondary)
	player_before := secondary.player
	testing.expect_value(
		t,
		resolve_route_event(&secondary, .Secondary),
		Special_Node_Result.Event_Resolved,
	)
	testing.expect(t, secondary.player == player_before)
	testing.expect_value(t, secondary.route_event.outcome, Special_Node_Outcome.Event_Secondary)
	testing.expect_value(t, secondary.route_event.applied_amount, i32(0))
}

@(test)
test_healing_spring_resolves_heal_and_gold_choices :: proc(t: ^testing.T) {
	primary := create_special_node_test_run(t, .Event, .Healing_Spring)
	defer destroy_run(&primary)
	primary.player.health = 90
	testing.expect_value(
		t,
		resolve_route_event(&primary, .Primary),
		Special_Node_Result.Event_Resolved,
	)
	testing.expect_value(t, primary.player.health, primary.player.stats.max_health)
	testing.expect_value(t, primary.route_event.applied_amount, i32(10))
	testing.expect_value(t, primary.route_event.outcome, Special_Node_Outcome.Event_Primary)

	secondary := create_special_node_test_run(t, .Event, .Healing_Spring)
	defer destroy_run(&secondary)
	gold_before := secondary.player.gold
	testing.expect_value(
		t,
		resolve_route_event(&secondary, .Secondary),
		Special_Node_Result.Event_Resolved,
	)
	testing.expect_value(
		t,
		secondary.player.gold,
		gold_before+secondary.route_event.secondary_gold,
	)
	testing.expect_value(
		t,
		secondary.route_event.applied_amount,
		secondary.route_event.secondary_gold,
	)
}

@(test)
test_forgotten_armory_resolves_card_and_gold_choices :: proc(t: ^testing.T) {
	primary := create_special_node_test_run(t, .Event, .Forgotten_Armory)
	defer destroy_run(&primary)
	count_before := primary.player.deck.owned_count
	next_id_before := primary.player.deck.next_card_id
	offered_card := primary.route_event.offered_card
	testing.expect(t, primary.route_event.has_offered_card)
	testing.expect_value(
		t,
		resolve_route_event(&primary, .Primary),
		Special_Node_Result.Event_Resolved,
	)
	testing.expect_value(t, primary.player.deck.owned_count, count_before+1)
	testing.expect_value(t, primary.player.deck.next_card_id, next_id_before+1)
	added := primary.player.deck.owned[count_before]
	testing.expect_value(t, added.id, next_id_before)
	testing.expect_value(t, added.definition_id, offered_card)
	testing.expect_value(t, primary.route_event.added_card_id, added.id)
	testing.expect_value(t, primary.route_event.outcome, Special_Node_Outcome.Event_Primary)

	secondary := create_special_node_test_run(t, .Event, .Forgotten_Armory)
	defer destroy_run(&secondary)
	deck_before := secondary.player.deck
	gold_before := secondary.player.gold
	testing.expect_value(
		t,
		resolve_route_event(&secondary, .Secondary),
		Special_Node_Result.Event_Resolved,
	)
	testing.expect(t, secondary.player.deck == deck_before)
	testing.expect_value(
		t,
		secondary.player.gold,
		gold_before+secondary.route_event.secondary_gold,
	)
}

@(test)
test_event_health_and_gold_failures_are_atomic :: proc(t: ^testing.T) {
	health_failure := create_special_node_test_run(t, .Event, .Blood_Offering)
	defer destroy_run(&health_failure)
	health_failure.player.health = health_failure.route_event.health_cost
	testing.expect(t, validate_run_state(&health_failure))
	before := capture_special_node_test_snapshot(&health_failure)
	testing.expect_value(
		t,
		resolve_route_event(&health_failure, .Primary),
		Special_Node_Result.Not_Enough_Health,
	)
	expect_special_node_test_snapshot(t, &health_failure, before)

	blood_overflow := create_special_node_test_run(t, .Event, .Blood_Offering)
	defer destroy_run(&blood_overflow)
	blood_overflow.player.health = 80
	blood_overflow.player.gold = max(i32)-blood_overflow.route_event.primary_gold+1
	testing.expect(t, validate_run_state(&blood_overflow))
	before = capture_special_node_test_snapshot(&blood_overflow)
	testing.expect_value(
		t,
		resolve_route_event(&blood_overflow, .Primary),
		Special_Node_Result.Overflow,
	)
	expect_special_node_test_snapshot(t, &blood_overflow, before)

	gold_failure := create_special_node_test_run(t, .Event, .Healing_Spring)
	defer destroy_run(&gold_failure)
	gold_failure.player.gold = max(i32)-gold_failure.route_event.secondary_gold+1
	testing.expect(t, validate_run_state(&gold_failure))
	before = capture_special_node_test_snapshot(&gold_failure)
	testing.expect_value(
		t,
		resolve_route_event(&gold_failure, .Secondary),
		Special_Node_Result.Overflow,
	)
	expect_special_node_test_snapshot(t, &gold_failure, before)

	invalid_choice := create_special_node_test_run(t, .Event, .Blood_Offering)
	defer destroy_run(&invalid_choice)
	before = capture_special_node_test_snapshot(&invalid_choice)
	testing.expect_value(
		t,
		resolve_route_event(&invalid_choice, Route_Event_Choice(99)),
		Special_Node_Result.Invalid,
	)
	expect_special_node_test_snapshot(t, &invalid_choice, before)
}

@(test)
test_forgotten_armory_full_deck_and_id_exhaustion_are_atomic :: proc(t: ^testing.T) {
	full := create_special_node_test_run(t, .Event, .Forgotten_Armory)
	defer destroy_run(&full)
	for full.player.deck.owned_count < MAX_OWNED_CARDS {
		_, added := add_owned_card(&full.player.deck, .Strike)
		testing.expect(t, added)
	}
	testing.expect(t, validate_run_state(&full))
	before := capture_special_node_test_snapshot(&full)
	testing.expect_value(
		t,
		resolve_route_event(&full, .Primary),
		Special_Node_Result.Deck_Full,
	)
	expect_special_node_test_snapshot(t, &full, before)

	exhausted := create_special_node_test_run(t, .Event, .Forgotten_Armory)
	defer destroy_run(&exhausted)
	exhausted.player.deck.next_card_id = max(u32)
	testing.expect(t, validate_run_state(&exhausted))
	before = capture_special_node_test_snapshot(&exhausted)
	testing.expect_value(
		t,
		resolve_route_event(&exhausted, .Primary),
		Special_Node_Result.Instance_Id_Exhausted,
	)
	expect_special_node_test_snapshot(t, &exhausted, before)
}

@(test)
test_treasure_claim_and_leave_are_one_shot :: proc(t: ^testing.T) {
	claimed := create_special_node_test_run(t, .Treasure)
	defer destroy_run(&claimed)
	gold_before := claimed.player.gold
	testing.expect_value(t, claim_treasure(&claimed), Special_Node_Result.Treasure_Claimed)
	testing.expect_value(t, claimed.player.gold, gold_before+claimed.treasure.gold_amount)
	testing.expect_value(t, claimed.treasure.outcome, Special_Node_Outcome.Treasure_Claimed)
	testing.expect_value(t, claimed.treasure.applied_amount, claimed.treasure.gold_amount)
	resolved_before := capture_special_node_test_snapshot(&claimed)
	testing.expect_value(t, claim_treasure(&claimed), Special_Node_Result.Already_Resolved)
	expect_special_node_test_snapshot(t, &claimed, resolved_before)
	testing.expect_value(t, leave_special_node(&claimed), Special_Node_Result.Already_Resolved)
	expect_special_node_test_snapshot(t, &claimed, resolved_before)

	left := create_special_node_test_run(t, .Treasure)
	defer destroy_run(&left)
	gold_before = left.player.gold
	testing.expect_value(t, leave_special_node(&left), Special_Node_Result.Left)
	testing.expect_value(t, left.player.gold, gold_before)
	testing.expect_value(t, left.treasure.outcome, Special_Node_Outcome.Left)
	testing.expect_value(t, left.treasure.applied_amount, i32(0))
	resolved_before = capture_special_node_test_snapshot(&left)
	testing.expect_value(t, claim_treasure(&left), Special_Node_Result.Already_Resolved)
	expect_special_node_test_snapshot(t, &left, resolved_before)
}

@(test)
test_treasure_overflow_is_atomic :: proc(t: ^testing.T) {
	run := create_special_node_test_run(t, .Treasure)
	defer destroy_run(&run)
	run.player.gold = max(i32)-run.treasure.gold_amount+1
	testing.expect(t, validate_run_state(&run))
	before := capture_special_node_test_snapshot(&run)
	testing.expect_value(t, claim_treasure(&run), Special_Node_Result.Overflow)
	expect_special_node_test_snapshot(t, &run, before)
}

@(test)
test_special_nodes_require_resolution_then_continue_exactly_once :: proc(t: ^testing.T) {
	kinds := [?]Node_Kind{.Rest, .Event, .Treasure}
	for kind in kinds {
		run := create_special_node_test_run(t, kind)
		before := capture_special_node_test_snapshot(&run)
		testing.expect(t, !special_node_can_continue(&run))
		testing.expect_value(t, continue_special_node(&run), Special_Node_Result.Invalid)
		expect_special_node_test_snapshot(t, &run, before)

		testing.expect_value(t, leave_special_node(&run), Special_Node_Result.Left)
		testing.expect(t, special_node_can_continue(&run))
		resolved_before := capture_special_node_test_snapshot(&run)
		testing.expect_value(t, leave_special_node(&run), Special_Node_Result.Already_Resolved)
		expect_special_node_test_snapshot(t, &run, resolved_before)

		cleared_before := run.cleared_count
		testing.expect_value(t, continue_special_node(&run), Special_Node_Result.Continued)
		testing.expect_value(t, run.phase, Run_Phase.Choose_Path)
		testing.expect_value(t, run.cleared_count, cleared_before+1)
		testing.expect_value(t, run.rest, Rest_Node_State{})
		testing.expect_value(t, run.route_event, Route_Event_State{})
		testing.expect_value(t, run.treasure, Treasure_Node_State{})
		node, found := current_run_node(&run)
		testing.expect(t, found && node.cleared)
		testing.expect(t, validate_run_state(&run))

		continued_before := capture_special_node_test_snapshot(&run)
		testing.expect_value(t, continue_special_node(&run), Special_Node_Result.Invalid)
		expect_special_node_test_snapshot(t, &run, continued_before)
		destroy_run(&run)
	}
	testing.expect_value(t, leave_special_node(nil), Special_Node_Result.Invalid)
	testing.expect_value(t, continue_special_node(nil), Special_Node_Result.Invalid)
}

@(test)
test_special_node_validation_rejects_corrupt_payloads_without_mutation :: proc(t: ^testing.T) {
	rest_run := create_special_node_test_run(t, .Rest)
	defer destroy_run(&rest_run)
	rest_run.rest.heal_amount += 1
	testing.expect(t, !validate_special_node_state(&rest_run))
	testing.expect(t, !validate_run_state(&rest_run))
	before := capture_special_node_test_snapshot(&rest_run)
	testing.expect_value(t, use_rest_recovery(&rest_run), Special_Node_Result.Invalid)
	testing.expect_value(t, leave_special_node(&rest_run), Special_Node_Result.Invalid)
	expect_special_node_test_snapshot(t, &rest_run, before)

	event_run := create_special_node_test_run(t, .Event, .Forgotten_Armory)
	defer destroy_run(&event_run)
	event_run.route_event.offered_card = .Count
	testing.expect(t, !validate_special_node_state(&event_run))
	testing.expect(t, !validate_run_state(&event_run))
	before = capture_special_node_test_snapshot(&event_run)
	testing.expect_value(
		t,
		resolve_route_event(&event_run, .Primary),
		Special_Node_Result.Invalid,
	)
	testing.expect_value(t, leave_special_node(&event_run), Special_Node_Result.Invalid)
	expect_special_node_test_snapshot(t, &event_run, before)

	treasure_run := create_special_node_test_run(t, .Treasure)
	defer destroy_run(&treasure_run)
	treasure_run.treasure.gold_amount += 1
	testing.expect(t, !validate_special_node_state(&treasure_run))
	testing.expect(t, !validate_run_state(&treasure_run))
	before = capture_special_node_test_snapshot(&treasure_run)
	testing.expect_value(t, claim_treasure(&treasure_run), Special_Node_Result.Invalid)
	testing.expect_value(t, leave_special_node(&treasure_run), Special_Node_Result.Invalid)
	expect_special_node_test_snapshot(t, &treasure_run, before)
}
