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
// (odin_pp_mechanics_lab_prima_persona_sponda.png); the camera rises. Then each weapon whose card is still to come,
// taken up by the lab alone (no card of theirs yet): its tag in the plate, the bare line, an empty hand, both
// buttons held for a second firing nothing (odin_pp_mechanics_lab_prima_persona_<pugni|spada|arco>.png). Its foes
// are held, so every run sees the same.
mechanics_lab_prima_persona :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, data: ^level.Level,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	fp := &renderer.tactical.first_person
	frame :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
		cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, fire := false) {
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true, nil, {focused = true, fire = fire, fire_right = fire})
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
	if len(room.obstacles) != len(run_session.MECHANICS_LAB_FIRST_PERSON_COVERS) || player.deck.hand_count != 1 ||
	   player.deck.hand[0].definition_id != .First_Person {
		fmt.eprintln("mechanics lab: the first person arena is not the one drawn, or its deck is not its own"); return false
	}
	card := player.deck.hand[0].id
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

	// The weapons still to come: the lab takes each up; its tag, the bare line, an empty hand, no shot.
	names := [game.First_Person_Weapon]string{.AK = "ak", .Fists = "pugni", .Sword = "spada", .Bow = "arco"}
	for weapon in game.First_Person_Weapon {
		if weapon == .AK { continue }
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
	fmt.eprintf("mechanics lab first person arena: %d shots of the AK in a second; %v, %v and %v shown with an empty hand and fired nothing\n",
		ak_shots, game.First_Person_Weapon.Fists, game.First_Person_Weapon.Sword, game.First_Person_Weapon.Bow)
	return true
}
