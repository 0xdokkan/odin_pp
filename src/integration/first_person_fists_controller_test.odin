package integration

import run_session "../run"
import "core:math"
import "core:testing"
import game "../game"
import level "../level"
import render "../render"

// FIRST PERSON BRAWLER through the controller (run/first_person_input.odin, Fase
// 2 passo 5): the movement keys held move the body turned with the view, Space
// jumps, a key pressed twice quickly dashes, a press of a button punches (with
// Shift a hook); the board's lane takes no step and Shift with a key no dodge.

@(private = "file")
fists_controller_begin :: proc(t: ^testing.T, room: ^game.Room, renderer: ^render.Renderer) {
	testing.expect(t, game.tactical_begin_first_person(room, 30, .Fists))
	view := &renderer.tactical.first_person
	view.engaged, view.amount, view.yaw = true, 1, 0
}

// The ways the keys move the body, turned with the view.
@(test)
test_first_person_fists_keys_turn_with_the_view :: proc(t: ^testing.T) {
	near :: proc(a, b: [2]f32) -> bool { return abs(a.x-b.x) < 1e-4 && abs(a.y-b.y) < 1e-4 }
	_, keys := run_session.first_person_fists_ways({}, 0)
	// Looking east: W east, D south (his right), S west, A north.
	testing.expect(t, near(keys[0], {1, 0}) && near(keys[1], {0, 1}) && near(keys[2], {-1, 0}) && near(keys[3], {0, -1}))
	wish, _ := run_session.first_person_fists_ways({true, true, false, false}, 0)
	testing.expect(t, near(wish, {math.SQRT_TWO/2, math.SQRT_TWO/2}), "W and D are not one diagonal of length 1")
	wish, _ = run_session.first_person_fists_ways({true, false, false, false}, -math.PI/2)
	testing.expect(t, near(wish, {0, -1}), "looking north W is not north")
	wish, _ = run_session.first_person_fists_ways({true, false, true, false}, 0.3)
	testing.expect(t, near(wish, {}), "W and S do not cancel")
}

// Held keys move him, Space jumps, a double tap dashes, presses punch; Shift with
// a key is no dodge, and the board's lane takes no step.
@(test)
test_first_person_fists_through_the_controller :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room: game.Room
	if !create_first_person_controller_test_room(t, &data, &player, &room) { return }
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	held: run_session.Buffered_Gameplay_Command
	dt := f32(1.0/60.0)
	fists_controller_begin(t, &room, renderer)
	f := &room.first_person.fists
	// The mouse taken first: nothing moves before.
	for _ in 0..<3 { first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt) }
	testing.expect(t, controller.look_captured)
	start := f.body
	// D held (looking east: south) for a fifth of a second.
	walk := run_session.Tactical_Controller_Input{}
	walk.walk[1] = true
	for _ in 0..<12 { first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, walk) }
	testing.expect(t, f.body.y-start.y > 0.5 && abs(f.body.x-start.x) < 1e-3, "D did not move him south")
	for _ in 0..<20 { first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt) }
	// The board's lane takes no step with the fists.
	controls := run_session.Run_Input{focused = true}
	controls.actions.pressed += {.North}
	_, stepped := run_session.poll_gameplay_command(&room, renderer, &cards, {}, false, false, false, controls)
	testing.expect(t, !stepped, "the lane took a step with the fists")
	// Space: a jump.
	jump := run_session.Tactical_Controller_Input{jump = true}
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, jump)
	testing.expect(t, f.airborne, "Space did not jump")
	for _ in 0..<40 { first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt) }
	testing.expect(t, !f.airborne)
	// A key pressed twice within a quarter of a second: a dash its way (A: north).
	tap := run_session.Tactical_Controller_Input{}
	tap.directions[3], tap.walk[3] = true, true
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, tap)
	for _ in 0..<6 { first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt) }
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, tap)
	testing.expect(t, f.dash_left > 0 || f.dash_recharge > 0, "the double tap did not dash")
	testing.expect(t, f.dash_way.y < -0.99, "the dash did not go north")
	for _ in 0..<90 { first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt) }
	// Two presses too far apart: no dash.
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, tap)
	for _ in 0..<30 { first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt) }
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, tap)
	testing.expect(t, f.dash_left <= 0 && f.dash_recharge <= 0, "a slow double tap dashed")
	for _ in 0..<30 { first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt) }
	// Shift and a key: no dodge's two cells at once.
	at := room.player.position
	dodge := run_session.Tactical_Controller_Input{shift = true}
	dodge.directions[0] = true
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, dodge)
	testing.expect(t, abs(room.player.position.x-at.x) <= 1, "Shift and W dodged")
	for _ in 0..<30 { first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt) }
	// A press of the left button: a jab, one however long held; with Shift a hook.
	shots := room.first_person.shots
	press := run_session.Tactical_Controller_Input{fire = true}
	for _ in 0..<40 { first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, press) }
	testing.expect_value(t, room.first_person.shots, shots+1)
	for _ in 0..<5 { first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt) }
	hook := run_session.Tactical_Controller_Input{fire = true, shift = true}
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, hook)
	testing.expect(t, room.first_person.shots == shots+2 && f.punch == .Left_Hook, "Shift and the left button are not a left hook")
	// The right button: a cross.
	for _ in 0..<40 { first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt) }
	cross := run_session.Tactical_Controller_Input{fire_right = true}
	first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, cross)
	testing.expect(t, room.first_person.shots == shots+3 && f.punch == .Cross, "the right button is not a cross")
}
