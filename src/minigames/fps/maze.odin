package fps

import rng "../../engine/rng"

// The crypt layout is a square grid of maze cells stored as tiles: odd/odd
// tiles are cells, the tiles between them are walls or passages and even/even
// tiles are the posts at wall corners. Rooms clear every tile inside a cell
// rectangle, so they read as halls with optional pillars.
MAX_CELLS :: 12
TILE_SIDE :: 2*MAX_CELLS + 1
MAX_TILES :: TILE_SIDE * TILE_SIDE
MAX_ROOMS :: 10
MAX_MAZE_CELLS :: MAX_CELLS * MAX_CELLS

Room :: struct {
	x, y, w, h: int, // in cells
}

Maze :: struct {
	cells:      int, // cells per side
	tiles:      int, // 2*cells + 1
	open:       [MAX_TILES]bool,
	room_of:    [MAX_TILES]i8, // -1 outside rooms
	rooms:      [MAX_ROOMS]Room,
	room_count: int,
	spawn_room: int,
	exit_room:  int,
	// Steps from the spawn cell through open passages, -1 if unreached.
	cell_dist:  [MAX_MAZE_CELLS]i32,
	max_dist:   i32,
}

tile_open :: proc "contextless" (m: ^Maze, tx, ty: int) -> bool {
	if tx < 0 || ty < 0 || tx >= m.tiles || ty >= m.tiles {
		return false
	}
	return m.open[ty*m.tiles+tx]
}

@(private)
set_tile :: proc "contextless" (m: ^Maze, tx, ty: int, open: bool) {
	if tx < 0 || ty < 0 || tx >= m.tiles || ty >= m.tiles {
		return
	}
	m.open[ty*m.tiles+tx] = open
}

tile_room :: proc "contextless" (m: ^Maze, tx, ty: int) -> int {
	if tx < 0 || ty < 0 || tx >= m.tiles || ty >= m.tiles {
		return -1
	}
	return int(m.room_of[ty*m.tiles+tx])
}

cell_room :: proc "contextless" (m: ^Maze, cx, cy: int) -> int {
	return tile_room(m, 2*cx+1, 2*cy+1)
}

cell_index :: proc "contextless" (m: ^Maze, cx, cy: int) -> int {
	return cy*m.cells + cx
}

// Number of open passages leaving a cell (4-neighbourhood).
cell_exits :: proc "contextless" (m: ^Maze, cx, cy: int) -> int {
	tx, ty := 2*cx+1, 2*cy+1
	n := 0
	for d in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
		if tile_open(m, tx+d.x, ty+d.y) {
			n += 1
		}
	}
	return n
}

is_dead_end :: proc "contextless" (m: ^Maze, cx, cy: int) -> bool {
	return cell_room(m, cx, cy) < 0 && cell_exits(m, cx, cy) == 1
}

room_center_cell :: proc "contextless" (room: Room) -> [2]int {
	return {room.x + room.w/2, room.y + room.h/2}
}

// Recursive backtracker plus extra loops and rooms. Every cell ends up
// connected to the spawn room, which the tests verify for many seeds.
maze_generate :: proc(m: ^Maze, cells: int, room_target: int, loop_chance: f32, r: ^rng.Rng) {
	m^ = {}
	m.cells = clamp(cells, 4, MAX_CELLS)
	m.tiles = 2*m.cells + 1
	for &v in m.room_of {
		v = -1
	}
	place_rooms(m, room_target, r)
	carve(m, r)
	for i in 0..<m.room_count {
		open_room(m, i)
	}
	// Loops turn the perfect maze into one with alternative routes, so a
	// chasing enemy can be circled around.
	for ty in 1..<m.tiles-1 {
		for tx in 1..<m.tiles-1 {
			between := (tx%2 == 1) != (ty%2 == 1)
			if between && !tile_open(m, tx, ty) && rng.chance(r, loop_chance) {
				set_tile(m, tx, ty, true)
			}
		}
	}
	compute_cell_distances(m)
	m.exit_room = farthest_room(m)
	add_pillars(m, r)
}

@(private)
place_rooms :: proc(m: ^Maze, room_target: int, r: ^rng.Rng) {
	// The antechamber sits in a random corner, so the far side of the map is
	// always a long way off.
	corner := rng.int_range(r, 0, 3)
	sx := rng.int_range(r, 0, 1)
	sy := rng.int_range(r, 0, 1)
	if corner&1 != 0 {
		sx = m.cells - 2 - sx
	}
	if corner&2 != 0 {
		sy = m.cells - 2 - sy
	}
	m.rooms[0] = Room{sx, sy, 2, 2}
	m.room_count = 1
	m.spawn_room = 0
	target := clamp(room_target, 1, MAX_ROOMS)
	for _ in 0..<120 {
		if m.room_count >= target {
			break
		}
		w := rng.int_range(r, 2, 3)
		h := rng.int_range(r, 2, 3)
		room := Room{rng.int_range(r, 0, m.cells-w), rng.int_range(r, 0, m.cells-h), w, h}
		ok := true
		for i in 0..<m.room_count {
			o := m.rooms[i]
			// One cell of margin keeps corridors between halls.
			if room.x <= o.x+o.w && o.x <= room.x+room.w && room.y <= o.y+o.h && o.y <= room.y+room.h {
				ok = false
				break
			}
		}
		if ok {
			m.rooms[m.room_count] = room
			m.room_count += 1
		}
	}
	if m.room_count < 2 {
		// The exit needs a hall of its own: the opposite corner is always free.
		m.rooms[1] = Room{m.cells - 2 - sx, m.cells - 2 - sy, 2, 2}
		m.room_count = 2
	}
}

@(private)
carve :: proc(m: ^Maze, r: ^rng.Rng) {
	visited: [MAX_MAZE_CELLS]bool
	stack: [MAX_MAZE_CELLS]i32
	top := 0
	start := room_center_cell(m.rooms[m.spawn_room])
	stack[0] = i32(cell_index(m, start.x, start.y))
	top = 1
	visited[stack[0]] = true
	set_tile(m, 2*start.x+1, 2*start.y+1, true)
	DIRS :: [4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
	dirs := DIRS
	for top > 0 {
		current := int(stack[top-1])
		cx, cy := current % m.cells, current / m.cells
		options: [4]int
		count := 0
		for d, i in dirs {
			nx, ny := cx+d.x, cy+d.y
			if nx < 0 || ny < 0 || nx >= m.cells || ny >= m.cells {
				continue
			}
			if !visited[cell_index(m, nx, ny)] {
				options[count] = i
				count += 1
			}
		}
		if count == 0 {
			top -= 1
			continue
		}
		d := dirs[options[rng.below(r, u64(count))]]
		nx, ny := cx+d.x, cy+d.y
		set_tile(m, 2*cx+1+d.x, 2*cy+1+d.y, true)
		set_tile(m, 2*nx+1, 2*ny+1, true)
		next := cell_index(m, nx, ny)
		visited[next] = true
		stack[top] = i32(next)
		top += 1
	}
}

@(private)
open_room :: proc(m: ^Maze, index: int) {
	room := m.rooms[index]
	for ty in 2*room.y+1..=2*(room.y+room.h)-1 {
		for tx in 2*room.x+1..=2*(room.x+room.w)-1 {
			set_tile(m, tx, ty, true)
			m.room_of[ty*m.tiles+tx] = i8(index)
		}
	}
}

@(private)
compute_cell_distances :: proc(m: ^Maze) {
	for &d in m.cell_dist {
		d = -1
	}
	queue: [MAX_MAZE_CELLS]i32
	head, tail := 0, 0
	start := room_center_cell(m.rooms[m.spawn_room])
	s := cell_index(m, start.x, start.y)
	m.cell_dist[s] = 0
	queue[tail] = i32(s)
	tail += 1
	m.max_dist = 0
	for head < tail {
		current := int(queue[head])
		head += 1
		cx, cy := current % m.cells, current / m.cells
		DIRS :: [4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
		for d in DIRS {
			nx, ny := cx+d.x, cy+d.y
			if nx < 0 || ny < 0 || nx >= m.cells || ny >= m.cells {
				continue
			}
			if !tile_open(m, 2*cx+1+d.x, 2*cy+1+d.y) {
				continue
			}
			n := cell_index(m, nx, ny)
			if m.cell_dist[n] >= 0 {
				continue
			}
			m.cell_dist[n] = m.cell_dist[current] + 1
			m.max_dist = max(m.max_dist, m.cell_dist[n])
			queue[tail] = i32(n)
			tail += 1
		}
	}
}

@(private)
farthest_room :: proc(m: ^Maze) -> int {
	best, best_dist := -1, i32(-1)
	for i in 0..<m.room_count {
		if i == m.spawn_room {
			continue
		}
		c := room_center_cell(m.rooms[i])
		d := m.cell_dist[cell_index(m, c.x, c.y)]
		if d > best_dist {
			best, best_dist = i, d
		}
	}
	return best
}

// Posts inside ordinary halls may stay standing as pillars: cover from
// cultist bolts and something to dance around.
@(private)
add_pillars :: proc(m: ^Maze, r: ^rng.Rng) {
	for i in 0..<m.room_count {
		if i == m.spawn_room || i == m.exit_room {
			continue
		}
		room := m.rooms[i]
		for ty in 2*room.y+2..=2*(room.y+room.h)-2 {
			for tx in 2*room.x+2..=2*(room.x+room.w)-2 {
				if tx%2 == 0 && ty%2 == 0 && rng.chance(r, 0.6) {
					set_tile(m, tx, ty, false)
				}
			}
		}
	}
}
