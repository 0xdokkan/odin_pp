package expedition

import campaign "../campaign"
import game "../game"
import grid "../engine/grid"
import level "../level"
import rng "../engine/rng"

// THE NETWORKS UNDER THE GROUND (Fase 7 of docs/piano-profondita.md, the second group of biomes): a biome raised by a base
// (relief.odin) has room under all of its ground, and a network runs there on the deep layer (NETWORK_LAYER), at the
// height NETWORK_FLOOR: halls joined by ways. City pop has its metro, three stations under its streets; the Egitto its
// necropolis, a great hall and a tomb under the desert, with a hall under the west pyramid's shaft (complex.odin); the
// Vietnam its galleries, from today's tunnel in the south to where the tunnel came out in the north-east, with chambers
// on the way (the user's choices).
//
// One goes down by stairs, a ramp in a pit from the ground to a step over the network, and at one place by a lift's
// shaft; a gate on a way opens from one side only, the network's shortcut. Its halls hold the biome's foes and a secret.
// Like a complex it is the biome's geography: fixed, made after the relief and the complexes, the same at every run.

NETWORK_LAYER :: i8(grid.LOWEST_LAYER)
NETWORK_FLOOR :: i32(0)
// The cells of a stair's ramp: from a step under the base down to a step over the network.
NETWORK_STAIR_STEPS :: 13
// The longest way from a hall's side to its lift's shaft; how far from a hall's middle its stair's foot may be.
NETWORK_STUB_MAX :: 24
NETWORK_STAIR_REACH :: 36

Network_Hall :: struct {
	// Its middle, in hundredths of the map's side (as the sites'); or, with `shaft`, the cell of the biome's complex's
	// shaft down to the network (its mark 'D').
	at:     [2]int,
	shaft:  bool,
	// How far it reaches from its middle, on each side.
	half:   [2]int,
	// The width of a stair down to it (0: none); whether the lift's shaft is in it, its foes, the secret.
	stair:  int,
	lift, guards, secret: bool,
}

Network_Plan :: struct {
	halls:    []Network_Hall,
	// The width of the ways from each hall to the next.
	way:      int,
	// The way with the gate (from hall `gate_way` to the next; -1: none): its lever is on the next hall's side.
	gate_way: int,
}

// City pop's metro: a west station and a middle one under the same street, a third to the south-east, at a crossing clear
// of the places round it; stairs at the two ends, the lift at the middle; the gate between the middle and the south-east,
// opened from the south-east.
@(private = "file")
METRO_HALLS := [?]Network_Hall{
	{at = {22, 30}, half = {4, 2}, stair = 2, guards = true},
	{at = {50, 30}, half = {4, 2}, lift = true},
	{at = {74, 59}, half = {4, 2}, stair = 2, guards = true, secret = true},
}

// The Egitto's necropolis: the hall under the west pyramid's shaft, the great hall with a stair down from the sand, a
// tomb with the secret. The gate between the pyramid's hall and the great hall opens from the great hall.
@(private = "file")
NECROPOLIS_HALLS := [?]Network_Hall{
	{shaft = true, half = {3, 3}},
	{at = {45, 45}, half = {9, 5}, stair = 3, guards = true},
	{at = {30, 72}, half = {3, 2}, guards = true, secret = true},
}

// The Vietnam's galleries: from today's tunnel, in the south, north and east by chambers to where it came out; trapdoors
// at four of them, a lift at another; the gate before the last stretch opens from the north-east.
@(private = "file")
GALLERY_HALLS := [?]Network_Hall{
	{at = {59, 89}, half = {2, 2}, stair = 2},
	{at = {59, 62}, half = {3, 2}, stair = 1, guards = true},
	{at = {78, 62}, half = {3, 2}, lift = true},
	{at = {78, 30}, half = {3, 2}, stair = 1, guards = true},
	{at = {92, 30}, half = {2, 2}},
	{at = {92, 10}, half = {2, 2}, stair = 2, secret = true},
}

network_plan :: proc(b: campaign.Biome) -> Network_Plan {
	#partial switch b {
	case .City: return {halls = METRO_HALLS[:], way = 3, gate_way = 1}
	case .Egypt: return {halls = NECROPOLIS_HALLS[:], way = 3, gate_way = 0}
	case .Vietnam: return {halls = GALLERY_HALLS[:], way = 2, gate_way = 3}
	}
	return {gate_way = -1}
}

// The middle of the plan's hall `index` on the map, on the network's layer.
network_hall_centre :: proc(w: ^World, plan: Network_Plan, index: int) -> grid.Position {
	hall := plan.halls[index]
	side := size(w)
	if hall.shaft {
		for c in w.complexes[:w.complex_count] {
			layout := complex_layout(c.kind)
			width, height := complex_size(layout)
			for y in 0..<height {
				for x in 0..<width { if layout.rows[y][x] == 'D' { return {x = c.origin.x+x, y = c.origin.y+y, layer = NETWORK_LAYER} } }
			}
		}
	}
	x := clamp(hall.at.x*side/100, 6+hall.half.x, side-7-hall.half.x)
	y := clamp(hall.at.y*side/100, 6+hall.half.y, side-7-hall.half.y)
	return {x = x, y = y, layer = NETWORK_LAYER}
}

@(private = "file")
network_floor :: proc(data: ^level.Level, x, y: int) {
	cell := grid.Position{x = x, y = y, layer = NETWORK_LAYER}
	_ = level.set_tile(data, cell, {kind = .Floor})
	_ = level.set_height(data, cell, NETWORK_FLOOR)
}

// Whether column (x, y) may hold the network under its ground: a floor there LAYER_SPACING steps over it at least (not a
// stair's pit), never a wall or a prop (under a wall the column is rock through, level.column_of: no room), off the rim.
@(private = "file")
network_room_under :: proc(data: ^level.Level, x, y: int) -> bool {
	if x < 4 || y < 4 || x >= data.tiles.width-4 || y >= data.tiles.height-4 { return false }
	tile, found := level.tile_at(data, {x = x, y = y})
	return found && level.kind_has_floor(tile.kind) && tile.kind != .Fence && level.height_at(data, {x = x, y = y}) >= NETWORK_FLOOR+level.LAYER_SPACING
}

// The cell nearest `at` that may hold the network (network_room_under), within `reach` cells; `at` if none does.
@(private = "file")
network_nearest :: proc(data: ^level.Level, at: grid.Position, reach: int) -> grid.Position {
	for radius in 0..=reach {
		for dy in -radius..=radius {
			for dx in -radius..=radius {
				if max(abs(dx), abs(dy)) != radius { continue }
				if network_room_under(data, at.x+dx, at.y+dy) { return {x = at.x+dx, y = at.y+dy, layer = NETWORK_LAYER} }
			}
		}
	}
	return at
}

// The way from `from` to `to`: the shortest walk over the columns that may hold the network (round the walls and the
// pits), `width` cells wide where the columns let it, its cells in `path` (none: no way).
@(private = "file")
network_way :: proc(data: ^level.Level, from, to: grid.Position, width: int, path: ^[dynamic]grid.Position) -> bool {
	clear(path)
	cells := len(data.tiles.cells)
	side := data.tiles.width
	came := make([]i32, cells, context.temp_allocator)
	for &value in came { value = -1 }
	queue := make([dynamic]i32, 0, 4096, context.temp_allocator)
	start, goal := i32(from.y*side+from.x), i32(to.y*side+to.x)
	if !network_room_under(data, from.x, from.y) || !network_room_under(data, to.x, to.y) { return false }
	came[start] = start
	append(&queue, start)
	steps := [4]grid.Position{{x = 1}, {x = -1}, {y = 1}, {y = -1}}
	for head := 0; head < len(queue) && came[goal] < 0; head += 1 {
		at := queue[head]
		x, y := int(at)%side, int(at)/side
		// Toward the goal first: the walk keeps straight where it can.
		for step in steps {
			nx, ny := x+step.x, y+step.y
			if !network_room_under(data, nx, ny) { continue }
			next := i32(ny*side+nx)
			if came[next] >= 0 { continue }
			came[next] = at
			append(&queue, next)
		}
	}
	if came[goal] < 0 { return false }
	for at := goal; ; at = came[at] {
		inject_at(path, 0, grid.Position{x = int(at)%side, y = int(at)/side, layer = NETWORK_LAYER})
		if at == start { break }
	}
	for cell, i in path {
		network_floor(data, cell.x, cell.y)
		// Across the way's direction at this cell, the other lanes.
		next := path[min(i+1, len(path)-1)]
		previous := path[max(i-1, 0)]
		d := grid.Position{x = next.x-previous.x, y = next.y-previous.y}
		across := grid.Position{x = 1} if d.x == 0 else grid.Position{y = 1}
		for lane in -(width/2)..=(width-1)/2 {
			if lane == 0 { continue }
			p := grid.offset(cell, across.x*lane, across.y*lane)
			if network_room_under(data, p.x, p.y) { network_floor(data, p.x, p.y) }
		}
	}
	return true
}

// Whether a stair's pit may take the ground cell `p`: open floor, at the base for the cell one walks out onto (`exit`), at
// the base or over it for the pit's own (its relief is dug away), clear of the sites, the complexes, the caves' massifs,
// the spawn, the patrols' ground and the central band, with nothing under it.
@(private = "file")
network_pit_free :: proc(w: ^World, data: ^level.Level, p: grid.Position, exit := false) -> bool {
	side := size(w)
	if p.x < 6 || p.y < 6 || p.x >= side-6 || p.y >= side-6 || abs(p.y-side/2) <= 5 { return false }
	tile, found := level.tile_at(data, p)
	height := level.height_at(data, p)
	if !found || tile.kind != .Floor || height < w.base || exit && height != w.base { return false }
	if _, owned := level.structure_index_at(data, p); owned { return false }
	for layer in grid.LOWEST_LAYER..<grid.GROUND_LAYER {
		if under, _ := level.tile_at(data, {x = p.x, y = p.y, layer = i8(layer)}); level.kind_has_floor(under.kind) { return false }
	}
	for &site in w.sites[:w.site_count] {
		low, high := site_bounds(&site)
		if p.x >= low.x-1 && p.y >= low.y-1 && p.x <= high.x+1 && p.y <= high.y+1 { return false }
	}
	for c in w.complexes[:w.complex_count] {
		zone := complex_level_zone(c)
		if p.x >= zone[0].x && p.y >= zone[0].y && p.x <= zone[1].x && p.y <= zone[1].y { return false }
	}
	for cave in w.caves[:w.cave_count] {
		for zone in cave_level_zones(cave.place) {
			if p.x >= zone[0].x && p.y >= zone[0].y && p.x <= zone[1].x && p.y <= zone[1].y { return false }
		}
	}
	if distance(p, data.player_spawn) <= 10 { return false }
	for i in 0..<4 {
		if distance(p, {x = side*(35+i*13)/100, y = side*(35+(i%2)*28)/100}) <= 5 { return false }
	}
	return true
}

// A stair down to a hall (its middle `centre`): a pit `width` cells wide whose ramp rises a step a cell from a step over
// the network to a step under the base, then the open ground at the base, and from the cell before its foot a way to the
// hall round the walls (network_way). The nearest pit to the hall that fits and has a way, within NETWORK_STAIR_REACH.
@(private = "file")
network_stair :: proc(w: ^World, data: ^level.Level, centre: grid.Position, half: [2]int, width: int) -> bool {
	anchor := network_nearest(data, centre, 6)
	if !network_room_under(data, anchor.x, anchor.y) { return false }
	sides := [4]grid.Position{{y = 1}, {x = 1}, {y = -1}, {x = -1}}
	cell :: proc(bottom, d, across: grid.Position, along, lane, width: int) -> grid.Position {
		offset := lane-width/2
		return {x = bottom.x+d.x*along+across.x*offset, y = bottom.y+d.y*along+across.y*offset}
	}
	path := make([dynamic]grid.Position, context.temp_allocator)
	for radius in max(half.x, half.y)+1..=NETWORK_STAIR_REACH {
		for dy in -radius..=radius {
			for dx in -radius..=radius {
				if max(abs(dx), abs(dy)) != radius { continue }
				bottom := grid.Position{x = centre.x+dx, y = centre.y+dy}
				for d in sides {
					across := grid.Position{x = abs(d.y), y = abs(d.x)}
					fits := true
					for lane in 0..<width {
						for k in 0..=NETWORK_STAIR_STEPS {
							p := cell(bottom, d, across, k, lane, width)
							if !network_pit_free(w, data, p, k == NETWORK_STAIR_STEPS) { fits = false; break }
						}
						entry := cell(bottom, d, across, -1, lane, width)
						if !fits || !network_room_under(data, entry.x, entry.y) { fits = false; break }
						// Beside the pit, the ground stays.
						for side_lane in ([2]int{-1, width}) {
							for k in 0..<NETWORK_STAIR_STEPS {
								p := cell(bottom, d, across, k, side_lane, width)
								if tile, found := level.tile_at(data, p); !found || tile.kind == .Void { fits = false }
							}
						}
					}
					if !fits { continue }
					// The pit first, so that the way goes round it; filled again if there is no way.
					for lane in 0..<width {
						for k in 0..<NETWORK_STAIR_STEPS { _ = level.set_height(data, cell(bottom, d, across, k, lane, width), NETWORK_FLOOR+1+i32(k)) }
					}
					entry := cell(bottom, d, across, -1, width/2, width)
					if network_way(data, entry, anchor, width, &path) {
						for lane in 0..<width { p := cell(bottom, d, across, -1, lane, width); network_floor(data, p.x, p.y) }
						return true
					}
					for lane in 0..<width {
						for k in 0..<NETWORK_STAIR_STEPS { _ = level.set_height(data, cell(bottom, d, across, k, lane, width), w.base) }
					}
				}
			}
		}
	}
	return false
}

// The lift's shaft by a hall: the column nearest its middle whose ground is open floor at the base, clear of the sites,
// with open floor round it; in the hall, or else at the end of a way from one of its sides, as a stair's. From the
// network up to the ground; the platform waits at the top.
@(private = "file")
network_lift :: proc(w: ^World, data: ^level.Level, centre: grid.Position, half: [2]int) -> bool {
	open :: proc(w: ^World, data: ^level.Level, p: grid.Position) -> bool {
		tile, found := level.tile_at(data, p)
		if !found || tile.kind != .Floor || level.height_at(data, p) != w.base { return false }
		if _, owned := level.structure_index_at(data, p); owned { return false }
		for &site in w.sites[:w.site_count] {
			low, high := site_bounds(&site)
			if p.x >= low.x-1 && p.y >= low.y-1 && p.x <= high.x+1 && p.y <= high.y+1 { return false }
		}
		return true
	}
	shaft :: proc(w: ^World, data: ^level.Level, top: grid.Position) -> bool {
		if !open(w, data, top) { return false }
		for step in ([4]grid.Position{{x = 1}, {x = -1}, {y = 1}, {y = -1}}) {
			if !open(w, data, grid.offset(top, step.x, step.y)) { return false }
		}
		return true
	}
	for radius in 0..=max(half.x, half.y) {
		for dy in -radius..=radius {
			for dx in -radius..=radius {
				if max(abs(dx), abs(dy)) != radius || abs(dx) > half.x || abs(dy) > half.y { continue }
				top := grid.Position{x = centre.x+dx, y = centre.y+dy}
				if shaft(w, data, top) { return level.add_lift(data, {x = top.x, y = top.y, layer = NETWORK_LAYER}, top, 1) }
			}
		}
	}
	sides := [4]grid.Position{{y = 1}, {x = 1}, {y = -1}, {x = -1}}
	for stub in 1..=NETWORK_STUB_MAX+4 {
		for d in sides {
			edge := grid.Position{x = centre.x+d.x*half.x, y = centre.y+d.y*half.y}
			top := grid.offset(edge, d.x*stub, d.y*stub)
			if !shaft(w, data, top) { continue }
			way := true
			for along in 1..=stub { p := grid.offset(edge, d.x*along, d.y*along); way = way && network_room_under(data, p.x, p.y) }
			if !way { continue }
			for along in 1..=stub { p := grid.offset(edge, d.x*along, d.y*along); network_floor(data, p.x, p.y) }
			return level.add_lift(data, {x = top.x, y = top.y, layer = NETWORK_LAYER}, top, 1)
		}
	}
	return false
}

// The network's gate on a way (`path`, from one hall to the next): at the cell nearest its middle where it goes straight,
// the way narrowed to that cell there; its lever the next cell, on the next hall's side.
@(private = "file")
network_gate :: proc(data: ^level.Level, path: []grid.Position, width: int) {
	if len(path) < 7 { return }
	middle := len(path)/2
	for offset in 0..<len(path)/2-3 {
		for i in ([2]int{middle+offset, middle-offset}) {
			if i < 2 || i > len(path)-3 { continue }
			d := grid.Position{x = path[i+1].x-path[i].x, y = path[i+1].y-path[i].y}
			straight := true
			for k in i-2..<i+2 { straight = straight && path[k+1].x-path[k].x == d.x && path[k+1].y-path[k].y == d.y }
			if !straight { continue }
			across := grid.Position{x = 1} if d.x == 0 else grid.Position{y = 1}
			for lane in -width..=width {
				if lane == 0 { continue }
				_ = level.set_tile(data, grid.offset(path[i], across.x*lane, across.y*lane), {kind = .Void})
			}
			_ = level.add_gate(data, path[i], path[i+1])
			return
		}
	}
}

// The map's network, after the complexes (generate): its halls, its ways, its gate, its stairs and its lift.
@(private)
place_network :: proc(w: ^World, data: ^level.Level) {
	plan := network_plan(w.biome)
	if len(plan.halls) == 0 || w.base < NETWORK_FLOOR+level.LAYER_SPACING { return }
	centres: [8]grid.Position
	count := min(len(plan.halls), len(centres))
	for i in 0..<count { centres[i] = network_hall_centre(w, plan, i) }
	// Each hall: the cells of its box that may hold it and join its middle (a wall over the box leaves no pocket apart).
	for i in 0..<count {
		half := plan.halls[i].half
		anchor := network_nearest(data, centres[i], 6)
		if !network_room_under(data, anchor.x, anchor.y) { continue }
		box := (2*half.x+1)*(2*half.y+1)
		seen := make([]bool, box, context.temp_allocator)
		queue := make([dynamic]grid.Position, 0, box, context.temp_allocator)
		inside :: proc(p, centre: grid.Position, half: [2]int) -> bool { return abs(p.x-centre.x) <= half.x && abs(p.y-centre.y) <= half.y }
		index :: proc(p, centre: grid.Position, half: [2]int) -> int { return (p.y-centre.y+half.y)*(2*half.x+1)+(p.x-centre.x+half.x) }
		if !inside(anchor, centres[i], half) { continue }
		seen[index(anchor, centres[i], half)] = true
		append(&queue, anchor)
		for head := 0; head < len(queue); head += 1 {
			at := queue[head]
			network_floor(data, at.x, at.y)
			for step in ([4]grid.Position{{x = 1}, {x = -1}, {y = 1}, {y = -1}}) {
				next := grid.offset(at, step.x, step.y)
				if !inside(next, centres[i], half) || seen[index(next, centres[i], half)] || !network_room_under(data, next.x, next.y) { continue }
				seen[index(next, centres[i], half)] = true
				append(&queue, next)
			}
		}
	}
	path := make([dynamic]grid.Position, context.temp_allocator)
	for i in 0..<count-1 {
		from, to := network_nearest(data, centres[i], 6), network_nearest(data, centres[i+1], 6)
		if !network_way(data, from, to, plan.way, &path) { continue }
		if i == plan.gate_way { network_gate(data, path[:], plan.way) }
	}
	for hall, i in plan.halls[:count] {
		if hall.stair > 0 { _ = network_stair(w, data, centres[i], hall.half, hall.stair) }
		if hall.lift { _ = network_lift(w, data, centres[i], hall.half) }
	}
}

// The network's foes and secret, on the map as it is after the retouches (generate): a group of the biome's foes in each
// hall that has them, credits and a relic in the hall with the secret, taken by hand.
@(private)
fill_network :: proc(w: ^World, data: ^level.Level) {
	plan := network_plan(w.biome)
	if len(plan.halls) == 0 || w.base < NETWORK_FLOOR+level.LAYER_SPACING { return }
	r := rng.create(w.seed~0x5E7_0071)
	for hall, i in plan.halls {
		centre := network_nearest(data, network_hall_centre(w, plan, i), 6)
		if tile, _ := level.tile_at(data, centre); tile.kind != .Floor { continue }
		if hall.secret {
			beside := grid.offset(centre, 1, 0)
			if tile, _ := level.tile_at(data, beside); tile.kind != .Floor { beside = centre }
			_ = add_drop(w, centre, campaign.make_item(.Credits, 40+i32(rng.next_u64(&r)%40)), 0, true)
			relic := 1+i32(rng.next_u64(&r)%(u64(game.Relic_Id.Count)-1))
			_ = add_drop(w, beside, campaign.make_item(.Relic, 1, relic), 0, true)
		}
		if hall.guards { add_group(w, data, -1, grid.offset(centre, 0, -1 if hall.half.y > 1 else 0), 2+rank(w.biome)/2, false, false) }
	}
}
