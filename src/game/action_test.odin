package game

import "core:testing"
import grid "../grid"
import level "../level"

@(test)
test_invalid_move_action_does_not_mutate_player :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 4, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	action := make_action(.Move, PLAYER_ENTITY, cell_target({x = 0, y = 0}), .Walkable_Cell)
	testing.expect(t, add_effect(&action, move_effect(PLAYER_ENTITY, {x = 0, y = 0})))
	report := resolve_action(&room, &action)

	testing.expect(t, !report.accepted)
	testing.expect_value(t, player.position, grid.Position{x = 1, y = 1})
}

@(test)
test_move_action_applies_effect_once :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 4, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	destination := grid.Position{x = 1, y = 2}
	action := make_action(.Move, PLAYER_ENTITY, cell_target(destination), .Walkable_Cell)
	testing.expect(t, add_effect(&action, move_effect(PLAYER_ENTITY, destination)))
	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	testing.expect_value(t, report.applied_effects, 1)
	testing.expect_value(t, player.position, destination)
	testing.expect_value(t, report.events.count, 1)
	testing.expect_value(t, report.events.events[0].kind, Game_Event_Kind.Moved)
	testing.expect_value(t, report.events.events[0].target, PLAYER_ENTITY)
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
