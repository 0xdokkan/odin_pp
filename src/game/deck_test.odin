package game

import "core:testing"

@(test)
test_starter_deck_has_unique_valid_instances :: proc(t: ^testing.T) {
	deck: Deck_State
	testing.expect(t, initialize_starter_deck(&deck, 1234))
	testing.expect(t, validate_deck_state(&deck))
	testing.expect_value(t, deck.owned_count, 10)
	testing.expect_value(t, deck.next_card_id, u32(11))
	testing.expect(t, !deck.combat_active)

	definition_counts: [int(Card_Id.Count)]int
	for index in 0..<deck.owned_count {
		card := deck.owned[index]
		testing.expect_value(t, card.id, u32(index+1))
		testing.expect(t, validate_card_instance(card))
		definition_index := int(card.definition_id)
		valid_definition_id := definition_index >= 0 && definition_index < len(definition_counts)
		testing.expect(t, valid_definition_id)
		if valid_definition_id {
			definition_counts[definition_index] += 1
		}
	}
	for definition_count in definition_counts {
		testing.expect_value(t, definition_count, 1)
	}
}

@(test)
test_deck_shuffle_is_deterministic_for_its_seed :: proc(t: ^testing.T) {
	first, second: Deck_State
	testing.expect(t, initialize_starter_deck(&first, 0xCAFE))
	testing.expect(t, initialize_starter_deck(&second, 0xCAFE))
	testing.expect(t, begin_deck_combat(&first))
	testing.expect(t, begin_deck_combat(&second))

	testing.expect_value(t, first.hand_count, STARTING_HAND_SIZE)
	testing.expect_value(t, second.hand_count, STARTING_HAND_SIZE)
	for index in 0..<STARTING_HAND_SIZE {
		testing.expect_value(t, first.hand[index], second.hand[index])
	}
	for index in 0..<first.draw_count {
		testing.expect_value(t, first.draw_pile[index], second.draw_pile[index])
	}
	testing.expect(t, validate_deck_state(&first))
	testing.expect(t, validate_deck_state(&second))
}

@(test)
test_draw_reshuffles_discard_without_losing_or_duplicating_cards :: proc(t: ^testing.T) {
	deck: Deck_State
	rules := Deck_Rules{hand_size = 2, max_energy = 3, energy_regen_per_pulse = 1}
	testing.expect(t, initialize_empty_deck(&deck, rules, 77))
	_, first_added := add_owned_card(&deck, .Strike)
	_, second_added := add_owned_card(&deck, .Guard)
	_, third_added := add_owned_card(&deck, .Toxic_Wave)
	testing.expect(t, first_added && second_added && third_added)
	testing.expect(t, begin_deck_combat(&deck))
	testing.expect_value(t, deck.hand_count, 2)
	testing.expect_value(t, deck.draw_count, 1)

	_, discarded := discard_hand_card(&deck, 0)
	testing.expect(t, discarded)
	_, drawn := draw_card(&deck)
	testing.expect(t, drawn)
	testing.expect_value(t, deck.draw_count, 0)
	testing.expect_value(t, deck.discard_count, 1)

	_, discarded = discard_hand_card(&deck, 0)
	testing.expect(t, discarded)
	_, drawn = draw_card(&deck)
	testing.expect(t, drawn)
	testing.expect_value(t, deck.hand_count, 2)
	testing.expect_value(t, deck.draw_count, 1)
	testing.expect_value(t, deck.discard_count, 0)
	testing.expect(t, validate_deck_state(&deck))
}

@(test)
test_deck_validator_rejects_duplicate_zone_membership :: proc(t: ^testing.T) {
	deck: Deck_State
	testing.expect(t, initialize_starter_deck(&deck, 12))
	testing.expect(t, begin_deck_combat(&deck))
	testing.expect(t, validate_deck_state(&deck))

	deck.draw_pile[0] = deck.hand[0]
	testing.expect(t, !validate_deck_state(&deck))
}

@(test)
test_energy_regeneration_is_clamped_to_deck_maximum :: proc(t: ^testing.T) {
	deck: Deck_State
	testing.expect(t, initialize_starter_deck(&deck, 12))
	testing.expect(t, begin_deck_combat(&deck))
	deck.energy = 0

	testing.expect_value(t, restore_deck_energy_after_pulse(&deck), i32(1))
	testing.expect_value(t, deck.energy, i32(1))
	deck.energy = deck.rules.max_energy
	testing.expect_value(t, restore_deck_energy_after_pulse(&deck), i32(0))
	testing.expect_value(t, deck.energy, deck.rules.max_energy)
}

@(test)
test_add_owned_card_failures_preserve_the_entire_deck :: proc(t: ^testing.T) {
	deck: Deck_State
	testing.expect(t, initialize_starter_deck(&deck, 0xADD))

	before := deck
	_, added := add_owned_card(&deck, .Count)
	testing.expect(t, !added)
	testing.expect(t, deck == before)
	_, added = add_owned_card(&deck, .Strike, -1)
	testing.expect(t, !added)
	testing.expect(t, deck == before)
	_, added = add_owned_card(&deck, .Strike, MAX_CARD_UPGRADE_LEVEL+1)
	testing.expect(t, !added)
	testing.expect(t, deck == before)

	deck.next_card_id = max(u32)
	before = deck
	_, added = add_owned_card(&deck, .Strike)
	testing.expect(t, !added)
	testing.expect(t, deck == before)

	testing.expect(t, initialize_starter_deck(&deck, 0xADD))
	for deck.owned_count < MAX_OWNED_CARDS {
		_, added = add_owned_card(&deck, .Strike)
		testing.expect(t, added)
	}
	before = deck
	_, added = add_owned_card(&deck, .Guard)
	testing.expect(t, !added)
	testing.expect(t, deck == before)

	testing.expect(t, initialize_starter_deck(&deck, 0xADD))
	testing.expect(t, begin_deck_combat(&deck))
	before = deck
	_, added = add_owned_card(&deck, .Guard)
	testing.expect(t, !added)
	testing.expect(t, deck == before)

	testing.expect(t, initialize_starter_deck(&deck, 0xADD))
	deck.owned[1].id = deck.owned[0].id
	before = deck
	_, added = add_owned_card(&deck, .Guard)
	testing.expect(t, !added)
	testing.expect(t, deck == before)
}

@(test)
test_upgrade_owned_card_targets_instance_id_and_changes_only_its_level :: proc(t: ^testing.T) {
	deck: Deck_State
	testing.expect(t, initialize_starter_deck(&deck, 0xC0DE))
	duplicate, added := add_owned_card(&deck, .Strike)
	testing.expect(t, added)
	original_strike := deck.owned[0]
	testing.expect_value(t, original_strike.definition_id, Card_Id.Strike)
	testing.expect(t, original_strike.id != duplicate.id)

	before := deck
	expected := before
	expected.owned[expected.owned_count-1].upgrade_level += 1
	testing.expect_value(t, upgrade_owned_card(&deck, duplicate.id), Deck_Mutation_Result.Upgraded)
	testing.expect(t, deck == expected)
	testing.expect_value(t, deck.owned[0], original_strike)
	testing.expect_value(t, deck.next_card_id, before.next_card_id)
	testing.expect_value(t, deck.random_state, before.random_state)
	testing.expect(t, validate_deck_state(&deck))
}

@(test)
test_upgrade_owned_card_failures_preserve_the_entire_deck :: proc(t: ^testing.T) {
	deck: Deck_State
	testing.expect(t, initialize_starter_deck(&deck, 0xFACE))
	card_id := deck.owned[0].id

	before := deck
	testing.expect_value(t, upgrade_owned_card(&deck, 0), Deck_Mutation_Result.Card_Not_Found)
	testing.expect(t, deck == before)
	testing.expect_value(t, upgrade_owned_card(&deck, deck.next_card_id+100), Deck_Mutation_Result.Card_Not_Found)
	testing.expect(t, deck == before)

	deck.owned[0].upgrade_level = MAX_CARD_UPGRADE_LEVEL
	before = deck
	testing.expect_value(t, upgrade_owned_card(&deck, card_id), Deck_Mutation_Result.Maximum_Upgrade)
	testing.expect(t, deck == before)

	testing.expect(t, initialize_starter_deck(&deck, 0xFACE))
	testing.expect(t, begin_deck_combat(&deck))
	before = deck
	testing.expect_value(t, upgrade_owned_card(&deck, card_id), Deck_Mutation_Result.Invalid)
	testing.expect(t, deck == before)

	testing.expect(t, initialize_starter_deck(&deck, 0xFACE))
	deck.owned[1].id = deck.owned[0].id
	before = deck
	testing.expect_value(t, upgrade_owned_card(&deck, card_id), Deck_Mutation_Result.Invalid)
	testing.expect(t, deck == before)
	testing.expect_value(t, upgrade_owned_card(nil, card_id), Deck_Mutation_Result.Invalid)
}

@(test)
test_remove_owned_card_targets_instance_id_preserves_order_and_never_recycles_id :: proc(t: ^testing.T) {
	deck: Deck_State
	testing.expect(t, initialize_starter_deck(&deck, 0xD311))
	duplicate, added := add_owned_card(&deck, .Strike)
	testing.expect(t, added)
	removed := deck.owned[0]
	before := deck

	testing.expect_value(t, remove_owned_card(&deck, removed.id), Deck_Mutation_Result.Removed)
	testing.expect_value(t, deck.owned_count, before.owned_count-1)
	for index in 0..<deck.owned_count {
		testing.expect_value(t, deck.owned[index], before.owned[index+1])
	}
	testing.expect_value(t, deck.owned[deck.owned_count], Card_Instance{})
	testing.expect_value(t, deck.next_card_id, before.next_card_id)
	testing.expect_value(t, deck.random_state, before.random_state)
	_, removed_still_present := owned_card_index_by_id(&deck, removed.id)
	duplicate_index, duplicate_present := owned_card_index_by_id(&deck, duplicate.id)
	testing.expect(t, !removed_still_present)
	testing.expect(t, duplicate_present)
	testing.expect_value(t, deck.owned[duplicate_index].definition_id, Card_Id.Strike)
	testing.expect(t, validate_deck_state(&deck))
}

@(test)
test_remove_owned_card_failures_preserve_the_entire_deck :: proc(t: ^testing.T) {
	deck: Deck_State
	testing.expect(t, initialize_starter_deck(&deck, 0xDE1E7E))
	card_id := deck.owned[0].id

	before := deck
	testing.expect_value(t, remove_owned_card(&deck, 0), Deck_Mutation_Result.Card_Not_Found)
	testing.expect(t, deck == before)
	testing.expect_value(t, remove_owned_card(&deck, deck.next_card_id+100), Deck_Mutation_Result.Card_Not_Found)
	testing.expect(t, deck == before)

	for deck.owned_count > MIN_OWNED_CARDS {
		result := remove_owned_card(&deck, deck.owned[deck.owned_count-1].id)
		testing.expect_value(t, result, Deck_Mutation_Result.Removed)
	}
	before = deck
	testing.expect_value(t, remove_owned_card(&deck, deck.owned[0].id), Deck_Mutation_Result.Minimum_Deck_Size)
	testing.expect(t, deck == before)

	testing.expect(t, initialize_starter_deck(&deck, 0xDE1E7E))
	testing.expect(t, begin_deck_combat(&deck))
	before = deck
	testing.expect_value(t, remove_owned_card(&deck, card_id), Deck_Mutation_Result.Invalid)
	testing.expect(t, deck == before)

	testing.expect(t, initialize_starter_deck(&deck, 0xDE1E7E))
	deck.owned[1].id = deck.owned[0].id
	before = deck
	testing.expect_value(t, remove_owned_card(&deck, card_id), Deck_Mutation_Result.Invalid)
	testing.expect(t, deck == before)
	testing.expect_value(t, remove_owned_card(nil, card_id), Deck_Mutation_Result.Invalid)
}
