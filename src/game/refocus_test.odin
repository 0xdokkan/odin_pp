package game

import "core:testing"
import level "../level"

configure_refocus_test_deck :: proc(
	t: ^testing.T,
	player: ^Player,
	definitions: []Card_Id,
	rules: Deck_Rules,
) {
	testing.expect(t, player != nil)
	testing.expect(t, initialize_empty_deck(&player.deck, rules, 0xF0C05))
	for definition_id in definitions {
		_, added := add_owned_card(&player.deck, definition_id)
		testing.expect(t, added)
	}
}

place_refocus_test_card_in_hand :: proc(
	t: ^testing.T,
	deck: ^Deck_State,
	definition_id: Card_Id,
	hand_slot: int,
) -> Card_Instance {
	testing.expect(t, deck != nil && hand_slot >= 0 && hand_slot < deck.hand_count)
	for index in 0..<deck.hand_count {
		if deck.hand[index].definition_id == definition_id {
			deck.hand[hand_slot], deck.hand[index] = deck.hand[index], deck.hand[hand_slot]
			testing.expect(t, validate_deck_state(deck))
			return deck.hand[hand_slot]
		}
	}
	for index in 0..<deck.draw_count {
		if deck.draw_pile[index].definition_id == definition_id {
			deck.hand[hand_slot], deck.draw_pile[index] =
				deck.draw_pile[index], deck.hand[hand_slot]
			testing.expect(t, validate_deck_state(deck))
			return deck.hand[hand_slot]
		}
	}
	testing.expectf(t, false, "definition %v was not present in a drawable combat zone", definition_id)
	return {}
}

@(test)
test_refocus_player_hand_cleans_pulses_then_refills_in_fifo_order :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	definitions := [?]Card_Id{
		.Counter_Rune,
		.Battle_Focus,
		.Strike,
		.Guard,
		.Afterimage,
		.Thorn_Coat,
	}
	configure_refocus_test_deck(t, &player, definitions[:], {
		hand_size = 3,
		max_energy = 3,
		energy_regen_per_pulse = 1,
	})
	enemies := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 8, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	counter := place_refocus_test_card_in_hand(t, &player.deck, .Counter_Rune, 0)
	battle := place_refocus_test_card_in_hand(t, &player.deck, .Battle_Focus, 1)
	strike := place_refocus_test_card_in_hand(t, &player.deck, .Strike, 2)
	room.enemies[0].intent = make_wait_intent(&room, room.enemies[0].position)
	player.deck.energy = 0

	refocus := refocus_player_hand(&room)

	testing.expect_value(t, refocus.result, Refocus_Result.Refocused)
	testing.expect(t, refocus_was_committed(refocus.result))
	testing.expect(t, refocus.pulse_report.advanced)
	testing.expect_value(t, refocus.hand_report.outcome_count, 3)
	testing.expect_value(t, refocus.hand_report.retained_count, 1)
	testing.expect_value(t, refocus.hand_report.discarded_count, 1)
	testing.expect_value(t, refocus.hand_report.exhausted_count, 1)
	testing.expect_value(t, refocus.drawn_count, 2)
	testing.expect_value(t, refocus.energy_before, i32(0))
	testing.expect_value(t, refocus.energy_after, i32(1))
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect_value(t, player.deck.hand_count, 3)
	testing.expect_value(t, player.deck.hand[0], counter)
	testing.expect_value(t, player.deck.discard_count, 1)
	testing.expect_value(t, player.deck.discard_pile[0], strike)
	testing.expect_value(t, player.deck.exhaust_count, 1)
	testing.expect_value(t, player.deck.exhaust_pile[0], battle)
	testing.expect(t, validate_deck_state(&player.deck))

	testing.expect_value(t, room.recent_events.count, 7)
	testing.expect_value(t, room.recent_events.events[0].kind, Game_Event_Kind.Hand_Refocused)
	testing.expect_value(t, room.recent_events.events[0].amount, i32(3))
	expected_cards := [?]Card_Instance{counter, battle, strike}
	expected_destinations := [?]Card_Zone{.Hand, .Exhaust, .Discard}
	for index in 0..<len(expected_cards) {
		event := room.recent_events.events[index+1]
		testing.expect_value(t, event.kind, Game_Event_Kind.Card_Refocused)
		testing.expect_value(t, event.card_id, expected_cards[index].id)
		testing.expect_value(t, event.card_definition, expected_cards[index].definition_id)
		testing.expect_value(t, event.from_card_zone, Card_Zone.Hand)
		testing.expect_value(t, event.to_card_zone, expected_destinations[index])
	}
	testing.expect_value(t, room.recent_events.events[4].kind, Game_Event_Kind.Pulse_Advanced)
	testing.expect_value(t, room.recent_events.events[5].kind, Game_Event_Kind.Card_Drawn)
	testing.expect_value(t, room.recent_events.events[6].kind, Game_Event_Kind.Card_Drawn)
}

@(test)
test_refocus_discards_combat_lifetime_then_replays_reshuffle :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	definitions := [?]Card_Id{.Strike}
	configure_refocus_test_deck(t, &player, definitions[:], {
		hand_size = 1,
		max_energy = 3,
		energy_regen_per_pulse = 1,
	})
	enemies := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 8, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	room.enemies[0].intent = make_wait_intent(&room, room.enemies[0].position)
	strike := player.deck.hand[0]
	spark, created := create_temporary_card(&player.deck, .Spark)
	testing.expect(t, created)
	expected := player.deck
	expected_hand, expected_cleanup := refocus_deck_hand(&expected)
	testing.expect(t, expected_cleanup)
	expected_draw, expected_drawn := draw_card(&expected)
	testing.expect(t, expected_drawn)

	refocus := refocus_player_hand(&room)

	testing.expect_value(t, refocus.result, Refocus_Result.Refocused)
	testing.expect_value(t, refocus.hand_report, expected_hand)
	testing.expect_value(t, refocus.hand_report.outcomes[0].card, strike)
	testing.expect_value(t, refocus.hand_report.outcomes[1].card, spark)
	testing.expect_value(t, refocus.hand_report.outcomes[0].destination, Card_Zone.Discard)
	testing.expect_value(t, refocus.hand_report.outcomes[1].destination, Card_Zone.Discard)
	testing.expect_value(t, refocus.hand_report.exhausted_count, 0)
	testing.expect_value(t, refocus.drawn_count, 1)
	testing.expect_value(t, refocus.drawn_cards[0], expected_draw)
	testing.expect_value(t, player.deck.random_state, expected.random_state)
	testing.expect_value(t, player.deck.hand[0], expected_draw)
	testing.expect_value(t, player.deck.draw_count, 1)
	testing.expect_value(t, player.deck.discard_count, 0)
	testing.expect_value(t, player.deck.exhaust_count, 0)
	testing.expect(t, validate_deck_state(&player.deck))
}

@(test)
test_refocus_terminal_pulse_commits_cleanup_without_refill :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	definitions := [?]Card_Id{.Strike, .Guard}
	configure_refocus_test_deck(t, &player, definitions[:], {
		hand_size = 1,
		max_energy = 3,
		energy_regen_per_pulse = 1,
	})
	player.health = 1
	enemies := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 8, attack = 3}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	refocus := refocus_player_hand(&room)

	testing.expect_value(t, refocus.result, Refocus_Result.Player_Defeated)
	testing.expect(t, refocus_was_committed(refocus.result))
	testing.expect(t, refocus.pulse_report.advanced && refocus.pulse_report.player_defeated)
	testing.expect_value(t, refocus.drawn_count, 0)
	testing.expect_value(t, room.phase, Room_Phase.Defeat)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect(t, !player.deck.combat_active)
	testing.expect_value(t, player.deck.hand_count, 0)
	testing.expect_value(t, refocus.energy_after, i32(0))
	for event in room.recent_events.events[:room.recent_events.count] {
		testing.expect(t, event.kind != .Card_Drawn)
	}
}

@(test)
test_refocus_combat_end_from_status_skips_refill_and_clears_runtime_zones :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	definitions := [?]Card_Id{.Strike, .Guard}
	configure_refocus_test_deck(t, &player, definitions[:], {
		hand_size = 1,
		max_energy = 3,
		energy_regen_per_pulse = 1,
	})
	enemies := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 1, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	enemy := enemy_entity(room.enemies[0].id)
	room.enemies[0].intent = make_wait_intent(&room, room.enemies[0].position)
	applied, _ := apply_status(&room, enemy, .Poison, 1, 1)
	testing.expect(t, applied)

	refocus := refocus_player_hand(&room)

	testing.expect_value(t, refocus.result, Refocus_Result.Combat_Ended)
	testing.expect(t, refocus_was_committed(refocus.result))
	testing.expect(t, refocus.pulse_report.advanced && refocus.pulse_report.combat_ended)
	testing.expect_value(t, refocus.drawn_count, 0)
	testing.expect_value(t, room.phase, Room_Phase.Loot)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect(t, !player.deck.combat_active)
	testing.expect(t, validate_deck_state(&player.deck))
}

@(test)
test_refocus_rejections_preserve_deck_pulse_and_recent_events :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	definitions := [?]Card_Id{.Strike, .Guard}
	configure_refocus_test_deck(t, &player, definitions[:], {
		hand_size = 1,
		max_energy = 3,
		energy_regen_per_pulse = 1,
	})
	enemies := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 8, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	record_event(&room.recent_events, {kind = .Gold_Gained, amount = 7})
	active_before := player.deck
	_, began_resolving := begin_resolving_hand_card(&player.deck, 0)
	testing.expect(t, began_resolving)
	deck_before := player.deck
	events_before := room.recent_events
	health_before := player.health

	refocus := refocus_player_hand(&room)

	testing.expect_value(t, refocus.result, Refocus_Result.Card_Resolving)
	testing.expect(t, !refocus_was_committed(refocus.result))
	testing.expect_value(t, player.deck, deck_before)
	testing.expect_value(t, room.recent_events, events_before)
	testing.expect_value(t, player.health, health_before)
	testing.expect_value(t, room.pulse_count, u64(0))

	player.deck = deck_before
	player.deck.random_state = 0
	corrupted_before := player.deck
	refocus = refocus_player_hand(&room)
	testing.expect_value(t, refocus.result, Refocus_Result.Invalid_Deck)
	testing.expect_value(t, player.deck, corrupted_before)
	testing.expect_value(t, room.recent_events, events_before)
	testing.expect_value(t, room.pulse_count, u64(0))

	player.deck = active_before
	room.phase = .Loot
	phase_deck_before := player.deck
	refocus = refocus_player_hand(&room)
	testing.expect_value(t, refocus.result, Refocus_Result.Invalid_Phase)
	testing.expect_value(t, player.deck, phase_deck_before)
	testing.expect_value(t, room.recent_events, events_before)
	testing.expect_value(t, room.pulse_count, u64(0))

	refocus = refocus_player_hand(nil)
	testing.expect_value(t, refocus.result, Refocus_Result.Invalid_Room)
}

@(test)
test_refocus_empty_hand_still_advances_exactly_one_pulse :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	definitions := [?]Card_Id{.Strike}
	configure_refocus_test_deck(t, &player, definitions[:], {
		hand_size = 1,
		max_energy = 3,
		energy_regen_per_pulse = 1,
	})
	enemies := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 8, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	room.enemies[0].intent = make_wait_intent(&room, room.enemies[0].position)
	_, exhausted := exhaust_hand_card(&player.deck, 0)
	testing.expect(t, exhausted)

	refocus := refocus_player_hand(&room)

	testing.expect_value(t, refocus.result, Refocus_Result.Refocused)
	testing.expect_value(t, refocus.hand_report.outcome_count, 0)
	testing.expect_value(t, refocus.drawn_count, 0)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect_value(t, room.recent_events.count, 2)
	testing.expect_value(t, room.recent_events.events[0].kind, Game_Event_Kind.Hand_Refocused)
	testing.expect_value(t, room.recent_events.events[0].amount, i32(0))
	testing.expect_value(t, room.recent_events.events[1].kind, Game_Event_Kind.Pulse_Advanced)
}
