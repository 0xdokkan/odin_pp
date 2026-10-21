package game

import rng "../engine/rng"

MAX_OWNED_CARDS     :: 32
// A hand holds up to MAX_HAND_CARDS: its draws and the cards made into it
// stop there. Rules that deal more at once (PROVA MECCANICHE's whole deck,
// main/mechanics_lab.odin) hold their hand size instead, up to
// MAX_HAND_CAPACITY, the hand's room (deck_hand_limit).
MAX_HAND_CARDS      :: 8
MAX_HAND_CAPACITY   :: 10
MAX_TEMPORARY_CARDS :: 16
MAX_COMBAT_CARDS    :: MAX_OWNED_CARDS+MAX_TEMPORARY_CARDS
MIN_OWNED_CARDS     :: 5

// La validazione profonda di zone e ownership e O(carte al quadrato) e gira su
// ogni primitiva del deck. I confini transazionali (begin combat, play,
// refocus, shop) validano sempre per intero; -define:DECK_DEEP_VALIDATION=false
// riduce le primitive interne ai soli controlli strutturali economici.
DECK_DEEP_VALIDATION :: #config(DECK_DEEP_VALIDATION, true)

STARTING_HAND_SIZE             :: 5
DEFAULT_MAX_ENERGY             :: i32(3)
DEFAULT_ENERGY_REGEN_PER_PULSE :: i32(1)
DEFAULT_DECK_SEED              :: u64(0x9E3779B97F4A7C15)

Deck_Rules :: struct {
	hand_size:                int,
	max_energy:               i32,
	energy_regen_per_pulse:   i32,
}

DEFAULT_DECK_RULES :: Deck_Rules{
	hand_size = STARTING_HAND_SIZE,
	max_energy = DEFAULT_MAX_ENERGY,
	energy_regen_per_pulse = DEFAULT_ENERGY_REGEN_PER_PULSE,
}

Card_Lifetime :: enum {
	Permanent,
	Combat,
	Count,
}

Card_Zone :: enum {
	Draw,
	Hand,
	Discard,
	Exhaust,
	Resolving,
	Count,
}

Deck_State :: struct {
	owned:             [MAX_OWNED_CARDS]Card_Instance,
	owned_count:       int,
	draw_pile:         [MAX_COMBAT_CARDS]Card_Instance,
	draw_count:        int,
	hand:              [MAX_HAND_CAPACITY]Card_Instance,
	hand_count:        int,
	discard_pile:      [MAX_COMBAT_CARDS]Card_Instance,
	discard_count:     int,
	exhaust_pile:      [MAX_COMBAT_CARDS]Card_Instance,
	exhaust_count:     int,
	resolving_card:    Card_Instance,
	has_resolving_card: bool,
	energy:            i32,
	rules:             Deck_Rules,
	next_card_id:      u32,
	combat_card_id_floor: u32,
	random_state:      u64,
	combat_active:     bool,
}

Deck_Mutation_Result :: enum {
	Invalid,
	Upgraded,
	Removed,
	Card_Not_Found,
	Maximum_Upgrade,
	Upgrade_Unavailable,
	Minimum_Deck_Size,
}

Card_Refocus_Outcome :: struct {
	card:        Card_Instance,
	destination: Card_Zone,
}

Deck_Refocus_Report :: struct {
	outcomes:        [MAX_HAND_CAPACITY]Card_Refocus_Outcome,
	outcome_count:   int,
	retained_count:  int,
	discarded_count: int,
	exhausted_count: int,
}

@(private)
deck_rules_are_valid :: proc(rules: Deck_Rules) -> bool {
	return rules.hand_size > 0 && rules.hand_size <= MAX_HAND_CAPACITY &&
	       rules.max_energy > 0 && rules.energy_regen_per_pulse >= 0
}

// How many cards the hand of `deck` may hold: MAX_HAND_CARDS, or its rules'
// hand size when they deal more at once.
deck_hand_limit :: proc(deck: ^Deck_State) -> int {
	return max(MAX_HAND_CARDS, deck.rules.hand_size)
}

@(private = "file")
normalized_deck_seed :: proc(seed: u64) -> u64 {
	if seed == 0 {
		return DEFAULT_DECK_SEED
	}
	return seed
}

initialize_empty_deck :: proc(
	deck: ^Deck_State,
	rules: Deck_Rules = DEFAULT_DECK_RULES,
	seed: u64 = DEFAULT_DECK_SEED,
) -> bool {
	if deck == nil || !deck_rules_are_valid(rules) {
		return false
	}
	deck^ = {
		rules = rules,
		next_card_id = 1,
		random_state = normalized_deck_seed(seed),
	}
	return true
}

owned_card_index_by_id :: proc(deck: ^Deck_State, id: u32) -> (int, bool) {
	if deck == nil || id == 0 || deck.owned_count < 0 || deck.owned_count > MAX_OWNED_CARDS {
		return 0, false
	}
	for index in 0..<deck.owned_count {
		if deck.owned[index].id == id {
			return index, true
		}
	}
	return 0, false
}

hand_card_index_by_id :: proc(deck: ^Deck_State, id: u32) -> (int, bool) {
	if deck == nil || id == 0 || deck.hand_count < 0 || deck.hand_count > MAX_HAND_CAPACITY {
		return 0, false
	}
	for index in 0..<deck.hand_count {
		if deck.hand[index].id == id {
			return index, true
		}
	}
	return 0, false
}

add_owned_card :: proc(
	deck: ^Deck_State,
	definition_id: Card_Id,
	upgrade_level: i32 = 0,
) -> (Card_Instance, bool) {
	if deck == nil || deck.combat_active || deck.owned_count < 0 ||
	   deck.owned_count >= MAX_OWNED_CARDS || deck.next_card_id == 0 ||
	   deck.next_card_id == max(u32) || !validate_deck_state(deck) {
		return {}, false
	}
	definition, found := card_definition_by_id(definition_id)
	if !found || definition.temporary_only {
		return {}, false
	}
	instance := Card_Instance{
		id = deck.next_card_id,
		definition_id = definition_id,
		upgrade_level = upgrade_level,
		lifetime = .Permanent,
	}
	if !validate_card_instance(instance) {
		return {}, false
	}
	deck.owned[deck.owned_count] = instance
	deck.owned_count += 1
	deck.next_card_id += 1
	return instance, true
}

upgrade_owned_card :: proc(deck: ^Deck_State, card_id: u32) -> Deck_Mutation_Result {
	if deck == nil || deck.combat_active || !validate_deck_state(deck) {
		return .Invalid
	}
	card_index, found := owned_card_index_by_id(deck, card_id)
	if !found {
		return .Card_Not_Found
	}
	if deck.owned[card_index].upgrade_level >= card_max_upgrade_level(deck.owned[card_index].definition_id) {
		return .Maximum_Upgrade
	}
	if !card_can_upgrade(deck.owned[card_index]) {
		return .Upgrade_Unavailable
	}

	upgraded := deck.owned[card_index]
	upgraded.upgrade_level += 1
	// A card that evolves becomes the next one at its upgrade (the Cannone, at its
	// second, the Cannone laser, which starts again from its own level 0).
	if definition, defined := card_definition_by_id(upgraded.definition_id); defined && definition.evolve_level > 0 &&
	   upgraded.upgrade_level >= definition.evolve_level {
		upgraded.definition_id, upgraded.upgrade_level = definition.evolves_to, 0
	}
	if !validate_card_instance(upgraded) {
		return .Invalid
	}
	deck.owned[card_index] = upgraded
	assert(validate_deck_state(deck))
	return .Upgraded
}

@(private)
remove_owned_card :: proc(deck: ^Deck_State, card_id: u32) -> Deck_Mutation_Result {
	if deck == nil || deck.combat_active || !validate_deck_state(deck) {
		return .Invalid
	}
	if deck.owned_count <= MIN_OWNED_CARDS {
		return .Minimum_Deck_Size
	}
	card_index, found := owned_card_index_by_id(deck, card_id)
	if !found {
		return .Card_Not_Found
	}

	for index in card_index..<deck.owned_count-1 {
		deck.owned[index] = deck.owned[index+1]
	}
	deck.owned_count -= 1
	deck.owned[deck.owned_count] = {}
	assert(validate_deck_state(deck))
	return .Removed
}

initialize_starter_deck :: proc(deck: ^Deck_State, seed: u64 = DEFAULT_DECK_SEED) -> bool {
	if !initialize_empty_deck(deck, DEFAULT_DECK_RULES, seed) {
		return false
	}
	starter_cards := [?]Card_Id{
		.Strike,
		.Arc_Bolt,
		.Piercing_Ray,
		.Shove,
		.Firebomb,
		.Guard,
		.Toxic_Wave,
		.Thorn_Coat,
		.Afterimage,
		.Dash,
	}
	for definition_id in starter_cards {
		_, added := add_owned_card(deck, definition_id)
		assert(added)
	}
	return validate_deck_state(deck)
}

@(private)
reseed_deck :: proc(deck: ^Deck_State, seed: u64) -> bool {
	if deck == nil || deck.combat_active {
		return false
	}
	deck.random_state = normalized_deck_seed(seed)
	return true
}

@(private)
deck_next_random :: proc(deck: ^Deck_State) -> u64 {
	assert(deck != nil && deck.random_state != 0)
	return rng.step(&deck.random_state)
}

@(private = "file")
shuffle_draw_pile :: proc(deck: ^Deck_State) {
	assert(deck != nil && deck.draw_count >= 0 && deck.draw_count <= MAX_COMBAT_CARDS)
	for index := deck.draw_count-1; index > 0; index -= 1 {
		swap_index := int(deck_next_random(deck)%u64(index+1))
		deck.draw_pile[index], deck.draw_pile[swap_index] =
			deck.draw_pile[swap_index], deck.draw_pile[index]
	}
}

@(private)
can_draw_card :: proc(deck: ^Deck_State) -> bool {
	return deck != nil && deck.combat_active && deck_state_is_consistent(deck) &&
	       deck.hand_count < deck_hand_limit(deck) &&
	       (deck.draw_count > 0 || deck.discard_count > 0)
}

draw_card :: proc(deck: ^Deck_State) -> (card: Card_Instance, ok: bool) {
	if !can_draw_card(deck) {
		return {}, false
	}

	staged := deck^
	if staged.draw_count == 0 {
		for index in 0..<staged.discard_count {
			staged.draw_pile[index] = staged.discard_pile[index]
			staged.discard_pile[index] = {}
		}
		staged.draw_count = staged.discard_count
		staged.discard_count = 0
		shuffle_draw_pile(&staged)
	}

	staged.draw_count -= 1
	card = staged.draw_pile[staged.draw_count]
	staged.draw_pile[staged.draw_count] = {}
	staged.hand[staged.hand_count] = card
	staged.hand_count += 1
	assert(deck_state_is_consistent(&staged))
	deck^ = staged
	return card, true
}

@(private)
draw_to_hand_size :: proc(deck: ^Deck_State) -> (drawn: int) {
	if deck == nil || !deck.combat_active {
		return
	}
	for deck.hand_count < deck.rules.hand_size {
		_, ok := draw_card(deck)
		if !ok {
			break
		}
		drawn += 1
	}
	return
}

begin_deck_combat :: proc(deck: ^Deck_State) -> bool {
	if deck == nil || deck.combat_active || !validate_deck_state(deck) || deck.owned_count <= 0 {
		return false
	}

	staged := deck^
	staged.draw_pile = {}
	staged.hand = {}
	staged.discard_pile = {}
	staged.exhaust_pile = {}
	staged.resolving_card = {}
	staged.draw_count = staged.owned_count
	staged.hand_count = 0
	staged.discard_count = 0
	staged.exhaust_count = 0
	staged.has_resolving_card = false
	staged.energy = staged.rules.max_energy
	staged.combat_card_id_floor = staged.next_card_id
	staged.combat_active = true
	// A room tool (the Canna da Pesca) is never drawn: it waits out the fight
	// in Exhaust, which nothing draws or reshuffles from.
	staged.draw_count = 0
	for card in staged.owned[:staged.owned_count] {
		if card_is_room_tool(card.definition_id) {
			staged.exhaust_pile[staged.exhaust_count] = card
			staged.exhaust_count += 1
		} else {
			staged.draw_pile[staged.draw_count] = card
			staged.draw_count += 1
		}
	}
	shuffle_draw_pile(&staged)
	draw_to_hand_size(&staged)
	if !validate_deck_state(&staged) {
		return false
	}
	deck^ = staged
	return true
}

// The cards a fight exhausted, not counting the room tools that only wait
// there (begin_deck_combat): what the hand's counters show.
deck_exhausted_count :: proc(deck: ^Deck_State) -> (count: int) {
	if deck == nil { return }
	for card in deck.exhaust_pile[:clamp(deck.exhaust_count, 0, MAX_COMBAT_CARDS)] {
		if !card_is_room_tool(card.definition_id) { count += 1 }
	}
	return
}

finish_deck_combat :: proc(deck: ^Deck_State) {
	if deck == nil {
		return
	}
	deck.draw_pile = {}
	deck.hand = {}
	deck.discard_pile = {}
	deck.exhaust_pile = {}
	deck.resolving_card = {}
	deck.draw_count = 0
	deck.hand_count = 0
	deck.discard_count = 0
	deck.exhaust_count = 0
	deck.has_resolving_card = false
	deck.energy = 0
	deck.combat_card_id_floor = 0
	deck.combat_active = false
}

@(private)
sync_deck_with_room_phase :: proc(room: ^Room) {
	if room != nil && room.player != nil && room.phase != .Combat {
		finish_deck_combat(&room.player.deck)
	}
}

@(private = "file")
can_move_hand_card_to_zone :: proc(
	deck: ^Deck_State,
	hand_index: int,
	destination: Card_Zone,
) -> bool {
	if deck == nil || !deck.combat_active || !deck_state_is_consistent(deck) ||
	   hand_index < 0 || hand_index >= deck.hand_count {
		return false
	}
	switch destination {
	case .Discard:
		return deck.discard_count < MAX_COMBAT_CARDS
	case .Exhaust:
		return deck.exhaust_count < MAX_COMBAT_CARDS
	case .Draw, .Hand, .Resolving, .Count:
	}
	return false
}

@(private)
can_discard_hand_card :: proc(deck: ^Deck_State, hand_index: int) -> bool {
	return can_move_hand_card_to_zone(deck, hand_index, .Discard)
}

move_hand_card_to_zone :: proc(
	deck: ^Deck_State,
	hand_index: int,
	destination: Card_Zone,
) -> (Card_Instance, bool) {
	if !can_move_hand_card_to_zone(deck, hand_index, destination) {
		return {}, false
	}

	staged := deck^
	card := staged.hand[hand_index]
	for index in hand_index..<staged.hand_count-1 {
		staged.hand[index] = staged.hand[index+1]
	}
	staged.hand_count -= 1
	staged.hand[staged.hand_count] = {}
	switch destination {
	case .Discard:
		staged.discard_pile[staged.discard_count] = card
		staged.discard_count += 1
	case .Exhaust:
		staged.exhaust_pile[staged.exhaust_count] = card
		staged.exhaust_count += 1
	case .Draw, .Hand, .Resolving, .Count:
		unreachable()
	}
	assert(deck_state_is_consistent(&staged))
	deck^ = staged
	return card, true
}

discard_hand_card :: proc(deck: ^Deck_State, hand_index: int) -> (Card_Instance, bool) {
	return move_hand_card_to_zone(deck, hand_index, .Discard)
}

@(private)
exhaust_hand_card :: proc(deck: ^Deck_State, hand_index: int) -> (Card_Instance, bool) {
	return move_hand_card_to_zone(deck, hand_index, .Exhaust)
}

refocus_deck_hand :: proc(deck: ^Deck_State) -> (report: Deck_Refocus_Report, ok: bool) {
	if deck == nil || !deck.combat_active || deck.has_resolving_card ||
	   !deck_state_is_consistent(deck) {
		return
	}

	original_hand := deck.hand
	original_count := deck.hand_count
	staged := deck^
	for index in 0..<original_count {
		card := original_hand[index]
		destination, valid_destination := card_destination_after_refocus(card)
		if !valid_destination {
			return {}, false
		}
		if destination == .Hand {
			report.retained_count += 1
		} else {
			hand_index, found := hand_card_index_by_id(&staged, card.id)
			if !found {
				return {}, false
			}
			moved_card, moved := move_hand_card_to_zone(&staged, hand_index, destination)
			if !moved || moved_card != card {
				return {}, false
			}
			if destination == .Discard {
				report.discarded_count += 1
			} else if destination == .Exhaust {
				report.exhausted_count += 1
			} else {
				return {}, false
			}
		}
		report.outcomes[report.outcome_count] = {card = card, destination = destination}
		report.outcome_count += 1
	}
	if report.outcome_count != original_count || !deck_state_is_consistent(&staged) {
		return {}, false
	}
	deck^ = staged
	return report, true
}

begin_resolving_hand_card :: proc(
	deck: ^Deck_State,
	hand_index: int,
) -> (Card_Instance, bool) {
	if deck == nil || !deck.combat_active || !deck_state_is_consistent(deck) ||
	   deck.has_resolving_card || hand_index < 0 || hand_index >= deck.hand_count {
		return {}, false
	}

	staged := deck^
	card := staged.hand[hand_index]
	for index in hand_index..<staged.hand_count-1 {
		staged.hand[index] = staged.hand[index+1]
	}
	staged.hand_count -= 1
	staged.hand[staged.hand_count] = {}
	staged.resolving_card = card
	staged.has_resolving_card = true
	assert(deck_state_is_consistent(&staged))
	deck^ = staged
	return card, true
}

finish_resolving_card :: proc(
	deck: ^Deck_State,
	destination: Card_Zone,
) -> (Card_Instance, bool) {
	if deck == nil || !deck.combat_active || !deck_state_is_consistent(deck) ||
	   !deck.has_resolving_card ||
	   (destination != .Discard && destination != .Exhaust) {
		return {}, false
	}
	if destination == .Discard && deck.discard_count >= MAX_COMBAT_CARDS {
		return {}, false
	}
	if destination == .Exhaust && deck.exhaust_count >= MAX_COMBAT_CARDS {
		return {}, false
	}

	staged := deck^
	card := staged.resolving_card
	staged.resolving_card = {}
	staged.has_resolving_card = false
	if destination == .Discard {
		staged.discard_pile[staged.discard_count] = card
		staged.discard_count += 1
	} else {
		staged.exhaust_pile[staged.exhaust_count] = card
		staged.exhaust_count += 1
	}
	assert(deck_state_is_consistent(&staged))
	deck^ = staged
	return card, true
}

@(private)
combat_temporary_card_count :: proc(deck: ^Deck_State) -> int {
	if deck == nil || !deck.combat_active {
		return 0
	}
	resolving_count := 0
	if deck.has_resolving_card {
		resolving_count = 1
	}
	return deck.draw_count+deck.hand_count+deck.discard_count+deck.exhaust_count+
	       resolving_count-
	       deck.owned_count
}

@(private)
can_create_temporary_card :: proc(
	deck: ^Deck_State,
	definition_id: Card_Id,
	upgrade_level: i32 = 0,
) -> bool {
	if deck == nil || !deck.combat_active || !deck_state_is_consistent(deck) ||
	   deck.hand_count >= deck_hand_limit(deck) || deck.next_card_id == max(u32) ||
	   combat_temporary_card_count(deck) >= MAX_TEMPORARY_CARDS ||
	   deck.draw_count+deck.hand_count+deck.discard_count+deck.exhaust_count+
	   (1 if deck.has_resolving_card else 0) >= MAX_COMBAT_CARDS {
		return false
	}
	instance := Card_Instance{
		id = deck.next_card_id,
		definition_id = definition_id,
		upgrade_level = upgrade_level,
		lifetime = .Combat,
	}
	return validate_card_instance(instance)
}

create_temporary_card :: proc(
	deck: ^Deck_State,
	definition_id: Card_Id,
	upgrade_level: i32 = 0,
) -> (Card_Instance, bool) {
	if !can_create_temporary_card(deck, definition_id, upgrade_level) {
		return {}, false
	}

	staged := deck^
	instance := Card_Instance{
		id = staged.next_card_id,
		definition_id = definition_id,
		upgrade_level = upgrade_level,
		lifetime = .Combat,
	}
	staged.hand[staged.hand_count] = instance
	staged.hand_count += 1
	staged.next_card_id += 1
	assert(deck_state_is_consistent(&staged))
	deck^ = staged
	return instance, true
}

@(private)
restore_deck_energy_after_pulse :: proc(deck: ^Deck_State) -> i32 {
	if deck == nil || !deck.combat_active || deck.energy >= deck.rules.max_energy {
		return 0
	}
	before := deck.energy
	deck.energy = min(deck.rules.max_energy, deck.energy+deck.rules.energy_regen_per_pulse)
	return deck.energy-before
}

@(private = "file")
deck_counts_are_valid :: proc(deck: ^Deck_State) -> bool {
	return deck != nil && deck_rules_are_valid(deck.rules) && deck.random_state != 0 &&
	       deck.next_card_id != 0 && deck.owned_count >= 0 && deck.owned_count <= MAX_OWNED_CARDS &&
	       deck.draw_count >= 0 && deck.draw_count <= MAX_COMBAT_CARDS &&
	       deck.hand_count >= 0 && deck.hand_count <= deck_hand_limit(deck) &&
	       deck.discard_count >= 0 && deck.discard_count <= MAX_COMBAT_CARDS &&
	       deck.exhaust_count >= 0 && deck.exhaust_count <= MAX_COMBAT_CARDS
}

@(private = "file")
deck_state_is_consistent :: proc(deck: ^Deck_State) -> bool {
	when DECK_DEEP_VALIDATION {
		return validate_deck_state(deck)
	} else {
		return deck_counts_are_valid(deck)
	}
}

validate_deck_state :: proc(deck: ^Deck_State) -> bool {
	if !deck_counts_are_valid(deck) {
		return false
	}

	for index in 0..<deck.owned_count {
		card := deck.owned[index]
		definition, found := card_definition_by_id(card.definition_id)
		if !found || definition.temporary_only || !validate_card_instance(card) ||
		   card.lifetime != .Permanent || card.id >= deck.next_card_id {
			return false
		}
		for previous in 0..<index {
			if deck.owned[previous].id == card.id {
				return false
			}
		}
	}

	if !deck.combat_active {
		return deck.draw_count == 0 && deck.hand_count == 0 &&
		       deck.discard_count == 0 && deck.exhaust_count == 0 &&
		       !deck.has_resolving_card && deck.resolving_card == (Card_Instance{}) &&
		       deck.energy == 0 && deck.combat_card_id_floor == 0
	}
	if deck.combat_card_id_floor == 0 || deck.combat_card_id_floor > deck.next_card_id ||
	   deck.energy < 0 || deck.energy > deck.rules.max_energy {
		return false
	}
	for index in 0..<deck.owned_count {
		if deck.owned[index].id >= deck.combat_card_id_floor {
			return false
		}
	}

	resolving_count := 0
	if deck.has_resolving_card {
		resolving_count = 1
	} else if deck.resolving_card != (Card_Instance{}) {
		return false
	}
	total_cards := deck.draw_count+deck.hand_count+deck.discard_count+deck.exhaust_count+
	               resolving_count
	if total_cards < deck.owned_count || total_cards > MAX_COMBAT_CARDS {
		return false
	}

	seen_owned: [MAX_OWNED_CARDS]bool
	seen_ids: [MAX_COMBAT_CARDS]u32
	seen_count := 0
	temporary_count := 0
	resolving_zone: [1]Card_Instance
	if deck.has_resolving_card {
		resolving_zone[0] = deck.resolving_card
	}
	zones := [?][]Card_Instance{
		deck.draw_pile[:deck.draw_count],
		deck.hand[:deck.hand_count],
		deck.discard_pile[:deck.discard_count],
		deck.exhaust_pile[:deck.exhaust_count],
		resolving_zone[:resolving_count],
	}
	for zone in zones {
		for card in zone {
			if !validate_card_instance(card) || card.id >= deck.next_card_id {
				return false
			}
			for previous in 0..<seen_count {
				if seen_ids[previous] == card.id {
					return false
				}
			}
			seen_ids[seen_count] = card.id
			seen_count += 1

			switch card.lifetime {
			case .Permanent:
				owned_index, found := owned_card_index_by_id(deck, card.id)
				if !found || seen_owned[owned_index] || card != deck.owned[owned_index] {
					return false
				}
				seen_owned[owned_index] = true
			case .Combat:
				if card.id < deck.combat_card_id_floor {
					return false
				}
				temporary_count += 1
			case .Count:
				return false
			}
		}
	}
	// Gli ID temporanei sono densi: ogni ID coniato dal floor del combat deve
	// esistere ancora in una zona. Un futuro effetto che distrugge carte
	// temporanee dovra sostituire questa uguaglianza con un contatore di
	// creazioni conservato dal deck.
	if seen_count != total_cards || temporary_count > MAX_TEMPORARY_CARDS ||
	   deck.next_card_id-deck.combat_card_id_floor != u32(temporary_count) ||
	   total_cards != deck.owned_count+temporary_count {
		return false
	}
	for index in 0..<deck.owned_count {
		if !seen_owned[index] {
			return false
		}
	}
	return true
}
