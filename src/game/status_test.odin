package game

import "core:testing"
import grid "../grid"
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

// Poison, Bruciatura and Rallentamento are stacks: each application adds its
// stacks, and they keep no duration. Every other status still needs one, and
// the player cannot be slowed.
@(test)
test_poison_burn_and_slow_stacks_add_up_without_a_duration :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 4, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	enemy := enemy_entity(room.enemies[0].id)
	for kind in ([?]Status_Kind{.Poison, .Burn, .Slow}) {
		testing.expect(t, status_kind_stacks(kind))
		applied, created := apply_status(&room, enemy, kind, 2, 0)
		testing.expect(t, applied && created)
		applied, created = apply_status(&room, enemy, kind, 1, 5)
		testing.expect(t, applied && !created)
		status, found := status_for_entity(&room, enemy, kind)
		testing.expect(t, found)
		if !found { continue }
		testing.expect_value(t, status.potency, i32(3))
		testing.expect_value(t, status.remaining_pulses, i32(0))
	}
	for kind in ([?]Status_Kind{.Shield, .Thorns, .Afterimage, .Stagger, .Survey}) {
		testing.expect(t, !status_kind_stacks(kind))
	}
	applied, _ := apply_status(&room, enemy, .Thorns, 1, 0)
	testing.expect(t, !applied)
	testing.expect(t, !effect_is_valid(&room, apply_status_effect(enemy, .Shield, 2, 0)))
	testing.expect(t, effect_is_valid(&room, apply_status_effect(enemy, .Burn, 2, 0)))
	burned, _ := apply_status(&room, PLAYER_ENTITY, .Burn, 1, 0)
	testing.expect(t, burned)
	slowed, _ := apply_status(&room, PLAYER_ENTITY, .Slow, 1, 0)
	testing.expect(t, !slowed)
	testing.expect(t, !effect_is_valid(&room, apply_status_effect(PLAYER_ENTITY, .Slow, 1, 0)))
	_, player_slowed := status_for_entity(&room, PLAYER_ENTITY, .Slow)
	testing.expect(t, !player_slowed)
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
test_poison_bites_each_enemy_action_and_wears_a_stack :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 10, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	enemy_ref := enemy_entity(room.enemies[0].id)
	apply_status(&room, enemy_ref, .Poison, 2, 0)

	// Its action (a wait counts) is followed by a bite of its stacks.
	room.enemies[0].intent = make_wait_intent(&room, room.enemies[0].position)
	first_pulse := advance_combat_pulse(&room)
	testing.expect(t, first_pulse.advanced)
	testing.expect_value(t, room.enemies[0].health, i32(8))
	poison_damage_found := false
	for index in 0..<first_pulse.events.count {
		event := first_pulse.events.events[index]
		if event.kind != .Damaged || event.target != enemy_ref {
			continue
		}
		poison_damage_found = true
		testing.expect(t, event.has_status_cause)
		testing.expect_value(t, event.status_cause, Status_Kind.Poison)
		testing.expect_value(t, event.source, SYSTEM_ENTITY)
	}
	testing.expect(t, poison_damage_found)
	status, found := status_for_entity(&room, enemy_ref, .Poison)
	testing.expect(t, found)
	if found { testing.expect_value(t, status.potency, i32(1)) }

	second_pulse := advance_combat_pulse(&room)
	testing.expect_value(t, room.enemies[0].health, i32(7))
	_, found = status_for_entity(&room, enemy_ref, .Poison)
	testing.expect(t, !found)
	expired_found := false
	for index in 0..<second_pulse.events.count {
		if second_pulse.events.events[index].kind == .Status_Expired {
			expired_found = true
		}
	}
	testing.expect(t, expired_found)
	_ = advance_combat_pulse(&room)
	testing.expect_value(t, room.enemies[0].health, i32(7))
}

// Every kind of intent carried out is an action: each bites once, a hit, a
// miss or a blocked step alike.
@(test)
test_poison_bites_after_every_intent_kind :: proc(t: ^testing.T) {
	for kind in ([?]Enemy_Intent_Kind{.Wait, .Recover, .Move, .Attack}) {
		level_data := create_test_level(t)
		player := create_test_player(t)
		enemy_spawns := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 10, attack = 1}}
		room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
		testing.expect(t, ok)
		enemy := &room.enemies[0]
		ref := enemy_entity(enemy.id)
		switch kind {
		case .Wait: enemy.intent = make_wait_intent(&room, enemy.position)
		case .Recover:
			enemy.intent = make_wait_intent(&room, enemy.position)
			enemy.intent.kind = .Recover
		case .Move:
			// Blocked by the player: a miss is still its action.
			enemy.intent = make_wait_intent(&room, enemy.position)
			enemy.intent.kind = .Move
			enemy.intent.destination = player.position
			enemy.intent.path[0] = enemy.intent.destination
			enemy.intent.path_count = 1
		case .Attack: enemy.intent = make_attack_intent(&room, enemy.position, player.position, 1)
		case .None, .Charge, .Bombard, .Protect:
		}
		apply_status(&room, ref, .Poison, 3, 0)
		pulse: Pulse_Report
		resolve_enemy_intents(&room, &pulse)
		testing.expect_value(t, room.enemies[0].health, i32(7))
		status, found := status_for_entity(&room, ref, .Poison)
		testing.expect(t, found && status.potency == 2)
		destroy_room(&room)
		level.destroy(&level_data)
	}
}

// The tactical roles' own intents (a charge, a bomb's windup, a protection)
// are actions too; a stagger that interrupts an intent is not.
@(test)
test_poison_bites_charges_windups_and_protections_but_not_an_interruption :: proc(t: ^testing.T) {
	Case :: struct {
		archetype:      Enemy_Archetype,
		position, ally: grid.Position,
		kind:           Enemy_Intent_Kind,
		staggered:      bool,
	}
	cases := [?]Case{
		{archetype = .Brute, position = {4, 1}, ally = {6, 6}, kind = .Charge},
		{archetype = .Bomber, position = {6, 2}, ally = {6, 6}, kind = .Bombard},
		{archetype = .Custodian, position = {2, 2}, ally = {2, 3}, kind = .Protect},
		{archetype = .Chaser, position = {4, 1}, ally = {6, 6}, kind = .Move, staggered = true},
	}
	for c in cases {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = c.position, health = 50, attack = 1, archetype = c.archetype},
			{position = c.ally, health = 50, attack = 1, archetype = .Chaser}}
		room := create_enemy_rework_room(t, &data, &player, spawns[:])
		enemy := &room.enemies[0]
		ref := enemy_entity(enemy.id)
		if c.kind == .Charge {
			// Lined up with the player, two cells between them.
			enemy.intent = make_wait_intent(&room, enemy.position)
			enemy.intent.kind = .Charge
			enemy.intent.destination = {4, 3}
			enemy.intent.path[0], enemy.intent.path[1] = {4, 2}, {4, 3}
			enemy.intent.path_count = 2
			enemy.intent.threatened_cells[0] = player.position
			enemy.intent.threatened_cell_count = 1
			enemy.intent.damage = 1
		} else if c.kind == .Move {
			enemy.intent = make_wait_intent(&room, enemy.position)
			enemy.intent.kind = .Move
			enemy.intent.destination = {4, 2}
			enemy.intent.path[0] = enemy.intent.destination
			enemy.intent.path_count = 1
		}
		testing.expect_value(t, enemy.intent.kind, c.kind)
		if c.kind == .Bombard { testing.expect(t, enemy.intent.windup) }
		if c.staggered { _, _ = apply_status(&room, ref, .Stagger, 1, 1) }
		_, _ = apply_status(&room, ref, .Poison, 3, 0)
		pulse: Pulse_Report
		resolve_enemy_intents(&room, &pulse, enemy.id)
		index, alive := enemy_index_by_id(&room, ref.id)
		testing.expect(t, alive)
		if alive {
			status, found := status_for_entity(&room, ref, .Poison)
			if c.staggered {
				testing.expect_value(t, room.enemies[index].health, i32(50))
				testing.expect(t, found && status.potency == 3)
			} else {
				testing.expect_value(t, room.enemies[index].health, i32(47))
				testing.expect(t, found && status.potency == 2)
			}
		}
		destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_poison_cause_survives_full_and_partial_shield_absorption :: proc(t: ^testing.T) {
	Case :: struct { poison, shield, damage: i32 }
	// Poison bypasses defense: the Shield takes its stacks first, then HP.
	for c in ([?]Case{{poison = 2, shield = 2, damage = 0}, {poison = 5, shield = 3, damage = 2}}) {
		level_data := create_test_level(t)
		defer level.destroy(&level_data)
		player := create_test_player(t)
		enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 4, attack = 1}}
		room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
		testing.expect(t, ok)
		defer destroy_room(&room)
		apply_status(&room, PLAYER_ENTITY, .Poison, c.poison, 0)
		apply_status(&room, PLAYER_ENTITY, .Shield, c.shield, 3)

		pulse: Pulse_Report
		tick_poison_on_action(&room, PLAYER_ENTITY, &pulse)

		testing.expect_value(t, pulse.damage_absorbed, c.shield)
		testing.expect_value(t, pulse.damage_dealt, c.damage)
		testing.expect_value(t, player.health, player.stats.max_health-c.damage)
		absorbed_count, damaged_count := 0, 0
		for index in 0..<pulse.events.count {
			event := pulse.events.events[index]
			if event.kind != .Damage_Absorbed && event.kind != .Damaged { continue }
			testing.expect(t, event.has_status_cause)
			testing.expect_value(t, event.status_cause, Status_Kind.Poison)
			if event.kind == .Damage_Absorbed {
				absorbed_count += 1
				testing.expect_value(t, event.amount, c.shield)
				testing.expect_value(t, event.status, Status_Kind.Shield)
			} else {
				damaged_count += 1
				testing.expect_value(t, event.amount, c.damage)
			}
		}
		testing.expect_value(t, absorbed_count, 1)
		testing.expect_value(t, damaged_count, 1 if c.damage > 0 else 0)
	}
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
test_player_poison_bites_his_own_actions_only_and_can_defeat_him :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	player.health = 3
	testing.expect_value(t, player.stats.defense, i32(1))
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 4, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	apply_status(&room, PLAYER_ENTITY, .Poison, 3, 0)

	// The enemies' pulse alone does not touch it.
	pulse := advance_combat_pulse(&room)
	testing.expect(t, !pulse.player_defeated)
	testing.expect_value(t, player.health, i32(3))
	// His wait does, by all its 3 stacks: his point of defense takes nothing
	// from a bite.
	testing.expect_value(t, wait_player_turn(&room), Action_Result.Player_Defeated)
	testing.expect_value(t, room.phase, Room_Phase.Defeat)
	testing.expect_value(t, player.health, i32(0))
	testing.expect(t, !player.deck.combat_active)
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
	// One stack each, spent by each enemy's response.
	_, first_poison_found := status_for_entity(&room, first_ref, .Poison)
	_, second_poison_found := status_for_entity(&room, second_ref, .Poison)
	testing.expect(t, !first_poison_found && !second_poison_found)
}
