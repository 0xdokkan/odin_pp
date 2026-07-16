package game

import "core:testing"

SPECIAL_NODE_TEST_CONFIG :: Run_Map_Config{
	layer_count = 7,
	min_nodes_per_middle_layer = 2,
	max_nodes_per_middle_layer = 3,
}

SPECIAL_NODE_TRAVERSAL_CONFIG :: Run_Map_Config{
	layer_count = 3,
	min_nodes_per_middle_layer = 2,
	max_nodes_per_middle_layer = 3,
}

special_node_test_seed_for_kind :: proc(wanted: Node_Kind) -> (u64, bool) {
	if !node_kind_is_special(wanted) {
		return 0, false
	}
	for seed in u64(1)..<u64(4096) {
		kind, ok := special_node_kind_for_depth(seed, 1)
		if ok && kind == wanted {
			return seed, true
		}
	}
	return 0, false
}

special_node_test_prepare_first_choice :: proc(run: ^Run_State) -> bool {
	if finish_room(run, .Complete) != .Reward {
		return false
	}
	return skip_card_reward(run) == .Skipped && run.phase == .Choose_Path
}

special_node_test_available_kind :: proc(run: ^Run_State, kind: Node_Kind) -> (Node_Id, bool) {
	for id in available_nodes(run) {
		node, found := node_at(run, id)
		if found && node.kind == kind {
			return id, true
		}
	}
	return INVALID_NODE_ID, false
}

@(test)
test_special_node_schedule_is_deterministic_and_cycles_every_kind :: proc(t: ^testing.T) {
	_, zero_ok := special_node_kind_for_depth(1, 0)
	_, negative_ok := special_node_kind_for_depth(1, -1)
	testing.expect(t, !zero_ok)
	testing.expect(t, !negative_ok)

	seeds := [?]u64{1, 2, 0xCAFE, 0xDEADBEEF}
	for seed in seeds {
		seen: [SPECIAL_NODE_KIND_COUNT]bool
		for depth in 1..=SPECIAL_NODE_KIND_COUNT {
			kind, ok := special_node_kind_for_depth(seed, depth)
			testing.expect(t, ok)
			if !ok {
				continue
			}
			testing.expect(t, node_kind_is_special(kind))
			index := int(kind)-int(Node_Kind.Shop)
			testing.expect(t, index >= 0 && index < len(seen))
			if index >= 0 && index < len(seen) {
				testing.expect(t, !seen[index])
				seen[index] = true
			}

			repeated, repeated_ok := special_node_kind_for_depth(
				seed,
				depth+SPECIAL_NODE_KIND_COUNT,
			)
			testing.expect(t, repeated_ok)
			testing.expect_value(t, repeated, kind)
			deterministic, deterministic_ok := special_node_kind_for_depth(seed, depth)
			testing.expect(t, deterministic_ok)
			testing.expect_value(t, deterministic, kind)
		}
		for was_seen in seen {
			testing.expect(t, was_seen)
		}
	}
}

@(test)
test_generated_layers_have_one_deterministic_special_and_at_least_one_room :: proc(t: ^testing.T) {
	for seed in u64(0)..<u64(64) {
		first, first_ok := generate_run_map(SPECIAL_NODE_TEST_CONFIG, seed)
		testing.expect(t, first_ok)
		if !first_ok {
			continue
		}
		second, second_ok := generate_run_map(SPECIAL_NODE_TEST_CONFIG, seed)
		testing.expect(t, second_ok)
		if !second_ok {
			destroy_run_map(&first)
			continue
		}

		for depth in 1..<SPECIAL_NODE_TEST_CONFIG.layer_count-1 {
			expected, expected_ok := special_node_kind_for_depth(seed, depth)
			testing.expect(t, expected_ok)
			start := first.layer_starts[depth]
			count := first.layer_counts[depth]
			testing.expect(t, count >= 2)
			special_count := 0
			room_count := 0
			for lane in 0..<count {
				index := start+lane
				node := first.nodes[index]
				other := second.nodes[index]
				testing.expect_value(t, other.kind, node.kind)
				testing.expect_value(t, other.room_seed, node.room_seed)
				if node_kind_is_special(node.kind) {
					special_count += 1
					testing.expect_value(t, node.kind, expected)
				} else if node_kind_has_room(node.kind) {
					room_count += 1
				}
			}
			testing.expect_value(t, special_count, 1)
			testing.expect(t, room_count >= 1)
			testing.expect_value(t, special_count+room_count, count)
		}

		destroy_run_map(&second)
		destroy_run_map(&first)
	}
}

@(test)
test_run_map_validation_rejects_tampered_special_distribution_and_cycle :: proc(t: ^testing.T) {
	route_map, ok := generate_run_map(SPECIAL_NODE_TEST_CONFIG, 0xA11CE)
	testing.expect(t, ok)
	if !ok {
		return
	}
	defer destroy_run_map(&route_map)

	depth := 1
	start := route_map.layer_starts[depth]
	count := route_map.layer_counts[depth]
	special_index := -1
	room_index := -1
	for index in start..<start+count {
		if node_kind_is_special(route_map.nodes[index].kind) {
			special_index = index
		} else if node_kind_has_room(route_map.nodes[index].kind) {
			room_index = index
		}
	}
	testing.expect(t, special_index >= 0)
	testing.expect(t, room_index >= 0)
	if special_index < 0 || room_index < 0 {
		return
	}

	special_before := route_map.nodes[special_index]
	room_before := route_map.nodes[room_index]
	expected, expected_ok := special_node_kind_for_depth(route_map.seed, depth)
	testing.expect(t, expected_ok)
	if !expected_ok {
		return
	}

	route_map.nodes[room_index].kind = expected
	route_map.nodes[room_index].room_seed = derive_node_room_seed(
		route_map.seed,
		route_map.nodes[room_index].id,
		expected,
		depth,
	)
	testing.expect(t, !validate_run_map(&route_map))
	route_map.nodes[room_index] = room_before

	route_map.nodes[special_index].kind = .Combat
	route_map.nodes[special_index].room_seed = derive_node_room_seed(
		route_map.seed,
		route_map.nodes[special_index].id,
		.Combat,
		depth,
	)
	testing.expect(t, !validate_run_map(&route_map))
	route_map.nodes[special_index] = special_before

	expected_index := int(expected)-int(Node_Kind.Shop)
	special_kinds := SPECIAL_NODE_KINDS
	wrong_kind := special_kinds[(expected_index+1)%SPECIAL_NODE_KIND_COUNT]
	route_map.nodes[special_index].kind = wrong_kind
	route_map.nodes[special_index].room_seed = derive_node_room_seed(
		route_map.seed,
		route_map.nodes[special_index].id,
		wrong_kind,
		depth,
	)
	testing.expect(t, !validate_run_map(&route_map))
	route_map.nodes[special_index] = special_before
	testing.expect(t, validate_run_map(&route_map))
}

@(test)
test_special_node_entry_failure_is_atomic_for_every_kind :: proc(t: ^testing.T) {
	for kind in SPECIAL_NODE_KINDS {
		seed, seed_found := special_node_test_seed_for_kind(kind)
		testing.expect(t, seed_found)
		if !seed_found {
			continue
		}
		run, run_ok := create_run(RUN_TEST_PLAYER_STATS, SPECIAL_NODE_TRAVERSAL_CONFIG, seed)
		testing.expect(t, run_ok)
		if !run_ok {
			continue
		}
		prepared := special_node_test_prepare_first_choice(&run)
		testing.expect(t, prepared)
		if !prepared {
			destroy_run(&run)
			continue
		}
		target_id, target_found := special_node_test_available_kind(&run, kind)
		testing.expect(t, target_found)
		if !target_found {
			destroy_run(&run)
			continue
		}
		target, node_found := node_at(&run, target_id)
		testing.expect(t, node_found)
		if !node_found {
			destroy_run(&run)
			continue
		}

		valid_room_seed := target.room_seed
		target.room_seed = 0
		target_before := target^
		player_before := run.player
		current_before := run.current_node
		phase_before := run.phase
		cleared_before := run.cleared_count
		reward_before := run.card_reward
		reward_rng_before := run.reward_random_state
		shop_before := run.shop
		shop_rng_before := run.shop_random_state
		rest_before := run.rest
		event_before := run.route_event
		treasure_before := run.treasure

		testing.expect_value(t, enter_node(&run, target_id), Node_Entry_Result.Invalid)
		testing.expect(t, run.player == player_before)
		testing.expect_value(t, run.current_node, current_before)
		testing.expect_value(t, run.phase, phase_before)
		testing.expect_value(t, run.cleared_count, cleared_before)
		testing.expect(t, run.card_reward == reward_before)
		testing.expect_value(t, run.reward_random_state, reward_rng_before)
		testing.expect(t, run.shop == shop_before)
		testing.expect_value(t, run.shop_random_state, shop_rng_before)
		testing.expect(t, run.rest == rest_before)
		testing.expect(t, run.route_event == event_before)
		testing.expect(t, run.treasure == treasure_before)
		testing.expect(t, target^ == target_before)

		target.room_seed = valid_room_seed
		destroy_run(&run)
	}
}

@(test)
test_run_traversal_dispatches_every_special_node_kind :: proc(t: ^testing.T) {
	for kind in SPECIAL_NODE_KINDS {
		seed, seed_found := special_node_test_seed_for_kind(kind)
		testing.expect(t, seed_found)
		if !seed_found {
			continue
		}
		run, run_ok := create_run(RUN_TEST_PLAYER_STATS, SPECIAL_NODE_TRAVERSAL_CONFIG, seed)
		testing.expect(t, run_ok)
		if !run_ok {
			continue
		}

		prepared := special_node_test_prepare_first_choice(&run)
		testing.expect(t, prepared)
		if !prepared {
			destroy_run(&run)
			continue
		}
		target_id, target_found := special_node_test_available_kind(&run, kind)
		testing.expect(t, target_found)
		if !target_found {
			destroy_run(&run)
			continue
		}

		entry := enter_node(&run, target_id)
		switch kind {
		case .Shop:
			testing.expect_value(t, entry, Node_Entry_Result.Shop)
			testing.expect_value(t, run.phase, Run_Phase.Shop)
			testing.expect_value(t, run.shop.source_node, target_id)
			testing.expect_value(t, leave_shop(&run), Shop_Result.Left)
		case .Rest:
			testing.expect_value(t, entry, Node_Entry_Result.Rest)
			testing.expect_value(t, run.phase, Run_Phase.Rest)
			testing.expect_value(t, run.rest.source_node, target_id)
			testing.expect_value(t, leave_special_node(&run), Special_Node_Result.Left)
			testing.expect_value(t, continue_special_node(&run), Special_Node_Result.Continued)
		case .Event:
			testing.expect_value(t, entry, Node_Entry_Result.Event)
			testing.expect_value(t, run.phase, Run_Phase.Event)
			testing.expect_value(t, run.route_event.source_node, target_id)
			testing.expect_value(t, leave_special_node(&run), Special_Node_Result.Left)
			testing.expect_value(t, continue_special_node(&run), Special_Node_Result.Continued)
		case .Treasure:
			testing.expect_value(t, entry, Node_Entry_Result.Treasure)
			testing.expect_value(t, run.phase, Run_Phase.Treasure)
			testing.expect_value(t, run.treasure.source_node, target_id)
			testing.expect_value(t, leave_special_node(&run), Special_Node_Result.Left)
			testing.expect_value(t, continue_special_node(&run), Special_Node_Result.Continued)
		case .Combat, .Elite, .Boss, .Count:
			testing.expect(t, false, "expected a special node")
		}

		testing.expect_value(t, run.phase, Run_Phase.Choose_Path)
		testing.expect_value(t, run.cleared_count, 2)
		testing.expect(t, validate_run_state(&run))
		boss_choices := available_nodes(&run)
		testing.expect_value(t, len(boss_choices), 1)
		if len(boss_choices) != 1 {
			destroy_run(&run)
			continue
		}
		boss, boss_found := node_at(&run, boss_choices[0])
		testing.expect(t, boss_found)
		if !boss_found {
			destroy_run(&run)
			continue
		}
		testing.expect_value(t, boss.kind, Node_Kind.Boss)
		testing.expect_value(t, enter_node(&run, boss.id), Node_Entry_Result.In_Room)
		testing.expect_value(t, finish_room(&run, .Complete), Run_Transition.Victory)
		testing.expect_value(t, run.phase, Run_Phase.Victory)
		testing.expect_value(t, run.cleared_count, 3)
		testing.expect(t, validate_run_state(&run))

		destroy_run(&run)
	}
}
