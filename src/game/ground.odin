package game

import grid "../engine/grid"

// POZZA DI VELENO and INCENDIO: what the player pours or lights on the floor
// of a tactical room. The ground is no Grid_Object: it lies under everything,
// takes no object slot, blocks nothing and never hurts the player. It belongs
// to the room and goes with it.
//
// A pool gives an enemy that enters one of its cells, by any movement (a step,
// each cell of a charge, a push or a pull, a landing), its Veleno: the stacks
// of the card that poured it. Pools side by side are one area. After every
// pool the room's open floor (walkable, no cover, no blocking object, not yet
// pool) splits into 4-neighbour areas: the largest is the outside, and every
// other area that the pools close (it touches one) fills at once, poisoning
// whoever stands there. Actors never close an area.
//
// A fire grows as a plus at each new window, when Bruciatura bites: its arms
// reach one cell, then two, three, four; an arm stops for good at a wall or a
// blocking object. At the fifth new window, when it would reach five, it goes
// out. An enemy that enters a burning cell, or stands on one as it catches,
// gets the fire's Bruciatura.

MAX_GROUND_FIRES :: 32
// The windows a fire grows; it goes out at the next one.
GROUND_FIRE_STAGES :: i32(4)

// North, east, south, west: Move_Direction's order.
GROUND_ARM_STEPS :: [Move_Direction]grid.Position{.North = {x = 0, y = -1}, .East = {x = 1, y = 0}, .South = {x = 0, y = 1}, .West = {x = -1, y = 0}}

Ground_Fire :: struct {
	id: u32,
	center: grid.Position,
	// The windows it has grown (0: the centre alone), how far each arm reached
	// and the arms a blocker stopped.
	stage: i32,
	arms: [Move_Direction]i32,
	stopped: bit_set[Move_Direction; u8],
	// The Bruciatura it gives.
	burn: i32,
}

Ground_State :: struct {
	// Per cell, row-major as the level's tiles: the Veleno a pool gives an
	// enemy entering it, 0 where the floor is dry. Made with the room.
	pool: []i32,
	fires: [MAX_GROUND_FIRES]Ground_Fire,
	fire_count: int,
	next_fire_id: u32,
}


@(private)
ground_kind_is_valid :: proc(kind: Status_Kind) -> bool {
	return kind == .Poison || kind == .Burn
}

place_ground_effect :: proc(cell: grid.Position, kind: Status_Kind, amount: i32) -> Effect {
	return {kind = .Place_Ground, target = PLAYER_ENTITY, destination = cell, status = kind, amount = amount}
}

@(private)
ground_index :: proc(room: ^Room, cell: grid.Position) -> (index: int, ok: bool) {
	if room == nil || room.level_data == nil { return }
	index, ok = grid.index_of(&room.level_data.tiles, cell)
	return index, ok && index < len(room.ground.pool)
}

// The Veleno of the pool on `cell` (0: dry, or off the board).
ground_pool_at :: proc(room: ^Room, cell: grid.Position) -> i32 {
	index, ok := ground_index(room, cell)
	return room.ground.pool[index] if ok else 0
}

ground_fire_covers :: proc(fire: Ground_Fire, cell: grid.Position) -> bool {
	if cell == fire.center { return true }
	steps := GROUND_ARM_STEPS
	for step, direction in steps {
		dx, dy := cell.x-fire.center.x, cell.y-fire.center.y
		reach := dx*step.x+dy*step.y
		if reach >= 1 && reach <= int(fire.arms[direction]) && dx == step.x*reach && dy == step.y*reach { return true }
	}
	return false
}

// The strongest fire burning on `cell` (0: none).
@(private)
ground_burn_at :: proc(room: ^Room, cell: grid.Position) -> (burn: i32) {
	if room == nil { return }
	for fire in room.ground.fires[:room.ground.fire_count] {
		if ground_fire_covers(fire, cell) { burn = max(burn, fire.burn) }
	}
	return
}

// A cell a pool or a fire may be poured on: walkable floor in a fight, no
// cover, no object of any kind, no enemy and not the player's own cell. Traps
// and the exit take them.
@(private = "file")
ground_cell_is_free :: proc(room: ^Room, cell: grid.Position) -> bool {
	if room == nil || room.player == nil || room.phase != .Combat ||
	   !base_cell_is_walkable(room, cell) || obstacle_at(room, cell) || room.player.position == cell { return false }
	if _, found := object_index_at(room, cell); found { return false }
	if _, found := enemy_index_at(room, cell); found { return false }
	return true
}

// A pool needs a dry cell; a fire a free slot (a fire may burn over a pool or
// another fire).
@(private)
ground_can_place :: proc(room: ^Room, kind: Status_Kind, cell: grid.Position) -> bool {
	if !ground_kind_is_valid(kind) || !ground_cell_is_free(room, cell) { return false }
	if kind == .Poison {
		_, inside := ground_index(room, cell)
		return inside && ground_pool_at(room, cell) == 0
	}
	return room.ground.fire_count < MAX_GROUND_FIRES
}

// Floor a pool can still spread over: walkable, no cover, no blocking object,
// not yet pool. Actors never stop it.
@(private = "file")
ground_cell_is_open :: proc(room: ^Room, cell: grid.Position, anchor: grid.Position) -> bool {
	return cell != anchor && !cell_blocks_movement(room, cell) && ground_pool_at(room, cell) == 0
}

// The cells a pool poured on `anchor` adds, the anchor first: the anchor, then
// every area of open floor it closes. The open floor splits into 4-neighbour
// areas; the largest is the outside (areas tied for the largest all are); any
// other area touching a pool fills. Row-major order, so the same board gives
// the same cells. The preview and the pouring share it; nothing changes here.
ground_pool_fill :: proc(room: ^Room, anchor: grid.Position, cells: ^[dynamic]grid.Position) {
	if room == nil || room.level_data == nil || cells == nil { return }
	if _, inside := ground_index(room, anchor); !inside { return }
	append(cells, anchor)
	tiles := &room.level_data.tiles
	count := len(tiles.cells)
	label := make([]i32, count)
	defer delete(label)
	queue := make([]int, count)
	defer delete(queue)
	sizes: [dynamic]int
	defer delete(sizes)
	touches: [dynamic]bool
	defer delete(touches)
	for &value in label { value = -1 }
	steps := GROUND_ARM_STEPS
	for start in 0..<count {
		cell := grid.Position{x = start%tiles.width, y = start/tiles.width}
		if label[start] >= 0 || !ground_cell_is_open(room, cell, anchor) { continue }
		area := i32(len(sizes))
		append(&sizes, 0)
		append(&touches, false)
		label[start] = area
		head, tail := 0, 1
		queue[0] = start
		for head < tail {
			at := queue[head]
			head += 1
			sizes[area] += 1
			here := grid.Position{x = at%tiles.width, y = at/tiles.width}
			for step in steps {
				next := grid.offset(here, step.x, step.y)
				index, ok := grid.index_of(tiles, next)
				if !ok { continue }
				if next == anchor || room.ground.pool[index] > 0 { touches[area] = true; continue }
				if label[index] >= 0 || !ground_cell_is_open(room, next, anchor) { continue }
				label[index] = area
				queue[tail] = index
				tail += 1
			}
		}
	}
	largest := 0
	for size in sizes { largest = max(largest, size) }
	for index in 0..<count {
		area := label[index]
		if area < 0 || sizes[area] == largest || !touches[area] { continue }
		append(cells, grid.Position{x = index%tiles.width, y = index/tiles.width})
	}
}

// Where a fire lit on `center` would burn over its life: its arms as long as
// they will grow, stopping where a blocker stands now. The preview's.
ground_fire_reach :: proc(room: ^Room, center: grid.Position) -> (fire: Ground_Fire) {
	fire.center = center
	if room == nil { return }
	steps := GROUND_ARM_STEPS
	for step, direction in steps {
		for fire.arms[direction] < GROUND_FIRE_STAGES {
			reach := int(fire.arms[direction])+1
			if cell_blocks_movement(room, grid.offset(center, step.x*reach, step.y*reach)) { break }
			fire.arms[direction] += 1
		}
	}
	fire.stage = GROUND_FIRE_STAGES
	return
}

// A status from the ground: a System's, as the board's devices give theirs,
// so the player's relics and reactions take no part in it.
@(private = "file")
ground_apply_status :: proc(room: ^Room, entity: Entity_Ref, kind: Status_Kind, potency: i32, report: ^Action_Report) -> bool {
	if room == nil || report == nil || potency <= 0 || !entity_exists(room, entity) || !can_apply_status(room, entity, kind) { return false }
	applied, _ := apply_status(room, entity, kind, potency, 0)
	if !applied { return false }
	status, found := status_for_entity(room, entity, kind)
	assert(found)
	report.statuses_applied += 1
	record_report_event(report, {kind = .Status_Applied, source = SYSTEM_ENTITY, target = entity, amount = status.potency, status = kind})
	return true
}

// Pours a pool (`kind` Poison) or lights a fire (Burn) on `cell`, its stacks
// `amount`. A pool's closed areas fill at once: every enemy standing on one
// gets its Veleno.
@(private)
place_ground :: proc(room: ^Room, kind: Status_Kind, cell: grid.Position, amount: i32, report: ^Action_Report) -> bool {
	if report == nil || amount <= 0 || !ground_can_place(room, kind, cell) { return false }
	if kind == .Burn {
		room.ground.next_fire_id += 1
		room.ground.fires[room.ground.fire_count] = {id = room.ground.next_fire_id, center = cell, burn = amount}
		room.ground.fire_count += 1
		return true
	}
	filled: [dynamic]grid.Position
	defer delete(filled)
	ground_pool_fill(room, cell, &filled)
	for at in filled {
		index, _ := ground_index(room, at)
		room.ground.pool[index] = amount
	}
	// The anchor is free; the cells filled with it may hold enemies.
	for at in filled[1:] {
		if enemy_index, found := enemy_index_at(room, at); found {
			ground_apply_status(room, enemy_entity(room.enemies[enemy_index].id), .Poison, amount, report)
		}
	}
	return true
}

// Every cell an enemy enters passes here (apply_movement_effect: a step, each
// cell of a charge, a push or a pull, a teleport's landing): a pool gives its
// Veleno, a fire its Bruciatura. The player is never touched, nor a foe the
// Lazzo holds in the air.
@(private)
trigger_ground_on_entry :: proc(room: ^Room, mover: Entity_Ref, report: ^Action_Report) {
	if room == nil || report == nil || room.phase != .Combat || mover.kind != .Enemy || enemy_is_out_of_play(room, mover.id) { return }
	position, present := entity_position(room, mover)
	if !present { return }
	ground_apply_status(room, mover, .Poison, ground_pool_at(room, position), report)
	ground_apply_status(room, mover, .Burn, ground_burn_at(room, position), report)
}

// A new window (tactical_expire_window, after Bruciatura has bitten): each
// fire grows its arms a cell, an arm stopping for good at a blocker, and a
// fire that has grown its four goes out. An enemy standing where the fire
// catches gets its Bruciatura once, however many fires reach it; it first
// bites at the next window, as for one that walks in.
grow_ground_fires :: proc(room: ^Room, pulse: ^Pulse_Report) {
	if room == nil || pulse == nil || room.phase != .Combat || room.ground.fire_count == 0 { return }
	ids, count := enemy_ids_in_planning_order(room)
	burning: [MAX_ENEMIES_PER_ROOM]bool
	for id, at in ids[:count] {
		index, _ := enemy_index_by_id(room, id)
		burning[at] = ground_burn_at(room, room.enemies[index].position) > 0
	}
	kept := 0
	steps := GROUND_ARM_STEPS
	for index in 0..<room.ground.fire_count {
		fire := room.ground.fires[index]
		if fire.stage >= GROUND_FIRE_STAGES { continue }
		fire.stage += 1
		for step, direction in steps {
			if direction in fire.stopped { continue }
			reach := int(fire.arms[direction])+1
			if cell_blocks_movement(room, grid.offset(fire.center, step.x*reach, step.y*reach)) {
				fire.stopped += {direction}
				continue
			}
			fire.arms[direction] += 1
		}
		room.ground.fires[kept] = fire
		kept += 1
	}
	for index in kept..<room.ground.fire_count { room.ground.fires[index] = {} }
	room.ground.fire_count = kept
	action := make_action(.Trigger, SYSTEM_ENTITY)
	for id, at in ids[:count] {
		index, _ := enemy_index_by_id(room, id)
		burn := ground_burn_at(room, room.enemies[index].position)
		// A foe out of play is out of the fire's reach.
		if burning[at] || burn <= 0 || enemy_is_out_of_play(room, id) { continue }
		added := add_effect(&action, apply_status_effect(enemy_entity(id), .Burn, burn, 0))
		assert(added)
	}
	if action.effect_count == 0 { return }
	report := resolve_action(room, &action)
	merge_action_report(pulse, &report)
}

// The ground as it was poured: nothing on the floor. A new room starts with
// its own (create_room); the mechanics lab clears its arena with this.
clear_ground :: proc(room: ^Room) {
	if room == nil { return }
	for &value in room.ground.pool { value = 0 }
	pool := room.ground.pool
	room.ground = {pool = pool}
}
