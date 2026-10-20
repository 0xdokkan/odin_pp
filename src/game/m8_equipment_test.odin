package game

import "core:testing"
import level "../level"

@(test)
test_m8_weapon_pickup_requires_equip_and_spends_only_accepted_melee :: proc(t: ^testing.T) {
	data := create_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	spawns := [?]Enemy_Spawn{{position = {2, 1}, health = 30, attack = 1}}
	room, ok := create_room(&data, &player, {enemies = spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	configure_tactical_room(&room, DEFAULT_TACTICAL_CONFIG)
	testing.expect(t, collect_weapon(&player, .Iron_Cleaver, 2))
	testing.expect_value(t, player_basic_attack_damage(&player), player.stats.attack)
	testing.expect(t, equip_reserved_weapon(&room))
	testing.expect_value(t, player_basic_attack_damage(&player), player.stats.attack+2)
	testing.expect_value(t, try_move_player(&room, .West), Action_Result.Blocked)
	testing.expect_value(t, player.equipment.weapon.uses_remaining, i32(2))
	testing.expect_value(t, try_move_player(&room, .East), Action_Result.Attacked)
	testing.expect_value(t, room.enemies[0].health, i32(26))
	testing.expect_value(t, player.equipment.weapon.uses_remaining, i32(1))
	// Clear the legitimately queued response before accepting another command.
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, try_move_player(&room, .East), Action_Result.Attacked)
	testing.expect_value(t, room.enemies[0].health, i32(22))
	testing.expect_value(t, player.equipment.weapon, Weapon_Slot{})
	testing.expect_value(t, player_basic_attack_damage(&player), player.stats.attack)
}

@(test)
test_m8_weapon_reserve_is_transactional_and_swaps_remaining_uses :: proc(t: ^testing.T) {
	data := create_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	room, ok := create_room(&data, &player, {})
	testing.expect(t, ok)
	defer destroy_room(&room)
	testing.expect(t, !collect_weapon(&player, .None, 2))
	testing.expect(t, !collect_weapon(&player, .Iron_Cleaver, 5))
	testing.expect(t, collect_weapon(&player, .Iron_Cleaver, 2))
	testing.expect(t, !collect_weapon(&player, .Storm_Pike, 3))
	testing.expect(t, equip_reserved_weapon(&room))
	testing.expect(t, collect_weapon(&player, .Storm_Pike, 3))
	testing.expect(t, equip_reserved_weapon(&room))
	testing.expect_value(t, player.equipment.weapon, Weapon_Slot{.Storm_Pike, 3})
	testing.expect_value(t, player.equipment.reserve, Weapon_Slot{.Iron_Cleaver, 2})
	append(&room.loot, Loot{position = player.position, kind = .Weapon, amount = 4, weapon_id = .Iron_Cleaver})
	testing.expect_value(t, collect_loot_in_magnet_range(&room), 0)
	testing.expect_value(t, len(room.loot), 1)
}

@(test)
test_m8_brute_drops_weapon_and_pickup_stays_unequipped :: proc(t: ^testing.T) {
	data := create_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	spawns := [?]Enemy_Spawn{{position = {2, 1}, health = 1, attack = 1, archetype = .Brute, drops_healing = true}}
	room, ok := create_room(&data, &player, {enemies = spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	drops, count := kill_enemy(&room, 0)
	testing.expect_value(t, count, 3)
	testing.expect_value(t, drops[2].kind, Loot_Kind.Weapon)
	testing.expect_value(t, drops[2].weapon_id, Weapon_Id.Iron_Cleaver)
	collect_loot_in_magnet_range(&room)
	testing.expect_value(t, player.equipment.weapon, Weapon_Slot{})
	testing.expect_value(t, player.equipment.reserve.id, Weapon_Id.Iron_Cleaver)
}
