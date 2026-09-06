package game

import grid "../grid"

EXPLOSIVE_FUSE_PULSES :: 2
EXPLOSIVE_DAMAGE :: i32(4)
MAX_ACTIVE_BOMBS :: 4

// The arming command finishes its pulse first, then two further decisions remain.
arm_explosive :: proc(room: ^Room, id: u32, source: Entity_Ref, events: ^Event_Log) -> bool {
	if room == nil || room.phase != .Combat {
		return false
	}
	index, found := object_index_by_id(room, id)
	if !found {
		return false
	}
	object := &room.objects[index]
	definition, _ := grid_object_definition(object.kind)
	if !definition.explosive || object.detonation_pulse != 0 {
		return false
	}
	object.detonation_pulse = room.pulse_count+EXPLOSIVE_FUSE_PULSES+1
	record_event(events, {
		kind = .Explosive_Armed, source = source, target = object_entity(id),
		from_position = object.position, to_position = object.position,
		pulse_count = object.detonation_pulse, duration = EXPLOSIVE_FUSE_PULSES,
	})
	return true
}

explosive_pulses_remaining :: proc(deadline, pulse: u64) -> int {
	return int(min(deadline-pulse, u64(EXPLOSIVE_FUSE_PULSES))) if deadline > pulse else 0
}

// Walls and fixed obstacles are excluded; cover objects can be destroyed by the blast.
explosion_contains_cell :: proc(room: ^Room, center, cell: grid.Position) -> bool {
	return grid_distance(center, cell) <= 1 && base_cell_is_walkable(room, cell) &&
	       !obstacle_at(room, cell)
}

active_bomb_count :: proc(room: ^Room) -> (count: int) {
	for object in room.objects {
		if object.kind == .Bomb && object.detonation_pulse != 0 {
			count += 1
		}
	}
	return
}

bomb_cell_is_available :: proc(room: ^Room, position: grid.Position) -> bool {
	_, occupied := object_index_at(room, position)
	return base_cell_is_walkable(room, position) && !obstacle_at(room, position) && !occupied
}

spawn_bomb :: proc(room: ^Room, source: Entity_Ref, position: grid.Position, events: ^Event_Log) -> bool {
	if room == nil || room.phase != .Combat || len(room.objects) >= MAX_GRID_OBJECTS_PER_ROOM ||
	   room.next_object_id == 0 || room.next_object_id == max(u32) ||
	   active_bomb_count(room) >= MAX_ACTIVE_BOMBS || !bomb_cell_is_available(room, position) {
		return false
	}
	id := room.next_object_id
	room.next_object_id += 1
	append(&room.objects, Grid_Object{
		id = id, kind = .Bomb, position = position, health = 1, max_health = 1,
	})
	record_event(events, {
		kind = .Object_Spawned, source = source, target = object_entity(id),
		object_kind = .Bomb, from_position = position, to_position = position,
	})
	arm_explosive(room, id, source, events)
	return true
}

ignite_barrel_near_fire :: proc(room: ^Room, id: u32, events: ^Event_Log) {
	index, found := object_index_by_id(room, id)
	if !found || room.objects[index].kind != .Barrel {
		return
	}
	position := room.objects[index].position
	for object in room.objects {
		if object.kind == .Fire && abs(position.x-object.position.x)+abs(position.y-object.position.y) == 1 {
			arm_explosive(room, id, object_entity(object.id), events)
			return
		}
	}
}

disarm_explosives_after_combat :: proc(room: ^Room, events: ^Event_Log) {
	if room == nil || room.phase == .Combat {
		return
	}
	for &object in room.objects {
		if object.detonation_pulse == 0 {
			continue
		}
		object.detonation_pulse = 0
		record_event(events, {
			kind = .Explosive_Disarmed, source = SYSTEM_ENTITY, target = object_entity(object.id),
		})
	}
}

resolve_due_explosives :: proc(room: ^Room, pulse: ^Pulse_Report) {
	// Snapshot and sort IDs: removals and chain ignition cannot alter this batch.
	ids: [MAX_GRID_OBJECTS_PER_ROOM]u32
	count := 0
	for object in room.objects {
		if object.detonation_pulse != 0 && object.detonation_pulse <= room.pulse_count+1 {
			insert_at := count
			for insert_at > 0 && ids[insert_at-1] > object.id {
				ids[insert_at] = ids[insert_at-1]
				insert_at -= 1
			}
			ids[insert_at] = object.id
			count += 1
		}
	}
	for id in ids[:count] {
		if room.phase != .Combat {
			break
		}
		index, found := object_index_by_id(room, id)
		if !found {
			continue
		}
		center := room.objects[index].position
		room.objects[index].detonation_pulse = 0
		source := object_entity(id)
		action := make_action(.Trigger, source, entity_target(source), .Entity)
		// Cell order makes friendly fire independent of unordered enemy/object storage.
		for y in center.y-1..=center.y+1 {
			for x in center.x-1..=center.x+1 {
				cell := grid.Position{x, y}
				if !explosion_contains_cell(room, center, cell) {
					continue
				}
				if room.player.position == cell {
					added := add_effect(&action, damage_effect(PLAYER_ENTITY, EXPLOSIVE_DAMAGE))
					assert(added)
				}
				if enemy_index, present := enemy_index_at(room, cell); present {
					added := add_effect(&action, damage_effect(enemy_entity(room.enemies[enemy_index].id), EXPLOSIVE_DAMAGE))
					assert(added)
				}
				if object, present := grid_object_at(room, cell); present && object.id != id {
					effect := damage_effect(object_entity(object.id), EXPLOSIVE_DAMAGE)
					if effect_is_valid(room, effect) {
						added := add_effect(&action, effect)
						assert(added)
					}
				}
			}
		}
		record_event(&pulse.events, {
			kind = .Explosion, source = source, target = source, amount = EXPLOSIVE_DAMAGE,
			from_position = center, to_position = center,
		})
		report := resolve_action(room, &action)
		assert(report.accepted)
		merge_action_report(pulse, &report)
		index, found = object_index_by_id(room, id)
		if found {
			removed := remove_grid_object(room, index)
			assert(removed)
			pulse.objects_destroyed += 1
		}
	}
}
