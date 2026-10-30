package render

import "core:math"
import "core:testing"
import game "../game"
import level "../level"

// A small cave under a massif (expedition/cave.odin's shape): the ground at 14 over x 4..11, y 4..11; on the layer under it,
// at 0, a tunnel along y 7 from x 4 into a room of 3 by 3 (x 7..9, y 6..8); its mouth on the open ground at (3, 7).
@(private = "file")
layers_test_level :: proc(t: ^testing.T) -> level.Level {
	data, ok := level.create(16, 16, {.Floor})
	testing.expect(t, ok)
	for y in 4..=11 { for x in 4..=11 { _ = level.set_height(&data, {x = x, y = y}, 14) } }
	for x in 4..=9 { _ = level.set_tile(&data, {x = x, y = 7, layer = -1}, {kind = .Floor}) }
	for y in 6..=8 { for x in 7..=9 { _ = level.set_tile(&data, {x = x, y = y, layer = -1}, {kind = .Floor}) } }
	error, _ := level.check_layers(&data)
	testing.expect_value(t, error, level.Layer_Error.None)
	return data
}

// The rooms under the ground: a floor quad for every floor, walls of rock where the next cell is rock, none at the mouth,
// and the cut of the rock at the rooms' top over the rock round them.
@(test)
test_the_rooms_under_the_ground_have_floors_walls_an_open_mouth_and_the_cut_of_the_rock :: proc(t: ^testing.T) {
	data := layers_test_level(t)
	defer level.destroy(&data)
	cache: Expedition_Under_Cache
	defer destroy_expedition_under(&cache)
	prepare_expedition_under(&cache, &data)
	step := game.HEIGHT_STEP_DRAWN
	floors, cuts, mouth_walls, walls := 0, 0, 0, 0
	for chunk in cache.chunks {
		for v in chunk.vertices {
			switch {
			case v.normal.y < .5:
				walls += 1
				// The face between the mouth (3, 7) and the tunnel's first cell (4, 7).
				if math.abs(v.position.x-4) < .1 && v.position.z > 7.01 && v.position.z < 7.99 { mouth_walls += 1 }
				testing.expect(t, v.position.y >= -.001 && v.position.y <= f32(level.LAYER_CLEARANCE)*step+.001)
			case v.color.r == 0:
				cuts += 1
				testing.expect(t, math.abs(v.position.y-f32(level.LAYER_CLEARANCE)*step) < .001)
			case:
				floors += 1
				testing.expect(t, math.abs(v.position.y) < .01)
			}
		}
	}
	testing.expect_value(t, floors, (6+6)*6)
	testing.expect(t, walls > 0 && cuts > 0)
	testing.expect_value(t, mouth_walls, 0)
	// The relief's side over the mouth opens down to the room's top, and nowhere else.
	m := level.layer_map(&data)
	bottom, open := terrain_opening(&m, 4, 7, {3, 7})
	testing.expect(t, open && bottom == f32(level.LAYER_CLEARANCE))
	_, beside := terrain_opening(&m, 4, 6, {3, 6})
	testing.expect(t, !beside)
	_, inward := terrain_opening(&m, 4, 7, {4, 6})
	testing.expect(t, !inward)
}

// A sleeping foe in a cave stands on the cave's floor, not on the rock over it (set_expedition_board_actors).
@(test)
test_a_figure_added_to_the_board_stands_on_its_own_layer :: proc(t: ^testing.T) {
	data := layers_test_level(t)
	defer level.destroy(&data)
	set_board_level(&data)
	defer set_board_level(nil)
	set_board_actors(nil)
	foe := game.Entity_Ref{kind = .System, id = 5}
	add_board_actor(foe, {x = 8, y = 7, layer = -1})
	testing.expect(t, entity_point_ground(foe, {8, 7}) < .01)
	testing.expect(t, math.abs(point_ground({8, 7})-14*game.HEIGHT_STEP_DRAWN) < .01)
	set_board_actors(nil)
}
