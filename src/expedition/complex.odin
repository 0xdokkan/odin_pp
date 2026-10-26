package expedition

import campaign "../campaign"
import game "../game"
import grid "../engine/grid"
import level "../level"
import rng "../engine/rng"

// THE COMPLEXES (Fase 7 of docs/piano-profondita.md): the map's places on several layers. Two floors of a column are
// LAYER_SPACING steps apart at least (level/layers.odin), and the relief's plateaus are 3 or 4 steps tall: so a complex
// raises blocks of rock COMPLEX_TOP steps over the level ground round it, walked on at their top, with bridges between
// them on the layer over the ground and tunnels under them on the layer under it, ramps and lifts up to them and a
// shortcut's gate that opens from one side only (the user's choice at the start of the first group of biomes).
//
// Like the caves, a complex is part of the biome's geography: its place and its layout come from the biome alone,
// chosen before the relief, which keeps the ground round it level (relief.odin). Every run finds its gate shut
// (level.Gate); the run decides only who guards it. Robotica cibernetica has a data node, the Far West a train's bridge
// between two mesas, the Giungla preistorica giant trees by a hill of bones.
//
// A layout is one string a row of cells, x eastward and y southward:
//   .     open ground, at the complex's floor (the level ground round it)
//   #     a block: rock COMPLEX_TOP steps over the floor, walked on at its top
//   $ @   a block's cell with the complex's secret on it, where its guards stand
//   =     a deck on the layer over the ground, at the blocks' top, over open ground
//   a..m  a ramp up a block, 1 to 13 steps over the floor
//   t &   a tunnel on the layer under the ground, at the floor, under a block; & where its guards stand
//   S     a shaft: a tunnel's cell with a lift up to the block's top over it
//   L     a lift up a block's side: its foot on the open ground, its landing on the deck's layer at the top
// Its gates are listed apart, each on the layer of its cell's mark (a tunnel's, a deck's or a block's top).

COMPLEX_TOP :: level.LAYER_SPACING+2
MAX_COMPLEXES :: 2
// The ground left level and clear of props round a complex's layout.
COMPLEX_MARGIN :: 3
COMPLEX_DECK :: i8(1)
COMPLEX_TUNNEL :: i8(-1)
// The map's lifts and gates the world keeps for its saves (World.lifts, World.gates).
MAX_WORLD_LIFTS :: game.MAX_ROOM_LIFTS
MAX_WORLD_GATES :: 8

Complex_Kind :: enum u8 { None, Data_Node, Train_Bridge, Giant_Trees }

Complex :: struct {
	kind:   Complex_Kind,
	// The cell of its layout's first row and column.
	origin: grid.Position,
	// The height of the level ground round it, and of its tunnels' floors (the relief's).
	floor:  i32,
}

Complex_Gate :: struct {
	cell, lever: grid.Position,
}

Complex_Layout :: struct {
	rows:    []string,
	gates:   []Complex_Gate,
	// How the blocks' tops look (render/expedition_floor_data.odin).
	surface: Site_Surface,
}

// Robotica cibernetica: two data platforms over a road, a walkway between them. Up the east one by its ramp; the west
// one has the secret and its guards, and under it a conduit, whose mouth on the road is shut by a gate opened from
// inside, with a shaft up to the top: once opened, the way up from the road.
@(private = "file")
DATA_NODE_ROWS := [?]string{
	"#########.......#########.............",
	"#$#######.......#########.............",
	"#####@###=======#########mlkjihgfedcba",
	"#########=======#########mlkjihgfedcba",
	"#########.......#########mlkjihgfedcba",
	"###Sttttt.......#########.............",
	"#########.......#########.............",
}
@(private = "file")
DATA_NODE_GATES := [?]Complex_Gate{{cell = {x = 8, y = 5}, lever = {x = 7, y = 5}}}

// Far West: the train's bridge over the canyon between two mesas. Up the west one by its trail; the east one has the
// secret and its guards, and a lift up its far side whose landing a gate shuts, opened from the top: once opened, the
// way up from below.
@(private = "file")
TRAIN_BRIDGE_ROWS := [?]string{
	".............########........########.",
	".............########........#$######.",
	"abcdefghijklm########========########.",
	"abcdefghijklm########========########L",
	"abcdefghijklm########========########.",
	".............########........####@###.",
	".............########........########.",
}
@(private = "file")
TRAIN_BRIDGE_GATES := [?]Complex_Gate{{cell = {x = 36, y = 3}, lever = {x = 35, y = 3}}}

// Giungla preistorica: a hill of bones with a cavern under it, open at both ends, where its guards are; up the hill by
// its slope, then over vine bridges to a first giant tree, with the secret in its top, and to a second one, which has a
// lift down to the ground; the second bridge has a gate opened from the first tree: once opened, the way up from below.
@(private = "file")
GIANT_TREES_ROWS := [?]string{
	"...............................................",
	".............#####t#####.......................",
	".............#####t#####.......................",
	".............#####t#####......#####......#####.",
	"abcdefghijklm###ttttt###......#####......#####.",
	"abcdefghijklm###tt&tt###======##$##======#####L",
	"abcdefghijklm###ttttt###......#####......#####.",
	".............#####t#####......#####......#####.",
	".............#####t#####.......................",
	".............#####t#####.......................",
	"...............................................",
}
@(private = "file")
GIANT_TREES_GATES := [?]Complex_Gate{{cell = {x = 36, y = 5}, lever = {x = 35, y = 5}}}

complex_layout :: proc(kind: Complex_Kind) -> Complex_Layout {
	switch kind {
	case .Data_Node: return {rows = DATA_NODE_ROWS[:], gates = DATA_NODE_GATES[:], surface = .Platform}
	case .Train_Bridge: return {rows = TRAIN_BRIDGE_ROWS[:], gates = TRAIN_BRIDGE_GATES[:]}
	case .Giant_Trees: return {rows = GIANT_TREES_ROWS[:], gates = GIANT_TREES_GATES[:]}
	case .None:
	}
	return {}
}

// The complexes of biome `b`, in order (none: .None).
complex_kinds :: proc(b: campaign.Biome) -> (kinds: [MAX_COMPLEXES]Complex_Kind) {
	#partial switch b {
	case .Cyber: kinds[0] = .Data_Node
	case .West: kinds[0] = .Train_Bridge
	case .Jungle: kinds[0] = .Giant_Trees
	}
	return
}

complex_biome :: proc(b: campaign.Biome) -> bool {
	return complex_kinds(b)[0] != .None
}

complex_size :: proc(layout: Complex_Layout) -> (width, height: int) {
	if len(layout.rows) == 0 { return }
	return len(layout.rows[0]), len(layout.rows)
}

// The mark of the layout's cell (x, y): '.' outside it.
complex_mark :: proc(layout: Complex_Layout, x, y: int) -> u8 {
	if y < 0 || y >= len(layout.rows) || x < 0 || x >= len(layout.rows[y]) { return '.' }
	return layout.rows[y][x]
}

complex_mark_block :: proc(mark: u8) -> bool {
	switch mark {
	case '#', '$', '@', 't', '&', 'S': return true
	}
	return false
}

complex_mark_tunnel :: proc(mark: u8) -> bool {
	return mark == 't' || mark == '&' || mark == 'S'
}

complex_mark_deck :: proc(mark: u8) -> bool {
	return mark == '=' || mark == 'L'
}

// How many steps over the floor a ramp's mark stands (0: no ramp).
complex_mark_ramp :: proc(mark: u8) -> i32 {
	if mark >= 'a' && mark <= 'm' { return i32(mark-'a')+1 }
	return 0
}

// The map's cell of the complex's layout cell `local`, on the layer its mark says: a tunnel's under the ground, a
// deck's over it, else the ground's.
complex_cell :: proc(c: Complex, local: grid.Position) -> grid.Position {
	mark := complex_mark(complex_layout(c.kind), local.x, local.y)
	layer := i8(grid.GROUND_LAYER)
	if complex_mark_tunnel(mark) { layer = COMPLEX_TUNNEL } else if complex_mark_deck(mark) { layer = COMPLEX_DECK }
	return {x = c.origin.x+local.x, y = c.origin.y+local.y, layer = layer}
}

// The middle cell of the complex's first bridge (its marks '='), on the deck's layer: in the middle of the rows it spans,
// in the middle of its first run along that row. The complex's origin if it has none.
complex_bridge_middle :: proc(c: Complex) -> grid.Position {
	layout := complex_layout(c.kind)
	width, height := complex_size(layout)
	first, last := -1, -1
	for y in 0..<height {
		for x in 0..<width { if layout.rows[y][x] == '=' { if first < 0 { first = y }; last = y } }
	}
	if first < 0 { return c.origin }
	row := (first+last)/2
	start := -1
	for x in 0..<width {
		if layout.rows[row][x] == '=' && start < 0 { start = x }
		if start >= 0 && (x == width-1 || layout.rows[row][x+1] != '=') { return complex_cell(c, {x = (start+x)/2, y = row}) }
	}
	return c.origin
}

// The complex whose layout holds column `p` (its index plus one, 0 for none), and the mark there.
complex_at :: proc(w: ^World, p: grid.Position) -> (index: int, mark: u8) {
	if w == nil { return 0, '.' }
	for c, i in w.complexes[:w.complex_count] {
		layout := complex_layout(c.kind)
		width, height := complex_size(layout)
		x, y := p.x-c.origin.x, p.y-c.origin.y
		if x >= 0 && y >= 0 && x < width && y < height { return i+1, layout.rows[y][x] }
	}
	return 0, '.'
}

// Whether the ground at column `p` is a complex's block or ramp: ground the relief does not make, with cliffs of its own.
complex_rock :: proc(w: ^World, p: grid.Position) -> bool {
	_, mark := complex_at(w, p)
	return complex_mark_block(mark) || complex_mark_ramp(mark) > 0
}

// The block over a tunnel's cell `p` (under the ground), as a box of cells (x0, y0, x1, y1, inclusive): its cells joined
// side by side to `p`'s column. False if `p` is in no complex's tunnel.
complex_tunnel_block :: proc(w: ^World, p: grid.Position) -> (low, high: grid.Position, ok: bool) {
	if p.layer >= grid.GROUND_LAYER { return }
	index, mark := complex_at(w, p)
	if index == 0 || !complex_mark_tunnel(mark) { return }
	c := w.complexes[index-1]
	layout := complex_layout(c.kind)
	width, height := complex_size(layout)
	seen: [64*16]bool
	queue: [64*16]grid.Position
	if width > 64 || height > 16 { return }
	start := grid.Position{x = p.x-c.origin.x, y = p.y-c.origin.y}
	queue[0], seen[start.y*64+start.x] = start, true
	low, high = start, start
	count := 1
	for head := 0; head < count; head += 1 {
		at := queue[head]
		low, high = {x = min(low.x, at.x), y = min(low.y, at.y)}, {x = max(high.x, at.x), y = max(high.y, at.y)}
		for step in ([4]grid.Position{{x = 1}, {x = -1}, {y = 1}, {y = -1}}) {
			next := grid.offset(at, step.x, step.y)
			if next.x < 0 || next.y < 0 || next.x >= width || next.y >= height || seen[next.y*64+next.x] { continue }
			if !complex_mark_block(complex_mark(layout, next.x, next.y)) { continue }
			seen[next.y*64+next.x] = true
			queue[count] = next
			count += 1
		}
	}
	return grid.offset(c.origin, low.x, low.y), grid.offset(c.origin, high.x, high.y), true
}

// The cells round a complex at `origin` over a layout of `width` by `height`: its own, with `margin` more on every side.
@(private = "file")
complex_bounds :: proc(origin: grid.Position, width, height, margin: int) -> (low, high: grid.Position) {
	return grid.offset(origin, -margin, -margin), grid.offset(origin, width-1+margin, height-1+margin)
}

// The ground the relief keeps level round a complex (relief.odin): its layout with COMPLEX_MARGIN cells all round.
@(private)
complex_level_zone :: proc(c: Complex) -> [2]grid.Position {
	width, height := complex_size(complex_layout(c.kind))
	low, high := complex_bounds(c.origin, width, height, COMPLEX_MARGIN)
	return {low, high}
}

// Whether a complex of `width` by `height` at `origin` stands on open ground: clear all round of the sites, the spawn,
// the central band, the patrols' ground, the mountain, the caves' massifs and the other complexes, on cells of the map
// that are floor or props (the relief and the props come after, and it clears them), on safe ground.
@(private = "file")
complex_free :: proc(w: ^World, data: ^level.Level, origin: grid.Position, width, height: int, others: []Complex) -> bool {
	side := size(w)
	low, high := complex_bounds(origin, width, height, COMPLEX_MARGIN)
	overlaps :: proc(low, high, other_low, other_high: grid.Position) -> bool {
		return high.x >= other_low.x && low.x <= other_high.x && high.y >= other_low.y && low.y <= other_high.y
	}
	// The west strip and the central band are the map's own ways across.
	if low.x < 14 || low.y < 5 || high.x >= side-6 || high.y >= side-6 { return false }
	if overlaps(low, high, {x = 0, y = side/2-5}, {x = side, y = side/2+5}) { return false }
	if mountain_present(w) {
		zone := mountain_zone()
		if overlaps(low, high, zone[0], zone[1]) { return false }
	}
	for cave in w.caves[:w.cave_count] {
		if cave.place.mountain { continue }
		zones := cave_level_zones(cave.place)
		for zone in zones { if overlaps(low, high, grid.offset(zone[0], -4, -4), grid.offset(zone[1], 4, 4)) { return false } }
	}
	for other in others {
		other_width, other_height := complex_size(complex_layout(other.kind))
		other_low, other_high := complex_bounds(other.origin, other_width, other_height, COMPLEX_MARGIN+4)
		if overlaps(low, high, other_low, other_high) { return false }
	}
	for &site in w.sites[:w.site_count] {
		site_low, site_high := site_bounds(&site)
		if overlaps(low, high, site_low, site_high) { return false }
	}
	for i in 0..<4 {
		anchor := grid.Position{x = side*(35+i*13)/100, y = side*(35+(i%2)*28)/100}
		if overlaps(low, high, grid.offset(anchor, -4, -4), grid.offset(anchor, 4, 4)) { return false }
	}
	if data.has_player_spawn && overlaps(low, high, grid.offset(data.player_spawn, -12, -12), grid.offset(data.player_spawn, 12, 12)) { return false }
	for y in low.y..=high.y {
		for x in low.x..=high.x {
			p := grid.Position{x = x, y = y}
			tile, found := level.tile_at(data, p)
			if !found || tile.kind != .Floor && tile.kind != .Wall { return false }
			if _, owned := level.structure_index_at(data, p); owned { return false }
			#partial switch terrain(w.biome, p) {
			case .Water, .Lava, .Bridge, .Gravity: return false
			}
		}
	}
	return true
}

// The places of the biome's complexes, before the relief, which keeps their ground level (relief.odin): the world's
// complexes, as many of the biome's as fit. A pure function of the biome and of the map made so far.
@(private)
plan_complexes :: proc(w: ^World, data: ^level.Level) {
	side := size(w)
	r := rng.create(0xC0A1E000+u64(w.biome))
	for kind in complex_kinds(w.biome) {
		if kind == .None || w.complex_count >= MAX_COMPLEXES { break }
		width, height := complex_size(complex_layout(kind))
		if side-width-24 <= 0 || side-height-16 <= 0 { continue }
		for _ in 0..<6000 {
			origin := grid.Position{x = 16+int(rng.next_u64(&r)%u64(side-width-24)), y = 8+int(rng.next_u64(&r)%u64(side-height-16))}
			if !complex_free(w, data, origin, width, height, w.complexes[:w.complex_count]) { continue }
			w.complexes[w.complex_count] = {kind = kind, origin = origin}
			w.complex_count += 1
			break
		}
	}
}

// Raises a complex on the level ground the relief left round it: its blocks and ramps, its decks and tunnels, its lifts
// and its gates, shut; the props round it cleared.
@(private = "file")
build_complex :: proc(data: ^level.Level, c: Complex) {
	layout := complex_layout(c.kind)
	width, height := complex_size(layout)
	low, high := complex_bounds(c.origin, width, height, COMPLEX_MARGIN)
	for y in low.y..=high.y {
		for x in low.x..=high.x {
			if tile, found := level.tile_at(data, {x = x, y = y}); found && tile.kind == .Wall { _ = level.set_tile(data, {x = x, y = y}, {kind = .Floor}) }
		}
	}
	top := c.floor+COMPLEX_TOP
	for y in 0..<height {
		for x in 0..<width {
			mark := layout.rows[y][x]
			ground := grid.offset(c.origin, x, y)
			if complex_mark_block(mark) { _ = level.set_height(data, ground, top) }
			if steps := complex_mark_ramp(mark); steps > 0 { _ = level.set_height(data, ground, c.floor+steps) }
			if complex_mark_tunnel(mark) {
				cell := grid.Position{x = ground.x, y = ground.y, layer = COMPLEX_TUNNEL}
				_ = level.set_tile(data, cell, {kind = .Floor})
				_ = level.set_height(data, cell, c.floor)
				// The shaft's platform waits at the top, where one first comes to it.
				if mark == 'S' { _ = level.add_lift(data, cell, ground, 1) }
			}
			if complex_mark_deck(mark) {
				cell := grid.Position{x = ground.x, y = ground.y, layer = COMPLEX_DECK}
				_ = level.set_tile(data, cell, {kind = .Floor})
				_ = level.set_height(data, cell, top)
				if mark == 'L' { _ = level.add_lift(data, ground, cell, 1) }
			}
		}
	}
	for gate in layout.gates { _ = level.add_gate(data, complex_cell(c, gate.cell), complex_cell(c, gate.lever)) }
}

// The map's complexes, after the relief: each on the level ground round it, at the height the relief left there.
@(private)
place_complexes :: proc(w: ^World, data: ^level.Level) {
	for &c in w.complexes[:w.complex_count] {
		c.floor = level.height_at(data, grid.offset(c.origin, -1, -1))
		build_complex(data, c)
	}
}

// The cells of the layout with mark `mark`, on the map (the first `len(cells)` of them, row by row).
@(private = "file")
complex_marked :: proc(c: Complex, mark: u8, cells: []grid.Position) -> (count: int) {
	layout := complex_layout(c.kind)
	width, height := complex_size(layout)
	for y in 0..<height {
		for x in 0..<width {
			if layout.rows[y][x] != mark || count >= len(cells) { continue }
			cells[count] = complex_cell(c, {x = x, y = y})
			count += 1
		}
	}
	return
}

// The complexes' secrets and guards, on the map as it is after the retouches (generate): credits and a relic on the
// secret's cell and beside it, taken by hand; a group of the biome's foes where its guards stand.
@(private)
fill_complexes :: proc(w: ^World, data: ^level.Level) {
	for c, i in w.complexes[:w.complex_count] {
		r := rng.create(w.seed~0xC0A1E5~u64(i+1)*0x9E3779B9)
		cells: [1]grid.Position
		if complex_marked(c, '$', cells[:]) == 1 {
			secret := cells[0]
			beside := secret
			for step in ([4]grid.Position{{x = -1}, {x = 1}, {y = -1}, {y = 1}}) {
				next := grid.offset(secret, step.x, step.y)
				if tile, _ := level.tile_at(data, next); tile.kind == .Floor && level.height_at(data, next) == level.height_at(data, secret) { beside = next; break }
			}
			if tile, _ := level.tile_at(data, secret); tile.kind == .Floor {
				_ = add_drop(w, secret, campaign.make_item(.Credits, 40+i32(rng.next_u64(&r)%40)), 0, true)
				relic := 1+i32(rng.next_u64(&r)%(u64(game.Relic_Id.Count)-1))
				_ = add_drop(w, beside, campaign.make_item(.Relic, 1, relic), 0, true)
			}
		}
		for mark in ([2]u8{'@', '&'}) {
			if complex_marked(c, mark, cells[:]) == 1 { add_group(w, data, -1, cells[0], 2+rank(w.biome)/2, false, false) }
		}
	}
}

// The map's lifts and gates, kept in the world for its saves (snapshot.odin restores them on the map).
@(private)
keep_lifts_and_gates :: proc(w: ^World, data: ^level.Level) {
	w.lift_count, w.gate_count = 0, 0
	for lift in data.lifts {
		if w.lift_count >= MAX_WORLD_LIFTS { break }
		w.lifts[w.lift_count] = lift
		w.lift_count += 1
	}
	for gate in data.gates {
		if w.gate_count >= MAX_WORLD_GATES { break }
		w.gates[w.gate_count] = gate
		w.gate_count += 1
	}
}
