package run

import combatdebug "../combatdebug"
import game "../game"
import render "../render"
import view "../engine/view"

// Native input -> gameplay commands -> telemetry and presentation. The pure
// command/routing rules are in gameplay_input.odin; the scene owns frame gates.

Card_Interaction_State :: struct {
	hovered_card_id:  u32,
	selected_card_id: u32,
	dragged_card_id:  u32,
	placing: bool,
	placement_direction: game.Move_Direction,
}

clear_card_interaction :: proc(state: ^Card_Interaction_State) {
	if state != nil {
		state^ = {}
	}
}

active_targeting_card_id :: proc(state: Card_Interaction_State) -> u32 {
	if state.dragged_card_id != 0 {
		return state.dragged_card_id
	}
	return state.selected_card_id
}

// FERETRO: the player holds Ctrl with arrows to loose; the board then marks
// the foes they reach (render.draw_arrow_aim).
arrows_aiming :: proc(room: ^game.Room, controls: Run_Input) -> bool {
	return arrows_aiming_at(room, run_down(controls, .Arrow_Aim))
}

// The same with Ctrl `held` or not. Behind his eyes he looses none.
arrows_aiming_at :: proc(room: ^game.Room, held: bool) -> bool {
	return held && room != nil && room.player != nil && room.phase == .Combat && game.player_charges(room, .Arrows) > 0 &&
	       !game.tactical_first_person_active(room)
}

// FERETRO's click while `aiming`: an arrow at the foe under the mouse when
// the arrows reach it. Such a click is the arrow's either way (`taken`): it
// never also picks up a card or drops one on the board.
arrow_shot_command :: proc(room: ^game.Room, renderer: ^render.Renderer, aiming, clicked: bool) -> (command: Gameplay_Command,
	has_command, taken: bool) {
	if !aiming || !clicked { return }
	taken = true
	if !renderer.has_hovered_cell { return }
	index, found := game.enemy_index_at(room, renderer.hovered_cell)
	if !found { return }
	foe := game.enemy_entity(room.enemies[index].id)
	if !game.player_arrow_target_is_valid(room, foe) { return }
	return {kind = .Shoot, origin_phase = .Combat, target = game.entity_target(foe)}, true, true
}

// The pointer for the Canna da Pesca's slot this frame.
Fishing_Input :: struct {
	mouse: view.Vec2,
	inside, pressed, released, down, cancel: bool,
}

// CANNA DA PESCA (game/fishing.odin): once the room is cleared, its slot
// (render.fishing_slot_bounds) holds the rod as the hand holds a card. A press
// on it picks the rod up; let go over a cell it may fish, it fishes there, and
// let go anywhere else it stays chosen, so that a click on such a cell fishes.
// Esc or a right click puts it back. While the board still shows an action
// (`spatial` false) nothing is picked up. A press that is the rod's is never
// a step's as well (`taken`). Pure routing, shared by the scene and the tests.
poll_fishing_command :: proc(room: ^game.Room, renderer: ^render.Renderer, cards: ^Card_Interaction_State, input: Fishing_Input,
	spatial: bool) -> (command: Gameplay_Command, has_command, taken: bool) {
	rod, held := game.fishing_rod(&room.player.deck)
	if !held || !game.fishing_room_open(room) || game.fishing_casts_left(room) <= 0 {
		clear_card_interaction(cards)
		return
	}
	// The rod is all there is to hold in a cleared room.
	if cards.hovered_card_id != rod.id { cards.hovered_card_id = 0 }
	if cards.selected_card_id != rod.id { cards.selected_card_id = 0 }
	if cards.dragged_card_id != rod.id { cards.dragged_card_id = 0 }
	if input.cancel {
		taken = cards.selected_card_id != 0 || cards.dragged_card_id != 0
		clear_card_interaction(cards)
		return
	}
	if !spatial { cards.dragged_card_id = 0 }
	over_slot := input.inside && render.point_in_rectangle(input.mouse, render.fishing_slot_bounds(renderer))
	cards.hovered_card_id = rod.id if over_slot && cards.dragged_card_id == 0 else 0
	// The cell under the pointer, when the rod may fish it.
	fish_at_pointer :: proc(room: ^game.Room, renderer: ^render.Renderer, rod: game.Card_Instance, input: Fishing_Input) -> (Gameplay_Command, bool) {
		if !input.inside || !render.card_drop_area_contains(renderer, input.mouse) || !renderer.has_hovered_cell ||
		   game.fishing_target_error(room, renderer.hovered_cell) != .Fished { return {}, false }
		return {kind = .Fish, origin_phase = .Loot, card_id = rod.id, target = game.cell_target(renderer.hovered_cell)}, true
	}
	if cards.dragged_card_id == rod.id {
		if input.released || !input.down {
			cards.dragged_card_id, cards.selected_card_id = 0, rod.id
			command, has_command = fish_at_pointer(room, renderer, rod, input)
		}
		return command, has_command, true
	}
	if !spatial { return }
	if over_slot && input.pressed {
		cards.dragged_card_id, cards.hovered_card_id, cards.selected_card_id = rod.id, 0, 0
		return {}, false, true
	}
	if cards.selected_card_id == rod.id && input.pressed {
		command, has_command = fish_at_pointer(room, renderer, rod, input)
		return command, has_command, true
	}
	return
}

// W, D, S and A step the ways of `keys` (north, east, south and west, but
// behind the player's eyes: render.first_person_keys).
poll_walk_command :: proc(phase: game.Room_Phase, controls: Run_Input, keys := game.MOVEMENT_KEY_DIRECTIONS) -> (Gameplay_Command, bool) {
	for action, index in RUN_WALK_ACTIONS {
		if run_pressed(controls, action) { return {kind = .Move, origin_phase = phase, direction = keys[index]}, true }
	}
	return {}, false
}

poll_gameplay_command :: proc(
	room: ^game.Room,
	renderer: ^render.Renderer,
	card_interaction: ^Card_Interaction_State,
	mouse_canvas: view.Vec2,
	mouse_in_canvas: bool,
	spatial_interaction_enabled: bool,
	debug_abilities: bool = false,
	controls: Run_Input = {},
) -> (command: Gameplay_Command, has_command: bool) {
	assert(room != nil && room.player != nil && renderer != nil && card_interaction != nil)
	// FIRST PERSON SHOOTER: the mouse is the view's and the hand is put away;
	// only steps and waits are left (first_person_input.odin).
	if game.tactical_first_person_active(room) {
		clear_card_interaction(card_interaction)
		pressed: [4]bool
		for action, index in RUN_WALK_ACTIONS { pressed[index] = run_pressed(controls, action) }
		return first_person_lane_command(pressed, run_down(controls, .Dodge_Modifier), run_pressed(controls, .Wait),
			render.first_person_keys(renderer))
	}
	raised_card_id := card_interaction.hovered_card_id
	if raised_card_id == 0 { raised_card_id = card_interaction.selected_card_id }
	if card_interaction.dragged_card_id != 0 { raised_card_id = 0 }
	if clicked, accepted := m8_pointer_gameplay_command(room, renderer, mouse_canvas, mouse_in_canvas,
		controls.left_pressed, spatial_interaction_enabled); accepted { return clicked, true }
	// The inspector's MOSTRA EFFETTO button is no cell of the board.
	mouse_inside := mouse_in_canvas && !render.relic_bar_contains_point(renderer, room, mouse_canvas, raised_card_id) &&
		!render.m8_hud_contains_point(renderer, room, mouse_canvas) &&
		!render.tactical_inspector_effect_contains(renderer, room, card_interaction.hovered_card_id, card_interaction.selected_card_id,
			card_interaction.dragged_card_id, mouse_canvas)
	input_deck, input_phase := render.renderer_hand_deck(renderer, room)
	if input_phase == .Loot {
		// The room cleared: the Canna da Pesca's slot takes its own presses.
		fishing := Fishing_Input{mouse = mouse_canvas, inside = mouse_inside, pressed = controls.left_pressed,
			released = controls.left_released, down = controls.left_down,
			cancel = run_pressed(controls, .Cancel) || controls.right_pressed}
		if fish, has_fish, taken := poll_fishing_command(room, renderer, card_interaction, fishing, spatial_interaction_enabled); taken {
			return fish, has_fish
		}
		return poll_walk_command(.Loot, controls)
	}
	if input_phase != .Combat || !input_deck.combat_active {
		clear_card_interaction(card_interaction)
		return
	}
	if run_pressed(controls, .Cancel) || controls.right_pressed {
		if card_interaction.placing {
			card_interaction.placing = false
			renderer.tactical.expedition_placement = false
			return
		}
		clear_card_interaction(card_interaction)
		return
	}
	if card_interaction.selected_card_id != 0 {
		_, selected_found := game.hand_card_index_by_id(
			input_deck,
			card_interaction.selected_card_id,
		)
		if !selected_found {
			card_interaction.selected_card_id = 0
		}
	}
	if !spatial_interaction_enabled {
		card_interaction.dragged_card_id = 0
	}
	if room.player.tactical.config.expedition && spatial_interaction_enabled && controls.wheel != 0 {
		expedition_cycle_hand(card_interaction, input_deck, controls.wheel)
	}
	renderer.tactical.expedition_placement = card_interaction.placing
	renderer.tactical.expedition_direction = card_interaction.placement_direction

	card_interaction.hovered_card_id = 0
	if card_interaction.dragged_card_id == 0 && mouse_inside {
		if hand_index, found := render.hand_card_at_point(
			renderer,
			input_deck,
			mouse_canvas,
			raised_card_id,
		); found {
			card_interaction.hovered_card_id = input_deck.hand[hand_index].id
		}
	}

	// Recovery and Movimento Ombra leave only walking (in the shadow, its steps).
	if game.tactical_is_recovering(room) || game.tactical_shadow_active(room) {
		card_interaction.selected_card_id = 0
		card_interaction.dragged_card_id = 0
		// Shift+WASD requests an active dodge; do not silently turn it into a walk.
		if run_down(controls, .Dodge_Modifier) { return }
		return poll_walk_command(.Combat, controls)
	}

	if spatial_interaction_enabled && card_interaction.dragged_card_id != 0 {
		if controls.left_released || !controls.left_down {
			dragged_card_id := card_interaction.dragged_card_id
			card_interaction.dragged_card_id = 0
			card_interaction.selected_card_id = dragged_card_id
			if mouse_inside && render.card_drop_area_contains(renderer, mouse_canvas) &&
			   renderer.has_hovered_cell {
				if hand_index, found := game.hand_card_index_by_id(input_deck, dragged_card_id); found {
					if room.player.tactical.config.expedition && game.card_requires_orientation(input_deck.hand[hand_index].definition_id) {
						card_interaction.placing = true
						renderer.tactical.expedition_placement = true
						return
					}
					return targeted_card_command(room, input_deck.hand[hand_index], renderer.hovered_cell)
				}
			}
		}
		return
	}

	// FERETRO: Ctrl held, a left click on a foe the arrows reach looses one;
	// over the hand the click stays the hand's.
	if spatial_interaction_enabled && mouse_inside && card_interaction.hovered_card_id == 0 {
		if shot, has_shot, taken := arrow_shot_command(room, renderer, arrows_aiming(room, controls), controls.left_pressed); taken {
			return shot, has_shot
		}
	}

	if run_pressed(controls, .Refocus) ||
	   (spatial_interaction_enabled && mouse_inside && controls.left_pressed &&
	    render.refocus_button_at_point(renderer, mouse_canvas)) {
		return Gameplay_Command{kind = .Refocus, origin_phase = .Combat}, true
	}

	requested_slot := pressed_hand_slot(controls, 10)
	if spatial_interaction_enabled && mouse_inside && controls.left_pressed &&
	   card_interaction.hovered_card_id != 0 {
		if card_interaction.selected_card_id == card_interaction.hovered_card_id {
			if index, found := game.hand_card_index_by_id(input_deck, card_interaction.selected_card_id); found {
				if card_command, immediate := immediate_card_command(input_deck.hand[index]); immediate { return card_command, true }
			}
		}
		card_interaction.dragged_card_id = card_interaction.hovered_card_id
		card_interaction.hovered_card_id = 0
		card_interaction.selected_card_id = 0
		return
	}
	if requested_slot >= 0 && requested_slot < input_deck.hand_count {
		card := input_deck.hand[requested_slot]
		if card_command, immediate := immediate_card_command(card); immediate {
			return card_command, true
		}
		if !spatial_interaction_enabled {
			return
		}
		card_interaction.selected_card_id = card.id
		return
	}

	if spatial_interaction_enabled && card_interaction.selected_card_id != 0 && mouse_inside &&
	   render.card_drop_area_contains(renderer, mouse_canvas) && controls.left_pressed &&
	   renderer.has_hovered_cell {
		if hand_index, found := game.hand_card_index_by_id(
			input_deck,
			card_interaction.selected_card_id,
		); found {
			card := input_deck.hand[hand_index]
			if room.player.tactical.config.expedition {
				if game.card_requires_orientation(card.definition_id) && !card_interaction.placing {
					card_interaction.placing = true
					renderer.tactical.expedition_placement = true
					return
				}
				if immediate, ok := immediate_card_command(card); ok { return immediate, true }
			}
			command, has_command = targeted_card_command(room, card, renderer.hovered_cell)
			command.direction = card_interaction.placement_direction
			return
		}
		return
	}

	if debug_abilities && run_pressed(controls, .Debug_Thorns) {
		return Gameplay_Command{kind = .Ability, origin_phase = .Combat, ability = .Thorn_Coat}, true
	} else if debug_abilities && run_pressed(controls, .Debug_Afterimage) {
		return Gameplay_Command{kind = .Ability, origin_phase = .Combat, ability = .Afterimage}, true
	}
	if walk, pressed := poll_walk_command(.Combat, controls); pressed { return walk, true }
	if run_pressed(controls, .Wait) {
		return Gameplay_Command{kind = .Wait, origin_phase = .Combat}, true
	}
	return
}

Gameplay_Command_Execution :: struct {
	committed:              bool,
	clears_card_interaction: bool,
}

capture_gameplay_command_telemetry :: proc(
	room: ^game.Room,
	command: Gameplay_Command,
) -> (
	snapshot: combatdebug.Command_Snapshot,
	resolved_kind: combatdebug.Command_Kind,
	descriptor: combatdebug.Command_Descriptor,
	ok: bool,
) {
	snapshot, ok = combatdebug.capture_command_snapshot(room)
	if !ok {
		return
	}
	switch command.kind {
	case .None:
		return snapshot, {}, {}, false
	case .Move:
		resolved_kind, ok = combatdebug.command_kind_for_move(room, command.direction)
		// A shadow step walks from the shadow's cell and never bumps.
		if game.tactical_shadow_active(room) { resolved_kind = .Move }
	case .Dodge, .Wait, .Timeout, .Continue_Pulse, .Begin_Diagonal, .QTE_Key, .QTE_Fail, .Defense, .Activate, .Equip,
	     .Shadow_Emerge, .Lasso_Spin, .Pinball_Roll:
		resolved_kind = .Wait
	// An arrow is neither a step nor a bump nor a card, and the rod's cast is
	// no card either; nor is a shot of the AK.
	case .Ability, .Shoot, .Fish, .First_Person_Fire:
		resolved_kind = .Ability
	case .Play_Card:
		resolved_kind = .Play_Card
		descriptor, _ = combatdebug.capture_card_descriptor(room, command.card_id, command.target)
	case .Refocus:
		resolved_kind = .Refocus
	}
	return snapshot, resolved_kind, descriptor, ok
}

execute_gameplay_command :: proc(room: ^game.Room, command: Gameplay_Command) -> (
	execution: Gameplay_Command_Execution,
) {
	if room == nil || room.player == nil || !gameplay_command_is_valid(command) ||
	   room.phase != command.origin_phase {
		return
	}
	switch command.kind {
	case .None:
		return
	case .Activate:
		// A square of coils around enemies opens the floor's ring instead of
		// discharging; the duel itself costs no board time.
		opened_ring: bool
		execution.committed, opened_ring = game.activate_tesla(room)
		if execution.committed && !opened_ring { game.finish_player_combat_command(room, 1) }
	case .Equip:
		execution.committed = game.equip_reserved_weapon(room)
		if execution.committed {
			game.clear_event_log(room.recent_events)
			if room.phase == .Combat { game.finish_player_combat_command(room, 1) }
		}
	case .Timeout:
		if room == nil || room.player == nil || room.player.tactical.remaining > 0 { return }
		execution.committed = game.tactical_expire_window(room)
		if execution.committed { room.player.tactical.metrics.timeouts += 1 }
	case .Continue_Pulse:
		execution.committed = game.continue_tactical_pulse(room)
	case .Begin_Diagonal:
		execution.committed = game.begin_diagonal_qte(room, command.offset)
	case .Defense:
		if game.select_defense(room, command.defense) { game.clear_event_log(room.recent_events); execution.committed = true }
	case .QTE_Key:
		game.clear_event_log(room.recent_events)
		execution.committed = game.qte_key(room, command.direction)
	case .QTE_Fail:
		execution.committed = game.resolve_qte(room, false)
	case .Shadow_Emerge:
		execution.committed = game.tactical_end_shadow(room)
	case .Lasso_Spin:
		execution.committed = game.resolve_lasso_spin(room)
	case .Pinball_Roll:
		execution.committed = game.resolve_pinball_roll(room)
	case .Move:
		// Inside Movimento Ombra the keys walk the shadow, on its own beats.
		if game.tactical_shadow_active(room) {
			execution.committed = game.try_shadow_step(room, command.direction, command.diagonal, command.beat) == .Moved
			break
		}
		spent := room.player.tactical.beat_spent
		critical := game.tactical_claim_beat(room, command.beat)
		result: game.Action_Result
		if critical && command.diagonal != {} {
			result = game.try_move_player_diagonal(room, command.diagonal)
		} else {
			room.player.tactical.critical_next = critical
			result = game.try_move_player(room, command.direction)
			room.player.tactical.critical_next = false
			// Only a bump is critical on a straight key: a plain step leaves
			// the tick to the next action.
			if result != .Attacked { room.player.tactical.beat_spent = spent }
		}
		execution.committed = result != .Invalid_Phase && result != .Blocked
		if execution.committed && command.diagonal == {} { room.player.tactical.facing = command.direction }
		// A step that did not happen gives its tick back.
		if !execution.committed { room.player.tactical.beat_spent = spent }
	case .Dodge:
		execution.committed = game.try_dodge_player(room, command.direction)
		execution.clears_card_interaction = execution.committed
	case .Wait:
		result := game.wait_player_turn(room)
		execution.committed = result != .Invalid_Phase
	case .Ability:
		result := game.use_player_ability(room, command.ability)
		execution.committed = result != .Invalid_Phase
	case .Play_Card:
		spent := room.player.tactical.beat_spent
		if game.tactical_card_claims_beat(room, command.card_id) {
			room.player.tactical.critical_next = game.tactical_claim_beat(room, command.beat)
		}
		play := game.play_card(room, command.card_id, command.target, command.direction)
		room.player.tactical.critical_next = false
		execution.committed = game.card_play_was_committed(play.result)
		execution.clears_card_interaction = execution.committed
		if !execution.committed { room.player.tactical.beat_spent = spent }
	case .Shoot:
		// Never stamped with a beat: an arrow is never critical.
		result := game.shoot_player_arrow(room, command.target.entity)
		execution.committed = result != .Invalid_Phase && result != .Blocked
		execution.clears_card_interaction = execution.committed
	case .Fish:
		report := game.fish_with_rod(room, command.target.cell)
		execution.committed = report.result == .Fished
		execution.clears_card_interaction = execution.committed
	case .Refocus:
		refocus := game.refocus_player_hand(room)
		execution.committed = game.refocus_was_committed(refocus.result)
		execution.clears_card_interaction = execution.committed
	case .First_Person_Fire:
		_, execution.committed = game.first_person_fire(room, command.aim)
	}
	game.tactical_end_combat(room)
	return
}

execute_observed_gameplay_command :: proc(
	room: ^game.Room,
	command: Gameplay_Command,
	playtest: ^combatdebug.Playtest_Session = nil,
) -> (execution: Gameplay_Command_Execution) {
	snapshot: combatdebug.Command_Snapshot
	resolved_kind: combatdebug.Command_Kind
	descriptor: combatdebug.Command_Descriptor
	telemetry_captured := false
	if playtest != nil && playtest.active && playtest.room_active {
		snapshot, resolved_kind, descriptor, telemetry_captured =
			capture_gameplay_command_telemetry(room, command)
	}

	execution = execute_gameplay_command(room, command)
	if !telemetry_captured {
		return
	}
	_, observed := combatdebug.observe_playtest_command_detailed(
		playtest,
		snapshot,
		resolved_kind,
		descriptor,
		execution.committed,
		room,
	)
	assert(observed)
	if room.phase != .Combat {
		room_finished := combatdebug.finish_playtest_room(playtest, room)
		assert(room_finished)
	}
	return
}

commit_gameplay_command :: proc(
	room: ^game.Room,
	renderer: ^render.Renderer,
	card_interaction: ^Card_Interaction_State,
	command: Gameplay_Command,
	playtest: ^combatdebug.Playtest_Session = nil,
) -> bool {
	if room == nil || renderer == nil || card_interaction == nil { return false }
	world_command := (command.kind == .Continue_Pulse || command.kind == .Timeout || command.kind == .Lasso_Spin || command.kind == .Pinball_Roll ||
		 command.kind == .Defense || ((command.kind == .QTE_Key || command.kind == .QTE_Fail) && room.qte.kind == .Defense) ||
		 command.kind == .First_Person_Fire)
	if world_command {
		// Reserve a whole event log before mutating gameplay: no committed beat
		// can lose its presentation when the bounded world bank is full.
		if render.renderer_world_available_cues(renderer) < game.MAX_GAME_EVENTS { return false }
	} else if render.renderer_blocks_player_input(renderer) { return false }
	before := render.capture_room_presentation(room)
	execution := execute_observed_gameplay_command(room, command, playtest)
	if !execution.committed {
		return false
	}
	after := render.capture_room_presentation(room)
	if execution.clears_card_interaction || room.phase != .Combat {
		clear_card_interaction(card_interaction)
	}
	if room.recent_events.count > 0 {
		started := render.begin_renderer_world_timeline(renderer, before, room.recent_events, &after) if world_command else
			render.begin_renderer_event_timeline(renderer, before, room.recent_events, &after)
		assert(started, "committed gameplay must retain its presentation")
		if command.kind == .Play_Card && game.tactical_is_casting(room) {
			render.fit_card_cast_timeline(renderer, room.player.tactical.cast_duration)
		}
	}
	return true
}

keyboard_route_choice :: proc(run: ^game.Run_State, controls: Run_Input) -> (game.Node_Id, bool) {
	choices := game.available_nodes(run)
	choice_index := -1
	if run_pressed(controls, .Route_1) {
		choice_index = 0
	} else if run_pressed(controls, .Route_2) {
		choice_index = 1
	} else if run_pressed(controls, .Route_3) {
		choice_index = 2
	}
	if choice_index < 0 || choice_index >= len(choices) {
		return game.INVALID_NODE_ID, false
	}
	return choices[choice_index], true
}
