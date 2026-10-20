package game

import "core:testing"
import level "../level"

player_command_epilogue_test_event_count :: proc(
	log: ^Event_Log,
	kind: Game_Event_Kind,
) -> int {
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
test_player_command_collects_loot_before_and_after_independent_world_beat :: proc(
	t: ^testing.T,
) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{
		{position = {x = 4, y = 1}, health = 1, attack = 1},
		{position = {x = 5, y = 3}, health = 8, attack = 1},
	}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	for &enemy in room.enemies {
		enemy.intent = make_wait_intent(&room, enemy.position)
	}
	poisoned_enemy := enemy_entity(room.enemies[0].id)
	applied, created := apply_status(&room, poisoned_enemy, .Poison, 1, 1)
	testing.expect(t, applied && created)
	append(&room.loot, Loot{
		position = player.position,
		kind = .Gold,
		amount = 2,
	})

	room.enemies[0].tactical_cooldown = 1
	outcome := finish_player_combat_command(&room)

	testing.expect_value(t, outcome, Player_Command_Outcome.Combat_Continues)
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect_value(t, player.gold, i32(2))
	testing.expect_value(t, len(room.enemies), 2)
	testing.expect_value(t, player_command_epilogue_test_event_count(room.recent_events, .Loot_Collected), 1)
	testing.expect_value(t, room.recent_events.events[0].kind, Game_Event_Kind.Loot_Collected)

	// The command pays time; the scheduler later settles poison and its drop.
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, room.phase, Room_Phase.Combat)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect_value(t, len(room.enemies), 1)
	testing.expect_value(t, len(room.loot), 0)
	testing.expect_value(t, player.gold, i32(3))
	testing.expect(t, player.deck.combat_active)
	testing.expect_value(t, player_command_epilogue_test_event_count(room.recent_events, .Pulse_Advanced), 1)
	testing.expect_value(t, player_command_epilogue_test_event_count(room.recent_events, .Loot_Collected), 1)
}

@(test)
test_player_command_epilogue_skips_pulse_when_command_already_ended_combat :: proc(
	t: ^testing.T,
) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 1, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	enemy := enemy_entity(room.enemies[0].id)
	action := make_action(.Attack, PLAYER_ENTITY, entity_target(enemy), .Opponent)
	testing.expect(t, add_effect(&action, damage_effect(enemy, 1)))
	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted)
	testing.expect(t, report.combat_ended)
	testing.expect_value(t, room.phase, Room_Phase.Loot)
	testing.expect(t, player.deck.combat_active)

	outcome := finish_player_combat_command(&room)

	testing.expect_value(t, outcome, Player_Command_Outcome.Combat_Ended)
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect_value(
		t,
		player_command_epilogue_test_event_count(room.recent_events, .Pulse_Advanced),
		0,
	)
	testing.expect_value(t, len(room.loot), 0)
	testing.expect_value(t, player.gold, i32(1))
	testing.expect(t, !player.deck.combat_active)
	testing.expect_value(t, player.deck.hand_count, 0)
	testing.expect_value(t, player.deck.energy, i32(0))
}

@(test)
test_world_beat_syncs_deck_when_queued_command_cost_defeats_player :: proc(
	t: ^testing.T,
) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	player.health = 1
	enemies := [?]Enemy_Spawn{{position = {x = 2, y = 1}, health = 8, attack = 2}}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)

	room.enemies[0].tactical_cooldown = 1
	outcome := finish_player_combat_command(&room)
	testing.expect_value(t, outcome, Player_Command_Outcome.Combat_Continues)
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, room.phase, Room_Phase.Defeat)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect_value(t, player.health, i32(0))
	testing.expect(t, !player.deck.combat_active)
	testing.expect_value(t, player.deck.hand_count, 0)
	testing.expect_value(t, player.deck.energy, i32(0))
	testing.expect_value(
		t,
		player_command_epilogue_test_event_count(room.recent_events, .Pulse_Advanced),
		1,
	)
}

@(test)
test_enemy_healing_drop_uses_explicit_spawn_policy_not_enemy_id :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{
		{position = {x = 2, y = 1}, health = 1, attack = 1, drops_healing = true},
		{position = {x = 4, y = 1}, health = 1, attack = 1},
		{position = {x = 5, y = 3}, health = 1, attack = 1},
	}
	room, ok := create_room(&level_data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	testing.expect_value(t, room.enemies[0].id, u32(1))
	testing.expect_value(t, room.enemies[2].id, u32(3))

	first_drops, first_drop_count := kill_enemy(&room, 0)
	third_index, found := enemy_index_by_id(&room, 3)
	testing.expect(t, found)
	third_drops, third_drop_count := kill_enemy(&room, third_index)

	testing.expect_value(t, first_drop_count, 2)
	testing.expect_value(t, first_drops[0].kind, Loot_Kind.Gold)
	testing.expect_value(t, first_drops[1].kind, Loot_Kind.Healing)
	testing.expect_value(t, first_drops[1].amount, i32(2))
	testing.expect_value(t, third_drop_count, 1)
	testing.expect_value(t, third_drops[0].kind, Loot_Kind.Gold)
}
