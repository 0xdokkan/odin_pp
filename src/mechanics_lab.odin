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
// arena with no cover, a deck made only of the cards under test (one
// Movimento Ombra and one of each card of Phase 2: Pozza di Veleno, Incendio,
// Deflect, Feretro, Dado del Destino, Lama Velenosa) and enemies that never
// stop coming (game/sandbox.odin). It never touches the profile, gives no
// rewards and has no exit to walk to.
MECHANICS_LAB_WIDTH :: 23
MECHANICS_LAB_HEIGHT :: 17
MECHANICS_LAB_DECK :: [7]game.Card_Id{.Shadow_Step, .Poison_Pool, .Wildfire, .Deflect, .Coffin, .Fate_Dice, .Venom_Blade}
// The whole deck in hand: every card under test can be tried at once.
MECHANICS_LAB_RULES :: game.Deck_Rules{hand_size = len(MECHANICS_LAB_DECK), max_energy = 12, energy_regen_per_pulse = 3}
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

// With `dice`, a dice card's roll shows over the window as in the game.
mechanics_lab_smoke_frame :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^Tactical_Controller,
	cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command, dt: f32, clock := false, dice: ^render.Dice_Renderer = nil) {
	render.update_renderer_frame_timeline(renderer, dt)
	// The board clock runs only where a capture needs real time to pass.
	step_tactical_controller(controller, room, renderer, cards, buffer, dt if clock else 0, true, {focused = true})
	render.advance_sprite_assets(&renderer.sprite_assets, dt)
	render.update_tactical_view(renderer, room, {}, false, true)
	render.update_tactical_atmosphere(renderer, dt)
	overlay: app.Window_Overlay
	dice_state: Dice_Window_Overlay
	if cue, found := render.active_presentation_cue(&renderer.timeline); found && dice != nil && cue.started && cue.kind == .Dice_Rolled {
		dice_state = {renderer = dice, roll = cue.event.dice_roll, progress = render.presentation_cue_progress(cue),
			seed = dice_event_visual_seed(cue.event), card = cue.event.card_definition}
		update_window_dice_overlay(window, &dice_state)
		overlay = draw_window_dice_overlay
	}
	app.begin_canvas(window, render.RESIN_BACKGROUND)
	render.draw_tactical_world(renderer, room, 0)
	render.draw_tactical_status(renderer, room)
	render.draw_tactical_hand(renderer, room, 0, 0, 0, {})
	render.draw_tactical_hud(renderer, room, false, false)
	render.draw_mechanics_lab_banner(renderer, room, true)
	app.present(window, render.LETTERBOX_COLOR, overlay, &dice_state)
	// The sounds are counted, not played: the smoke runs without a device.
	render.play_lab_sounds(renderer, nil, 0)
}

// The sandbox in the real window: the lab's whole deck in hand, a square of
// coils around the arrivals, the last kill that keeps the combat going and the
// refill; then Movimento Ombra played, the shadow walked and the rise, every
// kind of blow, a slowed brute's seal, the pools and the fire and, last, the
// player's charges.
run_mechanics_lab_smoke :: proc(window: ^app.Window, renderer: ^render.Renderer, dice: ^render.Dice_Renderer) -> bool {
	data: level.Level
	defer level.destroy(&data)
	player, created := game.create_player({max_health = 22, attack = 2, defense = 0})
	if !created || !game.configure_tactical(&player, game.DEFAULT_TACTICAL_CONFIG) { return false }
	room, built := create_mechanics_lab_room(&data, &player, game.DEFAULT_TACTICAL_CONFIG)
	if !built { fmt.eprintln("mechanics lab: arena not built"); return false }
	defer game.destroy_room(&room)
	if player.deck.hand_count != len(MECHANICS_LAB_DECK) { fmt.eprintln("mechanics lab: not the whole deck in hand"); return false }
	for id in MECHANICS_LAB_DECK {
		if _, held := mechanics_lab_hand_card(&player, id); !held { fmt.eprintln("mechanics lab: no", id, "in hand"); return false }
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
	if !mechanics_lab_blows(window, renderer, &room, &controller, &cards, &buffer) { return false }
	if !mechanics_lab_slow(window, renderer, &room, &controller, &cards, &buffer) { return false }
	if !mechanics_lab_ground(window, renderer, &room, &controller, &cards, &buffer) { return false }
	if !mechanics_lab_charges(window, renderer, dice, &room, &controller, &cards, &buffer) { return false }
	return mechanics_lab_sounds_heard(renderer)
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
mechanics_lab_play :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^Tactical_Controller,
	cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command, card: game.Card_Id, target: game.Target) -> bool {
	mechanics_lab_wait_free(window, renderer, room, controller, cards, buffer)
	id, held := mechanics_lab_hand_card(room.player, card)
	room.player.deck.energy = room.player.deck.rules.max_energy
	return held && commit_gameplay_command(room, renderer, cards, {kind = .Play_Card, origin_phase = .Combat,
		card_id = id, target = target})
}

// Frames with the clock running until the player may play a card again.
mechanics_lab_wait_free :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^Tactical_Controller,
	cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command, dice: ^render.Dice_Renderer = nil) {
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
mechanics_lab_blows :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^Tactical_Controller,
	cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command) -> bool {
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
			if frame%2 == 0 { rl.TakeScreenshot(fmt.ctprintf("odin_pp_living_blow_%s_%02d.png", blow.name, frame/2)) }
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
mechanics_lab_statuses :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^Tactical_Controller,
	cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command) -> bool {
	if len(room.enemies) == 0 { fmt.eprintln("mechanics lab: no foe for the statuses"); return false }
	foe := game.enemy_entity(room.enemies[0].id)
	for enemy in room.enemies { if enemy.archetype == .Brute { foe = game.enemy_entity(enemy.id) } }
	before := render.capture_room_presentation(room)
	game.clear_event_log(&room.recent_events)
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
	game.append_event_log(&room.recent_events, &marked.events)
	after := render.capture_room_presentation(room)
	if !render.begin_renderer_event_timeline(renderer, before, &room.recent_events, &after) { return false }
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
mechanics_lab_slow :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^Tactical_Controller,
	cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command) -> bool {
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
	game.clear_event_log(&room.recent_events)
	marks := game.make_action(.Trigger, game.SYSTEM_ENTITY)
	if !game.add_effect(&marks, game.apply_status_effect(foe, .Slow, SLOW, 0)) { return false }
	marked := game.resolve_action(room, &marks)
	if !marked.accepted || marked.statuses_applied != 1 { fmt.eprintln("mechanics lab: the slow was refused"); return false }
	game.append_event_log(&room.recent_events, &marked.events)
	after := render.capture_room_presentation(room)
	if !render.begin_renderer_event_timeline(renderer, before, &room.recent_events, &after) { return false }
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
// The flat board shows both too (odin_pp_mechanics_lab_pool_flat.png,
// odin_pp_mechanics_lab_fire_flat.png).
mechanics_lab_ground :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^Tactical_Controller,
	cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command) -> bool {
	player := room.player
	foe :: proc(room: ^game.Room, id: u32) -> ^game.Enemy {
		index, found := game.enemy_index_by_id(room, id)
		return &room.enemies[index] if found else nil
	}
	stacks :: proc(room: ^game.Room, id: u32, kind: game.Status_Kind) -> i32 {
		status, found := game.status_for_entity(room, game.enemy_entity(id), kind)
		return status.potency if found else 0
	}
	// Held where it stands: recovering, its next intent planned afresh.
	hold :: mechanics_lab_hold
	// The same frame on the flat board.
	flat :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^Tactical_Controller,
		cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command, name: cstring) {
		renderer.tactical.scene_3d = false
		for _ in 0..<3 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 0) }
		rl.TakeScreenshot(name)
		renderer.tactical.scene_3d = true
		for _ in 0..<2 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 0) }
	}
	pour :: proc(room: ^game.Room, kind: game.Status_Kind, cell: grid.Position) -> bool {
		action := game.make_action(.Card, game.PLAYER_ENTITY, game.cell_target(cell), .Walkable_Cell)
		return game.add_effect(&action, game.place_ground_effect(cell, kind, 2)) && game.resolve_action(room, &action).accepted
	}
	// The lane's own play, once the player may act.
	play :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^Tactical_Controller,
		cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command, card: game.Card_Id, cell: grid.Position) -> bool {
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
	center := grid.Position{MECHANICS_LAB_WIDTH/2, MECHANICS_LAB_HEIGHT/2}
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
		render.draw_mechanics_lab_banner(renderer, room, true)
		app.present(window, render.LETTERBOX_COLOR)
	}
	rl.TakeScreenshot("odin_pp_mechanics_lab_pool_preview.png")
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
	flat(window, renderer, room, controller, cards, buffer, "odin_pp_mechanics_lab_pool_flat.png")
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
			rl.TakeScreenshot("odin_pp_mechanics_lab_fire.png")
			flat(window, renderer, room, controller, cards, buffer, "odin_pp_mechanics_lab_fire_flat.png")
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
// (odin_pp_living_fate_lethal_NN.png) but is only a critical on the Custodian, a
// miniboss (odin_pp_living_fate_boss_NN.png). LAMA VELENOSA: its die rolled as it
// is played (odin_pp_mechanics_lab_venom_roll.png), the bumps it poisons after
// (odin_pp_living_venom_NN.png).
mechanics_lab_charges :: proc(window: ^app.Window, renderer: ^render.Renderer, dice: ^render.Dice_Renderer, room: ^game.Room,
	controller: ^Tactical_Controller, cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command) -> bool {
	player := room.player
	center := grid.Position{MECHANICS_LAB_WIDTH/2, MECHANICS_LAB_HEIGHT/2}
	foe :: proc(room: ^game.Room, id: u32) -> ^game.Enemy {
		index, found := game.enemy_index_by_id(room, id)
		return &room.enemies[index] if found else nil
	}
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
	// The four cards in hand, each under the mouse: its inspector's lines
	// (odin_pp_mechanics_lab_card_<Card>.png).
	for card in ([4]game.Card_Id{.Deflect, .Coffin, .Fate_Dice, .Venom_Blade}) {
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
			if frame%2 == 0 { rl.TakeScreenshot(fmt.ctprintf("odin_pp_living_%s_%02d.png", blow.name, frame/2)) }
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
	renderer.tactical.arrow_aim = arrows_aiming_at(room, true)
	renderer.has_hovered_cell, renderer.hovered_cell = true, foe(room, covered_id).position
	_, covered_shot, covered_taken := arrow_shot_command(room, renderer, renderer.tactical.arrow_aim, true)
	if !covered_taken || covered_shot { fmt.eprintln("mechanics lab: the click on the covered foe was not swallowed"); return false }
	// The mouse on the foe in reach: the board marks it alone, a click looses.
	renderer.hovered_cell = foe(room, target_id).position
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_arrow_aim.png")
	shot, has_shot, taken := arrow_shot_command(room, renderer, renderer.tactical.arrow_aim, true)
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
	fate_bump :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^Tactical_Controller,
		cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command, sides, face: i32) -> bool {
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
	// LAMA VELENOSA, from the hand: its roll over the window, then a bump.
	if !reset(room, center) { return false }
	venom_id, venom_placed := game.spawn_enemy(room, {position = {center.x, center.y-1}, health = 60, attack = 1, archetype = .Chaser})
	if !venom_placed { fmt.eprintln("mechanics lab: no room for the venom's foe"); return false }
	mechanics_lab_hold(room, venom_id)
	mechanics_lab_wait_free(window, renderer, room, controller, cards, buffer)
	forced, found := mechanics_lab_dice_for_face(3, 4)
	if !found { return false }
	player.dice = forced
	if !mechanics_lab_play(window, renderer, room, controller, cards, buffer, .Venom_Blade, self) {
		fmt.eprintln("mechanics lab: Lama Velenosa was not played"); return false
	}
	rolled := false
	for _ in 0..<300 {
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true, dice)
		cue, showing := render.active_presentation_cue(&renderer.timeline)
		if showing && cue.kind == .Dice_Rolled && render.presentation_cue_progress(cue) > 0.86 && !rolled {
			rl.TakeScreenshot("odin_pp_mechanics_lab_venom_roll.png")
			rolled = true
		}
		if !render.renderer_blocks_player_input(renderer) { break }
	}
	if !rolled || game.player_charges(room, .Venom_Blade) != 3 { fmt.eprintln("mechanics lab: Lama Velenosa rolled no 3"); return false }
	// The loaded bump: its 2 and Veleno 2, one charge spent (the Veleno bites
	// the foe's own next action, in the film).
	if !mechanics_lab_commit(window, renderer, room, controller, cards, buffer, {kind = .Move, origin_phase = .Combat, direction = .North}) {
		fmt.eprintln("mechanics lab: the loaded bump was not taken"); return false
	}
	venomed := foe(room, venom_id)
	if venomed == nil || venomed.health != 58 || stacks(room, venom_id, .Poison) != game.VENOM_BLADE_POISON || game.player_charges(room, .Venom_Blade) != 2 {
		fmt.eprintln("mechanics lab: the loaded bump left Veleno", stacks(room, venom_id, .Poison), "and", game.player_charges(room, .Venom_Blade), "charges"); return false
	}
	mechanics_lab_film(window, renderer, room, controller, cards, buffer, 76, 2, "venom")
	fmt.eprintf("mechanics lab charges: deflected a bolt, a cleave and a charge, an arrow (none through cover), three fated bumps " +
		"(Bruciatura 2, lethal, critical on the Custodian), Lama %d left\n", game.player_charges(room, .Venom_Blade))
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
		render.draw_mechanics_lab_banner(renderer, room, true)
		app.present(window, render.LETTERBOX_COLOR)
	}
	rl.TakeScreenshot(name)
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
		render.draw_mechanics_lab_banner(renderer, room, true)
		app.present(window, render.LETTERBOX_COLOR)
	}
	rl.TakeScreenshot(name)
	renderer.has_hovered_cell = false
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
	shadow_card, held := mechanics_lab_hand_card(player, .Shadow_Step)
	if !held || !commit_gameplay_command(room, renderer, cards, {kind = .Play_Card, origin_phase = .Combat,
		card_id = shadow_card, target = game.entity_target(game.PLAYER_ENTITY)}) || !game.tactical_shadow_active(room) {
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
	for card in ([4]game.Card_Id{.Deflect, .Coffin, .Fate_Dice, .Venom_Blade}) {
		sfx, _ := render.lab_card_sfx(card)
		if sounds.played[sfx] == 0 { fmt.eprintln("mechanics lab: no sound for the card", card, sfx); return false }
	}
	for kind in ([4]game.Status_Kind{.Deflect, .Arrows, .Fate, .Venom_Blade}) {
		sfx, _ := render.lab_status_sfx(kind)
		if sounds.played[sfx] == 0 { fmt.eprintln("mechanics lab: no sound for the charge", kind, sfx); return false }
	}
	// What they do: a blow turned back, an arrow loosed, a die at a bump.
	for sfx in ([?]audio.Lab_Sfx{.Pilgrim_Deflect, .Pilgrim_Shoot, .Ui_Fate_Die}) {
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
	if !mechanics_lab_commit(window, renderer, room, controller, cards, buffer, command) { fmt.eprintln("mechanics lab: capture not committed:", name); return false }
	mechanics_lab_film(window, renderer, room, controller, cards, buffer, 76, 2, name)
	return true
}

// Commits one command once the player may act (the clock runs meanwhile).
mechanics_lab_commit :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^Tactical_Controller,
	cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command, command: Gameplay_Command) -> bool {
	for _ in 0..<240 {
		if game.tactical_allows_action(room) && !render.renderer_blocks_player_input(renderer) { break }
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
	}
	return commit_gameplay_command(room, renderer, cards, command)
}
