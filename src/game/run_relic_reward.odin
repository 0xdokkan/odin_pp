package game

RUN_RELIC_REWARD_SALT :: u64(0xFA356E8185CF279D)

Run_Relic_Origin :: enum { None, Starter, Elite, Treasure }

Run_Relic_Reward :: struct {
	offers: Relic_Offers,
	source_node: Node_Id,
	origin: Run_Relic_Origin,
}

make_run_relic_reward :: proc(run: ^Run_State, origin: Run_Relic_Origin) -> Run_Relic_Reward {
	if run == nil || !run.relic_rewards_enabled || origin < .Starter || origin > .Treasure { return {} }
	seed := mix_room_seed(run.seed~RUN_RELIC_REWARD_SALT~u64(run.current_node)*ROOM_SEED_ID_MIX~u64(origin))
	offers := make_relic_offers(&run.player, seed)
	if offers.count == 0 { return {} }
	return {offers = offers, source_node = run.current_node, origin = origin}
}

run_has_relic_choice :: proc(run: ^Run_State) -> bool {
	return run != nil && run.relic_reward.origin != .None
}

@(private)
validate_run_relic_reward :: proc(run: ^Run_State) -> bool {
	if run == nil { return false }
	reward := run.relic_reward
	if reward.origin < .None || reward.origin > .Treasure { return false }
	if reward.origin == .None { return reward == Run_Relic_Reward{} }
	if !run.relic_rewards_enabled || reward.source_node != run.current_node { return false }
	node, found := current_run_node(run)
	if !found { return false }
	switch reward.origin {
	case .None: return false
	case .Starter:
		if run.current_node != Node_Id(0) || run.phase != .In_Room || node.cleared { return false }
	case .Elite:
		if node.kind != .Elite || run.phase != .Reward || !node.cleared { return false }
	case .Treasure:
		if node.kind != .Treasure || run.phase != .Treasure || !run.treasure.resolved ||
		   run.treasure.outcome != .Treasure_Claimed { return false }
	}
	return reward == make_run_relic_reward(run, reward.origin)
}

choose_run_relic :: proc(run: ^Run_State, choice: int) -> bool {
	if !run_has_relic_choice(run) || !validate_run_state(run) ||
	   choice < 0 || choice >= run.relic_reward.offers.count { return false }
	staged := run^
	if !acquire_relic(&staged.player, staged.relic_reward.offers.choices[choice]) { return false }
	staged.relic_reward = {}
	if !validate_run_state(&staged) { return false }
	run.player.relics = staged.player.relics
	run.relic_reward = {}
	return true
}

skip_run_relic :: proc(run: ^Run_State) -> bool {
	if !run_has_relic_choice(run) || !validate_run_state(run) { return false }
	run.relic_reward = {}
	return true
}
