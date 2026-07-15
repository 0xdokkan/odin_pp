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

card_reward_next_random :: proc(run: ^Run_State) -> u64 {
	assert(run != nil && run.reward_random_state != 0)
	x := run.reward_random_state
	x ~= x >> 12
	x ~= x << 25
	x ~= x >> 27
	run.reward_random_state = x
	return x*0x2545F4914F6CDD1D
}

validate_card_reward_state :: proc(run: ^Run_State) -> bool {
	if run == nil || run.reward_random_state == 0 || !validate_deck_state(&run.player.deck) {
		return false
	}
	if run.phase != .Reward {
		return run.card_reward == Card_Reward_State{}
	}
	if run.card_reward.choice_count != CARD_REWARD_CHOICE_COUNT ||
	   run.card_reward.source_node != run.current_node || run.player.deck.combat_active {
		return false
	}
	node, node_found := current_run_node(run)
	if !node_found || !node.cleared || node.outgoing_count <= 0 {
		return false
	}
	for index in 0..<run.card_reward.choice_count {
		definition, found := card_definition_by_id(run.card_reward.choices[index])
		if !found || !validate_card_definition(&definition) {
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
	   int(Card_Id.Count) < CARD_REWARD_CHOICE_COUNT {
		return false
	}
	node, node_found := current_run_node(run)
	if !node_found || !node.cleared || node.outgoing_count <= 0 {
		return false
	}

	pool: [int(Card_Id.Count)]Card_Id
	for index in 0..<len(pool) {
		pool[index] = Card_Id(index)
	}
	for index in 0..<CARD_REWARD_CHOICE_COUNT {
		remaining := len(pool)-index
		swap_index := index+int(card_reward_next_random(run)%u64(remaining))
		pool[index], pool[swap_index] = pool[swap_index], pool[index]
		run.card_reward.choices[index] = pool[index]
	}
	run.card_reward.choice_count = CARD_REWARD_CHOICE_COUNT
	run.card_reward.source_node = run.current_node
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
	       run.player.deck.owned_count < MAX_OWNED_CARDS
}

finish_card_reward :: proc(run: ^Run_State) {
	assert(run != nil && run.phase == .Reward)
	run.card_reward = {}
	run.phase = .Choose_Path
}

choose_card_reward :: proc(run: ^Run_State, choice_index: int) -> Card_Reward_Result {
	if run == nil || run.phase != .Reward || !validate_card_reward_state(run) ||
	   choice_index < 0 || choice_index >= run.card_reward.choice_count {
		return .Invalid
	}
	if run.player.deck.owned_count >= MAX_OWNED_CARDS {
		return .Deck_Full
	}
	_, added := add_owned_card(&run.player.deck, run.card_reward.choices[choice_index])
	if !added {
		return .Invalid
	}
	finish_card_reward(run)
	assert(validate_card_reward_state(run))
	return .Added
}

skip_card_reward :: proc(run: ^Run_State) -> Card_Reward_Result {
	if run == nil || run.phase != .Reward || !validate_card_reward_state(run) {
		return .Invalid
	}
	finish_card_reward(run)
	assert(validate_card_reward_state(run))
	return .Skipped
}
