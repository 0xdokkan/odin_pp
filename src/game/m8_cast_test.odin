package game

import "core:testing"
import level "../level"

@(test)
test_m8_card_cast_charges_only_pulse_gradually_and_freezes_world_state :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	card := rework_hand_card(t, &room, .Guard)
	tactical_tick(&room, 0.25, true, false)
	before, enemy := player.tactical, room.enemies[0]
	result := play_card(&room, card.id, entity_target(PLAYER_ENTITY))
	testing.expect_value(t, result.result, Card_Play_Result.Played)
	testing.expect_value(t, player.tactical.remaining, before.remaining)
	testing.expect_value(t, player.tactical.cast_remaining, tactical_card_time_cost(.Guard))
	testing.expect(t, !tactical_allows_action(&room) && !tactical_allows_movement(&room))
	testing.expect(t, !tactical_tick(&room, 0.25, true, false))
	testing.expect_value(t, player.tactical.remaining, before.remaining-0.25)
	testing.expect_value(t, player.tactical.cast_remaining, f32(0.75))
	testing.expect(t, !tactical_tick(&room, 0.75, true, false))
	testing.expect_value(t, player.tactical.remaining, before.remaining-1)
	testing.expect(t, tactical_allows_action(&room))
	testing.expect_value(t, player.tactical.clock_fraction, before.clock_fraction)
	testing.expect_value(t, player.tactical.queued_beats, 0)
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect_value(t, room.enemies[0], enemy)
	shield, found := status_for_entity(&room, PLAYER_ENTITY, .Shield)
	testing.expect(t, found)
	if found { testing.expect_value(t, shield.remaining_pulses, i32(2)) }
}

@(test)
test_m8_card_cast_long_frame_has_no_world_catchup_and_respects_pause :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	tactical_begin_card_cast(&room, 3)
	before := player.tactical
	testing.expect(t, !tactical_tick(&room, 10, false, true))
	testing.expect_value(t, player.tactical, before)
	testing.expect(t, !tactical_tick(&room, 10, true, false))
	testing.expect_value(t, player.tactical.remaining, f32(17))
	testing.expect_value(t, player.tactical.cast_remaining, f32(0))
	testing.expect_value(t, player.tactical.clock_fraction, f32(0))
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect(t, !tactical_tick(&room, 0.5, true, false))
	testing.expect_value(t, player.tactical.clock_fraction, f32(0.5))
}

@(test)
test_m8_last_positive_window_finishes_full_cast_before_recovery :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	player.tactical.remaining = 0.25
	tactical_begin_card_cast(&room, 3)
	testing.expect(t, !tactical_tick(&room, 0.5, true, false))
	testing.expect_value(t, player.tactical.remaining, f32(0))
	testing.expect_value(t, player.tactical.cast_remaining, f32(2.5))
	testing.expect(t, !tactical_expire_window(&room))
	testing.expect(t, tactical_tick(&room, 2.5, true, false))
	testing.expect_value(t, player.tactical.cast_remaining, f32(0))
	testing.expect(t, tactical_expire_window(&room))
	testing.expect_value(t, player.tactical.phase, Tactical_Phase.Recovery)
	testing.expect_value(t, player.tactical.remaining, TACTICAL_RECOVERY_SECONDS)
	testing.expect_value(t, room.pulse_count, u64(0))
}

@(test)
test_m8_rejected_card_never_starts_cast_or_changes_existing_time :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	card := rework_hand_card(t, &room, .Guard)
	player.deck.energy = 0
	before := player.tactical
	result := play_card(&room, card.id, entity_target(PLAYER_ENTITY))
	testing.expect_value(t, result.result, Card_Play_Result.Not_Enough_Energy)
	testing.expect_value(t, player.tactical, before)
	testing.expect(t, !tactical_is_casting(&room))
}

@(test)
test_m8_cast_endfight_and_room_entry_clear_cast_lifecycle :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	tactical_begin_card_cast(&room, 4)
	room.phase = .Loot
	tactical_end_combat(&room)
	testing.expect_value(t, player.tactical.cast_remaining, f32(0))
	testing.expect_value(t, player.tactical.cast_duration, f32(0))
	testing.expect(t, !tactical_is_casting(&room))
	player.tactical.cast_remaining, player.tactical.cast_duration = 2, 4
	begin_tactical_room(&room)
	testing.expect_value(t, player.tactical.cast_remaining, f32(0))
	testing.expect_value(t, player.tactical.cast_duration, f32(0))
}
