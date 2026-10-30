package integration
import devtools "../devtools"
import run_session "../run"


import "core:testing"
import game "../game"
import grid "../engine/grid"
import level "../level"
import render "../render"

@(test)
test_m7_fresh_and_repeated_walks_execute_during_real_enemy_movement :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room: game.Room
	if !testing.expect(t, devtools.create_tactical_independent_world_room(&data, &player, &room)) { return }
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	buffer: run_session.Buffered_Gameplay_Command
	testing.expect(t, !run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
		3, true, {focused = true}))
	testing.expect(t, render.renderer_world_is_busy(renderer) && !render.renderer_blocks_player_input(renderer))
	testing.expect_value(t, room.pulse_count, u64(3))
	testing.expect_value(t, player.tactical.phase, game.Tactical_Phase.Decision)
	// Wait only until the actual enemy cue has begun interpolating, never seek
	// it to completion. Both actors must retain distinct simultaneous paths.
	enemy_start := render.presentation_position({x = 2, y = 4})
	enemy_end := render.presentation_position(room.enemies[0].position)
	snapshot := render.renderer_presentation_snapshot(renderer, &room)
	for _ in 0..<60 {
		if snapshot.enemies[0].position != enemy_start { break }
		render.update_renderer_frame_timeline(renderer, 1.0/60.0)
		snapshot = render.renderer_presentation_snapshot(renderer, &room)
	}
	testing.expect(t, snapshot.enemies[0].position != enemy_start && snapshot.enemies[0].position != enemy_end)
	enemy_before := snapshot.enemies[0].position
	testing.expect(t, devtools.tactical_independent_fresh_move(&controller, &room, renderer, &cards, &buffer, .East),
		"a fresh key during an enemy move must commit immediately, not wait for the enemy's animation")
	testing.expect(t, !buffer.chord.active)
	testing.expect_value(t, player.position, grid.Position{x = 8, y = 4})
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
	testing.expect(t, devtools.tactical_independent_fresh_move(&controller, &room, renderer, &cards, &buffer, .South),
		"a second fresh key must not wait for the enemy's remaining animation")
	testing.expect_value(t, player.position, grid.Position{x = 8, y = 5})
	testing.expect(t, !buffer.chord.active)
	testing.expect_value(t, renderer.timeline.update_failures, 0)
}

@(test)
test_m7_card_commit_and_idle_clock_remain_live_during_enemy_presentation :: proc(t: ^testing.T) {
	for playback_speed in ([2]f32{1, 4}) {
		data: level.Level
		player: game.Player
		room: game.Room
		if !testing.expect(t, devtools.create_tactical_independent_world_room(&data, &player, &room)) { return }
		defer level.destroy(&data)
		defer game.destroy_room(&room)
		renderer := new(render.Renderer)
		defer free(renderer)
		defer render.destroy_renderer_world_playback(renderer)
		testing.expect(t, render.set_renderer_playback_speed(renderer, playback_speed))
		controller := run_session.Tactical_Controller{was_focused = true}
		cards: run_session.Card_Interaction_State
		buffer: run_session.Buffered_Gameplay_Command
		testing.expect(t, !run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
			3, true, {focused = true}))
		testing.expect(t, render.renderer_world_is_busy(renderer))
		for _ in 0..<4 {
			// dt belongs to the simulation, not to the enemy cue or its playback
			// speed. Each controller frame still receives the full elapsed time.
			render.update_renderer_frame_timeline(renderer, 0.015625)
			testing.expect(t, !run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
				0.015625, true, {focused = true}))
		}
		testing.expect_value(t, player.tactical.remaining, f32(16.9375))
		testing.expect_value(t, player.tactical.metrics.decision_seconds, f64(3.0625))
		testing.expect(t, render.renderer_world_is_busy(renderer))
		guard: u32
		for card in player.deck.hand[:player.deck.hand_count] {
			if card.definition_id == .Guard { guard = card.id }
		}
		testing.expect(t, guard != 0 && run_session.commit_gameplay_command(&room, renderer, &cards,
			{kind = .Play_Card, origin_phase = .Combat, card_id = guard,
			 target = game.entity_target(game.PLAYER_ENTITY)}),
			"a legal card must commit while the enemy continues animating")
		_, shielded := game.status_for_entity(&room, game.PLAYER_ENTITY, .Shield)
		testing.expect(t, shielded && render.renderer_world_is_busy(renderer))
		testing.expect_value(t, player.tactical.remaining, f32(16.9375))
		// M8 casts reserve the player and freeze the enemy rhythm, while
		// their cost is paid through the real pulse countdown exactly once.
		testing.expect(t, render.renderer_blocks_player_input(renderer))
		testing.expect(t, run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
			0.25, true, {focused = true}))
		testing.expect_value(t, player.tactical.remaining, f32(16.6875))
		testing.expect_value(t, player.tactical.metrics.decision_seconds, f64(3.3125))
		testing.expect_value(t, room.pulse_count, u64(3))
		testing.expect_value(t, player.tactical.cast_remaining, f32(0.75))
		testing.expect_value(t, renderer.timeline.update_failures, 0)
	}
}

@(test)
test_m7_enemy_world_presentation_keeps_pause_and_qte_boundaries :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room: game.Room
	if !testing.expect(t, devtools.create_tactical_independent_world_room(&data, &player, &room)) { return }
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	buffer: run_session.Buffered_Gameplay_Command
	run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 3, true, {focused = true})
	testing.expect(t, render.renderer_world_is_busy(renderer))
	before := player.tactical.remaining
	testing.expect(t, run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
		0.25, true, {focused = true, pause = true, directions = {false, true, false, false}}))
	testing.expect_value(t, player.tactical.remaining, before)
	testing.expect(t, !buffer.chord.active)
	testing.expect_value(t, player.position, data.player_spawn)
	controller.paused = false
	room.qte = {kind = .Defense, remaining = 3}
	testing.expect(t, run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
		0.25, true, {focused = true, directions = {false, true, false, false}}))
	testing.expect_value(t, player.tactical.remaining, before)
	testing.expect_value(t, room.qte.remaining, f32(2.75))
	testing.expect(t, !buffer.chord.active)
	testing.expect_value(t, player.position, data.player_spawn)
}

@(test)
test_m7_independent_world_window_fixture_headless :: proc(t: ^testing.T) {
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	testing.expect(t, devtools.run_tactical_independent_world_smoke(nil, renderer))
}

@(test)
test_m7_world_capacity_preflight_preserves_pending_gameplay_and_resumes_after_playback :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room: game.Room
	if !testing.expect(t, devtools.create_tactical_independent_world_room(&data, &player, &room)) { return }
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	buffer: run_session.Buffered_Gameplay_Command
	run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 1, true, {focused = true})
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
	before_events := room.recent_events^
	testing.expect(t, !run_session.commit_gameplay_command(&room, renderer, &cards,
		{kind = .Continue_Pulse, origin_phase = .Combat}))
	testing.expect_value(t, player, before_player)
	testing.expect_value(t, room.tactical_pulse, before_pulse)
	testing.expect_value(t, room.pulse_count, before_count)
	testing.expect_value(t, room.enemies[0], before_enemy)
	testing.expect_value(t, room.recent_events^, before_events)
	// Real playback returns the occupied slots. The pending authoritative beat
	// then resumes exactly once, without a forced reset or discarded time debt.
	render.update_renderer_frame_timeline(renderer, seed.cue.duration+0.01)
	testing.expect(t, !render.renderer_world_is_busy(renderer))
	testing.expect(t, !run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
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
	spawns := [?]game.Enemy_Spawn{{position = {x = 2, y = 1}, health = 20, attack = 1}}
	room, created := game.create_room(&data, &player, {enemies = spawns[:]})
	if !testing.expect(t, created) { return }
	defer game.destroy_room(&room)
	// Arrange this defense one beat before the deadline, leaving that last
	// paid beat pending through the QTE independently of role balance.
	room.enemies[0].tactical_cooldown = 2
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	buffer: run_session.Buffered_Gameplay_Command
	testing.expect(t, run_session.commit_gameplay_command(&room, renderer, &cards,
		{kind = .Ability, origin_phase = .Combat, ability = .Guard}))
	testing.expect(t, render.renderer_blocks_player_input(renderer))
	input := run_session.Tactical_Controller_Input{focused = true, directions = {true, false, false, false}}
	input.defenses[int(game.Defense_Mode.Parry)] = true
	testing.expect(t, run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 2, true, input))
	testing.expect_value(t, room.qte.kind, game.QTE_Kind.Defense)
	testing.expect_value(t, room.qte.remaining, config.qte_seconds)
	testing.expect(t, !room.qte.selected && room.qte.progress == 0 && !buffer.chord.active)
	testing.expect_value(t, player.position, data.player_spawn)
	testing.expect_value(t, player.tactical.remaining, f32(0))
	testing.expect_value(t, player.tactical.queued_beats, 1)
	testing.expect_value(t, player.tactical.cycle, 0)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect(t, run_session.commit_gameplay_command(&room, renderer, &cards,
		{kind = .QTE_Fail, origin_phase = .Combat}))
	testing.expect(t, run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
		0, true, {focused = true}))
	testing.expect_value(t, room.qte.kind, game.QTE_Kind.None)
	testing.expect_value(t, room.pulse_count, u64(3))
	testing.expect_value(t, player.tactical.queued_beats, 0)
	testing.expect_value(t, player.tactical.phase, game.Tactical_Phase.Recovery)
	testing.expect_value(t, player.tactical.cycle, 1)
	testing.expect_value(t, player.position, data.player_spawn)
}
