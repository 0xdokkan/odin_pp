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
	if room.phase != .Combat {
		play.result = .Invalid_Phase
		return
	}
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

	play.action_report = resolve_action(room, &action)
	if !play.action_report.accepted {
		play.result = .Action_Rejected
		play.energy_after = deck.energy
		return
	}

	deck.energy -= definition.cost
	discarded_card, discarded := discard_hand_card(deck, hand_index)
	assert(discarded && discarded_card == play.card)
	record_event(&room.recent_events, {
		kind = .Card_Played,
		source = PLAYER_ENTITY,
		target = PLAYER_ENTITY,
		amount = definition.cost,
		card_id = play.card.id,
		card_definition = play.card.definition_id,
	})
	append_event_log(&room.recent_events, &play.action_report.events)
	collect_loot_in_magnet_range(room)

	if room.phase == .Defeat {
		play.result = .Player_Defeated
		sync_deck_with_room_phase(room)
		play.energy_after = deck.energy
		return
	}
	if room.phase == .Loot {
		play.result = .Combat_Ended
		sync_deck_with_room_phase(room)
		play.energy_after = deck.energy
		return
	}

	play.pulse_report = advance_combat_pulse(room)
	append_event_log(&room.recent_events, &play.pulse_report.events)
	collect_loot_in_magnet_range(room)
	if room.phase == .Defeat {
		play.result = .Player_Defeated
		sync_deck_with_room_phase(room)
		play.energy_after = deck.energy
		return
	}
	if room.phase == .Loot {
		play.result = .Combat_Ended
		sync_deck_with_room_phase(room)
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
		})
	}
	assert(validate_deck_state(deck))
	play.result = .Played
	play.energy_after = deck.energy
	return
}
