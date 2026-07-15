package game

MAX_REACTION_BINDINGS_PER_ROOM :: 32
REACTION_BINDING_UNLIMITED :: -1

Reaction_Binding_Source_Kind :: enum {
	System,
	Ability,
	Card,
	Passive,
}

Reaction_Binding_Source :: struct {
	kind: Reaction_Binding_Source_Kind,
	id:   u32,
}

Reaction_Binding :: struct {
	id:                 u32,
	definition_id:      Reaction_Id,
	owner:              Entity_Ref,
	potency:            i32,
	remaining_charges:  i32,
	remaining_pulses:   i32,
	priority_modifier:  i32,
	source:             Reaction_Binding_Source,
}

Reaction_Binding_Config :: struct {
	definition_id:     Reaction_Id,
	owner:             Entity_Ref,
	potency:           i32,
	charges:           i32,
	duration:          i32,
	priority_modifier: i32,
	source:            Reaction_Binding_Source,
}

Reaction_Binding_Set :: struct {
	items:   [MAX_REACTION_BINDINGS_PER_ROOM]Reaction_Binding,
	count:   int,
	next_id: u32,
}

reaction_binding_index_by_id :: proc(room: ^Room, id: u32) -> (int, bool) {
	if room == nil || id == 0 || room.reaction_bindings.count < 0 ||
	   room.reaction_bindings.count > MAX_REACTION_BINDINGS_PER_ROOM {
		return 0, false
	}
	for index in 0..<room.reaction_bindings.count {
		if room.reaction_bindings.items[index].id == id {
			return index, true
		}
	}
	return 0, false
}

reaction_binding_by_id :: proc(room: ^Room, id: u32) -> (^Reaction_Binding, bool) {
	index, found := reaction_binding_index_by_id(room, id)
	if !found {
		return nil, false
	}
	return &room.reaction_bindings.items[index], true
}

reaction_binding_is_active :: proc(room: ^Room, binding: ^Reaction_Binding) -> bool {
	return room != nil && binding != nil && binding.id != 0 && binding.potency > 0 &&
	       (binding.remaining_charges == REACTION_BINDING_UNLIMITED || binding.remaining_charges > 0) &&
	       (binding.remaining_pulses == REACTION_BINDING_UNLIMITED || binding.remaining_pulses > 0) &&
	       entity_exists(room, binding.owner)
}

can_add_reaction_binding :: proc(room: ^Room, config: Reaction_Binding_Config) -> bool {
	if room == nil || room.reaction_bindings.count < 0 ||
	   room.reaction_bindings.count >= MAX_REACTION_BINDINGS_PER_ROOM ||
	   config.potency <= 0 ||
	   (config.charges != REACTION_BINDING_UNLIMITED && config.charges <= 0) ||
	   (config.duration != REACTION_BINDING_UNLIMITED && config.duration <= 0) ||
	   !entity_exists(room, config.owner) {
		return false
	}
	definition, found := reaction_definition_by_id(config.definition_id)
	return found && validate_reaction_definition(&definition)
}

add_reaction_binding :: proc(
	room: ^Room,
	config: Reaction_Binding_Config,
) -> (binding_id: u32, ok: bool) {
	if !can_add_reaction_binding(room, config) {
		return 0, false
	}
	if room.reaction_bindings.next_id == 0 {
		room.reaction_bindings.next_id = 1
	}
	if room.reaction_bindings.next_id == max(u32) {
		return 0, false
	}

	binding_id = room.reaction_bindings.next_id
	room.reaction_bindings.next_id += 1
	room.reaction_bindings.items[room.reaction_bindings.count] = {
		id = binding_id,
		definition_id = config.definition_id,
		owner = config.owner,
		potency = config.potency,
		remaining_charges = config.charges,
		remaining_pulses = config.duration,
		priority_modifier = config.priority_modifier,
		source = config.source,
	}
	room.reaction_bindings.count += 1
	return binding_id, true
}

remove_reaction_binding :: proc(
	room: ^Room,
	binding_id: u32,
) -> (removed: Reaction_Binding, ok: bool) {
	index, found := reaction_binding_index_by_id(room, binding_id)
	if !found {
		return {}, false
	}
	removed = room.reaction_bindings.items[index]
	for current in index..<room.reaction_bindings.count-1 {
		room.reaction_bindings.items[current] = room.reaction_bindings.items[current+1]
	}
	room.reaction_bindings.count -= 1
	room.reaction_bindings.items[room.reaction_bindings.count] = {}
	return removed, true
}

remove_reaction_bindings_for_owner :: proc(room: ^Room, owner: Entity_Ref) -> (removed_count: int) {
	if room == nil {
		return
	}
	index := 0
	for index < room.reaction_bindings.count {
		binding := room.reaction_bindings.items[index]
		if binding.owner != owner {
			index += 1
			continue
		}
		_, removed := remove_reaction_binding(room, binding.id)
		assert(removed)
		removed_count += 1
	}
	return
}

reaction_binding_priority :: proc(base, modifier: i32) -> i32 {
	value := i64(base)+i64(modifier)
	return i32(clamp(value, i64(min(i32)), i64(max(i32))))
}

consume_reaction_binding :: proc(
	room: ^Room,
	binding_id: u32,
) -> (event: Game_Event, exhausted: bool) {
	binding, found := reaction_binding_by_id(room, binding_id)
	if !found || !reaction_binding_is_active(room, binding) ||
	   binding.remaining_charges == REACTION_BINDING_UNLIMITED {
		return {}, false
	}
	binding.remaining_charges -= 1
	if binding.remaining_charges > 0 {
		return {}, false
	}
	removed, ok := remove_reaction_binding(room, binding_id)
	assert(ok)
	return Game_Event{
		kind = .Reaction_Binding_Exhausted,
		source = SYSTEM_ENTITY,
		target = removed.owner,
		amount = removed.potency,
		duration = removed.remaining_pulses,
		reaction = removed.definition_id,
		binding_id = removed.id,
		binding_source = removed.source,
	}, true
}

tick_reaction_bindings :: proc(room: ^Room, pulse: ^Pulse_Report) {
	assert(room != nil && pulse != nil)
	if room.phase != .Combat {
		return
	}

	index := 0
	for index < room.reaction_bindings.count {
		binding := &room.reaction_bindings.items[index]
		if binding.remaining_pulses == REACTION_BINDING_UNLIMITED {
			index += 1
			continue
		}
		binding.remaining_pulses -= 1
		if binding.remaining_pulses > 0 {
			index += 1
			continue
		}

		binding_id := binding.id
		removed, ok := remove_reaction_binding(room, binding_id)
		assert(ok)
		pulse.reaction_bindings_removed += 1
		record_event(&pulse.events, {
			kind = .Reaction_Binding_Expired,
			source = SYSTEM_ENTITY,
			target = removed.owner,
			amount = removed.potency,
			reaction = removed.definition_id,
			binding_id = removed.id,
			binding_source = removed.source,
		})
	}
}
