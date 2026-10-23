package game

import grid "../engine/grid"

// What the player sets down on the floor of a tactical room for a while: the
// CANNONE and the CANNONE LASER (cannon.odin) and the BUCO NERO
// (black_hole.odin). Each is a Grid_Object that lives `life` world beats and
// acts at each beat (continue_tactical_pulse), then goes. Alike to the Tesla
// Coil they stand on a free cell: walkable floor, no cover, no object, no trap,
// no body (the player's and the foes') and never under the Pinball's ball.

MAX_CANNONS :: 2
MAX_BLACK_HOLES :: 2
// The beats of one party of both: the cannons shoot, the holes pull, at the
// world's own second.
EMPLACEMENT_BEAT_SECONDS :: 1

emplacement_kind :: proc(kind: Grid_Object_Kind) -> bool {
	return kind == .Field_Cannon || kind == .Devouring_Hole
}

emplacement_count :: proc(room: ^Room, kind: Grid_Object_Kind) -> (count: int) {
	if room == nil { return }
	for object in room.objects { if object.kind == kind { count += 1 } }
	return
}

// Whether a `kind` can be set down on `cell` now.
emplacement_can_place :: proc(room: ^Room, kind: Grid_Object_Kind, cell: grid.Position) -> bool {
	if room == nil || room.player == nil || room.level_data == nil || room.phase != .Combat || !emplacement_kind(kind) ||
	   len(room.objects) >= MAX_GRID_OBJECTS_PER_ROOM || room.next_object_id == 0 || room.next_object_id == max(u32) ||
	   !base_cell_is_walkable(room, cell) || obstacle_at(room, cell) || cell == room.exit_position || cell == room.player.position {
		return false
	}
	if _, occupied := object_index_at(room, cell); occupied { return false }
	if _, trapped := trap_index_at(room, cell); trapped { return false }
	if _, occupied := enemy_index_at(room, cell); occupied { return false }
	if pinball_covers_cell(room, cell) { return false }
	limit := MAX_CANNONS if kind == .Field_Cannon else MAX_BLACK_HOLES
	return emplacement_count(room, kind) < limit
}

// Sets one down. `power` is its damage a beat, `seconds` its beats, `way` a
// cannon's facing, `radius` a hole's damage radius (its pull reaches one more),
// `laser` a cannon's beam. The event's `amount` is the power, `duration` the
// way (+4 for a laser) or the radius.
@(private)
place_emplacement :: proc(room: ^Room, kind: Grid_Object_Kind, cell: grid.Position, power, seconds, radius: i32, way: Move_Direction,
	laser: bool, report: ^Action_Report) -> bool {
	if report == nil || power <= 0 || seconds <= 0 || !emplacement_can_place(room, kind, cell) { return false }
	object := Grid_Object{
		id = room.next_object_id, kind = kind, position = cell,
		life = seconds, power = power, radius = radius, facing = way, laser = laser,
	}
	room.next_object_id += 1
	append(&room.objects, object)
	duration := i32(way)+(4 if laser else 0) if kind == .Field_Cannon else radius
	record_report_event(report, {kind = .Object_Spawned, source = PLAYER_ENTITY, target = object_entity(object.id),
		object_kind = kind, from_position = cell, to_position = cell, amount = power, duration = duration,
		card_definition = .Laser_Cannon if laser else (.Field_Cannon if kind == .Field_Cannon else .Devouring_Hole)})
	return true
}

// The foes in play on the floor, by ID.
@(private)
emplacement_foe_ids :: proc(room: ^Room) -> (ids: [MAX_ENEMIES_PER_ROOM]u32, count: int) {
	for enemy in room.enemies {
		if enemy_is_out_of_play(room, enemy.id) || count >= MAX_ENEMIES_PER_ROOM { continue }
		ids[count] = enemy.id
		count += 1
	}
	for i in 1..<max(count, 1) {
		id, at := ids[i], i
		for at > 0 && ids[at-1] > id { ids[at] = ids[at-1]; at -= 1 }
		ids[at] = id
	}
	return
}

// Each living emplacement's beat, from the pulse (tactical.odin).
emplacement_beat :: proc(room: ^Room, pulse: ^Pulse_Report) {
	if room == nil || pulse == nil || room.phase != .Combat { return }
	cannon_beat(room, pulse)
	if room.phase != .Combat { return }
	black_hole_beat(room, pulse)
}
