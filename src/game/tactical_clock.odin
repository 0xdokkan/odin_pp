package game

TACTICAL_WORLD_BEAT_SECONDS :: f32(1)
TACTICAL_RECOVERY_SECONDS :: f32(1)

tactical_is_casting :: proc(room: ^Room) -> bool {
	return tactical_enabled(room) && room.phase == .Combat && room.player.tactical.cast_remaining > 0
}

tactical_begin_card_cast :: proc(room: ^Room, seconds: f32) {
	if !tactical_enabled(room) || room.phase != .Combat || seconds <= 0 { return }
	s := &room.player.tactical
	s.cast_remaining, s.cast_duration = seconds, seconds
	s.metrics.decisions += 1
}

// Each telegraph has a deadline of its own. Recovery and an already prepared
// projectile advance faster than a fresh action; classic combat ignores this.
tactical_enemy_intent_seconds :: proc(enemy: ^Enemy) -> f32 {
	if enemy.intent.kind == .Recover || enemy.aim_ready || enemy.bomb_ready { return 1 }
	switch enemy.archetype {
	case .Chaser: return 2
	case .Archer, .Custodian: return 3
	case .Brute, .Bomber, .Demolitionist: return 4
	case .Count: return 1
	}
	return 1
}

tactical_enemy_seconds :: proc(room: ^Room, enemy: ^Enemy) -> f32 {
	if !tactical_enabled(room) || enemy == nil { return 0 }
	return max(f32(0), enemy.tactical_cooldown-room.player.tactical.clock_fraction)
}

tactical_schedule_enemy :: proc(room: ^Room, enemy: ^Enemy) {
	if tactical_enabled(room) { enemy.tactical_cooldown = tactical_enemy_intent_seconds(enemy) }
}

tactical_queue_next_beat :: proc(room: ^Room) {
	s := &room.player.tactical
	if room.phase != .Combat || (s.phase != .Decision && s.phase != .Recovery) ||
	   s.queued_beats <= 0 || room.tactical_pulse.pending { return }
	room.tactical_pulse.pending = true
	room.tactical_pulse.forced = s.phase == .Recovery
	if s.phase == .Decision { s.phase = .Resolving }
}

// Recovery is timed by the same active clock as the world. A beat may finish
// before the recovery deadline; a QTE may defer its final beat beyond it.
tactical_finish_recovery :: proc(room: ^Room) {
	if !tactical_is_recovering(room) || room.tactical_pulse.pending || room.qte.kind != .None { return }
	s := &room.player.tactical
	if s.remaining > 0 || s.queued_beats > 0 { return }
	s.phase = .Decision
	s.budget = s.config.timer_seconds
	s.remaining = f32(s.budget)
}

// The same elapsed-time path receives frame time and the extra cost of accepted
// actions. It never executes gameplay recursively: the controller drains beats
// through Continue_Pulse, preserving bounded logs and defense QTE suspension.
tactical_advance_clock :: proc(room: ^Room, seconds: f32) {
	s := &room.player.tactical
	elapsed := min(max(f32(0), seconds), max(f32(0), s.remaining))
	s.remaining = max(f32(0), s.remaining-elapsed)
	if s.remaining < 0.00001 { s.remaining = 0 }
	s.clock_fraction += elapsed
	// Frame partitions can leave a tiny rounding remainder at an integer edge.
	beats := int(s.clock_fraction+0.00001)
	s.clock_fraction = max(f32(0), s.clock_fraction-f32(beats))
	s.queued_beats += beats
	tactical_queue_next_beat(room)
}

tactical_spend_action_time :: proc(room: ^Room, seconds: f32) {
	if !tactical_enabled(room) || room.phase != .Combat || !(seconds > 0) { return }
	s := &room.player.tactical
	if s.config.timed_actions {
		// The action lasts its cost: the window and the world run through it
		// in real time, and the player waits for it to finish. Recovery walks
		// take their time too.
		if s.phase != .Decision && s.phase != .Recovery { return }
		s.metrics.decisions += 1
		s.action_remaining, s.action_duration = seconds, seconds
		return
	}
	if s.phase != .Decision { return }
	s.metrics.decisions += 1
	tactical_advance_clock(room, seconds)
}

// A deadline ends the entire decision window, never an individual action.
// Expiry waits until all charged world time has resolved, so a lethal final
// beat cannot accidentally start another window or carry work into the loot.
tactical_expire_window :: proc(room: ^Room) -> bool {
	if !tactical_enabled(room) || room.phase != .Combat || room.tactical_pulse.pending ||
	   room.qte.kind != .None || room.player.tactical.remaining > 0 { return false }
	s := &room.player.tactical
	if s.phase != .Decision || s.queued_beats > 0 || s.cast_remaining > 0 { return false }
	clear_event_log(&room.recent_events)
	s.cycle = min(s.cycle, max(int)-1)+1
	s.metrics.pauses += 1
	s.phase = .Recovery
	s.remaining = TACTICAL_RECOVERY_SECONDS
	// The window's end also ends a timed action still running.
	s.action_remaining, s.action_duration = 0, 0
	return true
}
