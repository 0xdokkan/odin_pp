package devtools
import artifacts "artifacts"
import run_session "../run"

import "core:fmt"
import app "../engine/app"
import game "../game"
import grid "../engine/grid"
import level "../level"
import render "../render"

// LAYERS (game/layers.odin, Fase 3 of docs/piano-profondita.md) in the lab's seventh arena (run.Mechanics_Lab_Arena.Layers,
// F3): the player walks up a ramp onto the bridge, a fire is cast from it onto the road, the foe on the bridge is pushed
// off it and falls, the player walks under the bridge, into the cave through its mouth and up the ladder on the hill's
// cliff. With the Fase 4's view (game/layer_view.odin): a foe hidden under the deck shows its outline to the player on
// the bridge, the pointer reaches a road's cell through the deck faded over the player, and a foe stands on the bridge
// over him. Stills odin_pp_mechanics_lab_layers_*.png.

// The shortest walk from `from` to `to` across the layers, a step at a time as the player makes it (game.walk_step: a
// ramp, a mouth, a ladder), round the foes (empty if there is none); with `avoid_lifts`, round the lifts' landings too
// (a step onto one is a call or a ride: mechanics_lab_lifts.odin).
@(private)
layers_lab_route :: proc(room: ^game.Room, from, to: grid.Position, avoid_lifts := false) -> [dynamic]game.Move_Direction {
	cells := game.room_table_cells(room.level_data)
	came := make([]int, cells, context.temp_allocator)
	for i in 0..<cells { came[i] = -1 }
	queue := make([dynamic]grid.Position, context.temp_allocator)
	start, _ := game.room_table_index(room, from)
	came[start] = start
	append(&queue, from)
	for head := 0; head < len(queue); head += 1 {
		cell := queue[head]
		if cell == to { break }
		for step in MOUNTAIN_LAB_STEPS {
			next := game.walk_step(room, cell, step.offset)
			index, inside := game.room_table_index(room, next)
			if !inside || came[index] >= 0 || game.cell_blocks_movement(room, next) { continue }
			if !game.is_ladder_move(room, cell, next) && game.step_height_blocked(room, cell, next) { continue }
			// A foe in the way is not a step: walking into it is a blow.
			if _, occupied := game.enemy_index_at(room, next); occupied { continue }
			if avoid_lifts && next != to {
				if _, _, landing := level.lift_at(room.level_data, next); landing { continue }
			}
			came[index], _ = game.room_table_index(room, cell)
			append(&queue, next)
		}
	}
	route := make([dynamic]game.Move_Direction, context.temp_allocator)
	end, inside := game.room_table_index(room, to)
	if !inside || came[end] < 0 { return route }
	for cell := to; cell != from; {
		index, _ := game.room_table_index(room, cell)
		before := game.room_table_cell(room, came[index])
		for step in MOUNTAIN_LAB_STEPS {
			if before.x+step.offset.x == cell.x && before.y+step.offset.y == cell.y { inject_at(&route, 0, step.direction) }
		}
		cell = before
	}
	return route
}

// Sets a foe down on `cell` (a teleport, as the board shows one), the board then left to show it.
@(private = "file")
layers_lab_place :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, archetype: game.Enemy_Archetype, cell: grid.Position) -> bool {
	foe := game.Enemy{}
	for enemy in room.enemies { if enemy.archetype == archetype { foe = enemy } }
	if foe.id == 0 { fmt.eprintln("mechanics lab: no", archetype, "to set down on", cell); return false }
	game.clear_event_log(room.recent_events)
	presentation := render.capture_room_presentation(room)
	place := game.make_action(.Move, game.PLAYER_ENTITY, game.entity_target(game.enemy_entity(foe.id)), .Entity)
	if !game.add_effect(&place, game.move_effect(game.enemy_entity(foe.id), cell, .Teleport)) { return false }
	report := game.resolve_action(room, &place)
	if !report.accepted { fmt.eprintln("mechanics lab: the", archetype, "was not set down on", cell); return false }
	game.append_event_log(room.recent_events, &report.events)
	after := render.capture_room_presentation(room)
	if !render.begin_renderer_event_timeline(renderer, presentation, room.recent_events, &after) { return false }
	for _ in 0..<40 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	placed := mechanics_lab_enemy(room, foe.id)
	return placed != nil && placed.position == cell
}

// Walks the player to `to`, the foes held, and takes a still there.
@(private = "file")
layers_lab_walk :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, controller: ^run_session.Tactical_Controller,
	cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command, to: grid.Position, name: cstring) -> bool {
	player := room.player
	for step := 0; player.position != to && step < 200; step += 1 {
		for foe in room.enemies { mechanics_lab_hold(room, foe.id) }
		walk := layers_lab_route(room, player.position, to)
		if len(walk) == 0 { fmt.eprintln("mechanics lab: no way across the layers from", player.position, "to", to); return false }
		before := player.position
		if !mountain_lab_step(window, renderer, room, controller, cards, buffer, walk[0]) { fmt.eprintln("mechanics lab: a step across the layers was refused at", before); return false }
		mechanics_lab_wait_free(window, renderer, room, controller, cards, buffer)
		if player.position == before { fmt.eprintln("mechanics lab: the walk across the layers did not step at", before); return false }
	}
	if player.position != to { fmt.eprintln("mechanics lab: the walk across the layers ended at", player.position, "not", to); return false }
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	mechanics_lab_still(window, renderer, room, 0, name)
	return true
}

mechanics_lab_layers :: proc(window: ^app.Window, renderer: ^render.Renderer, room: ^game.Room, data: ^level.Level,
	controller: ^run_session.Tactical_Controller, cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) -> bool {
	player := room.player
	game.destroy_room(room)
	player.health = player.stats.max_health
	rebuilt, built := run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG, .Layers)
	if !built { fmt.eprintln("mechanics lab: the arena of the layers was not built"); return false }
	room^ = rebuilt
	render.clear_event_animations(renderer)
	controller^ = {was_focused = true}
	for foe in room.enemies { mechanics_lab_hold(room, foe.id) }
	renderer.tactical.world_orbit.distance = 30
	for _ in 0..<20 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	if player.position != run_session.MECHANICS_LAB_LAYERS_START || !level.has_layers(data) {
		fmt.eprintln("mechanics lab: the arena of the layers is not the one drawn"); return false
	}
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_layers_arena.png")

	// Up the west ramp and onto the bridge, to its south edge over the road.
	edge := grid.Position{x = 17, y = 15, layer = 1}
	if !layers_lab_walk(window, renderer, room, controller, cards, buffer, edge, "odin_pp_mechanics_lab_layers_bridge.png") { return false }

	// The brute under the deck, beside the player's column: the deck hides it, its outline shows; the road under the
	// player is a little darker (Fase 4).
	if !layers_lab_place(window, renderer, room, controller, cards, buffer, .Brute, {x = 16, y = 14}) { return false }
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_layers_foe_under.png")
	// The room's hologram: the player on the bridge's deck, the brute on the road under it.
	mechanics_lab_hologram_still(window, renderer, room, "odin_pp_mechanics_lab_layers_mappa.png")

	// A fire cast from the bridge onto the road below: the line goes down past the deck's edge.
	fire, has_fire := mechanics_lab_card_of(player, .Wildfire)
	if !has_fire { fmt.eprintln("mechanics lab: no Incendio in hand"); return false }
	definition, _ := game.card_definition_by_id(.Wildfire)
	road := grid.Position{x = 17, y = 18}
	evaluation := game.evaluate_card_targeting(room, fire, game.card_target_request_at(definition, road))
	if evaluation.error != .None || evaluation.query.error != .None {
		fmt.eprintln("mechanics lab: no cast from the bridge onto the road:", evaluation.error, evaluation.query.error); return false
	}
	player.deck.energy = player.deck.rules.max_energy
	mechanics_lab_capture_hits(window, renderer, room, fire.id, 0, road, "odin_pp_mechanics_lab_layers_shot.png")

	// The foe on the bridge's edge pushed off it: it falls twelve steps onto the road, and the fall costs ten.
	archer := game.Enemy{}
	for foe in room.enemies { if foe.archetype == .Archer { archer = foe } }
	if archer.id == 0 || archer.position.layer != 1 { fmt.eprintln("mechanics lab: the archer is not on the bridge"); return false }
	before_health := archer.health
	landing := grid.Position{x = archer.position.x, y = archer.position.y+1}
	query := game.query_entity_movement(room, game.enemy_entity(archer.id), landing)
	if !game.movement_query_is_clear(&query) || query.destination != landing { fmt.eprintln("mechanics lab: the archer cannot be pushed off the bridge"); return false }
	presentation := render.capture_room_presentation(room)
	push := game.make_action(.Move, game.PLAYER_ENTITY, game.entity_target(game.enemy_entity(archer.id)), .Entity)
	if !game.add_effect(&push, game.move_effect(game.enemy_entity(archer.id), landing)) { return false }
	report := game.resolve_action(room, &push)
	if !report.accepted { fmt.eprintln("mechanics lab: the push off the bridge was refused"); return false }
	game.append_event_log(room.recent_events, &report.events)
	after := render.capture_room_presentation(room)
	if !render.begin_renderer_event_timeline(renderer, presentation, room.recent_events, &after) { return false }
	fallen := mechanics_lab_enemy(room, archer.id)
	if fallen == nil || fallen.position != landing || fallen.health != before_health-game.HEIGHT_FALL_MAX_DAMAGE {
		fmt.eprintln("mechanics lab: the fall off the bridge cost", before_health-(fallen.health if fallen != nil else 0), "instead of", game.HEIGHT_FALL_MAX_DAMAGE); return false
	}
	for _ in 0..<14 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	artifacts.screenshot("odin_pp_mechanics_lab_layers_fall.png")

	// Down the east ramp and back along the road, under the bridge: its deck over the player fades.
	if !layers_lab_walk(window, renderer, room, controller, cards, buffer, {x = 17, y = 14}, "odin_pp_mechanics_lab_layers_under.png") { return false }

	// The pointer on a road's cell under the deck: it goes through the deck faded over the player (Fase 4).
	pointed := grid.Position{x = 19, y = 13}
	render.update_tactical_view(renderer, room, render.tactical_project(renderer, {f32(pointed.x)+0.5, f32(pointed.y)+0.5}, 0.03), true)
	if !renderer.has_hovered_cell || renderer.hovered_cell != pointed {
		fmt.eprintln("mechanics lab: the pointer under the deck picked", renderer.hovered_cell, "not", pointed); return false
	}
	// Shown with the Incendio aimed there: the cell under the deck is its target.
	player.deck.energy = player.deck.rules.max_energy
	mechanics_lab_capture_hits(window, renderer, room, fire.id, 0, pointed, "odin_pp_mechanics_lab_layers_pointer.png")

	// The archer set back on the bridge, over the player: it stands on the faded deck.
	if !layers_lab_place(window, renderer, room, controller, cards, buffer, .Archer, {x = 18, y = 14, layer = 1}) { return false }
	mechanics_lab_still(window, renderer, room, 0, "odin_pp_mechanics_lab_layers_foe_over.png")
	// Into the cave through its west mouth, beside the foe waiting in its room: the hill over it is half seen.
	if !layers_lab_walk(window, renderer, room, controller, cards, buffer, {x = 37, y = 7, layer = -1}, "odin_pp_mechanics_lab_layers_cave.png") { return false }
	// Out again, and up the ladder on the hill's west cliff, onto its top.
	if !layers_lab_walk(window, renderer, room, controller, cards, buffer, {x = 35, y = 4}, "odin_pp_mechanics_lab_layers_ladder.png") { return false }
	if game.cell_height(room, player.position) != 14 { fmt.eprintln("mechanics lab: the ladder did not reach the hill's top"); return false }

	render.reset_tactical_orbit(&renderer.tactical.world_orbit)
	// The fight back, as F5 brings it, for the act after this one.
	game.destroy_room(room)
	player.health = player.stats.max_health
	rebuilt, built = run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG)
	if !built { fmt.eprintln("mechanics lab: the arena was not rebuilt after the layers"); return false }
	room^ = rebuilt
	render.clear_event_animations(renderer)
	controller^ = {was_focused = true}
	for _ in 0..<12 { mechanics_lab_smoke_frame(window, renderer, room, controller, cards, buffer, 1.0/60.0) }
	return true
}
