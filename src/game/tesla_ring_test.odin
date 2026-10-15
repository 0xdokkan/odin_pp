package game

import "core:testing"
import grid "../grid"
import level "../level"

tesla_ring_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player) -> Room {
	// Two enemies stand inside the square (2,2)-(6,6); a third waits outside.
	spawns := [?]Enemy_Spawn{
		{position = {3, 3}, health = 100, attack = 1},
		{position = {5, 5}, health = 100, attack = 1},
		{position = {7, 1}, health = 100, attack = 1},
	}
	return create_enemy_rework_room(t, data, player, spawns[:])
}

deploy_tesla_test_coils :: proc(t: ^testing.T, room: ^Room, cells: [4]grid.Position) {
	clear(&room.objects)
	log: Event_Log
	for cell in cells { testing.expect(t, deploy_board_device(room, .Tesla_Coil, cell, 8, 0, &log)) }
}

tesla_ring_holds :: proc(room: ^Room, id: u32) -> bool {
	for slot in 0..<room.tesla_ring.count { if room.tesla_ring.enemy_ids[slot] == id { return true } }
	return false
}

@(test)
test_tesla_square_opens_the_ring_once_per_floor_around_enemies :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tesla_ring_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	// A rectangle is a field, not a ring; neither is a square with a 1x1 inside.
	deploy_tesla_test_coils(t, &room, {{2, 2}, {7, 2}, {7, 6}, {2, 6}})
	_, found := query_tesla_ring(&room)
	testing.expect(t, !found)
	deploy_tesla_test_coils(t, &room, {{1, 5}, {3, 5}, {3, 7}, {1, 7}})
	_, found = query_tesla_ring(&room)
	testing.expect(t, !found)
	// The square with a 3x3 inside pulls in exactly the enemies within it.
	deploy_tesla_test_coils(t, &room, {{2, 2}, {6, 2}, {6, 6}, {2, 6}})
	ring, ok := query_tesla_ring(&room)
	testing.expect(t, ok)
	testing.expect_value(t, ring.count, 2)
	preview := query_tesla_controls(&room)
	testing.expect(t, preview.can_activate && preview.network.ready)
	testing.expect_value(t, preview.ring, ring)
	// A previously drawn button cannot authorize a later, unavailable command.
	room.objects[0].device_cooldown = 2
	blocked := query_tesla_controls(&room)
	testing.expect(t, !blocked.can_activate && blocked.ring.count == 0)
	testing.expect_value(t, blocked.network.cooldown, i32(2))
	before_events := room.recent_events
	committed, opened := activate_tesla(&room)
	testing.expect(t, !committed && !opened)
	testing.expect_value(t, room.recent_events, before_events)
	testing.expect_value(t, board_tesla_count(&room), 4)
	room.objects[0].device_cooldown = 0
	committed, opened = activate_tesla(&room)
	testing.expect(t, committed && opened)
	testing.expect(t, room.tesla_ring.pending && .Tesla_Ring in player.floor_secrets)
	testing.expect(t, tesla_ring_holds(&room, room.enemies[0].id) && tesla_ring_holds(&room, room.enemies[1].id))
	testing.expect(t, !tesla_ring_holds(&room, room.enemies[2].id))
	// The coils are spent without a discharge.
	testing.expect_value(t, board_tesla_count(&room), 0)
	for enemy in room.enemies { testing.expect_value(t, enemy.health, i32(100)) }
	testing.expect_value(t, player.health, i32(100))
	testing.expect(t, !begin_tesla_ring(&room))
	// Once settled, the floor's ring is gone: a new square only discharges.
	_ = settle_tesla_ring(&room, {won = false, remaining = {1000, 1000, 0, 0}})
	deploy_tesla_test_coils(t, &room, {{2, 2}, {6, 2}, {6, 6}, {2, 6}})
	_, found = query_tesla_ring(&room)
	testing.expect(t, !found)
	testing.expect(t, !begin_tesla_ring(&room))
	// The next floor opens it again.
	begin_floor(&player)
	_, found = query_tesla_ring(&room)
	testing.expect(t, found)
}

@(test)
test_tesla_ring_win_defeats_its_roster_with_loot :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tesla_ring_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	deploy_tesla_test_coils(t, &room, {{2, 2}, {6, 2}, {6, 6}, {2, 6}})
	testing.expect(t, begin_tesla_ring(&room))
	outside := room.enemies[2].id
	report := settle_tesla_ring(&room, {won = true})
	testing.expect(t, report.settled && report.won)
	testing.expect_value(t, report.defeated, 2)
	testing.expect_value(t, len(room.enemies), 1)
	testing.expect_value(t, room.enemies[0].id, outside)
	// Each knockout drops its loot (the magnet may already have collected it).
	drops := 0
	for event in room.recent_events.events[:room.recent_events.count] { if event.kind == .Loot_Dropped { drops += 1 } }
	testing.expect(t, drops >= 2)
	testing.expect_value(t, room.phase, Room_Phase.Combat)
	testing.expect_value(t, player.health, i32(100))
	// A ring win still counts toward the durable unlocks.
	testing.expect(t, report.reward.won && report.reward.has_unlock)
	testing.expect_value(t, player.m8_profile.ring_wins, u32(1))
	testing.expect(t, !room.tesla_ring.pending)
	testing.expect(t, !settle_tesla_ring(&room, {won = true}).settled)
}

@(test)
test_tesla_ring_loss_costs_a_quarter_and_keeps_wounds :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tesla_ring_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	deploy_tesla_test_coils(t, &room, {{2, 2}, {6, 2}, {6, 6}, {2, 6}})
	testing.expect(t, begin_tesla_ring(&room))
	first, second := room.tesla_ring.enemy_ids[0], room.tesla_ring.enemy_ids[1]
	// The first opponent leaves with half its health; the second was knocked out.
	report := settle_tesla_ring(&room, {won = false, remaining = {500, 0, 0, 0}})
	testing.expect(t, report.settled && !report.won)
	testing.expect_value(t, report.defeated, 1)
	testing.expect_value(t, report.player_damage, i32(25))
	testing.expect_value(t, player.health, i32(75))
	index, found := enemy_index_by_id(&room, first)
	testing.expect(t, found)
	testing.expect_value(t, room.enemies[index].health, i32(50))
	_, found = enemy_index_by_id(&room, second)
	testing.expect(t, !found)
	testing.expect_value(t, player.m8_profile.ring_wins, u32(0))
	// A loss never takes the last point of health.
	begin_floor(&player)
	player.health = 10
	deploy_tesla_test_coils(t, &room, {{2, 2}, {6, 2}, {6, 6}, {2, 6}})
	testing.expect(t, begin_tesla_ring(&room))
	report = settle_tesla_ring(&room, {won = false, remaining = {1000, 1000, 1000, 1000}})
	testing.expect_value(t, player.health, i32(1))
	testing.expect_value(t, room.phase, Room_Phase.Combat)
}
