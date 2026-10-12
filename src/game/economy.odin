package game

import rng "../engine/rng"

MAX_CARD_OFFER_DEPTH :: 12

Card_Rarity_Weights :: struct {
	common, uncommon, rare: u32,
}

card_rarity_weights :: proc(kind: Node_Kind, depth: int) -> (result: Card_Rarity_Weights, ok: bool) {
	if depth < 0 || !node_kind_is_valid(kind) ||
	   (kind != .Combat && kind != .Elite && kind != .Boss && kind != .Shop && kind != .Event) {
		return {}, false
	}
	bounded_depth := min(depth, MAX_CARD_OFFER_DEPTH)
	common := max(22, 70-bounded_depth*4)
	uncommon := 25+bounded_depth*2
	rare := 5+bounded_depth*2
	switch kind {
	case .Combat:
	case .Elite:
		common = max(12, common-10)
		uncommon += 4
		rare += 6
	case .Boss:
		common = max(8, common-14)
		uncommon += 5
		rare += 9
	case .Shop:
		common = max(8, common-15)
		uncommon += 6
		rare += 9
	case .Event:
		common = max(16, common-5)
		uncommon += 3
		rare += 2
	case .Rest, .Treasure, .Count:
		return {}, false
	}
	return {
		common = u32(common),
		uncommon = u32(uncommon),
		rare = u32(rare),
	}, true
}

card_rarity_weight :: proc(weights: Card_Rarity_Weights, rarity: Card_Rarity) -> u32 {
	switch rarity {
	case .Common:
		return weights.common
	case .Uncommon:
		return weights.uncommon
	case .Rare:
		return weights.rare
	case .Count:
	}
	return 0
}

card_offer_weight :: proc(definition: Card_Definition, node: ^Run_Node, profile: ^M8_Profile = nil) -> u64 {
	validated_definition := definition
	if node == nil || !validate_card_definition(&validated_definition) || definition.temporary_only || !m8_card_unlocked(definition.id, profile) ||
	   card_is_scopa(definition.id) {
		return 0
	}
	weights, ok := card_rarity_weights(node.kind, node.depth)
	if !ok {
		return 0
	}
	rarity_weight := card_rarity_weight(weights, definition.rarity)
	return u64(rarity_weight)*u64(definition.reward_weight)
}

economy_next_random :: proc(random_state: ^u64) -> u64 {
	assert(random_state != nil && random_state^ != 0)
	return rng.step(random_state)
}

generate_weighted_card_choices :: proc(
	random_state: ^u64,
	node: ^Run_Node,
	destination: []Card_Id,
	profile: ^M8_Profile = nil,
) -> bool {
	if random_state == nil || random_state^ == 0 || node == nil || node.depth < 0 ||
	   len(destination) <= 0 || len(destination) > int(Card_Id.Count) {
		return false
	}
	collectible_count := 0
	for definition in CARD_DEFINITIONS {
		if card_offer_weight(definition, node, profile) > 0 {
			collectible_count += 1
		}
	}
	if len(destination) > collectible_count {
		return false
	}

	staged_random_state := random_state^
	staged_choices: [int(Card_Id.Count)]Card_Id
	selected: [int(Card_Id.Count)]bool
	for choice_index in 0..<len(destination) {
		total_weight: u64
		for definition in CARD_DEFINITIONS {
			if !selected[int(definition.id)] {
				total_weight += card_offer_weight(definition, node, profile)
			}
		}
		if total_weight == 0 {
			return false
		}

		roll := economy_next_random(&staged_random_state)%total_weight
		chosen := Card_Id.Count
		for definition in CARD_DEFINITIONS {
			if selected[int(definition.id)] {
				continue
			}
			weight := card_offer_weight(definition, node, profile)
			if roll < weight {
				chosen = definition.id
				break
			}
			roll -= weight
		}
		if chosen == .Count {
			return false
		}
		staged_choices[choice_index] = chosen
		selected[int(chosen)] = true
	}
	for choice_index in 0..<len(destination) {
		destination[choice_index] = staged_choices[choice_index]
	}
	random_state^ = staged_random_state
	return true
}
