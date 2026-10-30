package devtools
import artifacts "artifacts"
import run_session "../run"

import "core:fmt"
import app "../engine/app"
import game "../game"
import grid "../engine/grid"
import render "../render"

// CANNONE, BUCO NERO and DINOSAURO (game/cannon.odin, black_hole.odin,
// dinosaur.odin), the deck's own copies played from the hand as the lane plays
// them. Each act is one fresh arena (mechanics_lab_party_arena); its stills and
// reels are odin_pp_mechanics_lab_*.png and odin_pp_living_*_NN.png; its sounds
// are counted by mechanics_lab_sounds_heard.

// How many of `kind` stand on the board.
@(private = "file")
mechanics_lab_objects_of :: proc(room: ^game.Room, kind: game.Grid_Object_Kind) -> (count: int) {
	for object in room.objects { if object.kind == kind { count += 1 } }
	return
}

// A cannon played from the hand east of the player, aimed east with the wheel
// as the lane gives its way (Gameplay_Command.aim_way).
@(private = "file")
mechanics_lab_play_cannon :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, card: game.Card_Id, cell: grid.Position,
	way: game.Move_Direction) -> bool {
	mechanics_lab_wait_free(window, renderer, room, controller, cards, buffer)
	id, held := mechanics_lab_hand_card(room.player, card)
	room.player.deck.energy = room.player.deck.rules.max_energy
	return held && run_session.commit_gameplay_command(room, renderer, cards, {kind = .Play_Card, origin_phase = .Combat, card_id = id,
		target = game.cell_target(cell), aim_way = way, has_aim_way = true})
}

// The cannon: its aim held over the board with the wheel's arrow (east), then
// played; its balls fly every beat to the first of two foes in its line and
// the second is never touched; then, as the Cannone laser (the card turned for
// the act: its evolution is the deck's, tested in game), the beam hurts both.
mechanics_lab_cannon :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	center := grid.Position{x = run_session.MECHANICS_LAB_WIDTH/2, y = run_session.MECHANICS_LAB_HEIGHT/2}
	spawn :: mechanics_lab_spawn_enemy
	foe :: mechanics_lab_enemy
	if !mechanics_lab_party_arena(window, renderer, room, controller, cards, buffer, "the Cannone") { return false }
	cannon_at := grid.offset(center, 2, 0)
	first_id, second_id := spawn(room, grid.offset(center, 6, 0), 60), spawn(room, grid.offset(center, 8, 0), 60)
	if first_id == 0 || second_id == 0 { fmt.eprintln("mechanics lab: no room for the cannon's foes"); return false }
	render.clear_event_animations(renderer)
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	id, held := mechanics_lab_hand_card(player, .Field_Cannon)
	if !held { fmt.eprintln("mechanics lab: no Cannone in hand"); return false }
	mechanics_lab_still(window, renderer, room, id, "odin_pp_mechanics_lab_card_Cannon.png")
	render.set_flood_aim(renderer, true, true, .East)
	mechanics_lab_capture_aim(window, renderer, room, id, cannon_at, "odin_pp_mechanics_lab_cannon_aim.png")
	render.set_flood_aim(renderer, false, false, .East)
	if !mechanics_lab_play_cannon(window, renderer, room, controller, cards, buffer, .Field_Cannon, cannon_at, .East) {
		fmt.eprintln("mechanics lab: the Cannone was not played"); return false
	}
	if mechanics_lab_objects_of(room, .Field_Cannon) != 1 { fmt.eprintln("mechanics lab: no cannon on the board"); return false }
	if cannon, found := game.grid_object_at(room, cannon_at); !found || cannon.facing != .East || cannon.life != game.CANNON_SECONDS || cannon.laser {
		fmt.eprintln("mechanics lab: the cannon stands wrong"); return false
	}
	frame := 0
	// A ball in flight, and the foe it strikes.
	flight := false
	for _ in 0..<900 {
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "cannon", 6, &frame)
		for offset in 0..<render.renderer_active_cue_count(renderer) {
			cue, showing := render.renderer_active_cue_at(renderer, offset)
			if showing && cue.started && cue.kind == .Cannon_Fired && !flight && render.presentation_cue_progress(cue) > 0.45 {
				artifacts.screenshot("odin_pp_mechanics_lab_cannon_flight.png")
				flight = true
			}
		}
		if enemy := foe(room, first_id); enemy != nil && enemy.health < 60 && flight { break }
	}
	first, second := foe(room, first_id), foe(room, second_id)
	if first == nil || second == nil || first.health >= 60 { fmt.eprintln("mechanics lab: the ball did not strike the first foe"); return false }
	if second.health != 60 { fmt.eprintln("mechanics lab: the ball went through the first foe"); return false }
	if !flight { fmt.eprintln("mechanics lab: no ball was seen in flight"); return false }
	artifacts.screenshot("odin_pp_mechanics_lab_cannon_hit.png")
	// Its time runs out: the cannon falls apart (the beat is the world's).
	for index in 0..<len(room.objects) { if room.objects[index].kind == .Field_Cannon { room.objects[index].life = 1 } }
	broke := false
	for _ in 0..<400 {
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "cannon_end", 6, &frame)
		if mechanics_lab_objects_of(room, .Field_Cannon) == 0 && !render.renderer_blocks_player_input(renderer) { broke = true; break }
	}
	if !broke { fmt.eprintln("mechanics lab: the cannon did not fall apart"); return false }
	// The laser: the same stand, a beam through both foes.
	if !mechanics_lab_borrow(player, .Field_Cannon, .Laser_Cannon) { return false }
	defer mechanics_lab_borrow(player, .Laser_Cannon, .Field_Cannon)
	before_first, before_second := foe(room, first_id).health, foe(room, second_id).health
	laser_id, laser_held := mechanics_lab_hand_card(player, .Laser_Cannon)
	if !laser_held { fmt.eprintln("mechanics lab: no Cannone laser in hand"); return false }
	mechanics_lab_still(window, renderer, room, laser_id, "odin_pp_mechanics_lab_card_Laser_Cannon.png")
	if !mechanics_lab_play_cannon(window, renderer, room, controller, cards, buffer, .Laser_Cannon, cannon_at, .East) {
		fmt.eprintln("mechanics lab: the Cannone laser was not played"); return false
	}
	beam := false
	for _ in 0..<600 {
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "laser", 4, &frame)
		for offset in 0..<render.renderer_active_cue_count(renderer) {
			cue, showing := render.renderer_active_cue_at(renderer, offset)
			if showing && cue.started && cue.kind == .Cannon_Fired && !beam && render.presentation_cue_progress(cue) > 0.2 {
				artifacts.screenshot("odin_pp_mechanics_lab_laser_beam.png")
				beam = true
			}
		}
		a, b := foe(room, first_id), foe(room, second_id)
		if a != nil && b != nil && a.health < before_first && b.health < before_second && beam { break }
	}
	a, b := foe(room, first_id), foe(room, second_id)
	if a == nil || b == nil || a.health >= before_first || b.health >= before_second || !beam {
		fmt.eprintln("mechanics lab: the beam did not strike both foes"); return false
	}
	clear(&room.objects)
	for _ in 0..<30 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true) }
	fmt.eprintf("mechanics lab cannon: a ball struck the first foe only, the cannon fell apart, the beam struck both, %d frames\n", frame)
	return true
}

// The hole: its two areas held over the board, played east of the player; a
// weak foe inside it dies swallowed, one at the edge of the pull is drawn in
// and hurt, and after its eight beats it closes.
mechanics_lab_black_hole :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	center := grid.Position{x = run_session.MECHANICS_LAB_WIDTH/2, y = run_session.MECHANICS_LAB_HEIGHT/2}
	spawn :: mechanics_lab_spawn_enemy
	foe :: mechanics_lab_enemy
	if !mechanics_lab_party_arena(window, renderer, room, controller, cards, buffer, "the Buco Nero") { return false }
	hole_at := grid.offset(center, 3, 0)
	inside_id := spawn(room, grid.offset(hole_at, 1, 0), 2*game.BLACK_HOLE_BASE_DAMAGE-1)
	far_id := spawn(room, grid.offset(hole_at, 0, -2), 60)
	boss_id := spawn(room, grid.offset(hole_at, -2, 2), 90, .Custodian)
	if inside_id == 0 || far_id == 0 || boss_id == 0 { fmt.eprintln("mechanics lab: no room for the hole's foes"); return false }
	render.clear_event_animations(renderer)
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	id, held := mechanics_lab_hand_card(player, .Devouring_Hole)
	if !held { fmt.eprintln("mechanics lab: no Buco Nero in hand"); return false }
	mechanics_lab_still(window, renderer, room, id, "odin_pp_mechanics_lab_card_Black_Hole.png")
	mechanics_lab_capture_aim(window, renderer, room, id, hole_at, "odin_pp_mechanics_lab_black_hole_aim.png")
	if !mechanics_lab_play(window, renderer, room, controller, cards, buffer, .Devouring_Hole, game.cell_target(hole_at)) {
		fmt.eprintln("mechanics lab: the Buco Nero was not played"); return false
	}
	if mechanics_lab_objects_of(room, .Devouring_Hole) != 1 { fmt.eprintln("mechanics lab: no hole on the board"); return false }
	frame := 0
	still := false
	for _ in 0..<700 {
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "black_hole", 6, &frame)
		if frame == 90 && !still { artifacts.screenshot("odin_pp_mechanics_lab_black_hole_open.png"); still = true }
		if foe(room, inside_id) == nil && .Black_Hole_Swallowed in renderer.shown_events && !render.renderer_blocks_player_input(renderer) { break }
	}
	if foe(room, inside_id) != nil || .Black_Hole_Swallowed not_in renderer.shown_events { fmt.eprintln("mechanics lab: the weak foe was not swallowed"); return false }
	far, boss := foe(room, far_id), foe(room, boss_id)
	if far == nil || far.health >= 60 { fmt.eprintln("mechanics lab: the far foe was not drawn in and hurt"); return false }
	if far.position.x != hole_at.x || abs(far.position.y-hole_at.y) > 1 { fmt.eprintln("mechanics lab: the far foe stands at", far.position); return false }
	if boss == nil || boss.position != (grid.offset(hole_at, -2, 2)) { fmt.eprintln("mechanics lab: the heavy foe was moved"); return false }
	artifacts.screenshot("odin_pp_mechanics_lab_black_hole_pull.png")
	// It closes at its eighth beat.
	for index in 0..<len(room.objects) { if room.objects[index].kind == .Devouring_Hole { room.objects[index].life = 1 } }
	closed := false
	for _ in 0..<400 {
		mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "black_hole_end", 6, &frame)
		if mechanics_lab_objects_of(room, .Devouring_Hole) == 0 && !render.renderer_blocks_player_input(renderer) { closed = true; break }
	}
	if !closed { fmt.eprintln("mechanics lab: the hole did not close"); return false }
	for _ in 0..<30 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true) }
	fmt.eprintf("mechanics lab black hole: a foe swallowed, one drawn in, the heavy one left, it closed, %d frames\n", frame)
	return true
}

// The ride, once for each face of its d4: the dinosaur under the player, the
// chip of the HUD, and what each does. Velociraptor: a quick step and a bump
// that bleeds; Stegosauro: a brute's blow is turned back at it with no prompt;
// Dilophosaurus: a bump that poisons; Giganotosauro: a step that stomps the
// foes round it and a bump that would kill a chaser walks onto it instead and crushes it.
mechanics_lab_dinosaur :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	center := grid.Position{x = run_session.MECHANICS_LAB_WIDTH/2, y = run_session.MECHANICS_LAB_HEIGHT/2}
	spawn :: mechanics_lab_spawn_enemy
	foe :: mechanics_lab_enemy
	stacks :: proc(room: ^game.Room, id: u32, kind: game.Status_Kind) -> i32 {
		status, found := game.status_for_entity(room, game.enemy_entity(id), kind)
		return status.potency if found else 0
	}
	step :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
		cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, way: game.Move_Direction) -> bool {
		return mechanics_lab_commit(window, renderer, room, controller, cards, buffer, {kind = .Move, origin_phase = .Combat, direction = way})
	}
	for face in i32(1)..=4 {
		if !mechanics_lab_party_arena(window, renderer, room, controller, cards, buffer, "the Dinosauro") { return false }
		room.ride = {}
		dice, rolled := mechanics_lab_dice_for_face(face, 4)
		if !rolled { fmt.eprintln("mechanics lab: no dice for the face", face); return false }
		player.dice = dice
		render.clear_event_animations(renderer)
		for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
		if face == 1 {
			id, held := mechanics_lab_hand_card(player, .Dino_Ride)
			if !held { fmt.eprintln("mechanics lab: no Dinosauro in hand"); return false }
			mechanics_lab_still(window, renderer, room, id, "odin_pp_mechanics_lab_card_Dinosaur.png")
		}
		if !mechanics_lab_play(window, renderer, room, controller, cards, buffer, .Dino_Ride, game.entity_target(game.PLAYER_ENTITY)) {
			fmt.eprintln("mechanics lab: the Dinosauro was not played"); return false
		}
		kind := game.Dino_Kind(face-1)
		if !room.ride.active || room.ride.kind != kind || room.ride.remaining != game.RIDE_SECONDS { fmt.eprintln("mechanics lab: the ride is", room.ride, "for the face", face); return false }
		name := game.dino_name(kind)
		frame := 0
		for _ in 0..<180 { mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, fmt.tprintf("dino_%d", face), 6, &frame) }
		// The chip says which one and how long.
		chips := render.tactical_status_chip_layout(renderer, room)
		fits := false
		for index in 0..<chips.shown {
			if text := string(chips.texts[index]); len(text) >= len(name) && text[:len(name)] == name || len(text) >= 3 && text[:3] == name[:3] { fits = true }
		}
		if !fits { fmt.eprintln("mechanics lab: no chip for the", name); return false }
		mechanics_lab_still(window, renderer, room, 0, fmt.ctprintf("odin_pp_mechanics_lab_dino_%d.png", face))
		switch kind {
		case .Raptor:
			bait := spawn(room, grid.offset(center, 0, -3), 60)
			if bait == 0 { return false }
			if !step(window, renderer, room, controller, cards, buffer, .North) || !step(window, renderer, room, controller, cards, buffer, .North) ||
			   !step(window, renderer, room, controller, cards, buffer, .North) { return false }
			for _ in 0..<60 { mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "dino_raptor_bump", 6, &frame) }
			if stacks(room, bait, .Bleed) < 1 { fmt.eprintln("mechanics lab: the raptor's bump did not bleed"); return false }
			// The second bump bites for the stack the first left, and bleeds again.
			before := foe(room, bait).health
			if !step(window, renderer, room, controller, cards, buffer, .North) { return false }
			for _ in 0..<60 { mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "dino_raptor_bump", 6, &frame) }
			if stacks(room, bait, .Bleed) != 2 || before-foe(room, bait).health < 2 { fmt.eprintln("mechanics lab: the bleeding did not bite"); return false }
		case .Stego:
			archer := spawn(room, grid.offset(center, 4, 0), 30, .Archer, true)
			if archer == 0 { return false }
			hurt := false
			for _ in 0..<900 {
				mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "dino_stego", 6, &frame)
				if enemy := foe(room, archer); enemy == nil || enemy.health < 30 { hurt = true; break }
			}
			if !hurt || player.health != player.stats.max_health || room.qte.kind != .None {
				fmt.eprintln("mechanics lab: the stegosaurus did not turn the bolt back clean"); return false
			}
		case .Dilo:
			bait := spawn(room, grid.offset(center, 0, -2), 60)
			if bait == 0 { return false }
			if !step(window, renderer, room, controller, cards, buffer, .North) || !step(window, renderer, room, controller, cards, buffer, .North) { return false }
			// Poison wears a stack a beat: watched as it lands, the bump's own
			// resolution first (at the player's pace the next beat can fall on
			// the very next frame and wear the one stack away).
			poisoned := stacks(room, bait, .Poison) >= 1
			for _ in 0..<90 {
				mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "dino_dilo_bump", 6, &frame)
				if stacks(room, bait, .Poison) >= 1 { poisoned = true; break }
			}
			if !poisoned { fmt.eprintln("mechanics lab: the dilophosaurus's bump did not poison"); return false }
			for _ in 0..<20 { mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "dino_dilo_bump", 6, &frame) }
		case .Giga:
			left, right := spawn(room, grid.offset(center, -1, -1), 60), spawn(room, grid.offset(center, 1, -1), 60)
			victim := spawn(room, grid.offset(center, 0, -3), 30, .Chaser)
			if left == 0 || right == 0 || victim == 0 { return false }
			if !step(window, renderer, room, controller, cards, buffer, .North) { return false }
			for _ in 0..<80 { mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "dino_giga_stomp", 6, &frame) }
			a, b := foe(room, left), foe(room, right)
			if a == nil || b == nil || a.health != 60-game.GIGA_STOMP_DAMAGE || b.health != 60-game.GIGA_STOMP_DAMAGE {
				fmt.eprintln("mechanics lab: the stomp did not hurt the foes beside him"); return false
			}
			if !step(window, renderer, room, controller, cards, buffer, .North) || !step(window, renderer, room, controller, cards, buffer, .North) { return false }
			for _ in 0..<80 { mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "dino_giga_bite", 6, &frame) }
			// His bump would kill the chaser: he walks onto it and crushes it.
			if foe(room, victim) != nil || player.position != (grid.offset(center, 0, -3)) {
				fmt.eprintln("mechanics lab: the giganotosaurus did not crush the chaser under him"); return false
			}
			if .Dino_Stomp not_in renderer.shown_events { fmt.eprintln("mechanics lab: no crush was shown"); return false }
		}
		artifacts.screenshot(fmt.ctprintf("odin_pp_mechanics_lab_dino_%d_after.png", face))
		// The ride's end: the dinosaur goes.
		room.ride.remaining = 1
		ended := false
		for _ in 0..<400 {
			mechanics_lab_reel_frame(window, renderer, room, controller, cards, buffer, "dino_end", 6, &frame)
			if !room.ride.active && !render.renderer_blocks_player_input(renderer) { ended = true; break }
		}
		if !ended { fmt.eprintln("mechanics lab: the ride did not end"); return false }
		for _ in 0..<40 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true) }
		fmt.eprintf("mechanics lab dinosaur: the %s rode and did its work, %d frames\n", name, frame)
	}
	return true
}
