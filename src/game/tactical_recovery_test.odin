package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

@(test)
test_tactical_recovery_walks_are_free_but_attacks_and_cards_are_unavailable :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_test_room(t, &data, &player, true)
	defer level.destroy(&data)
	defer destroy_room(&room)
	player.tactical.remaining = 0
	testing.expect(t, tactical_expire_window(&room))
	before := player.tactical
	deck := player.deck
	health := room.enemies[0].health
	record_event(room.recent_events, {kind = .Pulse_Advanced})
	log := room.recent_events^
	testing.expect(t, tactical_allows_movement(&room))
	testing.expect(t, !tactical_allows_action(&room))
	testing.expect_value(t, try_move_player(&room, .East), Action_Result.Invalid_Phase)
	testing.expect_value(t, play_card(&room, player.deck.hand[0].id, entity_target(PLAYER_ENTITY)).result, Card_Play_Result.Invalid_Phase)
	testing.expect_value(t, refocus_player_hand(&room).result, Refocus_Result.Invalid_Phase)
	testing.expect_value(t, wait_player_turn(&room), Action_Result.Invalid_Phase)
	testing.expect_value(t, use_player_ability(&room, .Guard), Action_Result.Invalid_Phase)
	testing.expect(t, !try_dodge_player(&room, .South))
	testing.expect(t, !begin_diagonal_qte(&room, {1, 1}))
	testing.expect_value(t, room.recent_events^, log)
	testing.expect_value(t, room.enemies[0].health, health)
	testing.expect_value(t, player.deck, deck)
	for direction in ([?]Move_Direction{.South, .South, .East, .West, .North, .North}) {
		testing.expect_value(t, try_move_player(&room, direction), Action_Result.Moved)
		testing.expect_value(t, player.tactical, before)
		testing.expect_value(t, room.pulse_count, u64(0))
		testing.expect(t, !room.tactical_pulse.pending)
	}
	testing.expect_value(t, player.position, grid.Position{1, 1})
}

@(test)
test_tactical_recovery_uses_one_active_second_across_frame_partitions :: proc(t: ^testing.T) {
	for partitions in ([?]int{1, 4, 60, 120}) {
		data: level.Level
		player: Player
		room := tactical_clock_test_room(t, &data, &player)
		player.tactical.remaining = 0
		testing.expect(t, tactical_expire_window(&room))
		for frame in 0..<partitions {
			testing.expect(t, tactical_is_recovering(&room))
			testing.expect(t, !tactical_tick(&room, f32(1)/f32(partitions), true, false))
			drain_tactical_test_pulse(t, &room)
			if frame < partitions-1 { testing.expect(t, tactical_is_recovering(&room)) }
		}
		testing.expect_value(t, player.tactical.phase, Tactical_Phase.Decision)
		testing.expect_value(t, player.tactical.remaining, f32(20))
		testing.expect_value(t, room.pulse_count, u64(1))
		testing.expect_value(t, player.tactical.metrics.forced_pulses, u64(1))
		testing.expect(t, abs(player.tactical.clock_fraction) < 0.0001)
		destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_tactical_recovery_early_world_beat_does_not_end_the_timer :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	player.tactical.remaining = 0
	player.tactical.clock_fraction = 0.75
	testing.expect(t, tactical_expire_window(&room))
	testing.expect(t, !tactical_tick(&room, 0.25, true, true))
	drain_tactical_test_pulse(t, &room)
	testing.expect(t, tactical_is_recovering(&room))
	testing.expect_value(t, player.tactical.remaining, f32(0.75))
	testing.expect_value(t, room.pulse_count, u64(1))
	for _ in 0..<20 { testing.expect(t, !continue_tactical_pulse(&room)) }
	testing.expect(t, !tactical_tick(&room, 10, false, false))
	testing.expect_value(t, player.tactical.remaining, f32(0.75))
	testing.expect(t, !tactical_tick(&room, 0.75, true, true))
	testing.expect_value(t, player.tactical.phase, Tactical_Phase.Decision)
	testing.expect_value(t, player.tactical.remaining, f32(20))
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect_value(t, player.tactical.clock_fraction, f32(0.75))
	testing.expect_value(t, player.tactical.metrics.hologram_seconds, f64(1))
}

@(test)
test_tactical_recovery_shares_enemy_bomb_status_and_energy_clock :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	room.pulse_count = 2
	room.enemies[0].tactical_cooldown = 1
	initial_position := room.enemies[0].position
	player.deck.energy = 0
	// A status that runs by the beat (Veleno now waits for his own actions).
	_, _ = apply_status(&room, PLAYER_ENTITY, .Thorns, 2, 1)
	testing.expect(t, spawn_bomb(&room, enemy_entity(1), player.position, room.recent_events))
	room.objects[0].detonation_pulse = 3
	player.tactical.remaining = 0
	testing.expect(t, tactical_expire_window(&room))
	testing.expect(t, !tactical_tick(&room, 0.5, true, false))
	testing.expect_value(t, player.health, i32(100))
	testing.expect_value(t, active_bomb_count(&room), 1)
	testing.expect_value(t, room.enemies[0].position, initial_position)
	testing.expect_value(t, player.deck.energy, i32(0))
	testing.expect(t, !tactical_tick(&room, 0.5, true, false))
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, room.pulse_count, u64(3))
	testing.expect_value(t, player.health, i32(97))
	testing.expect_value(t, active_bomb_count(&room), 0)
	testing.expect(t, room.enemies[0].position != initial_position)
	_, thorned := status_for_entity(&room, PLAYER_ENTITY, .Thorns)
	testing.expect(t, !thorned)
	testing.expect_value(t, player.deck.energy, i32(1))
	testing.expect_value(t, player.tactical.phase, Tactical_Phase.Decision)
}

@(test)
test_tactical_recovery_defense_qte_suspends_time_then_resumes_same_window :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_test_room(t, &data, &player, true)
	defer level.destroy(&data)
	defer destroy_room(&room)
	player.tactical.remaining = 0
	player.tactical.clock_fraction = 0.5
	testing.expect(t, tactical_expire_window(&room))
	testing.expect(t, !tactical_tick(&room, 0.5, true, false))
	testing.expect(t, continue_tactical_pulse(&room))
	testing.expect(t, continue_tactical_pulse(&room))
	testing.expect_value(t, room.qte.kind, QTE_Kind.Defense)
	testing.expect(t, !tactical_allows_movement(&room))
	testing.expect(t, !tactical_tick(&room, 10, true, false))
	testing.expect_value(t, player.tactical.remaining, f32(0.5))
	testing.expect(t, select_defense(&room, .Dodge))
	testing.expect(t, qte_key(&room, .South))
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, player.health, i32(1000))
	testing.expect(t, tactical_is_recovering(&room))
	testing.expect(t, tactical_allows_movement(&room))
	testing.expect(t, !tactical_tick(&room, 0.5, true, false))
	testing.expect_value(t, player.tactical.phase, Tactical_Phase.Decision)
	testing.expect_value(t, player.tactical.remaining, f32(2))
	testing.expect_value(t, room.pulse_count, u64(1))
}

@(test)
test_tactical_recovery_walk_still_resolves_lethal_floor_hazards :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {7, 1}, health = 100, attack = 1}}
	objects := [?]Grid_Object_Spawn{{kind = .Fire, position = {4, 5}}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:], objects[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	player.health = 1
	player.tactical.remaining = 0
	testing.expect(t, tactical_expire_window(&room))
	testing.expect_value(t, try_move_player(&room, .South), Action_Result.Player_Defeated)
	testing.expect_value(t, room.phase, Room_Phase.Defeat)
	testing.expect(t, !room.tactical_pulse.pending)
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect(t, !tactical_is_recovering(&room))
}

@(test)
test_tactical_recovery_lethal_world_beat_cleans_up_without_an_extra_window :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	// Its own move on the recovery's beat is what its poison bites.
	room.enemies[0].tactical_cooldown = 1
	_, _ = apply_status(&room, enemy_entity(1), .Poison, 100, 0)
	player.tactical.remaining = 0
	testing.expect(t, tactical_expire_window(&room))
	testing.expect(t, !tactical_tick(&room, 1, true, false))
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, room.phase, Room_Phase.Loot)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect_value(t, player.tactical.metrics.forced_pulses, u64(1))
	testing.expect_value(t, player.tactical.cycle, 1)
	testing.expect_value(t, player.tactical.clock_fraction, f32(0))
	testing.expect_value(t, player.tactical.queued_beats, 0)
	testing.expect(t, !room.tactical_pulse.pending)
	testing.expect(t, !continue_tactical_pulse(&room))
	testing.expect_value(t, try_move_player(&room, .North), Action_Result.Moved)
}
