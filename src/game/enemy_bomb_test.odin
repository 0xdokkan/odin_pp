package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

// The board of the bombs' tests: the player at (4,4) in a walled 9×9 room, a
// bomber at (7,4) ready to throw at (5,4).
@(private = "file")
bomb_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player) -> Room {
	spawns := [?]Enemy_Spawn{{position = {x = 7, y = 4}, health = 20, attack = 2, archetype = .Bomber}}
	room := create_enemy_rework_room(t, data, player, spawns[:])
	bomber := &room.enemies[0]
	bomber.intent = make_wait_intent(&room, bomber.position)
	bomber.intent.kind, bomber.intent.destination, bomber.intent.damage = .Bombard, {x = 5, y = 4}, TACTICAL_BOMB_DAMAGE
	for y in 3..=5 { for x in 4..=6 {
		bomber.intent.threatened_cells[bomber.intent.threatened_cell_count] = {x = x, y = y}
		bomber.intent.threatened_cell_count += 1
	} }
	return room
}

// The bomber's throw on its beat: in the air, not on its cell.
@(private = "file")
bomb_test_throw :: proc(t: ^testing.T, room: ^Room) -> Pulse_Report {
	pulse: Pulse_Report
	resolve_enemy_intents(room, &pulse, room.enemies[0].id)
	testing.expect_value(t, room.bombs.count, i32(1))
	testing.expect_value(t, len(room.objects), 0)
	return pulse
}

// It flies ENEMY_BOMB_FLIGHT world seconds, then lands with its fuse lit: the
// blast on the same beat as a bomb set down at once.
@(test)
test_a_bombers_bomb_flies_then_lands_with_its_fuse_lit :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := bomb_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	thrown_on := room.pulse_count
	pulse := bomb_test_throw(t, &room)
	testing.expect_value(t, spatial_card_event_count(&pulse.events, .Bomb_Thrown), 1)
	testing.expect_value(t, spatial_card_event_count(&pulse.events, .Object_Spawned), 0)
	thrown := pulse.events.events[0]
	testing.expect_value(t, thrown.from_position, grid.Position{x = 7, y = 4})
	testing.expect_value(t, thrown.to_position, grid.Position{x = 5, y = 4})
	// The beat's count moves on as it ends.
	room.pulse_count += 1
	room.bombs.pending = ENEMY_BOMB_FLIGHT*0.5
	testing.expect(t, resolve_enemy_flights(&room))
	testing.expect_value(t, room.bombs.count, i32(1))
	testing.expect_value(t, len(room.objects), 0)
	testing.expect(t, abs(enemy_bomb_progress(&room, room.bombs.items[0])-0.5) < 1e-5)
	room.bombs.pending = ENEMY_BOMB_FLIGHT*0.5
	testing.expect(t, resolve_enemy_flights(&room))
	testing.expect_value(t, room.bombs.count, i32(0))
	testing.expect_value(t, len(room.objects), 1)
	bomb := room.objects[0]
	testing.expect_value(t, bomb.kind, Grid_Object_Kind.Bomb)
	testing.expect_value(t, bomb.position, grid.Position{x = 5, y = 4})
	testing.expect_value(t, bomb.detonation_pulse, thrown_on+u64(TACTICAL_BOMB_FUSE)+1)
	testing.expect_value(t, spatial_card_event_count(room.recent_events, .Explosive_Armed), 1)
}

// A cell taken while it flew: it rolls off and goes out, a miss.
@(test)
test_a_bomb_landing_on_a_taken_cell_misses :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := bomb_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	_ = bomb_test_throw(t, &room)
	append(&room.objects, Grid_Object{id = room.next_object_id, kind = .Ice_Block, position = {x = 5, y = 4}, health = 4, max_health = 4})
	room.next_object_id += 1
	room.bombs.pending = ENEMY_BOMB_FLIGHT
	testing.expect(t, resolve_enemy_flights(&room))
	testing.expect_value(t, room.bombs.count, i32(0))
	testing.expect_value(t, len(room.objects), 1)
	testing.expect_value(t, spatial_card_event_count(room.recent_events, .Attack_Missed), 1)
}

// The world holds it as it holds the world (a cast); a beat lands it first,
// before its own work, however little time it was given.
@(test)
test_a_bomb_holds_with_the_world_and_lands_before_a_beat :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := bomb_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	_ = bomb_test_throw(t, &room)
	tactical_begin_card_cast(&room, 1)
	testing.expect(t, !tactical_tick(&room, 0.5, true, false))
	testing.expect_value(t, room.bombs.pending, f32(0))
	testing.expect(t, !tactical_flights_due(&room))
	player.tactical.cast_remaining = 0
	testing.expect(t, !tactical_tick(&room, 1, true, false))
	testing.expect(t, room.tactical_pulse.pending)
	testing.expect(t, continue_tactical_pulse(&room))
	testing.expect_value(t, room.bombs.count, i32(0))
	testing.expect_value(t, len(room.objects), 1)
}

// The bombs in the air count with those on the board: no second throw.
@(test)
test_a_bomb_in_the_air_counts_against_the_bomb_limit :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := bomb_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	_ = bomb_test_throw(t, &room)
	testing.expect_value(t, active_bomb_count(&room), 1)
	testing.expect(t, active_bomb_count(&room) >= TACTICAL_BOMB_LIMIT)
}
