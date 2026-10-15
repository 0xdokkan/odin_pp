package game

ROUTE_EVENT_KIND_SEED_SALT :: u64(0xC6BC279692B5CC83)
ROUTE_EVENT_CARD_SEED_SALT :: u64(0x4CF5AD432745937F)

Route_Event_Kind :: enum {
	Blood_Offering,
	Healing_Spring,
	Forgotten_Armory,
	Count,
}

Route_Event_Choice :: enum {
	Primary,
	Secondary,
}

Special_Node_Outcome :: enum {
	None,
	Left,
	Recovered,
	Upgraded,
	Event_Primary,
	Event_Secondary,
	Treasure_Claimed,
}

Special_Node_Result :: enum {
	Invalid,
	Recovered,
	Upgraded,
	Event_Resolved,
	Treasure_Claimed,
	Left,
	Continued,
	Already_Resolved,
	Card_Not_Found,
	Maximum_Upgrade,
	Upgrade_Unavailable,
	Deck_Full,
	Instance_Id_Exhausted,
	Not_Enough_Health,
	Overflow,
}

Rest_Node_State :: struct {
	source_node:    Node_Id,
	heal_amount:    i32,
	resolved:       bool,
	outcome:        Special_Node_Outcome,
	applied_amount: i32,
	target_card_id: u32,
}

Route_Event_State :: struct {
	source_node:     Node_Id,
	kind:            Route_Event_Kind,
	has_offered_card: bool,
	offered_card:    Card_Id,
	health_cost:     i32,
	heal_amount:     i32,
	primary_gold:    i32,
	secondary_gold:  i32,
	resolved:        bool,
	outcome:         Special_Node_Outcome,
	applied_amount:  i32,
	added_card_id:   u32,
}

Treasure_Node_State :: struct {
	source_node:    Node_Id,
	gold_amount:    i32,
	resolved:       bool,
	outcome:        Special_Node_Outcome,
	applied_amount: i32,
}

route_event_kind_name :: proc(kind: Route_Event_Kind) -> string {
	switch kind {
	case .Blood_Offering:
		return "Blood Offering"
	case .Healing_Spring:
		return "Healing Spring"
	case .Forgotten_Armory:
		return "Forgotten Armory"
	case .Count:
	}
	return "Unknown"
}

special_node_outcome_name :: proc(outcome: Special_Node_Outcome) -> string {
	switch outcome {
	case .None:
		return "Unresolved"
	case .Left:
		return "Left untouched"
	case .Recovered:
		return "Recovered"
	case .Upgraded:
		return "Card upgraded"
	case .Event_Primary:
		return "First choice resolved"
	case .Event_Secondary:
		return "Second choice resolved"
	case .Treasure_Claimed:
		return "Treasure claimed"
	}
	return "Unknown"
}

valid_special_source_node :: proc(node: ^Run_Node, expected_kind: Node_Kind) -> bool {
	return node != nil && node.kind == expected_kind && int(node.id) > 0 && node.depth > 0 &&
	       node.room_seed != 0 && node.outgoing_count > 0
}

percent_of_max_health :: proc(max_health, percent: i32) -> (i32, bool) {
	if max_health <= 0 || percent <= 0 || percent > 100 {
		return 0, false
	}
	amount := (i64(max_health)*i64(percent))/100
	amount = max(i64(1), amount)
	if amount > i64(max(i32)) {
		return 0, false
	}
	return i32(amount), true
}

safe_add_nonnegative_i32 :: proc(value, amount: i32) -> (i32, bool) {
	if value < 0 || amount < 0 {
		return 0, false
	}
	result := i64(value)+i64(amount)
	if result > i64(max(i32)) {
		return 0, false
	}
	return i32(result), true
}

safe_heal :: proc(health, max_health, amount: i32) -> (new_health, applied: i32, ok: bool) {
	if health < 0 || max_health <= 0 || health > max_health || amount < 0 {
		return 0, 0, false
	}
	result := min(i64(max_health), i64(health)+i64(amount))
	return i32(result), i32(result)-health, true
}

build_rest_node_state :: proc(player: ^Player, node: ^Run_Node) -> (Rest_Node_State, bool) {
	if player == nil || !valid_special_source_node(node, .Rest) {
		return {}, false
	}
	heal_amount, ok := percent_of_max_health(player.stats.max_health, 30)
	if !ok {
		return {}, false
	}
	return {source_node = node.id, heal_amount = heal_amount}, true
}

// `excluded`: the cards the Armory leaves out (card_offer_exclusions of the
// player's deck as the event opens).
build_route_event_state :: proc(player: ^Player, node: ^Run_Node, excluded: Card_Offer_Exclusions = {}) -> (result: Route_Event_State, ok: bool) {
	if player == nil || !valid_special_source_node(node, .Event) {
		return {}, false
	}
	result.source_node = node.id
	result.kind = Route_Event_Kind(
		mix_room_seed(node.room_seed~ROUTE_EVENT_KIND_SEED_SALT)%u64(Route_Event_Kind.Count),
	)
	depth := min(node.depth, MAX_CARD_OFFER_DEPTH)
	switch result.kind {
	case .Blood_Offering:
		result.health_cost, ok = percent_of_max_health(player.stats.max_health, 20)
		if !ok {
			return {}, false
		}
		result.primary_gold = i32(8+depth*2)
	case .Healing_Spring:
		result.heal_amount, ok = percent_of_max_health(player.stats.max_health, 25)
		if !ok {
			return {}, false
		}
		result.secondary_gold = i32(4+depth)
	case .Forgotten_Armory:
		random_state := normalized_card_reward_seed(node.room_seed~ROUTE_EVENT_CARD_SEED_SALT)
		choice: [1]Card_Id
		if !generate_weighted_card_choices(&random_state, node, choice[:], &player.m8_profile, player.tactical.config.enabled, excluded) {
			return {}, false
		}
		result.has_offered_card = true
		result.offered_card = choice[0]
		result.secondary_gold = i32(5+depth)
	case .Count:
		return {}, false
	}
	return result, true
}

build_treasure_node_state :: proc(node: ^Run_Node) -> (Treasure_Node_State, bool) {
	if !valid_special_source_node(node, .Treasure) {
		return {}, false
	}
	depth := min(node.depth, MAX_CARD_OFFER_DEPTH)
	return {source_node = node.id, gold_amount = i32(7+depth*2)}, true
}

rest_node_state_is_valid :: proc(run: ^Run_State) -> bool {
	if run == nil || run.phase != .Rest || (run.route_event != Route_Event_State{}) ||
	   (run.treasure != Treasure_Node_State{}) || run.player.deck.combat_active {
		return false
	}
	node, found := current_run_node(run)
	if !found || !node.entered || node.cleared || run.rest.source_node != node.id {
		return false
	}
	expected, expected_ok := build_rest_node_state(&run.player, node)
	if !expected_ok || run.rest.heal_amount != expected.heal_amount {
		return false
	}
	if !run.rest.resolved {
		return run.rest.outcome == .None && run.rest.applied_amount == 0 &&
		       run.rest.target_card_id == 0
	}
	switch run.rest.outcome {
	case .Left:
		return run.rest.applied_amount == 0 && run.rest.target_card_id == 0
	case .Recovered:
		return run.rest.applied_amount >= 0 && run.rest.applied_amount <= run.rest.heal_amount &&
		       run.rest.target_card_id == 0
	case .Upgraded:
		card_index, card_found := owned_card_index_by_id(&run.player.deck, run.rest.target_card_id)
		return run.rest.applied_amount == 0 && card_found &&
		       run.player.deck.owned[card_index].upgrade_level > 0
	case .None, .Event_Primary, .Event_Secondary, .Treasure_Claimed:
	}
	return false
}

route_event_state_is_valid :: proc(run: ^Run_State) -> bool {
	if run == nil || run.phase != .Event || (run.rest != Rest_Node_State{}) ||
	   (run.treasure != Treasure_Node_State{}) || run.player.deck.combat_active {
		return false
	}
	node, found := current_run_node(run)
	if !found || !node.entered || node.cleared || run.route_event.source_node != node.id {
		return false
	}
	// The offer as the event opened: the card the Armory added since (a Canna
	// da Pesca) was not in the deck then.
	expected, expected_ok := build_route_event_state(&run.player, node, card_offer_exclusions(&run.player.deck, run.route_event.added_card_id))
	if !expected_ok || run.route_event.kind != expected.kind ||
	   run.route_event.has_offered_card != expected.has_offered_card ||
	   run.route_event.offered_card != expected.offered_card ||
	   run.route_event.health_cost != expected.health_cost ||
	   run.route_event.heal_amount != expected.heal_amount ||
	   run.route_event.primary_gold != expected.primary_gold ||
	   run.route_event.secondary_gold != expected.secondary_gold {
		return false
	}
	if !run.route_event.resolved {
		return run.route_event.outcome == .None && run.route_event.applied_amount == 0 &&
		       run.route_event.added_card_id == 0
	}
	switch run.route_event.outcome {
	case .Left:
		return run.route_event.applied_amount == 0 && run.route_event.added_card_id == 0
	case .Event_Primary:
		switch run.route_event.kind {
		case .Blood_Offering:
			return run.route_event.applied_amount == run.route_event.primary_gold &&
			       run.route_event.added_card_id == 0
		case .Healing_Spring:
			return run.route_event.applied_amount >= 0 &&
			       run.route_event.applied_amount <= run.route_event.heal_amount &&
			       run.route_event.added_card_id == 0
		case .Forgotten_Armory:
			card_index, card_found := owned_card_index_by_id(
				&run.player.deck,
				run.route_event.added_card_id,
			)
			return run.route_event.applied_amount == 0 && card_found &&
			       run.player.deck.owned[card_index].definition_id == run.route_event.offered_card
		case .Count:
		}
	case .Event_Secondary:
		return run.route_event.applied_amount == run.route_event.secondary_gold &&
		       run.route_event.added_card_id == 0
	case .None, .Recovered, .Upgraded, .Treasure_Claimed:
	}
	return false
}

treasure_node_state_is_valid :: proc(run: ^Run_State) -> bool {
	if run == nil || run.phase != .Treasure || (run.rest != Rest_Node_State{}) ||
	   (run.route_event != Route_Event_State{}) || run.player.deck.combat_active {
		return false
	}
	node, found := current_run_node(run)
	if !found || !node.entered || node.cleared || run.treasure.source_node != node.id {
		return false
	}
	expected, expected_ok := build_treasure_node_state(node)
	if !expected_ok || run.treasure.gold_amount != expected.gold_amount {
		return false
	}
	if !run.treasure.resolved {
		return run.treasure.outcome == .None && run.treasure.applied_amount == 0
	}
	switch run.treasure.outcome {
	case .Left:
		return run.treasure.applied_amount == 0
	case .Treasure_Claimed:
		return run.treasure.applied_amount == run.treasure.gold_amount
	case .None, .Recovered, .Upgraded, .Event_Primary, .Event_Secondary:
	}
	return false
}

validate_special_node_state :: proc(run: ^Run_State) -> bool {
	if run == nil {
		return false
	}
	switch run.phase {
	case .Rest:
		return rest_node_state_is_valid(run)
	case .Event:
		return route_event_state_is_valid(run)
	case .Treasure:
		return treasure_node_state_is_valid(run)
	case .In_Room, .Reward, .Shop, .Choose_Path, .Victory, .Defeat:
		return (run.rest == Rest_Node_State{}) && (run.route_event == Route_Event_State{}) &&
		       (run.treasure == Treasure_Node_State{})
	}
	return false
}

// Availability queries are read-only and deliberately local to the action.
// Commands retain full run validation before checking these rules, then stage
// and validate the result before committing it. HUD polling need not copy or
// validate the entire run merely to display a button.
special_node_is_resolved :: proc(run: ^Run_State) -> bool {
	if run == nil { return false }
	switch run.phase {
	case .Rest: return run.rest.resolved
	case .Event: return run.route_event.resolved
	case .Treasure: return run.treasure.resolved
	case .In_Room, .Reward, .Shop, .Choose_Path, .Victory, .Defeat:
	}
	return false
}

@(private)
rest_recovery_check :: proc(run: ^Run_State) -> (Special_Node_Result, i32, i32) {
	if run == nil || run.phase != .Rest { return .Invalid, 0, 0 }
	if run.rest.resolved { return .Already_Resolved, 0, 0 }
	health, applied, ok := safe_heal(run.player.health, run.player.stats.max_health, run.rest.heal_amount)
	if !ok { return .Invalid, 0, 0 }
	return .Recovered, health, applied
}

@(private)
rest_upgrade_check :: proc(run: ^Run_State, card_id: u32) -> Special_Node_Result {
	if run == nil || run.phase != .Rest { return .Invalid }
	if run.rest.resolved { return .Already_Resolved }
	index, found := owned_card_index_by_id(&run.player.deck, card_id)
	if !found { return .Card_Not_Found }
	card := run.player.deck.owned[index]
	if card.upgrade_level >= card_max_upgrade_level(card.definition_id) { return .Maximum_Upgrade }
	if !card_can_upgrade(card) { return .Upgrade_Unavailable }
	return .Upgraded
}

@(private)
route_event_choice_check :: proc(run: ^Run_State, choice: Route_Event_Choice) -> (
	result: Special_Node_Result, health, gold, applied: i32,
) {
	if run == nil || run.phase != .Event || int(choice) < 0 || int(choice) > int(Route_Event_Choice.Secondary) {
		return .Invalid, 0, 0, 0
	}
	if run.route_event.resolved { return .Already_Resolved, 0, 0, 0 }
	health, gold = run.player.health, run.player.gold
	switch run.route_event.kind {
	case .Blood_Offering:
		if choice == .Primary {
			if health <= run.route_event.health_cost { return .Not_Enough_Health, 0, 0, 0 }
			ok: bool
			gold, ok = safe_add_nonnegative_i32(gold, run.route_event.primary_gold)
			if !ok { return .Overflow, 0, 0, 0 }
			health -= run.route_event.health_cost
			applied = run.route_event.primary_gold
		}
	case .Healing_Spring, .Forgotten_Armory:
		if choice == .Secondary {
			ok: bool
			gold, ok = safe_add_nonnegative_i32(gold, run.route_event.secondary_gold)
			if !ok { return .Overflow, 0, 0, 0 }
			applied = run.route_event.secondary_gold
		} else if run.route_event.kind == .Healing_Spring {
			ok: bool
			health, applied, ok = safe_heal(health, run.player.stats.max_health, run.route_event.heal_amount)
			if !ok { return .Invalid, 0, 0, 0 }
		} else {
			if run.player.deck.owned_count >= MAX_OWNED_CARDS { return .Deck_Full, 0, 0, 0 }
			if run.player.deck.next_card_id >= max(u32) { return .Instance_Id_Exhausted, 0, 0, 0 }
		}
	case .Count:
		return .Invalid, 0, 0, 0
	}
	return .Event_Resolved, health, gold, applied
}

@(private)
treasure_claim_check :: proc(run: ^Run_State) -> (Special_Node_Result, i32) {
	if run == nil || run.phase != .Treasure { return .Invalid, 0 }
	if run.treasure.resolved { return .Already_Resolved, 0 }
	gold, ok := safe_add_nonnegative_i32(run.player.gold, run.treasure.gold_amount)
	if !ok { return .Overflow, 0 }
	return .Treasure_Claimed, gold
}

special_node_primary_is_enabled :: proc(run: ^Run_State) -> bool {
	if run == nil { return false }
	switch run.phase {
	case .Rest:
		result, _, _ := rest_recovery_check(run)
		return result == .Recovered
	case .Event:
		result, _, _, _ := route_event_choice_check(run, .Primary)
		return result == .Event_Resolved
	case .Treasure:
		result, _ := treasure_claim_check(run)
		return result == .Treasure_Claimed
	case .In_Room, .Reward, .Shop, .Choose_Path, .Victory, .Defeat:
	}
	return false
}

special_node_secondary_is_enabled :: proc(run: ^Run_State, selected_card_id: u32) -> bool {
	if run == nil { return false }
	switch run.phase {
	case .Rest:
		return rest_upgrade_check(run, selected_card_id) == .Upgraded
	case .Event:
		result, _, _, _ := route_event_choice_check(run, .Secondary)
		return result == .Event_Resolved
	case .Treasure, .In_Room, .Reward, .Shop, .Choose_Path, .Victory, .Defeat:
	}
	return false
}

use_rest_recovery :: proc(run: ^Run_State) -> Special_Node_Result {
	if run == nil || run.phase != .Rest || !validate_run_state(run) { return .Invalid }
	result, health, applied := rest_recovery_check(run)
	if result != .Recovered { return result }
	staged := run^
	staged.player.health = health
	staged.rest.resolved = true
	staged.rest.outcome = .Recovered
	staged.rest.applied_amount = applied
	if !validate_run_state(&staged) { return .Invalid }
	run.player.health = staged.player.health
	run.rest = staged.rest
	return .Recovered
}

use_rest_upgrade :: proc(run: ^Run_State, card_id: u32) -> Special_Node_Result {
	if run == nil || run.phase != .Rest || !validate_run_state(run) { return .Invalid }
	result := rest_upgrade_check(run, card_id)
	if result != .Upgraded { return result }
	staged_deck := run.player.deck
	if upgrade_owned_card(&staged_deck, card_id) != .Upgraded { return .Invalid }
	staged := run^
	staged.player.deck = staged_deck
	staged.rest.resolved = true
	staged.rest.outcome = .Upgraded
	staged.rest.target_card_id = card_id
	if !validate_run_state(&staged) { return .Invalid }
	run.player.deck = staged.player.deck
	run.rest = staged.rest
	return .Upgraded
}

resolve_route_event :: proc(run: ^Run_State, choice: Route_Event_Choice) -> Special_Node_Result {
	if run == nil || run.phase != .Event || !validate_run_state(run) { return .Invalid }
	result, health, gold, applied := route_event_choice_check(run, choice)
	if result != .Event_Resolved { return result }
	staged := run^
	staged.player.health, staged.player.gold = health, gold
	staged.route_event.resolved = true
	staged.route_event.outcome = .Event_Primary if choice == .Primary else .Event_Secondary
	staged.route_event.applied_amount = applied
	if run.route_event.kind == .Forgotten_Armory && choice == .Primary {
		instance, added := add_owned_card(&staged.player.deck, run.route_event.offered_card)
		if !added { return .Invalid }
		staged.route_event.added_card_id = instance.id
	}
	if !validate_run_state(&staged) { return .Invalid }
	run.player = staged.player
	run.route_event = staged.route_event
	return .Event_Resolved
}

claim_treasure :: proc(run: ^Run_State) -> Special_Node_Result {
	if run == nil || run.phase != .Treasure || !validate_run_state(run) { return .Invalid }
	result, gold := treasure_claim_check(run)
	if result != .Treasure_Claimed { return result }
	staged := run^
	staged.player.gold = gold
	staged.treasure.resolved = true
	staged.treasure.outcome = .Treasure_Claimed
	staged.treasure.applied_amount = run.treasure.gold_amount
	staged.relic_reward = make_run_relic_reward(&staged, .Treasure)
	if !validate_run_state(&staged) { return .Invalid }
	run.player.gold = staged.player.gold
	run.treasure = staged.treasure
	run.relic_reward = staged.relic_reward
	return .Treasure_Claimed
}

leave_special_node :: proc(run: ^Run_State) -> Special_Node_Result {
	if run == nil || !validate_run_state(run) {
		return .Invalid
	}
	staged := run^
	switch run.phase {
	case .Rest:
		if run.rest.resolved {
			return .Already_Resolved
		}
		staged.rest.resolved = true
		staged.rest.outcome = .Left
	case .Event:
		if run.route_event.resolved {
			return .Already_Resolved
		}
		staged.route_event.resolved = true
		staged.route_event.outcome = .Left
	case .Treasure:
		if run.treasure.resolved {
			return .Already_Resolved
		}
		staged.treasure.resolved = true
		staged.treasure.outcome = .Left
	case .In_Room, .Reward, .Shop, .Choose_Path, .Victory, .Defeat:
		return .Invalid
	}
	if !validate_run_state(&staged) {
		return .Invalid
	}
	run.rest = staged.rest
	run.route_event = staged.route_event
	run.treasure = staged.treasure
	return .Left
}

special_node_can_continue :: proc(run: ^Run_State) -> bool {
	if run == nil || run_has_relic_choice(run) || !validate_run_state(run) {
		return false
	}
	switch run.phase {
	case .Rest:
		return run.rest.resolved
	case .Event:
		return run.route_event.resolved
	case .Treasure:
		return run.treasure.resolved
	case .In_Room, .Reward, .Shop, .Choose_Path, .Victory, .Defeat:
	}
	return false
}

continue_special_node :: proc(run: ^Run_State) -> Special_Node_Result {
	if !special_node_can_continue(run) {
		return .Invalid
	}
	node, found := current_run_node(run)
	if !found || node.cleared {
		return .Invalid
	}
	rest_before := run.rest
	event_before := run.route_event
	treasure_before := run.treasure
	cleared_count_before := run.cleared_count
	phase_before := run.phase

	node.cleared = true
	run.cleared_count += 1
	run.rest = {}
	run.route_event = {}
	run.treasure = {}
	run.phase = .Choose_Path
	if !validate_run_state(run) {
		node.cleared = false
		run.rest = rest_before
		run.route_event = event_before
		run.treasure = treasure_before
		run.cleared_count = cleared_count_before
		run.phase = phase_before
		return .Invalid
	}
	return .Continued
}
