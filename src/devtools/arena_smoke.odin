package devtools
import artifacts "artifacts"
import run_session "../run"

import "core:fmt"
import "core:time"
import app "../engine/app"
import game "../game"
import render "../render"

Arena_Smoke_Report :: struct {
	rooms, largest_roster, combat_moves, loot_moves, transitions, frames: int,
	world_high_water: int,
	world_beats: u64,
	generation_ms, simulation_ms, peak_simulation_ms: f64,
	combat_draw_frames, map_draw_frames: int,
	combat_draw_ms, map_draw_ms, combat_draw_peak_ms, map_draw_peak_ms: f64,
}

arena_smoke_step :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command,
	report: ^Arena_Smoke_Report, frame_dt, simulation_dt: f32) -> bool {
	started := time.tick_now()
	if room.qte.kind != .None {
		if !run_session.commit_gameplay_command(room, renderer, cards, {kind = .QTE_Fail, origin_phase = .Combat}) { return false }
	}
	render.update_renderer_frame_timeline(renderer, frame_dt)
	run_session.step_tactical_controller(controller, room, renderer, cards, buffer, simulation_dt, true, {focused = true})
	elapsed := time.duration_milliseconds(time.tick_since(started))
	report.simulation_ms += elapsed
	report.peak_simulation_ms = max(report.peak_simulation_ms, elapsed)
	report.frames += 1
	if renderer.world_playback != nil {
		report.world_high_water = max(report.world_high_water, renderer.world_playback.high_water)
		if renderer.world_playback.rejected_batches != 0 { return false }
	}
	if renderer.timeline.update_failures != 0 || renderer.timeline.dropped_count != 0 || room.recent_events.dropped_count != 0 { return false }
	if window != nil {
		render.advance_sprite_assets(&renderer.sprite_assets, frame_dt)
		render.update_tactical_view(renderer, room, {}, false, true)
		render.update_tactical_atmosphere(renderer, frame_dt)
		draw_started := time.tick_now()
		app.begin_canvas(window, render.RESIN_BACKGROUND)
		if controller.hologram {
			render.draw_hologram(renderer, room)
		} else {
			render.draw_tactical_world(renderer, room, 0)
			render.draw_tactical_status(renderer, room)
			render.draw_tactical_hand(renderer, room, 0, 0, 0, {})
		}
		render.draw_tactical_hud(renderer, room, false, controller.hologram)
		draw_elapsed := time.duration_milliseconds(time.tick_since(draw_started))
		if !(draw_elapsed >= 0 && draw_elapsed < max(f64)) { return false }
		if controller.hologram {
			report.map_draw_frames += 1
			report.map_draw_ms += draw_elapsed
			report.map_draw_peak_ms = max(report.map_draw_peak_ms, draw_elapsed)
		} else {
			report.combat_draw_frames += 1
			report.combat_draw_ms += draw_elapsed
			report.combat_draw_peak_ms = max(report.combat_draw_peak_ms, draw_elapsed)
		}
		app.present(window, render.LETTERBOX_COLOR)
	}
	return true
}

arena_smoke_settle :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command,
	report: ^Arena_Smoke_Report) -> bool {
	for _ in 0..<1200 {
		if !render.renderer_timeline_is_busy(renderer) && !room.tactical_pulse.pending && room.qte.kind == .None { return true }
		if !arena_smoke_step(window, renderer, room, controller, cards, buffer, report, 0.1, 0) { return false }
	}
	return false
}

// Every image receives three complete present calls; macOS captures the front
// buffer, so a single render followed by TakeScreenshot may show the old view.
arena_smoke_capture :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command,
	report: ^Arena_Smoke_Report, filename: cstring) -> bool {
	for _ in 0..<3 {
		if !arena_smoke_step(window, renderer, room, controller, cards, buffer, report, 0, 0) { return false }
	}
	if window != nil { artifacts.screenshot(filename) }
	return true
}

arena_smoke_encounter :: proc(window: ^app.Window, renderer: ^render.Renderer,
	node: game.Run_Node, report: ^Arena_Smoke_Report) -> bool {
	started := time.tick_now()
	active_node := node
	blueprint, error := game.generate_room_blueprint(&active_node)
	report.generation_ms += time.duration_milliseconds(time.tick_since(started))
	if error != .None { return tactical_polish_check(false, "arena blueprint generation failed") }
	defer game.destroy_room_blueprint(&blueprint)
	player, created := game.create_player({max_health = 1000, attack = 2, defense = 1})
	if !created || !game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG) { return false }
	room, built := game.create_room(&blueprint.level_data, &player, game.room_blueprint_content(&blueprint))
	if !built { return false }
	defer game.destroy_room(&room)
	report.rooms += 1
	report.largest_roster = max(report.largest_roster, len(room.enemies))
	if window != nil {
		fmt.printf("Arena depth %d: %dx%d %v, %d enemies\n", node.depth,
			blueprint.level_data.tiles.width, blueprint.level_data.tiles.height, room.family, len(room.enemies))
	}
	render.clear_event_animations(renderer)
	render.reset_tactical_orbit(&renderer.tactical.world_orbit)
	render.reset_tactical_orbit(&renderer.tactical.hologram_orbit)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	buffer: run_session.Buffered_Gameplay_Command
	if !arena_smoke_capture(window, renderer, &room, &controller, &cards, &buffer, report,
		fmt.ctprintf("odin_pp_arenas_depth_%d_combat.png", node.depth)) { return false }
	// The ordinary hologram control consumes real pulse time, even on the
	// largest board. Its first quarter second cannot trigger a defense QTE.
	run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 0, true,
		{focused = true, map_input = {toggle = true}})
	if !controller.hologram || !arena_smoke_step(window, renderer, &room, &controller, &cards, &buffer, report, 0.25, 0.25) { return false }
	if !tactical_polish_check(abs(player.tactical.remaining-19.75) < 0.0001 && player.tactical.metrics.hologram_seconds == 0.25,
		"large-room hologram did not consume pulse time") { return false }
	if !arena_smoke_capture(window, renderer, &room, &controller, &cards, &buffer, report,
		fmt.ctprintf("odin_pp_arenas_depth_%d_map.png", node.depth)) { return false }
	run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 0, true,
		{focused = true, map_input = {toggle = true}})
	// Reach the chasers' first action, not merely a world-clock marker.
	if controller.hologram || !arena_smoke_step(window, renderer, &room, &controller, &cards, &buffer, report, 2.75, 2.75) { return false }
	if !tactical_polish_check(room.pulse_count == 3 && render.renderer_world_is_busy(renderer) &&
		!render.renderer_blocks_player_input(renderer), "large roster blocked the independent player lane") { return false }
	moved := false
	for direction in game.Move_Direction {
		destination := game.add_position(player.position, game.direction_offset(direction))
		_, occupied := game.enemy_index_at(&room, destination)
		if occupied || game.cell_blocks_movement(&room, destination) { continue }
		moved = tactical_independent_fresh_move(&controller, &room, renderer, &cards, &buffer, direction)
		if moved { report.combat_moves += 1; break }
	}
	if !tactical_polish_check(moved, "fresh movement failed while large roster animated") { return false }
	if !arena_smoke_settle(window, renderer, &room, &controller, &cards, &buffer, report) { return false }
	// Exercise the actual mixed roster long enough for every normal cadence.
	// Health is intentionally high: this probes flow and CPU cost, not balance.
	for _ in 0..<1000 {
		if player.tactical.metrics.decision_seconds >= 6 && room.pulse_count >= 7 { break }
		if !arena_smoke_step(window, renderer, &room, &controller, &cards, &buffer, report, 0.1, 0.1) { return false }
	}
	if !arena_smoke_settle(window, renderer, &room, &controller, &cards, &buffer, report) { return false }
	if !tactical_polish_check(room.phase == .Combat && player.tactical.metrics.decision_seconds >= 6 &&
		room.pulse_count >= 7 && !room.tactical_pulse.pending, "large encounter cadence failed to progress") { return false }
	report.world_beats += room.pulse_count
	if node.depth == 6 && !arena_smoke_capture(window, renderer, &room, &controller, &cards, &buffer, report,
		"odin_pp_arenas_boss_active.png") { return false }
	// Resolve a finisher through ordinary effects and the normal phase epilogue.
	// No phase mutation or enemy-list clearing hides a broken transition.
	before := render.capture_room_presentation(&room)
	game.clear_event_log(room.recent_events)
	action := game.Action{kind = .Ability, source = game.PLAYER_ENTITY}
	for enemy in room.enemies {
		action.effects[action.effect_count] = {kind = .Damage, target = game.enemy_entity(enemy.id), amount = 1000}
		action.effect_count += 1
	}
	resolved := game.resolve_action(&room, &action)
	if !resolved.accepted { return false }
	game.append_event_log(room.recent_events, &resolved.events)
	game.finish_player_combat_command(&room, 0)
	after := render.capture_room_presentation(&room)
	if !render.begin_renderer_event_timeline(renderer, before, room.recent_events, &after) || room.phase != .Loot { return false }
	if !arena_smoke_settle(window, renderer, &room, &controller, &cards, &buffer, report) { return false }
	for _ in 0..<13 {
		if !arena_smoke_step(window, renderer, &room, &controller, &cards, &buffer, report, 0.1, 0) { return false }
	}
	if window != nil && !tactical_polish_check(renderer.tactical.no_fog && renderer.tactical.clear_light >= 0.999,
		"large cleared room did not brighten") { return false }
	if node.depth == 6 && !arena_smoke_capture(window, renderer, &room, &controller, &cards, &buffer, report,
		"odin_pp_arenas_loot.png") { return false }
	clock, beats := player.tactical.remaining, room.pulse_count
	for _ in 0..<blueprint.level_data.tiles.width*blueprint.level_data.tiles.height {
		if room.phase != .Loot { break }
		direction, found := tactical_route_move(&room)
		if !found || !run_session.commit_gameplay_command(&room, renderer, &cards, {kind = .Move, origin_phase = .Loot, direction = direction}) { return false }
		report.loot_moves += 1
		if !arena_smoke_settle(window, renderer, &room, &controller, &cards, &buffer, report) { return false }
	}
	if !tactical_polish_check(room.phase == .Complete && player.tactical.remaining == clock && room.pulse_count == beats,
		"large-room loot path or free exploration failed") { return false }
	game.destroy_room(&room)
	previous_family := blueprint.profile.level_config.family
	next_node := game.Run_Node{id = node.id+1, depth = node.depth+1, kind = .Combat, room_seed = node.room_seed+1}
	game.destroy_room_blueprint(&blueprint)
	blueprint, error = game.generate_room_blueprint(&next_node, previous_family)
	if error != .None { return false }
	room, built = game.create_room(&blueprint.level_data, &player, game.room_blueprint_content(&blueprint))
	if !built || player.tactical.remaining != 20 || player.tactical.cycle != 0 || room.pulse_count != 0 { return false }
	render.clear_event_animations(renderer)
	if !arena_smoke_capture(window, renderer, &room, &controller, &cards, &buffer, report,
		fmt.ctprintf("odin_pp_arenas_depth_%d_next.png", node.depth)) { return false }
	if window != nil && !tactical_polish_check(!renderer.tactical.no_fog && renderer.tactical.clear_light == 0,
		"next large room retained cleared-room lighting") { return false }
	report.transitions += 1
	return window == nil || (report.map_draw_frames > 0 && report.combat_draw_frames > 0)
}

run_arena_smoke :: proc(window: ^app.Window, renderer: ^render.Renderer, report: ^Arena_Smoke_Report) -> bool {
	for depth in ([4]int{0, 2, 4, 6}) {
		node := game.Run_Node{id = game.Node_Id(depth+1), depth = depth,
			kind = .Boss if depth == 6 else .Combat, room_seed = u64(7919+depth)}
		if !arena_smoke_encounter(window, renderer, node, report) {
			fmt.eprintf("Arena smoke failed at depth %d\n", depth)
			return false
		}
	}
	return true
}

run_arena_view_smoke :: proc(window: ^app.Window, renderer: ^render.Renderer, dice: ^render.Dice_Renderer) -> bool {
	report: Arena_Smoke_Report
	ok := run_arena_smoke(window, renderer, &report)
	if ok {
		fmt.printf("Arena smoke: %d rooms; up to %d enemies; %d independent combat moves; %d loot moves; %d world beats; %d transitions; no dropped events; world queue peak %d; generation %.2fms; simulation %.3fms/frame (peak %.3fms), excludes GPU/present\n",
			report.rooms, report.largest_roster, report.combat_moves, report.loot_moves, report.world_beats,
			report.transitions, report.world_high_water, report.generation_ms,
			report.simulation_ms/f64(max(1, report.frames)), report.peak_simulation_ms)
		if window != nil {
			fmt.printf("Arena CPU draw submission: world %d frames %.3fms avg %.3fms peak; hologram %d frames %.3fms avg %.3fms peak; excludes present/vsync/PNG and is not GPU time\n",
				report.combat_draw_frames, report.combat_draw_ms/f64(report.combat_draw_frames), report.combat_draw_peak_ms,
				report.map_draw_frames, report.map_draw_ms/f64(report.map_draw_frames), report.map_draw_peak_ms)
		}
	}
	return ok
}
