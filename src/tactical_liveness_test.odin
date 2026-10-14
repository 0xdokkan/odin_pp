package main

import "core:fmt"
import "core:testing"
import game "game"
import level "level"
import render "render"

Tactical_Liveness_Probe :: struct {
	controller: Tactical_Controller,
	cards: Card_Interaction_State,
	buffer: Buffered_Gameplay_Command,
	accepted, released: int,
}

// Match the native frame order: presentation advances visually while the world
// clock receives the full focused frame delta. Seeking either timeline to the
// end would miss stalls and accidental ownership of ordinary player input.
tactical_liveness_frame :: proc(probe: ^Tactical_Liveness_Probe, room: ^game.Room,
	renderer: ^render.Renderer, input: Tactical_Controller_Input, dt: f32,
	requested: Gameplay_Command = {}) -> bool {
	if !probe.controller.paused && probe.controller.was_focused && input.focused {
		render.update_renderer_frame_timeline(renderer, dt)
	}
	blocked := step_tactical_controller(&probe.controller, room, renderer, &probe.cards, &probe.buffer,
		dt, true, input)
	if blocked { return false }
	probe.released += 1
	// Nothing is held across frames: only this frame's request or press acts.
	command := requested
	if command.kind == .None {
		for pressed, index in input.directions {
			if pressed { command = {kind = .Move, origin_phase = room.phase, direction = game.Move_Direction(index)}; break }
		}
	}
	if command.kind == .None { return false }
	accepted := commit_gameplay_command(room, renderer, &probe.cards, command)
	if accepted { probe.accepted += 1 }
	return accepted
}

@(test)
test_m7_controller_rendered_frames_finish_late_recoveries_and_release_new_walks :: proc(t: ^testing.T) {
	for speed in ([2]f32{1, 4}) {
		for irregular in ([2]bool{false, true}) {
			rows := [?]string{"#########", "#@......#", "#.......#", "#...>...#", "#.......#", "#########"}
			data, err, _ := level.from_ascii(rows[:])
			testing.expect_value(t, err, level.Parse_Error.None)
			defer level.destroy(&data)
			player, created := game.create_player({max_health = 10000, attack = 2, defense = 1})
			testing.expect(t, created)
			config := game.DEFAULT_TACTICAL_CONFIG
			config.timer_seconds = 2
			testing.expect(t, game.configure_tactical(&player, config))
			enemies := [?]game.Enemy_Spawn{{position = {2, 1}, health = 10000, attack = 2},
				{position = {6, 1}, health = 10000, attack = 2, archetype = .Archer}}
			room, built := game.create_room(&data, &player, {enemies = enemies[:]})
			testing.expect(t, built)
			defer game.destroy_room(&room)
			renderer := new(render.Renderer)
			defer free(renderer)
			defer render.destroy_renderer_world_playback(renderer)
			render.set_renderer_playback_speed(renderer, speed)
			probe := Tactical_Liveness_Probe{controller = {was_focused = true}}
			map_opened, saw_recovery, saw_qte, finished: bool
			map_frames := 0
			frames := 0
			frame_steps := [4]f32{1.0/240.0, 0.017, 0.083, 0.2}
			for frames < 30000 {
				frames += 1
				dt := f32(1.0/60.0)
				if irregular { dt = frame_steps[frames%4] }
				input := Tactical_Controller_Input{focused = true}
				if room.qte.kind != .None { saw_qte = true }
				if player.tactical.phase == .Recovery { saw_recovery = true }
				// A map left open has to consume its clock and reach an ordinary
				// timeout/recovery, rather than freezing the simulation permanently.
				if !map_opened && player.tactical.phase == .Decision && !render.renderer_timeline_is_busy(renderer) {
					input.map_input.toggle = true
					map_opened = true
				}
				if probe.controller.hologram { map_frames += 1 }
				if frames == 37 || frames == 43 { input.pause = true }
				if frames >= 63 && frames < 76 { input.focused = false }
				if !probe.controller.hologram && room.qte.kind == .None {
					direction, found := m7_route_move(&room)
					if found { input.directions[int(direction)] = true }
				}
				// QTE receives no answer, exercising actual defense timeouts.
				// Recovery continues using frame time while fresh walks remain valid.
				accepted := tactical_liveness_frame(&probe, &room, renderer, input, dt)
				if room.phase != .Combat || renderer.timeline.update_failures != 0 { break }
				if accepted && player.tactical.cycle >= 4 {
					finished = true
					break
				}
			}
			testing.expect(t, finished && saw_recovery && saw_qte && map_frames > 0 &&
				player.tactical.metrics.hologram_seconds > 0 && player.tactical.metrics.qte_failures > 0 &&
				player.tactical.metrics.forced_pulses >= 3 && renderer.timeline.update_failures == 0,
				fmt.tprintf("controller liveness: speed=%.0f irregular=%v frames=%d phase=%v tactical=%v pulse=%d pending=%v qte=%v timeline=%v cursor=%d/%d budget=%d remaining=%.3f",
					speed, irregular, frames, room.phase, player.tactical.phase, room.pulse_count,
					room.tactical_pulse.pending, room.qte.kind, render.renderer_timeline_is_busy(renderer),
					renderer.timeline.head, renderer.timeline.count, player.tactical.budget, player.tactical.remaining))
		}
	}
}

@(test)
test_m7_controller_survives_terminal_recovery_and_defense_then_enters_next_room :: proc(t: ^testing.T) {
	Ending :: enum {Direct_Parry, Recovery_Poison, Recovery_Parry}
	for ending in Ending {
		run, created := game.create_run({max_health = 1000, attack = 2, defense = 1}, DEMO_RUN_CONFIG, 0xC0FFEE)
		testing.expect(t, created)
		defer game.destroy_run(&run)
		config := game.DEFAULT_TACTICAL_CONFIG
		config.timer_seconds = 3 if ending == .Direct_Parry else 1
		testing.expect(t, game.configure_tactical(&run.player, config))
		testing.expect(t, game.initialize_empty_deck(&run.player.deck, game.DEFAULT_DECK_RULES, 71))
		for id in ([5]game.Card_Id{.Strike, .Guard, .Dash, .Battle_Focus, .Arc_Bolt}) {
			_, added := game.add_owned_card(&run.player.deck, id)
			testing.expect(t, added)
		}
		data := create_gameplay_command_test_level(t)
		defer level.destroy(&data)
		enemies := [?]game.Enemy_Spawn{{position = {2, 1}, health = 2, attack = 1}}
		room, built := game.create_room(&data, &run.player, {enemies = enemies[:]})
		testing.expect(t, built)
		defer game.destroy_room(&room)
		// This fixture specifically offers the first attack on the recovery
		// beat; casts no longer advance the enemy's cooldown in M8.
		if ending == .Recovery_Parry { room.enemies[0].tactical_cooldown = 1 }
		renderer := new(render.Renderer)
		defer free(renderer)
		defer render.destroy_renderer_world_playback(renderer)
		probe := Tactical_Liveness_Probe{controller = {was_focused = true}}
		guard: u32
		for card in run.player.deck.hand[:run.player.deck.hand_count] {
			if card.definition_id == .Guard { guard = card.id }
		}
		testing.expect(t, guard != 0)
		if ending == .Recovery_Poison {
			applied, _ := game.apply_status(&room, game.enemy_entity(1), .Poison, 1, 3)
			testing.expect(t, applied)
		}
		guard_played, saw_recovery, saw_recovery_parry: bool
		frames := 0
		for room.phase == .Combat && frames < 10000 {
			frames += 1
			input := Tactical_Controller_Input{focused = true}
			requested: Gameplay_Command
			if run.player.tactical.phase == .Recovery { saw_recovery = true }
			if room.qte.kind == .Defense && ending != .Recovery_Poison && guard_played {
				if !room.qte.selected { input.defenses[int(game.Defense_Mode.Parry)] = true }
				else { input.directions[int(room.qte.keys[room.qte.progress])] = true }
				if run.player.tactical.phase == .Recovery { saw_recovery_parry = true }
			} else if run.player.tactical.phase == .Decision {
				requested = {kind = .Wait, origin_phase = .Combat}
				if ending != .Recovery_Poison && !guard_played {
					requested = {kind = .Play_Card, origin_phase = .Combat, card_id = guard,
						target = game.entity_target(game.PLAYER_ENTITY)}
				}
			}
			if tactical_liveness_frame(&probe, &room, renderer, input, 1.0/60.0, requested) && requested.card_id == guard {
				guard_played = true
			}
		}
		testing.expect(t, room.phase == .Loot && room.qte.kind == .None && !room.tactical_pulse.pending &&
			run.player.tactical.phase == .Decision && !run.player.deck.combat_active,
			fmt.tprintf("terminal %v failed after %d frames: room=%v tactical=%v qte=%v pending=%v",
				ending, frames, room.phase, run.player.tactical.phase, room.qte.kind, room.tactical_pulse.pending))
		if room.phase != .Loot { continue }
		testing.expect(t, ending == .Direct_Parry || saw_recovery)
		testing.expect(t, ending != .Recovery_Parry || saw_recovery_parry)
		for room.phase == .Loot && frames < 12000 {
			frames += 1
			input := Tactical_Controller_Input{focused = true}
			direction, found := m7_route_move(&room)
			if !found { break }
			input.directions[int(direction)] = true
			tactical_liveness_frame(&probe, &room, renderer, input, 1.0/60.0)
		}
		testing.expect_value(t, room.phase, game.Room_Phase.Complete)
		for render.renderer_timeline_is_busy(renderer) && frames < 12500 {
			frames += 1
			tactical_liveness_frame(&probe, &room, renderer, {focused = true}, 1.0/60.0)
		}
		testing.expect(t, !render.renderer_timeline_is_busy(renderer))
		testing.expect_value(t, game.finish_room(&run, room.phase), game.Run_Transition.Reward)
		testing.expect(t, game.skip_card_reward(&run) == .Skipped)
		next := game.INVALID_NODE_ID
		for id in game.available_nodes(&run) {
			node, found := game.node_at(&run, id)
			if found && game.node_kind_has_room(node.kind) { next = id; break }
		}
		testing.expect(t, next != game.INVALID_NODE_ID && enter_demo_node(&data, &run, &room, next, true))
		render.clear_event_animations(renderer)
		clear_card_interaction(&probe.cards)
		clear_gameplay_command_buffer(&probe.buffer)
		direction, found := m7_route_move(&room)
		testing.expect(t, found)
		input := Tactical_Controller_Input{focused = true}
		input.directions[int(direction)] = true
		testing.expect(t, tactical_liveness_frame(&probe, &room, renderer, input, 0),
			fmt.tprintf("new room after %v refuses a fresh walk", ending))
		testing.expect_value(t, renderer.timeline.update_failures, 0)
	}
}
