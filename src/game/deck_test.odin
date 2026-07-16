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
	expected_starter := [?]Card_Id{
		.Strike,
		.Arc_Bolt,
		.Piercing_Ray,
		.Cross_Slash,
		.Firebomb,
		.Guard,
		.Toxic_Wave,
		.Thorn_Coat,
		.Afterimage,
		.Counter_Rune,
	}
	for definition, index in CARD_DEFINITIONS {
		expected := 0
		for starter_id in expected_starter {
			if definition.id == starter_id {
				expected += 1
			}
		}
		testing.expect_value(t, definition_counts[index], expected)
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

@(test)
test_hand_size_is_a_refill_target_not_the_runtime_capacity :: proc(t: ^testing.T) {
	deck: Deck_State
	rules := Deck_Rules{hand_size = 5, max_energy = 3, energy_regen_per_pulse = 1}
	testing.expect(t, initialize_empty_deck(&deck, rules, 0xA11CE))
	for _ in 0..<MAX_HAND_CARDS {
		_, added := add_owned_card(&deck, .Strike)
		testing.expect(t, added)
	}
	testing.expect(t, begin_deck_combat(&deck))
	testing.expect_value(t, deck.hand_count, rules.hand_size)
	active_before := deck
	testing.expect(t, !begin_deck_combat(&deck))
	testing.expect_value(t, deck, active_before)

	for _ in rules.hand_size..<MAX_HAND_CARDS {
		_, drawn := draw_card(&deck)
		testing.expect(t, drawn)
	}
	testing.expect_value(t, deck.hand_count, MAX_HAND_CARDS)
	testing.expect(t, validate_deck_state(&deck))

	before := deck
	_, drawn := draw_card(&deck)
	testing.expect(t, !drawn)
	testing.expect_value(t, deck, before)
}

@(test)
test_exhausted_permanent_does_not_reshuffle_and_returns_next_combat :: proc(t: ^testing.T) {
	deck: Deck_State
	rules := Deck_Rules{hand_size = 1, max_energy = 3, energy_regen_per_pulse = 1}
	testing.expect(t, initialize_empty_deck(&deck, rules, 0xE7A057))
	owned, added := add_owned_card(&deck, .Strike)
	testing.expect(t, added)
	testing.expect(t, begin_deck_combat(&deck))

	next_card_id := deck.next_card_id
	random_state := deck.random_state
	exhausted, ok := exhaust_hand_card(&deck, 0)
	testing.expect(t, ok)
	testing.expect_value(t, exhausted, owned)
	testing.expect_value(t, deck.hand_count, 0)
	testing.expect_value(t, deck.draw_count, 0)
	testing.expect_value(t, deck.discard_count, 0)
	testing.expect_value(t, deck.exhaust_count, 1)
	testing.expect_value(t, deck.exhaust_pile[0], owned)
	testing.expect_value(t, deck.next_card_id, next_card_id)
	testing.expect_value(t, deck.random_state, random_state)
	testing.expect(t, validate_deck_state(&deck))

	before_draw := deck
	_, drawn := draw_card(&deck)
	testing.expect(t, !drawn)
	testing.expect_value(t, deck, before_draw)

	finish_deck_combat(&deck)
	testing.expect_value(t, deck.exhaust_count, 0)
	testing.expect_value(t, deck.combat_card_id_floor, u32(0))
	testing.expect_value(t, deck.next_card_id, next_card_id)
	testing.expect(t, validate_deck_state(&deck))
	testing.expect(t, begin_deck_combat(&deck))
	testing.expect_value(t, deck.hand_count, 1)
	testing.expect_value(t, deck.hand[0], owned)
}

@(test)
test_temporary_card_uses_monotonic_id_and_is_removed_after_combat :: proc(t: ^testing.T) {
	deck: Deck_State
	testing.expect(t, initialize_starter_deck(&deck, 0x7E4F))
	testing.expect(t, begin_deck_combat(&deck))
	owned_before := deck.owned
	owned_count_before := deck.owned_count
	next_id_before := deck.next_card_id
	random_before := deck.random_state
	testing.expect_value(t, deck.combat_card_id_floor, next_id_before)

	temporary, created := create_temporary_card(&deck, .Strike, 2)
	testing.expect(t, created)
	testing.expect_value(t, temporary.id, next_id_before)
	testing.expect_value(t, temporary.definition_id, Card_Id.Strike)
	testing.expect_value(t, temporary.upgrade_level, i32(2))
	testing.expect_value(t, temporary.lifetime, Card_Lifetime.Combat)
	testing.expect_value(t, deck.next_card_id, next_id_before+1)
	testing.expect_value(t, deck.random_state, random_before)
	testing.expect_value(t, deck.owned, owned_before)
	testing.expect_value(t, deck.owned_count, owned_count_before)
	testing.expect_value(t, combat_temporary_card_count(&deck), 1)
	testing.expect(t, validate_deck_state(&deck))

	temporary_index, in_hand := hand_card_index_by_id(&deck, temporary.id)
	testing.expect(t, in_hand)
	moved, exhausted := exhaust_hand_card(&deck, temporary_index)
	testing.expect(t, exhausted)
	testing.expect_value(t, moved, temporary)
	testing.expect_value(t, deck.exhaust_pile[deck.exhaust_count-1], temporary)
	testing.expect(t, validate_deck_state(&deck))

	finish_deck_combat(&deck)
	testing.expect_value(t, deck.next_card_id, next_id_before+1)
	testing.expect_value(t, deck.owned, owned_before)
	testing.expect_value(t, deck.owned_count, owned_count_before)
	testing.expect_value(t, combat_temporary_card_count(&deck), 0)
	testing.expect(t, validate_deck_state(&deck))

	testing.expect(t, begin_deck_combat(&deck))
	total_cards := deck.draw_count+deck.hand_count+deck.discard_count+deck.exhaust_count
	testing.expect_value(t, total_cards, owned_count_before)
	testing.expect_value(t, deck.combat_card_id_floor, next_id_before+1)
	_, found := hand_card_index_by_id(&deck, temporary.id)
	testing.expect(t, !found)
}

@(test)
test_temporary_limit_counts_every_combat_zone_and_rejection_is_atomic :: proc(t: ^testing.T) {
	deck: Deck_State
	testing.expect(t, initialize_starter_deck(&deck, 0x71A17))
	testing.expect(t, begin_deck_combat(&deck))
	for index in 0..<MAX_TEMPORARY_CARDS {
		temporary, created := create_temporary_card(&deck, .Guard)
		testing.expect(t, created)
		hand_index, found := hand_card_index_by_id(&deck, temporary.id)
		testing.expect(t, found)
		if index%2 == 0 {
			_, moved := discard_hand_card(&deck, hand_index)
			testing.expect(t, moved)
		} else {
			_, moved := exhaust_hand_card(&deck, hand_index)
			testing.expect(t, moved)
		}
	}
	testing.expect_value(t, combat_temporary_card_count(&deck), MAX_TEMPORARY_CARDS)
	testing.expect(t, validate_deck_state(&deck))

	before := deck
	_, created := create_temporary_card(&deck, .Strike)
	testing.expect(t, !created)
	testing.expect_value(t, deck, before)
}

@(test)
test_full_owned_deck_and_temporary_budget_fit_fixed_combat_storage :: proc(t: ^testing.T) {
	deck: Deck_State
	testing.expect(t, initialize_empty_deck(&deck, DEFAULT_DECK_RULES, 0x48))
	for _ in 0..<MAX_OWNED_CARDS {
		_, added := add_owned_card(&deck, .Strike)
		testing.expect(t, added)
	}
	testing.expect(t, begin_deck_combat(&deck))
	for _ in 0..<MAX_TEMPORARY_CARDS {
		temporary, created := create_temporary_card(&deck, .Strike)
		testing.expect(t, created)
		hand_index, found := hand_card_index_by_id(&deck, temporary.id)
		testing.expect(t, found)
		_, moved := discard_hand_card(&deck, hand_index)
		testing.expect(t, moved)
	}
	total_cards := deck.draw_count+deck.hand_count+deck.discard_count+deck.exhaust_count
	testing.expect_value(t, total_cards, MAX_COMBAT_CARDS)
	testing.expect_value(t, combat_temporary_card_count(&deck), MAX_TEMPORARY_CARDS)
	testing.expect(t, validate_deck_state(&deck))
}

@(test)
test_temporary_creation_failures_preserve_the_entire_deck :: proc(t: ^testing.T) {
	deck: Deck_State
	testing.expect(t, initialize_starter_deck(&deck, 0xFA11))
	inactive := deck
	_, created := create_temporary_card(&deck, .Strike)
	testing.expect(t, !created)
	testing.expect_value(t, deck, inactive)

	testing.expect(t, begin_deck_combat(&deck))
	before := deck
	_, created = create_temporary_card(&deck, .Count)
	testing.expect(t, !created)
	testing.expect_value(t, deck, before)
	_, created = create_temporary_card(&deck, .Strike, -1)
	testing.expect(t, !created)
	testing.expect_value(t, deck, before)
	_, created = create_temporary_card(&deck, .Strike, MAX_CARD_UPGRADE_LEVEL+1)
	testing.expect(t, !created)
	testing.expect_value(t, deck, before)

	for deck.hand_count < MAX_HAND_CARDS {
		_, drawn := draw_card(&deck)
		testing.expect(t, drawn)
	}
	before = deck
	_, created = create_temporary_card(&deck, .Strike)
	testing.expect(t, !created)
	testing.expect_value(t, deck, before)

	finish_deck_combat(&deck)
	deck.next_card_id = max(u32)
	testing.expect(t, begin_deck_combat(&deck))
	before = deck
	_, created = create_temporary_card(&deck, .Strike)
	testing.expect(t, !created)
	testing.expect_value(t, deck, before)

	corrupted := deck
	corrupted.combat_card_id_floor = 0
	before = corrupted
	_, created = create_temporary_card(&corrupted, .Strike)
	testing.expect(t, !created)
	testing.expect_value(t, corrupted, before)
}

@(test)
test_zone_move_rejections_are_atomic :: proc(t: ^testing.T) {
	deck: Deck_State
	testing.expect(t, initialize_starter_deck(&deck, 0x20AE))
	testing.expect(t, begin_deck_combat(&deck))
	before := deck

	invalid_destinations := [?]Card_Zone{.Draw, .Hand, .Resolving, .Count}
	for destination in invalid_destinations {
		_, moved := move_hand_card_to_zone(&deck, 0, destination)
		testing.expect(t, !moved)
		testing.expect_value(t, deck, before)
	}
	_, moved := move_hand_card_to_zone(&deck, -1, .Discard)
	testing.expect(t, !moved)
	testing.expect_value(t, deck, before)
	_, moved = move_hand_card_to_zone(&deck, deck.hand_count, .Exhaust)
	testing.expect(t, !moved)
	testing.expect_value(t, deck, before)

	finish_deck_combat(&deck)
	before = deck
	_, moved = discard_hand_card(&deck, 0)
	testing.expect(t, !moved)
	testing.expect_value(t, deck, before)
}

@(test)
test_deck_validator_rejects_corrupted_temporary_ownership_and_ids :: proc(t: ^testing.T) {
	deck: Deck_State
	testing.expect(t, initialize_starter_deck(&deck, 0xC022))
	testing.expect(t, begin_deck_combat(&deck))
	temporary, created := create_temporary_card(&deck, .Strike)
	testing.expect(t, created)
	hand_index, found := hand_card_index_by_id(&deck, temporary.id)
	testing.expect(t, found)

	corrupted := deck
	corrupted.hand[hand_index].lifetime = .Permanent
	testing.expect(t, !validate_deck_state(&corrupted))

	corrupted = deck
	corrupted.owned[0].lifetime = .Combat
	testing.expect(t, !validate_deck_state(&corrupted))

	corrupted = deck
	corrupted.hand[hand_index].id = corrupted.combat_card_id_floor-1
	testing.expect(t, !validate_deck_state(&corrupted))

	corrupted = deck
	corrupted.discard_pile[corrupted.discard_count] = temporary
	corrupted.discard_count += 1
	testing.expect(t, !validate_deck_state(&corrupted))

	corrupted = deck
	corrupted.combat_card_id_floor = corrupted.next_card_id+1
	testing.expect(t, !validate_deck_state(&corrupted))

	corrupted = deck
	corrupted.hand[hand_index].id += 1
	corrupted.next_card_id += 1
	testing.expect(t, !validate_deck_state(&corrupted))

	corrupted = deck
	corrupted.next_card_id += 1
	testing.expect(t, !validate_deck_state(&corrupted))
}

@(test)
test_resolving_zone_keeps_played_card_out_of_reshuffle :: proc(t: ^testing.T) {
	deck: Deck_State
	rules := Deck_Rules{hand_size = 1, max_energy = 3, energy_regen_per_pulse = 1}
	testing.expect(t, initialize_empty_deck(&deck, rules, 0x2E501))
	_, first_added := add_owned_card(&deck, .Strike)
	_, second_added := add_owned_card(&deck, .Guard)
	testing.expect(t, first_added && second_added)
	testing.expect(t, begin_deck_combat(&deck))
	played := deck.hand[0]

	resolving, began := begin_resolving_hand_card(&deck, 0)
	testing.expect(t, began)
	testing.expect_value(t, resolving, played)
	testing.expect(t, deck.has_resolving_card)
	testing.expect_value(t, deck.resolving_card, played)
	testing.expect_value(t, deck.hand_count, 0)
	testing.expect(t, validate_deck_state(&deck))

	drawn, ok := draw_card(&deck)
	testing.expect(t, ok)
	testing.expect(t, drawn.id != played.id)
	testing.expect_value(t, deck.hand_count, 1)
	testing.expect_value(t, deck.draw_count, 0)
	testing.expect_value(t, deck.discard_count, 0)
	testing.expect_value(t, deck.resolving_card, played)

	before_second_draw := deck
	_, ok = draw_card(&deck)
	testing.expect(t, !ok)
	testing.expect_value(t, deck, before_second_draw)

	finished, moved := finish_resolving_card(&deck, .Exhaust)
	testing.expect(t, moved)
	testing.expect_value(t, finished, played)
	testing.expect(t, !deck.has_resolving_card)
	testing.expect_value(t, deck.resolving_card, Card_Instance{})
	testing.expect_value(t, deck.exhaust_pile[0], played)
	testing.expect_value(t, deck.exhaust_count, 1)
	testing.expect(t, validate_deck_state(&deck))
}

@(test)
test_resolving_zone_transitions_reject_invalid_operations_atomically :: proc(t: ^testing.T) {
	deck: Deck_State
	testing.expect(t, initialize_starter_deck(&deck, 0x2E502))
	testing.expect(t, begin_deck_combat(&deck))

	before := deck
	_, finished := finish_resolving_card(&deck, .Discard)
	testing.expect(t, !finished)
	testing.expect_value(t, deck, before)
	_, began := begin_resolving_hand_card(&deck, -1)
	testing.expect(t, !began)
	testing.expect_value(t, deck, before)

	card: Card_Instance
	card, began = begin_resolving_hand_card(&deck, 0)
	testing.expect(t, began)
	resolving := deck
	_, began = begin_resolving_hand_card(&deck, 0)
	testing.expect(t, !began)
	testing.expect_value(t, deck, resolving)

	invalid_destinations := [?]Card_Zone{.Draw, .Hand, .Resolving, .Count}
	for destination in invalid_destinations {
		_, finished = finish_resolving_card(&deck, destination)
		testing.expect(t, !finished)
		testing.expect_value(t, deck, resolving)
	}
	finished_card: Card_Instance
	finished_card, finished = finish_resolving_card(&deck, .Discard)
	testing.expect(t, finished)
	testing.expect_value(t, finished_card, card)
	testing.expect_value(t, deck.discard_pile[deck.discard_count-1], card)
	testing.expect(t, validate_deck_state(&deck))
}

@(test)
test_temporary_card_in_resolving_zone_counts_toward_budget_and_clears_at_finish :: proc(t: ^testing.T) {
	deck: Deck_State
	testing.expect(t, initialize_starter_deck(&deck, 0x2E503))
	testing.expect(t, begin_deck_combat(&deck))
	temporary, created := create_temporary_card(&deck, .Strike)
	testing.expect(t, created)
	hand_index, found := hand_card_index_by_id(&deck, temporary.id)
	testing.expect(t, found)
	_, began := begin_resolving_hand_card(&deck, hand_index)
	testing.expect(t, began)
	testing.expect_value(t, combat_temporary_card_count(&deck), 1)
	testing.expect(t, validate_deck_state(&deck))

	finish_deck_combat(&deck)
	testing.expect(t, !deck.has_resolving_card)
	testing.expect_value(t, deck.resolving_card, Card_Instance{})
	testing.expect_value(t, combat_temporary_card_count(&deck), 0)
	testing.expect(t, validate_deck_state(&deck))
}

@(test)
test_deck_validator_rejects_corrupted_resolving_slot :: proc(t: ^testing.T) {
	deck: Deck_State
	testing.expect(t, initialize_starter_deck(&deck, 0x2E504))
	testing.expect(t, begin_deck_combat(&deck))

	corrupted := deck
	corrupted.resolving_card = corrupted.hand[0]
	testing.expect(t, !validate_deck_state(&corrupted))

	_, began := begin_resolving_hand_card(&deck, 0)
	testing.expect(t, began)
	corrupted = deck
	corrupted.has_resolving_card = false
	testing.expect(t, !validate_deck_state(&corrupted))

	corrupted = deck
	corrupted.resolving_card = corrupted.hand[0]
	testing.expect(t, !validate_deck_state(&corrupted))
}

@(test)
test_temporary_only_definition_cannot_be_owned_but_can_be_created_in_combat :: proc(t: ^testing.T) {
	temporary_definition := Card_Id.Count
	for definition in CARD_DEFINITIONS {
		if definition.temporary_only {
			temporary_definition = definition.id
			break
		}
	}
	testing.expect(t, temporary_definition != .Count)
	if temporary_definition == .Count {
		return
	}

	deck: Deck_State
	testing.expect(t, initialize_empty_deck(&deck, DEFAULT_DECK_RULES, 0x7E4F0))
	before := deck
	_, added := add_owned_card(&deck, temporary_definition)
	testing.expect(t, !added)
	testing.expect_value(t, deck, before)

	_, added = add_owned_card(&deck, .Strike)
	testing.expect(t, added)
	testing.expect(t, begin_deck_combat(&deck))
	temporary, created := create_temporary_card(&deck, temporary_definition)
	testing.expect(t, created)
	testing.expect_value(t, temporary.definition_id, temporary_definition)
	testing.expect_value(t, temporary.lifetime, Card_Lifetime.Combat)
	testing.expect(t, validate_deck_state(&deck))
}

@(test)
test_refocus_deck_hand_classifies_the_original_hand_in_stable_order :: proc(t: ^testing.T) {
	deck: Deck_State
	rules := Deck_Rules{hand_size = 3, max_energy = 3, energy_regen_per_pulse = 1}
	testing.expect(t, initialize_empty_deck(&deck, rules, 0xF0C05))
	_, counter_added := add_owned_card(&deck, .Counter_Rune)
	_, battle_added := add_owned_card(&deck, .Battle_Focus)
	_, strike_added := add_owned_card(&deck, .Strike)
	testing.expect(t, counter_added && battle_added && strike_added)
	testing.expect(t, begin_deck_combat(&deck))

	ordered: [3]Card_Instance
	for card in deck.hand[:deck.hand_count] {
		#partial switch card.definition_id {
		case .Counter_Rune:
			ordered[0] = card
		case .Battle_Focus:
			ordered[1] = card
		case .Strike:
			ordered[2] = card
		}
	}
	deck.hand[0] = ordered[0]
	deck.hand[1] = ordered[1]
	deck.hand[2] = ordered[2]
	testing.expect(t, validate_deck_state(&deck))
	random_before := deck.random_state
	energy_before := deck.energy

	report, ok := refocus_deck_hand(&deck)

	testing.expect(t, ok)
	testing.expect_value(t, report.outcome_count, 3)
	testing.expect_value(t, report.retained_count, 1)
	testing.expect_value(t, report.discarded_count, 1)
	testing.expect_value(t, report.exhausted_count, 1)
	testing.expect_value(t, report.outcomes[0], Card_Refocus_Outcome{
		card = ordered[0],
		destination = .Hand,
	})
	testing.expect_value(t, report.outcomes[1], Card_Refocus_Outcome{
		card = ordered[1],
		destination = .Exhaust,
	})
	testing.expect_value(t, report.outcomes[2], Card_Refocus_Outcome{
		card = ordered[2],
		destination = .Discard,
	})
	testing.expect_value(t, deck.hand_count, 1)
	testing.expect_value(t, deck.hand[0], ordered[0])
	testing.expect_value(t, deck.exhaust_count, 1)
	testing.expect_value(t, deck.exhaust_pile[0], ordered[1])
	testing.expect_value(t, deck.discard_count, 1)
	testing.expect_value(t, deck.discard_pile[0], ordered[2])
	testing.expect_value(t, deck.random_state, random_before)
	testing.expect_value(t, deck.energy, energy_before)
	testing.expect(t, validate_deck_state(&deck))
}

@(test)
test_refocus_retains_cards_above_the_hand_size_target :: proc(t: ^testing.T) {
	deck: Deck_State
	rules := Deck_Rules{hand_size = 1, max_energy = 3, energy_regen_per_pulse = 1}
	testing.expect(t, initialize_empty_deck(&deck, rules, 0xAE7A1))
	_, first_added := add_owned_card(&deck, .Counter_Rune)
	_, second_added := add_owned_card(&deck, .Counter_Rune)
	testing.expect(t, first_added && second_added)
	testing.expect(t, begin_deck_combat(&deck))
	_, drawn := draw_card(&deck)
	testing.expect(t, drawn)
	testing.expect_value(t, deck.hand_count, 2)

	report, ok := refocus_deck_hand(&deck)

	testing.expect(t, ok)
	testing.expect_value(t, report.outcome_count, 2)
	testing.expect_value(t, report.retained_count, 2)
	testing.expect_value(t, report.discarded_count, 0)
	testing.expect_value(t, report.exhausted_count, 0)
	testing.expect_value(t, deck.hand_count, 2)
	testing.expect(t, deck.hand_count > deck.rules.hand_size)
	testing.expect(t, validate_deck_state(&deck))
}

@(test)
test_refocus_deck_hand_rejections_preserve_the_entire_deck :: proc(t: ^testing.T) {
	inactive: Deck_State
	testing.expect(t, initialize_starter_deck(&inactive, 0xBAD))
	inactive_before := inactive
	_, ok := refocus_deck_hand(&inactive)
	testing.expect(t, !ok)
	testing.expect_value(t, inactive, inactive_before)

	active := inactive
	testing.expect(t, begin_deck_combat(&active))
	_, began_resolving := begin_resolving_hand_card(&active, 0)
	testing.expect(t, began_resolving)
	resolving_before := active
	_, ok = refocus_deck_hand(&active)
	testing.expect(t, !ok)
	testing.expect_value(t, active, resolving_before)

	corrupted := resolving_before
	corrupted.has_resolving_card = false
	corrupted.resolving_card = {}
	corrupted.random_state = 0
	corrupted_before := corrupted
	_, ok = refocus_deck_hand(&corrupted)
	testing.expect(t, !ok)
	testing.expect_value(t, corrupted, corrupted_before)

	_, ok = refocus_deck_hand(nil)
	testing.expect(t, !ok)
}
