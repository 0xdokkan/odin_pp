package integration
import run_session "../run"

import "core:testing"
import game "../game"
import level "../level"
import render "../render"

@(test)
test_m8_cast_and_dice_share_exact_clock_without_advancing_world :: proc(t: ^testing.T) {
	for speed in ([2]f32{1, 4}) {
		data := create_gameplay_command_test_level(t)
		defer level.destroy(&data)
		player := create_gameplay_command_test_player(t)
		testing.expect(t, game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
		enemies := [?]game.Enemy_Spawn{{position = {x = 5, y = 3}, health = 100, attack = 1}}
		room, built := game.create_room(&data, &player, {enemies = enemies[:]})
		testing.expect(t, built)
		defer game.destroy_room(&room)
		renderer := new(render.Renderer)
		defer free(renderer)
		defer render.destroy_renderer_world_playback(renderer)
		render.set_renderer_playback_speed(renderer, speed)
		before := render.capture_room_presentation(&room)
		events: game.Event_Log
		game.record_event(&events, {kind = .Card_Played, card_definition = .Shock_Floor})
		game.record_event(&events, {kind = .Dice_Rolled, card_definition = .Shock_Floor})
		game.record_event(&events, {kind = .Card_Moved, card_definition = .Shock_Floor})
		testing.expect(t, render.begin_renderer_event_timeline(renderer, before, &events, &before))
		render.fit_card_cast_timeline(renderer, 3)
		game.tactical_begin_card_cast(&room, 3)
		controller := run_session.Tactical_Controller{was_focused = true}
		cards: run_session.Card_Interaction_State
		buffer: run_session.Buffered_Gameplay_Command
		deadline := room.enemies[0].tactical_cooldown
		cinematic_frames := 0
		for _ in 0..<900 {
			if !render.renderer_blocks_player_input(renderer) && !game.tactical_is_casting(&room) { break }
			clock := player.tactical.remaining
			render.update_renderer_frame_timeline(renderer, 1.0/60.0)
			if renderer.frame_simulation_dt == 0 { cinematic_frames += 1 }
			run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
				1.0/60.0, true, {focused = true})
			if render.presentation_time_policy(&renderer.timeline) == .Cinematic && renderer.frame_simulation_dt == 0 {
				testing.expect_value(t, player.tactical.remaining, clock)
			}
		}
		testing.expect(t, cinematic_frames >= 18, "dice must have fully paused frames")
		testing.expect(t, !render.renderer_blocks_player_input(renderer) && !game.tactical_is_casting(&room))
		testing.expect(t, abs(player.tactical.remaining-17) < 0.001, "cast pays exactly3pulse seconds, including at F4x4")
		testing.expect_value(t, room.pulse_count, u64(0))
		testing.expect_value(t, room.enemies[0].tactical_cooldown, deadline)
		testing.expect_value(t, player.tactical.clock_fraction, f32(0))
		testing.expect(t, game.tactical_allows_action(&room))
	}
}

@(test)
test_m8_cinematic_holds_background_enemy_presentation :: proc(t: ^testing.T) {
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	events: game.Event_Log
	game.record_event(&events, {kind = .Moved, target = game.enemy_entity(1), from_position = {x = 1, y = 1}, to_position = {x = 2, y = 1}})
	before := render.Room_Presentation{valid = true}
	testing.expect(t, render.begin_renderer_world_timeline(renderer, before, &events, &before))
	dice: game.Event_Log
	game.record_event(&dice, {kind = .Dice_Rolled})
	testing.expect(t, render.begin_renderer_event_timeline(renderer, before, &dice, &before))
	for _ in 0..<5 { render.update_renderer_frame_timeline(renderer, 1.0/60.0) }
	testing.expect_value(t, renderer.frame_simulation_dt, f32(0))
	testing.expect(t, render.renderer_world_is_busy(renderer))
	testing.expect_value(t, renderer.world_playback.cues[0].cue.elapsed, f32(0))
}

@(test)
test_m8_standalone_cinematic_defers_pending_world_and_qte_input :: proc(t: ^testing.T) {
	data := create_gameplay_command_test_level(t)
	defer level.destroy(&data)
	player := create_gameplay_command_test_player(t)
	testing.expect(t, game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
	enemies := [?]game.Enemy_Spawn{{position = {x = 5, y = 3}, health = 20, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	game.tactical_spend_action_time(&room, 1)
	testing.expect(t, room.tactical_pulse.pending)
	before := render.capture_room_presentation(&room)
	events: game.Event_Log
	game.record_event(&events, {kind = .Dice_Rolled})
	testing.expect(t, render.begin_renderer_event_timeline(renderer, before, &events, &before))
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	buffer: run_session.Buffered_Gameplay_Command
	render.update_renderer_frame_timeline(renderer, 0.05)
	testing.expect(t, run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 0.05, true, {focused = true}))
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect_value(t, player.tactical.queued_beats, 1)
	testing.expect_value(t, player.tactical.remaining, f32(19))
	room.qte = {kind = .Diagonal, remaining = 1, selected = true, length = 1, keys = {.East,.North}}
	render.update_renderer_frame_timeline(renderer, 0.05)
	testing.expect(t, run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
		0.05, true, {focused = true, directions = {false,true,false,false}}))
	testing.expect_value(t, room.qte.remaining, f32(1))
	testing.expect_value(t, room.qte.progress, 0)
}

@(test)
test_m8_pause_edges_do_not_charge_cast_without_presenting_it :: proc(t: ^testing.T) {
	player := create_gameplay_command_test_player(t)
	testing.expect(t, game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
	room := game.Room{player = &player, phase = .Combat}
	game.tactical_begin_card_cast(&room, 2)
	renderer := new(render.Renderer)
	defer free(renderer)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	buffer: run_session.Buffered_Gameplay_Command
	for _ in 0..<2 {
		testing.expect(t, run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
			30, true, {focused = true, pause = true}))
		testing.expect_value(t, player.tactical.remaining, f32(20))
		testing.expect_value(t, player.tactical.cast_remaining, f32(2))
	}
	testing.expect(t, !controller.paused)
	testing.expect(t, run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
		0.5, true, {focused = true}))
	testing.expect_value(t, player.tactical.cast_remaining, f32(1.5))
	testing.expect_value(t, player.tactical.remaining, f32(19.5))
}
