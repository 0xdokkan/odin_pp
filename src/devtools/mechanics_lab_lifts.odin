package devtools

import "core:fmt"
import artifacts "artifacts"
import app "../engine/app"
import game "../game"
import grid "../engine/grid"
import level "../level"
import render "../render"
import run_session "../run"

// LIFTS AND GATES (game/lift.odin, Fase 7 of docs/piano-profondita.md) in the lab's seventh arena
// (run.Mechanics_Lab_Arena.Lifts, F3), all with steps: the player calls the cliff's platform down with a step toward its
// empty landing, waits for it, rides it up and walks off onto the plateau; calls the shaft's platform up and rides it
// down into the hall; opens the gate across the hall's way out from its lever and walks out; then the foe in the hall,
// let go, takes the shaft up after the player, out of play on the way. Stills odin_pp_mechanics_lab_lift_*.png.

// Walks the player to `to` round the lifts' landings (a step onto one is a call or a ride), the foes held.
@(private = "file")
lift_lab_walk :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, to: grid.Position) -> bool {
	player := room.player
	for step := 0; player.position != to && step < 200; step += 1 {
		for foe in room.enemies { mechanics_lab_hold(room, foe.id) }
		walk := layers_lab_route(room, player.position, to, true)
		if len(walk) == 0 { fmt.eprintln("mechanics lab: no way from", player.position, "to", to, "round the lifts"); return false }
		before := player.position
		if !mountain_lab_step(window, renderer, room, controller, cards, buffer, walk[0]) { fmt.eprintln("mechanics lab: a step was refused at", before); return false }
		mechanics_lab_wait_free(window, renderer, room, controller, cards, buffer)
		if player.position == before { fmt.eprintln("mechanics lab: the walk did not step at", before); return false }
	}
	if player.position != to { fmt.eprintln("mechanics lab: the walk ended at", player.position, "not", to); return false }
	return true
}

// The board left to show `seconds`.
@(private = "file")
lift_lab_frames :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, seconds: f32) {
	for _ in 0..<int(seconds*60) { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true) }
}

// The board left to show platform `index` until it rests.
@(private = "file")
lift_lab_wait_platform :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, index: int) -> bool {
	for _ in 0..<600 {
		if !room.lifts.platforms[index].moving { return true }
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
	}
	fmt.eprintln("mechanics lab: platform", index, "never stopped")
	return false
}

// A step toward a lift's landing whose platform is away: no step, the platform called, and on its way here.
@(private = "file")
lift_lab_call :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, direction: game.Move_Direction, index, end: int) -> bool {
	before := room.player.position
	if mountain_lab_step(window, renderer, room, controller, cards, buffer, direction) || room.player.position != before {
		fmt.eprintln("mechanics lab: the step toward the empty landing at", before, "went on"); return false
	}
	platform := room.lifts.platforms[index]
	if !platform.moving || int(platform.at) != end || platform.has_rider { fmt.eprintln("mechanics lab: the step did not call platform", index); return false }
	return true
}

// A step onto a platform resting at its landing: the player rides it to the other end, out of reach on the way (a still
// halfway, `name`), and stands there when it stops.
@(private = "file")
lift_lab_ride :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, direction: game.Move_Direction, index: int,
	arrival: grid.Position, name: cstring) -> bool {
	mechanics_lab_wait_free(window, renderer, room, controller, cards, buffer)
	if !mountain_lab_step(window, renderer, room, controller, cards, buffer, direction) { fmt.eprintln("mechanics lab: the step onto platform", index, "was refused"); return false }
	if !game.lift_player_riding(room) || !game.tactical_player_intangible(room) || room.player.position != arrival {
		fmt.eprintln("mechanics lab: the player does not ride platform", index, "to", arrival); return false
	}
	lift_lab_frames(window, renderer, room, controller, cards, buffer, game.lift_journey_seconds(room, index)*0.5)
	artifacts.screenshot(name)
	mechanics_lab_wait_free(window, renderer, room, controller, cards, buffer)
	if game.lift_player_riding(room) || room.lifts.platforms[index].moving { fmt.eprintln("mechanics lab: the ride on platform", index, "did not end"); return false }
	return true
}

mechanics_lab_lifts :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, data: ^level.Level,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	game.destroy_room(room)
	player.health = player.stats.max_health
	rebuilt, built := run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG, .Lifts)
	if !built { fmt.eprintln("mechanics lab: the arena of the lifts was not built"); return false }
	room^ = rebuilt
	render.clear_event_animations(renderer)
	controller^ = {was_focused = true}
	for foe in room.enemies { mechanics_lab_hold(room, foe.id) }
	renderer.tactical.world_orbit.distance = 28
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	if player.position != run_session.MECHANICS_LAB_LIFTS_START || room.lifts.count != 2 || len(data.gates) != 1 {
		fmt.eprintln("mechanics lab: the arena of the lifts is not the one drawn"); return false
	}
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_lift_arena.png")

	// The cliff's lift, its platform up top: called down with a step toward its empty landing, waited for, ridden up.
	if !lift_lab_walk(window, renderer, room, controller, cards, buffer, {x = 10, y = 10}) { return false }
	if !lift_lab_call(window, renderer, room, controller, cards, buffer, .East, 0, 0) { return false }
	lift_lab_frames(window, renderer, room, controller, cards, buffer, game.lift_journey_seconds(room, 0)*0.5)
	artifacts.screenshot("odin_pp_mechanics_lab_lift_chiamata.png")
	if !lift_lab_wait_platform(window, renderer, room, controller, cards, buffer, 0) { return false }
	if !lift_lab_ride(window, renderer, room, controller, cards, buffer, .East, 0, {x = 11, y = 10, layer = 1}, "odin_pp_mechanics_lab_lift_salita.png") { return false }
	// Up there, on its landing: drawn at the top, where the player stands.
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_lift_arrivo.png")
	// Off its landing, a step onto the plateau's edge.
	if !lift_lab_walk(window, renderer, room, controller, cards, buffer, {x = 12, y = 10}) { return false }
	if game.cell_height(room, player.position) != 14 { fmt.eprintln("mechanics lab: the lift did not reach the plateau's top"); return false }
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_lift_cima.png")

	// The shaft, its platform down in the hall: called up, ridden down.
	if !lift_lab_walk(window, renderer, room, controller, cards, buffer, {x = 17, y = 5}) { return false }
	if !lift_lab_call(window, renderer, room, controller, cards, buffer, .East, 1, 0) { return false }
	if !lift_lab_wait_platform(window, renderer, room, controller, cards, buffer, 1) { return false }
	if !lift_lab_ride(window, renderer, room, controller, cards, buffer, .East, 1, {x = 18, y = 5, layer = -1}, "odin_pp_mechanics_lab_lift_pozzo.png") { return false }

	// The gate across the hall's way out: shut it stops the step, a step into its bars from its lever opens it.
	gate := grid.Position{x = 24, y = 7, layer = -1}
	if !lift_lab_walk(window, renderer, room, controller, cards, buffer, {x = 23, y = 7, layer = -1}) { return false }
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_lift_cancello_chiuso.png")
	if !mountain_lab_step(window, renderer, room, controller, cards, buffer, .East) { fmt.eprintln("mechanics lab: the step into the gate's bars was refused"); return false }
	mechanics_lab_wait_free(window, renderer, room, controller, cards, buffer)
	if _, open, _ := level.gate_at(data, gate); !open || player.position.x != 23 { fmt.eprintln("mechanics lab: the gate did not open from its lever"); return false }
	if !lift_lab_walk(window, renderer, room, controller, cards, buffer, {x = 26, y = 7}) { return false }
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_lift_cancello_aperto.png")

	// The foe in the hall, let go, goes for the player up on the plateau: up the shaft, out of play on the way.
	chaser: u32
	for foe in room.enemies { if foe.archetype == .Chaser { chaser = foe.id } }
	if chaser == 0 { fmt.eprintln("mechanics lab: no foe in the hall"); return false }
	player.position = {x = 20, y = 4}
	render.clear_event_animations(renderer)
	if foe := mechanics_lab_enemy(room, chaser); foe != nil { foe.recovery_pulses = 0 }
	game.plan_enemy_intents(room)
	rode := false
	for _ in 0..<1200 {
		for foe in room.enemies { if foe.id != chaser { mechanics_lab_hold(room, foe.id) } }
		mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0, true)
		if index, riding := game.lift_riding(room, game.enemy_entity(chaser)); riding {
			if !game.enemy_is_out_of_play(room, chaser) { fmt.eprintln("mechanics lab: the foe riding the shaft is in play"); return false }
			if !rode { lift_lab_frames(window, renderer, room, controller, cards, buffer, game.lift_journey_seconds(room, index)*0.5); artifacts.screenshot("odin_pp_mechanics_lab_lift_nemico.png") }
			rode = true
		} else if rode { break }
	}
	foe := mechanics_lab_enemy(room, chaser)
	if !rode || foe == nil || foe.position.layer != grid.GROUND_LAYER || game.cell_height(room, foe.position) != 14 {
		fmt.eprintln("mechanics lab: the foe did not ride the shaft up to the plateau"); return false
	}

	render.reset_tactical_orbit(&renderer.tactical.world_orbit)
	// The fight back, as F5 brings it, for whatever comes after.
	game.destroy_room(room)
	player.health = player.stats.max_health
	rebuilt, built = run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG)
	if !built { fmt.eprintln("mechanics lab: the arena was not rebuilt after the lifts"); return false }
	room^ = rebuilt
	render.clear_event_animations(renderer)
	controller^ = {was_focused = true}
	for _ in 0..<12 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	return true
}
