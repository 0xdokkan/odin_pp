package game

import "core:math"
import "core:testing"
import grid "../engine/grid"
import level "../level"

// FIRST PERSON BRAWLER's critical marks (first_person_marks.odin), in the AK's
// test room with the fists, the player in (6, 6).

@(private = "file")
marks_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, spawns: []Enemy_Spawn) -> Room {
	room := first_person_test_room(t, data, player, spawns)
	for foe in room.enemies { lasso_test_hold(&room, foe.id) }
	testing.expect(t, tactical_begin_first_person(&room, 30, .Fists))
	return room
}

@(private = "file")
marks_run :: proc(room: ^Room, seconds: f32, punch := First_Person_Punch.None, yaw := f32(0), pitch := f32(0), wish := [2]f32{}) {
	input := First_Person_Fists_Input{wish = wish, punch = punch, aim = {yaw = yaw, pitch = pitch}}
	for _ in 0..<int(math.round(seconds/FISTS_STEP)) {
		_ = first_person_fists_move(room, input, FISTS_STEP)
		input.punch = .None
	}
}

// The mark watching `id`, set lit on `zone`, on the head or not.
@(private = "file")
marks_light :: proc(t: ^testing.T, room: ^Room, id: u32, zone: i8, high: bool) {
	for &mark in room.first_person.fists.marks {
		if mark.enemy_id != id { continue }
		mark.zone, mark.high, mark.lit, mark.wait, mark.chained = zone, high, 1, 0, false
		return
	}
	testing.expect(t, false, "no mark watches the foe")
}

// The marks watch the nearest foes within 3.5 cells, four at most; one out of
// reach is not watched.
@(test)
test_marks_watch_the_nearest_foes_in_reach :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{
		{position = {x = 8, y = 6}, health = 30, attack = 1}, {position = {x = 6, y = 8}, health = 30, attack = 1},
		{position = {x = 4, y = 6}, health = 30, attack = 1}, {position = {x = 6, y = 4}, health = 30, attack = 1},
		{position = {x = 8, y = 8}, health = 30, attack = 1}, {position = {x = 10, y = 10}, health = 30, attack = 1},
	}
	room := marks_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	marks_run(&room, FISTS_STEP)
	near := [4]grid.Position{{x = 8, y = 6}, {x = 6, y = 8}, {x = 4, y = 6}, {x = 6, y = 4}}
	for mark in room.first_person.fists.marks {
		index, found := enemy_index_by_id(&room, mark.enemy_id)
		testing.expect(t, found)
		in_near := false
		for cell in near { in_near = in_near || room.enemies[index].position == cell }
		testing.expectf(t, in_near, "a mark on %v", room.enemies[index].position)
	}
	// One of the four goes out of reach: the next nearest, (8, 8), takes its slot.
	room.enemies[0].position = {x = 1, y = 1}
	marks_run(&room, FISTS_STEP)
	watched := false
	for mark in room.first_person.fists.marks {
		index, _ := enemy_index_by_id(&room, mark.enemy_id)
		watched = watched || room.enemies[index].position == {x = 8, y = 8}
	}
	testing.expect(t, watched, "the next nearest is not watched")
}

// A mark lights after 0.6..1.4 s, stays lit 1.2 s, goes dark 0.6..1.4 s; the same
// room gives the same marks.
@(test)
test_marks_light_on_their_time_and_repeat :: proc(t: ^testing.T) {
	Light :: struct { at: f32, zone: i8, high: bool }
	runs: [2][4]Light
	for run in 0..<2 {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {x = 8, y = 6}, health = 30, attack = 1}}
		room := marks_room(t, &data, &player, spawns[:])
		lit_since, dark_since := f32(-1), f32(0)
		count := 0
		for step in 1..=2400 {
			marks_run(&room, FISTS_STEP)
			now := f32(step)*FISTS_STEP
			mark := room.first_person.fists.marks[0]
			if mark.lit > 0 && lit_since < 0 {
				wait := now-dark_since
				testing.expectf(t, wait >= FISTS_MARK_WAIT_MIN-0.01 && wait <= FISTS_MARK_WAIT_MAX+0.01, "lit after %v s", wait)
				if count < 4 { runs[run][count] = {at = now, zone = mark.zone, high = mark.high} }
				count += 1
				lit_since = now
			} else if mark.lit <= 0 && lit_since >= 0 {
				testing.expectf(t, abs(now-lit_since-FISTS_MARK_SECONDS) < 0.01, "lit %v s", now-lit_since)
				lit_since, dark_since = -1, now
			}
		}
		testing.expect(t, count >= 4, "too few marks in 10 s (2400 steps)")
		destroy_room(&room)
		level.destroy(&data)
	}
	testing.expect(t, runs[0] == runs[1], "the same room gave other marks")
}

// The zones across the card as he sees it, from the crosshair: its left side,
// left of its middle, right of it, its right side; head or body with the view's pitch.
@(test)
test_marks_zones_under_the_crosshair :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 8, y = 6}, health = 60, attack = 1}}
	room := marks_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	marks_run(&room, 0.8, wish = {1, 0})
	marks_run(&room, 0.3)
	id := room.enemies[0].id
	for yaw, zone in ([4]f32{-0.55, -0.2, 0.2, 0.55}) {
		got, high, on := first_person_crosshair_zone(&room, id, {yaw = yaw})
		testing.expectf(t, on && got == i8(zone) && high, "yaw %v: zone %v high %v on %v", yaw, got, high, on)
	}
	_, high, on := first_person_crosshair_zone(&room, id, {yaw = -0.2, pitch = -0.45})
	testing.expect(t, on && !high, "looking down is not the body")
	_, _, on = first_person_crosshair_zone(&room, id, {yaw = 1.2})
	testing.expect(t, !on, "looking away is on the card")
}

// The right punch on the lit mark with the crosshair over it: three times its
// damage, the mark out, the next lit in 0.3 s elsewhere; a critical hook
// staggers. The wrong punch, the crosshair beside the mark, or the head for the
// body: the punch's own damage, the mark still lit.
@(test)
test_marks_make_criticals :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 8, y = 6}, health = 200, attack = 1}}
	room := marks_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	marks_run(&room, 0.8, wish = {1, 0})
	marks_run(&room, 0.3)
	foe := &room.enemies[0]
	id := foe.id
	blow :: proc(t: ^testing.T, room: ^Room, punch: First_Person_Punch, yaw, pitch: f32, zone: i8, high: bool) -> i32 {
		marks_light(t, room, room.enemies[0].id, zone, high)
		health := room.enemies[0].health
		marks_run(room, FISTS_PUNCHES[punch].land+FISTS_STEP, punch, yaw, pitch)
		lost := health-room.enemies[0].health
		marks_run(room, FISTS_PUNCHES[punch].recover)
		return lost
	}
	// The wrong punch, the crosshair beside, the head for the body: no critical.
	testing.expect_value(t, blow(t, &room, .Cross, -0.2, 0, 1, true), FISTS_PUNCHES[.Cross].damage)
	testing.expect_value(t, blow(t, &room, .Jab, 0.2, 0, 1, true), FISTS_PUNCHES[.Jab].damage)
	testing.expect_value(t, blow(t, &room, .Jab, -0.2, 0, 1, false), FISTS_PUNCHES[.Jab].damage)
	testing.expect_value(t, room.first_person.fists.crits, i32(0))
	// The jab on its mark: a critical, the mark out and chained.
	marks_light(t, &room, id, 1, true)
	health := foe.health
	marks_run(&room, FISTS_PUNCHES[.Jab].land+FISTS_STEP, .Jab, -0.2)
	testing.expect_value(t, health-foe.health, FISTS_PUNCHES[.Jab].damage*FISTS_CRITICAL_FACTOR)
	testing.expect(t, room.first_person.fists.crits == 1 && first_person_lit_mark(&room, id) == nil)
	marks_run(&room, FISTS_MARK_CHAIN+0.01)
	next := first_person_lit_mark(&room, id)
	testing.expect(t, next != nil && next.zone != 1, "the chain's next mark")
	marks_run(&room, FISTS_PUNCHES[.Jab].recover)
	// The body's mark looking down.
	testing.expect_value(t, blow(t, &room, .Jab, -0.2, -0.45, 1, false), FISTS_PUNCHES[.Jab].damage*FISTS_CRITICAL_FACTOR)
	// The left hook on its mark: a critical that staggers.
	testing.expect_value(t, blow(t, &room, .Left_Hook, -0.55, 0, 0, true), FISTS_PUNCHES[.Left_Hook].damage*FISTS_CRITICAL_FACTOR)
	_, staggered := status_for_entity(&room, enemy_entity(id), .Stagger)
	testing.expect(t, staggered, "the critical hook did not stagger")
	testing.expect_value(t, room.first_person.fists.crits, i32(3))
}
