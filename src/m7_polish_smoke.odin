package main

import "core:fmt"
import rl "vendor:raylib"
import app "app"
import game "game"
import level "level"
import render "render"

m7_polish_check :: proc(valid: bool, description: string) -> bool {
	if !valid { fmt.eprintln("M7 polish flow:", description) }
	return valid
}

// The probe follows the window's presentation order. Gameplay is always issued
// through the normal command dispatcher and waits for its actual event timeline.
m7_polish_frame :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room) {
	render.advance_sprite_assets(&renderer.sprite_assets, 1.0/60.0)
	render.update_renderer_frame_timeline(renderer, 1.0/60.0)
	render.update_tactical_view(renderer, room, {}, false, true)
	render.update_tactical_atmosphere(renderer, 1.0/60.0)
	app.begin_canvas(window, render.RESIN_BACKGROUND)
	render.draw_tactical_world(renderer, room, 0)
	render.draw_status(renderer, room, window.scale_mode)
	render.draw_tactical_hand(renderer, room, 0, 0, 0, {})
	render.draw_tactical_hud(renderer, room, false, false)
	app.present(window, render.LETTERBOX_COLOR)
}

m7_polish_settle :: proc(window: ^app.Window, renderer: ^render.Renderer,
	room: ^game.Room, cards: ^Card_Interaction_State) -> bool {
	controller := Tactical_Controller{was_focused = true}
	buffer: Buffered_Gameplay_Command
	for _ in 0..<1200 {
		cast_dt := min(f32(1.0/60.0), room.player.tactical.cast_remaining)
		m7_polish_frame(window, renderer, room)
		if cast_dt > 0 { step_tactical_controller(&controller, room, renderer, cards, &buffer, cast_dt, true, {focused = true}) }
		if !m7_polish_check(renderer.timeline.update_failures == 0, "timeline update failed") { return false }
		if render.renderer_timeline_is_busy(renderer) || game.tactical_is_casting(room) { continue }
		// This archer is aiming at the cell that the player just left. A defense
		// prompt here would mean the fixture no longer describes its own rules.
		if !m7_polish_check(room.qte.kind == .None, "unexpected defense in aimed-shot fixture") { return false }
		if room.tactical_pulse.pending {
			if !commit_gameplay_command(room, renderer, cards, {kind = .Continue_Pulse, origin_phase = .Combat}) { return false }
			continue
		}
		return true
	}
	return m7_polish_check(false, "presentation or pulse did not settle within 1200 frames")
}

m7_polish_command :: proc(window: ^app.Window, renderer: ^render.Renderer,
	room: ^game.Room, cards: ^Card_Interaction_State, command: Gameplay_Command) -> bool {
	if !m7_polish_check(commit_gameplay_command(room, renderer, cards, command), "gameplay command rejected") { return false }
	return m7_polish_settle(window, renderer, room, cards)
}

// A complete room lifecycle, rather than a forced phase switch: moving reveals
// the archer, a ranged card kills it beyond loot magnet range, walking collects
// that drop, and the actual run/reward/route APIs install the following room.
run_m7_polish_smoke :: proc(window: ^app.Window, renderer: ^render.Renderer) -> bool {
	run, created := game.create_run(DEMO_PLAYER_STATS, DEMO_RUN_CONFIG, DEFAULT_RUNTIME_OPTIONS.seed)
	if !created { return false }
	defer game.destroy_run(&run)
	config := game.DEFAULT_TACTICAL_CONFIG
	config.vision_size = 9
	if !game.configure_tactical(&run.player, config) ||
	   !game.initialize_empty_deck(&run.player.deck, game.DEFAULT_DECK_RULES, 71) { return false }
	for id in ([?]game.Card_Id{.Piercing_Ray, .Guard, .Dash, .Battle_Focus, .Strike}) {
		if _, added := game.add_owned_card(&run.player.deck, id); !added { return false }
	}
	rows := [?]string{
		"#############", "#...........#", "#..##.......#", "#..#........#",
		"#....@......#", "#...........#", "#...........#", "#.........>.#", "#############",
	}
	data, err, _ := level.from_ascii(rows[:])
	if err != .None { return false }
	defer level.destroy(&data)
	spawns := [?]game.Enemy_Spawn{{position = {10, 4}, health = 3, attack = 2, archetype = .Archer}}
	room, built := game.create_room(&data, &run.player, {enemies = spawns[:]})
	if !built { return false }
	defer game.destroy_room(&room)
	render.clear_event_animations(renderer)
	render.reset_tactical_orbit(&renderer.tactical.world_orbit)
	cards: Card_Interaction_State
	for _ in 0..<3 { m7_polish_frame(window, renderer, &room) }
	if !m7_polish_check(room.phase == .Combat && !renderer.tactical.no_fog && renderer.tactical.clear_light == 0,
		"initial combat light or fog is wrong") { return false }
	if !m7_polish_check(game.tactical_cell_visible(&room, {1, 4}) && !game.tactical_cell_visible(&room, {10, 4}),
		"fixture must start with the archer beyond vision") { return false }
	if !m7_polish_command(window, renderer, &room, &cards, {kind = .Move, origin_phase = .Combat, direction = .East}) { return false }
	if !m7_polish_check(run.player.position == (game.add_position(data.player_spawn, {1, 0})) && room.pulse_count == 1 &&
		game.tactical_cell_visible(&room, {10, 4}) && !game.tactical_cell_visible(&room, {1, 4}) &&
		!render.tactical_render_visible(renderer, {1, 4}), "combat movement or fog without exploration memory failed") { return false }
	for _ in 0..<3 { m7_polish_frame(window, renderer, &room) }
	rl.TakeScreenshot("odin_pp_m7_polish_combat.png")
	ray: u32
	for card in run.player.deck.hand[:run.player.deck.hand_count] { if card.definition_id == .Piercing_Ray { ray = card.id } }
	if !m7_polish_check(ray != 0, "ranged card missing from fixture hand") { return false }
	gold_before := run.player.gold
	if !m7_polish_command(window, renderer, &room, &cards,
		{kind = .Play_Card, origin_phase = .Combat, card_id = ray, target = game.cell_target({10, 4})}) { return false }
	if !m7_polish_check(room.phase == .Loot && len(room.enemies) == 0 && len(room.loot) == 1 &&
		room.qte.kind == .None && !room.tactical_pulse.pending && !run.player.deck.combat_active,
		"ranged kill did not leave a clean loot phase with its distant drop") { return false }
	for _ in 0..<90 { m7_polish_frame(window, renderer, &room) }
	if !m7_polish_check(renderer.tactical.no_fog && renderer.tactical.clear_light >= 0.999 &&
		render.tactical_render_visible(renderer, room.exit_position), "cleared room did not illuminate its exit") { return false }
	rl.TakeScreenshot("odin_pp_m7_polish_loot.png")
	pulses_after_combat, clock_after_combat := room.pulse_count, run.player.tactical.remaining
	if !commit_gameplay_command(&room, renderer, &cards, {kind = .Move, origin_phase = .Loot, direction = .East}) { return false }
	controller := Tactical_Controller{was_focused = true}
	buffer: Buffered_Gameplay_Command
	input := Tactical_Controller_Input{focused = true}
	input.directions[int(game.Move_Direction.East)] = true
	if !m7_polish_check(render.renderer_timeline_is_busy(renderer) &&
		step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 0, true, input) && buffer.occupied,
		"WASD during loot animation was lost instead of buffered") { return false }
	if !m7_polish_settle(window, renderer, &room, &cards) { return false }
	if !m7_polish_check(len(room.loot) == 0 && run.player.gold == gold_before+1,
		"loot movement did not collect the real enemy drop") { return false }
	if !m7_polish_check(!step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
		0, true, {focused = true}), "idle loot controller still blocks the buffered move") { return false }
	buffered, has_buffered := take_gameplay_command(&buffer)
	before_buffered_move := run.player.position
	if !m7_polish_check(has_buffered && buffered.kind == .Move && buffered.direction == .East &&
		m7_polish_command(window, renderer, &room, &cards, buffered) &&
		run.player.position == game.add_position(before_buffered_move, {1, 0}),
		"the buffered loot move did not resume when presentation finished") { return false }
	loot_moves := 2
	for room.phase == .Loot && loot_moves < 32 {
		direction, found := m7_route_move(&room)
		if !m7_polish_check(found, "no route to the exit after combat") { return false }
		if !m7_polish_command(window, renderer, &room, &cards, {kind = .Move, origin_phase = .Loot, direction = direction}) { return false }
		loot_moves += 1
	}
	if !m7_polish_check(room.phase == .Complete && run.player.position == room.exit_position &&
		room.pulse_count == pulses_after_combat && run.player.tactical.remaining == clock_after_combat,
		"loot route did not finish without advancing combat") { return false }
	if !m7_polish_check(game.finish_room(&run, room.phase) == .Reward && game.skip_card_reward(&run) == .Skipped,
		"completed room did not pass through its reward") { return false }
	next := game.INVALID_NODE_ID
	for id in game.available_nodes(&run) {
		node, found := game.node_at(&run, id)
		if found && game.node_kind_has_room(node.kind) { next = id; break }
	}
	if !m7_polish_check(next != game.INVALID_NODE_ID && enter_demo_node(&data, &run, &room, next, true),
		"next combat node could not be entered") { return false }
	render.clear_event_animations(renderer)
	render.frame_level(renderer, &data)
	for _ in 0..<3 { m7_polish_frame(window, renderer, &room) }
	if !m7_polish_check(room.phase == .Combat && !renderer.tactical.no_fog && renderer.tactical.clear_light == 0 &&
		game.tactical_allows_action(&room), "next room retained loot lighting or blocked normal combat input") { return false }
	next_room_origin := run.player.position
	moved_in_next_room := false
	for index in 0..<4 {
		direction := game.Move_Direction(index)
		destination := game.add_position(next_room_origin, game.direction_offset(direction))
		query := game.query_entity_movement(&room, game.PLAYER_ENTITY, destination)
		if !game.movement_query_is_clear(&query) { continue }
		if !m7_polish_command(window, renderer, &room, &cards, {kind = .Move, origin_phase = .Combat, direction = direction}) { return false }
		moved_in_next_room = run.player.position == destination
		break
	}
	if !m7_polish_check(moved_in_next_room && room.phase == .Combat && !renderer.tactical.no_fog &&
		renderer.tactical.clear_light == 0, "movement in the following combat room failed") { return false }
	for _ in 0..<3 { m7_polish_frame(window, renderer, &room) }
	rl.TakeScreenshot("odin_pp_m7_polish_next_room.png")
	fmt.printf("M7 polish: combat move + ranged kill; %d loot moves with buffered WASD; drop collected; reward + next room move; fog/light reset; timeline_errors=%d\n",
		loot_moves, renderer.timeline.update_failures)
	return true
}
