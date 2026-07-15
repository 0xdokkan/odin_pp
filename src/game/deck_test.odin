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
