package devtools
import artifacts "artifacts"
import run_session "../run"

import "core:fmt"
import app "../engine/app"
import game "../game"
import grid "../engine/grid"
import level "../level"
import render "../render"

// HEIGHTS (game/height.odin, render/height_view.odin) in the lab's second arena
// (run.Mechanics_Lab_Arena.Heights, F3): the player climbs the stair of three
// to the plateau, is stopped by its cliff, a foe is pushed off it and falls, and
// the Lazzo is held from up there. Stills odin_pp_mechanics_lab_heights_*.png.

// One step of the player, as the lane makes it, and the frames its slide takes.
@(private = "file")
mechanics_lab_step :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, direction: game.Move_Direction) -> bool {
	mechanics_lab_wait_free(window, renderer, room, controller, cards, buffer)
	accepted := run_session.commit_gameplay_command(room, renderer, cards, {kind = .Move, origin_phase = .Combat, direction = direction})
	for _ in 0..<30 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	return accepted
}

mechanics_lab_heights :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, data: ^level.Level,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	// The arena of heights, as F3 brings it.
	game.destroy_room(room)
	player.health = player.stats.max_health
	rebuilt, built := run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG, .Heights)
	if !built { fmt.eprintln("mechanics lab: the arena of heights was not built"); return false }
	room^ = rebuilt
	render.clear_event_animations(renderer)
	controller^ = {was_focused = true}
	for foe in room.enemies { mechanics_lab_hold(room, foe.id) }
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	start := player.position
	if game.cell_height(room, start) != 0 || game.cell_height(room, {12, 8}) != 1 || game.cell_height(room, {14, 8}) != 3 ||
	   game.cell_height(room, {15, 8}) != 4 || game.cell_height(room, {4, 11}) != 9 {
		fmt.eprintln("mechanics lab: the arena of heights is not the one drawn"); return false
	}
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_heights_arena.png")

	// The stair: three steps up, one each, then onto the plateau.
	for step in 1..=3 {
		if !mechanics_lab_step(window, renderer, room, controller, cards, buffer, .East) || game.cell_height(room, player.position) != i32(step) {
			fmt.eprintln("mechanics lab: the player did not climb the stair at step", step); return false
		}
	}
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_heights_stair.png")
	if !mechanics_lab_step(window, renderer, room, controller, cards, buffer, .East) || game.cell_height(room, player.position) != 4 {
		fmt.eprintln("mechanics lab: the player did not reach the plateau"); return false
	}
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_heights_plateau.png")

	// Across the plateau to its edge, where the cliff stops the walk.
	for _ in 0..<4 {
		if !mechanics_lab_step(window, renderer, room, controller, cards, buffer, .East) { fmt.eprintln("mechanics lab: the plateau did not hold the player"); return false }
	}
	edge := player.position
	if edge != (grid.Position{19, 8}) { fmt.eprintln("mechanics lab: the player is not at the plateau's edge:", edge); return false }
	mechanics_lab_wait_free(window, renderer, room, controller, cards, buffer)
	if game.try_move_player(room, .East) != .Blocked || player.position != edge {
		fmt.eprintln("mechanics lab: the cliff did not stop the walk"); return false
	}
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_heights_cliff.png")

	// The Lazzo held from the plateau: a foe below, further than the card's reach
	// on flat ground, is within it from four steps above.
	lasso, has_lasso := mechanics_lab_card_of(player, .Lasso)
	if !has_lasso { fmt.eprintln("mechanics lab: no Lazzo in hand"); return false }
	definition, _ := game.card_definition_by_id(.Lasso)
	reach := definition.targeting.cast_range.maximum
	if game.height_range_maximum(room, reach, edge, {edge.x+reach, edge.y}) != reach+1 {
		fmt.eprintln("mechanics lab: no bonus in reach from the plateau"); return false
	}
	player.deck.energy = player.deck.rules.max_energy
	mechanics_lab_capture_hits(window, renderer, room, lasso.id, 0, {edge.x+1, edge.y}, "odin_pp_mechanics_lab_heights_reach.png")

	// A foe pushed off the plateau: down the cliff it falls, and the fall hurts
	// (the drop of four steps costs three). Up the same cliff it cannot be pushed.
	archer := game.Enemy{}
	for foe in room.enemies { if foe.archetype == .Archer { archer = foe } }
	if archer.id == 0 || game.cell_height(room, archer.position) != 4 { fmt.eprintln("mechanics lab: the archer is not on the plateau"); return false }
	before_health := archer.health
	landing := grid.Position{archer.position.x+2, archer.position.y}
	query := game.query_entity_movement(room, game.enemy_entity(archer.id), landing)
	if !game.movement_query_is_clear(&query) { fmt.eprintln("mechanics lab: the archer cannot be pushed off the plateau"); return false }
	presentation := render.capture_room_presentation(room)
	push := game.make_action(.Move, game.PLAYER_ENTITY, game.entity_target(game.enemy_entity(archer.id)), .Entity)
	if !game.add_effect(&push, game.move_effect(game.enemy_entity(archer.id), landing)) { return false }
	report := game.resolve_action(room, &push)
	if !report.accepted { fmt.eprintln("mechanics lab: the push was refused"); return false }
	game.append_event_log(room.recent_events, &report.events)
	after := render.capture_room_presentation(room)
	if !render.begin_renderer_event_timeline(renderer, presentation, room.recent_events, &after) { return false }
	fallen := mechanics_lab_enemy(room, archer.id)
	if fallen == nil || fallen.position != landing || fallen.health != before_health-3 {
		fmt.eprintln("mechanics lab: the fall cost", before_health-(fallen.health if fallen != nil else 0), "instead of 3"); return false
	}
	for _ in 0..<14 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	artifacts.screenshot("odin_pp_mechanics_lab_heights_fall.png")
	up := game.query_entity_movement(room, game.enemy_entity(archer.id), archer.position)
	if up.error != .Static_Blocker { fmt.eprintln("mechanics lab: a push climbed the cliff:", up.error); return false }

	// The fight back, as F5 brings it, for the act after this one.
	game.destroy_room(room)
	player.health = player.stats.max_health
	rebuilt, built = run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG)
	if !built { fmt.eprintln("mechanics lab: the arena was not rebuilt after the heights"); return false }
	room^ = rebuilt
	render.clear_event_animations(renderer)
	controller^ = {was_focused = true}
	for _ in 0..<12 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	return true
}
