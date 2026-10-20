package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

@(test)
test_custodian_support_precedes_ally_movement_in_stable_id_order :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	storage_orders := [?]bool{false, true}
	for reverse_storage in storage_orders {
		player := create_test_player(t)
		spawns := [?]Enemy_Spawn{
			{position = {5, 2}, health = 8, attack = 1},
			{position = {6, 2}, health = 8, attack = 1, archetype = .Custodian},
		}
		room, ok := create_room(&data, &player, {enemies = spawns[:]})
		testing.expect(t, ok)
		if reverse_storage {
			room.enemies[0], room.enemies[1] = room.enemies[1], room.enemies[0]
			plan_enemy_intents(&room)
		}
		custodian_index, _ := enemy_index_by_id(&room, 2)
		intent := room.enemies[custodian_index].intent
		testing.expect_value(t, intent.kind, Enemy_Intent_Kind.Protect)
		testing.expect_value(t, intent.protected_ally, enemy_entity(1))
		testing.expect_value(t, intent.destination, grid.Position{5, 2})
		pulse := advance_combat_pulse(&room)
		shield, found := status_for_entity(&room, enemy_entity(1), .Shield)
		testing.expect(t, found)
		if found {
			testing.expect_value(t, shield.potency, i32(2))
			testing.expect_value(t, shield.remaining_pulses, i32(2))
		}
		shield_index, has_shield_event := enemy_archetype_test_event_index(&pulse.events,
			.Status_Applied, enemy_entity(2), enemy_entity(1))
		move_index, moved := enemy_archetype_test_event_index(&pulse.events,
			.Moved, enemy_entity(1), enemy_entity(1))
		testing.expect(t, has_shield_event && moved && shield_index < move_index)
		testing.expect_value(t, room.enemies[custodian_index].intent.kind, Enemy_Intent_Kind.Recover)
		room.enemies[custodian_index].recovery_pulses = 10
		advance_combat_pulse(&room)
		shield, found = status_for_entity(&room, enemy_entity(1), .Shield)
		testing.expect(t, found)
		if found {
			testing.expect_value(t, shield.remaining_pulses, i32(1))
		}
		advance_combat_pulse(&room)
		_, found = status_for_entity(&room, enemy_entity(1), .Shield)
		testing.expect(t, !found)
		destroy_room(&room)
	}
}

@(test)
test_forced_displacement_or_death_cancels_frozen_custodian_protection :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	for scenario in 0..<4 {
		player := create_test_player(t)
		spawns := [?]Enemy_Spawn{
			{position = {5, 2}, health = 8, attack = 1},
			{position = {6, 2}, health = 8, attack = 1, archetype = .Custodian},
		}
		room, ok := create_room(&data, &player, {enemies = spawns[:]})
		testing.expect(t, ok)
		target := enemy_entity(1 if scenario == 1 || scenario == 2 else 2)
		action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(target), .Entity)
		if scenario < 2 {
			testing.expect(t, add_effect(&action, move_effect(target,
				grid.Position{5, 3} if scenario == 1 else grid.Position{6, 3})))
		} else {
			testing.expect(t, add_effect(&action, damage_effect(target, 8)))
		}
		report := resolve_action(&room, &action)
		testing.expect(t, report.accepted)
		pulse := advance_combat_pulse(&room)
		_, shielded := status_for_entity(&room, enemy_entity(1), .Shield)
		testing.expect(t, !shielded)
		if scenario != 3 {
			miss, found := enemy_intent_test_event(&pulse.events, .Attack_Missed)
			testing.expect(t, found)
			testing.expect_value(t, miss.target, enemy_entity(1))
			custodian_index, _ := enemy_index_by_id(&room, 2)
			testing.expect_value(t, room.enemies[custodian_index].recovery_pulses, i32(2))
		}
		destroy_room(&room)
	}
}

@(test)
test_custodian_line_rechecks_movable_cover_without_retargeting :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	spawns := [?]Enemy_Spawn{
		{position = {4, 2}, health = 8, attack = 1},
		{position = {6, 2}, health = 8, attack = 1, archetype = .Custodian},
	}
	objects := [?]Grid_Object_Spawn{{position = {5, 3}, kind = .Ice_Block}}
	room, ok := create_room(&data, &player, {enemies = spawns[:], objects = objects[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	testing.expect_value(t, room.enemies[1].intent.kind, Enemy_Intent_Kind.Protect)
	action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(object_entity(1)), .Entity)
	testing.expect(t, add_effect(&action, move_effect(object_entity(1), {5, 2})))
	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted)
	testing.expect(t, validate_enemy_intent_structure(&room, &room.enemies[1].intent))
	pulse := advance_combat_pulse(&room)
	testing.expect_value(t, spatial_card_event_count(&pulse.events, .Status_Applied), 0)
	testing.expect_value(t, spatial_card_event_count(&pulse.events, .Attack_Missed), 1)
	_, shielded := status_for_entity(&room, enemy_entity(1), .Shield)
	testing.expect(t, !shielded)
}

@(test)
test_custodian_shield_absorbs_two_damage_then_breaks :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	spawns := [?]Enemy_Spawn{
		{position = {5, 2}, health = 8, attack = 1},
		{position = {6, 2}, health = 8, attack = 1, archetype = .Custodian},
	}
	room, ok := create_room(&data, &player, {enemies = spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	advance_combat_pulse(&room)
	action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(enemy_entity(1)), .Entity)
	testing.expect(t, add_effect(&action, damage_effect(enemy_entity(1), 4)))
	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted)
	testing.expect_value(t, report.damage_absorbed, i32(2))
	testing.expect_value(t, room.enemies[0].health, i32(6))
	_, shielded := status_for_entity(&room, enemy_entity(1), .Shield)
	testing.expect(t, !shielded)
}

@(test)
test_demolitionist_bomb_charge_and_two_pulse_recovery :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	spawns := [?]Enemy_Spawn{{position = {5, 1}, health = 30, attack = 2, archetype = .Demolitionist}}
	room, ok := create_room(&data, &player, {enemies = spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	testing.expect_value(t, room.enemies[0].boss_phase, i32(1))
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Bombard)
	advance_combat_pulse(&room)
	testing.expect(t, room.enemies[0].bomb_ready && !room.enemies[0].intent.windup)
	advance_combat_pulse(&room)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Recover)
	for _ in 0..<TACTICAL_BOMBER_RECOVERY { advance_combat_pulse(&room) }
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Charge)
	testing.expect_value(t, room.enemies[0].intent.damage, i32(4))
	advance_combat_pulse(&room)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Recover)
	testing.expect_value(t, room.enemies[0].recovery_pulses, i32(2))
	for recovery in 0..<2 {
		pulse := advance_combat_pulse(&room)
		testing.expect_value(t, pulse.enemy_actions, 0)
		testing.expect_value(t, room.enemies[0].recovery_pulses, i32(1-recovery))
	}
	// After charging into melee range, the next bomb cycle repositions for a safe lob.
	testing.expect_value(t, room.enemies[0].boss_cycle, u32(0))
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Move)
	testing.expect(t, validate_enemy_intents(&room))
}

@(test)
test_demolitionist_phase_transition_preserves_announced_attack :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	spawns := [?]Enemy_Spawn{{position = {5, 1}, health = 30, attack = 2, archetype = .Demolitionist}}
	room, ok := create_room(&data, &player, {enemies = spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	room.enemies[0].boss_cycle = 1
	room.enemies[0].intent, room.enemies[0].tactical_cooldown = {}, 0
	plan_enemy_intents(&room)
	announced := room.enemies[0].intent
	testing.expect_value(t, announced.kind, Enemy_Intent_Kind.Charge)
	action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(enemy_entity(1)), .Entity)
	testing.expect(t, add_effect(&action, damage_effect(enemy_entity(1), 15)))
	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted)
	testing.expect_value(t, room.enemies[0].boss_phase, i32(1))
	testing.expect_value(t, room.enemies[0].intent, announced)
	pulse := advance_combat_pulse(&room)
	testing.expect_value(t, pulse.damage_dealt, i32(3))
	testing.expect_value(t, room.enemies[0].boss_phase, i32(2))
	testing.expect_value(t, room.enemies[0].boss_cycle, u32(0))
	testing.expect_value(t, room.enemies[0].recovery_pulses, i32(2))
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Recover)
}

@(test)
test_demolitionist_overdrive_throws_twice_then_announces_long_charge :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	spawns := [?]Enemy_Spawn{{position = {5, 1}, health = 30, attack = 2, archetype = .Demolitionist}}
	room, ok := create_room(&data, &player, {enemies = spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	player.health, player.stats.max_health = 100, 100
	room.enemies[0].health = 15
	room.enemies[0].intent, room.enemies[0].tactical_cooldown = {}, 0
	plan_enemy_intents(&room)
	testing.expect_value(t, room.enemies[0].boss_phase, i32(2))
	throws := 0
	for _ in 0..<16 {
		pulse := advance_combat_pulse(&room)
		throws += spatial_card_event_count(&pulse.events, .Object_Spawned)
		testing.expect(t, active_bomb_count(&room) <= TACTICAL_BOMB_LIMIT)
		if throws == 2 && room.enemies[0].intent.kind == .Charge { break }
	}
	testing.expect_value(t, throws, 2)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Charge)
	testing.expect_value(t, room.enemies[0].intent.damage, i32(6))
	// Overdrive threatens six cells without changing the announced cell later.
	room.enemies[0].position = {7, 1}
	room.enemies[0].intent, room.enemies[0].tactical_cooldown = {}, 0
	plan_enemy_intents(&room)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Charge)
	testing.expect_value(t, room.enemies[0].intent.path_count, 5)
	testing.expect(t, validate_enemy_intents(&room))
}

@(test)
test_interrupted_demolitionist_charge_still_gives_long_recovery :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	spawns := [?]Enemy_Spawn{{position = {5, 1}, health = 30, attack = 2, archetype = .Demolitionist}}
	room, ok := create_room(&data, &player, {enemies = spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	room.enemies[0].boss_cycle = 1
	room.enemies[0].intent, room.enemies[0].tactical_cooldown = {}, 0
	plan_enemy_intents(&room)
	action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(enemy_entity(1)), .Entity)
	testing.expect(t, add_effect(&action, move_effect(enemy_entity(1), {5, 2})))
	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted)
	pulse := advance_combat_pulse(&room)
	testing.expect_value(t, player.health, i32(10))
	testing.expect_value(t, spatial_card_event_count(&pulse.events, .Move_Blocked), 1)
	testing.expect_value(t, room.enemies[0].recovery_pulses, i32(2))
	testing.expect_value(t, room.enemies[0].boss_cycle, u32(0))
}

@(test)
test_demolitionist_unaligned_or_blocked_approach_has_bounded_recovery :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	for scenario in 0..<2 {
		player := create_test_player(t)
		spawns := [?]Enemy_Spawn{{position = {7, 4}, health = 30, attack = 2, archetype = .Demolitionist}}
		blockers := [?]grid.Position{{6, 4}, {7, 3}, {8, 4}}
		room, ok := create_room(&data, &player, {
			enemies = spawns[:], obstacles = blockers[:] if scenario == 1 else nil,
		})
		testing.expect(t, ok)
		room.enemies[0].boss_cycle = 1
		room.enemies[0].intent, room.enemies[0].tactical_cooldown = {}, 0
		plan_enemy_intents(&room)
		testing.expect_value(t, room.enemies[0].intent.kind,
			Enemy_Intent_Kind.Wait if scenario == 1 else Enemy_Intent_Kind.Move)
		advance_combat_pulse(&room)
		testing.expect_value(t, room.enemies[0].boss_approach_pulses, i32(1))
		advance_combat_pulse(&room)
		testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Recover)
		testing.expect_value(t, room.enemies[0].recovery_pulses, i32(2))
		testing.expect_value(t, room.enemies[0].boss_cycle, u32(0))
		for _ in 0..<2 {
			pulse := advance_combat_pulse(&room)
			testing.expect_value(t, pulse.enemy_actions, 0)
		}
		testing.expect(t, room.enemies[0].intent.kind != .Recover)
		destroy_room(&room)
	}
}

@(test)
test_demolitionist_death_cancels_pending_offense_and_phase_transition :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	spawns := [?]Enemy_Spawn{
		{position = {5, 1}, health = 30, attack = 2, archetype = .Demolitionist},
		{position = {7, 4}, health = 8, attack = 1},
	}
	room, ok := create_room(&data, &player, {enemies = spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Bombard)
	action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(enemy_entity(1)), .Entity)
	testing.expect(t, add_effect(&action, damage_effect(enemy_entity(1), 30)))
	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted)
	pulse := advance_combat_pulse(&room)
	testing.expect_value(t, spatial_card_event_count(&pulse.events, .Object_Spawned), 0)
	testing.expect_value(t, active_bomb_count(&room), 0)
	testing.expect_value(t, player.health, i32(10))
	testing.expect_value(t, len(room.enemies), 1)
	testing.expect(t, validate_enemy_intents(&room))
}
