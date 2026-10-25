package devtools
import artifacts "artifacts"
import run_session "../run"

import "core:fmt"
import app "../engine/app"
import game "../game"
import grid "../engine/grid"
import level "../level"
import render "../render"

// THE SPIRAL MOUNTAIN (level/mountain.odin) in the lab's fourth arena (run.Mechanics_Lab_Arena.Mountain, F3):
// the player walks the whole path from the ground to the summit a step at a time, a cliff between two laps
// stops the walk, the archer waiting at the top is pushed off and falls the whole mountain's height (the
// fall costs at most ten), and the robot is seen from eight places on the climb, behind the mountain
// and before it. Stills odin_pp_mechanics_lab_mountain_*.png.

Mountain_Step :: struct { offset: grid.Position, direction: game.Move_Direction }

MOUNTAIN_LAB_STEPS := [4]Mountain_Step{
	{{x = 0, y = -1}, .North}, {{x = 1, y = 0}, .East}, {{x = 0, y = 1}, .South}, {{x = -1, y = 0}, .West},
}

@(private = "file")
mountain_lab_cell :: proc(offset: grid.Position) -> grid.Position {
	centre := run_session.MECHANICS_LAB_MOUNTAIN_CENTER
	return grid.offset(centre, offset.x, offset.y)
}

// The shortest walk, a step of one height at a time, from `from` to `to` (empty if there is none).
mountain_lab_route :: proc(room: ^game.Room, from, to: grid.Position) -> [dynamic]game.Move_Direction {
	width, height := room.level_data.tiles.width, room.level_data.tiles.height
	came := make([]int, width*height, context.temp_allocator)
	for i in 0..<width*height { came[i] = -1 }
	queue := make([dynamic]grid.Position, context.temp_allocator)
	append(&queue, from)
	came[from.y*width+from.x] = from.y*width+from.x
	for head := 0; head < len(queue); head += 1 {
		cell := queue[head]
		if cell == to { break }
		for step in MOUNTAIN_LAB_STEPS {
			next := grid.offset(cell, step.offset.x, step.offset.y)
			if next.x < 0 || next.y < 0 || next.x >= width || next.y >= height { continue }
			if came[next.y*width+next.x] >= 0 || (next != to && game.cell_blocks_movement(room, next)) || game.step_height_blocked(room, cell, next) { continue }
			// A foe in the way is not a step: walking into it is a blow.
			if _, occupied := game.enemy_index_at(room, next); occupied { continue }
			came[next.y*width+next.x] = cell.y*width+cell.x
			append(&queue, next)
		}
	}
	route := make([dynamic]game.Move_Direction, context.temp_allocator)
	if came[to.y*width+to.x] < 0 { return route }
	for cell := to; cell != from; {
		previous := came[cell.y*width+cell.x]
		before := grid.Position{x = previous%width, y = previous/width}
		for step in MOUNTAIN_LAB_STEPS {
			if before.x+step.offset.x == cell.x && before.y+step.offset.y == cell.y { inject_at(&route, 0, step.direction) }
		}
		cell = before
	}
	return route
}

// One step of the player, as the lane makes it (the next call waits for its slide to end).
mountain_lab_step :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, direction: game.Move_Direction) -> bool {
	mechanics_lab_wait_free(window, renderer, room, controller, cards, buffer)
	return run_session.commit_gameplay_command(room, renderer, cards, {kind = .Move, origin_phase = .Combat, direction = direction})
}

mechanics_lab_mountain :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, data: ^level.Level,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	game.destroy_room(room)
	player.health = player.stats.max_health
	rebuilt, built := run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG, .Mountain)
	if !built { fmt.eprintln("mechanics lab: the arena of the mountain was not built"); return false }
	room^ = rebuilt
	render.clear_event_animations(renderer)
	controller^ = {was_focused = true}
	for foe in room.enemies { mechanics_lab_hold(room, foe.id) }
	// Further back than the lab's usual view: the mountain and its surroundings fit in it.
	renderer.tactical.world_orbit.distance = 34
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	summit := mountain_lab_cell(level.mountain_summit())
	if game.cell_height(room, player.position) != 0 || game.cell_height(room, summit) != i32(level.MOUNTAIN_TOP) {
		fmt.eprintln("mechanics lab: the arena of the mountain is not the one drawn"); return false
	}
	archer := game.Enemy{}
	for foe in room.enemies { if foe.archetype == .Archer { archer = foe } }
	if archer.id == 0 || game.cell_height(room, archer.position) != i32(level.MOUNTAIN_TOP) {
		fmt.eprintln("mechanics lab: the archer is not at the summit"); return false
	}
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_mountain_arena.png")

	// The whole climb: every step of the walk is at most one step up or down, and the summit is reached.
	route := mountain_lab_route(room, player.position, summit)
	if len(route) < 100 { fmt.eprintln("mechanics lab: the walk to the summit is only", len(route), "cells"); return false }
	stills := [?]int{len(route)/4, len(route)/2, len(route)*3/4}
	names := [?]cstring{"odin_pp_mechanics_lab_mountain_quarter.png", "odin_pp_mechanics_lab_mountain_half.png", "odin_pp_mechanics_lab_mountain_three_quarters.png"}
	blocked_checked := false
	// The foes are held at every step, and the walk is planned afresh from where the player stands, so that
	// one that wakes and gets in the way does not matter.
	for index := 0; player.position != summit && index < 3*len(route); index += 1 {
		for foe in room.enemies { mechanics_lab_hold(room, foe.id) }
		walk := mountain_lab_route(room, player.position, summit)
		if len(walk) == 0 { fmt.eprintln("mechanics lab: no way up from", player.position); return false }
		direction := walk[0]
		before := player.position
		if !mountain_lab_step(window, renderer, room, controller, cards, buffer, direction) {
			fmt.eprintln("mechanics lab: step", index, "of the climb was refused at", before); return false
		}
		mechanics_lab_wait_free(window, renderer, room, controller, cards, buffer)
		if player.position == before || abs(game.cell_height(room, player.position)-game.cell_height(room, before)) > 1 {
			fmt.eprintln("mechanics lab: the climb did not step at", before, "->", player.position, "going", direction, "heights", game.cell_height(room, before), game.cell_height(room, player.position)); return false
		}
		for still, which in stills {
			if index+1 == still {
				for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
				mechanics_lab_still(window, renderer, room, 0, names[which])
			}
		}
		// Halfway up, the next lap's cliff stops the walk.
		if index >= len(route)/2 && !blocked_checked {
			for step in MOUNTAIN_LAB_STEPS {
				next := grid.offset(player.position, step.offset.x, step.offset.y)
				if _, occupied := game.enemy_index_at(room, next); occupied { continue }
				if !game.cell_blocks_movement(room, next) && game.step_height_blocked(room, player.position, next) {
					mechanics_lab_wait_free(window, renderer, room, controller, cards, buffer)
					at := player.position
					if game.try_move_player(room, step.direction) != .Blocked || player.position != at {
						fmt.eprintln("mechanics lab: the lap's cliff did not stop the walk at", at); return false
					}
					blocked_checked = true
					break
				}
			}
		}
	}
	if player.position != summit { fmt.eprintln("mechanics lab: the climb ended at", player.position, "not", summit); return false }
	if !blocked_checked { fmt.eprintln("mechanics lab: no cliff beside the climb's second half"); return false }
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_mountain_summit.png")

	// The archer pushed off the summit: down the cliff to the lowest cell beside it, the fall costs the drop less one
	// (at most ten, the most a fall costs).
	archer = mechanics_lab_enemy(room, archer.id)^
	landing, lowest := grid.Position{}, i32(1<<20)
	for step in MOUNTAIN_LAB_STEPS {
		next := grid.offset(archer.position, step.offset.x, step.offset.y)
		if game.cell_blocks_movement(room, next) || next == player.position { continue }
		if h := game.cell_height(room, next); h < lowest { landing, lowest = next, h }
	}
	drop := game.cell_height(room, archer.position)-lowest
	if drop < 2 { fmt.eprintln("mechanics lab: no cliff beside the archer"); return false }
	expected := i32(min(int(drop)-1, 10))
	before_health := archer.health
	query := game.query_entity_movement(room, game.enemy_entity(archer.id), landing)
	if !game.movement_query_is_clear(&query) { fmt.eprintln("mechanics lab: the archer cannot be pushed off the summit"); return false }
	presentation := render.capture_room_presentation(room)
	push := game.make_action(.Move, game.PLAYER_ENTITY, game.entity_target(game.enemy_entity(archer.id)), .Entity)
	if !game.add_effect(&push, game.move_effect(game.enemy_entity(archer.id), landing)) { return false }
	report := game.resolve_action(room, &push)
	if !report.accepted { fmt.eprintln("mechanics lab: the push was refused"); return false }
	game.append_event_log(room.recent_events, &report.events)
	after := render.capture_room_presentation(room)
	if !render.begin_renderer_event_timeline(renderer, presentation, room.recent_events, &after) { return false }
	fallen := mechanics_lab_enemy(room, archer.id)
	if fallen == nil || fallen.position != landing || fallen.health != before_health-expected {
		fmt.eprintln("mechanics lab: the fall cost", before_health-(fallen.health if fallen != nil else 0), "instead of", expected); return false
	}
	for _ in 0..<14 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	artifacts.screenshot("odin_pp_mechanics_lab_mountain_fall.png")

	// The robot seen from eight places of the climb, behind the mountain (to the camera) and before it.
	for index in 0..<8 {
		laps := f32(index)*f32(level.MOUNTAIN_LAPS)/8+0.1
		room.player.position = mountain_lab_cell(level.mountain_path_cell(laps))
		for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
		mechanics_lab_still(window, renderer, room, 0, fmt.ctprintf("odin_pp_mechanics_lab_mountain_view_%d.png", index))
	}

	render.reset_tactical_orbit(&renderer.tactical.world_orbit)
	// The fight back, as F5 brings it, for the act after this one.
	game.destroy_room(room)
	player.health = player.stats.max_health
	rebuilt, built = run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG)
	if !built { fmt.eprintln("mechanics lab: the arena was not rebuilt after the mountain"); return false }
	room^ = rebuilt
	render.clear_event_animations(renderer)
	controller^ = {was_focused = true}
	for _ in 0..<12 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	return true
}
