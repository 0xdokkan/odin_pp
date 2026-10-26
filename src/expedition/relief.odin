package expedition

import "core:math"
import campaign "../campaign"
import grid "../engine/grid"
import level "../level"

// THE RELIEF OF THE EXPEDITIONS (Fase 3 of docs/piano-griglia.md): every biome has hills, dunes,
// terraces or plateaus of its own, in steps of height (level.heights; a step is drawn
// game.HEIGHT_STEP_DRAWN of a cell tall, a walker climbs one step at a time and a cliff of two or
// more stops it). Like the rest of the biome's geography it is a pure function of the biome and the
// coordinates, so the same biome has the same relief at every run, whatever the seed.
//
//   Cyber     raised data platforms, up a stair
//   West      mesas up a stair, low swells between
//   Jungle    many small hills
//   City      raised plazas up a few steps
//   Egypt     long dunes of sand
//   Vietnam   terraced hills: a step every two cells
//   Snow      plateaus up a stair, drifts between
//   Inferno   ledges and rock spires
//   Gothic    graveyard mounds round a crypt hill
//   Sky       islands at their own heights, with sloping bridges between
//   Space     craters, with a raised rim
//   Secret    a few low mounds (the boulder's hill is a complex: complex.odin)
//
// The ground is made in two layers. The smooth one (hills, dunes, swells) never has a cliff: it is
// relaxed so that neighbouring cells are at most one step apart, and flat round everything that must
// stay level (the sites and their courtyards, the spawn, the patrols' ground). The plateau one has its
// own cliffs, only where it is well clear of those, with a stair up one side.

RELIEF_MAX :: u8(12)

// THE RAISED BIOMES (Fase 7 of docs/piano-profondita.md, the user's choice for its second group): City pop, Egitto and
// Vietnam have all their ground raised by a base, so that there is room under it for their networks on the deep layer
// (network.odin); the surface is the same, and drawn as before (level.Level.base). In the third group the Neve too, for
// the crevasse dug in its snow (complex.odin), and the Gotico, for its crypt and catacombs (network.odin); in the fourth
// the Spazio, for its deep craters and the galleries between them.
EXPEDITION_RAISED_BASE :: level.LAYER_SPACING+2

biome_base :: proc(b: campaign.Biome) -> i32 {
	#partial switch b {
	case .City, .Egypt, .Vietnam, .Snow, .Gothic, .Space: return EXPEDITION_RAISED_BASE
	}
	return 0
}

@(private = "file")
Relief :: struct {
	size:      int,
	smooth:    []u8,
	plateau:   []u8,
	// Cells that must stay at the height they were given (a site, the spawn).
	fixed:     []bool,
	// The tiles, to know where there is nothing.
	tiles:     []level.Tile,
}

@(private = "file")
relief_hash :: proc(a, b: int, salt: u32) -> u32 {
	h := u32(a+4099)*0x9e3779b9 ~ u32(b+1873)*0x85ebca6b ~ salt*0xc2b2ae35
	h ~= h>>15
	h *= 0x2c1b3c6d
	h ~= h>>12
	h *= 0x297a2d39
	h ~= h>>15
	return h
}

@(private = "file")
paint_max :: proc(r: ^Relief, layer: []u8, x, y: int, steps: int) {
	if x < 2 || y < 2 || x >= r.size-2 || y >= r.size-2 || steps <= 0 { return }
	at := y*r.size+x
	if r.tiles[at].kind == .Void { return }
	layer[at] = max(layer[at], u8(min(steps, int(RELIEF_MAX))))
}

// A cone: `height` steps at (cx, cy), one fewer every `ring` cells away (scaled by `ax` along x and `ay`
// along y, both at most 1, so that two neighbouring cells are never more than a step apart).
@(private = "file")
paint_cone :: proc(r: ^Relief, cx, cy, height: int, ring, ax, ay: f32) {
	reach := int(f32(height)*ring/min(ax, ay))+2
	for y in cy-reach..=cy+reach {
		for x in cx-reach..=cx+reach {
			dx, dy := f32(x-cx)*ax, f32(y-cy)*ay
			d := math.sqrt(dx*dx+dy*dy)
			steps := height-int(d/ring)
			paint_max(r, r.smooth, x, y, steps)
		}
	}
}

// A ring ridge: the crater's rim, `height` steps at radius `radius`, falling away on both sides.
@(private = "file")
paint_rim :: proc(r: ^Relief, cx, cy: int, radius: f32, height: int, ring: f32) {
	reach := int(radius+f32(height)*ring)+2
	for y in cy-reach..=cy+reach {
		for x in cx-reach..=cx+reach {
			dx, dy := f32(x-cx), f32(y-cy)
			d := abs(math.sqrt(dx*dx+dy*dy)-radius)
			paint_max(r, r.smooth, x, y, height-int(d/ring))
		}
	}
}

// Scatters `paint` over the map, one possible motif in every `block`-cell block, with `chance` percent.
@(private = "file")
scatter :: proc(r: ^Relief, block, chance: int, salt: u32, paint: proc(r: ^Relief, x, y: int, h: u32)) {
	for by := 0; by*block < r.size; by += 1 {
		for bx := 0; bx*block < r.size; bx += 1 {
			h := relief_hash(bx, by, salt)
			if int(h%100) >= chance { continue }
			margin := block/4
			x := bx*block+margin+int((h>>8)%u32(max(1, block-2*margin)))
			y := by*block+margin+int((h>>16)%u32(max(1, block-2*margin)))
			paint(r, x, y, h)
		}
	}
}

// A plateau: `rect` of `height` steps with a three-cell-wide stair going down from one of its sides.
// Only where it and its stair are clear (`clear` says so for a bounding box).
@(private = "file")
Plateau :: struct { x, y, width, depth: int, height: int, side: int }

@(private = "file")
plateau_box :: proc(p: Plateau) -> (low, high: grid.Position) {
	low, high = {x = p.x, y = p.y}, {x = p.x+p.width-1, y = p.y+p.depth-1}
	run := p.height
	switch p.side {
	case 0: low.y -= run          // the stair runs up from the north
	case 1: high.x += run         // from the east
	case 2: high.y += run         // from the south
	case 3: low.x -= run          // from the west
	}
	return
}

// The height of the plateau layer at a cell: the top inside the rect, the stair outside it.
@(private = "file")
plateau_height :: proc(p: Plateau, x, y: int) -> int {
	if x >= p.x && x < p.x+p.width && y >= p.y && y < p.y+p.depth { return p.height }
	mid_x, mid_y := p.x+p.width/2, p.y+p.depth/2
	switch p.side {
	case 0: if y < p.y && abs(x-mid_x) <= 1 { return p.height-(p.y-y) }
	case 1: if x >= p.x+p.width && abs(y-mid_y) <= 1 { return p.height-(x-(p.x+p.width-1)) }
	case 2: if y >= p.y+p.depth && abs(x-mid_x) <= 1 { return p.height-(y-(p.y+p.depth-1)) }
	case 3: if x < p.x && abs(y-mid_y) <= 1 { return p.height-(p.x-x) }
	}
	return 0
}

// Per biome: what the smooth layer holds.
@(private = "file")
paint_smooth :: proc(r: ^Relief, b: campaign.Biome) {
	n := r.size
	switch b {
	case .Cyber:
		scatter(r, 26, 85, 10, proc(r: ^Relief, x, y: int, h: u32) { paint_cone(r, x, y, 1, 6, 1, 0.8) })
	case .West:
		scatter(r, 22, 80, 11, proc(r: ^Relief, x, y: int, h: u32) { paint_cone(r, x, y, 1+int(h%2), 4, 1, 0.7) })
	case .Jungle:
		scatter(r, 18, 85, 12, proc(r: ^Relief, x, y: int, h: u32) { paint_cone(r, x, y, 2+int(h%2), 1.7, 1, 1) })
	case .City:
		scatter(r, 24, 80, 13, proc(r: ^Relief, x, y: int, h: u32) { paint_cone(r, x, y, 1, 5, 0.9, 0.9) })
	case .Egypt:
		scatter(r, 26, 90, 14, proc(r: ^Relief, x, y: int, h: u32) {
			// Long dunes, along x or along y.
			if h&1 == 0 { paint_cone(r, x, y, 3+int((h>>3)%2), 1.5, 0.35, 1) } else { paint_cone(r, x, y, 3+int((h>>3)%2), 1.5, 1, 0.35) }
		})
	case .Vietnam:
		scatter(r, 40, 85, 15, proc(r: ^Relief, x, y: int, h: u32) { paint_cone(r, x, y, 4+int(h%2), 2, 1, 0.85) })
	case .Snow:
		scatter(r, 20, 75, 16, proc(r: ^Relief, x, y: int, h: u32) { paint_cone(r, x, y, 1+int(h%2), 3, 1, 1) })
	case .Inferno:
		scatter(r, 18, 70, 17, proc(r: ^Relief, x, y: int, h: u32) { paint_cone(r, x, y, 3, 1.2, 1, 1) })
	case .Gothic:
		scatter(r, 12, 70, 18, proc(r: ^Relief, x, y: int, h: u32) { paint_cone(r, x, y, 2, 2, 1, 1) })
		paint_cone(r, n*2/3, n/2+16, 4, 2, 1, 1)
	case .Sky:
		// Islands of 21 by 21 cells in blocks of 24, each at a height of its own; the bridges between
		// them slope from one to the other.
		island :: proc(i, j: int) -> int { return 2+((i*7+j*3)%3) }
		for y in 2..<n-2 {
			for x in 2..<n-2 {
				bx, by := x%24, y%24
				i, j := x/24, y/24
				steps := 0
				switch {
				case bx < 21 && by < 21: steps = island(i, j)
				case bx >= 21 && by < 21:
					// Ground in the gap between the islands (i, j) and (i+1, j) (a bridge, or the middle's
					// walkway): it slopes from one to the other.
					a, c := island(i, j), island(i+1, j)
					steps = a+(c-a)*(bx-20)/4
				case by >= 21 && bx < 21:
					a, c := island(i, j), island(i, j+1)
					steps = a+(c-a)*(by-20)/4
				case:
					steps = island(i, j)
				}
				paint_max(r, r.smooth, x, y, steps)
			}
		}
	case .Space:
		scatter(r, 36, 80, 19, proc(r: ^Relief, x, y: int, h: u32) { paint_rim(r, x, y, 6+f32(h%4), 3, 1.2) })
	case .Secret:
		// The great hill in the middle the sites' level ground had cut down to a ridge: the boulder's hill is now a
		// complex of its own (complex.odin, Fase 7 of docs/piano-profondita.md).
		scatter(r, 30, 40, 20, proc(r: ^Relief, x, y: int, h: u32) { paint_cone(r, x, y, 2, 2, 1, 1) })
	case .Count:
	}
}

// Per biome: the plateaus (height, size, how many blocks have one).
@(private = "file")
plateau_plan :: proc(b: campaign.Biome) -> (block, chance, height: int, width, depth: [2]int) {
	switch b {
	case .Cyber: return 44, 70, 3, {10, 14}, {7, 10}
	case .West: return 48, 70, 4, {12, 16}, {8, 11}
	case .City: return 40, 60, 2, {9, 12}, {9, 12}
	case .Snow: return 50, 75, 5, {12, 16}, {9, 12}
	case .Inferno: return 46, 65, 3, {8, 11}, {6, 9}
	case .Jungle, .Egypt, .Vietnam, .Gothic, .Sky, .Space, .Secret, .Count: return 0, 0, 0, {}, {}
	}
	return 0, 0, 0, {}, {}
}

// Writes the biome's relief onto the map: level ground round the sites, the spawn and the patrols' ground.
@(private)
apply_relief :: proc(w: ^World, data: ^level.Level) {
	size := w.side_length
	zones := make([dynamic][2]grid.Position, context.temp_allocator)
	for &site in w.sites[:w.site_count] {
		low, high := site_bounds(&site)
		append(&zones, [2]grid.Position{grid.offset(low, -4, -4), grid.offset(high, 4, 4)})
	}
	append(&zones, [2]grid.Position{grid.offset(data.player_spawn, -8, -8), grid.offset(data.player_spawn, 8, 8)})
	for i in 0..<4 {
		at := grid.Position{x = size*(35+i*13)/100, y = size*(35+(i%2)*28)/100}
		append(&zones, [2]grid.Position{grid.offset(at, -6, -6), grid.offset(at, 6, 6)})
	}
	if mountain_present(w) { append(&zones, mountain_zone()) }
	// Round each cave's massif on the open map, and in front of its mouth (cave.odin).
	for cave in w.caves[:w.cave_count] {
		if cave.place.mountain { continue }
		for zone in cave_level_zones(cave.place) { append(&zones, zone) }
	}
	// Round each complex (complex.odin).
	for c in w.complexes[:w.complex_count] { append(&zones, complex_level_zone(c)) }
	if w.biome == .Gothic { append(&zones, [2]grid.Position{{x = size/2-5, y = size/2-15}, {x = size/2+5, y = size/2-5}}) }
	heights := relief_heights(w.biome, data.tiles.cells[:], size, zones[:])
	// The biome's base under all of it.
	for &steps in heights { steps += u8(w.base) }
	_ = level.set_height_table(data, heights)
	data.base = w.base
}

// Heights, one per cell in the tiles' order, for biome `b` on `tiles` (size by size). `zones` are the
// rectangles that must be level (min and max cell, inclusive) and stay at the height the smooth layer
// has at their middle.
relief_heights :: proc(b: campaign.Biome, tiles: []level.Tile, size: int, zones: [][2]grid.Position) -> []u8 {
	count := size*size
	r := Relief{size = size, tiles = tiles}
	r.smooth = make([]u8, count, context.temp_allocator)
	r.plateau = make([]u8, count, context.temp_allocator)
	r.fixed = make([]bool, count, context.temp_allocator)
	paint_smooth(&r, b)
	// The level ground. Zones that overlap are one level ground (one height); each takes the height the
	// smooth layer reaches in the first of them.
	group := make([]int, len(zones), context.temp_allocator)
	for i in 0..<len(zones) { group[i] = i }
	find :: proc(group: []int, i: int) -> int {
		at := i
		for group[at] != at { at = group[at] }
		return at
	}
	for i in 0..<len(zones) {
		for j in i+1..<len(zones) {
			a, c := zones[i], zones[j]
			// Zones that touch, or are only a cell or two apart, share one height too.
			near := 2
			if a[0].x <= c[1].x+near && c[0].x <= a[1].x+near && a[0].y <= c[1].y+near && c[0].y <= a[1].y+near { group[find(group, j)] = find(group, i) }
		}
	}
	bases := make([]u8, len(zones), context.temp_allocator)
	for i in 0..<len(zones) {
		if find(group, i) != i { continue }
		// The height of the ground the zone mostly stands on: the tallest of its cells, which in the Sky is its island.
		for y in max(0, zones[i][0].y)..=min(size-1, zones[i][1].y) {
			for x in max(0, zones[i][0].x)..=min(size-1, zones[i][1].x) { bases[i] = max(bases[i], r.smooth[y*size+x]) }
		}
	}
	// Level ground is at the bottom, so that ground levelled at two places never needs a cliff between
	// them. In the Sky, where every island is at a height of its own, it keeps the height of the island it
	// is on, and the ground round it is brought up or down to meet it.
	for zone, i in zones {
		base := bases[find(group, i)] if b == .Sky else 0
		for y in max(0, zone[0].y)..=min(size-1, zone[1].y) {
			for x in max(0, zone[0].x)..=min(size-1, zone[1].x) {
				if tiles[y*size+x].kind == .Void { continue }
				r.smooth[y*size+x] = base
				r.fixed[y*size+x] = true
			}
		}
	}
	relax(&r, b == .Sky)
	// The plateaus, where well clear of every level zone.
	clearance := distance_from_fixed(&r)
	block, chance, height, widths, depths := plateau_plan(b)
	if block > 0 {
		for by := 0; by*block < size; by += 1 {
			for bx := 0; bx*block < size; bx += 1 {
				if int(relief_hash(bx, by, 30)%100) >= chance { continue }
				// A few places are tried in turn, the first clear one is taken.
				for attempt in u32(0)..<8 {
				h := relief_hash(bx, by, 31+attempt)
				plateau := Plateau{
					width = widths[0]+int((h>>4)%u32(widths[1]-widths[0]+1)),
					depth = depths[0]+int((h>>10)%u32(depths[1]-depths[0]+1)),
					height = height, side = int((h>>16)%4),
				}
				margin := height+3
				plateau.x = bx*block+margin+int((h>>18)%u32(max(1, block-plateau.width-2*margin)))
				plateau.y = by*block+margin+int((h>>24)%u32(max(1, block-plateau.depth-2*margin)))
				low, high := plateau_box(plateau)
				if low.x < 4 || low.y < 4 || high.x >= size-4 || high.y >= size-4 { continue }
				clear := true
				for y in low.y-2..=high.y+2 {
					for x in low.x-2..=high.x+2 {
						at := y*size+x
						if tiles[at].kind == .Void || clearance[at] < 2 { clear = false }
					}
				}
				if !clear { continue }
				for y in low.y..=high.y {
					for x in low.x..=high.x { paint_max(&r, r.plateau, x, y, plateau_height(plateau, x, y)) }
				}
				break
				}
			}
		}
	}
	heights := make([]u8, count, context.temp_allocator)
	for i in 0..<count { heights[i] = max(r.smooth[i], r.plateau[i]) }
	return heights
}

// Makes the smooth layer one step at most from cell to cell, keeping the fixed cells as they are: a cell
// is never higher than a neighbour plus one. Only ever lowering, it settles on the highest ground that
// has no cliff (the fixed cells are the lowest points, so none of them has to rise). In the Sky, where
// the fixed cells are at different heights, a cell below its neighbours' reach is raised too.
@(private = "file")
relax :: proc(r: ^Relief, both_ways: bool) {
	n := r.size
	for pass in 0..<200 {
		changed := false
		forward := pass%2 == 0
		for index in 0..<n*n {
			at := index if forward else n*n-1-index
			if r.fixed[at] || r.tiles[at].kind == .Void { continue }
			x, y := at%n, at/n
			ceiling, floor := int(RELIEF_MAX), 0
			for step in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
				nx, ny := x+step.x, y+step.y
				if nx < 0 || ny < 0 || nx >= n || ny >= n || r.tiles[ny*n+nx].kind == .Void { continue }
				ceiling = min(ceiling, int(r.smooth[ny*n+nx])+1)
				floor = max(floor, int(r.smooth[ny*n+nx])-1)
			}
			if int(r.smooth[at]) > ceiling { r.smooth[at] = u8(ceiling); changed = true }
			else if both_ways && int(r.smooth[at]) < floor { r.smooth[at] = u8(floor); changed = true }
		}
		if !changed { break }
	}
}

// How far, in steps of one cell (Manhattan), every cell is from the nearest fixed one.
@(private = "file")
distance_from_fixed :: proc(r: ^Relief) -> []i16 {
	n := r.size
	dist := make([]i16, n*n, context.temp_allocator)
	queue := make([]int, n*n, context.temp_allocator)
	head, tail := 0, 0
	for at in 0..<n*n {
		if r.fixed[at] { queue[tail] = at; tail += 1 } else { dist[at] = 32000 }
	}
	for head < tail {
		at := queue[head]
		head += 1
		x, y := at%n, at/n
		for step in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
			nx, ny := x+step.x, y+step.y
			if nx < 0 || ny < 0 || nx >= n || ny >= n { continue }
			next := ny*n+nx
			if dist[next] <= dist[at]+1 { continue }
			dist[next] = dist[at]+1
			queue[tail] = next
			tail += 1
		}
	}
	return dist
}
