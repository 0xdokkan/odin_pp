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
	drawn_card:         Card_Instance,
	drew_card:          bool,
	action_report:      Action_Report,
	pulse_report:       Pulse_Report,
}

card_play_was_committed :: proc(result: Card_Play_Result) -> bool {
	return result == .Played || result == .Combat_Ended || result == .Player_Defeated
}

play_card :: proc(room: ^Room, card_id: u32, target: Target) -> (play: Card_Play_Report) {
	play.result = .Invalid_Room
	if room == nil || room.player == nil {
		return
	}
	if room.phase != .Combat || !tactical_allows_action(room) {
		play.result = .Invalid_Phase
		return
	}
	if !tactical_target_visible(room, target) { play.result = .Action_Rejected; return }
	clear_event_log(&room.recent_events)
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
	definition, definition_found := card_definition_by_id(play.card.definition_id, tactical_enabled(room))
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

	play.action_report = resolve_played_card_action(room, play.card, target, &action)
	if !play.action_report.accepted {
		deck^ = deck_before
		play.result = .Action_Rejected
		play.energy_after = deck.energy
		return
	}

	resolved_card, finished_resolving := finish_resolving_card(deck, play.destination)
	assert(finished_resolving && resolved_card == play.card)
	record_event(&room.recent_events, {
		kind = .Card_Played,
		source = PLAYER_ENTITY,
		target = PLAYER_ENTITY,
		amount = definition.cost,
		card_id = play.card.id,
		card_definition = play.card.definition_id,
		card_upgrade_level = play.card.upgrade_level,
		card_lifetime = play.card.lifetime,
		from_card_zone = .Hand,
		to_card_zone = .Resolving,
	})
	append_event_log(&room.recent_events, &play.action_report.events)
	record_event(&room.recent_events, {
		kind = .Card_Moved,
		source = PLAYER_ENTITY,
		target = PLAYER_ENTITY,
		card_id = play.card.id,
		card_definition = play.card.definition_id,
		card_upgrade_level = play.card.upgrade_level,
		card_lifetime = play.card.lifetime,
		from_card_zone = .Resolving,
		to_card_zone = play.destination,
	})
	apply_card_relics(room, play.destination, &play.action_report)
	pulse_report, outcome := finish_player_combat_command(room, tactical_card_time_cost(play.card.definition_id))
	play.pulse_report = pulse_report
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

	if tactical_enabled(room) {
		room.tactical_pulse.deferred_draws += 1
		play.result = .Played
		play.energy_after = deck.energy
		return
	}

	play.drawn_card, play.drew_card = draw_card(deck)
	if play.drew_card {
		record_event(&room.recent_events, {
			kind = .Card_Drawn,
			source = PLAYER_ENTITY,
			target = PLAYER_ENTITY,
			card_id = play.drawn_card.id,
			card_definition = play.drawn_card.definition_id,
			card_upgrade_level = play.drawn_card.upgrade_level,
			card_lifetime = play.drawn_card.lifetime,
			from_card_zone = .Draw,
			to_card_zone = .Hand,
		})
	}
	assert(validate_deck_state(deck))
	play.result = .Played
	play.energy_after = deck.energy
	return
}
