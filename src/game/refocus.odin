package game

Refocus_Result :: enum {
	Refocused,
	Combat_Ended,
	Player_Defeated,
	Invalid_Room,
	Invalid_Phase,
	Invalid_Deck,
	Card_Resolving,
	Cleanup_Failed,
}

Refocus_Report :: struct {
	result:        Refocus_Result,
	hand_report:   Deck_Refocus_Report,
	energy_before: i32,
	energy_after:  i32,
}

refocus_was_committed :: proc(result: Refocus_Result) -> bool {
	return result == .Refocused || result == .Combat_Ended || result == .Player_Defeated
}

@(private = "file")
record_refocused_card :: proc(log: ^Event_Log, outcome: Card_Refocus_Outcome) -> bool {
	return record_event(log, make_card_zone_event(
		.Card_Refocused, PLAYER_ENTITY, PLAYER_ENTITY, outcome.card, .Hand, outcome.destination,
	))
}

refocus_player_hand :: proc(room: ^Room) -> (refocus: Refocus_Report) {
	refocus.result = .Invalid_Room
	if room == nil || room.player == nil {
		return
	}
	// Behind his eyes his hand is put away (first_person.odin).
	if room.phase != .Combat || !tactical_control_allowed(room, .Board_Action) {
		refocus.result = .Invalid_Phase
		return
	}

	deck := &room.player.deck
	if !deck.combat_active || !validate_deck_state(deck) {
		refocus.result = .Invalid_Deck
		return
	}
	if deck.has_resolving_card {
		refocus.result = .Card_Resolving
		return
	}
	refocus.energy_before = deck.energy

	staged_deck := deck^
	hand_report, cleanup_ok := refocus_deck_hand(&staged_deck)
	if !cleanup_ok {
		refocus.result = .Cleanup_Failed
		refocus.energy_after = deck.energy
		return
	}
	refocus.hand_report = hand_report
	staged_events := Event_Log{}
	if !record_event(&staged_events, {
		kind = .Hand_Refocused,
		source = PLAYER_ENTITY,
		target = PLAYER_ENTITY,
		amount = i32(refocus.hand_report.outcome_count),
	}) {
		refocus.result = .Cleanup_Failed
		refocus.energy_after = deck.energy
		return
	}
	for index in 0..<refocus.hand_report.outcome_count {
		if !record_refocused_card(&staged_events, refocus.hand_report.outcomes[index]) {
			refocus.result = .Cleanup_Failed
			refocus.energy_after = deck.energy
			return
		}
	}
	if !validate_deck_state(&staged_deck) {
		refocus.result = .Cleanup_Failed
		refocus.energy_after = deck.energy
		return
	}

	deck^ = staged_deck
	copy_event_log(room.recent_events, &staged_events)
	outcome := finish_player_combat_command(room, TACTICAL_REFOCUS_SECONDS)
	switch outcome {
	case .Player_Defeated:
		refocus.result = .Player_Defeated
		refocus.energy_after = deck.energy
		return
	case .Combat_Ended:
		refocus.result = .Combat_Ended
		refocus.energy_after = deck.energy
		return
	case .Combat_Continues:
	}

	room.tactical_pulse.refill = true
	for card_outcome in refocus.hand_report.outcomes[:refocus.hand_report.outcome_count] {
		if card_outcome.destination == .Exhaust { room.tactical_pulse.exhaust_relic = true }
	}
	refocus.result = .Refocused
	refocus.energy_after = deck.energy
	return
}
