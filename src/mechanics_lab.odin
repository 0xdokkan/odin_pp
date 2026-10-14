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
// then one of those cards played, the shadow walked and the rise, every kind of
// blow and, last, a slowed brute's seal.
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
	return mechanics_lab_sounds_heard(renderer)
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

// Empties the arena for the next act: every foe falls with its own clip.
mechanics_lab_clear_arena :: proc(room: ^game.Room) -> bool {
	action := game.Action{kind = .Ability, source = game.PLAYER_ENTITY}
	for enemy in room.enemies {
		action.effects[action.effect_count] = {kind = .Damage, target = game.enemy_entity(enemy.id), amount = 1000}
		action.effect_count += 1
	}
	return action.effect_count == 0 || game.resolve_action(room, &action).accepted
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
