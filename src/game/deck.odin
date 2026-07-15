package game

MAX_OWNED_CARDS :: 32
MAX_HAND_CARDS  :: 8

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

Deck_State :: struct {
	owned:             [MAX_OWNED_CARDS]Card_Instance,
	owned_count:       int,
	draw_pile:         [MAX_OWNED_CARDS]Card_Instance,
	draw_count:        int,
	hand:              [MAX_HAND_CARDS]Card_Instance,
	hand_count:        int,
	discard_pile:      [MAX_OWNED_CARDS]Card_Instance,
	discard_count:     int,
	energy:            i32,
	rules:             Deck_Rules,
	next_card_id:      u32,
	random_state:      u64,
	combat_active:     bool,
}

deck_rules_are_valid :: proc(rules: Deck_Rules) -> bool {
	return rules.hand_size > 0 && rules.hand_size <= MAX_HAND_CARDS &&
	       rules.max_energy > 0 && rules.energy_regen_per_pulse >= 0
}

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
	if deck == nil || id == 0 || deck.hand_count < 0 || deck.hand_count > MAX_HAND_CARDS {
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
	instance := Card_Instance{
		id = deck.next_card_id,
		definition_id = definition_id,
		upgrade_level = upgrade_level,
	}
	if !validate_card_instance(instance) {
		return {}, false
	}
	deck.owned[deck.owned_count] = instance
	deck.owned_count += 1
	deck.next_card_id += 1
	return instance, true
}

initialize_starter_deck :: proc(deck: ^Deck_State, seed: u64 = DEFAULT_DECK_SEED) -> bool {
	if !initialize_empty_deck(deck, DEFAULT_DECK_RULES, seed) {
		return false
	}
	starter_cards := [?]Card_Id{
		.Strike,
		.Arc_Bolt,
		.Piercing_Ray,
		.Cross_Slash,
		.Firebomb,
		.Guard,
		.Toxic_Wave,
		.Thorn_Coat,
		.Afterimage,
		.Counter_Rune,
	}
	for definition_id in starter_cards {
		_, added := add_owned_card(deck, definition_id)
		assert(added)
	}
	return validate_deck_state(deck)
}

reseed_deck :: proc(deck: ^Deck_State, seed: u64) -> bool {
	if deck == nil || deck.combat_active {
		return false
	}
	deck.random_state = normalized_deck_seed(seed)
	return true
}

deck_next_random :: proc(deck: ^Deck_State) -> u64 {
	assert(deck != nil && deck.random_state != 0)
	x := deck.random_state
	x ~= x >> 12
	x ~= x << 25
	x ~= x >> 27
	deck.random_state = x
	return x*0x2545F4914F6CDD1D
}

shuffle_draw_pile :: proc(deck: ^Deck_State) {
	assert(deck != nil && deck.draw_count >= 0 && deck.draw_count <= MAX_OWNED_CARDS)
	for index := deck.draw_count-1; index > 0; index -= 1 {
		swap_index := int(deck_next_random(deck)%u64(index+1))
		deck.draw_pile[index], deck.draw_pile[swap_index] =
			deck.draw_pile[swap_index], deck.draw_pile[index]
	}
}

draw_card :: proc(deck: ^Deck_State) -> (card: Card_Instance, ok: bool) {
	if deck == nil || !deck.combat_active || deck.hand_count < 0 ||
	   deck.hand_count >= deck.rules.hand_size || deck.hand_count >= MAX_HAND_CARDS ||
	   deck.draw_count < 0 || deck.draw_count > MAX_OWNED_CARDS ||
	   deck.discard_count < 0 || deck.discard_count > MAX_OWNED_CARDS {
		return {}, false
	}
	if deck.draw_count == 0 {
		if deck.discard_count <= 0 || deck.discard_count > MAX_OWNED_CARDS {
			return {}, false
		}
		for index in 0..<deck.discard_count {
			deck.draw_pile[index] = deck.discard_pile[index]
			deck.discard_pile[index] = {}
		}
		deck.draw_count = deck.discard_count
		deck.discard_count = 0
		shuffle_draw_pile(deck)
	}

	deck.draw_count -= 1
	card = deck.draw_pile[deck.draw_count]
	deck.draw_pile[deck.draw_count] = {}
	deck.hand[deck.hand_count] = card
	deck.hand_count += 1
	return card, true
}

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
	if deck == nil || !validate_deck_state(deck) || deck.owned_count <= 0 {
		return false
	}
	deck.draw_pile = {}
	deck.hand = {}
	deck.discard_pile = {}
	deck.draw_count = deck.owned_count
	deck.hand_count = 0
	deck.discard_count = 0
	deck.energy = deck.rules.max_energy
	deck.combat_active = true
	for index in 0..<deck.owned_count {
		deck.draw_pile[index] = deck.owned[index]
	}
	shuffle_draw_pile(deck)
	draw_to_hand_size(deck)
	return validate_deck_state(deck)
}

finish_deck_combat :: proc(deck: ^Deck_State) {
	if deck == nil {
		return
	}
	deck.draw_pile = {}
	deck.hand = {}
	deck.discard_pile = {}
	deck.draw_count = 0
	deck.hand_count = 0
	deck.discard_count = 0
	deck.energy = 0
	deck.combat_active = false
}

sync_deck_with_room_phase :: proc(room: ^Room) {
	if room != nil && room.player != nil && room.phase != .Combat {
		finish_deck_combat(&room.player.deck)
	}
}

discard_hand_card :: proc(deck: ^Deck_State, hand_index: int) -> (Card_Instance, bool) {
	if deck == nil || !deck.combat_active || hand_index < 0 || hand_index >= deck.hand_count ||
	   deck.discard_count < 0 || deck.discard_count >= MAX_OWNED_CARDS {
		return {}, false
	}
	card := deck.hand[hand_index]
	for index in hand_index..<deck.hand_count-1 {
		deck.hand[index] = deck.hand[index+1]
	}
	deck.hand_count -= 1
	deck.hand[deck.hand_count] = {}
	deck.discard_pile[deck.discard_count] = card
	deck.discard_count += 1
	return card, true
}

restore_deck_energy_after_pulse :: proc(deck: ^Deck_State) -> i32 {
	if deck == nil || !deck.combat_active || deck.energy >= deck.rules.max_energy {
		return 0
	}
	before := deck.energy
	deck.energy = min(deck.rules.max_energy, deck.energy+deck.rules.energy_regen_per_pulse)
	return deck.energy-before
}

validate_deck_state :: proc(deck: ^Deck_State) -> bool {
	if deck == nil || !deck_rules_are_valid(deck.rules) || deck.random_state == 0 ||
	   deck.next_card_id == 0 || deck.owned_count < 0 || deck.owned_count > MAX_OWNED_CARDS ||
	   deck.draw_count < 0 || deck.draw_count > MAX_OWNED_CARDS ||
	   deck.hand_count < 0 || deck.hand_count > MAX_HAND_CARDS ||
	   deck.discard_count < 0 || deck.discard_count > MAX_OWNED_CARDS {
		return false
	}

	for index in 0..<deck.owned_count {
		card := deck.owned[index]
		if !validate_card_instance(card) || card.id >= deck.next_card_id {
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
		       deck.discard_count == 0 && deck.energy == 0
	}
	if deck.hand_count > deck.rules.hand_size || deck.energy < 0 || deck.energy > deck.rules.max_energy ||
	   deck.draw_count+deck.hand_count+deck.discard_count != deck.owned_count {
		return false
	}

	seen: [MAX_OWNED_CARDS]bool
	for index in 0..<deck.draw_count {
		owned_index, found := owned_card_index_by_id(deck, deck.draw_pile[index].id)
		if !found || seen[owned_index] || deck.draw_pile[index] != deck.owned[owned_index] {
			return false
		}
		seen[owned_index] = true
	}
	for index in 0..<deck.hand_count {
		owned_index, found := owned_card_index_by_id(deck, deck.hand[index].id)
		if !found || seen[owned_index] || deck.hand[index] != deck.owned[owned_index] {
			return false
		}
		seen[owned_index] = true
	}
	for index in 0..<deck.discard_count {
		owned_index, found := owned_card_index_by_id(deck, deck.discard_pile[index].id)
		if !found || seen[owned_index] || deck.discard_pile[index] != deck.owned[owned_index] {
			return false
		}
		seen[owned_index] = true
	}
	return true
}
