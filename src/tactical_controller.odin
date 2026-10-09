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
	focused, pause, shift: bool,
	directions: [4]bool,
	diagonals: [4]bool,
	defenses: [4]bool,
	map_input: Tactical_Map_Input,
}

buffer_tactical_walk_input :: proc(buffer: ^Buffered_Gameplay_Command, phase: game.Room_Phase, directions: [4]bool) {
	for pressed, index in directions {
		if pressed {
			offer_gameplay_command(buffer, {kind = .Move, origin_phase = phase, direction = game.Move_Direction(index)})
			break
		}
	}
}

// The decision clock and QTE deadline are independent of presentation speed.
// A window boundary cancels old input, then permits a fresh recovery walk.
update_tactical_controller :: proc(
	controller: ^Tactical_Controller, room: ^game.Room, renderer: ^render.Renderer,
	cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command,
	dt: f32, available: bool, mouse: view.Vec2, inside: bool, playtest: ^combatdebug.Playtest_Session,
) -> (blocks_input: bool) {
	input := Tactical_Controller_Input{
		focused = rl.IsWindowFocused(), pause = rl.IsKeyPressed(.P),
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
	if input.pause {
		controller.paused = !controller.paused
		clear_card_interaction(cards)
		clear_gameplay_command_buffer(buffer)
		renderer.frame_clock_valid = false
		// Neither pause edge owns elapsed gameplay time or a rendered cast frame.
		return true
	}
	if controller.paused { return true }
	simulation_dt := dt
	cinematic_input := render.presentation_time_policy(&renderer.timeline) == .Cinematic ||
		(renderer.frame_clock_valid && renderer.frame_had_cinematic)
	// Consume the renderer's exact non-cinematic slice. Dice may begin/end
	// partway through this frame; no pulse or world debt accrues inside them.
	if renderer.frame_clock_valid {
		simulation_dt = min(max(f32(0), dt), renderer.frame_simulation_dt)
		renderer.frame_clock_valid = false
	} else if render.presentation_time_policy(&renderer.timeline) == .Cinematic {
		return true
	}
	if game.tactical_is_casting(room) {
		clear_gameplay_command_buffer(buffer)
		game.tactical_tick(room, simulation_dt, true, false)
		return true
	}
	if cinematic_input { return true }
	map_toggled := update_tactical_map_controls(controller, room, renderer, cards, buffer, input.map_input)
	command := Gameplay_Command{origin_phase = .Combat}
	if room.qte.kind != .None {
		controller.hologram = false
		clear_gameplay_command_buffer(buffer)
		room.qte.remaining = max(f32(0), room.qte.remaining-simulation_dt)
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
		if command.kind != .None {
			clear_card_interaction(cards)
			commit_gameplay_command(room, renderer, cards, command, playtest)
		}
		return true
	}
	// Resolve due gameplay atomically, then let the pictures run independently.
	// The real clock also advances during the player's own animation; only its
	// input lane waits for that animation. Never reuse this frame's key for a
	// defense QTE which has just appeared while resolving the world.
	if !drain_tactical_world_commands(room, renderer, cards, playtest) {
		if room.qte.kind != .None {
			controller.hologram = false
			clear_card_interaction(cards)
			clear_gameplay_command_buffer(buffer)
		}
		return true
	}
	game.tactical_tick(room, simulation_dt, true, controller.hologram)
	if !drain_tactical_world_commands(room, renderer, cards, playtest) {
		if room.qte.kind != .None {
			controller.hologram = false
			clear_card_interaction(cards)
			clear_gameplay_command_buffer(buffer)
		}
		return true
	}
	// Expiration is checked after all paid beats, including the last second.
	if game.tactical_tick(room, 0, true, controller.hologram) {
		controller.hologram = false
		clear_card_interaction(cards)
		clear_gameplay_command_buffer(buffer)
		if !commit_gameplay_command(room, renderer, cards, {kind = .Timeout, origin_phase = .Combat}, playtest) { return true }
		// A fresh walk on this exact boundary is already a recovery walk.
		// Discarded targeting or old buffered commands cannot cross with it.
	}
	if game.tactical_is_recovering(room) {
		cards.selected_card_id = 0
		cards.dragged_card_id = 0
	}
	movement_buffer_allowed := !controller.hologram && !map_toggled &&
		(room.phase == .Loot || (room.phase == .Combat && game.tactical_allows_movement(room)))
	if !movement_buffer_allowed || (buffer.occupied && buffer.command.origin_phase != room.phase) {
		clear_gameplay_command_buffer(buffer)
	}
	if render.renderer_blocks_player_input(renderer) {
		if movement_buffer_allowed && !input.shift && cards.dragged_card_id == 0 {
			buffer_tactical_walk_input(buffer, room.phase, input.directions)
		}
		return true
	}
	if !controller.hologram && room.phase == .Combat && room.player.tactical.phase == .Decision {
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
		clear_gameplay_command_buffer(buffer)
		commit_gameplay_command(room, renderer, cards, command, playtest)
		return true
	}
	return map_toggled || controller.hologram || room.qte.kind != .None
}

// One beat contains a start, at most one command per enemy, and a finish.
// The extra beat accounts for debt already started before a defense QTE.
// Backpressure leaves authoritative gameplay untouched until cues have space.
drain_tactical_world_commands :: proc(room: ^game.Room, renderer: ^render.Renderer,
	cards: ^Card_Interaction_State, playtest: ^combatdebug.Playtest_Session) -> bool {
	budget := (max(0, room.player.tactical.queued_beats)+1)*(game.MAX_ENEMIES_PER_ROOM+2)
	for _ in 0..<budget {
		if room.qte.kind != .None { return false }
		if room.phase != .Combat || !room.tactical_pulse.pending { return true }
		if !commit_gameplay_command(room, renderer, cards,
			{kind = .Continue_Pulse, origin_phase = .Combat}, playtest) { return false }
	}
	return room.qte.kind == .None && !room.tactical_pulse.pending
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
