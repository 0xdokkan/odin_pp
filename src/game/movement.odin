package game

import grid "../grid"

MAX_MOVEMENT_PATH_CELLS :: MAX_TARGETING_PATH_CELLS

Movement_Mode :: enum {
	Traverse,
	Teleport,
}

Movement_Error :: enum {
	None,
	Invalid_Room,
	Invalid_Mover,
	Same_Position,
	Destination_Out_Of_Bounds,
	Path_Not_Aligned,
	Path_Too_Long,
	Static_Blocker,
	Actor_Blocker,
	Object_Blocker,
}

Movement_Query :: struct {
	error:       Movement_Error,
	mode:        Movement_Mode,
	mover:       Entity_Ref,
	origin:      grid.Position,
	destination: grid.Position,
	cells:       [MAX_MOVEMENT_PATH_CELLS]grid.Position,
	count:       int,
	blocker:     grid.Position,
	has_blocker: bool,
}

movement_actor_blocks :: proc(
	room: ^Room,
	mover: Entity_Ref,
	position: grid.Position,
) -> bool {
	assert(room != nil && room.player != nil)
	if mover.kind == .Player {
		_, occupied := enemy_index_at(room, position)
		return occupied
	}
	if mover.kind == .Enemy {
		if room.player.position == position {
			return true
		}
		mover_index, found := enemy_index_by_id(room, mover.id)
		if !found {
			return true
		}
		_, occupied := enemy_index_at(room, position, mover_index)
		return occupied
	}
	if mover.kind == .Object {
		if room.player.position == position {
			return true
		}
		_, occupied := enemy_index_at(room, position)
		return occupied
	}
	return true
}

movement_object_blocks :: proc(
	room: ^Room,
	mover: Entity_Ref,
	position: grid.Position,
) -> bool {
	assert(room != nil)
	if mover.kind != .Object {
		return false
	}
	mover_index, found := object_index_by_id(room, mover.id)
	if !found {
		return true
	}
	_, occupied := object_index_at(room, position, mover_index)
	return occupied
}

movement_path_blocker :: proc(
	room: ^Room,
	origin: grid.Position,
	path: ^[MAX_MOVEMENT_PATH_CELLS]grid.Position,
	path_count: int,
) -> (blocker: grid.Position, found: bool) {
	if room == nil || path == nil || path_count < 0 || path_count > MAX_MOVEMENT_PATH_CELLS {
		return {}, true
	}
	previous := origin
	for position in path[:path_count] {
		if cell_blocks_movement(room, position) {
			return position, true
		}
		step_x := position.x-previous.x
		step_y := position.y-previous.y
		if step_x != 0 && step_y != 0 {
			side_x := grid.Position{x = previous.x+step_x, y = previous.y}
			side_y := grid.Position{x = previous.x, y = previous.y+step_y}
			if cell_blocks_movement(room, side_x) && cell_blocks_movement(room, side_y) {
				return side_x, true
			}
		}
		previous = position
	}
	return
}

query_entity_movement :: proc(
	room: ^Room,
	mover: Entity_Ref,
	destination: grid.Position,
	mode: Movement_Mode = .Traverse,
) -> (query: Movement_Query) {
	query.error = .Invalid_Room
	query.mode = mode
	query.mover = mover
	query.destination = destination
	if room == nil || room.player == nil || room.level_data == nil {
		return
	}
	query.error = .Invalid_Mover
	if mover.kind != .Player && mover.kind != .Enemy && mover.kind != .Object {
		return
	}
	if mover.kind == .Object {
		object_index, object_found := object_index_by_id(room, mover.id)
		if !object_found {
			return
		}
		definition, definition_found := grid_object_definition(room.objects[object_index].kind)
		if !definition_found || !definition.movable {
			return
		}
	}
	origin, found := entity_position(room, mover)
	if !found {
		return
	}
	return query_movement_from(room, mover, origin, destination, mode)
}

// The same rules from an explicit origin: the shadow of Movimento Ombra walks
// away from the body that stays at player.position (tactical_shadow.odin).
query_movement_from :: proc(
	room: ^Room,
	mover: Entity_Ref,
	origin, destination: grid.Position,
	mode: Movement_Mode = .Traverse,
) -> (query: Movement_Query) {
	query.error = .Invalid_Room
	query.mode = mode
	query.mover = mover
	query.destination = destination
	if room == nil || room.player == nil || room.level_data == nil {
		return
	}
	query.origin = origin
	query.error = .Same_Position
	if origin == destination {
		return
	}
	query.error = .Destination_Out_Of_Bounds
	if !grid.contains(&room.level_data.tiles, destination) {
		return
	}

	switch mode {
	case .Traverse:
		query.error = .Path_Not_Aligned
		if !targeting_line_is_aligned(origin, destination) {
			return
		}
		traced := false
		query.count, traced = trace_targeting_line(origin, destination, &query.cells)
		if !traced || query.count <= 0 {
			query.error = .Path_Too_Long
			return
		}
	case .Teleport:
		query.cells[0] = destination
		query.count = 1
	}

	if mode == .Traverse {
		if blocker, blocked := movement_path_blocker(
			room,
			origin,
			&query.cells,
			query.count,
		); blocked {
			query.error = .Static_Blocker
			query.blocker = blocker
			query.has_blocker = true
			return
		}
	} else if cell_blocks_movement(room, destination) {
		// Teleport checks only its landing cell; intermediate geometry is ignored.
		query.error = .Static_Blocker
		query.blocker = destination
		query.has_blocker = true
		return
	}
	for index in 0..<query.count {
		position := query.cells[index]
		if movement_object_blocks(room, mover, position) {
			query.error = .Object_Blocker
			query.blocker = position
			query.has_blocker = true
			return
		}
		if movement_actor_blocks(room, mover, position) {
			query.error = .Actor_Blocker
			query.blocker = position
			query.has_blocker = true
			return
		}
	}
	query.error = .None
	return
}

movement_query_is_clear :: proc(query: ^Movement_Query) -> bool {
	return query != nil && query.error == .None && query.count > 0 &&
	       query.count <= MAX_MOVEMENT_PATH_CELLS && !query.has_blocker
}

set_entity_position :: proc(room: ^Room, entity: Entity_Ref, position: grid.Position) {
	assert(room != nil && room.player != nil)
	switch entity.kind {
	case .Player:
		room.player.position = position
	case .Enemy:
		index, found := enemy_index_by_id(room, entity.id)
		assert(found)
		room.enemies[index].position = position
	case .Object:
		index, found := object_index_by_id(room, entity.id)
		assert(found)
		room.objects[index].position = position
	case .Trap, .System:
		unreachable()
	}
}

apply_movement_effect :: proc(
	room: ^Room,
	source: Entity_Ref,
	effect: Effect,
	report: ^Action_Report,
) {
	assert(room != nil && report != nil)
	query := query_entity_movement(
		room,
		effect.target,
		effect.destination,
		effect.movement_mode,
	)
	assert(movement_query_is_clear(&query))

	from_position := query.origin
	for index in 0..<query.count {
		to_position := query.cells[index]
		set_entity_position(room, effect.target, to_position)
		final_step := index == query.count-1
		movement_event_index := report.events.count
		record_report_event(report, {
			kind = .Moved if final_step else .Movement_Step,
			source = source,
			target = effect.target,
			from_position = from_position,
			to_position = to_position,
			area_mask = EVENT_TELEPORT_BIT if effect.movement_mode == .Teleport else 0,
		})
		movement_recorded := report.events.count > movement_event_index
		trigger_cell_entry(room, effect.target, report)
		if effect.target.kind == .Object {
			ignite_barrel_near_fire(room, effect.target.id, &report.events)
		}
		if !entity_exists(room, effect.target) {
			if !final_step && movement_recorded {
				report.events.events[movement_event_index].kind = .Moved
			}
			return
		}
		from_position = to_position
	}
	// LAZZO: whatever moves the player (a dodge, a push, a teleport) lets the
	// rope go (lasso.odin).
	if effect.target == PLAYER_ENTITY { release_lasso(room, report) }
}

// What a cell does to whoever enters it: a shock floor's trap, a hazard's
// bite, a pool's Veleno or a fire's Bruciatura. Every cell a movement enters,
// and the Lazzo's foe falling where it was held (lasso.odin).
trigger_cell_entry :: proc(room: ^Room, target: Entity_Ref, report: ^Action_Report) {
	trigger_shock_floors_on_entry(room, target, &report.events)
	trigger_cell_hazard(room, target, report)
	trigger_ground_on_entry(room, target, report)
}
