package level

import grid "../grid"

Tile_Kind :: enum u8 {
	Void,
	Floor,
	Wall,
	Door,
	Player_Spawn,
	Exit,
}

Tile :: struct {
	kind: Tile_Kind,
}

Level :: struct {
	tiles:            grid.Grid(Tile),
	player_spawn:     grid.Position,
	has_player_spawn: bool,
}

Parse_Error :: enum {
	None,
	Empty_Map,
	Inconsistent_Row_Width,
	Unknown_Symbol,
	Missing_Player_Spawn,
	Multiple_Player_Spawns,
}

create :: proc(width, height: int, initial_tile := Tile{kind = .Void}) -> (result: Level, ok: bool) {
	tiles, valid := grid.create(Tile, width, height, initial_tile)
	if !valid {
		return {}, false
	}
	result.tiles = tiles
	return result, true
}

destroy :: proc(level: ^Level) {
	if level == nil {
		return
	}
	grid.destroy(&level.tiles)
	level^ = {}
}

tile_at :: proc(level: ^Level, position: grid.Position) -> (Tile, bool) {
	if level == nil {
		return {}, false
	}
	return grid.get(&level.tiles, position)
}

set_tile :: proc(level: ^Level, position: grid.Position, tile: Tile) -> bool {
	if level == nil {
		return false
	}
	return grid.set(&level.tiles, position, tile)
}

is_walkable :: proc(kind: Tile_Kind) -> bool {
	switch kind {
	case .Floor, .Door, .Player_Spawn, .Exit:
		return true
	case .Void, .Wall:
		return false
	}
	return false
}

tile_from_symbol :: proc(symbol: u8) -> (Tile, bool) {
	switch symbol {
	case ' ':
		return Tile{kind = .Void}, true
	case '.':
		return Tile{kind = .Floor}, true
	case '#':
		return Tile{kind = .Wall}, true
	case '+':
		return Tile{kind = .Door}, true
	case '@':
		return Tile{kind = .Player_Spawn}, true
	case '>':
		return Tile{kind = .Exit}, true
	}
	return {}, false
}

tile_symbol :: proc(kind: Tile_Kind) -> string {
	switch kind {
	case .Void:
		return " "
	case .Floor:
		return "."
	case .Wall:
		return "#"
	case .Door:
		return "+"
	case .Player_Spawn:
		return "@"
	case .Exit:
		return ">"
	}
	return "?"
}

parse_error_text :: proc(err: Parse_Error) -> string {
	switch err {
	case .None:
		return "no error"
	case .Empty_Map:
		return "the map is empty"
	case .Inconsistent_Row_Width:
		return "map rows have different widths"
	case .Unknown_Symbol:
		return "the map contains an unknown symbol"
	case .Missing_Player_Spawn:
		return "the map needs one player spawn (@)"
	case .Multiple_Player_Spawns:
		return "the map contains more than one player spawn (@)"
	}
	return "unknown parse error"
}

from_ascii :: proc(rows: []string) -> (result: Level, err: Parse_Error, error_at: grid.Position) {
	if len(rows) == 0 || len(rows[0]) == 0 {
		return {}, .Empty_Map, {}
	}

	width := len(rows[0])
	for row, y in rows {
		if len(row) != width {
			return {}, .Inconsistent_Row_Width, {x = len(row), y = y}
		}
	}

	level, ok := create(width, len(rows))
	if !ok {
		return {}, .Empty_Map, {}
	}

	for row, y in rows {
		for symbol, x in row {
			position := grid.Position{x = x, y = y}
			tile, known := tile_from_symbol(cast(u8)symbol)
			if !known {
				destroy(&level)
				return {}, .Unknown_Symbol, position
			}

			if tile.kind == .Player_Spawn {
				if level.has_player_spawn {
					destroy(&level)
					return {}, .Multiple_Player_Spawns, position
				}
				level.player_spawn = position
				level.has_player_spawn = true
			}

			assert(set_tile(&level, position, tile))
		}
	}

	if !level.has_player_spawn {
		destroy(&level)
		return {}, .Missing_Player_Spawn, {}
	}

	return level, .None, {}
}

generate_room :: proc(width, height: int) -> (result: Level, ok: bool) {
	if width < 5 || height < 5 {
		return {}, false
	}

	level, valid := create(width, height, Tile{kind = .Floor})
	if !valid {
		return {}, false
	}

	for y in 0..<height {
		for x in 0..<width {
			is_border := x == 0 || y == 0 || x == width-1 || y == height-1
			if is_border {
				assert(set_tile(&level, {x = x, y = y}, Tile{kind = .Wall}))
			}
		}
	}

	// Deterministic pillars make the example procedural without introducing a
	// random generator before the game has defined its determinism contract.
	for y := 3; y < height-2; y += 3 {
		for x := 3; x < width-2; x += 4 {
			assert(set_tile(&level, {x = x, y = y}, Tile{kind = .Wall}))
		}
	}

	level.player_spawn = {x = 1, y = 1}
	level.has_player_spawn = true
	assert(set_tile(&level, level.player_spawn, Tile{kind = .Player_Spawn}))
	assert(set_tile(&level, {x = width-2, y = height-2}, Tile{kind = .Exit}))

	return level, true
}
