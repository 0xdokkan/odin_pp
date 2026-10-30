package hubworld

import "core:testing"

// The hall's stations stand as in the user's drawing: 6 Ranch 7 up to the left, Tre in
// fuga up to the right, the way out to the plaza at the right, the roulette down to the
// left and the d20 duel down to the right; each turned to the middle.
@(test)
test_the_casino_hall_is_laid_out_as_drawn :: proc(t: ^testing.T) {
	room := casino_room()
	ranch, run, roulette := room.stations[Casino_Station.Ranch].center, room.stations[Casino_Station.Run].center, room.stations[Casino_Station.Roulette].center
	dice, plaza := room.stations[Casino_Station.Dice].center, room.stations[Casino_Station.Plaza].center
	testing.expect(t, ranch.x < -5 && ranch.y < -5, "6 Ranch 7 up to the left")
	testing.expect(t, run.x > 5 && run.y < -5, "Tre in fuga up to the right")
	testing.expect(t, roulette.x < -5 && roulette.y > 5, "the roulette down to the left")
	testing.expect(t, dice.x > 5 && dice.y > 5, "the d20 down to the right")
	testing.expect(t, plaza.x > 10 && abs(plaza.y) < 0.01, "the way out at the right")
	testing.expect_value(t, room.exit, int(Casino_Station.Plaza))
	for k in 0..<room.count {
		s := room.stations[k]
		toward := normalize({-s.center.x, -s.center.y})
		testing.expect(t, dot(s.front, toward) > 0.9999, "turned to the middle")
		// The way out is set in the wall: only its depth counts.
		extent := max(s.half.x, s.half.y) if k != room.exit else s.half.y
		testing.expect(t, length(s.center)+extent <= room.radius+0.01, "inside the room")
		for j in k+1..<room.count {
			testing.expect(t, station_distance(s, room.stations[j].center) > 2, "stations apart")
		}
	}
}

@(test)
test_the_robot_arrives_at_the_middle_and_nothing_opens :: proc(t: ^testing.T) {
	room := casino_room()
	w: Room_World
	room_place_at_centre(&w)
	for _ in 0..<120 {
		_, did := room_step(&room, &w, {}, 1.0/60.0)
		testing.expect(t, !did)
	}
	for k in 0..<room.count { testing.expect(t, !station_in_door(room.stations[k], w.position, DOOR_REARM_MARGIN)) }
}

@(test)
test_the_robot_cannot_enter_a_station_nor_leave_the_room :: proc(t: ^testing.T) {
	room := casino_room()
	w: Room_World
	for k in 0..<room.count {
		room_place_at_centre(&w)
		centre := room.stations[k].center
		for _ in 0..<600 { room_step(&room, &w, centre-w.position, 1.0/60.0) }
		testing.expect(t, station_distance(room.stations[k], w.position) >= ROBOT_RADIUS-0.01, "stopped at the footprint")
		testing.expect(t, length(w.position) <= room.radius)
	}
	for direction in ([4]Vec2{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
		room_place_at_centre(&w)
		for _ in 0..<2000 { room_step(&room, &w, direction, 1.0/60.0) }
		testing.expect(t, length(w.position) <= room.radius-ROBOT_RADIUS+0.01)
	}
}

// A click on each station walks the robot to its door and opens that one only, once.
@(test)
test_a_click_on_each_station_opens_its_door_once :: proc(t: ^testing.T) {
	room := casino_room()
	for k in 0..<room.count {
		w: Room_World
		room_place_at_centre(&w)
		room_walk_to(&room, &w, k)
		opened := 0
		which := -1
		for _ in 0..<1800 {
			if entered, did := room_step(&room, &w, {}, 1.0/60.0); did { opened += 1; which = entered }
		}
		testing.expect_value(t, opened, 1)
		testing.expect_value(t, which, k)
	}
}

@(test)
test_the_robot_comes_back_outside_the_door_of_the_station_it_left_by :: proc(t: ^testing.T) {
	room := casino_room()
	for k in 0..<room.count {
		w: Room_World
		room_place_before(&room, &w, k)
		s := room.stations[k]
		testing.expect(t, !station_in_door(s, w.position, DOOR_REARM_MARGIN), "outside the door and its margin")
		testing.expect(t, station_distance(s, w.position) >= ROBOT_RADIUS)
		testing.expect(t, length(w.position) < room.radius)
		testing.expect(t, w.armed[k])
		for _ in 0..<60 { _, did := room_step(&room, &w, {}, 1.0/60.0); testing.expect(t, !did) }
	}
}

@(test)
test_a_click_in_the_hall_lands_on_the_station_under_it :: proc(t: ^testing.T) {
	room := casino_room()
	for k in 0..<room.count {
		hit, found := room_station_at(&room, room.stations[k].center)
		testing.expect(t, found)
		testing.expect_value(t, hit, k)
	}
	_, found := room_station_at(&room, {0, 0})
	testing.expect(t, !found)
}

@(test)
test_a_ray_hits_the_station_it_points_at :: proc(t: ^testing.T) {
	room := casino_room()
	for k in 0..<room.count {
		s := room.stations[k]
		from := station_from_local(s, {0, s.half.y+6})
		origin := [3]f32{from.x, s.height+6, from.y}
		target := [3]f32{s.center.x, s.height*0.5, s.center.y}
		distance, hit := station_ray_hits(s, origin, {target.x-origin.x, target.y-origin.y, target.z-origin.z})
		testing.expect(t, hit && distance > 0 && distance < 1, "the ray enters the box")
		_, hit_middle := station_ray_hits(s, {0, 10, 0}, {0, -1, 0})
		testing.expect(t, !hit_middle)
	}
}

// The dissolve goes dark, switches once at the darkest moment and clears again.
@(test)
test_the_dissolve_switches_once_in_the_dark :: proc(t: ^testing.T) {
	f: Fade
	testing.expect_value(t, fade_alpha(f), f32(0))
	testing.expect(t, !fade_step(&f, 0.1), "an idle dissolve does nothing")
	fade_begin(&f)
	switches := 0
	previous := f32(0)
	rising := true
	darkest := f32(0)
	for _ in 0..<60 {
		dt := f32(1.0/60.0)
		if fade_step(&f, dt) {
			switches += 1
			testing.expect(t, fade_alpha(f) > 0.95, "dark when it switches")
		}
		a := fade_alpha(f)
		darkest = max(darkest, a)
		if rising && a < previous { rising = false }
		if !rising { testing.expect(t, a <= previous+0.0001, "clears monotonically") }
		previous = a
	}
	testing.expect_value(t, switches, 1)
	testing.expect(t, darkest > 0.99)
	testing.expect(t, !f.active, "over after two phases")
	testing.expect_value(t, fade_alpha(f), f32(0))
}

@(test)
test_the_hall_ambience_is_light_and_the_wheel_ticks_only_near_the_roulette :: proc(t: ^testing.T) {
	a := ambience_start(7)
	murmurs, slots, wheels := 0, 0, 0
	for _ in 0..<(60*60) {
		cues := ambience_step(&a, 1.0/60.0, false)
		if .Murmur in cues { murmurs += 1 }
		if .Slot in cues { slots += 1 }
		if .Wheel in cues { wheels += 1 }
	}
	// A minute: a murmur every 3.5 to 5 seconds, a slot every 6 to 11, no wheel away.
	testing.expect(t, murmurs >= 11 && murmurs <= 18, "murmur now and then")
	testing.expect(t, slots >= 5 && slots <= 11, "a slot now and then")
	testing.expect_value(t, wheels, 0)
	for _ in 0..<(60*10) {
		if .Wheel in ambience_step(&a, 1.0/60.0, true) { wheels += 1 }
	}
	testing.expect(t, wheels >= 20 && wheels <= 24, "the wheel ticks while the robot is near")
	// The same seed gives the same sounds.
	first, second := ambience_start(3), ambience_start(3)
	for _ in 0..<600 {
		testing.expect(t, ambience_step(&first, 1.0/60.0, false) == ambience_step(&second, 1.0/60.0, false))
	}
}
