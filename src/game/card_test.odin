package game

import "core:testing"
import grid "../grid"
import level "../level"

@(test)
test_builtin_card_definitions_are_valid :: proc(t: ^testing.T) {
	testing.expect(t, validate_card_definitions())
	// Keep persisted catalog boundaries stable when extending the enum.
	testing.expect_value(t, int(Card_Id.Heavy_Blow), int(Card_Id.Grappling_Hook)+1)
	testing.expect_value(t, int(Card_Id.Volatile_Study), int(Card_Id.Fate_Strike)-1)
	testing.expect_value(t, int(Card_Id.Chain_Lightning), int(Card_Id.Sundering_Blow)-1)

	definition, found := card_definition_by_id(.Strike)
	testing.expect(t, found)
	testing.expect_value(t, definition.cost, i32(1))
	testing.expect_value(t, definition.targeting.cast_range, Targeting_Range{.Manhattan, 1, 1})
	testing.expect_value(t, definition.targeting.shape, Target_Shape.Single)
	definition.effect_count = MAX_CARD_DEFINITION_EFFECTS+1
	testing.expect(t, !validate_card_definition(&definition))
	definition.effect_count = 1
	definition.targeting.cast_range.maximum = 0
	testing.expect(t, !validate_card_definition(&definition))

	definition, found = card_definition_by_id(.Strike)
	testing.expect(t, found)
	definition.targeting.rule = .Entity
	testing.expect(t, !validate_card_definition(&definition))

	definition, found = card_definition_by_id(.Guard)
	testing.expect(t, found)
	definition.effects[0].status = Status_Kind(99)
	testing.expect(t, !validate_card_definition(&definition))

	definition, found = card_definition_by_id(.Spark_Forge)
	testing.expect(t, found)
	definition.effects[0].has_card_definition = false
	testing.expect(t, !validate_card_definition(&definition))

	piercing_ray, piercing_ray_found := card_definition_by_id(.Piercing_Ray)
	testing.expect(t, piercing_ray_found)
	testing.expect_value(t, piercing_ray.targeting.shape, Target_Shape.Line)
	testing.expect_value(t, piercing_ray.effects[0].target, Card_Target_Selector.Each_Affected_Enemy)

	cross_slash, cross_slash_found := card_definition_by_id(.Cross_Slash)
	testing.expect(t, cross_slash_found)
	testing.expect_value(t, cross_slash.targeting.shape, Target_Shape.Cross)
	testing.expect_value(t, cross_slash.targeting.radius, 1)

	firebomb, firebomb_found := card_definition_by_id(.Firebomb)
	testing.expect(t, firebomb_found)
	testing.expect_value(t, firebomb.targeting.shape, Target_Shape.Square)
	testing.expect_value(t, firebomb.targeting.radius, 1)

	toxic_wave, toxic_wave_found := card_definition_by_id(.Toxic_Wave)
	testing.expect(t, toxic_wave_found)
	testing.expect_value(t, toxic_wave.targeting.rule, Target_Rule.None)
	testing.expect_value(t, toxic_wave.effects[0].target, Card_Target_Selector.Each_Enemy)

	battle_focus, battle_focus_found := card_definition_by_id(.Battle_Focus)
	testing.expect(t, battle_focus_found && battle_focus.exhaust_on_play && battle_focus.ethereal)
	testing.expect_value(t, battle_focus.effects[0].kind, Effect_Kind.Draw_Cards)
	testing.expect_value(t, battle_focus.effects[0].base_amount, i32(2))

	counter_rune, counter_rune_found := card_definition_by_id(.Counter_Rune)
	testing.expect(t, counter_rune_found && counter_rune.retain_on_refocus)

	calculated_risk, calculated_risk_found := card_definition_by_id(.Calculated_Risk)
	testing.expect(t, calculated_risk_found)
	testing.expect_value(t, calculated_risk.effect_count, 2)
	testing.expect_value(t, calculated_risk.effects[0].kind, Effect_Kind.Draw_Cards)
	testing.expect_value(t, calculated_risk.effects[1].kind, Effect_Kind.Discard_Cards)

	spark_forge, spark_forge_found := card_definition_by_id(.Spark_Forge)
	testing.expect(t, spark_forge_found)
	testing.expect_value(t, spark_forge.effects[0].kind, Effect_Kind.Create_Card)
	testing.expect_value(t, spark_forge.effects[0].card_definition, Card_Id.Spark)
	study, study_found := card_definition_by_id(.Volatile_Study)
	testing.expect(t, study_found && study.ethereal)

	spark, spark_found := card_definition_by_id(.Spark)
	testing.expect(t, spark_found && spark.temporary_only)
	testing.expect_value(t, spark.targeting.cast_range, Targeting_Range{.Manhattan, 1, 2})
	testing.expect(t, !validate_card_instance({id = 80, definition_id = .Spark}))
	testing.expect(t, validate_card_instance({
		id = 80,
		definition_id = .Spark,
		lifetime = .Combat,
	}))

	_, found = card_definition_by_id(.Count)
	testing.expect(t, !found)
}

@(test)
test_refocus_keywords_are_exclusive_and_ignore_play_lifecycle :: proc(t: ^testing.T) {
	counter_rune, counter_found := card_definition_by_id(.Counter_Rune)
	_, battle_found := card_definition_by_id(.Battle_Focus)
	strike, strike_found := card_definition_by_id(.Strike)
	testing.expect(t, counter_found && battle_found && strike_found)

	invalid := counter_rune
	invalid.ethereal = true
	testing.expect(t, !validate_card_definition(&invalid))
	destination, valid := card_definition_destination_after_refocus(invalid)
	testing.expect(t, !valid)
	testing.expect_value(t, destination, Card_Zone.Count)

	strike.exhaust_on_play = true
	testing.expect(t, validate_card_definition(&strike))
	destination, valid = card_definition_destination_after_refocus(strike)
	testing.expect(t, valid)
	testing.expect_value(t, destination, Card_Zone.Discard)

	destination, valid = card_destination_after_refocus({
		id = 1,
		definition_id = .Counter_Rune,
	})
	testing.expect(t, valid)
	testing.expect_value(t, destination, Card_Zone.Hand)
	destination, valid = card_destination_after_refocus({
		id = 2,
		definition_id = .Battle_Focus,
	})
	testing.expect(t, valid)
	testing.expect_value(t, destination, Card_Zone.Exhaust)
	destination, valid = card_destination_after_refocus({
		id = 3,
		definition_id = .Spark,
		lifetime = .Combat,
	})
	testing.expect(t, valid)
	testing.expect_value(t, destination, Card_Zone.Discard)

	destination, valid = card_destination_after_refocus({definition_id = .Strike})
	testing.expect(t, !valid)
	testing.expect_value(t, destination, Card_Zone.Count)
}

@(test)
test_card_economy_metadata_is_valid_and_covers_every_rarity :: proc(t: ^testing.T) {
	rarity_counts: [int(Card_Rarity.Count)]int
	for definition in CARD_DEFINITIONS {
		if definition.temporary_only {
			testing.expect_value(t, definition.reward_weight, u32(0))
			testing.expect_value(t, definition.shop_base_price, i32(0))
		} else {
			testing.expect(t, definition.reward_weight > 0)
			testing.expect(t, definition.shop_base_price > 0)
		}
		rarity_counts[int(definition.rarity)] += 1
	}
	for count in rarity_counts {
		testing.expect(t, count > 0)
	}
	// These additions must remain ordinary rewards, irrespective of tuning.
	node := Run_Node{kind = .Combat, depth = 0}
	for id in ([7]Card_Id{.Heavy_Blow, .Venom_Needle, .Caustic_Bloom, .Purifying_Guard, .Volatile_Study, .Fate_Strike, .Chain_Lightning}) {
		definition, found := card_definition_by_id(id)
		testing.expect(t, found && !definition.temporary_only)
		testing.expect(t, card_offer_weight(definition, &node) > 0)
	}

	definition, found := card_definition_by_id(.Strike)
	testing.expect(t, found)
	definition.rarity = .Count
	testing.expect(t, !validate_card_definition(&definition))

	definition, found = card_definition_by_id(.Strike)
	testing.expect(t, found)
	definition.reward_weight = 0
	testing.expect(t, !validate_card_definition(&definition))

	definition, found = card_definition_by_id(.Strike)
	testing.expect(t, found)
	definition.shop_base_price = 0
	testing.expect(t, !validate_card_definition(&definition))

	spark, spark_found := card_definition_by_id(.Spark)
	testing.expect(t, spark_found && spark.temporary_only)
	testing.expect(t, validate_card_definition(&spark))
	spark.reward_weight = 1
	testing.expect(t, !validate_card_definition(&spark))
}

@(test)
test_card_rarity_weights_scale_with_depth_and_node_kind :: proc(t: ^testing.T) {
	early_combat, ok := card_rarity_weights(.Combat, 0)
	testing.expect(t, ok)
	testing.expect_value(t, early_combat, Card_Rarity_Weights{common = 70, uncommon = 25, rare = 5})

	deep_combat, deep_ok := card_rarity_weights(.Combat, MAX_CARD_OFFER_DEPTH)
	testing.expect(t, deep_ok)
	testing.expect_value(t, deep_combat, Card_Rarity_Weights{common = 22, uncommon = 49, rare = 29})
	clamped_combat, clamped_ok := card_rarity_weights(.Combat, MAX_CARD_OFFER_DEPTH+100)
	testing.expect(t, clamped_ok)
	testing.expect_value(t, clamped_combat, deep_combat)

	early_elite, elite_ok := card_rarity_weights(.Elite, 0)
	testing.expect(t, elite_ok)
	testing.expect_value(t, early_elite, Card_Rarity_Weights{common = 60, uncommon = 29, rare = 11})
	early_boss, boss_ok := card_rarity_weights(.Boss, 0)
	testing.expect(t, boss_ok)
	testing.expect_value(t, early_boss, Card_Rarity_Weights{common = 56, uncommon = 30, rare = 14})
	early_shop, shop_ok := card_rarity_weights(.Shop, 0)
	testing.expect(t, shop_ok)
	testing.expect_value(t, early_shop, Card_Rarity_Weights{common = 55, uncommon = 31, rare = 14})
	early_event, event_ok := card_rarity_weights(.Event, 0)
	testing.expect(t, event_ok)
	testing.expect_value(t, early_event, Card_Rarity_Weights{common = 65, uncommon = 28, rare = 7})

	testing.expect(t, deep_combat.common < early_combat.common)
	testing.expect(t, deep_combat.uncommon > early_combat.uncommon)
	testing.expect(t, deep_combat.rare > early_combat.rare)
	testing.expect(t, early_elite.rare > early_combat.rare)
	testing.expect(t, early_boss.rare > early_elite.rare)
	testing.expect_value(t, card_rarity_weight(early_combat, .Common), early_combat.common)
	testing.expect_value(t, card_rarity_weight(early_combat, .Uncommon), early_combat.uncommon)
	testing.expect_value(t, card_rarity_weight(early_combat, .Rare), early_combat.rare)
	testing.expect_value(t, card_rarity_weight(early_combat, .Count), u32(0))

	_, ok = card_rarity_weights(.Combat, -1)
	testing.expect(t, !ok)
	_, ok = card_rarity_weights(.Rest, 0)
	testing.expect(t, !ok)
	_, ok = card_rarity_weights(.Treasure, 0)
	testing.expect(t, !ok)
	_, ok = card_rarity_weights(Node_Kind(99), 0)
	testing.expect(t, !ok)
}

@(test)
test_weighted_card_choices_are_deterministic_distinct_and_transactional_on_rejection :: proc(t: ^testing.T) {
	node := Run_Node{kind = .Combat, depth = 0}
	strike, strike_found := card_definition_by_id(.Strike)
	firebomb, firebomb_found := card_definition_by_id(.Firebomb)
	testing.expect(t, strike_found && firebomb_found)
	testing.expect_value(t, card_offer_weight(strike, &node), u64(70*100))
	testing.expect_value(t, card_offer_weight(firebomb, &node), u64(5*75))
	testing.expect_value(t, card_offer_weight(strike, nil), u64(0))
	spark, spark_found := card_definition_by_id(.Spark)
	testing.expect(t, spark_found)
	testing.expect_value(t, card_offer_weight(spark, &node), u64(0))

	first_state := u64(0xA11CE)
	second_state := first_state
	first: [3]Card_Id
	second: [3]Card_Id
	testing.expect(t, generate_weighted_card_choices(&first_state, &node, first[:]))
	testing.expect(t, generate_weighted_card_choices(&second_state, &node, second[:]))
	testing.expect_value(t, first_state, second_state)
	testing.expect_value(t, first, second)
	for choice, index in first {
		_, found := card_definition_by_id(choice)
		testing.expect(t, found)
		testing.expect(t, choice != .Spark)
		for previous in 0..<index {
			testing.expect(t, choice != first[previous])
		}
	}

	invalid_node := Run_Node{kind = Node_Kind(99), depth = 0}
	rejected_state := u64(0xBADC0DE)
	rejected_choices := [3]Card_Id{.Firebomb, .Guard, .Strike}
	state_before := rejected_state
	choices_before := rejected_choices
	testing.expect(t, !generate_weighted_card_choices(
		&rejected_state,
		&invalid_node,
		rejected_choices[:],
	))
	testing.expect_value(t, rejected_state, state_before)
	testing.expect_value(t, rejected_choices, choices_before)

	zero_state: u64
	testing.expect(t, !generate_weighted_card_choices(&zero_state, &node, rejected_choices[:]))
	testing.expect_value(t, zero_state, u64(0))

	too_many_choices: [int(Card_Id.Count)]Card_Id
	for &choice in too_many_choices {
		choice = .Spark
	}
	too_many_before := too_many_choices
	too_many_state := u64(0xC011EC7)
	too_many_state_before := too_many_state
	testing.expect(t, !generate_weighted_card_choices(
		&too_many_state,
		&node,
		too_many_choices[:],
	))
	testing.expect_value(t, too_many_state, too_many_state_before)
	testing.expect_value(t, too_many_choices, too_many_before)
}

@(test)
test_card_drop_target_translates_cells_without_mutating_room :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 6, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	strike, found := card_definition_by_id(.Strike)
	testing.expect(t, found)
	target, has_target := card_drop_target(
		&room,
		{id = 1, definition_id = strike.id},
		room.enemies[0].position,
	)
	testing.expect(t, has_target)
	testing.expect_value(t, target, entity_target(enemy_entity(room.enemies[0].id)))
	_, has_target = card_drop_target(&room, {id = 1, definition_id = strike.id}, {x = 3, y = 1})
	testing.expect(t, !has_target)

	guard, guard_found := card_definition_by_id(.Guard)
	testing.expect(t, guard_found)
	target, has_target = card_drop_target(
		&room,
		{id = 2, definition_id = guard.id},
		{x = 3, y = 1},
	)
	testing.expect(t, has_target)
	testing.expect_value(t, target, entity_target(PLAYER_ENTITY))
}

@(test)
test_strike_card_compiles_upgrade_and_chosen_target :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 6, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	enemy_ref := enemy_entity(room.enemies[0].id)

	action, err := compile_card_action(&room, {
		id = 101,
		definition_id = .Strike,
		upgrade_level = 2,
	}, entity_target(enemy_ref))

	testing.expect_value(t, err, Card_Compile_Error.None)
	testing.expect_value(t, action.kind, Action_Kind.Card)
	testing.expect_value(t, action.target_rule, Target_Rule.Opponent_Or_Object)
	testing.expect_value(t, action.effect_count, 1)
	testing.expect_value(t, action.effects[0].target, enemy_ref)
	testing.expect_value(t, action.effects[0].amount, i32(5))
	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted)
	testing.expect_value(t, room.enemies[0].health, i32(1))
}

@(test)
test_card_compiler_rejects_invalid_instance_and_target :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 6, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	target := entity_target(enemy_entity(room.enemies[0].id))

	// Card validation precedes targeting in both entry points. Keep explicit
	// expected errors, rather than only checking preview/compiler agreement.
	for fixture in ([?]struct {card: Card_Instance, error: Card_Compile_Error}{
		{{definition_id = .Strike}, .Invalid_Instance},
		{{definition_id = .Count}, .Invalid_Instance},
		{{id = 1, definition_id = .Count}, .Unknown_Definition},
		{{id = 2, definition_id = .Spark, lifetime = .Permanent}, .Invalid_Instance},
		{{id = 3, definition_id = .Strike, lifetime = .Count}, .Invalid_Instance},
		{{id = 4, definition_id = .Strike, upgrade_level = -1}, .Invalid_Instance},
		{{id = 5, definition_id = .Fate_Strike, upgrade_level = MAX_DICE_UPGRADE_LEVEL+1}, .Invalid_Instance},
	}) {
		_, err := compile_card_action(&room, fixture.card, {})
		testing.expect_value(t, err, fixture.error)
		preview := evaluate_card_targeting(&room, fixture.card, {})
		testing.expect_value(t, preview.error, fixture.error)
	}

	_, err := compile_card_action(&room, {id = 1, definition_id = .Strike}, target)
	testing.expect_value(t, err, Card_Compile_Error.Target_Out_Of_Range)

	// An unresolved entity is rejected before the compiler checks mode rules;
	// the preview receives an anchor request and has no entity to resolve.
	lasso := Card_Instance{id = 6, definition_id = .Lasso}
	_, err = compile_card_action(&room, lasso, entity_target(enemy_entity(max(u32))))
	testing.expect_value(t, err, Card_Compile_Error.Invalid_Target)
	_, err = compile_card_action(&room, lasso, target)
	testing.expect_value(t, err, Card_Compile_Error.Invalid_Phase)
	preview := evaluate_card_targeting(&room, lasso, {})
	testing.expect_value(t, preview.error, Card_Compile_Error.Invalid_Phase)

	room.phase = .Loot
	_, err = compile_card_action(&room, {}, {})
	testing.expect_value(t, err, Card_Compile_Error.Invalid_Phase)
	preview = evaluate_card_targeting(&room, {}, {})
	testing.expect_value(t, preview.error, Card_Compile_Error.Invalid_Phase)
	_, err = compile_card_action(nil, {}, {})
	testing.expect_value(t, err, Card_Compile_Error.Invalid_Room)
	preview = evaluate_card_targeting(nil, {}, {})
	testing.expect_value(t, preview.error, Card_Compile_Error.Invalid_Room)
}

@(test)
test_arc_bolt_uses_targeting_range_and_helpers_support_diagonals :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{
		{position = {x = 4, y = 1}, health = 8, attack = 1},
		{position = {x = 5, y = 1}, health = 8, attack = 1},
	}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	in_range := entity_target(enemy_entity(room.enemies[0].id))
	action, err := compile_card_action(&room, {id = 8, definition_id = .Arc_Bolt}, in_range)
	testing.expect_value(t, err, Card_Compile_Error.None)
	testing.expect_value(t, action.effects[0].amount, i32(3))

	out_of_range := entity_target(enemy_entity(room.enemies[1].id))
	_, err = compile_card_action(&room, {id = 9, definition_id = .Arc_Bolt}, out_of_range)
	testing.expect_value(t, err, Card_Compile_Error.Target_Out_Of_Range)

	origin := grid.Position{x = 2, y = 2}
	testing.expect(t, targeting_range_contains({.Chebyshev, 1, 2}, origin, {x = 4, y = 4}))
	testing.expect(t, !targeting_range_contains({.Manhattan, 1, 2}, origin, {x = 4, y = 4}))
}

@(test)
test_toxic_wave_card_expands_one_effect_per_enemy :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{
		{position = {x = 2, y = 1}, health = 6, attack = 1},
		{position = {x = 4, y = 1}, health = 6, attack = 1},
	}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	action, err := compile_card_action(&room, {
		id = 7,
		definition_id = .Toxic_Wave,
		upgrade_level = 1,
	}, {})

	testing.expect_value(t, err, Card_Compile_Error.None)
	testing.expect_value(t, action.effect_count, 2)
	for index in 0..<action.effect_count {
		testing.expect_value(t, action.effects[index].kind, Effect_Kind.Apply_Status)
		testing.expect_value(t, action.effects[index].target, enemy_entity(u32(index+1)))
		testing.expect_value(t, action.effects[index].amount, i32(2))
		testing.expect_value(t, action.effects[index].status, Status_Kind.Poison)
	}
}

@(test)
test_global_card_supports_nine_enemies_without_truncation :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{
		{position = {x = 2, y = 1}, health = 6, attack = 1},
		{position = {x = 3, y = 1}, health = 6, attack = 1},
		{position = {x = 4, y = 1}, health = 6, attack = 1},
		{position = {x = 5, y = 1}, health = 6, attack = 1},
		{position = {x = 1, y = 2}, health = 6, attack = 1},
		{position = {x = 2, y = 2}, health = 6, attack = 1},
		{position = {x = 4, y = 2}, health = 6, attack = 1},
		{position = {x = 5, y = 2}, health = 6, attack = 1},
		{position = {x = 1, y = 3}, health = 6, attack = 1},
	}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	action, err := compile_card_action(&room, {id = 9, definition_id = .Toxic_Wave}, {})
	testing.expect_value(t, err, Card_Compile_Error.None)
	testing.expect_value(t, action.effect_count, len(enemy_spawns))
	for index in 0..<action.effect_count {
		testing.expect_value(t, action.effects[index].target, enemy_entity(u32(index+1)))
		testing.expect_value(t, action.effects[index].status, Status_Kind.Poison)
	}

	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted)
	testing.expect_value(t, report.applied_effects, len(enemy_spawns))
	for id in u32(1)..=u32(len(enemy_spawns)) {
		_, poisoned := status_for_entity(&room, enemy_entity(id), .Poison)
		testing.expect(t, poisoned)
	}
}

@(test)
test_area_card_compilation_preserves_shape_and_stable_enemy_order :: proc(t: ^testing.T) {
	// Independent target oracles: agreement with the preview alone could let
	// both paths accept the same incorrect shape or storage order.
	cases := [?]struct {
		definition_id: Card_Id,
		anchor: grid.Position,
		enemies: [4]grid.Position,
		enemy_count: int,
		expected_ids: [3]u32,
		target_count: int,
	}{
		{.Piercing_Ray, {5, 1}, {{4, 1}, {5, 3}, {2, 1}, {}}, 3, {1, 3, 0}, 2},
		{.Cross_Slash, {2, 2}, {{2, 3}, {5, 3}, {2, 1}, {1, 2}}, 4, {1, 3, 4}, 3},
		{.Firebomb, {4, 2}, {{5, 3}, {2, 3}, {3, 1}, {4, 3}}, 4, {1, 3, 4}, 3},
	}
	for fixture in cases {
		level_data := create_test_level(t)
		defer level.destroy(&level_data)
		player := create_test_player(t)
		spawns: [4]Enemy_Spawn
		for index in 0..<fixture.enemy_count {
			spawns[index] = {position = fixture.enemies[index], health = 5, attack = 1}
		}
		room, ok := create_room(&level_data, &player, {enemies = spawns[:fixture.enemy_count]})
		testing.expect(t, ok)
		defer destroy_room(&room)

		instance := Card_Instance{id = 90+u32(fixture.definition_id), definition_id = fixture.definition_id}
		target := cell_target(fixture.anchor)
		action, err := compile_card_action(&room, instance, target)
		testing.expect_value(t, err, Card_Compile_Error.None)
		testing.expect_value(t, action.target, target)
		testing.expect_value(t, action.target_rule, Target_Rule.Walkable_Cell)
		if !testing.expect_value(t, action.effect_count, fixture.target_count) { continue }
		for effect, index in action.effects[:action.effect_count] {
			testing.expect_value(t, effect.kind, Effect_Kind.Damage)
			testing.expect_value(t, effect.target, enemy_entity(fixture.expected_ids[index]))
			testing.expect_value(t, effect.amount, i32(2))
		}
	}
}

@(test)
test_card_preview_and_compiler_agree_for_every_grid_anchor :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{
		{position = {x = 4, y = 1}, health = 5, attack = 1},
		{position = {x = 5, y = 3}, health = 5, attack = 1},
	}
	obstacles := [?]grid.Position{{x = 3, y = 1}}
	room, ok := create_room(&level_data, &player, {
		enemies = enemy_spawns[:],
		obstacles = obstacles[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)
	definition, found := card_definition_by_id(.Firebomb)
	testing.expect(t, found)
	instance := Card_Instance{id = 77, definition_id = .Firebomb}

	for y in 0..<level_data.tiles.height {
		for x in 0..<level_data.tiles.width {
			anchor := grid.Position{x = x, y = y}
			request := card_target_request_at(definition, anchor)
			preview := evaluate_card_targeting(&room, instance, request)
			_, compile_error := compile_card_action(&room, instance, cell_target(anchor))

			testing.expect_value(t, preview.error, compile_error)
		}
	}
}

@(test)
test_counter_rune_card_preserves_instance_as_binding_source :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 6, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	action, err := compile_card_action(&room, {
		id = 42,
		definition_id = .Counter_Rune,
		upgrade_level = 1,
	}, entity_target(PLAYER_ENTITY))
	testing.expect_value(t, err, Card_Compile_Error.None)
	testing.expect_value(t, action.effects[0].binding_source, Reaction_Binding_Source{kind = .Card, id = 42})
	testing.expect_value(t, action.effects[0].amount, i32(3))

	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted)
	testing.expect_value(t, room.reaction_bindings.count, 1)
	binding := room.reaction_bindings.items[0]
	testing.expect_value(t, binding.definition_id, Reaction_Id.Thorns_Counter)
	testing.expect_value(t, binding.remaining_charges, i32(2))
	testing.expect_value(t, binding.remaining_pulses, i32(4))
	testing.expect_value(t, binding.source, Reaction_Binding_Source{kind = .Card, id = 42})
}
