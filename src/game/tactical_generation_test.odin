package game

import "core:testing"
import level "../level"



@(test)
test_tactical_central_spawn_preserves_encounter_safety_for_every_family :: proc(t: ^testing.T) {
	seen: [3][level.Room_Family]bool
	for seed in u64(1)..=64 {
		for kind, kind_index in ([?]Node_Kind{.Combat, .Elite, .Boss}) {
			node := test_generation_node(0, kind, 0 if kind == .Combat else 4, seed)
			when !ODIN_TEST_FULL {
				profile, ok := room_generation_profile(&node)
				if !testing.expect(t, ok) { continue }
				if seen[kind_index][profile.level_config.family] { continue }
			}
			blueprint, err := generate_room_blueprint(&node)
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
