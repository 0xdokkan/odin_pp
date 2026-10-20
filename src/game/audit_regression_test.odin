package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

@(test)
test_catalog_every_allowed_upgrade_changes_an_instantiated_effect :: proc(t: ^testing.T) {
	for definition in CARD_DEFINITIONS {
		if definition.id == .Count { continue }
		if definition.temporary_only {
			continue
		}
		for upgrade in i32(0)..<MAX_CARD_UPGRADE_LEVEL {
			card := Card_Instance{id = 1, definition_id = definition.id, upgrade_level = upgrade}
			upgraded := card
			upgraded.upgrade_level += 1
			changed := false
			for index in 0..<definition.effect_count {
				template := definition.effects[index]
				if template.kind == .Move {
					continue
				}
				before, before_ok := instantiate_card_effect(template, PLAYER_ENTITY, card)
				after, after_ok := instantiate_card_effect(template, PLAYER_ENTITY, upgraded)
				testing.expect(t, before_ok && after_ok)
				changed = changed || before != after
			}
			if card_dice_count(definition.id) > 0 {
				// A dice card's upgrade changes only its die, up to the D20.
				testing.expect(t, !changed, definition.name)
				testing.expect_value(t, card_can_upgrade(card), upgrade < MAX_DICE_UPGRADE_LEVEL)
				continue
			}
			// A card with its own top (the Lazzo's five) sells no level past it.
			testing.expect_value(t, card_can_upgrade(card), changed && upgrade < card_max_upgrade_level(definition.id))
		}
	}
	testing.expect(t, !card_can_upgrade({}))
	testing.expect(t, !card_can_upgrade({id = 1, definition_id = .Strike, upgrade_level = MAX_CARD_UPGRADE_LEVEL}))
	testing.expect(t, !card_can_upgrade({id = 1, definition_id = .Fate_Strike, upgrade_level = MAX_DICE_UPGRADE_LEVEL}))
	testing.expect(t, !validate_card_instance({id = 1, definition_id = .Fate_Strike, upgrade_level = MAX_DICE_UPGRADE_LEVEL+1}))
}

@(test)
test_dice_card_upgrade_services_stop_at_the_d20 :: proc(t: ^testing.T) {
	shop := create_shop_test_run(t)
	defer destroy_run(&shop)
	rest := create_special_node_test_run(t, .Rest)
	defer destroy_run(&rest)
	for definition in ([5]Card_Id{.Fate_Strike, .Shock_Floor, .Sundering_Blow, .Twin_Venom, .Prismatic_Barrage}) {
		deck: Deck_State
		testing.expect(t, initialize_empty_deck(&deck))
		card, added := add_owned_card(&deck, definition)
		testing.expect(t, added)
		for level in i32(1)..=MAX_DICE_UPGRADE_LEVEL {
			testing.expect_value(t, upgrade_owned_card(&deck, card.id), Deck_Mutation_Result.Upgraded)
			testing.expect_value(t, deck.owned[0].upgrade_level, level)
		}
		before := deck
		testing.expect_value(t, upgrade_owned_card(&deck, card.id), Deck_Mutation_Result.Maximum_Upgrade)
		testing.expect(t, deck == before)
		_, over := add_owned_card(&deck, definition, MAX_DICE_UPGRADE_LEVEL+1)
		testing.expect(t, !over)
		// Shop and rest refuse the D20 card without touching gold, deck or node.
		shop_card, shop_added := add_owned_card(&shop.player.deck, definition, MAX_DICE_UPGRADE_LEVEL)
		rest_card, rest_added := add_owned_card(&rest.player.deck, definition, MAX_DICE_UPGRADE_LEVEL)
		testing.expect(t, shop_added && rest_added)
		shop_before := capture_shop_test_snapshot(&shop)
		rest_before := capture_special_node_test_snapshot(&rest)
		_, has_price := shop_upgrade_price(&shop, shop_card.id)
		testing.expect(t, !has_price && !shop_upgrade_can_be_bought(&shop, shop_card.id))
		testing.expect_value(t, buy_shop_upgrade(&shop, shop_card.id), Shop_Result.Maximum_Upgrade)
		testing.expect_value(t, use_rest_upgrade(&rest, rest_card.id), Special_Node_Result.Maximum_Upgrade)
		expect_shop_test_snapshot(t, &shop, shop_before)
		expect_special_node_test_snapshot(t, &rest, rest_before)
	}
}

@(test)
test_no_op_upgrades_preserve_shop_and_rest_transactions :: proc(t: ^testing.T) {
	shop := create_shop_test_run(t)
	defer destroy_run(&shop)
	rest := create_special_node_test_run(t, .Rest)
	defer destroy_run(&rest)
	unchanged_cards := [?]Card_Id{.Battle_Focus, .Calculated_Risk, .Spark_Forge, .Dash}
	for definition in unchanged_cards {
		shop_card, shop_added := add_owned_card(&shop.player.deck, definition)
		rest_card, rest_added := add_owned_card(&rest.player.deck, definition)
		testing.expect(t, shop_added && rest_added)
		shop_before := capture_shop_test_snapshot(&shop)
		rest_before := capture_special_node_test_snapshot(&rest)
		testing.expect(t, !card_can_upgrade(shop_card))
		_, has_price := shop_upgrade_price(&shop, shop_card.id)
		testing.expect(t, !has_price && !shop_upgrade_can_be_bought(&shop, shop_card.id))
		testing.expect_value(t, buy_shop_upgrade(&shop, shop_card.id), Shop_Result.Upgrade_Unavailable)
		testing.expect_value(t, use_rest_upgrade(&rest, rest_card.id), Special_Node_Result.Upgrade_Unavailable)
		expect_shop_test_snapshot(t, &shop, shop_before)
		expect_special_node_test_snapshot(t, &rest, rest_before)
	}
}

@(test)
test_enemy_archetypes_detour_around_a_wall :: proc(t: ^testing.T) {
	rows := [?]string{"#######", "#.....#", "#.#@..#", "#...>.#", "#######"}
	level_data, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	defer level.destroy(&level_data)
	archetypes := [?]Enemy_Archetype{.Chaser, .Archer, .Brute}
	for archetype in archetypes {
		player := create_test_player(t)
		enemies := [?]Enemy_Spawn{{position = {1, 2}, health = 10, attack = 1, archetype = archetype}}
		room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
		testing.expect(t, ok)
		intent := room.enemies[0].intent
		testing.expect_value(t, intent.kind, Enemy_Intent_Kind.Move)
		testing.expect_value(t, intent.destination, grid.Position{1, 1})
		distances := raw_data(room.enemy_path_distances)
		for _ in 0..<5 {
			advance_combat_pulse(&room)
		}
		testing.expect(t, room.enemies[0].position != grid.Position{1, 2})
		testing.expect(t, raw_data(room.enemy_path_distances) == distances)
		if archetype == .Chaser {
			testing.expect(t, player.health < player.stats.max_health)
		}
		destroy_room(&room)
	}
}

@(test)
test_pathfinding_waits_when_disconnected_and_rebuilds_after_object_removal :: proc(t: ^testing.T) {
	rows := [?]string{"#######", "#@...>#", "#######"}
	level_data, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {4, 1}, health = 10, attack = 1}}
	objects := [?]Grid_Object_Spawn{{kind = .Ice_Block, position = {3, 1}}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:], objects = objects[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Wait)
	testing.expect(t, remove_grid_object(&room, 0))
	// La rimozione non cambia un intento committed.
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Wait)
	advance_combat_pulse(&room)
	testing.expect_value(t, room.enemies[0].position, grid.Position{4, 1})
	testing.expect_value(t, room.enemies[0].intent.destination, grid.Position{3, 1})
}

@(test)
test_resolve_action_does_not_grow_preallocated_loot :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{
		{position = {3, 1}, health = 1, attack = 1},
		{position = {4, 1}, health = 1, attack = 1, drops_healing = true},
		{position = {5, 1}, health = 1, attack = 1},
	}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	capacity := cap(room.loot)
	testing.expect(t, capacity >= 4)
	for len(room.enemies) > 0 {
		target := enemy_entity(room.enemies[0].id)
		action := make_action(.Card, PLAYER_ENTITY, entity_target(target), .Opponent)
		testing.expect(t, add_effect(&action, damage_effect(target, 10)))
		report := resolve_action(&room, &action)
		testing.expect(t, report.accepted)
	}
	testing.expect_value(t, len(room.loot), 4)
	testing.expect_value(t, cap(room.loot), capacity)
}
