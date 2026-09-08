package game

// Fixed run inventory; no combat RNG and no allocation when a relic fires.
Relic_Id :: enum {
	None,
	Iron_Knuckle,
	Ash_Bookmark,
	Swift_Soles,
	Venom_Vial,
	Guard_Sigil,
	Mending_Thread,
	Count,
}

MAX_RUN_RELICS :: int(Relic_Id.Count)-1
RELIC_OFFER_COUNT :: 3

Relic_Definition :: struct {
	id: Relic_Id,
	name: string,
	description: string,
}

RELIC_DEFINITIONS :: [?]Relic_Definition{
	{.Iron_Knuckle, "Iron Knuckle", "First successful push each pulse: gain 1 Shield for 2 pulses."},
	{.Ash_Bookmark, "Ash Bookmark", "First Exhaust each combat: draw 1 extra card."},
	{.Swift_Soles, "Swift Soles", "First movement card each combat: restore 1 energy."},
	{.Venom_Vial, "Venom Vial", "First Poison applied to an enemy each combat: +1 potency."},
	{.Guard_Sigil, "Guard Sigil", "Enter combat with 2 Shield for 3 pulses."},
	{.Mending_Thread, "Mending Thread", "After clearing a combat room: heal 2 HP."},
}

Relic_Combat_State :: struct {
	started: bool,
	entry_used: bool,
	push_used: bool,
	push_pulse: u64,
	exhaust_used: bool,
	movement_used: bool,
	poison_used: bool,
	clear_used: bool,
}

Relic_State :: struct {
	owned: [MAX_RUN_RELICS]Relic_Id,
	count: int,
	combat: Relic_Combat_State,
}

Relic_Offers :: struct {
	choices: [RELIC_OFFER_COUNT]Relic_Id,
	count: int,
}

relic_definition :: proc(id: Relic_Id) -> (Relic_Definition, bool) {
	if id <= .None || id >= .Count {
		return {}, false
	}
	definitions := RELIC_DEFINITIONS
	return definitions[int(id)-1], true
}

validate_relic_state :: proc(state: ^Relic_State) -> bool {
	if state == nil || state.count < 0 || state.count > MAX_RUN_RELICS {
		return false
	}
	for index in 0..<state.count {
		_, valid := relic_definition(state.owned[index])
		if !valid {
			return false
		}
		for previous in 0..<index {
			if state.owned[previous] == state.owned[index] {
				return false
			}
		}
	}
	for index in state.count..<MAX_RUN_RELICS {
		if state.owned[index] != .None {
			return false
		}
	}
	return true
}

player_has_relic :: proc(player: ^Player, id: Relic_Id) -> bool {
	if player == nil || id <= .None || id >= .Count ||
	   player.relics.count < 0 || player.relics.count > MAX_RUN_RELICS {
		return false
	}
	for owned in player.relics.owned[:player.relics.count] {
		if owned == id {
			return true
		}
	}
	return false
}

acquire_relic :: proc(player: ^Player, id: Relic_Id) -> bool {
	_, valid := relic_definition(id)
	if player == nil || !valid || !validate_relic_state(&player.relics) ||
	   player.relics.count >= MAX_RUN_RELICS || player_has_relic(player, id) {
		return false
	}
	player.relics.owned[player.relics.count] = id
	player.relics.count += 1
	return true
}

make_relic_offers :: proc(player: ^Player, seed: u64) -> (offers: Relic_Offers) {
	if player == nil || !validate_relic_state(&player.relics) {
		return
	}
	available: [MAX_RUN_RELICS]Relic_Id
	available_count := 0
	for definition in RELIC_DEFINITIONS {
		if !player_has_relic(player, definition.id) {
			available[available_count] = definition.id
			available_count += 1
		}
	}
	random_state := seed~u64(0xDB4F0B9175AE2165)
	if random_state == 0 {
		random_state = 1
	}
	for available_count > 0 && offers.count < RELIC_OFFER_COUNT {
		index := int(economy_next_random(&random_state)%u64(available_count))
		offers.choices[offers.count] = available[index]
		offers.count += 1
		available_count -= 1
		available[index] = available[available_count]
	}
	return
}

validate_relic_offers :: proc(player: ^Player, offers: ^Relic_Offers) -> bool {
	if player == nil || offers == nil || !validate_relic_state(&player.relics) ||
	   offers.count < 0 || offers.count > RELIC_OFFER_COUNT {
		return false
	}
	for index in 0..<offers.count {
		id := offers.choices[index]
		_, valid := relic_definition(id)
		if !valid || player_has_relic(player, id) {
			return false
		}
		for previous in 0..<index {
			if offers.choices[previous] == id {
				return false
			}
		}
	}
	for index in offers.count..<RELIC_OFFER_COUNT {
		if offers.choices[index] != .None {
			return false
		}
	}
	return true
}
