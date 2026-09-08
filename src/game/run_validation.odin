package game

validate_run_state :: proc(run: ^Run_State) -> bool {
	if run == nil || run.reward_random_state == 0 || run.shop_random_state == 0 ||
	   run.last_room_family < .Scattered || run.last_room_family > .Asymmetric ||
	   run.seed != run.route_map.seed || !validate_run_map(&run.route_map) ||
	   run.player.stats.max_health <= 0 || run.player.health < 0 ||
	   run.player.health > run.player.stats.max_health || run.player.gold < 0 ||
	   !validate_deck_state(&run.player.deck) || !validate_relic_state(&run.player.relics) ||
	   !validate_dice_state(&run.player.dice) || !validate_card_reward_state(run) ||
	   !validate_shop_state(run) || !validate_special_node_state(run) || !validate_run_relic_reward(run) {
		return false
	}
	node, found := current_run_node(run)
	if !found || node.id != run.current_node || !node_kind_is_valid(node.kind) || !node.entered {
		return false
	}

	cleared_count := 0
	for &candidate in run.route_map.nodes {
		if candidate.cleared {
			if !candidate.entered {
				return false
			}
			cleared_count += 1
		}
	}
	if cleared_count != run.cleared_count {
		return false
	}

	switch run.phase {
	case .In_Room:
		return node_kind_has_room(node.kind) && !node.cleared
	case .Reward:
		return (node.kind == .Combat || node.kind == .Elite) && node.cleared &&
		       node.outgoing_count > 0
	case .Shop:
		return node.kind == .Shop && node.outgoing_count > 0
	case .Rest:
		return node.kind == .Rest && !node.cleared && node.outgoing_count > 0
	case .Event:
		return node.kind == .Event && !node.cleared && node.outgoing_count > 0
	case .Treasure:
		return node.kind == .Treasure && !node.cleared && node.outgoing_count > 0
	case .Choose_Path:
		return node.cleared && node.outgoing_count > 0 && !run.player.deck.combat_active
	case .Victory:
		return node.kind == .Boss && node.cleared && node.outgoing_count == 0 &&
		       !run.player.deck.combat_active
	case .Defeat:
		return node_kind_has_room(node.kind) && !node.cleared && !run.player.deck.combat_active
	}
	return false
}
