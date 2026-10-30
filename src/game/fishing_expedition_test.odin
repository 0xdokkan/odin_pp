package game

import "core:testing"
import level "../level"

@(test)
test_expedition_fishing_produces_food_but_legacy_fishing_still_heals :: proc(t: ^testing.T) {
	for physical in ([2]bool{false, true}) {
		data: level.Level; player: Player
		room := fishing_test_room(t, &data, &player)
		defer destroy_room(&room); defer level.destroy(&data)
		player.tactical.config.expedition = physical
		room.fishing.random = fishing_test_stream(false)
		before := player.health
		report := fish_with_rod(&room, {x = 6, y = 5})
		testing.expect_value(t, report.result, Fishing_Result.Fished)
		testing.expect(t, !report.card && report.roll.total >= 1 && report.roll.total <= 4)
		if physical {
			testing.expect_value(t, player.health, before)
			testing.expect_value(t, report.healed, i32(0))
			testing.expect_value(t, len(room.loot), 1)
			testing.expect_value(t, room.loot[0].kind, Loot_Kind.Healing)
			testing.expect_value(t, room.loot[0].healing_amount, report.roll.total)
		} else {
			testing.expect_value(t, player.health, before+report.roll.total)
			testing.expect_value(t, report.healed, report.roll.total)
			testing.expect_value(t, len(room.loot), 0)
		}
	}
}
