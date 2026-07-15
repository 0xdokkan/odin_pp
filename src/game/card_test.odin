package game

import "core:testing"
import grid "../grid"
import level "../level"

@(test)
test_builtin_card_definitions_are_valid :: proc(t: ^testing.T) {
	testing.expect(t, validate_card_definitions())

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

	_, found = card_definition_by_id(.Count)
	testing.expect(t, !found)
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
	target, has_target := card_drop_target(&room, strike, room.enemies[0].position)
	testing.expect(t, has_target)
	testing.expect_value(t, target, entity_target(enemy_entity(room.enemies[0].id)))
	_, has_target = card_drop_target(&room, strike, {x = 3, y = 1})
	testing.expect(t, !has_target)

	guard, guard_found := card_definition_by_id(.Guard)
	testing.expect(t, guard_found)
	target, has_target = card_drop_target(&room, guard, {x = 3, y = 1})
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
	testing.expect_value(t, action.target_rule, Target_Rule.Opponent)
	testing.expect_value(t, action.effect_count, 1)
	testing.expect_value(t, action.effects[0].target, enemy_ref)
	testing.expect_value(t, action.effects[0].amount, i32(4))
	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted)
	testing.expect_value(t, room.enemies[0].health, i32(2))
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

	_, err := compile_card_action(&room, {definition_id = .Strike}, target)
	testing.expect_value(t, err, Card_Compile_Error.Invalid_Instance)

	_, err = compile_card_action(&room, {id = 1, definition_id = .Strike}, target)
	testing.expect_value(t, err, Card_Compile_Error.Target_Out_Of_Range)

	_, err = compile_card_action(nil, {id = 1, definition_id = .Strike}, target)
	testing.expect_value(t, err, Card_Compile_Error.Invalid_Room)
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

expect_affected_card_compilation :: proc(
	t: ^testing.T,
	definition_id: Card_Id,
	anchor: grid.Position,
	enemy_spawns: []Enemy_Spawn,
	expected_enemy_ids: []u32,
) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns})
	testing.expect(t, ok)
	defer destroy_room(&room)

	instance := Card_Instance{
		id = u32(90+int(definition_id)),
		definition_id = definition_id,
	}
	target := cell_target(anchor)
	action, err := compile_card_action(&room, instance, target)

	testing.expect_value(t, err, Card_Compile_Error.None)
	testing.expect_value(t, action.target, target)
	testing.expect_value(t, action.target_rule, Target_Rule.Walkable_Cell)
	testing.expect_value(t, action.effect_count, len(expected_enemy_ids))
	for index in 0..<action.effect_count {
		testing.expect_value(t, action.effects[index].kind, Effect_Kind.Damage)
		testing.expect_value(t, action.effects[index].target, enemy_entity(expected_enemy_ids[index]))
		testing.expect_value(t, action.effects[index].amount, i32(2))
	}
}

@(test)
test_piercing_ray_compiles_only_line_enemy_ids_in_stable_order :: proc(t: ^testing.T) {
	enemy_spawns := [?]Enemy_Spawn{
		{position = {x = 4, y = 1}, health = 5, attack = 1},
		{position = {x = 5, y = 3}, health = 5, attack = 1},
		{position = {x = 2, y = 1}, health = 5, attack = 1},
	}
	expected_enemy_ids := [?]u32{1, 3}
	expect_affected_card_compilation(
		t,
		.Piercing_Ray,
		{x = 5, y = 1},
		enemy_spawns[:],
		expected_enemy_ids[:],
	)
}

@(test)
test_cross_slash_compiles_only_cross_enemy_ids_in_stable_order :: proc(t: ^testing.T) {
	enemy_spawns := [?]Enemy_Spawn{
		{position = {x = 2, y = 3}, health = 5, attack = 1},
		{position = {x = 5, y = 3}, health = 5, attack = 1},
		{position = {x = 2, y = 1}, health = 5, attack = 1},
		{position = {x = 1, y = 2}, health = 5, attack = 1},
	}
	expected_enemy_ids := [?]u32{1, 3, 4}
	expect_affected_card_compilation(
		t,
		.Cross_Slash,
		{x = 2, y = 2},
		enemy_spawns[:],
		expected_enemy_ids[:],
	)
}

@(test)
test_firebomb_compiles_only_square_enemy_ids_in_stable_order :: proc(t: ^testing.T) {
	enemy_spawns := [?]Enemy_Spawn{
		{position = {x = 5, y = 3}, health = 5, attack = 1},
		{position = {x = 2, y = 3}, health = 5, attack = 1},
		{position = {x = 3, y = 1}, health = 5, attack = 1},
		{position = {x = 4, y = 3}, health = 5, attack = 1},
	}
	expected_enemy_ids := [?]u32{1, 3, 4}
	expect_affected_card_compilation(
		t,
		.Firebomb,
		{x = 4, y = 2},
		enemy_spawns[:],
		expected_enemy_ids[:],
	)
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
