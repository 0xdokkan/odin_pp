package main

import "core:testing"
import game "game"
import level "level"
import render "render"

// A walled room, one Pinball in hand and one foe beside the player at (5, 4).
create_pinball_controller_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^game.Player, room: ^game.Room) -> bool {
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
	configure_single_card_test_deck(t, player, .Pinball)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.vision_size = 0
	config.timed_actions = true
	testing.expect(t, game.configure_tactical(player, config))
	enemies := [?]game.Enemy_Spawn{{position = {6, 4}, health = 40, attack = 1}}
	built: bool
	room^, built = game.create_room(data, player, {enemies = enemies[:]})
	return testing.expect(t, built)
}

// PINBALL through the controller: the strike is the player's own cast; then
// the roll's seconds go out as world commands after the frame's beats, its
// pictures replay cleanly, the player steps while it rolls, and at twenty
// seconds of the world's own time the ball bursts and the room is cleared.
@(test)
test_pinball_rolls_in_world_commands_while_the_player_acts :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room: game.Room
	if !create_pinball_controller_test_room(t, &data, &player, &room) { return }
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := Tactical_Controller{was_focused = true}
	cards: Card_Interaction_State
	held: Buffered_Gameplay_Command
	dt := f32(1.0/60.0)
	west := Gameplay_Command{kind = .Move, origin_phase = .Combat, direction = .West}
	foe := room.enemies[0].id
	testing.expect(t, gameplay_command_is_valid({kind = .Pinball_Roll, origin_phase = .Combat}))
	testing.expect(t, !gameplay_command_is_valid({kind = .Pinball_Roll, origin_phase = .Loot}))
	// Nothing to roll: the command commits nothing.
	testing.expect(t, !commit_gameplay_command(&room, renderer, &cards, {kind = .Pinball_Roll, origin_phase = .Combat}))
	testing.expect(t, commit_gameplay_command(&room, renderer, &cards, {kind = .Play_Card, origin_phase = .Combat,
		card_id = player.deck.hand[0].id, target = game.entity_target(game.enemy_entity(foe))}))
	testing.expect(t, game.tactical_pinball_active(&room) && game.tactical_is_casting(&room))
	frames := 0
	for (game.tactical_is_casting(&room) || render.renderer_blocks_player_input(renderer)) && frames < 600 {
		testing.expect(t, !scene_lane_frame(t, &controller, &room, renderer, &cards, &held, west, false, dt))
		frames += 1
	}
	testing.expect(t, frames < 600)
	testing.expect_value(t, room.pinball.run, f64(0))
	// The roll: a second of the world's, seven cells; the player steps west meanwhile.
	stepped := false
	for frame := 0; frame < 60; frame += 1 {
		if scene_lane_frame(t, &controller, &room, renderer, &cards, &held, west, !stepped, dt) { stepped = true }
	}
	testing.expect(t, stepped)
	testing.expect(t, abs(game.pinball_rolled(&room.pinball)-1) < 0.05)
	// The rest of its time, and its burst: the room is cleared.
	for frame := 0; frame < 60*30 && room.phase == .Combat; frame += 1 {
		_ = scene_lane_frame(t, &controller, &room, renderer, &cards, &held, west, false, dt)
	}
	testing.expect_value(t, room.phase, game.Room_Phase.Loot)
	testing.expect(t, !room.pinball.active && len(room.enemies) == 0)
	for _ in 0..<600 {
		if !render.renderer_timeline_is_busy(renderer) { break }
		render.update_renderer_frame_timeline(renderer, 0.05)
	}
	render.update_renderer_event_timeline(renderer, 100)
	testing.expect_value(t, renderer.timeline.update_failures, 0)
	if testing.expect(t, renderer.world_playback != nil) { testing.expect_value(t, renderer.world_playback.rejected_batches, 0) }
}
