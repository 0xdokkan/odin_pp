package integration
import run_session "../run"

import "core:testing"
import game "../game"
import level "../level"

relic_flow_test_run :: proc(
	t: ^testing.T,
	next_kind: game.Node_Kind = .Count,
	needs_guard: bool = false,
) -> (game.Run_State, game.Node_Id) {
	for seed in u64(1)..<u64(513) {
		run, ok := game.create_run(run_session.DEMO_PLAYER_STATS, run_session.DEMO_RUN_CONFIG, seed, true)
		testing.expect(t, ok)
		guard := !needs_guard
		for id in run.relic_reward.offers.choices[:run.relic_reward.offers.count] {
			guard = guard || id == .Guard_Sigil
		}
		target := game.INVALID_NODE_ID
		current, _ := game.current_run_node(&run)
		for id in current.outgoing[:current.outgoing_count] {
			node, _ := game.node_at(&run, id)
			if next_kind == .Count || node.kind == next_kind {
				target = id
				break
			}
		}
		if guard && target != game.INVALID_NODE_ID {
			return run, target
		}
		game.destroy_run(&run)
	}
	testing.expect(t, false, "could not find seeded relic flow fixture")
	return {}, game.INVALID_NODE_ID
}

relic_flow_find_offer :: proc(run: ^game.Run_State, id: game.Relic_Id) -> int {
	for offered, index in run.relic_reward.offers.choices[:run.relic_reward.offers.count] {
		if offered == id { return index }
	}
	return -1
}

@(test)
test_relic_starter_guard_selection_is_atomic_and_applies_entry_shield_once :: proc(t: ^testing.T) {
	run, _ := relic_flow_test_run(t, needs_guard = true)
	defer game.destroy_run(&run)
	data: level.Level
	defer level.destroy(&data)
	room: game.Room
	defer game.destroy_room(&room)
	testing.expect(t, run_session.replace_current_demo_room(&data, &run, &room, true))
	testing.expect_value(t, run.relic_reward.origin, game.Run_Relic_Origin.Starter)
	testing.expect_value(t, run.relic_reward.offers.count, 3)
	player_before := run.player
	offers_before := run.relic_reward
	reward_rng, shop_rng := run.reward_random_state, run.shop_random_state
	testing.expect(t, !run_session.resolve_demo_relic_choice(&run, &room, 9, false))
	testing.expect_value(t, run.player, player_before)
	testing.expect_value(t, run.relic_reward, offers_before)
	testing.expect_value(t, game.finish_room(&run, .Complete), game.Run_Transition.Invalid)
	choice := relic_flow_find_offer(&run, .Guard_Sigil)
	testing.expect(t, choice >= 0)
	testing.expect(t, run_session.resolve_demo_relic_choice(&run, &room, choice, false))
	testing.expect(t, game.player_has_relic(&run.player, .Guard_Sigil))
	shield, found := game.status_for_entity(&room, game.PLAYER_ENTITY, .Shield)
	testing.expect(t, found && shield.potency == 2 && shield.remaining_pulses == 3)
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect_value(t, run.reward_random_state, reward_rng)
	testing.expect_value(t, run.shop_random_state, shop_rng)
	testing.expect_value(t, run.player.deck.random_state, player_before.deck.random_state)
	testing.expect(t, !run_session.resolve_demo_relic_choice(&run, &room, choice, false))
	game.apply_entry_relic(&room)
	testing.expect_value(t, shield.potency, i32(2))
	testing.expect(t, game.validate_run_state(&run))
}

@(test)
test_relic_starter_skip_preserves_inventory_and_random_streams :: proc(t: ^testing.T) {
	run, _ := relic_flow_test_run(t)
	defer game.destroy_run(&run)
	data: level.Level
	defer level.destroy(&data)
	room: game.Room
	defer game.destroy_room(&room)
	testing.expect(t, run_session.replace_current_demo_room(&data, &run, &room, true))
	player_before := run.player
	reward_rng, shop_rng := run.reward_random_state, run.shop_random_state
	testing.expect(t, run_session.resolve_demo_relic_choice(&run, &room, -1, true))
	testing.expect_value(t, run.player, player_before)
	testing.expect_value(t, run.reward_random_state, reward_rng)
	testing.expect_value(t, run.shop_random_state, shop_rng)
	testing.expect(t, !game.run_has_relic_choice(&run))
	testing.expect(t, game.validate_run_state(&run))
}

@(test)
test_relic_guard_persists_into_next_room_and_restart_clears_inventory :: proc(t: ^testing.T) {
	run, _ := relic_flow_test_run(t, needs_guard = true)
	defer game.destroy_run(&run)
	data: level.Level
	defer level.destroy(&data)
	room: game.Room
	defer game.destroy_room(&room)
	testing.expect(t, run_session.replace_current_demo_room(&data, &run, &room, true))
	testing.expect(t, run_session.resolve_demo_relic_choice(&run, &room, relic_flow_find_offer(&run, .Guard_Sigil), false))
	run.player.relics.combat.exhaust_used = true
	room.phase = .Complete
	testing.expect_value(t, game.finish_room(&run, room.phase), game.Run_Transition.Reward)
	testing.expect_value(t, game.skip_card_reward(&run), game.Card_Reward_Result.Skipped)
	target := first_available_room_node(&run)
	testing.expect(t, target != game.INVALID_NODE_ID)
	testing.expect(t, run_session.enter_demo_node(&data, &run, &room, target, true))
	testing.expect(t, game.player_has_relic(&run.player, .Guard_Sigil))
	testing.expect(t, !run.player.relics.combat.exhaust_used)
	shield, found := game.status_for_entity(&room, game.PLAYER_ENTITY, .Shield)
	testing.expect(t, found && shield.potency == 2)
	testing.expect(t, room.player == &run.player)
	testing.expect(t, run_session.restart_demo_session(&data, &run, &room, run.seed+1000, true))
	testing.expect_value(t, run.player.relics.count, 0)
	testing.expect_value(t, run.relic_reward.origin, game.Run_Relic_Origin.Starter)
	testing.expect(t, run.relic_rewards_enabled)
	_, found = game.status_for_entity(&room, game.PLAYER_ENTITY, .Shield)
	testing.expect(t, !found)
	testing.expect(t, game.validate_run_state(&run))
}

@(test)
test_relic_elite_reward_preserves_card_reward_and_blocks_path_until_resolved :: proc(t: ^testing.T) {
	for skip in ([2]bool{false, true}) {
		run, elite := relic_flow_test_run(t, .Elite)
		data: level.Level
		room: game.Room
		testing.expect(t, run_session.replace_current_demo_room(&data, &run, &room, true))
		testing.expect(t, run_session.resolve_demo_relic_choice(&run, &room, -1, true))
		room.phase = .Complete
		testing.expect_value(t, game.finish_room(&run, room.phase), game.Run_Transition.Reward)
		testing.expect_value(t, game.skip_card_reward(&run), game.Card_Reward_Result.Skipped)
		testing.expect(t, run_session.enter_demo_node(&data, &run, &room, elite, true))
		room.phase = .Complete
		testing.expect_value(t, game.finish_room(&run, room.phase), game.Run_Transition.Reward)
		testing.expect_value(t, run.relic_reward.origin, game.Run_Relic_Origin.Elite)
		cards := run.card_reward
		reward_rng, shop_rng := run.reward_random_state, run.shop_random_state
		testing.expect_value(t, game.skip_card_reward(&run), game.Card_Reward_Result.Invalid)
		testing.expect_value(t, game.choose_card_reward(&run, 0), game.Card_Reward_Result.Invalid)
		testing.expect_value(t, run.card_reward, cards)
		choice := -1 if skip else 0
		testing.expect(t, run_session.resolve_demo_relic_choice(&run, &room, choice, skip))
		testing.expect_value(t, run.card_reward, cards)
		testing.expect_value(t, run.phase, game.Run_Phase.Reward)
		testing.expect_value(t, run.player.relics.count, 0 if skip else 1)
		testing.expect_value(t, run.reward_random_state, reward_rng)
		testing.expect_value(t, run.shop_random_state, shop_rng)
		testing.expect_value(t, game.choose_card_reward(&run, 0), game.Card_Reward_Result.Added)
		testing.expect_value(t, run.phase, game.Run_Phase.Choose_Path)
		testing.expect(t, game.validate_run_state(&run))
		game.destroy_room(&room)
		level.destroy(&data)
		game.destroy_run(&run)
	}
}

@(test)
test_relic_treasure_claim_offers_once_and_gates_continue :: proc(t: ^testing.T) {
	run, treasure := relic_flow_test_run(t, .Treasure)
	defer game.destroy_run(&run)
	data: level.Level
	defer level.destroy(&data)
	room: game.Room
	defer game.destroy_room(&room)
	testing.expect(t, run_session.replace_current_demo_room(&data, &run, &room, true))
	testing.expect(t, run_session.resolve_demo_relic_choice(&run, &room, -1, true))
	room.phase = .Complete
	testing.expect_value(t, game.finish_room(&run, room.phase), game.Run_Transition.Reward)
	testing.expect_value(t, game.skip_card_reward(&run), game.Card_Reward_Result.Skipped)
	testing.expect(t, run_session.enter_demo_node(&data, &run, &room, treasure, true))
	testing.expect_value(t, game.claim_treasure(&run), game.Special_Node_Result.Treasure_Claimed)
	testing.expect_value(t, run.relic_reward.origin, game.Run_Relic_Origin.Treasure)
	offer := run.relic_reward
	gold := run.player.gold
	testing.expect(t, !game.special_node_can_continue(&run))
	testing.expect_value(t, game.continue_special_node(&run), game.Special_Node_Result.Invalid)
	testing.expect_value(t, game.claim_treasure(&run), game.Special_Node_Result.Already_Resolved)
	testing.expect_value(t, run.relic_reward, offer)
	testing.expect_value(t, run.player.gold, gold)
	testing.expect(t, run_session.resolve_demo_relic_choice(&run, &room, 0, false))
	testing.expect_value(t, run.player.relics.count, 1)
	testing.expect_value(t, run.player.gold, gold)
	testing.expect_value(t, game.continue_special_node(&run), game.Special_Node_Result.Continued)
	testing.expect_value(t, run.phase, game.Run_Phase.Choose_Path)
	testing.expect(t, game.validate_run_state(&run))
}

@(test)
test_relic_offer_validation_rejects_stale_node_invalid_origin_and_reordered_choices :: proc(t: ^testing.T) {
	run, _ := relic_flow_test_run(t)
	defer game.destroy_run(&run)
	original := run.relic_reward
	player_before := run.player
	for corruption in 0..<3 {
		run.relic_reward = original
		switch corruption {
		case 0:
			run.relic_reward.source_node = game.INVALID_NODE_ID
		case 1:
			run.relic_reward = game.make_run_relic_reward(&run, game.Run_Relic_Origin(99))
			// Unknown origins must never construct a real offer.
			testing.expect_value(t, run.relic_reward, game.Run_Relic_Reward{})
			run.relic_reward = original
			run.relic_reward.origin = game.Run_Relic_Origin(99)
		case 2:
			run.relic_reward.offers.choices[0], run.relic_reward.offers.choices[1] =
				run.relic_reward.offers.choices[1], run.relic_reward.offers.choices[0]
		}
		corrupt := run.relic_reward
		testing.expect(t, !game.validate_run_state(&run))
		testing.expect(t, !game.choose_run_relic(&run, 0))
		testing.expect(t, !game.skip_run_relic(&run))
		testing.expect_value(t, run.player, player_before)
		testing.expect_value(t, run.relic_reward, corrupt)
	}
}
