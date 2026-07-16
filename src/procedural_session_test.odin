package main

import "core:testing"
import game "game"
import level "level"

create_procedural_session_test_run :: proc(t: ^testing.T, seed: u64) -> game.Run_State {
	run, ok := game.create_run(DEMO_PLAYER_STATS, DEMO_RUN_CONFIG, seed)
	testing.expect(t, ok)
	return run
}

first_available_room_node :: proc(run: ^game.Run_State) -> game.Node_Id {
	for choice in game.available_nodes(run) {
		node, found := game.node_at(run, choice)
		if found && game.node_kind_has_room(node.kind) {
			return choice
		}
	}
	return game.INVALID_NODE_ID
}

create_procedural_run_with_first_special :: proc(
	t: ^testing.T,
	seed: u64,
	kind: game.Node_Kind,
) -> (game.Run_State, game.Node_Id) {
	for offset in u64(0)..<u64(512) {
		run := create_procedural_session_test_run(t, seed+offset)
		current, found := game.current_run_node(&run)
		if found {
			for index in 0..<current.outgoing_count {
				candidate_id := current.outgoing[index]
				candidate, candidate_found := game.node_at(&run, candidate_id)
				if candidate_found && candidate.kind == kind {
					return run, candidate_id
				}
			}
		}
		game.destroy_run(&run)
	}
	testing.expect(t, false)
	return {}, game.INVALID_NODE_ID
}

procedural_level_fingerprint :: proc(level_data: ^level.Level) -> (result: u64) {
	if level_data == nil {
		return
	}
	result = 0xCBF29CE484222325
	for tile in level_data.tiles.cells {
		result = (result~u64(int(tile.kind)+1))*0x100000001B3
	}
	result = (result~u64(level_data.player_spawn.x+1))*0x100000001B3
	result = (result~u64(level_data.player_spawn.y+1))*0x100000001B3
	return
}

@(test)
test_procedural_room_install_rebinds_borrowed_pointers :: proc(t: ^testing.T) {
	level_data: level.Level
	defer level.destroy(&level_data)
	run := create_procedural_session_test_run(t, 0xA11CE)
	defer game.destroy_run(&run)
	room: game.Room
	defer game.destroy_room(&room)

	testing.expect(t, replace_current_demo_room(&level_data, &run, &room, true))
	testing.expect(t, room.player == &run.player)
	testing.expect(t, room.level_data == &level_data)
	testing.expect_value(t, run.player.position, level_data.player_spawn)
	testing.expect_value(t, room.phase, game.Room_Phase.Combat)
	testing.expect(t, len(room.enemies) > 0)
	testing.expect(t, game.validate_enemy_intents(&room))

	node, found := game.current_run_node(&run)
	testing.expect(t, found)
	profile, profile_ok := game.room_generation_profile(node)
	testing.expect(t, profile_ok)
	report := level.validate_generated_room(&level_data, profile.level_config)
	testing.expect_value(t, report.error, level.Room_Validation_Error.None)
}

@(test)
test_enter_node_installs_its_deterministic_room :: proc(t: ^testing.T) {
	level_data: level.Level
	defer level.destroy(&level_data)
	run := create_procedural_session_test_run(t, 0xBADC0DE)
	defer game.destroy_run(&run)
	room: game.Room
	defer game.destroy_room(&room)
	testing.expect(t, replace_current_demo_room(&level_data, &run, &room, true))

	room.phase = .Complete
	testing.expect_value(t, game.finish_room(&run, room.phase), game.Run_Transition.Reward)
	testing.expect_value(t, game.skip_card_reward(&run), game.Card_Reward_Result.Skipped)
	choices := game.available_nodes(&run)
	testing.expect(t, len(choices) > 0)
	if len(choices) == 0 {
		return
	}
	target_id := first_available_room_node(&run)
	testing.expect(t, target_id != game.INVALID_NODE_ID)
	target, found := game.node_at(&run, target_id)
	testing.expect(t, found)
	if !found {
		return
	}
	expected_seed := target.room_seed

	testing.expect(t, enter_demo_node(&level_data, &run, &room, target_id, true))
	testing.expect_value(t, run.current_node, target_id)
	testing.expect_value(
		t,
		game.derive_node_room_seed(run.seed, target.id, target.kind, target.depth),
		expected_seed,
	)
	testing.expect(t, room.player == &run.player)
	testing.expect(t, room.level_data == &level_data)
	testing.expect_value(t, run.player.position, level_data.player_spawn)
}

@(test)
test_shop_mutations_persist_into_the_next_procedural_room :: proc(t: ^testing.T) {
	level_data: level.Level
	defer level.destroy(&level_data)
	run, shop_node := create_procedural_run_with_first_special(t, 0x5A0FCAFE, .Shop)
	defer game.destroy_run(&run)
	room: game.Room
	defer game.destroy_room(&room)
	testing.expect(t, replace_current_demo_room(&level_data, &run, &room, true))

	room.phase = .Complete
	testing.expect_value(t, game.finish_room(&run, room.phase), game.Run_Transition.Reward)
	run.player.gold = 20
	testing.expect_value(t, game.skip_card_reward(&run), game.Card_Reward_Result.Skipped)
	testing.expect(t, enter_demo_node(&level_data, &run, &room, shop_node, true))
	testing.expect_value(t, run.phase, game.Run_Phase.Shop)

	upgraded_id := run.player.deck.owned[0].id
	upgrade_before := run.player.deck.owned[0].upgrade_level
	owned_before := run.player.deck.owned_count
	purchased_definition := run.shop.offers[0].definition_id
	purchased_id := run.player.deck.next_card_id
	testing.expect_value(t, game.buy_shop_upgrade(&run, upgraded_id), game.Shop_Result.Upgraded)
	testing.expect_value(t, game.buy_shop_card(&run, 0), game.Shop_Result.Purchased)
	testing.expect_value(t, run.player.deck.owned_count, owned_before+1)
	testing.expect_value(t, game.leave_shop(&run), game.Shop_Result.Left)

	next_room := first_available_room_node(&run)
	testing.expect(t, next_room != game.INVALID_NODE_ID)
	if next_room == game.INVALID_NODE_ID {
		return
	}
	testing.expect(t, enter_demo_node(&level_data, &run, &room, next_room, true))
	testing.expect_value(t, run.phase, game.Run_Phase.In_Room)
	testing.expect(t, run.shop == game.Shop_State{})
	testing.expect(t, run.player.deck.combat_active)
	testing.expect(t, room.player == &run.player)
	testing.expect(t, room.level_data == &level_data)

	upgraded_index, upgraded_found := game.owned_card_index_by_id(&run.player.deck, upgraded_id)
	testing.expect(t, upgraded_found)
	if upgraded_found {
		testing.expect_value(
			t,
			run.player.deck.owned[upgraded_index].upgrade_level,
			upgrade_before+1,
		)
	}
	purchased_index, purchased_found := game.owned_card_index_by_id(&run.player.deck, purchased_id)
	testing.expect(t, purchased_found)
	if purchased_found {
		testing.expect_value(
			t,
			run.player.deck.owned[purchased_index].definition_id,
			purchased_definition,
		)
	}
}

@(test)
test_special_nodes_preserve_the_room_until_the_next_room_node_is_installed :: proc(t: ^testing.T) {
	special_kinds := [?]game.Node_Kind{.Shop, .Rest, .Event, .Treasure}
	for kind, kind_index in special_kinds {
		level_data: level.Level
		run, special_node := create_procedural_run_with_first_special(
			t,
			0x51EC1A1+u64(kind_index)*0x100,
			kind,
		)
		room: game.Room
		testing.expect(t, replace_current_demo_room(&level_data, &run, &room, true))

		room.phase = .Complete
		testing.expect_value(t, game.finish_room(&run, room.phase), game.Run_Transition.Reward)
		testing.expect_value(t, game.skip_card_reward(&run), game.Card_Reward_Result.Skipped)
		level_fingerprint_before := procedural_level_fingerprint(&level_data)
		level_cells_before := &level_data.tiles.cells[0]
		enemy_cells_before := &room.enemies[0]
		enemy_count_before := len(room.enemies)
		room_phase_before := room.phase

		testing.expect(t, enter_demo_node(&level_data, &run, &room, special_node, true))
		testing.expect_value(t, run.current_node, special_node)
		testing.expect_value(t, procedural_level_fingerprint(&level_data), level_fingerprint_before)
		testing.expect(t, &level_data.tiles.cells[0] == level_cells_before)
		testing.expect(t, &room.enemies[0] == enemy_cells_before)
		testing.expect_value(t, len(room.enemies), enemy_count_before)
		testing.expect_value(t, room.phase, room_phase_before)
		testing.expect(t, room.player == &run.player)
		testing.expect(t, room.level_data == &level_data)

		switch kind {
		case .Shop:
			testing.expect_value(t, run.phase, game.Run_Phase.Shop)
			testing.expect_value(t, game.leave_shop(&run), game.Shop_Result.Left)
		case .Rest:
			testing.expect_value(t, run.phase, game.Run_Phase.Rest)
			testing.expect_value(t, game.leave_special_node(&run), game.Special_Node_Result.Left)
			testing.expect_value(t, game.continue_special_node(&run), game.Special_Node_Result.Continued)
		case .Event:
			testing.expect_value(t, run.phase, game.Run_Phase.Event)
			testing.expect_value(t, game.leave_special_node(&run), game.Special_Node_Result.Left)
			testing.expect_value(t, game.continue_special_node(&run), game.Special_Node_Result.Continued)
		case .Treasure:
			testing.expect_value(t, run.phase, game.Run_Phase.Treasure)
			testing.expect_value(t, game.leave_special_node(&run), game.Special_Node_Result.Left)
			testing.expect_value(t, game.continue_special_node(&run), game.Special_Node_Result.Continued)
		case .Combat, .Elite, .Boss, .Count:
			testing.expect(t, false, "expected a special node kind")
		}

		next_room := first_available_room_node(&run)
		testing.expect(t, next_room != game.INVALID_NODE_ID)
		if next_room != game.INVALID_NODE_ID {
			testing.expect(t, enter_demo_node(&level_data, &run, &room, next_room, true))
			testing.expect_value(t, run.phase, game.Run_Phase.In_Room)
			testing.expect(t, room.player == &run.player)
			testing.expect(t, room.level_data == &level_data)
			testing.expect(t, &level_data.tiles.cells[0] != level_cells_before)
		}

		game.destroy_room(&room)
		game.destroy_run(&run)
		level.destroy(&level_data)
	}
}

@(test)
test_restart_rebinds_room_to_replaced_run_and_level :: proc(t: ^testing.T) {
	level_data: level.Level
	defer level.destroy(&level_data)
	run := create_procedural_session_test_run(t, 7)
	defer game.destroy_run(&run)
	room: game.Room
	defer game.destroy_room(&room)
	testing.expect(t, replace_current_demo_room(&level_data, &run, &room, true))

	for seed in u64(8)..<u64(24) {
		testing.expect(t, restart_demo_session(&level_data, &run, &room, seed, true))
		testing.expect_value(t, run.seed, seed)
		testing.expect(t, room.player == &run.player)
		testing.expect(t, room.level_data == &level_data)
		testing.expect_value(t, run.player.position, level_data.player_spawn)
		testing.expect_value(t, room.phase, game.Room_Phase.Combat)
	}
}

@(test)
test_failed_node_entry_leaves_session_unchanged :: proc(t: ^testing.T) {
	level_data: level.Level
	defer level.destroy(&level_data)
	run := create_procedural_session_test_run(t, 0xDEAD)
	defer game.destroy_run(&run)
	room: game.Room
	defer game.destroy_room(&room)
	testing.expect(t, replace_current_demo_room(&level_data, &run, &room, true))

	room.phase = .Complete
	testing.expect_value(t, game.finish_room(&run, room.phase), game.Run_Transition.Reward)
	testing.expect_value(t, game.skip_card_reward(&run), game.Card_Reward_Result.Skipped)
	choices := game.available_nodes(&run)
	testing.expect(t, len(choices) > 0)
	if len(choices) == 0 {
		return
	}
	target_id := first_available_room_node(&run)
	testing.expect(t, target_id != game.INVALID_NODE_ID)
	target, found := game.node_at(&run, target_id)
	testing.expect(t, found)
	if !found {
		return
	}
	target.room_seed = 0

	phase_before := run.phase
	current_node_before := run.current_node
	player_before := run.player
	target_entered_before := target.entered
	level_fingerprint_before := procedural_level_fingerprint(&level_data)
	level_cells_before := &level_data.tiles.cells[0]
	room_phase_before := room.phase
	enemy_count_before := len(room.enemies)
	testing.expect(t, enemy_count_before > 0)
	if enemy_count_before == 0 {
		return
	}
	first_enemy_before := room.enemies[0]

	testing.expect(t, !enter_demo_node(&level_data, &run, &room, target_id, true))
	testing.expect_value(t, run.phase, phase_before)
	testing.expect_value(t, run.current_node, current_node_before)
	testing.expect(t, run.player == player_before)
	testing.expect_value(t, target.entered, target_entered_before)
	testing.expect_value(t, procedural_level_fingerprint(&level_data), level_fingerprint_before)
	testing.expect(t, &level_data.tiles.cells[0] == level_cells_before)
	testing.expect(t, room.player == &run.player)
	testing.expect(t, room.level_data == &level_data)
	testing.expect_value(t, room.phase, room_phase_before)
	testing.expect_value(t, len(room.enemies), enemy_count_before)
	testing.expect_value(t, room.enemies[0], first_enemy_before)
}

@(test)
test_prepared_room_can_be_reused_without_leaking_previous_owners :: proc(t: ^testing.T) {
	run := create_procedural_session_test_run(t, 0xABCD)
	defer game.destroy_run(&run)
	node, found := game.current_run_node(&run)
	testing.expect(t, found)
	if !found {
		return
	}
	prepared: Prepared_Demo_Room
	defer destroy_prepared_demo_room(&prepared)
	testing.expect(t, prepare_demo_room(&prepared, &run, node, true))
	testing.expect(t, len(prepared.level_data.tiles.cells) > 0)
	testing.expect(t, len(prepared.room.enemies) > 0)

	invalid_node := node^
	invalid_node.room_seed = 0
	testing.expect(t, !prepare_demo_room(&prepared, &run, &invalid_node, true))
	testing.expect_value(t, len(prepared.level_data.tiles.cells), 0)
	testing.expect_value(t, len(prepared.room.enemies), 0)
	testing.expect(t, prepared.room.player == nil)
}
