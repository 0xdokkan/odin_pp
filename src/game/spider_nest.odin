package game

import grid "../engine/grid"

// NIDO DI RAGNI (docs/piano-ia.md, Fase 9): set down like the Cannone, on a free cell one to three cells away, two at
// most. It stops the steps, not the sight; it lives 20 world beats (`life`), its spiderlings bite (`power`), and `radius`
// counts the blows it took (the board draws them as tears).
//
// - A spiderling leaves at once, then one every two beats. It runs at 4 cells a second, around the walls by the
//   shortest way (in steps, not as the crow flies) and through bodies, to the nearest foe; there it bites and dies.
//   Its foe dead, it goes to the nearest one; with none it waits; 5 seconds without arriving and it dies. Nothing can
//   strike it and nothing on the ground touches it.
// - Every blow of a foe that takes the nest's cell takes 3 seconds off it, once a blow, whatever its damage and even a
//   blow aimed at the player.
// - The bait: a foe next to a nest and not next to the player strikes the nest (intent.target_object).
//
// The spiderlings are no objects of the grid: a cell holds one object, and they run through bodies and over each
// other. They live in the player's clock (Spider_Swarm, Tactical_State), so the room keeps its size, and run on the
// world's seconds as the arrows do (fly_enemy_flights, a world command).

SPIDER_NEST_SECONDS :: i32(20)
SPIDER_BITE_DAMAGE :: i32(2)
SPIDER_NEST_MAX_UPGRADE_LEVEL :: i32(2)
MAX_SPIDER_NESTS :: 2
// A spiderling every this many beats.
SPIDER_BORN_BEATS :: i32(2)
SPIDER_NEST_BLOW_SECONDS :: i32(3)
SPIDER_CELLS_A_SECOND :: f32(4)
SPIDER_LIFE_SECONDS :: f32(5)
MAX_SPIDERLINGS :: 12
// How far a spiderling looks for its foe, each way, in cells.
SPIDER_REACH :: 24
@(private = "file")
SPIDER_WINDOW :: 2*SPIDER_REACH+1
// A spiderling's steps and bite in a world command's log: one flight never fills it.
@(private = "file")
SPIDER_EVENT_HEADROOM :: 12

Spiderling :: struct {
	// The cell it stands on, the cell it came from (for the drawing) and how far along the way to the next it is.
	position, from: grid.Position,
	travelled: f32,
	age: f32,
	bite: i32,
	// Its nest (it may be gone: the spiderling runs on).
	nest: u32,
}

Spider_Swarm :: struct {
	items: [MAX_SPIDERLINGS]Spiderling,
	count: i32,
	// The world's seconds waiting to be run out.
	pending: f32,
}

@(private)
place_spider_nest_effect :: proc(bite, seconds: i32) -> Effect {
	return {kind = .Place_Spider_Nest, target = PLAYER_ENTITY, amount = bite, duration = seconds}
}

spider_nest_count :: proc(room: ^Room) -> int { return emplacement_count(room, .Spider_Nest) }

// Sets a nest down: the first spiderling leaves at once.
@(private)
place_spider_nest :: proc(room: ^Room, cell: grid.Position, bite, seconds: i32, report: ^Action_Report) -> bool {
	if !place_emplacement(room, .Spider_Nest, cell, bite, seconds, 0, .North, false, report) { return false }
	nest := room.objects[len(room.objects)-1]
	spider_hatch(room, nest, &report.events)
	return true
}

@(private = "file")
spider_hatch :: proc(room: ^Room, nest: Grid_Object, events: ^Event_Log) {
	swarm := &room.player.tactical.spiders
	if swarm.count >= MAX_SPIDERLINGS { return }
	swarm.items[swarm.count] = {position = nest.position, from = nest.position, bite = nest.power, nest = nest.id}
	swarm.count += 1
	record_event(events, {kind = .Spider_Hatched, source = object_entity(nest.id), target = object_entity(nest.id),
		from_position = nest.position, to_position = nest.position, amount = nest.life})
}

// Takes `seconds` off a nest; at nothing it is gone.
@(private = "file")
spider_nest_loses :: proc(room: ^Room, index: int, seconds: i32, events: ^Event_Log) {
	nest := &room.objects[index]
	nest.life -= seconds
	if nest.life > 0 { return }
	id, cell := nest.id, nest.position
	remove_grid_object(room, index)
	record_event(events, {kind = .Spider_Nest_Closed, source = SYSTEM_ENTITY, target = object_entity(id),
		from_position = cell, to_position = cell})
}

// Each nest's beat, from the pulse (emplacement_beat): a beat less, and a spiderling every second one.
@(private)
spider_nest_beat :: proc(room: ^Room, pulse: ^Pulse_Report) {
	ids: [MAX_SPIDER_NESTS]u32
	count := 0
	for object in room.objects { if object.kind == .Spider_Nest && count < len(ids) { ids[count] = object.id; count += 1 } }
	for id in ids[:count] {
		index, found := object_index_by_id(room, id)
		if !found { continue }
		spider_nest_loses(room, index, 1, &pulse.events)
		index, found = object_index_by_id(room, id)
		if found && room.objects[index].life%SPIDER_BORN_BEATS == 0 { spider_hatch(room, room.objects[index], &pulse.events) }
	}
}

// A foe's blow takes the nest at `index`: 3 seconds off, whatever its damage.
@(private)
spider_nest_struck :: proc(room: ^Room, index: int, source: Entity_Ref, events: ^Event_Log) {
	room.objects[index].radius += 1
	nest := room.objects[index]
	record_event(events, {kind = .Spider_Nest_Struck, source = source, target = object_entity(nest.id),
		from_position = nest.position, to_position = nest.position, amount = SPIDER_NEST_BLOW_SECONDS})
	spider_nest_loses(room, index, SPIDER_NEST_BLOW_SECONDS, events)
}

// A foe's blow over `cells`: every nest it takes loses its seconds, once for the blow.
@(private)
spider_nests_under_blow :: proc(room: ^Room, cells: []grid.Position, source: Entity_Ref, events: ^Event_Log) {
	for cell in cells {
		if index, found := object_index_at(room, cell); found && room.objects[index].kind == .Spider_Nest {
			spider_nest_struck(room, index, source, events)
		}
	}
}

// THE BAIT: a foe next to a nest and not next to the player strikes the nest.
@(private)
spider_nest_bait :: proc(room: ^Room, enemy: ^Enemy, origin: grid.Position, intent: ^Enemy_Intent) {
	if intent.kind == .Recover || intent.kind == .None { return }
	p := room.player.position
	if abs(p.x-origin.x)+abs(p.y-origin.y) == 1 { return }
	for object in room.objects {
		if object.kind != .Spider_Nest || object.position.layer != origin.layer { continue }
		if abs(object.position.x-origin.x)+abs(object.position.y-origin.y) != 1 { continue }
		bait := make_attack_intent(room, origin, object.position, max(enemy.attack, 1))
		bait.target_object = object.id
		intent^ = bait
		return
	}
}

// Whether a spiderling can run over `cell`: the floor, under bodies; not walls, covers or solid objects.
@(private = "file")
spider_cell_is_open :: proc(room: ^Room, cell: grid.Position, nest: u32) -> bool {
	if !base_cell_is_walkable(room, cell) || obstacle_at(room, cell) { return false }
	if index, found := object_index_at(room, cell); found {
		object := room.objects[index]
		definition, _ := grid_object_definition(object.kind)
		if object.id != nest && definition.blocks_movement { return false }
	}
	return true
}

// The first step of the shortest way (in steps, around the walls) from `from` to the nearest foe in play, and the
// cell it leads to; `there`: a foe stands on `from`. A breadth-first search in a window round the spiderling, in the
// order north, east, south, west: the same way every time.
@(private)
spider_way :: proc(room: ^Room, from: grid.Position, nest: u32) -> (next: grid.Position, found, there: bool) {
	if index, foe := enemy_index_at(room, from); foe && !enemy_is_out_of_play(room, room.enemies[index].id) { return from, true, true }
	queue: [SPIDER_WINDOW*SPIDER_WINDOW]u16
	// 0: not seen; else the direction of the first step, plus one.
	first: [SPIDER_WINDOW*SPIDER_WINDOW]u8
	at := proc(x, y: int) -> int { return y*SPIDER_WINDOW+x }
	head, tail := 0, 0
	centre := SPIDER_REACH
	first[at(centre, centre)] = 5
	queue[tail] = u16(at(centre, centre))
	tail += 1
	for head < tail {
		index := int(queue[head])
		head += 1
		x, y := index%SPIDER_WINDOW, index/SPIDER_WINDOW
		for direction in Move_Direction {
			step := direction_offset(direction)
			nx, ny := x+step.x, y+step.y
			if nx < 0 || ny < 0 || nx >= SPIDER_WINDOW || ny >= SPIDER_WINDOW || first[at(nx, ny)] != 0 { continue }
			cell := grid.offset(from, nx-centre, ny-centre)
			if !spider_cell_is_open(room, cell, nest) { continue }
			way := first[index] if first[index] != 5 else u8(direction)+1
			first[at(nx, ny)] = way
			if foe, standing := enemy_index_at(room, cell); standing && !enemy_is_out_of_play(room, room.enemies[foe].id) {
				return add_position(from, direction_offset(Move_Direction(way-1))), true, false
			}
			queue[tail] = u16(at(nx, ny))
			tail += 1
		}
	}
	return from, false, false
}

// The spiderlings run their seconds waiting into `pulse` (fly_enemy_flights).
@(private)
run_spiderlings :: proc(room: ^Room, pulse: ^Pulse_Report) {
	swarm := &room.player.tactical.spiders
	if swarm.count == 0 { swarm.pending = 0; return }
	seconds := swarm.pending
	swarm.pending = 0
	for index := i32(0); index < swarm.count && room.phase == .Combat; {
		spider := &swarm.items[index]
		spider.age += seconds
		spider.travelled += seconds*SPIDER_CELLS_A_SECOND
		gone := false
		for !gone && spider.travelled >= 1 && pulse.events.count <= MAX_GAME_EVENTS-SPIDER_EVENT_HEADROOM {
			next, found, there := spider_way(room, spider.position, spider.nest)
			if there { gone = true; spider_bites(room, spider^, pulse); break }
			if !found { spider.travelled = 0; break }
			spider.travelled -= 1
			spider.from, spider.position = spider.position, next
			if foe, standing := enemy_index_at(room, next); standing && !enemy_is_out_of_play(room, room.enemies[foe].id) {
				gone = true
				spider_bites(room, spider^, pulse)
			}
		}
		if !gone && spider.age >= SPIDER_LIFE_SECONDS {
			gone = true
			record_event(&pulse.events, {kind = .Spider_Died, source = SYSTEM_ENTITY, target = SYSTEM_ENTITY,
				from_position = spider.position, to_position = spider.position})
		}
		if gone {
			swarm.items[index] = swarm.items[swarm.count-1]
			swarm.count -= 1
			continue
		}
		index += 1
	}
}

// The bite: an attack of the player's, without him; then the spiderling is gone.
@(private = "file")
spider_bites :: proc(room: ^Room, spider: Spiderling, pulse: ^Pulse_Report) {
	index, found := enemy_index_at(room, spider.position)
	if !found { return }
	foe := enemy_entity(room.enemies[index].id)
	record_event(&pulse.events, {kind = .Spider_Bite, source = SYSTEM_ENTITY, target = foe,
		from_position = spider.from, to_position = spider.position, amount = spider.bite})
	action := make_action(.Trigger, SYSTEM_ENTITY, entity_target(foe), .Entity)
	if add_effect(&action, damage_effect(foe, spider.bite)) {
		report := resolve_action(room, &action)
		merge_action_report(pulse, &report)
	}
}

// The fight over: the nests and the spiderlings go with it.
@(private)
spider_nests_end_combat :: proc(room: ^Room) {
	room.player.tactical.spiders = {}
	for index := len(room.objects)-1; index >= 0; index -= 1 {
		if room.objects[index].kind == .Spider_Nest { remove_grid_object(room, index) }
	}
}
