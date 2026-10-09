package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import game "game"
import render "render"
import view "view"
import rl "vendor:raylib"

M8_PROFILE_PATH :: "odin_pp_profile.json"
M8_Profile_File :: struct { version: int, progress: game.M8_Profile }
M8_Session :: struct {
	character_open, ring_open, save_enabled: bool,
	ring: game.Ring_Challenge,
	reward: game.Ring_Reward,
	status: string,
}

M8_Session_Input :: struct {
	focused, inside, pressed: bool,
	mouse: view.Vec2,
	ring_left, ring_right, ring_jab, ring_dodge, ring_grab: bool,
}

// Object controls have one input path: an enabled button's left-click edge.
m8_pointer_gameplay_command :: proc(room: ^game.Room, renderer: ^render.Renderer,
	mouse: view.Vec2, inside, pressed, available: bool) -> (Gameplay_Command, bool) {
	if !inside || !pressed || !available { return {}, false }
	switch render.m8_control_at_point(renderer, room, mouse) {
	case .Activate: return {kind = .Activate, origin_phase = room.phase}, true
	case .Equip: return {kind = .Equip, origin_phase = room.phase}, true
	case .None, .Character, .Ring:
	}
	return {}, false
}

load_m8_profile :: proc(path: string) -> (game.M8_Profile, bool) {
	if !os.exists(path) { return {}, true }
	data, error := os.read_entire_file(path, context.allocator)
	if error != nil { return {}, false }
	defer delete(data)
	if len(data) > 4096 { return {}, false }
	file: M8_Profile_File
	if json.unmarshal(data, &file) != nil || file.version != game.M8_PROFILE_VERSION ||
	   !game.m8_profile_valid(file.progress) { return {}, false }
	return file.progress, true
}

save_m8_profile :: proc(path: string, profile: game.M8_Profile) -> bool {
	if !game.m8_profile_valid(profile) { return false }
	data, error := json.marshal(M8_Profile_File{game.M8_PROFILE_VERSION, profile})
	if error != nil { return false }
	defer delete(data)
	temporary := fmt.tprintf("%s.tmp", path)
	if os.write_entire_file(temporary, data) != nil { return false }
	return os.rename(temporary, path) == nil
}

// Modals own input, arena clocks and presentation until explicitly closed.
update_m8_session :: proc(session: ^M8_Session, room: ^game.Room, renderer: ^render.Renderer,
	controller: ^Tactical_Controller, cards: ^Card_Interaction_State,
	buffer: ^Buffered_Gameplay_Command, available: bool, dt: f32, mouse: view.Vec2, inside: bool) -> bool {
	input := M8_Session_Input{focused = rl.IsWindowFocused(), inside = inside, mouse = mouse,
		pressed = rl.IsMouseButtonPressed(.LEFT), ring_left = rl.IsKeyPressed(.A), ring_right = rl.IsKeyPressed(.D),
		ring_jab = rl.IsKeyPressed(.ONE), ring_dodge = rl.IsKeyPressed(.TWO), ring_grab = rl.IsKeyPressed(.THREE)}
	return step_m8_session(session, room, renderer, controller, cards, buffer, available, dt, input)
}

step_m8_session :: proc(session: ^M8_Session, room: ^game.Room, renderer: ^render.Renderer,
	controller: ^Tactical_Controller, cards: ^Card_Interaction_State,
	buffer: ^Buffered_Gameplay_Command, available: bool, dt: f32, input: M8_Session_Input) -> bool {
	if !available || !input.focused { return session.character_open || session.ring_open }
	left_click := input.inside && input.pressed
	if session.ring_open {
		leave := left_click && render.point_in_rectangle(input.mouse, render.m8_modal_control_bounds(renderer, .Leave_Ring))
		if session.ring.phase == .Active {
			if leave { session.ring.phase = .Lost }
			else {
				if input.ring_left { game.ring_command(&session.ring, .Left) }
				if input.ring_right { game.ring_command(&session.ring, .Right) }
				if input.ring_jab { game.ring_command(&session.ring, .Jab) }
				if input.ring_dodge { game.ring_command(&session.ring, .Dodge) }
				if input.ring_grab { game.ring_command(&session.ring, .Grab) }
				game.tick_ring(&session.ring, dt)
			}
		}
		if session.ring.phase != .Active && !session.ring.settled {
			session.reward = game.settle_ring_challenge(room, &session.ring)
			if session.reward.won {
				if !session.save_enabled || !save_m8_profile(M8_PROFILE_PATH, room.player.m8_profile) {
					session.status = "Salvataggio non riuscito: progressi validi per questa sessione."
					fmt.eprintln(session.status)
				} else { session.status = "Progressi salvati." }
			}
		}
		if session.ring.phase != .Active && leave { session.ring_open = false }
		return true
	}
	if session.character_open {
		if left_click && render.point_in_rectangle(input.mouse, render.m8_modal_control_bounds(renderer, .Close_Character)) { session.character_open = false }
		return true
	}
	if controller.paused || controller.hologram || room.qte.kind != .None ||
	   (room.phase != .Combat && room.phase != .Loot) ||
	   game.tactical_is_casting(room) || render.renderer_timeline_is_busy(renderer) { return false }
	clicked: render.M8_Control
	if left_click { clicked = render.m8_control_at_point(renderer, room, input.mouse) }
	if clicked == .Character { session.character_open = true }
	if clicked == .Ring && room.phase == .Loot {
		session.ring, session.ring_open = game.begin_ring_challenge(room)
		session.reward = {}
		session.status = ""
	}
	if session.character_open || session.ring_open {
		clear_card_interaction(cards)
		clear_gameplay_command_buffer(buffer)
		return true
	}
	return false
}
