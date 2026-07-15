package level

import "core:testing"
import grid "../grid"

@(test)
test_ascii_map_parses_tiles_and_spawn :: proc(t: ^testing.T) {
	rows := [?]string{
		"#####",
		"#@..#",
		"#.+>#",
		"#####",
	}

	level, err, _ := from_ascii(rows[:])
	testing.expect_value(t, err, Parse_Error.None)
	defer destroy(&level)

	testing.expect_value(t, level.tiles.width, 5)
	testing.expect_value(t, level.tiles.height, 4)
	testing.expect_value(t, level.player_spawn, grid.Position{x = 1, y = 1})

	door, found := tile_at(&level, {x = 2, y = 2})
	testing.expect(t, found)
	testing.expect_value(t, door.kind, Tile_Kind.Door)
	testing.expect(t, is_walkable(door.kind))
}

@(test)
test_ascii_map_rejects_invalid_shapes_and_symbols :: proc(t: ^testing.T) {
	uneven := [?]string{"####", "#@#"}
	_, shape_err, shape_at := from_ascii(uneven[:])
	testing.expect_value(t, shape_err, Parse_Error.Inconsistent_Row_Width)
	testing.expect_value(t, shape_at, grid.Position{x = 3, y = 1})

	unknown := [?]string{"###", "#@!", "###"}
	_, symbol_err, symbol_at := from_ascii(unknown[:])
	testing.expect_value(t, symbol_err, Parse_Error.Unknown_Symbol)
	testing.expect_value(t, symbol_at, grid.Position{x = 2, y = 1})
}

@(test)
test_ascii_map_requires_one_spawn :: proc(t: ^testing.T) {
	missing := [?]string{"###", "#.#", "###"}
	_, missing_err, _ := from_ascii(missing[:])
	testing.expect_value(t, missing_err, Parse_Error.Missing_Player_Spawn)

	multiple := [?]string{"#####", "#@.@#", "#####"}
	_, multiple_err, multiple_at := from_ascii(multiple[:])
	testing.expect_value(t, multiple_err, Parse_Error.Multiple_Player_Spawns)
	testing.expect_value(t, multiple_at, grid.Position{x = 3, y = 1})
}

@(test)
test_generated_room_has_solid_border_and_walkable_spawn :: proc(t: ^testing.T) {
	level, ok := generate_room(12, 8)
	testing.expect(t, ok)
	defer destroy(&level)

	for y in 0..<level.tiles.height {
		for x in 0..<level.tiles.width {
			is_border := x == 0 || y == 0 || x == level.tiles.width-1 || y == level.tiles.height-1
			if !is_border {
				continue
			}
			tile, found := tile_at(&level, {x = x, y = y})
			testing.expect(t, found)
			testing.expect_value(t, tile.kind, Tile_Kind.Wall)
		}
	}

	spawn, found := tile_at(&level, level.player_spawn)
	testing.expect(t, found)
	testing.expect(t, is_walkable(spawn.kind))
}
