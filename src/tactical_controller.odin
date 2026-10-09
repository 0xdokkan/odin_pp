package main

import "core:fmt"
import rl "vendor:raylib"
import game "game"
import grid "grid"
import view "view"
import render "render"
import combatdebug "combatdebug"

Tactical_Controller :: struct {
	hologram, paused, was_focused: bool,
}

M7_INPUT_TRACE :: #config(M7_INPUT_TRACE, false)

Tactical_Controller_Input :: struct {
	focused, pause, end_preparation, shift: bool,
	directions: [4]bool,
	diagonals: [4]bool,
	defenses: [4]bool,
	map_input: Tactical_Map_Input,
}

// The decision clock and QTE deadline are independent of presentation speed.
// Timeout wins at the boundary; no second command can be issued in that frame.
update_tactical_controller :: proc(
	controller: ^Tactical_Controller, room: ^game.Room, renderer: ^render.Renderer,
	cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command,
	dt: f32, available: bool, mouse: view.Vec2, inside: bool, playtest: ^combatdebug.Playtest_Session,
) -> (blocks_input: bool) {
	input := Tactical_Controller_Input{
		focused = rl.IsWindowFocused(), pause = rl.IsKeyPressed(.P), end_preparation = rl.IsKeyPressed(.ENTER),
		shift = rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT),
		map_input = {mouse = mouse, inside = inside, toggle = rl.IsKeyPressed(.TAB), close = rl.IsKeyPressed(.ESCAPE),
			reset = rl.IsKeyPressed(.R), pressed = rl.IsMouseButtonPressed(.LEFT), down = rl.IsMouseButtonDown(.LEFT),
			wheel = rl.GetMouseWheelMove()},
	}
	for key, index in ([?]rl.KeyboardKey{.W, .D, .S, .A}) { input.directions[index] = rl.IsKeyPressed(key) }
	for key, index in ([?]rl.KeyboardKey{.Q, .E, .Z, .C}) { input.diagonals[index] = rl.IsKeyPressed(key) }
	for key, index in ([?]rl.KeyboardKey{.J, .K, .L, .I}) { input.defenses[index] = rl.IsKeyPressed(key) }
	blocked := step_tactical_controller(controller, room, renderer, cards, buffer, dt, available, input, playtest)
	if M7_INPUT_TRACE {
		if input.directions != ([4]bool{}) || input.pause || input.map_input.toggle {
			cue, has_cue := render.active_presentation_cue(&renderer.timeline)
			elapsed, duration := f32(0), f32(0)
			if has_cue { elapsed, duration = cue.elapsed, cue.duration }
			fmt.printf("M7 input: keys=%v shift=%v focused=%v available=%v paused=%v map=%v blocked=%v room=%v tactical=%v pending=%v qte=%v qte_clock=%.3f clock=%.3f dt=%.6f timeline=%d/%d cue=%.6f/%.6f drag=%d deck_active=%v buffered=%v position=%v\n",
				input.directions, input.shift, input.focused, available, controller.paused, controller.hologram, blocked,
				room.phase, room.player.tactical.phase, room.tactical_pulse.pending, room.qte.kind,
				room.qte.remaining, room.player.tactical.remaining, dt, renderer.timeline.head, renderer.timeline.count,
				elapsed, duration, cards.dragged_card_id, room.player.deck.combat_active, buffer.occupied, room.player.position)
			for pressed, index in input.directions {
				if !pressed { continue }
				destination := game.add_position(room.player.position, game.direction_offset(game.Move_Direction(index)))
				query := game.query_entity_movement(room, game.PLAYER_ENTITY, destination)
				fmt.printf("M7 destination: direction=%v cell=%v query=%v\n", game.Move_Direction(index), destination, query.error)
			}
		}
	}
	return blocked
}

// The native input snapshot also drives headless lifecycle regressions.
step_tactical_controller :: proc(
	controller: ^Tactical_Controller, room: ^game.Room, renderer: ^render.Renderer,
	cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command,
	dt: f32, available: bool, input: Tactical_Controller_Input, playtest: ^combatdebug.Playtest_Session = nil,
) -> (blocks_input: bool) {
	if !game.tactical_enabled(room) { return false }
	if !available { controller.hologram = false; clear_gameplay_command_buffer(buffer); return true }
	if !input.focused {
		controller.was_focused = false
		clear_gameplay_command_buffer(buffer)
		renderer.tactical.hologram_orbit.dragging = false
		renderer.tactical.world_orbit.dragging = false
		return true
	}
	// Do not charge the first resumed frame for time spent outside the window.
	if !controller.was_focused { controller.was_focused = true; return true }
	if input.pause { controller.paused = !controller.paused; clear_card_interaction(cards); clear_gameplay_command_buffer(buffer) }
	if controller.paused { return true }
	busy := render.renderer_timeline_is_busy(renderer)
	map_toggled := update_tactical_map_controls(controller, room, renderer, cards, buffer, input.map_input)
	// M7 owns input while the timeline plays, so the ordinary poll below main's
	// controller call cannot see a one-frame press. Preserve one walk through a
	// normal response pulse; never carry it across an interaction/rules boundary.
	movement_buffer_allowed := !controller.hologram && !map_toggled && room.qte.kind == .None &&
		(room.phase == .Loot || (room.phase == .Combat &&
		 (room.player.tactical.phase == .Decision || room.player.tactical.phase == .Resolving)))
	if !movement_buffer_allowed || (buffer.occupied && buffer.command.origin_phase != room.phase) {
		clear_gameplay_command_buffer(buffer)
	}
	if movement_buffer_allowed && (busy || room.tactical_pulse.pending) && !input.shift && cards.dragged_card_id == 0 {
		for pressed, index in input.directions {
			if pressed {
				offer_gameplay_command(buffer, {kind = .Move, origin_phase = room.phase, direction = game.Move_Direction(index)})
				break
			}
		}
	}
	if busy { return true }
	command := Gameplay_Command{origin_phase = .Combat}
	if room.qte.kind != .None {
		controller.hologram = false
		room.qte.remaining = max(f32(0), room.qte.remaining-dt)
		if room.qte.remaining <= 0 { command.kind = .QTE_Fail }
		else if !room.qte.selected {
			for pressed, index in input.defenses {
				if pressed { command.kind = .Defense; command.defense = game.Defense_Mode(index); break }
			}
		} else {
			for pressed, index in input.directions {
				if pressed { command.kind = .QTE_Key; command.direction = game.Move_Direction(index); break }
			}
		}
	} else if room.tactical_pulse.pending || (room.phase == .Combat && room.player.tactical.phase == .Forced) {
		command.kind = .Continue_Pulse
	} else if game.tactical_tick(room, dt, true, controller.hologram) {
		command.kind = .Timeout
		controller.hologram = false
	} else if room.phase == .Combat && room.player.tactical.phase == .Preparation && input.end_preparation {
		command.kind = .End_Preparation
	} else if !controller.hologram && room.phase == .Combat && room.player.tactical.phase == .Decision {
		if input.shift {
			for pressed, index in input.directions {
				if pressed { command.kind = .Dodge; command.direction = game.Move_Direction(index); break }
			}
		}
		offsets := [?]grid.Position{{-1, -1}, {1, -1}, {-1, 1}, {1, 1}}
		for pressed, index in input.diagonals {
			if command.kind == .None && pressed { command.kind = .Begin_Diagonal; command.offset = offsets[index]; break }
		}
	}
	if command.kind != .None {
		clear_card_interaction(cards)
		if command.kind != .Continue_Pulse { clear_gameplay_command_buffer(buffer) }
		commit_gameplay_command(room, renderer, cards, command, playtest)
		return true
	}
	return map_toggled || controller.hologram || room.qte.kind != .None
}

Tactical_Map_Input :: struct {
	mouse: view.Vec2,
	inside, toggle, close, reset, pressed, down: bool,
	wheel: f32,
}

// Pure input routing, shared by the native window and headless regressions.
// The caller still advances tactical_tick while the map consumes mouse input.
update_tactical_map_controls :: proc(controller: ^Tactical_Controller, room: ^game.Room, renderer: ^render.Renderer,
	cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command, input: Tactical_Map_Input) -> bool {
	if room.qte.kind != .None { return false }
	map_clicked := input.inside && input.pressed && render.point_in_rectangle(input.mouse, render.tactical_map_button_bounds(renderer))
	toggled := input.toggle || map_clicked || (controller.hologram && input.close)
	if toggled {
		controller.hologram = !controller.hologram
		if controller.hologram { room.player.tactical.metrics.hologram_opens += 1 }
		clear_card_interaction(cards)
		clear_gameplay_command_buffer(buffer)
	}
	if controller.hologram {
		if input.reset || (input.inside && input.pressed && render.point_in_rectangle(input.mouse, render.tactical_map_reset_bounds())) {
			render.reset_tactical_orbit(&renderer.tactical.hologram_orbit)
		}
		render.update_tactical_orbit_pointer(&renderer.tactical.hologram_orbit, input.mouse,
			input.inside && render.point_in_rectangle(input.mouse, render.tactical_map_drag_bounds(renderer)), input.pressed, input.down, input.wheel)
	} else { renderer.tactical.hologram_orbit.dragging = false }
	return toggled
}
