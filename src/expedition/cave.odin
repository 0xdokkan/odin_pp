package expedition

import campaign "../campaign"
import game "../game"
import grid "../engine/grid"
import level "../level"
import rng "../engine/rng"

// THE CAVES (Fase 5 of docs/piano-griglia.md). An arch on the open map leads, with a fade, into a small map of its own
// (level/cave.odin): two or three rooms in a row, foes in them, a secret with its reward at the far end. The way out is
// the arch again. Four biomes have them: the Snow (one in the spiral mountain, halfway up, and up to two more on the
// map), the Far West, the Egypt and the Inferno (one to three each).
//
// The cave is drawn on the very same grid, in the middle of it: on going in, the open map's tiles and heights are put away
// (in an Outer_Map the scene keeps, and saves with the checkpoint), the cave's plan is stamped over a blank map, and
// the player stands at its arrival; on going out, the open map comes back as it was. What belongs to the open map
// (its sites, groups and drops) does nothing in the meantime, and what belongs to the cave (its groups and drops,
// marked with its number) does nothing outside.

MAX_CAVES :: 3

Cave_State :: enum u8 { Unvisited, Visited, Looted }
Cave :: struct {
	// The arch on the open map: its site.
	site:  int,
	seed:  u64,
	state: Cave_State,
}

// The open map while the player is in a cave: every cell's tile kind and height.
Outer_Map :: struct {
	kinds, heights: [MAX_CELLS]u8,
}

cave_biome :: proc(b: campaign.Biome) -> bool {
	#partial switch b {
	case .Snow, .West, .Egypt, .Inferno: return true
	}
	return false
}

// Where a cave's plan sits on the map: the middle, whatever the cave.
cave_origin :: proc(w: ^World) -> grid.Position {
	side := size(w)
	return {(side-level.CAVE_WIDTH)/2, (side-level.CAVE_HEIGHT)/2}
}

cave_world_cell :: proc(w: ^World, local: grid.Position) -> grid.Position {
	return game.add_position(cave_origin(w), local)
}

// Whether something marked `tag` (a group's, a drop's) is where the player is.
in_scope :: proc(w: ^World, tag: u8) -> bool {
	return w != nil && int(tag) == w.in_cave
}

// The ground of a cell: the biome's, but in a cave nothing of the open map's terrain is under the player's feet.
ground :: proc(w: ^World, p: grid.Position) -> Terrain {
	if w.in_cave > 0 { return .Plain }
	return terrain(w.biome, p)
}

// The cave the arch at site `site` leads to (-1 if it is not one).
cave_of_site :: proc(w: ^World, site: int) -> int {
	for cave, i in w.caves[:w.cave_count] { if cave.site == site { return i } }
	return -1
}

// The open map's arch, as a site's layout draws it (site_layout.odin): a block of rock three cells wide with the doorway
// between its legs, and the ground in front of it cleared.
@(private = "file")
stamp_cave_arch :: proc(data: ^level.Level, p: grid.Position) {
	site := Site{kind = .Cave, position = p, layout_version = SITE_LAYOUT_VERSION}
	stamp_site(data, &site)
}

// A free place for an arch: open ground at the map's own level, clear of the sites, the spawn, the patrols' ground, the
// central band, the mountain and the other arches.
@(private = "file")
cave_entrance_free :: proc(w: ^World, data: ^level.Level, p: grid.Position, others: []grid.Position) -> bool {
	side := size(w)
	if p.x < 14 || p.y < 8 || p.x >= side-8 || p.y >= side-8 { return false }
	if abs(p.y-side/2) <= 5 { return false }
	if distance(p, data.player_spawn) < 14 { return false }
	for y in p.y-4..=p.y+3 {
		for x in p.x-4..=p.x+4 {
			tile, ok := level.tile_at(data, {x, y})
			if !ok || tile.kind == .Void || tile.kind == .Exit || level.height_at(data, {x, y}) != 0 { return false }
		}
	}
	for &site in w.sites[:w.site_count] {
		low, high := site_bounds(&site)
		if p.x+5 >= low.x && p.x-5 <= high.x && p.y+4 >= low.y && p.y-4 <= high.y { return false }
	}
	for other in others { if distance(other, p) < 24 { return false } }
	for i in 0..<4 {
		anchor := grid.Position{side*(35+i*13)/100, side*(35+(i%2)*28)/100}
		if distance(anchor, p) < 9 { return false }
	}
	if mountain_present(w) {
		zone := mountain_zone()
		if p.x+5 >= zone[0].x && p.x-5 <= zone[1].x && p.y+4 >= zone[0].y && p.y-4 <= zone[1].y { return false }
	}
	return true
}

@(private = "file")
add_cave :: proc(w: ^World, p: grid.Position, r: ^rng.Rng) -> int {
	if w.cave_count >= MAX_CAVES || w.site_count >= MAX_SITES { return -1 }
	seed := rng.next_u64(r)
	// The mountain's has no rock of its own: the path is what it stands on (layout 0, like the sites that have none).
	layout := SITE_LAYOUT_VERSION if !(mountain_present(w) && w.cave_count == 0) else u8(0)
	w.sites[w.site_count] = Site{kind = .Cave, position = p, secret = true, active = true, group = -1, seed = seed, layout_version = layout}
	w.caves[w.cave_count] = Cave{site = w.site_count, seed = seed~0x6A09E667}
	w.site_count += 1
	w.cave_count += 1
	add_cave_content(w, w.cave_count-1)
	return w.cave_count-1
}

// A foe of the cave's own: stronger than the open map's at its rank.
@(private = "file")
cave_member :: proc(w: ^World, plan: ^level.Cave_Plan, anchor: grid.Position, local: grid.Position, r: ^rng.Rng, taken: []grid.Position) -> (Member, bool) {
	// The nearest free floor cell of the plan to the anchor.
	for radius in 0..=2 {
		for dy in -radius..=radius {
			for dx in -radius..=radius {
				cell := grid.Position{anchor.x+dx, anchor.y+dy}
				if level.cave_plan_at(plan, cell.x, cell.y) != '.' { continue }
				if cell == plan.arrival || cell == plan.secret { continue }
				occupied := false
				for other in taken { occupied = occupied || other == cell }
				if occupied { continue }
				kind := game.Enemy_Archetype(rng.next_u64(r)%5)
				hp := i32(7+rank(w.biome)*2)
				if kind == .Brute || kind == .Custodian { hp += 3 }
				attack := 2+i32(rank(w.biome))
				if w.biome == .Inferno { hp += 3; attack += 1 }
				if w.biome == .Egypt && kind == .Chaser { hp += 5 }
				member := Member{enemy = {position = cave_world_cell(w, cell), health = hp, max_health = hp, attack = attack, archetype = kind}, alive = true}
				return member, true
			}
		}
	}
	return {}, false
}

// The cave's inhabitants and treasure, made once with the map: a group in each room that has one, and the secret.
@(private = "file")
add_cave_content :: proc(w: ^World, index: int) {
	cave := &w.caves[index]
	plan := level.cave_plan(cave.seed)
	r := rng.create(cave.seed~0xBEEF)
	for g in 0..<plan.groups {
		if w.group_count >= MAX_GROUPS { break }
		group := &w.groups[w.group_count]
		group^ = Group{anchor = cave_world_cell(w, plan.anchors[g]), site = -1, cave = u8(index+1)}
		taken: [level.CAVE_MAX_ROOMS*4+4]grid.Position
		for i in 0..<plan.foes[g] {
			member, ok := cave_member(w, &plan, plan.anchors[g], {}, &r, taken[:i])
			if !ok { continue }
			taken[i] = {member.enemy.position.x-cave_origin(w).x, member.enemy.position.y-cave_origin(w).y}
			group.members[group.count] = member
			group.count += 1
		}
		if group.count == 0 { continue }
		w.group_count += 1
	}
	// The secret: credits and a relic, to be taken by hand.
	secret := cave_world_cell(w, plan.secret)
	_ = add_drop(w, secret, campaign.make_item(.Credits, 40+i32(rng.next_u64(&r)%40)), 0, true, index+1)
	relic := 1+i32(rng.next_u64(&r)%(u64(game.Relic_Id.Count)-1))
	_ = add_drop(w, game.add_position(secret, {-1, 0}), campaign.make_item(.Relic, 1, relic), 0, true, index+1)
}

// The places on the map where there can be a cave: the same for a biome at every run, like the rest of its geography. The Snow's
// first is on the spiral mountain's path, halfway up; the others are open ground, each with its arch's rock stamped (a
// rock formation with a doorway-shaped niche, which is all it is where the run has no cave).
@(private = "file")
cave_candidates :: proc(w: ^World, data: ^level.Level) -> (places: [MAX_CAVES]grid.Position, count: int) {
	if mountain_present(w) {
		places[count] = mountain_cell(level.mountain_path_cell(1.75))
		count += 1
	}
	side := size(w)
	r := rng.create(0xCA7E0000+u64(w.biome))
	for _ in 0..<800 {
		if count >= MAX_CAVES { break }
		p := grid.Position{14+int(rng.next_u64(&r)%u64(side-28)), 10+int(rng.next_u64(&r)%u64(side-20))}
		if !cave_entrance_free(w, data, p, places[:count]) { continue }
		stamp_cave_arch(data, p)
		places[count] = p
		count += 1
	}
	return
}

// The map's caves: between one and three in all (the Snow's mountain always has its own), picked from the places there can
// be one, as the run's seed decides.
@(private)
place_caves :: proc(w: ^World, data: ^level.Level) {
	if !cave_biome(w.biome) { return }
	places, count := cave_candidates(w, data)
	if count == 0 { return }
	r := rng.create(w.seed~0xCA7E5)
	total := min(count, 1+int(rng.next_u64(&r)%3))
	chosen: [MAX_CAVES]bool
	picked := 0
	if mountain_present(w) { chosen[0] = true; picked = 1 }
	for picked < total {
		i := int(rng.next_u64(&r)%u64(count))
		if chosen[i] { continue }
		chosen[i] = true
		picked += 1
	}
	for i in 0..<count { if chosen[i] { _ = add_cave(w, places[i], &r) } }
}

// Goes into cave `index` from where the player stands: puts the open map away in `outer`, stamps the cave, and stands the
// player at its arrival. False (and nothing changed) if the player cannot now: in a fight, or already in a cave.
enter_cave :: proc(w: ^World, data: ^level.Level, room: ^game.Room, outer: ^Outer_Map, index: int) -> bool {
	if w == nil || data == nil || room == nil || outer == nil || room.player == nil || index < 0 || index >= w.cave_count || w.in_cave != 0 || room.phase == .Combat { return false }
	cells := len(data.tiles.cells)
	if cells > MAX_CELLS || !level.tile_kinds(data, outer.kinds[:cells]) { return false }
	for i in 0..<cells { outer.heights[i] = 0 }
	if level.has_heights(data) { copy(outer.heights[:cells], data.heights[:]) }
	blank := make([]u8, cells, context.temp_allocator)
	if !level.set_tile_kinds(data, blank) || !level.set_height_table(data, blank) { return false }
	plan := level.cave_plan(w.caves[index].seed)
	origin := cave_origin(w)
	if !level.cave_stamp(data, origin, &plan) { return false }
	// The open map's structures are put away with it (their tiles are in the outer map; the world keeps their records).
	_ = level.set_structures(data, nil)
	arrival := game.add_position(origin, plan.arrival)
	_ = level.set_tile(data, arrival, {.Player_Spawn})
	w.cave_return = room.player.position
	w.in_cave = index+1
	w.mounted = false
	if w.caves[index].state == .Unvisited { w.caves[index].state = .Visited }
	room.player.position = arrival
	return true
}

// Comes out of the cave the player is in, at the arch it went in by, and brings the open map back as it was.
exit_cave :: proc(w: ^World, data: ^level.Level, room: ^game.Room, outer: ^Outer_Map) -> bool {
	if w == nil || data == nil || room == nil || outer == nil || room.player == nil || w.in_cave <= 0 || room.phase == .Combat { return false }
	cells := len(data.tiles.cells)
	if cells > MAX_CELLS || !level.set_tile_kinds(data, outer.kinds[:cells]) || !level.set_height_table(data, outer.heights[:cells]) { return false }
	_ = level.set_structures(data, w.structures[:w.structure_count])
	w.in_cave = 0
	room.player.position = w.cave_return
	return true
}

// How many of the sites there are to draw and to ask: all of them on the open map, none in a cave.
visible_sites :: proc(w: ^World) -> int {
	return 0 if w.in_cave > 0 else w.site_count
}

// The cell the player stands on coming into the cave the player is in, and goes out from.
cave_arrival :: proc(w: ^World) -> (cell: grid.Position, ok: bool) {
	if w == nil || w.in_cave <= 0 || w.in_cave > w.cave_count { return }
	plan := level.cave_plan(w.caves[w.in_cave-1].seed)
	return cave_world_cell(w, plan.arrival), true
}

// A cave's secret is taken once its drops are gone.
cave_looted :: proc(w: ^World, index: int) -> bool {
	for drop in w.drops[:w.drop_count] { if int(drop.cave) == index+1 { return false } }
	return true
}
