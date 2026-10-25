package game

import "core:testing"
import level "../level"

@(test)
test_tactical_beats_are_struck_only_by_real_time_and_reward_once :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_clock_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	// A fresh window starts on a whole second, but that is not a tick.
	testing.expect_value(t, tactical_beat_target(&room), u32(0))
	// Paying an action advances the clock by whole seconds without a tick.
	tactical_spend_action_time(&room, 1)
	drain_tactical_test_pulse(t, &room, false)
	testing.expect_value(t, player.tactical.beat_index, u32(0))
	testing.expect_value(t, tactical_beat_target(&room), u32(0))
	// Real time nearing the next second opens the window early...
	testing.expect(t, !tactical_tick(&room, 0.9, true, false))
	testing.expect_value(t, tactical_beat_target(&room), u32(1))
	testing.expect(t, tactical_claim_beat(&room, 1))
	// ...and that beat rewards a single action, before or after it strikes.
	testing.expect(t, !tactical_claim_beat(&room, 1))
	testing.expect(t, !tactical_tick(&room, 0.15, true, false))
	drain_tactical_test_pulse(t, &room, false)
	testing.expect_value(t, player.tactical.beat_index, u32(1))
	testing.expect_value(t, tactical_beat_target(&room), u32(0))
	// The next one is caught just after it strikes.
	testing.expect(t, !tactical_tick(&room, 0.85, true, false))
	testing.expect(t, !tactical_tick(&room, 0.12, true, false))
	drain_tactical_test_pulse(t, &room, false)
	testing.expect_value(t, player.tactical.beat_index, u32(2))
	testing.expect_value(t, tactical_beat_target(&room), u32(2))
	// Too long after it, the tick is gone.
	testing.expect(t, !tactical_tick(&room, 0.2, true, false))
	testing.expect_value(t, tactical_beat_target(&room), u32(0))
	testing.expect(t, !tactical_claim_beat(&room, 1))
}

@(test)
test_tactical_critical_steps_bumps_and_diagonals :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 4, y = 3}, health = 100, attack = 1}, {position = {x = 7, y = 7}, health = 100, attack = 1}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	base := player_basic_attack_damage(&player)
	// A bump on the tick hits twice as hard.
	player.tactical.critical_next = true
	testing.expect_value(t, try_move_player(&room, .North), Action_Result.Attacked)
	testing.expect_value(t, room.enemies[0].health, 100-critical_bump_damage(base))
	testing.expect(t, !player.tactical.critical_next)
	drain_tactical_test_pulse(t, &room, false)
	// A straight step on the tick is still one cell: the tick's step is the diagonal.
	player.tactical.critical_next = true
	start := player.position
	testing.expect_value(t, try_move_player(&room, .West), Action_Result.Moved)
	testing.expect_value(t, player.position.x, start.x-1)
	testing.expect(t, !player.tactical.critical_next)
	drain_tactical_test_pulse(t, &room, false)
	// Two keys on the tick step diagonally; a single axis is not a diagonal.
	testing.expect_value(t, try_move_player_diagonal(&room, {x = 1, y = 0}), Action_Result.Blocked)
	before := player.position
	testing.expect_value(t, try_move_player_diagonal(&room, {x = 1, y = 1}), Action_Result.Moved)
	testing.expect_value(t, player.position.x, before.x+1)
	testing.expect_value(t, player.position.y, before.y+1)
}

@(test)
test_tactical_critical_cards_strengthen_every_effect_kind :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 7, y = 7}, health = 100, attack = 1}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	action := make_action(.Card, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
	testing.expect(t, add_effect(&action, damage_effect(enemy_entity(room.enemies[0].id), 3)))
	testing.expect(t, add_effect(&action, apply_status_effect(PLAYER_ENTITY, .Shield, 4, 2)))
	testing.expect(t, add_effect(&action, apply_status_effect(enemy_entity(room.enemies[0].id), .Poison, 2, 0)))
	testing.expect(t, add_effect(&action, Effect{kind = .Gain_Gold, target = PLAYER_ENTITY, amount = 6}))
	plain := action
	tactical_critical_scale(&room, &plain)
	testing.expect_value(t, plain.effects[0].amount, i32(3))
	player.tactical.critical_card = true
	tactical_critical_scale(&room, &action)
	testing.expect_value(t, action.effects[0].amount, i32(5))
	testing.expect_value(t, action.effects[1].amount, i32(6))
	testing.expect_value(t, action.effects[1].duration, i32(3))
	// One more stack; a stack has no duration to lengthen.
	testing.expect_value(t, action.effects[2].amount, i32(3))
	testing.expect_value(t, action.effects[2].duration, i32(0))
	testing.expect_value(t, action.effects[3].amount, i32(9))
	// A coil deployed on the tick is built with twice the health.
	events: Event_Log
	testing.expect(t, deploy_board_device(&room, .Tesla_Coil, {x = 2, y = 2}, 8, 0, &events))
	coil := room.objects[len(room.objects)-1]
	definition, _ := grid_object_definition(.Tesla_Coil)
	testing.expect_value(t, coil.health, definition.max_health*2)
	player.tactical.critical_card = false
}
