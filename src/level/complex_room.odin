package level

import "core:math/rand"
import grid "../engine/grid"

// These routes remain clear of both architecture and generated solid objects.
// Wide approaches let large encounters flank instead of forming a single queue.
complex_room_crossing_is_reserved :: proc(width, height: int, position: grid.Position) -> bool {
	return position.x <= 2 || position.y <= 2 || position.x >= width-3 || position.y >= height-3 ||
	       abs(position.x-width/2) <= 1 || abs(position.y-height/2) <= 1 ||
	       (abs(position.x-width/2) <= 2 && abs(position.y-height/2) <= 2)
}

write_complex_family_wall :: proc(data: ^Level, x, y: int) {
	if complex_room_crossing_is_reserved(data.tiles.width, data.tiles.height, {x, y}) { return }
	write_family_wall(data, x, y)
}

complex_court_gate_row :: proc(height, y: int) -> bool {
	return abs(y-height/2) <= 1 || y == height/3 || y == height/3+1 ||
	       y == height*2/3 || y == height*2/3+1
}

complex_court_partition_x :: proc(width, complexity, partition: int) -> int {
	if partition <= 0 { return 0 }
	if partition >= complexity+2 { return width-1 }
	x := partition*(width-1)/(complexity+2)
	// An odd number of partitions otherwise puts a whole divider inside the
	// central north/south avenue. Offset it so every tier adds a real court.
	if abs(x-width/2) <= 1 { x = width/2+3 }
	return x
}

write_complex_room_family :: proc(data: ^Level, config: Room_Generation_Config, generator: rand.Generator) {
	width, height := config.width, config.height
	switch config.family {
	case .Scattered:
		unreachable()
	case .Pillars:
		// Repeated resin columns form several staggered lanes, with larger cover
		// footprints deeper in the run. Each island has at least two clear sides.
		stagger := rand.int_range(0, 2, generator)
		row := 0
		for y := 3; y <= height-5; y += 6 {
			for x := 3+(row+stagger)%2; x <= width-5; x += 6 {
				pillar_width := 3 if config.complexity >= 2 && (x+y)%3 == 0 else 2
				for dy in 0..<2 {
					for dx in 0..<pillar_width { write_complex_family_wall(data, x+dx, y+dy) }
				}
			}
			row += 1
		}
	case .Ring:
		// Four independent L-shaped bastions surround an open central court.
		// Three-cell gates connect that court to a second, outer flanking loop.
		rx := max(4, width/4+rand.int_range(-1, 2, generator))
		ry := max(3, height/4+rand.int_range(0, 2, generator))
		left, right := max(4, width/2-rx), min(width-5, width/2+rx)
		top, bottom := max(4, height/2-ry), min(height-5, height/2+ry)
		for y in top..=bottom {
			for x in left..=right {
				if x < left+2 || x > right-2 || y < top+2 || y > bottom-2 {
					write_complex_family_wall(data, x, y)
				}
			}
		}
		// Satellite columns add cover along the outer circuit in later arenas.
		if config.complexity >= 2 {
			for y in ([2]int{3, height-5}) {
				for x in ([2]int{3, width-5}) {
					for dy in 0..<2 {
						for dx in 0..<2 { write_complex_family_wall(data, x+dx, y+dy) }
					}
				}
			}
		}
	case .Twin_Courts:
		// Three to five adjoining courts. Every partition has several two-cell
		// gates plus the shared central avenue and the outer perimeter routes.
		for partition in 1..=config.complexity+1 {
			x := complex_court_partition_x(width, config.complexity, partition)
			for y in 3..<height-3 {
				if !complex_court_gate_row(height, y) { write_complex_family_wall(data, x, y) }
			}
		}
		// Short transverse walls give the courts local cover without sealing
		// their north/south route or reducing a gate to a one-cell bottleneck.
		for court in 0..<config.complexity+2 {
			left := complex_court_partition_x(width, config.complexity, court)
			right := complex_court_partition_x(width, config.complexity, court+1)
			y := 4 if court%2 == 0 else height-5
			for x in left+3..=right-3 { write_complex_family_wall(data, x, y) }
		}
	case .Asymmetric:
		// Broken, independently mirrored L-cover makes successive skirmish
		// spaces. The separated shapes cannot enclose an unreachable pocket.
		for y := 3; y <= height-6; y += 7 {
			for x := 3; x <= width-6; x += 8 {
				mirror_x := rand.int_range(0, 2, generator) == 0
				mirror_y := rand.int_range(0, 2, generator) == 0
				arm := min(4+rand.int_range(0, 2, generator), width-3-x, height-3-y)
				for offset in 0..<arm {
					write_complex_family_wall(data, x+(arm-1 if mirror_x else 0), y+offset)
					write_complex_family_wall(data, x+offset, y+(arm-1 if mirror_y else 0))
				}
			}
		}
	}
}

// Large arenas previously tried every exit for every successively closer spawn.
// Exit extrema answer whether a spawn has any sufficiently distant exit in O(1).
// Only the nearest feasible spawn ties then participate in reservoir sampling.
select_complex_room_anchors :: proc(data: ^Level, config: Room_Generation_Config, generator: rand.Generator) -> (result: Room_Anchor_Pair, found: bool) {
	minimum, maximum := exit_candidate_bounds(config)
	exits := make([dynamic]grid.Position)
	defer delete(exits)
	min_sum, max_sum, min_difference, max_difference := max(int), min(int), max(int), min(int)
	for y in minimum.y..=maximum.y {
		for x in minimum.x..=maximum.x {
			position := grid.Position{x, y}
			if !has_full_interior_clearance(position, config.exit_clearance_radius, config.width, config.height) ||
			   !clearance_is_walkable(data, position, config.exit_clearance_radius) { continue }
			append(&exits, position)
			min_sum, max_sum = min(min_sum, x+y), max(max_sum, x+y)
			min_difference, max_difference = min(min_difference, x-y), max(max_difference, x-y)
		}
	}
	if len(exits) == 0 { return {}, false }
	spawns := make([dynamic]grid.Position, 0, 4)
	defer delete(spawns)
	closest := max(int)
	for y in 1+config.spawn_clearance_radius..<config.height-1-config.spawn_clearance_radius {
		for x in 1+config.spawn_clearance_radius..<config.width-1-config.spawn_clearance_radius {
			position := grid.Position{x, y}
			distance := spawn_center_distance_squared(config, position)
			if distance > closest || !clearance_is_walkable(data, position, config.spawn_clearance_radius) { continue }
			farthest := max(max_sum-(x+y), (x+y)-min_sum, max_difference-(x-y), (x-y)-min_difference)
			if farthest < config.min_spawn_exit_distance { continue }
			if distance < closest { closest = distance; clear(&spawns) }
			append(&spawns, position)
		}
	}
	choices := 0
	for spawn in spawns {
		for exit_position in exits {
			if !anchor_pair_is_valid(config, spawn, exit_position) { continue }
			choices += 1
			if rand.int_range(0, choices, generator) == 0 { result = {spawn, exit_position} }
		}
	}
	return result, choices > 0
}
