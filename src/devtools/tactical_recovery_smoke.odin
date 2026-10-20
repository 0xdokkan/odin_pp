package devtools
import artifacts "artifacts"
import run_session "../run"

import "core:fmt"
import app "../engine/app"
import game "../game"
import level "../level"
import render "../render"

// Advance recovery with actual frame time, including defense QTEs. Visual
// playback is deliberately independent of the countdown and never seeks ahead.
tactical_visual_finish_recovery :: proc(probe: ^Tactical_Visual_Probe, window: ^app.Window,
	renderer: ^render.Renderer, room: ^game.Room, cards: ^run_session.Card_Interaction_State) -> bool {
	controller := run_session.Tactical_Controller{was_focused = true}
	buffer: run_session.Buffered_Gameplay_Command
	for _ in 0..<1200 {
		if room.phase != .Combat || (room.player.tactical.phase == .Decision && !room.tactical_pulse.pending) { return true }
		run_session.step_tactical_controller(&controller, room, renderer, cards, &buffer,
			1.0/60.0, true, {focused = true})
		if !tactical_visual_frame(probe, window, renderer, room) { return false }
	}
	return tactical_polish_check(false, "fixed recovery did not finish through focused frame time")
}

run_tactical_recovery_smoke :: proc(window: ^app.Window, renderer: ^render.Renderer) -> bool {
	rows := [?]string{
		"###############", "#.............#", "#.............#", "#...#.........#",
		"#......@......#", "#.............#", "#.............#", "#..........>..#", "###############",
	}
	data, error, _ := level.from_ascii(rows[:])
	if error != .None { return false }
	defer level.destroy(&data)
	player, created := game.create_player({max_health = 100, attack = 2, defense = 1})
	config := game.DEFAULT_TACTICAL_CONFIG
	config.timer_seconds, config.vision_size = 2, 0
	if !created || !game.configure_tactical(&player, config) ||
	   !game.initialize_empty_deck(&player.deck, game.DEFAULT_DECK_RULES, 93) { return false }
	for id in ([?]game.Card_Id{.Guard, .Strike, .Dash, .Firebomb, .Heavy_Blow}) {
		if _, added := game.add_owned_card(&player.deck, id); !added { return false }
	}
	spawns := [?]game.Enemy_Spawn{
		{position = {2, 4}, health = 20, attack = 2},
		{position = {8, 4}, health = 20, attack = 2, archetype = .Brute},
	}
	room, built := game.create_room(&data, &player, {enemies = spawns[:]})
	if !built { return false }
	defer game.destroy_room(&room)
	render.clear_event_animations(renderer)
	render.reset_tactical_orbit(&renderer.tactical.world_orbit)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	buffer: run_session.Buffered_Gameplay_Command
	probe: Tactical_Visual_Probe
	for capture in Tactical_Visual_Capture { probe.captured += {capture} }
	// The timeout frame must discard old interaction state but already allow a
	// fresh walk. The real chaser movement remains on the background timeline.
	if !tactical_polish_check(!run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
		2, true, {focused = true}) && player.tactical.phase == .Recovery &&
		player.tactical.remaining == 1 && render.renderer_world_is_busy(renderer),
		"deadline did not enter a movable one-second recovery") { return false }
	guard: u32
	for card in player.deck.hand[:player.deck.hand_count] {
		if card.definition_id == .Guard { guard = card.id }
	}
	before := player
	for command in ([?]run_session.Gameplay_Command{
		{kind = .Move, origin_phase = .Combat, direction = .East},
		{kind = .Play_Card, origin_phase = .Combat, card_id = guard, target = game.entity_target(game.PLAYER_ENTITY)},
		{kind = .Refocus, origin_phase = .Combat},
	}) {
		if !tactical_polish_check(!run_session.execute_gameplay_command(&room, command).committed,
			"recovery accepted an attack, card or refocus") { return false }
	}
	if !tactical_polish_check(player == before && tactical_independent_fresh_move(&controller, &room, renderer,
		&cards, &buffer, .South) && player.tactical.remaining == 1,
		"walking charged recovery time or blocked behind enemy playback") { return false }
	for frame in 0..<8 {
		if !tactical_visual_frame(&probe, window, renderer, &room, dt = 0.125) { return false }
		run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer,
			0.125, true, {focused = true})
		if frame == 3 {
			if !tactical_polish_check(player.tactical.phase == .Recovery && player.tactical.remaining == 0.5 &&
				tactical_independent_fresh_move(&controller, &room, renderer, &cards, &buffer, .East) &&
				player.tactical.remaining == 0.5, "fresh walk changed the fixed recovery deadline") { return false }
			if window != nil {
				if !tactical_visual_frame(&probe, window, renderer, &room, dt = 0) { return false }
				artifacts.screenshot("odin_pp_m7_recovery_walk.png")
			}
		}
		if frame < 7 && !tactical_polish_check(player.tactical.phase == .Recovery,
			"recovery ended before one second of focused clock") { return false }
	}
	if !tactical_polish_check(player.tactical.phase == .Decision && player.tactical.remaining == 2 &&
		room.pulse_count == 3 && player.tactical.metrics.forced_pulses == 1 &&
		player.tactical.metrics.decisions == 0 && player.position == {8, 5} &&
		!room.tactical_pulse.pending && room.qte.kind == .None,
		"one-second recovery failed to restore the full configured pulse") { return false }
	if !tactical_polish_check(run_session.commit_gameplay_command(&room, renderer, &cards,
		{kind = .Play_Card, origin_phase = .Combat, card_id = guard, target = game.entity_target(game.PLAYER_ENTITY)}),
		"card input did not return after recovery") { return false }
	if window != nil {
		fmt.printf("M7 recovery: 1.000s focused clock; two free walks; attack/card/refocus rejected; enemy beat continued; next pulse/card ready; playback=%.0fx\n",
			render.renderer_playback_speed(renderer))
	}
	return renderer.timeline.update_failures == 0 && renderer.timeline.dropped_count == 0
}
