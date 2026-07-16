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
	drawn_cards:   [MAX_HAND_CARDS]Card_Instance,
	drawn_count:   int,
	energy_before: i32,
	energy_after:  i32,
	pulse_report:  Pulse_Report,
}

refocus_was_committed :: proc(result: Refocus_Result) -> bool {
	return result == .Refocused || result == .Combat_Ended || result == .Player_Defeated
}

record_refocused_card :: proc(log: ^Event_Log, outcome: Card_Refocus_Outcome) -> bool {
	return record_event(log, {
		kind = .Card_Refocused,
		source = PLAYER_ENTITY,
		target = PLAYER_ENTITY,
		card_id = outcome.card.id,
		card_definition = outcome.card.definition_id,
		card_upgrade_level = outcome.card.upgrade_level,
		card_lifetime = outcome.card.lifetime,
		from_card_zone = .Hand,
		to_card_zone = outcome.destination,
	})
}

record_refocus_draw :: proc(log: ^Event_Log, card: Card_Instance) -> bool {
	return record_event(log, {
		kind = .Card_Drawn,
		source = PLAYER_ENTITY,
		target = PLAYER_ENTITY,
		card_id = card.id,
		card_definition = card.definition_id,
		card_upgrade_level = card.upgrade_level,
		card_lifetime = card.lifetime,
		from_card_zone = .Draw,
		to_card_zone = .Hand,
	})
}

refocus_player_hand :: proc(room: ^Room) -> (refocus: Refocus_Report) {
	refocus.result = .Invalid_Room
	if room == nil || room.player == nil {
		return
	}
	if room.phase != .Combat {
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
	room.recent_events = staged_events
	pulse_report, outcome := finish_player_combat_command(room)
	refocus.pulse_report = pulse_report
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

	for deck.hand_count < deck.rules.hand_size {
		card, drawn := draw_card(deck)
		if !drawn {
			break
		}
		refocus.drawn_cards[refocus.drawn_count] = card
		refocus.drawn_count += 1
		record_refocus_draw(&room.recent_events, card)
	}
	assert(validate_deck_state(deck))
	refocus.result = .Refocused
	refocus.energy_after = deck.energy
	return
}
