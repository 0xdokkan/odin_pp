package devtools
import artifacts "artifacts"
import run_session "../run"

import "core:fmt"
import app "../engine/app"
import game "../game"
import level "../level"
import render "../render"

// Exercise the real controller and bounded presentation continuations. Idle
// time advances during enemy movement; card casts pause only enemy time;
// there is no direct enemy/state advancement here.
run_tactical_timed_pulse_smoke :: proc(window: ^app.Window, renderer: ^render.Renderer) -> bool {
	rows := [?]string{
		"###############", "#.............#", "#.............#", "#..##.........#",
		"#......@......#", "#.............#", "#.............#", "#..........>..#", "###############",
	}
	data, err, _ := level.from_ascii(rows[:])
	if err != .None { return false }
	defer level.destroy(&data)
	player, created := game.create_player({max_health = 100, attack = 2, defense = 1})
	config := game.DEFAULT_TACTICAL_CONFIG
	config.vision_size = 0
	if !created || !game.configure_tactical(&player, config) ||
	   !game.initialize_empty_deck(&player.deck, game.DEFAULT_DECK_RULES, 73) { return false }
	for id in ([?]game.Card_Id{.Guard, .Strike, .Dash, .Firebomb, .Heavy_Blow}) {
		if _, added := game.add_owned_card(&player.deck, id); !added { return false }
	}
	spawns := [?]game.Enemy_Spawn{
		{position = {x = 2, y = 4}, health = 20, attack = 2},
		{position = {x = 11, y = 6}, health = 20, attack = 2, archetype = .Brute},
		{position = {x = 11, y = 2}, health = 20, attack = 2, archetype = .Archer},
	}
	room, built := game.create_room(&data, &player, {enemies = spawns[:]})
	if !built { return false }
	defer game.destroy_room(&room)
	render.clear_event_animations(renderer)
	render.reset_tactical_orbit(&renderer.tactical.world_orbit)
	probe: Tactical_Visual_Probe
	// These captures belong to the existing VFX probe, not this timing fixture.
	for capture in Tactical_Visual_Capture { probe.captured += {capture} }
	cards: run_session.Card_Interaction_State
	guard: u32
	for card in player.deck.hand[:player.deck.hand_count] {
		if card.definition_id == .Guard { guard = card.id }
	}
	if guard == 0 { return false }
	for direction, index in ([2]game.Move_Direction{.East, .West}) {
		if !tactical_visual_command(&probe, window, renderer, &room, &cards,
			{kind = .Move, origin_phase = .Combat, direction = direction}) { return false }
		if !tactical_polish_check(player.tactical.phase == .Decision && player.tactical.cycle == 0 &&
			abs(player.tactical.remaining-(f32(config.timer_seconds)-f32(index+1)*game.TACTICAL_MOVE_SECONDS)) < 0.0001 && player.tactical.budget == config.timer_seconds,
			"a move ended or refilled the shared timed pulse") { return false }
	}
	if !tactical_visual_command(&probe, window, renderer, &room, &cards,
		{kind = .Play_Card, origin_phase = .Combat, card_id = guard,
		 target = game.entity_target(game.PLAYER_ENTITY)}) { return false }
	after_actions := f32(config.timer_seconds)-2*game.TACTICAL_MOVE_SECONDS-game.tactical_card_time_cost(.Guard)
	if !tactical_polish_check(player.position == data.player_spawn && abs(player.tactical.remaining-after_actions) < 0.0001 &&
		player.tactical.cycle == 0 && player.tactical.phase == .Decision && room.pulse_count == 1 &&
		player.tactical.metrics.decisions == 3 && room.enemies[0].position == spawns[0].position &&
		room.enemies[1].position == spawns[1].position,
		"three commands did not share their countdown or advance enemy time") { return false }
	for _ in 0..<3 { if !tactical_visual_frame(&probe, window, renderer, &room) { return false } }
	if window != nil { artifacts.screenshot("odin_pp_m7_timed_actions.png") }
	controller := run_session.Tactical_Controller{was_focused = true}
	buffer: run_session.Buffered_Gameplay_Command
	if !run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 0, true,
		{focused = true, map_input = {toggle = true}}) || !controller.hologram { return false }
	before_enemy := room.enemies[0].position
	before_clock := player.tactical.metrics.decision_seconds
	for _ in 0..<1200 {
		elapsed := player.tactical.metrics.decision_seconds-before_clock
		dt := f32(min(f64(0.125), max(f64(0), 1.5-elapsed)))
		if !tactical_visual_frame(&probe, window, renderer, &room, dt = dt if dt > 0 else 1.0/60.0) { return false }
		run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
			dt, true, {focused = true})
		if elapsed >= 1.5 && !room.tactical_pulse.pending && !render.renderer_timeline_is_busy(renderer) { break }
	}
	if !tactical_polish_check(abs(player.tactical.remaining-(after_actions-1.5)) < 0.0001 && room.pulse_count == 3 &&
		player.position == data.player_spawn && room.enemies[0].position != before_enemy &&
		room.enemies[1].position == spawns[1].position &&
		controller.hologram && player.tactical.metrics.hologram_seconds == 1.5 &&
		player.tactical.phase == .Decision && player.tactical.cycle == 0 && room.qte.kind == .None,
		"hologram or idle time froze the enemy cadence or restarted the shared pulse") { return false }
	if window != nil {
		for _ in 0..<3 {
			render.update_tactical_view(renderer, &room, {}, false, true)
			app.begin_canvas(window, render.RESIN_BACKGROUND)
			render.draw_hologram(renderer, &room)
			render.draw_tactical_hud(renderer, &room, false, true)
			app.present(window, render.LETTERBOX_COLOR)
		}
		artifacts.screenshot("odin_pp_m7_timed_hologram.png")
		fmt.printf("M7 timed pulse: 2 moves + Guard in one window; %.2fs -> %.2fs after 1.5s hologram; 3 world beats; card cast freezes enemy rhythm; timeline_errors=%d\n",
			after_actions, player.tactical.remaining, renderer.timeline.update_failures)
	}
	return renderer.timeline.update_failures == 0 && !room.tactical_pulse.pending
}
