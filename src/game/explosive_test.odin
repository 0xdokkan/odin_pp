package game

import "core:testing"
import grid "../grid"
import level "../level"

@(test)
test_starter_damage_cards_can_ignite_barrels :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	definitions := [?]Card_Id{.Strike, .Arc_Bolt, .Firebomb}
	for definition in definitions {
		player := create_test_player(t)
		objects := [?]Grid_Object_Spawn{{kind = .Barrel, position = {2, 1}}}
		room := make_explosive_test_room(t, &data, &player, objects[:])
		target := entity_target(object_entity(room.objects[0].id))
		if definition == .Firebomb {
			target = cell_target({2, 2})
		}
		card_id := force_card_definition_into_hand(t, &player.deck, definition)
		play := play_card(&room, card_id, target)
		testing.expect_value(t, play.result, Card_Play_Result.Played)
		testing.expect_value(t, room.objects[0].detonation_pulse, u64(3))
		testing.expect_value(t, room.objects[0].health, i32(1))
		testing.expect_value(t, spatial_card_event_count(&room.recent_events, .Explosive_Armed), 1)
		destroy_room(&room)
	}
}

@(test)
test_loot_phase_can_clear_blocks_pushed_into_exit_path :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	kinds := [?]Grid_Object_Kind{.Barrel, .Ice_Block}
	for kind in kinds {
		player := create_test_player(t)
		objects := [?]Grid_Object_Spawn{{kind = kind, position = {2, 1}}}
		room, ok := create_room(&data, &player, {objects = objects[:]})
		testing.expect(t, ok)
		for _ in 0..<2 {
			if len(room.objects) > 0 {
				testing.expect_value(t, try_move_player(&room, .East), Action_Result.Attacked)
			}
		}
		testing.expect_value(t, len(room.objects), 0)
		testing.expect_value(t, try_move_player(&room, .East), Action_Result.Moved)
		testing.expect_value(t, player.position, grid.Position{2, 1})
		testing.expect_value(t, room.pulse_count, u64(0))
		destroy_room(&room)
	}
}

make_explosive_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, objects: []Grid_Object_Spawn) -> Room {
	enemies := [?]Enemy_Spawn{{position = {8, 4}, health = 20, attack = 1}}
	room, ok := create_room(data, player, {enemies = enemies[:], objects = objects})
	testing.expect(t, ok)
	room.enemies[0].recovery_pulses = 100
	plan_enemy_intents(&room)
	return room
}

@(test)
test_shove_arms_and_moves_barrel_with_two_further_decisions :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	objects := [?]Grid_Object_Spawn{{kind = .Barrel, position = {2, 1}}}
	room := make_explosive_test_room(t, &data, &player, objects[:])
	defer destroy_room(&room)
	id := room.objects[0].id
	card_id := force_card_definition_into_hand(t, &player.deck, .Shove)
	play := play_card(&room, card_id, entity_target(object_entity(id)))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, room.objects[0].position, grid.Position{3, 1})
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect_value(t, explosive_pulses_remaining(room.objects[0].detonation_pulse, room.pulse_count), 2)
	testing.expect_value(t, spatial_card_event_count(&room.recent_events, .Explosive_Armed), 1)
	testing.expect_value(t, try_move_player(&room, .North), Action_Result.Blocked)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect(t, !arm_explosive(&room, id, PLAYER_ENTITY, &room.recent_events))
	testing.expect_value(t, wait_player_turn(&room), Action_Result.None)
	testing.expect_value(t, explosive_pulses_remaining(room.objects[0].detonation_pulse, room.pulse_count), 1)
	testing.expect_value(t, wait_player_turn(&room), Action_Result.None)
	_, exists := object_index_by_id(&room, id)
	testing.expect(t, !exists)
	testing.expect_value(t, player.health, i32(10))
	testing.expect_value(t, spatial_card_event_count(&room.recent_events, .Explosion), 1)
}

@(test)
test_armed_bomb_can_be_shoved_without_resetting_fuse :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	room := make_explosive_test_room(t, &data, &player, nil)
	defer destroy_room(&room)
	testing.expect(t, spawn_bomb(&room, SYSTEM_ENTITY, {2, 1}, &room.recent_events))
	id := room.objects[0].id
	deadline := room.objects[0].detonation_pulse
	card := Card_Instance{id = 901, definition_id = .Shove}
	action, err := compile_card_action(&room, card, entity_target(object_entity(id)))
	testing.expect_value(t, err, Card_Compile_Error.None)
	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted)
	testing.expect_value(t, report.skipped_effects, 1)
	testing.expect_value(t, room.objects[0].position, grid.Position{3, 1})
	testing.expect_value(t, room.objects[0].detonation_pulse, deadline)
	testing.expect(t, !cell_blocks_movement(&room, room.objects[0].position))
}

@(test)
test_chain_explosion_arms_next_barrel_with_fresh_fuse :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	objects := [?]Grid_Object_Spawn{
		{kind = .Barrel, position = {3, 2}}, {kind = .Barrel, position = {4, 2}},
		{kind = .Ice_Block, position = {3, 3}},
	}
	room := make_explosive_test_room(t, &data, &player, objects[:])
	defer destroy_room(&room)
	first_id, second_id := room.objects[0].id, room.objects[1].id
	room.objects[0].detonation_pulse = 1
	pulse := advance_combat_pulse(&room)
	testing.expect_value(t, pulse.objects_destroyed, 2)
	testing.expect_value(t, spatial_card_event_count(&pulse.events, .Explosion), 1)
	_, first_exists := object_index_by_id(&room, first_id)
	testing.expect(t, !first_exists)
	index, found := object_index_by_id(&room, second_id)
	testing.expect(t, found)
	testing.expect_value(t, explosive_pulses_remaining(room.objects[index].detonation_pulse, room.pulse_count), 2)
	advance_combat_pulse(&room)
	testing.expect_value(t, len(room.objects), 1)
	pulse = advance_combat_pulse(&room)
	testing.expect_value(t, len(room.objects), 0)
	testing.expect_value(t, spatial_card_event_count(&pulse.events, .Explosion), 1)
}

@(test)
test_barrel_moved_next_to_fire_ignites_without_taking_hazard_damage :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	objects := [?]Grid_Object_Spawn{{kind = .Barrel, position = {2, 2}}, {kind = .Fire, position = {4, 2}}}
	room := make_explosive_test_room(t, &data, &player, objects[:])
	defer destroy_room(&room)
	barrel := object_entity(room.objects[0].id)
	action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(barrel), .Entity)
	testing.expect(t, add_effect(&action, move_effect(barrel, {3, 2})))
	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted)
	testing.expect_value(t, room.objects[0].detonation_pulse, u64(3))
	testing.expect_value(t, report.damage_dealt, i32(0))
	testing.expect_value(t, spatial_card_event_count(&report.events, .Explosive_Armed), 1)
}

@(test)
test_explosion_friendly_fire_obeys_shield_and_destroys_last_enemy_before_attack :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	objects := [?]Grid_Object_Spawn{{kind = .Barrel, position = {2, 2}}}
	room := make_explosive_test_room(t, &data, &player, objects[:])
	defer destroy_room(&room)
	room.enemies[0].position = {2, 1}
	room.enemies[0].health = 4
	room.enemies[0].recovery_pulses = 0
	plan_enemy_intents(&room)
	action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(PLAYER_ENTITY), .Entity)
	testing.expect(t, add_effect(&action, apply_status_effect(PLAYER_ENTITY, .Shield, 2, 3)))
	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted)
	room.objects[0].detonation_pulse = 1
	pulse := advance_combat_pulse(&room)
	testing.expect_value(t, room.phase, Room_Phase.Loot)
	testing.expect_value(t, pulse.enemy_actions, 0)
	testing.expect_value(t, player.health, i32(9))
	testing.expect_value(t, pulse.damage_absorbed, i32(2))
	testing.expect_value(t, pulse.enemies_defeated, 1)
}

@(test)
test_simultaneous_explosion_deaths_preserve_defeat_and_disarm_other_bombs :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	objects := [?]Grid_Object_Spawn{{kind = .Barrel, position = {2, 2}}, {kind = .Barrel, position = {6, 2}}}
	room := make_explosive_test_room(t, &data, &player, objects[:])
	defer destroy_room(&room)
	player.health = 1
	room.enemies[0].position = {2, 1}
	room.enemies[0].health = 1
	plan_enemy_intents(&room)
	room.objects[0].detonation_pulse = 1
	room.objects[1].detonation_pulse = 2
	pulse := advance_combat_pulse(&room)
	testing.expect_value(t, player.health, i32(0))
	testing.expect_value(t, len(room.enemies), 0)
	testing.expect_value(t, room.phase, Room_Phase.Defeat)
	testing.expect(t, pulse.player_defeated)
	testing.expect_value(t, len(room.objects), 1)
	testing.expect_value(t, room.objects[0].detonation_pulse, u64(0))
	testing.expect_value(t, spatial_card_event_count(&pulse.events, .Explosive_Disarmed), 1)
}

@(test)
test_bombs_disarm_when_player_finishes_combat :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	room := make_explosive_test_room(t, &data, &player, nil)
	defer destroy_room(&room)
	testing.expect(t, spawn_bomb(&room, SYSTEM_ENTITY, player.position, &room.recent_events))
	room.enemies[0].position = {2, 1}
	room.enemies[0].health = 1
	plan_enemy_intents(&room)
	testing.expect_value(t, try_move_player(&room, .East), Action_Result.Combat_Ended)
	testing.expect_value(t, room.objects[0].detonation_pulse, u64(0))
	testing.expect_value(t, player.health, i32(10))
	testing.expect_value(t, spatial_card_event_count(&room.recent_events, .Explosive_Disarmed), 1)
}

@(test)
test_bomb_capacity_failed_spawn_is_atomic_and_ids_are_not_reused :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	room := make_explosive_test_room(t, &data, &player, nil)
	defer destroy_room(&room)
	for x in 2..<2+MAX_ACTIVE_BOMBS {
		testing.expect(t, spawn_bomb(&room, SYSTEM_ENTITY, {x, 2}, &room.recent_events))
	}
	next_id := room.next_object_id
	count := room.recent_events.count
	testing.expect(t, !spawn_bomb(&room, SYSTEM_ENTITY, {7, 2}, &room.recent_events))
	testing.expect_value(t, room.next_object_id, next_id)
	testing.expect_value(t, room.recent_events.count, count)
	testing.expect(t, remove_grid_object(&room, 0))
	testing.expect(t, spawn_bomb(&room, SYSTEM_ENTITY, {7, 2}, &room.recent_events))
	testing.expect_value(t, room.objects[len(room.objects)-1].id, next_id)
	testing.expect(t, remove_grid_object(&room, 0))
	room.next_object_id = max(u32)
	testing.expect(t, !spawn_bomb(&room, SYSTEM_ENTITY, {7, 3}, &room.recent_events))
	testing.expect_value(t, room.next_object_id, max(u32))
}

@(test)
test_due_explosions_have_stable_id_order_after_unordered_storage :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	objects := [?]Grid_Object_Spawn{{kind = .Barrel, position = {4, 2}}, {kind = .Barrel, position = {6, 2}}}
	room := make_explosive_test_room(t, &data, &player, objects[:])
	defer destroy_room(&room)
	for &object in room.objects {
		object.detonation_pulse = 1
	}
	room.objects[0], room.objects[1] = room.objects[1], room.objects[0]
	pulse := advance_combat_pulse(&room)
	last_id: u32
	for event in pulse.events.events[:pulse.events.count] {
		if event.kind == .Explosion {
			testing.expect(t, event.source.id > last_id)
			last_id = event.source.id
		}
	}
	testing.expect_value(t, spatial_card_event_count(&pulse.events, .Explosion), 2)
	testing.expect_value(t, pulse.events.dropped_count, 0)
}
