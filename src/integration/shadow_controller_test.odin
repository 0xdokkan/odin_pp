package integration
import run_session "../run"

import "core:testing"
import game "../game"
import grid "../engine/grid"
import level "../level"
import render "../render"

@(test)
test_m7_shadow_holds_its_clock_for_the_card_walks_on_moves_and_rises_by_command :: proc(t: ^testing.T) {
	data := create_gameplay_command_test_level(t)
	defer level.destroy(&data)
	player := create_gameplay_command_test_player(t)
	configure_single_card_test_deck(t, &player, .Shadow_Step)
	testing.expect(t, game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
	enemies := [?]game.Enemy_Spawn{{position = {x = 5, y = 3}, health = 8, attack = 1}}
	room, ok := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	buffer: run_session.Buffered_Gameplay_Command
	window := player.tactical.remaining
	testing.expect(t, run_session.commit_gameplay_command(&room, renderer, &cards, {kind = .Play_Card, origin_phase = .Combat,
		card_id = player.deck.hand[0].id, target = game.entity_target(game.PLAYER_ENTITY)}))
	testing.expect(t, game.tactical_shadow_active(&room))
	// The card's own cue holds the shadow's four seconds.
	testing.expect(t, render.renderer_blocks_player_input(renderer))
	testing.expect(t, run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 1, true, {focused = true}))
	testing.expect_value(t, player.tactical.shadow_remaining, game.TACTICAL_SHADOW_SECONDS)
	render.update_renderer_event_timeline(renderer, 100)
	// The card, its sinking and its replacement drawn at once all replay cleanly.
	testing.expect_value(t, renderer.timeline.update_failures, 0)
	// An ordinary walk moves the shadow, never the body, and leaves the lane
	// to the shadow's own lockout.
	body := player.position
	testing.expect(t, run_session.commit_gameplay_command(&room, renderer, &cards, {kind = .Move, origin_phase = .Combat, direction = .East}))
	testing.expect_value(t, player.position, body)
	testing.expect_value(t, player.tactical.shadow_position, grid.Position{x = 2, y = 1})
	testing.expect(t, !render.renderer_blocks_player_input(renderer))
	testing.expect(t, game.tactical_player_busy(&room))
	for _ in 0..<40 {
		if !game.tactical_shadow_active(&room) { break }
		run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 0.25, true, {focused = true})
	}
	testing.expect(t, !game.tactical_shadow_active(&room))
	testing.expect_value(t, player.position, grid.Position{x = 2, y = 1})
	testing.expect_value(t, player.tactical.remaining, window)
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect(t, render.renderer_blocks_player_input(renderer), "the rise keeps its presentation")
	render.update_renderer_event_timeline(renderer, 100)
	testing.expect_value(t, renderer.timeline.update_failures, 0)
}

// The scene's lane inside the shadow, frame by frame: presses during the
// card's cue and during a 0.4 s step are dropped, and a press on a shadow beat
// waits for its partner key across the controller's frames (here none comes:
// it steps straight and leaves the beat unspent).
@(test)
test_m7_shadow_lane_drops_presses_during_a_step_and_keeps_the_tick_chord :: proc(t: ^testing.T) {
	data := create_gameplay_command_test_level(t)
	defer level.destroy(&data)
	player := create_gameplay_command_test_player(t)
	configure_single_card_test_deck(t, &player, .Shadow_Step)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.timed_actions = true
	testing.expect(t, game.configure_tactical(&player, config))
	enemies := [?]game.Enemy_Spawn{{position = {x = 5, y = 3}, health = 8, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	held: run_session.Buffered_Gameplay_Command
	dt := f32(1.0/60.0)
	east := run_session.Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .East}
	south := run_session.Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .South}
	window := player.tactical.remaining
	testing.expect(t, run_session.commit_gameplay_command(&room, renderer, &cards, {kind = .Play_Card, origin_phase = .Combat,
		card_id = player.deck.hand[0].id, target = game.entity_target(game.PLAYER_ENTITY)}))
	// The card's cue drops presses and holds the shadow's clock.
	for _ in 0..<30 { testing.expect(t, !scene_lane_frame(t, &controller, &room, renderer, &cards, &held, east, true, dt)) }
	testing.expect(t, render.renderer_blocks_player_input(renderer))
	testing.expect_value(t, player.tactical.shadow_remaining, game.TACTICAL_SHADOW_SECONDS)
	for _ in 0..<120 {
		if !render.renderer_blocks_player_input(renderer) { break }
		testing.expect(t, !scene_lane_frame(t, &controller, &room, renderer, &cards, &held, east, false, dt))
	}
	testing.expect(t, player.tactical.shadow_remaining > game.TACTICAL_SHADOW_SECONDS-2*dt)
	body := player.position
	testing.expect(t, scene_lane_frame(t, &controller, &room, renderer, &cards, &held, east, true, dt))
	stepped := game.add_position(body, {x = 1, y = 0})
	testing.expect_value(t, player.tactical.shadow_position, stepped)
	// The step's own lockout drops presses too (the frame on which it runs
	// out is already free).
	dropped := 0
	for player.tactical.shadow_step_remaining > 2*dt && dropped < 60 {
		testing.expect(t, game.tactical_player_busy(&room))
		testing.expect(t, !scene_lane_frame(t, &controller, &room, renderer, &cards, &held, east, true, dt))
		testing.expect(t, !held.chord.active)
		dropped += 1
	}
	testing.expect(t, dropped > 15)
	testing.expect_value(t, player.tactical.shadow_position, stepped)
	for _ in 0..<120 {
		if game.tactical_shadow_beat_target(&room) != 0 { break }
		testing.expect(t, !scene_lane_frame(t, &controller, &room, renderer, &cards, &held, east, false, dt))
	}
	testing.expect_value(t, game.tactical_shadow_beat_target(&room), u32(1))
	testing.expect(t, !scene_lane_frame(t, &controller, &room, renderer, &cards, &held, south, true, dt))
	testing.expect(t, held.chord.active)
	waited := 0
	for !scene_lane_frame(t, &controller, &room, renderer, &cards, &held, south, false, dt) && waited < 30 { waited += 1 }
	testing.expect(t, waited > 0 && f32(waited)*dt < run_session.BEAT_CHORD_SECONDS+dt)
	testing.expect_value(t, player.tactical.shadow_position, game.add_position(stepped, {x = 0, y = 1}))
	testing.expect(t, 1 not_in player.tactical.shadow_beats_spent)
	for _ in 0..<600 {
		if !game.tactical_shadow_active(&room) { break }
		testing.expect(t, !scene_lane_frame(t, &controller, &room, renderer, &cards, &held, east, false, dt))
	}
	testing.expect(t, !game.tactical_shadow_active(&room))
	testing.expect_value(t, player.position, game.add_position(stepped, {x = 0, y = 1}))
	testing.expect_value(t, player.tactical.remaining, window)
	testing.expect_value(t, room.pulse_count, u64(0))
}

// Played on the tick, the card leaves the beat alone: no critical, no badge,
// and the tick is still there for the first move after the rise.
@(test)
test_m7_shadow_card_on_the_tick_does_not_claim_the_beat :: proc(t: ^testing.T) {
	data := create_gameplay_command_test_level(t)
	defer level.destroy(&data)
	player := create_gameplay_command_test_player(t)
	configure_single_card_test_deck(t, &player, .Shadow_Step)
	testing.expect(t, game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
	enemies := [?]game.Enemy_Spawn{{position = {x = 5, y = 3}, health = 8, attack = 1}}
	room, ok := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer game.destroy_room(&room)
	testing.expect(t, !game.tactical_tick(&room, 0.9, true, false))
	beat := game.tactical_beat_target(&room)
	testing.expect_value(t, beat, u32(1))
	played := run_session.execute_gameplay_command(&room, {kind = .Play_Card, origin_phase = .Combat,
		card_id = player.deck.hand[0].id, target = game.entity_target(game.PLAYER_ENTITY), beat = beat})
	testing.expect(t, played.committed)
	testing.expect(t, game.tactical_shadow_active(&room))
	testing.expect_value(t, player.tactical.beat_spent, u32(0))
	for event in room.recent_events.events[:room.recent_events.count] {
		testing.expect(t, !game.event_is_critical(event))
	}
	testing.expect(t, !game.tactical_tick(&room, game.TACTICAL_SHADOW_SECONDS, true, false))
	testing.expect(t, run_session.execute_gameplay_command(&room, {kind = .Shadow_Emerge, origin_phase = .Combat}).committed)
	testing.expect_value(t, game.tactical_beat_target(&room), beat)
}
