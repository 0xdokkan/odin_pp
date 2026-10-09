package game

MAX_STATUSES_PER_ENTITY :: 8

Status_Kind :: enum {
	Poison,
	Shield,
	Thorns,
	Afterimage,
	Stagger,
	Survey,
}

status_kind_is_valid :: proc(kind: Status_Kind) -> bool {
	switch kind {
	case .Poison, .Shield, .Thorns, .Afterimage, .Stagger, .Survey:
		return true
	}
	return false
}

status_kind_name :: proc(kind: Status_Kind) -> string {
	switch kind {
	case .Poison:
		return "Poison"
	case .Shield:
		return "Shield"
	case .Thorns:
		return "Thorns"
	case .Afterimage:
		return "Afterimage"
	case .Stagger:
		return "Stagger"
	case .Survey:
		return "Survey"
	}
	return "Unknown"
}

Status :: struct {
	kind:             Status_Kind,
	potency:          i32,
	remaining_pulses: i32,
}

Status_Set :: struct {
	items: [MAX_STATUSES_PER_ENTITY]Status,
	count: int,
}

status_index :: proc(statuses: ^Status_Set, kind: Status_Kind) -> (int, bool) {
	if statuses == nil || !status_kind_is_valid(kind) ||
	   statuses.count < 0 || statuses.count > MAX_STATUSES_PER_ENTITY {
		return 0, false
	}
	for index in 0..<statuses.count {
		if statuses.items[index].kind == kind {
			return index, true
		}
	}
	return 0, false
}

status_set_for_entity :: proc(room: ^Room, entity: Entity_Ref) -> (^Status_Set, bool) {
	if room == nil || room.player == nil {
		return nil, false
	}
	switch entity.kind {
	case .Player:
		if entity.id == 0 {
			return &room.player.statuses, true
		}
	case .Enemy:
		index, found := enemy_index_by_id(room, entity.id)
		if found {
			return &room.enemies[index].statuses, true
		}
	case .Trap, .Object, .System:
	}
	return nil, false
}

status_for_entity :: proc(room: ^Room, entity: Entity_Ref, kind: Status_Kind) -> (^Status, bool) {
	statuses, found := status_set_for_entity(room, entity)
	if !found {
		return nil, false
	}
	index, has_status := status_index(statuses, kind)
	if !has_status {
		return nil, false
	}
	return &statuses.items[index], true
}

can_apply_status :: proc(room: ^Room, entity: Entity_Ref, kind: Status_Kind) -> bool {
	statuses, found := status_set_for_entity(room, entity)
	if !found || !status_kind_is_valid(kind) ||
	   statuses.count < 0 || statuses.count > MAX_STATUSES_PER_ENTITY {
		return false
	}
	_, already_present := status_index(statuses, kind)
	return already_present || statuses.count < MAX_STATUSES_PER_ENTITY
}

apply_status :: proc(
	room: ^Room,
	entity: Entity_Ref,
	kind: Status_Kind,
	potency, duration: i32,
) -> (applied, created: bool) {
	if potency <= 0 || duration <= 0 || !can_apply_status(room, entity, kind) {
		return false, false
	}
	statuses, found := status_set_for_entity(room, entity)
	assert(found)
	if index, already_present := status_index(statuses, kind); already_present {
		status := &statuses.items[index]
		switch kind {
		case .Poison, .Thorns, .Afterimage, .Stagger, .Survey:
			status.potency = max(status.potency, potency)
		case .Shield:
			available := max(i32)-status.potency
			status.potency += min(potency, available)
		}
		status.remaining_pulses = max(status.remaining_pulses, duration)
		return true, false
	}

	statuses.items[statuses.count] = {
		kind = kind,
		potency = potency,
		remaining_pulses = duration,
	}
	statuses.count += 1
	return true, true
}

remove_status :: proc(room: ^Room, entity: Entity_Ref, kind: Status_Kind) -> (removed: Status, ok: bool) {
	statuses, found := status_set_for_entity(room, entity)
	if !found {
		return {}, false
	}
	index, has_status := status_index(statuses, kind)
	if !has_status {
		return {}, false
	}

	removed = statuses.items[index]
	for current in index..<statuses.count-1 {
		statuses.items[current] = statuses.items[current+1]
	}
	statuses.count -= 1
	statuses.items[statuses.count] = {}
	return removed, true
}

clear_statuses :: proc(statuses: ^Status_Set) {
	if statuses != nil {
		statuses^ = {}
	}
}
