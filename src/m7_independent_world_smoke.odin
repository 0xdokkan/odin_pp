package main

import "core:fmt"
import rl "vendor:raylib"
import app "app"
import game "game"
import level "level"
import render "render"

// A real encounter shared by native-window smoke and controller regressions.
// The chaser's first move takes place away from the player, so a defense QTE
// cannot be confused with a presentation-only input lock.
create_m7_independent_world_room :: proc(data: ^level.Level, player: ^game.Player,
	room: ^game.Room) -> bool {
	rows := [?]string{
		"###############", "#.............#", "#.............#", "#...#.........#",
		"#......@......#", "#.............#", "#.............#", "#..........>..#", "###############",
	}
	err: level.Parse_Error
	data^, err, _ = level.from_ascii(rows[:])
	if err != .None { return false }
	created: bool
	player^, created = game.create_player({max_health = 100, attack = 2, defense = 1})
	config := game.DEFAULT_TACTICAL_CONFIG
	config.vision_size = 0
	if !created || !game.configure_tactical(player, config) ||
	   !game.initialize_empty_deck(&player.deck, game.DEFAULT_DECK_RULES, 74) { return false }
	for id in ([?]game.Card_Id{.Guard, .Strike, .Dash, .Firebomb, .Heavy_Blow}) {
		if _, added := game.add_owned_card(&player.deck, id); !added { return false }
	}
	spawns := [?]game.Enemy_Spawn{
		{position = {2, 4}, health = 20, attack = 2},
		{position = {11, 6}, health = 20, attack = 2, archetype = .Brute},
		{position = {11, 2}, health = 20, attack = 2, archetype = .Archer},
	}
	room^, created = game.create_room(data, player, {enemies = spawns[:]})
	return created
}

// Feed a fresh movement press through the same controller/poll/commit path as
// the native loop. A buffered command does not satisfy this fixture: movement
// must be accepted on the exact frame on which the press arrives.
m7_independent_fresh_move :: proc(controller: ^Tactical_Controller, room: ^game.Room,
	renderer: ^render.Renderer, cards: ^Card_Interaction_State,
	buffer: ^Buffered_Gameplay_Command, direction: game.Move_Direction) -> bool {
	input := Tactical_Controller_Input{focused = true}
	input.directions[int(direction)] = true
	if step_tactical_controller(controller, room, renderer, cards, buffer, 0, true, input) || buffer.occupied { return false }
	return commit_gameplay_command(room, renderer, cards,
		{kind = .Move, origin_phase = .Combat, direction = direction})
}

m7_independent_visual_frame :: proc(probe: ^M7_Visual_Probe, window: ^app.Window,
	renderer: ^render.Renderer, room: ^game.Room, controller: ^Tactical_Controller,
	cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command) -> bool {
	if !m7_visual_frame(probe, window, renderer, room) { return false }
	step_tactical_controller(controller, room, renderer, cards, buffer, 1.0/60.0, true, {focused = true})
	return true
}

run_m7_independent_world_smoke :: proc(window: ^app.Window, renderer: ^render.Renderer) -> bool {
	data: level.Level
	player: game.Player
	room: game.Room
	if !create_m7_independent_world_room(&data, &player, &room) { return false }
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	render.clear_event_animations(renderer)
	render.reset_tactical_orbit(&renderer.tactical.world_orbit)
	controller := Tactical_Controller{was_focused = true}
	cards: Card_Interaction_State
	buffer: Buffered_Gameplay_Command
	probe: M7_Visual_Probe
	for capture in M7_Visual_Capture { probe.captured += {capture} }
	for _ in 0..<3 {
		if !m7_independent_visual_frame(&probe, window, renderer, &room, &controller, &cards, &buffer) { return false }
	}
	// Real idle time schedules the first chaser movement. The same call must
	// finish bounded gameplay continuations without waiting for their pictures.
	blocked := step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
		2, true, {focused = true})
	if !m7_polish_check(!blocked && render.renderer_world_is_busy(renderer) &&
		!render.renderer_blocks_player_input(renderer) && !room.tactical_pulse.pending &&
		room.enemies[0].position != {2, 4}, "enemy cadence still exclusively owns player input") { return false }
	if !m7_independent_fresh_move(&controller, &room, renderer, &cards, &buffer, .East) { return false }
	for _ in 0..<8 {
		if !m7_independent_visual_frame(&probe, window, renderer, &room, &controller, &cards, &buffer) { return false }
	}
	if window != nil { rl.TakeScreenshot("odin_pp_m7_independent_movement.png") }
	// Release only the player's own move. Enemy movement has its own longer
	// duration and must still be playing when the next fresh key arrives.
	for _ in 0..<60 {
		if !render.renderer_blocks_player_input(renderer) { break }
		if !m7_independent_visual_frame(&probe, window, renderer, &room, &controller, &cards, &buffer) { return false }
	}
	if window != nil {
		// Present the state after the controller, as the native loop does, with
		// no extra simulation or playback step solely for the screenshot.
		if !m7_visual_frame(&probe, window, renderer, &room, dt = 0) { return false }
		rl.TakeScreenshot("odin_pp_m7_independent_ready.png")
	}
	if !m7_polish_check(render.renderer_world_is_busy(renderer) &&
		m7_independent_fresh_move(&controller, &room, renderer, &cards, &buffer, .South),
		"a repeated fresh movement waited for enemy animation") { return false }
	for _ in 0..<60 {
		if !render.renderer_blocks_player_input(renderer) { break }
		if !m7_independent_visual_frame(&probe, window, renderer, &room, &controller, &cards, &buffer) { return false }
	}
	// The two accepted moves paid two additional world beats. Drain their
	// gameplay immediately while retaining the concurrent world presentation.
	if step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
		0, true, {focused = true}) { return false }
	guard: u32
	for card in player.deck.hand[:player.deck.hand_count] {
		if card.definition_id == .Guard { guard = card.id }
	}
	if !m7_polish_check(guard != 0 && render.renderer_world_is_busy(renderer) &&
		!render.renderer_blocks_player_input(renderer) &&
		commit_gameplay_command(&room, renderer, &cards, {kind = .Play_Card, origin_phase = .Combat,
			card_id = guard, target = game.entity_target(game.PLAYER_ENTITY)}),
		"card was rejected while the enemy lane was active") { return false }
	for _ in 0..<8 {
		if !m7_independent_visual_frame(&probe, window, renderer, &room, &controller, &cards, &buffer) { return false }
	}
	if window != nil { rl.TakeScreenshot("odin_pp_m7_independent_card.png") }
	for _ in 0..<240 {
		if !m7_independent_visual_frame(&probe, window, renderer, &room, &controller, &cards, &buffer) { return false }
		if !render.renderer_timeline_is_busy(renderer) && !room.tactical_pulse.pending { break }
	}
	if window != nil {
		fmt.printf("M7 independent world: fresh move + repeat move + Guard accepted during enemy presentation; player=%v; clock=%.2f; world_beats=%d; timeline_errors=%d\n",
			player.position, player.tactical.remaining, room.pulse_count, renderer.timeline.update_failures)
	}
	return player.tactical.metrics.decision_seconds > 2 &&
		player.tactical.remaining < f32(player.tactical.config.timer_seconds)-5 &&
		!render.renderer_timeline_is_busy(renderer) && !room.tactical_pulse.pending &&
		!buffer.occupied && room.qte.kind == .None && renderer.timeline.update_failures == 0
}
