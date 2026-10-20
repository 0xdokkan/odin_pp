package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

fire_hazard_event_count :: proc(log: ^Event_Log, kind: Game_Event_Kind) -> int {
	if log == nil {
		return 0
	}
	count := 0
	for event in log.events[:log.count] {
		if event.kind == kind {
			count += 1
		}
	}
	return count
}

@(test)
test_traverse_through_fire_triggers_each_entered_cell_without_consuming_it :: proc(
	t: ^testing.T,
) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 8, attack = 1}}
	objects := [?]Grid_Object_Spawn{
		{kind = .Fire, position = {x = 2, y = 1}},
		{kind = .Fire, position = {x = 3, y = 1}},
	}
	room, ok := create_room(&level_data, &player, {
		enemies = enemies[:],
		objects = objects[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)
	action := make_action(.Move, PLAYER_ENTITY, cell_target({x = 3, y = 1}), .Walkable_Cell)
	testing.expect(t, add_effect(&action, move_effect(PLAYER_ENTITY, {x = 3, y = 1})))

	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	testing.expect_value(t, player.position.x, 3)
	testing.expect_value(t, player.position.y, 1)
	// Player defense reduces each definition-level hit from 2 to 1.
	testing.expect_value(t, player.health, i32(8))
	testing.expect_value(t, len(room.objects), 2)
	testing.expect_value(t, fire_hazard_event_count(&report.events, .Hazard_Triggered), 2)
	testing.expect_value(t, fire_hazard_event_count(&report.events, .Damaged), 2)
	testing.expect_value(t, report.events.events[0].kind, Game_Event_Kind.Movement_Step)
	testing.expect_value(t, report.events.events[1].kind, Game_Event_Kind.Hazard_Triggered)
	testing.expect_value(t, report.events.events[2].kind, Game_Event_Kind.Damaged)
	testing.expect_value(t, report.events.events[3].kind, Game_Event_Kind.Moved)
	testing.expect_value(t, report.events.events[4].kind, Game_Event_Kind.Hazard_Triggered)
	testing.expect_value(t, report.events.events[5].kind, Game_Event_Kind.Damaged)
}

@(test)
test_fire_uses_shield_pipeline_and_remains_active :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 8, attack = 1}}
	objects := [?]Grid_Object_Spawn{{kind = .Fire, position = {x = 2, y = 1}}}
	room, ok := create_room(&level_data, &player, {
		enemies = enemies[:],
		objects = objects[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)
	player.position = room.objects[0].position
	applied, created := apply_status(&room, PLAYER_ENTITY, .Shield, 2, 2)
	testing.expect(t, applied && created)
	health_before := player.health

	resolution := resolve_grid_object_hazard_for_entity(&room, PLAYER_ENTITY)

	testing.expect(t, resolution.triggered)
	testing.expect_value(t, resolution.object_id, room.objects[0].id)
	testing.expect(t, resolution.report.accepted)
	testing.expect_value(t, resolution.report.damage_absorbed, i32(1))
	testing.expect_value(t, resolution.report.damage_dealt, i32(0))
	testing.expect_value(t, player.health, health_before)
	testing.expect_value(t, fire_hazard_event_count(&resolution.report.events, .Hazard_Triggered), 1)
	testing.expect_value(t, fire_hazard_event_count(&resolution.report.events, .Damage_Absorbed), 1)
	testing.expect_value(t, fire_hazard_event_count(&resolution.report.events, .Damaged), 0)
	testing.expect_value(t, len(room.objects), 1)
}

@(test)
test_enemy_killed_entering_fire_drops_loot_and_ends_combat :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 2, attack = 1}}
	objects := [?]Grid_Object_Spawn{{kind = .Fire, position = {x = 3, y = 1}}}
	room, ok := create_room(&level_data, &player, {
		enemies = enemies[:],
		objects = objects[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)
	enemy := enemy_entity(room.enemies[0].id)
	action := make_action(.Move, enemy, cell_target({x = 3, y = 1}), .Walkable_Cell)
	testing.expect(t, add_effect(&action, move_effect(enemy, {x = 3, y = 1})))

	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	testing.expect(t, report.combat_ended)
	testing.expect_value(t, report.enemies_defeated, 1)
	testing.expect_value(t, room.phase, Room_Phase.Loot)
	testing.expect_value(t, len(room.enemies), 0)
	testing.expect_value(t, len(room.loot), 1)
	testing.expect_value(t, len(room.objects), 1)
	testing.expect_value(t, fire_hazard_event_count(&report.events, .Hazard_Triggered), 1)
	testing.expect_value(t, fire_hazard_event_count(&report.events, .Entity_Defeated), 1)
	testing.expect_value(t, fire_hazard_event_count(&report.events, .Loot_Dropped), 1)
}

@(test)
test_fire_stays_dangerous_in_loot_without_advancing_a_pulse :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	objects := [?]Grid_Object_Spawn{{kind = .Fire, position = {x = 2, y = 1}}}
	room, ok := create_room(&level_data, &player, {objects = objects[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	testing.expect_value(t, room.phase, Room_Phase.Loot)
	pulse_before := room.pulse_count

	result := try_move_player(&room, .East)

	testing.expect_value(t, result, Action_Result.Moved)
	testing.expect_value(t, player.health, i32(9))
	testing.expect_value(t, room.pulse_count, pulse_before)
	testing.expect_value(t, len(room.objects), 1)
	testing.expect_value(t, fire_hazard_event_count(room.recent_events, .Hazard_Triggered), 1)
	testing.expect_value(t, fire_hazard_event_count(room.recent_events, .Damaged), 1)
}

@(test)
test_wait_while_standing_on_fire_does_not_retrigger_it :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 8, attack = 1}}
	objects := [?]Grid_Object_Spawn{{kind = .Fire, position = {x = 2, y = 1}}}
	room, ok := create_room(&level_data, &player, {
		enemies = enemies[:],
		objects = objects[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)

	move_result := try_move_player(&room, .East)
	testing.expect_value(t, move_result, Action_Result.Moved)
	testing.expect_value(t, fire_hazard_event_count(room.recent_events, .Hazard_Triggered), 1)
	drain_tactical_test_pulse(t, &room)
	health_after_entry := player.health
	pulse_after_entry := room.pulse_count

	wait_result := wait_player_turn(&room)
	drain_tactical_test_pulse(t, &room)

	testing.expect_value(t, wait_result, Action_Result.None)
	testing.expect_value(t, room.pulse_count, pulse_after_entry+1)
	testing.expect_value(t, player.health, health_after_entry)
	testing.expect_value(t, fire_hazard_event_count(room.recent_events, .Hazard_Triggered), 0)
	testing.expect_value(t, len(room.objects), 1)
}

@(test)
test_teleport_triggers_only_fire_on_its_landing_cell :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 8, attack = 1}}
	objects := [?]Grid_Object_Spawn{
		{kind = .Fire, position = {x = 2, y = 1}},
		{kind = .Fire, position = {x = 3, y = 1}},
	}
	room, ok := create_room(&level_data, &player, {
		enemies = enemies[:],
		objects = objects[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)
	action := make_action(.Move, PLAYER_ENTITY, cell_target({x = 3, y = 1}), .Walkable_Cell)
	testing.expect(t, add_effect(
		&action,
		move_effect(PLAYER_ENTITY, {x = 3, y = 1}, .Teleport),
	))

	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	testing.expect_value(t, player.position.x, 3)
	testing.expect_value(t, player.position.y, 1)
	testing.expect_value(t, player.health, i32(9))
	testing.expect_value(t, fire_hazard_event_count(&report.events, .Moved), 1)
	testing.expect_value(t, fire_hazard_event_count(&report.events, .Movement_Step), 0)
	testing.expect_value(t, fire_hazard_event_count(&report.events, .Hazard_Triggered), 1)
	testing.expect_value(t, len(room.objects), 2)
}

@(test)
test_fire_rejects_targeting_damage_and_forced_movement :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 8, attack = 1}}
	objects := [?]Grid_Object_Spawn{{kind = .Fire, position = {x = 2, y = 1}}}
	room, ok := create_room(&level_data, &player, {
		enemies = enemies[:],
		objects = objects[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)
	fire := object_entity(room.objects[0].id)

	testing.expect(t, entity_exists(&room, fire))
	testing.expect(t, !entity_is_targetable_object(&room, fire))
	testing.expect(t, !target_matches_rule(
		&room,
		PLAYER_ENTITY,
		entity_target(fire),
		.Opponent_Or_Object,
	))
	testing.expect(t, !effect_is_valid(&room, damage_effect(fire, 2)))
	movement := query_entity_movement(&room, fire, {x = 3, y = 1})
	testing.expect_value(t, movement.error, Movement_Error.Invalid_Mover)
}

@(test)
test_shove_damages_ice_but_cannot_overlap_it_with_fire :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 8, attack = 1}}
	ice_position := grid.Position{x = 2, y = 1}
	fire_position := grid.Position{x = 3, y = 1}
	objects := [?]Grid_Object_Spawn{
		{kind = .Ice_Block, position = ice_position},
		{kind = .Fire, position = fire_position},
	}
	room, ok := create_room(&level_data, &player, {
		enemies = enemies[:],
		objects = objects[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)
	ice := room.objects[0]
	fire := room.objects[1]
	card := Card_Instance{id = 801, definition_id = .Shove}

	evaluation := evaluate_card_targeting(&room, card, {
		anchor = ice_position,
		has_anchor = true,
	})
	testing.expect_value(t, evaluation.error, Card_Compile_Error.None)
	testing.expect(t, evaluation.has_movement)
	testing.expect_value(t, evaluation.movement.error, Movement_Error.Object_Blocker)
	testing.expect(t, evaluation.movement.has_blocker)
	testing.expect_value(t, evaluation.movement.blocker, fire_position)
	action, compile_error := compile_card_action(
		&room,
		card,
		entity_target(object_entity(ice.id)),
	)
	testing.expect_value(t, compile_error, Card_Compile_Error.None)

	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	testing.expect_value(t, report.applied_effects, 1)
	testing.expect_value(t, report.skipped_effects, 1)
	testing.expect_value(t, report.damage_dealt, i32(1))
	testing.expect_value(t, len(room.objects), 2)
	ice_index, ice_found := object_index_by_id(&room, ice.id)
	fire_index, fire_found := object_index_by_id(&room, fire.id)
	testing.expect(t, ice_found && fire_found)
	if ice_found {
		testing.expect_value(t, room.objects[ice_index].position, ice_position)
		testing.expect_value(t, room.objects[ice_index].health, i32(3))
	}
	if fire_found {
		testing.expect_value(t, room.objects[fire_index].position, fire_position)
	}
	testing.expect_value(t, fire_hazard_event_count(&report.events, .Moved), 0)
	testing.expect_value(t, fire_hazard_event_count(&report.events, .Hazard_Triggered), 0)
}
