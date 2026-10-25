package game

import "core:slice"
import grid "../engine/grid"

EXPLOSIVE_FUSE_PULSES :: 2
EXPLOSIVE_DAMAGE :: i32(4)
MAX_ACTIVE_BOMBS :: 4

// World beats advance the fuse; the arming beat completes before its countdown.
@(private)
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
	fuse := EXPLOSIVE_FUSE_PULSES
	object.explosion_damage = EXPLOSIVE_DAMAGE
	if room != nil && room.player != nil && object.kind == .Bomb && source.kind == .Enemy {
		fuse = TACTICAL_BOMB_FUSE
		object.explosion_damage = TACTICAL_BOMB_DAMAGE
	}
	object.fuse_pulses = fuse
	object.detonation_pulse = room.pulse_count+u64(fuse)+1
	record_event(events, {
		kind = .Explosive_Armed, source = source, target = object_entity(id),
		from_position = object.position, to_position = object.position,
		pulse_count = object.detonation_pulse, duration = i32(fuse),
	})
	return true
}

explosive_pulses_remaining :: proc(deadline, pulse: u64, fuse: int = EXPLOSIVE_FUSE_PULSES) -> int {
	return int(min(deadline-pulse, u64(max(1, fuse)))) if deadline > pulse else 0
}

// Walls and fixed obstacles are excluded; cover objects can be destroyed by the blast. With layers, the
// blast takes one cell a column, as an area does (layers.odin).
explosion_contains_cell :: proc(room: ^Room, center, cell: grid.Position) -> bool {
	return grid_distance(center, cell) <= 1 && base_cell_is_walkable(room, cell) &&
	       !obstacle_at(room, cell) && area_takes(room, center, cell)
}

@(private)
active_bomb_count :: proc(room: ^Room) -> (count: int) {
	for object in room.objects {
		if object.kind == .Bomb && object.detonation_pulse != 0 {
			count += 1
		}
	}
	return
}

@(private)
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

@(private)
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

@(private)
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

@(private)
resolve_due_explosives :: proc(room: ^Room, pulse: ^Pulse_Report) {
	// Snapshot and sort IDs: removals and chain ignition cannot alter this batch.
	ids: [MAX_GRID_OBJECTS_PER_ROOM]u32
	count := 0
	for object in room.objects {
		if object.detonation_pulse != 0 && object.detonation_pulse <= room.pulse_count+1 {
			ids[count] = object.id
			count += 1
		}
	}
	slice.sort(ids[:count])
	for id in ids[:count] {
		if room.phase != .Combat {
			break
		}
		index, found := object_index_by_id(room, id)
		if !found {
			continue
		}
		center := room.objects[index].position
		damage := room.objects[index].explosion_damage
		if damage <= 0 { damage = EXPLOSIVE_DAMAGE }
		room.objects[index].detonation_pulse = 0
		source := object_entity(id)
		action := make_action(.Trigger, source, entity_target(source), .Entity)
		// Cell order makes friendly fire independent of unordered enemy/object storage.
		for y in center.y-1..=center.y+1 {
			for x in center.x-1..=center.x+1 {
				cell := grid.Position{x = x, y = y}
				if !explosion_contains_cell(room, center, cell) {
					continue
				}
				if room.player.position == cell {
					added := add_effect(&action, damage_effect(PLAYER_ENTITY, damage))
					assert(added)
				}
				if enemy_index, present := enemy_index_at(room, cell); present {
					added := add_effect(&action, damage_effect(enemy_entity(room.enemies[enemy_index].id), damage))
					assert(added)
				}
				if object, present := grid_object_at(room, cell); present && object.id != id {
					effect := damage_effect(object_entity(object.id), damage)
					if effect_is_valid(room, effect) {
						added := add_effect(&action, effect)
						assert(added)
					}
				}
			}
		}
		record_event(&pulse.events, {
			kind = .Explosion, source = source, target = source, amount = damage,
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
