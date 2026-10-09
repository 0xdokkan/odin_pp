package game

import grid "../grid"

// One effective catalog for payment, targeting, resolution and presentation.
// Lifetimes, rarity and upgrade eligibility remain shared with classic mode.
rework_tactical_card :: proc(definition: ^Card_Definition) {
	d := definition
	d.tactical = true
	switch d.id {
	case .Arc_Bolt:
		d.cost, d.effects[0].base_amount = 1, 2
	case .Piercing_Ray, .Cross_Slash:
		d.effects[0].base_amount = 3
	case .Guard:
		d.effects[0].base_amount, d.effects[0].duration = 4, 2
	case .Thorn_Coat:
		d.effects[0].base_amount = 2
	case .Counter_Rune:
		d.effects[0].base_amount = 3
	case .Battle_Focus:
		d.effects[1] = {kind = .Apply_Status, target = .Player, status = .Survey, base_amount = 1, duration = 3}
		d.effect_count = 2
	case .Spark_Forge:
		d.effects[0].base_amount = 2
	case .Shove:
		// Relocate explosives before damaging them, so their blast follows the shove.
		d.effects[0], d.effects[1] = d.effects[1], d.effects[0]
	case .Dash:
		d.cost = 1
		d.targeting.cast_range.maximum = 4
		d.effects[1] = d.effects[0]
		d.effects[0] = {kind = .Apply_Status, target = .Player, status = .Shield, base_amount = 2, duration = 2}
		d.effect_count = 2
	case .Grappling_Hook:
		d.cost = 1
	case .Heavy_Blow:
		d.effects[0].base_amount = 4
		d.effects[1] = {kind = .Apply_Status, target = .Chosen_Entity, status = .Stagger, base_amount = 1, duration = 1}
		d.effect_count = 2
	case .Venom_Needle:
		d.effects[1].base_amount, d.effects[1].duration = 2, 2
	case .Purifying_Guard:
		d.effects[0].base_amount, d.effects[0].duration = 3, 2
	case .Volatile_Study:
		d.effects[1].base_amount = 2
	case .Strike, .Toxic_Wave, .Afterimage, .Calculated_Risk, .Spark,
	     .Firebomb, .Caustic_Bloom, .Fate_Strike, .Chain_Lightning,
	     .Sundering_Blow, .Prismatic_Barrage, .Twin_Venom, .Count:
	}
}

tactical_card_enemy_in_area :: proc(room: ^Room, card: Card_Id, position: grid.Position) -> bool {
	if !tactical_enabled(room) { return true }
	if !tactical_cell_visible(room, position) { return false }
	if card == .Toxic_Wave {
		return max(abs(position.x-room.player.position.x), abs(position.y-room.player.position.y)) <= 2
	}
	return true
}

tactical_strike_bonus :: proc(room: ^Room, target: Entity_Ref) -> i32 {
	if !tactical_enabled(room) || target.kind != .Enemy { return 0 }
	index, found := enemy_index_by_id(room, target.id)
	if !found { return 0 }
	_, staggered := status_for_entity(room, target, .Stagger)
	if room.enemies[index].recovery_pulses > 0 || staggered { return 2 }
	return 0
}

// Survey reveals the current surroundings only, never an exploration memory.
tactical_vision_size :: proc(config: Tactical_Config, statuses: ^Status_Set) -> int {
	if config.vision_size == 0 { return 0 }
	if _, surveying := status_index(statuses, .Survey); surveying { return min(MAX_TACTICAL_VISION, max(3, config.vision_size)+2) }
	return config.vision_size
}

enemy_is_staggered :: proc(room: ^Room, enemy: ^Enemy) -> bool {
	if !tactical_enabled(room) { return false }
	_, found := status_index(&enemy.statuses, .Stagger)
	return found
}

interrupt_staggered_enemy :: proc(room: ^Room, enemy: ^Enemy, pulse: ^Pulse_Report) -> bool {
	if !enemy_is_staggered(room, enemy) { return false }
	enemy.bomb_ready, enemy.aim_ready = false, false
	enemy.intent = {}
	enemy.recovery_pulses = max(i32(1), enemy.recovery_pulses)
	record_enemy_attack_miss(pulse, enemy_entity(enemy.id), enemy.position, enemy.position)
	return true
}
