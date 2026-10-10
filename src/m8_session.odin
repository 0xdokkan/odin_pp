package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import game "game"
import host "engine/host"
import render "render"
import view "view"
import rl "vendor:raylib"

M8_PROFILE_PATH :: "odin_pp_profile.json"
M8_Profile_File :: struct { version: int, progress: game.M8_Profile }
M8_Session :: struct {
	character_open, save_enabled: bool,
	requested: render.M8_Control,
	ring_pending: bool,
	// M8 progression receipt only; the live ring simulation belongs to fight.
	ring: game.Ring_Challenge,
	reward: game.Ring_Reward,
	status: string,
}

M8_Session_Input :: struct {
	focused, inside, pressed, escape: bool,
	mouse: view.Vec2,
}

// Object controls have one input path: an enabled button's left-click edge.
m8_pointer_gameplay_command :: proc(room: ^game.Room, renderer: ^render.Renderer,
	mouse: view.Vec2, inside, pressed, available: bool) -> (Gameplay_Command, bool) {
	if !inside || !pressed || !available { return {}, false }
	switch render.m8_control_at_point(renderer, room, mouse) {
	case .Activate: return {kind = .Activate, origin_phase = room.phase}, true
	case .Equip: return {kind = .Equip, origin_phase = room.phase}, true
	case .None, .Character, .Ring, .FPS:
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
		pressed = rl.IsMouseButtonPressed(.LEFT), escape = rl.IsKeyPressed(.ESCAPE)}
	consumed := step_m8_session(session, room, renderer, controller, cards, buffer, available, dt, input)
	return consumed
}

step_m8_session :: proc(session: ^M8_Session, room: ^game.Room, renderer: ^render.Renderer,
	controller: ^Tactical_Controller, cards: ^Card_Interaction_State,
	buffer: ^Buffered_Gameplay_Command, available: bool, dt: f32, input: M8_Session_Input) -> bool {
	if session.requested != .None || session.ring_pending {return true}
	if !available || !input.focused { return session.character_open }
	left_click := input.inside && input.pressed
	if session.character_open {
		if input.escape || left_click && render.point_in_rectangle(input.mouse, render.m8_modal_control_bounds(renderer, .Close_Character)) { session.character_open = false }
		return true
	}
	if controller.paused || controller.hologram || room.qte.kind != .None ||
	   (room.phase != .Combat && room.phase != .Loot) ||
	   game.tactical_is_casting(room) || render.renderer_timeline_is_busy(renderer) { return false }
	clicked: render.M8_Control
	if left_click { clicked = render.m8_control_at_point(renderer, room, input.mouse) }
	if clicked == .Character { session.character_open = true }
	if clicked == .Ring && room.phase == .Loot {
		started: bool
		session.ring, started = game.begin_ring_challenge(room)
		if started {session.requested=.Ring; session.ring_pending=true}
		session.reward = {}
		session.status = ""
	}
	if clicked == .FPS {session.requested=.FPS}
	if session.character_open || session.requested != .None {
		clear_card_interaction(cards)
		clear_gameplay_command_buffer(buffer)
		return true
	}
	return false
}

// Accept only the outstanding ring receipt. Standalone victories and foreign
// results cannot unlock cards, and closing a won result cannot pay twice.
settle_m8_host_activity :: proc(session: ^M8_Session, room: ^game.Room, from: string, result: Maybe(host.Result)) -> bool {
    if !session.ring_pending || from != "ring" {return false}
    r, has := result.?
    if has && r.minigame != "ring" {return false}
    session.ring_pending=false
    session.requested=.None
    session.ring.phase=.Won if has && r.outcome==.Won else .Lost
    session.reward=game.settle_ring_challenge(room,&session.ring)
    session.status=""
    if session.reward.won && session.save_enabled && !save_m8_profile(M8_PROFILE_PATH,room.player.m8_profile) {
        session.status="Salvataggio non riuscito: progressi validi per questa sessione."
    }
    return true
}
