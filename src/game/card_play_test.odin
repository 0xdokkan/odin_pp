package game

import "core:testing"
import grid "../grid"
import level "../level"

configure_test_deck :: proc(
	t: ^testing.T,
	player: ^Player,
	definitions: []Card_Id,
	rules: Deck_Rules,
) {
	testing.expect(t, player != nil)
	testing.expect(t, initialize_empty_deck(&player.deck, rules, 99))
	for definition_id in definitions {
		_, added := add_owned_card(&player.deck, definition_id)
		testing.expect(t, added)
	}
	testing.expect(t, validate_deck_state(&player.deck))
}

hand_card_id_for_definition :: proc(
	t: ^testing.T,
	deck: ^Deck_State,
	definition_id: Card_Id,
) -> u32 {
	for index in 0..<deck.hand_count {
		if deck.hand[index].definition_id == definition_id {
			return deck.hand[index].id
		}
	}
	testing.expectf(t, false, "definition %v was not present in hand", definition_id)
	return 0
}

force_card_definition_into_hand :: proc(
	t: ^testing.T,
	deck: ^Deck_State,
	definition_id: Card_Id,
) -> u32 {
	if card_id := hand_card_id_for_definition_if_present(deck, definition_id); card_id != 0 {
		return card_id
	}
	for index in 0..<deck.draw_count {
		if deck.draw_pile[index].definition_id == definition_id {
			deck.hand[0], deck.draw_pile[index] = deck.draw_pile[index], deck.hand[0]
			testing.expect(t, validate_deck_state(deck))
			return deck.hand[0].id
		}
	}
	testing.expectf(t, false, "definition %v was not present in combat zones", definition_id)
	return 0
}

hand_card_id_for_definition_if_present :: proc(deck: ^Deck_State, definition_id: Card_Id) -> u32 {
	if deck == nil {
		return 0
	}
	for index in 0..<deck.hand_count {
		if deck.hand[index].definition_id == definition_id {
			return deck.hand[index].id
		}
	}
	return 0
}

@(test)
test_invalid_card_target_does_not_mutate_deck_or_room :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	definitions := [?]Card_Id{.Strike}
	configure_test_deck(t, &player, definitions[:], {
		hand_size = 1,
		max_energy = 3,
		energy_regen_per_pulse = 1,
	})
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 6, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	card_id := player.deck.hand[0].id
	deck_before := player.deck
	enemy_before := room.enemies[0]

	play := play_card(&room, card_id, entity_target(enemy_entity(enemy_before.id)))

	testing.expect_value(t, play.result, Card_Play_Result.Compile_Failed)
	testing.expect_value(t, play.compile_error, Card_Compile_Error.Target_Out_Of_Range)
	testing.expect_value(t, player.deck, deck_before)
	testing.expect_value(t, room.enemies[0], enemy_before)
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect_value(t, room.recent_events.count, 0)
}

@(test)
test_blocked_line_of_sight_does_not_commit_card :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	definitions := [?]Card_Id{.Arc_Bolt}
	configure_test_deck(t, &player, definitions[:], {
		hand_size = 1,
		max_energy = 3,
		energy_regen_per_pulse = 1,
	})
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 4, y = 1}, health = 6, attack = 1}}
	obstacles := [?]grid.Position{{x = 3, y = 1}}
	room, ok := create_room(&level_data, &player, {
		enemies = enemy_spawns[:],
		obstacles = obstacles[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)
	card_id := player.deck.hand[0].id
	deck_before := player.deck
	enemy_before := room.enemies[0]

	play := play_card(&room, card_id, entity_target(enemy_entity(enemy_before.id)))

	testing.expect_value(t, play.result, Card_Play_Result.Compile_Failed)
	testing.expect_value(t, play.compile_error, Card_Compile_Error.Target_Blocked)
	testing.expect_value(t, player.deck, deck_before)
	testing.expect_value(t, room.enemies[0], enemy_before)
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect_value(t, room.recent_events.count, 0)
}

@(test)
test_insufficient_energy_does_not_pay_or_discard_card :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	definitions := [?]Card_Id{.Guard}
	configure_test_deck(t, &player, definitions[:], {
		hand_size = 1,
		max_energy = 3,
		energy_regen_per_pulse = 1,
	})
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 6, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	player.deck.energy = 0
	deck_before := player.deck

	play := play_card(&room, player.deck.hand[0].id, entity_target(PLAYER_ENTITY))

	testing.expect_value(t, play.result, Card_Play_Result.Not_Enough_Energy)
	testing.expect_value(t, player.deck, deck_before)
	_, has_shield := status_for_entity(&room, PLAYER_ENTITY, .Shield)
	testing.expect(t, !has_shield)
	testing.expect_value(t, room.pulse_count, u64(0))
}

@(test)
test_successful_card_play_pays_resolves_pulses_and_draws :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	definitions := [?]Card_Id{.Guard, .Strike, .Afterimage}
	configure_test_deck(t, &player, definitions[:], {
		hand_size = 3,
		max_energy = 3,
		energy_regen_per_pulse = 1,
	})
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 8, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	card_id := hand_card_id_for_definition(t, &player.deck, .Guard)

	play := play_card(&room, card_id, entity_target(PLAYER_ENTITY))

	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect(t, card_play_was_committed(play.result))
	testing.expect(t, play.action_report.accepted)
	testing.expect(t, play.pulse_report.advanced)
	testing.expect_value(t, play.cost, i32(1))
	testing.expect_value(t, play.energy_before, i32(3))
	testing.expect_value(t, play.energy_after, i32(3))
	testing.expect(t, play.drew_card)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect_value(t, player.deck.hand_count, 3)
	testing.expect(t, validate_deck_state(&player.deck))
	shield, has_shield := status_for_entity(&room, PLAYER_ENTITY, .Shield)
	testing.expect(t, has_shield)
	testing.expect_value(t, shield.potency, i32(3))
	testing.expect_value(t, shield.remaining_pulses, i32(2))
	testing.expect_value(t, room.recent_events.events[0].kind, Game_Event_Kind.Card_Played)
	testing.expect_value(t, room.recent_events.events[0].card_id, card_id)
	testing.expect_value(t, room.recent_events.events[2].kind, Game_Event_Kind.Card_Moved)
	testing.expect_value(t, room.recent_events.events[2].from_card_zone, Card_Zone.Resolving)
	testing.expect_value(t, room.recent_events.events[2].to_card_zone, Card_Zone.Discard)
	testing.expect_value(t, room.recent_events.events[room.recent_events.count-1].kind, Game_Event_Kind.Card_Drawn)
}

@(test)
test_area_card_play_damages_only_footprint_and_advances_one_pulse :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	definitions := [?]Card_Id{.Firebomb}
	configure_test_deck(t, &player, definitions[:], {
		hand_size = 1,
		max_energy = 3,
		energy_regen_per_pulse = 1,
	})
	enemy_spawns := [?]Enemy_Spawn{
		{position = {x = 4, y = 1}, health = 8, attack = 1},
		{position = {x = 2, y = 2}, health = 8, attack = 1},
		{position = {x = 5, y = 3}, health = 8, attack = 1},
	}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	card_id := player.deck.hand[0].id

	play := play_card(&room, card_id, cell_target({x = 3, y = 1}))

	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, play.card.definition_id, Card_Id.Firebomb)
	testing.expect_value(t, play.action_report.applied_effects, 2)
	testing.expect_value(t, play.action_report.events.count, 4)
	testing.expect_value(t, play.action_report.events.events[0].kind, Game_Event_Kind.Spell_Launched)
	testing.expect_value(t, play.action_report.events.events[1].kind, Game_Event_Kind.Spell_Impact)
	testing.expect_value(t, play.action_report.events.events[2].target, enemy_entity(1))
	testing.expect_value(t, play.action_report.events.events[3].target, enemy_entity(2))
	testing.expect(t, play.pulse_report.advanced)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect_value(t, player.deck.energy, i32(2))
	testing.expect(t, play.drew_card)

	inside_index, inside_found := enemy_index_by_id(&room, 1)
	second_inside_index, second_inside_found := enemy_index_by_id(&room, 2)
	outside_index, outside_found := enemy_index_by_id(&room, 3)
	testing.expect(t, inside_found)
	testing.expect(t, second_inside_found)
	testing.expect(t, outside_found)
	testing.expect_value(t, room.enemies[inside_index].health, i32(6))
	testing.expect_value(t, room.enemies[second_inside_index].health, i32(6))
	testing.expect_value(t, room.enemies[outside_index].health, i32(8))
}

@(test)
test_energy_costs_accumulate_between_pulses :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	definitions := [?]Card_Id{.Toxic_Wave}
	configure_test_deck(t, &player, definitions[:], {
		hand_size = 1,
		max_energy = 3,
		energy_regen_per_pulse = 1,
	})
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 20, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	first := play_card(&room, player.deck.hand[0].id, {})
	testing.expect_value(t, first.result, Card_Play_Result.Played)
	testing.expect_value(t, player.deck.energy, i32(2))
	second := play_card(&room, player.deck.hand[0].id, {})
	testing.expect_value(t, second.result, Card_Play_Result.Played)
	testing.expect_value(t, player.deck.energy, i32(1))
	deck_before := player.deck
	third := play_card(&room, player.deck.hand[0].id, {})
	testing.expect_value(t, third.result, Card_Play_Result.Not_Enough_Energy)
	testing.expect_value(t, player.deck, deck_before)
	testing.expect_value(t, room.pulse_count, u64(2))
}

@(test)
test_card_that_ends_combat_commits_without_extra_pulse :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	definitions := [?]Card_Id{.Strike}
	configure_test_deck(t, &player, definitions[:], {
		hand_size = 1,
		max_energy = 3,
		energy_regen_per_pulse = 1,
	})
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 2, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	card_id := player.deck.hand[0].id
	enemy_ref := enemy_entity(room.enemies[0].id)

	play := play_card(&room, card_id, entity_target(enemy_ref))

	testing.expect_value(t, play.result, Card_Play_Result.Combat_Ended)
	testing.expect(t, card_play_was_committed(play.result))
	testing.expect(t, !play.pulse_report.advanced)
	testing.expect_value(t, room.phase, Room_Phase.Loot)
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect_value(t, player.gold, i32(1))
	testing.expect(t, !player.deck.combat_active)
	testing.expect_value(t, player.deck.hand_count, 0)
	testing.expect_value(t, player.deck.owned_count, 1)
	testing.expect(t, validate_deck_state(&player.deck))
}

@(test)
test_battle_focus_draws_before_moving_to_exhaust :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	definitions := [?]Card_Id{
		.Battle_Focus,
		.Strike,
		.Guard,
		.Afterimage,
		.Arc_Bolt,
		.Thorn_Coat,
	}
	configure_test_deck(t, &player, definitions[:], {
		hand_size = 3,
		max_energy = 3,
		energy_regen_per_pulse = 1,
	})
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 12, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	card_id := force_card_definition_into_hand(t, &player.deck, .Battle_Focus)

	play := play_card(&room, card_id, entity_target(PLAYER_ENTITY))

	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, play.destination, Card_Zone.Exhaust)
	testing.expect_value(t, play.action_report.cards_drawn, 2)
	testing.expect_value(t, play.action_report.events.count, 2)
	testing.expect_value(t, player.deck.exhaust_count, 1)
	testing.expect_value(t, player.deck.exhaust_pile[0].id, card_id)
	testing.expect(t, play.drew_card)
	testing.expect_value(t, player.deck.hand_count, 5)
	testing.expect_value(t, player.deck.discard_count, 0)
	testing.expect(t, !player.deck.has_resolving_card)
	_, battle_focus_in_hand := hand_card_index_by_id(&player.deck, card_id)
	testing.expect(t, !battle_focus_in_hand)
	testing.expect(t, validate_deck_state(&player.deck))

	testing.expect_value(t, room.recent_events.events[0].kind, Game_Event_Kind.Card_Played)
	testing.expect_value(t, room.recent_events.events[1].kind, Game_Event_Kind.Card_Drawn)
	testing.expect_value(t, room.recent_events.events[2].kind, Game_Event_Kind.Card_Drawn)
	testing.expect_value(t, room.recent_events.events[3].kind, Game_Event_Kind.Card_Moved)
	testing.expect_value(t, room.recent_events.events[3].from_card_zone, Card_Zone.Resolving)
	testing.expect_value(t, room.recent_events.events[3].to_card_zone, Card_Zone.Exhaust)
}

@(test)
test_calculated_risk_draws_then_discards_the_leftmost_remaining_card :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	definitions := [?]Card_Id{
		.Calculated_Risk,
		.Strike,
		.Guard,
		.Afterimage,
		.Arc_Bolt,
		.Thorn_Coat,
		.Counter_Rune,
	}
	configure_test_deck(t, &player, definitions[:], {
		hand_size = 3,
		max_energy = 3,
		energy_regen_per_pulse = 1,
	})
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 12, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	card_id := force_card_definition_into_hand(t, &player.deck, .Calculated_Risk)
	played_index, found := hand_card_index_by_id(&player.deck, card_id)
	testing.expect(t, found)
	expected_discard_id := player.deck.hand[0].id
	if played_index == 0 {
		expected_discard_id = player.deck.hand[1].id
	}

	play := play_card(&room, card_id, entity_target(PLAYER_ENTITY))

	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, play.destination, Card_Zone.Discard)
	testing.expect_value(t, play.action_report.cards_drawn, 2)
	testing.expect_value(t, play.action_report.cards_discarded, 1)
	testing.expect_value(t, play.action_report.events.count, 3)
	testing.expect_value(t, play.action_report.events.events[0].kind, Game_Event_Kind.Card_Drawn)
	testing.expect_value(t, play.action_report.events.events[1].kind, Game_Event_Kind.Card_Drawn)
	discard_event := play.action_report.events.events[2]
	testing.expect_value(t, discard_event.kind, Game_Event_Kind.Card_Moved)
	testing.expect_value(t, discard_event.card_id, expected_discard_id)
	testing.expect_value(t, discard_event.from_card_zone, Card_Zone.Hand)
	testing.expect_value(t, discard_event.to_card_zone, Card_Zone.Discard)
	testing.expect_value(t, player.deck.discard_count, 2)
	testing.expect_value(t, player.deck.discard_pile[0].id, expected_discard_id)
	testing.expect_value(t, player.deck.discard_pile[1].id, card_id)
	testing.expect_value(t, player.deck.hand_count, 4)
	testing.expect(t, validate_deck_state(&player.deck))
}

@(test)
test_spark_forge_creates_a_temporary_card_that_exhausts_on_play :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	definitions := [?]Card_Id{.Spark_Forge, .Strike, .Guard, .Afterimage, .Thorn_Coat}
	configure_test_deck(t, &player, definitions[:], {
		hand_size = 3,
		max_energy = 3,
		energy_regen_per_pulse = 1,
	})
	enemy_spawns := [?]Enemy_Spawn{{
		position = {x = 3, y = 1},
		health = 12,
		attack = 1,
		archetype = .Chaser,
	}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	forge_id := force_card_definition_into_hand(t, &player.deck, .Spark_Forge)
	next_id_before := player.deck.next_card_id

	forge_play := play_card(&room, forge_id, entity_target(PLAYER_ENTITY))

	testing.expect_value(t, forge_play.result, Card_Play_Result.Played)
	testing.expect_value(t, forge_play.action_report.cards_created, 1)
	testing.expect_value(t, player.deck.next_card_id, next_id_before+1)
	spark_id := hand_card_id_for_definition(t, &player.deck, .Spark)
	spark_index, spark_found := hand_card_index_by_id(&player.deck, spark_id)
	testing.expect(t, spark_found)
	testing.expect_value(t, player.deck.hand[spark_index].lifetime, Card_Lifetime.Combat)
	create_event := forge_play.action_report.events.events[0]
	testing.expect_value(t, create_event.kind, Game_Event_Kind.Card_Created)
	testing.expect_value(t, create_event.card_id, spark_id)
	testing.expect_value(t, create_event.card_lifetime, Card_Lifetime.Combat)

	enemy_ref := enemy_entity(room.enemies[0].id)
	health_before := room.enemies[0].health
	spark_play := play_card(&room, spark_id, entity_target(enemy_ref))

	testing.expect_value(t, spark_play.result, Card_Play_Result.Played)
	testing.expect_value(t, spark_play.cost, i32(0))
	testing.expect_value(t, spark_play.destination, Card_Zone.Exhaust)
	testing.expect_value(t, room.enemies[0].health, health_before-2)
	testing.expect(t, player.deck.exhaust_count > 0)
	testing.expect_value(t, player.deck.exhaust_pile[player.deck.exhaust_count-1].id, spark_id)
	testing.expect(t, validate_deck_state(&player.deck))
}

@(test)
test_deck_effect_rejection_restores_resolving_card_and_energy :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	definitions := [?]Card_Id{.Calculated_Risk}
	configure_test_deck(t, &player, definitions[:], {
		hand_size = 1,
		max_energy = 3,
		energy_regen_per_pulse = 1,
	})
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 12, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	card_id := player.deck.hand[0].id
	deck_before := player.deck

	play := play_card(&room, card_id, entity_target(PLAYER_ENTITY))

	testing.expect_value(t, play.result, Card_Play_Result.Action_Rejected)
	testing.expect_value(t, player.deck, deck_before)
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect_value(t, room.recent_events.count, 0)
}
