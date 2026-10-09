package game

import "core:testing"
import grid "../grid"
import level "../level"

tactical_clock_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player,
	archetype: Enemy_Archetype = .Chaser) -> Room {
	spawns := [?]Enemy_Spawn{{position = {7, 4}, health = 100, attack = 3, archetype = archetype}}
	return create_enemy_rework_room(t, data, player, spawns[:])
}

@(test)
test_tactical_clock_actions_preserve_the_window_and_share_fractional_time :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, !tactical_tick(&room, 0.25, true, true))
	tactical_spend_action_time(&room, 1)
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, player.tactical.remaining, f32(18.75))
	testing.expect_value(t, player.tactical.phase, Tactical_Phase.Decision)
	testing.expect_value(t, player.tactical.budget, 20)
	testing.expect_value(t, player.tactical.cycle, 0)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect_value(t, player.tactical.clock_fraction, f32(0.25))
	testing.expect(t, !tactical_tick(&room, 0.75, true, false))
	testing.expect(t, room.tactical_pulse.pending)
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, player.tactical.remaining, f32(18))
	testing.expect_value(t, room.pulse_count, u64(2))
	testing.expect_value(t, player.tactical.metrics.hologram_seconds, f64(0.25))
}

@(test)
test_tactical_clock_enemies_keep_independent_deadlines_and_frozen_telegraphs :: proc(t: ^testing.T) {
	for archetype in ([?]Enemy_Archetype{.Chaser, .Archer, .Brute, .Bomber, .Custodian, .Demolitionist}) {
		data: level.Level
		player: Player
		room := tactical_clock_test_room(t, &data, &player, archetype)
		initial := room.enemies[0].intent
		seconds := int(room.enemies[0].tactical_cooldown)
		testing.expect(t, seconds >= 2 && seconds <= 4)
		for second in 1..<seconds {
			tactical_spend_action_time(&room, 1)
			drain_tactical_test_pulse(t, &room)
			testing.expect_value(t, room.enemies[0].intent, initial)
			testing.expect_value(t, room.enemies[0].tactical_cooldown, f32(seconds-second))
		}
		tactical_spend_action_time(&room, 1)
		drain_tactical_test_pulse(t, &room)
		testing.expect(t, room.enemies[0].intent.planned_pulse > initial.planned_pulse)
		testing.expect_value(t, room.pulse_count, u64(seconds))
		testing.expect_value(t, player.tactical.cycle, 0)
		destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_tactical_clock_deadline_waits_for_paid_beats_and_resets_only_after_recovery :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	player.tactical.config.timer_seconds = 2
	begin_tactical_room(&room)
	// A cost that exceeds the remaining window is capped at its boundary.
	tactical_spend_action_time(&room, 10)
	testing.expect_value(t, player.tactical.remaining, f32(0))
	testing.expect(t, !tactical_expire_window(&room))
	drain_tactical_test_pulse(t, &room, false)
	testing.expect_value(t, room.pulse_count, u64(2))
	testing.expect(t, !tactical_allows_action(&room))
	testing.expect(t, tactical_tick(&room, 0, true, false))
	testing.expect(t, tactical_expire_window(&room))
	testing.expect_value(t, player.tactical.remaining, TACTICAL_RECOVERY_SECONDS)
	testing.expect_value(t, player.tactical.cycle, 1)
	testing.expect(t, !continue_tactical_pulse(&room))
	testing.expect(t, !tactical_tick(&room, 1, true, false))
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, player.tactical.remaining, f32(2))
	testing.expect_value(t, player.tactical.queued_beats, 0)
	testing.expect_value(t, player.tactical.phase, Tactical_Phase.Decision)
	testing.expect_value(t, room.pulse_count, u64(3))
}

@(test)
test_tactical_clock_pauses_during_qte_and_continuations_without_losing_debt :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	tactical_spend_action_time(&room, 3)
	testing.expect(t, !tactical_tick(&room, 30, true, true))
	testing.expect_value(t, player.tactical.remaining, f32(17))
	testing.expect_value(t, player.tactical.queued_beats, 3)
	testing.expect(t, continue_tactical_pulse(&room))
	room.qte = {kind = .Defense}
	testing.expect(t, !continue_tactical_pulse(&room))
	testing.expect(t, !tactical_tick(&room, 30, true, false))
	testing.expect_value(t, player.tactical.queued_beats, 2)
	room.qte = {}
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, room.pulse_count, u64(3))
	testing.expect_value(t, player.tactical.remaining, f32(17))
	testing.expect(t, tactical_allows_action(&room))
}

@(test)
test_tactical_clock_combat_end_and_new_room_clear_all_time_debt :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	tactical_spend_action_time(&room, 4.5)
	room.phase = .Loot
	tactical_end_combat(&room)
	testing.expect_value(t, player.tactical.clock_fraction, f32(0))
	testing.expect_value(t, player.tactical.queued_beats, 0)
	testing.expect(t, !room.tactical_pulse.pending)
	testing.expect(t, !continue_tactical_pulse(&room))
	player.tactical.clock_fraction, player.tactical.queued_beats = 0.5, 5
	begin_tactical_room(&room)
	testing.expect_value(t, player.tactical.clock_fraction, f32(0))
	testing.expect_value(t, player.tactical.queued_beats, 0)
	testing.expect_value(t, player.tactical.remaining, f32(20))
}

@(test)
test_tactical_clock_stagger_cancels_a_slow_enemy_before_status_expiry :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player, .Archer)
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, room.enemies[0].tactical_cooldown, f32(3))
	_, _ = apply_status(&room, enemy_entity(1), .Stagger, 1, 1)
	tactical_spend_action_time(&room, 1)
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Recover)
	testing.expect(t, !room.enemies[0].aim_ready)
	testing.expect(t, !enemy_is_staggered(&room, &room.enemies[0]))
	testing.expect_value(t, player.health, i32(100))
}

@(test)
test_tactical_clock_heavy_card_leaves_exposure_after_its_own_cost :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {5, 4}, health = 100, attack = 3}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	card := rework_hand_card(t, &room, .Heavy_Blow)
	result := play_card(&room, card.id, entity_target(enemy_entity(1)))
	testing.expect_value(t, result.result, Card_Play_Result.Played)
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, player.tactical.remaining, f32(20)-tactical_card_time_cost(.Heavy_Blow))
	testing.expect_value(t, room.enemies[0].recovery_pulses, i32(1))
	testing.expect_value(t, tactical_strike_bonus(&room, enemy_entity(1)), i32(2))
	testing.expect_value(t, player.health, i32(100))
}

@(test)
test_tactical_clock_rejected_input_does_not_charge_or_reset_time :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	player.position = {1, 1}
	testing.expect(t, !tactical_tick(&room, 0.5, true, false))
	before := player.tactical
	testing.expect_value(t, try_move_player(&room, .North), Action_Result.Blocked)
	testing.expect_value(t, player.position, grid.Position{1, 1})
	testing.expect_value(t, player.tactical, before)
	testing.expect(t, !tactical_tick(&room, 10, false, true))
	testing.expect_value(t, player.tactical, before)
	testing.expect(t, !room.tactical_pulse.pending)
}

@(test)
test_tactical_clock_frame_partition_does_not_duplicate_world_beats :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	for _ in 0..<120 {
		tactical_tick(&room, f32(1)/60, true, false)
		drain_tactical_test_pulse(t, &room)
	}
	testing.expect_value(t, room.pulse_count, u64(2))
	testing.expect(t, abs(player.tactical.remaining-18) < 0.001)
	testing.expect(t, player.tactical.clock_fraction < 0.001)
	testing.expect_value(t, player.tactical.cycle, 0)
}

@(test)
test_tactical_clock_walks_do_not_retarget_a_committed_archer_shot :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player, .Archer)
	defer level.destroy(&data)
	defer destroy_room(&room)
	initial := room.enemies[0].intent
	testing.expect_value(t, try_move_player(&room, .North), Action_Result.Moved)
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, room.enemies[0].intent, initial)
	testing.expect_value(t, try_move_player(&room, .West), Action_Result.Moved)
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, room.enemies[0].intent, initial)
	tactical_tick(&room, 1, true, false)
	drain_tactical_test_pulse(t, &room)
	testing.expect(t, room.enemies[0].aim_ready)
	testing.expect_value(t, room.enemies[0].aim_anchor, grid.Position{4, 4})
	tactical_tick(&room, 1, true, false)
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, player.health, i32(100))
	testing.expect_value(t, room.enemies[0].recovery_pulses, i32(1))
	testing.expect_value(t, player.tactical.remaining, f32(16))
}

@(test)
test_tactical_clock_lethal_first_beat_discards_later_charged_beats :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	_, _ = apply_status(&room, enemy_entity(1), .Poison, 100, 1)
	tactical_spend_action_time(&room, 4)
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, room.phase, Room_Phase.Loot)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect_value(t, player.tactical.queued_beats, 0)
	testing.expect(t, !room.tactical_pulse.pending)
	testing.expect(t, !continue_tactical_pulse(&room))
	testing.expect(t, tactical_allows_action(&room))
}

@(test)
test_tactical_clock_energy_regenerates_every_third_shared_beat_and_stays_capped :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	player.deck.energy = 0
	testing.expect(t, !tactical_tick(&room, 0.5, true, false))
	testing.expect_value(t, try_move_player(&room, .North), Action_Result.Moved)
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect_value(t, player.deck.energy, i32(0))
	testing.expect_value(t, player.tactical.remaining, f32(18.5))
	testing.expect(t, !tactical_tick(&room, 0.5, true, false))
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, room.pulse_count, u64(2))
	testing.expect_value(t, player.deck.energy, i32(0))
	testing.expect(t, !tactical_tick(&room, 1, true, false))
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, room.pulse_count, u64(3))
	testing.expect_value(t, player.deck.energy, i32(1))
	// Two real seconds plus exactly one second for the accepted movement.
	testing.expect_value(t, player.tactical.remaining, f32(17))
	testing.expect_value(t, player.tactical.metrics.decisions, u64(1))
	for beat in 4..=12 {
		testing.expect(t, !tactical_tick(&room, 1, true, false))
		drain_tactical_test_pulse(t, &room)
		testing.expect_value(t, room.pulse_count, u64(beat))
		testing.expect_value(t, player.deck.energy, min(player.deck.rules.max_energy, i32(beat/3)))
	}
	testing.expect_value(t, player.deck.energy, player.deck.rules.max_energy)
	testing.expect_value(t, player.tactical.remaining, f32(8))
	markers := 0
	for event in room.recent_events.events[:room.recent_events.count] {
		if event.kind != .Pulse_Advanced { continue }
		markers += 1
		testing.expect_value(t, event.energy_restored, i32(0))
		testing.expect_value(t, event.energy_wasted, i32(1))
	}
	testing.expect_value(t, markers, 1)
}
