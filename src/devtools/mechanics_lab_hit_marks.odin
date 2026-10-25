package devtools
import artifacts "artifacts"
import run_session "../run"

import "core:fmt"
import app "../engine/app"
import game "../game"
import grid "../engine/grid"
import render "../render"

// "THIS ONE CAN BE HIT" (render/card_hit_mark.odin): the cards held over a board
// of foes, the cells of the foes they would really hit lit hot with a column of
// sparks, the one under the mouse locked. Stills odin_pp_mechanics_lab_hit_*.png:
// the Lazzo, the Pinball (a Custodian it cannot take stays red), the Inondazione
// (every foe), the Cannone aimed east (the foe in its line only), the Buco Nero
// (the foes in its 3x3) and the Lazzo only under the mouse in the hand (faint).

// The board as the act draws it: a chosen card (and the one only under the mouse
// in the hand), the pointer on `cell`.
mechanics_lab_capture_hits :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, selected, hovered: u32,
	cell: grid.Position, name: cstring) {
	for _ in 0..<3 {
		render.update_renderer_frame_timeline(renderer, 0)
		render.update_tactical_view(renderer, room, {}, false, true)
		renderer.has_hovered_cell, renderer.hovered_cell = true, cell
		app.begin_canvas(window, render.RESIN_BACKGROUND)
		render.draw_tactical_world(renderer, room, selected, nil, hovered if selected == 0 else 0)
		render.draw_tactical_status(renderer, room)
		render.draw_tactical_hand(renderer, room, hovered, selected, 0, {})
		render.draw_tactical_hud(renderer, room, false, false)
		render.draw_mechanics_lab_banner(renderer, room)
		app.present(window, render.LETTERBOX_COLOR)
	}
	artifacts.screenshot(name)
	renderer.has_hovered_cell = false
}

// The foes some valid cast of `card` would hit, over the whole arena.
@(private = "file")
mechanics_lab_hits_of :: proc(room: ^game.Room, card: game.Card_Instance) -> (all: game.Card_Hit_Set) {
	definition, _ := game.card_definition_by_id(card.definition_id)
	for y in 0..<room.level_data.tiles.height {
		for x in 0..<room.level_data.tiles.width {
			evaluation := game.evaluate_card_targeting(room, card, game.card_target_request_at(definition, {x = x, y = y}))
			hits := game.card_hit_enemies(room, card, &evaluation)
			for id in hits.ids[:hits.count] { game.card_hit_set_add(&all, id) }
		}
	}
	return
}

mechanics_lab_card_of :: proc(player: ^game.Player, id: game.Card_Id) -> (card: game.Card_Instance, ok: bool) {
	hand, held := mechanics_lab_hand_card(player, id)
	if !held { return }
	index, _ := game.hand_card_index_by_id(&player.deck, hand)
	return player.deck.hand[index], true
}

@(private = "file")
mechanics_lab_foe_cell :: proc(room: ^game.Room, id: u32) -> grid.Position {
	enemy := mechanics_lab_enemy(room, id)
	return enemy.position if enemy != nil else {}
}

mechanics_lab_hit_marks :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	center := grid.Position{x = run_session.MECHANICS_LAB_WIDTH/2, y = run_session.MECHANICS_LAB_HEIGHT/2}
	spawn :: mechanics_lab_spawn_enemy
	if !mechanics_lab_party_arena(window, renderer, room, controller, cards, buffer, "the hit marks") { return false }
	// Foes held about the player: one beside him to the east, one to the south, a
	// Custodian (a miniboss: no Pinball takes it), one far east on his row, one
	// far west.
	east := spawn(room, grid.offset(center, 1, 0), 60)
	south := spawn(room, grid.offset(center, 0, 1), 60)
	custodian := spawn(room, grid.offset(center, 2, -2), 80, .Custodian)
	far_east := spawn(room, grid.offset(center, 7, 0), 60)
	far_west := spawn(room, grid.offset(center, -6, 2), 60)
	if east == 0 || south == 0 || custodian == 0 || far_east == 0 || far_west == 0 {
		fmt.eprintln("mechanics lab: no room for the hit marks' foes"); return false
	}
	render.clear_event_animations(renderer)
	render.set_flood_aim(renderer, false, false, .East)
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	player.deck.energy = player.deck.rules.max_energy
	lasso, has_lasso := mechanics_lab_card_of(player, .Lasso)
	pinball, has_pinball := mechanics_lab_card_of(player, .Pinball)
	wave, has_wave := mechanics_lab_card_of(player, .Flood_Wave)
	cannon, has_cannon := mechanics_lab_card_of(player, .Field_Cannon)
	hole, has_hole := mechanics_lab_card_of(player, .Devouring_Hole)
	if !has_lasso || !has_pinball || !has_wave || !has_cannon || !has_hole {
		fmt.eprintln("mechanics lab: a card of the hit marks is not in hand"); return false
	}

	// The Lazzo takes every foe it can reach, the Custodian included (a miniboss
	// is a valid target), and the foe under the mouse locks.
	lasso_hits := mechanics_lab_hits_of(room, lasso)
	if !game.card_hit_set_contains(&lasso_hits, east) || !game.card_hit_set_contains(&lasso_hits, south) ||
	   !game.card_hit_set_contains(&lasso_hits, custodian) {
		fmt.eprintln("mechanics lab: the Lazzo does not mark the foes it can take"); return false
	}
	mechanics_lab_capture_hits(window, renderer, room, lasso.id, 0, mechanics_lab_foe_cell(room, east), "odin_pp_mechanics_lab_hit_lasso.png")

	// The Pinball takes the foes beside the player; the Custodian is too heavy
	// and is not marked (it keeps its red "too heavy" ring).
	pinball_hits := mechanics_lab_hits_of(room, pinball)
	if !game.card_hit_set_contains(&pinball_hits, east) || game.card_hit_set_contains(&pinball_hits, custodian) ||
	   game.card_hit_set_contains(&pinball_hits, far_west) {
		fmt.eprintln("mechanics lab: the Pinball marks the wrong foes"); return false
	}
	mechanics_lab_capture_hits(window, renderer, room, pinball.id, 0, mechanics_lab_foe_cell(room, south), "odin_pp_mechanics_lab_hit_pinball.png")

	// The Inondazione sweeps every foe in play, wherever it is dropped.
	wave_hits := mechanics_lab_hits_of(room, wave)
	if wave_hits.count != len(room.enemies) { fmt.eprintln("mechanics lab: the wave does not mark every foe"); return false }
	mechanics_lab_capture_hits(window, renderer, room, wave.id, 0, grid.offset(center, -2, 0), "odin_pp_mechanics_lab_hit_flood.png")

	// The Cannone aimed east from beside the player: the first foe in its line.
	render.set_flood_aim(renderer, true, true, .East)
	mechanics_lab_capture_hits(window, renderer, room, cannon.id, 0, grid.offset(center, -1, 0), "odin_pp_mechanics_lab_hit_cannon.png")
	render.set_flood_aim(renderer, false, false, .East)

	// The Buco Nero over the foe to the south: the foes in its 3x3.
	mechanics_lab_capture_hits(window, renderer, room, hole.id, 0, grid.offset(center, 0, 2), "odin_pp_mechanics_lab_hit_hole.png")

	// No card chosen, the Lazzo only under the mouse in the hand: its range and
	// its foes show faintly, and the pointer on the board changes nothing.
	mechanics_lab_capture_hits(window, renderer, room, 0, lasso.id, mechanics_lab_foe_cell(room, east), "odin_pp_mechanics_lab_hit_hover.png")
	return true
}
