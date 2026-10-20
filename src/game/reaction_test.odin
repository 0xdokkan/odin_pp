package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

@(test)
test_builtin_reaction_definitions_are_valid :: proc(t: ^testing.T) {
	testing.expect(t, validate_reaction_definitions())

	invalid, found := reaction_definition_by_id(.Thorns_Counter)
	testing.expect(t, found)
	invalid.effects[0].kind = .Move
	testing.expect(t, !validate_reaction_definition(&invalid))
}

@(test)
test_reaction_batch_sorts_by_priority_then_definition_id :: proc(t: ^testing.T) {
	batch: Reaction_Batch
	add_reaction_request(&batch, {definition_id = .Afterimage_Guard, priority = 10})
	add_reaction_request(&batch, {definition_id = .Afterimage_Guard, priority = 100})
	add_reaction_request(&batch, {definition_id = .Thorns_Counter, priority = 100})

	sort_reaction_batch(&batch)

	testing.expect_value(t, batch.items[0].definition_id, Reaction_Id.Thorns_Counter)
	testing.expect_value(t, batch.items[1].definition_id, Reaction_Id.Afterimage_Guard)
	testing.expect_value(t, batch.items[2].priority, i32(10))
}

@(test)
test_reaction_event_queue_is_fifo_across_wraparound :: proc(t: ^testing.T) {
	queue: Reaction_Event_Queue
	for index in 0..<MAX_REACTION_QUEUE_EVENTS {
		testing.expect(t, reaction_queue_push(&queue, {
			kind = .Damaged,
			amount = i32(index),
		}))
	}
	testing.expect(t, !reaction_queue_push(&queue, {kind = .Moved}))
	testing.expect_value(t, queue.dropped_count, 1)

	wrapped_count := MAX_REACTION_QUEUE_EVENTS/2
	for expected in 0..<wrapped_count {
		event, ok := reaction_queue_pop(&queue)
		testing.expect(t, ok)
		testing.expect_value(t, event.amount, i32(expected))
	}
	for index in 0..<wrapped_count {
		testing.expect(t, reaction_queue_push(&queue, {
			kind = .Healed,
			amount = i32(MAX_REACTION_QUEUE_EVENTS+index),
		}))
	}

	for expected in wrapped_count..<MAX_REACTION_QUEUE_EVENTS+wrapped_count {
		event, ok := reaction_queue_pop(&queue)
		testing.expect(t, ok)
		testing.expect_value(t, event.amount, i32(expected))
	}
	_, found := reaction_queue_pop(&queue)
	testing.expect(t, !found)
}

@(test)
test_afterimage_definition_converts_owner_movement_into_shield :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 4, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	apply_status(&room, PLAYER_ENTITY, .Afterimage, 2, 3)

	destination := grid.Position{x = 1, y = 2}
	action := make_action(.Move, PLAYER_ENTITY, cell_target(destination), .Walkable_Cell)
	testing.expect(t, add_effect(&action, move_effect(PLAYER_ENTITY, destination)))
	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	testing.expect_value(t, report.reactions_triggered, 1)
	testing.expect_value(t, report.events.count, 2)
	testing.expect_value(t, report.events.events[0].kind, Game_Event_Kind.Moved)
	testing.expect_value(t, report.events.events[1].kind, Game_Event_Kind.Status_Applied)
	shield, found := status_for_entity(&room, PLAYER_ENTITY, .Shield)
	testing.expect(t, found)
	testing.expect_value(t, shield.potency, i32(2))
	testing.expect_value(t, shield.remaining_pulses, i32(2))
}

@(test)
test_combat_only_reactions_do_not_trigger_during_loot :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	room, ok := create_room(&level_data, &player, {})
	testing.expect(t, ok)
	defer destroy_room(&room)
	apply_status(&room, PLAYER_ENTITY, .Afterimage, 2, 3)

	result := try_move_player(&room, .South)

	testing.expect_value(t, result, Action_Result.Moved)
	_, has_shield := status_for_entity(&room, PLAYER_ENTITY, .Shield)
	testing.expect(t, !has_shield)
}

@(test)
test_thorns_reacts_after_damage_and_preserves_event_order :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 6, attack = 3}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	apply_status(&room, PLAYER_ENTITY, .Thorns, 2, 3)

	enemy := room.enemies[0]
	action := make_action(.Attack, enemy_entity(enemy.id), entity_target(PLAYER_ENTITY), .Adjacent_Opponent)
	testing.expect(t, add_effect(&action, damage_effect(PLAYER_ENTITY, enemy.attack)))
	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	testing.expect_value(t, report.reactions_triggered, 1)
	testing.expect_value(t, report.reaction_events_processed, 2)
	testing.expect_value(t, report.damage_dealt, i32(4))
	testing.expect_value(t, player.health, i32(8))
	testing.expect_value(t, room.enemies[0].health, i32(4))
	testing.expect_value(t, report.events.count, 2)
	testing.expect_value(t, report.events.events[0].source, enemy_entity(enemy.id))
	testing.expect_value(t, report.events.events[0].target, PLAYER_ENTITY)
	testing.expect_value(t, report.events.events[1].source, PLAYER_ENTITY)
	testing.expect_value(t, report.events.events[1].target, enemy_entity(enemy.id))
}

@(test)
test_reaction_queue_preserves_damage_after_dense_deck_events :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 100, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	enemy_ref := enemy_entity(room.enemies[0].id)
	apply_status(&room, enemy_ref, .Thorns, 2, 3)

	action := make_action(.Ability, PLAYER_ENTITY, entity_target(enemy_ref), .Opponent)
	for index in 0..<9 {
		if index%2 == 0 {
			testing.expect(t, add_effect(&action, discard_cards_effect(MAX_HAND_CARDS)))
		} else {
			testing.expect(t, add_effect(&action, draw_cards_effect(MAX_HAND_CARDS)))
		}
	}
	testing.expect(t, add_effect(&action, damage_effect(enemy_ref, 1)))
	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	testing.expect(t, report.events.count > 64)
	testing.expect_value(t, report.reaction_events_dropped, 0)
	testing.expect_value(t, report.reactions_triggered, 1)
	testing.expect_value(t, report.reaction_events_processed, 71)
	testing.expect_value(t, room.enemies[0].health, i32(99))
	testing.expect_value(t, player.health, i32(9))
}

@(test)
test_thorns_does_not_react_to_fully_absorbed_damage :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 6, attack = 3}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	apply_status(&room, PLAYER_ENTITY, .Shield, 2, 3)
	apply_status(&room, PLAYER_ENTITY, .Thorns, 2, 3)

	enemy := room.enemies[0]
	action := make_action(.Attack, enemy_entity(enemy.id), entity_target(PLAYER_ENTITY), .Adjacent_Opponent)
	testing.expect(t, add_effect(&action, damage_effect(PLAYER_ENTITY, enemy.attack)))
	report := resolve_action(&room, &action)

	testing.expect_value(t, report.damage_absorbed, i32(2))
	testing.expect_value(t, report.damage_dealt, i32(0))
	testing.expect_value(t, report.reactions_triggered, 0)
	testing.expect_value(t, player.health, i32(10))
	testing.expect_value(t, room.enemies[0].health, i32(6))
}

@(test)
test_mutual_thorns_stops_at_the_iterative_chain_limit :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	player.stats.max_health = 100
	player.health = 100
	enemies := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 100, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	enemy_ref := enemy_entity(room.enemies[0].id)
	apply_status(&room, PLAYER_ENTITY, .Thorns, 1, 3)
	apply_status(&room, enemy_ref, .Thorns, 1, 3)

	action := make_action(.Attack, PLAYER_ENTITY, entity_target(enemy_ref), .Adjacent_Opponent)
	testing.expect(t, add_effect(&action, damage_effect(enemy_ref, player.stats.attack)))
	report := resolve_action(&room, &action)

	testing.expect_value(t, report.reactions_triggered, MAX_REACTION_ACTIONS_PER_CHAIN)
	testing.expect(t, report.reaction_limit_reached)
	testing.expect_value(t, report.reactions_dropped, 1)
	testing.expect_value(t, report.reaction_events_processed, MAX_REACTION_ACTIONS_PER_CHAIN+1)
	testing.expect(t, player.health > 0)
	testing.expect(t, room.enemies[0].health > 0)
}

@(test)
test_thorns_can_remove_current_enemies_without_breaking_the_scheduler :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{
		{position = {x = 2, y = 1}, health = 1, attack = 2},
		{position = {x = 1, y = 2}, health = 1, attack = 2},
	}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	apply_status(&room, PLAYER_ENTITY, .Thorns, 1, 3)

	for &enemy in room.enemies { enemy.tactical_cooldown = 1 }
	result := wait_player_turn(&room)

	testing.expect_value(t, result, Action_Result.None)
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, player.health, i32(8))
	testing.expect_value(t, len(room.enemies), 0)
	testing.expect_value(t, room.phase, Room_Phase.Loot)
}

@(test)
test_thorn_coat_is_one_action_and_reacts_in_the_same_pulse :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 4, attack = 2}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	for &enemy in room.enemies { enemy.tactical_cooldown = 1 }
	result := use_player_ability(&room, .Thorn_Coat)

	testing.expect_value(t, result, Action_Result.Used_Ability)
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect_value(t, player.health, i32(9))
	testing.expect_value(t, room.enemies[0].health, i32(3))
	thorns, found := status_for_entity(&room, PLAYER_ENTITY, .Thorns)
	testing.expect(t, found)
	testing.expect_value(t, thorns.remaining_pulses, i32(2))
}

@(test)
test_afterimage_ability_arms_future_movement_reactions :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 4, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	result := use_player_ability(&room, .Afterimage)
	testing.expect_value(t, result, Action_Result.Used_Ability)
	_, shielded_on_cast := status_for_entity(&room, PLAYER_ENTITY, .Shield)
	testing.expect(t, !shielded_on_cast)
	afterimage, found := status_for_entity(&room, PLAYER_ENTITY, .Afterimage)
	testing.expect(t, found)
	testing.expect_value(t, afterimage.remaining_pulses, i32(4))

	drain_tactical_test_pulse(t, &room)
	result = try_move_player(&room, .South)
	testing.expect_value(t, result, Action_Result.Moved)
	drain_tactical_test_pulse(t, &room)
	shield, shielded_after_move := status_for_entity(&room, PLAYER_ENTITY, .Shield)
	testing.expect(t, shielded_after_move)
	testing.expect_value(t, shield.potency, i32(1))
	// The shorter step triggers the shield immediately but does not spend
	// its first pulse until the world's next beat arrives.
	testing.expect_value(t, shield.remaining_pulses, i32(2))
	testing.expect_value(t, room.pulse_count, u64(1))
	tactical_tick(&room, 1-TACTICAL_MOVE_SECONDS, true, false)
	drain_tactical_test_pulse(t, &room)
	shield, shielded_after_move = status_for_entity(&room, PLAYER_ENTITY, .Shield)
	testing.expect(t, shielded_after_move)
	testing.expect_value(t, shield.remaining_pulses, i32(1))
	testing.expect_value(t, room.pulse_count, u64(2))
}

@(test)
test_runtime_binding_triggers_without_status_and_consumes_charges :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 10, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	install := make_action(.Ability, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
	testing.expect(t, add_effect(&install, add_reaction_binding_effect(
		PLAYER_ENTITY,
		.Thorns_Counter,
		2,
		2,
		4,
		0,
		{kind = .Card, id = 42},
	)))
	install_report := resolve_action(&room, &install)
	testing.expect(t, install_report.accepted)
	testing.expect_value(t, install_report.reaction_bindings_added, 1)
	testing.expect_value(t, install_report.events.events[0].kind, Game_Event_Kind.Reaction_Binding_Added)
	binding_id := install_report.events.events[0].binding_id

	enemy := room.enemies[0]
	first_attack := make_action(.Attack, enemy_entity(enemy.id), entity_target(PLAYER_ENTITY), .Adjacent_Opponent)
	testing.expect(t, add_effect(&first_attack, damage_effect(PLAYER_ENTITY, enemy.attack)))
	first_report := resolve_action(&room, &first_attack)
	testing.expect_value(t, first_report.reactions_triggered, 1)
	binding, found := reaction_binding_by_id(&room, binding_id)
	testing.expect(t, found)
	testing.expect_value(t, binding.remaining_charges, i32(1))
	testing.expect_value(t, binding.source, Reaction_Binding_Source{kind = .Card, id = 42})

	second_attack := make_action(.Attack, enemy_entity(enemy.id), entity_target(PLAYER_ENTITY), .Adjacent_Opponent)
	testing.expect(t, add_effect(&second_attack, damage_effect(PLAYER_ENTITY, enemy.attack)))
	second_report := resolve_action(&room, &second_attack)
	testing.expect_value(t, second_report.reactions_triggered, 1)
	testing.expect_value(t, second_report.reaction_bindings_removed, 1)
	_, found = reaction_binding_by_id(&room, binding_id)
	testing.expect(t, !found)
	exhausted := second_report.events.events[second_report.events.count-1]
	testing.expect_value(t, exhausted.kind, Game_Event_Kind.Reaction_Binding_Exhausted)
	testing.expect_value(t, exhausted.binding_source, Reaction_Binding_Source{kind = .Card, id = 42})

	third_attack := make_action(.Attack, enemy_entity(enemy.id), entity_target(PLAYER_ENTITY), .Adjacent_Opponent)
	testing.expect(t, add_effect(&third_attack, damage_effect(PLAYER_ENTITY, enemy.attack)))
	third_report := resolve_action(&room, &third_attack)
	testing.expect_value(t, third_report.reactions_triggered, 0)
	testing.expect_value(t, room.enemies[0].health, i32(6))
}

@(test)
test_runtime_binding_expires_after_its_pulse_duration :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 10, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	binding_id, added := add_reaction_binding(&room, {
		definition_id = .Afterimage_Guard,
		owner = PLAYER_ENTITY,
		potency = 2,
		charges = REACTION_BINDING_UNLIMITED,
		duration = 2,
		source = {kind = .Passive, id = 7},
	})
	testing.expect(t, added)

	first_pulse := advance_combat_pulse(&room)
	testing.expect_value(t, first_pulse.reaction_bindings_removed, 0)
	binding, found := reaction_binding_by_id(&room, binding_id)
	testing.expect(t, found)
	testing.expect_value(t, binding.remaining_pulses, i32(1))

	second_pulse := advance_combat_pulse(&room)
	testing.expect_value(t, second_pulse.reaction_bindings_removed, 1)
	_, found = reaction_binding_by_id(&room, binding_id)
	testing.expect(t, !found)
	expired := second_pulse.events.events[second_pulse.events.count-2]
	testing.expect_value(t, expired.kind, Game_Event_Kind.Reaction_Binding_Expired)
	testing.expect_value(t, expired.binding_source, Reaction_Binding_Source{kind = .Passive, id = 7})
	testing.expect_value(
		t,
		second_pulse.events.events[second_pulse.events.count-1].kind,
		Game_Event_Kind.Pulse_Advanced,
	)
}

@(test)
test_binding_priority_modifier_orders_it_before_status_activation :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 10, attack = 3}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	apply_status(&room, PLAYER_ENTITY, .Thorns, 1, 3)
	_, added := add_reaction_binding(&room, {
		definition_id = .Thorns_Counter,
		owner = PLAYER_ENTITY,
		potency = 2,
		charges = REACTION_BINDING_UNLIMITED,
		duration = REACTION_BINDING_UNLIMITED,
		priority_modifier = 100,
		source = {kind = .Passive, id = 9},
	})
	testing.expect(t, added)

	enemy := room.enemies[0]
	action := make_action(.Attack, enemy_entity(enemy.id), entity_target(PLAYER_ENTITY), .Adjacent_Opponent)
	testing.expect(t, add_effect(&action, damage_effect(PLAYER_ENTITY, enemy.attack)))
	report := resolve_action(&room, &action)

	testing.expect_value(t, report.reactions_triggered, 2)
	testing.expect_value(t, report.events.count, 3)
	testing.expect_value(t, report.events.events[1].amount, i32(2))
	testing.expect_value(t, report.events.events[2].amount, i32(1))
	testing.expect_value(t, room.enemies[0].health, i32(7))
}

@(test)
test_enemy_death_removes_its_runtime_bindings :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 2, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	enemy_ref := enemy_entity(room.enemies[0].id)
	_, added := add_reaction_binding(&room, {
		definition_id = .Afterimage_Guard,
		owner = enemy_ref,
		potency = 1,
		charges = REACTION_BINDING_UNLIMITED,
		duration = REACTION_BINDING_UNLIMITED,
		source = {kind = .Passive, id = 1},
	})
	testing.expect(t, added)

	result := try_move_player(&room, .East)

	testing.expect_value(t, result, Action_Result.Combat_Ended)
	testing.expect_value(t, room.reaction_bindings.count, 0)
}

@(test)
test_stale_reaction_request_does_not_consume_its_binding_charge :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 5, attack = 2}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	_, high_added := add_reaction_binding(&room, {
		definition_id = .Thorns_Counter,
		owner = PLAYER_ENTITY,
		potency = 5,
		charges = 1,
		duration = 3,
		priority_modifier = 100,
		source = {kind = .Card, id = 1},
	})
	low_id, low_added := add_reaction_binding(&room, {
		definition_id = .Thorns_Counter,
		owner = PLAYER_ENTITY,
		potency = 1,
		charges = 1,
		duration = 3,
		priority_modifier = 0,
		source = {kind = .Card, id = 2},
	})
	testing.expect(t, high_added && low_added)

	enemy := room.enemies[0]
	action := make_action(.Attack, enemy_entity(enemy.id), entity_target(PLAYER_ENTITY), .Adjacent_Opponent)
	testing.expect(t, add_effect(&action, damage_effect(PLAYER_ENTITY, enemy.attack)))
	report := resolve_action(&room, &action)

	testing.expect_value(t, report.reactions_triggered, 1)
	testing.expect_value(t, room.phase, Room_Phase.Loot)
	low_binding, found := reaction_binding_by_id(&room, low_id)
	testing.expect(t, found)
	testing.expect_value(t, low_binding.remaining_charges, i32(1))
}
