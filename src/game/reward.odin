package game

CARD_REWARD_CHOICE_COUNT :: 3
CARD_REWARD_SEED_SALT    :: u64(0xA24BAED4963EE407)
DEFAULT_CARD_REWARD_SEED :: u64(0x9FB21C651E98DF25)

Card_Reward_State :: struct {
	choices:      [CARD_REWARD_CHOICE_COUNT]Card_Id,
	choice_count: int,
	source_node:  Node_Id,
}

Card_Reward_Result :: enum {
	Invalid,
	Added,
	Skipped,
	Deck_Full,
}

normalized_card_reward_seed :: proc(seed: u64) -> u64 {
	if seed == 0 {
		return DEFAULT_CARD_REWARD_SEED
	}
	return seed
}

validate_card_reward_state :: proc(run: ^Run_State) -> bool {
	if run == nil || run.reward_random_state == 0 || run.shop_random_state == 0 ||
	   run.player.gold < 0 || !validate_deck_state(&run.player.deck) {
		return false
	}
	if run.phase != .Reward {
		return run.card_reward == Card_Reward_State{}
	}
	if run.card_reward.choice_count != CARD_REWARD_CHOICE_COUNT ||
	   run.card_reward.source_node != run.current_node || run.player.deck.combat_active ||
	   (run.shop != Shop_State{}) {
		return false
	}
	node, node_found := current_run_node(run)
	if !node_found || (node.kind != .Combat && node.kind != .Elite) ||
	   !node.cleared || node.outgoing_count <= 0 {
		return false
	}
	for index in 0..<run.card_reward.choice_count {
		definition, found := card_definition_by_id(run.card_reward.choices[index])
		if !found || !validate_card_definition(&definition) || definition.temporary_only {
			return false
		}
		for previous in 0..<index {
			if run.card_reward.choices[previous] == run.card_reward.choices[index] {
				return false
			}
		}
	}
	return true
}

begin_card_reward :: proc(run: ^Run_State) -> bool {
	if run == nil || run.phase != .In_Room || run.card_reward.choice_count != 0 ||
	   run.reward_random_state == 0 || run.player.deck.combat_active ||
	   (run.shop != Shop_State{}) || int(Card_Id.Count) < CARD_REWARD_CHOICE_COUNT {
		return false
	}
	node, node_found := current_run_node(run)
	if !node_found || (node.kind != .Combat && node.kind != .Elite) ||
	   !node.cleared || node.outgoing_count <= 0 {
		return false
	}

	staged_random_state := run.reward_random_state
	staged_reward := Card_Reward_State{source_node = run.current_node}
	if !generate_weighted_card_choices(
		&staged_random_state,
		node,
		staged_reward.choices[:CARD_REWARD_CHOICE_COUNT],
		&run.player.m8_profile,
		run.player.tactical.config.enabled,
		card_offer_exclusions(&run.player.deck),
	) {
		return false
	}
	staged_reward.choice_count = CARD_REWARD_CHOICE_COUNT
	run.reward_random_state = staged_random_state
	run.card_reward = staged_reward
	run.phase = .Reward
	assert(validate_card_reward_state(run))
	return true
}

available_card_rewards :: proc(run: ^Run_State) -> []Card_Id {
	if run == nil || run.phase != .Reward || !validate_card_reward_state(run) {
		return nil
	}
	return run.card_reward.choices[:run.card_reward.choice_count]
}

card_reward_can_be_added :: proc(run: ^Run_State) -> bool {
	return run != nil && run.phase == .Reward && validate_card_reward_state(run) &&
	       run.player.deck.owned_count < MAX_OWNED_CARDS &&
	       run.player.deck.next_card_id < max(u32)
}

finish_card_reward :: proc(run: ^Run_State) -> bool {
	if run == nil || run.phase != .Reward || run_has_relic_choice(run) || !validate_card_reward_state(run) {
		return false
	}
	staged := run^
	staged.card_reward = {}
	staged.phase = .Choose_Path
	if !validate_run_state(&staged) {
		return false
	}
	run.card_reward = staged.card_reward
	run.phase = staged.phase
	assert(validate_card_reward_state(run))
	assert(validate_run_state(run))
	return true
}

choose_card_reward :: proc(run: ^Run_State, choice_index: int) -> Card_Reward_Result {
	if run == nil || run.phase != .Reward || !validate_card_reward_state(run) ||
	   choice_index < 0 || choice_index >= run.card_reward.choice_count {
		return .Invalid
	}
	if run.player.deck.owned_count >= MAX_OWNED_CARDS {
		return .Deck_Full
	}
	staged_deck := run.player.deck
	_, added := add_owned_card(&staged_deck, run.card_reward.choices[choice_index])
	if !added {
		return .Invalid
	}
	staged_run := run^
	staged_run.player.deck = staged_deck
	if !finish_card_reward(&staged_run) {
		return .Invalid
	}
	run.player.deck = staged_run.player.deck
	run.card_reward = staged_run.card_reward
	run.phase = staged_run.phase
	assert(validate_card_reward_state(run))
	assert(validate_run_state(run))
	return .Added
}

skip_card_reward :: proc(run: ^Run_State) -> Card_Reward_Result {
	if run == nil || run.phase != .Reward || !validate_card_reward_state(run) {
		return .Invalid
	}
	if !finish_card_reward(run) {
		return .Invalid
	}
	assert(validate_card_reward_state(run))
	return .Skipped
}
