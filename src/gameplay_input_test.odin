package main

import "core:testing"
import game "game"
import level "level"
import render "render"

// Nothing is kept for later: clearing drops even a tick move waiting for its
// diagonal partner, so no boundary can replay it.
@(test)
test_clearing_held_input_drops_a_pending_tick_chord :: proc(t: ^testing.T) {
	held := Buffered_Gameplay_Command{chord = {command = {kind = .Move, origin_phase = .Combat, direction = .North, beat = 3},
		timer = BEAT_CHORD_SECONDS, active = true}}
	clear_gameplay_command_buffer(&held)
	testing.expect_value(t, held, Buffered_Gameplay_Command{})
	clear_gameplay_command_buffer(nil)
}

@(test)
test_gameplay_command_rejects_kinds_outside_their_origin_phase :: proc(t: ^testing.T) {
	testing.expect(t, gameplay_command_is_valid({
		kind = .Move,
		origin_phase = .Loot,
		direction = .North,
	}))
	testing.expect(t, !gameplay_command_is_valid({kind = .Wait, origin_phase = .Loot}))
	testing.expect(t, !gameplay_command_is_valid({kind = .Refocus, origin_phase = .Loot}))
	testing.expect(t, !gameplay_command_is_valid({
		kind = .Play_Card,
		origin_phase = .Complete,
		card_id = 1,
	}))
}

// A busy lane drops the command and any pending chord; a free lane passes an
// off-tick command through at once, and a tick move after its chord wait.
@(test)
test_route_drops_commands_while_busy_and_passes_them_when_free :: proc(t: ^testing.T) {
	data := create_gameplay_command_test_level(t)
	defer level.destroy(&data)
	player := create_gameplay_command_test_player(t)
	testing.expect(t, game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG))
	enemies := [?]game.Enemy_Spawn{{position = {5, 3}, health = 20, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	east := Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .East}
	held := Buffered_Gameplay_Command{chord = {command = east, timer = BEAT_CHORD_SECONDS, active = true}}
	_, routed := route_gameplay_command(&held, &room, true, east, true, 1.0/60.0)
	testing.expect(t, !routed)
	testing.expect_value(t, held, Buffered_Gameplay_Command{})
	// A fresh window is not on the tick: the command needs no partner key.
	ready, passed := route_gameplay_command(&held, &room, false, east, true, 1.0/60.0)
	testing.expect(t, passed)
	testing.expect_value(t, ready, east)
	testing.expect(t, !held.chord.active)
	// A tick move waits a few frames for its diagonal partner key, then steps
	// straight when none comes.
	tick := Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .East, beat = 1}
	held.chord = {command = tick, timer = BEAT_CHORD_SECONDS, active = true}
	straight: Gameplay_Command
	stepped := false
	frames := 0
	for !stepped && frames < 60 {
		straight, stepped = route_gameplay_command(&held, &room, false, {}, false, 1.0/60.0)
		frames += 1
	}
	testing.expect(t, stepped && frames > 1 && f32(frames-1)/60 < BEAT_CHORD_SECONDS)
	testing.expect_value(t, straight, tick)
	testing.expect(t, !held.chord.active)
}

// One native frame of the scene (roguelike_update): presentation, the tactical
// controller (a classic board has none) with the frame's keys, then, unless
// the controller keeps the frame for itself (the scene then drops all held
// input), the input lane with the scene's busy flag, and the commit.
// `pressed` presses `command` for the controller and the lane's poll alike.
// With `only_while_busy` the lane takes the press only on a frame the player's
// own action still holds after this frame's update, so the frame on which the
// action ends never counts as a press made during it. Whatever the frame, the
// controller never takes up a press for later.
scene_lane_frame :: proc(t: ^testing.T, controller: ^Tactical_Controller, room: ^game.Room, renderer: ^render.Renderer,
	cards: ^Card_Interaction_State, held: ^Buffered_Gameplay_Command, command: Gameplay_Command, pressed: bool,
	dt: f32, only_while_busy := false) -> (committed: bool) {
	render.update_renderer_frame_timeline(renderer, dt)
	input := Tactical_Controller_Input{focused = true}
	if pressed && command.kind == .Move { input.directions[int(command.direction)] = true }
	before := held^
	blocked := step_tactical_controller(controller, room, renderer, cards, held, dt, true, input)
	testing.expect(t, held^ == before || held^ == Buffered_Gameplay_Command{}, "the controller kept a press for later")
	if blocked {
		clear_gameplay_command_buffer(held)
		return false
	}
	busy := render.renderer_blocks_player_input(renderer) || game.tactical_player_busy(room)
	ready, ok := route_gameplay_command(held, room, busy, command, pressed && (busy || !only_while_busy), dt)
	return ok && commit_gameplay_command(room, renderer, cards, ready)
}

// Pressing forward twice during one step makes one step, not two: the second
// press arrives while the first step's animation and timed second still run,
// and nothing brings it back when they end. A press after the action acts.
@(test)
test_presses_during_the_players_own_action_are_dropped_not_chained :: proc(t: ^testing.T) {
	data := create_gameplay_command_test_level(t)
	defer level.destroy(&data)
	player := create_gameplay_command_test_player(t)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.timed_actions = true
	testing.expect(t, game.configure_tactical(&player, config))
	enemies := [?]game.Enemy_Spawn{{position = {5, 3}, health = 20, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := Tactical_Controller{was_focused = true}
	cards: Card_Interaction_State
	held: Buffered_Gameplay_Command
	east := Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .East}
	dt := f32(1.0/60.0)
	testing.expect(t, scene_lane_frame(t, &controller, &room, renderer, &cards, &held, east, true, dt))
	first := player.position
	testing.expect_value(t, first, game.add_position(data.player_spawn, {1, 0}))
	testing.expect(t, render.renderer_blocks_player_input(renderer) && game.tactical_player_busy(&room))
	// A press on every frame of the step's animation and of its timed second
	// is dropped (the frame on which the second runs out is already free).
	dropped := 0
	for player.tactical.action_remaining > 2*dt && dropped < 600 {
		testing.expect(t, !scene_lane_frame(t, &controller, &room, renderer, &cards, &held, east, true, dt))
		testing.expect(t, !held.chord.active)
		dropped += 1
	}
	testing.expect(t, dropped > 30)
	testing.expect_value(t, player.position, first)
	// Nothing comes back on its own once the action is over.
	for _ in 0..<30 { testing.expect(t, !scene_lane_frame(t, &controller, &room, renderer, &cards, &held, east, false, dt)) }
	testing.expect(t, !game.tactical_player_busy(&room) && !render.renderer_blocks_player_input(renderer))
	testing.expect_value(t, player.position, first)
	// A press made after the action acts once (on the tick it first waits a
	// few frames for a diagonal partner key).
	moved := 0
	for index in 0..<8 {
		if scene_lane_frame(t, &controller, &room, renderer, &cards, &held, east, index == 0, dt) { moved += 1 }
	}
	testing.expect_value(t, moved, 1)
	testing.expect_value(t, player.position, game.add_position(first, {1, 0}))
}

// The same rule on a classic board (--classic, and the card practice, which
// turns the tactical rules off): a press on every frame of the player's own
// turn, his step and the enemies' answer, is dropped, nothing is kept for its
// end, and a fresh press after it moves exactly one cell.
@(test)
test_classic_presses_during_the_players_own_turn_are_dropped_not_chained :: proc(t: ^testing.T) {
	data := create_gameplay_command_test_level(t)
	defer level.destroy(&data)
	player := create_gameplay_command_test_player(t)
	enemies := [?]game.Enemy_Spawn{{position = {5, 3}, health = 20, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	testing.expect(t, !game.tactical_enabled(&room))
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller: Tactical_Controller
	cards: Card_Interaction_State
	held: Buffered_Gameplay_Command
	east := Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .East}
	dt := f32(1.0/60.0)
	testing.expect(t, scene_lane_frame(t, &controller, &room, renderer, &cards, &held, east, true, dt))
	first := player.position
	testing.expect_value(t, first, game.add_position(data.player_spawn, {1, 0}))
	testing.expect(t, render.renderer_blocks_player_input(renderer))
	dropped := 0
	for render.renderer_blocks_player_input(renderer) && dropped < 600 {
		testing.expect(t, !scene_lane_frame(t, &controller, &room, renderer, &cards, &held, east, true, dt, only_while_busy = true))
		testing.expect_value(t, held, Buffered_Gameplay_Command{})
		dropped += 1
	}
	testing.expect(t, dropped > 5 && !render.renderer_blocks_player_input(renderer))
	testing.expect_value(t, player.position, first)
	for _ in 0..<30 { testing.expect(t, !scene_lane_frame(t, &controller, &room, renderer, &cards, &held, east, false, dt)) }
	testing.expect_value(t, player.position, first)
	moved := 0
	for index in 0..<8 {
		if scene_lane_frame(t, &controller, &room, renderer, &cards, &held, east, index == 0, dt) { moved += 1 }
	}
	testing.expect_value(t, moved, 1)
	testing.expect_value(t, player.position, game.add_position(first, {1, 0}))
}

// The dodge is an answer, not a held press: Shift+WASD during the step's
// animation is dropped like any other key, but in the timed second after it
// the dodge acts at once and cuts that second short with its own.
@(test)
test_a_dodge_still_cuts_the_players_own_timed_action_short :: proc(t: ^testing.T) {
	data := create_gameplay_command_test_level(t)
	defer level.destroy(&data)
	player := create_gameplay_command_test_player(t)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.timed_actions = true
	testing.expect(t, game.configure_tactical(&player, config))
	enemies := [?]game.Enemy_Spawn{{position = {5, 3}, health = 20, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := Tactical_Controller{was_focused = true}
	cards: Card_Interaction_State
	held: Buffered_Gameplay_Command
	testing.expect(t, commit_gameplay_command(&room, renderer, &cards, {kind = .Move, origin_phase = .Combat, direction = .East}))
	step := player.position
	dodge := Tactical_Controller_Input{focused = true, shift = true, directions = {false, false, true, false}}
	testing.expect(t, step_tactical_controller(&controller, &room, renderer, &cards, &held, 0, true, dodge))
	testing.expect_value(t, player.position, step)
	render.update_renderer_event_timeline(renderer, 100)
	testing.expect(t, !step_tactical_controller(&controller, &room, renderer, &cards, &held, 0.25, true, {focused = true}))
	testing.expect(t, game.tactical_player_busy(&room) && player.tactical.action_remaining < game.TACTICAL_DODGE_SECONDS)
	testing.expect(t, step_tactical_controller(&controller, &room, renderer, &cards, &held, 0, true, dodge))
	testing.expect_value(t, player.position, game.add_position(step, {0, 2}))
	testing.expect_value(t, player.tactical.action_remaining, game.TACTICAL_DODGE_SECONDS)
	testing.expect(t, !held.chord.active)
}
