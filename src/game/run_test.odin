package game

import "core:testing"

TEST_RUN_CONFIG :: Run_Map_Config{
	layer_count = 7,
	min_nodes_per_middle_layer = 2,
	max_nodes_per_middle_layer = 3,
}

RUN_TEST_PLAYER_STATS :: Player_Stats{
	max_health = 10,
	attack = 2,
	defense = 1,
}

@(test)
test_node_room_seed_is_pure_nonzero_and_uses_all_inputs :: proc(t: ^testing.T) {
	base := derive_node_room_seed(91, Node_Id(2), .Combat, 3)
	testing.expect(t, base != 0)
	testing.expect_value(t, base, derive_node_room_seed(91, Node_Id(2), .Combat, 3))
	testing.expect(t, base != derive_node_room_seed(92, Node_Id(2), .Combat, 3))
	testing.expect(t, base != derive_node_room_seed(91, Node_Id(3), .Combat, 3))
	testing.expect(t, base != derive_node_room_seed(91, Node_Id(2), .Elite, 3))
	testing.expect(t, base != derive_node_room_seed(91, Node_Id(2), .Combat, 4))
}

@(test)
test_run_map_is_deterministic_for_a_seed :: proc(t: ^testing.T) {
	first, first_ok := generate_run_map(TEST_RUN_CONFIG, 0xCAFE)
	testing.expect(t, first_ok)
	defer destroy_run_map(&first)
	second, second_ok := generate_run_map(TEST_RUN_CONFIG, 0xCAFE)
	testing.expect(t, second_ok)
	defer destroy_run_map(&second)

	testing.expect_value(t, len(first.nodes), len(second.nodes))
	testing.expect_value(t, first.seed, second.seed)
	testing.expect_value(t, len(first.layer_starts), len(second.layer_starts))
	for node, index in first.nodes {
		other := second.nodes[index]
		testing.expect_value(t, node.id, other.id)
		testing.expect_value(t, node.kind, other.kind)
		testing.expect_value(t, node.depth, other.depth)
		testing.expect_value(t, node.room_seed, other.room_seed)
		testing.expect(t, node.room_seed != 0)
		testing.expect_value(t, node.lane, other.lane)
		testing.expect_value(t, node.outgoing_count, other.outgoing_count)
		for outgoing_index in 0..<node.outgoing_count {
			testing.expect_value(t, node.outgoing[outgoing_index], other.outgoing[outgoing_index])
		}
	}
}

@(test)
test_run_map_validation_rejects_tampered_room_seed :: proc(t: ^testing.T) {
	route_map, ok := generate_run_map(TEST_RUN_CONFIG, 0x5151)
	testing.expect(t, ok)
	defer destroy_run_map(&route_map)
	testing.expect(t, validate_run_map(&route_map))

	route_map.nodes[0].room_seed ~= 1
	testing.expect(t, !validate_run_map(&route_map))
}

@(test)
test_run_map_validation_rejects_nodes_outside_declared_layers :: proc(t: ^testing.T) {
	route_map, ok := generate_run_map(TEST_RUN_CONFIG, 0x6161)
	testing.expect(t, ok)
	defer destroy_run_map(&route_map)
	testing.expect(t, validate_run_map(&route_map))

	last := route_map.nodes[len(route_map.nodes)-1]
	last.id = Node_Id(len(route_map.nodes))
	last.room_seed = derive_node_room_seed(route_map.seed, last.id, last.kind, last.depth)
	append(&route_map.nodes, last)
	testing.expect(t, !validate_run_map(&route_map))
}

@(test)
test_run_map_validation_rejects_edge_outside_next_layer_interval :: proc(t: ^testing.T) {
	route_map, ok := generate_run_map(TEST_RUN_CONFIG, 0x7171)
	testing.expect(t, ok)
	defer destroy_run_map(&route_map)
	testing.expect(t, validate_run_map(&route_map))

	source := &route_map.nodes[route_map.layer_starts[0]]
	next_depth := 1
	rogue := route_map.nodes[route_map.layer_starts[next_depth]]
	rogue.id = Node_Id(len(route_map.nodes))
	rogue.room_seed = derive_node_room_seed(route_map.seed, rogue.id, rogue.kind, rogue.depth)
	append(&route_map.nodes, rogue)
	source.outgoing[0] = rogue.id
	testing.expect(t, !validate_run_map(&route_map))
}

@(test)
test_generated_run_maps_hold_their_invariants :: proc(t: ^testing.T) {
	for seed in u64(0)..<u64(128) {
		route_map, ok := generate_run_map(TEST_RUN_CONFIG, seed)
		testing.expect(t, ok)
		if !ok {
			continue
		}
		testing.expect(t, validate_run_map(&route_map))

		for node in route_map.nodes {
			testing.expect(t, node.room_seed != 0)
			testing.expect(t, node.outgoing_count <= MAX_NODE_CONNECTIONS)
			if node.depth < TEST_RUN_CONFIG.layer_count-2 {
				testing.expect(t, node.outgoing_count >= 2)
			}
		}
		destroy_run_map(&route_map)
	}
}

@(test)
test_run_rejects_invalid_map_configuration :: proc(t: ^testing.T) {
	invalid_configs := [?]Run_Map_Config{
		{layer_count = 2, min_nodes_per_middle_layer = 2, max_nodes_per_middle_layer = 3},
		{layer_count = 5, min_nodes_per_middle_layer = 1, max_nodes_per_middle_layer = 3},
		{layer_count = 5, min_nodes_per_middle_layer = 3, max_nodes_per_middle_layer = 2},
		{layer_count = 5, min_nodes_per_middle_layer = 2, max_nodes_per_middle_layer = 4},
	}

	for config in invalid_configs {
		route_map, ok := generate_run_map(config, 1)
		testing.expect(t, !ok)
		destroy_run_map(&route_map)
	}
}

@(test)
test_run_only_accepts_connected_path_choices :: proc(t: ^testing.T) {
	run, ok := create_run(RUN_TEST_PLAYER_STATS, TEST_RUN_CONFIG, 42)
	testing.expect(t, ok)
	defer destroy_run(&run)

	testing.expect_value(t, run.phase, Run_Phase.In_Room)
	testing.expect(t, validate_card_reward_state(&run))
	testing.expect_value(t, len(available_nodes(&run)), 0)
	testing.expect_value(t, finish_room(&run, .Combat), Run_Transition.Invalid)
	testing.expect_value(t, finish_room(&run, .Complete), Run_Transition.Reward)
	testing.expect_value(t, run.phase, Run_Phase.Reward)
	testing.expect_value(t, len(available_nodes(&run)), 0)
	testing.expect(t, !choose_node(&run, INVALID_NODE_ID))
	testing.expect_value(t, skip_card_reward(&run), Card_Reward_Result.Skipped)
	testing.expect_value(t, run.phase, Run_Phase.Choose_Path)

	choices := available_nodes(&run)
	testing.expect(t, len(choices) >= 2 && len(choices) <= MAX_NODE_CONNECTIONS)
	current_before := run.current_node
	testing.expect(t, !choose_node(&run, INVALID_NODE_ID))
	testing.expect_value(t, run.current_node, current_before)

	chosen := choices[0]
	testing.expect(t, choose_node(&run, chosen))
	testing.expect_value(t, run.current_node, chosen)
	testing.expect_value(t, run.phase, Run_Phase.In_Room)
	node, found := current_run_node(&run)
	testing.expect(t, found)
	testing.expect(t, node.entered)
}

@(test)
test_run_reaches_victory_by_traversing_one_node_per_layer :: proc(t: ^testing.T) {
	run, ok := create_run(RUN_TEST_PLAYER_STATS, TEST_RUN_CONFIG, 99)
	testing.expect(t, ok)
	defer destroy_run(&run)
	run.player.health = 6
	run.player.gold = 17

	for run.phase != .Victory {
		transition := finish_room(&run, .Complete)
		if transition == .Victory {
			break
		}
		testing.expect_value(t, transition, Run_Transition.Reward)
		testing.expect_value(t, run.phase, Run_Phase.Reward)
		testing.expect_value(t, skip_card_reward(&run), Card_Reward_Result.Skipped)
		testing.expect_value(t, run.phase, Run_Phase.Choose_Path)
		choices := available_nodes(&run)
		testing.expect(t, len(choices) > 0)
		chosen := choices[0]
		testing.expect(t, choose_node(&run, chosen))
	}

	testing.expect_value(t, run.cleared_count, TEST_RUN_CONFIG.layer_count)
	testing.expect_value(t, run.player.health, i32(6))
	testing.expect_value(t, run.player.gold, i32(17))
	testing.expect_value(t, finish_room(&run, .Complete), Run_Transition.Invalid)
}

@(test)
test_defeat_terminates_the_run_without_clearing_the_node :: proc(t: ^testing.T) {
	run, ok := create_run(RUN_TEST_PLAYER_STATS, TEST_RUN_CONFIG, 7)
	testing.expect(t, ok)
	defer destroy_run(&run)

	transition := finish_room(&run, .Defeat)
	testing.expect_value(t, transition, Run_Transition.Defeat)
	testing.expect_value(t, run.phase, Run_Phase.Defeat)
	testing.expect_value(t, run.cleared_count, 0)
	node, found := current_run_node(&run)
	testing.expect(t, found)
	testing.expect(t, !node.cleared)
}
