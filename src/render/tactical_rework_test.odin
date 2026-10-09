package render

import "core:testing"
import game "../game"
import level "../level"

@(test)
test_reworked_card_costs_replay_in_the_same_catalog_as_the_hand :: proc(t: ^testing.T) {
	rows := [?]string{"#########", "#@......#", "#.......#", "#....>..#", "#########"}
	data, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	defer level.destroy(&data)
	player, made := game.create_player({max_health = 20, attack = 2})
	testing.expect(t, made)
	testing.expect(t, game.initialize_empty_deck(&player.deck, game.DEFAULT_DECK_RULES, 5))
	for _ in 0..<5 { _, _ = game.add_owned_card(&player.deck, .Dash) }
	testing.expect(t, game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
	spawns := [?]game.Enemy_Spawn{{position = {7, 3}, health = 100, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = spawns[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	before := capture_room_presentation(&room)
	play := game.play_card(&room, player.deck.hand[0].id, game.cell_target({3, 1}))
	testing.expect_value(t, play.result, game.Card_Play_Result.Played)
	after := capture_room_presentation(&room)
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, &room.recent_events, &after))
	for _ in 0..<100 {
		if !event_timeline_is_busy(&timeline) { break }
		update_event_timeline(&timeline, 1)
	}
	testing.expect(t, !event_timeline_is_busy(&timeline))
	testing.expect_value(t, timeline.update_failures, 0)
	testing.expect_value(t, timeline.view.deck, player.deck)
	testing.expect_value(t, timeline.view.player.statuses, player.statuses)
	testing.expect_value(t, player.deck.energy, i32(2))
	d, _ := game.card_definition_by_id(.Dash, true)
	first, second := gothic_card_lines({definition_id = .Dash}, d.tactical)
	testing.expect_value(t, string(first), "MUOVI 1-4 / SCUDO 2")
	testing.expect_value(t, string(second), "SCUDO PRIMA / 2 PULSE")
}

@(test)
test_survey_visibility_waits_for_the_presented_status_then_forgets_it :: proc(t: ^testing.T) {
	rows := [?]string{"#########", "#@......#", "#.......#", "#....>..#", "#########"}
	data, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	defer level.destroy(&data)
	player, made := game.create_player({max_health = 20, attack = 2})
	testing.expect(t, made)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.vision_size = 3
	testing.expect(t, game.configure_tactical(&player, config))
	enemies := [?]game.Enemy_Spawn{{position = {7, 3}, health = 8, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	renderer := create(960, 540, &data)
	snapshot: Room_Presentation
	renderer.tactical = {enabled = true, snapshot = &snapshot}
	update_tactical_view(&renderer, &room, {}, false)
	renderer.timeline.view = snapshot
	renderer.timeline.count = 1
	renderer.timeline.cues[0] = {kind = .Status_Applied, duration = 1}
	_, _ = game.apply_status(&room, game.PLAYER_ENTITY, .Survey, 1, 3)
	update_tactical_view(&renderer, &room, {}, false)
	testing.expect(t, !tactical_render_visible(&renderer, {3, 1}))
	testing.expect(t, game.tactical_cell_visible(&room, {3, 1}))
	renderer.timeline.view = capture_room_presentation(&room)
	update_tactical_view(&renderer, &room, {}, false)
	testing.expect(t, tactical_render_visible(&renderer, {3, 1}))
	_, _ = game.remove_status(&room, game.PLAYER_ENTITY, .Survey)
	update_tactical_view(&renderer, &room, {}, false)
	testing.expect(t, tactical_render_visible(&renderer, {3, 1}))
	renderer.timeline.count = 0
	update_tactical_view(&renderer, &room, {}, false)
	testing.expect(t, !tactical_render_visible(&renderer, {3, 1}))
}
