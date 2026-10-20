package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

test_furnace_modifier :: proc() -> Room_Modifier {
	result := Room_Modifier{kind = .Furnace, cell_count = 4,
		activation_pulse = 2, damage = ROOM_HAZARD_DAMAGE}
	cells := [?]grid.Position{{2, 1}, {3, 1}, {4, 1}, {5, 1}}
	copy(result.cells[:], cells[:])
	return result
}

make_furnace_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player) -> Room {
	enemies := [?]Enemy_Spawn{{position = {3, 1}, health = 20, attack = 1}}
	objects := [?]Grid_Object_Spawn{
		{kind = .Barrel, position = {4, 1}}, {kind = .Ice_Block, position = {5, 1}},
	}
	room, ok := create_room(data, player, {enemies = enemies[:], objects = objects[:],
		modifier = test_furnace_modifier()})
	testing.expect(t, ok)
	room.enemies[0].recovery_pulses = 100
	plan_enemy_intents(&room)
	return room
}

@(test)
test_furnace_warns_two_beats_and_hits_actors_and_objects :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	room := make_furnace_test_room(t, &data, &player)
	defer destroy_room(&room)
	player.position = {2, 1}
	testing.expect(t, room_modifier_warning_active(&room.modifier, room.pulse_count))
	room.recent_events^ = advance_combat_pulse(&room).events
	testing.expect_value(t, player.health, i32(10))
	testing.expect_value(t, room_modifier_pulses_remaining(&room.modifier, room.pulse_count), 1)
	room.recent_events^ = advance_combat_pulse(&room).events
	testing.expect_value(t, player.health, i32(8))
	testing.expect_value(t, room.enemies[0].health, i32(17))
	testing.expect_value(t, room.objects[1].health, i32(1))
	testing.expect_value(t, explosive_pulses_remaining(room.objects[0].detonation_pulse, room.pulse_count), 2)
	testing.expect_value(t, spatial_card_event_count(room.recent_events, .Room_Hazard_Triggered), 1)
	testing.expect_value(t, room.recent_events.events[0].kind, Game_Event_Kind.Room_Hazard_Triggered)
}

@(test)
test_furnace_has_two_cooldown_pulses_before_next_warning :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {8, 4}, health = 20, attack = 1}}
	room, ok := create_room(&data, &player, {enemies = enemies[:], modifier = test_furnace_modifier()})
	testing.expect(t, ok)
	defer destroy_room(&room)
	room.enemies[0].recovery_pulses = 100
	plan_enemy_intents(&room)
	testing.expect_value(t, try_move_player(&room, .North), Action_Result.Blocked)
	testing.expect_value(t, room.pulse_count, u64(0))
	room.recent_events^ = advance_combat_pulse(&room).events
	room.recent_events^ = advance_combat_pulse(&room).events
	testing.expect_value(t, room_modifier_pulses_remaining(&room.modifier, room.pulse_count), 4)
	testing.expect(t, !room_modifier_warning_active(&room.modifier, room.pulse_count))
	room.recent_events^ = advance_combat_pulse(&room).events
	testing.expect(t, !room_modifier_warning_active(&room.modifier, room.pulse_count))
	room.recent_events^ = advance_combat_pulse(&room).events
	testing.expect(t, room_modifier_warning_active(&room.modifier, room.pulse_count))
	room.recent_events^ = advance_combat_pulse(&room).events
	testing.expect_value(t, spatial_card_event_count(room.recent_events, .Room_Hazard_Triggered), 0)
	room.recent_events^ = advance_combat_pulse(&room).events
	testing.expect_value(t, spatial_card_event_count(room.recent_events, .Room_Hazard_Triggered), 1)
	testing.expect_value(t, player.health, i32(10))
}

@(test)
test_furnace_simultaneous_final_kill_preserves_player_defeat :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	room := make_furnace_test_room(t, &data, &player)
	defer destroy_room(&room)
	player.position = {2, 1}
	player.health = 1
	room.enemies[0].health = 1
	room.modifier.activation_pulse = 1
	pulse := advance_combat_pulse(&room)
	testing.expect(t, pulse.player_defeated)
	testing.expect_value(t, len(room.enemies), 0)
	testing.expect_value(t, room.phase, Room_Phase.Defeat)
	testing.expect_value(t, room.modifier.activation_pulse, u64(0))
	testing.expect_value(t, room.objects[0].detonation_pulse, u64(0))
}

@(test)
test_furnace_disarms_when_player_finishes_combat :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	room := make_furnace_test_room(t, &data, &player)
	defer destroy_room(&room)
	action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(enemy_entity(1)), .Entity)
	testing.expect(t, add_effect(&action, damage_effect(enemy_entity(1), 20)))
	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted && report.combat_ended)
	testing.expect_value(t, room.phase, Room_Phase.Loot)
	testing.expect_value(t, room.modifier.activation_pulse, u64(0))
	pulse := advance_combat_pulse(&room)
	testing.expect(t, !pulse.advanced)
	testing.expect_value(t, player.health, i32(10))
}

@(test)
test_room_rejects_invalid_furnace_lanes_without_consuming_player_state :: proc(t: ^testing.T) {
	data := create_enemy_archetype_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	valid := test_furnace_modifier()
	variants := [5]Room_Modifier{valid, valid, valid, valid, valid}
	variants[0].cell_count = MAX_ROOM_HAZARD_CELLS+1
	variants[1].cells[1] = variants[1].cells[0]
	variants[2].cells[1] = {3, 2}
	variants[3].cells[1] = data.player_spawn
	variants[4].damage = 0
	before := player
	for modifier in variants {
		room, ok := create_room(&data, &player, {modifier = modifier})
		testing.expect(t, !ok)
		destroy_room(&room)
		testing.expect_value(t, player, before)
	}
}

@(test)
test_encounter_recipes_are_seeded_grouped_and_keep_boss_unique :: proc(t: ^testing.T) {
	seen: [5]bool
	modifiers: [2]bool
	for seed in 1..=96 {
		node := test_generation_node(3, .Combat, 4, u64(seed))
		blueprint, err := generate_room_blueprint(&node)
		testing.expect_value(t, err, Room_Blueprint_Error.None)
		if err != .None { continue }
		seen[int(blueprint.encounter_kind)] = true
		modifiers[int(blueprint.modifier.kind)] = true
		testing.expect(t, validate_blueprint_encounter(&blueprint))
		content := room_blueprint_content(&blueprint)
		testing.expect_value(t, content.encounter_kind, blueprint.encounter_kind)
		testing.expect_value(t, content.modifier, blueprint.modifier)
		for enemy in blueprint.enemies {
			testing.expect(t, enemy.archetype != .Demolitionist)
		}
		if blueprint.encounter_kind == .Powder_Keg {
			testing.expect_value(t, blueprint.objects[0].kind, Grid_Object_Kind.Barrel)
			testing.expect_value(t, blueprint.objects[1].kind, Grid_Object_Kind.Barrel)
		}
		if blueprint.modifier.kind != .None {
			testing.expect(t, !room_modifier_contains_cell(&blueprint.modifier, blueprint.level_data.player_spawn))
			testing.expect(t, !room_modifier_contains_cell(&blueprint.modifier, blueprint.exit_position))
			rows := blueprint.modifier.cells[0].y == blueprint.modifier.cells[1].y
			for cell in blueprint.modifier.cells[:blueprint.modifier.cell_count] {
				testing.expect(t, blueprint_hazard_cell_has_escape(&blueprint, cell, rows))
			}
			blueprint.modifier.damage += 1
			testing.expect(t, !validate_room_blueprint(&blueprint))
		}
		destroy_room_blueprint(&blueprint)
	}
	testing.expect(t, seen[int(Encounter_Kind.Powder_Keg)] && seen[int(Encounter_Kind.Escort)] &&
		seen[int(Encounter_Kind.Assault)])
	testing.expect(t, modifiers[0] && modifiers[1])
}
