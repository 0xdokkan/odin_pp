package hubworld

import "core:testing"

// The twelve places stand in a half circle in front of the arrival, the way out behind.
@(test)
test_the_arcade_places_stand_in_a_half_circle_with_the_way_out_behind :: proc(t: ^testing.T) {
	room := arcade_room(ARCADE_SLOTS)
	testing.expect_value(t, room.count, ARCADE_SLOTS+1)
	testing.expect_value(t, room.exit, ARCADE_EXIT)
	for k in 0..<ARCADE_SLOTS {
		s := room.stations[k]
		testing.expect(t, s.center.y < 0, "in the upper half, ahead of the arrival")
		testing.expect(t, abs(length(s.center)-ARCADE_RING_RADIUS) < 0.01, "on the circle")
		testing.expect(t, dot(s.front, normalize({-s.center.x, -s.center.y})) > 0.9999, "turned to the middle")
		testing.expect(t, length(s.center)+max(s.half.x, s.half.y) <= room.radius, "inside the room")
		if k > 0 {
			previous := room.stations[k-1]
			testing.expect(t, station_distance(s, previous.center) > 1.5, "places apart")
			// Neighbouring doors do not overlap: walking along them opens nothing by chance.
			testing.expect(t, length(station_door_center(s)-station_door_center(previous)) > 2*DOOR_HALF_WIDTH+0.3, "doors apart")
		}
	}
	// The first place is to the left, the last to the right.
	testing.expect(t, room.stations[0].center.x < -8 && room.stations[ARCADE_SLOTS-1].center.x > 8)
	exit := room.stations[ARCADE_EXIT]
	testing.expect(t, exit.center.y > 10 && abs(exit.center.x) < 0.01, "the way out behind the arrival")
	testing.expect(t, length(exit.center)+exit.half.y <= room.radius+0.01)
}

// Lit cabinets are the first `unlocked` ones and have a door; the rest are cloth-covered
// decor with no name and no door; the way out is always a door.
@(test)
test_only_the_unlocked_cabinets_have_a_door_and_the_covered_ones_say_nothing :: proc(t: ^testing.T) {
	for unlocked in 0..=ARCADE_SLOTS {
		room := arcade_room(unlocked)
		for k in 0..<ARCADE_SLOTS {
			s := room.stations[k]
			testing.expect_value(t, s.decor, k >= unlocked)
			if s.decor {
				testing.expect_value(t, s.name, "")
				testing.expect_value(t, s.subtitle, "")
			}
		}
		testing.expect(t, !room.stations[ARCADE_EXIT].decor)
	}
	// Out-of-range counts are held to the twelve places.
	testing.expect_value(t, arcade_room(-3).stations[0].decor, true)
	testing.expect_value(t, arcade_room(99).stations[ARCADE_SLOTS-1].decor, false)
	// With none unlocked nothing but the way out can be entered, whatever the robot does.
	room := arcade_room(0)
	w: Room_World
	for k in 0..<ARCADE_SLOTS {
		room_place_at_centre(&w)
		for _ in 0..<600 {
			_, did := room_step(&room, &w, room.stations[k].center-w.position, 1.0/60.0)
			testing.expect(t, !did)
		}
		_, found := room_station_at(&room, room.stations[k].center)
		testing.expect(t, !found, "a covered cabinet cannot be clicked")
	}
}

@(test)
test_a_click_on_each_lit_cabinet_opens_its_door_once :: proc(t: ^testing.T) {
	room := arcade_room(ARCADE_SLOTS)
	for k in 0..<room.count {
		w: Room_World
		room_place_at_centre(&w)
		room_walk_to(&room, &w, k)
		opened, which := 0, -1
		for _ in 0..<2400 {
			if entered, did := room_step(&room, &w, {}, 1.0/60.0); did { opened += 1; which = entered }
		}
		testing.expect_value(t, opened, 1)
		testing.expect_value(t, which, k)
	}
}

@(test)
test_the_robot_comes_back_in_front_of_the_cabinet_it_left_by :: proc(t: ^testing.T) {
	room := arcade_room(ARCADE_SLOTS)
	for k in 0..<room.count {
		w: Room_World
		room_place_before(&room, &w, k)
		s := room.stations[k]
		testing.expect(t, !station_in_door(s, w.position, DOOR_REARM_MARGIN), "outside the door and its margin")
		testing.expect(t, w.armed[k])
		for other in 0..<room.count {
			testing.expect(t, station_distance(room.stations[other], w.position) >= ROBOT_RADIUS-0.01, "not inside anything")
		}
		for _ in 0..<60 { _, did := room_step(&room, &w, {}, 1.0/60.0); testing.expect(t, !did) }
	}
}

@(test)
test_the_twelve_cabinets_have_twelve_distinct_colours :: proc(t: ^testing.T) {
	for a in 0..<ARCADE_SLOTS {
		for b in a+1..<ARCADE_SLOTS {
			d := abs(arcade_hue(a)-arcade_hue(b))
			d = min(d, 360-d)
			testing.expect(t, d >= 10, "colours apart")
		}
	}
}
