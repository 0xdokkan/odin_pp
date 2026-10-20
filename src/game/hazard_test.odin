package game

import "core:testing"
import level "../level"

hazard_test_event_count :: proc(log: ^Event_Log, kind: Game_Event_Kind) -> int {
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
test_player_trap_adapter_disarms_and_appends_damage_once :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 8, attack = 1}}
	traps := [?]Trap_Spawn{{position = {x = 1, y = 2}, damage = 4}}
	room, ok := create_room(&level_data, &player, {
		enemies = enemies[:],
		traps = traps[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)

	player.position = room.traps[0].position
	testing.expect_value(t, room.recent_events.count, 0)

	trigger_trap(&room)

	testing.expect(t, !room.traps[0].armed)
	testing.expect_value(t, player.health, i32(7))
	testing.expect_value(t, room.recent_events.count, 2)
	testing.expect_value(t, room.recent_events.events[0].kind, Game_Event_Kind.Trap_Triggered)
	testing.expect_value(t, room.recent_events.events[1].kind, Game_Event_Kind.Damaged)
	testing.expect_value(t, room.recent_events.events[1].source, trap_entity(room.traps[0].id))
	testing.expect_value(t, room.recent_events.events[1].target, PLAYER_ENTITY)

	trigger_trap(&room)

	testing.expect_value(t, player.health, i32(7))
	testing.expect_value(t, room.recent_events.count, 2)
}

@(test)
test_enemy_trap_resolution_honors_shield_death_and_explicit_drops :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{
		{
			position = {x = 2, y = 1},
			health = 2,
			attack = 1,
			drops_healing = true,
		},
	}
	traps := [?]Trap_Spawn{{position = {x = 3, y = 1}, damage = 3}}
	room, ok := create_room(&level_data, &player, {
		enemies = enemies[:],
		traps = traps[:],
	})
	testing.expect(t, ok)
	defer destroy_room(&room)

	enemy := enemy_entity(room.enemies[0].id)
	applied, created := apply_status(&room, enemy, .Shield, 1, 2)
	testing.expect(t, applied && created)
	room.enemies[0].position = room.traps[0].position

	resolution := resolve_trap_for_entity(&room, enemy)

	testing.expect(t, resolution.triggered)
	testing.expect_value(t, resolution.trap_id, room.traps[0].id)
	testing.expect(t, resolution.report.accepted)
	testing.expect_value(t, resolution.report.damage_absorbed, i32(1))
	testing.expect_value(t, resolution.report.damage_dealt, i32(2))
	testing.expect_value(t, resolution.report.enemies_defeated, 1)
	testing.expect(t, resolution.report.combat_ended)
	testing.expect_value(t, room.phase, Room_Phase.Loot)
	testing.expect_value(t, len(room.enemies), 0)
	testing.expect_value(t, len(room.loot), 2)
	testing.expect(t, !room.traps[0].armed)
	testing.expect_value(
		t,
		hazard_test_event_count(&resolution.report.events, .Trap_Triggered),
		1,
	)
	testing.expect_value(
		t,
		hazard_test_event_count(&resolution.report.events, .Damage_Absorbed),
		1,
	)
	testing.expect_value(
		t,
		hazard_test_event_count(&resolution.report.events, .Entity_Defeated),
		1,
	)
	testing.expect_value(
		t,
		hazard_test_event_count(&resolution.report.events, .Loot_Dropped),
		2,
	)
	testing.expect_value(t, room.recent_events.count, 0)
	append_event_log(room.recent_events, &resolution.report.events)
	testing.expect_value(t, room.recent_events.count, resolution.report.events.count)
}

@(test)
test_trap_resolution_on_cell_without_trap_is_a_noop :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 8, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	player_before := player
	phase_before := room.phase

	resolution := resolve_trap_for_entity(&room, PLAYER_ENTITY)

	testing.expect(t, !resolution.triggered)
	testing.expect_value(t, resolution.trap_id, u32(0))
	testing.expect(t, !resolution.report.accepted)
	testing.expect_value(t, resolution.report.events.count, 0)
	testing.expect_value(t, player, player_before)
	testing.expect_value(t, room.phase, phase_before)
	testing.expect_value(t, room.recent_events.count, 0)
}
