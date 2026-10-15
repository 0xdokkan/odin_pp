package game

import "core:testing"
import grid "../grid"
import level "../level"

arena_compatibility_hash :: proc(blueprint: ^Room_Blueprint) -> u64 {
	hash := u64(14695981039346656037)
	mix :: proc(hash: ^u64, value: int) { hash^ = (hash^~u64(value))*1099511628211 }
	mix_position :: proc(hash: ^u64, position: grid.Position) { mix(hash, position.x); mix(hash, position.y) }
	mix(&hash, blueprint.level_data.tiles.width)
	mix(&hash, blueprint.level_data.tiles.height)
	mix_position(&hash, blueprint.level_data.player_spawn)
	mix_position(&hash, blueprint.exit_position)
	for cell in blueprint.level_data.tiles.cells { mix(&hash, int(cell.kind)) }
	for enemy in blueprint.enemies {
		mix_position(&hash, enemy.position)
		mix(&hash, int(enemy.archetype)); mix(&hash, int(enemy.health)); mix(&hash, int(enemy.attack))
	}
	for obstacle in blueprint.obstacles { mix_position(&hash, obstacle) }
	for trap in blueprint.traps { mix_position(&hash, trap.position); mix(&hash, int(trap.damage)) }
	for object in blueprint.objects { mix_position(&hash, object.position); mix(&hash, int(object.kind)) }
	return hash
}

@(test)
test_arena_progression_preserves_legacy_rooms :: proc(t: ^testing.T) {
	// Captured before the progression change: geometry, anchors, roster, traps
	// and objects must all keep their seeded ordering in the legacy paths.
	expected := [?]u64{
		8121667582311555035, 2405377929276258985, 11537757873144908426,
		17734044712456417097, 6574506746188810855, 10033635374348756734,
		2648737434455942221, 3148738511542268274, 2847178824596872397,
		12177049974555128568, 4695759264541062819, 15747700827686040169,
		1345742107051187227, 14616536019589972991, 12178865995150018295,
		658043700574800456, 16121760560638974580, 12633176597817086690,
	}
	index := 0
	for tactical in ([?]bool{false, true}) {
		for depth in ([?]int{0, 1, 5, 8}) {
			if tactical && depth > 1 { continue }
			for kind in ([?]Node_Kind{.Combat, .Elite, .Boss}) {
				node := test_generation_node(7, kind, depth, 0xCAFE)
				blueprint, err := generate_room_blueprint(&node, .Scattered, tactical)
				testing.expect_value(t, err, Room_Blueprint_Error.None)
				testing.expect_value(t, arena_compatibility_hash(&blueprint), expected[index])
				index += 1
				destroy_room_blueprint(&blueprint)
			}
		}
	}
}

@(test)
test_arena_progression_scales_area_rosters_and_caps :: proc(t: ^testing.T) {
	for kind in ([?]Node_Kind{.Combat, .Elite, .Boss}) {
		for depth in ([?]int{0, 1, 2, 3, 4, 5, 6, 8, 127, max(int)}) {
			node := Run_Node{id = 7, kind = kind, depth = depth, room_seed = 0xCAFE}
			profile, ok := room_generation_profile(&node, .Scattered, true)
			testing.expect(t, ok)
			tier := tactical_arena_tier(depth)
			expected_width, expected_height := 17+8*tier, 11+6*tier
			if kind == .Elite { expected_width += 2; expected_height += 1 }
			if kind == .Boss { expected_width += 4; expected_height += 2 }
			testing.expect_value(t, profile.level_config.width, expected_width)
			testing.expect_value(t, profile.level_config.height, expected_height)
			testing.expect_value(t, profile.level_config.complexity, tier)
			testing.expect(t, profile.encounter_config.enemy_health > 0 && profile.encounter_config.enemy_attack > 0)
			if depth < MAX_RUN_MAP_LAYERS {
				classic, classic_ok := room_generation_profile(&node)
				testing.expect(t, classic_ok)
				testing.expect_value(t, profile.encounter_config.enemy_health, classic.encounter_config.enemy_health)
				testing.expect_value(t, profile.encounter_config.enemy_attack, classic.encounter_config.enemy_attack)
				testing.expect_value(t, profile.encounter_config.trap_damage, classic.encounter_config.trap_damage)
			}
			if tier > 0 {
				expected_count := 4+4*tier
				if kind == .Elite { expected_count += 2 }
				if kind == .Boss { expected_count += 4 if tier < 3 else 6 }
				testing.expect_value(t, profile.encounter_config.target_enemies, expected_count)
				testing.expect_value(t, profile.encounter_config.max_enemies, expected_count)
			}
		}
	}
}

@(test)
test_arena_progression_seeded_geometry_roster_and_spread :: proc(t: ^testing.T) {
	seen_families: [5]bool
	for depth in ([?]int{2, 3, 4, 5, 6, 20}) {
		for kind in ([?]Node_Kind{.Combat, .Elite, .Boss}) {
			profile_families: [level.Room_Family]bool
			// Some profiles need more than the original twelve seeds to select
			// all four families. Quick mode searches profiles without generating
			// repeated families; full mode retains its original seed matrix.
			seed_limit := 12 if ODIN_TEST_FULL else 64
			for seed in 1..=seed_limit {
				node := test_generation_node(7, kind, depth, u64(seed)*7919)
				when !ODIN_TEST_FULL {
					profile, ok := room_generation_profile(&node, level.Room_Family(seed%5), true)
					if !testing.expect(t, ok) { continue }
					if profile_families[profile.level_config.family] { continue }
				}
				blueprint, err := generate_room_blueprint(&node, level.Room_Family(seed%5), true)
				testing.expectf(t, err == .None, "depth=%v kind=%v seed=%v error=%v", depth, kind, seed, err)
				if err != .None { continue }
				seen_families[int(blueprint.profile.level_config.family)] = true
				profile_families[blueprint.profile.level_config.family] = true
				testing.expect_value(t, len(blueprint.enemies), blueprint.profile.encounter_config.target_enemies)
				roles, role_count := progressive_encounter_required_roles(&blueprint)
				for role in roles[:role_count] {
					found := false
					for enemy in blueprint.enemies { if enemy.archetype == role { found = true } }
					testing.expect(t, found)
				}
				min_x, max_x, min_y, max_y := max(int), 0, max(int), 0
				quadrants: [4]bool
				for enemy in blueprint.enemies {
					min_x, max_x = min(min_x, enemy.position.x), max(max_x, enemy.position.x)
					min_y, max_y = min(min_y, enemy.position.y), max(max_y, enemy.position.y)
					quadrant := (1 if enemy.position.x >= blueprint.level_data.tiles.width/2 else 0)+
					            (2 if enemy.position.y >= blueprint.level_data.tiles.height/2 else 0)
					quadrants[quadrant] = true
				}
				testing.expectf(t, max_x-min_x >= blueprint.level_data.tiles.width/2 &&
					max_y-min_y >= blueprint.level_data.tiles.height/2,
					"spread depth=%v kind=%v seed=%v spans=%v,%v", depth, kind, seed, max_x-min_x, max_y-min_y)
				if depth >= 4 {
					occupied := 0
					for present in quadrants { if present { occupied += 1 } }
					testing.expectf(t, occupied >= 3, "quadrants depth=%v kind=%v seed=%v count=%v", depth, kind, seed, occupied)
				}
				destroy_room_blueprint(&blueprint)
			}
			when !ODIN_TEST_FULL {
				for family in ([?]level.Room_Family{.Pillars, .Ring, .Twin_Courts, .Asymmetric}) {
					testing.expectf(t, profile_families[family], "depth=%v kind=%v missing family=%v", depth, kind, family)
				}
			}
		}
	}
	// Scattered remains a classic generator; run rooms choose these four families.
	for seen in seen_families[1:] { testing.expect(t, seen) }
}

@(test)
test_arena_progression_determinism_and_roster_validation :: proc(t: ^testing.T) {
	for depth in ([?]int{2, 4, 6}) {
		node := test_generation_node(7, .Boss, depth, 0xBEEF)
		first, first_error := generate_room_blueprint(&node, .Pillars, true)
		second, second_error := generate_room_blueprint(&node, .Pillars, true)
		testing.expect_value(t, first_error, Room_Blueprint_Error.None)
		testing.expect_value(t, second_error, Room_Blueprint_Error.None)
		if first_error == .None && second_error == .None {
			expect_blueprints_equal(t, &first, &second)
			bosses := 0
			for enemy in first.enemies { if enemy.archetype == .Demolitionist { bosses += 1 } }
			testing.expect_value(t, bosses, 1)
			pop(&first.enemies)
			testing.expect(t, !validate_room_blueprint(&first))
		}
		destroy_room_blueprint(&first)
		destroy_room_blueprint(&second)
	}
}
