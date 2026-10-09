package game

import "core:testing"
import level "../level"
import grid "../grid"

@(test)
test_larger_fog_exposes_blockers_but_not_cells_behind_them :: proc(t: ^testing.T) {
	rows := [?]string{"#########", "#.......#", "#.......#", "#.......#", "#...@...#", "#.......#", "#.......#", "#...>...#", "#########"}
	data, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	defer level.destroy(&data)
	player := create_test_player(t)
	testing.expect(t, configure_tactical(&player, DEFAULT_TACTICAL_CONFIG))
	room, ok := create_room(&data, &player, {})
	testing.expect(t, ok)
	defer destroy_room(&room)
	for size in ([?]int{3, 5, 7}) {
		player.tactical.config.vision_size = size
		count := 0
		for y in 0..<9 { for x in 0..<9 { if tactical_cell_visible(&room, {x, y}) { count += 1 } } }
		testing.expect_value(t, count, size*size)
	}
	append(&room.obstacles, Obstacle{position = {5, 4}})
	testing.expect(t, tactical_cell_visible(&room, {5, 4}))
	testing.expect(t, !tactical_cell_visible(&room, {6, 4}))
	testing.expect(t, !tactical_cell_visible(&room, {7, 4}))
	testing.expect(t, tactical_cell_visible(&room, {4, 7}))
	append(&room.obstacles, Obstacle{position = {4, 5}})
	testing.expect(t, !tactical_cell_visible(&room, {6, 6}))
	clear(&room.obstacles)
	player.position = {1, 1}
	testing.expect(t, !tactical_cell_visible(&room, {6, 6}))
}

tactical_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, adjacent: bool = false) -> Room {
	data^ = create_test_level(t)
	player^ = create_test_player(t)
	player.health = 1000
	player.stats.max_health = 1000
	config := DEFAULT_TACTICAL_CONFIG
	config.timer_seconds = 2
	testing.expect(t, configure_tactical(player, config))
	spawns := [?]Enemy_Spawn{{position = ({2, 1} if adjacent else {5, 3}), health = 1000, attack = 3}}
	room, ok := create_room(data, player, {enemies = spawns[:]})
	testing.expect(t, ok)
	// Defense fixtures begin one second before an already committed attack.
	// Role cadence itself is exercised separately by tactical_clock_test.
	if adjacent { room.enemies[0].tactical_cooldown = 1 }
	return room
}

drain_tactical_test_pulse :: proc(t: ^testing.T, room: ^Room, expire_window: bool = true) {
	for _ in 0..<4000 {
		if tactical_is_casting(room) {
			tactical_tick(room, room.player.tactical.cast_remaining, true, false)
		}
		if room.qte.kind != .None { testing.expect(t, resolve_qte(room, false)) }
		if !room.tactical_pulse.pending {
			if expire_window && room.phase == .Combat && room.player.tactical.phase == .Decision && room.player.tactical.remaining <= 0 {
				testing.expect(t, tactical_expire_window(room))
			}
			return
		}
		testing.expect(t, continue_tactical_pulse(room))
		testing.expect_value(t, room.recent_events.dropped_count, 0)
	}
	testing.expect(t, false, "pulse failed to terminate")
}

@(test)
test_tactical_windows_have_fixed_recovery_without_per_action_timer_reset :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	for cycle in 1..=4 {
		for spent in 0..<2 {
			testing.expect_value(t, player.tactical.budget, 2)
			testing.expect_value(t, player.tactical.remaining, f32(2-spent))
			testing.expect(t, wait_player_turn(&room) != .Invalid_Phase)
			drain_tactical_test_pulse(t, &room)
		}
		testing.expect_value(t, player.tactical.cycle, cycle)
		testing.expect(t, tactical_is_recovering(&room))
		testing.expect_value(t, player.tactical.remaining, TACTICAL_RECOVERY_SECONDS)
		testing.expect(t, !continue_tactical_pulse(&room), "animation updates cannot manufacture recovery beats")
		testing.expect(t, !tactical_tick(&room, TACTICAL_RECOVERY_SECONDS, true, false))
		drain_tactical_test_pulse(t, &room)
		testing.expect_value(t, player.tactical.phase, Tactical_Phase.Decision)
		testing.expect_value(t, player.tactical.budget, 2)
	}
	testing.expect_value(t, player.tactical.metrics.forced_pulses, u64(4))
	testing.expect_value(t, room.pulse_count, u64(12))
}

@(test)
test_tactical_hologram_uses_clock_and_rejected_inputs_do_not_reset_it :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, !tactical_tick(&room, 0.25, true, true))
	testing.expect_value(t, try_move_player(&room, .North), Action_Result.Blocked)
	testing.expect_value(t, player.tactical.remaining, f32(1.75))
	testing.expect(t, !tactical_tick(&room, 1, true, true))
	testing.expect(t, room.tactical_pulse.pending)
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, player.tactical.remaining, f32(0.75))
	testing.expect_value(t, player.tactical.metrics.hologram_seconds, f64(1.25))
	testing.expect(t, !tactical_tick(&room, 10, false, true))
	testing.expect_value(t, player.tactical.remaining, f32(0.75))
	testing.expect(t, !tactical_tick(&room, 1, true, true))
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, player.tactical.remaining, TACTICAL_RECOVERY_SECONDS)
	testing.expect(t, tactical_is_recovering(&room))
	testing.expect_value(t, room.pulse_count, u64(2))
	testing.expect_value(t, player.tactical.metrics.hologram_seconds, f64(2))
}

@(test)
test_tactical_cards_refill_after_cast_without_advancing_world :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	player.deck.hand[0].definition_id = .Guard
	for &owned in player.deck.owned[:player.deck.owned_count] {
		if owned.id == player.deck.hand[0].id { owned.definition_id = .Guard }
	}
	hand := player.deck.hand_count
	play := play_card(&room, player.deck.hand[0].id, entity_target(PLAYER_ENTITY))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, player.deck.hand_count, hand-1)
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect_value(t, player.deck.hand_count, hand)
	testing.expect_value(t, player.tactical.phase, Tactical_Phase.Decision)
	testing.expect(t, validate_deck_state(&player.deck))
}

@(test)
test_tactical_diagonal_success_and_failure_each_consume_one_pulse :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, begin_diagonal_qte(&room, {1, 1}))
	testing.expect(t, qte_key(&room, .East))
	testing.expect(t, qte_key(&room, .South))
	testing.expect_value(t, player.position, grid.Position{2, 2})
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect(t, begin_diagonal_qte(&room, {-1, -1}))
	testing.expect(t, qte_key(&room, .East))
	testing.expect_value(t, player.position, grid.Position{2, 2})
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, room.pulse_count, u64(2))
	testing.expect_value(t, player.tactical.metrics.qte_failures, u64(1))
}

@(test)
test_tactical_defense_waits_before_damage_and_parry_resumes_once :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_test_room(t, &data, &player, true)
	defer level.destroy(&data)
	defer destroy_room(&room)
	_, _ = apply_status(&room, PLAYER_ENTITY, .Shield, 1, 3)
	health := player.health
	testing.expect(t, wait_player_turn(&room) != .Invalid_Phase)
	testing.expect(t, continue_tactical_pulse(&room))
	testing.expect(t, continue_tactical_pulse(&room))
	testing.expect_value(t, room.qte.kind, QTE_Kind.Defense)
	testing.expect_value(t, player.health, health)
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect(t, !continue_tactical_pulse(&room))
	testing.expect(t, select_defense(&room, .Parry))
	testing.expect(t, qte_key(&room, room.qte.keys[0]))
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, room.enemies[0].health, i32(998))
	testing.expect_value(t, player.health, health)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect(t, !continue_tactical_pulse(&room))
}

@(test)
test_tactical_visibility_does_not_remember_cells_and_rejects_hidden_targets :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	player.tactical.config.vision_size = 5
	testing.expect(t, tactical_cell_visible(&room, {1, 1}))
	testing.expect(t, !tactical_cell_visible(&room, {5, 3}))
	player.position = {4, 2}
	testing.expect(t, !tactical_cell_visible(&room, {1, 1}))
	testing.expect(t, tactical_cell_visible(&room, {5, 3}))
	player.position = {1, 1}
	play := play_card(&room, player.deck.hand[0].id, entity_target(enemy_entity(room.enemies[0].id)))
	testing.expect_value(t, play.result, Card_Play_Result.Action_Rejected)
	testing.expect_value(t, room.pulse_count, u64(0))
}

@(test)
test_tactical_failed_defense_and_terminal_recovery_beat :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_test_room(t, &data, &player, true)
	defer level.destroy(&data)
	defer destroy_room(&room)
	player.health = 1
	player.tactical.remaining = 0
	testing.expect(t, tactical_expire_window(&room))
	testing.expect(t, !tactical_tick(&room, 1, true, false))
	_, _ = apply_status(&room, PLAYER_ENTITY, .Afterimage, 1, 4)
	testing.expect(t, continue_tactical_pulse(&room))
	testing.expect(t, continue_tactical_pulse(&room))
	testing.expect_value(t, room.qte.kind, QTE_Kind.Defense)
	testing.expect(t, resolve_qte(&room, false))
	testing.expect(t, continue_tactical_pulse(&room))
	testing.expect_value(t, room.phase, Room_Phase.Defeat)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect(t, !continue_tactical_pulse(&room))
	testing.expect(t, !room.tactical_pulse.pending)
}

@(test)
test_tactical_parry_kill_finishes_started_pulse_without_extra_attack :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_test_room(t, &data, &player, true)
	defer level.destroy(&data)
	defer destroy_room(&room)
	room.enemies[0].health = 1
	_, _ = apply_status(&room, PLAYER_ENTITY, .Shield, 1, 3)
	testing.expect(t, wait_player_turn(&room) != .Invalid_Phase)
	testing.expect(t, continue_tactical_pulse(&room))
	testing.expect(t, continue_tactical_pulse(&room))
	testing.expect(t, select_defense(&room, .Parry))
	testing.expect(t, qte_key(&room, room.qte.keys[0]))
	testing.expect_value(t, room.phase, Room_Phase.Loot)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect_value(t, player.health, i32(1000))
	markers := 0
	for event in room.recent_events.events[:room.recent_events.count] {
		if event.kind == .Pulse_Advanced { markers += 1 }
	}
	testing.expect_value(t, markers, 1)
	testing.expect(t, !continue_tactical_pulse(&room))
}

@(test)
test_tactical_deflection_requires_thorns_and_preserves_committed_intent :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_test_room(t, &data, &player, true)
	defer level.destroy(&data)
	defer destroy_room(&room)
	room.enemies[0].archetype = .Archer
	_, _ = apply_status(&room, PLAYER_ENTITY, .Thorns, 1, 3)
	intent := room.enemies[0].intent
	testing.expect(t, wait_player_turn(&room) != .Invalid_Phase)
	testing.expect(t, continue_tactical_pulse(&room))
	testing.expect(t, continue_tactical_pulse(&room))
	testing.expect(t, !select_defense(&room, .Parry))
	testing.expect(t, select_defense(&room, .Deflect))
	testing.expect(t, qte_key(&room, room.qte.keys[0]))
	testing.expect_value(t, room.enemies[0].intent, intent)
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, room.enemies[0].health, i32(1000)-intent.damage)
	testing.expect_value(t, player.health, i32(1000))
}

@(test)
test_tactical_dodge_revalidates_landing_and_can_invalidate_an_attack :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_test_room(t, &data, &player, true)
	defer level.destroy(&data)
	defer destroy_room(&room)
	_, _ = apply_status(&room, PLAYER_ENTITY, .Afterimage, 1, 3)
	testing.expect(t, wait_player_turn(&room) != .Invalid_Phase)
	testing.expect(t, continue_tactical_pulse(&room))
	testing.expect(t, continue_tactical_pulse(&room))
	testing.expect(t, select_defense(&room, .Dodge))
	testing.expect(t, qte_key(&room, .South))
	testing.expect_value(t, player.position, grid.Position{1, 2})
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, player.health, i32(1000))
	testing.expect_value(t, room.pulse_count, u64(1))
}

@(test)
test_tactical_two_by_two_and_opaque_corners :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	player.position = {3, 2}
	player.tactical.config.vision_size = 2
	player.tactical.facing = .North
	count := 0
	for y in 0..<data.tiles.height {
		for x in 0..<data.tiles.width {
			if tactical_cell_visible(&room, {x, y}) { count += 1 }
		}
	}
	testing.expect_value(t, count, 4)
	player.tactical.config.vision_size = 3
	append(&room.obstacles, Obstacle{position = {4, 2}})
	append(&room.obstacles, Obstacle{position = {3, 3}})
	testing.expect(t, !tactical_cell_visible(&room, {4, 3}))
	testing.expect(t, !begin_diagonal_qte(&room, {1, 1}))
	testing.expect_value(t, room.pulse_count, u64(0))
}

@(test)
test_tactical_room_change_resets_pressure_but_preserves_run_metrics :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_test_room(t, &data, &player)
	defer level.destroy(&data)
	player.tactical.cycle = 5
	player.tactical.budget = 1
	player.tactical.metrics = {decisions = 11, pauses = 5, forced_pulses = 25, hologram_seconds = 8.25}
	metrics := player.tactical.metrics
	config := player.tactical.config
	room.phase = .Loot
	sync_deck_with_room_phase(&room)
	tactical_end_combat(&room)
	destroy_room(&room)
	spawns := [?]Enemy_Spawn{{position = {5, 3}, health = 5, attack = 1}}
	ok: bool
	room, ok = create_room(&data, &player, {enemies = spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	testing.expect_value(t, player.tactical.cycle, 0)
	testing.expect_value(t, player.tactical.budget, config.timer_seconds)
	testing.expect_value(t, player.tactical.remaining, f32(config.timer_seconds))
	testing.expect_value(t, player.tactical.phase, Tactical_Phase.Decision)
	testing.expect_value(t, player.tactical.config, config)
	testing.expect_value(t, player.tactical.metrics, metrics)
	testing.expect(t, !room.tactical_pulse.pending)
	testing.expect(t, configure_tactical(&player, DEFAULT_TACTICAL_CONFIG))
	testing.expect_value(t, player.tactical.cycle, 0)
	testing.expect_value(t, player.tactical.budget, 20)
	testing.expect_value(t, player.tactical.metrics, Tactical_Metrics{})
}

@(test)
test_tactical_action_time_and_idle_time_produce_identical_world_results :: proc(t: ^testing.T) {
	data_a, data_b: level.Level
	player_a, player_b: Player
	room_a := tactical_test_room(t, &data_a, &player_a, true)
	room_b := tactical_test_room(t, &data_b, &player_b, true)
	defer level.destroy(&data_a)
	defer level.destroy(&data_b)
	defer destroy_room(&room_a)
	defer destroy_room(&room_b)
	for player in ([2]^Player{&player_a, &player_b}) {
		player.tactical.config.timer_seconds = 20
		player.tactical.budget, player.tactical.remaining = 20, 20
	}
	_, _ = apply_status(&room_a, PLAYER_ENTITY, .Shield, 3, 3)
	_, _ = apply_status(&room_b, PLAYER_ENTITY, .Shield, 3, 3)
	// A real-time second and a paid action second feed exactly the same world
	// schedule, including enemy recovery, status expiry and energy regeneration.
	for _ in 0..<4 {
		testing.expect(t, !tactical_tick(&room_a, 1, true, false))
		testing.expect(t, wait_player_turn(&room_b) != .Invalid_Phase)
		drain_tactical_test_pulse(t, &room_a)
		drain_tactical_test_pulse(t, &room_b)
		testing.expect_value(t, room_b.pulse_count, room_a.pulse_count)
		testing.expect_value(t, player_b.health, player_a.health)
		testing.expect_value(t, player_b.statuses, player_a.statuses)
		testing.expect_value(t, player_b.deck, player_a.deck)
		testing.expect_value(t, room_b.enemies[0], room_a.enemies[0])
	}
}
