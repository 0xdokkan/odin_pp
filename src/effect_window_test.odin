package main

import "core:math"
import "core:mem"
import "core:testing"
import rl "vendor:raylib"
import host "engine/host"
import game "game"
import render "render"
import view "view"

effect_test_center :: proc(bounds: rl.Rectangle) -> view.Vec2 {
	return {bounds.x+bounds.width*0.5, bounds.y+bounds.height*0.5}
}

// A tactical run's session in a fight (host_run_fixture's, with a foe and a
// tactical player): the run renderer is headless, the session not attached.
effect_test_fight :: proc(t: ^testing.T, seed: u64 = 0xC0FFEE) -> ^Roguelike_Session {
	rs := roguelike_session_new()
	ok: bool
	rs.run_state, ok = game.create_run(DEMO_PLAYER_STATS, DEMO_RUN_CONFIG, seed)
	testing.expect(t, ok)
	rs.run_created = true
	testing.expect(t, configure_demo_tactical_player(&rs.run_state.player, rs.options.tactical))
	rs.level_data = create_gameplay_command_test_level(t)
	spawns := [?]game.Enemy_Spawn{{position = {5, 3}, health = 30, attack = 1}}
	rs.room, ok = game.create_room(&rs.level_data, &rs.run_state.player, {enemies = spawns[:]})
	testing.expect(t, ok)
	rs.room_created = true
	testing.expect(t, game.configure_tactical_room(&rs.room, rs.options.tactical))
	rs.run_state.phase = .In_Room
	node, found := game.current_run_node(&rs.run_state)
	testing.expect(t, found)
	node.kind = .Combat
	rs.iso_renderer.canvas_width, rs.iso_renderer.canvas_height = 960, 540
	rs.iso_renderer.tactical.enabled = true
	return rs
}

// The same at the first stop of `kind` after the first room (a shop, a rest).
effect_test_stop :: proc(t: ^testing.T, kind: game.Node_Kind) -> ^Roguelike_Session {
	seed, found := demo_seed_with_first_special(0xC0FFEE, kind)
	testing.expect(t, found)
	rs := effect_test_fight(t, seed)
	rs.room.phase = .Complete
	testing.expect_value(t, game.finish_room(&rs.run_state, .Complete), game.Run_Transition.Reward)
	testing.expect_value(t, game.skip_card_reward(&rs.run_state), game.Card_Reward_Result.Skipped)
	stop := available_node_of_kind(&rs.run_state, kind)
	testing.expect(t, stop != game.INVALID_NODE_ID && game.enter_node(&rs.run_state, stop) != .Invalid)
	return rs
}

effect_test_open :: proc(t: ^testing.T, rs: ^Roguelike_Session, card: game.Card_Instance, source: Effect_Window_Source = .None) {
	testing.expectf(t, open_effect_window_in_run(rs, card, source), "the window opens on %v (%v)", card.definition_id, effect_window_refusal(rs))
}

// Esc, a right click or CHIUDI close it; RICOMINCIA or R start the film
// again; hovering does nothing, a click on the stage or off the panel does
// nothing, and without focus nothing does anything.
@(test)
test_effect_window_closes_only_on_escape_right_click_or_chiudi :: proc(t: ^testing.T) {
	w: Effect_Window
	width, height := f32(960), f32(540)
	on_close := effect_test_center(effect_window_close_bounds(width, height))
	on_restart := effect_test_center(effect_window_restart_bounds(width, height))
	on_stage := effect_test_center(effect_window_stage_bounds(width, height))
	testing.expect_value(t, step_effect_window(&w, {focused = true, inside = true, mouse = on_close}, width, height), Effect_Window_Control.None)
	testing.expect_value(t, w.hovered, Effect_Window_Control.Close)
	testing.expect_value(t, step_effect_window(&w, {focused = true, inside = true, mouse = on_restart}, width, height), Effect_Window_Control.None)
	testing.expect_value(t, w.hovered, Effect_Window_Control.Restart)
	testing.expect_value(t, step_effect_window(&w, {focused = true, inside = true, pressed = true, mouse = on_stage}, width, height), Effect_Window_Control.None)
	testing.expect_value(t, step_effect_window(&w, {focused = true, inside = true, pressed = true, mouse = {4, 4}}, width, height), Effect_Window_Control.None)
	testing.expect_value(t, step_effect_window(&w, {inside = true, pressed = true, escape = true, right_pressed = true, restart = true, mouse = on_close},
		width, height), Effect_Window_Control.None)
	testing.expect_value(t, w.hovered, Effect_Window_Control.None)
	testing.expect_value(t, step_effect_window(&w, {focused = true, inside = true, pressed = true, mouse = on_close}, width, height), Effect_Window_Control.Close)
	testing.expect_value(t, step_effect_window(&w, {focused = true, escape = true}, width, height), Effect_Window_Control.Close)
	testing.expect_value(t, step_effect_window(&w, {focused = true, inside = true, right_pressed = true, mouse = on_stage}, width, height), Effect_Window_Control.Close)
	testing.expect_value(t, step_effect_window(&w, {focused = true, inside = true, pressed = true, mouse = on_restart}, width, height), Effect_Window_Control.Restart)
	testing.expect_value(t, step_effect_window(&w, {focused = true, restart = true}, width, height), Effect_Window_Control.Restart)
	// A click outside the canvas (the letterbox) is no click on CHIUDI.
	testing.expect_value(t, step_effect_window(&w, {focused = true, pressed = true, mouse = on_close}, width, height), Effect_Window_Control.None)
}

// The stage is three quarters of the canvas, on whole pixels: at 1280x720 its
// 960x540 target lands 1:1 on the window's pixels; at any size it follows the
// canvas and stays on the window. The panel holds it, its head and buttons.
@(test)
test_effect_window_stage_maps_one_to_one_at_1280x720 :: proc(t: ^testing.T) {
	width, height := f32(960), f32(540)
	panel, stage := effect_window_panel_bounds(width, height), effect_window_stage_bounds(width, height)
	close, restart := effect_window_close_bounds(width, height), effect_window_restart_bounds(width, height)
	title, subtitle := effect_window_title_bounds(width, height), effect_window_subtitle_bounds(width, height)
	testing.expect(t, panel.x >= 0 && panel.y >= 0 && panel.x+panel.width <= width && panel.y+panel.height <= height)
	testing.expect(t, stage.x > panel.x && stage.y > panel.y && stage.x+stage.width < panel.x+panel.width && stage.y+stage.height < panel.y+panel.height)
	testing.expect(t, abs((panel.y)-(height-panel.y-panel.height)) <= 3, "the panel stands in the middle")
	testing.expect_value(t, stage.width, f32(EFFECT_STAGE_WIDTH)*0.75)
	testing.expect_value(t, stage.width*9, stage.height*16)
	testing.expect(t, math.mod(stage.x, 3) == 0 && math.mod(stage.y, 3) == 0, "the stage's corner is a whole window pixel at 4/3")
	for control in ([2]rl.Rectangle{close, restart}) {
		testing.expect(t, control.y >= panel.y && control.y+control.height < stage.y && control.x+control.width <= panel.x+panel.width)
	}
	testing.expect(t, restart.x+restart.width < close.x && title.x+title.width < restart.x)
	testing.expect(t, subtitle.y >= title.y && subtitle.y+subtitle.height <= stage.y && subtitle.x+subtitle.width < restart.x)
	Size :: struct {window: [2]int, mode: view.Scale_Mode, stage: rl.Rectangle}
	sizes := [?]Size{
		{{1280, 720}, .Fit, {160, 116, 960, 540}},
		{{1920, 1080}, .Fit, {240, 174, 1440, 810}},
		{{2560, 1440}, .Fit, {320, 232, 1920, 1080}},
		{{1600, 900}, .Fit, {200, 145, 1200, 675}},
		{{640, 360}, .Fit, {80, 58, 480, 270}},
		// F2's whole scale: the canvas 1:1 in the window's middle.
		{{1280, 720}, .Integer, {280, 177, 720, 405}},
	}
	for size in sizes {
		viewport, ok := view.calculate_viewport(size.window.x, size.window.y, 960, 540, size.mode)
		testing.expect(t, ok)
		d := effect_window_stage_destination(viewport, stage)
		testing.expectf(t, d == size.stage, "%v %v: the stage at %v", size.window, size.mode, d)
		testing.expect(t, d.x >= 0 && d.y >= 0 && d.x+d.width <= f32(size.window.x) && d.y+d.height <= f32(size.window.y))
	}
}

// The window shows its film from a room of its own: the run's player, its
// deck, its room and its clocks stand still, the film's renderer is not the
// run's, and Esc gives the run back with nothing held and its first frame
// charged no time.
@(test)
test_effect_window_opens_frozen_and_never_touches_the_run :: proc(t: ^testing.T) {
	rs := effect_test_fight(t)
	defer roguelike_destroy(rs)
	w := &rs.effect_window
	card := rs.run_state.player.deck.hand[0]
	rs.card_interaction = {selected_card_id = card.id}
	rs.gameplay_buffer.chord.active = true
	rs.tactical_controller.was_focused = true
	rs.iso_renderer.frame_clock_valid = true
	before := rs.run_state.player
	pulse, events, foe := rs.room.pulse_count, rs.room.recent_events.count, rs.room.enemies[0]
	effect_test_open(t, rs, card, .Inspector)
	testing.expect(t, w.open && w.film != nil && w.renderer != nil && w.film_ready && w.source == .Inspector && w.card == card)
	testing.expect(t, w.renderer != &rs.iso_renderer && w.renderer.tactical.showcase)
	testing.expect(t, rs.card_interaction == {} && !rs.gameplay_buffer.chord.active, "the run gives up what it held")
	for _ in 0..<240 { step_effect_window_in_run(rs, {focused = true}, 1.0/60.0) }
	testing.expect(t, w.film_time > 3.9 && w.film_time < 4.1)
	testing.expect(t, len(effect_window_caption(w)) > 0)
	testing.expect_value(t, rs.run_state.player, before)
	testing.expect_value(t, rs.room.pulse_count, pulse)
	testing.expect_value(t, rs.room.recent_events.count, events)
	testing.expect_value(t, rs.room.enemies[0], foe)
	testing.expect_value(t, rs.run_state.phase, game.Run_Phase.In_Room)
	// Unfocused, the film waits too.
	time := w.film_time
	step_effect_window_in_run(rs, {escape = true}, 1.0/60.0)
	testing.expect(t, w.open && w.film_time == time)
	step_effect_window_in_run(rs, {focused = true, escape = true}, 1.0/60.0)
	testing.expect(t, !w.open && w.film == nil && w.renderer == nil && !w.film_ready)
	testing.expect(t, !rs.tactical_controller.was_focused && !rs.iso_renderer.frame_clock_valid && !rs.mouse_inside)
	testing.expect_value(t, rs.run_state.player, before)
}

// The scene's frame with the window open is the window's: the film runs, no
// scene is pushed or popped, nothing of the run is read or advanced (its
// clocks, its timeline, its sprites); out of focus the film waits as well.
@(test)
test_effect_window_gate_runs_only_the_window :: proc(t: ^testing.T) {
	rs := effect_test_fight(t)
	defer roguelike_destroy(rs)
	before := rs.run_state.player
	pulse := rs.room.pulse_count
	effect_test_open(t, rs, rs.run_state.player.deck.hand[1], .Inspector)
	commands: host.Commands
	frame := host.Frame{dt = 1.0/60.0, focused = true, window_focused = true, mouse_inside = true, mouse = {480, 300},
		canvas = {0, 0, 960, 540}, commands = &commands}
	for _ in 0..<120 { roguelike_update(rs, &frame) }
	testing.expect(t, rs.effect_window.open && rs.effect_window.film_time > 1.9, "the film ran its two seconds")
	testing.expect_value(t, commands.count, 0)
	testing.expect_value(t, rs.run_state.player, before)
	testing.expect_value(t, rs.room.pulse_count, pulse)
	testing.expect_value(t, rs.iso_renderer.sprite_assets.elapsed, 0)
	testing.expect(t, !render.renderer_timeline_is_busy(&rs.iso_renderer))
	time := rs.effect_window.film_time
	frame.window_focused = false
	for _ in 0..<30 { roguelike_update(rs, &frame) }
	frame.window_focused, frame.focused = true, false
	for _ in 0..<30 { roguelike_update(rs, &frame) }
	testing.expect_value(t, rs.effect_window.film_time, time)
	testing.expect(t, rs.effect_window.open)
}

// A reward's MOSTRA EFFETTO shows its card as offered (no one's, at no
// upgrade) and never picks it; I shows the card under the mouse; the classic
// loop has no board to show it on, so no button.
@(test)
test_effect_reward_buttons_show_offers_and_never_pick :: proc(t: ^testing.T) {
	rs := effect_test_fight(t)
	defer roguelike_destroy(rs)
	rs.room.phase = .Complete
	testing.expect_value(t, game.finish_room(&rs.run_state, .Complete), game.Run_Transition.Reward)
	choices := game.available_card_rewards(&rs.run_state)
	owned := rs.run_state.player.deck.owned_count
	for index in 0..<len(choices) {
		point := effect_test_center(render.reward_effect_bounds(960, 540, index, len(choices)))
		card, source, found := effect_window_entry_at(rs, point)
		testing.expect(t, found && source == .Reward && card.definition_id == choices[index] && card.upgrade_level == 0 && card.lifetime == .Permanent)
		_, on_card := render.reward_card_at_point(&rs.run_state, 960, 540, point)
		testing.expect(t, !on_card && !render.reward_skip_at_point(960, 540, point))
	}
	_, _, found := effect_window_entry_at(rs, effect_test_center(render.reward_card_bounds(960, 540, 0, len(choices))))
	testing.expect(t, !found, "the card itself is the choice's")
	rs.reward_hovered_index = 2
	card, source, keyed := effect_window_key_entry(rs)
	testing.expect(t, keyed && source == .Reward && card.definition_id == choices[2])
	rs.reward_hovered_index = -1
	_, _, keyed = effect_window_key_entry(rs)
	testing.expect(t, !keyed)
	testing.expect(t, roguelike_effect_entry(rs, true, effect_test_center(render.reward_effect_bounds(960, 540, 1, len(choices))), false))
	testing.expect(t, rs.effect_window.open && rs.effect_window.card.definition_id == choices[1])
	step_effect_window_in_run(rs, {focused = true, right_pressed = true}, 1.0/60.0)
	testing.expect_value(t, rs.run_state.phase, game.Run_Phase.Reward)
	testing.expect_value(t, rs.run_state.player.deck.owned_count, owned)
	rs.options.tactical.enabled = false
	_, _, found = effect_window_entry_at(rs, effect_test_center(render.reward_effect_bounds(960, 540, 0, len(choices))))
	testing.expect(t, !found)
	rs.reward_hovered_index = 0
	_, _, keyed = effect_window_key_entry(rs)
	testing.expect(t, !keyed)
}

// The shop's buttons show each offer as offered and the owned card chosen as
// the deck holds it (its upgrade too), and buy nothing: gold, the offers, the
// deck and the shop's one upgrade and removal stay as they were; the owned
// card's button needs a card chosen; I shows the offer under the mouse, else
// the card chosen; the window's Esc never leaves the shop.
@(test)
test_effect_shop_buttons_show_offers_and_the_chosen_card_and_never_buy :: proc(t: ^testing.T) {
	rs := effect_test_stop(t, .Shop)
	defer roguelike_destroy(rs)
	testing.expect_value(t, rs.run_state.phase, game.Run_Phase.Shop)
	rs.run_state.player.gold = 60
	rs.run_state.player.deck.owned[1].upgrade_level = 1
	shop, deck := rs.run_state.shop, rs.run_state.player.deck
	for index in 0..<rs.run_state.shop.offer_count {
		card, source, found := effect_window_entry_at(rs, effect_test_center(render.shop_offer_effect_bounds(960, 540, index)))
		testing.expect(t, found && source == .Shop_Offer && card.definition_id == shop.offers[index].definition_id && card.upgrade_level == 0)
	}
	owned_button := effect_test_center(render.owned_card_effect_bounds(960, 540))
	_, _, found := effect_window_entry_at(rs, owned_button)
	testing.expect(t, !found, "no card chosen: no card to show")
	rs.shop_render_state.selected_card_id = deck.owned[1].id
	card, source, chosen := effect_window_entry_at(rs, owned_button)
	testing.expect(t, chosen && source == .Shop_Owned && card == deck.owned[1] && card.upgrade_level == 1)
	card, source, chosen = effect_window_key_entry(rs)
	testing.expect(t, chosen && source == .Shop_Owned && card == deck.owned[1])
	rs.shop_render_state.has_hovered_offer, rs.shop_render_state.hovered_offer_index = true, 2
	card, source, chosen = effect_window_key_entry(rs)
	testing.expect(t, chosen && source == .Shop_Offer && card.definition_id == shop.offers[2].definition_id)
	rs.shop_render_state.has_hovered_offer = false
	testing.expect(t, roguelike_effect_entry(rs, true, effect_test_center(render.shop_offer_effect_bounds(960, 540, 0)), false))
	testing.expect(t, rs.effect_window.open)
	// The scene's frames go to the window: no purchase, page or way out.
	commands: host.Commands
	frame := host.Frame{dt = 1.0/60.0, focused = true, window_focused = true, mouse_inside = true, canvas = {0, 0, 960, 540}, commands = &commands}
	for _ in 0..<30 { roguelike_update(rs, &frame) }
	step_effect_window_in_run(rs, {focused = true, escape = true}, 1.0/60.0)
	testing.expect(t, !rs.effect_window.open)
	testing.expect(t, roguelike_effect_entry(rs, true, owned_button, false) && rs.effect_window.card == deck.owned[1])
	step_effect_window_in_run(rs, {focused = true, inside = true, pressed = true, mouse = effect_test_center(effect_window_close_bounds(960, 540))}, 1.0/60.0)
	testing.expect(t, !rs.effect_window.open)
	testing.expect_value(t, rs.run_state.phase, game.Run_Phase.Shop)
	testing.expect_value(t, rs.run_state.player.gold, 60)
	testing.expect_value(t, rs.run_state.shop, shop)
	testing.expect_value(t, rs.run_state.player.deck.owned_count, deck.owned_count)
	testing.expect_value(t, rs.run_state.player.deck.owned, deck.owned)
	testing.expect_value(t, rs.shop_render_state.selected_card_id, deck.owned[1].id)
	testing.expect_value(t, commands.count, 0)
}

// The rest's button shows the owned card chosen for its upgrade, never
// resolving the rest; it is there only while the rest is.
@(test)
test_effect_rest_button_shows_the_chosen_card :: proc(t: ^testing.T) {
	rs := effect_test_stop(t, .Rest)
	defer roguelike_destroy(rs)
	testing.expect_value(t, rs.run_state.phase, game.Run_Phase.Rest)
	button := effect_test_center(render.owned_card_effect_bounds(960, 540))
	_, _, found := effect_window_entry_at(rs, button)
	testing.expect(t, !found)
	owned := rs.run_state.player.deck.owned[0]
	rs.special_render_state.selected_card_id = owned.id
	card, source, chosen := effect_window_entry_at(rs, button)
	testing.expect(t, chosen && source == .Rest && card == owned)
	health := rs.run_state.player.health
	testing.expect(t, roguelike_effect_entry(rs, true, button, false) && rs.effect_window.open)
	for _ in 0..<20 { step_effect_window_in_run(rs, {focused = true}, 1.0/60.0) }
	step_effect_window_in_run(rs, {focused = true, escape = true}, 1.0/60.0)
	testing.expect(t, !rs.run_state.rest.resolved && rs.run_state.player.health == health && rs.run_state.phase == .Rest)
	rs.run_state.rest.resolved = true
	_, _, found = effect_window_entry_at(rs, button)
	testing.expect(t, !found, "a rest resolved has no upgrade to choose")
	_, _, found = effect_window_key_entry(rs)
	testing.expect(t, !found)
}

effect_test_m8 :: proc(rs: ^Roguelike_Session, input: M8_Session_Input) -> bool {
	return step_m8_session(&rs.m8_session, &rs.room, &rs.iso_renderer, &rs.tactical_controller, &rs.card_interaction,
		&rs.gameplay_buffer, true, 1.0/60.0, input)
}

// The sheet's MAZZO: its lines a card and level each, its pages turned (to
// their first line), a line chosen with a click; MOSTRA EFFETTO or I ask for
// the window on the line chosen, as the deck holds it; the window opens over
// the sheet and its Esc closes the window alone.
@(test)
test_effect_sheet_lines_choose_page_and_ask :: proc(t: ^testing.T) {
	rs := effect_test_fight(t)
	defer roguelike_destroy(rs)
	deck := &rs.run_state.player.deck
	game.finish_deck_combat(deck)
	for card in ([?]struct{id: game.Card_Id, level: i32}{{.Pinball, 2}, {.Lasso, 1}, {.Deflect, 0}, {.Coffin, 2}, {.Fate_Dice, 1}}) {
		_, added := game.add_owned_card(deck, card.id, card.level)
		testing.expect(t, added)
	}
	testing.expect(t, game.begin_deck_combat(deck))
	rs.m8_session.character_open, rs.m8_session.sheet = true, {}
	r := &rs.iso_renderer
	layout := render.character_sheet_deck_layout(r, &rs.room, 0)
	testing.expect(t, layout.pages >= 2)
	sheet := &rs.m8_session.sheet
	testing.expect(t, effect_test_m8(rs, {focused = true, inside = true, pressed = true, mouse = effect_test_center(layout.previous)}))
	testing.expect(t, sheet.deck_page == 0 && sheet.deck_selected == 0, "no page before the first")
	testing.expect(t, effect_test_m8(rs, {focused = true, inside = true, pressed = true, mouse = effect_test_center(layout.next)}))
	testing.expect(t, sheet.deck_page == 1 && sheet.deck_selected == layout.per_page)
	page := render.character_sheet_deck_layout(r, &rs.room, sheet.deck_page)
	testing.expect(t, effect_test_m8(rs, {focused = true, inside = true, pressed = true, mouse = effect_test_center(render.character_sheet_deck_row_bounds(&page, 1))}))
	testing.expect_value(t, sheet.deck_selected, layout.per_page+1)
	testing.expect(t, !rs.m8_session.has_effect_request)
	testing.expect(t, effect_test_m8(rs, {focused = true, inside = true, pressed = true, mouse = effect_test_center(layout.button)}))
	testing.expect(t, rs.m8_session.has_effect_request && rs.m8_session.effect_source == .Sheet &&
		rs.m8_session.effect_request == page.rows[layout.per_page+1].card)
	rs.m8_session.has_effect_request = false
	// The last line's card, upgraded: the request carries its upgrade.
	last := render.character_sheet_deck_layout(r, &rs.room, 99)
	sheet.deck_page, sheet.deck_selected = last.page, last.row_count-1
	testing.expect(t, effect_test_m8(rs, {focused = true, inspect = true}))
	testing.expect(t, rs.m8_session.has_effect_request && rs.m8_session.effect_request == last.rows[last.row_count-1].card)
	testing.expect_value(t, rs.m8_session.effect_request.definition_id, game.Card_Id.Fate_Dice)
	testing.expect_value(t, rs.m8_session.effect_request.upgrade_level, 1)
	testing.expect(t, roguelike_take_effect_request(rs) && rs.effect_window.open && rs.effect_window.source == .Sheet)
	testing.expect(t, !rs.m8_session.has_effect_request)
	step_effect_window_in_run(rs, {focused = true, escape = true}, 1.0/60.0)
	testing.expect(t, !rs.effect_window.open && rs.m8_session.character_open, "the window's Esc closes the window alone")
	// The sheet's own Esc, then, closes it.
	testing.expect(t, effect_test_m8(rs, {focused = true, escape = true}))
	testing.expect(t, !rs.m8_session.character_open)
}

// The inspector's MOSTRA EFFETTO: for a card only under the mouse a click asks
// for nothing (it would pick the card up) and its key asks; for the card
// chosen a click on its button asks, the board no target under it; the
// window then opens on the card as it is, playing nothing. A dragged card,
// the pause, the map or a defence ask for nothing.
@(test)
test_effect_inspector_asks_for_the_card_it_shows :: proc(t: ^testing.T) {
	rs := effect_test_fight(t)
	defer roguelike_destroy(rs)
	deck := &rs.run_state.player.deck
	card := deck.hand[0]
	session := &rs.m8_session
	button := effect_test_center(render.tactical_inspector_effect_bounds())
	rs.card_interaction = {hovered_card_id = card.id}
	testing.expect(t, !effect_test_m8(rs, {focused = true, inside = true, pressed = true, mouse = button}))
	testing.expect(t, !session.has_effect_request)
	testing.expect(t, effect_test_m8(rs, {focused = true, inspect = true}))
	testing.expect(t, session.has_effect_request && session.effect_request == card && session.effect_source == .Inspector)
	session.has_effect_request = false
	rs.card_interaction = {selected_card_id = card.id}
	energy, hand := deck.energy, deck.hand_count
	testing.expect(t, render.tactical_inspector_effect_contains(&rs.iso_renderer, &rs.room, 0, card.id, 0, button), "the board takes no aim under the button")
	testing.expect(t, effect_test_m8(rs, {focused = true, inside = true, pressed = true, mouse = button}))
	testing.expect(t, session.has_effect_request && session.effect_request == card)
	testing.expect(t, roguelike_take_effect_request(rs) && rs.effect_window.open && rs.effect_window.card == card)
	testing.expect(t, rs.card_interaction == {})
	step_effect_window_in_run(rs, {focused = true, escape = true}, 1.0/60.0)
	testing.expect_value(t, deck.energy, energy)
	testing.expect_value(t, deck.hand_count, hand)
	testing.expect_value(t, deck.hand[0], card)
	refusals := [?]struct{what: string, set: proc(rs: ^Roguelike_Session)}{
		{"dragged", proc(rs: ^Roguelike_Session) { rs.card_interaction = {dragged_card_id = rs.run_state.player.deck.hand[0].id} }},
		{"paused", proc(rs: ^Roguelike_Session) { rs.tactical_controller.paused = true }},
		{"the map", proc(rs: ^Roguelike_Session) { rs.tactical_controller.hologram = true }},
		{"a defence", proc(rs: ^Roguelike_Session) { rs.room.qte.kind = .Defense }},
		{"Movimento Ombra", proc(rs: ^Roguelike_Session) { rs.run_state.player.tactical.phase = .Shadow }},
	}
	phase := rs.run_state.player.tactical.phase
	for refusal in refusals {
		rs.card_interaction = {selected_card_id = card.id}
		refusal.set(rs)
		// Neither its key nor a click on its (dimmed) button asks.
		_ = effect_test_m8(rs, {focused = true, inspect = true})
		testing.expectf(t, !session.has_effect_request, "%s: no request", refusal.what)
		_ = effect_test_m8(rs, {focused = true, inside = true, pressed = true, mouse = button})
		testing.expectf(t, !session.has_effect_request, "%s: no request from the button", refusal.what)
		rs.tactical_controller.paused, rs.tactical_controller.hologram, rs.room.qte.kind = false, false, .None
		rs.run_state.player.tactical.phase = phase
	}
}

// Every card there is, at its first upgrade and its last, has a film the
// window opens, runs and closes; nothing of the window outlives it (no
// allocation left, no bad free) and the run stands still throughout.
@(test)
test_effect_window_opens_for_every_card :: proc(t: ^testing.T) {
	rs := effect_test_fight(t)
	defer roguelike_destroy(rs)
	before := rs.run_state.player
	pulse := rs.room.pulse_count
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	{
		context.allocator = mem.tracking_allocator(&track)
		for id in game.Card_Id {
			if id == .Count { continue }
			definition, _ := game.card_definition_by_id(id, true)
			for level, index in ([2]i32{0, game.card_max_upgrade_level(id)}) {
				if index > 0 && level == 0 { continue }
				card := game.Card_Instance{id = 1, definition_id = id, upgrade_level = level, lifetime = .Combat if definition.temporary_only else .Permanent}
				if !open_effect_window_in_run(rs, card, .None) {
					testing.expectf(t, false, "%v +%d: the window does not open (%v)", id, level, effect_window_refusal(rs))
					continue
				}
				testing.expectf(t, rs.effect_window.film_ready, "%v +%d: no film", id, level)
				for _ in 0..<30 { step_effect_window_in_run(rs, {focused = true}, 1.0/60.0) }
				testing.expectf(t, len(effect_window_caption(&rs.effect_window)) > 0, "%v +%d: no caption", id, level)
				step_effect_window_in_run(rs, {focused = true, inside = true, pressed = true, mouse = effect_test_center(effect_window_restart_bounds(960, 540))}, 1.0/60.0)
				testing.expectf(t, rs.effect_window.film_ready && rs.effect_window.film_time == 0, "%v +%d: RICOMINCIA", id, level)
				for _ in 0..<10 { step_effect_window_in_run(rs, {focused = true}, 1.0/60.0) }
				step_effect_window_in_run(rs, {focused = true, escape = true}, 1.0/60.0)
				testing.expectf(t, !rs.effect_window.open, "%v +%d: Esc closes it", id, level)
			}
		}
	}
	testing.expectf(t, len(track.allocation_map) == 0, "%d allocations of the window left", len(track.allocation_map))
	testing.expectf(t, len(track.bad_free_array) == 0, "%d bad frees", len(track.bad_free_array))
	testing.expect_value(t, rs.run_state.player, before)
	testing.expect_value(t, rs.room.pulse_count, pulse)
}

// The window and the card's film meet on card_demo_open/step/close alone: on
// the board the window lends it (flat or 3D, as the run's is), stepped by the
// window's own frames, every card at every level it can reach plays its first
// take to its end and shows all its card promises (card_demo_shown), then the
// film starts afresh; the run stands still throughout. Quick runs sample the
// different integrations at their base/top levels; card_demo_test always
// checks the entire catalog's actual effects and every upgrade.
@(test)
test_effect_window_films_show_every_card_at_every_level :: proc(t: ^testing.T) {
	rs := effect_test_fight(t)
	defer roguelike_destroy(rs)
	before := rs.run_state.player
	pulse := rs.room.pulse_count
	w := &rs.effect_window
	for board_3d in ([2]bool{false, true}) {
		rs.iso_renderer.tactical.scene_3d, rs.iso_renderer.tactical.perspective = board_3d, board_3d
		for id in game.Card_Id {
			if id == .Count { continue }
			when !ODIN_TEST_FULL {
				quick_cards := bit_set[game.Card_Id]{.Strike, .Fate_Strike, .Tesla_Coil, .Shadow_Step, .Fishing_Rod, .First_Person}
				if id not_in quick_cards { continue }
			}
			definition, _ := game.card_definition_by_id(id, true)
			for level in i32(0)..=game.card_max_upgrade_level(id) {
				when !ODIN_TEST_FULL {
					if level != 0 && level != game.card_max_upgrade_level(id) { continue }
				}
				card := game.Card_Instance{id = 1, definition_id = id, upgrade_level = level, lifetime = .Combat if definition.temporary_only else .Permanent}
				if !open_effect_window_in_run(rs, card, .None) {
					testing.expectf(t, false, "%v +%d: the window does not open (%v)", id, level, effect_window_refusal(rs))
					continue
				}
				if !testing.expectf(t, w.film_ready && w.renderer.tactical.scene_3d == board_3d, "%v +%d (3D %v): no film", id, level, board_3d) {
					step_effect_window_in_run(rs, {focused = true, escape = true}, 1.0/60.0)
					continue
				}
				frames := 0
				for w.film.stage != .Done && frames < 60*45 {
					step_effect_window_in_run(rs, {focused = true}, 1.0/60.0)
					frames += 1
				}
				missing, shown := card_demo_shown(w.film, w.renderer)
				testing.expectf(t, shown && w.film.stage == .Done && w.film.takes == 1 && w.film.take_time < CARD_DEMO_TAKE_LIMIT,
					"%v +%d (3D %v) in the window: played %v, missing %v, foes hurt %d, the take ran %.1f s", id, level, board_3d, w.film.played,
					missing, card_demo_foes_hurt(w.film), w.film.take_time)
				testing.expectf(t, w.renderer.timeline.update_failures == 0, "%v +%d (3D %v): %d timeline failures", id, level, board_3d,
					w.renderer.timeline.update_failures)
				step_effect_window_in_run(rs, {focused = true}, 1.0/60.0)
				testing.expectf(t, w.film.takes == 2 && w.film.stage == .Settle, "%v +%d (3D %v): the film does not start afresh", id, level, board_3d)
				step_effect_window_in_run(rs, {focused = true, escape = true}, 1.0/60.0)
				testing.expectf(t, !w.open, "%v +%d: Esc closes it", id, level)
			}
		}
	}
	testing.expect_value(t, rs.run_state.player, before)
	testing.expect_value(t, rs.room.pulse_count, pulse)
}

// The window never opens while the board is busy or has no film to give: the
// pause, the map, a duel (6 RANCH 7, the ring, a square of coils about to open
// it), a defence, a cast, the dice, behind the player's eyes (diving or
// rising too), Movimento Ombra, an action still showing, the classic loop, or
// itself open. The requests refuse and take their press all the same. The
// run's screens show no board: what the last room left behind never keeps
// their buttons from opening it.
@(test)
test_effect_window_refuses_while_busy :: proc(t: ^testing.T) {
	rs := effect_test_fight(t)
	defer roguelike_destroy(rs)
	card := rs.run_state.player.deck.hand[0]
	testing.expect_value(t, effect_window_refusal(rs), Effect_Window_Refusal.None)
	Busy :: struct {
		reason: Effect_Window_Refusal,
		set: proc(rs: ^Roguelike_Session),
	}
	cases := [?]Busy{
		{.Paused, proc(rs: ^Roguelike_Session) { rs.tactical_controller.paused = true }},
		{.Map, proc(rs: ^Roguelike_Session) { rs.tactical_controller.hologram = true }},
		{.Duel, proc(rs: ^Roguelike_Session) { rs.m8_session.ranch.active = true }},
		{.Duel, proc(rs: ^Roguelike_Session) { rs.m8_session.ring_pending = true }},
		{.Duel, proc(rs: ^Roguelike_Session) { rs.room.tesla_ring.pending = true }},
		{.Defense, proc(rs: ^Roguelike_Session) { rs.room.qte.kind = .Defense }},
		{.Cast, proc(rs: ^Roguelike_Session) { rs.run_state.player.tactical.cast_remaining = 1 }},
		{.Dice, proc(rs: ^Roguelike_Session) {
			rs.iso_renderer.timeline.cues[0] = {kind = .Dice_Rolled, duration = 1, started = true}
			rs.iso_renderer.timeline.head, rs.iso_renderer.timeline.count = 0, 1
		}},
		{.First_Person, proc(rs: ^Roguelike_Session) { rs.room.first_person.active = true }},
		{.First_Person, proc(rs: ^Roguelike_Session) { rs.iso_renderer.tactical.first_person.amount = 0.4 }},
		{.Shadow, proc(rs: ^Roguelike_Session) { rs.run_state.player.tactical.phase = .Shadow }},
		{.Busy, proc(rs: ^Roguelike_Session) {
			rs.iso_renderer.timeline.cues[0] = {kind = .Move, duration = 1}
			rs.iso_renderer.timeline.head, rs.iso_renderer.timeline.count = 0, 1
		}},
		{.Classic, proc(rs: ^Roguelike_Session) { rs.options.tactical.enabled = false }},
	}
	for busy in cases {
		saved_controller, saved_ranch, saved_ring := rs.tactical_controller, rs.m8_session.ranch.active, rs.m8_session.ring_pending
		saved_tesla, saved_qte, saved_tactical := rs.room.tesla_ring, rs.room.qte, rs.run_state.player.tactical
		saved_first_person, saved_view := rs.room.first_person, rs.iso_renderer.tactical.first_person
		busy.set(rs)
		testing.expect_value(t, effect_window_refusal(rs), busy.reason)
		testing.expectf(t, !open_effect_window_in_run(rs, card, .Inspector) && !rs.effect_window.open, "%v: it opened", busy.reason)
		m8_request_effect(&rs.m8_session, card, .Inspector)
		testing.expectf(t, roguelike_take_effect_request(rs) && !rs.effect_window.open, "%v: the request opened it", busy.reason)
		testing.expect(t, rs.effect_window.film == nil && rs.effect_window.renderer == nil)
		rs.tactical_controller, rs.m8_session.ranch.active, rs.m8_session.ring_pending = saved_controller, saved_ranch, saved_ring
		rs.room.tesla_ring, rs.room.qte, rs.run_state.player.tactical = saved_tesla, saved_qte, saved_tactical
		rs.room.first_person, rs.iso_renderer.tactical.first_person = saved_first_person, saved_view
		rs.iso_renderer.timeline = {}
		rs.options.tactical.enabled = true
		testing.expect_value(t, effect_window_refusal(rs), Effect_Window_Refusal.None)
	}
	// Open, it does not open again.
	effect_test_open(t, rs, card)
	testing.expect_value(t, effect_window_refusal(rs), Effect_Window_Refusal.Open)
	testing.expect(t, !open_effect_window_in_run(rs, card, .None))
	step_effect_window_in_run(rs, {focused = true, escape = true}, 1.0/60.0)
	testing.expect(t, !rs.effect_window.open)
	// The room won while the view still stood behind the player's eyes, with a
	// defence and a cast left on it: the reward's buttons open it all the same.
	rs.room.phase = .Complete
	testing.expect_value(t, game.finish_room(&rs.run_state, .Complete), game.Run_Transition.Reward)
	rs.iso_renderer.tactical.first_person.amount = 0.4
	rs.room.qte.kind = .Defense
	rs.run_state.player.tactical.cast_remaining = 1
	testing.expect_value(t, effect_window_refusal(rs), Effect_Window_Refusal.None)
	choices := game.available_card_rewards(&rs.run_state)
	testing.expect(t, roguelike_effect_entry(rs, true, effect_test_center(render.reward_effect_bounds(960, 540, 0, len(choices))), false))
	testing.expect(t, rs.effect_window.open && rs.effect_window.card.definition_id == choices[0])
	testing.expect_value(t, effect_window_refusal(rs), Effect_Window_Refusal.Open)
	step_effect_window_in_run(rs, {focused = true, escape = true}, 1.0/60.0)
	rs.options.tactical.enabled = false
	testing.expect_value(t, effect_window_refusal(rs), Effect_Window_Refusal.Classic)
	rs.options.tactical.enabled = true
	rs.iso_renderer.tactical.first_person.amount, rs.room.qte.kind = 0, .None
}

// A film that could not be built: the stage says so, the window stays open
// and its clock runs, and RICOMINCIA (or R) tries the film afresh.
@(test)
test_effect_window_without_a_film_says_so_and_tries_again :: proc(t: ^testing.T) {
	rs := effect_test_fight(t)
	defer roguelike_destroy(rs)
	w := &rs.effect_window
	effect_test_open(t, rs, rs.run_state.player.deck.hand[0], .Inspector)
	testing.expect(t, w.film_ready && effect_window_caption(w) != string(EFFECT_WINDOW_NO_FILM))
	// As card_demo_open leaves a film it could not build.
	w.film_ready = false
	for _ in 0..<10 { step_effect_window_in_run(rs, {focused = true}, 1.0/60.0) }
	testing.expect(t, w.open && !w.film_ready && w.film_time > 0.1)
	testing.expect_value(t, effect_window_caption(w), string(EFFECT_WINDOW_NO_FILM))
	step_effect_window_in_run(rs, {focused = true, restart = true}, 1.0/60.0)
	testing.expect(t, w.open && w.film_ready && w.film_time == 0, "RICOMINCIA builds the film again")
	testing.expect(t, effect_window_caption(w) != string(EFFECT_WINDOW_NO_FILM))
	step_effect_window_in_run(rs, {focused = true}, 1.0/60.0)
	testing.expect(t, w.film_time > 0)
	step_effect_window_in_run(rs, {focused = true, escape = true}, 1.0/60.0)
	testing.expect(t, !w.open && w.film == nil)
	testing.expect_value(t, effect_window_caption(w), "")
}

// MOSTRA EFFETTO's buttons light under the mouse wherever they stand: the
// inspector's (where the board's view never reaches), the open sheet's MAZZO,
// and on the run's screens the reward's even where the last room's HUD stood
// (a weapon held: its plate's place over the bar); the board's view keeps
// clear of the HUD's controls in a room, and nothing lights with the window
// out of focus or the game paused.
@(test)
test_effect_buttons_light_under_the_mouse :: proc(t: ^testing.T) {
	rs := effect_test_fight(t)
	defer roguelike_destroy(rs)
	r := &rs.iso_renderer
	rs.run_state.player.equipment.weapon = {id = .Iron_Cleaver, uses_remaining = 3}
	card := rs.run_state.player.deck.hand[0]
	rs.mouse_inside = true
	// In the room: over the weapon's plate the view and the HUD both stand
	// back; over the inspector's button the HUD lights it, the view stays off.
	rs.mouse_canvas = effect_test_center(render.m8_weapon_bounds(r, &rs.room))
	view, hud := roguelike_pointer_inside(rs, true)
	testing.expect(t, !view && !hud)
	rs.card_interaction = {selected_card_id = card.id}
	rs.mouse_canvas = effect_test_center(render.tactical_inspector_effect_bounds())
	view, hud = roguelike_pointer_inside(rs, true)
	testing.expect(t, !view && hud, "the inspector's button lights, the board takes no aim under it")
	view, hud = roguelike_pointer_inside(rs, false)
	testing.expect(t, !view && !hud, "out of focus nothing lights")
	rs.tactical_controller.paused = true
	view, hud = roguelike_pointer_inside(rs, true)
	testing.expect(t, !view && !hud, "paused nothing lights")
	rs.tactical_controller.paused = false
	rs.mouse_canvas = {480, 250}
	view, hud = roguelike_pointer_inside(rs, true)
	testing.expect(t, view && hud, "the board takes the mouse elsewhere")
	// The sheet open: a modal over the board, its own lines and buttons lit.
	rs.card_interaction = {}
	rs.m8_session.character_open, rs.m8_modal = true, true
	rs.mouse_canvas = effect_test_center(render.character_sheet_deck_layout(r, &rs.room, 0).button)
	view, hud = roguelike_pointer_inside(rs, true)
	testing.expect(t, !view && hud, "the sheet's MOSTRA EFFETTO lights, the board is held")
	rs.m8_session.character_open, rs.m8_modal = false, false
	// The reward: no board, the button where the weapon's plate stood lights.
	rs.room.phase = .Complete
	testing.expect_value(t, game.finish_room(&rs.run_state, .Complete), game.Run_Transition.Reward)
	choices := game.available_card_rewards(&rs.run_state)
	button := render.reward_effect_bounds(960, 540, 0, len(choices))
	weapon := render.m8_weapon_bounds(r, &rs.room)
	under := effect_test_point_in_both(button, weapon)
	testing.expect(t, render.point_in_rectangle(under, button) && render.point_in_rectangle(under, weapon), "a point of the button under the plate's place")
	rs.mouse_canvas = under
	_, hud = roguelike_pointer_inside(rs, true)
	testing.expect(t, hud, "the reward's button lights where the room's HUD stood")
}

// A point inside both rectangles (their overlap's centre).
effect_test_point_in_both :: proc(a, b: rl.Rectangle) -> view.Vec2 {
	x0, y0 := max(a.x, b.x), max(a.y, b.y)
	x1, y1 := min(a.x+a.width, b.x+b.width), min(a.y+a.height, b.y+b.height)
	return {(x0+x1)*0.5, (y0+y1)*0.5}
}

// After CHIUDI the run takes up where it was: nothing held or buffered, the
// mouse and the keys as they are now, and the controller's first frame back
// blocked and charged no time, so that neither the click that closed it nor
// a key of that frame acts; the frame after runs the clock as usual.
@(test)
test_effect_window_close_resumes_without_click_through :: proc(t: ^testing.T) {
	rs := effect_test_fight(t)
	defer roguelike_destroy(rs)
	rs.tactical_controller.was_focused = true
	effect_test_open(t, rs, rs.run_state.player.deck.hand[0], .Inspector)
	for _ in 0..<12 { step_effect_window_in_run(rs, {focused = true}, 1.0/60.0) }
	rs.card_interaction = {hovered_card_id = 7}
	rs.gameplay_buffer.chord.active = true
	step_effect_window_in_run(rs, {focused = true, inside = true, pressed = true, mouse = effect_test_center(effect_window_close_bounds(960, 540))}, 1.0/60.0)
	testing.expect(t, !rs.effect_window.open)
	testing.expect(t, rs.card_interaction == {} && !rs.gameplay_buffer.chord.active && !rs.mouse_inside)
	testing.expect(t, !rs.tactical_controller.was_focused && !rs.iso_renderer.frame_clock_valid)
	player := &rs.run_state.player
	remaining, position := player.tactical.remaining, player.position
	blocked := step_tactical_controller(&rs.tactical_controller, &rs.room, &rs.iso_renderer, &rs.card_interaction, &rs.gameplay_buffer,
		1.0/60.0, true, {focused = true, directions = {false, true, false, false}, defenses = {true, false, false, false}})
	testing.expect(t, blocked, "the first frame back is blocked")
	testing.expect_value(t, player.tactical.remaining, remaining)
	testing.expect_value(t, player.position, position)
	_ = step_tactical_controller(&rs.tactical_controller, &rs.room, &rs.iso_renderer, &rs.card_interaction, &rs.gameplay_buffer,
		1.0/60.0, true, {focused = true})
	testing.expect(t, player.tactical.remaining < remaining, "then the clock runs")
}
