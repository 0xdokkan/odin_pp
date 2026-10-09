package main

import "core:fmt"
import "core:os"
import "core:strings"
import game "game"
import render "render"

INPUT_DIAGNOSTIC_MAX_BYTES :: 8192
INPUT_DIAGNOSTIC_MAX_FILES :: 256

Input_Diagnostic_Frame :: struct {
	dt: f32,
	focused, route_map, scripted, mouse_left, shift: bool,
	wasd_down: [4]bool,
}

// Fixed, game-only content. No environment, file paths, account information or
// gameplay mutations; it is safe to capture while any input gate is active.
format_input_diagnostic :: proc(storage: []u8, run: ^game.Run_State, room: ^game.Room,
	renderer: ^render.Renderer, controller: ^Tactical_Controller,
	cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command,
	frame: Input_Diagnostic_Frame) -> string {
	b := strings.builder_from_bytes(storage)
	fmt.sbprintf(&b, "ODIN INPUT SNAPSHOT v1 (F8, before frame update)\n")
	if run == nil || room == nil || room.player == nil || renderer == nil || controller == nil || cards == nil || buffer == nil {
		fmt.sbprintf(&b, "invalid_snapshot_arguments=true\n")
		return strings.to_string(b)
	}
	p := room.player
	s := &p.tactical
	active_relic := game.run_has_relic_choice(run)
	available := run.phase == .In_Room && !active_relic && !frame.route_map && !frame.scripted
	fmt.sbprintf(&b, "seed=%d run_phase=%v node=%d room_phase=%v family=%v pulse=%d enemies=%d\n",
		run.seed, run.phase, run.current_node, room.phase, room.family, room.pulse_count, len(room.enemies))
	fmt.sbprintf(&b, "frame_dt=%.9f focused=%v was_focused=%v paused=%v available=%v route_map=%v relic_choice=%v scripted=%v hologram=%v\n",
		frame.dt, frame.focused, controller.was_focused, controller.paused, available,
		frame.route_map, active_relic, frame.scripted, controller.hologram)
	fmt.sbprintf(&b, "held_WDSA=%v shift=%v mouse_left=%v\n", frame.wasd_down, frame.shift, frame.mouse_left)
	fmt.sbprintf(&b, "player=%v health=%d deck_active=%v energy=%d hand_count=%d deck_resolving=%v tactical_allows_action=%v\n",
		p.position, p.health, p.deck.combat_active, p.deck.energy, p.deck.hand_count,
		p.deck.has_resolving_card, game.tactical_allows_action(room))
	fmt.sbprintf(&b, "tactical_enabled=%v phase=%v remaining=%.9f budget=%d cycle=%d recovering=%v dodge_recovery=%d\n",
		s.config.enabled, s.phase, s.remaining, s.budget, s.cycle, game.tactical_is_recovering(room), s.dodge_recovery)
	fmt.sbprintf(&b, "pulse_pending=%v started=%v forced=%v cursor=%d count=%d defense_answered=%d\n",
		room.tactical_pulse.pending, room.tactical_pulse.started, room.tactical_pulse.forced,
		room.tactical_pulse.cursor, room.tactical_pulse.count, room.tactical_pulse.defense_answered)
	fmt.sbprintf(&b, "qte=%v remaining=%.9f selected=%v mode=%v progress=%d length=%d enemy=%d destination=%v\n",
		room.qte.kind, room.qte.remaining, room.qte.selected, room.qte.mode, room.qte.progress,
		room.qte.length, room.qte.enemy_id, room.qte.destination)
	fmt.sbprintf(&b, "timeline_busy=%v head=%d count=%d failures=%d dropped=%d speed=%.3f presentation_phase=%v presentation_player=%v\n",
		render.renderer_timeline_is_busy(renderer), renderer.timeline.head, renderer.timeline.count,
		renderer.timeline.update_failures, renderer.timeline.dropped_count, render.renderer_playback_speed(renderer),
		renderer.timeline.view.phase, renderer.timeline.view.player.position)
	fmt.sbprintf(&b, "player_animation_blocks_input=%v world_busy=%v world_cues=%d world_high_water=%d world_rejected_batches=%d clock_fraction=%.6f queued_beats=%d\n",
		render.renderer_blocks_player_input(renderer), render.renderer_world_is_busy(renderer),
		(renderer.world_playback.count if renderer.world_playback != nil else 0),
		(renderer.world_playback.high_water if renderer.world_playback != nil else 0),
		(renderer.world_playback.rejected_batches if renderer.world_playback != nil else 0),
		s.clock_fraction, s.queued_beats)
	if cue, found := render.active_presentation_cue(&renderer.timeline); found {
		fmt.sbprintf(&b, "active_cue=%v started=%v elapsed=%.9f duration=%.9f event=%v source=%v target=%v\n",
			cue.kind, cue.started, cue.elapsed, cue.duration, cue.event.kind, cue.event.source, cue.event.target)
	}
	fmt.sbprintf(&b, "cards_hovered=%d selected=%d dragged=%d buffer_occupied=%v buffer_kind=%v buffer_phase=%v buffer_direction=%v\n",
		cards.hovered_card_id, cards.selected_card_id, cards.dragged_card_id,
		buffer.occupied, buffer.command.kind, buffer.command.origin_phase, buffer.command.direction)
	for direction in game.Move_Direction {
		destination := game.add_position(p.position, game.direction_offset(direction))
		query := game.query_entity_movement(room, game.PLAYER_ENTITY, destination)
		fmt.sbprintf(&b, "neighbor=%v cell=%v movement_query=%v has_blocker=%v blocker=%v",
			direction, destination, query.error, query.has_blocker, query.blocker)
		if object, found := game.grid_object_at(room, destination); found {
			fmt.sbprintf(&b, " object=%v object_id=%d object_hp=%d", object.kind, object.id, object.health)
		}
		if index, found := game.enemy_index_at(room, destination); found {
			enemy := room.enemies[index]
			fmt.sbprintf(&b, " enemy=%v enemy_id=%d enemy_hp=%d", enemy.archetype, enemy.id, enemy.health)
		}
		fmt.sbprintf(&b, "\n")
	}
	return strings.to_string(b)
}

// Files are exclusive and numbered: a second F8 captures progress (or its
// absence) without replacing the evidence from the first press.
write_input_diagnostic :: proc(run: ^game.Run_State, room: ^game.Room,
	renderer: ^render.Renderer, controller: ^Tactical_Controller,
	cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command,
	frame: Input_Diagnostic_Frame, directory: string = ".") -> (path: string, ok: bool) {
	storage: [INPUT_DIAGNOSTIC_MAX_BYTES]u8
	report := format_input_diagnostic(storage[:], run, room, renderer, controller, cards, buffer, frame)
	for index in 0..<INPUT_DIAGNOSTIC_MAX_FILES {
		candidate := fmt.aprintf("%s/odin_pp_input_%d.txt", directory, index)
		file, err := os.open(candidate, {.Write, .Create, .Excl})
		if err != nil {
			delete(candidate)
			if err == .Exist { continue }
			return
		}
		count, write_err := os.write(file, transmute([]u8)report)
		close_err := os.close(file)
		if write_err != nil || close_err != nil || count != len(report) {
			os.remove(candidate)
			delete(candidate)
			return
		}
		return candidate, true
	}
	return
}
