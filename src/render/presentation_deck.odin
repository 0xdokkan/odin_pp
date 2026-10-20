package render

import game "../game"

// The presented deck replays gameplay events on its own copy. Each operation
// checks its transition before changing the copy and restores it on failure;
// neither a malformed event nor animation timing may alter the real deck.
// Zone policies and deck mutations remain owned by game.

@(private="file")
presentation_card_matches_event :: proc(card: game.Card_Instance, event: game.Game_Event) -> bool {
	return card.id == event.card_id && card.definition_id == event.card_definition &&
	       card.upgrade_level == event.card_upgrade_level && card.lifetime == event.card_lifetime
}

@(private)
apply_presentation_card_played :: proc(deck: ^game.Deck_State, event: game.Game_Event) -> bool {
	if deck == nil || !game.validate_deck_state(deck) || event.amount < 0 ||
	   event.amount > deck.energy || event.from_card_zone != .Hand ||
	   event.to_card_zone != .Resolving || event.source != game.PLAYER_ENTITY ||
	   event.target != game.PLAYER_ENTITY {
		return false
	}
	hand_index, found := game.hand_card_index_by_id(deck, event.card_id)
	if !found {
		return false
	}
	card := deck.hand[hand_index]
	definition, definition_found := game.card_definition_by_id(card.definition_id)
	if !game.validate_card_instance(card) || !presentation_card_matches_event(card, event) ||
	   !definition_found || definition.cost != event.amount {
		return false
	}

	before := deck^
	deck.energy -= event.amount
	resolving_card, resolving := game.begin_resolving_hand_card(deck, hand_index)
	if !resolving || resolving_card != card || !game.validate_deck_state(deck) {
		deck^ = before
		return false
	}
	return true
}

@(private)
apply_presentation_card_moved :: proc(deck: ^game.Deck_State, event: game.Game_Event) -> bool {
	if deck == nil || !game.validate_deck_state(deck) || event.target != game.PLAYER_ENTITY ||
	   (event.from_card_zone != .Hand && event.from_card_zone != .Resolving) ||
	   (event.to_card_zone != .Discard && event.to_card_zone != .Exhaust) {
		return false
	}
	card: game.Card_Instance
	hand_index := 0
	if event.from_card_zone == .Hand {
		found: bool
		hand_index, found = game.hand_card_index_by_id(deck, event.card_id)
		if !found {
			return false
		}
		card = deck.hand[hand_index]
	} else {
		if !deck.has_resolving_card {
			return false
		}
		card = deck.resolving_card
		expected_destination, valid_destination := game.card_destination_after_play(card)
		if !valid_destination || event.to_card_zone != expected_destination {
			return false
		}
	}
	if !game.validate_card_instance(card) || !presentation_card_matches_event(card, event) {
		return false
	}

	before := deck^
	moved_card: game.Card_Instance
	moved := false
	if event.from_card_zone == .Hand {
		moved_card, moved = game.move_hand_card_to_zone(deck, hand_index, event.to_card_zone)
	} else {
		moved_card, moved = game.finish_resolving_card(deck, event.to_card_zone)
	}
	if !moved || !game.validate_card_instance(moved_card) || !presentation_card_matches_event(moved_card, event) ||
	   (event.from_card_zone == .Hand && moved_card != card) || !game.validate_deck_state(deck) {
		deck^ = before
		return false
	}
	return true
}

@(private)
apply_presentation_card_drawn :: proc(deck: ^game.Deck_State, event: game.Game_Event) -> bool {
	if deck == nil || !game.validate_deck_state(deck) || event.target != game.PLAYER_ENTITY ||
	   event.from_card_zone != .Draw || event.to_card_zone != .Hand {
		return false
	}
	before := deck^
	drawn_card, drawn := game.draw_card(deck)
	if !drawn || !game.validate_deck_state(deck) || !presentation_card_matches_event(drawn_card, event) {
		deck^ = before
		return false
	}
	return true
}

@(private)
apply_presentation_card_created :: proc(deck: ^game.Deck_State, event: game.Game_Event) -> bool {
	if deck == nil || !game.validate_deck_state(deck) || event.target != game.PLAYER_ENTITY ||
	   event.from_card_zone != .Count || event.to_card_zone != .Hand ||
	   event.card_lifetime != .Combat {
		return false
	}

	before := deck^
	created_card, created := game.create_temporary_card(
		deck,
		event.card_definition,
		event.card_upgrade_level,
	)
	if !created || !game.validate_deck_state(deck) || !presentation_card_matches_event(created_card, event) {
		deck^ = before
		return false
	}
	return true
}

@(private)
apply_presentation_hand_refocused :: proc(deck: ^game.Deck_State, event: game.Game_Event) -> bool {
	return deck != nil && game.validate_deck_state(deck) && event.source == game.PLAYER_ENTITY &&
	       event.target == game.PLAYER_ENTITY && event.amount == i32(deck.hand_count)
}

@(private)
apply_presentation_card_refocused :: proc(deck: ^game.Deck_State, event: game.Game_Event) -> bool {
	if deck == nil || !game.validate_deck_state(deck) || event.source != game.PLAYER_ENTITY ||
	   event.target != game.PLAYER_ENTITY || event.from_card_zone != .Hand {
		return false
	}
	hand_index, found := game.hand_card_index_by_id(deck, event.card_id)
	if !found {
		return false
	}
	card := deck.hand[hand_index]
	if !game.validate_card_instance(card) || !presentation_card_matches_event(card, event) {
		return false
	}
	expected_destination, valid_destination := game.card_destination_after_refocus(card)
	if !valid_destination || event.to_card_zone != expected_destination {
		return false
	}
	if expected_destination == .Hand {
		return true
	}
	if expected_destination != .Discard && expected_destination != .Exhaust {
		return false
	}

	before := deck^
	moved_card, moved := game.move_hand_card_to_zone(deck, hand_index, expected_destination)
	if !moved || moved_card != card || !game.validate_deck_state(deck) {
		deck^ = before
		return false
	}
	return true
}
