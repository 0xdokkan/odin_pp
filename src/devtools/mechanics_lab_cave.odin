package devtools
import run_session "../run"

import "core:fmt"
import app "../engine/app"
import game "../game"
import grid "../engine/grid"
import level "../level"
import render "../render"

// A CAVE (level/cave.odin) in the lab's fifth arena (run.Mechanics_Lab_Arena.Cave, F3): the plan's rooms and galleries with its
// foes in them, walked from the arrival to the secret at the far end and back, a step at a time (the foes held), with a still in
// each room. Stills odin_pp_mechanics_lab_cave_*.png.

@(private = "file")
cave_lab_walk :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, to: grid.Position, name: cstring, still_at: [2]grid.Position,
	still_names: [2]cstring) -> bool {
	player := room.player
	stills_taken: [2]bool
	for step := 0; player.position != to && step < 400; step += 1 {
		for foe in room.enemies { mechanics_lab_hold(room, foe.id) }
		walk := mountain_lab_route(room, player.position, to)
		if len(walk) == 0 { fmt.eprintln("mechanics lab: no way through the cave from", player.position, "to", to); return false }
		before := player.position
		if !mountain_lab_step(window, renderer, room, controller, cards, buffer, walk[0]) { fmt.eprintln("mechanics lab: a step in the cave was refused at", before); return false }
		mechanics_lab_wait_free(window, renderer, room, controller, cards, buffer)
		if player.position == before { fmt.eprintln("mechanics lab: the walk in the cave did not step at", before); return false }
		for at, i in still_at {
			if !stills_taken[i] && max(abs(player.position.x-at.x), abs(player.position.y-at.y)) <= 1 {
				stills_taken[i] = true
				for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
				mechanics_lab_still(window, renderer, room, 0, still_names[i])
			}
		}
	}
	if player.position != to { fmt.eprintln("mechanics lab: the walk ended at", player.position, "not", to); return false }
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	mechanics_lab_still(window, renderer, room, 0, name)
	return true
}

mechanics_lab_cave :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, data: ^level.Level,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	game.destroy_room(room)
	player.health = player.stats.max_health
	rebuilt, built := run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG, .Cave)
	if !built { fmt.eprintln("mechanics lab: the arena of the cave was not built"); return false }
	room^ = rebuilt
	render.clear_event_animations(renderer)
	controller^ = {was_focused = true}
	for foe in room.enemies { mechanics_lab_hold(room, foe.id) }
	renderer.tactical.world_orbit.distance = 32
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	plan := level.cave_plan(run_session.MECHANICS_LAB_CAVE_SEED)
	arrival := grid.Position{plan.arrival.x+1, plan.arrival.y+1}
	secret := grid.Position{plan.secret.x+1, plan.secret.y+1}
	if player.position != arrival { fmt.eprintln("mechanics lab: the player is not at the cave's arrival:", player.position, arrival); return false }
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_cave_arrival.png")

	// The rock stops the step: the cell north or south of the arrival's row that is rock, tried from beside it.
	blocked := false
	for step in MOUNTAIN_LAB_STEPS {
		next := grid.Position{player.position.x+step.offset.x, player.position.y+step.offset.y}
		if game.cell_blocks_movement(room, next) {
			if game.try_move_player(room, step.direction) != .Blocked || player.position != arrival { fmt.eprintln("mechanics lab: the cave's rock did not stop the step"); return false }
			blocked = true
			break
		}
	}
	if !blocked { fmt.eprintln("mechanics lab: no rock beside the arrival"); return false }

	// To the secret and back, with a still in the first room that has foes and at the gallery to the last room.
	rooms := [2]grid.Position{{plan.anchors[0].x+1, plan.anchors[0].y+1}, {plan.anchors[plan.groups-1].x+1, plan.anchors[plan.groups-1].y+1}}
	names := [2]cstring{"odin_pp_mechanics_lab_cave_first_room.png", "odin_pp_mechanics_lab_cave_last_room.png"}
	if !cave_lab_walk(window, renderer, room, controller, cards, buffer, secret, "odin_pp_mechanics_lab_cave_secret.png", rooms, names) { return false }
	if !cave_lab_walk(window, renderer, room, controller, cards, buffer, arrival, "odin_pp_mechanics_lab_cave_back.png", rooms, {"odin_pp_mechanics_lab_cave_back_last.png", "odin_pp_mechanics_lab_cave_back_first.png"}) { return false }

	render.reset_tactical_orbit(&renderer.tactical.world_orbit)
	// The fight back, as F5 brings it, for the act after this one.
	game.destroy_room(room)
	player.health = player.stats.max_health
	rebuilt, built = run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG)
	if !built { fmt.eprintln("mechanics lab: the arena was not rebuilt after the cave"); return false }
	room^ = rebuilt
	render.clear_event_animations(renderer)
	controller^ = {was_focused = true}
	for _ in 0..<12 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	return true
}
