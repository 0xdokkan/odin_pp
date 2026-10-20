package game

Trap_Resolution :: struct {
	triggered: bool,
	trap_id:   u32,
	report:    Action_Report,
}

Grid_Object_Hazard_Resolution :: struct {
	triggered: bool,
	object_id: u32,
	report:    Action_Report,
}

@(private = "file")
trigger_trap_hazard :: proc(
	room: ^Room,
	mover: Entity_Ref,
	report: ^Action_Report,
) -> (triggered: bool, trap_id: u32) {
	position, mover_found := entity_position(room, mover)
	if !mover_found {
		return
	}
	trap_index, trap_found := trap_index_at(room, position)
	if !trap_found || !room.traps[trap_index].armed || room.traps[trap_index].damage <= 0 {
		return
	}

	trap := room.traps[trap_index]
	room.traps[trap_index].armed = false
	record_report_event(report, {
		kind = .Trap_Triggered,
		source = trap_entity(trap.id),
		target = mover,
		from_position = position,
		to_position = position,
	})
	apply_damage_effect(
		room,
		trap_entity(trap.id),
		damage_effect(mover, trap.damage),
		report,
	)
	return true, trap.id
}

@(private = "file")
trigger_grid_object_hazard :: proc(
	room: ^Room,
	mover: Entity_Ref,
	report: ^Action_Report,
) -> (triggered: bool, object_id: u32) {
	position, mover_found := entity_position(room, mover)
	if !mover_found {
		return
	}
	object_index, object_found := object_index_at(room, position)
	if !object_found {
		return
	}
	object := room.objects[object_index]
	definition, definition_found := grid_object_definition(object.kind)
	if !definition_found || !definition.hazardous || definition.hazard_damage <= 0 {
		return
	}

	source := object_entity(object.id)
	record_report_event(report, {
		kind = .Hazard_Triggered,
		source = source,
		target = mover,
		amount = definition.hazard_damage,
		from_position = position,
		to_position = position,
	})
	apply_damage_effect(
		room,
		source,
		damage_effect(mover, definition.hazard_damage),
		report,
	)
	return true, object.id
}

@(private)
trigger_cell_hazard :: proc(
	room: ^Room,
	mover: Entity_Ref,
	report: ^Action_Report,
) -> (triggered: bool, trap_id: u32) {
	if room == nil || room.player == nil || report == nil ||
	   (room.phase != .Combat && room.phase != .Loot) ||
	   (mover.kind != .Player && mover.kind != .Enemy) {
		return
	}
	if !entity_exists(room, mover) {
		return
	}
	trap_triggered, triggered_trap_id := trigger_trap_hazard(room, mover, report)
	triggered = trap_triggered
	trap_id = triggered_trap_id
	if !entity_exists(room, mover) {
		return
	}
	object_triggered, _ := trigger_grid_object_hazard(room, mover, report)
	triggered = triggered || object_triggered
	return
}

// Restituisce gli eventi nel report: il chiamante ne possiede l'accodamento.
@(private)
resolve_trap_for_entity :: proc(room: ^Room, mover: Entity_Ref) -> (result: Trap_Resolution) {
	if room == nil || room.player == nil ||
	   (room.phase != .Combat && room.phase != .Loot) ||
	   (mover.kind != .Player && mover.kind != .Enemy) {
		return
	}
	initial_phase := room.phase
	result.triggered, result.trap_id = trigger_trap_hazard(room, mover, &result.report)
	if !result.triggered {
		return
	}
	result.report.accepted = true
	result.report.applied_effects = 1
	result.report.combat_ended = initial_phase == .Combat && room.phase == .Loot
	result.report.player_defeated = room.phase == .Defeat
	dispatch_reactions(room, &result.report)
	return
}

@(private)
resolve_grid_object_hazard_for_entity :: proc(
	room: ^Room,
	mover: Entity_Ref,
) -> (result: Grid_Object_Hazard_Resolution) {
	if room == nil || room.player == nil ||
	   (room.phase != .Combat && room.phase != .Loot) ||
	   (mover.kind != .Player && mover.kind != .Enemy) {
		return
	}
	initial_phase := room.phase
	result.triggered, result.object_id =
		trigger_grid_object_hazard(room, mover, &result.report)
	if !result.triggered {
		return
	}
	result.report.accepted = true
	result.report.applied_effects = 1
	result.report.combat_ended = initial_phase == .Combat && room.phase == .Loot
	result.report.player_defeated = room.phase == .Defeat
	dispatch_reactions(room, &result.report)
	return
}
