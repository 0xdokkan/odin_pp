package expedition

import "core:fmt"
import "core:slice"
import "core:testing"
import campaign "../campaign"
import game "../game"

import grid "../engine/grid"
import level "../level"

@(private = "file")
COMPLEX_BIOMES :: [3]campaign.Biome{.Cyber, .West, .Jungle}

// The walkable cells of the map no walk from the spawn reaches, on any layer (level.layer_reach: ramps, mouths, decks,
// lifts), the gates shut: none but a massif's top, rock over a cave.
@(private = "file")
complex_stranded :: proc(w: ^World, data: ^level.Level) -> (stranded: int, first: grid.Position) {
	seen := level.layer_reach(data, data.player_spawn, context.temp_allocator)
	for layer in grid.LOWEST_LAYER..=grid.HIGHEST_LAYER {
		for y in 0..<data.tiles.height {
			for x in 0..<data.tiles.width {
				p := grid.Position{x = x, y = y, layer = i8(layer)}
				tile, _ := level.tile_at(data, p)
				if !level.is_walkable(tile.kind) || seen[level.layer_reach_index(data, p)] || cave_rock(w, p) { continue }
				if stranded == 0 { first = p }
				stranded += 1
			}
		}
	}
	return
}

// Robotica cibernetica, the Far West and the Giungla have their complexes, at the same places and the same at every run,
// on every layer, with the same lifts and gates; the map keeps the layers' rule. The other biomes have none.
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
// It reaches the secret, and both sides of each gate: the lever's, and the other.
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
		secrets := 0
		for drop in w.drops[:w.drop_count] {
			if drop.cave != 0 || !drop.manual_only { continue }
			if index, _ := complex_at(&w, drop.position); index == 0 { continue }
			secrets += 1
			testing.expectf(t, seen[level.layer_reach_index(&data, drop.position)], "%v: the secret at %v cannot be walked to", biome, drop.position)
		}
		testing.expectf(t, secrets == 2, "%v: %d drops of a complex's secret", biome, secrets)
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
