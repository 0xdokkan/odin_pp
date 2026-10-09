package game

Weapon_Id :: enum { None, Iron_Cleaver, Storm_Pike }
Weapon_Definition :: struct {
	name: string,
	bonus_damage, max_uses: i32,
}
Weapon_Slot :: struct { id: Weapon_Id, uses_remaining: i32 }
Equipment_State :: struct { weapon, reserve: Weapon_Slot }

weapon_definition :: proc(id: Weapon_Id) -> (Weapon_Definition, bool) {
	switch id {
	case .None: return {}, false
	case .Iron_Cleaver: return {"Mannaia di ferro", 2, 4}, true
	case .Storm_Pike: return {"Picca della tempesta", 3, 3}, true
	}
	return {}, false
}

weapon_slot_valid :: proc(slot: Weapon_Slot) -> bool {
	if slot.id == .None { return slot.uses_remaining == 0 }
	definition, found := weapon_definition(slot.id)
	return found && slot.uses_remaining > 0 && slot.uses_remaining <= definition.max_uses
}

collect_weapon :: proc(player: ^Player, id: Weapon_Id, uses: i32) -> bool {
	if player == nil || player.equipment.reserve.id != .None { return false }
	slot := Weapon_Slot{id, uses}
	if id == .None || !weapon_slot_valid(slot) { return false }
	player.equipment.reserve = slot
	return true
}

// Equipping is deliberate: a magnet pickup never replaces a weapon in use.
// The displaced weapon stays in reserve, retaining its remaining charges.
equip_reserved_weapon :: proc(room: ^Room) -> bool {
	if room == nil || room.player == nil || (room.phase != .Combat && room.phase != .Loot) ||
	   !tactical_allows_action(room) || room.player.equipment.reserve.id == .None { return false }
	equipment := &room.player.equipment
	if !weapon_slot_valid(equipment.reserve) || !weapon_slot_valid(equipment.weapon) { return false }
	equipment.weapon, equipment.reserve = equipment.reserve, equipment.weapon
	return true
}

player_basic_attack_damage :: proc(player: ^Player) -> i32 {
	if player == nil { return 0 }
	damage := player.stats.attack
	if definition, found := weapon_definition(player.equipment.weapon.id); found &&
	   weapon_slot_valid(player.equipment.weapon) { damage = i32(min(i64(max(i32)), i64(damage)+i64(definition.bonus_damage))) }
	return damage
}

consume_equipped_weapon_use :: proc(player: ^Player) {
	if player == nil || player.equipment.weapon.id == .None { return }
	assert(weapon_slot_valid(player.equipment.weapon))
	player.equipment.weapon.uses_remaining -= 1
	if player.equipment.weapon.uses_remaining == 0 { player.equipment.weapon = {} }
}
