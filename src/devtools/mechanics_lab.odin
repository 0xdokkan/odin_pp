package devtools
import artifacts "artifacts"
import run_session "../run"

import "core:fmt"
import app "../engine/app"
import audio "../engine/audio"
import gfx "../engine/gfx"
import game "../game"
import grid "../engine/grid"
import level "../level"
import render "../render"
import view "../engine/view"

// With `dice`, a dice card's roll shows over the window as in the game;
// `input` is the controller's (the first person act's mouse and keys).
mechanics_lab_smoke_frame :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, dt: f32, clock := false, dice: ^render.Dice_Renderer = nil,
	input := run_session.Tactical_Controller_Input{focused = true}) {
	render.update_renderer_frame_timeline(renderer, dt)
	// The board clock runs only where a capture needs real time to pass.
	run_session.step_tactical_controller(controller, room, renderer, cards, buffer, dt if clock else 0, true, input)
	render.advance_sprite_assets(&renderer.sprite_assets, dt)
	render.update_tactical_view(renderer, room, {}, false, true)
	render.update_tactical_atmosphere(renderer, dt)
	overlay: app.Window_Overlay
	dice_state: run_session.Dice_Window_Overlay
	if cue, found := render.active_presentation_cue(&renderer.timeline); found && dice != nil && cue.started && cue.kind == .Dice_Rolled {
		dice_state = {renderer = dice, roll = cue.event.dice_roll, progress = render.presentation_cue_progress(cue),
			seed = run_session.dice_event_visual_seed(cue.event), card = cue.event.card_definition, outcome = render.dice_presentation_outcome(&renderer.timeline)}
		run_session.update_window_dice_overlay(window, &dice_state)
		overlay = run_session.draw_window_dice_overlay
	}
	app.begin_canvas(window, render.RESIN_BACKGROUND)
	render.draw_tactical_world(renderer, room, 0)
	render.draw_tactical_status(renderer, room)
	render.draw_tactical_hand(renderer, room, 0, 0, 0, {})
	render.draw_tactical_hud(renderer, room, false, false)
	render.draw_mechanics_lab_banner(renderer, room)
	app.present(window, render.LETTERBOX_COLOR, overlay, &dice_state)
	// The sounds are counted, not played: the smoke runs without a device.
	render.play_lab_sounds(renderer, nil, 0)
}

// The sandbox in the real window: the lab's whole deck in hand, a square of
// coils around the arrivals, the last kill that keeps the combat going and the
// refill; then every kind of blow, a slowed brute's seal, the pools and the
// fire, the player's charges and, last, the Lazzo, the Pinball
// (mechanics_lab_pinball.odin), the First Person Shooter
// (mechanics_lab_first_person.odin), the Inondazione and Bomb Marley
// (mechanics_lab_party.odin), the Cannone, the Buco Nero and the Dinosauro
// (mechanics_lab_arsenal.odin) and the Canna da Pesca.
run_mechanics_lab_smoke :: proc(window: ^app.Window, renderer: ^render.Renderer, dice: ^render.Dice_Renderer) -> bool {
	data: level.Level
	defer level.destroy(&data)
	player, created := game.create_player({max_health = 22, attack = 2, defense = 0})
	if !created || !game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG) { return false }
	room, built := run_session.create_mechanics_lab_room(&data, &player, game.DEFAULT_TACTICAL_CONFIG)
	if !built { fmt.eprintln("mechanics lab: arena not built"); return false }
	defer game.destroy_room(&room)
	if player.deck.hand_count != run_session.MECHANICS_LAB_RULES.hand_size { fmt.eprintln("mechanics lab: not the whole deck in hand"); return false }
	for id in run_session.MECHANICS_LAB_DECK {
		// The Canna da Pesca waits in Exhaust, never in hand.
		if game.card_is_room_tool(id) {
			if player.deck.exhaust_count != 1 || player.deck.exhaust_pile[0].definition_id != id { fmt.eprintln("mechanics lab: the", id, "is not waiting in Exhaust"); return false }
			continue
		}
		if _, held := mechanics_lab_hand_card(&player, id); !held { fmt.eprintln("mechanics lab: no", id, "in hand"); return false }
	}
	render.clear_event_animations(renderer)
	render.reset_tactical_orbit(&renderer.tactical.world_orbit)
	render.set_living_cards(renderer, true)
	defer render.set_living_cards(renderer, false)
	render.set_mechanics_lab(renderer, true, true)
	defer render.set_mechanics_lab(renderer, false)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	buffer: run_session.Buffered_Gameplay_Command
	sandbox := game.begin_sandbox(7)
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, &room, &controller, &cards, &buffer, 1.0/60.0) }
	artifacts.screenshot("odin_pp_mechanics_lab.png")
	if !mechanics_lab_card_words(renderer, &player) { return false }
	// A square of coils around an arrival offers the ring, every time.
	log: game.Event_Log
	center := grid.Position{run_session.MECHANICS_LAB_WIDTH/2, run_session.MECHANICS_LAB_HEIGHT/2}
	for offset in ([4]grid.Position{{-1, -1}, {2, -1}, {2, 2}, {-1, 2}}) {
		if !game.deploy_board_device(&room, .Tesla_Coil, {center.x+offset.x, center.y+offset.y}, 8, 0, &log) { fmt.eprintln("mechanics lab: coil not placed"); return false }
	}
	if _, inside := game.spawn_enemy(&room, {position = {center.x+1, center.y+1}, health = 12, attack = 2, archetype = .Chaser}); !inside {
		fmt.eprintln("mechanics lab: no arrival inside the square"); return false
	}
	player.floor_secrets += {.Tesla_Ring}
	_, _ = game.sandbox_tick(&room, &sandbox, 0)
	if _, ready := game.query_tesla_ring(&room); !ready { fmt.eprintln("mechanics lab: the ring is not offered again"); return false }
	render.clear_event_animations(renderer)
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, &room, &controller, &cards, &buffer, 1.0/60.0) }
	artifacts.screenshot("odin_pp_mechanics_lab_square.png")
	// Arrivals fill the arena up to its maximum.
	for _ in 0..<600 {
		if len(room.enemies) >= game.SANDBOX_MAX_ENEMIES { break }
		_, _ = game.sandbox_tick(&room, &sandbox, 0.5)
	}
	if len(room.enemies) != game.SANDBOX_MAX_ENEMIES { fmt.eprintf("mechanics lab: %d enemies\n", len(room.enemies)); return false }
	render.clear_event_animations(renderer)
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, &room, &controller, &cards, &buffer, 1.0/60.0) }
	artifacts.screenshot("odin_pp_mechanics_lab_full.png")
	// The last kill keeps the combat, the hand and the coils.
	action := game.Action{kind = .Ability, source = game.PLAYER_ENTITY}
	for enemy in room.enemies {
		action.effects[action.effect_count] = {kind = .Damage, target = game.enemy_entity(enemy.id), amount = 100}
		action.effect_count += 1
	}
	if !game.resolve_action(&room, &action).accepted { return false }
	if room.phase != .Combat || len(room.enemies) != 0 || player.deck.hand_count == 0 {
		fmt.eprintln("mechanics lab: clearing the arena ended the combat"); return false
	}
	_, refilled := game.sandbox_tick(&room, &sandbox, 0)
	if !refilled || len(room.enemies) != 1 { fmt.eprintln("mechanics lab: empty arena not refilled"); return false }
	for _ in 0..<60 { mechanics_lab_smoke_frame(window, renderer, &room, &controller, &cards, &buffer, 1.0/60.0) }
	artifacts.screenshot("odin_pp_mechanics_lab_refill.png")
	// Death, then a restart: the player's standee must come back.
	player.health = 1
	before := render.capture_room_presentation(&room)
	game.clear_event_log(room.recent_events)
	blow := game.make_action(.Attack, game.enemy_entity(room.enemies[0].id))
	if !game.add_effect(&blow, game.damage_effect(game.PLAYER_ENTITY, 50)) { return false }
	report := game.resolve_action(&room, &blow)
	if !report.accepted || room.phase != .Defeat { fmt.eprintln("mechanics lab: the player did not fall"); return false }
	game.append_event_log(room.recent_events, &report.events)
	after := render.capture_room_presentation(&room)
	if !render.begin_renderer_event_timeline(renderer, before, room.recent_events, &after) { return false }
	for _ in 0..<240 { mechanics_lab_smoke_frame(window, renderer, &room, &controller, &cards, &buffer, 1.0/60.0) }
	game.destroy_room(&room)
	player.health = player.stats.max_health
	room, built = run_session.create_mechanics_lab_room(&data, &player, game.DEFAULT_TACTICAL_CONFIG)
	if !built { return false }
	render.clear_event_animations(renderer)
	for _ in 0..<30 { mechanics_lab_smoke_frame(window, renderer, &room, &controller, &cards, &buffer, 1.0/60.0) }
	artifacts.screenshot("odin_pp_mechanics_lab_restart.png")
	standee := render.living_find(renderer, game.PLAYER_ENTITY, gfx.Flipbook_Character.Pilgrim)
	if standee == nil || standee.action == .Death { fmt.eprintln("mechanics lab: the player's card did not come back"); return false }
	// A step and a bump, frame by frame: the drawing acts, the card slides
	// as a block at the push. Captures for the animated previews.
	if !mechanics_lab_capture(window, renderer, &room, &controller, &cards, &buffer, {kind = .Move, origin_phase = .Combat, direction = .East}, "move") { return false }
	// The foe stands to the north, beside the card on screen rather than in
	// front of it, so the blow can be seen.
	if _, placed := game.spawn_enemy(&room, {position = {player.position.x, player.position.y-1}, health = 40, attack = 1, archetype = .Chaser}); !placed {
		fmt.eprintln("mechanics lab: no foe beside the player"); return false
	}
	render.clear_event_animations(renderer)
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, &room, &controller, &cards, &buffer, 1.0/60.0) }
	if !mechanics_lab_capture(window, renderer, &room, &controller, &cards, &buffer, {kind = .Move, origin_phase = .Combat, direction = .North}, "attack") { return false }
	// The player's action ring on every tick, and the enemy intent displays on
	// trial, one after the other (F6 in the lab).
	if renderer.tactical.living_assets.ring_shader.id == 0 { fmt.eprintln("mechanics lab: no action rings"); return false }
	for mode in render.Intent_Display {
		renderer.tactical.intent_display = mode
		mechanics_lab_film(window, renderer, &room, &controller, &cards, &buffer, 120, 3, fmt.tprintf("intents_%d", int(mode)))
	}
	// One instant with a blow about to land: compact tags with ground
	// warnings, then tags alone. Both show the same current intent.
	renderer.tactical.intent_display = .Both
	for _ in 0..<900 {
		imminent := false
		for &enemy in room.enemies {
			if enemy.intent.kind != .Attack && enemy.intent.kind != .Charge { continue }
			left := game.tactical_enemy_seconds(&room, &enemy)
			if left > 0.1 && left < 0.45 { imminent = true }
		}
		if imminent && room.qte.kind == .None { break }
		mechanics_lab_smoke_frame(window, renderer, &room, &controller, &cards, &buffer, 1.0/60.0, true)
	}
	for mode in ([2]render.Intent_Display{.Both, .Labels}) {
		renderer.tactical.intent_display = mode
		for _ in 0..<2 { mechanics_lab_smoke_frame(window, renderer, &room, &controller, &cards, &buffer, 0) }
		artifacts.screenshot("odin_pp_living_intent_both.png" if mode == .Both else "odin_pp_living_intent_labels.png")
	}
	renderer.tactical.intent_display = .Both
	// A cure: the green paper token. (Blows got red ones above.)
	player.health = max(1, player.health-3)
	cure_before := render.capture_room_presentation(&room)
	game.clear_event_log(room.recent_events)
	cure := game.make_action(.Ability, game.PLAYER_ENTITY)
	if !game.add_effect(&cure, game.heal_effect(game.PLAYER_ENTITY, 3)) { return false }
	cured := game.resolve_action(&room, &cure)
	if !cured.accepted { fmt.eprintln("mechanics lab: the cure was refused"); return false }
	game.append_event_log(room.recent_events, &cured.events)
	cure_after := render.capture_room_presentation(&room)
	if !render.begin_renderer_event_timeline(renderer, cure_before, room.recent_events, &cure_after) { return false }
	mechanics_lab_film(window, renderer, &room, &controller, &cards, &buffer, 80, 2, "heal")
	if !mechanics_lab_statuses(window, renderer, &room, &controller, &cards, &buffer) { return false }
	// The shrinking window: the last second runs out into a stun, cards only.
	player.tactical.config.shrinking_window = true
	player.tactical.budget, player.tactical.remaining, player.tactical.won_seconds = 1, 0.1, 0
	for _ in 0..<300 {
		mechanics_lab_smoke_frame(window, renderer, &room, &controller, &cards, &buffer, 1.0/60.0, true)
		if game.tactical_is_stunned(&room) { break }
	}
	if !game.tactical_is_stunned(&room) || !game.tactical_allows_cards(&room) || game.tactical_allows_movement(&room) {
		fmt.eprintln("mechanics lab: the last second did not run out into a stun"); return false
	}
	for _ in 0..<10 { mechanics_lab_smoke_frame(window, renderer, &room, &controller, &cards, &buffer, 1.0/60.0, true) }
	artifacts.screenshot("odin_pp_mechanics_lab_stun.png")
	// The pause menu and the defeat screen, with the way back to the menu.
	renderer.tactical.pause_hovered, renderer.tactical.pause_menu = .Menu, true
	defeat := game.Run_State{phase = .Defeat}
	for screen in 0..<2 {
		for _ in 0..<3 {
			app.begin_canvas(window, render.RESIN_BACKGROUND)
			render.draw_tactical_world(renderer, &room, 0)
			render.draw_tactical_hand(renderer, &room, 0, 0, 0, {})
			render.draw_tactical_hud(renderer, &room, screen == 0, false)
			if screen == 1 { render.draw_defeat_overlay(&defeat, renderer.canvas_width, renderer.canvas_height, .Menu, true, theme = renderer) }
			app.present(window, render.LETTERBOX_COLOR)
		}
		artifacts.screenshot("odin_pp_mechanics_lab_pause.png" if screen == 0 else "odin_pp_mechanics_lab_defeat.png")
	}
	renderer.tactical.pause_hovered, renderer.tactical.pause_menu = .None, false
	if !mechanics_lab_blows(window, renderer, &room, &controller, &cards, &buffer) { return false }
	if !mechanics_lab_slow(window, renderer, &room, &controller, &cards, &buffer) { return false }
	if !mechanics_lab_ground(window, renderer, &room, &controller, &cards, &buffer) { return false }
	if !mechanics_lab_charges(window, renderer, dice, &room, &controller, &cards, &buffer) { return false }
	if !mechanics_lab_lasso(window, renderer, &room, &controller, &cards, &buffer) { return false }
	if !mechanics_lab_pinball(window, renderer, &room, &controller, &cards, &buffer) { return false }
	if !mechanics_lab_first_person(window, renderer, &room, &data, &controller, &cards, &buffer) { return false }
	if !mechanics_lab_flood(window, renderer, &room, &controller, &cards, &buffer) { return false }
	if !mechanics_lab_marley(window, renderer, &room, &controller, &cards, &buffer) { return false }
	if !mechanics_lab_cannon(window, renderer, &room, &controller, &cards, &buffer) { return false }
	if !mechanics_lab_black_hole(window, renderer, &room, &controller, &cards, &buffer) { return false }
	if !mechanics_lab_dinosaur(window, renderer, &room, &controller, &cards, &buffer) { return false }
	if !mechanics_lab_fishing(window, renderer, dice, &room, &controller, &cards, &buffer) { return false }
	return mechanics_lab_sounds_heard(renderer)
}

// Every card of the lab's deck, at every level it can reach, says all its
// words on the hand's own cards and in the inspector without a line drawn
// smaller or cut, nor a name cut, measured with the game's font
// (render.tactical_card_text_misfit); the Canna da Pesca on its own slot. The
// hand holds ten cards, more than the game's: they keep the width of a full
// hand of the game's (eight, narrow ones) and overlap. Each shows all the
// words of its face, its cost, time, icon, marks and key before the next
// covers it (render.tactical_hand_reveal), in the hand as it is dealt and in
// any order it can take, the pointer finds it there, and raised it rises
// whole inside the canvas, under the pointer still.
mechanics_lab_card_words :: proc(renderer: ^render.Renderer, player: ^game.Player) -> bool {
	deck := &player.deck
	count := deck.hand_count
	width := render.tactical_hand_card_bounds(renderer, 0, count).width
	full := render.tactical_hand_card_bounds(renderer, 0, game.MAX_HAND_CARDS).width
	if count != run_session.MECHANICS_LAB_RULES.hand_size || !render.tactical_hand_overlaps(count) || width != full ||
	   renderer.tactical.hand_reveal.count != count {
		fmt.eprintf("mechanics lab: %d cards %.0f px wide, a full hand's are %.0f px\n", count, width, full); return false
	}
	least := width
	for index in 0..<count {
		bounds := render.tactical_hand_card_bounds(renderer, index, count)
		raised := render.tactical_hand_raised_card_bounds(renderer, index, count)
		shown := render.tactical_hand_card_visible_width(renderer, index, count)
		middle := view.Vec2{bounds.x+shown*0.5, bounds.y+bounds.height*0.5}
		pointed, found := render.hand_card_at_point(renderer, deck, middle)
		top := view.Vec2{bounds.x+bounds.width-4, raised.y+2}
		lifted, kept := render.hand_card_at_point(renderer, deck, top, deck.hand[index].id)
		definition, _ := game.card_definition_by_id(deck.hand[index].definition_id)
		covered := render.tactical_card_text_misfit(renderer, deck.hand[index], definition, width, shown)
		if bounds.width != width || shown < render.TACTICAL_HAND_REVEAL_ICON || covered != "" || raised.width != width ||
		   raised.y >= bounds.y || raised.x < 0 || raised.y < 0 ||
		   raised.x+raised.width > renderer.canvas_width || raised.y+raised.height > renderer.canvas_height ||
		   !found || pointed != index || !kept || lifted != index {
			fmt.eprintf("mechanics lab: hand card %d of %d: %v shows %.0f px (%s), raised to %v, pointed %v %d, lifted %v %d\n", index+1, count,
				bounds, shown, covered, raised, found, pointed, kept, lifted); return false
		}
		if index < count-1 { least = min(least, shown) }
	}
	// Any order: the hand's whole need, with the card that needs least last
	// (shown whole), still fits across it.
	needed, smallest := f32(0), width
	for card in deck.hand[:count] {
		definition, _ := game.card_definition_by_id(card.definition_id)
		need := render.tactical_hand_reveal_need(renderer, card, definition, width)
		needed += need
		smallest = min(smallest, need)
	}
	span := renderer.canvas_width-render.TACTICAL_HAND_OVERLAP_GUTTER*2
	if needed-smallest+width > span {
		fmt.eprintf("mechanics lab: the hand's words need %.0f px of %.0f in some order\n", needed-smallest+width, span); return false
	}
	checked := 0
	for id in run_session.MECHANICS_LAB_DECK {
		definition, found := game.card_definition_by_id(id)
		if !found { return false }
		card := game.Card_Instance{id = 1, definition_id = id, lifetime = .Permanent}
		card_width := render.fishing_slot_bounds(renderer).width if game.card_is_room_tool(id) else width
		for {
			if misfit := render.tactical_card_text_misfit(renderer, card, definition, card_width); misfit != "" {
				fmt.eprintf("mechanics lab: %v +%d on a %.0f px card: %s\n", id, card.upgrade_level, card_width, misfit)
				return false
			}
			checked += 1
			if !game.card_can_upgrade(card) { break }
			card.upgrade_level += 1
		}
	}
	// The Pinball and the First Person Shooter on the game's wider faces too:
	// a hand of five or six, the shop's and the rewards' (render.menu_card_face).
	faces := [4]f32{render.tactical_hand_card_bounds(renderer, 0, 5).width, render.tactical_hand_card_bounds(renderer, 0, 6).width,
		render.shop_offer_bounds(renderer.canvas_width, renderer.canvas_height, 0).width,
		render.reward_card_bounds(renderer.canvas_width, renderer.canvas_height, 0, game.CARD_REWARD_CHOICE_COUNT).width}
	wide := 0
	for id in ([2]game.Card_Id{.Pinball, .First_Person}) {
		definition, _ := game.card_definition_by_id(id)
		card := game.Card_Instance{id = 1, definition_id = id, lifetime = .Permanent}
		for {
			for face_width in faces {
				if face_width < render.CARD_NARROW_WIDTH {
					fmt.eprintf("mechanics lab: a %.0f px wide face is a narrow one\n", face_width); return false
				}
				if misfit := render.tactical_card_text_misfit(renderer, card, definition, face_width); misfit != "" {
					fmt.eprintf("mechanics lab: %v +%d on a %.0f px card: %s\n", id, card.upgrade_level, face_width, misfit)
					return false
				}
				wide += 1
			}
			if !game.card_can_upgrade(card) { break }
			card.upgrade_level += 1
		}
	}
	fmt.eprintf("mechanics lab words: %d cards and levels hold on %.0f px cards and in the inspector, the Pinball and the First Person Shooter on %d faces %.0f, %.0f, %.0f and %.0f px wide; %d cards in hand, at least %.0f px of each showing, all their words (%.0f of %.0f px in any order)\n",
		checked, width, wide, faces[0], faces[1], faces[2], faces[3], count, least, needed-smallest+width, span)
	return true
}

// The lab's deck no longer holds Pozza di Veleno, Deflect and Feretro (the
// Cannone, the Buco Nero and the Dinosauro took their places), but their acts
// still test them: for the act's time `to` takes the place of `from` (the same
// instance, wherever it lies), and the act puts it back with the two turned.
mechanics_lab_borrow :: proc(player: ^game.Player, from, to: game.Card_Id) -> bool {
	deck := &player.deck
	swapped := 0
	swap :: proc(cards: []game.Card_Instance, count: int, from, to: game.Card_Id) -> (done: int) {
		for &card in cards[:count] {
			if card.definition_id == from { card.definition_id, card.upgrade_level = to, 0; done += 1 }
		}
		return
	}
	swapped += swap(deck.owned[:], deck.owned_count, from, to)
	hand := swap(deck.hand[:], deck.hand_count, from, to)
	swapped += swap(deck.draw_pile[:], deck.draw_count, from, to)
	swapped += swap(deck.discard_pile[:], deck.discard_count, from, to)
	swapped += swap(deck.exhaust_pile[:], deck.exhaust_count, from, to)
	if swapped == 0 || hand == 0 { fmt.eprintln("mechanics lab: no", from, "to stand for", to); return false }
	return true
}

// The id of a `card` in the hand.
mechanics_lab_hand_card :: proc(player: ^game.Player, card: game.Card_Id) -> (id: u32, ok: bool) {
	for held in player.deck.hand[:player.deck.hand_count] {
		if held.definition_id == card { return held.id, true }
	}
	return
}

// A `card` of the hand played at `target` as the lane plays it, once the
// player may act (the clock runs meanwhile), with the energy it needs.
mechanics_lab_play :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, card: game.Card_Id, target: game.Target) -> bool {
	mechanics_lab_wait_free(window, renderer, room, controller, cards, buffer)
	id, held := mechanics_lab_hand_card(room.player, card)
	room.player.deck.energy = room.player.deck.rules.max_energy
	return held && run_session.commit_gameplay_command(room, renderer, cards, {kind = .Play_Card, origin_phase = .Combat,
		card_id = id, target = target})
}

// Frames with the clock running until the player may play a card again.
mechanics_lab_wait_free :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, dice: ^render.Dice_Renderer = nil) {
	for _ in 0..<600 {
		if game.tactical_allows_cards(room) && !render.renderer_blocks_player_input(renderer) && !game.tactical_player_busy(room) { break }
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true, dice)
	}
}

// Dice whose next die of `sides` rolls `face`: the lab shows chosen faces.
mechanics_lab_dice_for_face :: proc(face, sides: i32) -> (dice: game.Dice_State, ok: bool) {
	for seed in u64(1)..<u64(400_000) {
		dice = game.make_dice_state(seed)
		staged := dice
		if roll, rolled := game.roll_dice_pool(&staged, 1, sides); rolled && roll.total == face { return dice, true }
	}
	return {}, false
}

// Every kind of blow on the board, one at a time, filmed every second frame
// as odin_pp_living_blow_<name>_NN.png: each enemy's own weapon over its
// cells (the brute's cleave over three, and his charge struck once he has
// arrived), the archer's bolt into the player and into the floor, the
// bomber's bomb, the archmage's ember on a barrel, and the player's bumps with
// his lantern and with each M8 weapon. Every look must have shown.
mechanics_lab_blows :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	Blow :: struct {
		name: string,
		archetype: game.Enemy_Archetype,
		at: grid.Position,
		look: render.Attack_Look,
		cleave, miss, charge, barrel: bool,
	}
	center := player.position
	blows := [?]Blow{
		{name = "bolt", archetype = .Archer, at = {center.x+4, center.y}, look = .Bolt},
		{name = "bolt_miss", archetype = .Archer, at = {center.x-4, center.y}, look = .Bolt, miss = true},
		{name = "cleave", archetype = .Brute, at = {center.x+1, center.y}, look = .Cleaver, cleave = true},
		{name = "charge", archetype = .Brute, at = {center.x+3, center.y}, look = .Cleaver, charge = true},
		{name = "claws", archetype = .Chaser, at = {center.x, center.y-1}, look = .Claws},
		{name = "crozier", archetype = .Custodian, at = {center.x-1, center.y}, look = .Crozier},
		{name = "staff", archetype = .Demolitionist, at = {center.x, center.y+1}, look = .Staff},
		{name = "bomb", archetype = .Bomber, at = {center.x+3, center.y-1}, look = .Bomb},
		{name = "ember", archetype = .Demolitionist, at = {center.x+3, center.y-3}, look = .Ember, barrel = true},
	}
	for blow in blows {
		if !mechanics_lab_clear_arena(room) { return false }
		player.health = player.stats.max_health
		// The smoke stands him back where the blows aim (no walk to show).
		player.position = center
		id, placed := game.spawn_enemy(room, {position = blow.at, health = 60, attack = 1, archetype = blow.archetype})
		if !placed { fmt.eprintln("mechanics lab: no room for the", blow.name); return false }
		index, _ := game.enemy_index_by_id(room, id)
		enemy := &room.enemies[index]
		aim := center
		intent := game.make_attack_intent(room, enemy.position, aim, 1)
		if blow.cleave {
			for side in ([2]grid.Position{{aim.x, aim.y-1}, {aim.x, aim.y+1}}) {
				intent.threatened_cells[intent.threatened_cell_count] = side
				intent.threatened_cell_count += 1
			}
		}
		if blow.charge {
			// Two cells at a run, then the blow from the third.
			intent.kind = .Charge
			for step in 1..=2 {
				intent.path[intent.path_count] = {enemy.position.x-step, aim.y}
				intent.path_count += 1
			}
			intent.destination = intent.path[intent.path_count-1]
		}
		barrel: u32
		if blow.barrel {
			// A barrel by the player, set alight from afar.
			barrel = room.next_object_id
			room.next_object_id += 1
			append(&room.objects, game.Grid_Object{id = barrel, kind = .Barrel, position = {center.x+1, center.y-1}, health = 1, max_health = 1})
			intent = game.make_attack_intent(room, enemy.position, {center.x+1, center.y-1}, 1)
			intent.target_object = barrel
		}
		intent.push = blow.cleave || blow.charge
		enemy.intent = intent
		// A miss: he has stepped off the line the archer shot along.
		if blow.miss { player.position = {center.x, center.y+1} }
		render.clear_event_animations(renderer)
		for _ in 0..<12 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
		shown := renderer.tactical.attack_fx.spawned[blow.look]
		before := render.capture_room_presentation(room)
		pulse: game.Pulse_Report
		game.resolve_enemy_intents(room, &pulse, id)
		after := render.capture_room_presentation(room)
		if pulse.events.count == 0 || !render.begin_renderer_world_timeline(renderer, before, &pulse.events, &after) {
			fmt.eprintln("mechanics lab: the", blow.name, "was not shown"); return false
		}
		frames := 80 if blow.charge else 48
		for frame in 0..<frames {
			mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0)
			if frame%2 == 0 { artifacts.screenshot(fmt.ctprintf("odin_pp_living_blow_%s_%02d.png", blow.name, frame/2)) }
		}
		if renderer.tactical.attack_fx.spawned[blow.look] != shown+1 {
			fmt.eprintln("mechanics lab: the", blow.name, "showed no", blow.look); return false
		}
		if barrel != 0 {
			if at, found := game.object_index_by_id(room, barrel); found { _ = game.remove_grid_object(room, at) }
		}
	}
	// The player's bumps: the lantern, then each M8 weapon in his hand.
	weapons := [?]game.Weapon_Slot{{}, {id = .Iron_Cleaver, uses_remaining = 4}, {id = .Storm_Pike, uses_remaining = 3}}
	looks := [?]render.Attack_Look{.Lantern, .Iron_Cleaver, .Storm_Pike}
	names := [?]string{"lantern", "iron_cleaver", "storm_pike"}
	for weapon, index in weapons {
		if !mechanics_lab_clear_arena(room) { return false }
		player.health = player.stats.max_health
		player.equipment.weapon = weapon
		if _, placed := game.spawn_enemy(room, {position = {player.position.x+1, player.position.y}, health = 60, attack = 1, archetype = .Chaser}); !placed {
			fmt.eprintln("mechanics lab: no foe for the bump"); return false
		}
		render.clear_event_animations(renderer)
		for _ in 0..<12 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
		shown := renderer.tactical.attack_fx.spawned[looks[index]]
		if !mechanics_lab_capture(window, renderer, room, controller, cards, buffer, {kind = .Move, origin_phase = .Combat, direction = .East},
			fmt.tprintf("blow_%s", names[index])) { return false }
		if renderer.tactical.attack_fx.spawned[looks[index]] <= shown {
			fmt.eprintln("mechanics lab: the bump showed no", looks[index]); return false
		}
	}
	player.equipment.weapon = {}
	for look in render.Attack_Look {
		if look != .None && renderer.tactical.attack_fx.spawned[look] == 0 { fmt.eprintln("mechanics lab: no prop for", look); return false }
	}
	fmt.eprintln("mechanics lab blows:", renderer.tactical.attack_fx.spawned)
	return true
}

// The stack statuses, filmed as odin_pp_living_statuses_NN.png and held still
// as odin_pp_mechanics_lab_statuses.png: Veleno, Bruciatura and Rallentamento
// on a foe (the brute, when one is in the arena), Bruciatura and Veleno on the
// player. Their tags at the feet, their names and stacks in the HUD and in the
// foe's inspector; the window that runs out next (the stun below) burns.
mechanics_lab_statuses :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	if len(room.enemies) == 0 { fmt.eprintln("mechanics lab: no foe for the statuses"); return false }
	foe := game.enemy_entity(room.enemies[0].id)
	for enemy in room.enemies { if enemy.archetype == .Brute { foe = game.enemy_entity(enemy.id) } }
	before := render.capture_room_presentation(room)
	game.clear_event_log(room.recent_events)
	marks := game.make_action(.Trigger, game.SYSTEM_ENTITY)
	effects := [5]game.Effect{
		game.apply_status_effect(foe, .Poison, 3, 0), game.apply_status_effect(foe, .Burn, 2, 0), game.apply_status_effect(foe, .Slow, 2, 0),
		game.apply_status_effect(game.PLAYER_ENTITY, .Burn, 1, 0), game.apply_status_effect(game.PLAYER_ENTITY, .Poison, 2, 0),
	}
	for effect in effects {
		if !game.add_effect(&marks, effect) { fmt.eprintln("mechanics lab: a status effect refused"); return false }
	}
	marked := game.resolve_action(room, &marks)
	if !marked.accepted || marked.statuses_applied != len(effects) { fmt.eprintln("mechanics lab: the statuses were refused"); return false }
	game.append_event_log(room.recent_events, &marked.events)
	after := render.capture_room_presentation(room)
	if !render.begin_renderer_event_timeline(renderer, before, room.recent_events, &after) { return false }
	mechanics_lab_film(window, renderer, room, controller, cards, buffer, 60, 3, "statuses")
	// Held still, the mouse on the foe: its inspector lists them too.
	mechanics_lab_inspect_still(window, renderer, room, foe, "odin_pp_mechanics_lab_statuses.png")
	return true
}

// Rallentamento on the seal, last: a brute slowed by 2 keeps the step it had
// planned (off the player's lines, so not a charge), then plans the next
// intent 2 s longer, so its seal counts two more notches and fills that much
// slower (odin_pp_mechanics_lab_slow.png, its inspector open); once that
// action is carried out the slow wears a stack and the intent after it is held
// 1 s (odin_pp_mechanics_lab_slow_worn.png).
mechanics_lab_slow :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	SLOW :: i32(2)
	brute :: proc(room: ^game.Room, id: u32) -> ^game.Enemy {
		index, found := game.enemy_index_by_id(room, id)
		return &room.enemies[index] if found else nil
	}
	stacks :: proc(enemy: ^game.Enemy) -> i32 {
		index, found := game.status_index(&enemy.statuses, .Slow)
		return enemy.statuses.items[index].potency if found else 0
	}
	player := room.player
	if !mechanics_lab_clear_arena(room) { return false }
	player.health = player.stats.max_health
	// No weapon panel over the board where the brute's tags stand: the bumps'
	// weapons go, and so do the spares on the floor the magnet would pick up.
	player.equipment = {}
	for index := len(room.loot)-1; index >= 0; index -= 1 {
		if room.loot[index].kind == .Weapon { unordered_remove(&room.loot, index) }
	}
	id, placed := game.spawn_enemy(room, {position = {player.position.x+3, player.position.y+2}, health = 60, attack = 1, archetype = .Brute})
	if !placed { fmt.eprintln("mechanics lab: no room for the slowed brute"); return false }
	foe := game.enemy_entity(id)
	before := render.capture_room_presentation(room)
	game.clear_event_log(room.recent_events)
	marks := game.make_action(.Trigger, game.SYSTEM_ENTITY)
	if !game.add_effect(&marks, game.apply_status_effect(foe, .Slow, SLOW, 0)) { return false }
	marked := game.resolve_action(room, &marks)
	if !marked.accepted || marked.statuses_applied != 1 { fmt.eprintln("mechanics lab: the slow was refused"); return false }
	game.append_event_log(room.recent_events, &marked.events)
	after := render.capture_room_presentation(room)
	if !render.begin_renderer_event_timeline(renderer, before, room.recent_events, &after) { return false }
	// The held intent, a second and a half into its countdown.
	enemy: ^game.Enemy
	for _ in 0..<900 {
		enemy = brute(room, id)
		if enemy == nil { break }
		if enemy.intent.slowed == SLOW && room.qte.kind == .None && !render.renderer_blocks_player_input(renderer) &&
		   game.tactical_enemy_intent_seconds(enemy)-game.tactical_enemy_seconds(room, enemy) >= 1.5 { break }
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
	}
	if enemy == nil || enemy.intent.slowed != SLOW || stacks(enemy) != SLOW {
		fmt.eprintln("mechanics lab: the brute planned no intent held by its slow"); return false
	}
	held, base := game.tactical_enemy_intent_seconds(enemy), game.tactical_enemy_base_seconds(enemy)
	if held != base+f32(SLOW) { fmt.eprintf("mechanics lab: a slowed intent of %.1f s, not %.1f\n", held, base+f32(SLOW)); return false }
	kind := enemy.intent.kind
	mechanics_lab_inspect_still(window, renderer, room, foe, "odin_pp_mechanics_lab_slow.png")
	// Carried out, it wears one stack; the next intent is held one second.
	for _ in 0..<900 {
		enemy = brute(room, id)
		if enemy == nil || (stacks(enemy) < SLOW && enemy.intent.slowed == SLOW-1 && room.qte.kind == .None &&
		   !render.renderer_blocks_player_input(renderer)) { break }
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
	}
	if enemy == nil || stacks(enemy) != SLOW-1 || enemy.intent.slowed != SLOW-1 ||
	   game.tactical_enemy_intent_seconds(enemy) != game.tactical_enemy_base_seconds(enemy)+f32(SLOW-1) {
		fmt.eprintln("mechanics lab: the slowed action did not wear one stack"); return false
	}
	for _ in 0..<30 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true) }
	mechanics_lab_inspect_still(window, renderer, room, foe, "odin_pp_mechanics_lab_slow_worn.png")
	fmt.eprintf("mechanics lab slow: %v held %.0f s (%.0f s base), then %v %.0f s with %d stack left\n",
		kind, held, base, enemy.intent.kind, game.tactical_enemy_intent_seconds(enemy), stacks(enemy))
	return true
}

// POZZA DI VELENO and INCENDIO from the hand, as the lane plays them. A ring
// of pools around a chaser held where it stands, its last cell left open: the
// card's preview shows the area it would close (odin_pp_mechanics_lab_pool_preview.png),
// then the last pool is thrown there and the closed cells flood out from it,
// poisoning the chaser once (odin_pp_living_pool_NN.png): eight cells of 2
// Veleno in all. A second chaser walks through two pools toward the player and
// takes a dose at each one, splashing, each of its steps biting its stacks; then
// the player steps into a pool of his own and nothing touches him
// (odin_pp_living_pool_walk_NN.png). Then a fire lit beside a held brute grows
// its four arms a cell at each window, catches the brute at the second
// (Bruciatura 1, which bites from the third and never wears) and the player's
// own cell without a mark on him, and goes out at the fifth
// (odin_pp_living_fire_NN.png, odin_pp_mechanics_lab_fire.png at its height).
mechanics_lab_ground :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	// The Pozza di Veleno takes the Dinosauro's place for this act.
	if !mechanics_lab_borrow(player, .Dinosaur, .Poison_Pool) { return false }
	defer mechanics_lab_borrow(player, .Poison_Pool, .Dinosaur)
	foe :: mechanics_lab_enemy
	stacks :: proc(room: ^game.Room, id: u32, kind: game.Status_Kind) -> i32 {
		status, found := game.status_for_entity(room, game.enemy_entity(id), kind)
		return status.potency if found else 0
	}
	// Held where it stands: recovering, its next intent planned afresh.
	hold :: mechanics_lab_hold
	pour :: proc(room: ^game.Room, kind: game.Status_Kind, cell: grid.Position) -> bool {
		action := game.make_action(.Card, game.PLAYER_ENTITY, game.cell_target(cell), .Walkable_Cell)
		return game.add_effect(&action, game.place_ground_effect(cell, kind, 2)) && game.resolve_action(room, &action).accepted
	}
	// The lane's own play, once the player may act.
	play :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
		cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, card: game.Card_Id, cell: grid.Position) -> bool {
		return mechanics_lab_play(window, renderer, room, controller, cards, buffer, card, game.cell_target(cell))
	}
	if !mechanics_lab_clear_arena(room) { return false }
	game.clear_ground(room)
	player.health = player.stats.max_health
	player.equipment = {}
	clear(&room.loot)
	// No Veleno or Bruciatura left on him from the acts before: the ground's
	// must never show on him.
	for kind in ([2]game.Status_Kind{.Poison, .Burn}) { _, _ = game.remove_status(room, game.PLAYER_ENTITY, kind) }
	// Whole windows: no stun in the fire's five.
	player.tactical.config.shrinking_window = false
	center := grid.Position{run_session.MECHANICS_LAB_WIDTH/2, run_session.MECHANICS_LAB_HEIGHT/2}
	player.position = center
	player.tactical.facing = .North
	held_id, held_placed := game.spawn_enemy(room, {position = {center.x, center.y-3}, health = 40, attack = 1, archetype = .Chaser})
	if !held_placed { fmt.eprintln("mechanics lab: no room for the held chaser"); return false }
	hold(room, held_id)
	// The ring around its cell and the one beside it, but the cell below it.
	closing := grid.Position{center.x, center.y-2}
	ring := [?]grid.Position{{center.x, center.y-4}, {center.x+1, center.y-4}, {center.x+2, center.y-3}, {center.x+1, center.y-2}, {center.x-1, center.y-3}}
	for cell in ring {
		if !pour(room, .Poison, cell) { fmt.eprintln("mechanics lab: the ring's pool at", cell, "was refused"); return false }
	}
	render.clear_event_animations(renderer)
	for _ in 0..<30 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	// The card's preview: the cell, and the area it closes.
	pool_card, has_pool := mechanics_lab_hand_card(player, .Poison_Pool)
	if !has_pool { fmt.eprintln("mechanics lab: no Pozza di Veleno in hand"); return false }
	for _ in 0..<3 {
		render.update_renderer_frame_timeline(renderer, 0)
		render.update_tactical_view(renderer, room, {}, false, true)
		renderer.has_hovered_cell, renderer.hovered_cell = true, closing
		app.begin_canvas(window, render.RESIN_BACKGROUND)
		render.draw_tactical_world(renderer, room, pool_card)
		render.draw_tactical_status(renderer, room)
		render.draw_tactical_hand(renderer, room, 0, pool_card, 0, {})
		render.draw_tactical_hud(renderer, room, false, false)
		render.draw_mechanics_lab_banner(renderer, room)
		app.present(window, render.LETTERBOX_COLOR)
	}
	artifacts.screenshot("odin_pp_mechanics_lab_pool_preview.png")
	renderer.has_hovered_cell = false
	ground := renderer.tactical.ground
	if ground == nil { fmt.eprintln("mechanics lab: no ground on the board"); return false }
	splashed := ground.splashed
	if !play(window, renderer, room, controller, cards, buffer, .Poison_Pool, closing) {
		fmt.eprintln("mechanics lab: Pozza di Veleno was not played"); return false
	}
	// The game has it all at once; the board shows it from the landing on.
	for cell in ([2]grid.Position{{center.x, center.y-3}, {center.x+1, center.y-3}}) {
		if game.ground_pool_at(room, cell) <= 0 { fmt.eprintln("mechanics lab: the closed cell", cell, "did not fill"); return false }
	}
	// Eight cells of pool (the ring's five, the last one and the two it
	// closed), each with the card's 2 Veleno; nothing outside filled. The
	// chaser shut in took its dose once.
	pooled := 0
	for value in room.ground.pool {
		if value == 0 { continue }
		if value != 2 { fmt.eprintln("mechanics lab: a pool cell of", value, "Veleno"); return false }
		pooled += 1
	}
	if pooled != len(ring)+3 || stacks(room, held_id, .Poison) != 2 {
		fmt.eprintln("mechanics lab:", pooled, "pool cells, the closed chaser with Veleno", stacks(room, held_id, .Poison)); return false
	}
	mechanics_lab_film(window, renderer, room, controller, cards, buffer, 90, 3, "pool")

	// A chaser walks the pools toward the player: a dose and a splash each.
	walker_id, walker_placed := game.spawn_enemy(room, {position = {center.x+4, center.y}, health = 40, attack = 1, archetype = .Chaser})
	if !walker_placed { fmt.eprintln("mechanics lab: no room for the walking chaser"); return false }
	for cell in ([2]grid.Position{{center.x+3, center.y}, {center.x+2, center.y}}) {
		if !pour(room, .Poison, cell) { fmt.eprintln("mechanics lab: the path's pool at", cell, "was refused"); return false }
	}
	frame := 0
	for _ in 0..<900 {
		walker := foe(room, walker_id)
		if walker == nil || walker.position == (grid.Position{center.x+1, center.y}) { break }
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "pool_walk", 6, &frame)
	}
	// 2 Veleno at each pool cell it entered, and each of its steps bit its
	// stacks: 2 at the first pool, 3 at the second, 2 on the dry cell after,
	// with 1 left. There it stays.
	walker := foe(room, walker_id)
	if walker == nil || walker.position != (grid.Position{center.x+1, center.y}) || walker.health != 40-7 || stacks(room, walker_id, .Poison) != 1 {
		fmt.eprintln("mechanics lab: the walking chaser came with", walker.health if walker != nil else -1, "hp and Veleno",
			stacks(room, walker_id, .Poison)); return false
	}
	hold(room, walker_id)
	for _ in 0..<45 { mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "pool_walk", 6, &frame) }
	if ground.splashed != splashed+2 {
		fmt.eprintln("mechanics lab: the walking chaser splashed", ground.splashed-splashed, "times"); return false
	}
	// The player steps into a pool of his own: no Veleno on him, no splash.
	walked := grid.Position{center.x-1, center.y}
	if !pour(room, .Poison, walked) { fmt.eprintln("mechanics lab: the player's pool was refused"); return false }
	if !mechanics_lab_commit(window, renderer, room, controller, cards, buffer, {kind = .Move, origin_phase = .Combat, direction = .West}) {
		fmt.eprintln("mechanics lab: the player's step into the pool was not taken"); return false
	}
	for _ in 0..<60 { mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "pool_walk", 6, &frame) }
	if _, poisoned := game.status_for_entity(room, game.PLAYER_ENTITY, .Poison); poisoned || player.position != walked || ground.splashed != splashed+2 {
		fmt.eprintln("mechanics lab: the player's own pool touched him at", player.position); return false
	}
	// INCENDIO beside a held brute: five windows.
	if !mechanics_lab_clear_arena(room) { return false }
	game.clear_ground(room)
	player.health = player.stats.max_health
	player.position = center
	brute_id, brute_placed := game.spawn_enemy(room, {position = {center.x+2, center.y-2}, health = 60, attack = 1, archetype = .Brute})
	if !brute_placed { fmt.eprintln("mechanics lab: no room for the held brute"); return false }
	hold(room, brute_id)
	render.clear_event_animations(renderer)
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	ground = renderer.tactical.ground
	catches := ground.catches
	sounds := renderer.tactical.lab_sounds
	if sounds == nil { fmt.eprintln("mechanics lab: no sounds before the fire"); return false }
	spreads, outs := sounds.played[.World_Fire_Spread], sounds.played[.World_Fire_Out]
	if !play(window, renderer, room, controller, cards, buffer, .Wildfire, {center.x+2, center.y}) {
		fmt.eprintln("mechanics lab: Incendio was not played"); return false
	}
	frame = 0
	for _ in 0..<60 { mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "fire", 4, &frame) }
	if room.ground.fire_count != 1 { fmt.eprintln("mechanics lab: no fire lit"); return false }
	for window_index in 1..=5 {
		// The window runs out (the controller's Timeout), the fire grows, the
		// recovery passes and the next window opens.
		for _ in 0..<600 {
			if player.tactical.phase == .Decision && !render.renderer_blocks_player_input(renderer) && !game.tactical_player_busy(room) { break }
			mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
		}
		cycle := player.tactical.cycle
		player.tactical.remaining = min(player.tactical.remaining, 0.05)
		for _ in 0..<600 {
			if player.tactical.cycle != cycle { break }
			mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
		}
		if player.tactical.cycle == cycle { fmt.eprintln("mechanics lab: window", window_index, "did not run out"); return false }
		for _ in 0..<36 { mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "fire", 4, &frame) }
		if window_index == 4 {
			artifacts.screenshot("odin_pp_mechanics_lab_fire.png")

		}
		// Caught at the second window, the brute has Bruciatura 1 from then on
		// (once, and it never wears); it bites first and the fire grows after,
		// so the first bite comes at the third.
		burn := stacks(room, brute_id, .Burn)
		brute := foe(room, brute_id)
		if brute == nil || burn != (1 if window_index >= 2 else 0) || brute.health != 60-i32(max(0, window_index-2)) {
			fmt.eprintln("mechanics lab: Bruciatura", burn, "on the brute with", brute.health if brute != nil else -1, "hp after window", window_index)
			return false
		}
		if (window_index < 5) != (room.ground.fire_count == 1) { fmt.eprintln("mechanics lab: a fire count of", room.ground.fire_count, "after window", window_index); return false }
		// No wall within four cells: each arm as long as the windows it grew.
		if window_index < 5 {
			fire := room.ground.fires[0]
			grown := fire.stage == i32(window_index) && fire.stopped == {}
			for arm in fire.arms { grown = grown && arm == i32(window_index) }
			if !grown { fmt.eprintln("mechanics lab: the fire after window", window_index, "is", fire); return false }
		}
		// From the second window the west arm burns the player's own cell:
		// nothing on him.
		if _, burned := game.status_for_entity(room, game.PLAYER_ENTITY, .Burn); burned {
			fmt.eprintln("mechanics lab: the fire burned the player after window", window_index); return false
		}
	}
	for _ in 0..<30 { mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "fire", 4, &frame) }
	if ground.catches <= catches { fmt.eprintln("mechanics lab: the fire caught no card on the board"); return false }
	// No wall in its way: it roared at each of its four growths, never as it
	// was lit, and went out once at the fifth window.
	if sounds.played[.World_Fire_Spread] != spreads+4 || sounds.played[.World_Fire_Out] != outs+1 {
		fmt.eprintln("mechanics lab: the fire roared", sounds.played[.World_Fire_Spread]-spreads, "times and went out",
			sounds.played[.World_Fire_Out]-outs, "times")
		return false
	}
	brute := foe(room, brute_id)
	fmt.eprintf("mechanics lab ground: pool %d cells, %d splashes, fire caught %d, brute %d hp with Bruciatura %d\n",
		len(ring)+3, ground.splashed-splashed, ground.catches-catches, brute.health if brute != nil else 0, stacks(room, brute_id, .Burn))
	game.clear_ground(room)
	return true
}

// A foe held where it stands: recovering, its next intent planned afresh.
mechanics_lab_hold :: proc(room: ^game.Room, id: u32) {
	index, found := game.enemy_index_by_id(room, id)
	if !found { return }
	enemy := &room.enemies[index]
	enemy.recovery_pulses = 99
	enemy.intent, enemy.tactical_cooldown = {}, 0
	game.plan_enemy_intents(room)
}

// The player's charges from the hand, as the lane plays them, each filmed
// every second frame. DEFLECT: an archer's bolt reaches the player's card,
// turns and flies home into its shooter, one bolt and never a second
// (odin_pp_living_deflect_bolt_NN.png); a brute's cleave and then his charge are
// answered by the player's own riposte (odin_pp_living_deflect_cleave_NN.png,
// odin_pp_living_deflect_charge_NN.png). Each time no defence prompt opens
// though his dodge is ready, he takes nothing and is not pushed, the attacker
// takes the blow's 3 and the charge is spent. FERETRO: Ctrl held, the foes its
// arrows reach are marked and the one behind a block of cover is not
// (odin_pp_mechanics_lab_arrow_aim.png); a click on that one looses nothing, the
// click on the marked one looses a paper arrow, a second of the window, for 1
// damage and one status (odin_pp_living_arrow_NN.png). DADO DEL DESTINO: a bump
// rolls the card's d4 at the hit, its die on a paper tag at the struck card, and
// its 2 leaves Bruciatura 2 (odin_pp_living_fate_NN.png); the card played again
// loads back to three bumps, never more; on a d20 a 16 fells the foe
// (odin_pp_living_fate_lethal_NN.png), and with three more charges beside it
// the HUD's three chips and count say every word whole, its d20 too
// (odin_pp_mechanics_lab_fate_chips.png); the 16 is only a critical on the
// Custodian, a miniboss (odin_pp_living_fate_boss_NN.png).
mechanics_lab_charges :: proc(window: ^app.Window, renderer: ^render.Renderer, dice: ^render.Dice_Renderer, room: ^game.Room,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	center := grid.Position{run_session.MECHANICS_LAB_WIDTH/2, run_session.MECHANICS_LAB_HEIGHT/2}
	// Deflect and Feretro take the Cannone's and the Buco Nero's places for this act.
	if !mechanics_lab_borrow(player, .Cannon, .Deflect) || !mechanics_lab_borrow(player, .Black_Hole, .Coffin) { return false }
	defer {
		mechanics_lab_borrow(player, .Deflect, .Cannon)
		mechanics_lab_borrow(player, .Coffin, .Black_Hole)
	}
	foe :: mechanics_lab_enemy
	stacks :: proc(room: ^game.Room, id: u32, kind: game.Status_Kind) -> i32 {
		status, found := game.status_for_entity(room, game.enemy_entity(id), kind)
		return status.potency if found else 0
	}
	// A fresh arena around the player in the middle, his hands empty, no
	// charge left from the card before and no bite on him: each card is seen
	// alone.
	reset :: proc(room: ^game.Room, center: grid.Position) -> bool {
		if !mechanics_lab_clear_arena(room) { return false }
		game.clear_ground(room)
		room.player.health = room.player.stats.max_health
		room.player.position = center
		room.player.equipment = {}
		for kind in ([6]game.Status_Kind{.Deflect, .Arrows, .Fate, .Venom_Blade, .Poison, .Burn}) { _, _ = game.remove_status(room, game.PLAYER_ENTITY, kind) }
		for index := len(room.loot)-1; index >= 0; index -= 1 {
			if room.loot[index].kind == .Weapon { unordered_remove(&room.loot, index) }
		}
		return true
	}
	self := game.entity_target(game.PLAYER_ENTITY)
	if !reset(room, center) { return false }
	player.tactical.facing = .East
	// The three cards in hand, each under the mouse: its inspector's lines
	// (odin_pp_mechanics_lab_card_<Card>.png).
	for card in ([3]game.Card_Id{.Deflect, .Coffin, .Fate_Dice}) {
		id, held := mechanics_lab_hand_card(player, card)
		if !held { fmt.eprintln("mechanics lab: no", card, "in hand"); return false }
		mechanics_lab_still(window, renderer, room, id, fmt.ctprintf("odin_pp_mechanics_lab_card_%v.png", card))
	}
	// DEFLECT, from the hand, on an archer's bolt.
	if !mechanics_lab_play(window, renderer, room, controller, cards, buffer, .Deflect, self) {
		fmt.eprintln("mechanics lab: Deflect was not played"); return false
	}
	mechanics_lab_wait_free(window, renderer, room, controller, cards, buffer)
	if game.player_charges(room, .Deflect) != 1 { fmt.eprintln("mechanics lab: Deflect loaded", game.player_charges(room, .Deflect)); return false }
	Blow :: struct {
		name: string,
		archetype: game.Enemy_Archetype,
		at: grid.Position,
		cleave, charge: bool,
		look: render.Attack_Look,
		frames: int,
	}
	blows := [?]Blow{
		{name = "deflect_bolt", archetype = .Archer, at = {center.x+4, center.y}, look = .Bolt, frames = 64},
		{name = "deflect_cleave", archetype = .Brute, at = {center.x+1, center.y}, cleave = true, look = .Cleaver, frames = 64},
		{name = "deflect_charge", archetype = .Brute, at = {center.x+3, center.y}, charge = true, look = .Cleaver, frames = 80},
	}
	for blow, index in blows {
		if index > 0 {
			// The whole deck is in hand: the card is back for the next blow.
			if !reset(room, center) || !mechanics_lab_play(window, renderer, room, controller, cards, buffer, .Deflect, self) {
				fmt.eprintln("mechanics lab: Deflect was not played again"); return false
			}
			mechanics_lab_wait_free(window, renderer, room, controller, cards, buffer)
		}
		id, placed := game.spawn_enemy(room, {position = blow.at, health = 60, attack = 3, archetype = blow.archetype})
		if !placed { fmt.eprintln("mechanics lab: no room for the", blow.name); return false }
		enemy := foe(room, id)
		intent := game.make_attack_intent(room, enemy.position, center, 3)
		if blow.cleave {
			for side in ([2]grid.Position{{center.x, center.y-1}, {center.x, center.y+1}}) {
				intent.threatened_cells[intent.threatened_cell_count] = side
				intent.threatened_cell_count += 1
			}
		}
		if blow.charge {
			// Two cells at a run, then the blow from the third.
			intent.kind = .Charge
			for step in 1..=2 {
				intent.path[intent.path_count] = {enemy.position.x-step, center.y}
				intent.path_count += 1
			}
			intent.destination = intent.path[intent.path_count-1]
		}
		intent.push = blow.cleave || blow.charge
		enemy.intent = intent
		// RIFLESSO answers the blow by itself: no defence prompt, though his
		// dodge is ready to offer.
		if !game.tactical_dodge_ready(room) || !game.tactical_dodge_has_landing(room) || game.tactical_is_stunned(room) ||
		   game.offer_defense_qte(room, enemy) || room.qte.kind != .None {
			fmt.eprintln("mechanics lab: a defence prompt for the", blow.name, "over RIFLESSO:", room.qte.kind); return false
		}
		render.clear_event_animations(renderer)
		for _ in 0..<12 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
		spawned := renderer.tactical.attack_fx.spawned
		health := player.health
		before := render.capture_room_presentation(room)
		pulse: game.Pulse_Report
		game.resolve_enemy_intents(room, &pulse, id)
		after := render.capture_room_presentation(room)
		if pulse.events.count == 0 || !render.begin_renderer_world_timeline(renderer, before, &pulse.events, &after) {
			fmt.eprintln("mechanics lab: the", blow.name, "was not shown"); return false
		}
		for frame in 0..<blow.frames {
			mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0)
			if frame%2 == 0 { artifacts.screenshot(fmt.ctprintf("odin_pp_living_%s_%02d.png", blow.name, frame/2)) }
		}
		shown := renderer.tactical.attack_fx.spawned
		struck := foe(room, id)
		// He takes nothing and stays where he stood (no push); the attacker
		// takes the blow's 3 and the charge is spent. One bolt that goes and
		// comes back; a swing or a charge answered by the lantern.
		riposte := shown[.Lantern]-spawned[.Lantern]
		if player.health != health || player.position != center || game.player_charges(room, .Deflect) != 0 ||
		   struck == nil || struck.health != 57 || shown[blow.look] != spawned[blow.look]+1 || riposte != (0 if blow.look == .Bolt else 1) {
			fmt.eprintln("mechanics lab: the", blow.name, "was not sent back: player", player.health, "at", player.position,
				"foe", struck.health if struck != nil else -1, "props", shown); return false
		}
	}
	// FERETRO, from the hand: Ctrl held, the foes in reach; the click.
	if !reset(room, center) { return false }
	if !mechanics_lab_play(window, renderer, room, controller, cards, buffer, .Coffin, self) {
		fmt.eprintln("mechanics lab: Feretro was not played"); return false
	}
	mechanics_lab_wait_free(window, renderer, room, controller, cards, buffer)
	if game.player_charges(room, .Arrows) != 3 { fmt.eprintln("mechanics lab: Feretro loaded", game.player_charges(room, .Arrows), "arrows"); return false }
	// A foe in the line of fire, and one behind a block of cover.
	cover := grid.Position{center.x, center.y+2}
	append(&room.obstacles, game.Obstacle{position = cover})
	target_id, target_placed := game.spawn_enemy(room, {position = {center.x+3, center.y-1}, health = 60, attack = 1, archetype = .Chaser})
	covered_id, covered_placed := game.spawn_enemy(room, {position = {center.x, center.y+3}, health = 60, attack = 1, archetype = .Chaser})
	if !target_placed || !covered_placed { fmt.eprintln("mechanics lab: no room for the arrows' foes"); return false }
	mechanics_lab_hold(room, target_id)
	mechanics_lab_hold(room, covered_id)
	render.clear_event_animations(renderer)
	for _ in 0..<12 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	if !game.player_arrow_target_is_valid(room, game.enemy_entity(target_id)) || game.player_arrow_target_is_valid(room, game.enemy_entity(covered_id)) {
		fmt.eprintln("mechanics lab: the arrows reach the wrong foes"); return false
	}
	// Ctrl held: a click on the foe behind the cover looses nothing (and
	// picks up no card either).
	renderer.tactical.arrow_aim = run_session.arrows_aiming_at(room, true)
	renderer.has_hovered_cell, renderer.hovered_cell = true, foe(room, covered_id).position
	_, covered_shot, covered_taken := run_session.arrow_shot_command(room, renderer, renderer.tactical.arrow_aim, true)
	if !covered_taken || covered_shot { fmt.eprintln("mechanics lab: the click on the covered foe was not swallowed"); return false }
	// The mouse on the foe in reach: the board marks it alone, a click looses.
	renderer.hovered_cell = foe(room, target_id).position
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_arrow_aim.png")
	shot, has_shot, taken := run_session.arrow_shot_command(room, renderer, renderer.tactical.arrow_aim, true)
	renderer.tactical.arrow_aim, renderer.has_hovered_cell = false, false
	if !taken || !has_shot { fmt.eprintln("mechanics lab: the click on the marked foe loosed no arrow"); return false }
	bolts := renderer.tactical.attack_fx.spawned[.Bolt]
	if !mechanics_lab_commit(window, renderer, room, controller, cards, buffer, shot) { fmt.eprintln("mechanics lab: the arrow was not loosed"); return false }
	// One action of a second: 1 damage and one of Veleno 2, Bruciatura 1 or
	// Rallentamento 1; the foe behind the cover untouched.
	arrowed, sheltered := foe(room, target_id), foe(room, covered_id)
	poison, burn, slow := stacks(room, target_id, .Poison), stacks(room, target_id, .Burn), stacks(room, target_id, .Slow)
	marked := (poison == 2 && burn == 0 && slow == 0) || (poison == 0 && burn == 1 && slow == 0) || (poison == 0 && burn == 0 && slow == 1)
	if arrowed == nil || arrowed.health != 60-game.COFFIN_ARROW_DAMAGE || !marked || game.player_charges(room, .Arrows) != 2 ||
	   player.tactical.action_duration != game.TACTICAL_ARROW_SECONDS || sheltered == nil || sheltered.health != 60 {
		fmt.eprintln("mechanics lab: the arrow did not strike as it should: foe", arrowed.health if arrowed != nil else -1,
			"Veleno", poison, "Bruciatura", burn, "Rallentamento", slow, "arrows", game.player_charges(room, .Arrows),
			"action", player.tactical.action_duration); return false
	}
	mechanics_lab_film(window, renderer, room, controller, cards, buffer, 76, 2, "arrow")
	if renderer.tactical.attack_fx.spawned[.Bolt] != bolts+1 { fmt.eprintln("mechanics lab: the arrow flew as no bolt"); return false }
	for index := len(room.obstacles)-1; index >= 0; index -= 1 {
		if room.obstacles[index].position == cover { ordered_remove(&room.obstacles, index) }
	}
	// DADO DEL DESTINO, from the hand: three bumps that roll their die at the hit.
	fate_bump :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
		cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, sides, face: i32) -> bool {
		forced, found := mechanics_lab_dice_for_face(face, sides)
		if !found { fmt.eprintln("mechanics lab: no dice for a", face); return false }
		room.player.tactical.fate_sides, room.player.dice = sides, forced
		return mechanics_lab_commit(window, renderer, room, controller, cards, buffer, {kind = .Move, origin_phase = .Combat, direction = .North})
	}
	if !reset(room, center) { return false }
	if !mechanics_lab_play(window, renderer, room, controller, cards, buffer, .Fate_Dice, self) {
		fmt.eprintln("mechanics lab: Dado del Destino was not played"); return false
	}
	mechanics_lab_wait_free(window, renderer, room, controller, cards, buffer)
	if game.player_charges(room, .Fate) != game.FATE_DICE_CHARGES || game.player_fate_sides(room) != 4 {
		fmt.eprintln("mechanics lab: Dado del Destino loaded", game.player_charges(room, .Fate), "bumps with a d", game.player_fate_sides(room)); return false
	}
	// DESTINO's chip names the die its bumps will roll (the HUD's chip text).
	fate_chip :: proc(renderer: ^render.Renderer, room: ^game.Room) -> string {
		status := render.renderer_status_view(renderer, room)
		index, loaded := game.status_index(&status.statuses, .Fate)
		if !loaded { return "" }
		return string(render.tactical_status_chip_text(status.statuses.items[index], false, status.fate_sides))
	}
	if chip := fate_chip(renderer, room); chip != "DESTINO 3 d4" { fmt.eprintln("mechanics lab: the DESTINO chip says", chip); return false }
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_fate_chip.png")
	fated_id, fated_placed := game.spawn_enemy(room, {position = {center.x, center.y-1}, health = 60, attack = 1, archetype = .Chaser})
	if !fated_placed { fmt.eprintln("mechanics lab: no room for the fated foe"); return false }
	mechanics_lab_hold(room, fated_id)
	render.clear_event_animations(renderer)
	for _ in 0..<12 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	// Its d4 shows a 2: the bump's 2 and Bruciatura of as many stacks.
	if !fate_bump(window, renderer, room, controller, cards, buffer, 4, 2) { fmt.eprintln("mechanics lab: the d4's bump was not taken"); return false }
	fated := foe(room, fated_id)
	if fated == nil || fated.health != 58 || stacks(room, fated_id, .Burn) != 2 || game.player_charges(room, .Fate) != 2 {
		fmt.eprintln("mechanics lab: the d4's 2 left", stacks(room, fated_id, .Burn), "Bruciatura and", game.player_charges(room, .Fate), "bumps"); return false
	}
	mechanics_lab_film(window, renderer, room, controller, cards, buffer, 76, 2, "fate")
	// Played again, it loads back to three bumps, never more.
	if !mechanics_lab_play(window, renderer, room, controller, cards, buffer, .Fate_Dice, self) {
		fmt.eprintln("mechanics lab: Dado del Destino was not played again"); return false
	}
	mechanics_lab_wait_free(window, renderer, room, controller, cards, buffer)
	if game.player_charges(room, .Fate) != game.FATE_DICE_CHARGES {
		fmt.eprintln("mechanics lab: Dado del Destino played again loaded", game.player_charges(room, .Fate), "bumps"); return false
	}
	// On a d20 a 16 fells the foe outright.
	if !fate_bump(window, renderer, room, controller, cards, buffer, 20, 16) { fmt.eprintln("mechanics lab: the d20's bump was not taken"); return false }
	if foe(room, fated_id) != nil || game.player_charges(room, .Fate) != 2 {
		fmt.eprintln("mechanics lab: the d20's 16 did not fell the foe"); return false
	}
	mechanics_lab_film(window, renderer, room, controller, cards, buffer, 76, 2, "fate_lethal")
	if chip := fate_chip(renderer, room); chip != "DESTINO 2 d20" { fmt.eprintln("mechanics lab: after the d20 the DESTINO chip says", chip); return false }
	// Three more charges beside it: three chips and a count, DESTINO's d20 among
	// them, every word whole in its chip (each takes the room its words ask,
	// render.tactical_status_chip_layout; odin_pp_mechanics_lab_fate_chips.png).
	others := [3]game.Status_Kind{.Deflect, .Arrows, .Venom_Blade}
	for kind in others { _, _ = game.apply_status(room, game.PLAYER_ENTITY, kind, 2, 0) }
	for _ in 0..<2 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 0) }
	chips := render.tactical_status_chip_layout(renderer, room)
	if chips.shown != 3 || chips.more != 1 { fmt.eprintln("mechanics lab: the HUD shows", chips.shown, "chips and", chips.more, "more"); return false }
	for index in 0..<chips.shown {
		if _, _, _, fit := render.gothic_text_fit_plan(renderer, chips.texts[index], chips.bounds[index].width-render.HUD_CHIP_TEXT_MARGIN, 12); fit != .Fits {
			fmt.eprintln("mechanics lab: the HUD chip", chips.texts[index], "does not hold in", chips.bounds[index].width, "px:", fit); return false
		}
	}
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_fate_chips.png")
	for kind in others { _, _ = game.remove_status(room, game.PLAYER_ENTITY, kind) }
	// The Custodian is a miniboss: the same 16 is only a critical, the bump's
	// 2 doubled.
	custodian_id, custodian_placed := game.spawn_enemy(room, {position = {center.x, center.y-1}, health = 60, attack = 1, archetype = .Custodian})
	if !custodian_placed { fmt.eprintln("mechanics lab: no room for the Custodian"); return false }
	mechanics_lab_hold(room, custodian_id)
	render.clear_event_animations(renderer)
	for _ in 0..<12 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	if !fate_bump(window, renderer, room, controller, cards, buffer, 20, 16) { fmt.eprintln("mechanics lab: the Custodian's bump was not taken"); return false }
	custodian := foe(room, custodian_id)
	if custodian == nil || custodian.health != 56 || game.player_charges(room, .Fate) != 1 {
		fmt.eprintln("mechanics lab: the d20's 16 on the Custodian left him", custodian.health if custodian != nil else -1, "hp"); return false
	}
	mechanics_lab_film(window, renderer, room, controller, cards, buffer, 76, 2, "fate_boss")
	fmt.eprintln("mechanics lab charges: deflected a bolt, a cleave and a charge, an arrow (none through cover), three fated bumps (Bruciatura 2, lethal, critical on the Custodian)")
	return true
}

// LAZZO from the hand (game/lasso.odin), as the lane plays it. Four cells from
// the west wall the ring is 3, where one cell further east it would be 4: the
// wall stands on the fourth cell. Aimed, the board marks the foes it can take,
// the Custodian included, and the ring it would spin on, the
// three foes held on it in orange (odin_pp_mechanics_lab_lasso_preview.png,
// odin_pp_mechanics_lab_lasso_miniboss.png). Thrown four cells north-north-east,
// the rope flies, wraps and lifts the foe onto its ring
// (odin_pp_living_lasso_throw_NN.png), then swings it round the player while
// the world runs (odin_pp_living_lasso_NN.png, every third frame through the
// hits, then every eighth):
// hits 1, 2 and 3 on the foes held north, south and north-east, each knocked
// straight away from the player as many cells as its number (the last one
// diagonally) and wounded as much, the swung foe with it; every full turn
// takes 1 more from the swung foe (its life checked at every frame); meanwhile
// a free archer, set down after the aim's stills, aims and shoots the pivot,
// the defence prompt opens, the blow goes through and the rope holds; on its
// 18th point the swung foe falls and the rope goes slack. Beside the west wall
// the ring is 1: the swung foe smashes into the wall, each smash's number on
// it alone, and turns back at every one (odin_pp_living_lasso_smash_NN.png); the
// HUD's rope line holds whole in either window; a dodge then lets it go: it
// lands under itself and plans a fresh intent at once, no daze, its card
// falling with MOLLATO as the dodge shows (odin_pp_living_lasso_release_NN.png).
mechanics_lab_lasso :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	center := grid.Position{run_session.MECHANICS_LAB_WIDTH/2, run_session.MECHANICS_LAB_HEIGHT/2}
	foe :: mechanics_lab_enemy
	// A fresh arena, the player at `at` with a whole window and his dodge
	// ready, nothing on him from the acts before.
	reset :: proc(room: ^game.Room, at: grid.Position) -> bool {
		if !mechanics_lab_clear_arena(room) { return false }
		game.clear_ground(room)
		clear(&room.loot)
		room.player.health = room.player.stats.max_health
		room.player.position = at
		room.player.equipment = {}
		for kind in ([6]game.Status_Kind{.Deflect, .Arrows, .Fate, .Venom_Blade, .Poison, .Burn}) { _, _ = game.remove_status(room, game.PLAYER_ENTITY, kind) }
		room.player.tactical.dodge_recovery = 0
		return true
	}
	// A foe held where it stands, unless `free`: then it plans as any foe.
	spawn :: mechanics_lab_spawn_enemy
	// The aim as the board shows it with the mouse on `cell`.
	aim :: mechanics_lab_capture_aim
	// Frames with the clock running until a window opens that the throw and
	// its spin will not run out of.
	wait_window :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
		cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, seconds: f32) {
		for _ in 0..<600 {
			if room.player.tactical.phase == .Decision && room.player.tactical.remaining > seconds && !render.renderer_blocks_player_input(renderer) &&
			   !game.tactical_player_busy(room) && !room.tactical_pulse.pending && room.qte.kind == .None { break }
			mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
		}
	}
	// What the rope's hits have taken from the swung foe so far: hit n takes n,
	// counted from the first hit's number.
	struck :: proc(state: game.Lasso_State) -> i32 {
		return state.hits*state.first_hit+state.hits*(state.hits-1)/2
	}
	// One frame of a film with the clock running, saved as
	// odin_pp_living_<name>_NN.png when `save` (NN counted by `shot`).
	reel :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
		cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, name: string, save: bool, shot: ^int) {
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
		if save {
			artifacts.screenshot(fmt.ctprintf("odin_pp_living_%s_%02d.png", name, shot^))
			shot^ += 1
		}
	}
	wait_window(window, renderer, room, controller, cards, buffer, 12)
	// I. The west wall on the fourth cell: a ring of 3.
	at := grid.Position{4, center.y}
	if !reset(room, at) { return false }
	player.tactical.facing = .East
	open, _ := game.lasso_radius(room, {at.x+1, at.y})
	walled, walled_smash := game.lasso_radius(room, at)
	if open != 4 || walled != 3 || walled_smash {
		fmt.eprintln("mechanics lab: four cells from the wall the Lazzo spins at", walled, "and a cell further at", open); return false
	}
	SWUNG :: i32(18)
	// The foe to swing, four cells off: it is pulled in onto the ring.
	target_id := spawn(room, {at.x+2, at.y-4}, SWUNG)
	// Three foes held on the ring, struck in the spin's order: north, south,
	// north-east (each knocked off it where the board shows it).
	standing := [3]struct{id: u32, cell: grid.Position}{{cell = {at.x, at.y-3}}, {cell = {at.x, at.y+3}}, {cell = {at.x+2, at.y-2}}}
	for &stander in standing { stander.id = spawn(room, stander.cell, 30) }
	custodian_id := spawn(room, {at.x+4, at.y-3}, 40, .Custodian)
	if target_id == 0 || standing[0].id == 0 || standing[1].id == 0 || standing[2].id == 0 || custodian_id == 0 {
		fmt.eprintln("mechanics lab: no room for the lasso's foes"); return false
	}
	render.clear_event_animations(renderer)
	for _ in 0..<12 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	card, held := mechanics_lab_hand_card(player, .Lasso)
	if !held { fmt.eprintln("mechanics lab: no Lazzo in hand"); return false }
	index, _ := game.hand_card_index_by_id(&player.deck, card)
	instance := player.deck.hand[index]
	mechanics_lab_still(window, renderer, room, card, "odin_pp_mechanics_lab_card_Lasso.png")
	aim(window, renderer, room, card, foe(room, target_id).position, "odin_pp_mechanics_lab_lasso_preview.png")
	// The Custodian is a miniboss: the same valid target as every other foe.
	custodian := foe(room, custodian_id).position
	_, takes := game.card_drop_target(room, instance, custodian)
	if !takes || game.lasso_target_error(room, game.entity_target(game.enemy_entity(custodian_id))) != .None {
		fmt.eprintln("mechanics lab: the Lazzo refused the Custodian"); return false
	}
	aim(window, renderer, room, card, custodian, "odin_pp_mechanics_lab_lasso_miniboss.png")
	// Then a free archer east, four cells down a clear line, off the ring: it
	// takes aim at once.
	archer_id := spawn(room, {at.x+4, at.y}, 30, .Archer, free = true)
	if archer_id == 0 { fmt.eprintln("mechanics lab: no room for the archer"); return false }
	for _ in 0..<12 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	if aiming := foe(room, archer_id); aiming == nil || aiming.intent.kind != .Attack || !aiming.intent.windup {
		fmt.eprintln("mechanics lab: the free archer takes no aim at the pivot"); return false
	}
	lasso := &renderer.tactical.lasso
	hits, smashes, whirrs, releases, drops := lasso.spawned_hits, lasso.spawned_smashes, lasso.whirrs, lasso.releases, lasso.drops
	health, pulses := player.health, room.pulse_count
	if !mechanics_lab_play(window, renderer, room, controller, cards, buffer, .Lasso, game.entity_target(game.enemy_entity(target_id))) ||
	   !room.lasso.active || room.lasso.radius != 3 || room.lasso.smash || room.lasso.first_hit != 1 {
		fmt.eprintln("mechanics lab: the Lazzo by the wall was not thrown at radius 3:", room.lasso.radius, room.lasso.first_hit); return false
	}
	frame := 0
	for _ in 0..<240 {
		if !game.tactical_is_casting(room) && !render.renderer_blocks_player_input(renderer) { break }
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "lasso_throw", 4, &frame)
	}
	// The spin. At every frame the swung foe has lost its hits' numbers and one
	// a turn, nothing else; the archer's blow opens a defence prompt that lets it
	// through, and the rope holds.
	seen: game.Lasso_State
	shot, spun := 0, 0
	prompted, held_on, wounded := false, false, false
	for _ in 0..<1800 {
		if !room.lasso.active { break }
		reel(window, renderer, room, controller, cards, buffer, "lasso", spun%(3 if spun < 60 else 8) == 0, &shot)
		spun += 1
		if room.lasso.active {
			seen = room.lasso
			swung := foe(room, target_id)
			if swung == nil || swung.health != SWUNG-struck(seen)-seen.turns {
				fmt.eprintln("mechanics lab: the swung foe has", swung.health if swung != nil else -1, "hp after", seen.hits, "hits and",
					seen.turns, "turns"); return false
			}
		}
		if room.qte.kind == .Defense && room.qte.enemy_id == archer_id { prompted = true }
		if prompted && room.qte.kind == .None && room.lasso.active { held_on = true }
		if room.lasso.active && player.health < health { wounded = true }
	}
	// The rope slack, the body falling.
	for after in 0..<24 { reel(window, renderer, room, controller, cards, buffer, "lasso", after%6 == 0, &shot) }
	mechanics_lab_hold(room, archer_id)
	if room.lasso.active || foe(room, target_id) != nil || room.phase != .Combat || game.tactical_player_busy(room) {
		fmt.eprintln("mechanics lab: the lassoed foe did not fall"); return false
	}
	// Hits 1, 2 and 3, each struck foe knocked as many cells away from the
	// player as its hit's number (snapped to the eight ways) and wounded as
	// much; every turn before the fatal one seen.
	for stander, order in standing {
		hit := seen.first_hit+i32(order)
		step := game.lasso_radial_step(at, stander.cell)
		landing := grid.Position{stander.cell.x+step.x*int(hit), stander.cell.y+step.y*int(hit)}
		struck_foe := foe(room, stander.id)
		if struck_foe == nil || struck_foe.position != landing || struck_foe.health != 30-hit {
			fmt.eprintln("mechanics lab: hit", hit, "left the foe from", stander.cell, "on", struck_foe.position if struck_foe != nil else stander.cell,
				"with", struck_foe.health if struck_foe != nil else -1, "hp, not on", landing); return false
		}
	}
	if seen.hits != 3 || seen.turns != SWUNG-struck(seen)-1 {
		fmt.eprintln("mechanics lab: the rope made", seen.hits, "hits and", seen.turns, "turns"); return false
	}
	// The world ran through the spin: its beats, the archer's aim and its one
	// shot, which reached the pivot while the rope still held.
	archer := foe(room, archer_id)
	if archer == nil || room.pulse_count < pulses+4 || !prompted || !held_on || !wounded || player.health != health-archer.attack {
		fmt.eprintln("mechanics lab: the world did not run under the rope:", room.pulse_count-pulses, "beats, prompt", prompted, "held", held_on,
			"player", player.health, "of", health); return false
	}
	if lasso.spawned_hits < hits+3 || lasso.whirrs <= whirrs || lasso.drops <= drops || lasso.ring_texture.id == 0 {
		fmt.eprintln("mechanics lab: the lasso was not shown:", lasso.spawned_hits-hits, "hits,", lasso.whirrs-whirrs, "whirrs"); return false
	}
	turns := seen.turns+1
	// II. Beside the west wall: a ring of 1, smashes into the wall and back.
	wait_window(window, renderer, room, controller, cards, buffer, 6)
	if !reset(room, {1, center.y}) { return false }
	SMASHED :: i32(60)
	// Free, not held: let go, it plans afresh.
	smashed_id := spawn(room, {4, center.y}, SMASHED, free = true)
	if smashed_id == 0 { fmt.eprintln("mechanics lab: no room for the smashed foe"); return false }
	render.clear_event_animations(renderer)
	for _ in 0..<12 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	if !mechanics_lab_play(window, renderer, room, controller, cards, buffer, .Lasso, game.entity_target(game.enemy_entity(smashed_id))) ||
	   !room.lasso.active || room.lasso.radius != 1 || !room.lasso.smash {
		fmt.eprintln("mechanics lab: the Lazzo beside the wall did not smash:", room.lasso.radius, room.lasso.smash); return false
	}
	for _ in 0..<240 {
		if !game.tactical_is_casting(room) && !render.renderer_blocks_player_input(renderer) { break }
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
	}
	// Each smash's number on the swung foe alone, a turn's 1 too, and the spin
	// turned back at each: its way flips with every smash.
	frame = 0
	for _ in 0..<150 {
		if !room.lasso.active { break }
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "lasso_smash", 5, &frame)
		if !room.lasso.active { break }
		state := room.lasso
		swung := foe(room, smashed_id)
		if swung == nil || swung.health != SMASHED-struck(state)-state.turns || state.direction != (-1 if state.hits%2 == 0 else 1) {
			fmt.eprintln("mechanics lab: after", state.hits, "smashes and", state.turns, "turns the swung foe has",
				swung.health if swung != nil else -1, "hp, turning", state.direction); return false
		}
	}
	if !room.lasso.active || room.lasso.hits < 2 || lasso.spawned_smashes < smashes+2 {
		fmt.eprintln("mechanics lab: the lasso smashed", room.lasso.hits, "times,", lasso.spawned_smashes-smashes, "shown"); return false
	}
	bounces := room.lasso.hits
	// The HUD's rope line holds whole beside the plate's objective, in the
	// lab's fixed window and in the game's shrinking one, and with two figures
	// each and a full room (render.lasso_hud_line beside the rope's short
	// objective), whatever lets it go.
	for shrinking in ([2]bool{false, true}) {
		player.tactical.config.shrinking_window = shrinking
		line := render.lasso_hud_status(room)
		room_width := render.tactical_hud_status_room(renderer, render.tactical_hud_objective(renderer, room))
		if _, _, _, fit := render.gothic_text_fit_plan(renderer, line, room_width, 10); fit != .Fits {
			fmt.eprintln("mechanics lab: the HUD's rope line", line, "does not hold in", room_width, "px:", fit); return false
		}
	}
	player.tactical.config.shrinking_window = false
	worst := render.tactical_hud_status_room(renderer, render.tactical_hud_foes_objective(game.MAX_ENEMIES_PER_ROOM))
	for way in render.Lasso_Let_Go {
		line := render.lasso_hud_line(88, 88, way, 8)
		if _, _, _, fit := render.gothic_text_fit_plan(renderer, line, worst, 10); fit != .Fits {
			fmt.eprintln("mechanics lab: the HUD's rope line", line, "does not hold in", worst, "px:", fit); return false
		}
	}
	// A dodge lets go (away from the cell under the foe): it lands under
	// itself and plans a fresh intent at once, no daze; its card falls with
	// MOLLATO as the dodge shows, not once it has played.
	under := game.lasso_arc_cell(&room.lasso, room.lasso.arc)
	dodge := game.Move_Direction.South
	for direction in ([3]game.Move_Direction{.South, .North, .East}) {
		if landing, clear := game.tactical_dodge_destination(room, direction); clear && landing != under { dodge = direction; break }
	}
	if !run_session.commit_gameplay_command(room, renderer, cards, {kind = .Dodge, origin_phase = .Combat, direction = dodge}) || room.lasso.active {
		fmt.eprintln("mechanics lab: the dodge did not let the lasso go"); return false
	}
	smashed := foe(room, smashed_id)
	if smashed == nil || smashed.position != under || smashed.recovery_pulses != 0 ||
	   smashed.intent.kind == .Recover || smashed.intent.kind == .Wait || smashed.intent.kind == .None {
		fmt.eprintln("mechanics lab: the released foe did not land on", under, "with a fresh intent:",
			smashed.intent.kind if smashed != nil else game.Enemy_Intent_Kind.None); return false
	}
	planned := smashed.intent.kind
	frame = 0
	dropped := -1
	for after in 0..<45 {
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "lasso_release", 3, &frame)
		if dropped < 0 && lasso.releases > releases { dropped = after }
	}
	if dropped < 0 || dropped > 2 || lasso.released <= 0 {
		fmt.eprintln("mechanics lab: the board let the lasso go", dropped, "frames after the dodge"); return false
	}
	mechanics_lab_hold(room, smashed_id)
	fmt.eprintf("mechanics lab lasso: radius 3 by the wall (4 a cell further), hits 1, 2, 3 and %d turns, the archer's blow through the rope; " +
		"radius 1 with %d smashes and as many turns back, let go on %v, then %v\n", turns, bounces, under, planned)
	return true
}

// A stream for the room's catches whose next one is a card, or else food of
// `food`: the lab shows chosen catches.
mechanics_lab_fishing_stream :: proc(card: bool, food := game.Fishing_Food.Fish) -> (seed: u64, ok: bool) {
	for candidate in u64(1)..<u64(400_000) {
		random := candidate
		if game.fishing_catch_is_card(&random) != card { continue }
		if card || game.fishing_catch_food(&random) == food { return candidate, true }
	}
	return
}

// CANNA DA PESCA (game/fishing.odin), as F7 and its slot play it, last. F7
// clears the arena as a room's last fall clears it: two held foes fall and the
// rod's slot opens with PESCA 1/1 (odin_pp_living_fishing_clear_NN.png). Its
// inspector under the mouse (odin_pp_mechanics_lab_rod_slot.png); then chosen,
// with the mouse on the water's cell, the cells it may fish and that one green
// (odin_pp_mechanics_lab_rod_preview.png). Picked up on the slot and let go
// over that cell, it fishes there: the cast, the bobber on the new water, the
// bite, a fish reeled out and flying to the player, its d4 over the window (a
// 3: odin_pp_mechanics_lab_fishing_roll.png) and its 3 of life
// (odin_pp_living_fishing_NN.png); the room's one fishing is then spent, and
// the 3D board shows the water.
// The rod upgraded, F7 again starts afresh, no water and two fishings
// (PESCA 2/2: odin_pp_mechanics_lab_rod_slot_upgraded.png): first a card comes
// out of the water into the run deck, never another rod
// (odin_pp_living_fishing_card_NN.png), then the same water fished again, no
// new pool, gives bread for its d4's 2 (odin_pp_living_fishing_again_NN.png),
// and the room's fishings are made; F7 once more gives the new room its two.
// No fishing sounds the player's own clips (his lantern's blow, the pickup's
// coins, a card's cast).
// Last, the rule of one rod a run: with the rod in the deck no offer draws
// another, where the same draws without it do.
mechanics_lab_fishing :: proc(window: ^app.Window, renderer: ^render.Renderer, dice: ^render.Dice_Renderer, room: ^game.Room,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	center := grid.Position{run_session.MECHANICS_LAB_WIDTH/2, run_session.MECHANICS_LAB_HEIGHT/2}
	// Plays frames with the clock running until the board is done showing,
	// every `every`th saved as odin_pp_living_<name>_NN.png (the dice over the
	// window as the game shows them); the roll's still once it has settled.
	film :: proc(window: ^app.Window, renderer: ^render.Renderer, dice: ^render.Dice_Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
		cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, name: string, every: int, roll: cstring = nil) -> (rolled: bool) {
		frame := 0
		for _ in 0..<720 {
			mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true, dice)
			if frame%every == 0 { artifacts.screenshot(fmt.ctprintf("odin_pp_living_%s_%02d.png", name, frame/every)) }
			frame += 1
			cue, showing := render.active_presentation_cue(&renderer.timeline)
			if roll != nil && !rolled && showing && cue.kind == .Dice_Rolled && render.presentation_cue_progress(cue) > 0.86 {
				artifacts.screenshot(roll)
				rolled = true
			}
			if !render.renderer_blocks_player_input(renderer) { break }
		}
		for _ in 0..<2*every {
			mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true, dice)
			if frame%every == 0 { artifacts.screenshot(fmt.ctprintf("odin_pp_living_%s_%02d.png", name, frame/every)) }
			frame += 1
		}
		return
	}
	// The board with the rod chosen (`selected`) or under the mouse, the mouse
	// on `cell` (none: off the board).
	still :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, hovered, selected: u32, cell: grid.Position, on_cell: bool, name: cstring) {
		for _ in 0..<3 {
			render.update_renderer_frame_timeline(renderer, 0)
			render.update_tactical_view(renderer, room, {}, false, true)
			renderer.has_hovered_cell, renderer.hovered_cell = on_cell, cell
			app.begin_canvas(window, render.RESIN_BACKGROUND)
			render.draw_tactical_world(renderer, room, selected)
			render.draw_tactical_status(renderer, room)
			render.draw_tactical_hand(renderer, room, hovered, selected, 0, {})
			render.draw_tactical_hud(renderer, room, false, false)
			render.draw_mechanics_lab_banner(renderer, room)
			app.present(window, render.LETTERBOX_COLOR)
		}
		artifacts.screenshot(name)
		renderer.has_hovered_cell = false
	}
	// The board shows `cell` as the rod's water.
	shows_water :: proc(renderer: ^render.Renderer, cell: grid.Position) -> bool {
		return renderer.tactical.snapshot != nil && render.presentation_ground_water(&renderer.tactical.snapshot.ground, cell)
	}
	// Waits for a free board, then a fresh arena around the player in the
	// middle, a little hurt, nothing on him from the acts before.
	for _ in 0..<600 {
		if !render.renderer_blocks_player_input(renderer) && !game.tactical_player_busy(room) && !game.tactical_is_casting(room) &&
		   room.qte.kind == .None && !room.tactical_pulse.pending { break }
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
	}
	if !mechanics_lab_clear_arena(room) { return false }
	game.clear_ground(room)
	clear(&room.loot)
	player.position = center
	player.equipment = {}
	for kind in ([6]game.Status_Kind{.Deflect, .Arrows, .Fate, .Venom_Blade, .Poison, .Burn}) { _, _ = game.remove_status(room, game.PLAYER_ENTITY, kind) }
	player.health = player.stats.max_health-6
	for at in ([2]grid.Position{{center.x+3, center.y-2}, {center.x-3, center.y+1}}) {
		id, placed := game.spawn_enemy(room, {position = at, health = 30, attack = 1, archetype = .Chaser})
		if !placed { fmt.eprintln("mechanics lab: no room for the foes F7 clears"); return false }
		mechanics_lab_hold(room, id)
	}
	render.clear_event_animations(renderer)
	for _ in 0..<12 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	if game.fishing_room_open(room) { fmt.eprintln("mechanics lab: the rod opened in a fight"); return false }
	// F7: every foe falls and the room is cleared, its exit still shut.
	if !run_session.mechanics_lab_clear_for_fishing(room, renderer) { fmt.eprintln("mechanics lab: F7 did not clear the arena"); return false }
	if room.phase != .Loot || len(room.enemies) != 0 || !game.fishing_room_open(room) || game.fishing_casts_left(room) != 1 {
		fmt.eprintln("mechanics lab: the cleared arena does not open the rod:", room.phase, len(room.enemies), game.fishing_casts_left(room)); return false
	}
	_ = film(window, renderer, dice, room, controller, cards, buffer, "fishing_clear", 6)
	// The fallen cards finish toppling.
	for _ in 0..<150 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true) }
	sandbox := game.begin_sandbox(11)
	if _, spawned := game.sandbox_tick(room, &sandbox, 10); spawned { fmt.eprintln("mechanics lab: a foe arrived in the cleared arena"); return false }
	rod, held := game.fishing_rod(&player.deck)
	if !held { fmt.eprintln("mechanics lab: no rod in the deck"); return false }
	water := grid.Position{center.x+2, center.y-1}
	still(window, renderer, room, rod.id, 0, {}, false, "odin_pp_mechanics_lab_rod_slot.png")
	still(window, renderer, room, 0, rod.id, water, true, "odin_pp_mechanics_lab_rod_preview.png")
	if game.fishing_target_error(room, water) != .Fished || game.fishing_target_error(room, {center.x+4, center.y}) != .Out_Of_Reach ||
	   game.fishing_target_error(room, center) == .Fished {
		fmt.eprintln("mechanics lab: the rod's aim is wrong"); return false
	}
	// Picked up on the slot, let go over the cell: the lane's own fishing.
	slot := render.fishing_slot_bounds(renderer)
	cards^ = {}
	_, picked, taken := run_session.poll_fishing_command(room, renderer, cards, {mouse = {slot.x+slot.width*0.5, slot.y+40}, inside = true, pressed = true, down = true}, true)
	if picked || !taken || cards.dragged_card_id != rod.id { fmt.eprintln("mechanics lab: the slot did not pick the rod up"); return false }
	renderer.has_hovered_cell, renderer.hovered_cell = true, water
	command, dropped, _ := run_session.poll_fishing_command(room, renderer, cards, {mouse = render.cell_center(renderer, water), inside = true, released = true}, true)
	renderer.has_hovered_cell = false
	if !dropped || command.kind != .Fish || command.target != game.cell_target(water) { fmt.eprintln("mechanics lab: the rod let go over the water fished nothing"); return false }
	// A fish, its d4 a 3.
	stream, found := mechanics_lab_fishing_stream(false, .Fish)
	if !found { return false }
	room.fishing.random = stream
	forced, forced_found := mechanics_lab_dice_for_face(3, 4)
	if !forced_found { return false }
	player.dice = forced
	health, owned := player.health, player.deck.owned_count
	view := &renderer.tactical.fishing
	casts, bites, catches, cards_caught := view.casts, view.bites, view.catches, view.cards
	failures := renderer.timeline.update_failures
	// The player's card sounds no clip of its own while it fishes: neither the
	// lantern's blow, the pickup's coins nor a card's cast (render.lab_actor_sfx).
	clip_sounds :: proc(renderer: ^render.Renderer) -> [3]int {
		s := renderer.tactical.lab_sounds
		if s == nil { return {} }
		return {s.played[.Pilgrim_Attack], s.played[.Pilgrim_Interact], s.played[.Pilgrim_Cast]}
	}
	voiced := clip_sounds(renderer)
	if !run_session.commit_gameplay_command(room, renderer, cards, command) { fmt.eprintln("mechanics lab: the fishing was not taken"); return false }
	if player.health != health+3 || !game.fishing_cell_is_water(room, water) || game.fishing_casts_left(room) != 0 || player.deck.owned_count != owned {
		fmt.eprintln("mechanics lab: the fish gave", player.health-health, "life"); return false
	}
	if !film(window, renderer, dice, room, controller, cards, buffer, "fishing", 5, "odin_pp_mechanics_lab_fishing_roll.png") {
		fmt.eprintln("mechanics lab: the fish's d4 did not show"); return false
	}
	if clip_sounds(renderer) != voiced { fmt.eprintln("mechanics lab: the fishing sounded the player's blow, pickup or cast:", clip_sounds(renderer), voiced); return false }
	if view.casts != casts+1 || view.bites != bites+1 || view.catches != catches+1 || view.cards != cards_caught ||
	   renderer.timeline.update_failures != failures {
		fmt.eprintln("mechanics lab: the fishing was not shown:", view.casts-casts, view.bites-bites, view.catches-catches); return false
	}
	// The room's one fishing is made; the board shows the new water.
	if game.fishing_target_error(room, water) != .Spent { fmt.eprintln("mechanics lab: a second fishing was allowed"); return false }
	if !shows_water(renderer, water) { fmt.eprintln("mechanics lab: the board shows no water on", water); return false }

	// The rod upgraded out of a fight, as a rest or a shop upgrades it: a room's
	// fishings are 1 + its level, two now.
	if game.upgrade_owned_card(&player.deck, rod.id) != .Upgraded { fmt.eprintln("mechanics lab: the rod was not upgraded"); return false }
	// F7 again: afresh, no water, and two fishings (PESCA 2/2).
	if !run_session.mechanics_lab_clear_for_fishing(room, renderer) || room.fishing.water_count != 0 || game.fishing_casts_allowed(room) != 2 ||
	   game.fishing_casts_left(room) != 2 {
		fmt.eprintln("mechanics lab: F7 again did not start two fishings afresh:", game.fishing_casts_left(room)); return false
	}
	for _ in 0..<12 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	if shows_water(renderer, water) { fmt.eprintln("mechanics lab: the last room's water still shows"); return false }
	still(window, renderer, room, rod.id, 0, {}, false, "odin_pp_mechanics_lab_rod_slot_upgraded.png")
	// The first: a card out of the water, into the run deck, never another rod.
	stream, found = mechanics_lab_fishing_stream(true)
	if !found { return false }
	room.fishing.random = stream
	owned = player.deck.owned_count
	health = player.health
	voiced = clip_sounds(renderer)
	if !run_session.commit_gameplay_command(room, renderer, cards, {kind = .Fish, origin_phase = .Loot, card_id = rod.id, target = game.cell_target(water)}) {
		fmt.eprintln("mechanics lab: the second room's fishing was not taken"); return false
	}
	caught := player.deck.owned[player.deck.owned_count-1]
	if player.deck.owned_count != owned+1 || caught.definition_id == .Fishing_Rod || player.health != health || !game.validate_deck_state(&player.deck) ||
	   game.fishing_casts_left(room) != 1 || room.fishing.water_count != 1 {
		fmt.eprintln("mechanics lab: the card caught is", caught.definition_id); return false
	}
	_ = film(window, renderer, dice, room, controller, cards, buffer, "fishing_card", 5)
	if view.cards != cards_caught+1 || renderer.timeline.update_failures != failures {
		fmt.eprintln("mechanics lab: the card caught was not shown"); return false
	}
	// The second on the same water, fished again (no new pool): bread, its d4
	// a 2. Then the room's two fishings are made.
	stream, found = mechanics_lab_fishing_stream(false, .Bread)
	if !found { return false }
	room.fishing.random = stream
	forced, forced_found = mechanics_lab_dice_for_face(2, 4)
	if !forced_found { return false }
	player.dice = forced
	health = player.health
	catches = view.catches
	if !run_session.commit_gameplay_command(room, renderer, cards, {kind = .Fish, origin_phase = .Loot, card_id = rod.id, target = game.cell_target(water)}) {
		fmt.eprintln("mechanics lab: the same water was not fished again"); return false
	}
	if player.health != health+2 || room.fishing.water_count != 1 || game.fishing_casts_left(room) != 0 || game.fishing_target_error(room, water) != .Spent {
		fmt.eprintln("mechanics lab: the bread gave", player.health-health, "life,", game.fishing_casts_left(room), "fishings left"); return false
	}
	_ = film(window, renderer, dice, room, controller, cards, buffer, "fishing_again", 5)
	if view.catches != catches+1 || renderer.timeline.update_failures != failures || !shows_water(renderer, water) {
		fmt.eprintln("mechanics lab: the second fishing was not shown"); return false
	}
	if clip_sounds(renderer) != voiced { fmt.eprintln("mechanics lab: the fishings sounded the player's blow, pickup or cast:", clip_sounds(renderer), voiced); return false }
	// F7 once more: a new room, its two fishings afresh.
	if !run_session.mechanics_lab_clear_for_fishing(room, renderer) || game.fishing_casts_left(room) != 2 || room.fishing.water_count != 0 {
		fmt.eprintln("mechanics lab: a new room did not give the rod its two fishings again"); return false
	}
	for _ in 0..<12 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	// One rod a run: while the deck holds it, no offer brings another. The
	// rewards, the shop, the Armory and a catch all draw with the deck's
	// exclusions (card_offer_exclusions); the same draws without them bring
	// rods.
	excluded := game.card_offer_exclusions(&player.deck)
	rod_definition, _ := game.card_definition_by_id(.Fishing_Rod)
	node := game.Run_Node{kind = .Combat, depth = 4}
	if excluded != {.Fishing_Rod} || game.card_offer_weight(rod_definition, &node) == 0 ||
	   game.card_offer_weight(rod_definition, &node, &player.m8_profile, excluded) != 0 {
		fmt.eprintln("mechanics lab: the deck's rod does not leave the rod out of the offers:", excluded); return false
	}
	with_rod, without_rod := 0, 0
	for seed in u64(1)..=400 {
		for leave_out in ([2]bool{true, false}) {
			random := seed
			offer: [3]game.Card_Id
			if !game.generate_weighted_card_choices(&random, &node, offer[:], &player.m8_profile, excluded if leave_out else {}) {
				fmt.eprintln("mechanics lab: no offer drawn for seed", seed); return false
			}
			for id in offer {
				if id != .Fishing_Rod { continue }
				if leave_out { with_rod += 1 } else { without_rod += 1 }
			}
		}
	}
	if with_rod != 0 || without_rod == 0 {
		fmt.eprintln("mechanics lab: rods offered:", with_rod, "with one in the deck,", without_rod, "without"); return false
	}
	fmt.eprintf("mechanics lab fishing: F7 cleared the arena, a fish for 3 life on %v; the rod at +1 fished there twice, a %v and bread for 2; " +
		"no rod in 400 offers with one in the deck (%d in as many without)\n", water, caught.definition_id, without_rod)
	return true
}

// Empties the arena for the next act: every foe falls with its own clip.
mechanics_lab_clear_arena :: proc(room: ^game.Room) -> bool {
	action := game.Action{kind = .Ability, source = game.PLAYER_ENTITY}
	for enemy in room.enemies {
		action.effects[action.effect_count] = {kind = .Damage, target = game.enemy_entity(enemy.id), amount = 1000}
		action.effect_count += 1
	}
	return action.effect_count == 0 || game.resolve_action(room, &action).accepted
}

// A still frame of the board as it stands (the hover and the aim the caller
// set), with `hovered` the hand card under the mouse (0: none), saved as `name`.
mechanics_lab_still :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, hovered: u32, name: cstring) {
	for _ in 0..<3 {
		render.update_renderer_frame_timeline(renderer, 0)
		render.update_tactical_view(renderer, room, {}, false, true)
		app.begin_canvas(window, render.RESIN_BACKGROUND)
		render.draw_tactical_world(renderer, room, 0)
		render.draw_tactical_status(renderer, room)
		render.draw_tactical_hand(renderer, room, hovered, 0, 0, {})
		render.draw_tactical_hud(renderer, room, false, false)
		render.draw_mechanics_lab_banner(renderer, room)
		app.present(window, render.LETTERBOX_COLOR)
	}
	artifacts.screenshot(name)
}

// A still frame with the mouse on `foe`, so its inspector stands beside the
// board, saved as `name`.
mechanics_lab_inspect_still :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, foe: game.Entity_Ref, name: cstring) {
	for _ in 0..<3 {
		render.update_renderer_frame_timeline(renderer, 0)
		render.update_tactical_view(renderer, room, {}, false, true)
		if index, found := game.enemy_index_by_id(room, foe.id); found {
			renderer.has_hovered_cell, renderer.hovered_cell = true, room.enemies[index].position
		}
		app.begin_canvas(window, render.RESIN_BACKGROUND)
		render.draw_tactical_world(renderer, room, 0)
		render.draw_tactical_status(renderer, room)
		render.draw_tactical_hand(renderer, room, 0, 0, 0, {})
		render.draw_tactical_hud(renderer, room, false, false)
		render.draw_mechanics_lab_banner(renderer, room)
		app.present(window, render.LETTERBOX_COLOR)
	}
	artifacts.screenshot(name)
	renderer.has_hovered_cell = false
}

// One frame of a film with the clock running; every `every`th one is saved
// as odin_pp_living_<name>_NN.png.
mechanics_lab_reel_frame :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, name: string, every: int, frame: ^int) {
	mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
	if frame^%every == 0 { artifacts.screenshot(fmt.ctprintf("odin_pp_living_%s_%02d.png", name, frame^/every)) }
	frame^ += 1
}

// The smoke's actions each sounded: steps, blows, hurts, the clock, the
// cure, the statuses, the stun and the fall.
mechanics_lab_sounds_heard :: proc(renderer: ^render.Renderer) -> bool {
	sounds := renderer.tactical.lab_sounds
	if sounds == nil { fmt.eprintln("mechanics lab: no sounds"); return false }
	heard := 0
	for count, sfx in sounds.played {
		if count > 0 { fmt.eprintln("mechanics lab sound:", sfx, count); heard += 1 }
	}
	// The step's clip follows the camera: any of the three.
	if sounds.played[.Pilgrim_Move_Side]+sounds.played[.Pilgrim_Move_Up]+sounds.played[.Pilgrim_Move_Down] == 0 {
		fmt.eprintln("mechanics lab: no sound for the step"); return false
	}
	for sfx in ([?]audio.Lab_Sfx{.Pilgrim_Attack, .Pilgrim_Hurt, .Ghoul_Hurt, .Pilgrim_Death, .Ui_Defeat, .Pilgrim_Heal, .Ui_Beat_Tick, .Ui_Stun}) {
		if sounds.played[sfx] == 0 { fmt.eprintln("mechanics lab: no sound for", sfx); return false }
	}
	for kind in ([?]game.Status_Kind{.Poison, .Burn, .Slow}) {
		sfx, _ := render.lab_status_sfx(kind)
		if sounds.played[sfx] == 0 { fmt.eprintln("mechanics lab: no sound for the status", kind, sfx); return false }
	}
	// The ground's: each card, its splash and its fire, an enemy splashing,
	// the fire spreading at a new window and going out at its fifth.
	for sfx in ([?]audio.Lab_Sfx{.Card_Poison_Pool, .Card_Wildfire, .World_Pool_Splash, .World_Fire, .World_Fire_Spread, .World_Fire_Out}) {
		if sounds.played[sfx] == 0 { fmt.eprintln("mechanics lab: no sound for", sfx); return false }
	}
	// The player's charges: each card, and each charge as it is loaded.
	for card in ([3]game.Card_Id{.Deflect, .Coffin, .Fate_Dice}) {
		sfx, _ := render.lab_card_sfx(card)
		if sounds.played[sfx] == 0 { fmt.eprintln("mechanics lab: no sound for the card", card, sfx); return false }
	}
	for kind in ([3]game.Status_Kind{.Deflect, .Arrows, .Fate}) {
		sfx, _ := render.lab_status_sfx(kind)
		if sounds.played[sfx] == 0 { fmt.eprintln("mechanics lab: no sound for the charge", kind, sfx); return false }
	}
	// What they do: a blow turned back, an arrow loosed, a die at a bump.
	for sfx in ([?]audio.Lab_Sfx{.Pilgrim_Deflect, .Pilgrim_Shoot, .Ui_Fate_Die}) {
		if sounds.played[sfx] == 0 { fmt.eprintln("mechanics lab: no sound for", sfx); return false }
	}
	// The Lazzo's: its card, the throw, the loop cinching, the whirr of its
	// turns, a hit, a smash and the rope let go.
	for sfx in ([?]audio.Lab_Sfx{.Card_Lasso, .Pilgrim_Lasso_Throw, .World_Lasso_Wrap, .World_Lasso_Whirr, .World_Lasso_Hit,
		.World_Lasso_Smash, .World_Lasso_Release}) {
		if sounds.played[sfx] == 0 { fmt.eprintln("mechanics lab: no sound for the rope", sfx); return false }
	}
	// The Pinball's: its card, the strike, a ding, a bong and the burst.
	for sfx in ([?]audio.Lab_Sfx{render.LAB_PINBALL_CARD, render.LAB_PINBALL_LAUNCH, render.LAB_PINBALL_DING, render.LAB_PINBALL_BONG,
		render.LAB_PINBALL_BURST}) {
		if sounds.played[sfx] == 0 { fmt.eprintln("mechanics lab: no sound for the Pinball", sfx); return false }
	}
	// The Canna da Pesca's: its card as it is cast, the plop, the bite, the
	// reel, food caught and a card caught.
	for sfx in ([?]audio.Lab_Sfx{.Card_Fishing_Rod, .World_Bobber_Plop, .World_Fish_Bite, .Pilgrim_Reel, .Pilgrim_Catch,
		.Ui_Fish_Card}) {
		if sounds.played[sfx] == 0 { fmt.eprintln("mechanics lab: no sound for the fishing", sfx); return false }
	}
	// The First Person Shooter's: its card, the dive in, a shot, a hit, a
	// shot on stone and the rise out.
	for sfx in ([?]audio.Lab_Sfx{render.LAB_FIRST_PERSON_CARD, render.LAB_FIRST_PERSON_ENTER, render.LAB_FIRST_PERSON_SHOT,
		render.LAB_FIRST_PERSON_HIT, render.LAB_FIRST_PERSON_RICOCHET, render.LAB_FIRST_PERSON_EXIT}) {
		if sounds.played[sfx] == 0 { fmt.eprintln("mechanics lab: no sound for the first person", sfx); return false }
	}
	// The Inondazione's: its card, the wave, a foe splashed and a fire's steam.
	for sfx in ([?]audio.Lab_Sfx{.Card_Flood, .World_Flood_Wave, .World_Flood_Splash, .World_Flood_Steam}) {
		if sounds.played[sfx] == 0 { fmt.eprintln("mechanics lab: no sound for the flood", sfx); return false }
	}
	// Bomb Marley's: its card, the ball, the lights, a warning, a bomb and its
	// blast, a character saved, the seconds earned, the groove in both beats
	// and the end.
	for sfx in ([?]audio.Lab_Sfx{.Card_Bomb_Marley, .World_Marley_Ball, .World_Marley_Lights, .World_Marley_Warn, .World_Marley_Bomb,
		.World_Marley_Blast, .World_Marley_Safe, .World_Marley_Bonus, .World_Marley_Groove_A, .World_Marley_Groove_B, .World_Marley_End}) {
		if sounds.played[sfx] == 0 { fmt.eprintln("mechanics lab: no sound for the party", sfx); return false }
	}
	// The Cannone's: its card, the stand, a shot, a strike, the beam, the fall;
	// the Buco Nero's: its card, the opening, the hum, the pull, a foe swallowed,
	// the closing; the Dinosauro's: its card, a roar of each, the steps, a stomp
	// and the climb down; the Sanguinamento's.
	for sfx in ([?]audio.Lab_Sfx{.Card_Cannon, .Card_Laser_Cannon, .World_Cannon_Place, .World_Cannon_Fire, .World_Cannon_Hit, .World_Laser_Fire,
		.World_Cannon_Break, .Card_Black_Hole, .World_Black_Hole_Open, .World_Black_Hole_Hum, .World_Black_Hole_Pull, .World_Black_Hole_Swallow,
		.World_Black_Hole_Close, .Card_Dinosaur, .World_Dino_Roar_Raptor, .World_Dino_Roar_Stego, .World_Dino_Roar_Dilo, .World_Dino_Roar_Giga,
		.World_Dino_Step_Small, .World_Dino_Step_Heavy, .World_Dino_Stomp, .World_Dino_Dismount, .Ui_Status_Bleed, .World_Bleed_Tick}) {
		if sounds.played[sfx] == 0 { fmt.eprintln("mechanics lab: no sound for the arsenal", sfx); return false }
	}
	fmt.eprintln("mechanics lab sounds:", heard)
	return true
}

// Plays `frames` frames with the clock running and saves every `every`th one
// as odin_pp_living_<name>_NN.png.
mechanics_lab_film :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, frames, every: int, name: string) {
	for frame in 0..<frames {
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
		if frame%every == 0 { artifacts.screenshot(fmt.ctprintf("odin_pp_living_%s_%02d.png", name, frame/every)) }
	}
}

// Commits one command, then plays a second and a quarter of real time and
// saves every second frame as odin_pp_living_<name>_NN.png.
mechanics_lab_capture :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, command: run_session.Gameplay_Command, name: string) -> bool {
	if !mechanics_lab_commit(window, renderer, room, controller, cards, buffer, command) { fmt.eprintln("mechanics lab: capture not committed:", name); return false }
	mechanics_lab_film(window, renderer, room, controller, cards, buffer, 76, 2, name)
	return true
}

// Commits one command once the player may act (the clock runs meanwhile).
mechanics_lab_commit :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, command: run_session.Gameplay_Command) -> bool {
	for _ in 0..<240 {
		if game.tactical_allows_action(room) && !render.renderer_blocks_player_input(renderer) { break }
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
	}
	return run_session.commit_gameplay_command(room, renderer, cards, command)
}
