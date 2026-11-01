package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

// The board of the archers' tests: the player at (4,4) in a walled 9×9 room,
// an archer at (7,4) aiming its shot at him (enemy_arrow.odin).
@(private = "file")
arrow_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, others: []Enemy_Spawn = nil) -> Room {
	spawns: [4]Enemy_Spawn
	spawns[0] = {position = {x = 7, y = 4}, health = 100, attack = 3, archetype = .Archer}
	for other, index in others { spawns[index+1] = other }
	room := create_enemy_rework_room(t, data, player, spawns[:1+len(others)])
	archer := &room.enemies[0]
	archer.intent = make_attack_intent(&room, archer.position, room.player.position, 3)
	return room
}

// The archer's shot on its beat: the arrow it looses.
@(private = "file")
arrow_test_loose :: proc(t: ^testing.T, room: ^Room) -> Pulse_Report {
	pulse: Pulse_Report
	resolve_enemy_intents(room, &pulse, room.enemies[0].id)
	testing.expect_value(t, room.arrows.count, 1)
	return pulse
}

// No defence of the keys answers it; it lands as it enters his cell, 2.5
// cells on at ENEMY_ARROW_SPEED, not before.
@(test)
test_an_archers_arrow_flies_and_lands_on_the_player :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := arrow_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	_, _ = apply_status(&room, PLAYER_ENTITY, .Shield, 1, 3)
	testing.expect(t, !offer_defense_qte(&room, &room.enemies[0]))
	_, _ = remove_status(&room, PLAYER_ENTITY, .Shield)
	pulse := arrow_test_loose(t, &room)
	loosed := pulse.events.events[0]
	testing.expect_value(t, loosed.kind, Game_Event_Kind.Arrow_Loosed)
	testing.expect_value(t, loosed.from_position, grid.Position{x = 7, y = 4})
	testing.expect_value(t, loosed.to_position, grid.Position{x = 0, y = 4})
	testing.expect_value(t, player.health, i32(100))
	// 0.3 s: two cells entered, not his.
	room.arrows.pending = 0.3
	testing.expect(t, resolve_arrow_flight(&room))
	testing.expect_value(t, player.health, i32(100))
	testing.expect_value(t, room.arrows.count, 1)
	room.arrows.pending = 0.02
	testing.expect(t, resolve_arrow_flight(&room))
	testing.expect_value(t, player.health, i32(97))
	testing.expect_value(t, room.arrows.count, 0)
	landed := false
	for event in room.recent_events.events[:room.recent_events.count] {
		landed = landed || (event.kind == .Arrow_Landed && event.target == PLAYER_ENTITY && event.to_position == player.position)
	}
	testing.expect(t, landed)
}

// Stepped out of its line, he is missed: it flies on to the wall and lands there.
@(test)
test_an_archers_arrow_misses_one_who_stepped_out_and_stops_at_the_wall :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := arrow_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	_ = arrow_test_loose(t, &room)
	room.player.position = {x = 4, y = 3}
	room.arrows.pending = 2
	testing.expect(t, resolve_arrow_flight(&room))
	testing.expect_value(t, player.health, i32(100))
	testing.expect_value(t, room.arrows.count, 0)
	wall := false
	for event in room.recent_events.events[:room.recent_events.count] {
		wall = wall || (event.kind == .Arrow_Landed && event.target == SYSTEM_ENTITY && event.to_position == grid.Position{x = 0, y = 4})
	}
	testing.expect(t, wall)
}

// A foe in its line takes it, and the player behind is spared.
@(test)
test_an_archers_arrow_strikes_the_first_foe_in_its_line :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	others := [?]Enemy_Spawn{{position = {x = 5, y = 4}, health = 20, attack = 1}}
	room := arrow_test_room(t, &data, &player, others[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	_ = arrow_test_loose(t, &room)
	room.arrows.pending = 1
	testing.expect(t, resolve_arrow_flight(&room))
	testing.expect_value(t, player.health, i32(100))
	testing.expect_value(t, room.enemies[1].health, i32(17))
	testing.expect_value(t, room.arrows.count, 0)
}

// The world holds it as it holds the world (a cast); a beat flies it first,
// before its own work: no beat ever passes an arrow.
@(test)
test_an_archers_arrow_holds_with_the_world_and_lands_before_a_beat :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := arrow_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	_ = arrow_test_loose(t, &room)
	tactical_begin_card_cast(&room, 1)
	testing.expect(t, !tactical_tick(&room, 0.5, true, false))
	testing.expect_value(t, room.arrows.pending, f64(0))
	testing.expect(t, !tactical_arrows_due(&room))
	player.tactical.cast_remaining = 0
	testing.expect(t, !tactical_tick(&room, 1, true, false))
	testing.expect(t, room.tactical_pulse.pending && room.arrows.pending > 0)
	testing.expect(t, continue_tactical_pulse(&room))
	testing.expect_value(t, player.health, i32(97))
	testing.expect_value(t, room.arrows.count, 0)
}
