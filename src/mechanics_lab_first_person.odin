package main

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import app "app"
import game "game"
import grid "grid"
import level "level"
import render "render"

// FIRST PERSON SHOOTER (game/first_person.odin) in PROVA MECCANICHE's smoke,
// the deck's own copy played from the hand (raised to +5 for its last play:
// smoke state only, the arena and its deck rebuilt after the act). Its card and
// inspector (odin_pp_mechanics_lab_card_First_Person.png), its words on the
// hand's own cards at every level; played on himself: three energy and no
// window time, the cards, the refocus and the arrows refused; the camera dives
// into his eyes as the card's cue plays (odin_pp_living_fps_dive_NN.png, every
// third frame), his card fading, the AK, the crosshair and the countdown in
// place (odin_pp_mechanics_lab_fps.png), the hand slid away under the canvas.
// The trigger held for a second at sixty frames: six shots into the ghoul
// three cells north, each a wound of one point, the window and the view's own
// seconds a second shorter for the second gone and no more, his Veleno never
// biting; no swing of his card, no hurt of the ghoul's
// (odin_pp_living_fps_fire_NN.png). One shot west stops on an ice block, the
// foe behind it untouched (odin_pp_mechanics_lab_fps_wall.png), and one south
// on the arena's edge wall (odin_pp_mechanics_lab_fps_stone.png). Facing east W
// steps east, D south, S west and A north, the eye gliding from cell to cell
// (odin_pp_living_fps_steps_NN.png); W into a foe is a bump, the lantern
// swinging into view (odin_pp_living_fps_bump_NN.png), and Shift with D dodges
// south. A free ghoul's blow opens the defence prompt behind his eyes, the
// view's seconds held with the world's, and E then A dodges to the view's left
// (odin_pp_mechanics_lab_fps_defense.png); a blow let through flashes the
// edges red (odin_pp_mechanics_lab_fps_hurt.png). Through the window's end he
// still fires in the recovery; then the twenty seconds run out, as many beats
// of the world's gone by, and the camera rises
// (odin_pp_living_fps_rise_NN.png). A +5 copy lasts thirty, a flat board
// turns 3D for it (odin_pp_mechanics_lab_fps_flat.png) and back to flat after
// F7 ends it (odin_pp_mechanics_lab_fps_flat_after.png). The HUD's words hold.
mechanics_lab_first_person :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, data: ^level.Level,
	controller: ^Tactical_Controller, cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command) -> bool {
	player := room.player
	center := grid.Position{MECHANICS_LAB_WIDTH/2, MECHANICS_LAB_HEIGHT/2}
	fp := &renderer.tactical.first_person
	foe :: mechanics_lab_enemy
	spawn :: mechanics_lab_spawn_enemy
	// A frame with the clock running, the mouse the view's and the trigger
	// `fire` (with Shift and keys when given), saved as
	// odin_pp_living_<name>_NN.png when `save`.
	frame :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^Tactical_Controller,
		cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command, fire := false, name := "", save := false, shot: ^int = nil,
		dt := f32(1.0/60.0), input := Tactical_Controller_Input{}) {
		given := input
		given.focused, given.fire = true, fire
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, dt, true, nil, given)
		if save && shot != nil {
			rl.TakeScreenshot(fmt.ctprintf("odin_pp_living_%s_%02d.png", name, shot^))
			shot^ += 1
		}
	}
	// Frames until the player may act again (the clock runs meanwhile).
	free_board :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^Tactical_Controller,
		cards: ^Card_Interaction_State, buffer: ^Buffered_Gameplay_Command) {
		for _ in 0..<600 {
			if game.tactical_allows_action(room) && !render.renderer_blocks_player_input(renderer) && !game.tactical_player_busy(room) { break }
			mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true, nil, {focused = true})
		}
	}
	// The deck's own card in the hand, at `upgrade` (smoke state: the arena
	// and its deck are rebuilt after the act).
	deck_card :: proc(player: ^game.Player, upgrade: i32) -> (id: u32, ok: bool) {
		deck := &player.deck
		for &card in deck.hand[:deck.hand_count] {
			if card.definition_id != .First_Person { continue }
			card.upgrade_level = upgrade
			for &owned in deck.owned[:deck.owned_count] {
				if owned.id == card.id { owned.upgrade_level = upgrade }
			}
			return card.id, card.lifetime == .Permanent && game.validate_deck_state(deck)
		}
		return
	}
	sounds := renderer.tactical.lab_sounds
	if sounds == nil { fmt.eprintln("mechanics lab: no sounds before the first person act"); return false }
	free_board(window, renderer, room, controller, cards, buffer)
	// A fresh arena around the player in the middle, facing north: a ghoul held
	// three cells north, an ice block two west and a foe held behind it.
	if !mechanics_lab_clear_arena(room) { return false }
	game.clear_ground(room)
	clear(&room.loot)
	player.health = player.stats.max_health
	player.position = center
	player.equipment = {}
	for kind in ([6]game.Status_Kind{.Deflect, .Arrows, .Fate, .Venom_Blade, .Poison, .Burn}) { _, _ = game.remove_status(room, game.PLAYER_ENTITY, kind) }
	player.tactical.dodge_recovery, player.tactical.facing = 0, .North
	ghoul_id := spawn(room, {center.x, center.y-3}, 40)
	ice := grid.Position{center.x-2, center.y}
	append(&room.objects, game.Grid_Object{id = room.next_object_id, kind = .Ice_Block, position = ice, health = 4, max_health = 4})
	room.next_object_id += 1
	hidden_id := spawn(room, {center.x-4, center.y}, 30, .Archer)
	if ghoul_id == 0 || hidden_id == 0 { fmt.eprintln("mechanics lab: no room for the first person's foes"); return false }
	render.clear_event_animations(renderer)
	for _ in 0..<12 { frame(window, renderer, room, controller, cards, buffer) }
	card, in_hand := deck_card(player, 0)
	if !in_hand { fmt.eprintln("mechanics lab: no First Person Shooter in hand"); return false }
	mechanics_lab_still(window, renderer, room, card, "odin_pp_mechanics_lab_card_First_Person.png")
	// Its words on the hand's own cards (this hand's width) and in the
	// inspector, at every level.
	definition, _ := game.card_definition_by_id(.First_Person, true)
	width := render.tactical_hand_card_bounds(renderer, 0, player.deck.hand_count).width
	for upgrade in i32(0)..=game.FIRST_PERSON_MAX_UPGRADE_LEVEL {
		if misfit := render.tactical_card_text_misfit(renderer, {id = 1, definition_id = .First_Person, upgrade_level = upgrade}, definition, width); misfit != "" {
			fmt.eprintf("mechanics lab: First Person Shooter +%d on a %.0f px card: %s\n", upgrade, width, misfit); return false
		}
	}
	// Played on himself, the window open and full.
	for _ in 0..<600 {
		if player.tactical.phase == .Decision && player.tactical.remaining >= f32(player.tactical.budget)-0.5 && game.tactical_allows_cards(room) &&
		   !render.renderer_blocks_player_input(renderer) && !game.tactical_player_busy(room) { break }
		frame(window, renderer, room, controller, cards, buffer)
	}
	player.deck.energy = player.deck.rules.max_energy
	window_left, heard := player.tactical.remaining, sounds.played
	enters, exits := fp.enters, fp.exits
	view_pulses := room.pulse_count
	if !commit_gameplay_command(room, renderer, cards, {kind = .Play_Card, origin_phase = .Combat, card_id = card,
		target = game.entity_target(game.PLAYER_ENTITY)}) || !game.tactical_first_person_active(room) {
		fmt.eprintln("mechanics lab: the First Person Shooter was not played"); return false
	}
	if room.first_person.duration != 20 || player.deck.energy != player.deck.rules.max_energy-3 || player.tactical.remaining != window_left ||
	   player.tactical.cast_remaining != 0 {
		fmt.eprintln("mechanics lab: the First Person Shooter took", room.first_person.duration, "s,", player.deck.rules.max_energy-player.deck.energy,
			"energy and", window_left-player.tactical.remaining, "s of the window"); return false
	}
	// No card, refocus or arrow now.
	other := player.deck.hand[0].id
	applied, _ := game.apply_status(room, game.PLAYER_ENTITY, .Arrows, 3, 0)
	if !applied || game.tactical_allows_cards(room) ||
	   commit_gameplay_command(room, renderer, cards, {kind = .Play_Card, origin_phase = .Combat, card_id = other, target = game.entity_target(game.PLAYER_ENTITY)}) ||
	   commit_gameplay_command(room, renderer, cards, {kind = .Refocus, origin_phase = .Combat}) ||
	   commit_gameplay_command(room, renderer, cards, {kind = .Shoot, origin_phase = .Combat, target = game.entity_target(game.enemy_entity(ghoul_id))}) {
		fmt.eprintln("mechanics lab: a card, a refocus or an arrow was taken behind his eyes"); return false
	}
	_, _ = game.remove_status(room, game.PLAYER_ENTITY, .Arrows)
	// The dive, paced by the card's cue.
	shot := 0
	dived := -1
	for index in 0..<150 {
		frame(window, renderer, room, controller, cards, buffer, name = "fps_dive", save = index%3 == 0, shot = &shot)
		if render.first_person_amount(renderer) >= 1 { dived = index; break }
	}
	eye := fp.eye
	camera := renderer.tactical.camera
	if dived < 0 || rl.Vector3Distance(camera.position, eye) > 0.001 || !render.first_person_hides_player(renderer) || fp.enters != enters+1 {
		fmt.eprintln("mechanics lab: the camera did not dive into his eyes:", dived, camera.position, eye); return false
	}
	for _ in 0..<2 { frame(window, renderer, room, controller, cards, buffer, name = "fps_dive", save = true, shot = &shot) }
	if sounds.played[render.LAB_FIRST_PERSON_ENTER] != heard[render.LAB_FIRST_PERSON_ENTER]+1 {
		fmt.eprintln("mechanics lab: the dive made no sound"); return false
	}
	// The hand has slid away under the canvas: no card behind his eyes.
	if render.first_person_hand_drop(renderer) < render.TACTICAL_HAND_HEIGHT {
		fmt.eprintln("mechanics lab: the hand did not slide away behind his eyes:", render.first_person_hand_drop(renderer)); return false
	}
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_fps.png")
	// A second of the trigger held at sixty frames: six shots into the ghoul.
	fp.yaw, fp.pitch = -math.PI/2, 0
	poisoned, _ := game.apply_status(room, game.PLAYER_ENTITY, .Poison, 2, 0)
	if !poisoned { return false }
	for _ in 0..<2 { frame(window, renderer, room, controller, cards, buffer) }
	shots, hits, ghoul := room.first_person.shots, room.first_person.hits, foe(room, ghoul_id).health
	window_left, heard = player.tactical.remaining, sounds.played
	view_left := room.first_person.remaining
	health := player.health
	shot = 0
	for index in 0..<60 { frame(window, renderer, room, controller, cards, buffer, fire = true, name = "fps_fire", save = index%2 == 0, shot = &shot) }
	for index in 0..<12 { frame(window, renderer, room, controller, cards, buffer, name = "fps_fire", save = index%2 == 0, shot = &shot) }
	poison, _ := game.status_for_entity(room, game.PLAYER_ENTITY, .Poison)
	fired := room.first_person.shots-shots
	// The view's seconds are the world's, as the window's: the shots took none.
	if fired != 6 || room.first_person.hits-hits != 6 || foe(room, ghoul_id).health != ghoul-6 ||
	   abs(window_left-player.tactical.remaining-(1+12.0/60)) > 0.01 || abs(view_left-room.first_person.remaining-(1+12.0/60)) > 0.01 ||
	   poison.potency != 2 || player.health != health {
		fmt.eprintln("mechanics lab: a second of the trigger fired", fired, "shots,", room.first_person.hits-hits, "hits, the ghoul at",
			foe(room, ghoul_id).health, "the window", window_left-player.tactical.remaining, "s shorter, the view",
			view_left-room.first_person.remaining, "s, Veleno", poison.potency); return false
	}
	// Each of the six a hitscan into the ghoul for one point.
	for number in shots+1..=room.first_person.shots {
		entry := room.first_person.trail[(number-1)%game.FIRST_PERSON_TRAIL]
		if entry.number != number || entry.hit != .Foe || entry.target != game.enemy_entity(ghoul_id) || entry.damage != game.FIRST_PERSON_SHOT_DAMAGE {
			fmt.eprintln("mechanics lab: shot", number, "met", entry.hit, "for", entry.damage); return false
		}
	}
	if sounds.played[render.LAB_FIRST_PERSON_SHOT] != heard[render.LAB_FIRST_PERSON_SHOT]+6 || sounds.played[render.LAB_FIRST_PERSON_HIT] < heard[render.LAB_FIRST_PERSON_HIT]+5 ||
	   sounds.played[.Pilgrim_Attack] != heard[.Pilgrim_Attack] || sounds.played[.Ghoul_Hurt] != heard[.Ghoul_Hurt] {
		fmt.eprintln("mechanics lab: the shots sounded", sounds.played[render.LAB_FIRST_PERSON_SHOT]-heard[render.LAB_FIRST_PERSON_SHOT], "times,",
			sounds.played[render.LAB_FIRST_PERSON_HIT]-heard[render.LAB_FIRST_PERSON_HIT], "hits; swings", sounds.played[.Pilgrim_Attack]-heard[.Pilgrim_Attack],
			"hurts", sounds.played[.Ghoul_Hurt]-heard[.Ghoul_Hurt]); return false
	}
	_, _ = game.remove_status(room, game.PLAYER_ENTITY, .Poison)
	// West: the ice block stops a shot, the archer behind it untouched.
	fp.yaw = math.PI
	for _ in 0..<2 { frame(window, renderer, room, controller, cards, buffer) }
	hidden, ricochets := foe(room, hidden_id).health, fp.ricochets
	shots = room.first_person.shots
	for _ in 0..<30 {
		frame(window, renderer, room, controller, cards, buffer, fire = room.first_person.shots == shots)
		if room.first_person.shots > shots { break }
	}
	last := room.first_person.trail[(room.first_person.shots-1)%game.FIRST_PERSON_TRAIL]
	for _ in 0..<4 { frame(window, renderer, room, controller, cards, buffer) }
	if room.first_person.shots != shots+1 || last.hit != .Solid || last.cell != ice || foe(room, hidden_id).health != hidden || fp.ricochets != ricochets+1 {
		fmt.eprintln("mechanics lab: the shot west met", last.hit, "at", last.cell, "not the ice at", ice); return false
	}
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_fps_wall.png")
	// South: the arena's edge wall stops one, a ricochet off the stone.
	fp.yaw = math.PI/2
	for _ in 0..<2 { frame(window, renderer, room, controller, cards, buffer) }
	ricochets = fp.ricochets
	shots = room.first_person.shots
	for _ in 0..<30 {
		frame(window, renderer, room, controller, cards, buffer, fire = room.first_person.shots == shots)
		if room.first_person.shots > shots { break }
	}
	stone := room.first_person.trail[(room.first_person.shots-1)%game.FIRST_PERSON_TRAIL]
	// The tracer's flight to the wall, eight cells off, and the stone chips
	// its spark throws off.
	for _ in 0..<16 { frame(window, renderer, room, controller, cards, buffer) }
	edge := grid.Position{player.position.x, MECHANICS_LAB_HEIGHT-1}
	tile, inside := level.tile_at(data, edge)
	_, object := game.grid_object_at(room, edge)
	if room.first_person.shots != shots+1 || stone.hit != .Solid || stone.cell != edge || !inside || level.is_walkable(tile.kind) || object ||
	   fp.ricochets != ricochets+1 {
		fmt.eprintln("mechanics lab: the shot south met", stone.hit, "at", stone.cell, "not the edge wall at", edge); return false
	}
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_fps_stone.png")
	// Facing east: W east, D south, S west, A north, the eye gliding.
	fp.yaw = 0
	for _ in 0..<2 { frame(window, renderer, room, controller, cards, buffer) }
	keys := render.first_person_keys(renderer)
	if keys != ([4]game.Move_Direction{.East, .South, .West, .North}) { fmt.eprintln("mechanics lab: the keys facing east are", keys); return false }
	shot = 0
	ways := [4]grid.Position{{1, 0}, {0, 1}, {-1, 0}, {0, -1}}
	for way, index in ways {
		free_board(window, renderer, room, controller, cards, buffer)
		from := player.position
		if !commit_gameplay_command(room, renderer, cards, {kind = .Move, origin_phase = .Combat, direction = keys[index]}) ||
		   player.position != game.add_position(from, way) {
			fmt.eprintln("mechanics lab: key", index, "facing east did not step", way); return false
		}
		previous := renderer.tactical.camera.position
		for step in 0..<24 {
			frame(window, renderer, room, controller, cards, buffer, name = "fps_steps", save = index == 0 && step%2 == 0, shot = &shot)
			now := renderer.tactical.camera.position
			along := (now.x-previous.x)*f32(way.x)+(now.z-previous.z)*f32(way.y)
			if along < -0.0001 { fmt.eprintln("mechanics lab: the eye slid back on step", index); return false }
			previous = now
		}
		if abs(previous.x-f32(player.position.x)-0.5) > 0.001 || abs(previous.z-f32(player.position.y)-0.5) > 0.001 {
			fmt.eprintln("mechanics lab: the eye did not reach", player.position, previous); return false
		}
	}
	// W into a foe is a bump.
	bumped_id := spawn(room, {center.x+1, center.y}, 30)
	free_board(window, renderer, room, controller, cards, buffer)
	if bumped_id == 0 || !commit_gameplay_command(room, renderer, cards, {kind = .Move, origin_phase = .Combat, direction = keys[0]}) ||
	   player.position != center || foe(room, bumped_id).health != 30-player.stats.attack {
		fmt.eprintln("mechanics lab: W into the foe east was no bump"); return false
	}
	shot = 0
	for index in 0..<40 { frame(window, renderer, room, controller, cards, buffer, name = "fps_bump", save = index%2 == 0, shot = &shot) }
	// Shift and D dodge south, two cells.
	free_board(window, renderer, room, controller, cards, buffer)
	dodge := Tactical_Controller_Input{shift = true}
	dodge.directions[1] = true
	frame(window, renderer, room, controller, cards, buffer, input = dodge)
	if player.position != (grid.Position{center.x, center.y+2}) {
		fmt.eprintln("mechanics lab: Shift and D facing east dodged to", player.position); return false
	}
	for _ in 0..<40 { frame(window, renderer, room, controller, cards, buffer) }
	// A free ghoul east of him, faced: its blow opens the defence prompt
	// behind his eyes, the view's seconds held with the world; E, then A,
	// dodges to the view's left (north).
	_ = mechanics_lab_clear_arena(room)
	player.tactical.dodge_recovery = 0
	fp.yaw, fp.pitch = 0, 0
	attacker_id := spawn(room, {player.position.x+1, player.position.y}, 60, free = true)
	if attacker_id == 0 { fmt.eprintln("mechanics lab: no room for the free ghoul"); return false }
	prompted := false
	for _ in 0..<600 {
		frame(window, renderer, room, controller, cards, buffer)
		if room.qte.kind == .Defense { prompted = true; break }
	}
	if !prompted { fmt.eprintln("mechanics lab: the free ghoul's blow opened no defence prompt"); return false }
	held := room.first_person.remaining
	for _ in 0..<3 { frame(window, renderer, room, controller, cards, buffer) }
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_fps_defense.png")
	if room.first_person.remaining != held || render.first_person_amount(renderer) < 1 || !game.tactical_first_person_active(room) {
		fmt.eprintln("mechanics lab: the defence prompt did not hold the view's seconds", held, room.first_person.remaining); return false
	}
	from := player.position
	choose := Tactical_Controller_Input{}
	choose.defenses[3] = true
	frame(window, renderer, room, controller, cards, buffer, input = choose)
	land := Tactical_Controller_Input{}
	land.directions[3] = true
	frame(window, renderer, room, controller, cards, buffer, input = land)
	if room.qte.kind != .None || player.position != (grid.Position{from.x, from.y-1}) {
		fmt.eprintln("mechanics lab: E then A facing east dodged to", player.position, "from", from); return false
	}
	// A blow let through: the edges flash red.
	hurt, struck := false, player.health
	for _ in 0..<900 {
		frame(window, renderer, room, controller, cards, buffer)
		if player.health < struck && fp.hurt_at > 0 && renderer.sprite_assets.elapsed-fp.hurt_at >= 0.05 { hurt = true; break }
	}
	if !hurt { fmt.eprintln("mechanics lab: no blow reached him behind his eyes"); return false }
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_fps_hurt.png")
	mechanics_lab_hold(room, attacker_id)
	// Through the window's end: the recovery, and he still fires.
	for _ in 0..<600 {
		if room.qte.kind == .None && !room.tactical_pulse.pending && player.tactical.phase == .Decision { break }
		frame(window, renderer, room, controller, cards, buffer)
	}
	player.tactical.remaining = 0.05
	for _ in 0..<60 {
		frame(window, renderer, room, controller, cards, buffer)
		if player.tactical.phase == .Recovery { break }
	}
	shots = room.first_person.shots
	for _ in 0..<12 {
		frame(window, renderer, room, controller, cards, buffer, fire = true)
		if player.tactical.phase != .Recovery { break }
	}
	if !game.tactical_first_person_active(room) || room.first_person.shots <= shots {
		fmt.eprintln("mechanics lab: no shot in the recovery behind his eyes"); return false
	}
	// The seconds run out; the camera rises.
	for _ in 0..<400 {
		if !game.tactical_first_person_active(room) { break }
		frame(window, renderer, room, controller, cards, buffer, dt = 0.1)
		if room.qte.kind != .None { frame(window, renderer, room, controller, cards, buffer) }
	}
	// Twenty seconds of the world's: as many beats meanwhile, one a second
	// (the defence prompt held them with the view's).
	beats := room.pulse_count-view_pulses
	if game.tactical_first_person_active(room) || room.first_person.remaining != 0 || beats < 19 || beats > 21 {
		fmt.eprintln("mechanics lab: the twenty seconds did not run out:", room.first_person.remaining, "after", beats, "beats"); return false
	}
	shot = 0
	for index in 0..<90 {
		frame(window, renderer, room, controller, cards, buffer, name = "fps_rise", save = index%2 == 0, shot = &shot)
		if render.first_person_amount(renderer) <= 0 && index > 4 { break }
	}
	if render.first_person_amount(renderer) > 0 || fp.exits != exits+1 || sounds.played[render.LAB_FIRST_PERSON_EXIT] <= heard[render.LAB_FIRST_PERSON_EXIT] ||
	   controller.look_captured {
		fmt.eprintln("mechanics lab: the camera did not rise back:", render.first_person_amount(renderer)); return false
	}
	// A +5 copy: thirty seconds, the flat board 3D behind his eyes, flat
	// again once F7 ends them.
	free_board(window, renderer, room, controller, cards, buffer)
	upgraded, upgraded_held := deck_card(player, game.FIRST_PERSON_MAX_UPGRADE_LEVEL)
	player.deck.energy = player.deck.rules.max_energy
	if !upgraded_held || !commit_gameplay_command(room, renderer, cards, {kind = .Play_Card, origin_phase = .Combat, card_id = upgraded,
		target = game.entity_target(game.PLAYER_ENTITY)}) || room.first_person.duration != 30 {
		fmt.eprintln("mechanics lab: the +5 copy was not thirty seconds:", room.first_person.duration); return false
	}
	for _ in 0..<90 {
		render.sync_first_person_board(renderer, room, false)
		frame(window, renderer, room, controller, cards, buffer)
		if render.first_person_amount(renderer) >= 1 { break }
	}
	render.sync_first_person_board(renderer, room, false)
	if !renderer.tactical.scene_3d { fmt.eprintln("mechanics lab: the flat board stayed flat behind his eyes"); return false }
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_fps_flat.png")
	// The HUD's words hold: the countdown in its plate, the line beside the
	// plate's objective (a full room's too).
	countdown := render.first_person_countdown_bounds(renderer)
	if _, _, _, fit := render.gothic_text_fit_plan(renderer, render.first_person_countdown_text(30), countdown.width-24, 18); fit != .Fits {
		fmt.eprintln("mechanics lab: the countdown does not hold in its plate:", fit); return false
	}
	for objective in ([2]cstring{render.tactical_hud_objective(renderer, room), render.tactical_hud_foes_objective(game.MAX_ENEMIES_PER_ROOM)}) {
		room_width := render.tactical_hud_status_room(renderer, objective)
		if _, _, _, fit := render.gothic_text_fit_plan(renderer, render.FIRST_PERSON_HUD_STATUS, room_width, 10); fit != .Fits {
			fmt.eprintln("mechanics lab: the HUD's line behind his eyes does not hold in", room_width, "px:", fit); return false
		}
	}
	for _ in 0..<120 {
		if !render.renderer_blocks_player_input(renderer) { break }
		frame(window, renderer, room, controller, cards, buffer)
	}
	if !mechanics_lab_clear_for_fishing(room, renderer) || game.tactical_first_person_active(room) {
		fmt.eprintln("mechanics lab: F7 did not end the view"); return false
	}
	for _ in 0..<120 {
		render.sync_first_person_board(renderer, room, false)
		frame(window, renderer, room, controller, cards, buffer)
		if render.first_person_amount(renderer) <= 0 && !render.renderer_blocks_player_input(renderer) { break }
	}
	render.sync_first_person_board(renderer, room, false)
	for _ in 0..<2 { frame(window, renderer, room, controller, cards, buffer) }
	flat := !renderer.tactical.scene_3d
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_fps_flat_after.png")
	render.sync_first_person_board(renderer, room, true)
	if !flat { fmt.eprintln("mechanics lab: the board did not turn flat again after the view"); return false }
	// The fight back, as F5 brings it: a fresh arena for the act after this one.
	game.destroy_room(room)
	player.health = player.stats.max_health
	rebuilt, built := create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG)
	if !built { fmt.eprintln("mechanics lab: the arena was not rebuilt after the first person act"); return false }
	room^ = rebuilt
	render.frame_level(renderer, data)
	render.clear_event_animations(renderer)
	controller^ = {was_focused = true}
	for _ in 0..<12 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	fmt.eprintf("mechanics lab first person: dived in %d frames, 6 shots a second into the ghoul, the ice and the edge wall stopped one each, " +
		"keys and dodge with the view, the defence prompt and a wound behind his eyes, a shot in the recovery, out after %d beats; " +
		"%v, %v, %v, %v and %v sounded\n", dived, beats,
		render.LAB_FIRST_PERSON_ENTER, render.LAB_FIRST_PERSON_SHOT, render.LAB_FIRST_PERSON_HIT, render.LAB_FIRST_PERSON_RICOCHET,
		render.LAB_FIRST_PERSON_EXIT)
	return true
}
