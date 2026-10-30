package devtools
import artifacts "artifacts"
import run_session "../run"

import "core:fmt"
import app "../engine/app"
import game "../game"
import level "../level"
import render "../render"
import western "../western"

western_smoke_frame :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, session: ^run_session.Player_Activities, dt: f32) {
	// The bubble is modal: like the run scene, the board timeline waits for it.
	if !session.ranch.active { render.update_renderer_frame_timeline(renderer, dt) }
	render.advance_sprite_assets(&renderer.sprite_assets, dt)
	render.update_tactical_view(renderer, room, {}, false, true)
	render.update_tactical_atmosphere(renderer, dt)
	app.begin_canvas(window, render.RESIN_BACKGROUND)
	render.draw_tactical_world(renderer, room, 0)
	render.draw_tactical_status(renderer, room)
	render.draw_tactical_hand(renderer, room, 0, 0, 0, {})
	render.draw_tactical_hud(renderer, room, false, false)
	if session.ranch.active { render.draw_western_bubble(renderer, room, &session.ranch.state, session.ranch.card_from) }
	app.present(window, render.LETTERBOX_COLOR)
}

// 6 RANCH 7 in the real window: with the pair in hand the bubble opens over the
// board by itself, the cards fly to the sign, and the ride is pressed on the ticks.
run_western_smoke :: proc(window: ^app.Window, renderer: ^render.Renderer, dice: ^render.Dice_Renderer) -> bool {
	rows := [?]string{"###########", "#.........#", "#.........#", "#.........#", "#....@....#", "#.........#", "#.........#", "#........>#", "###########"}
	data, error, _ := level.from_ascii(rows[:])
	if error != .None { return false }
	defer level.destroy(&data)
	player, created := game.create_player({max_health = 22, attack = 2, defense = 0})
	config := game.DEFAULT_TACTICAL_CONFIG
	config.vision_size = 0
	if !created || !game.configure_tactical(&player, config) || !game.initialize_empty_deck(&player.deck, {5, 12, 1}, 812) { return false }
	for id in ([5]game.Card_Id{.Strike, .Sei_Denari, .Guard, .Sette_Denari, .Heavy_Blow}) {
		if _, added := game.add_owned_card(&player.deck, id); !added { return false }
	}
	player.health = 9
	enemies := [?]game.Enemy_Spawn{{position = {x = 3, y = 2}, health = 30, attack = 1}, {position = {x = 7, y = 6}, health = 30, attack = 1, archetype = .Brute}}
	room, built := game.create_room(&data, &player, {enemies = enemies[:]})
	if !built { return false }
	defer game.destroy_room(&room)
	render.clear_event_animations(renderer)
	render.reset_tactical_orbit(&renderer.tactical.world_orbit)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	buffer: run_session.Buffered_Gameplay_Command
	session: run_session.Player_Activities
	if !m8_smoke_settle(window, renderer, dice, &room, &controller, &cards, &buffer) { return false }
	if !game.western_ranch_can_start(&room) { fmt.eprintln("6 RANCH 7: the pair is not in hand"); return false }
	for _ in 0..<3 { western_smoke_frame(window, renderer, &room, &session, 0) }
	artifacts.screenshot("odin_pp_western_hand.png")
	gold := player.gold
	Shot :: struct { at: f32, phase: western.Phase, name: cstring }
	shots := [?]Shot{
		{0.95, .Intro, "odin_pp_western_cards.png"},
		{2.0, .Intro, "odin_pp_western_sign.png"},
		{2.85, .Intro, "odin_pp_western_gate.png"},
		{3.75, .Intro, "odin_pp_western_riders.png"},
		{western.tick_time(0)-0.08, .Ride, "odin_pp_western_ride.png"},
		{western.tick_time(1)+0.1, .Ride, "odin_pp_western_grab.png"},
		{0.5, .Outro, "odin_pp_western_win.png"},
	}
	shot := 0
	dt := f32(1.0/60.0)
	for frame in 0..<1200 {
		ranch := &session.ranch
		// Press on the frame nearest to each tick.
		press := false
		if ranch.active && ranch.state.phase == .Ride {
			target := western.tick_time(ranch.state.tick)
			press = ranch.state.time+dt >= target-dt*0.5 && ranch.state.offsets[western.PLAYER] == western.NO_PRESS
		}
		consumed := run_session.step_player_activities(&session, &room, renderer, &controller, &cards, &buffer, true, dt, {focused = true, ranch_press = press})
		if frame == 0 && !(consumed && ranch.active) { fmt.eprintln("6 RANCH 7 did not open by itself"); return false }
		if ranch.finished { break }
		western_smoke_frame(window, renderer, &room, &session, dt)
		if shot < len(shots) && ranch.state.phase == shots[shot].phase && ranch.state.time >= shots[shot].at {
			artifacts.screenshot(shots[shot].name)
			shot += 1
		}
	}
	ranch := &session.ranch
	if !ranch.finished || !ranch.reward.won || player.health != player.stats.max_health || player.gold != gold+game.WESTERN_RANCH_GOLD {
		fmt.eprintf("6 RANCH 7 reward missing: finished=%v won=%v health=%d gold=%d\n", ranch.finished, ranch.reward.won, player.health, player.gold-gold)
		return false
	}
	// The reward reads as ordinary feedback over the player.
	for _ in 0..<24 { western_smoke_frame(window, renderer, &room, &session, dt) }
	artifacts.screenshot("odin_pp_western_reward.png")
	if game.western_ranch_can_start(&room) { fmt.eprintln("6 RANCH 7 can reopen on the same floor"); return false }
	return shot == len(shots)
}
