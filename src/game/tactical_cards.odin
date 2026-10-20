package game

import grid "../engine/grid"

tactical_card_enemy_in_area :: proc(room: ^Room, card: Card_Id, position: grid.Position) -> bool {
	if !tactical_cell_visible(room, position) { return false }
	if card == .Toxic_Wave {
		return max(abs(position.x-room.player.position.x), abs(position.y-room.player.position.y)) <= 2
	}
	return true
}

@(private)
tactical_strike_bonus :: proc(room: ^Room, target: Entity_Ref) -> i32 {
	if room == nil || room.player == nil || target.kind != .Enemy { return 0 }
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
	if room == nil || room.player == nil { return false }
	_, found := status_index(&enemy.statuses, .Stagger)
	return found
}

@(private)
interrupt_staggered_enemy :: proc(room: ^Room, enemy: ^Enemy, pulse: ^Pulse_Report) -> bool {
	if !enemy_is_staggered(room, enemy) { return false }
	enemy.bomb_ready, enemy.aim_ready = false, false
	enemy.intent = {}
	enemy.recovery_pulses = max(i32(1), enemy.recovery_pulses)
	record_enemy_attack_miss(pulse, enemy_entity(enemy.id), enemy.position, enemy.position)
	return true
}
