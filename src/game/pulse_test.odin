package game

import "core:testing"
import level "../level"

// Low-level resolver fixture: scheduler integration is covered by tactical tests.
advance_combat_pulse :: proc(room: ^Room) -> (pulse: Pulse_Report) {
	if room == nil || room.phase != .Combat {
		return
	}
	pulse.advanced = true
	resolve_due_explosives(room, &pulse)
	resolve_due_room_modifier(room, &pulse)
	resolve_enemy_intents(room, &pulse)
	finish_combat_pulse(room, &pulse)
	return
}

@(test)
test_continuing_combat_emits_terminal_pulse_snapshot_after_ticks_and_energy_restore :: proc(
	t: ^testing.T,
) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 6, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	room.enemies[0].intent = make_wait_intent(&room, room.enemies[0].position)
	player.deck.energy = 0
	applied, created := apply_status(&room, PLAYER_ENTITY, .Shield, 2, 1)
	testing.expect(t, applied && created)

	room.pulse_count = 2
	pulse := advance_combat_pulse(&room)

	testing.expect(t, pulse.advanced)
	testing.expect_value(t, room.phase, Room_Phase.Combat)
	testing.expect_value(t, room.pulse_count, u64(3))
	testing.expect_value(t, pulse.events.dropped_count, 0)
	testing.expect_value(t, pulse.events.count, 2)
	testing.expect_value(t, pulse.events.events[0].kind, Game_Event_Kind.Status_Expired)
	pulse_event := pulse.events.events[1]
	testing.expect_value(t, pulse_event.kind, Game_Event_Kind.Pulse_Advanced)
	testing.expect_value(t, pulse_event.source, SYSTEM_ENTITY)
	testing.expect_value(t, pulse_event.target, PLAYER_ENTITY)
	testing.expect_value(t, pulse_event.pulse_count, room.pulse_count)
	testing.expect_value(t, pulse_event.energy, player.deck.energy)
	testing.expect_value(t, pulse.energy_restored, i32(1))
	testing.expect_value(t, pulse.energy_wasted, i32(0))
	testing.expect_value(t, pulse_event.energy_restored, pulse.energy_restored)
	testing.expect_value(t, pulse_event.energy_wasted, pulse.energy_wasted)
	testing.expect(t, pulse_event.statuses_advanced)
	testing.expect(t, player.deck.energy > 0)
	_, status_found := status_for_entity(&room, PLAYER_ENTITY, .Shield)
	testing.expect(t, !status_found)
}

@(test)
test_combat_ending_during_intents_emits_pulse_without_advancing_statuses_or_energy :: proc(
	t: ^testing.T,
) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	player.health = 1
	enemies := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 6, attack = 2}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	enemy_ref := enemy_entity(room.enemies[0].id)
	player.deck.energy = 0
	applied, created := apply_status(&room, enemy_ref, .Shield, 2, 1)
	testing.expect(t, applied && created)

	pulse := advance_combat_pulse(&room)

	testing.expect(t, pulse.advanced)
	testing.expect(t, pulse.player_defeated)
	testing.expect_value(t, room.phase, Room_Phase.Defeat)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect_value(t, pulse.events.dropped_count, 0)
	testing.expect(t, pulse.events.count >= 2)
	pulse_event := pulse.events.events[pulse.events.count-1]
	testing.expect_value(t, pulse_event.kind, Game_Event_Kind.Pulse_Advanced)
	testing.expect_value(t, pulse_event.source, SYSTEM_ENTITY)
	testing.expect_value(t, pulse_event.target, PLAYER_ENTITY)
	testing.expect_value(t, pulse_event.pulse_count, room.pulse_count)
	testing.expect_value(t, pulse_event.energy, i32(0))
	testing.expect_value(t, pulse.energy_restored, i32(0))
	testing.expect_value(t, pulse.energy_wasted, i32(0))
	testing.expect_value(t, pulse_event.energy_restored, pulse.energy_restored)
	testing.expect_value(t, pulse_event.energy_wasted, pulse.energy_wasted)
	testing.expect(t, !pulse_event.statuses_advanced)
	status, status_found := status_for_entity(&room, enemy_ref, .Shield)
	testing.expect(t, status_found)
	testing.expect_value(t, status.remaining_pulses, i32(1))

	pulse_event_count := 0
	for index in 0..<pulse.events.count {
		if pulse.events.events[index].kind == .Pulse_Advanced {
			pulse_event_count += 1
		}
	}
	testing.expect_value(t, pulse_event_count, 1)
}

@(test)
test_full_energy_records_regen_wasted_at_cap :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 6, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	room.enemies[0].intent = make_wait_intent(&room, room.enemies[0].position)
	testing.expect_value(t, player.deck.energy, player.deck.rules.max_energy)
	room.pulse_count = 2
	pulse := advance_combat_pulse(&room)

	testing.expect(t, pulse.advanced)
	testing.expect_value(t, pulse.energy_restored, i32(0))
	testing.expect_value(
		t,
		pulse.energy_wasted,
		player.deck.rules.energy_regen_per_pulse,
	)
	pulse_event := pulse.events.events[pulse.events.count-1]
	testing.expect_value(t, pulse_event.kind, Game_Event_Kind.Pulse_Advanced)
	testing.expect_value(t, pulse_event.energy_restored, pulse.energy_restored)
	testing.expect_value(t, pulse_event.energy_wasted, pulse.energy_wasted)
}
