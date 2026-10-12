package main

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"
import app "app"
import gfx "engine/gfx"
import game "game"
import grid "grid"
import level "level"
import render "render"

// PROVA MECCANICHE: a sandbox for trying mechanics one at a time. A large
// arena with no cover, a deck made only of the cards under test (for now the
// Tesla coil) and enemies that never stop coming (game/sandbox.odin). It never
// touches the profile, gives no rewards and has no exit to walk to.
MECHANICS_LAB_WIDTH :: 23
MECHANICS_LAB_HEIGHT :: 17
MECHANICS_LAB_DECK :: [8]game.Card_Id{.Tesla_Coil, .Tesla_Coil, .Tesla_Coil, .Tesla_Coil, .Tesla_Coil, .Tesla_Coil, .Tesla_Coil, .Tesla_Coil}
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
	// No fog: every arrival is in plain sight.
	lab := config
	lab.enabled = true
	lab.vision_size = 0
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
	cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command, dt: f32) {
	render.update_renderer_frame_timeline(renderer, dt)
	step_tactical_controller(controller, room, renderer, cards, buffer, 0, true, {focused = true})
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
}

// The sandbox in the real window: a hand of Teslas, a square of coils around
// the arrivals, the last kill that keeps the combat going and the refill.
run_mechanics_lab_smoke :: proc(window: ^app.Window, renderer: ^render.Renderer, dice: ^render.Dice_Renderer) -> bool {
	data: level.Level
	defer level.destroy(&data)
	player, created := game.create_player({max_health = 22, attack = 2, defense = 0})
	if !created || !game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG) { return false }
	room, built := create_mechanics_lab_room(&data, &player, game.DEFAULT_TACTICAL_CONFIG)
	if !built { fmt.eprintln("mechanics lab: arena not built"); return false }
	defer game.destroy_room(&room)
	for card in player.deck.hand[:player.deck.hand_count] {
		if card.definition_id != .Tesla_Coil { fmt.eprintln("mechanics lab: a card other than Tesla"); return false }
	}
	render.clear_event_animations(renderer)
	render.reset_tactical_orbit(&renderer.tactical.world_orbit)
	render.frame_level(renderer, &data)
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
	standee := render.flipbook_find(renderer, game.PLAYER_ENTITY, gfx.Flipbook_Character.Pilgrim, {})
	if standee == nil || standee.action == .Death { fmt.eprintln("mechanics lab: the player's standee did not come back"); return false }
	return true
}
