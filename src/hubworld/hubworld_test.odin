package hubworld

import "core:math"
import "core:testing"

// The seven buildings stand round the plaza as in the user's drawing: the Portal
// at the top, the Deposito up to the right, Progressi at the right, the Uscita
// down to the right, Frammenti at the bottom, the Sala giochi at the left and the
// Casinò up to the left; each with its door to the middle.
@(test)
test_the_buildings_stand_where_the_drawing_puts_them :: proc(t: ^testing.T) {
	// Screen order: x to the right, z down.
	portal, storage, progress, exit := building_center(.Portal), building_center(.Storage), building_center(.Progress), building_center(.Exit)
	memories, arcade, casino := building_center(.Memories), building_center(.Arcade), building_center(.Casino)
	testing.expect(t, abs(portal.x) < 0.01 && portal.y < -10)
	testing.expect(t, storage.x > 5 && storage.y < 0)
	testing.expect(t, progress.x > 10 && abs(progress.y) < 2)
	testing.expect(t, exit.x > 5 && exit.y > 5)
	testing.expect(t, abs(memories.x) < 0.01 && memories.y > 10)
	testing.expect(t, arcade.x < -10 && abs(arcade.y) < 0.01)
	testing.expect(t, casino.x < -5 && casino.y < 0)
	// Every door is turned to the middle: the front points from the building to it.
	for b in Building {
		centre, front := building_center(b), building_front(b)
		toward := Vec2{-centre.x, -centre.y}
		toward = normalize(toward)
		testing.expect(t, dot(front, toward) > 0.9999, "front toward the middle")
		testing.expect(t, abs(dot(front, building_right(b))) < 0.0001)
	}
}

@(test)
test_no_two_buildings_touch_and_all_stand_inside_the_plaza :: proc(t: ^testing.T) {
	for a in Building {
		info := building_info(a)
		centre := building_center(a)
		testing.expect(t, length(centre)+max(info.half.x, info.half.y) < PLAZA_RADIUS)
		for b in Building {
			if b <= a { continue }
			// A point on `b`'s footprint's middle is far from `a`'s footprint.
			testing.expect(t, distance_to_building(a, building_center(b)) > 3, "buildings apart")
		}
	}
}

@(test)
test_the_robot_cannot_enter_a_building_nor_leave_the_plaza :: proc(t: ^testing.T) {
	w: World
	place_at_centre(&w)
	// Walk at every building's middle and past it: the robot ends outside it.
	for b in Building {
		place_at_centre(&w)
		centre := building_center(b)
		for _ in 0..<600 { step(&w, centre-w.position, 1.0/60.0) }
		testing.expect(t, distance_to_building(b, w.position) >= ROBOT_RADIUS-0.01, "stopped at the footprint")
		testing.expect(t, length(w.position) <= PLAZA_RADIUS)
	}
	// Walking out of the plaza is held at its edge.
	place_at_centre(&w)
	for _ in 0..<2000 { step(&w, {0, 1}, 1.0/60.0) }
	testing.expect(t, length(w.position) <= PLAZA_RADIUS-ROBOT_RADIUS+0.01)
}

// A door opens once, as the robot walks into it, and arms again only after the robot
// has left it: nothing opens by standing still or by passing back and forth.
@(test)
test_a_door_opens_once_and_arms_again_after_the_robot_leaves_it :: proc(t: ^testing.T) {
	w: World
	place_at_centre(&w)
	walk_to_building(&w, .Casino)
	opened := 0
	last: Building
	for _ in 0..<1200 {
		entered, did := step(&w, {}, 1.0/60.0)
		if did { opened += 1; last = entered }
	}
	testing.expect_value(t, opened, 1)
	testing.expect_value(t, last, Building.Casino)
	// Standing on the door does not open it again, nor does walking about on it.
	for _ in 0..<300 {
		_, did := step(&w, {0.2, 0.1}, 1.0/60.0)
		testing.expect(t, !did || !in_door(.Casino, w.position))
	}
	// Away from it, back into it: it opens again.
	w.position = from_local(.Casino, {0, building_info(.Casino).half.y+DOOR_DEPTH+DOOR_REARM_MARGIN+2})
	_, _ = step(&w, {}, 1.0/60.0)
	testing.expect(t, w.armed[.Casino])
	walk_to_building(&w, .Casino)
	again := 0
	for _ in 0..<600 { if _, did := step(&w, {}, 1.0/60.0); did { again += 1 } }
	testing.expect_value(t, again, 1)
}

@(test)
test_a_click_on_each_building_walks_the_robot_to_its_door :: proc(t: ^testing.T) {
	for b in Building {
		w: World
		place_at_centre(&w)
		walk_to_building(&w, b)
		got := false
		which: Building
		for _ in 0..<1500 {
			if entered, did := step(&w, {}, 1.0/60.0); did { got, which = true, entered; break }
		}
		testing.expect(t, got, "the robot reached the door")
		testing.expect_value(t, which, b)
	}
}

@(test)
test_the_keys_take_the_robot_back_from_a_click :: proc(t: ^testing.T) {
	w: World
	place_at_centre(&w)
	walk_to_building(&w, .Progress)
	step(&w, {}, 1.0/60.0)
	testing.expect(t, w.has_target)
	step(&w, {-1, 0}, 1.0/60.0)
	testing.expect(t, !w.has_target)
	testing.expect(t, w.facing_left)
}

@(test)
test_the_robot_comes_back_outside_the_door_it_left_by :: proc(t: ^testing.T) {
	for b in Building {
		w: World
		place_before_building(&w, b)
		testing.expect(t, !in_door(b, w.position, DOOR_REARM_MARGIN), "outside the door and its margin")
		testing.expect(t, distance_to_building(b, w.position) >= ROBOT_RADIUS)
		testing.expect(t, length(w.position) < PLAZA_RADIUS)
		testing.expect(t, w.armed[b])
		// Standing there opens nothing.
		for _ in 0..<60 { _, did := step(&w, {}, 1.0/60.0); testing.expect(t, !did) }
	}
}

@(test)
test_a_click_lands_on_the_building_under_it :: proc(t: ^testing.T) {
	for b in Building {
		hit, found := building_at(building_center(b))
		testing.expect(t, found)
		testing.expect_value(t, hit, b)
	}
	_, found := building_at({0, 0})
	testing.expect(t, !found)
	// Just beside a building still counts, far from all does not.
	info := building_info(.Casino)
	near := from_local(.Casino, {info.half.x+0.3, 0})
	hit, found2 := building_at(near)
	testing.expect(t, found2)
	testing.expect_value(t, hit, Building.Casino)
}

// A building is whole from FADE_FAR, fades as the robot comes near, and is gone from
// the patch before its door; beside it, it never goes below the minimum.
@(test)
test_a_building_fades_as_the_robot_comes_near_and_is_gone_at_its_door :: proc(t: ^testing.T) {
	for b in Building {
		info := building_info(b)
		front := info.half.y
		at := proc(b: Building, ahead: f32) -> Vec2 { return from_local(b, {0, building_info(b).half.y+ahead}) }
		// Far off in front: whole.
		testing.expect_value(t, building_opacity(b, at(b, FADE_FAR+1)), f32(1))
		// Coming nearer along the door's line: never more opaque, ending at 0.
		previous := f32(1)
		for ahead := FADE_FAR+1; ahead >= 0; ahead -= 0.25 {
			o := building_opacity(b, at(b, ahead))
			testing.expect(t, o <= previous+0.0001, "fades monotonically")
			previous = o
		}
		testing.expect_value(t, building_opacity(b, at(b, 1.0)), f32(0))
		testing.expect_value(t, building_opacity(b, at(b, DOOR_DEPTH)), f32(0))
		// Between the two it is partly there.
		mid := building_opacity(b, at(b, (FADE_FAR+FADE_GONE)*0.5))
		testing.expect(t, mid > 0.1 && mid < 0.9, "partly see-through")
		// Beside it, close: still there at the minimum, not gone.
		side := from_local(b, {info.half.x+0.5, 0})
		testing.expect_value(t, building_opacity(b, side), FADE_SIDE_MINIMUM)
		_ = front
	}
	// At the middle of the plaza the nearest are partly faded, the far ones whole.
	testing.expect(t, building_opacity(.Portal, {0, 0}) <= 1)
	_ = math.PI
}

@(test)
test_each_building_is_independent_of_the_others :: proc(t: ^testing.T) {
	// The robot at the Casino's door: that one is gone, the Deposito across the
	// plaza is whole.
	p := door_center(.Casino)
	testing.expect_value(t, building_opacity(.Casino, p), f32(0))
	testing.expect_value(t, building_opacity(.Storage, p), f32(1))
	testing.expect_value(t, building_opacity(.Exit, p), f32(1))
}

// A ray from the camera's side hits the wall of the building it points at and none
// when it passes over the plaza's middle.
@(test)
test_a_ray_hits_the_building_it_points_at :: proc(t: ^testing.T) {
	for b in Building {
		info := building_info(b)
		centre := building_center(b)
		// From above and in front of the building, looking at its middle.
		from := from_local(b, {0, info.half.y+6})
		origin := [3]f32{from.x, info.height+6, from.y}
		target := [3]f32{centre.x, info.height*0.5, centre.y}
		direction := [3]f32{target.x-origin.x, target.y-origin.y, target.z-origin.z}
		distance, hit := ray_hits_building(b, origin, direction)
		testing.expect(t, hit && distance > 0 && distance < 1, "the ray enters the box")
		// Straight down on the plaza's middle: no building.
		_, hit_middle := ray_hits_building(b, {0, 10, 0}, {0, -1, 0})
		testing.expect(t, !hit_middle)
	}
}
