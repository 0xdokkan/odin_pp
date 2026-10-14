package game

SHOP_CARD_OFFER_COUNT :: 3
SHOP_SEED_SALT        :: u64(0xDB4F0B9175AE2165)
DEFAULT_SHOP_SEED     :: u64(0xE7037ED1A0B428DB)

Shop_Card_Offer :: struct {
	definition_id: Card_Id,
	price:         i32,
	sold:          bool,
}

Shop_State :: struct {
	offers:       [SHOP_CARD_OFFER_COUNT]Shop_Card_Offer,
	offer_count:  int,
	source_node:  Node_Id,
	upgrade_used: bool,
	removal_used: bool,
}

Shop_Result :: enum {
	Invalid,
	Opened,
	Left,
	Purchased,
	Upgraded,
	Removed,
	Already_Sold,
	Not_Enough_Gold,
	Deck_Full,
	Card_Not_Found,
	Maximum_Upgrade,
	Upgrade_Unavailable,
	Minimum_Deck_Size,
	Service_Used,
}

normalized_shop_seed :: proc(seed: u64) -> u64 {
	if seed == 0 {
		return DEFAULT_SHOP_SEED
	}
	return seed
}

shop_card_price :: proc(definition: Card_Definition, depth: int) -> (i32, bool) {
	validated_definition := definition
	if !validate_card_definition(&validated_definition) || definition.temporary_only || depth < 0 {
		return 0, false
	}
	price := i64(definition.shop_base_price)+i64(min(depth, MAX_CARD_OFFER_DEPTH)/3)
	if price <= 0 || price > i64(max(i32)) {
		return 0, false
	}
	return i32(price), true
}

shop_upgrade_price :: proc(run: ^Run_State, card_id: u32) -> (i32, bool) {
	if run == nil || card_id == 0 || run.player.deck.combat_active {
		return 0, false
	}
	card_index, found := owned_card_index_by_id(&run.player.deck, card_id)
	if !found {
		return 0, false
	}
	card := run.player.deck.owned[card_index]
	if !card_can_upgrade(card) {
		return 0, false
	}
	definition, definition_found := card_definition_by_id(card.definition_id)
	node, node_found := current_run_node(run)
	if !definition_found || !node_found || node.depth < 0 {
		return 0, false
	}
	price := i64(2)+i64(definition.rarity)+i64(card.upgrade_level)*2+
	         i64(min(node.depth, MAX_CARD_OFFER_DEPTH)/4)
	if price <= 0 || price > i64(max(i32)) {
		return 0, false
	}
	return i32(price), true
}

shop_removal_price :: proc(run: ^Run_State) -> (i32, bool) {
	if run == nil || run.player.deck.combat_active {
		return 0, false
	}
	node, found := current_run_node(run)
	if !found || node.depth < 0 {
		return 0, false
	}
	price := i64(4)+i64(min(node.depth, MAX_CARD_OFFER_DEPTH)/4)
	if price <= 0 || price > i64(max(i32)) {
		return 0, false
	}
	return i32(price), true
}

build_shop_state_for_node :: proc(
	run: ^Run_State,
	node: ^Run_Node,
	random_state: ^u64,
) -> (result: Shop_State, ok: bool) {
	if run == nil || random_state == nil || random_state^ == 0 || run.player.gold < 0 ||
	   run.player.deck.combat_active || !validate_deck_state(&run.player.deck) ||
	   !valid_special_source_node(node, .Shop) {
		return {}, false
	}

	choices: [SHOP_CARD_OFFER_COUNT]Card_Id
	if !generate_weighted_card_choices(random_state, node, choices[:], &run.player.m8_profile, run.player.tactical.config.enabled) {
		return {}, false
	}
	for choice, index in choices {
		definition, definition_found := card_definition_by_id(choice)
		if !definition_found {
			return {}, false
		}
		price, price_ok := shop_card_price(definition, node.depth)
		if !price_ok {
			return {}, false
		}
		result.offers[index] = {definition_id = choice, price = price}
	}
	result.offer_count = SHOP_CARD_OFFER_COUNT
	result.source_node = node.id
	return result, true
}

build_shop_state :: proc(run: ^Run_State, random_state: ^u64) -> (Shop_State, bool) {
	if run == nil {
		return {}, false
	}
	node, found := current_run_node(run)
	if !found {
		return {}, false
	}
	return build_shop_state_for_node(run, node, random_state)
}

shop_payload_is_valid :: proc(run: ^Run_State) -> bool {
	if run == nil || run.shop.offer_count != SHOP_CARD_OFFER_COUNT ||
	   run.shop.source_node != run.current_node || run.player.deck.combat_active {
		return false
	}
	node, node_found := current_run_node(run)
	if !node_found || node.kind != .Shop || !node.entered || node.outgoing_count <= 0 {
		return false
	}
	if (run.phase == .Choose_Path && !node.cleared) ||
	   (run.phase != .Shop && run.phase != .Choose_Path) {
		return false
	}
	for index in 0..<run.shop.offer_count {
		offer := run.shop.offers[index]
		definition, found := card_definition_by_id(offer.definition_id)
		if !found || !validate_card_definition(&definition) || definition.temporary_only {
			return false
		}
		expected_price, price_ok := shop_card_price(definition, node.depth)
		if !price_ok || offer.price != expected_price {
			return false
		}
		for previous in 0..<index {
			if run.shop.offers[previous].definition_id == offer.definition_id {
				return false
			}
		}
	}
	return true
}

validate_shop_state :: proc(run: ^Run_State) -> bool {
	if run == nil || run.shop_random_state == 0 || run.player.gold < 0 ||
	   !validate_deck_state(&run.player.deck) {
		return false
	}
	switch run.phase {
	case .Shop:
		return run.card_reward == Card_Reward_State{} && shop_payload_is_valid(run)
	case .Choose_Path:
		return run.card_reward == Card_Reward_State{} &&
		       ((run.shop == Shop_State{}) || shop_payload_is_valid(run))
	case .In_Room, .Reward, .Rest, .Event, .Treasure, .Victory, .Defeat:
		return run.shop == Shop_State{}
	}
	return false
}

available_shop_offers :: proc(run: ^Run_State) -> []Shop_Card_Offer {
	if run == nil || run.phase != .Shop || !validate_shop_state(run) {
		return nil
	}
	return run.shop.offers[:run.shop.offer_count]
}

open_shop :: proc(run: ^Run_State) -> Shop_Result {
	if run == nil || run.phase != .Choose_Path || (run.shop == Shop_State{}) ||
	   !validate_shop_state(run) {
		return .Invalid
	}
	run.phase = .Shop
	assert(validate_shop_state(run))
	return .Opened
}

leave_shop :: proc(run: ^Run_State) -> Shop_Result {
	if run == nil || run.phase != .Shop || !validate_shop_state(run) {
		return .Invalid
	}
	node, found := current_run_node(run)
	if !found || node.kind != .Shop {
		return .Invalid
	}
	was_cleared := node.cleared
	cleared_count_before := run.cleared_count
	if !node.cleared {
		node.cleared = true
		run.cleared_count += 1
	}
	run.phase = .Choose_Path
	if !validate_run_state(run) {
		node.cleared = was_cleared
		run.cleared_count = cleared_count_before
		run.phase = .Shop
		return .Invalid
	}
	return .Left
}

shop_offer_can_be_bought :: proc(run: ^Run_State, offer_index: int) -> bool {
	if run == nil || run.phase != .Shop || !validate_shop_state(run) ||
	   offer_index < 0 || offer_index >= run.shop.offer_count {
		return false
	}
	offer := run.shop.offers[offer_index]
	return !offer.sold && run.player.gold >= offer.price &&
	       run.player.deck.owned_count < MAX_OWNED_CARDS && run.player.deck.next_card_id < max(u32)
}

buy_shop_card :: proc(run: ^Run_State, offer_index: int) -> Shop_Result {
	if run == nil || run.phase != .Shop || !validate_shop_state(run) ||
	   offer_index < 0 || offer_index >= run.shop.offer_count {
		return .Invalid
	}
	offer := run.shop.offers[offer_index]
	if offer.sold {
		return .Already_Sold
	}
	if run.player.gold < offer.price {
		return .Not_Enough_Gold
	}
	if run.player.deck.owned_count >= MAX_OWNED_CARDS {
		return .Deck_Full
	}

	staged_deck := run.player.deck
	_, added := add_owned_card(&staged_deck, offer.definition_id)
	if !added {
		return .Invalid
	}
	run.player.deck = staged_deck
	run.player.gold -= offer.price
	run.shop.offers[offer_index].sold = true
	assert(validate_shop_state(run))
	return .Purchased
}

shop_upgrade_can_be_bought :: proc(run: ^Run_State, card_id: u32) -> bool {
	if run == nil || run.phase != .Shop || !validate_shop_state(run) || run.shop.upgrade_used {
		return false
	}
	price, found := shop_upgrade_price(run, card_id)
	return found && run.player.gold >= price
}

buy_shop_upgrade :: proc(run: ^Run_State, card_id: u32) -> Shop_Result {
	if run == nil || run.phase != .Shop || !validate_shop_state(run) {
		return .Invalid
	}
	if run.shop.upgrade_used {
		return .Service_Used
	}
	card_index, found := owned_card_index_by_id(&run.player.deck, card_id)
	if !found {
		return .Card_Not_Found
	}
	if run.player.deck.owned[card_index].upgrade_level >= card_max_upgrade_level(run.player.deck.owned[card_index].definition_id) {
		return .Maximum_Upgrade
	}
	if !card_can_upgrade(run.player.deck.owned[card_index]) {
		return .Upgrade_Unavailable
	}
	price, price_ok := shop_upgrade_price(run, card_id)
	if !price_ok {
		return .Invalid
	}
	if run.player.gold < price {
		return .Not_Enough_Gold
	}

	staged_deck := run.player.deck
	if upgrade_owned_card(&staged_deck, card_id) != .Upgraded {
		return .Invalid
	}
	run.player.deck = staged_deck
	run.player.gold -= price
	run.shop.upgrade_used = true
	assert(validate_shop_state(run))
	return .Upgraded
}

shop_removal_can_be_bought :: proc(run: ^Run_State, card_id: u32) -> bool {
	if run == nil || run.phase != .Shop || !validate_shop_state(run) || run.shop.removal_used ||
	   run.player.deck.owned_count <= MIN_OWNED_CARDS {
		return false
	}
	_, found := owned_card_index_by_id(&run.player.deck, card_id)
	price, price_ok := shop_removal_price(run)
	return found && price_ok && run.player.gold >= price
}

buy_shop_removal :: proc(run: ^Run_State, card_id: u32) -> Shop_Result {
	if run == nil || run.phase != .Shop || !validate_shop_state(run) {
		return .Invalid
	}
	if run.shop.removal_used {
		return .Service_Used
	}
	if run.player.deck.owned_count <= MIN_OWNED_CARDS {
		return .Minimum_Deck_Size
	}
	if _, found := owned_card_index_by_id(&run.player.deck, card_id); !found {
		return .Card_Not_Found
	}
	price, price_ok := shop_removal_price(run)
	if !price_ok {
		return .Invalid
	}
	if run.player.gold < price {
		return .Not_Enough_Gold
	}

	staged_deck := run.player.deck
	if remove_owned_card(&staged_deck, card_id) != .Removed {
		return .Invalid
	}
	run.player.deck = staged_deck
	run.player.gold -= price
	run.shop.removal_used = true
	assert(validate_shop_state(run))
	return .Removed
}
