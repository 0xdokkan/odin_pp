package game

import "core:testing"
import level "../level"

// IA (docs/piano-ia.md, Fase 0): the card and its seconds.

ia_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player) -> Room {
	spawns := [?]Enemy_Spawn{{position = {x = 9, y = 5}, health = 50, attack = 1}}
	return ground_test_room(t, data, player, {enemies = spawns[:]})
}

// The seconds its IA_Begun says, if it says them.
ia_test_begun :: proc(log: ^Event_Log) -> (seconds: i32, found: bool) {
	for event in log.events[:log.count] {
		if event.kind == .IA_Begun { return event.amount, true }
	}
	return
}

@(test)
test_ia_is_a_rare_lab_card_of_two_energy :: proc(t: ^testing.T) {
	definition, found := card_definition_by_id(.IA)
	testing.expect(t, found && validate_card_definition(&definition))
	testing.expect_value(t, definition.name, "IA")
	testing.expect_value(t, definition.rarity, Card_Rarity.Rare)
	testing.expect_value(t, definition.cost, i32(2))
	testing.expect_value(t, definition.shop_base_price, i32(8))
	testing.expect_value(t, definition.reward_weight, u32(60))
	testing.expect_value(t, definition.dice_count, 0)
	testing.expect_value(t, definition.time_cost, f32(1))
	testing.expect_value(t, definition.targeting.rule, Target_Rule.Self)
	testing.expect_value(t, card_max_upgrade_level(.IA), IA_MAX_UPGRADE_LEVEL)
	testing.expect_value(t, expedition_card_energy_cost(.IA), i32(50))
	// Only in the lab until the plan's last phase (the user's choice: and then too).
	node := Run_Node{kind = .Combat, depth = 2}
	testing.expect(t, card_is_lab_only(.IA) && card_offer_weight(definition, &node) == 0 && !card_in_collection(.IA))
}

// 30 seconds, +3 an upgrade, +5 on the tick.
@(test)
test_ia_seconds_grow_with_upgrades_and_the_tick :: proc(t: ^testing.T) {
	for upgrade in i32(0)..=IA_MAX_UPGRADE_LEVEL {
		data: level.Level
		player: Player
		room := ia_test_room(t, &data, &player)
		play := arsenal_test_play(t, &room, .IA, entity_target(PLAYER_ENTITY), upgrade)
		testing.expect_value(t, play.result, Card_Play_Result.Played)
		seconds, said := ia_test_begun(room.recent_events)
		testing.expect(t, said)
		testing.expect_value(t, seconds, IA_SECONDS+IA_SECONDS_PER_UPGRADE*upgrade)
		testing.expect_value(t, player.tactical.ia_remaining, f32(seconds))
		testing.expect(t, ia_active(&room))
		destroy_room(&room)
		level.destroy(&data)
	}
	data: level.Level
	player: Player
	room := ia_test_room(t, &data, &player)
	defer { destroy_room(&room); level.destroy(&data) }
	action := make_action(.Card, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
	testing.expect(t, add_effect(&action, ia_effect(IA_SECONDS)))
	player.tactical.critical_card = true
	tactical_critical_scale(&room, &action)
	player.tactical.critical_card = false
	testing.expect_value(t, action.effects[0].amount, IA_SECONDS+IA_CRITICAL_SECONDS)
}

// Played again while they run, they start again from the full: never added up.
@(test)
test_ia_played_again_starts_from_the_full :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := ia_test_room(t, &data, &player)
	defer { destroy_room(&room); level.destroy(&data) }
	report: Action_Report
	testing.expect(t, begin_ia(&room, IA_SECONDS, &report))
	tactical_advance_clock(&room, 10)
	testing.expect_value(t, player.tactical.ia_remaining, f32(IA_SECONDS-10))
	testing.expect(t, begin_ia(&room, IA_SECONDS, &report))
	testing.expect_value(t, player.tactical.ia_remaining, f32(IA_SECONDS))
}

// The seconds run with the world's, stand still behind the eyes of a view and
// while the world stands (a cast, the defence keys), and end with the combat.
@(test)
test_ia_seconds_run_with_the_world_only :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := ia_test_room(t, &data, &player)
	defer { destroy_room(&room); level.destroy(&data) }
	report: Action_Report
	testing.expect(t, begin_ia(&room, IA_SECONDS, &report))
	tactical_advance_clock(&room, 0.5)
	testing.expect_value(t, player.tactical.ia_remaining, f32(IA_SECONDS)-0.5)
	// Behind the eyes: still.
	testing.expect(t, tactical_begin_first_person(&room, 3, .AK))
	testing.expect(t, !ia_active(&room))
	tactical_advance_clock(&room, 2)
	testing.expect_value(t, player.tactical.ia_remaining, f32(IA_SECONDS)-0.5)
	// The view over: they run again.
	tactical_advance_clock(&room, 1.5)
	testing.expect(t, !tactical_first_person_active(&room))
	testing.expect(t, ia_active(&room))
	tactical_advance_clock(&room, 1)
	testing.expect(t, player.tactical.ia_remaining < f32(IA_SECONDS)-0.5)
	// The defence keys stop the world's clock, and so the IA's.
	left := player.tactical.ia_remaining
	room.qte = {kind = .Defense, remaining = 1}
	tactical_tick(&room, 0.5, true, false)
	testing.expect_value(t, player.tactical.ia_remaining, left)
	room.qte = {}
	// The combat's end clears them.
	room.phase = .Loot
	tactical_end_combat(&room)
	testing.expect_value(t, player.tactical.ia_remaining, f32(0))
	testing.expect(t, !ia_active(&room))
}

// The seconds are the player's: the room does not grow.
@(test)
test_ia_keeps_the_room_under_nine_kilobytes :: proc(t: ^testing.T) {
	testing.expect(t, size_of(Room) < 9*1024)
	testing.expect_value(t, size_of(Room), 9208)
}
