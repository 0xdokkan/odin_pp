package hubworld

import "core:testing"

// The depot is laid out as in the user's drawing: the backpack up to the left, the
// character up to the right, the archive at the bottom, the way out down to the right.
@(test)
test_the_depot_is_laid_out_as_drawn :: proc(t: ^testing.T) {
	room := depot_room()
	backpack, character := room.stations[Depot_Station.Backpack].center, room.stations[Depot_Station.Character].center
	archive, plaza := room.stations[Depot_Station.Archive].center, room.stations[Depot_Station.Plaza].center
	testing.expect(t, backpack.x < -5 && backpack.y < -5, "backpack up to the left")
	testing.expect(t, character.x > 5 && character.y < -5, "character up to the right")
	testing.expect(t, abs(archive.x) < 0.01 && archive.y > 8, "archive at the bottom, in the middle")
	testing.expect(t, plaza.x > 5 && plaza.y > 5, "the way out down to the right")
	testing.expect_value(t, room.exit, int(Depot_Station.Plaza))
	// Doors for the first four, none for the crates.
	for k in 0..<room.count {
		testing.expect_value(t, room.stations[k].decor, k >= DEPOT_DOORS)
		s := room.stations[k]
		testing.expect(t, dot(s.front, normalize({-s.center.x, -s.center.y})) > 0.9999, "turned to the middle")
		extent := max(s.half.x, s.half.y) if k != room.exit else s.half.y
		testing.expect(t, length(s.center)+extent <= room.radius+0.01, "inside the room")
		for j in k+1..<room.count {
			testing.expect(t, station_distance(s, room.stations[j].center) > 2, "stations apart")
		}
	}
}

@(test)
test_a_click_in_the_depot_opens_each_door_once_and_the_crates_have_none :: proc(t: ^testing.T) {
	room := depot_room()
	for k in 0..<DEPOT_DOORS {
		w: Room_World
		room_place_at_centre(&w)
		room_walk_to(&room, &w, k)
		opened, which := 0, -1
		for _ in 0..<1800 {
			if entered, did := room_step(&room, &w, {}, 1.0/60.0); did { opened += 1; which = entered }
		}
		testing.expect_value(t, opened, 1)
		testing.expect_value(t, which, k)
	}
	// Walking into the crates stops at them and opens nothing.
	w: Room_World
	room_place_at_centre(&w)
	crates := room.stations[Depot_Station.Crates]
	for _ in 0..<900 {
		_, did := room_step(&room, &w, crates.center-w.position, 1.0/60.0)
		testing.expect(t, !did)
	}
	testing.expect(t, station_distance(crates, w.position) >= ROBOT_RADIUS-0.01, "stopped at the crates")
	// A click on the crates lands on nothing.
	_, found := room_station_at(&room, crates.center)
	testing.expect(t, !found)
}

@(test)
test_the_robot_comes_back_outside_the_door_of_the_depot_object_it_left_by :: proc(t: ^testing.T) {
	room := depot_room()
	for k in 0..<DEPOT_DOORS {
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
test_the_crates_pile_up_with_what_the_depot_holds :: proc(t: ^testing.T) {
	testing.expect_value(t, crate_count(0), CRATES_MINIMUM)
	testing.expect_value(t, crate_count(-4), CRATES_MINIMUM)
	previous := 0
	for stored in 0..<200 {
		count := crate_count(stored)
		testing.expect(t, count >= previous, "never fewer")
		testing.expect(t, count >= CRATES_MINIMUM && count <= CRATES_MAXIMUM)
		previous = count
	}
	testing.expect_value(t, crate_count(9), CRATES_MINIMUM+3)
	testing.expect_value(t, crate_count(1000), CRATES_MAXIMUM)
}

@(test)
test_the_archive_lights_its_spines_in_proportion_to_the_cards_known :: proc(t: ^testing.T) {
	testing.expect_value(t, shelf_lit(0, 40, 60), 0)
	testing.expect_value(t, shelf_lit(1, 400, 60), 1)
	testing.expect_value(t, shelf_lit(20, 40, 60), 30)
	testing.expect_value(t, shelf_lit(39, 40, 60), 58)
	testing.expect_value(t, shelf_lit(40, 40, 60), 60)
	testing.expect_value(t, shelf_lit(5, 0, 60), 0)
	previous := 0
	for known in 0..=40 {
		lit := shelf_lit(known, 40, 60)
		testing.expect(t, lit >= previous && lit <= 60)
		previous = lit
	}
}
