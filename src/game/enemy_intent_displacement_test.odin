package game

import "core:testing"
import grid "../grid"
import level "../level"

@(test)
test_stale_attack_intent_misses_after_enemy_displacement :: proc(t: ^testing.T) {
	level_data := create_enemy_archetype_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{
		position = {x = 2, y = 1},
		health = 6,
		attack = 3,
		archetype = .Chaser,
	}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Attack)

	enemy_id := room.enemies[0].id
	planned_origin := room.enemies[0].intent.origin
	planned_target := room.enemies[0].intent.threatened_cells[0]
	displaced_position := grid.Position{x = 2, y = 2}
	health_before := player.health
	room.enemies[0].position = displaced_position
	testing.expect(t, !validate_enemy_intent(&room, &room.enemies[0]))
	testing.expect(t, validate_enemy_intent_structure(&room, &room.enemies[0].intent))

	pulse: Pulse_Report
	resolve_enemy_intents(&room, &pulse)

	testing.expect_value(t, pulse.enemy_actions, 1)
	testing.expect_value(t, pulse.events.count, 1)
	testing.expect_value(t, pulse.events.dropped_count, 0)
	testing.expect_value(t, pulse.events.events[0].kind, Game_Event_Kind.Attack_Missed)
	testing.expect_value(t, pulse.events.events[0].source, enemy_entity(enemy_id))
	testing.expect_value(t, pulse.events.events[0].target, PLAYER_ENTITY)
	testing.expect_value(t, pulse.events.events[0].from_position, displaced_position)
	testing.expect_value(t, pulse.events.events[0].to_position, planned_target)
	testing.expect_value(t, player.health, health_before)
	testing.expect_value(t, room.enemies[0].position, displaced_position)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.None)
	testing.expect(t, displaced_position != planned_origin)
}

@(test)
test_stale_move_intent_reports_block_after_enemy_displacement :: proc(t: ^testing.T) {
	level_data := create_enemy_archetype_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{
		position = {x = 7, y = 3},
		health = 6,
		attack = 2,
		archetype = .Chaser,
	}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Move)

	enemy_id := room.enemies[0].id
	planned_destination := room.enemies[0].intent.destination
	displaced_position := grid.Position{x = 7, y = 2}
	room.enemies[0].position = displaced_position
	testing.expect(t, !validate_enemy_intents(&room))
	testing.expect(t, validate_enemy_intent_structure(&room, &room.enemies[0].intent))

	pulse: Pulse_Report
	resolve_enemy_intents(&room, &pulse)

	testing.expect_value(t, pulse.enemy_actions, 1)
	testing.expect_value(t, pulse.events.count, 1)
	testing.expect_value(t, pulse.events.dropped_count, 0)
	testing.expect_value(t, pulse.events.events[0].kind, Game_Event_Kind.Move_Blocked)
	testing.expect_value(t, pulse.events.events[0].source, enemy_entity(enemy_id))
	testing.expect_value(t, pulse.events.events[0].target, enemy_entity(enemy_id))
	testing.expect_value(t, pulse.events.events[0].from_position, displaced_position)
	testing.expect_value(t, pulse.events.events[0].to_position, planned_destination)
	testing.expect_value(t, room.enemies[0].position, displaced_position)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.None)
}

@(test)
test_stale_charge_intent_reports_block_without_moving_or_attacking :: proc(t: ^testing.T) {
	level_data := create_enemy_archetype_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{
		position = {x = 5, y = 1},
		health = 10,
		attack = 2,
		archetype = .Brute,
	}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Charge)

	enemy_id := room.enemies[0].id
	planned_destination := room.enemies[0].intent.destination
	displaced_position := grid.Position{x = 5, y = 2}
	health_before := player.health
	room.enemies[0].position = displaced_position
	testing.expect(t, !validate_enemy_intent(&room, &room.enemies[0]))
	testing.expect(t, validate_enemy_intent_structure(&room, &room.enemies[0].intent))

	pulse: Pulse_Report
	resolve_enemy_intents(&room, &pulse)

	testing.expect_value(t, pulse.enemy_actions, 1)
	testing.expect_value(t, pulse.events.count, 1)
	testing.expect_value(t, pulse.events.dropped_count, 0)
	testing.expect_value(t, pulse.events.events[0].kind, Game_Event_Kind.Move_Blocked)
	testing.expect_value(t, pulse.events.events[0].source, enemy_entity(enemy_id))
	testing.expect_value(t, pulse.events.events[0].target, enemy_entity(enemy_id))
	testing.expect_value(t, pulse.events.events[0].from_position, displaced_position)
	testing.expect_value(t, pulse.events.events[0].to_position, planned_destination)
	testing.expect_value(t, player.health, health_before)
	testing.expect_value(t, room.enemies[0].position, displaced_position)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.None)
}
