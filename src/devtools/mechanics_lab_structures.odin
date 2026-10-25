package devtools
import run_session "../run"

import "core:fmt"
import app "../engine/app"
import game "../game"
import grid "../engine/grid"
import level "../level"
import render "../render"

// STRUCTURES (level/structure.odin, render/structure_diorama.odin) in the lab's third arena
// (run.Mechanics_Lab_Arena.Structures, F3): the catalog of buildings and objects on the
// board, the cottage in its four turns, a hut the robot walks up to (stills at 6, 4, 2 and
// 1 cell, on the threshold, inside and outside again), the walls that stop the step and
// the door that lets it through. Stills odin_pp_mechanics_lab_structures_*.png.

// The robot at `at` for a while, so that the buildings' opacity has settled, then a still.
@(private = "file")
mechanics_lab_stand :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, at: grid.Position, name: cstring) {
	room.player.position = at
	for _ in 0..<40 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	mechanics_lab_still(window, renderer, room, 0, name)
}

mechanics_lab_structures :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, data: ^level.Level,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	// The arena of structures, as F3 brings it.
	game.destroy_room(room)
	player.health = player.stats.max_health
	rebuilt, built := run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG, .Structures)
	if !built { fmt.eprintln("mechanics lab: the arena of structures was not built"); return false }
	room^ = rebuilt
	render.clear_event_animations(renderer)
	controller^ = {was_focused = true}
	for foe in room.enemies { mechanics_lab_hold(room, foe.id) }
	// Further back than the lab's usual view: a building and its surroundings fit in it.
	renderer.tactical.world_orbit.distance = 26
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	if level.structure_count(data) != len(run_session.MECHANICS_LAB_STRUCTURES) {
		fmt.eprintln("mechanics lab: the arena of structures does not hold the whole catalog"); return false
	}
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_structures_arena.png")

	// The cottage in its four turns, along the bottom of the arena.
	mechanics_lab_stand(window, renderer, room, controller, cards, buffer, {x = 14, y = 20}, "odin_pp_mechanics_lab_structures_rotations.png")
	// The objects: the cart, the fountain, the statue and the machine in a row.
	mechanics_lab_stand(window, renderer, room, controller, cards, buffer, {x = 10, y = 15}, "odin_pp_mechanics_lab_structures_objects.png")

	// The hut at (12, 3), door at (14, 6): the robot walks up to it from the south.
	hut := -1
	for placed, index in data.structures { if placed.id == .Hut { hut = index } }
	if hut < 0 { fmt.eprintln("mechanics lab: no hut in the arena"); return false }
	// Every cell of the hut counts: the walls stop the step, the door lets it through.
	room.player.position = {x = 13, y = 7}
	mechanics_lab_wait_free(window, renderer, room, controller, cards, buffer)
	if game.try_move_player(room, .North) != .Blocked || room.player.position != (grid.Position{x = 13, y = 7}) {
		fmt.eprintln("mechanics lab: the hut's wall did not stop the step"); return false
	}
	room.player.position = {x = 14, y = 7}
	mechanics_lab_wait_free(window, renderer, room, controller, cards, buffer)
	if game.try_move_player(room, .North) != .Moved || room.player.position != (grid.Position{x = 14, y = 6}) {
		fmt.eprintln("mechanics lab: the hut's door did not let the step through"); return false
	}
	// The way the opacity goes: whole at six cells, gone on the threshold, whole again inside.
	stages := [?]struct { at: grid.Position, name: cstring, stage: game.Structure_Stage }{
		{{x = 14, y = 13}, "odin_pp_mechanics_lab_structures_hut_6.png", .Far},
		{{x = 14, y = 11}, "odin_pp_mechanics_lab_structures_hut_4.png", .Approaching},
		{{x = 14, y = 9}, "odin_pp_mechanics_lab_structures_hut_2.png", .Approaching},
		{{x = 14, y = 8}, "odin_pp_mechanics_lab_structures_hut_1.png", .Approaching},
		{{x = 14, y = 7}, "odin_pp_mechanics_lab_structures_hut_soglia.png", .Threshold},
		{{x = 14, y = 4}, "odin_pp_mechanics_lab_structures_hut_dentro.png", .Inside},
		{{x = 14, y = 9}, "odin_pp_mechanics_lab_structures_hut_fuori.png", .Approaching},
	}
	previous := f32(1)
	for step, i in stages {
		mechanics_lab_stand(window, renderer, room, controller, cards, buffer, step.at, step.name)
		view := game.structure_visibility(data, hut, {f32(step.at.x)+0.5, f32(step.at.y)+0.5})
		if view.stage != step.stage { fmt.eprintln("mechanics lab: the hut at", step.at, "is", view.stage, "not", step.stage); return false }
		// Walking in, the envelope only fades, until the inside.
		if i >= 1 && i <= 4 && view.opacity > previous { fmt.eprintln("mechanics lab: the hut grew more solid walking in"); return false }
		if i <= 4 { previous = view.opacity }
		if step.stage == .Inside && (view.opacity != 1 || view.roof) { fmt.eprintln("mechanics lab: inside, the walls are not whole or the roof shows"); return false }
	}

	render.reset_tactical_orbit(&renderer.tactical.world_orbit)
	// The fight back, as F5 brings it, for the act after this one.
	game.destroy_room(room)
	player.health = player.stats.max_health
	rebuilt, built = run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG)
	if !built { fmt.eprintln("mechanics lab: the arena was not rebuilt after the structures"); return false }
	room^ = rebuilt
	render.clear_event_animations(renderer)
	controller^ = {was_focused = true}
	for _ in 0..<12 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	return true
}
