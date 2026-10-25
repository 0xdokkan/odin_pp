package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

@(test)
test_move_action_rejects_invalid_cells_and_applies_valid_movement_once :: proc(t: ^testing.T) {
	Case :: struct {
		destination, expected_position: grid.Position,
		accepted: bool,
	}
	cases := [?]Case{
		{destination = {x = 0, y = 0}, expected_position = {x = 1, y = 1}, accepted = false},
		{destination = {x = 1, y = 2}, expected_position = {x = 1, y = 2}, accepted = true},
	}
	for c in cases {
		level_data := create_test_level(t)
		defer level.destroy(&level_data)
		player := create_test_player(t)
		enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 4, attack = 1}}
		room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
		testing.expect(t, ok)
		defer destroy_room(&room)

		action := make_action(.Move, PLAYER_ENTITY, cell_target(c.destination), .Walkable_Cell)
		testing.expect(t, add_effect(&action, move_effect(PLAYER_ENTITY, c.destination)))
		report := resolve_action(&room, &action)

		testing.expect_value(t, report.accepted, c.accepted)
		testing.expect_value(t, player.position, c.expected_position)
		testing.expect_value(t, report.applied_effects, 1 if c.accepted else 0)
		testing.expect_value(t, report.events.count, 1 if c.accepted else 0)
		if c.accepted {
			testing.expect_value(t, report.events.events[0].kind, Game_Event_Kind.Moved)
			testing.expect_value(t, report.events.events[0].target, PLAYER_ENTITY)
		}
	}
}

@(test)
test_damage_effect_uses_player_defense :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 4, attack = 4}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	enemy := room.enemies[0]
	action := make_action(.Attack, enemy_entity(enemy.id), entity_target(PLAYER_ENTITY), .Adjacent_Opponent)
	testing.expect(t, add_effect(&action, damage_effect(PLAYER_ENTITY, enemy.attack)))
	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	testing.expect_value(t, report.damage_dealt, i32(3))
	testing.expect_value(t, player.health, i32(7))
}

@(test)
test_effects_resolve_in_order_against_stable_enemy_ids :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{
		{position = {x = 2, y = 1}, health = 2, attack = 1},
		{position = {x = 4, y = 1}, health = 4, attack = 1},
	}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	first_id := room.enemies[0].id
	second_id := room.enemies[1].id

	action := make_action(.Ability, PLAYER_ENTITY, entity_target(enemy_entity(first_id)))
	testing.expect(t, add_effect(&action, damage_effect(enemy_entity(first_id), 2)))
	testing.expect(t, add_effect(&action, damage_effect(enemy_entity(first_id), 2)))
	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	testing.expect_value(t, report.applied_effects, 1)
	testing.expect_value(t, report.skipped_effects, 1)
	testing.expect_value(t, report.enemies_defeated, 1)
	testing.expect_value(t, len(room.enemies), 1)
	testing.expect_value(t, room.enemies[0].id, second_id)

	second_action := make_action(.Attack, PLAYER_ENTITY, entity_target(enemy_entity(second_id)))
	testing.expect(t, add_effect(&second_action, damage_effect(enemy_entity(second_id), 1)))
	second_report := resolve_action(&room, &second_action)
	testing.expect(t, second_report.accepted)
	testing.expect_value(t, room.enemies[0].health, i32(3))
}

@(test)
test_last_enemy_effect_reports_combat_end :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 2, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	enemy_id := room.enemies[0].id

	action := make_action(.Attack, PLAYER_ENTITY, entity_target(enemy_entity(enemy_id)))
	testing.expect(t, add_effect(&action, damage_effect(enemy_entity(enemy_id), 2)))
	report := resolve_action(&room, &action)

	testing.expect(t, report.combat_ended)
	testing.expect_value(t, report.enemies_defeated, 1)
	testing.expect_value(t, room.phase, Room_Phase.Loot)
	testing.expect_value(t, len(room.loot), 1)
}

@(test)
test_action_can_combine_healing_and_gold :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	player.health = 5
	room, ok := create_room(&level_data, &player, {})
	testing.expect(t, ok)
	defer destroy_room(&room)

	action := make_action(.Collect, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
	testing.expect(t, add_effect(&action, heal_effect(PLAYER_ENTITY, 3)))
	testing.expect(t, add_effect(&action, gain_gold_effect(4)))
	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	testing.expect_value(t, report.applied_effects, 2)
	testing.expect_value(t, report.healing_done, i32(3))
	testing.expect_value(t, report.gold_gained, i32(4))
	testing.expect_value(t, player.health, i32(8))
	testing.expect_value(t, player.gold, i32(4))
}

@(test)
test_invalid_action_source_cannot_apply_effects :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	room, ok := create_room(&level_data, &player, {})
	testing.expect(t, ok)
	defer destroy_room(&room)

	action := make_action(.Attack, enemy_entity(999), entity_target(PLAYER_ENTITY))
	testing.expect(t, add_effect(&action, damage_effect(PLAYER_ENTITY, 5)))
	report := resolve_action(&room, &action)

	testing.expect(t, !report.accepted)
	testing.expect_value(t, player.health, i32(10))
}

@(test)
test_wait_resolution_does_not_advance_the_scheduler :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 4, attack = 3}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	action := make_action(.Wait, PLAYER_ENTITY, {}, .None)
	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	testing.expect_value(t, report.applied_effects, 0)
	testing.expect_value(t, player.health, i32(10))
	testing.expect_value(t, room.enemies[0].position, grid.Position{x = 2, y = 1})
}

@(test)
test_action_effect_storage_has_a_fixed_capacity :: proc(t: ^testing.T) {
	action := make_action(.Ability, PLAYER_ENTITY)
	for _ in 0..<MAX_ACTION_EFFECTS {
		testing.expect(t, add_effect(&action, heal_effect(PLAYER_ENTITY, 1)))
	}
	testing.expect(t, !add_effect(&action, heal_effect(PLAYER_ENTITY, 1)))
	testing.expect_value(t, action.effect_count, MAX_ACTION_EFFECTS)
}

@(test)
test_target_rules_distinguish_melee_and_ranged_actions :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 4, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	enemy_id := room.enemies[0].id
	target := entity_target(enemy_entity(enemy_id))

	melee_action := make_action(.Attack, PLAYER_ENTITY, target, .Adjacent_Opponent)
	testing.expect(t, add_effect(&melee_action, damage_effect(enemy_entity(enemy_id), 1)))
	melee_report := resolve_action(&room, &melee_action)
	testing.expect(t, !melee_report.accepted)
	testing.expect_value(t, room.enemies[0].health, i32(4))

	ranged_action := make_action(.Ability, PLAYER_ENTITY, target, .Opponent)
	testing.expect(t, add_effect(&ranged_action, damage_effect(enemy_entity(enemy_id), 1)))
	ranged_report := resolve_action(&room, &ranged_action)
	testing.expect(t, ranged_report.accepted)
	testing.expect_value(t, room.enemies[0].health, i32(3))
}

@(test)
test_draw_cards_effect_draws_up_to_capacity_and_reports_each_card :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 4, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	expected_deck := player.deck
	expected_cards: [MAX_HAND_CARDS]Card_Instance
	expected_count := 0
	for can_draw_card(&expected_deck) {
		card, drawn := draw_card(&expected_deck)
		testing.expect(t, drawn)
		expected_cards[expected_count] = card
		expected_count += 1
	}
	testing.expect(t, expected_count > 0)

	action := make_action(.Ability, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
	testing.expect(t, add_effect(&action, draw_cards_effect(MAX_HAND_CARDS)))
	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	testing.expect_value(t, report.applied_effects, 1)
	testing.expect_value(t, report.cards_drawn, expected_count)
	testing.expect_value(t, report.events.count, expected_count)
	testing.expect_value(t, player.deck, expected_deck)
	for index in 0..<expected_count {
		event := report.events.events[index]
		testing.expect_value(t, event.kind, Game_Event_Kind.Card_Drawn)
		testing.expect_value(t, event.card_id, expected_cards[index].id)
		testing.expect_value(t, event.card_definition, expected_cards[index].definition_id)
		testing.expect_value(t, event.card_lifetime, expected_cards[index].lifetime)
		testing.expect_value(t, event.from_card_zone, Card_Zone.Draw)
		testing.expect_value(t, event.to_card_zone, Card_Zone.Hand)
	}
}

@(test)
test_discard_cards_effect_uses_stable_hand_order_and_reports_moves :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 4, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	expected_first := player.deck.hand[0]
	expected_second := player.deck.hand[1]
	expected_deck := player.deck
	_, first_discarded := discard_hand_card(&expected_deck, 0)
	_, second_discarded := discard_hand_card(&expected_deck, 0)
	testing.expect(t, first_discarded && second_discarded)

	action := make_action(.Ability, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
	testing.expect(t, add_effect(&action, discard_cards_effect(2)))
	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	testing.expect_value(t, report.cards_discarded, 2)
	testing.expect_value(t, report.events.count, 2)
	testing.expect_value(t, player.deck, expected_deck)
	expected_cards := [?]Card_Instance{expected_first, expected_second}
	for card, index in expected_cards {
		event := report.events.events[index]
		testing.expect_value(t, event.kind, Game_Event_Kind.Card_Moved)
		testing.expect_value(t, event.card_id, card.id)
		testing.expect_value(t, event.card_definition, card.definition_id)
		testing.expect_value(t, event.from_card_zone, Card_Zone.Hand)
		testing.expect_value(t, event.to_card_zone, Card_Zone.Discard)
	}
}

@(test)
test_create_card_effect_creates_combat_cards_up_to_hand_capacity :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 4, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	expected_deck := player.deck
	expected_cards: [MAX_HAND_CARDS]Card_Instance
	expected_count := 0
	for can_create_temporary_card(&expected_deck, .Spark) {
		card, created := create_temporary_card(&expected_deck, .Spark)
		testing.expect(t, created)
		expected_cards[expected_count] = card
		expected_count += 1
	}
	testing.expect(t, expected_count > 0)

	action := make_action(.Ability, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
	testing.expect(t, add_effect(&action, create_card_effect(.Spark, MAX_HAND_CARDS)))
	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	testing.expect_value(t, report.cards_created, expected_count)
	testing.expect_value(t, report.events.count, expected_count)
	testing.expect_value(t, player.deck, expected_deck)
	for index in 0..<expected_count {
		event := report.events.events[index]
		testing.expect_value(t, event.kind, Game_Event_Kind.Card_Created)
		testing.expect_value(t, event.card_id, expected_cards[index].id)
			testing.expect_value(t, event.card_definition, Card_Id.Spark)
			testing.expect_value(t, event.card_lifetime, Card_Lifetime.Combat)
			testing.expect_value(t, event.from_card_zone, Card_Zone.Count)
			testing.expect_value(t, event.to_card_zone, Card_Zone.Hand)
	}
}

@(test)
test_unavailable_deck_effect_rejects_without_mutation :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 4, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	deck_before := player.deck
	action := make_action(.Ability, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
	testing.expect(t, add_effect(&action, create_card_effect(.Count, 1)))
	report := resolve_action(&room, &action)

	testing.expect(t, !report.accepted)
	testing.expect_value(t, player.deck, deck_before)
	testing.expect_value(t, report.events.count, 0)
}
