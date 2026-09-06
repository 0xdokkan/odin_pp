package game

import "core:testing"
import grid "../grid"
import level "../level"

@(test)
test_brute_recovers_for_one_pulse_after_hit_miss_or_block :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	for scenario in 0..<3 {
		player := create_test_player(t)
		enemies := [?]Enemy_Spawn{{position = {5, 1}, health = 10, attack = 2, archetype = .Brute}}
		room, ok := create_room(&data, &player, {enemies = enemies[:]})
		testing.expect(t, ok)
		testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Charge)
		if scenario == 0 {
			wait_player_turn(&room)
		} else {
			try_move_player(&room, .South if scenario == 1 else .East)
		}
		testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Recover)
		health := player.health
		position := room.enemies[0].position
		pulse := advance_combat_pulse(&room)
		testing.expect_value(t, pulse.enemy_actions, 0)
		testing.expect_value(t, player.health, health)
		testing.expect_value(t, room.enemies[0].position, position)
		testing.expect_value(t, room.enemies[0].recovery_pulses, i32(0))
		testing.expect(t, room.enemies[0].intent.kind != .Recover)
		testing.expect(t, validate_enemy_intents(&room))
		destroy_room(&room)
	}
}

@(test)
test_bomber_commits_landing_cell_and_gives_two_decisions_to_escape :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {5, 1}, health = 10, attack = 2, archetype = .Bomber}}
	room, ok := create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Bombard)
	anchor := room.enemies[0].intent.destination
	testing.expect_value(t, anchor, player.position)
	testing.expect_value(t, try_move_player(&room, .South), Action_Result.Moved)
	testing.expect_value(t, room.objects[0].position, anchor)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Recover)
	testing.expect_value(t, room.objects[0].detonation_pulse, u64(3))
	id := room.objects[0].id
	testing.expect_value(t, try_move_player(&room, .South), Action_Result.Moved)
	testing.expect_value(t, len(room.objects), 1)
	testing.expect_value(t, wait_player_turn(&room), Action_Result.None)
	_, remains := object_index_by_id(&room, id)
	testing.expect(t, !remains)
	testing.expect_value(t, player.health, i32(10))
	testing.expect_value(t, spatial_card_event_count(&room.recent_events, .Explosion), 1)
}

@(test)
test_displaced_bomber_or_occupied_landing_cell_causes_a_miss :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	for scenario in 0..<2 {
		player := create_test_player(t)
		enemies := [?]Enemy_Spawn{{position = {5, 1}, health = 10, attack = 2, archetype = .Bomber}}
		room, ok := create_room(&data, &player, {enemies = enemies[:]})
		testing.expect(t, ok)
		if scenario == 0 {
			action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(enemy_entity(1)), .Entity)
			testing.expect(t, add_effect(&action, move_effect(enemy_entity(1), {5, 2})))
			report := resolve_action(&room, &action)
			testing.expect(t, report.accepted)
		} else {
			// Another committed throw has occupied the cell since planning.
			testing.expect(t, spawn_bomb(&room, SYSTEM_ENTITY, player.position, &room.recent_events))
		}
		pulse := advance_combat_pulse(&room)
		testing.expect_value(t, spatial_card_event_count(&pulse.events, .Attack_Missed), 1)
		testing.expect_value(t, spatial_card_event_count(&pulse.events, .Object_Spawned), 0)
		testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Recover)
		testing.expect_value(t, player.health, i32(10))
		destroy_room(&room)
	}
}

@(test)
test_bombers_reserve_distinct_cells_and_respect_shared_bomb_limit :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	enemies: [5]Enemy_Spawn
	for &enemy, index in enemies {
		enemy = {position = {2+index, 1}, health = 8, attack = 1, archetype = .Bomber}
	}
	room, ok := create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	player.position = {4, 3}
	plan_enemy_intents(&room)
	anchors: [MAX_ACTIVE_BOMBS]grid.Position
	count := 0
	for enemy in room.enemies {
		if enemy.intent.kind == .Bombard {
			testing.expect(t, !position_in_list(anchors[:count], enemy.intent.destination))
			anchors[count] = enemy.intent.destination
			count += 1
		}
	}
	testing.expect_value(t, count, MAX_ACTIVE_BOMBS)
	pulse := advance_combat_pulse(&room)
	testing.expect_value(t, active_bomb_count(&room), MAX_ACTIVE_BOMBS)
	testing.expect_value(t, spatial_card_event_count(&pulse.events, .Object_Spawned), MAX_ACTIVE_BOMBS)
}

@(test)
test_bomb_survives_its_bomber_while_combat_continues :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{
		{position = {5, 1}, health = 3, attack = 1, archetype = .Bomber},
		{position = {8, 4}, health = 20, attack = 1},
	}
	room, ok := create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	wait_player_turn(&room)
	testing.expect_value(t, active_bomb_count(&room), 1)
	action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(enemy_entity(1)), .Entity)
	testing.expect(t, add_effect(&action, damage_effect(enemy_entity(1), 3)))
	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted)
	testing.expect_value(t, room.phase, Room_Phase.Combat)
	testing.expect_value(t, active_bomb_count(&room), 1)
	advance_combat_pulse(&room)
	pulse := advance_combat_pulse(&room)
	testing.expect_value(t, spatial_card_event_count(&pulse.events, .Explosion), 1)
	testing.expect_value(t, player.health, i32(7))
}

@(test)
test_first_encounter_contains_bomber_and_tactical_objects :: proc(t: ^testing.T) {
	node := test_generation_node(0, .Combat, 0, 0xC0FFEE)
	blueprint, err := generate_room_blueprint(&node)
	testing.expect_value(t, err, Room_Blueprint_Error.None)
	defer destroy_room_blueprint(&blueprint)
	testing.expect_value(t, blueprint.enemies[0].archetype, Enemy_Archetype.Bomber)
	testing.expect_value(t, len(blueprint.objects), 4)
	testing.expect(t, validate_blueprint_objects(&blueprint))
	blueprint.objects[0].position = blueprint.enemies[0].position
	testing.expect(t, !validate_room_blueprint(&blueprint))
}
