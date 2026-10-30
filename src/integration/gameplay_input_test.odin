package integration
import run_session "../run"

import "core:testing"
import game "../game"
import level "../level"
import render "../render"

// Nothing is kept for later: clearing drops even a tick move waiting for its
// diagonal partner, so no boundary can replay it.
@(test)
test_clearing_held_input_drops_a_pending_tick_chord :: proc(t: ^testing.T) {
	held := run_session.Buffered_Gameplay_Command{chord = {command = {kind = .Move, origin_phase = .Combat, direction = .North, beat = 3},
		timer = run_session.BEAT_CHORD_SECONDS, active = true}}
	run_session.clear_gameplay_command_buffer(&held)
	testing.expect_value(t, held, run_session.Buffered_Gameplay_Command{})
	run_session.clear_gameplay_command_buffer(nil)
}

@(test)
test_gameplay_command_rejects_kinds_outside_their_origin_phase :: proc(t: ^testing.T) {
	testing.expect(t, run_session.gameplay_command_is_valid({
		kind = .Move,
		origin_phase = .Loot,
		direction = .North,
	}))
	testing.expect(t, !run_session.gameplay_command_is_valid({kind = .Wait, origin_phase = .Loot}))
	testing.expect(t, !run_session.gameplay_command_is_valid({kind = .Refocus, origin_phase = .Loot}))
	testing.expect(t, !run_session.gameplay_command_is_valid({
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
	enemies := [?]game.Enemy_Spawn{{position = {x = 5, y = 3}, health = 20, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	east := run_session.Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .East}
	held := run_session.Buffered_Gameplay_Command{chord = {command = east, timer = run_session.BEAT_CHORD_SECONDS, active = true}}
	_, routed := run_session.route_gameplay_command(&held, &room, true, east, true, 1.0/60.0)
	testing.expect(t, !routed)
	testing.expect_value(t, held, run_session.Buffered_Gameplay_Command{})
	// A fresh window is not on the tick: the command needs no partner key.
	ready, passed := run_session.route_gameplay_command(&held, &room, false, east, true, 1.0/60.0)
	testing.expect(t, passed)
	testing.expect_value(t, ready, east)
	testing.expect(t, !held.chord.active)
	// A tick move waits a few frames for its diagonal partner key, then steps
	// straight when none comes.
	tick := run_session.Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .East, beat = 1}
	held.chord = {command = tick, timer = run_session.BEAT_CHORD_SECONDS, active = true}
	straight: run_session.Gameplay_Command
	stepped := false
	frames := 0
	for !stepped && frames < 60 {
		straight, stepped = run_session.route_gameplay_command(&held, &room, false, {}, false, 1.0/60.0)
		frames += 1
	}
	testing.expect(t, stepped && frames > 1 && f32(frames-1)/60 < run_session.BEAT_CHORD_SECONDS)
	testing.expect_value(t, straight, tick)
	testing.expect(t, !held.chord.active)
}

// One native frame of the scene (roguelike_update): presentation, the tactical
// controller with the frame's keys, then, unless
// the controller keeps the frame for itself (the scene then drops all held
// input), the input lane with the scene's busy flag, and the commit.
// `pressed` presses `command` for the controller and the lane's poll alike.
// With `only_while_busy` the lane takes the press only on a frame the player's
// own action still holds after this frame's update, so the frame on which the
// action ends never counts as a press made during it. Whatever the frame, the
// controller never takes up a press for later.
scene_lane_frame :: proc(t: ^testing.T, controller: ^run_session.Tactical_Controller, room: ^game.Room, renderer: ^render.Renderer,
	cards: ^run_session.Card_Interaction_State, held: ^run_session.Buffered_Gameplay_Command, command: run_session.Gameplay_Command, pressed: bool,
	dt: f32, only_while_busy := false) -> (committed: bool) {
	render.update_renderer_frame_timeline(renderer, dt)
	input := run_session.Tactical_Controller_Input{focused = true}
	if pressed && command.kind == .Move { input.directions[int(command.direction)] = true }
	before := held^
	blocked := run_session.step_tactical_controller(controller, room, renderer, cards, held, dt, true, input)
	testing.expect(t, held^ == before || held^ == run_session.Buffered_Gameplay_Command{}, "the controller kept a press for later")
	if blocked {
		run_session.clear_gameplay_command_buffer(held)
		return false
	}
	busy := render.renderer_blocks_player_input(renderer) || game.tactical_player_busy(room)
	ready, ok := run_session.route_gameplay_command(held, room, busy, command, pressed && (busy || !only_while_busy), dt)
	return ok && run_session.commit_gameplay_command(room, renderer, cards, ready)
}

// The renderer and controller must honor the cheaper walk before the next
// world beat, including with the actual timed/shrinking-window game settings:
// at the player's pace a step's 0.8 s first price is 0.4 s.
@(test)
test_walk_input_reopens_at_point_four_seconds_before_the_world_beat :: proc(t: ^testing.T) {
	data := create_gameplay_command_test_level(t)
	defer level.destroy(&data)
	player := create_gameplay_command_test_player(t)
	testing.expect(t, game.configure_tactical(&player, game.GAME_TACTICAL_CONFIG))
	enemies := [?]game.Enemy_Spawn{{position = {x = 5, y = 3}, health = 20, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	held: run_session.Buffered_Gameplay_Command
	east := run_session.Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .East}
	testing.expect(t, scene_lane_frame(t, &controller, &room, renderer, &cards, &held, east, true, 0))
	first := player.position
	for _ in 0..<3 {
		testing.expect(t, !scene_lane_frame(t, &controller, &room, renderer, &cards, &held, east, true, 0.1))
	}
	testing.expect_value(t, player.position, first)
	testing.expect(t, scene_lane_frame(t, &controller, &room, renderer, &cards, &held, east, true, 0.1))
	testing.expect_value(t, player.position, game.add_position(first, {x = 1, y = 0}))
	testing.expect_value(t, player.tactical.metrics.decisions, u64(2))
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect(t, abs(player.tactical.remaining-19.6) < 0.001)
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
	enemies := [?]game.Enemy_Spawn{{position = {x = 5, y = 3}, health = 20, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	held: run_session.Buffered_Gameplay_Command
	east := run_session.Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .East}
	dt := f32(1.0/60.0)
	testing.expect(t, scene_lane_frame(t, &controller, &room, renderer, &cards, &held, east, true, dt))
	first := player.position
	testing.expect_value(t, first, game.add_position(data.player_spawn, {x = 1, y = 0}))
	testing.expect(t, render.renderer_blocks_player_input(renderer) && game.tactical_player_busy(&room))
	// A press on every frame of the step's animation and of its timed second
	// is dropped (the frame on which the second runs out is already free).
	dropped := 0
	for player.tactical.action_remaining > 2*dt && dropped < 600 {
		testing.expect(t, !scene_lane_frame(t, &controller, &room, renderer, &cards, &held, east, true, dt))
		testing.expect(t, !held.chord.active)
		dropped += 1
	}
	// The step's 0.4 s at the player's pace: 24 frames.
	testing.expect(t, dropped > 18)
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
	testing.expect_value(t, player.position, game.add_position(first, {x = 1, y = 0}))
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
	enemies := [?]game.Enemy_Spawn{{position = {x = 5, y = 3}, health = 20, attack = 1}}
	room, built := game.create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, built)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	held: run_session.Buffered_Gameplay_Command
	testing.expect(t, run_session.commit_gameplay_command(&room, renderer, &cards, {kind = .Move, origin_phase = .Combat, direction = .East}))
	step := player.position
	dodge := run_session.Tactical_Controller_Input{focused = true, shift = true, directions = {false, false, true, false}}
	testing.expect(t, run_session.step_tactical_controller(&controller, &room, renderer, &cards, &held, 0, true, dodge))
	testing.expect_value(t, player.position, step)
	render.update_renderer_event_timeline(renderer, 100)
	testing.expect(t, !run_session.step_tactical_controller(&controller, &room, renderer, &cards, &held, 0.25, true, {focused = true}))
	testing.expect(t, game.tactical_player_busy(&room) && player.tactical.action_remaining < game.TACTICAL_DODGE_SECONDS)
	testing.expect(t, run_session.step_tactical_controller(&controller, &room, renderer, &cards, &held, 0, true, dodge))
	testing.expect_value(t, player.position, game.add_position(step, {x = 0, y = 2}))
	testing.expect_value(t, player.tactical.action_remaining, game.TACTICAL_DODGE_SECONDS/game.TACTICAL_PLAYER_PACE)
	testing.expect(t, !held.chord.active)
}
