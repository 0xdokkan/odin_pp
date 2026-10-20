package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

make_ice_block_combat_room :: proc(
	t: ^testing.T,
	level_data: ^level.Level,
	player: ^Player,
	object_position: grid.Position,
	trap_position: grid.Position = {},
	with_trap: bool = false,
) -> Room {
	enemies := [?]Enemy_Spawn{{
		position = {x = 5, y = 3},
		health = 8,
		attack = 1,
	}}
	objects := [?]Grid_Object_Spawn{{
		kind = .Ice_Block,
		position = object_position,
	}}
	traps: [1]Trap_Spawn
	trap_count := 0
	if with_trap {
		traps[0] = {position = trap_position, damage = 3}
		trap_count = 1
	}
	room, ok := create_room(level_data, player, {
		enemies = enemies[:],
		objects = objects[:],
		traps = traps[:trap_count],
	})
	testing.expect(t, ok)
	return room
}

@(test)
test_ice_block_blocks_player_and_enemy_movement :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	room := make_ice_block_combat_room(t, &level_data, &player, {x = 2, y = 1})
	defer destroy_room(&room)

	player_result := try_move_player(&room, .East)
	testing.expect_value(t, player_result, Action_Result.Blocked)
	testing.expect_value(t, player.position, grid.Position{x = 1, y = 1})

	enemy_index := 0
	room.enemies[enemy_index].position = {x = 3, y = 1}
	testing.expect(t, !enemy_can_move_to(&room, enemy_index, {x = 2, y = 1}))
	query := query_entity_movement(
		&room,
		enemy_entity(room.enemies[enemy_index].id),
		{x = 2, y = 1},
	)
	testing.expect_value(t, query.error, Movement_Error.Static_Blocker)
}

@(test)
test_ice_block_occludes_entities_behind_it_but_is_targetable_itself :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 4, y = 1}, health = 8, attack = 1}}
	objects := [?]Grid_Object_Spawn{{kind = .Ice_Block, position = {x = 3, y = 1}}}
	room, ok := create_room(&level_data, &player, {
		enemies = enemies[:],
		objects = objects[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)

	blocked := evaluate_target_query(&room, PLAYER_ENTITY, {
		rule = .Opponent,
		cast_range = {.Chebyshev, 1, 4},
		shape = .Single,
		requires_line_of_sight = true,
	}, {
		anchor = room.enemies[0].position,
		has_anchor = true,
	})
	testing.expect_value(t, blocked.error, Target_Query_Error.Line_Of_Sight_Blocked)
	testing.expect_value(t, blocked.blocker, grid.Position{x = 3, y = 1})

	object := room.objects[0]
	targetable := evaluate_target_query(&room, PLAYER_ENTITY, {
		rule = .Opponent_Or_Object,
		cast_range = {.Chebyshev, 1, 3},
		shape = .Single,
		requires_line_of_sight = true,
	}, {
		anchor = object.position,
		has_anchor = true,
	})
	testing.expect_value(t, targetable.error, Target_Query_Error.None)
	testing.expect_value(t, targetable.primary_target, entity_target(object_entity(object.id)))
	testing.expect(t, target_cell_set_contains(&targetable.affected, object.position))
}

@(test)
test_shove_moves_and_damages_ice_without_triggering_trap :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	room := make_ice_block_combat_room(
		t,
		&level_data,
		&player,
		{x = 2, y = 1},
		{x = 3, y = 1},
		true,
	)
	defer destroy_room(&room)
	object := room.objects[0]
	object_ref := object_entity(object.id)
	card := Card_Instance{id = 701, definition_id = .Shove}

	evaluation := evaluate_card_targeting(&room, card, {
		anchor = object.position,
		has_anchor = true,
	})
	testing.expect_value(t, evaluation.error, Card_Compile_Error.None)
	testing.expect(t, evaluation.has_movement)
	testing.expect_value(t, evaluation.movement.destination, grid.Position{x = 3, y = 1})
	action, compile_error := compile_card_action(&room, card, entity_target(object_ref))
	testing.expect_value(t, compile_error, Card_Compile_Error.None)

	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	testing.expect_value(t, report.applied_effects, 2)
	testing.expect_value(t, report.objects_destroyed, 0)
	index, found := object_index_by_id(&room, object.id)
	testing.expect(t, found)
	if found {
		testing.expect_value(t, room.objects[index].health, i32(3))
		testing.expect_value(t, room.objects[index].position, grid.Position{x = 3, y = 1})
	}
	testing.expect(t, room.traps[0].armed)
	for event in report.events.events[:report.events.count] {
		testing.expect(t, event.kind != .Trap_Triggered)
	}
}

@(test)
test_destroyed_ice_block_is_removed_without_ending_combat :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	room := make_ice_block_combat_room(t, &level_data, &player, {x = 2, y = 1})
	defer destroy_room(&room)
	object_ref := object_entity(room.objects[0].id)
	action := make_action(
		.Ability,
		PLAYER_ENTITY,
		entity_target(object_ref),
		.Opponent_Or_Object,
	)
	testing.expect(t, add_effect(&action, damage_effect(object_ref, 4)))

	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	testing.expect_value(t, report.damage_dealt, i32(4))
	testing.expect_value(t, report.objects_destroyed, 1)
	testing.expect(t, !report.combat_ended)
	testing.expect_value(t, room.phase, Room_Phase.Combat)
	testing.expect_value(t, len(room.objects), 0)
	testing.expect(t, !entity_exists(&room, object_ref))
	testing.expect_value(t, report.events.count, 2)
	testing.expect_value(t, report.events.events[0].kind, Game_Event_Kind.Damaged)
	testing.expect_value(t, report.events.events[1].kind, Game_Event_Kind.Entity_Defeated)
}

@(test)
test_ice_block_moved_into_committed_intent_produces_move_blocked :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{
		position = {x = 3, y = 1},
		health = 8,
		attack = 1,
		archetype = .Chaser,
	}}
	objects := [?]Grid_Object_Spawn{{kind = .Ice_Block, position = {x = 4, y = 2}}}
	room, ok := create_room(&level_data, &player, {
		enemies = enemies[:],
		objects = objects[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Move)
	committed_destination := room.enemies[0].intent.destination
	testing.expect_value(t, committed_destination, grid.Position{x = 2, y = 1})

	room.objects[0].position = committed_destination
	pulse := advance_combat_pulse(&room)

	testing.expect(t, pulse.advanced)
	testing.expect_value(t, room.enemies[0].position, grid.Position{x = 3, y = 1})
	blocked_events := 0
	for event in pulse.events.events[:pulse.events.count] {
		if event.kind == .Move_Blocked && event.target == enemy_entity(room.enemies[0].id) {
			blocked_events += 1
			testing.expect_value(t, event.to_position, committed_destination)
		}
	}
	testing.expect_value(t, blocked_events, 1)
}

@(test)
test_ice_block_moved_into_committed_archer_line_causes_miss :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{
		position = {x = 5, y = 1},
		health = 8,
		attack = 3,
		archetype = .Archer,
	}}
	objects := [?]Grid_Object_Spawn{{kind = .Ice_Block, position = {x = 5, y = 2}}}
	room, ok := create_room(&level_data, &player, {
		enemies = enemies[:],
		objects = objects[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Attack)
	advance_combat_pulse(&room)
	testing.expect(t, room.enemies[0].aim_ready)
	health_before := player.health

	room.objects[0].position = {x = 3, y = 1}
	pulse := advance_combat_pulse(&room)

	testing.expect(t, pulse.advanced)
	testing.expect_value(t, player.health, health_before)
	miss_events := 0
	for event in pulse.events.events[:pulse.events.count] {
		if event.kind == .Attack_Missed && event.source == enemy_entity(room.enemies[0].id) {
			miss_events += 1
		}
	}
	testing.expect_value(t, miss_events, 1)
}
