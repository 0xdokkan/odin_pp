package game

import grid "../engine/grid"

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
// pressed on time but committed a little later: a move pressed on the tick
// waits a few frames for its diagonal partner key.
TACTICAL_BEAT_GRACE :: f32(0.45)
// A floor holds its die's roll (up to a D20) and the critical one more.
TACTICAL_SHOCK_FLOOR_MAX_CHARGES :: MAX_DIE_SIDES+1

// Called by tactical_tick with the fraction before real time advanced.
@(private)
tactical_note_beat_time :: proc(s: ^Tactical_State, before, elapsed: f32) {
	if before+elapsed >= 1-0.00001 {
		s.beat_index += u32(max(f32(1), before+elapsed+0.00001))
		s.beat_age = s.clock_fraction
	} else {
		s.beat_age += elapsed
	}
}

@(private)
tactical_reset_beats :: proc(s: ^Tactical_State) {
	s.beat_index, s.beat_spent, s.beat_age = 0, 0, 99
	s.critical_next, s.critical_card = false, false
}

// The beat an action pressed now lands on, or 0 when it is off the tick.
tactical_beat_target :: proc(room: ^Room) -> u32 {
	if room == nil || room.player == nil || room.phase != .Combat { return 0 }
	s := &room.player.tactical
	// Inside the shadow the press is judged against the shadow's own beats.
	if s.phase == .Shadow { return tactical_shadow_beat_target(room) }
	if s.phase != .Decision && !tactical_between_windows(s) { return 0 }
	if s.beat_index > 0 && s.beat_age <= TACTICAL_BEAT_WINDOW && s.beat_spent != s.beat_index { return s.beat_index }
	if 1-s.clock_fraction <= TACTICAL_BEAT_WINDOW && s.beat_spent != s.beat_index+1 { return s.beat_index+1 }
	return 0
}

// 0..1 nearness to the next tick, for the HUD metronome; `on` within the window.
// Inside the shadow, the nearness to the shadow's own next beat.
tactical_beat_glow :: proc(room: ^Room) -> (approach: f32, on: bool) {
	if room == nil || room.player == nil { return }
	s := &room.player.tactical
	approach = s.clock_fraction
	if tactical_shadow_active(room) {
		elapsed := tactical_shadow_elapsed(s)
		approach = elapsed-f32(int(elapsed))
	}
	on = tactical_beat_target(room) != 0
	return
}

// Spends a beat for one action; true when that action is critical.
tactical_claim_beat :: proc(room: ^Room, beat: u32) -> bool {
	if beat == 0 || room == nil || room.player == nil || room.phase != .Combat { return false }
	s := &room.player.tactical
	// The world's beats are frozen with it; the shadow claims its own.
	if s.phase == .Shadow { return false }
	if s.beat_spent == beat || beat < s.beat_index || beat > s.beat_index+1 { return false }
	if beat == s.beat_index && s.beat_age > TACTICAL_BEAT_GRACE { return false }
	s.beat_spent = beat
	return true
}

// Movimento Ombra stands outside the window's time, and the Dado del Destino
// loads its three bumps whatever the tick (it has no stronger version): played
// on the tick, each leaves the beat to the next action, with no critical and no
// badge.
tactical_card_claims_beat :: proc(room: ^Room, card_id: u32) -> bool {
	if room == nil || room.player == nil { return false }
	index, found := hand_card_index_by_id(&room.player.deck, card_id)
	if !found { return true }
	id := room.player.deck.hand[index].definition_id
	return id != .Shadow_Step && id != .Fate_Dice
}

// Read once by the action that the claim was made for.
@(private)
tactical_take_critical :: proc(room: ^Room) -> bool {
	if room == nil || room.player == nil { return false }
	critical := room.player.tactical.critical_next
	room.player.tactical.critical_next = false
	return critical
}

@(private = "file")
critical_damage :: proc(amount: i32) -> i32 {
	return max(amount+2, (amount*3+1)/2)
}

@(private = "file")
critical_boost :: proc(amount: i32) -> i32 {
	return max(amount+1, (amount*3+1)/2)
}

@(private)
critical_bump_damage :: proc(amount: i32) -> i32 {
	return amount*2
}

// The critical version of a card: more damage, stronger guards and gains,
// longer and stronger statuses, one more card drawn or created, stronger
// devices (a Tesla Coil also doubles its health when it is deployed).
@(private)
tactical_critical_scale :: proc(room: ^Room, action: ^Action) {
	if room == nil || room.player == nil || action == nil || !room.player.tactical.critical_card { return }
	for &effect in action.effects[:action.effect_count] {
		switch effect.kind {
		case .Damage:
			effect.amount = critical_damage(effect.amount)
		case .Heal, .Gain_Gold:
			effect.amount = critical_boost(effect.amount)
		case .Apply_Status:
			// The Dado del Destino loads its bumps, never more (and never claims
			// the tick: tactical_card_claims_beat). The other charges get one more.
			if effect.status == .Fate { continue }
			if effect.status == .Shield { effect.amount = critical_boost(effect.amount) } else { effect.amount += 1 }
			// Stacks have no duration to lengthen.
			if !status_kind_stacks(effect.status) { effect.duration += 1 }
		case .Add_Reaction_Binding:
			effect.amount += 1
			if effect.charges > 0 { effect.charges += 1 }
		// A pool or a fire gives a stack more; the Lazzo's first hit is one
		// harder (and so is every one after it), and so is the Pinball's value
		// (and the one every wall puts it back to).
		case .Draw_Cards, .Create_Card, .Gain_Energy, .Place_Ground, .Lasso, .Pinball:
			effect.amount += 1
		// The wave pushes one cell more; the party lasts five seconds longer.
		case .Flood:
			effect.amount += 1
		// A cannon and a hole hurt more; the ride lasts longer.
		case .Place_Cannon, .Open_Black_Hole:
			effect.amount = critical_damage(effect.amount)
		case .Ride:
			effect.amount += RIDE_CRITICAL_SECONDS
		case .Marley:
			effect.duration += MARLEY_CRITICAL_SECONDS
		case .Deploy_Device:
			effect.amount = critical_damage(effect.amount)
			if effect.object_kind == .Shock_Floor { effect.charges = min(effect.charges+1, TACTICAL_SHOCK_FLOOR_MAX_CHARGES) }
		// Unchanged; Movimento Ombra's four seconds never grow either, and the
		// Canna da Pesca is never played on the tick.
		case .Move, .Remove_Status, .Discard_Cards, .Enter_Shadow, .Fish:
		// Two seconds more behind the player's eyes.
		case .First_Person:
			effect.amount += FIRST_PERSON_CRITICAL_SECONDS
		}
	}
}

// Marks a critical action for presentation, including its roll: the face
// itself does not include the stronger effect applied after rolling.
mark_critical_events :: proc(log: ^Event_Log) {
	if log == nil { return }
	for &event in log.events[:log.count] {
		if event.kind == .Moved || event.kind == .Damaged || event.kind == .Dice_Rolled { event.area_mask |= EVENT_CRITICAL_BIT }
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
		clear_event_log(room.recent_events)
		// Always critical, loaded like a straight bump (player_charges.odin).
		if !player_bump(room, enemy_index, target, .Opponent, true) { return .Blocked }
		outcome := finish_player_combat_command(room)
		switch outcome {
		case .Player_Defeated: return .Player_Defeated
		case .Combat_Ended: return .Combat_Ended
		case .Combat_Continues:
		}
		return .Attacked
	}
	query := query_entity_movement(room, PLAYER_ENTITY, target)
	if !movement_query_is_clear(&query) { return .Blocked }
	clear_event_log(room.recent_events)
	action := make_action(.Move, PLAYER_ENTITY, cell_target(target), .Walkable_Cell)
	added := add_effect(&action, move_effect(PLAYER_ENTITY, target))
	assert(added)
	report := resolve_action(room, &action)
	if !report.accepted { return .Blocked }
	mark_critical_events(&report.events)
	append_event_log(room.recent_events, &report.events)
	collect_loot_in_magnet_range(room)
	room.player.tactical.facing = .North if offset.y < 0 else .South
	ride_stomp(room)
	outcome := finish_player_combat_command(room, player_move_seconds(room))
	switch outcome {
	case .Player_Defeated: return .Player_Defeated
	case .Combat_Ended: return .Combat_Ended
	case .Combat_Continues:
	}
	return .Moved
}
