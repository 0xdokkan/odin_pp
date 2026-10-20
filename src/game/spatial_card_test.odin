package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

create_spatial_card_test_level :: proc(t: ^testing.T) -> level.Level {
	rows := [?]string{
		"########",
		"#@.....#",
		"#......#",
		"#.....>#",
		"########",
	}
	result, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	return result
}

spatial_card_event_count :: proc(log: ^Event_Log, kind: Game_Event_Kind) -> int {
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
test_shove_preview_compile_and_hazard_resolution_share_destination :: proc(t: ^testing.T) {
	level_data := create_spatial_card_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{
		{position = {x = 2, y = 1}, health = 8, attack = 1},
		{position = {x = 6, y = 2}, health = 8, attack = 1},
	}
	traps := [?]Trap_Spawn{{position = {x = 3, y = 1}, damage = 3}}
	room, ok := create_room(&level_data, &player, {
		enemies = enemies[:],
		traps = traps[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)
	target_enemy := enemy_entity(room.enemies[0].id)
	card := Card_Instance{id = 91, definition_id = .Shove}
	request := Target_Request{anchor = room.enemies[0].position, has_anchor = true}

	evaluation := evaluate_card_targeting(&room, card, request)
	testing.expect_value(t, evaluation.error, Card_Compile_Error.None)
	testing.expect(t, evaluation.has_movement)
	testing.expect(t, movement_query_is_clear(&evaluation.movement))
	testing.expect_value(t, evaluation.movement.destination, grid.Position{x = 3, y = 1})
	action, compile_error := compile_card_action(&room, card, entity_target(target_enemy))
	testing.expect_value(t, compile_error, Card_Compile_Error.None)
	testing.expect_value(t, action.effect_count, 2)
	testing.expect_value(t, action.effects[0].kind, Effect_Kind.Move)
	testing.expect_value(t, action.effects[0].destination, evaluation.movement.destination)

	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	index, found := enemy_index_by_id(&room, target_enemy.id)
	testing.expect(t, found)
	if found {
		testing.expect_value(t, room.enemies[index].position, grid.Position{x = 3, y = 1})
		testing.expect_value(t, room.enemies[index].health, i32(4))
	}
	testing.expect(t, !room.traps[0].armed)
	testing.expect_value(t, spatial_card_event_count(&report.events, .Moved), 1)
	testing.expect_value(t, spatial_card_event_count(&report.events, .Trap_Triggered), 1)
	testing.expect_value(t, spatial_card_event_count(&report.events, .Damaged), 2)
}

@(test)
test_blocked_shove_keeps_damage_and_skips_only_movement :: proc(t: ^testing.T) {
	level_data := create_spatial_card_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{
		{position = {x = 2, y = 1}, health = 8, attack = 1},
		{position = {x = 6, y = 2}, health = 8, attack = 1},
	}
	obstacles := [?]grid.Position{{x = 3, y = 1}}
	room, ok := create_room(&level_data, &player, {
		enemies = enemies[:],
		obstacles = obstacles[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)
	target_enemy := enemy_entity(room.enemies[0].id)
	card := Card_Instance{id = 92, definition_id = .Shove}
	evaluation := evaluate_card_targeting(&room, card, {
		anchor = room.enemies[0].position,
		has_anchor = true,
	})
	testing.expect_value(t, evaluation.error, Card_Compile_Error.None)
	testing.expect_value(t, evaluation.movement.error, Movement_Error.Static_Blocker)
	action, compile_error := compile_card_action(&room, card, entity_target(target_enemy))
	testing.expect_value(t, compile_error, Card_Compile_Error.None)

	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	testing.expect_value(t, report.applied_effects, 1)
	testing.expect_value(t, report.skipped_effects, 1)
	testing.expect_value(t, room.enemies[0].health, i32(7))
	testing.expect_value(t, room.enemies[0].position, grid.Position{x = 2, y = 1})
}

@(test)
test_dash_traverses_two_traps_and_triggers_afterimage_once :: proc(t: ^testing.T) {
	level_data := create_spatial_card_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 6, y = 2}, health = 8, attack = 1}}
	traps := [?]Trap_Spawn{
		{position = {x = 2, y = 1}, damage = 2},
		{position = {x = 3, y = 1}, damage = 2},
	}
	room, ok := create_room(&level_data, &player, {
		enemies = enemies[:],
		traps = traps[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)
	applied, created := apply_status(&room, PLAYER_ENTITY, .Afterimage, 1, 4)
	testing.expect(t, applied && created)
	card := Card_Instance{id = 93, definition_id = .Dash}
	target := cell_target({x = 4, y = 1})
	action, compile_error := compile_card_action(&room, card, target)
	testing.expect_value(t, compile_error, Card_Compile_Error.None)

	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	testing.expect_value(t, player.position, grid.Position{x = 4, y = 1})
	testing.expect_value(t, player.health, i32(10))
	testing.expect_value(t, spatial_card_event_count(&report.events, .Movement_Step), 2)
	testing.expect_value(t, spatial_card_event_count(&report.events, .Moved), 1)
	testing.expect_value(t, spatial_card_event_count(&report.events, .Trap_Triggered), 2)
	testing.expect_value(t, report.reactions_triggered, 1)
	shield, shield_found := status_for_entity(&room, PLAYER_ENTITY, .Shield)
	testing.expect(t, shield_found)
	if shield_found {
		testing.expect_value(t, shield.potency, i32(1))
	}
}

@(test)
test_lethal_dash_promotes_reached_step_and_stops_the_path :: proc(t: ^testing.T) {
	level_data := create_spatial_card_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	player.health = 1
	enemies := [?]Enemy_Spawn{{position = {x = 6, y = 2}, health = 8, attack = 1}}
	traps := [?]Trap_Spawn{{position = {x = 2, y = 1}, damage = 4}}
	room, ok := create_room(&level_data, &player, {
		enemies = enemies[:],
		traps = traps[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)
	action, compile_error := compile_card_action(
		&room,
		{id = 94, definition_id = .Dash},
		cell_target({x = 4, y = 1}),
	)
	testing.expect_value(t, compile_error, Card_Compile_Error.None)

	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	testing.expect(t, report.player_defeated)
	testing.expect_value(t, room.phase, Room_Phase.Defeat)
	testing.expect_value(t, player.position, grid.Position{x = 2, y = 1})
	testing.expect_value(t, spatial_card_event_count(&report.events, .Movement_Step), 0)
	testing.expect_value(t, spatial_card_event_count(&report.events, .Moved), 1)
	testing.expect_value(t, report.events.events[0].kind, Game_Event_Kind.Status_Applied)
}

@(test)
test_dash_blocker_is_shared_by_preview_drop_and_compile_without_cost :: proc(t: ^testing.T) {
	level_data := create_spatial_card_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	testing.expect(t, initialize_empty_deck(&player.deck, {
		hand_size = 1,
		max_energy = 3,
		energy_regen_per_pulse = 1,
	}, 111))
	_, added := add_owned_card(&player.deck, .Dash)
	testing.expect(t, added)
	enemies := [?]Enemy_Spawn{{position = {x = 3, y = 1}, health = 8, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	card := player.deck.hand[0]
	request := Target_Request{anchor = {x = 4, y = 1}, has_anchor = true}
	evaluation := evaluate_card_targeting(&room, card, request)

	testing.expect_value(t, evaluation.error, Card_Compile_Error.Target_Blocked)
	testing.expect_value(t, evaluation.movement.error, Movement_Error.Actor_Blocker)
	testing.expect_value(t, evaluation.movement.blocker, grid.Position{x = 3, y = 1})
	_, has_drop_target := card_drop_target(&room, card, request.anchor)
	testing.expect(t, !has_drop_target)
	_, compile_error := compile_card_action(&room, card, cell_target(request.anchor))
	testing.expect_value(t, compile_error, Card_Compile_Error.Target_Blocked)
	energy_before := player.deck.energy
	play := play_card(&room, card.id, cell_target(request.anchor))
	testing.expect_value(t, play.result, Card_Play_Result.Compile_Failed)
	testing.expect_value(t, player.deck.energy, energy_before)
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect_value(t, player.deck.hand[0], card)
}

@(test)
test_grappling_hook_pulls_to_adjacent_and_preserves_committed_intent_until_resolution :: proc(
	t: ^testing.T,
) {
	level_data := create_spatial_card_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{
		{position = {x = 4, y = 1}, health = 8, attack = 1},
		{position = {x = 6, y = 2}, health = 8, attack = 1},
	}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	target_enemy := enemy_entity(room.enemies[0].id)
	intent_before := room.enemies[0].intent
	card := Card_Instance{id = 95, definition_id = .Grappling_Hook}
	evaluation := evaluate_card_targeting(&room, card, {
		anchor = room.enemies[0].position,
		has_anchor = true,
	})
	testing.expect_value(t, evaluation.error, Card_Compile_Error.None)
	testing.expect_value(t, evaluation.movement.destination, grid.Position{x = 2, y = 1})
	action, compile_error := compile_card_action(&room, card, entity_target(target_enemy))
	testing.expect_value(t, compile_error, Card_Compile_Error.None)

	report := resolve_action(&room, &action)

	testing.expect(t, report.accepted)
	index, found := enemy_index_by_id(&room, target_enemy.id)
	testing.expect(t, found)
	if found {
		testing.expect_value(t, room.enemies[index].position, grid.Position{x = 2, y = 1})
		testing.expect_value(t, room.enemies[index].intent, intent_before)
		testing.expect(t, validate_enemy_intent(&room, &room.enemies[index]))
		testing.expect(t, validate_enemy_intent_structure(&room, &room.enemies[index].intent))
	}
}

@(test)
test_grappling_hook_cannot_target_through_an_intervening_actor :: proc(t: ^testing.T) {
	level_data := create_spatial_card_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{
		{position = {x = 4, y = 1}, health = 8, attack = 1},
		{position = {x = 2, y = 1}, health = 8, attack = 1},
	}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	target := entity_target(enemy_entity(room.enemies[0].id))
	card := Card_Instance{id = 96, definition_id = .Grappling_Hook}
	evaluation := evaluate_card_targeting(&room, card, {
		anchor = room.enemies[0].position,
		has_anchor = true,
	})

	testing.expect_value(t, evaluation.error, Card_Compile_Error.Target_Blocked)
	_, compile_error := compile_card_action(&room, card, target)
	testing.expect_value(t, compile_error, Card_Compile_Error.Target_Blocked)
}
