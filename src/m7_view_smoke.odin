package main

import "core:fmt"
import rl "vendor:raylib"
import game "game"
import level "level"
import render "render"

M7_View_Smoke :: struct {
	frames, defense_frames: int,
	defense_pulse: u64,
	guard_started, defended: bool,
	saved_deck: game.Deck_State,
}

prepare_m7_view_room :: proc(data: ^level.Level, run: ^game.Run_State, room: ^game.Room) -> bool {
	rows := [?]string{"#########", "#.......#", "#.##....#", "#.#.....#", "#...@...#", "#.......#", "#.......#", "#...>...#", "#########"}
	new_level, err, _ := level.from_ascii(rows[:])
	if err != .None { return false }
	player := run.player
	game.finish_deck_combat(&player.deck)
	enemies := [?]game.Enemy_Spawn{
		{position = {5, 4}, health = 12, attack = 2},
		{position = {7, 3}, health = 10, attack = 2, archetype = .Archer},
		{position = {6, 6}, health = 20, attack = 2, archetype = .Custodian},
		{position = {2, 6}, health = 25, attack = 2, archetype = .Demolitionist},
	}
	new_room, ok := game.create_room(&new_level, &player, {enemies = enemies[:]})
	if !ok { level.destroy(&new_level); return false }
	game.destroy_room(room)
	level.destroy(data)
	data^ = new_level
	run.player = player
	room^ = new_room
	room.level_data, room.player = data, &run.player
	return true
}

// Called after presentation, so each screenshot captures a frame that actually
// displayed the state being checked. The scripted commands use the normal API.
step_m7_view_smoke :: proc(state: ^M7_View_Smoke, controller: ^Tactical_Controller,
	room: ^game.Room, renderer: ^render.Renderer, cards: ^Card_Interaction_State) -> (done, ok: bool) {
	state.frames += 1
	if state.frames > 600 { return true, false }
	if state.frames == 3 { rl.TakeScreenshot("odin_pp_m7_scene.png"); cards.hovered_card_id = room.player.deck.hand[0].id }
	if state.frames == 5 {
		rl.TakeScreenshot("odin_pp_m7_cards.png")
		state.saved_deck = room.player.deck
		for room.player.deck.hand_count < game.MAX_HAND_CARDS {
			if _, drawn := game.draw_card(&room.player.deck); !drawn { return true, false }
		}
	}
	if state.frames == 7 {
		rl.TakeScreenshot("odin_pp_m7_full_hand.png")
		room.player.deck = state.saved_deck
		clear_card_interaction(cards)
		controller.hologram = true
	}
	if state.frames == 10 {
		rl.TakeScreenshot("odin_pp_m7_hologram.png")
		render.adjust_tactical_orbit(&renderer.tactical.hologram_orbit, {140, 32}, 2)
		before := room.player.tactical.remaining
		if game.tactical_tick(room, 0.4, true, true) || abs(room.player.tactical.remaining-(before-0.4)) > 0.001 { return true, false }
	}
	command := Gameplay_Command{origin_phase = .Combat}
	if state.frames == 13 {
		rl.TakeScreenshot("odin_pp_m7_hologram_rotated.png")
		controller.hologram = false
		command.kind, command.offset = .Begin_Diagonal, {1, -1}
	} else if state.frames == 16 {
		rl.TakeScreenshot("odin_pp_m7_diagonal.png")
		command.kind, command.direction = .QTE_Key, .East
	} else if state.frames == 17 {
		command.kind, command.direction = .QTE_Key, .North
	} else if state.frames > 17 && !render.renderer_timeline_is_busy(renderer) {
		if room.qte.kind == .Defense {
			if !room.qte.selected {
				state.defense_frames += 1
				if state.defense_frames < 3 { return false, true }
				rl.TakeScreenshot("odin_pp_m7_defense.png")
				state.defense_pulse = room.pulse_count
				command.kind, command.defense = .Defense, .Parry
			} else {
				command.kind, command.direction = .QTE_Key, room.qte.keys[0]
				state.defended = true
			}
		} else if room.tactical_pulse.pending { command.kind = .Continue_Pulse }
		else if !state.guard_started {
			state.guard_started = true
			command.kind, command.ability = .Ability, .Guard
		} else if !state.defended && room.pulse_count < 4 {
			// The chaser now rests after missing the diagonal. Guard covers the next attack.
			command.kind = .Wait
		} else {
			valid := state.defended && room.pulse_count == state.defense_pulse+1 && room.pulse_count <= 5 &&
				room.player.tactical.metrics.qte_successes >= 2 && renderer.timeline.update_failures == 0
			fmt.printf("M7 defense: pulse=%d response_at=%d successes=%d timeline_errors=%d\n", room.pulse_count, state.defense_pulse, room.player.tactical.metrics.qte_successes, renderer.timeline.update_failures)
			return true, valid
		}
	}
	if command.kind != .None && !commit_gameplay_command(room, renderer, cards, command) { return true, false }
	return false, true
}
