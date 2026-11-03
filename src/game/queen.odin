package game

import grid "../engine/grid"
import level "../level"

// REGINA (docs/piano-ia.md, Fase 11): a chess queen set down like the Cannone, on a free cell one to three cells away, one
// at a time. She takes her cell and stops the steps of everybody, not the sight; nothing strikes or breaks her; she stands
// 20 world beats (`life`), then goes, as she does when the fight ends.
//
// - Her lines: the 8 ways of the chess queen, as long as the room. Walls, covers, solid objects and bodies (the player's
//   too) stop them: the first foe on a line is the one she can reach.
// - Her blow: as soon as a foe is on a line and she is ready, she runs along it to the cell next to him, stays there and
//   strikes for 4 (`power`), then waits 2 world seconds. Of several foes the nearest along its line; of equals the first
//   in the fixed order of the lines (north, north-east, east...): always the same.
// - When she looks: every frame the world runs, as the arrows fly (tactical_flights_due, a world command), and before
//   each beat (fly_enemy_flights): so «as soon as» holds for a foe pushed by a card too.
//
// Her wait lives in the player's clock (Tactical_State.queen_wait), there being one of her, so the room keeps its size.

QUEEN_SECONDS :: i32(20)
QUEEN_BASE_DAMAGE :: i32(4)
QUEEN_MAX_UPGRADE_LEVEL :: i32(2)
MAX_QUEENS :: 1
QUEEN_WAIT_SECONDS :: f32(2)
// How far she looks, along any line, in cells.
QUEEN_REACH :: 24

// The steps of her lines, in their fixed order.
QUEEN_LINES := [8]grid.Position{{x = 0, y = -1}, {x = 1, y = -1}, {x = 1, y = 0}, {x = 1, y = 1}, {x = 0, y = 1}, {x = -1, y = 1}, {x = -1, y = 0}, {x = -1, y = -1}}

@(private)
place_queen_effect :: proc(power, seconds: i32) -> Effect {
	return {kind = .Place_Queen, target = PLAYER_ENTITY, amount = power, duration = seconds}
}

// Sets her down, ready.
@(private)
place_queen :: proc(room: ^Room, cell: grid.Position, power, seconds: i32, report: ^Action_Report) -> bool {
	if !place_emplacement(room, .Queen, cell, power, seconds, 0, .North, false, report) { return false }
	room.player.tactical.queen_wait = 0
	return true
}

// The foe a line from `origin` reaches first and how many cells along it he stands.
@(private = "file")
queen_line_foe :: proc(room: ^Room, origin, step: grid.Position) -> (foe, distance: int, found: bool) {
	previous := origin
	for cells in 1..=QUEEN_REACH {
		cell := grid.offset(origin, step.x*cells, step.y*cells)
		if !level.layer_contains(room.level_data, cell) || step_height_blocked(room, previous, cell) { return }
		if index, standing := enemy_index_at(room, cell); standing && !enemy_is_out_of_play(room, room.enemies[index].id) {
			return index, cells, true
		}
		if cell == room.player.position || cell_blocks_movement(room, cell) { return }
		previous = cell
	}
	return
}

// The foe she would go for from `origin`: the nearest along his line, the first line of equals.
@(private)
queen_choice :: proc(room: ^Room, origin: grid.Position) -> (foe, distance: int, step: grid.Position, found: bool) {
	for line in QUEEN_LINES {
		index, cells, seen := queen_line_foe(room, origin, line)
		if seen && (!found || cells < distance) { foe, distance, step, found = index, cells, line, true }
	}
	return
}

// How many foes the lines from `cell` reach (the IA's first guess of where to set her).
queen_lines_seen :: proc(room: ^Room, cell: grid.Position) -> (count: int) {
	for line in QUEEN_LINES {
		if _, _, seen := queen_line_foe(room, cell, line); seen { count += 1 }
	}
	return
}

@(private = "file")
queen_index :: proc(room: ^Room) -> (index: int, found: bool) {
	for object, at in room.objects { if object.kind == .Queen { return at, true } }
	return
}

// Whether she stands ready with a foe on a line.
@(private)
queen_is_due :: proc(room: ^Room) -> bool {
	if room.player.tactical.queen_wait > 0 { return false }
	index, standing := queen_index(room)
	if !standing { return false }
	_, _, _, found := queen_choice(room, room.objects[index].position)
	return found
}

// She runs to the cell next to her foe and strikes (fly_enemy_flights).
@(private)
queen_strike :: proc(room: ^Room, pulse: ^Pulse_Report) {
	if !queen_is_due(room) { return }
	index, _ := queen_index(room)
	queen := &room.objects[index]
	foe, distance, step, _ := queen_choice(room, queen.position)
	id, power, from := queen.id, queen.power, queen.position
	stop := grid.offset(from, step.x*(distance-1), step.y*(distance-1))
	queen.position = stop
	if stop != from {
		record_event(&pulse.events, {kind = .Queen_Ran, source = SYSTEM_ENTITY, target = object_entity(id), object_kind = .Queen,
			from_position = from, to_position = stop})
	}
	struck := enemy_entity(room.enemies[foe].id)
	record_event(&pulse.events, {kind = .Queen_Struck, source = object_entity(id), target = struck, object_kind = .Queen,
		from_position = stop, to_position = room.enemies[foe].position, amount = power})
	room.player.tactical.queen_wait = QUEEN_WAIT_SECONDS
	action := make_action(.Trigger, object_entity(id))
	added := add_effect(&action, damage_effect(struck, power))
	assert(added)
	report := resolve_action(room, &action)
	merge_action_report(pulse, &report)
}

// Her beat, from the pulse: a beat less; at nothing she goes.
@(private)
queen_beat :: proc(room: ^Room, pulse: ^Pulse_Report) {
	index, standing := queen_index(room)
	if !standing { return }
	queen := &room.objects[index]
	queen.life -= 1
	if queen.life > 0 { return }
	record_event(&pulse.events, {kind = .Queen_Closed, source = SYSTEM_ENTITY, target = object_entity(queen.id), object_kind = .Queen,
		from_position = queen.position, to_position = queen.position})
	remove_grid_object(room, index)
}

// The fight over, she goes.
@(private)
queen_end_combat :: proc(room: ^Room) {
	room.player.tactical.queen_wait = 0
	if index, standing := queen_index(room); standing { remove_grid_object(room, index) }
}
