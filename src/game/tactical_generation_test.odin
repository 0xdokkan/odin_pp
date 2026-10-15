package game

import "core:testing"
import level "../level"

@(test)
test_tactical_rooms_expand_connected_layout_and_add_two_enemies_without_stat_inflation :: proc(t: ^testing.T) {
	// The original +2-cell/+2-role introduction applies to both opening layers.
	// Later arena tiers have exact rosters covered by arena_progression_test.
	for depth in 0..=1 {
	for seed in u64(1)..=12 {
		for kind in ([?]Node_Kind{.Combat, .Elite, .Boss}) {
			node := test_generation_node(0, kind, depth, seed)
			classic, classic_error := generate_room_blueprint(&node)
			testing.expect_value(t, classic_error, Room_Blueprint_Error.None)
			modern, modern_error := generate_room_blueprint(&node, tactical = true)
			testing.expect_value(t, modern_error, Room_Blueprint_Error.None)
			testing.expect(t, validate_room_blueprint(&modern))
			testing.expect_value(t, modern.level_data.tiles.width, classic.level_data.tiles.width+2)
			testing.expect_value(t, modern.level_data.tiles.height, classic.level_data.tiles.height+2)
			testing.expect(t, modern.profile.level_config.central_spawn)
			testing.expect(t, !classic.profile.level_config.central_spawn)
			testing.expect(t, level.is_interior_corner(classic.level_data.player_spawn, classic.level_data.tiles.width, classic.level_data.tiles.height))
			testing.expect(t, !level.is_interior_corner(modern.level_data.player_spawn, modern.level_data.tiles.width, modern.level_data.tiles.height))
			testing.expect_value(t, len(modern.enemies), len(classic.enemies)+2)
			testing.expect_value(t, modern.profile.encounter_config.enemy_health, classic.profile.encounter_config.enemy_health)
			testing.expect_value(t, modern.profile.encounter_config.enemy_attack, classic.profile.encounter_config.enemy_attack)
			again, err := generate_room_blueprint(&node, tactical = true)
			testing.expect_value(t, err, Room_Blueprint_Error.None)
			expect_blueprints_equal(t, &modern, &again)
			destroy_room_blueprint(&again)
			destroy_room_blueprint(&modern)
			destroy_room_blueprint(&classic)
		}
	}
	}
}

@(test)
test_tactical_central_spawn_preserves_encounter_safety_for_every_family :: proc(t: ^testing.T) {
	seen: [3][level.Room_Family]bool
	for seed in u64(1)..=64 {
		for kind, kind_index in ([?]Node_Kind{.Combat, .Elite, .Boss}) {
			node := test_generation_node(0, kind, 0 if kind == .Combat else 4, seed)
			when !ODIN_TEST_FULL {
				profile, ok := room_generation_profile(&node, tactical = true)
				if !testing.expect(t, ok) { continue }
				if seen[kind_index][profile.level_config.family] { continue }
			}
			blueprint, err := generate_room_blueprint(&node, tactical = true)
			testing.expectf(t, err == .None, "kind=%v seed=%v error=%v", kind, seed, err)
			if err != .None { continue }
			seen[kind_index][blueprint.profile.level_config.family] = true
			spawn := blueprint.level_data.player_spawn
			config := blueprint.profile.encounter_config
			testing.expect(t, level.has_full_interior_clearance(spawn, blueprint.profile.level_config.spawn_clearance_radius,
				blueprint.level_data.tiles.width, blueprint.level_data.tiles.height))
			for enemy in blueprint.enemies { testing.expect(t, grid_distance(enemy.position, spawn) > config.player_safe_radius) }
			for trap in blueprint.traps { testing.expect(t, grid_distance(trap.position, spawn) > config.player_safe_radius) }
			for obstacle in blueprint.obstacles { testing.expect(t, grid_distance(obstacle, spawn) > config.player_safe_radius) }
			for object in blueprint.objects { testing.expect(t, grid_distance(object.position, spawn) > config.player_safe_radius) }
			destroy_room_blueprint(&blueprint)
		}
	}
	for families, kind_index in seen {
		for family in ([?]level.Room_Family{.Pillars, .Ring, .Twin_Courts, .Asymmetric}) {
			testing.expectf(t, families[family], "kind index=%v missing family=%v", kind_index, family)
		}
	}
}
