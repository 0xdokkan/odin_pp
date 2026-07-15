package game

import "core:testing"

REWARD_TEST_RUN_CONFIG :: Run_Map_Config{
	layer_count = 5,
	min_nodes_per_middle_layer = 2,
	max_nodes_per_middle_layer = 3,
}

REWARD_TEST_PLAYER_STATS :: Player_Stats{
	max_health = 10,
	attack = 2,
	defense = 1,
}

@(test)
test_card_reward_offers_are_deterministic_distinct_and_valid :: proc(t: ^testing.T) {
	for seed in u64(0)..<u64(128) {
		first, first_ok := create_run(REWARD_TEST_PLAYER_STATS, REWARD_TEST_RUN_CONFIG, seed)
		testing.expect(t, first_ok)
		if !first_ok {
			continue
		}
		second, second_ok := create_run(REWARD_TEST_PLAYER_STATS, REWARD_TEST_RUN_CONFIG, seed)
		testing.expect(t, second_ok)
		if !second_ok {
			destroy_run(&first)
			continue
		}

		testing.expect_value(t, finish_room(&first, .Complete), Run_Transition.Reward)
		testing.expect_value(t, finish_room(&second, .Complete), Run_Transition.Reward)
		first_choices := available_card_rewards(&first)
		second_choices := available_card_rewards(&second)
		testing.expect_value(t, len(first_choices), CARD_REWARD_CHOICE_COUNT)
		testing.expect_value(t, len(second_choices), CARD_REWARD_CHOICE_COUNT)

		for index in 0..<len(first_choices) {
			testing.expect_value(t, first_choices[index], second_choices[index])
			definition, found := card_definition_by_id(first_choices[index])
			testing.expect(t, found)
			testing.expect(t, found && validate_card_definition(&definition))
			for previous in 0..<index {
				testing.expect(t, first_choices[index] != first_choices[previous])
			}
		}
		testing.expect(t, validate_card_reward_state(&first))
		testing.expect(t, validate_card_reward_state(&second))

		destroy_run(&first)
		destroy_run(&second)
	}
}

@(test)
test_card_reward_rng_is_independent_from_deck_rng :: proc(t: ^testing.T) {
	first, first_ok := create_run(REWARD_TEST_PLAYER_STATS, REWARD_TEST_RUN_CONFIG, 0xA11CE)
	testing.expect(t, first_ok)
	defer destroy_run(&first)
	second, second_ok := create_run(REWARD_TEST_PLAYER_STATS, REWARD_TEST_RUN_CONFIG, 0xA11CE)
	testing.expect(t, second_ok)
	defer destroy_run(&second)

	testing.expect(t, reseed_deck(&first.player.deck, 0x1111))
	testing.expect(t, reseed_deck(&second.player.deck, 0xEEEE))
	first_deck_rng := first.player.deck.random_state
	second_deck_rng := second.player.deck.random_state
	testing.expect(t, first_deck_rng != second_deck_rng)

	testing.expect_value(t, finish_room(&first, .Complete), Run_Transition.Reward)
	testing.expect_value(t, finish_room(&second, .Complete), Run_Transition.Reward)
	testing.expect_value(t, first.player.deck.random_state, first_deck_rng)
	testing.expect_value(t, second.player.deck.random_state, second_deck_rng)
	testing.expect_value(t, first.reward_random_state, second.reward_random_state)

	first_choices := available_card_rewards(&first)
	second_choices := available_card_rewards(&second)
	for index in 0..<CARD_REWARD_CHOICE_COUNT {
		testing.expect_value(t, first_choices[index], second_choices[index])
	}
}

@(test)
test_choosing_card_reward_is_atomic_and_one_shot :: proc(t: ^testing.T) {
	run, ok := create_run(REWARD_TEST_PLAYER_STATS, REWARD_TEST_RUN_CONFIG, 0xC001CE)
	testing.expect(t, ok)
	defer destroy_run(&run)
	testing.expect_value(t, finish_room(&run, .Complete), Run_Transition.Reward)

	choice_index := 1
	chosen_definition := run.card_reward.choices[choice_index]
	owned_before := run.player.deck.owned_count
	next_id_before := run.player.deck.next_card_id
	reward_rng_before := run.reward_random_state
	testing.expect_value(t, choose_card_reward(&run, choice_index), Card_Reward_Result.Added)

	testing.expect_value(t, run.phase, Run_Phase.Choose_Path)
	testing.expect_value(t, run.card_reward.choice_count, 0)
	testing.expect_value(t, run.player.deck.owned_count, owned_before+1)
	testing.expect_value(t, run.player.deck.next_card_id, next_id_before+1)
	testing.expect_value(t, run.player.deck.owned[owned_before].id, next_id_before)
	testing.expect_value(t, run.player.deck.owned[owned_before].definition_id, chosen_definition)
	testing.expect_value(t, run.reward_random_state, reward_rng_before)
	testing.expect(t, validate_deck_state(&run.player.deck))
	testing.expect(t, validate_card_reward_state(&run))

	deck_after := run.player.deck
	reward_after := run.card_reward
	testing.expect_value(t, choose_card_reward(&run, choice_index), Card_Reward_Result.Invalid)
	testing.expect(t, run.player.deck == deck_after)
	testing.expect(t, run.card_reward == reward_after)
	testing.expect_value(t, run.phase, Run_Phase.Choose_Path)
}

@(test)
test_invalid_card_reward_indices_do_not_mutate_state :: proc(t: ^testing.T) {
	run, ok := create_run(REWARD_TEST_PLAYER_STATS, REWARD_TEST_RUN_CONFIG, 0xBAD1D)
	testing.expect(t, ok)
	defer destroy_run(&run)
	testing.expect_value(t, finish_room(&run, .Complete), Run_Transition.Reward)

	deck_before := run.player.deck
	reward_before := run.card_reward
	rng_before := run.reward_random_state
	phase_before := run.phase
	testing.expect_value(t, choose_card_reward(&run, -1), Card_Reward_Result.Invalid)
	testing.expect_value(
		t,
		choose_card_reward(&run, run.card_reward.choice_count),
		Card_Reward_Result.Invalid,
	)
	testing.expect(t, run.player.deck == deck_before)
	testing.expect(t, run.card_reward == reward_before)
	testing.expect_value(t, run.reward_random_state, rng_before)
	testing.expect_value(t, run.phase, phase_before)
	testing.expect(t, validate_card_reward_state(&run))
	testing.expect_value(t, choose_card_reward(nil, 0), Card_Reward_Result.Invalid)
}

@(test)
test_skipping_card_reward_does_not_change_the_deck :: proc(t: ^testing.T) {
	run, ok := create_run(REWARD_TEST_PLAYER_STATS, REWARD_TEST_RUN_CONFIG, 0x5A1F)
	testing.expect(t, ok)
	defer destroy_run(&run)
	testing.expect_value(t, finish_room(&run, .Complete), Run_Transition.Reward)

	deck_before := run.player.deck
	rng_before := run.reward_random_state
	testing.expect_value(t, skip_card_reward(&run), Card_Reward_Result.Skipped)
	testing.expect(t, run.player.deck == deck_before)
	testing.expect_value(t, run.reward_random_state, rng_before)
	testing.expect_value(t, run.phase, Run_Phase.Choose_Path)
	testing.expect_value(t, run.card_reward.choice_count, 0)
	testing.expect(t, validate_card_reward_state(&run))
	testing.expect_value(t, skip_card_reward(&run), Card_Reward_Result.Invalid)
	testing.expect(t, run.player.deck == deck_before)
}

@(test)
test_full_deck_keeps_reward_open_until_it_is_skipped :: proc(t: ^testing.T) {
	run, ok := create_run(REWARD_TEST_PLAYER_STATS, REWARD_TEST_RUN_CONFIG, 0xF011)
	testing.expect(t, ok)
	defer destroy_run(&run)

	for run.player.deck.owned_count < MAX_OWNED_CARDS {
		_, added := add_owned_card(&run.player.deck, .Strike)
		testing.expect(t, added)
	}
	testing.expect(t, validate_deck_state(&run.player.deck))
	testing.expect_value(t, finish_room(&run, .Complete), Run_Transition.Reward)
	testing.expect(t, !card_reward_can_be_added(&run))

	deck_before := run.player.deck
	reward_before := run.card_reward
	rng_before := run.reward_random_state
	testing.expect_value(t, choose_card_reward(&run, 0), Card_Reward_Result.Deck_Full)
	testing.expect_value(t, run.phase, Run_Phase.Reward)
	testing.expect(t, run.player.deck == deck_before)
	testing.expect(t, run.card_reward == reward_before)
	testing.expect_value(t, run.reward_random_state, rng_before)
	testing.expect(t, validate_card_reward_state(&run))

	testing.expect_value(t, skip_card_reward(&run), Card_Reward_Result.Skipped)
	testing.expect_value(t, run.phase, Run_Phase.Choose_Path)
	testing.expect(t, run.player.deck == deck_before)
	testing.expect(t, validate_card_reward_state(&run))
}

@(test)
test_defeat_and_final_boss_do_not_open_card_rewards :: proc(t: ^testing.T) {
	defeated, defeated_ok := create_run(REWARD_TEST_PLAYER_STATS, REWARD_TEST_RUN_CONFIG, 0xDEF)
	testing.expect(t, defeated_ok)
	defer destroy_run(&defeated)
	defeat_rng_before := defeated.reward_random_state
	testing.expect_value(t, finish_room(&defeated, .Defeat), Run_Transition.Defeat)
	testing.expect_value(t, defeated.phase, Run_Phase.Defeat)
	testing.expect_value(t, defeated.card_reward.choice_count, 0)
	testing.expect_value(t, defeated.reward_random_state, defeat_rng_before)
	testing.expect_value(t, len(available_card_rewards(&defeated)), 0)
	testing.expect(t, validate_card_reward_state(&defeated))

	victorious, victorious_ok := create_run(REWARD_TEST_PLAYER_STATS, REWARD_TEST_RUN_CONFIG, 0xB055)
	testing.expect(t, victorious_ok)
	defer destroy_run(&victorious)
	for {
		node, found := current_run_node(&victorious)
		testing.expect(t, found)
		if !found || node.outgoing_count == 0 {
			break
		}
		testing.expect_value(t, finish_room(&victorious, .Complete), Run_Transition.Reward)
		testing.expect_value(t, skip_card_reward(&victorious), Card_Reward_Result.Skipped)
		choices := available_nodes(&victorious)
		testing.expect(t, len(choices) > 0)
		if len(choices) == 0 {
			break
		}
		testing.expect(t, choose_node(&victorious, choices[0]))
	}

	boss, boss_found := current_run_node(&victorious)
	testing.expect(t, boss_found)
	testing.expect(t, boss_found && boss.kind == .Boss)
	testing.expect(t, boss_found && boss.outgoing_count == 0)
	boss_reward_rng_before := victorious.reward_random_state
	owned_before := victorious.player.deck.owned_count
	testing.expect_value(t, finish_room(&victorious, .Complete), Run_Transition.Victory)
	testing.expect_value(t, victorious.phase, Run_Phase.Victory)
	testing.expect_value(t, victorious.card_reward.choice_count, 0)
	testing.expect_value(t, victorious.reward_random_state, boss_reward_rng_before)
	testing.expect_value(t, victorious.player.deck.owned_count, owned_before)
	testing.expect_value(t, len(available_card_rewards(&victorious)), 0)
	testing.expect(t, validate_card_reward_state(&victorious))
}
