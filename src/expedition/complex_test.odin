package expedition

import "core:fmt"
import "core:slice"
import "core:testing"
import campaign "../campaign"
import game "../game"

import grid "../engine/grid"
import level "../level"

@(private = "file")
COMPLEX_BIOMES :: [12]campaign.Biome{.Cyber, .West, .Jungle, .City, .Egypt, .Vietnam, .Snow, .Inferno, .Gothic, .Sky, .Space, .Secret}

// The walkable cells of the map no walk from the spawn reaches, on any layer (level.layer_reach: ramps, mouths, decks,
// lifts), the gates shut: none but a massif's top, rock over a cave, and the Cielo's few islets with no bridge to them
// (relief_test.odin), out of its complex.
@(private = "file")
complex_stranded :: proc(w: ^World, data: ^level.Level) -> (stranded: int, first: grid.Position) {
	seen := level.layer_reach(data, data.player_spawn, context.temp_allocator)
	for layer in grid.LOWEST_LAYER..=grid.HIGHEST_LAYER {
		for y in 0..<data.tiles.height {
			for x in 0..<data.tiles.width {
				p := grid.Position{x = x, y = y, layer = i8(layer)}
				tile, _ := level.tile_at(data, p)
				if !level.is_walkable(tile.kind) || seen[level.layer_reach_index(data, p)] || cave_rock(w, p) { continue }
				if index, _ := complex_at(w, p); w.biome == .Sky && index == 0 { continue }
				if stranded == 0 { first = p }
				stranded += 1
			}
		}
	}
	return
}

// The biomes with complexes (all twelve, after the fourth group of Fase 7) have them at the same places and the same at
// every run, on every layer, with the same lifts and gates; the map keeps the layers' rule. A biome without would have none.
@(test)
test_the_complexes_are_the_biomes_own_and_the_same_at_every_run :: proc(t: ^testing.T) {
	for biome in campaign.Biome {
		if biome == .Count { continue }
		a, b: World
		first, second: level.Level
		testing.expect(t, generate(&a, &first, biome, 3))
		testing.expect(t, generate(&b, &second, biome, 424242))
		defer level.destroy(&first)
		defer level.destroy(&second)
		if !complex_biome(biome) {
			testing.expectf(t, a.complex_count == 0 && len(first.lifts) == 0 && len(first.gates) == 0, "%v has a complex", biome)
			continue
		}
		testing.expectf(t, a.complex_count >= 1, "%v has no complex", biome)
		testing.expect_value(t, a.complex_count, b.complex_count)
		for c, i in a.complexes[:a.complex_count] {
			testing.expect_value(t, c, b.complexes[i])
			fmt.printfln("complex %v of %v at %v, floor %d", c.kind, biome, c.origin, c.floor)
		}
		error, bad := level.check_layers(&first)
		testing.expectf(t, error == .None, "%v: the layers break their rule at %v (%v)", biome, bad, error)
		for slot in 0..<level.LAYER_COUNT {
			testing.expect(t, slice.equal(first.planes[slot].tiles[:], second.planes[slot].tiles[:]), "the layers do not depend on the seed")
			testing.expect(t, slice.equal(first.planes[slot].heights[:], second.planes[slot].heights[:]))
		}
		testing.expect(t, slice.equal(first.lifts[:], second.lifts[:]) && slice.equal(first.gates[:], second.gates[:]))
		testing.expectf(t, len(first.lifts) >= 1 && len(first.gates) >= 1, "%v: %d lifts, %d gates", biome, len(first.lifts), len(first.gates))
		testing.expect_value(t, a.lift_count, len(first.lifts))
		testing.expect_value(t, a.gate_count, len(first.gates))
	}
}

// With every gate shut, a walk from the spawn reaches every walkable cell of every layer: a shortcut is only a shortcut.
// It reaches every complex's secret, and both sides of each gate: the lever's, and the other.
@(test)
test_everything_on_a_complex_can_be_walked_to_with_its_gates_shut :: proc(t: ^testing.T) {
	for biome in COMPLEX_BIOMES {
		w: World
		data: level.Level
		testing.expect(t, generate(&w, &data, biome, 11))
		defer level.destroy(&data)
		stranded, first := complex_stranded(&w, &data)
		testing.expectf(t, stranded == 0, "%v: %d walkable cells cannot be walked to, the first at %v", biome, stranded, first)
		seen := level.layer_reach(&data, data.player_spawn, context.temp_allocator)
		for gate in data.gates {
			tile, _ := level.tile_at(&data, gate.cell)
			testing.expectf(t, tile.kind == .Fence, "%v: the gate at %v is not shut", biome, gate.cell)
			testing.expectf(t, seen[level.layer_reach_index(&data, gate.lever)], "%v: the lever at %v cannot be walked to", biome, gate.lever)
			beyond := grid.Position{x = 2*gate.cell.x-gate.lever.x, y = 2*gate.cell.y-gate.lever.y, layer = gate.cell.layer}
			landing, found := level.column_walkable_near(&data, beyond.x, beyond.y, level.height_at(&data, gate.cell), 1)
			testing.expectf(t, found && seen[level.layer_reach_index(&data, landing)], "%v: the far side of the gate at %v cannot be walked to", biome, gate.cell)
		}
		// Two drops (credits and a relic) for each complex with a secret.
		secrets, want := 0, 0
		for c in w.complexes[:w.complex_count] {
			for row in complex_layout(c.kind).rows { for mark in transmute([]u8)row { if complex_mark_secret(mark) { want += 2 } } }
		}
		for drop in w.drops[:w.drop_count] {
			if drop.cave != 0 || !drop.manual_only { continue }
			if index, _ := complex_at(&w, drop.position); index == 0 { continue }
			secrets += 1
			testing.expectf(t, seen[level.layer_reach_index(&data, drop.position)], "%v: the secret at %v cannot be walked to", biome, drop.position)
		}
		testing.expectf(t, secrets == want && want >= 2, "%v: %d drops of a complex's secret, %d wanted", biome, secrets, want)
	}
}

// A save keeps the lifts and the gates as they are: an opened gate stays open, a platform stays at the end it rests at. A
// new run finds the gate shut. While a platform carries someone no save is made: the one before stands.
@(test)
test_a_save_keeps_a_complexs_gate_and_its_lifts_platform :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	p: game.Player
	room := test_world(t, &w, &data, &p, .West)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	game.end_expedition_encounter(&room)
	room.phase = .Loot
	testing.expect(t, len(data.gates) == 1 && len(data.lifts) == 1 && room.lifts.count == 1)
	gate, lift := data.gates[0], data.lifts[0]
	foot := lift.ends[0]
	testing.expect(t, game.gate_opens(&room, gate.lever, gate.cell))
	// The platform waits at the top: called down to the foot.
	testing.expect(t, game.lift_call(&room, foot))
	game.lift_tick(&room, 10)
	testing.expect(t, room.lifts.platforms[0].at == 0 && !room.lifts.platforms[0].moving)
	s := new(Snapshot)
	defer free(s)
	testing.expect(t, capture(&w, &room, s))
	testing.expect(t, valid_snapshot(s))
	w2: World
	data2: level.Level
	p2: game.Player
	room2: game.Room
	testing.expect(t, restore(s, &w2, &data2, &p2, &room2))
	defer level.destroy(&data2)
	defer game.destroy_room(&room2)
	testing.expect(t, slice.equal(data2.lifts[:], data.lifts[:]) && slice.equal(data2.gates[:], data.gates[:]))
	_, open, found := level.gate_at(&data2, gate.cell)
	testing.expect(t, found && open, "the gate stays open")
	testing.expect_value(t, room2.lifts.platforms[0].at, u8(0))
	// A new run: the gate is shut again.
	w3: World
	data3: level.Level
	testing.expect(t, generate(&w3, &data3, .West, 77))
	defer level.destroy(&data3)
	_, open, _ = level.gate_at(&data3, gate.cell)
	testing.expect(t, !open, "a new run finds the gate shut")
	// On the way up no save is made.
	testing.expect(t, game.lift_board(&room, game.PLAYER_ENTITY, foot))
	testing.expect(t, !stable(&room) && !capture(&w, &room, s))
}

// Walking freely by the Far West's mesa: a push against the lift's foot, its platform up top, calls it; the walker waits,
// steps on and rides it up, going nowhere on the way. Up there the gate on the mesa's edge does not open to a push from
// the landing; from its lever, on the mesa, it does.
@(test)
test_the_walker_calls_rides_and_opens_on_a_complex :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	p: game.Player
	room := test_world(t, &w, &data, &p, .West)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	game.end_expedition_encounter(&room)
	clear(&room.enemies)
	room.phase = .Loot
	lift, gate := data.lifts[0], data.gates[0]
	foot, landing := lift.ends[0], lift.ends[1]
	start := grid.offset(foot, 1, 0)
	p.position = start
	r: Roam
	roam_walk(&w, &room, &r, {-1, 0}, 0.5)
	testing.expect_value(t, p.position, start)
	testing.expect(t, room.lifts.platforms[0].moving && room.lifts.platforms[0].at == 0, "the push called the platform down")
	for _ in 0..<150 { game.lift_tick(&room, 1.0/60) }
	testing.expect(t, !room.lifts.platforms[0].moving)
	roam_walk(&w, &room, &r, {-1, 0}, 0.5)
	testing.expect(t, game.lift_player_riding(&room) && p.position == landing, "the walker rides the platform")
	before := r.position
	roam_walk(&w, &room, &r, {0, 1}, 0.5)
	testing.expect(t, r.position == before, "nobody walks off a platform on its way")
	for _ in 0..<150 { game.lift_tick(&room, 1.0/60) }
	testing.expect(t, !game.lift_player_riding(&room) && p.position == landing)
	roam_walk(&w, &room, &r, {-1, 0}, 0.5)
	_, open, _ := level.gate_at(&data, gate.cell)
	testing.expect(t, !open && p.position == landing, "the gate does not open from the landing")
	p.position = gate.lever
	roam_walk(&w, &room, &r, {1, 0}, 0.5)
	_, open, _ = level.gate_at(&data, gate.cell)
	testing.expect(t, open, "the gate opens to a push from its lever")
}

// The Neve is raised by a base, and its crevasse is dug into it: the bottom COMPLEX_TOP steps under the open ground round
// it, the stair a step a cell from the bottom up to a step under the snow, the rope bridge on the layer over the ground
// at the snow's height, and the lift from the bottom up to a landing at the snow's height.
@(test)
test_the_snows_crevasse_is_dug_into_its_raised_ground :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	testing.expect(t, generate(&w, &data, .Snow, 4))
	defer level.destroy(&data)
	testing.expect_value(t, w.base, EXPEDITION_RAISED_BASE)
	if !testing.expect(t, w.complex_count == 1 && w.complexes[0].kind == .Crevasse) { return }
	c := w.complexes[0]
	bottom, top := complex_levels(c)
	testing.expect(t, top == c.floor && bottom == c.floor-COMPLEX_TOP && bottom >= 0)
	layout := complex_layout(c.kind)
	width, height := complex_size(layout)
	for y in 0..<height {
		for x in 0..<width {
			mark := layout.rows[y][x]
			ground := grid.offset(c.origin, x, y)
			want := c.floor
			if complex_mark_pit(mark) { want = bottom } else if steps := complex_mark_ramp(mark); steps > 0 { want = bottom+steps }
			got := level.height_at(&data, ground)
			testing.expectf(t, got == want, "the crevasse's %c at %v is %d steps, not %d", mark, ground, got, want)
			if mark == '=' { testing.expect_value(t, level.height_at(&data, complex_cell(c, {x = x, y = y})), c.floor) }
		}
	}
	if !testing.expect_value(t, len(data.lifts), 1) { return }
	testing.expect_value(t, level.height_at(&data, data.lifts[0].ends[0]), bottom)
	testing.expect_value(t, level.height_at(&data, data.lifts[0].ends[1]), c.floor)
}

// The Inferno's bridge of bones goes over one of its streams of lava, on the layer over the ground, where there is no lava;
// its cliffs and its stair stand on dry ground.
@(test)
test_the_infernos_bridge_of_bones_goes_over_a_stream_of_lava :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	testing.expect(t, generate(&w, &data, .Inferno, 6))
	defer level.destroy(&data)
	if !testing.expect(t, w.complex_count == 1 && w.complexes[0].kind == .Bone_Bridge) { return }
	c := w.complexes[0]
	layout := complex_layout(c.kind)
	width, height := complex_size(layout)
	over := 0
	for y in 0..<height {
		for x in 0..<width {
			mark := layout.rows[y][x]
			ground := grid.offset(c.origin, x, y)
			lava := terrain(.Inferno, ground) == .Lava
			if complex_mark_deck(mark) {
				if lava { over += 1 }
				testing.expect_value(t, terrain(.Inferno, complex_cell(c, {x = x, y = y})), Terrain.Plain)
			}
			if complex_mark_block(mark) || complex_mark_ramp(mark) > 0 { testing.expectf(t, !lava, "the complex's %c at %v is on lava", mark, ground) }
		}
	}
	testing.expectf(t, over >= 3, "%d cells of the bridge over the lava", over)
}

// The Cielo's floating island hangs over one of its islands (the user's choice in Fase 7): on the layer over the ground,
// COMPLEX_TOP over the island's ground, which stays walkable under it, in its shade; nothing of it reaches the sky between
// the islands or a bridge, which stay as they are. Its secret and its guards are on it.
@(test)
test_the_skys_island_floats_over_one_of_its_islands :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	testing.expect(t, generate(&w, &data, .Sky, 8))
	defer level.destroy(&data)
	if !testing.expect(t, w.complex_count == 1 && w.complexes[0].kind == .Floating_Island) { return }
	c := w.complexes[0]
	testing.expectf(t, c.floor >= 2 && c.floor <= 4, "the island's ground is %d steps high", c.floor)
	layout := complex_layout(c.kind)
	width, height := complex_size(layout)
	decks := 0
	for y in -COMPLEX_MARGIN..<height+COMPLEX_MARGIN {
		for x in -COMPLEX_MARGIN..<width+COMPLEX_MARGIN {
			ground := grid.offset(c.origin, x, y)
			tile, _ := level.tile_at(&data, ground)
			testing.expectf(t, tile.kind != .Void && terrain(.Sky, ground) != .Bridge, "the complex reaches the sky or a bridge at %v", ground)
			if !complex_mark_deck(complex_mark(layout, x, y)) { continue }
			decks += 1
			deck := complex_cell(c, {x = x, y = y})
			over, _ := level.tile_at(&data, deck)
			testing.expect(t, level.is_walkable(over.kind) || over.kind == .Fence)
			testing.expect_value(t, level.height_at(&data, deck), c.floor+COMPLEX_TOP)
			// Under it the island, walkable at its own height.
			testing.expectf(t, level.is_walkable(tile.kind) && level.height_at(&data, ground) == c.floor, "no island under the deck at %v", ground)
		}
	}
	testing.expectf(t, decks >= 40, "an island of %d cells", decks)
	on_it := 0
	for drop in w.drops[:w.drop_count] { if drop.position.layer == COMPLEX_DECK { on_it += 1 } }
	guards := false
	for g in w.groups[:w.group_count] { guards = guards || g.count > 0 && g.members[0].enemy.position.layer == COMPLEX_DECK }
	testing.expectf(t, on_it == 2 && guards, "%d drops of the secret on the island, guards on it %v", on_it, guards)
}

// The cells a walk reaches from `start` under the base alone (the craters' bottoms and stairs, the galleries): a step to
// a neighbour column's walkable cell on any layer, a step from the height one is at.
@(private = "file")
reach_under_the_base :: proc(data: ^level.Level, start: grid.Position) -> []bool {
	seen := make([]bool, level.LAYER_COUNT*len(data.tiles.cells), context.temp_allocator)
	queue := make([dynamic]grid.Position, context.temp_allocator)
	seen[level.layer_reach_index(data, start)] = true
	append(&queue, start)
	for head := 0; head < len(queue); head += 1 {
		at := queue[head]
		for step in ([4]grid.Position{{x = 1}, {x = -1}, {y = 1}, {y = -1}}) {
			next, found := level.column_walkable_near(data, at.x+step.x, at.y+step.y, level.height_at(data, at), 1)
			if !found || level.height_at(data, next) >= data.base || seen[level.layer_reach_index(data, next)] { continue }
			seen[level.layer_reach_index(data, next)] = true
			append(&queue, next)
		}
	}
	return seen
}

// The Spazio is raised by a base for its three deep craters (the user's choice in Fase 7): each dug COMPLEX_TOP under its
// ground, open to the sky; its galleries on the deep layer come out of their walls. Under the ground alone a walk goes
// from the crater with the stair to the one with the secret, and on to the one with the lift only through the gate, which
// opens from the secret's side.
@(test)
test_the_spaces_galleries_join_its_deep_craters :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	testing.expect(t, generate(&w, &data, .Space, 12))
	defer level.destroy(&data)
	testing.expect_value(t, w.base, EXPEDITION_RAISED_BASE)
	kinds := [3]Complex_Kind{.Crater_Lift, .Crater_Hall, .Crater_Stair}
	bottoms: [3]grid.Position
	for kind, i in kinds {
		c, found := network_crater(&w, kind)
		if !testing.expectf(t, found, "the Spazio has no %v", kind) { return }
		bottom, top := complex_levels(c)
		testing.expect(t, bottom == 0 && top == w.base)
		layout := complex_layout(kind)
		width, height := complex_size(layout)
		for y in 0..<height {
			for x in 0..<width {
				if layout.rows[y][x] != '_' { continue }
				bottoms[i] = grid.offset(c.origin, x, y)
				testing.expect_value(t, level.height_at(&data, bottoms[i]), bottom)
			}
		}
	}
	gate := -1
	for g, i in data.gates { if g.cell.layer == NETWORK_LAYER { gate = i } }
	if !testing.expect(t, gate >= 0, "no gate on the galleries") { return }
	seen := reach_under_the_base(&data, bottoms[2])
	testing.expect(t, seen[level.layer_reach_index(&data, bottoms[1])], "the galleries do not join the stair's crater to the secret's")
	testing.expect(t, !seen[level.layer_reach_index(&data, bottoms[0])], "the lift's crater is reached past the shut gate")
	testing.expect(t, seen[level.layer_reach_index(&data, data.gates[gate].lever)], "the gate's lever is not on the secret's side")
	testing.expect(t, level.open_gate(&data, gate))
	seen = reach_under_the_base(&data, bottoms[2])
	testing.expect(t, seen[level.layer_reach_index(&data, bottoms[0])], "the galleries do not join the secret's crater to the lift's")
	// The lift goes from the bottom of its crater up to its ground.
	crater, found := network_crater(&w, .Crater_Lift)
	testing.expect(t, found)
	up := false
	for lift in data.lifts {
		if index, _ := complex_at(&w, lift.ends[0]); index > 0 && w.complexes[index-1] == crater {
			up = level.height_at(&data, lift.ends[0]) == 0 && level.height_at(&data, lift.ends[1]) == w.base
		}
	}
	testing.expect(t, up, "no lift up from the crater's bottom to the ground")
}

// The Memoria's boulder's hill (the user's choice in Fase 7, in place of the ridge in the middle that the sites' level ground
// had cut): its top COMPLEX_TOP over the ground, with the boulder on it as a wall; inside it, on the layer under the ground,
// the memory's hall with the secret and its guards, its shaft's lift up to the top. Its passage's gate opens from inside
// only. In the middle of the map the relief is low again.
@(test)
test_the_memorias_hill_holds_the_hall_of_its_memory :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	p: game.Player
	room := test_world(t, &w, &data, &p, .Secret)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	game.end_expedition_encounter(&room)
	clear(&room.enemies)
	room.phase = .Loot
	if !testing.expect(t, w.complex_count == 1 && w.complexes[0].kind == .Boulder_Hill) { return }
	c := w.complexes[0]
	boulder, found := complex_boulder(c)
	tile, _ := level.tile_at(&data, boulder)
	testing.expect(t, found && tile.kind == .Wall && level.height_at(&data, boulder) == c.floor+COMPLEX_TOP, "no boulder on the top")
	in_hall := 0
	for drop in w.drops[:w.drop_count] { if drop.position.layer == COMPLEX_TUNNEL { in_hall += 1 } }
	guards := false
	for g in w.groups[:w.group_count] { guards = guards || g.count > 0 && g.members[0].enemy.position.layer == COMPLEX_TUNNEL }
	testing.expectf(t, in_hall == 2 && guards, "%d drops of the secret in the hall, guards in it %v", in_hall, guards)
	if !testing.expect_value(t, len(data.lifts), 1) { return }
	shaft := data.lifts[0]
	testing.expect(t, shaft.ends[0].layer == COMPLEX_TUNNEL && level.height_at(&data, shaft.ends[1]) == c.floor+COMPLEX_TOP, "no shaft from the hall up to the top")
	if !testing.expect_value(t, len(data.gates), 1) { return }
	gate := data.gates[0]
	outside := grid.Position{x = 2*gate.cell.x-gate.lever.x, y = 2*gate.cell.y-gate.lever.y}
	testing.expect(t, !game.gate_opens(&room, outside, gate.cell), "the gate opens from the ground")
	testing.expect(t, game.gate_opens(&room, gate.lever, gate.cell), "the gate does not open from inside")
	side := data.tiles.width
	tallest := i32(0)
	for y in side/2-12..=side/2+12 {
		for x in side/2-12..=side/2+12 {
			if index, _ := complex_at(&w, {x = x, y = y}); index == 0 { tallest = max(tallest, level.height_at(&data, {x = x, y = y})) }
		}
	}
	testing.expectf(t, tallest <= 2, "the middle of the map is %d steps high", tallest)
}
