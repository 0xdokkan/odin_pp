package game

import "core:testing"
import level "../level"

@(private = "file")
open_world :: proc() -> level.Level {
	data, _ := level.create(60, 60, level.Tile{kind = .Floor})
	for i in 0..<60 {
		_ = level.set_tile(&data, {x = i, y = 0}, {kind = .Wall}); _ = level.set_tile(&data, {x = i, y = 59}, {kind = .Wall})
		_ = level.set_tile(&data, {x = 0, y = i}, {kind = .Wall}); _ = level.set_tile(&data, {x = 59, y = i}, {kind = .Wall})
	}
	_ = level.set_tile(&data, {x = 1, y = 1}, {kind = .Player_Spawn})
	data.player_spawn, data.has_player_spawn = {x = 1, y = 1}, true
	return data
}

// A hut at (20, 20): 5 by 4, walls on the top, left and right, the door at (22, 23), floor inside.

// The envelope is whole from five cells away, fades as the robot comes near along the way to
// the door, is gone from a cell before the door, and comes back as the robot goes away.
@(test)
test_a_building_fades_as_the_robot_walks_to_its_door_and_returns_as_it_leaves :: proc(t: ^testing.T) {
	data := open_world()
	defer level.destroy(&data)
	index, err := level.place_structure(&data, .Hut, {x = 20, y = 20}, 0, false)
	testing.expect_value(t, err, level.Placement_Error.None)
	// Straight down onto the door at x = 22.5, from far below to the door cell.
	far := structure_visibility(&data, index, {22.5, 40.5})
	testing.expect_value(t, far.stage, Structure_Stage.Far)
	testing.expect_value(t, far.opacity, f32(1))
	testing.expect(t, far.roof && !far.inside)
	previous := f32(1)
	reached_zero := false
	for y := f32(40.5); y >= 23.5; y -= 0.1 {
		view := structure_visibility(&data, index, {22.5, y})
		testing.expect(t, view.opacity <= previous+0.0001, "never more solid on the way in")
		previous = view.opacity
		if view.opacity == 0 { reached_zero = true }
	}
	testing.expect(t, reached_zero, "gone before the door")
	// On the threshold, and on the door itself: the envelope is gone.
	front := structure_visibility(&data, index, {22.5, 24.5})
	testing.expect_value(t, front.stage, Structure_Stage.Threshold)
	testing.expect_value(t, front.opacity, f32(0))
	door := structure_visibility(&data, index, {22.5, 23.5})
	testing.expect_value(t, door.stage, Structure_Stage.Threshold)
	testing.expect_value(t, door.opacity, f32(0))
	// Between whole and gone it is partly there.
	middle := structure_visibility(&data, index, {22.5, 26.5})
	testing.expect(t, middle.opacity > 0.05 && middle.opacity < 0.95, "partly see-through")
	testing.expect_value(t, middle.stage, Structure_Stage.Approaching)
	// Leaving: the same way back, never less solid.
	previous = 0
	for y := f32(23.5); y <= 40.5; y += 0.1 {
		view := structure_visibility(&data, index, {22.5, y})
		testing.expect(t, view.opacity >= previous-0.0001, "never fainter on the way out")
		previous = view.opacity
	}
	testing.expect_value(t, previous, f32(1))
}

// Beside a wall with no door the building is never fainter than the minimum; it is gone only at a door.
@(test)
test_beside_a_wall_without_a_door_the_building_never_goes_below_the_minimum :: proc(t: ^testing.T) {
	data := open_world()
	defer level.destroy(&data)
	index, _ := level.place_structure(&data, .Hut, {x = 20, y = 20}, 0, false)
	// Close to the left wall, and close behind the building (its door faces down).
	for position in ([4][2]f32{{19.1, 21.5}, {19.5, 20.5}, {22.5, 19.2}, {26.5, 21.5}}) {
		view := structure_visibility(&data, index, position)
		testing.expect(t, view.opacity >= STRUCTURE_FADE_MINIMUM-0.0001, "never below the minimum beside a wall")
		testing.expect(t, view.opacity < 1, "but fainter than whole")
		testing.expect_value(t, view.stage, Structure_Stage.Approaching)
	}
	// Right up against the wall: exactly the minimum.
	touching := structure_visibility(&data, index, {19.0, 21.5})
	testing.expect_value(t, touching.opacity, STRUCTURE_FADE_MINIMUM)
}

// Inside, the walls are whole again, the roof is hidden and the outside is darker; stepping
// out brings the threshold back.
@(test)
test_inside_the_walls_are_whole_the_roof_hidden_and_the_outside_darkened :: proc(t: ^testing.T) {
	data := open_world()
	defer level.destroy(&data)
	index, _ := level.place_structure(&data, .Hut, {x = 20, y = 20}, 0, false)
	for position in ([3][2]f32{{22.5, 21.5}, {21.2, 22.8}, {23.7, 21.1}}) {
		view := structure_visibility(&data, index, position)
		testing.expect_value(t, view.stage, Structure_Stage.Inside)
		testing.expect_value(t, view.opacity, f32(1))
		testing.expect(t, !view.roof, "the roof is hidden inside")
		testing.expect(t, view.inside)
	}
	out := structure_visibility(&data, index, {22.5, 24.5})
	testing.expect_value(t, out.stage, Structure_Stage.Threshold)
	testing.expect(t, !out.inside && out.roof)
}

// Each building has its own opacity: the robot at one's door has the other whole.
@(test)
test_two_buildings_fade_independently :: proc(t: ^testing.T) {
	data := open_world()
	defer level.destroy(&data)
	first, e1 := level.place_structure(&data, .Hut, {x = 10, y = 10}, 0, false)
	second, e2 := level.place_structure(&data, .Cottage, {x = 40, y = 40}, 0, false)
	testing.expect(t, e1 == .None && e2 == .None)
	// At the first hut's door (12.5, 14.5).
	at := [2]f32{12.5, 14.5}
	testing.expect_value(t, structure_visibility(&data, first, at).opacity, f32(0))
	testing.expect_value(t, structure_visibility(&data, second, at).opacity, f32(1))
	// An index that is not a structure is whole.
	testing.expect_value(t, structure_visibility(&data, 9, at).opacity, f32(1))
	testing.expect_value(t, structure_visibility(nil, 0, at).opacity, f32(1))
}

// The temple's colonnade is part of the building: close to its fence the building is fainter,
// and the gate is the way in.
@(test)
test_a_temple_fades_like_any_building_and_its_gate_is_the_way_in :: proc(t: ^testing.T) {
	data := open_world()
	defer level.destroy(&data)
	index, err := level.place_structure(&data, .Temple, {x = 20, y = 20}, 0, false)
	testing.expect_value(t, err, level.Placement_Error.None)
	// The gate is at (23, 26); the courtyard is inside.
	testing.expect_value(t, structure_visibility(&data, index, {23.5, 28.0}).stage, Structure_Stage.Threshold)
	testing.expect_value(t, structure_visibility(&data, index, {21.5, 22.5}).stage, Structure_Stage.Inside)
	testing.expect_value(t, structure_visibility(&data, index, {23.5, 40.5}).stage, Structure_Stage.Far)
}
