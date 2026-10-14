package main

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"
import app "app"
import audio "engine/audio"
import gfx "engine/gfx"
import game "game"
import grid "grid"
import level "level"
import render "render"

// PROVA MECCANICHE: a sandbox for trying mechanics one at a time. A large
// arena with no cover, a deck made only of the cards under test (for now
// Movimento Ombra) and enemies that never stop coming (game/sandbox.odin). It
// never touches the profile, gives no rewards and has no exit to walk to.
MECHANICS_LAB_WIDTH :: 23
MECHANICS_LAB_HEIGHT :: 17
MECHANICS_LAB_DECK :: [8]game.Card_Id{.Shadow_Step, .Shadow_Step, .Shadow_Step, .Shadow_Step, .Shadow_Step, .Shadow_Step, .Shadow_Step, .Shadow_Step}
MECHANICS_LAB_RULES :: game.Deck_Rules{hand_size = 5, max_energy = 12, energy_regen_per_pulse = 3}
MECHANICS_LAB_DECK_SEED :: u64(0x7E57_1AB)

// The open arena: walls only around the edge, the player in the middle and
// the (unused) exit tucked into a corner.
mechanics_lab_level :: proc() -> (level.Level, bool) {
	rows: [MECHANICS_LAB_HEIGHT]string
	for y in 0..<MECHANICS_LAB_HEIGHT {
		row := strings.builder_make(context.temp_allocator)
		for x in 0..<MECHANICS_LAB_WIDTH {
			switch {
			case x == 0 || y == 0 || x == MECHANICS_LAB_WIDTH-1 || y == MECHANICS_LAB_HEIGHT-1: strings.write_byte(&row, '#')
			case x == MECHANICS_LAB_WIDTH/2 && y == MECHANICS_LAB_HEIGHT/2: strings.write_byte(&row, '@')
			case x == MECHANICS_LAB_WIDTH-2 && y == MECHANICS_LAB_HEIGHT-2: strings.write_byte(&row, '>')
			case: strings.write_byte(&row, '.')
			}
		}
		rows[y] = strings.to_string(row)
	}
	data, error, _ := level.from_ascii(rows[:])
	return data, error == .None
}

// Replaces `data` with the arena and builds its endless room around `player`.
create_mechanics_lab_room :: proc(data: ^level.Level, player: ^game.Player, config: game.Tactical_Config) -> (room: game.Room, ok: bool) {
	arena, built := mechanics_lab_level()
	if !built { return }
	game.finish_deck_combat(&player.deck)
	if !game.initialize_empty_deck(&player.deck, MECHANICS_LAB_RULES, MECHANICS_LAB_DECK_SEED) { level.destroy(&arena); return }
	for id in MECHANICS_LAB_DECK {
		if _, added := game.add_owned_card(&player.deck, id); !added { level.destroy(&arena); return }
	}
	level.destroy(data)
	data^ = arena
	player.floor_secrets = {}
	// Three first arrivals, well away from the middle.
	spawns := [?]game.Enemy_Spawn{
		{position = {4, 4}, health = 12, attack = 2, archetype = .Chaser},
		{position = {MECHANICS_LAB_WIDTH-5, 4}, health = 10, attack = 2, archetype = .Archer},
		{position = {MECHANICS_LAB_WIDTH/2, MECHANICS_LAB_HEIGHT-4}, health = 18, attack = 3, archetype = .Brute},
	}
	room, ok = game.create_room(data, player, {enemies = spawns[:]})
	if !ok { return }
	room.endless = true
	// No fog: every arrival is in plain sight. Each action lasts its cost in
	// real time, so its animation has room to play.
	lab := config
	lab.enabled = true
	lab.vision_size = 0
	lab.timed_actions = true
	if !game.configure_tactical_room(&room, lab) { game.destroy_room(&room); return {}, false }
	return room, true
}

prepare_mechanics_lab :: proc(rs: ^Roguelike_Session) -> bool {
	if rs.room_created {
		game.destroy_room(&rs.room)
		rs.room_created = false
	}
	room, ok := create_mechanics_lab_room(&rs.level_data, &rs.run_state.player, rs.options.tactical)
	if !ok { return false }
	rs.room = room
	rs.room_created = true
	rs.sandbox = game.begin_sandbox(rs.run_seed)
	return true
}

mechanics_lab_smoke_frame :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^Tactical_Controller,
	cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command, dt: f32, clock := false) {
	render.update_renderer_frame_timeline(renderer, dt)
	// The board clock runs only where a capture needs real time to pass.
	step_tactical_controller(controller, room, renderer, cards, buffer, dt if clock else 0, true, {focused = true})
	render.advance_sprite_assets(&renderer.sprite_assets, dt)
	render.update_tactical_view(renderer, room, {}, false, true)
	render.update_tactical_atmosphere(renderer, dt)
	app.begin_canvas(window, render.RESIN_BACKGROUND)
	render.draw_tactical_world(renderer, room, 0)
	render.draw_tactical_status(renderer, room)
	render.draw_tactical_hand(renderer, room, 0, 0, 0, {})
	render.draw_tactical_hud(renderer, room, false, false)
	render.draw_mechanics_lab_banner(renderer, room, true)
	app.present(window, render.LETTERBOX_COLOR)
	// The sounds are counted, not played: the smoke runs without a device.
	render.play_lab_sounds(renderer, nil, 0)
}

// The sandbox in the real window: a hand of Movimento Ombra, a square of coils
// around the arrivals, the last kill that keeps the combat going and the refill;
// last, one of those cards played, the shadow walked and the rise.
run_mechanics_lab_smoke :: proc(window: ^app.Window, renderer: ^render.Renderer, dice: ^render.Dice_Renderer) -> bool {
	data: level.Level
	defer level.destroy(&data)
	player, created := game.create_player({max_health = 22, attack = 2, defense = 0})
	if !created || !game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG) { return false }
	room, built := create_mechanics_lab_room(&data, &player, game.DEFAULT_TACTICAL_CONFIG)
	if !built { fmt.eprintln("mechanics lab: arena not built"); return false }
	defer game.destroy_room(&room)
	for card in player.deck.hand[:player.deck.hand_count] {
		if card.definition_id != .Shadow_Step { fmt.eprintln("mechanics lab: a card other than Movimento Ombra"); return false }
	}
	render.clear_event_animations(renderer)
	render.reset_tactical_orbit(&renderer.tactical.world_orbit)
	render.frame_level(renderer, &data)
	render.set_living_cards(renderer, true)
	defer render.set_living_cards(renderer, false)
	render.set_mechanics_lab(renderer, true)
	defer render.set_mechanics_lab(renderer, false)
	controller := Tactical_Controller{was_focused = true}
	cards: Card_Interaction_State
	buffer: Buffered_Gameplay_Command
	sandbox := game.begin_sandbox(7)
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, &room, &controller, &cards, &buffer, 1.0/60.0) }
	rl.TakeScreenshot("odin_pp_mechanics_lab.png")
	// A square of coils around an arrival offers the ring, every time.
	log: game.Event_Log
	center := grid.Position{MECHANICS_LAB_WIDTH/2, MECHANICS_LAB_HEIGHT/2}
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
	rl.TakeScreenshot("odin_pp_mechanics_lab_square.png")
	// Arrivals fill the arena up to its maximum.
	for _ in 0..<600 {
		if len(room.enemies) >= game.SANDBOX_MAX_ENEMIES { break }
		_, _ = game.sandbox_tick(&room, &sandbox, 0.5)
	}
	if len(room.enemies) != game.SANDBOX_MAX_ENEMIES { fmt.eprintf("mechanics lab: %d enemies\n", len(room.enemies)); return false }
	render.clear_event_animations(renderer)
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, &room, &controller, &cards, &buffer, 1.0/60.0) }
	rl.TakeScreenshot("odin_pp_mechanics_lab_full.png")
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
	rl.TakeScreenshot("odin_pp_mechanics_lab_refill.png")
	// Death, then a restart: the player's standee must come back.
	player.health = 1
	before := render.capture_room_presentation(&room)
	game.clear_event_log(&room.recent_events)
	blow := game.make_action(.Attack, game.enemy_entity(room.enemies[0].id))
	if !game.add_effect(&blow, game.damage_effect(game.PLAYER_ENTITY, 50)) { return false }
	report := game.resolve_action(&room, &blow)
	if !report.accepted || room.phase != .Defeat { fmt.eprintln("mechanics lab: the player did not fall"); return false }
	game.append_event_log(&room.recent_events, &report.events)
	after := render.capture_room_presentation(&room)
	if !render.begin_renderer_event_timeline(renderer, before, &room.recent_events, &after) { return false }
	for _ in 0..<240 { mechanics_lab_smoke_frame(window, renderer, &room, &controller, &cards, &buffer, 1.0/60.0) }
	game.destroy_room(&room)
	player.health = player.stats.max_health
	room, built = create_mechanics_lab_room(&data, &player, game.DEFAULT_TACTICAL_CONFIG)
	if !built { return false }
	render.frame_level(renderer, &data)
	render.clear_event_animations(renderer)
	for _ in 0..<30 { mechanics_lab_smoke_frame(window, renderer, &room, &controller, &cards, &buffer, 1.0/60.0) }
	rl.TakeScreenshot("odin_pp_mechanics_lab_restart.png")
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
	// One instant with a blow about to land, under the new display and the old
	// one: the same frame twice, for a look at what the edge of the eye keeps.
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
		rl.TakeScreenshot("odin_pp_living_intent_both.png" if mode == .Both else "odin_pp_living_intent_labels.png")
	}
	renderer.tactical.intent_display = .Both
	// A cure: the green paper token. (Blows got red ones above.)
	player.health = max(1, player.health-3)
	cure_before := render.capture_room_presentation(&room)
	game.clear_event_log(&room.recent_events)
	cure := game.make_action(.Ability, game.PLAYER_ENTITY)
	if !game.add_effect(&cure, game.heal_effect(game.PLAYER_ENTITY, 3)) { return false }
	cured := game.resolve_action(&room, &cure)
	if !cured.accepted { fmt.eprintln("mechanics lab: the cure was refused"); return false }
	game.append_event_log(&room.recent_events, &cured.events)
	cure_after := render.capture_room_presentation(&room)
	if !render.begin_renderer_event_timeline(renderer, cure_before, &room.recent_events, &cure_after) { return false }
	mechanics_lab_film(window, renderer, &room, &controller, &cards, &buffer, 80, 2, "heal")
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
	rl.TakeScreenshot("odin_pp_mechanics_lab_stun.png")
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
		rl.TakeScreenshot("odin_pp_mechanics_lab_pause.png" if screen == 0 else "odin_pp_mechanics_lab_defeat.png")
	}
	renderer.tactical.pause_hovered, renderer.tactical.pause_menu = .None, false
	if !mechanics_lab_shadow(window, renderer, &room, &controller, &cards, &buffer) { return false }
	return mechanics_lab_sounds_heard(renderer)
}

// MOVIMENTO OMBRA from the hand, as the lane plays it, filmed every fourth
// frame as odin_pp_living_shadow_NN.png: the card sinks the player into his
// shadow, the shadow steps, takes a diagonal on its first beat and steps
// again while the world stands still, and when the four seconds are over he
// rises where it stopped. The window, the world's beats and every footstep
// wait for him; only the shadow's own sounds play.
mechanics_lab_shadow :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^Tactical_Controller,
	cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command) -> bool {
	player := room.player
	// From an open window, the stun above over and a second and a half into
	// it (the world's clock between two beats), nothing resolving or running.
	for _ in 0..<600 {
		if player.tactical.phase == .Decision && player.tactical.remaining <= f32(player.tactical.budget)-1.5 &&
		   game.tactical_can_begin_shadow(room) && !render.renderer_blocks_player_input(renderer) { break }
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
	}
	if room.phase != .Combat || player.tactical.phase != .Decision || !game.tactical_can_begin_shadow(room) {
		fmt.eprintln("mechanics lab: no open window for the shadow"); return false
	}
	sounds := renderer.tactical.lab_sounds
	if sounds == nil { fmt.eprintln("mechanics lab: no sounds before the shadow"); return false }
	heard := sounds.played
	left, clock, pulses, body := player.tactical.remaining, player.tactical.clock_fraction, room.pulse_count, player.position
	if player.deck.hand_count == 0 || player.deck.hand[0].definition_id != .Shadow_Step ||
	   !commit_gameplay_command(room, renderer, cards, {kind = .Play_Card, origin_phase = .Combat,
		card_id = player.deck.hand[0].id, target = game.entity_target(game.PLAYER_ENTITY)}) || !game.tactical_shadow_active(room) {
		fmt.eprintln("mechanics lab: Movimento Ombra was not played"); return false
	}
	frame := 0
	// The card and the sinking hold the shadow's four seconds.
	for _ in 0..<120 {
		if !render.renderer_blocks_player_input(renderer) { break }
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "shadow", 4, &frame)
	}
	if render.renderer_blocks_player_input(renderer) || player.tactical.shadow_remaining < game.TACTICAL_SHADOW_SECONDS-2.0/60.0 {
		fmt.eprintln("mechanics lab: the sinking ate the shadow's seconds"); return false
	}
	// Four steps, each as soon as the shadow's own lockout and its moment
	// allow: one straight away, the diagonal on the first beat, two more. The
	// first free way of each list is taken.
	Planned_Step :: struct {
		after: f32,
		beat: bool,
		ways: [4]grid.Position,
	}
	steps := [4]Planned_Step{
		{after = 0, ways = {{1, 0}, {0, 1}, {-1, 0}, {0, -1}}},
		{beat = true, ways = {{1, 1}, {1, -1}, {-1, 1}, {-1, -1}}},
		{after = 1.6, ways = {{0, 1}, {1, 0}, {-1, 0}, {0, -1}}},
		{after = 2.3, ways = {{1, 0}, {0, 1}, {0, -1}, {-1, 0}}},
	}
	shadow_cell := player.tactical.shadow_position
	for step, index in steps {
		for _ in 0..<240 {
			if !game.tactical_shadow_active(room) { break }
			if !render.renderer_blocks_player_input(renderer) && !game.tactical_player_busy(room) &&
			   game.tactical_shadow_elapsed(&player.tactical) >= step.after && (!step.beat || game.tactical_beat_target(room) != 0) { break }
			mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "shadow", 4, &frame)
		}
		if !game.tactical_shadow_active(room) { fmt.eprintln("mechanics lab: the shadow ended before step", index); return false }
		stepped := false
		for way in step.ways {
			// A diagonal is the lane's two keys on a beat: the first key's
			// direction, both keys' offset and the beat stamped at the press.
			command := Gameplay_Command{kind = .Move, origin_phase = .Combat}
			if step.beat {
				command.direction = .East if way.x > 0 else .West
				command.diagonal, command.beat = way, game.tactical_beat_target(room)
			} else {
				for direction in game.Move_Direction {
					if game.direction_offset(direction) == way { command.direction = direction }
				}
			}
			if commit_gameplay_command(room, renderer, cards, command) {
				stepped = player.tactical.shadow_position == game.add_position(shadow_cell, way)
				break
			}
		}
		if !stepped || player.position != body {
			fmt.eprintln("mechanics lab: shadow step", index, "not taken from", shadow_cell); return false
		}
		shadow_cell = player.tactical.shadow_position
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "shadow", 4, &frame)
	}
	// The rest of the four seconds, then the rise (the controller's own
	// command). Up to the rise the window and the world's clock stay where
	// they stopped; the body lands on the shadow's cell.
	risen := false
	rising: [audio.Lab_Sfx]int
	for _ in 0..<360 {
		if player.tactical.remaining != left || player.tactical.clock_fraction != clock || room.pulse_count != pulses {
			fmt.eprintf("mechanics lab: the world moved in the shadow (window %.3f -> %.3f s)\n", left, player.tactical.remaining); return false
		}
		if !game.tactical_shadow_active(room) { risen, rising = true, sounds.played; break }
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "shadow", 4, &frame)
	}
	if !risen || player.position != shadow_cell || shadow_cell == body {
		fmt.eprintln("mechanics lab: the player did not rise on the shadow's cell", shadow_cell, "but at", player.position); return false
	}
	// The card climbs out and the world's colours come back.
	for _ in 0..<120 {
		if !render.tactical_shadow_showing(renderer) && !render.renderer_blocks_player_input(renderer) && renderer.tactical.shadow.frozen <= 0 { break }
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "shadow", 4, &frame)
	}
	for _ in 0..<8 { mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "shadow", 4, &frame) }
	// The shadow's steps start no clip on the card: never the boots and the
	// card's scrape, nor a dodge for the diagonal; the rise is no walk either.
	// (Once risen the world's blows are back, and one that now misses him
	// rightly makes his card dodge.) Its own sounds all played.
	for sfx in ([?]audio.Lab_Sfx{.Pilgrim_Move_Side, .Pilgrim_Move_Up, .Pilgrim_Move_Down}) {
		if sounds.played[sfx] != heard[sfx] { fmt.eprintln("mechanics lab: a footstep in the shadow:", sfx); return false }
	}
	if rising[.Pilgrim_Dodge] != heard[.Pilgrim_Dodge] { fmt.eprintln("mechanics lab: a shadow step played the dodge"); return false }
	if sounds.played[.Card_Shadow_Step] != heard[.Card_Shadow_Step]+1 || sounds.played[.Pilgrim_Shadow_Sink] != heard[.Pilgrim_Shadow_Sink]+1 ||
	   sounds.played[.Pilgrim_Shadow_Step] != heard[.Pilgrim_Shadow_Step]+len(steps) ||
	   sounds.played[.Pilgrim_Shadow_Rise] != heard[.Pilgrim_Shadow_Rise]+1 || sounds.played[.Ui_Critical] <= heard[.Ui_Critical] ||
	   sounds.played[.Ui_Beat_Tick] < heard[.Ui_Beat_Tick]+game.TACTICAL_SHADOW_BEATS {
		fmt.eprintln("mechanics lab: the shadow's sounds did not all play"); return false
	}
	fmt.eprintf("mechanics lab shadow: %d steps, risen at %v from %v, window %.2f s kept, %d frames\n", len(steps), player.position, body, left, frame)
	return true
}

// One frame of a film with the clock running; every `every`th one is saved
// as odin_pp_living_<name>_NN.png.
mechanics_lab_reel_frame :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^Tactical_Controller,
	cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command, name: string, every: int, frame: ^int) {
	mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
	if frame^%every == 0 { rl.TakeScreenshot(fmt.ctprintf("odin_pp_living_%s_%02d.png", name, frame^/every)) }
	frame^ += 1
}

// The smoke's actions each sounded: steps, blows, hurts, the clock, the
// cure, the stun and the fall.
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
	fmt.eprintln("mechanics lab sounds:", heard)
	return true
}

// Plays `frames` frames with the clock running and saves every `every`th one
// as odin_pp_living_<name>_NN.png.
mechanics_lab_film :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^Tactical_Controller,
	cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command, frames, every: int, name: string) {
	for frame in 0..<frames {
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
		if frame%every == 0 { rl.TakeScreenshot(fmt.ctprintf("odin_pp_living_%s_%02d.png", name, frame/every)) }
	}
}

// Commits one command, then plays a second and a quarter of real time and
// saves every second frame as odin_pp_living_<name>_NN.png.
mechanics_lab_capture :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^Tactical_Controller,
	cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command, command: Gameplay_Command, name: string) -> bool {
	for _ in 0..<240 {
		if game.tactical_allows_action(room) && !render.renderer_blocks_player_input(renderer) { break }
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
	}
	if !commit_gameplay_command(room, renderer, cards, command) { fmt.eprintln("mechanics lab: capture not committed:", name); return false }
	for frame in 0..<76 {
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
		if frame%2 == 0 { rl.TakeScreenshot(fmt.ctprintf("odin_pp_living_%s_%02d.png", name, frame/2)) }
	}
	return true
}
