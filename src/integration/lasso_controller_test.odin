package integration
import run_session "../run"

import "core:testing"
import game "../game"
import level "../level"
import render "../render"

// A walled room with space for a ring of three round the player at (5, 4),
// one Lazzo in hand and one foe two cells east of him.
create_lasso_controller_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^game.Player, room: ^game.Room) -> bool {
	rows := [?]string{
		"###########",
		"#.........#",
		"#.........#",
		"#.........#",
		"#....@....#",
		"#.........#",
		"#.........#",
		"#........>#",
		"###########",
	}
	parsed: level.Parse_Error
	data^, parsed, _ = level.from_ascii(rows[:])
	if !testing.expect_value(t, parsed, level.Parse_Error.None) { return false }
	player^ = create_gameplay_command_test_player(t)
	player.stats.max_health, player.health = 30, 30
	configure_single_card_test_deck(t, player, .Lasso)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.vision_size = 0
	config.timed_actions = true
	testing.expect(t, game.configure_tactical(player, config))
	enemies := [?]game.Enemy_Spawn{{position = {7, 4}, health = 40, attack = 1}}
	built: bool
	room^, built = game.create_room(data, player, {enemies = enemies[:]})
	return testing.expect(t, built)
}

// LAZZO through the controller: the throw is the player's own cast; then the
// spin's seconds go out as world commands after the frame's beats, its
// pictures replay cleanly, a press while the rope holds is dropped (never
// kept), and Shift with a direction dodges and lets go: the foe lands under
// itself and plans a fresh intent at once, no daze.
@(test)
test_lasso_spins_in_world_commands_and_a_dodge_lets_go :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room: game.Room
	if !create_lasso_controller_test_room(t, &data, &player, &room) { return }
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	held: run_session.Buffered_Gameplay_Command
	dt := f32(1.0/60.0)
	east := run_session.Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .East}
	foe := room.enemies[0].id
	testing.expect(t, run_session.gameplay_command_is_valid({kind = .Lasso_Spin, origin_phase = .Combat}))
	testing.expect(t, !run_session.gameplay_command_is_valid({kind = .Lasso_Spin, origin_phase = .Loot}))
	// Nothing to spin: the command commits nothing.
	testing.expect(t, !run_session.commit_gameplay_command(&room, renderer, &cards, {kind = .Lasso_Spin, origin_phase = .Combat}))

	testing.expect(t, run_session.commit_gameplay_command(&room, renderer, &cards, {kind = .Play_Card, origin_phase = .Combat,
		card_id = player.deck.hand[0].id, target = game.entity_target(game.enemy_entity(foe))}))
	testing.expect(t, game.tactical_lasso_active(&room))
	testing.expect_value(t, room.lasso.radius, i32(3))
	testing.expect(t, game.tactical_is_casting(&room))
	// The throw holds the world: no spin while it is cast and shown.
	frames := 0
	for (game.tactical_is_casting(&room) || render.renderer_blocks_player_input(renderer)) && frames < 600 {
		testing.expect(t, !scene_lane_frame(t, &controller, &room, renderer, &cards, &held, east, true, dt))
		frames += 1
	}
	testing.expect(t, frames < 600)
	testing.expect_value(t, room.lasso.turns, i32(0))
	body := player.position

	// The spin, on the world's seconds: a whole first turn (0.9 s) costs the
	// foe 1; every press meanwhile is dropped.
	health := room.enemies[0].health
	spun := 0
	for room.lasso.turns == 0 && spun < 120 {
		testing.expect(t, !scene_lane_frame(t, &controller, &room, renderer, &cards, &held, east, true, dt))
		testing.expect(t, game.tactical_player_busy(&room))
		testing.expect(t, held == run_session.Buffered_Gameplay_Command{})
		spun += 1
	}
	testing.expect_value(t, room.lasso.turns, i32(1))
	testing.expectf(t, spun >= 46 && spun <= 56, "the first turn lasts 0.9 s of the world's, not %d frames", spun)
	testing.expect_value(t, room.enemies[0].health, health-game.LASSO_TURN_DAMAGE)
	testing.expect_value(t, player.position, body)

	// Shift and a direction: a dodge, which lets go.
	under := room.enemies[0].position
	input := run_session.Tactical_Controller_Input{focused = true, shift = true}
	input.directions[int(game.Move_Direction.South)] = true
	render.update_renderer_frame_timeline(renderer, dt)
	testing.expect(t, run_session.step_tactical_controller(&controller, &room, renderer, &cards, &held, dt, true, input))
	testing.expect(t, !room.lasso.active)
	testing.expect_value(t, player.position, game.add_position(body, {0, 2}))
	index, alive := game.enemy_index_by_id(&room, foe)
	testing.expect(t, alive)
	testing.expect_value(t, room.enemies[index].position, under)
	kind := room.enemies[index].intent.kind
	testing.expect(t, kind != .Recover && kind != .Wait && kind != .None)
	testing.expect_value(t, room.enemies[index].recovery_pulses, i32(0))
	testing.expect(t, game.validate_enemy_intents(&room))
	released := false
	for event in room.recent_events.events[:room.recent_events.count] {
		if event.kind == .Lasso_Released { released = true; testing.expect_value(t, event.amount, i32(1)) }
	}
	testing.expect(t, released)
	for _ in 0..<600 {
		if !render.renderer_timeline_is_busy(renderer) { break }
		render.update_renderer_frame_timeline(renderer, 0.05)
	}
	render.update_renderer_event_timeline(renderer, 100)
	testing.expect_value(t, renderer.timeline.update_failures, 0)
	if testing.expect(t, renderer.world_playback != nil) { testing.expect_value(t, renderer.world_playback.rejected_batches, 0) }
	testing.expect(t, !game.tactical_lasso_due(&room))
}
