package game

import grid "../grid"

// Acting on the tick. When the decision clock crosses a whole second, a move,
// a bump or a card played within TACTICAL_BEAT_WINDOW of that instant is
// critical: two direction keys pressed together step diagonally, a bump hits
// twice as hard and a card resolves a stronger version of itself. A straight
// step stays one cell and leaves the tick to the next action.
//
// Beats are counted only as real time crosses a second (tactical_tick). An
// action's cost advances the clock by whole seconds and never makes a beat of
// its own, and a fresh window starts on a whole number without being one, so
// the first action of a window is not free. Each beat rewards one action.
TACTICAL_BEAT_WINDOW :: f32(0.15)
// A beat stays claimable this long after it struck, for an action that was
// pressed on time but buffered behind the previous animation.
TACTICAL_BEAT_GRACE :: f32(0.45)
TACTICAL_SHOCK_FLOOR_MAX_CHARGES :: i32(5)

// Called by tactical_tick with the fraction before real time advanced.
tactical_note_beat_time :: proc(s: ^Tactical_State, before, elapsed: f32) {
	if before+elapsed >= 1-0.00001 {
		s.beat_index += u32(max(f32(1), before+elapsed+0.00001))
		s.beat_age = s.clock_fraction
	} else {
		s.beat_age += elapsed
	}
}

tactical_reset_beats :: proc(s: ^Tactical_State) {
	s.beat_index, s.beat_spent, s.beat_age = 0, 0, 99
	s.critical_next, s.critical_card = false, false
}

// The beat an action pressed now lands on, or 0 when it is off the tick.
tactical_beat_target :: proc(room: ^Room) -> u32 {
	if room == nil || room.player == nil || !tactical_enabled(room) || room.phase != .Combat { return 0 }
	s := &room.player.tactical
	if s.phase != .Decision && !tactical_between_windows(s) { return 0 }
	if s.beat_index > 0 && s.beat_age <= TACTICAL_BEAT_WINDOW && s.beat_spent != s.beat_index { return s.beat_index }
	if 1-s.clock_fraction <= TACTICAL_BEAT_WINDOW && s.beat_spent != s.beat_index+1 { return s.beat_index+1 }
	return 0
}

// 0..1 nearness to the next tick, for the HUD metronome; `on` within the window.
tactical_beat_glow :: proc(room: ^Room) -> (approach: f32, on: bool) {
	if room == nil || room.player == nil || !tactical_enabled(room) { return }
	s := &room.player.tactical
	approach = s.clock_fraction
	on = tactical_beat_target(room) != 0
	return
}

// Spends a beat for one action; true when that action is critical.
tactical_claim_beat :: proc(room: ^Room, beat: u32) -> bool {
	if beat == 0 || room == nil || room.player == nil || !tactical_enabled(room) || room.phase != .Combat { return false }
	s := &room.player.tactical
	if s.beat_spent == beat || beat < s.beat_index || beat > s.beat_index+1 { return false }
	if beat == s.beat_index && s.beat_age > TACTICAL_BEAT_GRACE { return false }
	s.beat_spent = beat
	return true
}

// Read once by the action that the claim was made for.
tactical_take_critical :: proc(room: ^Room) -> bool {
	if room == nil || room.player == nil { return false }
	critical := room.player.tactical.critical_next
	room.player.tactical.critical_next = false
	return critical
}

critical_damage :: proc(amount: i32) -> i32 {
	return max(amount+2, (amount*3+1)/2)
}

critical_boost :: proc(amount: i32) -> i32 {
	return max(amount+1, (amount*3+1)/2)
}

critical_bump_damage :: proc(amount: i32) -> i32 {
	return amount*2
}

// The critical version of a card: more damage, stronger guards and gains,
// longer and stronger statuses, one more card drawn or created, stronger
// devices (a Tesla Coil also doubles its health when it is deployed).
tactical_critical_scale :: proc(room: ^Room, action: ^Action) {
	if room == nil || room.player == nil || action == nil || !room.player.tactical.critical_card { return }
	for &effect in action.effects[:action.effect_count] {
		switch effect.kind {
		case .Damage:
			effect.amount = critical_damage(effect.amount)
		case .Heal, .Gain_Gold:
			effect.amount = critical_boost(effect.amount)
		case .Apply_Status:
			if effect.status == .Shield { effect.amount = critical_boost(effect.amount) } else { effect.amount += 1 }
			effect.duration += 1
		case .Add_Reaction_Binding:
			effect.amount += 1
			if effect.charges > 0 { effect.charges += 1 }
		case .Draw_Cards, .Create_Card, .Gain_Energy:
			effect.amount += 1
		case .Deploy_Device:
			effect.amount = critical_damage(effect.amount)
			if effect.object_kind == .Shock_Floor { effect.charges = min(effect.charges+1, TACTICAL_SHOCK_FLOOR_MAX_CHARGES) }
		case .Move, .Remove_Status, .Discard_Cards:
		}
	}
}

// Marks the movement and damage of a critical action for the presentation.
mark_critical_events :: proc(log: ^Event_Log) {
	if log == nil { return }
	for &event in log.events[:log.count] {
		if event.kind == .Moved || event.kind == .Damaged { event.area_mask |= EVENT_CRITICAL_BIT }
	}
}

// A diagonal step, allowed only on the tick (the claim is made by the caller).
// Stepping into an enemy is a critical bump.
try_move_player_diagonal :: proc(room: ^Room, offset: grid.Position) -> Action_Result {
	if room == nil || room.player == nil || room.phase != .Combat || !tactical_allows_movement(room) { return .Invalid_Phase }
	if abs(offset.x) != 1 || abs(offset.y) != 1 { return .Blocked }
	target := add_position(room.player.position, offset)
	if enemy_index, found := enemy_index_at(room, target); found {
		if !tactical_allows_action(room) { return .Invalid_Phase }
		clear_event_log(&room.recent_events)
		enemy := room.enemies[enemy_index]
		action := make_action(.Attack, PLAYER_ENTITY, entity_target(enemy_entity(enemy.id)), .Opponent)
		added := add_effect(&action, damage_effect(enemy_entity(enemy.id), critical_bump_damage(player_basic_attack_damage(room.player))))
		assert(added)
		report := resolve_action(room, &action)
		if !report.accepted { return .Blocked }
		consume_equipped_weapon_use(room.player)
		mark_critical_events(&report.events)
		append_event_log(&room.recent_events, &report.events)
		_, outcome := finish_player_combat_command(room)
		switch outcome {
		case .Player_Defeated: return .Player_Defeated
		case .Combat_Ended: return .Combat_Ended
		case .Combat_Continues:
		}
		return .Attacked
	}
	query := query_entity_movement(room, PLAYER_ENTITY, target)
	if !movement_query_is_clear(&query) { return .Blocked }
	clear_event_log(&room.recent_events)
	action := make_action(.Move, PLAYER_ENTITY, cell_target(target), .Walkable_Cell)
	added := add_effect(&action, move_effect(PLAYER_ENTITY, target))
	assert(added)
	report := resolve_action(room, &action)
	if !report.accepted { return .Blocked }
	mark_critical_events(&report.events)
	append_event_log(&room.recent_events, &report.events)
	collect_loot_in_magnet_range(room)
	room.player.tactical.facing = .North if offset.y < 0 else .South
	_, outcome := finish_player_combat_command(room)
	switch outcome {
	case .Player_Defeated: return .Player_Defeated
	case .Combat_Ended: return .Combat_Ended
	case .Combat_Continues:
	}
	return .Moved
}
