package level

import grid "../engine/grid"

// THE CAVES (Fase 5 of docs/piano-griglia.md): a small map of its own, two or three rooms in a row joined by
// narrow galleries, entered through an arch on the open map and left through the same arch. A pure function of a
// seed, so a cave is the same every time it is entered (what changes in it is kept by the expedition).
//
//   ##################################
//   #....#####........#######.....####      the arrival is at the west end, the secret in a niche at the east end;
//   #....................................   the foes wait in the rooms between.
//
// The plan is drawn on a CAVE_WIDTH by CAVE_HEIGHT board, or a smaller one (cave_plan_sized: the Far West's caves, Fase 5 of
// docs/piano-profondita.md); its border is rock.

CAVE_WIDTH  :: 34
CAVE_HEIGHT :: 18
CAVE_MAX_ROOMS :: 3
// The smallest board: two rooms.
CAVE_MIN_WIDTH  :: 22
CAVE_MIN_HEIGHT :: 12

Cave_Plan :: struct {
	// '#' rock, '.' floor.
	rows:    [CAVE_HEIGHT][CAVE_WIDTH]u8,
	// The board it is drawn on; the rest of rows is rock.
	width, height: int,
	rooms:   int,
	// Each room's cells, minimum and maximum corner (inclusive).
	boxes:   [CAVE_MAX_ROOMS][2]grid.Position,
	// Where the way out is (the first floor cell inside the west end), and where the secret lies.
	arrival: grid.Position,
	secret:  grid.Position,
	// A group waits at the middle of each room that has foes, `foes` of them.
	anchors: [CAVE_MAX_ROOMS]grid.Position,
	foes:    [CAVE_MAX_ROOMS]int,
	groups:  int,
}

@(private = "file")
cave_hash :: proc(seed: u64, salt: u64) -> u64 {
	z := seed+salt*0x9E3779B97F4A7C15+0x9E3779B97F4A7C15
	z = (z ~ (z >> 30))*0xBF58476D1CE4E5B9
	z = (z ~ (z >> 27))*0x94D049BB133111EB
	return z ~ (z >> 31)
}

@(private = "file")
cave_pick :: proc(seed: u64, salt: u64, low, high: int) -> int {
	return low+int(cave_hash(seed, salt)%u64(high-low+1))
}

@(private = "file")
cave_carve :: proc(plan: ^Cave_Plan, low, high: grid.Position) {
	for y in low.y..=high.y { for x in low.x..=high.x { plan.rows[y][x] = '.' } }
}

cave_plan :: proc(seed: u64) -> Cave_Plan {
	return cave_plan_sized(seed, CAVE_WIDTH, CAVE_HEIGHT)
}

// A plan on a board of `width` by `height` (between the smallest and CAVE_WIDTH by CAVE_HEIGHT): three rooms only on the
// whole board.
cave_plan_sized :: proc(seed: u64, board_width, board_height: int) -> (plan: Cave_Plan) {
	width, height := clamp(board_width, CAVE_MIN_WIDTH, CAVE_WIDTH), clamp(board_height, CAVE_MIN_HEIGHT, CAVE_HEIGHT)
	plan.width, plan.height = width, height
	for y in 0..<CAVE_HEIGHT { for x in 0..<CAVE_WIDTH { plan.rows[y][x] = '#' } }
	plan.rooms = 2+int(cave_hash(seed, 1)%2) if width == CAVE_WIDTH else 2
	// The rooms' columns: [x0, x1] each, with a gallery of three or four cells between one and the next.
	columns: [CAVE_MAX_ROOMS][2]int
	if plan.rooms == 2 {
		first := cave_pick(seed, 2, 10, 13) if width == CAVE_WIDTH else cave_pick(seed, 2, width/2-6, width/2-4)
		columns[0] = {2, first}
		columns[1] = {first+5, width-6}
	} else {
		first := cave_pick(seed, 2, 6, 7)
		second := cave_pick(seed, 3, 7, 8)
		columns[0] = {2, first}
		columns[1] = {first+4, first+3+second}
		columns[2] = {first+second+7, CAVE_WIDTH-6}
	}
	// Each room's rows: between 7 and 12 tall, somewhere in the board; the galleries run along the shared middle.
	middles: [CAVE_MAX_ROOMS]int
	for index in 0..<plan.rooms {
		tall := cave_pick(seed, u64(10+index), 7, min(12, height-4))
		top := cave_pick(seed, u64(20+index), 2, height-2-tall)
		plan.boxes[index] = {{x = columns[index][0], y = top}, {x = columns[index][1], y = top+tall-1}}
		cave_carve(&plan, plan.boxes[index][0], plan.boxes[index][1])
		middles[index] = top+tall/2
	}
	// The galleries, two cells wide, from a room's middle to the next room's.
	for index in 0..<plan.rooms-1 {
		x0, x1 := columns[index][1], columns[index+1][0]
		y0, y1 := middles[index], middles[index+1]
		// Along the gallery: across from the first room's middle, up or down at the middle column, across again.
		mid := (x0+x1)/2
		cave_carve(&plan, {x = x0, y = y0}, {x = mid, y = y0+1})
		cave_carve(&plan, {x = mid, y = min(y0, y1)}, {x = mid+1, y = max(y0, y1)+1})
		cave_carve(&plan, {x = mid, y = y1}, {x = x1, y = y1+1})
	}
	// A few pillars in the rooms, never against a wall nor beside each other, so that no pocket closes.
	for index in 0..<plan.rooms {
		box := plan.boxes[index]
		for attempt in 0..<4 {
			px := cave_pick(seed, u64(40+index*8+attempt), box[0].x+2, box[1].x-2)
			py := cave_pick(seed, u64(80+index*8+attempt), box[0].y+2, box[1].y-2)
			if box[1].x-box[0].x < 5 || box[1].y-box[0].y < 5 { continue }
			clear := true
			for oy in -1..=1 { for ox in -1..=1 { if plan.rows[py+oy][px+ox] != '.' { clear = false } } }
			// Keep the galleries' mouths and the room's middle row free.
			if abs(py-middles[index]) <= 1 { clear = false }
			if clear { plan.rows[py][px] = '#' }
		}
	}
	// The way out: the first cell of the first room on its middle row.
	plan.arrival = {x = plan.boxes[0][0].x, y = middles[0]}
	// The secret: a niche cut into the east wall of the last room, two cells tall and three deep, at its middle.
	last := plan.rooms-1
	niche_y := middles[last]
	cave_carve(&plan, {x = plan.boxes[last][1].x+1, y = niche_y}, {x = width-3, y = niche_y+1})
	plan.secret = {x = width-3, y = niche_y}
	// The foes: none in the first room when there are three; the others each have a group at their middle.
	for index in 0..<plan.rooms {
		if plan.rooms == 3 && index == 0 { continue }
		box := plan.boxes[index]
		// In the first room of two the group stands by the gallery, a good way from the arrival.
		anchor_x := box[1].x-1 if index == 0 else (box[0].x+box[1].x)/2
		plan.anchors[plan.groups] = {x = anchor_x, y = middles[index]}
		plan.foes[plan.groups] = 2+int(cave_hash(seed, u64(100+index))%2)+(1 if index == last else 0)
		plan.groups += 1
	}
	return
}

cave_plan_at :: proc(plan: ^Cave_Plan, x, y: int) -> u8 {
	if x < 0 || y < 0 || x >= plan.width || y >= plan.height { return '#' }
	return plan.rows[y][x]
}

// Writes the plan onto `data` with its top left corner at `origin`: floor and rock, flat. False if it does not fit.
cave_stamp :: proc(data: ^Level, origin: grid.Position, plan: ^Cave_Plan) -> bool {
	if data == nil || origin.x < 0 || origin.y < 0 || origin.x+CAVE_WIDTH > data.tiles.width || origin.y+CAVE_HEIGHT > data.tiles.height { return false }
	for y in 0..<CAVE_HEIGHT {
		for x in 0..<CAVE_WIDTH {
			cell := grid.offset(origin, x, y)
			_ = set_tile(data, cell, {.Wall if plan.rows[y][x] == '#' else .Floor})
		}
	}
	return true
}
