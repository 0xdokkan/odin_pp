package game

// Capabilities describe controls, not mutually exclusive mechanics. A Pinball
// may keep rolling while the player uses other controls; Shadow suspends its
// world clock without discarding it, the floor, or the room's devices.
Tactical_Capability :: enum { Action, Movement, Cards, Board_Action, Shadow, First_Person }

tactical_control_allowed :: proc(room: ^Room, capability: Tactical_Capability, ignore_busy := false) -> bool {
	// One riding a lift's platform does nothing until it stops, not even a dodge (lift.odin).
	if lift_player_riding(room) { return false }
	if room == nil || room.player == nil || room.phase != .Combat {
		return capability == .Action || capability == .Movement || capability == .Cards
	}
	s := &room.player.tactical
	defense_free := room.qte.kind == .None
	world_free := !room.tactical_pulse.pending && defense_free
	window_free := world_free && (s.config.expedition || s.remaining > 0) && s.cast_remaining <= 0
	body_free := s.action_remaining <= 0 && !room.lasso.active
	card_phase := s.phase == .Decision || s.phase == .Stunned
	switch capability {
	case .Action, .Board_Action:
		return window_free && s.phase == .Decision && (ignore_busy || body_free) &&
		       (capability != .Board_Action || !room.first_person.active)
	case .Movement:
		if s.phase == .Recovery { return world_free && (ignore_busy || body_free) }
		return window_free && s.phase == .Decision && (ignore_busy || body_free)
	case .Cards:
		// Stun permits cards even while a previous timed action is ending.
		return !room.first_person.active && window_free && !room.lasso.active &&
		       (s.phase == .Stunned || (s.phase == .Decision && s.action_remaining <= 0))
	case .Shadow:
		return !room.first_person.active && card_phase && window_free && body_free &&
		       s.queued_beats == 0 && !room.tesla_ring.pending
	case .First_Person:
		// This effect may start during its card's cast. Its entry policy is
		// deliberately less restrictive than the Shadow's still-world entry.
		return !room.first_person.active && card_phase && defense_free && !room.lasso.active
	}
	return false
}

// The dodge may interrupt a timed action and release the Lazzo's rope.
tactical_allows_action :: proc(room: ^Room, ignore_busy := false) -> bool {
	return tactical_control_allowed(room, .Action, ignore_busy)
}

tactical_allows_cards :: proc(room: ^Room) -> bool {
	return tactical_control_allowed(room, .Cards)
}

tactical_allows_movement :: proc(room: ^Room, ignore_busy := false) -> bool {
	return tactical_control_allowed(room, .Movement, ignore_busy)
}

tactical_can_begin_shadow :: proc(room: ^Room) -> bool {
	return tactical_control_allowed(room, .Shadow)
}

@(private)
tactical_can_begin_first_person :: proc(room: ^Room) -> bool {
	return tactical_control_allowed(room, .First_Person)
}

Tactical_Clock_Mode :: enum { Paused, Shadow, Cast, World }

// Clock ownership is independent of the presentation and of active mechanics.
// Cast spends only the window; Shadow spends only its own clock. Neither may
// accumulate world time to catch up after the suspension.
@(private)
tactical_clock_mode :: proc(room: ^Room, available := true) -> Tactical_Clock_Mode {
	if room == nil || room.player == nil || room.phase != .Combat || !available ||
	   room.tactical_pulse.pending || room.qte.kind != .None { return .Paused }
	s := &room.player.tactical
	if s.phase == .Shadow { return .Shadow }
	if s.phase != .Decision && !tactical_between_windows(s) { return .Paused }
	return .Cast if s.cast_remaining > 0 else .World
}
