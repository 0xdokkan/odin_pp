package integration
import run_session "../run"

import "core:testing"
import game "../game"
import level "../level"
import render "../render"

// THE JUICE (render/juice.odin): through a hit-stop the controller gives the
// world no time and keeps the lane's newest press; then the world runs again.
@(test)
test_a_hit_stop_gives_the_world_no_time_and_keeps_the_press :: proc(t: ^testing.T) {
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
	cooldown := room.enemies[0].tactical_cooldown
	fraction := player.tactical.clock_fraction
	testing.expect(t, render.juice_hit_stop(renderer, 0.06))
	for _ in 0..<3 {
		_ = render.update_renderer_frame_timeline(renderer, 1.0/60)
		testing.expect(t, run_session.step_tactical_controller(&controller, &room, renderer, &cards, &held, 1.0/60, true, {focused = true}))
		testing.expect(t, controller.lane_busy)
	}
	testing.expect_value(t, room.enemies[0].tactical_cooldown, cooldown)
	testing.expect_value(t, player.tactical.clock_fraction, fraction)
	for _ in 0..<6 {
		_ = render.update_renderer_frame_timeline(renderer, 1.0/60)
		_ = run_session.step_tactical_controller(&controller, &room, renderer, &cards, &held, 1.0/60, true, {focused = true})
	}
	testing.expect(t, !render.renderer_hit_stopped(renderer))
	testing.expect(t, player.tactical.clock_fraction > fraction || room.enemies[0].tactical_cooldown != cooldown)
}
