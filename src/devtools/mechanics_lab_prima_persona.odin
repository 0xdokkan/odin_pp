package devtools
import artifacts "artifacts"
import run_session "../run"

import "core:fmt"
import "core:math"
import "core:os"
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
	card, brawler, fencer, archer := u32(0), u32(0), u32(0), u32(0)
	for held in player.deck.hand[:player.deck.hand_count] {
		if held.definition_id == .First_Person { card = held.id }
		if held.definition_id == .First_Person_Brawler { brawler = held.id }
		if held.definition_id == .First_Person_Fencer { fencer = held.id }
		if held.definition_id == .First_Person_Archer { archer = held.id }
	}
	if len(room.obstacles) != len(run_session.MECHANICS_LAB_FIRST_PERSON_COVERS) || player.deck.hand_count != 4 || card == 0 || brawler == 0 ||
	   fencer == 0 || archer == 0 {
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
	// ODIN_PP_LAB_TIMING=ak measures the AK here, in the same arena as the fists (Fase 3).
	if timing, _ := os.lookup_env("ODIN_PP_LAB_TIMING", context.temp_allocator); timing == "ak" {
		return mechanics_lab_first_person_timing(window, renderer, room, controller, cards, buffer)
	}
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
	// ODIN_PP_LAB_TIMING=1 measures the fists' view here instead of going on
	// (Fase 3, against the AK's of Fase 0).
	if timing, _ := os.lookup_env("ODIN_PP_LAB_TIMING", context.temp_allocator); timing == "1" {
		return mechanics_lab_first_person_timing(window, renderer, room, controller, cards, buffer, .Fists)
	}
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
		// The jab landing: the stop, the gloves held and the brute's print white (Fase 3).
		struck := false
		for _ in 0..<40 {
			frame(window, renderer, room, controller, cards, buffer)
			dark(room)
			hit := fp.fists_hit_at > 0 && render.first_person_struck_flash(renderer, game.enemy_entity(brute)) >= 1
			if blow.punch == .Jab && hit && !struck { artifacts.screenshot("odin_pp_mechanics_lab_prima_persona_pugni_colpo.png") }
			struck = struck || hit
		}
		if !struck { fmt.eprintln("mechanics lab: the", blow.punch, "landed with no flash on the brute"); return false }
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
	// The critical's gold star, caught as it bursts (Fase 3).
	starred := false
	for _ in 0..<40 {
		frame(window, renderer, room, controller, cards, buffer)
		since := renderer.sprite_assets.elapsed-fp.fists_star_at
		if !starred && fp.fists_star_at > 0 && fp.fists_star.shown && since >= 0.1 {
			artifacts.screenshot("odin_pp_mechanics_lab_prima_persona_pugni_critico.png")
			starred = true
		}
	}
	if !starred { fmt.eprintln("mechanics lab: the critical cross burst no gold star"); return false }
	if lost := health-room.enemies[brute_index].health; lost != game.FISTS_PUNCHES[.Cross].damage*game.FISTS_CRITICAL_FACTOR ||
	   room.first_person.fists.crits != 1 {
		fmt.eprintln("mechanics lab: the cross on its mark took", lost, "and made", room.first_person.fists.crits, "criticals"); return false
	}
	if !leave(window, renderer, room, controller, cards, buffer) { fmt.eprintln("mechanics lab: the fists' view did not end"); return false }

	// FIRST PERSON FENCER from the hand (Fase 4): its words; behind his eyes the
	// blade, the brute in front; the point brought slowly to its far side, then
	// across its chest fast with the button held, a cut; the guard against its
	// blow; Q twice and the grapple on it three cells west.
	fencer_definition, _ := game.card_definition_by_id(.First_Person_Fencer)
	for upgrade in i32(0)..=game.FIRST_PERSON_MAX_UPGRADE_LEVEL {
		if misfit := render.tactical_card_text_misfit(renderer, {id = 1, definition_id = .First_Person_Fencer, upgrade_level = upgrade},
			fencer_definition, width); misfit != "" {
			fmt.eprintf("mechanics lab: First Person Fencer +%d on a %.0f px card: %s\n", upgrade, width, misfit); return false
		}
	}
	mechanics_lab_still(window, renderer, room, fencer, "odin_pp_mechanics_lab_card_First_Person_Fencer.png")
	room.enemies[brute_index].position = game.add_position(room.player.position, {x = 1})
	room.enemies[brute_index].health = 60
	room.player.tactical.facing = .East
	render.clear_event_animations(renderer)
	for _ in 0..<600 {
		if game.tactical_allows_cards(room) && !render.renderer_blocks_player_input(renderer) && !game.tactical_player_busy(room) { break }
		frame(window, renderer, room, controller, cards, buffer)
	}
	player.deck.energy = player.deck.rules.max_energy
	if !run_session.commit_gameplay_command(room, renderer, cards, {kind = .Play_Card, origin_phase = .Combat, card_id = fencer,
		target = game.entity_target(game.PLAYER_ENTITY)}) || room.first_person.weapon != .Sword {
		fmt.eprintln("mechanics lab: the arena's First Person Fencer was not played"); return false
	}
	if !settle(window, renderer, room, controller, cards, buffer, true) { fmt.eprintln("mechanics lab: no dive with the sword"); return false }
	for _ in 0..<12 { frame(window, renderer, room, controller, cards, buffer) }
	if render.first_person_hud_status(renderer) != render.FIRST_PERSON_HUD_STATUS_SWORD || string(render.first_person_countdown_text(20, .Sword)) != "FPF 20s" {
		fmt.eprintln("mechanics lab: the sword's words are not shown"); return false
	}
	artifacts.screenshot("odin_pp_mechanics_lab_prima_persona_spada.png")
	// ODIN_PP_LAB_TIMING=sword measures the sword's view here (Fase 4).
	if timing, _ := os.lookup_env("ODIN_PP_LAB_TIMING", context.temp_allocator); timing == "sword" {
		return mechanics_lab_first_person_timing(window, renderer, room, controller, cards, buffer, .Sword)
	}
	sword := &room.first_person.sword
	// The mouse that takes the point to `want` this frame, the left button held or not.
	toward :: proc(sword: ^game.First_Person_Sword, want: [2]f32, cut: bool) -> run_session.Tactical_Controller_Input {
		move := (want-sword.tip)/game.SWORD_TIP_PER_PIXEL
		return {look = {move.x, -move.y}, fire = cut}
	}
	chest, _ := game.sword_chest_on_screen(room, render.first_person_aim(renderer), sword.facing, room.enemies[brute_index])
	line := game.SWORD_HILT.y+(chest.y-game.SWORD_HILT.y)/0.75
	from, start, finish := sword.tip, [2]f32{-0.75, line}, [2]f32{0.45, line}
	for k in 1..=24 { drive(window, renderer, room, controller, cards, buffer, toward(sword, from+(start-from)*(f32(k)/24), false)) }
	health = room.enemies[brute_index].health
	// The cut's blood, caught a few frames after it lands (Fase 4, after the user's try).
	bled, since_cut := false, -1
	for k in 1..=15 {
		drive(window, renderer, room, controller, cards, buffer, toward(sword, start+(finish-start)*(f32(k)/15), true))
		if k == 9 { artifacts.screenshot("odin_pp_mechanics_lab_prima_persona_spada_taglio.png") }
		if since_cut >= 0 { since_cut += 1 }
		if since_cut < 0 && sword.strikes > 0 { since_cut = 0 }
		if since_cut == 4 && !bled { artifacts.screenshot("odin_pp_mechanics_lab_prima_persona_spada_sangue.png"); bled = true }
	}
	for _ in 0..<20 {
		frame(window, renderer, room, controller, cards, buffer)
		if since_cut >= 0 { since_cut += 1 }
		if since_cut == 4 && !bled { artifacts.screenshot("odin_pp_mechanics_lab_prima_persona_spada_sangue.png"); bled = true }
	}
	if !bled { fmt.eprintln("mechanics lab: no blood caught after the cut"); return false }
	if sword.strikes != 1 || room.enemies[brute_index].health >= health {
		fmt.eprintln("mechanics lab: the cut across the brute made", sword.strikes, "cuts, the brute at", room.enemies[brute_index].health); return false
	}
	cut := sword.last
	// The guard up: the brute's blow parried.
	for _ in 0..<20 { drive(window, renderer, room, controller, cards, buffer, {fire_right = true}) }
	brute_enemy := &room.enemies[brute_index]
	brute_enemy.intent = game.make_attack_intent(room, brute_enemy.position, room.player.position, 5)
	before := room.player.health
	pulse: game.Pulse_Report
	game.resolve_enemy_intents(room, &pulse, brute)
	for _ in 0..<3 { drive(window, renderer, room, controller, cards, buffer, {fire_right = true}) }
	artifacts.screenshot("odin_pp_mechanics_lab_prima_persona_spada_parata.png")
	if room.player.health != before || sword.parries != 1 { fmt.eprintln("mechanics lab: the guard did not parry the brute's blow"); return false }
	// Held again, as the lab holds its foes, before it is moved.
	mechanics_lab_hold(room, brute)
	for _ in 0..<10 { frame(window, renderer, room, controller, cards, buffer) }
	// Q twice: west. The brute three cells west, Ctrl: pulled to the cell in front.
	for _ in 0..<2 {
		drive(window, renderer, room, controller, cards, buffer, {diagonals = {true, false, false, false}})
		for _ in 0..<15 { frame(window, renderer, room, controller, cards, buffer) }
	}
	game.tactical_first_person_tick(room, game.SWORD_GRAPPLE_RECHARGE)
	brute_enemy.position = game.add_position(room.player.position, {x = -3})
	drive(window, renderer, room, controller, cards, buffer, {ctrl = true})
	for _ in 0..<6 { frame(window, renderer, room, controller, cards, buffer) }
	artifacts.screenshot("odin_pp_mechanics_lab_prima_persona_spada_rampino.png")
	// Caught: the chain taut as the brute is hauled in (Fase 5).
	for _ in 0..<8 { frame(window, renderer, room, controller, cards, buffer) }
	artifacts.screenshot("odin_pp_mechanics_lab_prima_persona_spada_rampino_tirato.png")
	if sword.facing != .West || sword.grapples != 1 || brute_enemy.position != game.add_position(room.player.position, {x = -1}) {
		fmt.eprintln("mechanics lab: the grapple did not pull the brute (facing", sword.facing, "grapples", sword.grapples, ")"); return false
	}
	// A spinning cut (after the user's try): the brute on his right; the blade
	// swept right past the middle, then E turns him the way it sweeps: the cut
	// spins into the brute, its words beside it.
	brute_enemy.position = game.add_position(room.player.position, {y = -1})
	mechanics_lab_hold(room, brute)
	for _ in 0..<6 { frame(window, renderer, room, controller, cards, buffer) }
	from = sword.tip
	spin_from, spin_to := [2]f32{-0.7, 0.05}, [2]f32{0.35, 0.05}
	for k in 1..=20 { drive(window, renderer, room, controller, cards, buffer, toward(sword, from+(spin_from-from)*(f32(k)/20), false)) }
	cuts := sword.strikes
	for k in 1..=10 { drive(window, renderer, room, controller, cards, buffer, toward(sword, spin_from+(spin_to-spin_from)*(f32(k)/10), true)) }
	spun := toward(sword, spin_to+[2]f32{0.05, 0}, true)
	spun.diagonals[1] = true
	drive(window, renderer, room, controller, cards, buffer, spun)
	for _ in 0..<5 { drive(window, renderer, room, controller, cards, buffer, toward(sword, spin_to+[2]f32{0.05, 0}, true)) }
	artifacts.screenshot("odin_pp_mechanics_lab_prima_persona_spada_roteante.png")
	if sword.facing != .North || sword.strikes != cuts+1 || !sword.last.spin {
		fmt.eprintln("mechanics lab: no spinning cut (facing", sword.facing, "cuts", sword.strikes-cuts, "last", sword.last, ")"); return false
	}
	spin := sword.last
	// A perfect parry (Fase 5): the guard let go, then raised just as the
	// brute's blow comes: the blade flashes white, sparks and a ring.
	// The brute back in front (the spin may have thrown it a cell), held.
	if index, found := game.enemy_index_by_id(room, brute); found { brute_index = index }
	brute_enemy = &room.enemies[brute_index]
	brute_enemy.position = game.add_position(room.player.position, {y = -1})
	mechanics_lab_hold(room, brute)
	for _ in 0..<4 { drive(window, renderer, room, controller, cards, buffer, {}) }
	drive(window, renderer, room, controller, cards, buffer, {fire_right = true})
	brute_enemy.intent = game.make_attack_intent(room, brute_enemy.position, room.player.position, 5)
	pulse = {}
	game.resolve_enemy_intents(room, &pulse, brute)
	// Its blow spent, it is held again before the world's next beat comes.
	mechanics_lab_hold(room, brute)
	for _ in 0..<3 { drive(window, renderer, room, controller, cards, buffer, {fire_right = true}) }
	artifacts.screenshot("odin_pp_mechanics_lab_prima_persona_spada_parata_perfetta.png")
	if sword.perfect_parries != 1 { fmt.eprintln("mechanics lab: no perfect parry (", sword.parries, "parries)"); return false }
	if !leave(window, renderer, room, controller, cards, buffer) { fmt.eprintln("mechanics lab: the sword's view did not end"); return false }

	// FIRST PERSON ARCHER from the hand (Fase 6): its words; behind his eyes the
	// bow, the brute three cells east; drawn a second with the right button (its
	// ring filling, the guide's dots), let go: the arrow into the brute. Then a
	// bank shot: the angle whose guide reaches the brute after one bounce
	// (searched round the compass), drawn to one bounce and let go.
	archer_definition, _ := game.card_definition_by_id(.First_Person_Archer)
	for upgrade in i32(0)..=game.FIRST_PERSON_MAX_UPGRADE_LEVEL {
		if misfit := render.tactical_card_text_misfit(renderer, {id = 1, definition_id = .First_Person_Archer, upgrade_level = upgrade},
			archer_definition, width); misfit != "" {
			fmt.eprintf("mechanics lab: First Person Archer +%d on a %.0f px card: %s\n", upgrade, width, misfit); return false
		}
	}
	mechanics_lab_still(window, renderer, room, archer, "odin_pp_mechanics_lab_card_First_Person_Archer.png")
	if index, found := game.enemy_index_by_id(room, brute); found { brute_index = index }
	brute_enemy = &room.enemies[brute_index]
	brute_enemy.position = game.add_position(room.player.position, {x = 3})
	brute_enemy.health = 60
	mechanics_lab_hold(room, brute)
	room.player.tactical.facing = .East
	render.clear_event_animations(renderer)
	for _ in 0..<600 {
		if game.tactical_allows_cards(room) && !render.renderer_blocks_player_input(renderer) && !game.tactical_player_busy(room) { break }
		frame(window, renderer, room, controller, cards, buffer)
	}
	player.deck.energy = player.deck.rules.max_energy
	if !run_session.commit_gameplay_command(room, renderer, cards, {kind = .Play_Card, origin_phase = .Combat, card_id = archer,
		target = game.entity_target(game.PLAYER_ENTITY)}) || room.first_person.weapon != .Bow {
		fmt.eprintln("mechanics lab: the arena's First Person Archer was not played"); return false
	}
	if !settle(window, renderer, room, controller, cards, buffer, true) { fmt.eprintln("mechanics lab: no dive with the bow"); return false }
	for _ in 0..<12 { frame(window, renderer, room, controller, cards, buffer) }
	if render.first_person_hud_status(renderer) != render.FIRST_PERSON_HUD_STATUS_BOW || string(render.first_person_countdown_text(20, .Bow)) != "FPA 20s" {
		fmt.eprintln("mechanics lab: the bow's words are not shown"); return false
	}
	artifacts.screenshot("odin_pp_mechanics_lab_prima_persona_arco.png")
	// ODIN_PP_LAB_TIMING=bow measures the bow's view here (Fase 6).
	if timing, _ := os.lookup_env("ODIN_PP_LAB_TIMING", context.temp_allocator); timing == "bow" {
		return mechanics_lab_first_person_timing(window, renderer, room, controller, cards, buffer, .Bow)
	}
	bow := &room.first_person.bow
	fp.yaw, fp.pitch = 0, 0
	for _ in 0..<60 { drive(window, renderer, room, controller, cards, buffer, {fire_right = true}) }
	artifacts.screenshot("odin_pp_mechanics_lab_prima_persona_arco_teso.png")
	health = brute_enemy.health
	for k in 0..<40 {
		drive(window, renderer, room, controller, cards, buffer, {})
		// The arrow on its way, as big as it draws (2026-10-29).
		if k == 2 { artifacts.screenshot("odin_pp_mechanics_lab_prima_persona_arco_volo.png") }
	}
	if bow.loosed != 1 || bow.hits != 1 || brute_enemy.health >= health {
		fmt.eprintln("mechanics lab: the bow's arrow did not strike the brute (loosed", bow.loosed, "hits", bow.hits, ")"); return false
	}
	straight := bow.last
	// The bank shot: the brute two cells south and three east, the angle whose
	// guide reaches it after one bounce.
	brute_enemy.position = game.add_position(room.player.position, {x = 3, y = 2})
	mechanics_lab_hold(room, brute)
	for _ in 0..<6 { frame(window, renderer, room, controller, cards, buffer) }
	bank, banked := f32(0), false
	charge := f32(0.3)
	for step in 0..<720 {
		yaw := f32(step)*math.PI/360
		path: [6]game.Bow_Path_Point
		count := game.bow_guide(room, {yaw = yaw, framed = false}, charge, path[:], 2)
		if count != 3 || !path[1].bounce || path[2].bounce { continue }
		end := path[2].at
		dx, dz := end.x-(f32(brute_enemy.position.x)+0.5), end.z-(f32(brute_enemy.position.y)+0.5)
		if dx*dx+dz*dz < 0.5*0.5 { bank, banked = yaw, true; break }
	}
	if !banked { fmt.eprintln("mechanics lab: no bank shot onto the brute was found"); return false }
	fp.yaw, fp.pitch = bank, 0
	held := int(math.ceil(charge*game.BOW_DRAW_SECONDS*60))+2
	for _ in 0..<held { drive(window, renderer, room, controller, cards, buffer, {fire_right = true}) }
	health = brute_enemy.health
	caught := false
	for _ in 0..<60 {
		drive(window, renderer, room, controller, cards, buffer, {})
		if !caught && bow.bounces > 0 {
			artifacts.screenshot("odin_pp_mechanics_lab_prima_persona_arco_sponda.png")
			caught = true
		}
	}
	if bow.loosed != 2 || bow.hits != 2 || bow.last.bounced != 1 || brute_enemy.health >= health {
		fmt.eprintln("mechanics lab: the bank shot did not strike the brute (hits", bow.hits, "bounced", bow.last.bounced, ")"); return false
	}
	banked_hit := bow.last
	// A critical zone looked at (Fase 7): its paper target on the wall, its light pulsing.
	if bow.zone_count > 0 {
		zone := bow.zones[0]
		open := game.direction_offset(game.Move_Direction(zone.face))
		face := [2]f32{f32(zone.cell.x)+0.5+f32(open.x)*0.5, f32(zone.cell.y)+0.5+f32(open.y)*0.5}
		p := room.player.position
		fp.yaw, fp.pitch = math.atan2(face.y-(f32(p.y)+0.5), face.x-(f32(p.x)+0.5)), 0
		for _ in 0..<6 { drive(window, renderer, room, controller, cards, buffer, {}) }
		artifacts.screenshot("odin_pp_mechanics_lab_prima_persona_arco_zona.png")
	}
	// A full draw loosed as the view ends: the arrow flies on, seen from the
	// board's camera (the user's choice, 2026-10-29).
	fp.yaw, fp.pitch = math.PI*0.75, 0
	loosed := bow.loosed
	for _ in 0..<int(game.BOW_DRAW_SECONDS*60)+4 { drive(window, renderer, room, controller, cards, buffer, {fire_right = true}) }
	drive(window, renderer, room, controller, cards, buffer, {})
	if bow.loosed != loosed+1 { fmt.eprintln("mechanics lab: the bow's last arrow was not loosed"); return false }
	if !leave(window, renderer, room, controller, cards, buffer) { fmt.eprintln("mechanics lab: the bow's view did not end"); return false }
	if !game.first_person_bow_arrows_out(room) { fmt.eprintln("mechanics lab: the arrow did not fly on after the view"); return false }
	artifacts.screenshot("odin_pp_mechanics_lab_prima_persona_arco_dopo.png")
	for _ in 0..<60*8 {
		if !game.first_person_bow_arrows_out(room) { break }
		frame(window, renderer, room, controller, cards, buffer)
	}
	if game.first_person_bow_arrows_out(room) { fmt.eprintln("mechanics lab: the arrow never ended after the view"); return false }

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
		"and a critical cross on its mark; the sword cut the brute (%v for %d), parried its blow, pulled it in, spun " +
		"into it (%d) and parried it perfectly; the bow struck the brute straight (%d) and off a wall (%d)\n", ak_shots, cut.kind, cut.damage,
		spin.damage, straight.damage, banked_hit.damage)
	return true
}
