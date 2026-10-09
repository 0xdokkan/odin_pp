package main

import "core:fmt"
import rl "vendor:raylib"
import app "app"
import game "game"
import level "level"
import render "render"

m7_room_refresh_spawn_valid :: proc(room: ^game.Room) -> bool {
	data := room.level_data
	return room.player.position == data.player_spawn &&
		!level.is_interior_corner(data.player_spawn, data.tiles.width, data.tiles.height) &&
		level.has_full_interior_clearance(data.player_spawn, 1, data.tiles.width, data.tiles.height) &&
		game.validate_enemy_intents(room)
}

// Uses actual generated rooms, actions, loot movement, rewards and node entry.
// High health/attack keep this transition probe deterministic; it is not a
// balance sample. Rendering uses the same command/timeline driver as VFX QA.
run_m7_room_refresh_smoke :: proc(window: ^app.Window, renderer: ^render.Renderer) -> bool {
	run, created := game.create_run({max_health = 1000, attack = 20, defense = 1}, DEMO_RUN_CONFIG, DEFAULT_RUNTIME_OPTIONS.seed)
	if !created { return false }
	defer game.destroy_run(&run)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.timer_seconds = 2
	if !configure_demo_tactical_player(&run.player, config) ||
	   !game.initialize_empty_deck(&run.player.deck, game.DEFAULT_DECK_RULES, 77) { return false }
	for id in ([?]game.Card_Id{.Piercing_Ray, .Fate_Strike, .Firebomb, .Heavy_Blow, .Dash}) {
		if _, added := game.add_owned_card(&run.player.deck, id); !added { return false }
	}
	data: level.Level
	defer level.destroy(&data)
	room: game.Room
	defer game.destroy_room(&room)
	if !replace_current_demo_room(&data, &run, &room, true) ||
	   !m7_polish_check(m7_room_refresh_spawn_valid(&room), "first procedural spawn is not centered and clear") { return false }
	render.clear_event_animations(renderer)
	render.reset_tactical_orbit(&renderer.tactical.world_orbit)
	previous_speed := render.renderer_playback_speed(renderer)
	if !render.set_renderer_playback_speed(renderer, 4) { return false }
	defer render.set_renderer_playback_speed(renderer, previous_speed)
	probe: M7_Visual_Probe
	// This smoke owns only its two room captures; do not replace the VFX images.
	for capture in M7_Visual_Capture { probe.captured += {capture} }
	cards: Card_Interaction_State
	for _ in 0..<3 { if !m7_visual_frame(&probe, window, renderer, &room) { return false } }
	if window != nil { rl.TakeScreenshot("odin_pp_m7_room_refresh_first.png") }
	first_spawn := data.player_spawn
	for cycle in 1..=2 {
		for _ in 0..<config.timer_seconds {
			if !m7_visual_command(&probe, window, renderer, &room, &cards,
				{kind = .Wait, origin_phase = .Combat}) { return false }
		}
		if !m7_polish_check(run.player.tactical.cycle == cycle &&
			run.player.tactical.phase == .Recovery && run.player.tactical.remaining == game.TACTICAL_RECOVERY_SECONDS,
			"procedural room did not keep recovery fixed at one second") { return false }
		if !m7_visual_finish_recovery(&probe, window, renderer, &room, &cards) { return false }
	}
	for _ in 0..<256 {
		if room.phase != .Combat { break }
		command := Gameplay_Command{origin_phase = .Combat}
		if run.player.tactical.phase == .Recovery {
			if !m7_visual_finish_recovery(&probe, window, renderer, &room, &cards) { return false }
			continue
		} else {
			for card in run.player.deck.hand[:run.player.deck.hand_count] {
				if command.kind != .None || card.definition_id == .Dash { continue }
				for enemy in room.enemies {
					target, found := game.card_drop_target(&room, card, enemy.position)
					if !found || !game.tactical_target_visible(&room, target) { continue }
					_, error := game.compile_card_action(&room, card, target)
					definition, _ := game.card_definition_by_id(card.definition_id, true)
					if error != .None || definition.cost > run.player.deck.energy { continue }
					command.kind, command.card_id, command.target = .Play_Card, card.id, target
					break
				}
			}
		}
		if command.kind == .None {
			direction, found := m7_route_move(&room)
			if !m7_polish_check(found, "procedural enemies are unreachable") { return false }
			command.kind, command.direction = .Move, direction
		}
		if !m7_visual_command(&probe, window, renderer, &room, &cards, command) { return false }
	}
	if !m7_polish_check(room.phase == .Loot && run.player.tactical.cycle >= 2,
		"procedural fight did not finish with accumulated pressure") {
		fmt.eprintf("M7 room refresh: phase=%v, cycle=%d, player=%v, health=%d, enemies=%d\n",
			room.phase, run.player.tactical.cycle, run.player.position, run.player.health, len(room.enemies))
		return false
	}
	metrics := run.player.tactical.metrics
	completed_cycle := run.player.tactical.cycle
	for _ in 0..<256 {
		if room.phase != .Loot { break }
		direction, found := m7_route_move(&room)
		if !found || !m7_visual_command(&probe, window, renderer, &room, &cards,
			{kind = .Move, origin_phase = .Loot, direction = direction}) { return false }
	}
	if !m7_polish_check(room.phase == .Complete && game.finish_room(&run, room.phase) == .Reward &&
		game.skip_card_reward(&run) == .Skipped, "procedural room failed to reach its reward") { return false }
	next := game.INVALID_NODE_ID
	for id in game.available_nodes(&run) {
		node, found := game.node_at(&run, id)
		if found && game.node_kind_has_room(node.kind) { next = id; break }
	}
	if next == game.INVALID_NODE_ID || !enter_demo_node(&data, &run, &room, next, true) { return false }
	if !m7_polish_check(m7_room_refresh_spawn_valid(&room) && room.pulse_count == 0 &&
		run.player.tactical.cycle == 0 &&
		run.player.tactical.budget == config.timer_seconds && run.player.tactical.remaining == f32(config.timer_seconds) &&
		run.player.tactical.phase == .Decision && run.player.tactical.metrics == metrics &&
		game.tactical_allows_action(&room), "new procedural room retained pressure or an invalid spawn") { return false }
	render.clear_event_animations(renderer)
	if window != nil { render.frame_level(renderer, &data) }
	for _ in 0..<3 { if !m7_visual_frame(&probe, window, renderer, &room) { return false } }
	if window != nil {
		if !m7_polish_check(!renderer.tactical.no_fog && renderer.tactical.clear_light == 0,
			"new procedural room retained cleared-room lighting") { return false }
		rl.TakeScreenshot("odin_pp_m7_room_refresh_next.png")
		fmt.printf("M7 room refresh: centered spawns %v -> %v; cycle %d -> 0; budget/clock reset to %d; cumulative metrics kept; reward + next room; timeline_errors=%d\n",
			first_spawn, data.player_spawn, completed_cycle, config.timer_seconds, renderer.timeline.update_failures)
	}
	return true
}
