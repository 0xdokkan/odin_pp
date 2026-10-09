package main

import "core:testing"
import game "game"
import grid "grid"
import level "level"
import render "render"

@(test)
test_m7_fresh_and_repeated_walks_execute_during_real_enemy_movement :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room: game.Room
	if !testing.expect(t, create_m7_independent_world_room(&data, &player, &room)) { return }
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := Tactical_Controller{was_focused = true}
	cards: Card_Interaction_State
	buffer: Buffered_Gameplay_Command
	testing.expect(t, !step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
		2, true, {focused = true}))
	testing.expect(t, render.renderer_world_is_busy(renderer) && !render.renderer_blocks_player_input(renderer))
	testing.expect_value(t, room.pulse_count, u64(2))
	testing.expect_value(t, player.tactical.phase, game.Tactical_Phase.Decision)
	// Wait only until the actual enemy cue has begun interpolating, never seek
	// it to completion. Both actors must retain distinct simultaneous paths.
	enemy_start := render.presentation_position({2, 4})
	enemy_end := render.presentation_position(room.enemies[0].position)
	snapshot := render.renderer_presentation_snapshot(renderer, &room)
	for _ in 0..<60 {
		if snapshot.enemies[0].position != enemy_start { break }
		render.update_renderer_frame_timeline(renderer, 1.0/60.0)
		snapshot = render.renderer_presentation_snapshot(renderer, &room)
	}
	testing.expect(t, snapshot.enemies[0].position != enemy_start && snapshot.enemies[0].position != enemy_end)
	enemy_before := snapshot.enemies[0].position
	testing.expect(t, m7_independent_fresh_move(&controller, &room, renderer, &cards, &buffer, .East),
		"a fresh key during an enemy move must commit immediately, not enter the walk buffer")
	testing.expect(t, !buffer.occupied)
	testing.expect_value(t, player.position, grid.Position{8, 4})
	snapshot = render.renderer_presentation_snapshot(renderer, &room)
	testing.expect_value(t, snapshot.enemies[0].position, enemy_before)
	render.update_renderer_frame_timeline(renderer, 1.0/60.0)
	snapshot = render.renderer_presentation_snapshot(renderer, &room)
	testing.expect(t, snapshot.enemies[0].position != enemy_before && snapshot.enemies[0].position != enemy_end)
	testing.expect(t, snapshot.player.position != render.presentation_position(data.player_spawn) &&
		snapshot.player.position != render.presentation_position(player.position),
		"player and enemy must both interpolate in the same presented frame")
	for _ in 0..<60 {
		if !render.renderer_blocks_player_input(renderer) { break }
		render.update_renderer_frame_timeline(renderer, 1.0/60.0)
	}
	testing.expect(t, render.renderer_world_is_busy(renderer))
	testing.expect(t, m7_independent_fresh_move(&controller, &room, renderer, &cards, &buffer, .South),
		"a second fresh key must not wait for the enemy's remaining animation")
	testing.expect_value(t, player.position, grid.Position{8, 5})
	testing.expect(t, !buffer.occupied)
	testing.expect_value(t, renderer.timeline.update_failures, 0)
}

@(test)
test_m7_card_commit_and_idle_clock_remain_live_during_enemy_presentation :: proc(t: ^testing.T) {
	for playback_speed in ([2]f32{1, 4}) {
		data: level.Level
		player: game.Player
		room: game.Room
		if !testing.expect(t, create_m7_independent_world_room(&data, &player, &room)) { return }
		defer level.destroy(&data)
		defer game.destroy_room(&room)
		renderer := new(render.Renderer)
		defer free(renderer)
		defer render.destroy_renderer_world_playback(renderer)
		testing.expect(t, render.set_renderer_playback_speed(renderer, playback_speed))
		controller := Tactical_Controller{was_focused = true}
		cards: Card_Interaction_State
		buffer: Buffered_Gameplay_Command
		testing.expect(t, !step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
			2, true, {focused = true}))
		testing.expect(t, render.renderer_world_is_busy(renderer))
		for _ in 0..<4 {
			// dt belongs to the simulation, not to the enemy cue or its playback
			// speed. Each controller frame still receives the full elapsed time.
			render.update_renderer_frame_timeline(renderer, 0.015625)
			testing.expect(t, !step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
				0.015625, true, {focused = true}))
		}
		testing.expect_value(t, player.tactical.remaining, f32(17.9375))
		testing.expect_value(t, player.tactical.metrics.decision_seconds, f64(2.0625))
		testing.expect(t, render.renderer_world_is_busy(renderer))
		guard: u32
		for card in player.deck.hand[:player.deck.hand_count] {
			if card.definition_id == .Guard { guard = card.id }
		}
		testing.expect(t, guard != 0 && commit_gameplay_command(&room, renderer, &cards,
			{kind = .Play_Card, origin_phase = .Combat, card_id = guard,
			 target = game.entity_target(game.PLAYER_ENTITY)}),
			"a legal card must commit while the enemy continues animating")
		_, shielded := game.status_for_entity(&room, game.PLAYER_ENTITY, .Shield)
		testing.expect(t, shielded && render.renderer_world_is_busy(renderer))
		testing.expect_value(t, player.tactical.remaining, f32(17.9375)-game.tactical_card_time_cost(.Guard))
		// Even the player's foreground card animation cannot pause enemy time.
		// It reserves only the next player command, while its paid beat and the
		// next quarter-second of real time continue in the world.
		testing.expect(t, render.renderer_blocks_player_input(renderer))
		testing.expect(t, step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
			0.25, true, {focused = true}))
		testing.expect_value(t, player.tactical.remaining, f32(17.6875)-game.tactical_card_time_cost(.Guard))
		testing.expect_value(t, player.tactical.metrics.decision_seconds, f64(2.3125))
		testing.expect_value(t, room.pulse_count, u64(3))
		testing.expect_value(t, renderer.timeline.update_failures, 0)
	}
}

@(test)
test_m7_enemy_world_presentation_keeps_pause_and_qte_boundaries :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room: game.Room
	if !testing.expect(t, create_m7_independent_world_room(&data, &player, &room)) { return }
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := Tactical_Controller{was_focused = true}
	cards: Card_Interaction_State
	buffer: Buffered_Gameplay_Command
	step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 2, true, {focused = true})
	testing.expect(t, render.renderer_world_is_busy(renderer))
	before := player.tactical.remaining
	testing.expect(t, step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
		0.25, true, {focused = true, pause = true, directions = {false, true, false, false}}))
	testing.expect_value(t, player.tactical.remaining, before)
	testing.expect(t, !buffer.occupied)
	testing.expect_value(t, player.position, data.player_spawn)
	controller.paused = false
	room.qte = {kind = .Defense, remaining = 3}
	testing.expect(t, step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
		0.25, true, {focused = true, directions = {false, true, false, false}}))
	testing.expect_value(t, player.tactical.remaining, before)
	testing.expect_value(t, room.qte.remaining, f32(2.75))
	testing.expect(t, !buffer.occupied)
	testing.expect_value(t, player.position, data.player_spawn)
}

@(test)
test_m7_independent_world_window_fixture_headless :: proc(t: ^testing.T) {
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	testing.expect(t, run_m7_independent_world_smoke(nil, renderer))
}

@(test)
test_m7_world_capacity_preflight_preserves_pending_gameplay_and_resumes_after_playback :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room: game.Room
	if !testing.expect(t, create_m7_independent_world_room(&data, &player, &room)) { return }
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := Tactical_Controller{was_focused = true}
	cards: Card_Interaction_State
	buffer: Buffered_Gameplay_Command
	step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 1, true, {focused = true})
	if !testing.expect(t, render.renderer_world_is_busy(renderer)) { return }
	// Reuse a valid cue produced by a real completed beat to put the bank at
	// its reservation boundary. No invalid cue/event is used to trip the guard.
	world := renderer.world_playback
	seed := world.cues[0]
	world.count = render.MAX_WORLD_PRESENTATION_CUES-game.MAX_GAME_EVENTS+1
	for &entry in world.cues[:world.count] { entry = seed }
	testing.expect_value(t, render.renderer_world_available_cues(renderer), game.MAX_GAME_EVENTS-1)
	game.tactical_tick(&room, 1, true, false)
	before_player := player
	before_pulse := room.tactical_pulse
	before_count := room.pulse_count
	before_enemy := room.enemies[0]
	before_events := room.recent_events
	testing.expect(t, !commit_gameplay_command(&room, renderer, &cards,
		{kind = .Continue_Pulse, origin_phase = .Combat}))
	testing.expect_value(t, player, before_player)
	testing.expect_value(t, room.tactical_pulse, before_pulse)
	testing.expect_value(t, room.pulse_count, before_count)
	testing.expect_value(t, room.enemies[0], before_enemy)
	testing.expect_value(t, room.recent_events, before_events)
	// Real playback returns the occupied slots. The pending authoritative beat
	// then resumes exactly once, without a forced reset or discarded time debt.
	render.update_renderer_frame_timeline(renderer, seed.cue.duration+0.01)
	testing.expect(t, !render.renderer_world_is_busy(renderer))
	testing.expect(t, !step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
		0, true, {focused = true}))
	testing.expect_value(t, room.pulse_count, before_count+1)
	testing.expect_value(t, player.tactical.queued_beats, 0)
	testing.expect_value(t, player.tactical.remaining, before_player.tactical.remaining)
	testing.expect(t, !room.tactical_pulse.pending && render.renderer_world_is_busy(renderer))
	testing.expect_value(t, renderer.world_playback.rejected_batches, 0)
}

@(test)
test_m7_new_defense_qte_does_not_reuse_the_same_frame_input_or_skip_paid_deadline_beats :: proc(t: ^testing.T) {
	data := create_gameplay_command_test_level(t)
	defer level.destroy(&data)
	player := create_gameplay_command_test_player(t)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.timer_seconds = 3
	testing.expect(t, game.configure_tactical(&player, config))
	configure_single_card_test_deck(t, &player, .Guard)
	spawns := [?]game.Enemy_Spawn{{position = {2, 1}, health = 20, attack = 1}}
	room, created := game.create_room(&data, &player, {enemies = spawns[:]})
	if !testing.expect(t, created) { return }
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := Tactical_Controller{was_focused = true}
	cards: Card_Interaction_State
	buffer: Buffered_Gameplay_Command
	testing.expect(t, commit_gameplay_command(&room, renderer, &cards,
		{kind = .Play_Card, origin_phase = .Combat, card_id = player.deck.hand[0].id,
		 target = game.entity_target(game.PLAYER_ENTITY)}))
	testing.expect(t, render.renderer_blocks_player_input(renderer))
	input := Tactical_Controller_Input{focused = true, directions = {true, false, false, false}}
	input.defenses[int(game.Defense_Mode.Parry)] = true
	testing.expect(t, step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 2, true, input))
	testing.expect_value(t, room.qte.kind, game.QTE_Kind.Defense)
	testing.expect_value(t, room.qte.remaining, config.qte_seconds)
	testing.expect(t, !room.qte.selected && room.qte.progress == 0 && !buffer.occupied)
	testing.expect_value(t, player.position, data.player_spawn)
	testing.expect_value(t, player.tactical.remaining, f32(0))
	testing.expect_value(t, player.tactical.queued_beats, 1)
	testing.expect_value(t, player.tactical.cycle, 0)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect(t, commit_gameplay_command(&room, renderer, &cards,
		{kind = .QTE_Fail, origin_phase = .Combat}))
	testing.expect(t, step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
		0, true, {focused = true}))
	testing.expect_value(t, room.qte.kind, game.QTE_Kind.None)
	testing.expect_value(t, room.pulse_count, u64(3))
	testing.expect_value(t, player.tactical.queued_beats, 0)
	testing.expect_value(t, player.tactical.phase, game.Tactical_Phase.Recovery)
	testing.expect_value(t, player.tactical.cycle, 1)
	testing.expect_value(t, player.position, data.player_spawn)
}
