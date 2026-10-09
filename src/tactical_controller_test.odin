package main

import "core:testing"
import game "game"
import grid "grid"
import level "level"
import render "render"

@(test)
test_m7_movement_pressed_during_loot_animation_is_delivered_once :: proc(t: ^testing.T) {
	data := create_gameplay_command_test_level(t)
	defer level.destroy(&data)
	player := create_gameplay_command_test_player(t)
	testing.expect(t, game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
	room, ok := game.create_room(&data, &player, {})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := Tactical_Controller{was_focused = true}
	cards: Card_Interaction_State
	buffer: Buffered_Gameplay_Command
	testing.expect(t, commit_gameplay_command(&room, renderer, &cards,
		{kind = .Move, origin_phase = .Loot, direction = .East}))
	testing.expect(t, render.renderer_timeline_is_busy(renderer))
	// A physical press exists for one frame only. Holding S after this frame
	// does not produce another IsKeyPressed, so losing it makes movement stall.
	testing.expect(t, step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
		0, true, {focused = true, directions = {false, false, true, false}}))
	testing.expect(t, buffer.occupied, "M7 must preserve the press while presentation owns input")
	render.update_renderer_event_timeline(renderer, 100)
	testing.expect(t, !step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
		0, true, {focused = true}))
	command, buffered := take_gameplay_command(&buffer)
	testing.expect(t, buffered)
	if buffered {
		testing.expect(t, commit_gameplay_command(&room, renderer, &cards, command))
		testing.expect_value(t, player.position, grid.Position{2, 2})
	}
	_, duplicated := take_gameplay_command(&buffer)
	testing.expect(t, !duplicated)
}

@(test)
test_m7_world_continuations_release_walk_without_waiting_for_enemy_animation :: proc(t: ^testing.T) {
	for during_timeline in ([2]bool{true, false}) { expect_m7_buffered_walk_through_pulse(t, during_timeline) }
}

expect_m7_buffered_walk_through_pulse :: proc(t: ^testing.T, during_timeline: bool) {
	data := create_gameplay_command_test_level(t)
	defer level.destroy(&data)
	player := create_gameplay_command_test_player(t)
	testing.expect(t, game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
	enemies := [?]game.Enemy_Spawn{{position = {5, 3}, health = 8, attack = 1}}
	room, ok := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	// The charged second actually moves this enemy, so a completed beat must
	// release input while its visual response is still being presented.
	room.enemies[0].tactical_cooldown = 1
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := Tactical_Controller{was_focused = true}
	cards: Card_Interaction_State
	buffer: Buffered_Gameplay_Command
	testing.expect(t, commit_gameplay_command(&room, renderer, &cards,
		{kind = .Move, origin_phase = .Combat, direction = .East}))
	if !during_timeline { render.update_renderer_event_timeline(renderer, 100) }
	blocked := step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
		0, true, {focused = true, directions = {false, false, true, false}})
	// Only the player's own unfinished step keeps its usual single walk
	// buffer. Ordinary world work completes in this same controller frame.
	testing.expect_value(t, blocked, during_timeline)
	testing.expect_value(t, buffer.occupied, during_timeline)
	testing.expect_value(t, room.qte.kind, game.QTE_Kind.None)
	testing.expect_value(t, player.tactical.phase, game.Tactical_Phase.Decision)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect(t, !room.tactical_pulse.pending)
	command := Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .South}
	if during_timeline {
		render.update_renderer_event_timeline(renderer, 100)
		testing.expect(t, !step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
			0, true, {focused = true}))
		buffered_command, buffered := take_gameplay_command(&buffer)
		testing.expect(t, buffered, "normal world continuations must preserve the player's buffered walk")
		if buffered { command = buffered_command }
	}
	testing.expect(t, commit_gameplay_command(&room, renderer, &cards, command))
	testing.expect_value(t, player.position, grid.Position{2, 2})
	_, duplicated := take_gameplay_command(&buffer)
	testing.expect(t, !duplicated)
}

@(test)
test_m7_input_buffer_is_discarded_at_rules_and_interaction_boundaries :: proc(t: ^testing.T) {
	Boundary :: enum {QTE, Map_Open, Map_Close, Pause, Focus, Unavailable, Phase_Change}
	for boundary in Boundary {
		player: game.Player
		testing.expect(t, game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
		room := game.Room{player = &player, phase = .Combat}
		renderer := new(render.Renderer)
		defer free(renderer)
		defer render.destroy_renderer_world_playback(renderer)
		renderer.canvas_width, renderer.canvas_height = 960, 540
		// The boundary must win even when presentation still owns the frame.
		renderer.timeline.count = 1
		renderer.timeline.cues[0].duration = 1
		controller := Tactical_Controller{was_focused = true}
		cards: Card_Interaction_State
		buffer: Buffered_Gameplay_Command
		testing.expect(t, offer_gameplay_command(&buffer, {kind = .Move, origin_phase = .Combat, direction = .East}))
		input := Tactical_Controller_Input{focused = true, directions = {false, false, true, false}}
		available := true
		switch boundary {
		case .QTE: room.qte.kind = .Defense
		case .Map_Open: input.map_input.toggle = true
		case .Map_Close: controller.hologram = true; input.map_input.close = true
		case .Pause: input.pause = true
		case .Focus: input.focused = false
		case .Unavailable: available = false
		case .Phase_Change: room.phase = .Loot; input.directions = {}
		}
		testing.expect(t, step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 0, available, input))
		testing.expect(t, !buffer.occupied, "an old walk must not replay after a rules/UI boundary")
	}
}

@(test)
test_m7_focus_resume_does_not_charge_absence_or_replay_queued_input :: proc(t: ^testing.T) {
	player: game.Player
	testing.expect(t, game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
	room := game.Room{player = &player, phase = .Combat}
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := Tactical_Controller{was_focused = true}
	cards: Card_Interaction_State
	buffer: Buffered_Gameplay_Command
	testing.expect(t, offer_gameplay_command(&buffer, {kind = .Move, origin_phase = .Combat, direction = .East}))
	testing.expect(t, step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 30, true, {}))
	testing.expect(t, !controller.was_focused && !buffer.occupied)
	testing.expect(t, step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 30, true, {focused = true}))
	testing.expect_value(t, player.tactical.remaining, f32(20))
	testing.expect(t, !step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 0.25, true, {focused = true}))
	testing.expect_value(t, player.tactical.remaining, f32(19.75))
}

@(test)
test_map_button_drag_close_and_clock_share_the_native_input_path :: proc(t: ^testing.T) {
	player: game.Player
	testing.expect(t, game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
	room := game.Room{player = &player, phase = .Combat}
	renderer := render.Renderer{canvas_width = 960, canvas_height = 540}
	controller: Tactical_Controller
	cards := Card_Interaction_State{selected_card_id = 42, dragged_card_id = 42}
	buffer: Buffered_Gameplay_Command
	button := render.tactical_map_button_bounds(&renderer)
	click := Tactical_Map_Input{mouse = {button.x+20, button.y+15}, inside = true, pressed = true, down = true}
	testing.expect(t, update_tactical_map_controls(&controller, &room, &renderer, &cards, &buffer, click))
	testing.expect(t, controller.hologram)
	testing.expect_value(t, cards, Card_Interaction_State{})
	testing.expect_value(t, player.tactical.metrics.hologram_opens, u64(1))
	testing.expect(t, !renderer.tactical.hologram_orbit.dragging)
	before := renderer.tactical.hologram_orbit
	// The opening button cannot start a drag; movement over the table must begin
	// with its own press. All inputs are routed away from cards while open.
	_ = update_tactical_map_controls(&controller, &room, &renderer, &cards, &buffer,
		{mouse = {500, 250}, inside = true, down = true})
	testing.expect_value(t, renderer.tactical.hologram_orbit.yaw, before.yaw)
	_ = update_tactical_map_controls(&controller, &room, &renderer, &cards, &buffer,
		{mouse = {500, 250}, inside = true, pressed = true, down = true})
	_ = update_tactical_map_controls(&controller, &room, &renderer, &cards, &buffer,
		{mouse = {570, 280}, inside = true, down = true, wheel = 1})
	testing.expect(t, renderer.tactical.hologram_orbit.yaw != before.yaw)
	testing.expect(t, renderer.tactical.hologram_orbit.pitch != before.pitch)
	testing.expect(t, renderer.tactical.hologram_orbit.distance < before.distance)
	testing.expect(t, !game.tactical_tick(&room, 2, true, controller.hologram))
	testing.expect_value(t, player.tactical.remaining, f32(18))
	testing.expect_value(t, player.tactical.metrics.hologram_seconds, f64(2))
	testing.expect_value(t, room.pulse_count, u64(0))
	_ = update_tactical_map_controls(&controller, &room, &renderer, &cards, &buffer, {reset = true})
	testing.expect_value(t, renderer.tactical.hologram_orbit, before)
	testing.expect(t, update_tactical_map_controls(&controller, &room, &renderer, &cards, &buffer, {close = true}))
	testing.expect(t, !controller.hologram)
	testing.expect_value(t, player.tactical.remaining, f32(18))
	// Closing on the button consumes the click too (no click-through action).
	testing.expect(t, update_tactical_map_controls(&controller, &room, &renderer, &cards, &buffer, {toggle = true}))
	testing.expect(t, update_tactical_map_controls(&controller, &room, &renderer, &cards, &buffer, click))
	testing.expect(t, !controller.hologram)
	room.qte.kind = .Diagonal
	testing.expect(t, !update_tactical_map_controls(&controller, &room, &renderer, &cards, &buffer, click))
	testing.expect(t, !controller.hologram)
}

@(test)
test_orbit_ignores_press_and_wheel_outside_and_releases_drag :: proc(t: ^testing.T) {
	orbit: render.Tactical_Orbit
	render.reset_tactical_orbit(&orbit)
	initial := orbit
	render.update_tactical_orbit_pointer(&orbit, {10, 10}, false, true, true, 3)
	testing.expect_value(t, orbit, initial)
	render.update_tactical_orbit_pointer(&orbit, {20, 20}, true, false, true, 0)
	testing.expect_value(t, orbit, initial)
	render.update_tactical_orbit_pointer(&orbit, {20, 20}, true, true, true, 0)
	render.update_tactical_orbit_pointer(&orbit, {50, 40}, false, false, true, 0)
	testing.expect(t, orbit.dragging && orbit.yaw != initial.yaw)
	render.update_tactical_orbit_pointer(&orbit, {70, 40}, false, false, false, 0)
	testing.expect(t, !orbit.dragging)
	ended := orbit
	render.update_tactical_orbit_pointer(&orbit, {90, 40}, true, false, false, 0)
	testing.expect_value(t, orbit, ended)
}
