package game

import "core:testing"

// How many cards an offer can hold at once at `node`: every card with a weight (rewards, shops, the Armory).
offerable_card_count :: proc(node: ^Run_Node, profile: ^M8_Profile = nil, excluded: Card_Offer_Exclusions = {}) -> (count: int) {
	for definition in CARD_DEFINITIONS {
		if definition.id != .Count && card_offer_weight(definition, node, profile, excluded) > 0 { count += 1 }
	}
	return
}

// THE CARDS REVISED ON 2026-10-25 (docs/registro-carte.md): five cards become another at their second upgrade, and those
// five and eight more are out of the game but for that.

@(private = "file")
EVOLUTIONS :: [5][2]Card_Id{
	{.Guard, .Purifying_Guard}, {.Strike, .Cross_Slash}, {.Arc_Bolt, .Chain_Lightning},
	{.Fate_Strike, .Prismatic_Barrage}, {.Venom_Needle, .Twin_Venom},
}

@(private = "file")
RETIRED :: [8]Card_Id{.Thorn_Coat, .Afterimage, .Counter_Rune, .Battle_Focus, .Spark_Forge, .Spark, .Volatile_Study, .Titan_Grip}

// Each of the five becomes the other at its second upgrade, which starts again from level 0; its first upgrade is an
// ordinary one; the card it becomes is only made so.
@(test)
test_five_cards_become_another_at_their_second_upgrade :: proc(t: ^testing.T) {
	for pair in EVOLUTIONS {
		base, evolved := pair[0], pair[1]
		definition, _ := card_definition_by_id(base)
		testing.expect_value(t, definition.evolves_to, evolved)
		testing.expect_value(t, definition.evolve_level, CARD_EVOLVE_LEVEL)
		target, _ := card_definition_by_id(evolved)
		testing.expect(t, target.evolution_only && target.reward_weight == 0 && !card_in_collection(evolved))
		deck: Deck_State
		testing.expect(t, initialize_empty_deck(&deck))
		card, added := add_owned_card(&deck, base)
		testing.expect(t, added)
		testing.expect_value(t, upgrade_owned_card(&deck, card.id), Deck_Mutation_Result.Upgraded)
		testing.expectf(t, deck.owned[0].definition_id == base && deck.owned[0].upgrade_level == 1, "%v after one upgrade", base)
		testing.expect_value(t, upgrade_owned_card(&deck, card.id), Deck_Mutation_Result.Upgraded)
		testing.expectf(t, deck.owned[0].definition_id == evolved && deck.owned[0].upgrade_level == 0, "%v after two upgrades is %v", base, deck.owned[0].definition_id)
		testing.expect_value(t, deck.owned[0].id, card.id)
		// The card it became upgrades on its own way.
		testing.expect_value(t, upgrade_owned_card(&deck, card.id), Deck_Mutation_Result.Upgraded)
		testing.expectf(t, deck.owned[0].definition_id == evolved && deck.owned[0].upgrade_level == 1, "%v upgrades once more", evolved)
	}
}

// The retired cards stay in the code (and play as they did, for a deck from an old save), but nothing deals, offers or
// discovers them; the starter deck and the first ring do without them.
@(test)
test_the_retired_cards_are_kept_but_never_dealt_offered_or_collected :: proc(t: ^testing.T) {
	node := Run_Node{kind = .Shop, depth = 9}
	profile := M8_Profile{ring_wins = 3}
	for id in RETIRED {
		definition, found := card_definition_by_id(id)
		testing.expect(t, found && validate_card_definition(&definition))
		testing.expect(t, card_is_retired(id) && !card_in_collection(id))
		testing.expect_value(t, card_offer_weight(definition, &node, &profile), u64(0))
	}
	for pair in EVOLUTIONS {
		testing.expect(t, !card_is_retired(pair[0]) && card_in_collection(pair[0]), "the base cards stay")
		testing.expect(t, !card_is_retired(pair[1]), "the cards an upgrade makes are not retired")
	}
	deck: Deck_State
	testing.expect(t, initialize_starter_deck(&deck))
	for card in deck.owned[:deck.owned_count] {
		testing.expectf(t, card_in_collection(card.definition_id), "%v in the starter deck", card.definition_id)
	}
	// Many rewards and shops, never a retired card nor one only an upgrade makes.
	choices: [3]Card_Id
	random := u64(77)
	for _ in 0..<400 {
		testing.expect(t, generate_weighted_card_choices(&random, &node, choices[:], &profile))
		for id in choices { testing.expectf(t, card_in_collection(id) || card_is_scopa(id), "%v offered", id) }
	}
	// The first ring's prize.
	testing.expect(t, !m8_card_unlocked(.Grappling_Hook) && m8_card_unlocked(.Grappling_Hook, &profile))
	testing.expect(t, m8_card_unlocked(.Titan_Grip))
}
