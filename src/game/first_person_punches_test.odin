package game

import "core:math"
import "core:testing"
import level "../level"

// FIRST PERSON BRAWLER's punches (first_person_punches.odin): the AK's test room,
// the player in (6, 6) with the fists, a foe held in (8, 6); walked up to it the
// body stands at 7.7, its card 0.8 ahead.

@(private = "file")
punch_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, health := i32(60)) -> Room {
	spawns := [?]Enemy_Spawn{{position = {x = 8, y = 6}, health = health, attack = 1}, {position = {x = 2, y = 10}, health = 40, attack = 1}}
	room := first_person_test_room(t, data, player, spawns[:])
	for foe in room.enemies { lasso_test_hold(&room, foe.id) }
	testing.expect(t, tactical_begin_first_person(&room, 30, .Fists))
	return room
}

// The critical marks kept dark: these tests weigh the punches alone
// (first_person_marks_test.odin weighs the criticals).
@(private = "file")
punch_dark :: proc(room: ^Room) {
	for &mark in room.first_person.fists.marks { mark.lit, mark.wait = 0, 1000 }
}

// Frames of `dt` for `seconds`: the punch pressed on the first, at `yaw`.
@(private = "file")
punch_run :: proc(room: ^Room, seconds: f32, punch := First_Person_Punch.None, yaw := f32(0), wish := [2]f32{}, dt := f32(1.0/60)) {
	input := First_Person_Fists_Input{wish = wish, punch = punch, aim = {yaw = yaw}}
	for _ in 0..<int(math.round(seconds/dt)) {
		_ = first_person_fists_move(room, input, dt)
		punch_dark(room)
		input.punch = .None
	}
}

@(private = "file")
punch_up_to_the_foe :: proc(t: ^testing.T, room: ^Room) {
	punch_run(room, 0.8, wish = {1, 0})
	punch_run(room, 0.3)
	testing.expect(t, abs(room.first_person.fists.body.x-(8-FISTS_RADIUS)) < 1e-3, "not up against the foe")
}

// The buttons: left a jab, right a cross, with Shift the hooks.
@(test)
test_punches_from_the_buttons :: proc(t: ^testing.T) {
	testing.expect_value(t, first_person_punch_for(true, false, false), First_Person_Punch.Jab)
	testing.expect_value(t, first_person_punch_for(false, true, false), First_Person_Punch.Cross)
	testing.expect_value(t, first_person_punch_for(true, false, true), First_Person_Punch.Left_Hook)
	testing.expect_value(t, first_person_punch_for(false, true, true), First_Person_Punch.Right_Hook)
	testing.expect_value(t, first_person_punch_for(false, false, true), First_Person_Punch.None)
	// The damage the user chose, and the times of the plan.
	testing.expect(t, FISTS_PUNCHES[.Jab].damage == 3 && FISTS_PUNCHES[.Cross].damage == 4 && FISTS_PUNCHES[.Left_Hook].damage == 6)
	testing.expect(t, FISTS_PUNCHES[.Jab].land < FISTS_PUNCHES[.Cross].land && FISTS_PUNCHES[.Cross].land < FISTS_PUNCHES[.Right_Hook].land)
}

// Each punch lands after its own time, with its damage, as a fists' wound; none is
// an action of his.
@(test)
test_punches_land_on_time_with_their_damage :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := punch_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	punch_up_to_the_foe(t, &room)
	foe := &room.enemies[0]
	decisions := room.player.tactical.metrics.decisions
	health := foe.health
	for punch in ([3]First_Person_Punch{.Jab, .Cross, .Right_Hook}) {
		rules := FISTS_PUNCHES[punch]
		punch_run(&room, rules.land-0.02, punch, dt = FISTS_STEP)
		testing.expectf(t, foe.health == health, "%v landed early", punch)
		// The step that lands it, its wound marked as the fists'.
		marked := false
		for _ in 0..<int(math.round(0.03/FISTS_STEP)) {
			_ = first_person_fists_move(&room, {aim = {yaw = 0}}, FISTS_STEP)
			punch_dark(&room)
			for event in room.recent_events.events[:room.recent_events.count] { marked = marked || event_is_first_person_punch(event) }
		}
		testing.expectf(t, health-foe.health == rules.damage, "%v: %d", punch, health-foe.health)
		testing.expectf(t, marked, "%v: no fists' wound among the events", punch)
		health = foe.health
		punch_run(&room, rules.recover, dt = FISTS_STEP)
	}
	testing.expect(t, room.first_person.shots == 3 && room.first_person.hits == 3)
	// The board knows whom the last one struck (its card flashes).
	testing.expect_value(t, room.first_person.fists.struck, foe.id)
	testing.expect(t, room.player.tactical.action_remaining == 0 && room.player.tactical.metrics.decisions == decisions, "a punch took time")
}

// Too far, a punch misses and costs only its own time; the hooks reach less far
// than the straights, and a hook reaches a foe off to its own side.
@(test)
test_punches_reach_and_the_hooks_side :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := punch_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	foe := &room.enemies[0]
	health := foe.health
	// From his cell's centre the card is 2 cells ahead: no punch reaches.
	punch_run(&room, 0.5, .Jab)
	testing.expect(t, foe.health == health && room.first_person.shots == 1 && room.first_person.hits == 0)
	punch_up_to_the_foe(t, &room)
	// Looking 55 degrees to the right of it: the foe is on the view's left. The
	// jab and the right hook miss; the left hook turns to it.
	yaw := f32(55*math.PI/180)
	punch_run(&room, 0.5, .Jab, yaw)
	punch_run(&room, 0.6, .Right_Hook, yaw)
	testing.expect(t, foe.health == health, "a punch looking away landed")
	punch_run(&room, 0.6, .Left_Hook, yaw)
	testing.expect_value(t, health-foe.health, FISTS_PUNCHES[.Left_Hook].damage)
}

// A press in the last 0.15 s of a punch waits for its end; an earlier one is
// dropped. The same presses give the same blows at 30, 60 and 144 frames a second.
@(test)
test_punches_wait_and_keep_time_at_any_frame_rate :: proc(t: ^testing.T) {
	for dt in ([3]f32{1.0/30, 1.0/60, 1.0/144}) {
		data: level.Level
		player: Player
		room := punch_room(t, &data, &player)
		punch_up_to_the_foe(t, &room)
		foe := &room.enemies[0]
		health := foe.health
		frame := 0
		press := proc(at: f32, frame: int, dt: f32) -> bool { return int(math.round(at/dt)) == frame }
		lost_at_third, lost_at_half := i32(-1), i32(-1)
		for elapsed := f32(0); frame < int(math.round(0.6/dt)); frame += 1 {
			input := First_Person_Fists_Input{aim = {yaw = 0}}
			// 0 s the jab; 1/20 s too early (dropped); 1/6 s in the jab's last 0.15 s (kept).
			if press(0, frame, dt) { input.punch = .Jab }
			if press(1.0/20, frame, dt) && dt != 1.0/30 { input.punch = .Cross }
			if press(1.0/6, frame, dt) { input.punch = .Cross }
			_ = first_person_fists_move(&room, input, dt)
			punch_dark(&room)
			elapsed += dt
			if frame+1 == int(math.round((1.0/3)/dt)) { lost_at_third = health-foe.health }
			if frame+1 == int(math.round(0.5/dt)) { lost_at_half = health-foe.health }
		}
		// The jab has landed by 1/3 s, the cross (from 0.30 s, landing at 0.46 s) by 0.5 s.
		testing.expectf(t, lost_at_third == 3 && lost_at_half == 7, "at %v fps: %d then %d", 1/dt, lost_at_third, lost_at_half)
		testing.expectf(t, room.first_person.shots == 2, "at %v fps: %d punches", 1/dt, room.first_person.shots)
		destroy_room(&room)
		level.destroy(&data)
	}
}

// While a punch is out he moves at half his speed; during a dash he throws none.
@(test)
test_punches_slow_the_body_and_wait_for_a_dash :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := punch_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	f := &room.first_person.fists
	// South, away from the foe: a jab out, the body at half its speed.
	punch_run(&room, 0.2, .Jab, f32(math.PI/2), {0, 1})
	speed := math.sqrt(f.velocity.x*f.velocity.x+f.velocity.y*f.velocity.y)
	testing.expectf(t, abs(speed-FISTS_SPEED*FISTS_PUNCH_SPEED_FACTOR) < 0.05, "speed %v", speed)
	punch_run(&room, 0.4)
	shots := room.first_person.shots
	_ = first_person_fists_move(&room, {dash = true, look = {-1, 0}}, FISTS_STEP)
	punch_run(&room, 0.05, .Jab)
	testing.expect(t, room.first_person.shots == shots, "a punch thrown during the dash")
}

// The blow that kills the last foe ends the fight, and the view with it.
@(test)
test_punches_can_end_the_fight :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 8, y = 6}, health = 3, attack = 1}}
	room := first_person_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	lasso_test_hold(&room, room.enemies[0].id)
	testing.expect(t, tactical_begin_first_person(&room, 30, .Fists))
	punch_up_to_the_foe(t, &room)
	result := Action_Result.None
	input := First_Person_Fists_Input{punch = .Jab}
	for _ in 0..<30 {
		result = first_person_fists_move(&room, input, 1.0/60)
		input.punch = .None
		if result == .Combat_Ended { break }
	}
	testing.expect_value(t, result, Action_Result.Combat_Ended)
	testing.expect(t, len(room.enemies) == 0 && !tactical_first_person_active(&room))
}
