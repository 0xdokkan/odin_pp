package devtools
import artifacts "artifacts"
import run_session "../run"

import "core:fmt"
import "core:math"
import app "../engine/app"
import game "../game"
import level "../level"
import render "../render"

// THE FIRST PERSON ARENA (run.Mechanics_Lab_Arena.First_Person, F3; docs/piano-prima-persona.md, Fase 1) in
// PROVA MECCANICHE's smoke, last of its acts: the arena from the board's camera, its pillars, niches, slanted walls,
// low covers, corridor and rise, the archer up on it and the brute, its deck's First Person Shooter in hand
// (odin_pp_mechanics_lab_prima_persona.png). The card played: behind his eyes the AK, looking north at the archer on
// the rise (odin_pp_mechanics_lab_prima_persona_ak.png), a second of the trigger, then east at the slanted wall
// (odin_pp_mechanics_lab_prima_persona_sponda.png); the camera rises. Then First Person Brawler (Fase 2) from the hand,
// its words and inspector (odin_pp_mechanics_lab_card_First_Person_Brawler.png): behind his eyes the two gloves, FPB
// in the plate and the fists' line (odin_pp_mechanics_lab_prima_persona_pugni.png); W held runs him free up to the
// brute, set in his way; a jab and a left hook thrown with the buttons, each glove caught on its way
// (odin_pp_mechanics_lab_prima_persona_pugni_jab.png, _gancio.png), each its damage; a mark lit on the brute's card
// for the cross (odin_pp_mechanics_lab_prima_persona_pugni_segno.png), the cross with the crosshair over it a
// critical. Then each weapon whose card is still to come, taken up by the lab alone (no card of theirs yet): its tag
// in the plate, the bare line, an empty hand, both buttons held for a second firing nothing
// (odin_pp_mechanics_lab_prima_persona_<spada|arco>.png). Its foes are held, so every run sees the same.
mechanics_lab_prima_persona :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, data: ^level.Level,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	fp := &renderer.tactical.first_person
	frame :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
		cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, fire := false) {
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true, nil, {focused = true, fire = fire, fire_right = fire})
	}
	// A frame with the given keys (the fists' movement keys, buttons and Shift).
	drive :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
		cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, input: run_session.Tactical_Controller_Input) {
		given := input
		given.focused = true
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true, nil, given)
	}
	// Frames until the camera is all the way in his eyes, or all the way back out.
	settle :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
		cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, inside: bool) -> bool {
		for _ in 0..<240 {
			amount := render.first_person_amount(renderer)
			if (inside && amount >= 1 || !inside && amount <= 0) && !render.renderer_blocks_player_input(renderer) { return true }
			frame(window, renderer, room, controller, cards, buffer)
		}
		return false
	}
	// The view over: its seconds run out and the camera rises.
	leave :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
		cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
		room.first_person.remaining = 0.01
		frame(window, renderer, room, controller, cards, buffer)
		return !game.tactical_first_person_active(room) && settle(window, renderer, room, controller, cards, buffer, false)
	}
	game.destroy_room(room)
	player.health = player.stats.max_health
	rebuilt, built := run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG, .First_Person)
	if !built { fmt.eprintln("mechanics lab: the first person arena was not built"); return false }
	room^ = rebuilt
	render.clear_event_animations(renderer)
	controller^ = {was_focused = true}
	for foe in room.enemies { mechanics_lab_hold(room, foe.id) }
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	card, brawler := u32(0), u32(0)
	for held in player.deck.hand[:player.deck.hand_count] {
		if held.definition_id == .First_Person { card = held.id }
		if held.definition_id == .First_Person_Brawler { brawler = held.id }
	}
	if len(room.obstacles) != len(run_session.MECHANICS_LAB_FIRST_PERSON_COVERS) || player.deck.hand_count != 2 || card == 0 || brawler == 0 {
		fmt.eprintln("mechanics lab: the first person arena is not the one drawn, or its deck is not its own"); return false
	}
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_prima_persona.png")

	// The AK from the hand: north at the archer up on the rise, a second of the trigger, east at the slanted wall.
	for _ in 0..<600 {
		if game.tactical_allows_cards(room) && !render.renderer_blocks_player_input(renderer) && !game.tactical_player_busy(room) { break }
		frame(window, renderer, room, controller, cards, buffer)
	}
	player.deck.energy = player.deck.rules.max_energy
	if !run_session.commit_gameplay_command(room, renderer, cards, {kind = .Play_Card, origin_phase = .Combat, card_id = card,
		target = game.entity_target(game.PLAYER_ENTITY)}) || room.first_person.weapon != .AK {
		fmt.eprintln("mechanics lab: the arena's First Person Shooter was not played"); return false
	}
	if !settle(window, renderer, room, controller, cards, buffer, true) { fmt.eprintln("mechanics lab: no dive in the first person arena"); return false }
	fp.yaw, fp.pitch = -math.PI/2, 0.12
	for _ in 0..<3 { frame(window, renderer, room, controller, cards, buffer) }
	artifacts.screenshot("odin_pp_mechanics_lab_prima_persona_ak.png")
	shots := room.first_person.shots
	for _ in 0..<60 { frame(window, renderer, room, controller, cards, buffer, fire = true) }
	for _ in 0..<20 { frame(window, renderer, room, controller, cards, buffer) }
	if room.first_person.shots <= shots { fmt.eprintln("mechanics lab: the AK did not fire in the first person arena"); return false }
	ak_shots := room.first_person.shots-shots
	// East-north-east: the slanted wall of the east side, (18,6) to (20,8).
	fp.yaw, fp.pitch = -0.15, 0
	for _ in 0..<3 { frame(window, renderer, room, controller, cards, buffer) }
	artifacts.screenshot("odin_pp_mechanics_lab_prima_persona_sponda.png")
	if !leave(window, renderer, room, controller, cards, buffer) { fmt.eprintln("mechanics lab: the AK's view did not end"); return false }

	// FIRST PERSON BRAWLER from the hand: its words on the hand's own cards and in the inspector, at every level.
	brawler_definition, _ := game.card_definition_by_id(.First_Person_Brawler)
	width := render.tactical_hand_card_bounds(renderer, 0, player.deck.hand_count).width
	for upgrade in i32(0)..=game.FIRST_PERSON_MAX_UPGRADE_LEVEL {
		if misfit := render.tactical_card_text_misfit(renderer, {id = 1, definition_id = .First_Person_Brawler, upgrade_level = upgrade},
			brawler_definition, width); misfit != "" {
			fmt.eprintf("mechanics lab: First Person Brawler +%d on a %.0f px card: %s\n", upgrade, width, misfit); return false
		}
	}
	mechanics_lab_still(window, renderer, room, brawler, "odin_pp_mechanics_lab_card_First_Person_Brawler.png")
	// The brute set in his way, east along his row.
	brute_index := -1
	for foe, index in room.enemies { if foe.archetype == .Brute { brute_index = index } }
	if brute_index < 0 { fmt.eprintln("mechanics lab: no brute in the first person arena"); return false }
	room.enemies[brute_index].position = {x = 16, y = 8}
	room.enemies[brute_index].health, room.enemies[brute_index].max_health = 60, 60
	brute := room.enemies[brute_index].id
	render.clear_event_animations(renderer)
	for _ in 0..<600 {
		if game.tactical_allows_cards(room) && !render.renderer_blocks_player_input(renderer) && !game.tactical_player_busy(room) { break }
		frame(window, renderer, room, controller, cards, buffer)
	}
	player.deck.energy = player.deck.rules.max_energy
	if !run_session.commit_gameplay_command(room, renderer, cards, {kind = .Play_Card, origin_phase = .Combat, card_id = brawler,
		target = game.entity_target(game.PLAYER_ENTITY)}) || room.first_person.weapon != .Fists {
		fmt.eprintln("mechanics lab: the arena's First Person Brawler was not played"); return false
	}
	if !settle(window, renderer, room, controller, cards, buffer, true) { fmt.eprintln("mechanics lab: no dive with the fists"); return false }
	fp.yaw, fp.pitch = 0, 0
	for _ in 0..<3 { frame(window, renderer, room, controller, cards, buffer) }
	if render.first_person_hud_status(renderer) != render.FIRST_PERSON_HUD_STATUS_FISTS || string(render.first_person_countdown_text(20, .Fists)) != "FPB 20s" {
		fmt.eprintln("mechanics lab: the fists' words are not shown"); return false
	}
	artifacts.screenshot("odin_pp_mechanics_lab_prima_persona_pugni.png")
	// The cybernetic proposals (Fase 3, passo 1): the same guard in each style.
	styles := [3]struct{style: render.First_Person_Glove_Style, name: cstring}{
		{.Cyber, "odin_pp_mechanics_lab_prima_persona_stile_cyber.png"},
		{.Neon, "odin_pp_mechanics_lab_prima_persona_stile_neon.png"},
		{.Circuits, "odin_pp_mechanics_lab_prima_persona_stile_circuiti.png"},
	}
	for proposal in styles {
		render.first_person_glove_style = proposal.style
		frame(window, renderer, room, controller, cards, buffer)
		artifacts.screenshot(proposal.name)
	}
	render.first_person_glove_style = .Leather_Gold
	frame(window, renderer, room, controller, cards, buffer)
	// W held: free up to the brute.
	run := run_session.Tactical_Controller_Input{}
	run.walk[0] = true
	body := &room.first_person.fists.body
	for _ in 0..<120 {
		drive(window, renderer, room, controller, cards, buffer, run)
		if body.x >= 15.6 { break }
	}
	for _ in 0..<20 { frame(window, renderer, room, controller, cards, buffer) }
	if body.x < 15.6 || room.player.position != {x = 15, y = 8} { fmt.eprintln("mechanics lab: the fists did not run up to the brute:", body^); return false }
	// The marks dark for the straight blows.
	dark :: proc(room: ^game.Room) { for &mark in room.first_person.fists.marks { mark.lit, mark.wait = 0, 1000 } }
	// A jab and a left hook, each glove caught on its way out.
	blows := [2]struct{punch: game.First_Person_Punch, name: cstring}{{.Jab, "odin_pp_mechanics_lab_prima_persona_pugni_jab.png"},
		{.Left_Hook, "odin_pp_mechanics_lab_prima_persona_pugni_gancio.png"}}
	for blow in blows {
		dark(room)
		health := room.enemies[brute_index].health
		press := run_session.Tactical_Controller_Input{fire = true, shift = blow.punch == .Left_Hook}
		for index in 0..<6 {
			drive(window, renderer, room, controller, cards, buffer, press)
			dark(room)
			if index == 4 { artifacts.screenshot(blow.name) }
		}
		for _ in 0..<40 { frame(window, renderer, room, controller, cards, buffer); dark(room) }
		if lost := health-room.enemies[brute_index].health; lost != game.FISTS_PUNCHES[blow.punch].damage {
			fmt.eprintln("mechanics lab: the", blow.punch, "took", lost, "from the brute"); return false
		}
	}
	// A mark lit on the brute's card for the cross; the cross on the brute, wherever the crosshair is on it, a critical.
	lit := false
	for &mark in room.first_person.fists.marks {
		if mark.enemy_id != brute { continue }
		mark.zone, mark.lit, mark.wait = 2, 1.2, 0
		lit = true
	}
	if !lit { fmt.eprintln("mechanics lab: no mark watches the brute"); return false }
	for _ in 0..<3 { frame(window, renderer, room, controller, cards, buffer) }
	artifacts.screenshot("odin_pp_mechanics_lab_prima_persona_pugni_segno.png")
	health := room.enemies[brute_index].health
	cross := run_session.Tactical_Controller_Input{fire_right = true}
	for _ in 0..<4 { drive(window, renderer, room, controller, cards, buffer, cross) }
	for _ in 0..<40 { frame(window, renderer, room, controller, cards, buffer) }
	if lost := health-room.enemies[brute_index].health; lost != game.FISTS_PUNCHES[.Cross].damage*game.FISTS_CRITICAL_FACTOR ||
	   room.first_person.fists.crits != 1 {
		fmt.eprintln("mechanics lab: the cross on its mark took", lost, "and made", room.first_person.fists.crits, "criticals"); return false
	}
	if !leave(window, renderer, room, controller, cards, buffer) { fmt.eprintln("mechanics lab: the fists' view did not end"); return false }

	// The weapons still to come: the lab takes each up; its tag, the bare line, an empty hand, no shot.
	names := [game.First_Person_Weapon]string{.AK = "ak", .Fists = "pugni", .Sword = "spada", .Bow = "arco"}
	for weapon in game.First_Person_Weapon {
		if weapon == .AK || weapon == .Fists { continue }
		if !game.tactical_begin_first_person(room, 20, weapon) { fmt.eprintln("mechanics lab: the", weapon, "was not taken up"); return false }
		if !settle(window, renderer, room, controller, cards, buffer, true) { fmt.eprintln("mechanics lab: no dive with the", weapon); return false }
		shots = room.first_person.shots
		for _ in 0..<60 { frame(window, renderer, room, controller, cards, buffer, fire = true) }
		if room.first_person.shots != shots || room.first_person.trigger || render.first_person_shown_weapon(renderer) != weapon ||
		   render.first_person_hud_status(renderer) != render.FIRST_PERSON_HUD_STATUS_BARE ||
		   string(render.first_person_countdown_text(20, weapon)) != fmt.tprintf("%s 20s", render.FIRST_PERSON_LOOKS[weapon].tag) {
			fmt.eprintln("mechanics lab: the", weapon, "is not shown as its own, or it fired"); return false
		}
		fp.yaw, fp.pitch = -math.PI/2, 0.12
		for _ in 0..<3 { frame(window, renderer, room, controller, cards, buffer) }
		artifacts.screenshot(fmt.ctprintf("odin_pp_mechanics_lab_prima_persona_%s.png", names[weapon]))
		if !leave(window, renderer, room, controller, cards, buffer) { fmt.eprintln("mechanics lab: the", weapon, "view did not end"); return false }
	}

	// The fight back, as F5 brings it, for whatever comes after.
	game.destroy_room(room)
	player.health = player.stats.max_health
	rebuilt, built = run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG)
	if !built { fmt.eprintln("mechanics lab: the arena was not rebuilt after the first person arena"); return false }
	room^ = rebuilt
	render.clear_event_animations(renderer)
	controller^ = {was_focused = true}
	for _ in 0..<12 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	fmt.eprintf("mechanics lab first person arena: %d shots of the AK in a second; the fists ran up to the brute, a jab, a hook " +
		"and a critical cross on its mark; %v and %v shown with an empty hand and fired nothing\n",
		ak_shots, game.First_Person_Weapon.Sword, game.First_Person_Weapon.Bow)
	return true
}
