package main

import "core:testing"
import game "game"
import render "render"

@(test)
test_terminal_room_transition_waits_for_the_presentation_timeline :: proc(t: ^testing.T) {
	player := game.Player{
		stats = {max_health = 10},
		health = 10,
	}
	room := game.Room{
		player = &player,
		phase = .Complete,
	}
	run := game.Run_State{phase = .In_Room}
	renderer: render.Renderer

	testing.expect(t, room_transition_is_ready(&run, &room, &renderer))
	events: game.Event_Log
	game.record_event(&events, {
		kind = .Moved,
		target = game.PLAYER_ENTITY,
		from_position = {x = 1, y = 1},
		to_position = {x = 2, y = 1},
	})
	testing.expect(t, render.begin_renderer_event_timeline(
		&renderer,
		render.capture_room_presentation(&room),
		&events,
	))
	testing.expect(t, !room_transition_is_ready(&run, &room, &renderer))

	render.update_renderer_event_timeline(&renderer, render.PRESENTATION_PLAYER_MOVE_DURATION)
	testing.expect(t, room_transition_is_ready(&run, &room, &renderer))
	run.phase = .Reward
	testing.expect(t, !room_transition_is_ready(&run, &room, &renderer))
}

@(test)
test_route_map_toggle_rejects_terminal_rooms_and_busy_timelines :: proc(t: ^testing.T) {
	player := game.Player{stats = {max_health = 10}, health = 10}
	room := game.Room{player = &player, phase = .Combat}
	run := game.Run_State{phase = .In_Room}
	renderer: render.Renderer

	testing.expect(t, route_map_toggle_is_allowed(&run, &room, &renderer))
	events: game.Event_Log
	game.record_event(&events, {
		kind = .Moved,
		target = game.PLAYER_ENTITY,
		from_position = {x = 1, y = 1},
		to_position = {x = 2, y = 1},
	})
	render.begin_renderer_event_timeline(
		&renderer,
		render.capture_room_presentation(&room),
		&events,
	)
	testing.expect(t, !route_map_toggle_is_allowed(&run, &room, &renderer))
	render.clear_event_animations(&renderer)

	room.phase = .Complete
	testing.expect(t, !route_map_toggle_is_allowed(&run, &room, &renderer))
	room.phase = .Defeat
	testing.expect(t, !route_map_toggle_is_allowed(&run, &room, &renderer))
}
