package game

import grid "../engine/grid"

TACTICAL_BOMB_FUSE :: 3
TACTICAL_BOMB_DAMAGE :: i32(3)
TACTICAL_BOMBER_RECOVERY :: i32(2)
TACTICAL_BOMB_LIMIT :: 1

Enemy_Path_Goal :: enum {Melee, Archer, Bomber}

@(private)
enemy_terrain_danger :: proc(room: ^Room, cell: grid.Position) -> int {
	danger := 0
	for trap in room.traps { if trap.armed && trap.position == cell { danger += 12 } }
	for object in room.objects {
		if object.kind == .Fire && object.position == cell { danger += 16 }
		if object.detonation_pulse != 0 && explosion_contains_cell(room, object.position, cell) {
			danger += 40 if object.detonation_pulse <= room.pulse_count+2 else 20
		}
	}
	// BOMB MARLEY: a warned column is a blast zone, unless the cell is lit.
	if marley_column_is_warned(room, cell.x) && !marley_cell_is_lit(room, cell) {
		danger += MARLEY_COLUMN_DANGER
	}
	return danger
}

// Foes within this many cells (Manhattan) of a free light make for it.
MARLEY_SHELTER_REACH :: 3
MARLEY_COLUMN_DANGER :: 24

// BOMB MARLEY: a foe off the lights, not beside the player, steps toward the
// nearest free lit cell within MARLEY_SHELTER_REACH: nearest first, then
// row-major, so the same room plans the same steps.
@(private)
tactical_marley_shelter :: proc(room: ^Room, origin: grid.Position,
	positions: ^[MAX_ENEMIES_PER_ROOM]grid.Position, count, index: int) -> (intent: Enemy_Intent, found: bool) {
	if !tactical_marley_active(room) || marley_cell_is_lit(room, origin) { return }
	if abs(origin.x-room.player.position.x)+abs(origin.y-room.player.position.y) <= 1 { return }
	target: grid.Position
	best := MARLEY_SHELTER_REACH+1
	for light in room.marley.lights[:room.marley.light_count] {
		distance := abs(origin.x-light.x)+abs(origin.y-light.y)
		if distance >= best || !planned_cell_is_available(room, positions, count, index, light) { continue }
		best, target = distance, light
	}
	if best > MARLEY_SHELTER_REACH { return }
	intent = make_wait_intent(room, origin)
	for step in ([?]grid.Position{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}) {
		cell := add_position(origin, step)
		if !planned_cell_is_available(room, positions, count, index, cell) { continue }
		distance := abs(cell.x-target.x)+abs(cell.y-target.y)
		if distance >= best { continue }
		best, found = distance, true
		intent.kind, intent.destination, intent.path[0], intent.path_count = .Move, cell, cell, 1
	}
	return
}

@(private)
enemy_has_lob_line :: proc(room: ^Room, origin, target: grid.Position) -> bool {
	path: [MAX_TARGETING_PATH_CELLS]grid.Position
	count, traced := trace_targeting_line(origin, target, &path)
	if !traced { return false }
	_, blocked := targeting_path_blocker(room, origin, &path, count)
	return !blocked
}

@(private)
enemy_position_is_goal :: proc(room: ^Room, cell: grid.Position, goal: Enemy_Path_Goal) -> bool {
	p := room.player.position
	if goal == .Melee { return cell == p }
	distance := abs(p.x-cell.x)+abs(p.y-cell.y)
	if goal == .Archer { return distance >= 2 && distance <= 5 && has_clear_orthogonal_line(room, cell, p) }
	return distance >= 3 && distance <= 5 && enemy_has_lob_line(room, cell, p)
}

// Weighted reverse Dijkstra: the cost of entering fire, traps or a blast zone
// changes the entire route, rather than only rejecting its final step.
// Stable cell/step order keeps identical seeds and replays deterministic.
// Indexed heap holds each frontier cell once; decreasing a distance moves it
// upwards in place. Cost ties use the row-major cell index, as the old scan did.
@(private = "file")
enemy_path_precedes :: proc(a, b: int, distances: []int) -> bool {
	return distances[a] < distances[b] || (distances[a] == distances[b] && a < b)
}

@(private = "file")
enemy_path_heap_up :: proc(heap, slots, distances: []int, start: int) {
	at := start
	for at > 0 {
		parent := (at-1)/2
		if !enemy_path_precedes(heap[at], heap[parent], distances) { break }
		heap[at], heap[parent] = heap[parent], heap[at]
		slots[heap[at]], slots[heap[parent]] = at, parent
		at = parent
	}
}

@(private = "file")
enemy_path_heap_pop :: proc(heap, slots, distances: []int, count: ^int) -> int {
	cell := heap[0]
	count^ -= 1
	slots[cell] = -1
	if count^ == 0 { return cell }
	heap[0] = heap[count^]
	slots[heap[0]] = 0
	at := 0
	for {
		child := at*2+1
		if child >= count^ { break }
		if child+1 < count^ && enemy_path_precedes(heap[child+1], heap[child], distances) { child += 1 }
		if !enemy_path_precedes(heap[child], heap[at], distances) { break }
		heap[at], heap[child] = heap[child], heap[at]
		slots[heap[at]], slots[heap[child]] = at, child
		at = child
	}
	return cell
}

@(private)
rebuild_tactical_enemy_distances :: proc(room: ^Room, distances: []int, goal: Enemy_Path_Goal) {
	visited := make([]bool, len(distances))
	costs := make([]int, len(distances))
	heap := make([]int, len(distances))
	slots := make([]int, len(distances))
	defer delete(visited)
	defer delete(costs)
	defer delete(heap)
	defer delete(slots)
	count := 0
	tiles := &room.level_data.tiles
	for &distance, i in distances {
		cell := grid.Position{i%tiles.width, i/tiles.width}
		distance, slots[i] = -1, -1
		if cell_blocks_movement(room, cell) { visited[i] = true; continue }
		costs[i] = 1+enemy_terrain_danger(room, cell)
		if enemy_position_is_goal(room, cell, goal) {
			distance = 0
			heap[count], slots[i] = i, count
			enemy_path_heap_up(heap, slots, distances, count)
			count += 1
		}
	}
	for count > 0 {
		best := enemy_path_heap_pop(heap, slots, distances, &count)
		score := distances[best]
		visited[best] = true
		cell := grid.Position{best%tiles.width, best/tiles.width}
		for step in ([?]grid.Position{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}) {
			i, ok := grid.index_of(tiles, add_position(cell, step))
			if !ok || visited[i] { continue }
			candidate := score+costs[best]
			if distances[i] >= 0 && candidate >= distances[i] { continue }
			distances[i] = candidate
			if slots[i] < 0 {
				heap[count], slots[i] = i, count
				count += 1
			}
			enemy_path_heap_up(heap, slots, distances, slots[i])
		}
	}
}

@(private = "file")
tactical_ranged_move :: proc(room: ^Room, enemy: ^Enemy, origin: grid.Position,
	positions: ^[MAX_ENEMIES_PER_ROOM]grid.Position, count, index: int, goal: Enemy_Path_Goal) -> Enemy_Intent {
	distances := make([]int, len(room.level_data.tiles.cells))
	defer delete(distances)
	rebuild_tactical_enemy_distances(room, distances, goal)
	start, valid := grid.index_of(&room.level_data.tiles, origin)
	if !valid || distances[start] < 0 { return plan_chaser_intent(room, enemy, origin, positions, count, index) }
	intent := make_wait_intent(room, origin)
	best := distances[start]
	for step in ([?]grid.Position{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}) {
		cell := add_position(origin, step)
		if !planned_cell_is_available(room, positions, count, index, cell) { continue }
		i, _ := grid.index_of(&room.level_data.tiles, cell)
		if distances[i] < 0 { continue }
		score := distances[i]+enemy_terrain_danger(room, cell)
		if score >= best { continue }
		best = score
		intent.kind, intent.destination, intent.path[0], intent.path_count = .Move, cell, cell, 1
	}
	return intent
}

@(private)
plan_tactical_archer :: proc(room: ^Room, enemy: ^Enemy, origin: grid.Position,
	positions: ^[MAX_ENEMIES_PER_ROOM]grid.Position, count, index: int) -> Enemy_Intent {
	if enemy.aim_ready { return make_attack_intent(room, origin, enemy.aim_anchor, enemy.attack) }
	if enemy_position_is_goal(room, origin, .Archer) {
		intent := make_attack_intent(room, origin, room.player.position, enemy.attack)
		intent.windup = true
		return intent
	}
	intent := tactical_ranged_move(room, enemy, origin, positions, count, index, .Archer)
	if intent.kind == .Wait && abs(origin.x-room.player.position.x)+abs(origin.y-room.player.position.y) == 1 {
		return make_attack_intent(room, origin, room.player.position, 1)
	}
	return intent
}

@(private)
tactical_enemy_escape :: proc(room: ^Room, origin: grid.Position,
	positions: ^[MAX_ENEMIES_PER_ROOM]grid.Position, count, index: int) -> (intent: Enemy_Intent, found: bool) {
	best := enemy_terrain_danger(room, origin)
	if best == 0 { return }
	intent = make_wait_intent(room, origin)
	for step in ([?]grid.Position{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}) {
		cell := add_position(origin, step)
		if !planned_cell_is_available(room, positions, count, index, cell) { continue }
		danger := enemy_terrain_danger(room, cell)
		if danger >= best { continue }
		best, found = danger, true
		intent.kind, intent.destination, intent.path[0], intent.path_count = .Move, cell, cell, 1
	}
	return
}

@(private = "file")
make_tactical_bomb_intent :: proc(room: ^Room, origin, anchor: grid.Position, windup: bool) -> Enemy_Intent {
	intent := make_wait_intent(room, origin)
	intent.kind, intent.destination, intent.windup = .Bombard, anchor, windup
	intent.damage = TACTICAL_BOMB_DAMAGE
	for y in anchor.y-1..=anchor.y+1 { for x in anchor.x-1..=anchor.x+1 {
		cell := grid.Position{x, y}
		if explosion_contains_cell(room, anchor, cell) {
			intent.threatened_cells[intent.threatened_cell_count] = cell
			intent.threatened_cell_count += 1
		}
	} }
	return intent
}

@(private)
plan_tactical_bomber :: proc(room: ^Room, enemy: ^Enemy, origin: grid.Position,
	positions: ^[MAX_ENEMIES_PER_ROOM]grid.Position, count, index: int, reserved: []grid.Position) -> Enemy_Intent {
	if enemy.bomb_ready {
		// A shove or a changed board may make this throw fail at resolution.
		// Never retarget the landing cell after the preparation was shown.
		return make_tactical_bomb_intent(room, origin, enemy.bomb_anchor, false)
	}
	if enemy.archetype == .Demolitionist {
		best_id := max(u32)
		anchor: grid.Position
		for object in room.objects {
			if object.kind != .Barrel || object.detonation_pulse != 0 ||
			   !explosion_contains_cell(room, object.position, room.player.position) ||
			   explosion_contains_cell(room, object.position, origin) ||
			   !enemy_has_lob_line(room, origin, object.position) { continue }
			if object.id < best_id { best_id, anchor = object.id, object.position }
		}
		if best_id != max(u32) {
			intent := make_attack_intent(room, origin, anchor, 1)
			intent.target_object = best_id
			return intent
		}
	}
	pending := 0
	for other in room.enemies { if other.id != enemy.id && other.bomb_ready { pending += 1 } }
	if active_bomb_count(room)+len(reserved)+pending < TACTICAL_BOMB_LIMIT &&
	   len(room.objects) < MAX_GRID_OBJECTS_PER_ROOM &&
	   enemy_position_is_goal(room, origin, .Bomber) &&
	   bomb_cell_is_available(room, room.player.position) {
		return make_tactical_bomb_intent(room, origin, room.player.position, true)
	}
	return tactical_ranged_move(room, enemy, origin, positions, count, index, .Bomber)
}

@(private)
resolve_tactical_enemy_push :: proc(room: ^Room, source: Entity_Ref, intent: ^Enemy_Intent,
	report: ^Action_Report, pulse: ^Pulse_Report) {
	if !intent.push || room.phase != .Combat { return }
	hurt_player := false
	for event in report.events.events[:report.events.count] {
		if event.kind == .Damaged && event.target == PLAYER_ENTITY && event.source == source && event.amount > 0 { hurt_player = true }
	}
	if !hurt_player { return }
	// A full block prevents the displacement; partial blocks still give ground.
	from, alive := entity_position(room, source)
	if !alive { return }
	step, _, aligned := orthogonal_step_and_distance(from, room.player.position)
	if !aligned { return }
	destination := add_position(room.player.position, step)
	query := query_entity_movement(room, PLAYER_ENTITY, destination)
	if !movement_query_is_clear(&query) { return }
	action := make_action(.Trigger, source, entity_target(PLAYER_ENTITY), .Opponent)
	added := add_effect(&action, move_effect(PLAYER_ENTITY, destination))
	assert(added)
	pushed := resolve_action(room, &action)
	merge_action_report(pulse, &pushed)
}
