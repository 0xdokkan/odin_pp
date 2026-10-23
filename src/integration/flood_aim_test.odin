package integration
import run_session "../run"

import "core:testing"
import game "../game"
import level "../level"
import render "../render"
import view "../engine/view"

// The Inondazione held over the board: the mouse's cell gives the wave's way
// until the wheel turns it a quarter turn a notch; the way then stays, the
// board is told (and the camera's zoom with it), and the card is played on a
// cell the chosen way names, whichever cell the mouse is over.
@(test)
test_flood_wheel_turns_the_waves_way_and_the_drop_follows :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player, created := game.create_player(run_session.DEMO_PLAYER_STATS)
	testing.expect(t, created)
	room, built := run_session.create_mechanics_lab_room(&data, &player, game.DEFAULT_TACTICAL_CONFIG)
	testing.expect(t, built)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	renderer.canvas_width, renderer.canvas_height = 960, 540
	flood: u32
	for card in player.deck.hand[:player.deck.hand_count] { if card.definition_id == .Flood_Wave { flood = card.id } }
	testing.expect(t, flood != 0)
	cards := run_session.Card_Interaction_State{dragged_card_id = flood}
	board := render.tactical_world_bounds(renderer)
	on_board := view.Vec2{board.x+board.width*0.5, board.y+board.height*0.5}
	east := game.add_position(player.position, {2, 0})
	renderer.has_hovered_cell, renderer.hovered_cell = true, east
	poll :: proc(room: ^game.Room, renderer: ^render.Renderer, cards: ^run_session.Card_Interaction_State, on_board: view.Vec2,
		controls: run_session.Run_Input) -> (run_session.Gameplay_Command, bool) {
		return run_session.poll_gameplay_command(room, renderer, cards, on_board, true, true, false, controls)
	}
	// Held over a cell east of him: the way is east, from the mouse.
	_, has := poll(&room, renderer, &cards, on_board, {left_down = true})
	testing.expect(t, !has)
	aim := renderer.tactical.flood_aim
	testing.expect(t, aim.active && !aim.forced && aim.way == .East && render.flood_aim_active(renderer))
	// A notch up turns it clockwise, to south; the mouse stays where it is.
	_, has = poll(&room, renderer, &cards, on_board, {left_down = true, wheel = 1})
	aim = renderer.tactical.flood_aim
	testing.expect(t, !has && aim.forced && aim.way == .South && cards.flood_way_set && cards.flood_way == .South)
	// Two down: south, east, north.
	_, _ = poll(&room, renderer, &cards, on_board, {left_down = true, wheel = -1})
	_, _ = poll(&room, renderer, &cards, on_board, {left_down = true, wheel = -1})
	aim = renderer.tactical.flood_aim
	testing.expect(t, aim.forced && aim.way == .North)
	// The way stays when the mouse moves.
	renderer.hovered_cell = game.add_position(player.position, {0, 2})
	_, _ = poll(&room, renderer, &cards, on_board, {left_down = true})
	testing.expect_value(t, renderer.tactical.flood_aim.way, game.Move_Direction.North)
	// Let go over a cell south: the command names a cell to the north.
	command, played := poll(&room, renderer, &cards, on_board, {left_released = true})
	testing.expect(t, played && command.kind == .Play_Card && command.card_id == flood)
	testing.expect_value(t, command.target.kind, game.Target_Kind.Cell)
	way, ok := game.flood_direction(player.position, command.target.cell)
	testing.expect(t, ok && way == .North)
	// The command played, the hand puts the card away (execute_gameplay_command
	// clears the interaction): the aim is over and the wheel is the camera's.
	run_session.clear_card_interaction(&cards)
	_, _ = poll(&room, renderer, &cards, on_board, {})
	testing.expect(t, !cards.flood_way_set && !render.flood_aim_active(renderer))

	// Without the wheel the mouse's cell gives the way, as before.
	cards = {dragged_card_id = flood}
	renderer.hovered_cell = game.add_position(player.position, {-2, 0})
	command, played = poll(&room, renderer, &cards, on_board, {left_released = true})
	testing.expect(t, played)
	way, ok = game.flood_direction(player.position, command.target.cell)
	testing.expect(t, ok && way == .West)
	// The wheel with another card held turns nothing.
	other: u32
	for card in player.deck.hand[:player.deck.hand_count] { if card.definition_id == .Wildfire { other = card.id } }
	cards = {dragged_card_id = other}
	_, _ = poll(&room, renderer, &cards, on_board, {left_down = true, wheel = 1})
	testing.expect(t, !cards.flood_way_set && !render.flood_aim_active(renderer))
}

@(test)
test_flood_turn_is_a_quarter_turn_a_notch :: proc(t: ^testing.T) {
	testing.expect_value(t, run_session.flood_turn(.North, 1), game.Move_Direction.East)
	testing.expect_value(t, run_session.flood_turn(.West, 1), game.Move_Direction.North)
	testing.expect_value(t, run_session.flood_turn(.North, -1), game.Move_Direction.West)
	testing.expect_value(t, run_session.flood_turn(.East, 4), game.Move_Direction.East)
	testing.expect_value(t, run_session.flood_turn(.South, -5), game.Move_Direction.East)
}
