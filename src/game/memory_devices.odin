package game

import grid "../engine/grid"

card_requires_orientation :: proc(id: Card_Id) -> bool {
	return id == .Cannon || id == .Flood
}

memory_device_kind :: proc(kind: Grid_Object_Kind) -> bool {
	return kind == .Cannon || kind == .Flood || kind == .Black_Hole || kind == .Bomb_Marley
}

memory_device_card :: proc(kind: Grid_Object_Kind) -> Card_Id {
	#partial switch kind {
	case .Cannon: return .Cannon
	case .Flood: return .Flood
	case .Black_Hole: return .Black_Hole
	case .Bomb_Marley: return .Bomb_Marley
	}
	return .Count
}

memory_device_contains :: proc(room: ^Room, object: Grid_Object, cell: grid.Position) -> bool {
	if !shape_cell_has_clear_path(room, object.position, cell) { return false }
	delta := grid.offset(cell, -object.position.x, -object.position.y)
	if object.kind == .Black_Hole || object.kind == .Bomb_Marley {
		return max(abs(delta.x), abs(delta.y)) <= 3
	}
	forward := direction_offset(object.device_direction)
	along := delta.x*forward.x+delta.y*forward.y
	side := abs(delta.x*forward.y-delta.y*forward.x)
	return along > 0 && along <= (7 if object.kind == .Cannon else 4) && side <= (0 if object.kind == .Cannon else 1)
}

// Stable IDs keep each pulse valid even when a hit kills or pushes a target.
// Four volleys bound placed effects; none can farm or damage dormant chunks.
@(private)
tick_memory_devices :: proc(room: ^Room, pulse: ^Pulse_Report) {
	ids: [MAX_GRID_OBJECTS_PER_ROOM]u32
	count := 0
	for &object in room.objects {
		if !memory_device_kind(object.kind) { continue }
		object.device_cooldown = max(0, object.device_cooldown-1)
		if object.device_cooldown > 0 { continue }
		ids[count], count = object.id, count+1
	}
	for id in ids[:count] {
		if room.phase != .Combat { break }
		index, found := object_index_by_id(room, id)
		if !found { continue }
		object := room.objects[index]
		room.objects[index].device_cooldown = 3 if object.kind == .Cannon else 2
		room.objects[index].device_charges -= 1
		foes, foe_count := enemy_ids_in_planning_order(room)
		// A basic cannon hits the nearest target; its first upgrade is a laser.
		nearest: u32
		best := 1000
		for enemy in room.enemies {
			if !memory_device_contains(room, object, enemy.position) { continue }
			distance := abs(enemy.position.x-object.position.x)+abs(enemy.position.y-object.position.y)
			if distance < best { nearest, best = enemy.id, distance }
		}
		record_event(&pulse.events, {kind = .Spell_Impact, source = object_entity(id), target = SYSTEM_ENTITY,
			card_definition = memory_device_card(object.kind), object_kind = object.kind,
			from_position = object.position, to_position = object.position, amount = object.device_damage})
		for enemy_id in foes[:foe_count] {
			if room.phase != .Combat { break }
			ei, exists := enemy_index_by_id(room, enemy_id)
			if !exists || enemy_is_out_of_play(room, enemy_id) { continue }
			position := room.enemies[ei].position
			if !memory_device_contains(room, object, position) { continue }
			if object.kind == .Cannon && object.device_target_limit <= 1 && enemy_id != nearest { continue }
			target := enemy_entity(enemy_id)
			action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(target), .Entity)
			add_effect(&action, damage_effect(target, object.device_damage))
			if object.kind == .Flood { add_effect(&action, apply_status_effect(target, .Slow, 1, 2)) }
			report := resolve_action(room, &action)
			merge_action_report(pulse, &report)
			if room.phase != .Combat || (object.kind != .Flood && object.kind != .Black_Hole) { continue }
			ei, exists = enemy_index_by_id(room, enemy_id)
			if !exists { continue }
			step := direction_offset(object.device_direction)
			if object.kind == .Black_Hole { step = {x = sign(object.position.x-position.x), y = sign(object.position.y-position.y)} }
			destination := add_position(position, step)
			move := make_action(.Trigger, SYSTEM_ENTITY, entity_target(target), .Entity)
			add_effect(&move, move_effect(target, destination))
			moved := resolve_action(room, &move)
			if moved.accepted { merge_action_report(pulse, &moved) }
		}
		index, found = object_index_by_id(room, id)
		if found && room.objects[index].device_charges <= 0 {
			remove_grid_object(room, index)
			record_event(&pulse.events, {kind = .Entity_Defeated, source = SYSTEM_ENTITY, target = object_entity(id), object_kind = object.kind})
		}
	}
}
