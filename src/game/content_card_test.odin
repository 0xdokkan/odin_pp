package game

import "core:testing"
import grid "../grid"
import level "../level"

CONTENT_CARD_IDS :: [?]Card_Id{
	.Heavy_Blow,
	.Venom_Needle,
	.Caustic_Bloom,
	.Purifying_Guard,
	.Volatile_Study,
}

@(test)
test_content_card_definitions_are_valid_collectible_and_append_only :: proc(t: ^testing.T) {
	testing.expect(t, validate_card_definitions())
	testing.expect_value(t, int(Card_Id.Heavy_Blow), int(Card_Id.Grappling_Hook)+1)
	testing.expect_value(t, int(Card_Id.Volatile_Study), int(Card_Id.Fate_Strike)-1)

	node := Run_Node{kind = .Combat, depth = 0}
	for id in CONTENT_CARD_IDS {
		definition, found := card_definition_by_id(id)
		testing.expect(t, found)
		testing.expect(t, found && validate_card_definition(&definition))
		testing.expect(t, !definition.temporary_only)
		testing.expect(t, card_offer_weight(definition, &node) > 0)
	}

	heavy, heavy_found := card_definition_by_id(.Heavy_Blow)
	testing.expect(t, heavy_found)
	testing.expect_value(t, heavy.rarity, Card_Rarity.Common)
	testing.expect_value(t, heavy.reward_weight, u32(85))
	testing.expect_value(t, heavy.shop_base_price, i32(4))
	testing.expect_value(t, heavy.cost, i32(2))
	testing.expect_value(t, heavy.targeting.rule, Target_Rule.Adjacent_Opponent)
	testing.expect_value(t, heavy.targeting.cast_range, Targeting_Range{.Manhattan, 1, 1})
	testing.expect_value(t, heavy.effects[0].base_amount, i32(5))
	testing.expect_value(t, heavy.effects[0].amount_per_upgrade, i32(1))

	needle, needle_found := card_definition_by_id(.Venom_Needle)
	testing.expect(t, needle_found)
	testing.expect_value(t, needle.rarity, Card_Rarity.Common)
	testing.expect_value(t, needle.reward_weight, u32(85))
	testing.expect_value(t, needle.shop_base_price, i32(4))
	testing.expect_value(t, needle.cost, i32(1))
	testing.expect_value(t, needle.targeting.cast_range, Targeting_Range{.Chebyshev, 1, 3})
	testing.expect(t, needle.targeting.requires_line_of_sight && needle.targeting.stops_on_wall)
	testing.expect_value(t, needle.effects[0].kind, Effect_Kind.Damage)
	testing.expect_value(t, needle.effects[1].kind, Effect_Kind.Apply_Status)
	testing.expect_value(t, needle.effects[1].status, Status_Kind.Poison)
	testing.expect_value(t, needle.effects[1].duration, i32(0))

	bloom, bloom_found := card_definition_by_id(.Caustic_Bloom)
	testing.expect(t, bloom_found)
	testing.expect_value(t, bloom.rarity, Card_Rarity.Uncommon)
	testing.expect_value(t, bloom.reward_weight, u32(70))
	testing.expect_value(t, bloom.shop_base_price, i32(6))
	testing.expect_value(t, bloom.cost, i32(2))
	testing.expect_value(t, bloom.targeting.shape, Target_Shape.Square)
	testing.expect_value(t, bloom.targeting.radius, 1)
	testing.expect_value(t, bloom.effects[0].target, Card_Target_Selector.Each_Affected_Enemy)

	guard, guard_found := card_definition_by_id(.Purifying_Guard)
	testing.expect(t, guard_found)
	testing.expect_value(t, guard.rarity, Card_Rarity.Uncommon)
	testing.expect_value(t, guard.reward_weight, u32(80))
	testing.expect_value(t, guard.shop_base_price, i32(5))
	testing.expect_value(t, guard.cost, i32(1))
	testing.expect_value(t, guard.effects[0].status, Status_Kind.Shield)
	testing.expect_value(t, guard.effects[1].kind, Effect_Kind.Remove_Status)
	testing.expect_value(t, guard.effects[1].status, Status_Kind.Poison)

	study, study_found := card_definition_by_id(.Volatile_Study)
	testing.expect(t, study_found)
	testing.expect_value(t, study.rarity, Card_Rarity.Rare)
	testing.expect_value(t, study.reward_weight, u32(60))
	testing.expect_value(t, study.shop_base_price, i32(8))
	testing.expect_value(t, study.cost, i32(2))
	testing.expect(t, study.exhaust_on_play && study.ethereal)
	testing.expect_value(t, study.effects[0].kind, Effect_Kind.Create_Card)
	testing.expect_value(t, study.effects[0].card_definition, Card_Id.Spark)
	testing.expect_value(t, study.effects[1].kind, Effect_Kind.Draw_Cards)
}

@(test)
test_heavy_blow_and_venom_needle_compile_targets_scaling_and_order :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{
		{position = {x = 2, y = 1}, health = 20, attack = 1},
		{position = {x = 4, y = 1}, health = 20, attack = 1},
	}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	heavy_target := enemy_entity(room.enemies[0].id)
	heavy_action, heavy_error := compile_card_action(
		&room,
		{id = 201, definition_id = .Heavy_Blow, upgrade_level = 3},
		entity_target(heavy_target),
	)
	testing.expect_value(t, heavy_error, Card_Compile_Error.None)
	testing.expect_value(t, heavy_action.effect_count, 1)
	testing.expect_value(t, heavy_action.effects[0], damage_effect(heavy_target, 8))

	needle_target := enemy_entity(room.enemies[1].id)
	needle_action, needle_error := compile_card_action(
		&room,
		{id = 202, definition_id = .Venom_Needle, upgrade_level = 2},
		entity_target(needle_target),
	)
	testing.expect_value(t, needle_error, Card_Compile_Error.None)
	testing.expect_value(t, needle_action.effect_count, 2)
	testing.expect_value(t, needle_action.effects[0], damage_effect(needle_target, 3))
	testing.expect_value(
		t,
		needle_action.effects[1],
		apply_status_effect(needle_target, .Poison, 1, 0),
	)

	blocked_level := create_test_level(t)
	defer level.destroy(&blocked_level)
	blocked_player := create_test_player(t)
	blocked_enemies := [?]Enemy_Spawn{{position = {x = 4, y = 1}, health = 20, attack = 1}}
	obstacles := [?]grid.Position{{x = 3, y = 1}}
	blocked_room, blocked_ok := create_room(&blocked_level, &blocked_player, {
		enemies = blocked_enemies[:],
		obstacles = obstacles[:],
	})
	testing.expect(t, blocked_ok)
	defer destroy_room(&blocked_room)
	_, blocked_error := compile_card_action(
		&blocked_room,
		{id = 203, definition_id = .Venom_Needle},
		entity_target(enemy_entity(blocked_room.enemies[0].id)),
	)
	testing.expect_value(t, blocked_error, Card_Compile_Error.Target_Blocked)
}

@(test)
test_caustic_bloom_applies_upgraded_poison_only_inside_square :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{
		{position = {x = 2, y = 1}, health = 20, attack = 1},
		{position = {x = 4, y = 1}, health = 20, attack = 1},
		{position = {x = 2, y = 2}, health = 20, attack = 1},
		{position = {x = 5, y = 3}, health = 20, attack = 1},
	}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	outside := enemy_entity(room.enemies[3].id)

	action, compile_error := compile_card_action(
		&room,
		{id = 204, definition_id = .Caustic_Bloom, upgrade_level = 2},
		cell_target({x = 3, y = 1}),
	)
	testing.expect_value(t, compile_error, Card_Compile_Error.None)
	testing.expect_value(t, action.effect_count, 3)
	for index in 0..<action.effect_count {
		testing.expect_value(t, action.effects[index].kind, Effect_Kind.Apply_Status)
		testing.expect_value(t, action.effects[index].amount, i32(4))
		testing.expect_value(t, action.effects[index].duration, i32(0))
	}

	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted)
	testing.expect_value(t, report.statuses_applied, 3)
	for index in 0..<3 {
		poison, found := status_for_entity(&room, enemy_entity(room.enemies[index].id), .Poison)
		testing.expect(t, found)
		if found {
			testing.expect_value(t, poison.potency, i32(4))
			testing.expect_value(t, poison.remaining_pulses, i32(0))
		}
	}
	_, outside_poisoned := status_for_entity(&room, outside, .Poison)
	testing.expect(t, !outside_poisoned)
}

@(test)
test_purifying_guard_keeps_cleanse_optional_and_preserves_effect_order :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 20, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	clean_action, clean_error := compile_card_action(
		&room,
		{id = 205, definition_id = .Purifying_Guard, upgrade_level = 2},
		entity_target(PLAYER_ENTITY),
	)
	testing.expect_value(t, clean_error, Card_Compile_Error.None)
	testing.expect_value(t, clean_action.effects[0], apply_status_effect(PLAYER_ENTITY, .Shield, 4, 3))
	testing.expect_value(t, clean_action.effects[1], remove_status_effect(PLAYER_ENTITY, .Poison))
	clean_report := resolve_action(&room, &clean_action)
	testing.expect(t, clean_report.accepted)
	testing.expect_value(t, clean_report.applied_effects, 1)
	testing.expect_value(t, clean_report.skipped_effects, 1)

	_, shield_removed := remove_status(&room, PLAYER_ENTITY, .Shield)
	testing.expect(t, shield_removed)
	poison_applied, _ := apply_status(&room, PLAYER_ENTITY, .Poison, 3, 4)
	testing.expect(t, poison_applied)
	poisoned_action, poisoned_error := compile_card_action(
		&room,
		{id = 206, definition_id = .Purifying_Guard},
		entity_target(PLAYER_ENTITY),
	)
	testing.expect_value(t, poisoned_error, Card_Compile_Error.None)
	poisoned_report := resolve_action(&room, &poisoned_action)
	testing.expect(t, poisoned_report.accepted)
	testing.expect_value(t, poisoned_report.applied_effects, 2)
	testing.expect_value(t, poisoned_report.skipped_effects, 0)
	testing.expect_value(t, poisoned_report.events.events[0].kind, Game_Event_Kind.Status_Applied)
	testing.expect_value(t, poisoned_report.events.events[1].kind, Game_Event_Kind.Status_Removed)
	_, poison_found := status_for_entity(&room, PLAYER_ENTITY, .Poison)
	testing.expect(t, !poison_found)
}

@(test)
test_volatile_study_exhausts_creates_then_draws_with_upgrade :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	definitions := [?]Card_Id{.Volatile_Study, .Strike, .Guard, .Afterimage}
	configure_test_deck(t, &player, definitions[:], {
		hand_size = 1,
		max_energy = 3,
		energy_regen_per_pulse = 1,
	})
	for index in 0..<player.deck.owned_count {
		if player.deck.owned[index].definition_id == .Volatile_Study {
			player.deck.owned[index].upgrade_level = 2
		}
	}
	testing.expect(t, validate_deck_state(&player.deck))
	enemies := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 20, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	card_id := force_card_definition_into_hand(t, &player.deck, .Volatile_Study)

	play := play_card(&room, card_id, entity_target(PLAYER_ENTITY))

	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, play.destination, Card_Zone.Exhaust)
	testing.expect_value(t, play.action_report.cards_created, 1)
	testing.expect_value(t, play.action_report.cards_drawn, 3)
	testing.expect_value(t, play.action_report.events.events[0].kind, Game_Event_Kind.Card_Created)
	for index in 1..=3 {
		testing.expect_value(t, play.action_report.events.events[index].kind, Game_Event_Kind.Card_Drawn)
	}
	testing.expect_value(t, player.deck.exhaust_count, 1)
	testing.expect_value(t, player.deck.exhaust_pile[0].id, card_id)
	testing.expect(t, hand_card_id_for_definition_if_present(&player.deck, .Spark) != 0)
	testing.expect_value(t, combat_temporary_card_count(&player.deck), 1)
	testing.expect(t, validate_deck_state(&player.deck))
}
