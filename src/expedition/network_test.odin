package expedition

import "core:slice"
import "core:testing"
import campaign "../campaign"
import game "../game"
import grid "../engine/grid"
import level "../level"

@(private = "file")
RAISED_BIOMES :: [5]campaign.Biome{.City, .Egypt, .Vietnam, .Gothic, .Space}

// City pop, the Egitto, the Vietnam, the Gotico and the Spazio are raised by a base, and have a network on the deep layer
// under it: halls at the network's floor (the Spazio's: its craters' bottoms), a stair down (a pit under the base), a lift
// down under the base and a gate on the network. The Neve is raised for its crevasse (complex.odin) and has none; the other
// biomes are not raised and have nothing on the deep layer.
@(test)
test_the_raised_biomes_have_a_network_under_their_ground :: proc(t: ^testing.T) {
	for biome in campaign.Biome {
		if biome == .Count { continue }
		w: World
		data: level.Level
		testing.expect(t, generate(&w, &data, biome, 5))
		defer level.destroy(&data)
		deep := data.planes[level.layer_slot(NETWORK_LAYER)]
		floors := 0
		for tile in deep.tiles { if level.kind_has_floor(tile.kind) { floors += 1 } }
		if biome_base(biome) == 0 {
			testing.expectf(t, w.base == 0 && data.base == 0 && floors == 0, "%v is raised or has a network", biome)
			continue
		}
		testing.expect_value(t, w.base, EXPEDITION_RAISED_BASE)
		testing.expect_value(t, data.base, EXPEDITION_RAISED_BASE)
		if len(network_plan(biome).halls) == 0 {
			testing.expectf(t, floors == 0, "%v: %d cells on the deep layer, and no network", biome, floors)
			continue
		}
		testing.expectf(t, floors >= 60, "%v: a network of %d cells", biome, floors)
		pits := 0
		for steps, at in data.heights {
			if data.tiles.cells[at].kind != .Void && i32(steps) < data.base { pits += 1 }
		}
		testing.expectf(t, pits >= NETWORK_STAIR_STEPS, "%v: %d cells of pits", biome, pits)
		deep_lift, deep_gate := false, false
		for lift in data.lifts { deep_lift = deep_lift || level.height_at(&data, lift.ends[0]) < data.base }
		for gate in data.gates { deep_gate = deep_gate || gate.cell.layer == NETWORK_LAYER }
		testing.expectf(t, deep_lift && deep_gate, "%v: a lift down to the network %v, a gate on it %v", biome, deep_lift, deep_gate)
		error, bad := level.check_layers(&data)
		testing.expectf(t, error == .None, "%v: the layers break their rule at %v (%v)", biome, bad, error)
	}
}

// The network's secret is reached from the spawn, with every gate shut, and so is every one of its halls' foes: under the
// base (in a hall on the deep layer, or at a crater's bottom).
@(test)
test_the_networks_secret_and_foes_can_be_walked_to :: proc(t: ^testing.T) {
	for biome in RAISED_BIOMES {
		w: World
		data: level.Level
		testing.expect(t, generate(&w, &data, biome, 9))
		defer level.destroy(&data)
		seen := level.layer_reach(&data, data.player_spawn, context.temp_allocator)
		secrets, foes := 0, 0
		for drop in w.drops[:w.drop_count] {
			if level.height_at(&data, drop.position) >= data.base { continue }
			secrets += 1
			testing.expectf(t, seen[level.layer_reach_index(&data, drop.position)], "%v: the secret at %v cannot be walked to", biome, drop.position)
		}
		for &group in w.groups[:w.group_count] {
			for member in group.members[:group.count] {
				if level.height_at(&data, member.enemy.position) >= data.base { continue }
				foes += 1
				testing.expectf(t, seen[level.layer_reach_index(&data, member.enemy.position)], "%v: a foe at %v cannot be walked to", biome, member.enemy.position)
			}
		}
		testing.expectf(t, secrets == 2 && foes >= 2, "%v: %d drops of the secret, %d foes under the ground", biome, secrets, foes)
	}
}

// The Vietnam's gallery goes from today's tunnel, in the south, to where the tunnel came out, in the north-east: on the
// deep layer alone, its gate open, one walks from the hall by the tunnel to the hall by the old way out.
@(test)
test_the_vietnams_gallery_joins_the_tunnel_to_where_it_came_out :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	testing.expect(t, generate(&w, &data, .Vietnam, 2))
	defer level.destroy(&data)
	for gate, i in data.gates { if gate.cell.layer == NETWORK_LAYER { _ = level.open_gate(&data, i) } }
	plan := network_plan(.Vietnam)
	start, end := network_hall_centre(&w, plan, 0), network_hall_centre(&w, plan, len(plan.halls)-1)
	tunnel := w.sites[15]
	testing.expect(t, tunnel.kind == .Tunnel && tunnel.active)
	testing.expectf(t, distance(start, tunnel.position) <= 12, "the gallery starts at %v, the tunnel is at %v", start, tunnel.position)
	testing.expectf(t, distance(end, {x = size(&w)-14, y = 16}) <= 12, "the gallery ends at %v", end)
	// A walk on the deep layer only.
	seen := make([]bool, len(data.tiles.cells), context.temp_allocator)
	queue := make([dynamic]grid.Position, context.temp_allocator)
	seen[start.y*data.tiles.width+start.x] = true
	append(&queue, start)
	for head := 0; head < len(queue); head += 1 {
		for step in ([4]grid.Position{{x = 1}, {x = -1}, {y = 1}, {y = -1}}) {
			next := grid.offset(queue[head], step.x, step.y)
			tile, found := level.tile_at(&data, next)
			if !found || !level.is_walkable(tile.kind) { continue }
			at := next.y*data.tiles.width+next.x
			if seen[at] { continue }
			seen[at] = true
			append(&queue, next)
		}
	}
	testing.expect(t, seen[end.y*data.tiles.width+end.x], "the gallery does not reach where the tunnel came out")
	// Today's jump is gone: the tunnel is no site to use.
	testing.expect_value(t, nearest_site(&w, tunnel.position), -1)
}

// A save keeps the world's base and the map raised by it; a save from before there was one (no base) is not raised.
@(test)
test_a_save_keeps_the_base_of_a_raised_biome :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	p: game.Player
	room := test_world(t, &w, &data, &p, .Egypt)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	game.end_expedition_encounter(&room)
	room.phase = .Loot
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
	testing.expect_value(t, data2.base, EXPEDITION_RAISED_BASE)
	testing.expect_value(t, w2.base, EXPEDITION_RAISED_BASE)
	testing.expect(t, slice.equal(data.heights[:], data2.heights[:]))
	testing.expect(t, slice.equal(data2.lifts[:], data.lifts[:]) && slice.equal(data2.gates[:], data.gates[:]))
}

// Under the ground the robot shakes off the Gotico's killer (the user's choice in Fase 7): while the robot is down in the
// catacombs the killer waits on the open ground, and comes again once the robot is up; a fight with him breaks off when
// the robot goes down.
@(test)
test_the_gothics_killer_does_not_follow_the_robot_under_the_ground :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	p: game.Player
	room := test_world(t, &w, &data, &p, .Gothic)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	game.end_expedition_encounter(&room)
	clear(&room.enemies)
	room.phase = .Loot
	// Nobody else to wake.
	killer := -1
	for &g, i in w.groups[:w.group_count] {
		if g.killer { killer = i } else { g.count = 0 }
	}
	for &site in w.sites[:w.site_count] { site.active = false }
	if !testing.expect(t, killer >= 0) { return }
	g := &w.groups[killer]
	// A cell of the catacombs far from him, with another beside it.
	deep, found := grid.Position{}, false
	for y in 0..<data.tiles.height {
		for x in 0..<data.tiles.width {
			cell := grid.Position{x = x, y = y, layer = NETWORK_LAYER}
			tile, _ := level.tile_at(&data, cell)
			beside, _ := level.tile_at(&data, grid.offset(cell, 1, 0))
			if tile.kind == .Floor && beside.kind == .Floor && distance(cell, g.anchor) > 24 { deep, found = cell, true }
		}
	}
	if !testing.expect(t, found) { return }
	before := g.anchor
	p.position = deep
	for _ in 0..<20 { tick(&w, &room, 0.2) }
	testing.expect_value(t, g.anchor, before)
	// Up on the open ground over it, he comes.
	p.position = {x = deep.x, y = deep.y}
	for _ in 0..<20 { tick(&w, &room, 0.2) }
	testing.expect(t, g.anchor != before && g.anchor.layer == grid.GROUND_LAYER, "the killer does not come")
	// A fight with him beside the robot, then the robot down under him: it breaks off.
	g.anchor = {x = deep.x+1, y = deep.y}
	g.members[0].enemy.position = g.anchor
	testing.expect(t, engage(&w, &room, killer) && g.active, "no fight with the killer")
	p.position = deep
	for _ in 0..<5 { tick(&w, &room, 0.2) }
	testing.expect(t, !g.active && len(room.enemies) == 0, "the fight goes on under the ground")
}
