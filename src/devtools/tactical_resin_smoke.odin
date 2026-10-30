package devtools
import artifacts "artifacts"
import run_session "../run"

import "core:fmt"
import app "../engine/app"
import game "../game"
import level "../level"
import render "../render"

draw_tactical_probe :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room,
	overlay: app.Window_Overlay = nil, overlay_data: rawptr = nil) {
	render.update_tactical_view(renderer, room, {}, false, true)
	app.begin_canvas(window, render.RESIN_BACKGROUND)
	render.draw_tactical_world(renderer, room, 0)
	render.draw_status(renderer, room, window.scale_mode)
	render.draw_tactical_hand(renderer, room, 0, 0, 0, {})
	render.draw_tactical_hud(renderer, room, false, false)
	app.present(window, render.LETTERBOX_COLOR, overlay, overlay_data)
}

run_tactical_resin_smoke :: proc(window: ^app.Window, renderer: ^render.Renderer, dice: ^render.Dice_Renderer) -> bool {
	run, ok := game.create_run(run_session.DEMO_PLAYER_STATS, run_session.DEMO_RUN_CONFIG, run_session.DEFAULT_OPTIONS.seed)
	if !ok { return false }
	defer game.destroy_run(&run)
	if !run_session.configure_demo_tactical_player(&run.player, game.DEFAULT_TACTICAL_CONFIG) { return false }
	data: level.Level
	defer level.destroy(&data)
	room: game.Room
	defer game.destroy_room(&room)
	if !run_session.replace_current_demo_room(&data, &run, &room, true) { return false }
	if data.tiles.width != 17 || data.tiles.height != 11 || len(room.enemies) < 4 { return false }
	renderer.timeline = {}
	render.reset_tactical_orbit(&renderer.tactical.world_orbit)
	for _ in 0..<3 { draw_tactical_probe(window, renderer, &room) }
	artifacts.screenshot("odin_pp_m7_expanded_room.png")
	run.player.tactical.config.vision_size = 0
	for _ in 0..<3 { draw_tactical_probe(window, renderer, &room) }
	artifacts.screenshot("odin_pp_m7_expanded_overview.png")
	game.destroy_room(&room)
	level.destroy(&data)
	rows := [?]string{"###########", "#.........#", "#.........#", "#.........#", "#....@....#", "#.........#", "#.........#", "#....>....#", "###########"}
	err: level.Parse_Error
	data, err, _ = level.from_ascii(rows[:])
	if err != .None { return false }
	game.finish_deck_combat(&run.player.deck)
	if !game.configure_tactical(&run.player, game.DEFAULT_TACTICAL_CONFIG) ||
	   !game.initialize_empty_deck(&run.player.deck, game.DEFAULT_DECK_RULES, 71) { return false }
	for card in ([?]game.Card_Id{.Prismatic_Barrage, .Fate_Strike, .Guard, .Shove, .Afterimage}) {
		if _, added := game.add_owned_card(&run.player.deck, card); !added { return false }
	}
	enemies := [?]game.Enemy_Spawn{{position = {x = 7, y = 4}, health = 100, attack = 1, archetype = .Brute}}
	room, ok = game.create_room(&data, &run.player, {enemies = enemies[:]})
	if !ok { return false }
	renderer.timeline = {}
	cards: run_session.Card_Interaction_State
	card_id: u32
	for card in run.player.deck.hand[:run.player.deck.hand_count] {
		if card.definition_id == .Prismatic_Barrage { card_id = card.id }
	}
	if card_id == 0 || !run_session.commit_gameplay_command(&room, renderer, &cards,
		{kind = .Play_Card, origin_phase = .Combat, card_id = card_id, target = game.entity_target(game.enemy_entity(1))}) { return false }
	committed_dice := run.player.dice
	shots := 0
	controller := run_session.Tactical_Controller{was_focused = true}
	buffer: run_session.Buffered_Gameplay_Command
	for _ in 0..<600 {
		cast_dt := min(f32(1.0/30.0), run.player.tactical.cast_remaining)
		render.update_renderer_frame_timeline(renderer, 1.0/30.0)
		run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer, cast_dt, true, {focused = true})
		cue, found := render.active_presentation_cue(&renderer.timeline)
		drawing := found && cue.started && cue.kind == .Dice_Rolled
		overlay: app.Window_Overlay
		state: run_session.Dice_Window_Overlay
		if drawing {
			overlay = run_session.draw_window_dice_overlay
			state = {renderer = dice, roll = cue.event.dice_roll, progress = render.presentation_cue_progress(cue),
				seed = run_session.dice_event_visual_seed(cue.event), card = cue.event.card_definition, outcome = render.dice_presentation_outcome(&renderer.timeline)}
			run_session.update_window_dice_overlay(window, &state)
		}
		draw_tactical_probe(window, renderer, &room, overlay, &state)
		if drawing && ((shots == 0 && state.progress >= 0.4) || (shots == 1 && state.progress >= 0.97)) {
			artifacts.screenshot(fmt.ctprintf("odin_pp_m7_resin_dice_%d.png", shots))
			shots += 1
		}
		if !render.renderer_timeline_is_busy(renderer) && !game.tactical_is_casting(&room) { break }
	}
	return shots == 2 && !game.tactical_is_casting(&room) && run.player.dice == committed_dice && renderer.timeline.update_failures == 0
}
