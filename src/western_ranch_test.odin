package main

import "core:testing"
import game "game"
import level "level"
import render "render"
import western "western"

@(test)
test_ranch_opens_by_itself_freezes_the_board_and_pays_once :: proc(t: ^testing.T) {
	data := create_gameplay_command_test_level(t)
	defer level.destroy(&data)
	player := create_gameplay_command_test_player(t)
	testing.expect(t, game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
	testing.expect(t, game.initialize_empty_deck(&player.deck, {hand_size = 3, max_energy = 3, energy_regen_per_pulse = 1}, 5))
	for id in ([3]game.Card_Id{.Sei_Denari, .Strike, .Sette_Denari}) {
		_, added := game.add_owned_card(&player.deck, id)
		testing.expect(t, added)
	}
	spawns := [?]game.Enemy_Spawn{{position = {5, 3}, health = 9, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = spawns[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	renderer.canvas_width, renderer.canvas_height = 960, 540
	renderer.tactical.enabled = true
	session: M8_Session
	controller: Tactical_Controller
	cards := Card_Interaction_State{selected_card_id = 42}
	buffer: Buffered_Gameplay_Command
	player.health = 4
	gold := player.gold
	clock, pulse := player.tactical.remaining, room.pulse_count
	// Holding the pair opens the bubble without any input.
	testing.expect(t, step_m8_session(&session, &room, renderer, &controller, &cards, &buffer, true, 0, {focused = true}))
	testing.expect(t, session.ranch.active && cards.selected_card_id == 0)
	testing.expect_value(t, player.deck.hand_count, 1)
	// The duel owns input and time until it ends; presses on every tick win it.
	dt := f32(1.0/60.0)
	for _ in 0..<2000 {
		state := &session.ranch.state
		press := state.phase == .Ride && state.time+dt >= western.tick_time(state.tick)-dt*0.5 &&
		         state.offsets[western.PLAYER] == western.NO_PRESS
		testing.expect(t, step_m8_session(&session, &room, renderer, &controller, &cards, &buffer, true, dt, {focused = true, ranch_press = press}))
		if session.ranch.finished { break }
	}
	testing.expect(t, session.ranch.finished && session.ranch.reward.won)
	testing.expect_value(t, player.health, player.stats.max_health)
	testing.expect_value(t, player.gold, gold+game.WESTERN_RANCH_GOLD)
	testing.expect_value(t, player.tactical.remaining, clock)
	testing.expect_value(t, room.pulse_count, pulse)
	// The floor's ranch is spent: the board is free again and nothing reopens.
	render.clear_event_animations(renderer)
	testing.expect(t, !step_m8_session(&session, &room, renderer, &controller, &cards, &buffer, true, 0, {focused = true}))
	testing.expect(t, !session.ranch.active)
}

@(test)
test_ranch_pauses_without_focus_and_ignores_presses_then :: proc(t: ^testing.T) {
	data := create_gameplay_command_test_level(t)
	defer level.destroy(&data)
	player := create_gameplay_command_test_player(t)
	testing.expect(t, game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
	testing.expect(t, game.initialize_empty_deck(&player.deck, {hand_size = 2, max_energy = 3, energy_regen_per_pulse = 1}, 5))
	for id in ([2]game.Card_Id{.Sette_Denari, .Sei_Denari}) {
		_, added := game.add_owned_card(&player.deck, id)
		testing.expect(t, added)
	}
	spawns := [?]game.Enemy_Spawn{{position = {5, 3}, health = 9, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = spawns[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	renderer.canvas_width, renderer.canvas_height = 960, 540
	renderer.tactical.enabled = true
	session: M8_Session
	controller: Tactical_Controller
	cards: Card_Interaction_State
	buffer: Buffered_Gameplay_Command
	testing.expect(t, step_m8_session(&session, &room, renderer, &controller, &cards, &buffer, true, 0, {focused = true}))
	for session.ranch.state.phase == .Intro {
		testing.expect(t, step_m8_session(&session, &room, renderer, &controller, &cards, &buffer, true, 0.05, {focused = true}))
	}
	before := session.ranch.state
	testing.expect(t, step_m8_session(&session, &room, renderer, &controller, &cards, &buffer, true, 0.5, {ranch_press = true}))
	testing.expect_value(t, session.ranch.state.time, before.time)
	testing.expect_value(t, session.ranch.state.offsets, before.offsets)
}
