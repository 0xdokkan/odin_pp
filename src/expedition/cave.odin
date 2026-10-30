package expedition

import campaign "../campaign"
import game "../game"
import grid "../engine/grid"
import level "../level"
import rng "../engine/rng"

// THE CAVES (Fase 5 of docs/piano-profondita.md; they came with Fase 5 of docs/piano-griglia.md). A cave is the layer
// under a massif of rock (level/layers.odin): its rooms are cells of CAVE_LAYER at the height of the ground round the
// massif, and the player walks in through its mouth, with no fade and no other map. Four biomes have them: the Snow
// (one room in the spiral mountain's core, its mouth on the path near halfway up, and more on the open map), the Far
// West, the Egypt and the Inferno.
//
// Every place has its massif and its cave at every run, the same geography: the places and the plans come from the
// biome alone, chosen before the relief, which keeps the ground round each massif level (relief.odin). The run picks
// which of them hold foes and a secret, between one and three, the mountain's always; the others are empty. Each cave
// has a site, at its mouth, which the map marks once found.
//
//   ####################################      the massif: the plan of level/cave.odin under rock, with a ring of rock
//   #....#####........#######.....#####       round it; a tunnel goes from its first room out through the ring to the
// @=....................................#     mouth (@) on the open ground, in front of the west side.

MAX_CAVES :: 3
CAVE_LAYER :: i8(-1)
// The massif's height over the ground round it at its edge: the cave's room and the rock over it, and two steps more.
// Inside the edge it rises a step a cell, up to CAVE_MASSIF_RISE more.
CAVE_MASSIF_HEIGHT :: level.LAYER_SPACING+2
CAVE_MASSIF_RISE :: 4
// The fewest cells of the mountain's room, and the most.
CAVE_MOUNTAIN_ROOM_MIN :: 12
CAVE_MOUNTAIN_ROOM_MAX :: 96

Cave_State :: enum u8 { Unvisited, Visited, Looted }
Cave :: struct {
	site:      int,
	// The run's: what its foes and its secret are.
	seed:      u64,
	state:     Cave_State,
	// Whether the run gave it foes and a secret.
	inhabited: bool,
	// Where it is: the same for the biome at every run.
	place:     Cave_Place,
}

// A place for a cave: its box on the map (its cells are on CAVE_LAYER; a ring of rock goes round it: the plan's board,
// or the mountain's room's), the seed of its plan (level/cave.odin; the mountain's room has none), the height of its
// floor, the open ground in front of its mouth, and its first cell inside.
Cave_Place :: struct {
	origin:         grid.Position,
	width, height:  int,
	plan_seed:      u64,
	floor:          i32,
	mountain:       bool,
	mouth, arrival: grid.Position,
}

cave_biome :: proc(b: campaign.Biome) -> bool {
	#partial switch b {
	case .Snow, .West, .Egypt, .Inferno: return true
	}
	return false
}

// The cell of cave `index` at `local` in its box, on its layer.
cave_world_cell :: proc(w: ^World, index: int, local: grid.Position) -> grid.Position {
	origin := w.caves[index].place.origin
	return {x = origin.x+local.x, y = origin.y+local.y, layer = CAVE_LAYER}
}

// Whether something marked `tag` (a group's, a drop's: the cave it was made in, or 0) is on the map with the player:
// always, now that the caves are a layer of the map and not a map of their own.
in_scope :: proc(w: ^World, tag: u8) -> bool {
	return w != nil
}

// The ground of a cell: the biome's, but nothing of the open map's terrain is under the rock.
ground :: proc(w: ^World, p: grid.Position) -> Terrain {
	if p.layer != grid.GROUND_LAYER { return .Plain }
	return terrain(w.biome, p)
}

// The cave whose mouth is site `site` (-1 if it is not one).
cave_of_site :: proc(w: ^World, site: int) -> int {
	for cave, i in w.caves[:w.cave_count] { if cave.site == site { return i } }
	return -1
}

// The cave that holds `p`, its rock's ring included: its index plus one, 0 for none (the open map).
cave_at :: proc(w: ^World, p: grid.Position) -> int {
	if w == nil || p.layer != CAVE_LAYER { return 0 }
	for cave, i in w.caves[:w.cave_count] {
		box := cave.place
		if p.x >= box.origin.x-1 && p.y >= box.origin.y-1 && p.x <= box.origin.x+box.width && p.y <= box.origin.y+box.height { return i+1 }
	}
	return 0
}

// Whether the ground cell at `p`'s column is the rock of a massif on the open map, its ring included (the mountain's cells
// are the mountain's): a top no one walks on, over a cave.
cave_rock :: proc(w: ^World, p: grid.Position) -> bool {
	if w == nil { return false }
	for cave in w.caves[:w.cave_count] {
		box := cave.place
		if box.mountain { continue }
		if p.x >= box.origin.x-1 && p.y >= box.origin.y-1 && p.x <= box.origin.x+box.width && p.y <= box.origin.y+box.height { return true }
	}
	return false
}

@(private = "file")
CAVE_STEPS :: [4]grid.Position{{x = 0, y = -1}, {x = 1, y = 0}, {x = 0, y = 1}, {x = -1, y = 0}}

// The mountain's room (the Snow's), as offsets from the mountain's centre: going down the path from near halfway up,
// the first cell of the path beside rock deep enough for a room, and the cells, 4-neighbours of one another, whose
// ground stands LAYER_SPACING steps over that path cell or more. The room's floor is at that cell's height; the path
// cell is its mouth, the first cell of the room its arrival.
@(private = "file")
mountain_cave_room :: proc(room: ^[CAVE_MOUNTAIN_ROOM_MAX]grid.Position) -> (count: int, mouth, arrival: grid.Position, floor: i32, ok: bool) {
	deep :: proc(offset: grid.Position, floor: i32) -> bool {
		_, inside := level.mountain_progress(offset)
		return inside && i32(level.mountain_height(offset)) >= floor+level.LAYER_SPACING
	}
	for step in 0..<50 {
		path := level.mountain_path_cell(1.75-f32(step)*0.02)
		floor = i32(level.mountain_height(path))
		for direction in CAVE_STEPS {
			start := grid.offset(path, direction.x, direction.y)
			if !deep(start, floor) { continue }
			room[0] = start
			count = 1
			for head := 0; head < count; head += 1 {
				for next_step in CAVE_STEPS {
					next := grid.offset(room[head], next_step.x, next_step.y)
					if count >= CAVE_MOUNTAIN_ROOM_MAX || !deep(next, floor) { continue }
					seen := false
					for cell in room[:count] { if cell == next { seen = true; break } }
					if !seen { room[count] = next; count += 1 }
				}
			}
			if count >= CAVE_MOUNTAIN_ROOM_MIN { return count, path, start, floor, true }
		}
	}
	return
}

// The board of a cave's plan in the biome: today's, but smaller in the Far West, whose map has no room for it (the
// user's choice in Fase 5).
cave_board :: proc(b: campaign.Biome) -> (width, height: int) {
	if b == .West { return 24, 14 }
	return level.CAVE_WIDTH, level.CAVE_HEIGHT
}

// The cells round a massif at `origin` over a board of `width` by `height`: its own (the plan and the ring of rock round
// it), with `margin` more on every side; and the apron of open ground in front of its mouth.
@(private = "file")
massif_bounds :: proc(origin: grid.Position, width, height, margin: int) -> (low, high: grid.Position) {
	return grid.offset(origin, -1-margin, -1-margin), grid.offset(origin, width+margin, height+margin)
}

// The mouth's site's ground (site_layout's .Cave): clear of props, level and safe.
@(private = "file")
massif_apron :: proc(mouth: grid.Position) -> (low, high: grid.Position) {
	return grid.offset(mouth, -3, -2), grid.offset(mouth, 0, 2)
}

// The ground the relief keeps level round a place on the open map (relief.odin): the massif with two cells all round,
// and the apron in front of its mouth.
@(private)
cave_level_zones :: proc(place: Cave_Place) -> (zones: [2][2]grid.Position) {
	low, high := massif_bounds(place.origin, place.width, place.height, 2)
	apron_low, apron_high := massif_apron(place.mouth)
	return {{low, high}, {grid.offset(apron_low, -1, -1), grid.offset(apron_high, 0, 1)}}
}

// Whether a massif over a board of `width` by `height` at `origin`, with its mouth at `mouth`, stands on open ground, the
// ground in front of its mouth too: a cell clear all round of the sites, the structures, the spawn, the central band,
// the patrols' anchors, the mountain and the other massifs, and its mouth on safe ground. Scattered props (Wall cells on
// open ground) are no matter, nor the ground's hazards under the rock: the rock covers them. The heights do not matter
// either: the relief comes after, and keeps it all level.
@(private = "file")
massif_free :: proc(w: ^World, data: ^level.Level, origin, mouth: grid.Position, width, height: int, others: []Cave_Place) -> bool {
	side := size(w)
	low, high := massif_bounds(origin, width, height, 1)
	apron_low, apron_high := massif_apron(mouth)
	low = {x = min(low.x, apron_low.x), y = min(low.y, apron_low.y)}
	high = {x = max(high.x, apron_high.x), y = max(high.y, apron_high.y)}
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
	for other in others {
		if other.mountain { continue }
		other_low, other_high := massif_bounds(other.origin, other.width, other.height, 4)
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
		}
	}
	// The way in is safe ground: no lava, water, bridge or well in front of the mouth.
	for y in apron_low.y..=apron_high.y {
		for x in apron_low.x..=apron_high.x {
			#partial switch terrain(w.biome, {x = x, y = y}) {
			case .Water, .Lava, .Bridge, .Gravity: return false
			}
		}
	}
	return true
}

// The seed of the plan of the biome's `index`-th cave place: fixed, like the rest of its geography.
@(private = "file")
cave_plan_seed :: proc(w: ^World, index: int) -> u64 {
	return 0xCA7E5EED+u64(w.biome)*64+u64(index)
}

// The places of the biome's caves: the mountain's room first in the Snow, then massifs on the open map, as many as fit,
// up to MAX_CAVES. A pure function of the biome and of the map made so far.
@(private = "file")
cave_places :: proc(w: ^World, data: ^level.Level) -> (places: [MAX_CAVES]Cave_Place, count: int) {
	if mountain_present(w) {
		room: [CAVE_MOUNTAIN_ROOM_MAX]grid.Position
		if cells, mouth, arrival, floor, ok := mountain_cave_room(&room); ok {
			low, high := room[0], room[0]
			for cell in room[:cells] {
				low = {x = min(low.x, cell.x), y = min(low.y, cell.y)}
				high = {x = max(high.x, cell.x), y = max(high.y, cell.y)}
			}
			at := mountain_cell(arrival)
			// The mountain stands on the biome's base (level.mountain_stamp).
			places[count] = {origin = mountain_cell(low), width = high.x-low.x+1, height = high.y-low.y+1, floor = w.base+floor, mountain = true,
				mouth = mountain_cell(mouth), arrival = {x = at.x, y = at.y, layer = CAVE_LAYER}}
			count += 1
		}
	}
	side := size(w)
	width, height := cave_board(w.biome)
	r := rng.create(0xCA7E0000+u64(w.biome))
	plan := level.cave_plan_sized(cave_plan_seed(w, count), width, height)
	for _ in 0..<6000 {
		if count >= MAX_CAVES { break }
		origin := grid.Position{x = 16+int(rng.next_u64(&r)%u64(side-width-24)), y = 8+int(rng.next_u64(&r)%u64(side-height-16))}
		mouth := grid.Position{x = origin.x-2, y = origin.y+plan.arrival.y}
		if !massif_free(w, data, origin, mouth, width, height, places[:count]) { continue }
		places[count] = {origin = origin, width = width, height = height, plan_seed = cave_plan_seed(w, count), mouth = mouth,
			arrival = {x = origin.x+plan.arrival.x, y = origin.y+plan.arrival.y, layer = CAVE_LAYER}}
		count += 1
		plan = level.cave_plan_sized(cave_plan_seed(w, count), width, height)
	}
	return
}

// Raises a place's massif and digs its cave under it: on the open map the plan's rooms on CAVE_LAYER at the height of
// the level ground round it (place.floor), under rock that rises from CAVE_MASSIF_HEIGHT over it at its edge, and the
// tunnel from the first room out through the ring to the mouth, with the props round it and in front of the mouth
// cleared; in the mountain its room.
@(private = "file")
dig_cave :: proc(data: ^level.Level, place: Cave_Place) {
	cave_floor :: proc(data: ^level.Level, x, y: int, height: i32) {
		cell := grid.Position{x = x, y = y, layer = CAVE_LAYER}
		_ = level.set_tile(data, cell, {kind = .Floor})
		_ = level.set_height(data, cell, height)
	}
	if place.mountain {
		room: [CAVE_MOUNTAIN_ROOM_MAX]grid.Position
		cells, _, _, _, ok := mountain_cave_room(&room)
		if !ok { return }
		for offset in room[:cells] { cell := mountain_cell(offset); cave_floor(data, cell.x, cell.y, place.floor) }
		return
	}
	clear_prop :: proc(data: ^level.Level, p: grid.Position) {
		if tile, found := level.tile_at(data, p); found && tile.kind == .Wall { _ = level.set_tile(data, p, {kind = .Floor}) }
	}
	low, high := massif_bounds(place.origin, place.width, place.height, 1)
	apron_low, apron_high := massif_apron(place.mouth)
	for y in low.y..=high.y { for x in low.x..=high.x { clear_prop(data, {x = x, y = y}) } }
	for y in apron_low.y..=apron_high.y { for x in apron_low.x..=apron_high.x { clear_prop(data, {x = x, y = y}) } }
	rock_low, rock_high := massif_bounds(place.origin, place.width, place.height, 0)
	for y in rock_low.y..=rock_high.y {
		for x in rock_low.x..=rock_high.x {
			edge := min(x-rock_low.x, y-rock_low.y, rock_high.x-x, rock_high.y-y)
			_ = level.set_height(data, {x = x, y = y}, place.floor+CAVE_MASSIF_HEIGHT+i32(min(edge, CAVE_MASSIF_RISE)))
		}
	}
	plan := level.cave_plan_sized(place.plan_seed, place.width, place.height)
	for y in 0..<place.height {
		for x in 0..<place.width {
			if level.cave_plan_at(&plan, x, y) == '.' { cave_floor(data, place.origin.x+x, place.origin.y+y, place.floor) }
		}
	}
	for x in -1..<plan.arrival.x { cave_floor(data, place.origin.x+x, place.mouth.y, place.floor) }
}

// A foe of the cave's own: stronger than the open map's at its rank.
@(private = "file")
cave_member :: proc(w: ^World, position: grid.Position, r: ^rng.Rng) -> Member {
	kind := game.Enemy_Archetype(rng.next_u64(r)%5)
	hp := i32(7+rank(w.biome)*2)
	if kind == .Brute || kind == .Custodian { hp += 3 }
	attack := 2+i32(rank(w.biome))
	if w.biome == .Inferno { hp += 3; attack += 1 }
	if w.biome == .Egypt && kind == .Chaser { hp += 5 }
	return {enemy = {position = position, health = hp, max_health = hp, attack = attack, archetype = kind}, alive = true}
}

// Whether the cell of cave `index` at `local` in its box is a floor of the map now (a retouch may have filled it).
@(private = "file")
cave_floor_at :: proc(w: ^World, data: ^level.Level, index: int, local: grid.Position) -> bool {
	tile, _ := level.tile_at(data, cave_world_cell(w, index, local))
	return tile.kind == .Floor
}

// The nearest floor cell of a plan to `anchor` that the map has as a floor, not its arrival nor its secret nor one of
// `taken`.
@(private = "file")
plan_free_cell :: proc(w: ^World, data: ^level.Level, index: int, plan: ^level.Cave_Plan, anchor: grid.Position, taken: []grid.Position) -> (cell: grid.Position, ok: bool) {
	for radius in 0..=2 {
		for dy in -radius..=radius {
			for dx in -radius..=radius {
				cell = grid.offset(anchor, dx, dy)
				if level.cave_plan_at(plan, cell.x, cell.y) != '.' || cell == plan.arrival || cell == plan.secret { continue }
				if !cave_floor_at(w, data, index, cell) { continue }
				occupied := false
				for other in taken { occupied = occupied || other == cell }
				if !occupied { return cell, true }
			}
		}
	}
	return
}

// The secret: credits and a relic, to be taken by hand.
@(private = "file")
add_cave_secret :: proc(w: ^World, index: int, at, beside: grid.Position, r: ^rng.Rng) {
	_ = add_drop(w, at, campaign.make_item(.Credits, 40+i32(rng.next_u64(r)%40)), 0, true, index+1)
	relic := 1+i32(rng.next_u64(r)%(u64(game.Relic_Id.Count)-1))
	_ = add_drop(w, beside, campaign.make_item(.Relic, 1, relic), 0, true, index+1)
}

// The floor of cave `index` nearest to `want` (the cell itself when it is one), within its box: where its secret goes
// when a retouch filled the plan's place for it.
@(private = "file")
cave_nearest_floor :: proc(w: ^World, data: ^level.Level, index: int, want: grid.Position) -> (cell: grid.Position, ok: bool) {
	for radius in 0..=4 {
		for dy in -radius..=radius {
			for dx in -radius..=radius {
				if max(abs(dx), abs(dy)) != radius { continue }
				cell = grid.offset(want, dx, dy)
				if tile, _ := level.tile_at(data, cell); tile.kind == .Floor && cave_at(w, cell) == index+1 { return cell, true }
			}
		}
	}
	return
}

// The cave's inhabitants and treasure, made once with the map: a group in each room of the plan that has one, and the
// secret in its niche; in the mountain's room a pair of foes, and the secret at its far end. Only on cells the map has
// as floors (after the retouches).
@(private = "file")
add_cave_content :: proc(w: ^World, data: ^level.Level, index: int) {
	cave := &w.caves[index]
	r := rng.create(cave.seed~0xBEEF)
	if cave.place.mountain {
		room: [CAVE_MOUNTAIN_ROOM_MAX]grid.Position
		cells, _, arrival, _, ok := mountain_cave_room(&room)
		if !ok { return }
		on_layer :: proc(offset: grid.Position) -> grid.Position {
			cell := mountain_cell(offset)
			return {x = cell.x, y = cell.y, layer = CAVE_LAYER}
		}
		// The two cells farthest from the arrival hold the secret.
		far, second := -1, -1
		for cell, i in room[:cells] {
			if far < 0 || distance(cell, arrival) > distance(room[far], arrival) { second, far = far, i }
			else if second < 0 || distance(cell, arrival) > distance(room[second], arrival) { second = i }
		}
		if secret, found := cave_nearest_floor(w, data, index, on_layer(room[far])); found {
			beside, near := cave_nearest_floor(w, data, index, on_layer(room[second]))
			add_cave_secret(w, index, secret, beside if near else secret, &r)
		}
		if w.group_count >= MAX_GROUPS { return }
		group := &w.groups[w.group_count]
		group^ = Group{anchor = on_layer(room[cells/2]), site = -1, cave = u8(index+1)}
		for cell, i in room[:cells] {
			if group.count >= 2 { break }
			if i == far || i == second || distance(cell, arrival) < 2 { continue }
			if tile, _ := level.tile_at(data, on_layer(cell)); tile.kind != .Floor { continue }
			group.members[group.count] = cave_member(w, on_layer(cell), &r)
			group.count += 1
		}
		if group.count > 0 { w.group_count += 1 }
		return
	}
	plan := level.cave_plan_sized(cave.place.plan_seed, cave.place.width, cave.place.height)
	for g in 0..<plan.groups {
		if w.group_count >= MAX_GROUPS { break }
		group := &w.groups[w.group_count]
		group^ = Group{anchor = cave_world_cell(w, index, plan.anchors[g]), site = -1, cave = u8(index+1)}
		taken: [level.CAVE_MAX_ROOMS*4+4]grid.Position
		for i in 0..<plan.foes[g] {
			cell, ok := plan_free_cell(w, data, index, &plan, plan.anchors[g], taken[:i])
			if !ok { continue }
			taken[i] = cell
			group.members[group.count] = cave_member(w, cave_world_cell(w, index, cell), &r)
			group.count += 1
		}
		if group.count > 0 { w.group_count += 1 }
	}
	if secret, found := cave_nearest_floor(w, data, index, cave_world_cell(w, index, plan.secret)); found {
		beside, near := cave_nearest_floor(w, data, index, grid.offset(secret, -1, 0))
		add_cave_secret(w, index, secret, beside if near else secret, &r)
	}
}

// The places of the map's caves, before the relief, which keeps their ground level (relief.odin): the world's caves,
// with nothing else yet.
@(private)
plan_caves :: proc(w: ^World, data: ^level.Level) {
	if !cave_biome(w.biome) { return }
	places, count := cave_places(w, data)
	for place in places[:count] {
		if w.site_count+w.cave_count >= MAX_SITES { break }
		w.caves[w.cave_count] = Cave{site = -1, place = place}
		w.cave_count += 1
	}
}

// The map's caves, after the relief: every place gets its massif, its cave and the site at its mouth; between one and
// three of them (the Snow's mountain's always) hold foes and a secret, as the run's seed decides.
@(private)
place_caves :: proc(w: ^World, data: ^level.Level) {
	count := w.cave_count
	if count == 0 { return }
	r := rng.create(w.seed~0xCA7E5)
	total := min(count, 1+int(rng.next_u64(&r)%3))
	chosen: [MAX_CAVES]bool
	picked := 0
	if w.caves[0].place.mountain { chosen[0] = true; picked = 1 }
	for picked < total {
		i := int(rng.next_u64(&r)%u64(count))
		if chosen[i] { continue }
		chosen[i] = true
		picked += 1
	}
	for &cave, i in w.caves[:count] {
		// On the open map the cave is at the height of the level ground round it.
		if !cave.place.mountain { cave.place.floor = level.height_at(data, cave.place.mouth) }
		cave.place.arrival.layer = CAVE_LAYER
		dig_cave(data, cave.place)
		seed := rng.next_u64(&r)
		w.sites[w.site_count] = Site{kind = .Cave, position = cave.place.mouth, secret = true, active = true, group = -1, seed = seed}
		cave.site, cave.seed, cave.inhabited = w.site_count, seed~0x6A09E667, chosen[i]
		w.site_count += 1
	}
}

// The foes and the secret of the caves the run gave them, on the map as it is after the retouches (generate).
@(private)
fill_caves :: proc(w: ^World, data: ^level.Level) {
	for cave, i in w.caves[:w.cave_count] { if cave.inhabited { add_cave_content(w, data, i) } }
}

// How many of the sites there are to draw and to ask: all of them.
visible_sites :: proc(w: ^World) -> int {
	return w.site_count
}

// The first cell inside the cave the player is in.
cave_arrival :: proc(w: ^World) -> (cell: grid.Position, ok: bool) {
	if w == nil || w.in_cave <= 0 || w.in_cave > w.cave_count { return }
	return w.caves[w.in_cave-1].place.arrival, true
}

// A cave's secret is taken once its drops are gone (an empty cave has none to take).
cave_looted :: proc(w: ^World, index: int) -> bool {
	for drop in w.drops[:w.drop_count] { if int(drop.cave) == index+1 { return false } }
	return true
}

// Where the player is among the caves (in_cave), and what each cave and its mouth's site have seen of him. Called
// every tick.
@(private)
update_caves :: proc(w: ^World, player: grid.Position) {
	w.in_cave = cave_at(w, player)
	for &cave, i in w.caves[:w.cave_count] {
		if w.in_cave == i+1 && cave.state == .Unvisited { cave.state = .Visited }
		if cave.inhabited && cave.state == .Visited && cave_looted(w, i) {
			cave.state = .Looted
			w.sites[cave.site].state = .Resolved
		}
	}
}
