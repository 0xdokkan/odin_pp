package render

import "core:testing"
import game "../game"
import grid "../engine/grid"
import level "../level"

// The ground under a point is the sculpted surface (level/surface.odin): exactly a cell's height in its middle, a
// ramp between cells a step apart, and an edge where they are a cliff apart. (Before Fase 1 of
// docs/piano-profondita.md it blended the four cells round the point, cliffs too.)
@(test)
test_the_ground_under_a_point_follows_the_sculpted_surface :: proc(t: ^testing.T) {
	data, _ := level.create(6, 6, level.Tile{kind = .Floor})
	defer level.destroy(&data)
	defer set_board_level(nil)
	set_board_level(&data)
	// A flat board is at 0 everywhere.
	testing.expect_value(t, point_ground({2.5, 3.2}), f32(0))
	level.set_height(&data, {x = 2, y = 2}, 4)
	// The view takes the table again when the geometry has changed.
	set_board_level(&data)
	step := f32(0.12)
	// A cliff of four steps all round: on the cell's own coordinates and up to its edge, its height; past the edge,
	// the flat ground.
	testing.expect(t, abs(point_ground({2, 2})-4*step) < 0.0001)
	testing.expect(t, abs(point_ground({1.51, 2})-4*step) < 0.0001)
	testing.expect(t, abs(point_ground({1.49, 2})) < 0.0001)
	testing.expect_value(t, point_ground({4, 4}), f32(0))
	testing.expect(t, abs(cell_ground({x = 2, y = 2})-4*step) < 0.0001)
	testing.expect_value(t, cell_ground({x = 0, y = 0}), f32(0))
	// A stair along x, a step a column: a ramp. Halfway between two middles it is halfway up, and it never jumps.
	for y in 0..<6 { for x in 0..<6 { level.set_height(&data, {x = x, y = y}, i32(x)) } }
	set_board_level(&data)
	testing.expect(t, abs(point_ground({3, 2})-3*step) < 0.0001)
	testing.expect(t, abs(point_ground({2.5, 2})-2.5*step) < 0.0001)
	last := point_ground({0, 2})
	for i in 1..=50 {
		here := point_ground({f32(i)*0.1, 2})
		testing.expect(t, here >= last-0.0001 && here-last < step*0.25)
		last = here
	}
}

@(test)
test_the_pointer_picks_the_cell_whose_floor_it_reaches_first :: proc(t: ^testing.T) {
	data, _ := level.create(10, 10, level.Tile{kind = .Floor})
	defer level.destroy(&data)
	defer set_board_level(nil)
	set_board_level(&data)
	// A steep ray going north (towards smaller z) over cell (4,4).
	origin := [3]f32{4.5, 3, 9.5}
	direction := [3]f32{0, -1.5, -3}
	// On a flat board the ray reaches the plane at z=3.5: the cell (4,3).
	cell, ok := pick_ground_cell(origin, direction)
	testing.expect(t, ok)
	testing.expect_value(t, cell, grid.Position{x = 4, y = 3})
	// With a plateau of six steps (0.72) at (4,4) the ray meets its top at z=4.9
	// first: the plateau's cell is the one under the pointer, not the ground behind it.
	level.set_height(&data, {x = 4, y = 4}, 6)
	set_board_level(&data)
	cell, ok = pick_ground_cell(origin, direction)
	testing.expect(t, ok)
	testing.expect_value(t, cell, grid.Position{x = 4, y = 4})
	// A ray going up, or flat, picks nothing.
	_, ok = pick_ground_cell(origin, {0, 1, -1})
	testing.expect(t, !ok)
	_, ok = pick_ground_cell(origin, {0, 0, -1})
	testing.expect(t, !ok)
	// A ray straight down over a cell picks it, raised or not.
	cell, ok = pick_ground_cell({7.5, 5, 7.5}, {0, -1, 0})
	testing.expect(t, ok)
	testing.expect_value(t, cell, grid.Position{x = 7, y = 7})
	cell, ok = pick_ground_cell({4.5, 5, 4.5}, {0, -1, 0})
	testing.expect(t, ok)
	testing.expect_value(t, cell, grid.Position{x = 4, y = 4})
}

// A hill between the camera and an actor hides it; the actor beside the hill, in front of it or on its top is seen.
@(test)
test_an_actor_behind_a_hill_is_hidden_from_the_camera :: proc(t: ^testing.T) {
	data, _ := level.create(20, 30, level.Tile{kind = .Floor})
	defer level.destroy(&data)
	defer set_board_level(nil)
	renderer := new(Renderer)
	defer free(renderer)
	// The camera south of the board looking north, high up.
	renderer.tactical.camera.position = {10, 12, 40}
	// A flat board hides nobody.
	set_board_level(&data)
	testing.expect(t, !terrain_hides_actor(renderer, {10, 5}))
	// A wall of cells 60 steps (7 cells) high across the middle: the actor behind it is hidden, the one in front is not.
	for x in 0..<20 { for y in 14..<17 { level.set_height(&data, {x = x, y = y}, 60) } }
	set_board_level(&data)
	testing.expect(t, terrain_hides_actor(renderer, {10, 5}), "behind the wall")
	testing.expect(t, !terrain_hides_actor(renderer, {10, 25}), "in front of the wall")
	// On the wall's top the actor is seen, whether it is at the near or the far edge.
	testing.expect(t, !terrain_hides_actor(renderer, {10, 15}), "on the wall's top")
	testing.expect(t, !terrain_hides_actor(renderer, {10, 14}), "at the wall's near edge")
	// A low step (two steps) in the way does not hide anyone standing far behind it.
	for x in 0..<20 { for y in 14..<17 { level.set_height(&data, {x = x, y = y}, 2) } }
	set_board_level(&data)
	testing.expect(t, !terrain_hides_actor(renderer, {10, 5}), "behind a low step")
}

// A figure stands on the ground under it, whether it steps (a card's slide) or the robot walks free.
@(test)
test_a_figure_stands_on_the_ground_whether_it_steps_or_walks_free :: proc(t: ^testing.T) {
	data, _ := level.create(8, 8, level.Tile{kind = .Floor})
	defer level.destroy(&data)
	defer set_board_level(nil)
	level.set_height(&data, {x = 3, y = 3}, 50)
	set_board_level(&data)
	renderer := new(Renderer)
	defer free(renderer)
	step := f32(0.12)
	_, stepping := living_card_slide_position(renderer, game.PLAYER_ENTITY, .Player, {3, 3})
	testing.expect(t, abs(stepping-50*step) < 0.0001, "a step lifts the figure to the ground")
	renderer.tactical.expedition_free = true
	_, walking := expedition_player_position(renderer, .Player, {3, 3})
	testing.expect(t, abs(walking-50*step) < 0.0001, "free walking too")
	_, flat := expedition_player_position(renderer, .Player, {6, 6})
	testing.expect_value(t, flat, f32(0))
}

// With layers the pointer goes through the columns: straight down over a bridge it picks the deck and beside it
// the road; a ray low under the deck reaches the road beyond it. A figure on the bridge stands on the deck and
// one under it on the road, in the same column (Fase 3 of docs/piano-profondita.md).
@(test)
test_the_pointer_and_the_figures_find_their_layer :: proc(t: ^testing.T) {
	data, _ := level.create(10, 10, level.Tile{kind = .Floor})
	defer level.destroy(&data)
	defer set_board_level(nil)
	for y in 0..<10 {
		bridge := grid.Position{x = 5, y = y, layer = 1}
		level.set_tile(&data, bridge, {kind = .Floor})
		level.set_height(&data, bridge, level.LAYER_SPACING)
	}
	set_board_level(&data)
	step := f32(0.12)
	cell, ok := pick_ground_cell({5.5, 5, 4.5}, {0, -1, 0})
	testing.expect(t, ok)
	testing.expect_value(t, cell, grid.Position{x = 5, y = 4, layer = 1})
	cell, ok = pick_ground_cell({3.5, 5, 4.5}, {0, -1, 0})
	testing.expect(t, ok)
	testing.expect_value(t, cell, grid.Position{x = 3, y = 4})
	cell, ok = pick_ground_cell({2, 0.6, 4.5}, {1, -0.08, 0})
	testing.expect(t, ok)
	testing.expect_value(t, cell, grid.Position{x = 9, y = 4})
	// The deck is drawn from its underside up, two steps thick.
	testing.expect(t, abs(cell_ground({x = 5, y = 4, layer = 1})-12*step) < 0.0001)
	testing.expect(t, abs(cell_base({x = 5, y = 4, layer = 1})-10*step) < 0.0001)
	set_board_actors(nil)
	defer clear(&board_actors)
	on_bridge, on_road := game.enemy_entity(1), game.enemy_entity(2)
	append(&board_actors, Board_Actor{on_bridge, {x = 5, y = 4, layer = 1}}, Board_Actor{on_road, {x = 5, y = 4}})
	testing.expect(t, abs(entity_point_ground(on_bridge, {5, 4})-12*step) < 0.0001)
	testing.expect_value(t, entity_point_ground(on_road, {5, 4}), f32(0))
}
