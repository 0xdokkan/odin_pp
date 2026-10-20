package render

import "core:testing"
import game "../game"

@(test)
test_renderer_timeline_wrappers_advance_and_clear_playback :: proc(t: ^testing.T) {
	player := game.Player{stats = {max_health = 10}, health = 10}
	room := make_presentation_timeline_test_room(&player, nil, nil)
	defer game.destroy_room(&room)
	events: game.Event_Log
	game.record_event(&events, {
		kind = .Moved,
		target = game.PLAYER_ENTITY,
		from_position = {1, 1},
		to_position = {2, 1},
	})
	renderer: Renderer

	testing.expect(t, begin_renderer_event_timeline(
		&renderer,
		capture_room_presentation(&room),
		&events,
	))
	testing.expect(t, renderer_timeline_is_busy(&renderer))

	testing.expect(t, !update_renderer_event_timeline(
		&renderer,
		PRESENTATION_PLAYER_MOVE_DURATION*0.5,
	))
	testing.expect(t, renderer_timeline_is_busy(&renderer))
	testing.expect(t, update_renderer_event_timeline(
		&renderer,
		PRESENTATION_PLAYER_MOVE_DURATION*0.5,
	))
	testing.expect(t, !renderer_timeline_is_busy(&renderer))

	begin_renderer_event_timeline(&renderer, capture_room_presentation(&room), &events)
	clear_event_animations(&renderer)
	testing.expect(t, !renderer_timeline_is_busy(&renderer))
	testing.expect_value(t, renderer.timeline, Presentation_Timeline{})
}

@(test)
test_renderer_status_view_uses_snapshot_until_timeline_becomes_idle :: proc(t: ^testing.T) {
	player := game.Player{
		stats = {max_health = 12},
		health = 10,
		gold = 4,
	}
	player.statuses.items[0] = {.Shield, 3, 2}
	player.statuses.count = 1
	enemies := [?]game.Enemy{
		{id = 1, position = {4, 1}, max_health = 5, health = 5},
		{id = 2, position = {5, 1}, max_health = 5, health = 5},
	}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	room.pulse_count = 7
	before := capture_room_presentation(&room)

	player.health = 3
	player.gold = 20
	player.statuses = {}
	player.statuses.items[0] = {.Poison, 2, 1}
	player.statuses.count = 1
	room.phase = .Loot
	room.pulse_count = 8
	unordered_remove(&room.enemies, 0)
	events: game.Event_Log
	game.record_event(&events, {
		kind = .Card_Played,
		target = game.PLAYER_ENTITY,
		card_id = 5,
		card_definition = .Strike,
	})
	renderer: Renderer
	testing.expect(t, begin_renderer_event_timeline(&renderer, before, &events))

	status := renderer_status_view(&renderer, &room)
	testing.expect_value(t, status.phase, game.Room_Phase.Combat)
	testing.expect_value(t, status.health, i32(10))
	testing.expect_value(t, status.max_health, i32(12))
	testing.expect_value(t, status.enemy_count, 2)
	testing.expect_value(t, status.gold, i32(4))
	testing.expect_value(t, status.pulse_count, u64(7))
	_, snapshot_has_shield := game.status_index(&status.statuses, .Shield)
	_, snapshot_has_poison := game.status_index(&status.statuses, .Poison)
	testing.expect(t, snapshot_has_shield)
	testing.expect(t, !snapshot_has_poison)

	testing.expect(t, update_renderer_event_timeline(&renderer, PRESENTATION_CARD_PLAY_DURATION))
	status = renderer_status_view(&renderer, &room)
	testing.expect_value(t, status.phase, game.Room_Phase.Loot)
	testing.expect_value(t, status.health, i32(3))
	testing.expect_value(t, status.enemy_count, 1)
	testing.expect_value(t, status.gold, i32(20))
	testing.expect_value(t, status.pulse_count, u64(8))
	_, final_has_shield := game.status_index(&status.statuses, .Shield)
	_, final_has_poison := game.status_index(&status.statuses, .Poison)
	testing.expect(t, !final_has_shield)
	testing.expect(t, final_has_poison)
}

@(test)
test_renderer_timeline_wrapper_handles_nil_and_empty_inputs_without_stale_state :: proc(t: ^testing.T) {
	renderer: Renderer
	testing.expect(t, !renderer_timeline_is_busy(nil))
	testing.expect(t, !begin_renderer_event_timeline(nil, {}, nil))
	testing.expect(t, !update_renderer_event_timeline(nil, 1))
	testing.expect(t, !begin_renderer_event_timeline(&renderer, {}, nil))
	testing.expect(t, !renderer_timeline_is_busy(&renderer))
	testing.expect_value(t, renderer.timeline, Presentation_Timeline{})
}
