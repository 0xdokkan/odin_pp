package expedition

import "core:slice"
import "core:testing"
import campaign "../campaign"
import game "../game"
import grid "../engine/grid"
import level "../level"

@(private = "file")
CAVE_BIOMES :: [4]campaign.Biome{.Snow, .West, .Egypt, .Inferno}

@(private = "file")
cave_world :: proc(t: ^testing.T, w: ^World, data: ^level.Level, p: ^game.Player, biome: campaign.Biome) -> game.Room {
	room := test_world(t, w, data, p, biome)
	game.end_expedition_encounter(&room)
	room.phase = .Loot
	return room
}

// The last of the biome's caves: one on the open map (the Snow's first is the mountain's), its tunnel running east from the mouth.
@(private = "file")
open_map_cave :: proc(w: ^World) -> int {
	return w.cave_count-1
}

// Every place of a cave biome has its massif and its cave at every run; between one and three of them hold foes and a secret,
// the Snow's mountain's always; the other biomes have none. Each cave's mouth is a secret site on the open ground, its arrival a
// floor under the rock, and the map keeps the rule of the layers' columns.
@(test)
test_every_cave_place_has_its_cave_and_one_to_three_are_inhabited :: proc(t: ^testing.T) {
	for biome in campaign.Biome {
		if biome == .Count { continue }
		for seed in ([?]u64{1, 7, 99, 12345, 777777}) {
			w: World
			data: level.Level
			testing.expect(t, generate(&w, &data, biome, seed))
			defer level.destroy(&data)
			if !cave_biome(biome) {
				testing.expectf(t, w.cave_count == 0 && !level.has_layers(&data), "%v has %d caves", biome, w.cave_count)
				continue
			}
			testing.expectf(t, w.cave_count >= 2, "%v has only %d places for a cave", biome, w.cave_count)
			error, bad := level.check_layers(&data)
			testing.expectf(t, error == .None, "%v: the layers break their rule at %v", biome, bad)
			inhabited := 0
			for cave, i in w.caves[:w.cave_count] {
				site := w.sites[cave.site]
				testing.expect(t, site.kind == .Cave && site.secret && site.active && site.state == .Unvisited)
				testing.expect_value(t, site.position, cave.place.mouth)
				testing.expect_value(t, cave_of_site(&w, cave.site), i)
				mouth, _ := level.tile_at(&data, cave.place.mouth)
				arrival, _ := level.tile_at(&data, cave.place.arrival)
				testing.expect(t, level.is_walkable(mouth.kind) && arrival.kind == .Floor && cave.place.arrival.layer == CAVE_LAYER)
				testing.expect_value(t, cave_at(&w, cave.place.arrival), i+1)
				testing.expect_value(t, cave_at(&w, cave.place.mouth), 0)
				groups, drops := 0, 0
				for &group in w.groups[:w.group_count] {
					if int(group.cave) != i+1 { continue }
					groups += 1
					testing.expect(t, group.count >= 2 && !group.patrol)
					for member in group.members[:group.count] { testing.expect_value(t, member.enemy.position.layer, CAVE_LAYER) }
				}
				for drop in w.drops[:w.drop_count] {
					if int(drop.cave) != i+1 { continue }
					drops += 1
					testing.expect(t, drop.manual_only && drop.position.layer == CAVE_LAYER)
				}
				if cave.inhabited {
					inhabited += 1
					testing.expectf(t, groups >= 1 && groups <= 3 && drops == 2, "%v cave %d has %d groups and %d drops", biome, i, groups, drops)
				} else {
					testing.expectf(t, groups == 0 && drops == 0, "%v: the empty cave %d has %d groups and %d drops", biome, i, groups, drops)
				}
			}
			testing.expect(t, inhabited >= 1 && inhabited <= 3)
			if biome == .Snow { testing.expect(t, w.caves[0].place.mountain && w.caves[0].inhabited) }
		}
	}
}

// The geography is the biome's, not the run's: the ground, the layers under it and the caves' places do not depend on the seed,
// only which of the caves hold foes does.
@(test)
test_the_geography_of_a_cave_biome_is_the_same_whatever_the_seed :: proc(t: ^testing.T) {
	for biome in CAVE_BIOMES {
		a, b: World
		first, second: level.Level
		testing.expect(t, generate(&a, &first, biome, 3))
		testing.expect(t, generate(&b, &second, biome, 424242))
		defer level.destroy(&first)
		defer level.destroy(&second)
		testing.expect(t, slice.equal(first.tiles.cells[:], second.tiles.cells[:]), "the tiles are the same")
		testing.expect(t, slice.equal(first.heights[:], second.heights[:]), "the heights are the same")
		for slot in 0..<level.LAYER_COUNT {
			same := slice.equal(first.planes[slot].tiles[:], second.planes[slot].tiles[:]) && slice.equal(first.planes[slot].heights[:], second.planes[slot].heights[:])
			testing.expectf(t, same, "%v: the layer in slot %d is not the same", biome, slot)
		}
		testing.expect_value(t, a.cave_count, b.cave_count)
		for i in 0..<min(a.cave_count, b.cave_count) { testing.expect_value(t, a.caves[i].place, b.caves[i].place) }
	}
}

// From the spawn the player walks to every cave's mouth and through it to every floor of the cave, a step at a time as the rules
// of the layers have it (game.walk_step): its rooms are one, and joined to the open map.
@(test)
test_every_cave_can_be_walked_into_from_the_spawn :: proc(t: ^testing.T) {
	for biome in CAVE_BIOMES {
		w: World
		data: level.Level
		p: game.Player
		room := cave_world(t, &w, &data, &p, biome)
		defer level.destroy(&data)
		defer game.destroy_room(&room)
		seen := make([]bool, game.room_table_cells(&data))
		queue := make([dynamic]grid.Position)
		defer delete(seen)
		defer delete(queue)
		start, _ := game.room_table_index(&room, data.player_spawn)
		seen[start] = true
		append(&queue, data.player_spawn)
		for head := 0; head < len(queue); head += 1 {
			for step in ([4]grid.Position{{x = 1, y = 0}, {x = -1, y = 0}, {x = 0, y = 1}, {x = 0, y = -1}}) {
				next := game.walk_step(&room, queue[head], step)
				index, inside := game.room_table_index(&room, next)
				if !inside || seen[index] || !game.base_cell_is_walkable(&room, next) || game.step_height_blocked(&room, queue[head], next) { continue }
				seen[index] = true
				append(&queue, next)
			}
		}
		for cave, i in w.caves[:w.cave_count] {
			mouth, _ := game.room_table_index(&room, cave.place.mouth)
			testing.expectf(t, seen[mouth], "%v: the mouth of cave %d at %v cannot be walked to", biome, i, cave.place.mouth)
			floors := 0
			for y in cave.place.origin.y-1..=cave.place.origin.y+cave.place.height {
				for x in cave.place.origin.x-1..=cave.place.origin.x+cave.place.width {
					cell := grid.Position{x = x, y = y, layer = CAVE_LAYER}
					tile, _ := level.tile_at(&data, cell)
					if tile.kind != .Floor { continue }
					floors += 1
					index, _ := game.room_table_index(&room, cell)
					testing.expectf(t, seen[index], "%v: the floor of cave %d at %v cannot be walked to", biome, i, cell)
				}
			}
			testing.expectf(t, floors >= CAVE_MOUNTAIN_ROOM_MIN, "%v: cave %d has %d floors", biome, i, floors)
		}
	}
}

// One walks into a cave through its mouth and out again, in the saddle too: nothing of the map changes, only where the player is
// (world.in_cave); under the rock nothing of the biome's ground is under him.
@(test)
test_the_player_walks_into_a_cave_and_out_and_nothing_else_changes :: proc(t: ^testing.T) {
	for biome in CAVE_BIOMES {
		w: World
		data: level.Level
		p: game.Player
		room := cave_world(t, &w, &data, &p, biome)
		defer level.destroy(&data)
		defer game.destroy_room(&room)
		// Nobody to wake on the way.
		w.group_count = 0
		before_tiles := slice.clone(data.tiles.cells[:])
		before_heights := slice.clone(data.heights[:])
		before_cave := slice.clone(data.planes[level.layer_slot(CAVE_LAYER)].tiles[:])
		defer delete(before_tiles)
		defer delete(before_heights)
		defer delete(before_cave)
		index := open_map_cave(&w)
		place := w.caves[index].place
		room.player.position = place.mouth
		w.mounted = true
		tick(&w, &room, 0.1)
		testing.expect_value(t, w.in_cave, 0)
		for step := 0; room.player.position != place.arrival && step < 8; step += 1 {
			if !testing.expectf(t, walk(&w, &room, {x = 1, y = 0}), "%v: the walk in stopped at %v", biome, room.player.position) { break }
		}
		testing.expect_value(t, room.player.position, place.arrival)
		tick(&w, &room, 0.1)
		testing.expect_value(t, w.in_cave, index+1)
		testing.expect(t, w.mounted, "in the saddle in the cave too")
		testing.expect_value(t, w.caves[index].state, Cave_State.Visited)
		testing.expect_value(t, ground(&w, room.player.position), Terrain.Plain)
		testing.expect_value(t, game.expedition_terrain(u8(biome), room.player.position), game.Expedition_Terrain.Plain)
		testing.expect_value(t, room.player.tactical.config.expedition_biome, u8(biome))
		for step := 0; room.player.position.layer != grid.GROUND_LAYER && step < 8; step += 1 {
			if !testing.expect(t, walk(&w, &room, {x = -1, y = 0})) { break }
		}
		tick(&w, &room, 0.1)
		testing.expect_value(t, w.in_cave, 0)
		testing.expect(t, slice.equal(before_tiles, data.tiles.cells[:]) && slice.equal(before_heights, data.heights[:]), "the ground is as it was")
		testing.expect(t, slice.equal(before_cave, data.planes[level.layer_slot(CAVE_LAYER)].tiles[:]), "the cave is as it was")
	}
}

// A cave's foes sleep under the rock while the player stands over them on the massif: the rock hides him. Inside, on their
// layer, they wake as anywhere, and the saddle is left for the fight.
@(test)
test_the_rock_hides_the_player_from_the_foes_under_it :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	p: game.Player
	room := cave_world(t, &w, &data, &p, .Egypt)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	group := -1
	for g, i in w.groups[:w.group_count] { if g.cave > 0 && !w.caves[g.cave-1].place.mountain { group = i; break } }
	if !testing.expect(t, group >= 0) { return }
	foe := w.groups[group].members[0].enemy.position
	room.player.position = {x = foe.x, y = foe.y}
	for _ in 0..<10 { tick(&w, &room, 0.2) }
	testing.expect(t, !w.groups[group].active && room.phase == .Loot, "seen through the rock")
	// Inside, two cells away on the same floor.
	for offset in ([4]grid.Position{{x = -2, y = 0}, {x = 2, y = 0}, {x = 0, y = -2}, {x = 0, y = 2}}) {
		cell := grid.offset(foe, offset.x, offset.y)
		if tile, _ := level.tile_at(&data, cell); tile.kind == .Floor { room.player.position = cell; break }
	}
	testing.expect_value(t, room.player.position.layer, CAVE_LAYER)
	w.mounted = true
	for _ in 0..<10 { tick(&w, &room, 0.2); if room.phase == .Combat { break } }
	testing.expect(t, room.phase == .Combat && w.groups[group].active, "not woken in the cave")
	testing.expect(t, !w.mounted, "the fight sets the robot down")
}

// A checkpoint taken in a cave comes back in it: the layers, the pools on them, where the player stands. A save from before the
// layers is refused, and so is a cell of a layer off the map.
@(test)
test_a_checkpoint_in_a_cave_comes_back_in_the_cave :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	p: game.Player
	room := cave_world(t, &w, &data, &p, .Inferno)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	arrival := w.caves[0].place.arrival
	room.player.position = arrival
	tick(&w, &room, 0.1)
	testing.expect_value(t, w.in_cave, 1)
	pool, _ := game.room_table_index(&room, grid.offset(arrival, 1, 0))
	room.ground.pool[pool] = 3
	s := new(Snapshot)
	defer free(s)
	testing.expect(t, capture(&w, &room, s))
	testing.expect(t, valid_snapshot(s))
	testing.expect(t, s.layer_cell_count > 0 && s.layer_pool_count == 1)
	w2: World
	data2: level.Level
	p2: game.Player
	room2: game.Room
	if !testing.expect(t, restore(s, &w2, &data2, &p2, &room2)) { return }
	defer level.destroy(&data2)
	defer game.destroy_room(&room2)
	testing.expect_value(t, room2.player.position, arrival)
	testing.expect_value(t, w2.in_cave, 1)
	testing.expect_value(t, w2.caves[0], w.caves[0])
	testing.expect(t, slice.equal(data.tiles.cells[:], data2.tiles.cells[:]) && slice.equal(data.heights[:], data2.heights[:]), "the ground")
	for slot in 0..<level.LAYER_COUNT {
		same := slice.equal(data.planes[slot].tiles[:], data2.planes[slot].tiles[:]) && slice.equal(data.planes[slot].heights[:], data2.planes[slot].heights[:])
		testing.expectf(t, same, "the layer in slot %d", slot)
	}
	testing.expect(t, slice.equal(room.ground.pool, room2.ground.pool), "the pools")
	s.layers_version = 0
	testing.expect(t, !valid_snapshot(s), "a save from before the layers")
	s.layers_version = SNAPSHOT_LAYERS
	s.layer_cells[0] = layer_cell_pack(size(&w)*size(&w), 0, .Floor, 0)
	testing.expect(t, !valid_snapshot(s), "a cell off the map")
}

// What drops in a cave lies where it fell, like anywhere; the cave's secret is its two drops, and once they are taken the cave is
// looted and its mouth's site resolved.
@(test)
test_a_cave_is_looted_once_its_secret_is_taken :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	p: game.Player
	room := cave_world(t, &w, &data, &p, .West)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	w.group_count = 0
	index := -1
	for cave, i in w.caves[:w.cave_count] { if cave.inhabited { index = i; break } }
	if !testing.expect(t, index >= 0) { return }
	room.player.position = w.caves[index].place.arrival
	tick(&w, &room, 0.1)
	testing.expect_value(t, w.caves[index].state, Cave_State.Visited)
	add_xp_drop(&w, room.player.position, 6)
	testing.expect_value(t, w.drops[w.drop_count-1].cave, u8(0))
	testing.expect_value(t, w.drops[w.drop_count-1].position, room.player.position)
	testing.expect(t, !cave_looted(&w, index))
	for i := 0; i < w.drop_count; {
		if int(w.drops[i].cave) == index+1 { w.drop_count -= 1; w.drops[i] = w.drops[w.drop_count] } else { i += 1 }
	}
	tick(&w, &room, 0.1)
	testing.expect_value(t, w.caves[index].state, Cave_State.Looted)
	testing.expect_value(t, w.sites[w.caves[index].site].state, Site_State.Resolved)
}

// A patrol lured into a cave walks in through its mouth, as anywhere.
@(test)
test_a_lured_patrol_walks_into_a_cave :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	p: game.Player
	room := cave_world(t, &w, &data, &p, .Egypt)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	place := w.caves[open_map_cave(&w)].place
	start := grid.offset(place.mouth, -3, 0)
	w.group_count = 1
	w.groups[0] = {anchor = start, patrol = true, count = 1, site = -1, members = {0 = {enemy = {position = start, health = 5, max_health = 5, attack = 2, archetype = .Chaser}, alive = true}}}
	room.player.position = data.player_spawn
	testing.expect(t, lure_patrol(&w, &room, place.arrival))
	inside := false
	for _ in 0..<40 {
		tick(&w, &room, 1.4)
		if w.groups[0].members[0].enemy.position.layer == CAVE_LAYER { inside = true; break }
	}
	testing.expect(t, inside, "the patrol stayed outside")
}
