package game

Card_Play_Result :: enum {
	Played,
	Combat_Ended,
	Player_Defeated,
	Invalid_Room,
	Invalid_Phase,
	Invalid_Deck,
	Card_Not_In_Hand,
	Invalid_Card,
	Not_Enough_Energy,
	Compile_Failed,
	Action_Rejected,
}

Card_Play_Report :: struct {
	result:             Card_Play_Result,
	compile_error:      Card_Compile_Error,
	card:               Card_Instance,
	cost:               i32,
	energy_before:      i32,
	energy_after:       i32,
	destination:        Card_Zone,
	action_report:      Action_Report,
}

card_play_was_committed :: proc(result: Card_Play_Result) -> bool {
	return result == .Played || result == .Combat_Ended || result == .Player_Defeated
}

play_card :: proc(room: ^Room, card_id: u32, target: Target) -> (play: Card_Play_Report) {
	play.result = .Invalid_Room
	if room == nil || room.player == nil {
		return
	}
	if room.phase != .Combat || !tactical_allows_cards(room) {
		play.result = .Invalid_Phase
		return
	}
	if !tactical_target_visible(room, target) { play.result = .Action_Rejected; return }
	clear_event_log(room.recent_events)
	deck := &room.player.deck
	if !deck.combat_active || !validate_deck_state(deck) {
		play.result = .Invalid_Deck
		return
	}

	hand_index, found := hand_card_index_by_id(deck, card_id)
	if !found {
		play.result = .Card_Not_In_Hand
		return
	}
	play.card = deck.hand[hand_index]
	definition, definition_found := card_definition_by_id(play.card.definition_id)
	if !definition_found || !validate_card_instance(play.card) || !validate_card_definition(&definition) {
		play.result = .Invalid_Card
		return
	}
	play.cost = definition.cost
	play.energy_before = deck.energy

	action, compile_error := compile_card_action(room, play.card, target)
	play.compile_error = compile_error
	if compile_error != .None {
		play.result = .Compile_Failed
		play.energy_after = deck.energy
		return
	}
	if deck.energy < definition.cost {
		play.result = .Not_Enough_Energy
		play.energy_after = deck.energy
		return
	}

	deck_before := deck^
	deck.energy -= definition.cost
	destination, valid_destination := card_destination_after_play(play.card)
	assert(valid_destination)
	play.destination = destination
	resolving_card, began_resolving := begin_resolving_hand_card(deck, hand_index)
	assert(began_resolving && resolving_card == play.card)

	// A card played on the tick resolves its critical version.
	critical := tactical_take_critical(room)
	room.player.tactical.critical_card = critical
	play.action_report = resolve_played_card_action(room, play.card, target, &action)
	room.player.tactical.critical_card = false
	if critical { mark_critical_events(&play.action_report.events) }
	if !play.action_report.accepted {
		deck^ = deck_before
		play.result = .Action_Rejected
		play.energy_after = deck.energy
		return
	}

	resolved_card, finished_resolving := finish_resolving_card(deck, play.destination)
	assert(finished_resolving && resolved_card == play.card)
	played_event := make_card_zone_event(
		.Card_Played, PLAYER_ENTITY, PLAYER_ENTITY, play.card, .Hand, .Resolving,
	)
	played_event.amount = definition.cost
	played_event.area_mask = EVENT_CRITICAL_BIT if critical else 0
	record_event(room.recent_events, played_event)
	append_event_log(room.recent_events, &play.action_report.events)
	record_event(room.recent_events, make_card_zone_event(
		.Card_Moved, PLAYER_ENTITY, PLAYER_ENTITY, play.card, .Resolving, play.destination,
	))
	apply_card_relics(room, play.destination, &play.action_report)
	// The card pays its time through its cast.
	outcome := finish_player_combat_command(room, 0)
	switch outcome {
	case .Player_Defeated:
		play.result = .Player_Defeated
		play.energy_after = deck.energy
		return
	case .Combat_Ended:
		play.result = .Combat_Ended
		play.energy_after = deck.energy
		return
	case .Combat_Continues:
	}

	seconds := tactical_card_time_cost(play.card.definition_id)
	tactical_begin_card_cast(room, seconds)
	tactical_count_card(room)
	room.tactical_pulse.deferred_draws += 1
	// A card that takes no time has no cast to wait for: it is a decision
	// of its own, and its replacement is drawn now.
	if seconds <= 0 {
		room.player.tactical.metrics.decisions += 1
		tactical_refill(room)
	}
	play.result = .Played
	play.energy_after = deck.energy
	return
}
