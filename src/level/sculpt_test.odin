package level

import "core:slice"
import "core:testing"
import grid "../engine/grid"

@(private = "file")
sculpt_test_level :: proc(t: ^testing.T) -> Level {
	data, ok := create(16, 12, {kind = .Floor})
	testing.expect(t, ok)
	_ = set_tile(&data, {x = 0, y = 0}, {kind = .Void})
	return data
}

// Raise and lower move every cell under a round brush a step; a Void cell, or one off the map, stays as it is.
@(test)
test_raise_and_lower_move_the_cells_under_the_brush_a_step :: proc(t: ^testing.T) {
	data := sculpt_test_level(t)
	defer destroy(&data)
	history: Sculpt_History
	defer sculpt_history_destroy(&history)
	stroke := sculpt_begin(&history)
	sculpt_raise(&data, stroke, {x = 5, y = 5}, 1, 1)
	sculpt_raise(&data, stroke, {x = 0, y = 0}, 1, 1)
	sculpt_end(&history)
	raised := 0
	for y in 0..<data.tiles.height { for x in 0..<data.tiles.width { if height_at(&data, {x = x, y = y}) > 0 { raised += 1 } } }
	// Two discs of nine cells; the Void corner and the cells off the map have no ground.
	testing.expect_value(t, raised, 9+3)
	testing.expect_value(t, height_at(&data, {x = 0, y = 0}), 0)
	stroke = sculpt_begin(&history)
	sculpt_raise(&data, stroke, {x = 5, y = 5}, 1, -1)
	sculpt_end(&history)
	testing.expect_value(t, height_at(&data, {x = 5, y = 5}), 0)
}

// Smoothing takes the mean of each cell and its neighbours as they were; flattening brings the brush to a height.
@(test)
test_smooth_takes_the_mean_and_flatten_levels :: proc(t: ^testing.T) {
	data := sculpt_test_level(t)
	defer destroy(&data)
	_ = set_height(&data, {x = 6, y = 6}, 9)
	history: Sculpt_History
	defer sculpt_history_destroy(&history)
	stroke := sculpt_begin(&history)
	sculpt_smooth(&data, stroke, {x = 6, y = 6}, 1)
	sculpt_end(&history)
	for dy in -1..=1 { for dx in -1..=1 { testing.expect_value(t, height_at(&data, {x = 6+dx, y = 6+dy}), 1) } }
	stroke = sculpt_begin(&history)
	sculpt_flatten(&data, stroke, {x = 6, y = 6}, 2, 4)
	sculpt_end(&history)
	testing.expect_value(t, height_at(&data, {x = 6, y = 6}), 4)
	testing.expect_value(t, height_at(&data, {x = 8, y = 6}), 4)
	testing.expect_value(t, height_at(&data, {x = 9, y = 6}), 0)
}

// Painting sets the kind; on a layer under the ground it makes floors, and Void takes them away again.
@(test)
test_paint_sets_kinds_on_any_layer :: proc(t: ^testing.T) {
	data := sculpt_test_level(t)
	defer destroy(&data)
	history: Sculpt_History
	defer sculpt_history_destroy(&history)
	stroke := sculpt_begin(&history)
	sculpt_paint(&data, stroke, {x = 3, y = 3}, 0, .Wall)
	sculpt_paint(&data, stroke, {x = 8, y = 8, layer = -1}, 1, .Floor)
	sculpt_end(&history)
	tile, _ := tile_at(&data, {x = 3, y = 3})
	testing.expect_value(t, tile.kind, Tile_Kind.Wall)
	cave, _ := tile_at(&data, {x = 8, y = 9, layer = -1})
	testing.expect_value(t, cave.kind, Tile_Kind.Floor)
	testing.expect(t, has_layers(&data))
	stroke = sculpt_begin(&history)
	sculpt_paint(&data, stroke, {x = 8, y = 8, layer = -1}, 1, .Void)
	sculpt_end(&history)
	gone, _ := tile_at(&data, {x = 8, y = 9, layer = -1})
	testing.expect_value(t, gone.kind, Tile_Kind.Void)
}

// A ramp climbs from one end's height to the other's along the line between them.
@(test)
test_a_ramp_climbs_between_its_two_ends :: proc(t: ^testing.T) {
	data := sculpt_test_level(t)
	defer destroy(&data)
	_ = set_height(&data, {x = 10, y = 5}, 8)
	history: Sculpt_History
	defer sculpt_history_destroy(&history)
	stroke := sculpt_begin(&history)
	sculpt_ramp(&data, stroke, {x = 2, y = 5}, {x = 10, y = 5}, 0)
	sculpt_end(&history)
	for x in 2..=10 { testing.expect_value(t, height_at(&data, {x = x, y = 5}), i32(x-2)) }
	testing.expect_value(t, height_at(&data, {x = 6, y = 6}), 0)
}

// A piece copied and pasted elsewhere is the same there, kinds and heights; the noise is the same for the same stroke.
@(test)
test_copy_paste_and_noise :: proc(t: ^testing.T) {
	data := sculpt_test_level(t)
	defer destroy(&data)
	_ = set_height(&data, {x = 2, y = 2}, 3)
	_ = set_tile(&data, {x = 3, y = 2}, {kind = .Fence})
	clip: Sculpt_Clip
	defer delete(clip.cells)
	sculpt_copy(&data, {x = 3, y = 3}, {x = 2, y = 2}, &clip)
	testing.expect(t, clip.width == 2 && clip.height == 2)
	history: Sculpt_History
	defer sculpt_history_destroy(&history)
	stroke := sculpt_begin(&history)
	sculpt_paste(&data, stroke, &clip, {x = 10, y = 7})
	sculpt_end(&history)
	testing.expect_value(t, height_at(&data, {x = 10, y = 7}), 3)
	fence, _ := tile_at(&data, {x = 11, y = 7})
	testing.expect_value(t, fence.kind, Tile_Kind.Fence)
	other := sculpt_test_level(t)
	defer destroy(&other)
	for map_ in ([2]^Level{&data, &other}) {
		_ = set_height_table(map_, nil)
		for y in 0..<map_.tiles.height { for x in 0..<map_.tiles.width { _ = set_height(map_, {x = x, y = y}, 5) } }
		s := sculpt_begin(&history)
		sculpt_noise(map_, s, {x = 7, y = 6}, 3, 42)
		sculpt_end(&history)
	}
	testing.expect(t, slice.equal(data.heights[:], other.heights[:]), "the same stroke gives the same ground")
	changed := 0
	for height in other.heights { testing.expect(t, height >= 4 && height <= 6); if height != 5 { changed += 1 } }
	testing.expect(t, changed > 0)
}

// A stroke keeps each cell once, what it was before and what it is after: undone, the map is as before; done again, as
// after; a new stroke after an undo forgets what was undone.
@(test)
test_undo_and_redo_take_back_and_do_again_a_whole_stroke :: proc(t: ^testing.T) {
	data := sculpt_test_level(t)
	defer destroy(&data)
	before := slice.clone(data.tiles.cells[:])
	defer delete(before)
	history: Sculpt_History
	defer sculpt_history_destroy(&history)
	stroke := sculpt_begin(&history)
	sculpt_raise(&data, stroke, {x = 5, y = 5}, 2, 1)
	sculpt_raise(&data, stroke, {x = 5, y = 5}, 2, 1)
	sculpt_paint(&data, stroke, {x = 5, y = 5}, 0, .Wall)
	sculpt_end(&history)
	cells := make([dynamic]grid.Position, context.temp_allocator)
	sculpt_footprint({x = 5, y = 5}, 2, &cells)
	testing.expect_value(t, len(history.strokes[0].changes), len(cells))
	testing.expect_value(t, height_at(&data, {x = 5, y = 4}), 2)
	testing.expect(t, sculpt_undo(&data, &history))
	testing.expect_value(t, height_at(&data, {x = 5, y = 4}), 0)
	testing.expect(t, slice.equal(before, data.tiles.cells[:]))
	testing.expect(t, !sculpt_undo(&data, &history), "nothing more to undo")
	testing.expect(t, sculpt_redo(&data, &history))
	wall, _ := tile_at(&data, {x = 5, y = 5})
	testing.expect_value(t, wall.kind, Tile_Kind.Wall)
	testing.expect_value(t, height_at(&data, {x = 5, y = 4}), 2)
	testing.expect(t, sculpt_undo(&data, &history))
	stroke = sculpt_begin(&history)
	sculpt_raise(&data, stroke, {x = 1, y = 1}, 0, 1)
	sculpt_end(&history)
	testing.expect_value(t, len(history.strokes), 1)
	testing.expect(t, !sculpt_redo(&data, &history), "what was undone is forgotten")
	// A stroke that changes nothing is not kept.
	_ = sculpt_begin(&history)
	sculpt_end(&history)
	testing.expect_value(t, len(history.strokes), 1)
}

// What a map was changed in is kept per layer and put on a fresh copy of the map, to the cell; retouches of another
// size, or of a kind that is none, are refused.
@(test)
test_retouches_are_the_difference_and_put_it_back :: proc(t: ^testing.T) {
	base := sculpt_test_level(t)
	edited := sculpt_test_level(t)
	defer destroy(&base)
	defer destroy(&edited)
	history: Sculpt_History
	defer sculpt_history_destroy(&history)
	stroke := sculpt_begin(&history)
	sculpt_raise(&edited, stroke, {x = 4, y = 4}, 1, 1)
	sculpt_paint(&edited, stroke, {x = 9, y = 3}, 0, .Wall)
	sculpt_raise(&edited, stroke, {x = 9, y = 3}, 0, 1)
	sculpt_paint(&edited, stroke, {x = 12, y = 8, layer = -1}, 0, .Floor)
	sculpt_end(&history)
	edits, ok := map_edits_diff(&base, &edited)
	defer map_edits_destroy(&edits)
	testing.expect(t, ok && map_edits_any(&edits))
	testing.expect(t, len(edits.layers[layer_slot(1)].kinds) == 0, "no retouch over the ground")
	testing.expect_value(t, edits.layers[layer_slot(0)].kinds[4*16+4], MAP_EDIT_NO_KIND)
	testing.expect_value(t, edits.layers[layer_slot(0)].heights[4*16+4], i16(1))
	fresh := sculpt_test_level(t)
	defer destroy(&fresh)
	testing.expect(t, map_edits_apply(&fresh, &edits))
	testing.expect(t, slice.equal(fresh.tiles.cells[:], edited.tiles.cells[:]) && slice.equal(fresh.heights[:], edited.heights[:]))
	for slot in 0..<LAYER_COUNT {
		testing.expect(t, slice.equal(fresh.planes[slot].tiles[:], edited.planes[slot].tiles[:]))
	}
	small, _ := create(8, 8, {kind = .Floor})
	defer destroy(&small)
	testing.expect(t, !map_edits_apply(&small, &edits))
	edits.layers[layer_slot(0)].kinds[0] = 200
	testing.expect(t, !map_edits_apply(&fresh, &edits))
}

// The start, the exit and the doors stay the code's, and a building's cells the building's: a brush moves the start's
// ground but neither paints it away nor pastes a second one, and no retouch changes a marker's kind or a building.
@(test)
test_the_codes_cells_stay_the_codes :: proc(t: ^testing.T) {
	data := sculpt_test_level(t)
	defer destroy(&data)
	_ = set_tile(&data, {x = 4, y = 4}, {kind = .Player_Spawn})
	data.player_spawn, data.has_player_spawn = {x = 4, y = 4}, true
	_ = set_tile(&data, {x = 12, y = 4}, {kind = .Exit})
	_, err := place_structure(&data, .Statue, {x = 8, y = 8}, 0, false)
	testing.expect_value(t, err, Placement_Error.None)
	history: Sculpt_History
	defer sculpt_history_destroy(&history)
	stroke := sculpt_begin(&history)
	sculpt_paint(&data, stroke, {x = 4, y = 4}, 1, .Wall)
	sculpt_raise(&data, stroke, {x = 4, y = 4}, 0, 1)
	sculpt_paint(&data, stroke, {x = 8, y = 8}, 0, .Floor)
	sculpt_end(&history)
	spawn, _ := tile_at(&data, {x = 4, y = 4})
	testing.expect_value(t, spawn.kind, Tile_Kind.Player_Spawn)
	testing.expect_value(t, height_at(&data, {x = 4, y = 4}), 1)
	wall, _ := tile_at(&data, {x = 5, y = 4})
	testing.expect_value(t, wall.kind, Tile_Kind.Wall)
	_, owned := structure_index_at(&data, {x = 8, y = 8})
	testing.expect(t, owned, "the statue is still there")
	// The start copied and pasted: a floor at its height.
	clip: Sculpt_Clip
	defer delete(clip.cells)
	sculpt_copy(&data, {x = 4, y = 4}, {x = 4, y = 4}, &clip)
	stroke = sculpt_begin(&history)
	sculpt_paste(&data, stroke, &clip, {x = 2, y = 9})
	sculpt_end(&history)
	pasted, _ := tile_at(&data, {x = 2, y = 9})
	testing.expect_value(t, pasted.kind, Tile_Kind.Floor)
	testing.expect_value(t, height_at(&data, {x = 2, y = 9}), 1)
	// Retouches that would make a start, take the exit away and pave the statue: only the exit's height changes.
	edits := Map_Edits{width = data.tiles.width, height = data.tiles.height}
	defer map_edits_destroy(&edits)
	tables := map_edit_layer(&edits, grid.GROUND_LAYER)
	w := data.tiles.width
	tables.kinds[10*w+1] = u8(Tile_Kind.Player_Spawn)
	tables.kinds[4*w+12], tables.heights[4*w+12] = u8(Tile_Kind.Floor), 2
	tables.kinds[8*w+8], tables.heights[8*w+8] = u8(Tile_Kind.Floor), 6
	testing.expect(t, map_edits_apply(&data, &edits))
	start, _ := tile_at(&data, {x = 1, y = 10})
	testing.expect_value(t, start.kind, Tile_Kind.Floor)
	exit, _ := tile_at(&data, {x = 12, y = 4})
	testing.expect_value(t, exit.kind, Tile_Kind.Exit)
	testing.expect_value(t, height_at(&data, {x = 12, y = 4}), 2)
	statue, _ := tile_at(&data, {x = 8, y = 8})
	testing.expect_value(t, statue.kind, Tile_Kind.Wall)
	testing.expect_value(t, height_at(&data, {x = 8, y = 8}), 0)
}

// A walker reaches a cave's floor through its mouth, and a cliff of two steps stops it.
@(test)
test_a_walker_reaches_across_the_layers_and_not_up_a_cliff :: proc(t: ^testing.T) {
	data := sculpt_test_level(t)
	defer destroy(&data)
	for y in 4..=8 { for x in 6..=10 { _ = set_height(&data, {x = x, y = y}, 14) } }
	for x in 6..=9 { _ = set_tile(&data, {x = x, y = 6, layer = -1}, {kind = .Floor}) }
	_ = set_height(&data, {x = 2, y = 10}, 2)
	seen := layer_reach(&data, {x = 3, y = 6})
	defer delete(seen)
	testing.expect(t, seen[layer_reach_index(&data, {x = 9, y = 6, layer = -1})], "into the cave")
	testing.expect(t, !seen[layer_reach_index(&data, {x = 8, y = 6})], "not onto the hill")
	testing.expect(t, !seen[layer_reach_index(&data, {x = 2, y = 10})], "not up the cliff")
	testing.expect(t, seen[layer_reach_index(&data, {x = 13, y = 2})])
}
