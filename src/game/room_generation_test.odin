package game

import "core:testing"

test_generation_node :: proc(id: int, kind: Node_Kind, depth: int, run_seed: u64) -> Run_Node {
	node_id := Node_Id(id)
	return {
		id = node_id,
		kind = kind,
		depth = depth,
		room_seed = derive_node_room_seed(run_seed, node_id, kind, depth),
	}
}

expect_blueprints_equal :: proc(t: ^testing.T, first, second: ^Room_Blueprint) {
	testing.expect(t, first != nil && second != nil)
	testing.expect_value(t, first.seed, second.seed)
	testing.expect_value(t, first.source_node, second.source_node)
	testing.expect_value(t, first.node_kind, second.node_kind)
	testing.expect_value(t, first.node_depth, second.node_depth)
	testing.expect_value(t, first.exit_position, second.exit_position)
	testing.expect_value(t, first.level_data.tiles.width, second.level_data.tiles.width)
	testing.expect_value(t, first.level_data.tiles.height, second.level_data.tiles.height)
	testing.expect_value(t, first.level_data.player_spawn, second.level_data.player_spawn)
	testing.expect_value(t, len(first.level_data.tiles.cells), len(second.level_data.tiles.cells))
	for tile, index in first.level_data.tiles.cells {
		testing.expect_value(t, tile, second.level_data.tiles.cells[index])
	}
	testing.expect_value(t, len(first.obstacles), len(second.obstacles))
	for obstacle, index in first.obstacles {
		testing.expect_value(t, obstacle, second.obstacles[index])
	}
	testing.expect_value(t, len(first.enemies), len(second.enemies))
	for enemy, index in first.enemies {
		testing.expect_value(t, enemy, second.enemies[index])
	}
	testing.expect_value(t, len(first.traps), len(second.traps))
	for trap, index in first.traps {
		testing.expect_value(t, trap, second.traps[index])
	}
}

room_blueprint_enemy_budget :: proc(blueprint: ^Room_Blueprint) -> (result: int) {
	if blueprint == nil {
		return
	}
	for enemy in blueprint.enemies {
		result += enemy_archetype_budget_cost(enemy.archetype)
	}
	return
}

expect_generation_invariant :: proc(
	t: ^testing.T,
	condition: bool,
	invariant: string,
	combination: int,
	run_seed: u64,
	kind: Node_Kind,
	depth: int,
	item_index := -1,
) {
	testing.expectf(
		t,
		condition,
		"invariant=%v combination=%v seed=%v kind=%v depth=%v item=%v",
		invariant,
		combination,
		run_seed,
		kind,
		depth,
		item_index,
	)
}

@(test)
test_room_blueprint_is_deterministic_for_a_node :: proc(t: ^testing.T) {
	node := test_generation_node(7, .Elite, 4, 0xCAFE)
	first, first_error := generate_room_blueprint(&node)
	testing.expect_value(t, first_error, Room_Blueprint_Error.None)
	defer destroy_room_blueprint(&first)
	second, second_error := generate_room_blueprint(&node)
	testing.expect_value(t, second_error, Room_Blueprint_Error.None)
	defer destroy_room_blueprint(&second)

	testing.expect(t, validate_room_blueprint(&first))
	testing.expect(t, validate_room_blueprint(&second))
	expect_blueprints_equal(t, &first, &second)
}

@(test)
test_room_generation_profiles_scale_by_node_kind :: proc(t: ^testing.T) {
	combat_node := test_generation_node(1, .Combat, 5, 77)
	elite_node := test_generation_node(2, .Elite, 5, 77)
	boss_node := test_generation_node(3, .Boss, 5, 77)
	combat, combat_ok := room_generation_profile(&combat_node)
	elite, elite_ok := room_generation_profile(&elite_node)
	boss, boss_ok := room_generation_profile(&boss_node)

	testing.expect(t, combat_ok && elite_ok && boss_ok)
	testing.expect(t, combat.encounter_config.enemy_budget < elite.encounter_config.enemy_budget)
	testing.expect(t, elite.encounter_config.enemy_budget < boss.encounter_config.enemy_budget)
	testing.expect(t, combat.encounter_config.trap_count < elite.encounter_config.trap_count)
	testing.expect(t, elite.level_config.width < boss.level_config.width)
	testing.expect(t, combat.level_config.wall_density_percent < boss.level_config.wall_density_percent)

	boss_blueprint, err := generate_room_blueprint(&boss_node)
	testing.expect_value(t, err, Room_Blueprint_Error.None)
	defer destroy_room_blueprint(&boss_blueprint)
	testing.expect(t, len(boss_blueprint.enemies) > 0)
	if len(boss_blueprint.enemies) > 0 {
		testing.expect_value(t, boss_blueprint.enemies[0].archetype, Enemy_Archetype.Brute)
	}
}

@(test)
test_room_blueprints_hold_invariants_across_run_seeds :: proc(t: ^testing.T) {
	kinds := [?]Node_Kind{.Combat, .Elite, .Boss}
	generated_count := 0
	for combination in 0..<4096 {
		profile_index := combination%(len(kinds)*9)
		kind := kinds[profile_index/9]
		depth := profile_index%9
		seed_index := combination/(len(kinds)*9)+1
		run_seed := u64(seed_index)*0x9E3779B97F4A7C15~u64(profile_index)
		node := test_generation_node(combination, kind, depth, run_seed)
		blueprint, err := generate_room_blueprint(&node)
		expect_generation_invariant(
			t, err == .None, "blueprint generated", combination, run_seed, kind, depth,
		)
		if err != .None {
			continue
		}
		generated_count += 1
		expect_generation_invariant(
			t,
			validate_room_blueprint(&blueprint),
			"blueprint validates",
			combination,
			run_seed,
			kind,
			depth,
		)
		config := blueprint.profile.encounter_config
		expect_generation_invariant(
			t,
			room_blueprint_enemy_budget(&blueprint) == config.enemy_budget,
			"enemy budget",
			combination,
			run_seed,
			kind,
			depth,
		)
		expect_generation_invariant(
			t,
			len(blueprint.obstacles) == config.obstacle_count,
			"obstacle count",
			combination,
			run_seed,
			kind,
			depth,
		)
		expect_generation_invariant(
			t,
			len(blueprint.traps) == config.trap_count,
			"trap count",
			combination,
			run_seed,
			kind,
			depth,
		)
		for enemy, enemy_index in blueprint.enemies {
			health, attack := enemy_stats_for_archetype(config, enemy.archetype)
			expect_generation_invariant(
				t,
				enemy.health == health && enemy.attack == attack,
				"enemy stats",
				combination,
				run_seed,
				kind,
				depth,
				enemy_index,
			)
		}
		for trap, trap_index in blueprint.traps {
			expect_generation_invariant(
				t,
				trap.damage == config.trap_damage,
				"trap damage",
				combination,
				run_seed,
				kind,
				depth,
				trap_index,
			)
		}
		expect_generation_invariant(
			t,
			all_unblocked_walkable_cells_are_connected(
				&blueprint.level_data,
				blueprint.obstacles[:],
			),
			"walkable cells connected",
			combination,
			run_seed,
			kind,
			depth,
		)

		player, player_ok := create_player(RUN_TEST_PLAYER_STATS)
		expect_generation_invariant(
			t, player_ok, "player created", combination, run_seed, kind, depth,
		)
		if !player_ok {
			destroy_room_blueprint(&blueprint)
			continue
		}
		room, room_ok := create_room(
			&blueprint.level_data,
			&player,
			room_blueprint_content(&blueprint),
		)
		expect_generation_invariant(
			t, room_ok, "room created", combination, run_seed, kind, depth,
		)
		if room_ok {
			destroy_room(&room)
		}
		destroy_room_blueprint(&blueprint)
	}
	testing.expectf(t, generated_count == 4096, "generated=%v expected=4096", generated_count)
}

@(test)
test_room_blueprint_validation_rejects_difficulty_tampering :: proc(t: ^testing.T) {
	node := test_generation_node(9, .Boss, 8, 0xFACE)
	blueprint, err := generate_room_blueprint(&node)
	testing.expect_value(t, err, Room_Blueprint_Error.None)
	defer destroy_room_blueprint(&blueprint)
	testing.expect(t, validate_room_blueprint(&blueprint))

	original_health := blueprint.enemies[0].health
	blueprint.enemies[0].health = 1
	testing.expect(t, !validate_room_blueprint(&blueprint))
	blueprint.enemies[0].health = original_health

	original_damage := blueprint.traps[0].damage
	blueprint.traps[0].damage += 1
	testing.expect(t, !validate_room_blueprint(&blueprint))
	blueprint.traps[0].damage = original_damage

	unordered_remove(&blueprint.obstacles, 0)
	testing.expect(t, !validate_room_blueprint(&blueprint))
}

@(test)
test_room_blueprint_rejects_invalid_or_zero_seed_nodes :: proc(t: ^testing.T) {
	invalid_nodes := [?]Run_Node{
		{id = INVALID_NODE_ID, kind = .Combat, depth = 0, room_seed = 1},
		{id = 0, kind = .Combat, depth = -1, room_seed = 1},
		{id = 0, kind = .Combat, depth = 0, room_seed = 0},
	}
	for &node in invalid_nodes {
		blueprint, err := generate_room_blueprint(&node)
		testing.expect_value(t, err, Room_Blueprint_Error.Invalid_Node)
		destroy_room_blueprint(&blueprint)
	}
}
