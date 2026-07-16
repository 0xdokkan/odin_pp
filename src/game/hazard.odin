package game

Trap_Resolution :: struct {
	triggered: bool,
	trap_id:   u32,
	report:    Action_Report,
}

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

// Restituisce gli eventi nel report: il chiamante ne possiede l'accodamento.
resolve_trap_for_entity :: proc(room: ^Room, mover: Entity_Ref) -> (result: Trap_Resolution) {
	if room == nil || room.player == nil ||
	   (room.phase != .Combat && room.phase != .Loot) ||
	   (mover.kind != .Player && mover.kind != .Enemy) {
		return
	}
	initial_phase := room.phase
	result.triggered, result.trap_id = trigger_cell_hazard(room, mover, &result.report)
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
