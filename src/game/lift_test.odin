package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

// A hill of 14 steps (x 4..9, y 1..5) with a lift up its west cliff, from (3,1) to a landing over it on layer +1, a
// step from the top, its platform at the top; a hall on layer -1 at 0 under the hill along y = 3 (x 5..9), down a shaft
// from (6,3) on the top, its platform at the bottom; the hall opens on the ground east at (10,3), past a gate at
// (8,3) that opens from (7,3).
@(private = "file")
lift_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, spawns: []Enemy_Spawn = {}) -> (room: Room) {
	rows := [?]string{
		"#############",
		"#@..........#",
		"#...........#",
		"#...........#",
		"#...........#",
		"#..........>#",
		"#############",
	}
	parsed: level.Parse_Error
	data^, parsed, _ = level.from_ascii(rows[:])
	testing.expect_value(t, parsed, level.Parse_Error.None)
	for y in 1..=5 { for x in 4..=9 { testing.expect(t, level.set_height(data, {x = x, y = y}, 14)) } }
	for x in 5..=9 { testing.expect(t, level.set_tile(data, {x = x, y = 3, layer = -1}, {kind = .Floor})) }
	testing.expect(t, level.set_tile(data, {x = 3, y = 1, layer = 1}, {kind = .Floor}))
	testing.expect(t, level.set_height(data, {x = 3, y = 1, layer = 1}, 14))
	testing.expect(t, level.add_lift(data, {x = 3, y = 1}, {x = 3, y = 1, layer = 1}, 1))
	testing.expect(t, level.add_lift(data, {x = 6, y = 3}, {x = 6, y = 3, layer = -1}, 1))
	testing.expect(t, level.add_gate(data, {x = 8, y = 3, layer = -1}, {x = 7, y = 3, layer = -1}))
	error, _ := level.check_layers(data)
	testing.expect_value(t, error, level.Layer_Error.None)
	player^ = create_test_player(t)
	made: bool
	room, made = create_room(data, player, {enemies = spawns})
	testing.expect(t, made)
	return
}

@(private = "file")
ride_out :: proc(room: ^Room, index: int) {
	lift_tick(room, lift_journey_seconds(room, index)+0.01)
}

// The player calls the cliff's lift with a step toward its empty landing, waits for it, steps on and rides up: in
// the shaft nothing reaches him and he does nothing, until the platform stops at the top; then he walks on.
@(test)
test_the_player_calls_waits_for_and_rides_a_lift :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := lift_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	room.phase = .Loot
	room.player.position = {x = 2, y = 1}
	foot, top := grid.Position{x = 3, y = 1}, grid.Position{x = 3, y = 1, layer = 1}
	testing.expect(t, lift_landing_shut(&room, foot), "the platform waits at the top")
	testing.expect_value(t, try_move_player(&room, .East), Action_Result.Blocked)
	testing.expect(t, room.lifts.platforms[0].moving && room.lifts.platforms[0].at == 0 && !room.lifts.platforms[0].has_rider)
	testing.expect_value(t, room.player.position, grid.Position{x = 2, y = 1})
	ride_out(&room, 0)
	testing.expect(t, !lift_landing_shut(&room, foot), "the platform came down")
	testing.expect_value(t, try_move_player(&room, .East), Action_Result.Moved)
	testing.expect_value(t, room.player.position, top)
	testing.expect(t, lift_player_riding(&room) && tactical_player_intangible(&room))
	testing.expect(t, lift_landing_shut(&room, top) && lift_landing_shut(&room, foot), "no floor at either end on the way")
	testing.expect(t, try_move_player(&room, .East) != .Moved && room.player.position == top, "the rider does nothing")
	ride_out(&room, 0)
	testing.expect(t, !lift_player_riding(&room) && !tactical_player_intangible(&room))
	testing.expect_value(t, try_move_player(&room, .East), Action_Result.Moved)
	testing.expect_value(t, room.player.position, grid.Position{x = 4, y = 1})
}

// Down the shaft into the hall; the gate does not open from the open ground's side, and opens to a step from its lever.
@(test)
test_the_player_goes_down_the_shaft_and_opens_the_gate_from_its_lever :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := lift_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	room.phase = .Loot
	gate := grid.Position{x = 8, y = 3, layer = -1}
	// From the hall's far side, past the gate: it stays shut.
	room.player.position = {x = 9, y = 3, layer = -1}
	testing.expect_value(t, try_move_player(&room, .West), Action_Result.Blocked)
	_, open, _ := level.gate_at(&data, gate)
	testing.expect(t, !open, "a gate does not open from the other side")
	// From the top, down the shaft (its platform at the bottom: called up first).
	room.player.position = {x = 6, y = 2}
	testing.expect_value(t, try_move_player(&room, .South), Action_Result.Blocked)
	ride_out(&room, 1)
	testing.expect_value(t, try_move_player(&room, .South), Action_Result.Moved)
	testing.expect_value(t, room.player.position, grid.Position{x = 6, y = 3, layer = -1})
	ride_out(&room, 1)
	testing.expect_value(t, try_move_player(&room, .East), Action_Result.Moved)
	testing.expect_value(t, try_move_player(&room, .East), Action_Result.Used_Ability)
	_, open, _ = level.gate_at(&data, gate)
	testing.expect(t, open)
	testing.expect_value(t, room.player.position, grid.Position{x = 7, y = 3, layer = -1})
	for _ in 0..<3 { testing.expect_value(t, try_move_player(&room, .East), Action_Result.Moved) }
	testing.expect_value(t, room.player.position, grid.Position{x = 10, y = 3})
}

// A foe in the hall goes for the player on the hill through the shaft: it steps onto the platform, and rides it out of
// play to the top. With the platform away, it calls it and waits.
@(test)
test_a_foe_takes_the_lift_and_calls_it :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3, layer = -1}, health = 12, attack = 2, archetype = .Chaser}}
	room := lift_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, room.phase, Room_Phase.Combat)
	room.player.position = {x = 8, y = 1}
	bottom, top := grid.Position{x = 6, y = 3, layer = -1}, grid.Position{x = 6, y = 3}
	plan_enemy_intents(&room)
	foe := &room.enemies[0]
	testing.expect(t, foe.intent.kind == .Move && foe.intent.destination == bottom, "the way up is the shaft")
	// Its step onto the platform: up it goes, out of play on the way.
	foe.position = bottom
	testing.expect(t, lift_board(&room, enemy_entity(foe.id), bottom))
	testing.expect_value(t, room.enemies[0].position, top)
	testing.expect(t, enemy_is_out_of_play(&room, room.enemies[0].id))
	_, found := enemy_index_at(&room, top)
	testing.expect(t, !found, "nothing reaches it in the shaft")
	ride_out(&room, 1)
	testing.expect(t, !enemy_is_out_of_play(&room, room.enemies[0].id))
	// Back in the hall with the platform up: it calls it down.
	room.enemies[0].position = {x = 5, y = 3, layer = -1}
	testing.expect(t, lift_landing_shut(&room, bottom))
	plan_enemy_intents(&room)
	testing.expect(t, room.lifts.platforms[1].moving && room.lifts.platforms[1].at == 1, "the foe calls the platform down")
}
