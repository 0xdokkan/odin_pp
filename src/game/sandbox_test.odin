package game

import "core:testing"
import level "../level"

@(test)
test_sandbox_last_kill_keeps_the_combat_and_the_arena_refills :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {7, 7}, health = 5, attack = 1}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	room.endless = true
	log: Event_Log
	testing.expect(t, deploy_board_device(&room, .Tesla_Coil, {2, 2}, 8, 0, &log))
	hand := player.deck.hand_count
	action := make_action(.Ability, PLAYER_ENTITY)
	testing.expect(t, add_effect(&action, damage_effect(enemy_entity(room.enemies[0].id), 50)))
	testing.expect(t, resolve_action(&room, &action).accepted)
	// No Loot: the hand, the coils and the clock stay in combat.
	testing.expect_value(t, len(room.enemies), 0)
	testing.expect_value(t, room.phase, Room_Phase.Combat)
	testing.expect_value(t, player.deck.hand_count, hand)
	testing.expect_value(t, board_tesla_count(&room), 1)
	// An empty arena is refilled at once, away from the player.
	sandbox := begin_sandbox(3)
	id, spawned := sandbox_tick(&room, &sandbox, 0)
	testing.expect(t, spawned)
	index, found := enemy_index_by_id(&room, id)
	testing.expect(t, found)
	enemy := room.enemies[index]
	// This 9x9 room is too small for the full distance: the farthest ring of cells.
	testing.expect_value(t, sandbox_distance(&room, enemy.position), 3)
	testing.expect(t, enemy.intent.kind != .None)
	testing.expect(t, validate_enemy_intents(&room))
	// Then one more every SANDBOX_SPAWN_SECONDS, up to the maximum.
	_, spawned = sandbox_tick(&room, &sandbox, SANDBOX_SPAWN_SECONDS*0.5)
	testing.expect(t, !spawned)
	_, spawned = sandbox_tick(&room, &sandbox, SANDBOX_SPAWN_SECONDS*0.5)
	testing.expect(t, spawned)
	for _ in 0..<40 { _, _ = sandbox_tick(&room, &sandbox, SANDBOX_SPAWN_SECONDS) }
	testing.expect_value(t, len(room.enemies), SANDBOX_MAX_ENEMIES)
	// Ordinary rooms still clear on the last kill.
	room.endless = false
	for len(room.enemies) > 0 {
		kill := make_action(.Ability, PLAYER_ENTITY)
		testing.expect(t, add_effect(&kill, damage_effect(enemy_entity(room.enemies[0].id), 100)))
		testing.expect(t, resolve_action(&room, &kill).accepted)
	}
	testing.expect_value(t, room.phase, Room_Phase.Loot)
}

@(test)
test_sandbox_spawns_wait_for_the_board_and_reopen_the_ring :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {7, 7}, health = 5, attack = 1}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	sandbox := begin_sandbox(9)
	// Only an endless room spawns.
	_, spawned := sandbox_tick(&room, &sandbox, 100)
	testing.expect(t, !spawned)
	room.endless = true
	// Never in the middle of a world beat.
	room.tactical_pulse.pending = true
	_, spawned = sandbox_tick(&room, &sandbox, 100)
	testing.expect(t, !spawned)
	room.tactical_pulse.pending = false
	_, spawned = sandbox_tick(&room, &sandbox, 0)
	testing.expect(t, spawned)
	// The floor's easter eggs open again in the sandbox.
	player.floor_secrets = {.Tesla_Ring, .Western_Ranch}
	_, _ = sandbox_tick(&room, &sandbox, 0)
	testing.expect_value(t, player.floor_secrets, bit_set[Floor_Secret; u8]{})
	// A newcomer can never land on an occupied cell.
	testing.expect(t, !enemy_spawn_cell_is_free(&room, player.position))
	testing.expect(t, !enemy_spawn_cell_is_free(&room, room.enemies[0].position))
	_, spawned = spawn_enemy(&room, {position = player.position, health = 5, attack = 1})
	testing.expect(t, !spawned)
}
