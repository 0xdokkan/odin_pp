package integration

import run_session "../run"
import "core:testing"
import game "../game"
import level "../level"
import render "../render"

// The keys of every weapon (docs/piano-prima-persona.md, Fase 1): the capture,
// the presses held from before and the pause are the AK's for all; the AK's
// trigger is the left button, the others' buttons do nothing yet.

// The room of the AK's controller tests with `weapon` taken up, the camera in
// his eyes.
first_person_weapon_controller_begin :: proc(t: ^testing.T, room: ^game.Room, renderer: ^render.Renderer, weapon: game.First_Person_Weapon) {
	testing.expect(t, game.tactical_begin_first_person(room, 20, weapon))
	view := &renderer.tactical.first_person
	view.engaged, view.amount, view.yaw = true, 1, 0
}

// The right button and Ctrl reach the controller from the native input.
@(test)
test_first_person_input_reads_the_right_button_and_ctrl :: proc(t: ^testing.T) {
	controller: run_session.Tactical_Controller
	controls := run_session.Run_Input{focused = true, left_down = true, right_down = true}
	controls.actions.down += {.Arrow_Aim, .Dodge_Modifier}
	input := run_session.tactical_controller_input(&controller, nil, controls, {}, false)
	testing.expect(t, input.fire && input.fire_right && input.ctrl && input.shift)
	input = run_session.tactical_controller_input(&controller, nil, {focused = true}, {}, false)
	testing.expect(t, !input.fire && !input.fire_right && !input.ctrl && !input.shift)
}

// For every weapon: both buttons already down as the view takes the mouse
// count for nothing until each is let go; then each counts on its own, with
// Shift and Ctrl; never while the camera dives. Only the AK's left button is a
// trigger: the others fire nothing in a second of both buttons held.
@(test)
test_first_person_buttons_latch_and_route_for_every_weapon :: proc(t: ^testing.T) {
	for weapon in game.First_Person_Weapon {
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
		first_person_weapon_controller_begin(t, &room, renderer, weapon)
		testing.expect_value(t, room.first_person.weapon, weapon)
		both := run_session.Tactical_Controller_Input{fire = true, fire_right = true}
		for _ in 0..<5 { first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, both) }
		testing.expect(t, controller.look_captured && controller.fire_latched && controller.right_latched)
		testing.expect(t, room.first_person.shots == 0 && !room.first_person.trigger)
		testing.expect_value(t, run_session.first_person_buttons(&controller, renderer, &room, both), run_session.First_Person_Buttons{})
		// The left let go: it counts again, the right still held does not.
		left := run_session.Tactical_Controller_Input{fire_right = true}
		testing.expect_value(t, run_session.first_person_buttons(&controller, renderer, &room, left), run_session.First_Person_Buttons{})
		testing.expect(t, !controller.fire_latched && controller.right_latched)
		testing.expect_value(t, run_session.first_person_buttons(&controller, renderer, &room, both), run_session.First_Person_Buttons{left = true})
		// The right let go too: both count, with the keys held.
		run_session.first_person_buttons(&controller, renderer, &room, {})
		testing.expect(t, !controller.right_latched)
		keyed := run_session.Tactical_Controller_Input{fire = true, fire_right = true, shift = true, ctrl = true}
		testing.expect_value(t, run_session.first_person_buttons(&controller, renderer, &room, keyed),
			run_session.First_Person_Buttons{left = true, right = true, shift = true, ctrl = true})
		// The camera still diving: nothing.
		renderer.tactical.first_person.amount = 0.5
		testing.expect_value(t, run_session.first_person_buttons(&controller, renderer, &room, keyed), run_session.First_Person_Buttons{})
		renderer.tactical.first_person.amount = 1
		// A second of both buttons: the AK's six shots, nobody else's.
		for _ in 0..<60 { first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, both) }
		testing.expect_value(t, room.first_person.shots, i32(6) if weapon == .AK else 0)
		testing.expect_value(t, room.first_person.trigger, weapon == .AK)
	}
}

// For every weapon a pause gives the mouse back and lets go of both buttons;
// the resume takes it again, and the buttons still down from the pause count
// for nothing until let go. The view over, the buttons are nothing.
@(test)
test_first_person_pause_latches_both_buttons_for_every_weapon :: proc(t: ^testing.T) {
	for weapon in game.First_Person_Weapon {
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
		first_person_weapon_controller_begin(t, &room, renderer, weapon)
		for _ in 0..<2 { first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt) }
		testing.expect(t, controller.look_captured && !controller.fire_latched && !controller.right_latched)
		pause := run_session.Tactical_Controller_Input{pause = true, fire = true, fire_right = true}
		first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, pause)
		testing.expect(t, controller.paused && !controller.look_captured && !room.first_person.trigger)
		testing.expect(t, controller.fire_latched && controller.right_latched)
		first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, pause)
		testing.expect(t, !controller.paused && controller.look_captured)
		both := run_session.Tactical_Controller_Input{fire = true, fire_right = true}
		for _ in 0..<5 { first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt, both) }
		testing.expect(t, controller.fire_latched && controller.right_latched && room.first_person.shots == 0)
		first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt)
		testing.expect_value(t, run_session.first_person_buttons(&controller, renderer, &room, both), run_session.First_Person_Buttons{left = true, right = true})
		// The view over: given back, and the buttons are nothing.
		room.first_person.remaining = 0.01
		first_person_controller_frame(&controller, &room, renderer, &cards, &held, dt)
		testing.expect(t, !game.tactical_first_person_active(&room) && !controller.look_captured)
		testing.expect_value(t, run_session.first_person_buttons(&controller, renderer, &room, both), run_session.First_Person_Buttons{})
	}
}
