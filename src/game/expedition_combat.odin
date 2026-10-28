package game

EXPEDITION_MAX_ENERGY :: i32(100)
EXPEDITION_ENERGY_PER_SECOND :: f32(8)
EXPEDITION_DRAW_BEATS :: u64(4)

// Prices are independent of upgrade level. Explicit values make balance
// changes reviewable and ensure every catalogue entry has a deliberate price.
@(private, rodata)
EXPEDITION_CARD_COSTS := [Card_Id]i32{
	.Strike = 15, .Arc_Bolt = 15, .Piercing_Ray = 25, .Cross_Slash = 25,
	.Firebomb = 40, .Guard = 15, .Toxic_Wave = 35, .Thorn_Coat = 25,
	.Afterimage = 25, .Counter_Rune = 25, .Battle_Focus = 15,
	.Calculated_Risk = 10, .Spark_Forge = 15, .Spark = 10, .Shove = 15,
	.Dash = 15, .Grappling_Hook = 20, .Heavy_Blow = 25, .Venom_Needle = 20,
	.Caustic_Bloom = 35, .Purifying_Guard = 25, .Volatile_Study = 20,
	.Fate_Strike = 25, .Chain_Lightning = 40, .Sundering_Blow = 35,
	.Prismatic_Barrage = 50, .Twin_Venom = 30, .Shock_Floor = 30,
	.Tesla_Coil = 35, .Titan_Grip = 45, .Storm_Crown = 55,
	.Sei_Denari = 10, .Sette_Denari = 10, .Shadow_Step = 35,
	.Poison_Pool = 30, .Wildfire = 45, .Deflect = 25, .Coffin = 35,
	.Fate_Dice = 30, .Venom_Blade = 25, .Lasso = 40,
	.Fishing_Rod = 10, .Pinball = 50, .First_Person = 60,
	.Cannon = 40, .Flood = 35, .Black_Hole = 60, .Bomb_Marley = 70, .Dinosaur = 45,
	// The Prova meccaniche's own versions (never offered yet): priced like the ones above.
	.Marley_Party = 70, .Flood_Wave = 35, .Field_Cannon = 40, .Laser_Cannon = 50, .Devouring_Hole = 60, .Dino_Ride = 45, .First_Person_Brawler = 60, .Count = 0,
}

expedition_card_energy_cost :: proc(id: Card_Id) -> i32 {
	return EXPEDITION_CARD_COSTS[id] if id >= .Strike && id < .Count else 0
}

card_energy_cost :: proc(room: ^Room, id: Card_Id) -> i32 {
	if id < .Strike || id >= .Count { return 0 }
	if room != nil && room.player != nil && room.player.tactical.config.expedition {
		return expedition_card_energy_cost(id)
	}
	definition, _ := card_definition_by_id(id)
	return definition.cost
}

// Call when entering the biome, before its first encounter is dealt.
configure_expedition_combat :: proc(room: ^Room) -> bool {
	return configure_tactical_room(room, EXPEDITION_TACTICAL_CONFIG)
}

begin_expedition_encounter :: proc(room: ^Room) -> bool {
	if room == nil || room.player == nil || room.player.health <= 0 { return false }
	if !room.player.tactical.config.expedition && !configure_expedition_combat(room) { return false }
	if room.player.deck.combat_active { finish_deck_combat(&room.player.deck) }
	if !begin_deck_combat(&room.player.deck) { return false }
	room.phase = .Combat
	room.tactical_pulse, room.qte = {}, {}
	begin_tactical_room(room)
	plan_enemy_intents(room)
	return true
}

end_expedition_encounter :: proc(room: ^Room) {
	if room == nil || room.player == nil { return }
	room.phase = .Defeat if room.player.health <= 0 else .Loot
	finish_deck_combat(&room.player.deck)
	disarm_board_devices_after_combat(room, room.recent_events)
	clear_enemy_intents(room)
	tactical_end_combat(room)
}

@(private)
expedition_regenerate_energy :: proc(room: ^Room, elapsed: f32) {
	s := &room.player.tactical
	deck := &room.player.deck
	if !s.config.expedition || !deck.combat_active || elapsed <= 0 { return }
	if deck.energy >= deck.rules.max_energy { s.energy_fraction = 0; return }
	s.energy_fraction += elapsed*EXPEDITION_ENERGY_PER_SECOND
	whole := i32(s.energy_fraction+0.00001)
	s.energy_fraction = max(f32(0), s.energy_fraction-f32(whole))
	deck.energy = min(deck.rules.max_energy, deck.energy+whole)
	if deck.energy == deck.rules.max_energy { s.energy_fraction = 0 }
}

@(private)
expedition_finish_beat :: proc(room: ^Room, pulse: ^Pulse_Report) {
	s := &room.player.tactical
	if !s.config.expedition { return }
	s.encounter_beats += 1
	expedition_terrain_beat(room, pulse)
	if s.encounter_beats%EXPEDITION_DRAW_BEATS != 0 { return }
	// The old window also paced fire. The four-beat hand cadence replaces it,
	// so fire still grows and burning still bites without a hidden deadline.
	s.cycle += 1
	tick_combatants(room, pulse, burn_status)
	if room.phase == .Combat { grow_ground_fires(room, pulse) }
	if room.phase == .Combat && room.player.deck.hand_count < deck_hand_limit(&room.player.deck) {
		room.tactical_pulse.deferred_draws += 1
	}
}

// The workshop removes cards outside combat and obeys the shared minimum size.
expedition_remove_card :: proc(deck: ^Deck_State, id: u32) -> Deck_Mutation_Result {
	return remove_owned_card(deck, id)
}

// Save validation shares the same invariants used when a room is constructed.
expedition_player_valid :: proc(player: ^Player) -> bool {
	return player != nil && valid_tactical_config(player.tactical.config) &&
		validate_relic_state(&player.relics) && validate_dice_state(&player.dice) &&
		weapon_slot_valid(player.equipment.weapon) && weapon_slot_valid(player.equipment.reserve) &&
		m8_profile_valid(player.m8_profile) && validate_deck_state(&player.deck)
}
