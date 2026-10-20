package run

import rl "vendor:raylib"
import combatdebug "../combatdebug"
import game "../game"
import render "../render"

// FIRST PERSON SHOOTER's input (game/first_person.odin, render/first_person.odin).
// While the player is behind his eyes the mouse is the view's: raylib's cursor
// is hidden and held (the controller's look_captured, which the native frame
// follows: sync_first_person_cursor), its moves turn the view, and the left
// button held is the AK's trigger, its shots committed after the frame's beats
// as world commands, so his own step never holds them back. A press made
// before the view took the mouse (the click that resumes a pause, the card's
// own double click) fires nothing until it is let go; the first frames after
// the mouse is taken or given back never turn the view (the cursor's warp). It
// gives the mouse back on a pause (P, or Esc there), on losing focus, with a
// modal over the board and when the view ends. The scene's lane is left with
// steps and waits, W, A, S and D turned with the view; the hand, its keys, the
// map, the arrows and the HUD's buttons are off (the pointer never reaches
// them: roguelike_scene.odin).

// Radians the view turns for a pixel of the mouse, before the profile's
// sensitivity; a frame's move counts up to this many pixels.
FIRST_PERSON_MOUSE_SENSITIVITY :: f32(0.0022)
FIRST_PERSON_LOOK_CLAMP :: f32(300)
FIRST_PERSON_LOOK_SETTLE_FRAMES :: 2
// Shots committed at most in a frame (a frame's seconds carry one more at most).
FIRST_PERSON_FIRE_BATCHES :: 3

// P pauses; behind the player's eyes Esc too, so the mouse can be freed.
first_person_pause_pressed :: proc(room: ^game.Room, controls: Run_Input) -> bool {
	return run_pressed(controls, .Pause) || (game.tactical_first_person_active(room) && run_pressed(controls, .Cancel))
}

// Whether the view should hold the mouse after this frame: behind the
// player's eyes, the board available and focused, nothing paused.
first_person_wants_mouse :: proc(controller: ^Tactical_Controller, room: ^game.Room, available: bool,
	input: Tactical_Controller_Input) -> bool {
	return game.tactical_first_person_active(room) && available && input.focused && controller.was_focused && !controller.paused
}

// Takes the mouse or gives it back as the frame leaves things; either way the
// next frames' moves are not looks, and a held press is not a shot.
first_person_follow_capture :: proc(controller: ^Tactical_Controller, room: ^game.Room, available: bool,
	input: Tactical_Controller_Input) {
	want := first_person_wants_mouse(controller, room, available, input)
	if want == controller.look_captured { return }
	controller.look_captured = want
	controller.look_settle = FIRST_PERSON_LOOK_SETTLE_FRAMES
	controller.fire_latched = true
	if !want { game.first_person_set_trigger(room, false) }
}

// The mouse turns the view: right turns it right, up looks up.
turn_first_person_look :: proc(controller: ^Tactical_Controller, renderer: ^render.Renderer, room: ^game.Room,
	input: Tactical_Controller_Input) {
	if !controller.look_captured || !game.tactical_first_person_active(room) { return }
	if controller.look_settle > 0 {
		controller.look_settle -= 1
		return
	}
	sensitivity := FIRST_PERSON_MOUSE_SENSITIVITY*(input.sensitivity if input.sensitivity > 0 else 1)
	render.turn_first_person_view(renderer, input.look.x*sensitivity, -input.look.y*sensitivity)
}

// The AK's trigger this frame: the button held with the mouse the view's, once
// any press from before has been let go and the dive is over.
first_person_trigger :: proc(controller: ^Tactical_Controller, renderer: ^render.Renderer, room: ^game.Room,
	input: Tactical_Controller_Input) -> bool {
	if !input.fire { controller.fire_latched = false }
	return game.tactical_first_person_active(room) && controller.look_captured && input.fire && !controller.fire_latched &&
	       !render.first_person_diving(renderer)
}

// The shots due, each a world command along the view's aim; never into a full
// world bank (the next frame fires what is left).
drain_first_person_fire :: proc(room: ^game.Room, renderer: ^render.Renderer, cards: ^Card_Interaction_State,
	playtest: ^combatdebug.Playtest_Session) {
	for _ in 0..<FIRST_PERSON_FIRE_BATCHES {
		if !game.first_person_fire_due(room) { return }
		command := Gameplay_Command{kind = .First_Person_Fire, origin_phase = .Combat, aim = render.first_person_aim(renderer)}
		if !commit_gameplay_command(room, renderer, cards, command, playtest) { return }
	}
}

// The scene's lane behind the player's eyes: a step of a movement key turned
// with the view, Space to wait; Shift held leaves the key to the controller's
// dodge. Nothing else. Pure, for the tests.
first_person_lane_command :: proc(pressed: [4]bool, shift, wait: bool, keys: [4]game.Move_Direction) -> (Gameplay_Command, bool) {
	if shift { return {}, false }
	for down, index in pressed {
		if down { return {kind = .Move, origin_phase = .Combat, direction = keys[index]}, true }
	}
	if wait { return {kind = .Wait, origin_phase = .Combat}, true }
	return {}, false
}

// raylib's cursor follows the controller: hidden and held while the view has
// the mouse. Called each native frame, so a reset controller (F5) or a frame
// that skipped the controller gets it back.
sync_first_person_cursor :: proc(controller: ^Tactical_Controller) {
	if controller.look_captured == rl.IsCursorHidden() { return }
	if controller.look_captured { rl.DisableCursor() } else { rl.EnableCursor() }
}

// The view gives the mouse back at once (a modal over the board, the scene
// suspended): no shot is held either.
release_first_person_mouse :: proc(controller: ^Tactical_Controller, room: ^game.Room) {
	if controller.look_captured {
		controller.look_captured = false
		controller.look_settle = FIRST_PERSON_LOOK_SETTLE_FRAMES
		controller.fire_latched = true
	}
	game.first_person_set_trigger(room, false)
	sync_first_person_cursor(controller)
}
