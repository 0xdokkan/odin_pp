package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

// A bridge (layer +1, 12 steps) along x = 3, y 0..8, over a flat road; and a hill of 14 steps (x 8..10) with a
// tunnel on layer -1 along y = 4. A 14x9 map of floor.
@(private = "file")
view_map :: proc() -> level.Level {
	data, _ := level.create(14, 9, level.Tile{kind = .Floor})
	for y in 0..<9 {
		bridge := grid.Position{x = 3, y = y, layer = 1}
		level.set_tile(&data, bridge, {kind = .Floor})
		level.set_height(&data, bridge, level.LAYER_SPACING)
		for x in 8..=10 { level.set_height(&data, {x = x, y = y}, 14) }
	}
	for x in 8..=10 { level.set_tile(&data, {x = x, y = 4, layer = -1}, {kind = .Floor}) }
	return data
}

@(private = "file")
viewer_at :: proc(cell: grid.Position) -> Layer_Viewer {
	return {point = {f32(cell.x)+0.5, f32(cell.y)+0.5}, cell = cell}
}

// What stands over the robot's head on a layer above his opens as he nears it: next to him almost gone, whole from
// six cells on; nothing under him or on his own layer fades, nor what is not over his head.
@(test)
test_what_covers_the_robot_fades_as_he_nears_it :: proc(t: ^testing.T) {
	data := view_map()
	defer level.destroy(&data)
	m := level.layer_map(&data)
	road := viewer_at({x = 3, y = 4})
	testing.expect(t, abs(layer_cover_opacity(&m, road, {x = 3, y = 4, layer = 1})-LAYER_FADE_MINIMUM) < 0.0001)
	nearer := layer_cover_opacity(&m, road, {x = 3, y = 6, layer = 1})
	farther := layer_cover_opacity(&m, road, {x = 3, y = 8, layer = 1})
	testing.expect(t, LAYER_FADE_MINIMUM < nearer && nearer < farther && farther < 1)
	far_road := viewer_at({x = 3, y = 0})
	testing.expect_value(t, layer_cover_opacity(&m, far_road, {x = 3, y = 8, layer = 1}), f32(1))
	// From the bridge the road under it stays whole, and so does the bridge itself.
	deck := viewer_at({x = 3, y = 4, layer = 1})
	testing.expect_value(t, layer_cover_opacity(&m, deck, {x = 3, y = 4}), f32(1))
	testing.expect_value(t, layer_cover_opacity(&m, deck, {x = 3, y = 5, layer = 1}), f32(1))
	// In the tunnel the hill over it fades; the flat ground outside its mouth is not over his head.
	tunnel := viewer_at({x = 8, y = 4, layer = -1})
	testing.expect(t, layer_cover_opacity(&m, tunnel, {x = 9, y = 4}) < 1)
	testing.expect_value(t, layer_cover_opacity(&m, tunnel, {x = 7, y = 4}), f32(1))
}

// Under a vault everything off the robot's layer is darker; on the bridge what is under him a little; on the road
// nothing.
@(test)
test_the_layers_off_the_robot_are_darker_under_a_vault_and_under_a_bridge :: proc(t: ^testing.T) {
	data := view_map()
	defer level.destroy(&data)
	m := level.layer_map(&data)
	tunnel := viewer_at({x = 9, y = 4, layer = -1})
	testing.expect(t, layer_viewer_in_vault(&m, tunnel))
	testing.expect_value(t, layer_cell_dim(&m, tunnel, {x = 1, y = 1}), LAYER_OUTSIDE_DIM)
	testing.expect_value(t, layer_cell_dim(&m, tunnel, {x = 8, y = 4, layer = -1}), f32(0))
	deck := viewer_at({x = 3, y = 4, layer = 1})
	testing.expect(t, !layer_viewer_in_vault(&m, deck))
	testing.expect_value(t, layer_cell_dim(&m, deck, {x = 5, y = 4}), LAYER_BELOW_DIM)
	testing.expect_value(t, layer_cell_dim(&m, deck, {x = 3, y = 5, layer = 1}), f32(0))
	road := viewer_at({x = 1, y = 4})
	testing.expect_value(t, layer_cell_dim(&m, road, {x = 3, y = 4, layer = 1}), f32(0))
	testing.expect_value(t, layer_cell_dim(&m, road, {x = 5, y = 4}), f32(0))
}

// A figure on the road under the deck is hidden from a camera above, unless the deck over it is faded; a figure
// on the deck, or in the open, is seen. A figure in the tunnel is hidden by the hill.
@(test)
test_a_figure_under_the_deck_or_in_the_rock_is_hidden :: proc(t: ^testing.T) {
	data := view_map()
	defer level.destroy(&data)
	m := level.layer_map(&data)
	step := HEIGHT_STEP_DRAWN
	eye := [3]f32{3.5, 10, 14.5}
	under := grid.Position{x = 3, y = 2}
	chest := [3]f32{3.5, 0.5, 2.5}
	far_viewer := viewer_at({x = 12, y = 0})
	testing.expect(t, layer_figure_hidden(&m, far_viewer, eye, chest, under))
	// The robot under the bridge next to the figure: the deck over both is faded, the figure seen.
	near_viewer := viewer_at({x = 3, y = 3})
	testing.expect(t, !layer_figure_hidden(&m, near_viewer, eye, chest, under))
	on_deck := grid.Position{x = 3, y = 2, layer = 1}
	testing.expect(t, !layer_figure_hidden(&m, far_viewer, eye, {3.5, 12*step+0.5, 2.5}, on_deck))
	testing.expect(t, !layer_figure_hidden(&m, far_viewer, eye, {5.5, 0.5, 2.5}, {x = 5, y = 2}))
	inside := grid.Position{x = 9, y = 4, layer = -1}
	testing.expect(t, layer_figure_hidden(&m, far_viewer, {9.5, 10, 14.5}, {9.5, 0.5, 4.5}, inside))
}
