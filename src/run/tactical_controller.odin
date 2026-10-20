package run

import "core:fmt"
import game "../game"
import grid "../engine/grid"
import view "../engine/view"
import render "../render"
import combatdebug "../combatdebug"

Tactical_Controller :: struct {
	hologram, paused, was_focused: bool,
	// FIRST PERSON SHOOTER (first_person_input.odin): the mouse is the view's
	// (raylib's cursor hidden and held: update_tactical_controller follows
	// this), the frames left before its moves turn the view, and a press made
	// before the view took the mouse, which fires nothing until it is let go.
	look_captured: bool,
	look_settle: int,
	fire_latched: bool,
}

M7_INPUT_TRACE :: #config(M7_INPUT_TRACE, false)

Tactical_Controller_Input :: struct {
	focused, pause, shift: bool,
	directions: [4]bool,
	diagonals: [4]bool,
	defenses: [4]bool,
	map_input: Tactical_Map_Input,
	// FIRST PERSON SHOOTER: the mouse's move this frame in pixels (only while
	// the view has the mouse), the left button held, and the profile's mouse
	// sensitivity (0: as it comes).
	look: [2]f32,
	fire: bool,
	sensitivity: f32,
}

// The decision clock and QTE deadline are independent of presentation speed.
// A window boundary cancels old input, then permits a fresh recovery walk.
update_tactical_controller :: proc(
	controller: ^Tactical_Controller, room: ^game.Room, renderer: ^render.Renderer,
	cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command,
	dt: f32, available: bool, mouse: view.Vec2, inside: bool, playtest: ^combatdebug.Playtest_Session,
	controls: Run_Input, sensitivity: f32 = 1,
) -> (blocks_input: bool) {
	input := tactical_controller_input(controller, room, controls, mouse, inside, sensitivity)
	blocked := step_tactical_controller(controller, room, renderer, cards, buffer, dt, available, input, playtest)
	sync_first_person_cursor(controller)
	if M7_INPUT_TRACE {
		if input.directions != ([4]bool{}) || input.pause || input.map_input.toggle {
			cue, has_cue := render.active_presentation_cue(&renderer.timeline)
			elapsed, duration := f32(0), f32(0)
			if has_cue { elapsed, duration = cue.elapsed, cue.duration }
			fmt.printf("M7 input: keys=%v shift=%v focused=%v available=%v paused=%v map=%v blocked=%v room=%v tactical=%v pending=%v qte=%v qte_clock=%.3f clock=%.3f dt=%.6f timeline=%d/%d cue=%.6f/%.6f drag=%d deck_active=%v chord=%v position=%v\n",
				input.directions, input.shift, input.focused, available, controller.paused, controller.hologram, blocked,
				room.phase, room.player.tactical.phase, room.tactical_pulse.pending, room.qte.kind,
				room.qte.remaining, room.player.tactical.remaining, dt, renderer.timeline.head, renderer.timeline.count,
				elapsed, duration, cards.dragged_card_id, room.player.deck.combat_active, buffer.chord.active, room.player.position)
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

// Pure adapter shared by native input and lifecycle regressions. Cursor capture
// still follows the stepped controller, after this frame's sampled delta.
tactical_controller_input :: proc(controller: ^Tactical_Controller, room: ^game.Room,
	controls: Run_Input, mouse: view.Vec2, inside: bool, sensitivity: f32 = 1) -> Tactical_Controller_Input {
	input := Tactical_Controller_Input{
		// Behind the player's eyes Esc pauses too, and gives the mouse back.
		focused = controls.focused, pause = first_person_pause_pressed(room, controls),
		shift = run_down(controls, .Dodge_Modifier),
		map_input = {mouse = mouse, inside = inside, toggle = run_pressed(controls, .Map), close = run_pressed(controls, .Cancel),
			reset = run_pressed(controls, .Recenter), pressed = controls.left_pressed, down = controls.left_down,
			wheel = controls.wheel},
		fire = controls.left_down, sensitivity = sensitivity,
	}
	if controller.look_captured {
		delta := controls.mouse_motion
		input.look = {clamp(delta.x, -FIRST_PERSON_LOOK_CLAMP, FIRST_PERSON_LOOK_CLAMP), clamp(delta.y, -FIRST_PERSON_LOOK_CLAMP, FIRST_PERSON_LOOK_CLAMP)}
	}
	for action, index in RUN_WALK_ACTIONS { input.directions[index] = run_pressed(controls, action) }
	for action, index in RUN_DIAGONAL_ACTIONS { input.diagonals[index] = run_pressed(controls, action) }
	// Block, parry, deflect, dodge. The dodge sits by WASD, which then picks
	// its landing; the diagonal keys are not read during a defence.
	for action, index in RUN_DEFENSE_ACTIONS { input.defenses[index] = run_pressed(controls, action) }
	return input
}

// The native input snapshot also drives headless lifecycle regressions.
step_tactical_controller :: proc(
	controller: ^Tactical_Controller, room: ^game.Room, renderer: ^render.Renderer,
	cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command,
	dt: f32, available: bool, input: Tactical_Controller_Input, playtest: ^combatdebug.Playtest_Session = nil,
) -> (blocks_input: bool) {
	if room == nil || room.player == nil { return false }
	// The view behind the player's eyes takes the mouse, or gives it back, as
	// this frame leaves things (first_person_input.odin).
	defer first_person_follow_capture(controller, room, available, input)
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
	// The eyes turn whatever the world does: they are no action.
	turn_first_person_look(controller, renderer, room, input)
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
	// Movimento Ombra: the world is frozen and only the shadow's clock runs,
	// and not while the card's own sinking cue still owns the player's input.
	// Its end is an explicit command, like a timeout; meanwhile the scene's
	// lane walks the shadow with ordinary moves, tick chord included.
	if game.tactical_shadow_active(room) {
		if render.renderer_blocks_player_input(renderer) {
			clear_gameplay_command_buffer(buffer)
			return true
		}
		game.tactical_tick(room, simulation_dt, true, controller.hologram)
		if game.tactical_shadow_due(room) {
			controller.hologram = false
			clear_card_interaction(cards)
			clear_gameplay_command_buffer(buffer)
			commit_gameplay_command(room, renderer, cards, {kind = .Shadow_Emerge, origin_phase = .Combat}, playtest)
			return true
		}
		return map_toggled || controller.hologram
	}
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
			// A key the panel names is its own letter; a dodge's landing turns
			// with the view behind the player's eyes.
			keys := game.MOVEMENT_KEY_DIRECTIONS
			if room.qte.kind == .Defense && room.qte.mode == .Dodge { keys = render.first_person_keys(renderer) }
			for pressed, index in input.directions {
				if pressed { command.kind = .QTE_Key; command.direction = keys[index]; break }
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
	// LAZZO: the frame's seconds spun out, as world commands, after its beats;
	// then the PINBALL's ball rolls them out.
	drain_lasso_spin_commands(room, renderer, cards, playtest)
	drain_pinball_roll_commands(room, renderer, cards, playtest)
	// FIRST PERSON SHOOTER: the trigger as the button holds it, then the shots
	// due, as world commands too.
	game.first_person_set_trigger(room, first_person_trigger(controller, renderer, room, input))
	drain_first_person_fire(room, renderer, cards, playtest)
	// Expiration is checked after all paid beats, including the last second.
	if game.tactical_tick(room, 0, true, controller.hologram) {
		controller.hologram = false
		clear_card_interaction(cards)
		clear_gameplay_command_buffer(buffer)
		if !commit_gameplay_command(room, renderer, cards, {kind = .Timeout, origin_phase = .Combat}, playtest) { return true }
		// A fresh walk on this exact boundary is already a recovery walk.
		// Discarded targeting or a pending tick chord cannot cross with it.
	}
	if game.tactical_is_recovering(room) {
		cards.selected_card_id = 0
		cards.dragged_card_id = 0
	}
	// The player's own animation owns the input lane: a press made now is
	// dropped, never kept for when the animation ends.
	if render.renderer_blocks_player_input(renderer) {
		clear_gameplay_command_buffer(buffer)
		return true
	}
	if !controller.hologram && room.phase == .Combat && room.player.tactical.phase == .Decision {
		// Behind the player's eyes the dodge turns with the view, and the
		// diagonal keys are off.
		fps := game.tactical_first_person_active(room)
		keys := render.first_person_keys(renderer)
		if input.shift {
			for pressed, index in input.directions {
				if pressed { command.kind = .Dodge; command.direction = keys[index]; break }
			}
		}
		offsets := [?]grid.Position{{-1, -1}, {1, -1}, {-1, 1}, {1, 1}}
		for pressed, index in input.diagonals {
			if !fps && command.kind == .None && pressed { command.kind = .Begin_Diagonal; command.offset = offsets[index]; break }
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

// A spin batch stops short of a full log; a frame's seconds (even a long
// frame's at the fastest spin) fit in this many.
LASSO_SPIN_BATCHES :: 4

// The Lazzo's seconds waiting, spun out in world commands (game.resolve_lasso_spin):
// never more batches than the bound, never into a full world bank.
drain_lasso_spin_commands :: proc(room: ^game.Room, renderer: ^render.Renderer,
	cards: ^Card_Interaction_State, playtest: ^combatdebug.Playtest_Session) {
	for _ in 0..<LASSO_SPIN_BATCHES {
		if !game.tactical_lasso_due(room) { return }
		if !commit_gameplay_command(room, renderer, cards, {kind = .Lasso_Spin, origin_phase = .Combat}, playtest) { return }
	}
}

// A roll batch stops short of a full log; a frame's seconds (even a long
// frame's at seven cells a second) fit in this many.
PINBALL_ROLL_BATCHES :: 4

// The Pinball's seconds waiting, rolled out in world commands
// (game.resolve_pinball_roll): never more batches than the bound, never into
// a full world bank.
drain_pinball_roll_commands :: proc(room: ^game.Room, renderer: ^render.Renderer,
	cards: ^Card_Interaction_State, playtest: ^combatdebug.Playtest_Session) {
	for _ in 0..<PINBALL_ROLL_BATCHES {
		if !game.tactical_pinball_due(room) { return }
		if !commit_gameplay_command(room, renderer, cards, {kind = .Pinball_Roll, origin_phase = .Combat}, playtest) { return }
	}
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
	// Behind the player's eyes there is no map: TAB and the button do nothing.
	if game.tactical_first_person_active(room) {
		controller.hologram = false
		renderer.tactical.hologram_orbit.dragging = false
		return false
	}
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
