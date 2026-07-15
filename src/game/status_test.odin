package game

import "core:testing"
import level "../level"

@(test)
test_invalid_status_kind_is_rejected_without_consuming_a_slot :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	room, ok := create_room(&level_data, &player, {})
	testing.expect(t, ok)
	defer destroy_room(&room)
	invalid_kind := Status_Kind(99)

	testing.expect(t, !status_kind_is_valid(invalid_kind))
	testing.expect(t, !can_apply_status(&room, PLAYER_ENTITY, invalid_kind))
	applied, created := apply_status(&room, PLAYER_ENTITY, invalid_kind, 1, 3)
	testing.expect(t, !applied && !created)
	testing.expect_value(t, player.statuses.count, 0)
}

@(test)
test_poison_refreshes_with_the_stronger_potency :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	room, ok := create_room(&level_data, &player, {})
	testing.expect(t, ok)
	defer destroy_room(&room)

	applied, created := apply_status(&room, PLAYER_ENTITY, .Poison, 2, 3)
	testing.expect(t, applied && created)
	applied, created = apply_status(&room, PLAYER_ENTITY, .Poison, 1, 5)
	testing.expect(t, applied && !created)
	status, found := status_for_entity(&room, PLAYER_ENTITY, .Poison)
	testing.expect(t, found)
	testing.expect_value(t, status.potency, i32(2))
	testing.expect_value(t, status.remaining_pulses, i32(5))
}

@(test)
test_shield_stacks_absorption_and_refreshes_duration :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	room, ok := create_room(&level_data, &player, {})
	testing.expect(t, ok)
	defer destroy_room(&room)

	apply_status(&room, PLAYER_ENTITY, .Shield, 2, 4)
	apply_status(&room, PLAYER_ENTITY, .Shield, 3, 2)
	status, found := status_for_entity(&room, PLAYER_ENTITY, .Shield)
	testing.expect(t, found)
	testing.expect_value(t, status.potency, i32(5))
	testing.expect_value(t, status.remaining_pulses, i32(4))
}

@(test)
test_shield_absorbs_damage_after_player_defense :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 4, attack = 5}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	apply_status(&room, PLAYER_ENTITY, .Shield, 3, 4)

	enemy := room.enemies[0]
	action := make_action(.Attack, enemy_entity(enemy.id), entity_target(PLAYER_ENTITY), .Adjacent_Opponent)
	testing.expect(t, add_effect(&action, damage_effect(PLAYER_ENTITY, enemy.attack)))
	report := resolve_action(&room, &action)

	testing.expect_value(t, report.damage_absorbed, i32(3))
	testing.expect_value(t, report.damage_dealt, i32(1))
	testing.expect_value(t, report.statuses_removed, 1)
	testing.expect_value(t, player.health, i32(9))
	_, has_shield := status_for_entity(&room, PLAYER_ENTITY, .Shield)
	testing.expect(t, !has_shield)
	testing.expect_value(t, report.events.count, 3)
	testing.expect_value(t, report.events.events[0].kind, Game_Event_Kind.Damage_Absorbed)
	testing.expect_value(t, report.events.events[1].kind, Game_Event_Kind.Status_Removed)
	testing.expect_value(t, report.events.events[2].kind, Game_Event_Kind.Damaged)
}

@(test)
test_status_effects_emit_apply_and_remove_events :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	room, ok := create_room(&level_data, &player, {})
	testing.expect(t, ok)
	defer destroy_room(&room)

	apply_action := make_action(.Ability, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
	testing.expect(t, add_effect(&apply_action, apply_status_effect(PLAYER_ENTITY, .Shield, 4, 3)))
	apply_report := resolve_action(&room, &apply_action)
	testing.expect(t, apply_report.accepted)
	testing.expect_value(t, apply_report.statuses_applied, 1)
	testing.expect_value(t, apply_report.events.events[0].kind, Game_Event_Kind.Status_Applied)

	remove_action := make_action(.Ability, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
	testing.expect(t, add_effect(&remove_action, remove_status_effect(PLAYER_ENTITY, .Shield)))
	remove_report := resolve_action(&room, &remove_action)
	testing.expect(t, remove_report.accepted)
	testing.expect_value(t, remove_report.statuses_removed, 1)
	testing.expect_value(t, remove_report.events.events[0].kind, Game_Event_Kind.Status_Removed)
}

@(test)
test_poison_ticks_and_expires_after_its_duration :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 4, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	enemy_ref := enemy_entity(room.enemies[0].id)
	apply_status(&room, enemy_ref, .Poison, 1, 2)

	first_pulse := advance_combat_pulse(&room)
	testing.expect(t, first_pulse.advanced)
	testing.expect_value(t, room.enemies[0].health, i32(3))
	status, found := status_for_entity(&room, enemy_ref, .Poison)
	testing.expect(t, found)
	testing.expect_value(t, status.remaining_pulses, i32(1))

	second_pulse := advance_combat_pulse(&room)
	testing.expect_value(t, room.enemies[0].health, i32(2))
	_, found = status_for_entity(&room, enemy_ref, .Poison)
	testing.expect(t, !found)
	expired_found := false
	for index in 0..<second_pulse.events.count {
		if second_pulse.events.events[index].kind == .Status_Expired {
			expired_found = true
		}
	}
	testing.expect(t, expired_found)
}

@(test)
test_poison_can_end_combat_during_a_pulse :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 1, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	apply_status(&room, enemy_entity(room.enemies[0].id), .Poison, 1, 3)

	pulse := advance_combat_pulse(&room)

	testing.expect(t, pulse.combat_ended)
	testing.expect_value(t, pulse.enemies_defeated, 1)
	testing.expect_value(t, room.phase, Room_Phase.Loot)
	testing.expect_value(t, len(room.enemies), 0)
}

@(test)
test_player_poison_can_cause_defeat_after_enemy_actions :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	player.health = 2
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 4, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	apply_status(&room, PLAYER_ENTITY, .Poison, 3, 2)

	pulse := advance_combat_pulse(&room)

	testing.expect(t, pulse.player_defeated)
	testing.expect_value(t, room.phase, Room_Phase.Defeat)
	testing.expect_value(t, player.health, i32(0))
}

@(test)
test_failed_room_creation_preserves_statuses_but_success_clears_them :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	first_room, ok := create_room(&level_data, &player, {})
	testing.expect(t, ok)
	apply_status(&first_room, PLAYER_ENTITY, .Shield, 3, 3)
	destroy_room(&first_room)

	enemies := [?]Enemy_Spawn{{position = {x = 4, y = 2}, health = 4, attack = 1}}
	traps := [?]Trap_Spawn{{position = {x = 4, y = 2}, damage = 2}}
	invalid_room, invalid_ok := create_room(&level_data, &player, {enemies = enemies[:], traps = traps[:]})
	testing.expect(t, !invalid_ok)
	destroy_room(&invalid_room)
	_, status_preserved := status_index(&player.statuses, .Shield)
	testing.expect(t, status_preserved)

	second_room, second_ok := create_room(&level_data, &player, {})
	testing.expect(t, second_ok)
	defer destroy_room(&second_room)
	_, status_cleared := status_index(&player.statuses, .Shield)
	testing.expect(t, !status_cleared)
}

@(test)
test_player_command_collects_action_and_pulse_events :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 4, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	result := try_move_player(&room, .South)

	testing.expect_value(t, result, Action_Result.Moved)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect(t, room.recent_events.count >= 2)
	testing.expect_value(t, room.recent_events.events[0].kind, Game_Event_Kind.Moved)
}

@(test)
test_guard_is_one_action_and_shields_the_enemy_response :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 4, attack = 3}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	result := use_player_ability(&room, .Guard)

	testing.expect_value(t, result, Action_Result.Used_Ability)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect_value(t, player.health, i32(10))
	shield, found := status_for_entity(&room, PLAYER_ENTITY, .Shield)
	testing.expect(t, found)
	testing.expect_value(t, shield.potency, i32(1))
	testing.expect_value(t, shield.remaining_pulses, i32(2))
}

@(test)
test_toxic_wave_targets_every_enemy_but_advances_one_pulse :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{
		{position = {x = 5, y = 3}, health = 3, attack = 1},
		{position = {x = 4, y = 3}, health = 3, attack = 1},
	}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	first_ref := enemy_entity(room.enemies[0].id)
	second_ref := enemy_entity(room.enemies[1].id)

	result := use_player_ability(&room, .Toxic_Wave)

	testing.expect_value(t, result, Action_Result.Used_Ability)
	testing.expect_value(t, room.pulse_count, u64(1))
	first_index, first_found := enemy_index_by_id(&room, first_ref.id)
	second_index, second_found := enemy_index_by_id(&room, second_ref.id)
	testing.expect(t, first_found && second_found)
	testing.expect_value(t, room.enemies[first_index].health, i32(2))
	testing.expect_value(t, room.enemies[second_index].health, i32(2))
	first_poison, first_poison_found := status_for_entity(&room, first_ref, .Poison)
	second_poison, second_poison_found := status_for_entity(&room, second_ref, .Poison)
	testing.expect(t, first_poison_found && second_poison_found)
	testing.expect_value(t, first_poison.remaining_pulses, i32(2))
	testing.expect_value(t, second_poison.remaining_pulses, i32(2))
}
