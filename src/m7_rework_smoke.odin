package main

import rl "vendor:raylib"
import app "app"
import game "game"
import level "level"
import render "render"

draw_m7_rework_probe :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room,
	selected: u32 = 0, inspect_enemy: bool = false) {
	render.update_tactical_view(renderer, room, {}, false, true)
	if inspect_enemy { renderer.has_hovered_cell, renderer.hovered_cell = true, room.enemies[2].position }
	app.begin_canvas(window, render.RESIN_BACKGROUND)
	render.draw_tactical_world(renderer, room, selected)
	render.draw_status(renderer, room, window.scale_mode)
	render.draw_tactical_hand(renderer, room, 0, selected, 0, {})
	render.draw_tactical_hud(renderer, room, false, false)
	app.present(window, render.LETTERBOX_COLOR)
}

run_m7_rework_smoke :: proc(window: ^app.Window, renderer: ^render.Renderer) -> bool {
	rows := [?]string{"###########", "#.........#", "#.........#", "#.........#", "#....@....#", "#.........#", "#.........#", "#....>....#", "###########"}
	data, err, _ := level.from_ascii(rows[:])
	if err != .None { return false }
	defer level.destroy(&data)
	player, created := game.create_player(DEMO_PLAYER_STATS)
	if !created || !game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG) ||
	   !game.initialize_empty_deck(&player.deck, game.DEFAULT_DECK_RULES, 71) { return false }
	for id in ([?]game.Card_Id{.Strike, .Dash, .Heavy_Blow, .Battle_Focus, .Guard}) {
		if _, added := game.add_owned_card(&player.deck, id); !added { return false }
	}
	spawns := [?]game.Enemy_Spawn{{position = {6, 4}, health = 24, attack = 2},
		{position = {5, 1}, health = 12, attack = 2, archetype = .Archer},
		{position = {8, 6}, health = 14, attack = 2, archetype = .Bomber},
		{position = {3, 6}, health = 24, attack = 3, archetype = .Brute},
		{position = {7, 6}, health = 18, attack = 1, archetype = .Custodian}}
	room, built := game.create_room(&data, &player, {enemies = spawns[:]})
	if !built { return false }
	defer game.destroy_room(&room)
	renderer.timeline = {}
	render.reset_tactical_orbit(&renderer.tactical.world_orbit)
	heavy, focus: u32
	for card in player.deck.hand[:player.deck.hand_count] {
		if card.definition_id == .Heavy_Blow { heavy = card.id }
		if card.definition_id == .Battle_Focus { focus = card.id }
	}
	if heavy == 0 || focus == 0 { return false }
	for _ in 0..<3 { draw_m7_rework_probe(window, renderer, &room, heavy) }
	rl.TakeScreenshot("odin_pp_m7_rework_cards.png")
	for _ in 0..<3 { draw_m7_rework_probe(window, renderer, &room, 0, true) }
	rl.TakeScreenshot("odin_pp_m7_rework_enemy.png")
	cards: Card_Interaction_State
	if !commit_gameplay_command(&room, renderer, &cards,
		{kind = .Play_Card, origin_phase = .Combat, card_id = heavy, target = game.entity_target(game.enemy_entity(1))}) { return false }
	for _ in 0..<600 {
		render.update_renderer_frame_timeline(renderer, 1.0/30.0)
		draw_m7_rework_probe(window, renderer, &room)
		if render.renderer_timeline_is_busy(renderer) { continue }
		if !room.tactical_pulse.pending { break }
		command := Gameplay_Command{kind = .Continue_Pulse, origin_phase = .Combat}
		if room.qte.kind != .None { command.kind = .QTE_Fail }
		if !commit_gameplay_command(&room, renderer, &cards, command) { return false }
	}
	if room.pulse_count != u64(game.tactical_card_time_cost(.Heavy_Blow)) || room.tactical_pulse.pending ||
	   room.enemies[0].health != 20 || player.health != player.stats.max_health { return false }
	if !commit_gameplay_command(&room, renderer, &cards,
		{kind = .Play_Card, origin_phase = .Combat, card_id = focus, target = game.entity_target(game.PLAYER_ENTITY)}) { return false }
	for _ in 0..<300 {
		render.update_renderer_frame_timeline(renderer, 1.0/30.0)
		draw_m7_rework_probe(window, renderer, &room)
		if render.renderer_timeline_is_busy(renderer) { continue }
		if !room.tactical_pulse.pending { break }
		command := Gameplay_Command{kind = .Continue_Pulse, origin_phase = .Combat}
		if room.qte.kind != .None { command.kind = .QTE_Fail }
		if !commit_gameplay_command(&room, renderer, &cards, command) { return false }
	}
	rl.TakeScreenshot("odin_pp_m7_rework_survey.png")
	return !render.renderer_timeline_is_busy(renderer) && !room.tactical_pulse.pending && renderer.timeline.update_failures == 0 &&
		game.tactical_cell_visible(&room, {1, 4})
}
