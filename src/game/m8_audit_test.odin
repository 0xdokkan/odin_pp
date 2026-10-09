package game

import "core:testing"
import level "../level"

@(test)
test_m8_dense_weapon_magnet_preserves_full_reserve_without_skipping_other_loot :: proc(t: ^testing.T) {
	data := create_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	room, ok := create_room(&data, &player, {})
	testing.expect(t, ok)
	defer destroy_room(&room)
	player.health = 1
	for _ in 0..<MAX_ENEMIES_PER_ROOM {
		append(&room.loot, Loot{position = player.position, kind = .Weapon, amount = 4, weapon_id = .Iron_Cleaver})
		append(&room.loot, Loot{position = player.position, kind = .Gold, amount = 1})
		append(&room.loot, Loot{position = player.position, kind = .Healing, amount = 2})
	}
	before_gold := player.gold
	collected := collect_loot_in_magnet_range(&room)
	testing.expect_value(t, collected, MAX_ENEMIES_PER_ROOM*2+1)
	testing.expect_value(t, player.equipment.weapon, Weapon_Slot{})
	testing.expect_value(t, player.equipment.reserve, Weapon_Slot{.Iron_Cleaver, 4})
	testing.expect_value(t, player.gold, before_gold+i32(MAX_ENEMIES_PER_ROOM))
	testing.expect_value(t, player.health, player.stats.max_health)
	testing.expect_value(t, len(room.loot), MAX_ENEMIES_PER_ROOM-1)
	for item in room.loot { testing.expect_value(t, item.kind, Loot_Kind.Weapon) }
	testing.expect_value(t, room.recent_events.dropped_count, 0)
	before_events := room.recent_events.count
	testing.expect_value(t, collect_loot_in_magnet_range(&room), 0)
	testing.expect_value(t, room.recent_events.count, before_events)
	testing.expect(t, equip_reserved_weapon(&room))
	testing.expect_value(t, collect_loot_in_magnet_range(&room), 1)
	testing.expect_value(t, len(room.loot), MAX_ENEMIES_PER_ROOM-2)
	testing.expect_value(t, room.recent_events.dropped_count, 0)
}
