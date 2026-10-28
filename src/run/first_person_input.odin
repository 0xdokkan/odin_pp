package run

import "core:math"
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
// them: roguelike_scene.odin). The capture, the latched presses and the pause
// are every weapon's; the buttons go to the weapon in hand
// (route_first_person_buttons), and every weapon steps as the AK does until
// its own phase gives it its own moves.

// Radians the view turns for a pixel of the mouse, before the profile's
// sensitivity; a frame's move counts up to this many pixels.
FIRST_PERSON_MOUSE_SENSITIVITY :: f32(0.0022)
FIRST_PERSON_LOOK_CLAMP :: f32(300)
FIRST_PERSON_LOOK_SETTLE_FRAMES :: 2
// Shots committed at most in a frame (a frame's seconds carry one more at most).
FIRST_PERSON_FIRE_BATCHES :: 3
// FIRST PERSON BRAWLER: two presses of one movement key within this dash (the user's choice).
FIRST_PERSON_DOUBLE_TAP_SECONDS :: f64(0.25)

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
	controller.fire_latched, controller.right_latched = true, true
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

// The view's buttons this frame, read once for every weapon (as Half-Life's
// ItemPostFrame reads them before its weapon's attacks): each mouse button
// held with the mouse the view's, once any press of it from before has been
// let go and the dive is over; Shift and Ctrl as they are held then.
First_Person_Buttons :: struct {
	left, right, shift, ctrl: bool,
}

first_person_buttons :: proc(controller: ^Tactical_Controller, renderer: ^render.Renderer, room: ^game.Room,
	input: Tactical_Controller_Input) -> (buttons: First_Person_Buttons) {
	if !input.fire { controller.fire_latched = false }
	if !input.fire_right { controller.right_latched = false }
	if !game.tactical_first_person_active(room) || !controller.look_captured || render.first_person_diving(renderer) { return }
	buttons.left = input.fire && !controller.fire_latched
	buttons.right = input.fire_right && !controller.right_latched
	buttons.shift, buttons.ctrl = input.shift, input.ctrl
	return
}

// The buttons to the weapon in hand (docs/piano-prima-persona.md, sezione 4.2):
// the AK's trigger is the left button, whatever else is held; the fists' are
// presses (drive_first_person_fists); the sword's and the bow's wait for their
// phases (4 and 6) and do nothing yet.
route_first_person_buttons :: proc(room: ^game.Room, buttons: First_Person_Buttons) {
	switch room.first_person.weapon {
	case .AK: game.first_person_set_trigger(room, buttons.left)
	case .Fists, .Sword, .Bow:
	}
}

// The way the movement keys held move the body, turned with the view (W
// forward, D right, S back, A left; `yaw` on the board), and the way each key
// alone points.
first_person_fists_ways :: proc(walk: [4]bool, yaw: f32) -> (wish: [2]f32, keys: [4][2]f32) {
	forward := [2]f32{math.cos(yaw), math.sin(yaw)}
	right := [2]f32{-forward.y, forward.x}
	keys = {forward, right, -forward, -right}
	for held, index in walk { if held { wish += keys[index] } }
	if length := math.sqrt(wish.x*wish.x+wish.y*wish.y); length > 1 { wish /= length }
	return
}

// FIRST PERSON BRAWLER's frame (game/first_person_fists.odin): the movement keys
// turned with the view, Space a jump, a movement key pressed twice within
// FIRST_PERSON_DOUBLE_TAP_SECONDS a dash its way, a button pressed a punch (with
// Shift a hook), along the view; committed as a world command of the frame's
// `seconds`. Nothing while the mouse is not the view's or the camera dives.
drive_first_person_fists :: proc(controller: ^Tactical_Controller, room: ^game.Room, renderer: ^render.Renderer,
	cards: ^Card_Interaction_State, input: Tactical_Controller_Input, buttons: First_Person_Buttons, seconds: f32,
	playtest: ^combatdebug.Playtest_Session) {
	controller.fists_clock += f64(max(f32(0), seconds))
	left, right := buttons.left && !controller.fists_left, buttons.right && !controller.fists_right
	controller.fists_left, controller.fists_right = buttons.left, buttons.right
	if !game.first_person_fists_active(room) || !controller.look_captured || render.first_person_diving(renderer) { return }
	yaw := renderer.tactical.first_person.yaw
	wish, keys := first_person_fists_ways(input.walk, yaw)
	fists := game.First_Person_Fists_Input{wish = wish, jump = input.jump, look = keys[0],
		punch = game.first_person_punch_for(left, right, buttons.shift), aim = render.first_person_aim(renderer)}
	for pressed, index in input.directions {
		if !pressed { continue }
		if controller.fists_clock-controller.fists_taps[index] <= FIRST_PERSON_DOUBLE_TAP_SECONDS {
			fists.dash, fists.look = true, keys[index]
			controller.fists_taps[index] = -1e9
		} else {
			controller.fists_taps[index] = controller.fists_clock
		}
	}
	command := Gameplay_Command{kind = .First_Person_Fists, origin_phase = .Combat, fists = fists, seconds = seconds}
	_ = commit_gameplay_command(room, renderer, cards, command, playtest)
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
		controller.fire_latched, controller.right_latched = true, true
	}
	game.first_person_set_trigger(room, false)
	sync_first_person_cursor(controller)
}
