package render

import "core:testing"
import game "../game"
import level "../level"

relic_presentation_player :: proc(t: ^testing.T, relic: game.Relic_Id) -> game.Player {
	player, ok := game.create_player({max_health = 20, attack = 2})
	testing.expect(t, ok)
	testing.expect(t, game.acquire_relic(&player, relic))
	testing.expect(t, game.initialize_empty_deck(&player.deck, {hand_size = 3, max_energy = 3, energy_regen_per_pulse = 1}, 99))
	definitions := [?]game.Card_Id{.Battle_Focus, .Strike, .Guard, .Arc_Bolt, .Dash, .Thorn_Coat, .Shove, .Guard, .Strike, .Dash}
	for id in definitions {
		_, added := game.add_owned_card(&player.deck, id)
		testing.expect(t, added)
	}
	return player
}

relic_presentation_card :: proc(t: ^testing.T, player: ^game.Player, definition: game.Card_Id) -> u32 {
	for card in player.deck.hand[:player.deck.hand_count] {
		if card.definition_id == definition { return card.id }
	}
	for &card in player.deck.draw_pile[:player.deck.draw_count] {
		if card.definition_id == definition {
			player.deck.hand[0], card = card, player.deck.hand[0]
			testing.expect(t, game.validate_deck_state(&player.deck))
			return player.deck.hand[0].id
		}
	}
	testing.expect(t, false, "relic presentation card missing")
	return 0
}

@(test)
test_relic_dash_energy_replays_refund_before_pulse_regeneration :: proc(t: ^testing.T) {
	data := create_encounter_presentation_test_level(t)
	defer level.destroy(&data)
	player := relic_presentation_player(t, .Swift_Soles)
	enemies := [?]game.Enemy_Spawn{{position = {x = 7, y = 3}, health = 40, attack = 1}}
	room, ok := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	id := relic_presentation_card(t, &player, .Dash)
	before := capture_room_presentation(&room)
	play := game.play_card(&room, id, game.cell_target({x = 3, y = 1}))
	testing.expect_value(t, play.result, game.Card_Play_Result.Played)
	advance_presentation_test_clock(t, &room, 1)
	after := capture_room_presentation(&room)
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, room.recent_events, &after))
	energy_seen, pulse_seen := false, false
	for event_timeline_is_busy(&timeline) {
		cue := timeline.cues[timeline.head]
		if cue.kind == .Energy_Gained {
			testing.expect(t, !pulse_seen)
			testing.expect_value(t, timeline.view.deck.energy, i32(2))
		}
		finish_encounter_test_cue(t, &timeline)
		if cue.kind == .Energy_Gained {
			energy_seen = true
			testing.expect_value(t, timeline.view.deck.energy, i32(3))
			testing.expect_value(t, timeline.view.pulse_count, u64(0))
		}
		if cue.kind == .Pulse_Advanced {
			pulse_seen = true
			testing.expect(t, energy_seen)
			testing.expect_value(t, timeline.view.deck.energy, i32(3))
		}
	}
	testing.expect(t, energy_seen && pulse_seen)
	testing.expect_value(t, timeline.view.deck, player.deck)
	testing.expect_value(t, timeline.view.relics, player.relics)
	testing.expect_value(t, timeline.update_failures, 0)
	testing.expect_value(t, timeline.dropped_count, 0)
}

@(test)
test_relic_exhaust_bonus_draw_replays_after_exhaust_and_before_pulse :: proc(t: ^testing.T) {
	data := create_encounter_presentation_test_level(t)
	defer level.destroy(&data)
	player := relic_presentation_player(t, .Ash_Bookmark)
	enemies := [?]game.Enemy_Spawn{{position = {x = 7, y = 3}, health = 40, attack = 1}}
	room, ok := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	id := relic_presentation_card(t, &player, .Battle_Focus)
	before := capture_room_presentation(&room)
	play := game.play_card(&room, id, game.entity_target(game.PLAYER_ENTITY))
	testing.expect_value(t, play.result, game.Card_Play_Result.Played)
	advance_presentation_test_clock(t, &room, 1)
	after := capture_room_presentation(&room)
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, room.recent_events, &after))
	exhaust_seen, bonus_seen, pulse_seen := false, false, false
	for event_timeline_is_busy(&timeline) {
		cue := timeline.cues[timeline.head]
		bonus := cue.kind == .Card_Drawn && cue.event.source == game.SYSTEM_ENTITY
		if bonus {
			testing.expect(t, exhaust_seen && !pulse_seen)
			testing.expect_value(t, timeline.view.deck.exhaust_count, 1)
			testing.expect_value(t, timeline.view.deck.hand_count, 4)
		}
		finish_encounter_test_cue(t, &timeline)
		if cue.kind == .Card_Moved && cue.event.to_card_zone == .Exhaust { exhaust_seen = true }
		if cue.kind == .Pulse_Advanced { pulse_seen = true }
		if bonus {
			bonus_seen = true
			testing.expect_value(t, timeline.view.deck.hand_count, 5)
		}
	}
	testing.expect(t, exhaust_seen && bonus_seen && pulse_seen)
	testing.expect_value(t, player.deck.hand_count, 6)
	testing.expect_value(t, timeline.view.deck, player.deck)
	testing.expect_value(t, timeline.update_failures, 0)
	testing.expect_value(t, timeline.dropped_count, 0)
}

@(test)
test_relic_refocus_bonus_draw_replays_after_pulse_and_normal_refill :: proc(t: ^testing.T) {
	data := create_encounter_presentation_test_level(t)
	defer level.destroy(&data)
	player := relic_presentation_player(t, .Ash_Bookmark)
	enemies := [?]game.Enemy_Spawn{{position = {x = 7, y = 3}, health = 40, attack = 1}}
	room, ok := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	relic_presentation_card(t, &player, .Battle_Focus)
	before := capture_room_presentation(&room)
	refocus := game.refocus_player_hand(&room)
	testing.expect_value(t, refocus.result, game.Refocus_Result.Refocused)
	advance_presentation_test_clock(t, &room, 1)
	after := capture_room_presentation(&room)
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, room.recent_events, &after))
	bonus_seen, pulse_seen := false, false
	for event_timeline_is_busy(&timeline) {
		cue := timeline.cues[timeline.head]
		bonus := cue.kind == .Card_Drawn && cue.event.source == game.SYSTEM_ENTITY
		if bonus {
			testing.expect(t, pulse_seen)
			testing.expect_value(t, timeline.view.deck.hand_count, 3)
		}
		finish_encounter_test_cue(t, &timeline)
		if cue.kind == .Pulse_Advanced { pulse_seen = true }
		if bonus {
			bonus_seen = true
			testing.expect_value(t, timeline.view.deck.hand_count, 4)
		}
	}
	testing.expect(t, bonus_seen && pulse_seen)
	testing.expect_value(t, timeline.view.deck, player.deck)
	testing.expect_value(t, timeline.update_failures, 0)
	testing.expect_value(t, timeline.dropped_count, 0)
}

@(test)
test_relic_mending_terminal_heal_replays_after_enemy_defeat_without_pulse :: proc(t: ^testing.T) {
	data := create_encounter_presentation_test_level(t)
	defer level.destroy(&data)
	player := relic_presentation_player(t, .Mending_Thread)
	player.health = 10
	enemies := [?]game.Enemy_Spawn{{position = {x = 2, y = 1}, health = 2, attack = 1}}
	room, ok := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	before := capture_room_presentation(&room)
	testing.expect_value(t, game.try_move_player(&room, .East), game.Action_Result.Combat_Ended)
	after := capture_room_presentation(&room)
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, room.recent_events, &after))
	defeat_seen, heal_seen := false, false
	for event_timeline_is_busy(&timeline) {
		cue := timeline.cues[timeline.head]
		testing.expect(t, cue.kind != .Pulse_Advanced)
		if cue.kind == .Heal {
			testing.expect(t, defeat_seen)
			testing.expect_value(t, timeline.view.player.health, i32(10))
		}
		finish_encounter_test_cue(t, &timeline)
		if cue.kind == .Defeat { defeat_seen = true }
		if cue.kind == .Heal {
			heal_seen = true
			testing.expect_value(t, timeline.view.player.health, i32(12))
		}
	}
	testing.expect(t, defeat_seen && heal_seen)
	testing.expect_value(t, timeline.view.player.health, player.health)
	testing.expect_value(t, timeline.view.phase, room.phase)
	testing.expect_value(t, timeline.update_failures, 0)
	testing.expect_value(t, timeline.dropped_count, 0)
}
