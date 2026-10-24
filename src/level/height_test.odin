package level

import "core:testing"

@(test)
test_a_map_has_no_heights_until_one_is_set :: proc(t: ^testing.T) {
	data, ok := create(4, 3, Tile{kind = .Floor})
	testing.expect(t, ok)
	defer destroy(&data)
	testing.expect(t, !has_heights(&data))
	testing.expect_value(t, height_at(&data, {2, 1}), i32(0))
	// Setting 0 on a flat map makes no table and no new geometry.
	revision := data.geometry_revision
	testing.expect(t, set_height(&data, {1, 1}, 0))
	testing.expect(t, !has_heights(&data) && data.geometry_revision == revision)
	testing.expect(t, set_height(&data, {2, 1}, 5))
	testing.expect(t, has_heights(&data))
	testing.expect_value(t, height_at(&data, {2, 1}), i32(5))
	testing.expect_value(t, height_at(&data, {0, 0}), i32(0))
	testing.expect(t, data.geometry_revision != revision)
	// The same height again changes nothing; a new one invalidates the geometry.
	revision = data.geometry_revision
	testing.expect(t, set_height(&data, {2, 1}, 5) && data.geometry_revision == revision)
	testing.expect(t, set_height(&data, {2, 1}, 6) && data.geometry_revision != revision)
}

@(test)
test_heights_are_bounded_and_off_the_map_is_flat :: proc(t: ^testing.T) {
	data, _ := create(3, 3, Tile{kind = .Floor})
	defer destroy(&data)
	testing.expect(t, !set_height(&data, {3, 0}, 2) && !set_height(&data, {-1, 0}, 2))
	testing.expect(t, set_height(&data, {1, 1}, 1000))
	testing.expect_value(t, height_at(&data, {1, 1}), i32(MAX_CELL_HEIGHT))
	testing.expect(t, set_height(&data, {1, 1}, -4))
	testing.expect_value(t, height_at(&data, {1, 1}), i32(0))
	testing.expect_value(t, height_at(&data, {9, 9}), i32(0))
	testing.expect_value(t, height_at(nil, {0, 0}), i32(0))
	testing.expect(t, !set_height(nil, {0, 0}, 1))
}

@(test)
test_height_rows_read_digits_and_letters :: proc(t: ^testing.T) {
	data, _ := create(4, 2, Tile{kind = .Floor})
	defer destroy(&data)
	rows := [?]string{"0129", " ae0", }
	testing.expect(t, apply_height_rows(&data, rows[:]))
	testing.expect_value(t, height_at(&data, {0, 0}), i32(0))
	testing.expect_value(t, height_at(&data, {2, 0}), i32(2))
	testing.expect_value(t, height_at(&data, {3, 0}), i32(9))
	testing.expect_value(t, height_at(&data, {1, 1}), i32(10))
	testing.expect_value(t, height_at(&data, {2, 1}), i32(14))
	// Rows of the wrong size or with another symbol are refused.
	short := [?]string{"012", "000"}
	testing.expect(t, !apply_height_rows(&data, short[:]))
	bad := [?]string{"01x9", "0000"}
	testing.expect(t, !apply_height_rows(&data, bad[:]))
	one := [?]string{"0000"}
	testing.expect(t, !apply_height_rows(&data, one[:]))
}

@(test)
test_the_tile_kinds_are_read_and_written_in_one_go :: proc(t: ^testing.T) {
	data, _ := create(5, 4, Tile{kind = .Floor})
	defer destroy(&data)
	_ = set_tile(&data, {1, 1}, {.Wall})
	_ = set_tile(&data, {3, 2}, {.Void})
	kinds: [20]u8
	testing.expect(t, tile_kinds(&data, kinds[:]))
	testing.expect_value(t, kinds[1*5+1], u8(Tile_Kind.Wall))
	testing.expect_value(t, kinds[2*5+3], u8(Tile_Kind.Void))
	// Wiping the map and putting it back is the same map, and each is one change of the geometry.
	before := data.geometry_revision
	blank: [20]u8
	testing.expect(t, set_tile_kinds(&data, blank[:]))
	testing.expect_value(t, data.geometry_revision, before+1)
	tile, _ := tile_at(&data, {1, 1})
	testing.expect_value(t, tile.kind, Tile_Kind.Void)
	testing.expect(t, set_tile_kinds(&data, kinds[:]))
	tile, _ = tile_at(&data, {1, 1})
	testing.expect_value(t, tile.kind, Tile_Kind.Wall)
	// The same kinds again change nothing; a wrong length or kind is refused.
	revision := data.geometry_revision
	testing.expect(t, set_tile_kinds(&data, kinds[:]) && data.geometry_revision == revision)
	testing.expect(t, !set_tile_kinds(&data, kinds[:5]))
	bad := kinds
	bad[0] = 250
	testing.expect(t, !set_tile_kinds(&data, bad[:]))
	testing.expect(t, !tile_kinds(&data, kinds[:5]))
}
