package integration
import devtools "../devtools"
import run_session "../run"


import "core:testing"
import game "../game"
import level "../level"
import render "../render"

@(test)
test_m7_timed_window_accepts_several_commands_and_hologram_keeps_enemy_time :: proc(t: ^testing.T) {
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	testing.expect(t, devtools.run_tactical_timed_pulse_smoke(nil, renderer))
}

@(test)
test_m7_fresh_walk_on_an_autonomous_world_beat_executes_in_the_same_frame :: proc(t: ^testing.T) {
	data := create_gameplay_command_test_level(t)
	defer level.destroy(&data)
	player := create_gameplay_command_test_player(t)
	testing.expect(t, game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
	enemies := [?]game.Enemy_Spawn{{position = {5, 3}, health = 20, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	buffer: run_session.Buffered_Gameplay_Command
	origin := player.position
	// An ordinary autonomous beat is not a turn boundary. The same frame must
	// remain available to poll and commit the fresh physical press immediately.
	testing.expect(t, !run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
		1, true, {focused = true, directions = {false, true, false, false}}))
	testing.expect(t, !buffer.chord.active)
	testing.expect_value(t, player.position, origin)
	testing.expect_value(t, player.tactical.metrics.decisions, u64(0))
	testing.expect_value(t, player.tactical.remaining, f32(19))
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect(t, render.renderer_world_is_busy(renderer))
	testing.expect(t, run_session.commit_gameplay_command(&room, renderer, &cards,
		{kind = .Move, origin_phase = .Combat, direction = .East}))
	testing.expect_value(t, player.position, game.add_position(origin, {1, 0}))
	testing.expect_value(t, player.tactical.metrics.decisions, u64(1))
	testing.expect(t, abs(player.tactical.remaining-18.2) < 0.001)
}

@(test)
test_m7_timed_deadline_discards_a_pending_chord_before_recovery :: proc(t: ^testing.T) {
	data := create_gameplay_command_test_level(t)
	defer level.destroy(&data)
	player := create_gameplay_command_test_player(t)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.timer_seconds = 1
	testing.expect(t, game.configure_tactical(&player, config))
	enemies := [?]game.Enemy_Spawn{{position = {5, 3}, health = 20, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	buffer: run_session.Buffered_Gameplay_Command
	buffer.chord = {command = {kind = .Move, origin_phase = .Combat, direction = .East, beat = 1}, timer = run_session.BEAT_CHORD_SECONDS, active = true}
	origin := player.position
	testing.expect(t, !run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
		1, true, {focused = true}))
	for _ in 0..<32 {
		if player.tactical.phase == .Recovery { break }
		render.update_renderer_event_timeline(renderer, 100)
		run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 0, true, {focused = true})
	}
	testing.expect_value(t, player.tactical.phase, game.Tactical_Phase.Recovery)
	testing.expect_value(t, player.tactical.cycle, 1)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect_value(t, player.position, origin)
	testing.expect_value(t, player.tactical.metrics.decisions, u64(0))
	testing.expect(t, !buffer.chord.active)
}

@(test)
test_m7_targeting_survives_an_autonomous_beat_but_ends_at_the_deadline :: proc(t: ^testing.T) {
	for expires in ([2]bool{false, true}) {
		data := create_gameplay_command_test_level(t)
		defer level.destroy(&data)
		player := create_gameplay_command_test_player(t)
		config := game.DEFAULT_TACTICAL_CONFIG
		if expires { config.timer_seconds = 1 }
		testing.expect(t, game.configure_tactical(&player, config))
		enemies := [?]game.Enemy_Spawn{{position = {5, 3}, health = 20, attack = 1}}
		room, built := game.create_room(&data, &player, {enemies = enemies[:]})
		testing.expect(t, built)
		defer game.destroy_room(&room)
		renderer := new(render.Renderer)
		defer free(renderer)
		defer render.destroy_renderer_world_playback(renderer)
		controller := run_session.Tactical_Controller{was_focused = true}
		cards := run_session.Card_Interaction_State{selected_card_id = 42, dragged_card_id = 42}
		buffer: run_session.Buffered_Gameplay_Command
		blocked := run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
			1, true, {focused = true})
		testing.expect(t, !blocked)
		if !expires {
			testing.expect_value(t, cards.selected_card_id, u32(42))
			testing.expect_value(t, cards.dragged_card_id, u32(42))
		}
		for _ in 0..<32 {
			if player.tactical.phase == .Recovery { break }
			render.update_renderer_event_timeline(renderer, 100)
			if !run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
				0, true, {focused = true}) { break }
		}
		if expires { testing.expect_value(t, cards, run_session.Card_Interaction_State{}) }
		else {
			testing.expect_value(t, cards.selected_card_id, u32(42))
			testing.expect_value(t, cards.dragged_card_id, u32(42))
			testing.expect_value(t, player.tactical.remaining, f32(19))
		}
	}
}
