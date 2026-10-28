package game

import "core:math"
import "core:testing"
import grid "../engine/grid"
import level "../level"

// FIRST PERSON BRAWLER's free body (first_person_fists.odin): the 13x13 room of
// the AK's tests, the player in (6, 6), a foe held far away in (2, 10) so the
// fight goes on.

@(private = "file")
fists_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, obstacles: []grid.Position = nil,
	spawns: []Enemy_Spawn = nil) -> Room {
	held := [?]Enemy_Spawn{{position = {x = 2, y = 10}, health = 40, attack = 1}}
	room := first_person_test_room(t, data, player, spawns if spawns != nil else held[:], obstacles)
	for foe in room.enemies { lasso_test_hold(&room, foe.id) }
	testing.expect(t, tactical_begin_first_person(&room, 30, .Fists))
	return room
}

// `seconds` of frames of `dt` with `input` (the jump and the dash only on the first).
@(private = "file")
fists_run :: proc(room: ^Room, input: First_Person_Fists_Input, seconds: f32, dt := f32(1.0/60)) -> (cells: [dynamic]grid.Position) {
	cells.allocator = context.temp_allocator
	given := input
	frames := int(math.round(seconds/dt))
	for _ in 0..<frames {
		_ = first_person_fists_move(room, given, dt)
		given.jump, given.dash = false, false
		if len(cells) == 0 || cells[len(cells)-1] != room.player.position { append(&cells, room.player.position) }
	}
	return
}

@(private = "file")
fists_speed :: proc(room: ^Room) -> f32 {
	v := room.first_person.fists.velocity
	return math.sqrt(v.x*v.x+v.y*v.y)
}

// Taken up at the centre of his cell; free at any angle, fast, his cell the one
// under the body; no time spent; a quick stop.
@(test)
test_fists_glide_free_at_any_angle :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := fists_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	f := &room.first_person.fists
	testing.expect(t, f.body == [2]f32{6.5, 6.5} && f.feet == 0 && !f.airborne)
	decisions := room.player.tactical.metrics.decisions
	// East and a little south: not along the grid.
	fists_run(&room, {wish = {1, 0.35}}, 0.6)
	d := f.body-[2]f32{6.5, 6.5}
	testing.expect(t, abs(d.y/d.x-0.35) < 0.01, "the way was not kept")
	testing.expect(t, abs(fists_speed(&room)-FISTS_SPEED) < 0.01, "not at full speed")
	testing.expect(t, d.x > 2.3 && d.x < 2.9)
	testing.expect_value(t, room.player.position, grid.Position{x = int(math.floor(f.body.x)), y = int(math.floor(f.body.y))})
	// No time spent, no decision counted.
	testing.expect(t, room.player.tactical.action_remaining == 0 && room.player.tactical.metrics.decisions == decisions)
	// Let go: still in about a tenth of a second, short of the cell's edge.
	fists_run(&room, {}, 0.2)
	testing.expect_value(t, fists_speed(&room), f32(0))
	// The full speed reached from rest in about a tenth of a second.
	fists_run(&room, {wish = {-1, 0}}, 0.12)
	testing.expect(t, fists_speed(&room) > FISTS_SPEED*0.95)
	// Only with the fists: the AK's view moves no body.
	room.first_person.weapon = .AK
	testing.expect_value(t, first_person_fists_move(&room, {wish = {1, 0}}, 0.1), Action_Result.Invalid_Phase)
}

// The same seconds give the same body whatever the frame.
@(test)
test_fists_same_at_any_frame_rate :: proc(t: ^testing.T) {
	bodies: [3][2]f32
	for dt, index in ([3]f32{1.0/30, 1.0/60, 1.0/144}) {
		data: level.Level
		player: Player
		room := fists_room(t, &data, &player)
		fists_run(&room, {wish = {1, -0.6}}, 0.6, dt)
		fists_run(&room, {wish = {-0.3, 1}, jump = true}, 0.6, dt)
		fists_run(&room, {}, 0.3, dt)
		bodies[index] = room.first_person.fists.body
		destroy_room(&room)
		level.destroy(&data)
	}
	for b in bodies[1:] { testing.expectf(t, abs(b.x-bodies[0].x) < 0.02 && abs(b.y-bodies[0].y) < 0.02, "%v against %v", b, bodies[0]) }
}

// Against a wall it slides along it; into a corner it stays out; the room's edge
// holds it.
@(test)
test_fists_slide_along_walls :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := fists_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	for y in 3..=9 { testing.expect(t, level.set_tile(&data, {x = 8, y = y}, {kind = .Wall})) }
	f := &room.first_person.fists
	fists_run(&room, {wish = {1, -0.5}}, 1.0)
	testing.expect(t, f.body.x <= 8-FISTS_RADIUS+1e-3, "into the wall")
	testing.expect(t, f.body.y < 5.8, "it did not slide north along the wall")
	testing.expect(t, room.player.position.x == 7)
	// North and east into the corner the wall's top makes with nothing: round it.
	fists_run(&room, {wish = {0.3, -1}}, 1.0)
	testing.expect(t, f.body.y >= 1+FISTS_RADIUS-1e-3, "through the room's edge")
	fists_run(&room, {wish = {1, 0}}, 1.0)
	testing.expect(t, f.body.x > 9, "it did not go round the wall's end")
}

// A low cover stops a walk; a jump clears it and lands past it, never on it.
@(test)
test_fists_jump_over_a_cover :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	cover := [?]grid.Position{{x = 8, y = 6}}
	room := fists_room(t, &data, &player, cover[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	f := &room.first_person.fists
	fists_run(&room, {wish = {1, 0}}, 0.8)
	testing.expect(t, f.body.x <= 8-FISTS_RADIUS+1e-3 && room.player.position == {x = 7, y = 6}, "walked into the cover")
	cells := fists_run(&room, {wish = {1, 0}, jump = true}, 0.8)
	for cell in cells { testing.expect(t, cell != cover[0], "stood on the cover") }
	testing.expect(t, room.player.position.x >= 9 && !f.airborne && f.feet == 0, "not past the cover")
	// The jump's top: FISTS_JUMP_STEPS, half a second in the air.
	testing.expect(t, abs(FISTS_GRAVITY*FISTS_JUMP_RISE_SECONDS-FISTS_JUMP_SPEED) < 1e-3)
}

// Steps: one up or down walking; a rise of 2 only with a jump, never one of 6; the
// edge of a drop of 2 holds a walk, a jump goes down it and falls it.
@(test)
test_fists_heights_as_on_foot_and_the_jump :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := fists_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	f := &room.first_person.fists
	// A stair of one step at x 7, a rise of 2 at x 8..9, a tower of 6 at x 10.
	for y in 1..=11 {
		testing.expect(t, level.set_height(&data, {x = 7, y = y}, 1))
		for x in 8..=9 { testing.expect(t, level.set_height(&data, {x = x, y = y}, 3)) }
		testing.expect(t, level.set_height(&data, {x = 10, y = y}, 9))
	}
	fists_run(&room, {wish = {1, 0}}, 1.0)
	testing.expect(t, room.player.position.x == 7 && f.feet == 1, "the stair's step")
	testing.expect(t, f.body.x <= 8-FISTS_RADIUS+1e-3, "walked up a rise of 2")
	fists_run(&room, {wish = {1, 0}, jump = true}, 0.6)
	testing.expect(t, room.player.position.x >= 8 && f.feet == 3 && !f.airborne, "the jump did not land on the rise")
	fists_run(&room, {wish = {1, 0}, jump = true}, 0.6)
	testing.expect(t, room.player.position.x == 9 && f.feet == 3, "a jump climbed the tower of 6")
	// Back west: the edge of the drop of 2 holds the walk.
	fists_run(&room, {wish = {-1, 0}}, 1.0)
	testing.expect(t, room.player.position.x == 8 && f.body.x >= 8+FISTS_RADIUS-1e-3, "walked off the edge")
	health := room.player.health
	fists_run(&room, {wish = {-1, 0}, jump = true}, 0.6)
	testing.expect(t, room.player.position.x <= 7 && !f.airborne, "the jump did not go down")
	testing.expect_value(t, health-room.player.health, fall_damage(2))
}

// A foe's cell stops the body like a wall.
@(test)
test_fists_foe_cell_stops_the_body :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	foes := [?]Enemy_Spawn{{position = {x = 8, y = 6}, health = 40, attack = 1}}
	room := fists_room(t, &data, &player, nil, foes[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	f := &room.first_person.fists
	fists_run(&room, {wish = {1, 0}}, 1.0)
	testing.expect(t, f.body.x <= 8-FISTS_RADIUS+1e-3 && room.player.position == {x = 7, y = 6})
	testing.expect(t, room.enemies[0].health == 40, "a push hurt it")
}

// The dash: 2 cells in 0.18 s at any angle (still: the look's way), then 1.2 s
// before the next.
@(test)
test_fists_dash :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := fists_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	f := &room.first_person.fists
	start := f.body
	fists_run(&room, {dash = true, look = {0, -1}}, FISTS_DASH_SECONDS, FISTS_STEP)
	testing.expect(t, abs(start.y-f.body.y-FISTS_DASH_CELLS) < 0.05 && abs(f.body.x-start.x) < 1e-3, "not 2 cells along the look")
	fists_run(&room, {}, 0.3)
	at := f.body
	fists_run(&room, {dash = true, wish = {1, 1}}, 0.1)
	testing.expect(t, f.body.x-at.x < 0.6, "a second dash before its recharge")
	fists_run(&room, {}, FISTS_DASH_RECHARGE)
	at = f.body
	fists_run(&room, {dash = true, wish = {1, 1}}, FISTS_DASH_SECONDS, FISTS_STEP)
	moved := f.body-at
	testing.expect(t, abs(moved.x-moved.y) < 0.02 && moved.x > 1.2, "the diagonal dash")
}

// Every cell the centre enters is a step into it, a Moved of its own: a trap
// there bites, as under a step.
@(test)
test_fists_cells_bring_their_effects :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	rows: [13]string
	cells: [13][13]u8
	for y in 0..<13 {
		for x in 0..<13 { cells[y][x] = '#' if x == 0 || y == 0 || x == 12 || y == 12 else '.' }
	}
	cells[6][6], cells[11][11] = '@', '>'
	for y in 0..<13 { rows[y] = string(cells[y][:]) }
	parsed: level.Parse_Error
	data, parsed, _ = level.from_ascii(rows[:])
	testing.expect_value(t, parsed, level.Parse_Error.None)
	defer level.destroy(&data)
	player = create_test_player(t)
	player.stats.max_health, player.health, player.stats.defense = 100, 100, 0
	testing.expect(t, configure_tactical(&player, DEFAULT_TACTICAL_CONFIG))
	held := [?]Enemy_Spawn{{position = {x = 2, y = 10}, health = 40, attack = 1}}
	traps := [?]Trap_Spawn{{position = {x = 8, y = 6}, damage = 3}}
	room, made := create_room(&data, &player, {enemies = held[:], traps = traps[:]})
	testing.expect(t, made)
	defer destroy_room(&room)
	lasso_test_hold(&room, room.enemies[0].id)
	testing.expect(t, tactical_begin_first_person(&room, 30, .Fists))
	moved := 0
	for _ in 0..<36 {
		_ = first_person_fists_move(&room, {wish = {1, 0}}, 1.0/60)
		for event in room.recent_events.events[:room.recent_events.count] {
			if event.kind == .Moved && event.target == PLAYER_ENTITY { moved += 1 }
		}
	}
	testing.expect(t, room.player.position.x >= 8 && moved == room.player.position.x-6, "not a Moved a cell")
	testing.expect_value(t, room.player.health, i32(100-3))
}

// A lift: pushing toward its landing calls the platform; on it the body rides,
// held; at the top it walks on.
@(test)
test_fists_call_and_ride_a_lift :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := fists_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	// A hill of 14 steps east of x 9, a lift up its cliff from (8,6) to a landing over it.
	for y in 1..=11 { for x in 9..=11 { testing.expect(t, level.set_height(&data, {x = x, y = y}, 14)) } }
	top := grid.Position{x = 8, y = 6, layer = 1}
	testing.expect(t, level.set_tile(&data, top, {kind = .Floor}))
	testing.expect(t, level.set_height(&data, top, 14))
	testing.expect(t, level.add_lift(&data, {x = 8, y = 6}, top, 1))
	error, _ := level.check_layers(&data)
	testing.expect_value(t, error, level.Layer_Error.None)
	lifts_reset(&room)
	testing.expect(t, lift_landing_shut(&room, {x = 8, y = 6}), "the platform waits at the top")
	f := &room.first_person.fists
	fists_run(&room, {wish = {1, 0}}, 0.6)
	testing.expect(t, room.lifts.platforms[0].moving && room.player.position == {x = 7, y = 6}, "the push did not call it")
	lift_tick(&room, lift_journey_seconds(&room, 0)+0.01)
	fists_run(&room, {wish = {1, 0}}, 0.3)
	testing.expect(t, lift_player_riding(&room) && f.body == [2]f32{8.5, 6.5}, "not riding, held")
	lift_tick(&room, lift_journey_seconds(&room, 0)+0.01)
	fists_run(&room, {wish = {1, 0}}, 0.6)
	testing.expect(t, !lift_player_riding(&room) && room.player.position.x >= 9 && f.feet == 14, "not on the hill")
}
