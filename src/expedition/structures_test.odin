package expedition

import "core:testing"
import campaign "../campaign"
import game "../game"
import grid "../engine/grid"
import level "../level"

@(test)
test_the_first_biome_has_its_buildings_and_objects_and_no_other_biome_has_any :: proc(t: ^testing.T) {
	for biome in campaign.Biome {
		if biome == .Count { continue }
		w: World
		data: level.Level
		testing.expect(t, generate(&w, &data, biome, 7))
		defer level.destroy(&data)
		if biome != .Cyber {
			testing.expect_value(t, w.structure_count, 0)
			testing.expect_value(t, level.structure_count(&data), 0)
			continue
		}
		wanted := CYBER_STRUCTURES
		// Nearly all of the ones wanted found a place; the world and the map agree on them.
		testing.expect(t, w.structure_count >= len(wanted)-2, "most of the structures were placed")
		testing.expect_value(t, level.structure_count(&data), w.structure_count)
		buildings, objects := 0, 0
		for i in 0..<w.structure_count {
			testing.expect_value(t, w.structures[i], data.structures[i])
			if level.structure_is_building(w.structures[i].id) { buildings += 1 } else { objects += 1 }
		}
		testing.expect(t, buildings >= 4 && objects >= 4, "buildings and objects")
	}
}

// The same biome has the same structures at every run, whatever the seed.
@(test)
test_the_structures_are_the_same_at_every_run :: proc(t: ^testing.T) {
	a, b: World
	first, second: level.Level
	testing.expect(t, generate(&a, &first, .Cyber, 1))
	testing.expect(t, generate(&b, &second, .Cyber, 123456789))
	defer level.destroy(&first)
	defer level.destroy(&second)
	testing.expect_value(t, a.structure_count, b.structure_count)
	for i in 0..<a.structure_count { testing.expect_value(t, a.structures[i], b.structures[i]) }
}

// A structure never stands on a site, the spawn or the exit, and every door of a building opens
// onto ground the robot can reach from the spawn.
@(test)
test_structures_leave_sites_spawn_and_exit_alone_and_every_door_is_reachable :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	testing.expect(t, generate(&w, &data, .Cyber, 3))
	defer level.destroy(&data)
	for i in 0..<w.structure_count {
		placed := w.structures[i]
		plan := data.structure_plans[i]
		for y in 0..<plan.height {
			for x in 0..<plan.width {
				if level.plan_at(&plan, x, y) == .Outside { continue }
				cell := grid.Position{placed.origin.x+x, placed.origin.y+y}
				testing.expect(t, distance(cell, data.player_spawn) > 8, "not on the spawn")
				for site in w.sites[:w.site_count] {
					testing.expect(t, distance(cell, site.position) > 4, "not on a site")
				}
			}
		}
	}
	// Reach from the spawn over everything a robot can walk on.
	seen := make([]bool, len(data.tiles.cells))
	queue := make([]grid.Position, len(data.tiles.cells))
	defer delete(seen)
	defer delete(queue)
	tail := 1
	queue[0] = data.player_spawn
	seen[data.player_spawn.y*data.tiles.width+data.player_spawn.x] = true
	for head := 0; head < tail; head += 1 {
		for offset in ([4]grid.Position{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
			q := game.add_position(queue[head], offset)
			tile, ok := level.tile_at(&data, q)
			if !ok || !level.is_walkable(tile.kind) { continue }
			at := q.y*data.tiles.width+q.x
			if seen[at] { continue }
			seen[at] = true
			queue[tail] = q
			tail += 1
		}
	}
	for tile, at in data.tiles.cells {
		if tile.kind == .Door || tile.kind == .Exit { testing.expect(t, seen[at], "every door and the exit are reachable") }
	}
	// And the floor inside every building.
	for i in 0..<w.structure_count {
		placed := w.structures[i]
		if !level.structure_is_building(placed.id) { continue }
		plan := data.structure_plans[i]
		for y in 0..<plan.height {
			for x in 0..<plan.width {
				if level.plan_at(&plan, x, y) != .Floor { continue }
				testing.expect(t, seen[(placed.origin.y+y)*data.tiles.width+(placed.origin.x+x)], "the inside of a building is reachable")
			}
		}
	}
}

// The list is saved with the world: restoring a snapshot brings the structures back, and a snapshot
// without any (an old save) restores with none and its tiles as they were.
@(test)
test_the_structures_are_saved_and_an_old_snapshot_loads_without_any :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	p: game.Player
	room := test_world(t, &w, &data, &p)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	testing.expect(t, w.structure_count > 0)
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
	testing.expect_value(t, w2.structure_count, w.structure_count)
	testing.expect_value(t, level.structure_count(&data2), w.structure_count)
	for cell, at in data.structure_cells { testing.expect_value(t, data2.structure_cells[at], cell) }
	for i in 0..<w.structure_count { testing.expect_value(t, data2.structures[i], w.structures[i]) }
	// An old snapshot: no list, the map exactly as saved.
	s.world.structure_count = 0
	s.world.structures = {}
	w3: World
	data3: level.Level
	p3: game.Player
	room3: game.Room
	testing.expect(t, valid_snapshot(s))
	testing.expect(t, restore(s, &w3, &data3, &p3, &room3))
	defer level.destroy(&data3)
	defer game.destroy_room(&room3)
	testing.expect_value(t, level.structure_count(&data3), 0)
	for tile, at in data.tiles.cells { testing.expect_value(t, data3.tiles.cells[at], tile) }
	// A record outside the map is refused.
	s.world.structure_count = 1
	s.world.structures[0] = {id = .Hut, origin = {-4, 5}}
	testing.expect(t, !valid_snapshot(s))
	s.world.structures[0] = {id = .Hut, origin = {5, 5}, rotation = 7}
	testing.expect(t, !valid_snapshot(s))
}
