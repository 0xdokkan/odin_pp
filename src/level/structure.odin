package level

import grid "../engine/grid"

// STRUCTURES ON MORE THAN ONE CELL (Fase 6 of docs/piano-griglia.md): complex objects
// (a cart, a fountain, a statue, a machine, a ruin, a pen) and buildings (a cottage, a
// hut, a temple). A structure is drawn as a plan of characters, as the vaults of
// Dungeon Crawl Stone Soup are, and placed on the map by writing its cells as ordinary
// tiles, so walking, sight, the enemies' AI and the cards' previews need no new rule:
//
//   #  a wall: stops the step and the sight
//   =  a low wall or fence: stops the step, not the sight
//   .  the structure's floor
//   +  a door: on the plan's edge, the only way into the floor inside
//   *  a point of use: floor, from which the structure is used
//   (space) outside the footprint: the ground stays as it is
//
// This file is the generic part: reading a plan, turning it, checking it and placing
// it. The catalog of structures is in structure_catalog.odin.

MAX_PLAN_SIDE :: 12
MAX_PLAN_CELLS :: MAX_PLAN_SIDE*MAX_PLAN_SIDE
// A map keeps its structures' index in a byte: 0 is no structure.
MAX_STRUCTURES_PER_LEVEL :: 64

Plan_Cell :: enum u8 { Outside, Wall, Fence, Floor, Door, Use }

Plan :: struct {
	width, height: int,
	cells:         [MAX_PLAN_CELLS]Plan_Cell,
}

// A cottage or a hut is a building the robot goes into; a cart or a statue is an object
// that is only walked round (a pen has a gate and a floor, and is an object too).
Structure_Kind :: enum u8 { Object, Building }

Rotation :: enum u8 { Quarter_0, Quarter_1, Quarter_2, Quarter_3 }
Rotation_Set :: bit_set[Rotation; u8]

Plan_Error :: enum u8 {
	None,
	Empty,
	Too_Big,
	Inconsistent_Row_Width,
	Unknown_Symbol,
	Door_Not_On_Edge,
	Building_Without_Door,
	Floor_Not_Connected,
}

plan_error_text :: proc(err: Plan_Error) -> string {
	switch err {
	case .None: return "no error"
	case .Empty: return "the plan is empty"
	case .Too_Big: return "the plan is bigger than the largest structure"
	case .Inconsistent_Row_Width: return "the plan's rows have different widths"
	case .Unknown_Symbol: return "the plan contains an unknown symbol"
	case .Door_Not_On_Edge: return "a door must stand on the edge of the plan"
	case .Building_Without_Door: return "a building needs a door"
	case .Floor_Not_Connected: return "a floor cell cannot be reached from a door"
	}
	return "?"
}

plan_cell_from_symbol :: proc(symbol: u8) -> (Plan_Cell, bool) {
	switch symbol {
	case ' ': return .Outside, true
	case '#': return .Wall, true
	case '=': return .Fence, true
	case '.': return .Floor, true
	case '+': return .Door, true
	case '*': return .Use, true
	}
	return .Outside, false
}

plan_at :: proc(plan: ^Plan, x, y: int) -> Plan_Cell {
	if x < 0 || y < 0 || x >= plan.width || y >= plan.height { return .Outside }
	return plan.cells[y*plan.width+x]
}

// A cell the robot can stand on once the structure stands.
plan_cell_walkable :: proc(cell: Plan_Cell) -> bool {
	return cell == .Floor || cell == .Door || cell == .Use
}

// How many cells the structure covers (every cell but the outside).
plan_footprint_count :: proc(plan: ^Plan) -> (count: int) {
	for y in 0..<plan.height { for x in 0..<plan.width { if plan_at(plan, x, y) != .Outside { count += 1 } } }
	return
}

// Checks what a plan must satisfy, whatever its turn: every door on the edge, a
// building with a door, every floor cell connected to a door (when there is a floor).
plan_problem :: proc(plan: ^Plan, kind: Structure_Kind) -> Plan_Error {
	doors := 0
	for y in 0..<plan.height {
		for x in 0..<plan.width {
			if plan_at(plan, x, y) != .Door { continue }
			doors += 1
			on_edge := false
			for step in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
				if plan_at(plan, x+step.x, y+step.y) == .Outside { on_edge = true }
			}
			if !on_edge { return .Door_Not_On_Edge }
		}
	}
	if kind == .Building && doors == 0 { return .Building_Without_Door }
	// Walk in from the doors over floor, door and use cells: nothing inside may stay out of reach.
	reached: [MAX_PLAN_CELLS]bool
	queue: [MAX_PLAN_CELLS][2]int
	head, tail := 0, 0
	floors := 0
	for y in 0..<plan.height {
		for x in 0..<plan.width {
			cell := plan_at(plan, x, y)
			if cell == .Floor || cell == .Use { floors += 1 }
			if cell == .Door { reached[y*plan.width+x] = true; queue[tail] = {x, y}; tail += 1 }
		}
	}
	if floors > 0 && doors == 0 { return .Floor_Not_Connected }
	reached_floors := 0
	for head < tail {
		at := queue[head]
		head += 1
		for step in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
			x, y := at.x+step.x, at.y+step.y
			if x < 0 || y < 0 || x >= plan.width || y >= plan.height || reached[y*plan.width+x] { continue }
			cell := plan_at(plan, x, y)
			if cell != .Floor && cell != .Use { continue }
			reached[y*plan.width+x] = true
			queue[tail] = {x, y}
			tail += 1
			reached_floors += 1
		}
	}
	if reached_floors != floors { return .Floor_Not_Connected }
	return .None
}

// Reads a plan from rows of text. Rows must be the same width; symbols are the ones
// above. A door must stand on the edge, a building needs a door, and the floor inside
// must be reachable from a door.
parse_plan :: proc(rows: []string, kind: Structure_Kind) -> (plan: Plan, err: Plan_Error) {
	if len(rows) == 0 || len(rows[0]) == 0 { return {}, .Empty }
	width := len(rows[0])
	if width > MAX_PLAN_SIDE || len(rows) > MAX_PLAN_SIDE { return {}, .Too_Big }
	plan.width, plan.height = width, len(rows)
	for row, y in rows {
		if len(row) != width { return {}, .Inconsistent_Row_Width }
		for x in 0..<width {
			cell, known := plan_cell_from_symbol(row[x])
			if !known { return {}, .Unknown_Symbol }
			plan.cells[y*width+x] = cell
		}
	}
	return plan, plan_problem(&plan, kind)
}

// The plan flipped left to right.
mirror_plan :: proc(plan: Plan) -> (result: Plan) {
	result = plan
	for y in 0..<plan.height { for x in 0..<plan.width { result.cells[y*plan.width+x] = plan.cells[y*plan.width+(plan.width-1-x)] } }
	return
}

// The plan turned a quarter of a turn clockwise.
rotate_plan :: proc(plan: Plan) -> (result: Plan) {
	result.width, result.height = plan.height, plan.width
	for y in 0..<plan.height {
		for x in 0..<plan.width {
			// (x, y) goes to (height-1-y, x).
			result.cells[x*result.width+(plan.height-1-y)] = plan.cells[y*plan.width+x]
		}
	}
	return
}

// The plan as it stands when mirrored (first) and turned `rotation` quarters.
transform_plan :: proc(plan: Plan, rotation: u8, mirror: bool) -> (result: Plan) {
	result = mirror_plan(plan) if mirror else plan
	for _ in 0..<(rotation%4) { result = rotate_plan(result) }
	return
}

// A structure standing on a map: which one, where its plan's top-left cell is, and
// how it was turned.
Placed_Structure :: struct {
	id:       Structure_Id,
	origin:   grid.Position,
	rotation: u8,
	mirror:   bool,
}

// The plan of a placed structure, turned.
placed_plan :: proc(placed: Placed_Structure) -> Plan {
	definition := structure_definition(placed.id)
	plan, _ := parse_plan(definition.rows, definition.kind)
	return transform_plan(plan, placed.rotation, placed.mirror)
}

Placement_Error :: enum u8 {
	None,
	Bad_Structure,
	Rotation_Not_Allowed,
	Mirror_Not_Allowed,
	Too_Many,
	Out_Of_Map,
	Not_Free,
	Overlap,
	Too_Close,
	Keep_Clear,
	Entrance_Blocked,
	Pocket,
}

placement_error_text :: proc(err: Placement_Error) -> string {
	switch err {
	case .None: return "no error"
	case .Bad_Structure: return "the structure's plan is not valid"
	case .Rotation_Not_Allowed: return "the structure may not be turned this way"
	case .Mirror_Not_Allowed: return "the structure may not be mirrored"
	case .Too_Many: return "the map holds no more structures"
	case .Out_Of_Map: return "the structure does not fit inside the map"
	case .Not_Free: return "the ground under the structure is not free floor"
	case .Overlap: return "the structure overlaps another one"
	case .Too_Close: return "the structure touches another one"
	case .Keep_Clear: return "the structure stands on something that must stay clear"
	case .Entrance_Blocked: return "a door of the structure opens onto a blocked cell"
	case .Pocket: return "the structure would shut a part of the map off"
	}
	return "?"
}

// Something the placement must leave alone (a site's courtyard, say).
Keep_Clear_Proc :: #type proc(user: rawptr, cell: grid.Position) -> bool

// The tile a plan cell writes onto the map; Outside writes nothing.
plan_tile :: proc(cell: Plan_Cell) -> (tile: Tile, writes: bool) {
	switch cell {
	case .Outside: return {}, false
	case .Wall: return Tile{kind = .Wall}, true
	case .Fence: return Tile{kind = .Fence}, true
	case .Floor, .Use: return Tile{kind = .Floor}, true
	case .Door: return Tile{kind = .Door}, true
	}
	return {}, false
}

// The structure whose footprint holds `cell`, if any.
structure_index_at :: proc(data: ^Level, cell: grid.Position) -> (index: int, found: bool) {
	if data == nil || len(data.structure_cells) == 0 { return }
	at, inside := grid.index_of(&data.tiles, cell)
	if !inside || at >= len(data.structure_cells) || data.structure_cells[at] == 0 { return }
	return int(data.structure_cells[at])-1, true
}

structure_count :: proc(data: ^Level) -> int {
	if data == nil { return 0 }
	return len(data.structures)
}

// What the structure at `index` has at `cell` (Outside beyond its footprint).
structure_plan_cell :: proc(data: ^Level, index: int, cell: grid.Position) -> Plan_Cell {
	if data == nil || index < 0 || index >= len(data.structures) { return .Outside }
	placed := data.structures[index]
	return plan_at(&data.structure_plans[index], cell.x-placed.origin.x, cell.y-placed.origin.y)
}

// Counts the walkable cells of `tiles` and those reached from `from` by 4-neighbour steps.
@(private)
reachable_walkable :: proc(tiles: []Tile, width, height: int, from: grid.Position) -> (reached, total: int) {
	visited := make([]bool, len(tiles), context.temp_allocator)
	queue := make([dynamic]int, 0, 256, context.temp_allocator)
	for tile in tiles { if is_walkable(tile.kind) { total += 1 } }
	start := from.y*width+from.x
	if from.x < 0 || from.y < 0 || from.x >= width || from.y >= height || !is_walkable(tiles[start].kind) { return 0, total }
	visited[start] = true
	append(&queue, start)
	head := 0
	for head < len(queue) {
		at := queue[head]
		head += 1
		reached += 1
		x, y := at%width, at/width
		for step in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
			nx, ny := x+step.x, y+step.y
			if nx < 0 || ny < 0 || nx >= width || ny >= height { continue }
			next := ny*width+nx
			if visited[next] || !is_walkable(tiles[next].kind) { continue }
			visited[next] = true
			append(&queue, next)
		}
	}
	return
}

// The first walkable cell (the spawn if the map has one): where reachability is counted from.
@(private)
reference_cell :: proc(data: ^Level) -> (cell: grid.Position, found: bool) {
	if data.has_player_spawn { return data.player_spawn, true }
	for tile, i in data.tiles.cells {
		if is_walkable(tile.kind) { return {i%data.tiles.width, i/data.tiles.width}, true }
	}
	return {}, false
}

// Whether `id` could be placed with its plan's top-left cell at `origin`, turned
// `rotation` quarters and mirrored or not, and why not if it cannot. The structure
// must: be a valid one and be turned only as its definition allows; fit inside the
// map, off the border; stand on free floor; not overlap or touch another structure;
// leave clear what `keep_clear` names; open every door onto walkable ground; and not
// shut off any part of a map that was whole.
place_check :: proc(data: ^Level, id: Structure_Id, origin: grid.Position, rotation: u8, mirror: bool,
	keep_clear: Keep_Clear_Proc = nil, user: rawptr = nil) -> Placement_Error {
	if data == nil || len(data.tiles.cells) == 0 { return .Out_Of_Map }
	definition := structure_definition(id)
	base, parsed := parse_plan(definition.rows, definition.kind)
	if parsed != .None { return .Bad_Structure }
	if Rotation(rotation%4) not_in definition.rotations { return .Rotation_Not_Allowed }
	if mirror && !definition.mirror { return .Mirror_Not_Allowed }
	if len(data.structures) >= MAX_STRUCTURES_PER_LEVEL { return .Too_Many }
	plan := transform_plan(base, rotation, mirror)
	width, height := data.tiles.width, data.tiles.height
	for y in 0..<plan.height {
		for x in 0..<plan.width {
			if plan_at(&plan, x, y) == .Outside { continue }
			cell := grid.Position{origin.x+x, origin.y+y}
			// Inside the map and off its border, which is the edge's wall or void.
			if cell.x < 1 || cell.y < 1 || cell.x >= width-1 || cell.y >= height-1 { return .Out_Of_Map }
			if _, taken := structure_index_at(data, cell); taken { return .Overlap }
			tile, _ := tile_at(data, cell)
			if tile.kind != .Floor { return .Not_Free }
			// A one-cell margin round another structure keeps the ways between them open.
			for dy in -1..=1 { for dx in -1..=1 {
				if _, near := structure_index_at(data, {cell.x+dx, cell.y+dy}); near { return .Too_Close }
			} }
			if keep_clear != nil && keep_clear(user, cell) { return .Keep_Clear }
		}
	}
	// Every door opens onto walkable ground that is not part of this structure.
	for y in 0..<plan.height {
		for x in 0..<plan.width {
			if plan_at(&plan, x, y) != .Door { continue }
			open := false
			for step in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
				if plan_at(&plan, x+step.x, y+step.y) != .Outside { continue }
				outside := grid.Position{origin.x+x+step.x, origin.y+y+step.y}
				tile, found := tile_at(data, outside)
				if found && tile.kind == .Floor { open = true }
			}
			if !open { return .Entrance_Blocked }
		}
	}
	// No pocket: a map that was whole must stay whole with the structure on it.
	reference, has_reference := reference_cell(data)
	if has_reference {
		before_reached, before_total := reachable_walkable(data.tiles.cells[:], width, height, reference)
		if before_reached == before_total {
			after := make([]Tile, len(data.tiles.cells), context.temp_allocator)
			copy(after, data.tiles.cells[:])
			for y in 0..<plan.height {
				for x in 0..<plan.width {
					tile, writes := plan_tile(plan_at(&plan, x, y))
					if writes { after[(origin.y+y)*width+(origin.x+x)] = tile }
				}
			}
			after_reached, after_total := reachable_walkable(after, width, height, reference)
			if after_reached != after_total { return .Pocket }
		}
	}
	return .None
}

// Places the structure if place_check allows it: writes its cells as tiles and records it.
place_structure :: proc(data: ^Level, id: Structure_Id, origin: grid.Position, rotation: u8, mirror: bool,
	keep_clear: Keep_Clear_Proc = nil, user: rawptr = nil) -> (index: int, err: Placement_Error) {
	err = place_check(data, id, origin, rotation, mirror, keep_clear, user)
	if err != .None { return -1, err }
	placed := Placed_Structure{id = id, origin = origin, rotation = rotation%4, mirror = mirror}
	plan := placed_plan(placed)
	for y in 0..<plan.height {
		for x in 0..<plan.width {
			tile, writes := plan_tile(plan_at(&plan, x, y))
			if writes { _ = set_tile(data, {origin.x+x, origin.y+y}, tile) }
		}
	}
	index = len(data.structures)
	append(&data.structures, placed)
	append(&data.structure_plans, plan)
	index_structure(data, index)
	return index, .None
}

@(private)
index_structure :: proc(data: ^Level, index: int) {
	if len(data.structure_cells) != len(data.tiles.cells) {
		resize(&data.structure_cells, len(data.tiles.cells))
	}
	placed := data.structures[index]
	plan := &data.structure_plans[index]
	for y in 0..<plan.height {
		for x in 0..<plan.width {
			if plan_at(plan, x, y) == .Outside { continue }
			at, inside := grid.index_of(&data.tiles, {placed.origin.x+x, placed.origin.y+y})
			if inside { data.structure_cells[at] = u8(index+1) }
		}
	}
}

// Sets the map's structures from a saved list. The tiles were saved with the map, so
// only the records and the cell index are rebuilt. False if one of the records is not
// valid (an unknown structure, a plan outside the map, too many).
set_structures :: proc(data: ^Level, list: []Placed_Structure) -> bool {
	if data == nil { return false }
	clear(&data.structures)
	clear(&data.structure_plans)
	clear(&data.structure_cells)
	if len(list) > MAX_STRUCTURES_PER_LEVEL { return false }
	for placed in list {
		if placed.id >= .Count || placed.rotation >= 4 { return false }
		plan := placed_plan(placed)
		if plan.width == 0 { return false }
		if placed.origin.x < 0 || placed.origin.y < 0 || placed.origin.x+plan.width > data.tiles.width || placed.origin.y+plan.height > data.tiles.height { return false }
		append(&data.structures, placed)
		append(&data.structure_plans, plan)
		index_structure(data, len(data.structures)-1)
	}
	return true
}
