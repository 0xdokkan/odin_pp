package level

import "core:math/rand"
import grid "../grid"

Room_Family :: enum { Scattered, Pillars, Ring, Twin_Courts, Asymmetric }

room_family_is_valid :: proc(family: Room_Family) -> bool {
	return family >= .Scattered && family <= .Asymmetric
}

room_family_name :: proc(family: Room_Family) -> string {
	switch family {
	case .Scattered: return "Chamber"
	case .Pillars: return "Pillar Arena"
	case .Ring: return "Ring"
	case .Twin_Courts: return "Twin Courts"
	case .Asymmetric: return "Broken Cover"
	}
	return "Chamber"
}

// Keep the perimeter open for flanking; both court gates also retain their approaches.
// Actors may use these cells, but generated fixed obstacles and objects may not seal them.
room_family_cell_is_reserved :: proc(data: ^Level, family: Room_Family, position: grid.Position) -> bool {
	if data == nil || family == .Scattered { return false }
	width, height := data.tiles.width, data.tiles.height
	if position.x == 1 || position.y == 1 || position.x == width-2 || position.y == height-2 {
		return true
	}
	if family == .Twin_Courts && abs(position.x-width/2) <= 1 {
		gate, found := tile_at(data, {width/2, position.y})
		return found && is_walkable(gate.kind)
	}
	return false
}

write_family_wall :: proc(data: ^Level, x, y: int) {
	written := set_tile(data, {x, y}, {kind = .Wall})
	assert(written)
}

generate_tactical_room_attempt :: proc(config: Room_Generation_Config, generator: rand.Generator) -> (result: Level, ok: bool) {
	result, ok = create(config.width, config.height, {kind = .Floor})
	if !ok { return {}, false }
	width, height := config.width, config.height
	for y in 0..<height {
		for x in 0..<width {
			if is_border_position({x, y}, width, height) { write_family_wall(&result, x, y) }
		}
	}
	switch config.family {
	case .Scattered:
		unreachable()
	case .Pillars:
		// Four separate cover islands, with horizontal and vertical lanes between them.
		left := width/3+rand.int_range(-1, 1, generator)
		right := width-1-left
		top, bottom := 3, height-4
		x_positions, y_positions := [2]int{left, right}, [2]int{top, bottom}
		for x in x_positions {
			for y in y_positions {
				write_family_wall(&result, x, y)
				if rand.int_range(0, 2, generator) == 0 { write_family_wall(&result, x+1, y) }
			}
		}
	case .Ring:
		// A solid central island forces clockwise/counterclockwise approaches.
		half_width := rand.int_range(1, 3, generator)
		center_x := width/2+rand.int_range(-1, 2, generator)
		for y in height/2-1..=height/2+1 {
			for x in center_x-half_width..=center_x+half_width { write_family_wall(&result, x, y) }
		}
	case .Twin_Courts:
		upper := 2+rand.int_range(0, 2, generator)
		lower := height-3-rand.int_range(0, 2, generator)
		for y in 1..<height-1 {
			if y != upper && y != lower { write_family_wall(&result, width/2, y) }
		}
	case .Asymmetric:
		mirror_x := rand.int_range(0, 2, generator) == 0
		mirror_y := rand.int_range(0, 2, generator) == 0
		branch := rand.int_range(2, 4, generator)
		for y in 2..=height-4 {
			x := width/3
			write_family_wall(&result, width-1-x if mirror_x else x, height-1-y if mirror_y else y)
		}
		for x in width/3+1..=width/3+branch {
			y := height-4
			write_family_wall(&result, width-1-x if mirror_x else x, height-1-y if mirror_y else y)
		}
		x, y := width-5, 3
		write_family_wall(&result, width-1-x if mirror_x else x, height-1-y if mirror_y else y)
	}

	// Select anchors around the completed shape, never carve away its defining walls.
	anchors := make([dynamic]Room_Anchor_Pair, 0, valid_anchor_pair_count(config))
	defer delete(anchors)
	minimum, maximum := exit_candidate_bounds(config)
	for spawn in interior_corners(width, height) {
		if !clearance_is_walkable(&result, spawn, config.spawn_clearance_radius) { continue }
		for y in minimum.y..=maximum.y {
			for x in minimum.x..=maximum.x {
				exit_position := grid.Position{x, y}
				if anchor_pair_is_valid(config, spawn, exit_position) &&
				   clearance_is_walkable(&result, exit_position, config.exit_clearance_radius) {
					append(&anchors, Room_Anchor_Pair{spawn, exit_position})
				}
			}
		}
	}
	if len(anchors) == 0 { destroy(&result); return {}, false }
	selected := anchors[rand.int_range(0, len(anchors), generator)]
	result.player_spawn = selected.spawn
	result.has_player_spawn = true
	spawn_written := set_tile(&result, selected.spawn, {kind = .Player_Spawn})
	exit_written := set_tile(&result, selected.exit, {kind = .Exit})
	assert(spawn_written && exit_written)
	if validate_generated_room(&result, config).error != .None { destroy(&result); return {}, false }
	return result, true
}
