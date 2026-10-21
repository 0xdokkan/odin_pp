package game

import grid "../engine/grid"

// INONDAZIONE. The player drops the card on a cell round him: the wave goes
// the way of the main axis from him to that cell (a tie goes along the row,
// east or west), one of the four directions. It starts at the wall behind it
// and sweeps the whole board to the wall in front, where it ends. Every foe on
// the floor it touches is pushed FLOOD_BASE_PUSH cells (+1 a card upgrade, +1
// on the tick) the way the wave goes, under the game's push rules: a wall, an
// obstacle, a blocking object or a body stops the push short, and a pool, a
// trap or a hazard acts on every cell the foe enters. It hurts nobody and
// every fire on the floor goes out, the player's Incendio and the board's own
// Fire objects, before anybody is pushed, so that no foe lands in one.
//
// All of it resolves at once as one committed action, in the order the wave
// reaches the foes' ranks from the far end: the head of a file moves first, so
// a file with room in front moves together, and every foe is pushed once. The
// player, the board's objects, the Lazzo's foe and the Pinball's ball are
// never moved. The sweep itself is the presentation's: it reads the events.

FLOOD_MAX_UPGRADE_LEVEL :: i32(3)
// The push of an unimproved card.
FLOOD_BASE_PUSH :: i32(1)
// The cells a flood's steam can cover (the sweep's cosmetic events).
FLOOD_STEAM_EVENT_LIMIT :: 96
// The wave's events (its sweep, its steam, the pushes and what they trigger)
// are shown together (Game_Event.visual_group).
FLOOD_VISUAL_GROUP :: u32(0x464C_0D00)

@(private)
flood_effect :: proc(cells: i32, aim: grid.Position) -> Effect {
	return {kind = .Flood, target = PLAYER_ENTITY, amount = cells, destination = aim}
}

// The way a wave goes for a card dropped on `aim` by a player standing on
// `from`; false when the two are the same cell.
flood_direction :: proc(from, aim: grid.Position) -> (direction: Move_Direction, ok: bool) {
	dx, dy := aim.x-from.x, aim.y-from.y
	if dx == 0 && dy == 0 { return }
	if abs(dx) >= abs(dy) { return .East if dx > 0 else .West, true }
	return .South if dy > 0 else .North, true
}

// How many cells from the wall the wave starts at a cell lies, along `direction`.
flood_progress :: proc(room: ^Room, direction: Move_Direction, cell: grid.Position) -> int {
	tiles := &room.level_data.tiles
	switch direction {
	case .East: return cell.x
	case .West: return tiles.width-1-cell.x
	case .South: return cell.y
	case .North: return tiles.height-1-cell.y
	}
	return 0
}

// How many cells the wave runs: the board's length along `direction`.
flood_length :: proc(room: ^Room, direction: Move_Direction) -> int {
	if room == nil || room.level_data == nil { return 0 }
	return room.level_data.tiles.width if direction == .East || direction == .West else room.level_data.tiles.height
}

// Whether a flood can be loosed now, and where the player's aim sends it.
@(private)
flood_can_begin :: proc(room: ^Room, aim: grid.Position) -> bool {
	if room == nil || room.player == nil || room.level_data == nil || room.phase != .Combat { return false }
	_, ok := flood_direction(room.player.position, aim)
	return ok
}

// The cells a fire burns over, one of each: the centre and its arms.
@(private = "file")
flood_fire_cells :: proc(fire: Ground_Fire, cells: ^[dynamic]grid.Position) {
	append(cells, fire.center)
	steps := GROUND_ARM_STEPS
	for step, direction in steps {
		for reach in 1..=int(fire.arms[direction]) { append(cells, grid.Position{fire.center.x+step.x*reach, fire.center.y+step.y*reach}) }
	}
}

// Puts out every fire on the floor, and records where the steam rises (one
// event a cell, the first FLOOD_STEAM_EVENT_LIMIT: cosmetic, so a full log
// drops it). Returns how many fires went out.
@(private = "file")
flood_put_out_fires :: proc(room: ^Room, report: ^Action_Report) -> (out: int) {
	steam: [dynamic]grid.Position
	defer delete(steam)
	for fire in room.ground.fires[:room.ground.fire_count] { flood_fire_cells(fire, &steam) }
	out += room.ground.fire_count
	for &fire in room.ground.fires { fire = {} }
	room.ground.fire_count = 0
	// The board's own fires: objects that burn where they lie.
	for index := len(room.objects)-1; index >= 0; index -= 1 {
		if room.objects[index].kind != .Fire { continue }
		append(&steam, room.objects[index].position)
		remove_grid_object(room, index)
		out += 1
	}
	seen: [dynamic]grid.Position
	defer delete(seen)
	events := 0
	for cell in steam {
		duplicate := false
		for known in seen { if known == cell { duplicate = true; break } }
		if duplicate { continue }
		append(&seen, cell)
		if events >= FLOOD_STEAM_EVENT_LIMIT { continue }
		record_event(&report.events, {kind = .Fire_Extinguished, source = PLAYER_ENTITY, target = SYSTEM_ENTITY,
			from_position = cell, to_position = cell, card_definition = .Flood})
		events += 1
	}
	return
}

// Pushes `id` up to `cells` cells along `direction`, one cell at a time, short
// of whatever stops it. Returns the cells it went.
@(private = "file")
flood_push_enemy :: proc(room: ^Room, id: u32, direction: Move_Direction, cells: i32, report: ^Action_Report) -> (moved: i32) {
	step := direction_offset(direction)
	for _ in 0..<cells {
		position, present := entity_position(room, enemy_entity(id))
		if !present || room.phase != .Combat { return }
		to := grid.Position{position.x+step.x, position.y+step.y}
		query := query_entity_movement(room, enemy_entity(id), to)
		if !movement_query_is_clear(&query) { return }
		apply_movement_effect(room, PLAYER_ENTITY, move_effect(enemy_entity(id), to), report)
		moved += 1
	}
	return
}

// The loosed wave (apply_effect). `cells` is the push, `aim` the cell the card
// was dropped on.
@(private)
begin_flood :: proc(room: ^Room, aim: grid.Position, cells: i32, report: ^Action_Report) -> bool {
	if report == nil || cells <= 0 || !flood_can_begin(room, aim) { return false }
	direction, _ := flood_direction(room.player.position, aim)
	tiles := &room.level_data.tiles
	first_event := report.events.count
	// From the middle of the wall behind to the middle of the wall in front;
	// `duration` is the direction (Move_Direction) and `amount` the push.
	first, last: grid.Position
	middle := grid.Position{tiles.width/2, tiles.height/2}
	switch direction {
	case .East: first, last = {0, middle.y}, {tiles.width-1, middle.y}
	case .West: first, last = {tiles.width-1, middle.y}, {0, middle.y}
	case .South: first, last = {middle.x, 0}, {middle.x, tiles.height-1}
	case .North: first, last = {middle.x, tiles.height-1}, {middle.x, 0}
	}
	record_report_event(report, {kind = .Flood_Swept, source = PLAYER_ENTITY, target = SYSTEM_ENTITY, from_position = first,
		to_position = last, amount = cells, duration = i32(direction), card_definition = .Flood})
	flood_put_out_fires(room, report)

	// The foes on the floor, the head of the wave's far end first (the largest
	// progress), then by ID: a file with room in front moves together.
	ids: [MAX_ENEMIES_PER_ROOM]u32
	rank: [MAX_ENEMIES_PER_ROOM]int
	count := 0
	for enemy in room.enemies {
		if enemy_is_out_of_play(room, enemy.id) || count >= MAX_ENEMIES_PER_ROOM { continue }
		ids[count], rank[count] = enemy.id, flood_progress(room, direction, enemy.position)
		count += 1
	}
	for i in 1..<max(count, 1) {
		id, at, key := ids[i], i, rank[i]
		for at > 0 && (rank[at-1] < key || (rank[at-1] == key && ids[at-1] > id)) {
			ids[at], rank[at] = ids[at-1], rank[at-1]
			at -= 1
		}
		ids[at], rank[at] = id, key
	}
	for index in 0..<count {
		flood_push_enemy(room, ids[index], direction, cells, report)
	}
	// One show: the pushes carry the card, so that the board times each to the
	// wave's arrival.
	for &event in report.events.events[first_event:report.events.count] {
		event.visual_group = FLOOD_VISUAL_GROUP
		if event.kind == .Moved || event.kind == .Movement_Step { event.card_definition = .Flood }
	}
	return true
}
