package game

import "core:testing"
import level "../level"

@(test)
test_prepared_bomber_does_not_retarget_an_occupied_landing_cell :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 5, y = 1}, health = 10, attack = 2, archetype = .Bomber}}
	room, ok := create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	advance_combat_pulse(&room)
	testing.expect(t, room.enemies[0].bomb_ready)
	// Another throw occupies the committed cell during the preparation.
	testing.expect(t, spawn_bomb(&room, SYSTEM_ENTITY, player.position, room.recent_events))
	pulse := advance_combat_pulse(&room)
	testing.expect_value(t, spatial_card_event_count(&pulse.events, .Attack_Missed), 1)
	testing.expect_value(t, spatial_card_event_count(&pulse.events, .Object_Spawned), 0)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Recover)
	testing.expect_value(t, player.health, i32(10))
}

@(test)
test_bomb_survives_its_bomber_while_combat_continues :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{
		{position = {x = 5, y = 1}, health = 3, attack = 1, archetype = .Bomber},
		{position = {x = 8, y = 4}, health = 20, attack = 1},
	}
	room, ok := create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	advance_combat_pulse(&room)
	advance_combat_pulse(&room)
	testing.expect_value(t, active_bomb_count(&room), 1)
	action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(enemy_entity(1)), .Entity)
	testing.expect(t, add_effect(&action, damage_effect(enemy_entity(1), 3)))
	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted)
	testing.expect_value(t, room.phase, Room_Phase.Combat)
	testing.expect_value(t, active_bomb_count(&room), 1)
	advance_combat_pulse(&room)
	advance_combat_pulse(&room)
	pulse := advance_combat_pulse(&room)
	testing.expect_value(t, spatial_card_event_count(&pulse.events, .Explosion), 1)
	testing.expect_value(t, player.health, i32(8))
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
