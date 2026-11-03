package devtools
import run_session "../run"

import "core:fmt"
import advisor "../advisor"
import app "../engine/app"
import artifacts "artifacts"
import game "../game"
import level "../level"
import render "../render"

// IA (game/ia.odin, docs/piano-ia.md, Fase 0), in the real window, in the IA's arena (run.Mechanics_Lab_Arena.IA, F3)
// with its own deck: the arena, its low walls, covers and four foes (odin_pp_ia_arena.png), and the card in hand
// (odin_pp_mechanics_lab_card_IA.png). Played, IA_Begun says its 30 seconds and "IA 30s" shows over the player while
// the chip under VITA counts them down on the world's clock (odin_pp_ia_card_NN.png). Behind the eyes of a view (the
// AK, taken up by the rules for two seconds) they stand still and the chip says IA FERMA (odin_pp_ia_card_view.png);
// the view over, they run again. Its foes are held, so every run sees the same.
// Fase 2: then the foes go free and the player follows the IA's advice for twenty seconds of the world (Fase 2: ten; the
// cards of Fase 3 need longer to come in), every advised move
// sent as the game's own commands the moment he is free; the cyan square on the cell to step on
// (odin_pp_ia_step_NN.png), the cyan cross on the foe to strike (odin_pp_ia_bump_NN.png), the word over him.
// Fase 3: the cards too: the advised card framed in cyan in the hand and its target marked, then the card raised
// as the player takes it (odin_pp_ia_card_hint_NN.png, even and odd).
mechanics_lab_ia :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, data: ^level.Level,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	game.destroy_room(room)
	player.health = player.stats.max_health
	rebuilt, built := run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG, .IA)
	if !built { fmt.eprintln("mechanics lab: the IA's arena was not built"); return false }
	room^ = rebuilt
	render.clear_event_animations(renderer)
	controller^ = {was_focused = true}
	for foe in room.enemies { mechanics_lab_hold(room, foe.id) }
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	if len(room.enemies) != 4 { fmt.eprintln("mechanics lab: the IA's arena has", len(room.enemies), "foes, not 4"); return false }
	id, held := mechanics_lab_hand_card(player, .IA)
	if !held || player.deck.hand_count != 8 { fmt.eprintln("mechanics lab: the IA's arena has not its eight cards in hand"); return false }
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_ia_arena.png")
	mechanics_lab_still(window, renderer, room, id, "odin_pp_mechanics_lab_card_IA.png")

	// Played: its seconds begin, said over the player.
	if !mechanics_lab_play(window, renderer, room, controller, cards, buffer, .IA, game.entity_target(game.PLAYER_ENTITY)) {
		fmt.eprintln("mechanics lab: the IA was not played"); return false
	}
	begun := false
	for event in room.recent_events.events[:room.recent_events.count] {
		if event.kind == .IA_Begun && event.amount == game.IA_SECONDS { begun = true }
	}
	if !begun || player.tactical.ia_remaining != f32(game.IA_SECONDS) {
		fmt.eprintln("mechanics lab: the IA began with", player.tactical.ia_remaining, "seconds, not", game.IA_SECONDS); return false
	}
	text, shown := render.ia_chip(room, false)
	if !shown || string(text) != "IA 30s" { fmt.eprintln("mechanics lab: the IA's chip says", text); return false }
	before := player.tactical.ia_remaining
	mechanics_lab_film(window, renderer, room, controller, cards, buffer, 90, 6, "ia_card")
	spent := before-player.tactical.ia_remaining
	// Ninety frames of a sixtieth: a second and a half of the world, less the card's cast (the world stands still in it).
	if !(spent > 1.0 && spent <= 1.5+0.01) { fmt.eprintln("mechanics lab: the IA's seconds ran", spent, "in a second and a half"); return false }

	// Behind the eyes of a view they stand still; the view over, they run again.
	if !game.tactical_begin_first_person(room, 2, .AK) { fmt.eprintln("mechanics lab: the AK's view did not open for the IA"); return false }
	held_at, view_left := player.tactical.ia_remaining, room.first_person.remaining
	for _ in 0..<60 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true) }
	// The world's clock ran (the view's own seconds went down), the IA's did not.
	if !(room.first_person.remaining < view_left-0.5) { fmt.eprintln("mechanics lab: the world's clock did not run in the view"); return false }
	if player.tactical.ia_remaining != held_at { fmt.eprintln("mechanics lab: the IA's seconds ran behind the eyes"); return false }
	if text, shown = render.ia_chip(room, false); !shown || string(text) != "IA FERMA" { fmt.eprintln("mechanics lab: the IA's chip behind the eyes says", text); return false }
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_ia_card_view.png")
	for _ in 0..<240 {
		if !game.tactical_first_person_active(room) { break }
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
	}
	if game.tactical_first_person_active(room) { fmt.eprintln("mechanics lab: the AK's view did not end"); return false }
	after_view := player.tactical.ia_remaining
	for _ in 0..<30 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true) }
	if !(player.tactical.ia_remaining < after_view) { fmt.eprintln("mechanics lab: the IA's seconds did not run again after the view"); return false }
	artifacts.screenshot("odin_pp_ia_card_after.png")
	return mechanics_lab_ia_follow(window, renderer, room, controller, cards, buffer)
}

// The foes free, the player follows the IA's advice for twenty seconds of the world, or until its seconds are over.
@(private = "file")
mechanics_lab_ia_follow :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	for &foe in room.enemies { foe.recovery_pulses = 0 }
	steps, bumps, played, followed := 0, 0, 0, 0
	health := room.player.health
	for frame := 0; frame < 1200 && room.phase == .Combat && game.ia_active(room); frame += 1 {
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
		advice := run_session.advisor_current_advice()
		free := advisor.player_free(room) || room.qte.kind != .None
		if !advice.valid || !free || render.renderer_blocks_player_input(renderer) { continue }
		// The marks of the advice about to be followed, as the player sees them.
		if renderer.tactical.advice.mark == .None { fmt.eprintln("mechanics lab: the IA's advice has no mark"); return false }
		#partial switch advice.kind {
		case .Step, .Dodge, .Diagonal:
			if steps < 8 { artifacts.screenshot(fmt.ctprintf("odin_pp_ia_step_%02d.png", steps)) }
			steps += 1
		case .Bump:
			if bumps < 8 { artifacts.screenshot(fmt.ctprintf("odin_pp_ia_bump_%02d.png", bumps)) }
			bumps += 1
		case .Card:
			// The card framed in the hand and its target marked; then raised, as the player takes it.
			if played < 4 {
				artifacts.screenshot(fmt.ctprintf("odin_pp_ia_card_hint_%02d.png", 2*played))
				mechanics_lab_still(window, renderer, room, advice.move.card_id, fmt.ctprintf("odin_pp_ia_card_hint_%02d.png", 2*played+1))
			}
			played += 1
		}
		commands, count := run_session.advisor_move_commands(room, advice.move)
		for command in commands[:count] { run_session.commit_gameplay_command(room, renderer, cards, command) }
		followed += 1
	}
	fmt.eprintf("mechanics lab IA: %d moves followed (%d steps, %d bumps, %d cards), life %d to %d, %d foes left\n",
		followed, steps, bumps, played, health, room.player.health, len(room.enemies))
	if steps == 0 || bumps == 0 || played == 0 { fmt.eprintln("mechanics lab: the IA advised no step, no bump or no card in twenty seconds"); return false }
	return true
}
