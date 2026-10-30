package game

import "core:testing"
import level "../level"

@(test)
test_takeovers_preserve_pinball_and_room_objects_across_freeze_and_cleanup :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 7, y = 6}, health = 30, attack = 1}, {position = {x = 9, y = 6}, health = 30, attack = 1}}
	room := lasso_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	report: Action_Report
	testing.expect(t, begin_pinball(&room, enemy_entity(room.enemies[0].id), 2, &report))
	testing.expect(t, deploy_board_device(&room, .Tesla_Coil, {x = 4, y = 4}, 8, 0, room.recent_events))
	device := room.objects[0]
	fishing := room.fishing
	ball := room.pinball
	window := player.tactical.remaining
	testing.expect(t, tactical_begin_shadow(&room, 1))
	testing.expect_value(t, tactical_clock_mode(&room), Tactical_Clock_Mode.Shadow)
	testing.expect(t, !tactical_tick(&room, 1, true, false))
	testing.expect_value(t, room.pinball, ball)
	testing.expect_value(t, player.tactical.remaining, window)
	testing.expect(t, tactical_end_shadow(&room))
	testing.expect(t, tactical_begin_first_person(&room, 2))
	testing.expect(t, tactical_allows_movement(&room) && !tactical_allows_cards(&room))
	testing.expect(t, !tactical_tick(&room, 0.25, true, false))
	testing.expect_value(t, room.pinball.pending, f64(0.25))
	testing.expect_value(t, room.first_person.remaining, f32(1.75))
	// A cast spends its window while both ongoing world mechanics stand still.
	tactical_begin_card_cast(&room, 0.25)
	testing.expect_value(t, tactical_clock_mode(&room), Tactical_Clock_Mode.Cast)
	testing.expect(t, !tactical_tick(&room, 0.25, true, false))
	testing.expect_value(t, room.pinball.pending, f64(0.25))
	testing.expect_value(t, room.first_person.remaining, f32(1.75))
	room.first_person.shots, room.first_person.hits = 3, 2
	room.phase = .Loot
	tactical_end_combat(&room)
	testing.expect(t, !room.pinball.active && !room.lasso.active && !room.first_person.active)
	testing.expect_value(t, room.first_person.shots, i32(3))
	testing.expect_value(t, room.first_person.hits, i32(2))
	testing.expect_value(t, room.objects[0], device)
	testing.expect_value(t, room.fishing, fishing)
	testing.expect_value(t, tactical_clock_mode(&room), Tactical_Clock_Mode.Paused)
}

@(test)
test_control_policy_preserves_recovery_stun_and_takeover_entry_differences :: proc(t: ^testing.T) {
	player := create_test_player(t)
	room := Room{player = &player, phase = .Combat}
	s := &player.tactical
	s.phase, s.remaining = .Recovery, 0
	testing.expect(t, tactical_allows_movement(&room) && !tactical_allows_action(&room) && !tactical_allows_cards(&room))
	s.phase, s.remaining, s.action_remaining = .Stunned, 1, 0.5
	testing.expect(t, tactical_allows_cards(&room) && !tactical_allows_movement(&room))
	// FPS can be the effect currently being cast; Shadow requires a still world.
	s.cast_remaining, s.queued_beats = 0.5, 1
	testing.expect(t, tactical_can_begin_first_person(&room) && !tactical_can_begin_shadow(&room))
	room.lasso.active = true
	testing.expect(t, !tactical_can_begin_first_person(&room) && !tactical_allows_cards(&room))
	s.phase, s.cast_remaining, s.action_remaining, s.queued_beats = .Decision, 0, 0, 0
	testing.expect(t, !tactical_allows_action(&room) && tactical_allows_action(&room, true))
	room.qte.kind = .Defense
	testing.expect(t, !tactical_allows_action(&room, true))
	testing.expect_value(t, tactical_clock_mode(&room), Tactical_Clock_Mode.Paused)
}
