package level

import "core:math/rand"
import "core:sync"
import grid "../engine/grid"

Tile_Kind :: enum u8 {
	Void,
	Floor,
	Wall,
	Door,
	Player_Spawn,
	Exit,
	// A low wall: it stops the step but not the sight (structure.odin).
	Fence,
}

Tile :: struct {
	kind: Tile_Kind,
}

Level :: struct {
	tiles:            grid.Grid(Tile),
	player_spawn:     grid.Position,
	has_player_spawn: bool,
	// Generated arena tier; zero also covers parsed maps and legacy rooms.
	layout_complexity: int,
	// A lifetime identity avoids stale GPU caches when an allocator reuses a
	// destroyed map's address. Neither counter participates in gameplay RNG.
	geometry_id, geometry_revision: u64,
	// The height of each cell in steps, a unit the rules count in (a step up is
	// walked, a cliff of two or more is a wall). Empty means flat: every cell is
	// at 0, which is every map that was not given heights.
	heights: [dynamic]u8,
	// The structures standing on the map (structure.odin): each one, its plan turned as
	// placed, and for every cell the number of the structure over it (0 for none, else
	// its index plus one). The tiles themselves are ordinary ones.
	structures:      [dynamic]Placed_Structure,
	structure_plans: [dynamic]Plan,
	structure_cells: [dynamic]u8,
	// The layers other than the ground (layers.odin), by layer_slot: the ground's slot stays empty.
	planes:  [LAYER_COUNT]Layer_Plane,
	ladders: [dynamic]Ladder,
	// The lifts' shafts (layers.odin); where each platform is, the game keeps.
	lifts:   [dynamic]Lift,
	// The shortcuts' gates (layers.odin): shut, a gate's cell is a Fence; open, a Floor.
	gates:   [dynamic]Gate,
	// The height of the map's level ground, in steps: 0, or a base the map's ground was raised by so that there is room
	// under it for the layers below (Fase 7 of docs/piano-profondita.md). It is drawn at the board's plane: the rules count
	// heights from 0 as ever, only the drawing takes the base off.
	base:    i32,
}

// The tallest a cell can be.
MAX_CELL_HEIGHT :: 255

@(private)
next_geometry_id: u64

Parse_Error :: enum {
	None,
	Empty_Map,
	Inconsistent_Row_Width,
	Unknown_Symbol,
	Missing_Player_Spawn,
	Multiple_Player_Spawns,
}

Room_Generation_Config :: struct {
	family:                   Room_Family,
	central_spawn:            bool,
	complexity:               int,
	width, height:            int,
	wall_density_percent:     int,
	spawn_clearance_radius:   int,
	exit_center_radius:       int,
	exit_clearance_radius:    int,
	min_spawn_exit_distance:  int,
	min_walkable_percent:     int,
	max_attempts:             int,
}

Room_Generation_Error :: enum {
	None,
	Invalid_Config,
	Attempts_Exhausted,
}

Room_Validation_Error :: enum {
	None,
	Invalid_Level,
	Border_Not_Solid,
	Invalid_Spawn,
	Missing_Exit,
	Multiple_Exits,
	Spawn_Clearance_Blocked,
	Exit_Clearance_Blocked,
	Exit_Unreachable,
	Disconnected_Walkable_Area,
	Too_Few_Walkable_Cells,
	Spawn_Exit_Too_Close,
}

Room_Validation_Report :: struct {
	error:                       Room_Validation_Error,
	exit_position:               grid.Position,
	walkable_count:              int,
	reachable_count:             int,
	spawn_exit_distance:         int,
}

CARDINAL_OFFSETS :: [4]grid.Position{
	{x = 0, y = -1},
	{x = 1, y = 0},
	{x = 0, y = 1},
	{x = -1, y = 0},
}

MIN_GENERATED_ROOM_DIMENSION :: 5
MAX_GENERATED_ROOM_DIMENSION :: 128
MAX_ROOM_GENERATION_ATTEMPTS :: 1024

Room_Anchor_Pair :: struct {
	spawn, exit: grid.Position,
}

create :: proc(width, height: int, initial_tile := Tile{kind = .Void}) -> (result: Level, ok: bool) {
	tiles, valid := grid.create(Tile, width, height, initial_tile)
	if !valid {
		return {}, false
	}
	result.tiles = tiles
	result.geometry_id = sync.atomic_add(&next_geometry_id, 1)+1
	result.geometry_revision = 1
	return result, true
}

destroy :: proc(level: ^Level) {
	if level == nil {
		return
	}
	grid.destroy(&level.tiles)
	delete(level.heights)
	delete(level.structures)
	delete(level.structure_plans)
	delete(level.structure_cells)
	destroy_layers(level)
	level^ = {}
}

// The height of `position` in steps, on its layer: 0 on a flat map, off the map or without heights.
height_at :: proc(level: ^Level, position: grid.Position) -> i32 {
	if level == nil { return 0 }
	if position.layer != grid.GROUND_LAYER { return plane_height(level, position) }
	if len(level.heights) == 0 { return 0 }
	index, found := grid.index_of(&level.tiles, position)
	if !found || index >= len(level.heights) { return 0 }
	return i32(level.heights[index])
}

has_heights :: proc(level: ^Level) -> bool {
	return level != nil && len(level.heights) > 0
}

// Raises or lowers one cell (0..MAX_CELL_HEIGHT). The first non-zero height makes
// the map's height table; a change alters the geometry like a tile does.
set_height :: proc(level: ^Level, position: grid.Position, height: i32) -> bool {
	if level == nil { return false }
	steps := clamp(height, 0, i32(MAX_CELL_HEIGHT))
	if position.layer != grid.GROUND_LAYER { return set_plane_height(level, position, steps) }
	index, found := grid.index_of(&level.tiles, position)
	if !found { return false }
	if len(level.heights) == 0 {
		if steps == 0 { return true }
		resize(&level.heights, len(level.tiles.cells))
	}
	if i32(level.heights[index]) == steps { return true }
	level.heights[index] = u8(steps)
	mark_geometry_changed(level)
	return true
}

// Sets the whole height table at once (one value per cell, in the tiles' order); all zeros is
// a flat map and leaves the table empty. A change alters the geometry like a tile does.
set_height_table :: proc(level: ^Level, heights: []u8) -> bool {
	if level == nil || len(heights) != len(level.tiles.cells) { return false }
	flat := true
	for steps in heights { if steps != 0 { flat = false; break } }
	if flat { clear(&level.heights); mark_geometry_changed(level); return true }
	resize(&level.heights, len(heights))
	copy(level.heights[:], heights)
	mark_geometry_changed(level)
	return true
}

// Every cell's tile kind, in the tiles' order, into `out` (as many as the map has cells).
tile_kinds :: proc(level: ^Level, out: []u8) -> bool {
	if level == nil || len(out) < len(level.tiles.cells) { return false }
	for tile, i in level.tiles.cells { out[i] = u8(tile.kind) }
	return true
}

// Sets every cell's tile kind at once (one per cell, in the tiles' order): a single change of the geometry,
// where a call of set_tile for each cell would make as many. False if a kind is not one.
set_tile_kinds :: proc(level: ^Level, kinds: []u8) -> bool {
	if level == nil || len(kinds) != len(level.tiles.cells) { return false }
	for kind in kinds { if Tile_Kind(kind) > max(Tile_Kind) { return false } }
	changed := false
	for kind, i in kinds {
		if u8(level.tiles.cells[i].kind) != kind { level.tiles.cells[i].kind = Tile_Kind(kind); changed = true }
	}
	if changed { mark_geometry_changed(level) }
	return true
}

// Heights from rows of text the size of the map: ' ' or '0' is flat, '1'..'9'
// that many steps, 'a'..'f' ten to fifteen. Used by the arenas that test heights.
apply_height_rows :: proc(level: ^Level, rows: []string) -> bool {
	if level == nil || len(rows) != level.tiles.height { return false }
	for row in rows { if len(row) != level.tiles.width { return false } }
	for row, y in rows {
		for symbol, x in row {
			steps: i32
			switch {
			case symbol >= '0' && symbol <= '9': steps = i32(symbol-'0')
			case symbol >= 'a' && symbol <= 'f': steps = i32(symbol-'a')+10
			case symbol == ' ':
			case: return false
			}
			if !set_height(level, {x = x, y = y}, steps) { return false }
		}
	}
	return true
}

// The tile of `position` on its layer: a cell of another layer that holds nothing is Void.
tile_at :: proc(level: ^Level, position: grid.Position) -> (Tile, bool) {
	if level == nil {
		return {}, false
	}
	if position.layer != grid.GROUND_LAYER { return plane_tile(level, position) }
	return grid.get(&level.tiles, position)
}

set_tile :: proc(level: ^Level, position: grid.Position, tile: Tile) -> bool {
	if level == nil {
		return false
	}
	if position.layer != grid.GROUND_LAYER { return set_plane_tile(level, position, tile) }
	previous, found := grid.get(&level.tiles, position)
	if !found {return false}
	if previous == tile {return true}
	if !grid.set(&level.tiles, position, tile) {return false}
	mark_geometry_changed(level)
	return true
}

// Call after a bulk write into tiles.cells. Ordinary mutations should use
// set_tile, which also avoids invalidating caches for an unchanged cell.
mark_geometry_changed :: proc(level: ^Level) {
	if level != nil {level.geometry_revision += 1}
}

is_walkable :: proc(kind: Tile_Kind) -> bool {
	switch kind {
	case .Floor, .Door, .Player_Spawn, .Exit:
		return true
	case .Void, .Wall, .Fence:
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
	case '=':
		return Tile{kind = .Fence}, true
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
	case .Fence:
		return "="
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

			written := set_tile(&level, position, tile)
			assert(written)
		}
	}

	if !level.has_player_spawn {
		destroy(&level)
		return {}, .Missing_Player_Spawn, {}
	}

	return level, .None, {}
}

default_room_generation_config :: proc(width, height: int) -> Room_Generation_Config {
	return {
		width = width,
		height = height,
		wall_density_percent = 14,
		spawn_clearance_radius = 1,
		exit_center_radius = 1,
		exit_clearance_radius = 1,
		min_spawn_exit_distance = max(2, width/4+height/4),
		min_walkable_percent = 65,
		max_attempts = 64,
	}
}

interior_corners :: proc(width, height: int) -> [4]grid.Position {
	return {
		{x = 1, y = 1},
		{x = width-2, y = 1},
		{x = width-2, y = height-2},
		{x = 1, y = height-2},
	}
}

manhattan_distance :: proc(a, b: grid.Position) -> int {
	return abs(a.x-b.x)+abs(a.y-b.y)
}

inside_clearance :: proc(position, center: grid.Position, radius: int) -> bool {
	return max(abs(position.x-center.x), abs(position.y-center.y)) <= radius
}

has_full_interior_clearance :: proc(
	position: grid.Position,
	radius, width, height: int,
) -> bool {
	return position.x-radius >= 1 && position.x+radius <= width-2 &&
	       position.y-radius >= 1 && position.y+radius <= height-2
}

exit_candidate_bounds :: proc(config: Room_Generation_Config) -> (
	minimum, maximum: grid.Position,
) {
	center := grid.Position{x = config.width/2, y = config.height/2}
	minimum = {
		x = max(1, center.x-config.exit_center_radius),
		y = max(1, center.y-config.exit_center_radius),
	}
	maximum = {
		x = min(config.width-2, center.x+config.exit_center_radius),
		y = min(config.height-2, center.y+config.exit_center_radius),
	}
	return
}

anchor_pair_is_valid :: proc(
	config: Room_Generation_Config,
	spawn_position, exit_position: grid.Position,
) -> bool {
	return has_full_interior_clearance(
		exit_position,
		config.exit_clearance_radius,
		config.width,
		config.height,
	) && manhattan_distance(spawn_position, exit_position) >= config.min_spawn_exit_distance
}

valid_anchor_pair_count :: proc(config: Room_Generation_Config) -> (result: int) {
	minimum, maximum := exit_candidate_bounds(config)
	for spawn_position in interior_corners(config.width, config.height) {
		for y in minimum.y..=maximum.y {
			for x in minimum.x..=maximum.x {
				if anchor_pair_is_valid(config, spawn_position, {x = x, y = y}) {
					result += 1
				}
			}
		}
	}
	return
}

anchor_pair_at :: proc(config: Room_Generation_Config, target_index: int) -> (Room_Anchor_Pair, bool) {
	if target_index < 0 {
		return {}, false
	}
	minimum, maximum := exit_candidate_bounds(config)
	current_index := 0
	for spawn_position in interior_corners(config.width, config.height) {
		for y in minimum.y..=maximum.y {
			for x in minimum.x..=maximum.x {
				exit_position := grid.Position{x = x, y = y}
				if !anchor_pair_is_valid(config, spawn_position, exit_position) {
					continue
				}
				if current_index == target_index {
					return {spawn = spawn_position, exit = exit_position}, true
				}
				current_index += 1
			}
		}
	}
	return {}, false
}

generation_config_is_valid :: proc(config: Room_Generation_Config) -> bool {
	if !room_family_is_valid(config.family) ||
	   config.complexity < 0 || config.complexity > 3 ||
	   (config.family != .Scattered && (config.width < 13 || config.height < 9)) ||
	   config.width < MIN_GENERATED_ROOM_DIMENSION ||
	   config.height < MIN_GENERATED_ROOM_DIMENSION ||
	   config.width > MAX_GENERATED_ROOM_DIMENSION ||
	   config.height > MAX_GENERATED_ROOM_DIMENSION ||
	   config.wall_density_percent < 0 || config.wall_density_percent > 100 ||
	   config.spawn_clearance_radius < 0 || config.exit_center_radius < 0 ||
	   config.exit_clearance_radius < 0 ||
	   config.spawn_clearance_radius > MAX_GENERATED_ROOM_DIMENSION ||
	   config.exit_center_radius > MAX_GENERATED_ROOM_DIMENSION ||
	   config.exit_clearance_radius > MAX_GENERATED_ROOM_DIMENSION ||
	   config.min_spawn_exit_distance < 1 ||
	   config.min_spawn_exit_distance > MAX_GENERATED_ROOM_DIMENSION*2 ||
	   config.min_walkable_percent < 1 || config.min_walkable_percent > 100 ||
	   config.max_attempts <= 0 || config.max_attempts > MAX_ROOM_GENERATION_ATTEMPTS {
		return false
	}
	if config.central_spawn {
		// With central placement both anchors need their full clearance. The
		// farthest corners of these regions bound every possible anchor pair.
		spawn_min := 1+config.spawn_clearance_radius
		spawn_max := grid.Position{x = config.width-2-config.spawn_clearance_radius, y = config.height-2-config.spawn_clearance_radius}
		exit_min, exit_max := exit_candidate_bounds(config)
		exit_min.x = max(exit_min.x, 1+config.exit_clearance_radius)
		exit_min.y = max(exit_min.y, 1+config.exit_clearance_radius)
		exit_max.x = min(exit_max.x, config.width-2-config.exit_clearance_radius)
		exit_max.y = min(exit_max.y, config.height-2-config.exit_clearance_radius)
		if spawn_min > spawn_max.x || spawn_min > spawn_max.y || exit_min.x > exit_max.x || exit_min.y > exit_max.y { return false }
		farthest := max(abs(spawn_min-exit_max.x), abs(spawn_max.x-exit_min.x)) +
		            max(abs(spawn_min-exit_max.y), abs(spawn_max.y-exit_min.y))
		return farthest >= config.min_spawn_exit_distance
	}
	return valid_anchor_pair_count(config) > 0
}

is_border_position :: proc(position: grid.Position, width, height: int) -> bool {
	return position.x == 0 || position.y == 0 ||
	       position.x == width-1 || position.y == height-1
}

is_interior_corner :: proc(position: grid.Position, width, height: int) -> bool {
	corners := interior_corners(width, height)
	for corner in corners {
		if position == corner {
			return true
		}
	}
	return false
}

clearance_is_walkable :: proc(
	level_data: ^Level,
	center: grid.Position,
	radius: int,
) -> bool {
	assert(level_data != nil && radius >= 0)
	minimum_x := max(1, center.x-radius)
	maximum_x := min(level_data.tiles.width-2, center.x+radius)
	minimum_y := max(1, center.y-radius)
	maximum_y := min(level_data.tiles.height-2, center.y+radius)
	for y in minimum_y..=maximum_y {
		for x in minimum_x..=maximum_x {
			tile, found := tile_at(level_data, {x = x, y = y})
			if !found || !is_walkable(tile.kind) {
				return false
			}
		}
	}
	return true
}

validate_generated_room :: proc(
	level_data: ^Level,
	config: Room_Generation_Config,
) -> (result: Room_Validation_Report) {
	result.error = .Invalid_Level
	result.spawn_exit_distance = -1
	if level_data == nil || !generation_config_is_valid(config) ||
	   level_data.tiles.width != config.width || level_data.tiles.height != config.height ||
	   len(level_data.tiles.cells) != config.width*config.height {
		return
	}

	spawn_position: grid.Position
	spawn_count := 0
	exit_count := 0
	for tile, index in level_data.tiles.cells {
		position, found := grid.position_of(&level_data.tiles, index)
		if !found {
			return
		}
		if is_border_position(position, config.width, config.height) && tile.kind != .Wall {
			result.error = .Border_Not_Solid
			return
		}
		if is_walkable(tile.kind) {
			result.walkable_count += 1
		}
		#partial switch tile.kind {
		case .Player_Spawn:
			spawn_position = position
			spawn_count += 1
		case .Exit:
			result.exit_position = position
			exit_count += 1
		}
	}

	valid_spawn_position := has_full_interior_clearance(spawn_position, config.spawn_clearance_radius, config.width, config.height) if config.central_spawn else
	                        is_interior_corner(spawn_position, config.width, config.height)
	if spawn_count != 1 || !level_data.has_player_spawn ||
	   level_data.player_spawn != spawn_position || !valid_spawn_position {
		result.error = .Invalid_Spawn
		return
	}
	if exit_count == 0 {
		result.error = .Missing_Exit
		return
	}
	if exit_count > 1 {
		result.error = .Multiple_Exits
		return
	}

	minimum_exit, maximum_exit := exit_candidate_bounds(config)
	if result.exit_position.x < minimum_exit.x || result.exit_position.x > maximum_exit.x ||
	   result.exit_position.y < minimum_exit.y || result.exit_position.y > maximum_exit.y {
		return
	}
	if !has_full_interior_clearance(
		result.exit_position,
		config.exit_clearance_radius,
		config.width,
		config.height,
	) {
		result.error = .Exit_Clearance_Blocked
		return
	}
	if manhattan_distance(spawn_position, result.exit_position) < config.min_spawn_exit_distance {
		result.error = .Spawn_Exit_Too_Close
		return
	}
	if !clearance_is_walkable(level_data, spawn_position, config.spawn_clearance_radius) {
		result.error = .Spawn_Clearance_Blocked
		return
	}
	if !clearance_is_walkable(level_data, result.exit_position, config.exit_clearance_radius) {
		result.error = .Exit_Clearance_Blocked
		return
	}

	cell_count := grid.cell_count(&level_data.tiles)
	distances := make([]int, cell_count)
	defer delete(distances)
	for &distance in distances {
		distance = -1
	}
	queue := make([]grid.Position, cell_count)
	defer delete(queue)

	spawn_index, found := grid.index_of(&level_data.tiles, spawn_position)
	assert(found)
	distances[spawn_index] = 0
	queue[0] = spawn_position
	head, tail := 0, 1
	for head < tail {
		position := queue[head]
		head += 1
		position_index, valid := grid.index_of(&level_data.tiles, position)
		assert(valid)
		result.reachable_count += 1

		for offset in CARDINAL_OFFSETS {
			neighbor := grid.Position{x = position.x+offset.x, y = position.y+offset.y}
			neighbor_index, inside := grid.index_of(&level_data.tiles, neighbor)
			if !inside || distances[neighbor_index] >= 0 {
				continue
			}
			tile, present := tile_at(level_data, neighbor)
			assert(present)
			if !is_walkable(tile.kind) {
				continue
			}
			distances[neighbor_index] = distances[position_index]+1
			queue[tail] = neighbor
			tail += 1
		}
	}

	exit_index, exit_found := grid.index_of(&level_data.tiles, result.exit_position)
	assert(exit_found)
	result.spawn_exit_distance = distances[exit_index]
	if result.spawn_exit_distance < 0 {
		result.error = .Exit_Unreachable
		return
	}
	if result.reachable_count != result.walkable_count {
		result.error = .Disconnected_Walkable_Area
		return
	}
	interior_count := (config.width-2)*(config.height-2)
	if result.walkable_count*100 < interior_count*config.min_walkable_percent {
		result.error = .Too_Few_Walkable_Cells
		return
	}
	result.error = .None
	return
}

generate_room_attempt :: proc(
	config: Room_Generation_Config,
	generator: rand.Generator,
) -> (result: Level, ok: bool) {
	if config.family != .Scattered {
		return generate_tactical_room_attempt(config, generator)
	}
	result, ok = create(config.width, config.height, Tile{kind = .Floor})
	if !ok {
		return {}, false
	}

	for y in 0..<config.height {
		for x in 0..<config.width {
			position := grid.Position{x = x, y = y}
			if is_border_position(position, config.width, config.height) {
				written := set_tile(&result, position, Tile{kind = .Wall})
				assert(written)
			}
		}
	}

	anchors: Room_Anchor_Pair
	anchors_found: bool
	if config.central_spawn {
		anchors, anchors_found = select_central_room_anchors(&result, config, generator)
	} else {
		pair_count := valid_anchor_pair_count(config)
		selected_pair := rand.int_range(0, pair_count, generator)
		anchors, anchors_found = anchor_pair_at(config, selected_pair)
	}
	if !anchors_found {
		destroy(&result)
		return {}, false
	}
	spawn_position := anchors.spawn
	exit_position := anchors.exit

	wall_candidates := make([dynamic]grid.Position, 0, (config.width-2)*(config.height-2))
	defer delete(wall_candidates)
	for y in 1..<config.height-1 {
		for x in 1..<config.width-1 {
			position := grid.Position{x = x, y = y}
			if inside_clearance(position, spawn_position, config.spawn_clearance_radius) ||
			   inside_clearance(position, exit_position, config.exit_clearance_radius) {
				continue
			}
			append(&wall_candidates, position)
		}
	}
	rand.shuffle(wall_candidates[:], generator)
	wall_count := len(wall_candidates)*config.wall_density_percent/100
	for index in 0..<wall_count {
		written := set_tile(&result, wall_candidates[index], Tile{kind = .Wall})
		assert(written)
	}

	result.player_spawn = spawn_position
	result.has_player_spawn = true
	spawn_written := set_tile(&result, spawn_position, Tile{kind = .Player_Spawn})
	exit_written := set_tile(&result, exit_position, Tile{kind = .Exit})
	assert(spawn_written && exit_written)
	report := validate_generated_room(&result, config)
	if report.error != .None {
		destroy(&result)
		return {}, false
	}
	return result, true
}

generate_room :: proc(
	config: Room_Generation_Config,
	seed: u64,
) -> (result: Level, err: Room_Generation_Error) {
	if !generation_config_is_valid(config) {
		return {}, .Invalid_Config
	}

	random_state: rand.Xoshiro256_Random_State
	generator := rand.xoshiro256_random_generator(&random_state)
	rand.reset_u64(seed, generator)
	for _ in 0..<config.max_attempts {
		generated, ok := generate_room_attempt(config, generator)
		if ok {
			return generated, .None
		}
	}
	return {}, .Attempts_Exhausted
}
