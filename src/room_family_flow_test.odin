package main

import "core:testing"
import game "game"
import level "level"

@(test)
test_family_history_changes_only_when_prepared_room_is_installed :: proc(t: ^testing.T) {
	run := create_procedural_session_test_run(t, 0xA551)
	defer game.destroy_run(&run)
	data: level.Level
	defer level.destroy(&data)
	room: game.Room
	defer game.destroy_room(&room)
	prepared: Prepared_Demo_Room
	defer destroy_prepared_demo_room(&prepared)
	node, found := game.current_run_node(&run)
	testing.expect(t, found)
	if !found { return }
	testing.expect_value(t, run.last_room_family, level.Room_Family.Scattered)
	testing.expect(t, prepare_demo_room(&prepared, &run, node, true))
	first_family := prepared.room.family
	testing.expect(t, first_family != .Scattered)
	testing.expect_value(t, run.last_room_family, level.Room_Family.Scattered)
	install_prepared_demo_room(&data, &run, &room, &prepared)
	testing.expect_value(t, run.last_room_family, first_family)
	testing.expect_value(t, room.family, first_family)

	room.phase = .Complete
	testing.expect_value(t, game.finish_room(&run, room.phase), game.Run_Transition.Reward)
	testing.expect_value(t, game.skip_card_reward(&run), game.Card_Reward_Result.Skipped)
	next_id := first_available_room_node(&run)
	next_node, next_found := game.node_at(&run, next_id)
	testing.expect(t, next_found)
	if !next_found { return }
	testing.expect(t, prepare_demo_room(&prepared, &run, next_node, true))
	testing.expect(t, prepared.room.family != first_family)
	testing.expect_value(t, run.last_room_family, first_family)
	fingerprint := procedural_level_fingerprint(&data)
	invalid := next_node^
	invalid.room_seed = 0
	testing.expect(t, !prepare_demo_room(&prepared, &run, &invalid, true))
	testing.expect_value(t, run.last_room_family, first_family)
	testing.expect_value(t, room.family, first_family)
	testing.expect_value(t, procedural_level_fingerprint(&data), fingerprint)
}

@(test)
test_special_nodes_keep_last_room_family_for_the_next_room :: proc(t: ^testing.T) {
	kinds := [4]game.Node_Kind{.Shop, .Rest, .Event, .Treasure}
	for kind, index in kinds {
		run, special_id := create_procedural_run_with_first_special(t, 0xFA110+u64(index), kind)
		data: level.Level
		room: game.Room
		testing.expect(t, replace_current_demo_room(&data, &run, &room, true))
		previous_family := room.family
		room.phase = .Complete
		testing.expect_value(t, game.finish_room(&run, room.phase), game.Run_Transition.Reward)
		testing.expect_value(t, game.skip_card_reward(&run), game.Card_Reward_Result.Skipped)
		testing.expect(t, enter_demo_node(&data, &run, &room, special_id, true))
		testing.expect_value(t, run.last_room_family, previous_family)
		if kind == .Shop {
			testing.expect_value(t, game.leave_shop(&run), game.Shop_Result.Left)
		} else {
			testing.expect_value(t, game.leave_special_node(&run), game.Special_Node_Result.Left)
			testing.expect_value(t, game.continue_special_node(&run), game.Special_Node_Result.Continued)
		}
		testing.expect_value(t, run.last_room_family, previous_family)
		next_id := first_available_room_node(&run)
		testing.expect(t, next_id != game.INVALID_NODE_ID)
		if next_id != game.INVALID_NODE_ID {
			next_node, found := game.node_at(&run, next_id)
			testing.expect(t, found)
			if found {
				expected_family := game.room_family_for_node(next_node, previous_family)
				testing.expect(t, enter_demo_node(&data, &run, &room, next_id, true))
				testing.expect_value(t, room.family, expected_family)
				testing.expect_value(t, run.last_room_family, expected_family)
				testing.expect(t, room.family != previous_family)
			}
		}
		game.destroy_room(&room)
		level.destroy(&data)
		game.destroy_run(&run)
	}
}

Family_Path_Snapshot :: struct {
	families: [32]level.Room_Family,
	layouts: [32]u64,
	nodes: [32]game.Node_Id,
	count: int,
}

record_installed_family_path :: proc(t: ^testing.T, seed: u64) -> (snapshot: Family_Path_Snapshot) {
	run := create_procedural_session_test_run(t, seed)
	defer game.destroy_run(&run)
	data: level.Level
	defer level.destroy(&data)
	room: game.Room
	defer game.destroy_room(&room)
	testing.expect(t, replace_current_demo_room(&data, &run, &room, true))
	for step in 0..<len(snapshot.families) {
		snapshot.families[step] = room.family
		snapshot.layouts[step] = procedural_level_fingerprint(&data)
		snapshot.nodes[step] = run.current_node
		snapshot.count += 1
		testing.expect_value(t, run.last_room_family, room.family)
		if step > 0 { testing.expect(t, room.family != snapshot.families[step-1]) }
		room.phase = .Complete
		transition := game.finish_room(&run, room.phase)
		if transition == .Victory { return }
		testing.expect_value(t, transition, game.Run_Transition.Reward)
		testing.expect_value(t, game.skip_card_reward(&run), game.Card_Reward_Result.Skipped)
		next_id := first_available_room_node(&run)
		testing.expect(t, next_id != game.INVALID_NODE_ID)
		if next_id == game.INVALID_NODE_ID { return }
		testing.expect(t, enter_demo_node(&data, &run, &room, next_id, true))
	}
	testing.expect(t, false, "room path did not reach the boss")
	return
}

@(test)
test_same_chosen_route_reproduces_installed_room_families_without_repetitions :: proc(t: ^testing.T) {
	for seed in u64(11)..=18 {
		first := record_installed_family_path(t, seed)
		second := record_installed_family_path(t, seed)
		testing.expect(t, first.count > 2)
		testing.expect_value(t, first, second)
	}
}

@(test)
test_restart_discards_family_history_and_recreates_the_first_seeded_room :: proc(t: ^testing.T) {
	run := create_procedural_session_test_run(t, 0xFAC7)
	defer game.destroy_run(&run)
	data: level.Level
	defer level.destroy(&data)
	room: game.Room
	defer game.destroy_room(&room)
	testing.expect(t, replace_current_demo_room(&data, &run, &room, true))
	for seed in u64(31)..=38 {
		testing.expect(t, restart_demo_session(&data, &run, &room, seed, true))
		node, found := game.current_run_node(&run)
		testing.expect(t, found)
		if !found { return }
		expected_family := game.room_family_for_node(node)
		testing.expect_value(t, room.family, expected_family)
		testing.expect_value(t, run.last_room_family, expected_family)
		first_fingerprint := procedural_level_fingerprint(&data)
		// Restarting from this same family must allow it again as the new first room.
		testing.expect(t, restart_demo_session(&data, &run, &room, seed, true))
		testing.expect_value(t, room.family, expected_family)
		testing.expect_value(t, run.last_room_family, expected_family)
		testing.expect_value(t, procedural_level_fingerprint(&data), first_fingerprint)
	}
}
