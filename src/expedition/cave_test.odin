package expedition

import "core:slice"
import "core:testing"
import campaign "../campaign"
import game "../game"
import grid "../engine/grid"
import level "../level"

@(private = "file")
CAVE_BIOMES :: [4]campaign.Biome{.Snow, .West, .Egypt, .Inferno}

// The cave biomes have between one and three caves at every run, each at an arch that is a secret site; the Snow's first is on the
// spiral mountain's path; the others have none.
@(test)
test_the_four_biomes_have_one_to_three_caves_and_the_others_none :: proc(t: ^testing.T) {
	for biome in campaign.Biome {
		if biome == .Count { continue }
		for seed in ([?]u64{1, 7, 99, 12345, 777777}) {
			w: World
			data: level.Level
			testing.expect(t, generate(&w, &data, biome, seed))
			defer level.destroy(&data)
			if !cave_biome(biome) {
				testing.expectf(t, w.cave_count == 0, "%v has %d caves", biome, w.cave_count)
				continue
			}
			testing.expectf(t, w.cave_count >= 1 && w.cave_count <= 3, "%v seed %d has %d caves", biome, seed, w.cave_count)
			for cave, i in w.caves[:w.cave_count] {
				site := w.sites[cave.site]
				testing.expect(t, site.kind == .Cave && site.secret && site.active && site.state == .Unvisited)
				testing.expect_value(t, cave_of_site(&w, cave.site), i)
				// Each has its foes (marked with its number) and its secret.
				groups, drops := 0, 0
				for group in w.groups[:w.group_count] { if int(group.cave) == i+1 { groups += 1; testing.expect(t, group.count >= 2 && !group.patrol) } }
				for drop in w.drops[:w.drop_count] { if int(drop.cave) == i+1 { drops += 1; testing.expect(t, drop.manual_only) } }
				testing.expectf(t, groups >= 1 && groups <= 3 && drops == 2, "%v cave %d has %d groups and %d drops", biome, i, groups, drops)
			}
			// What is not a cave's is the open map's.
			for group in w.groups[:w.group_count] { if group.cave == 0 { testing.expect(t, group.count >= 1) } }
			if biome == .Snow {
				testing.expect_value(t, w.sites[w.caves[0].site].position, mountain_cell(level.mountain_path_cell(1.75)))
			}
		}
	}
}

// The geography is the biome's, not the run's: the tiles do not depend on the seed, only which of the places has a cave does.
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
	}
}

// The arch of every cave can be walked to from the spawn, one step of height at a time, and the doorway's cell is floor.
@(test)
test_every_arch_can_be_walked_to_from_the_spawn :: proc(t: ^testing.T) {
	for biome in CAVE_BIOMES {
		for seed in ([?]u64{2, 31, 4444}) {
			w: World
			data: level.Level
			testing.expect(t, generate(&w, &data, biome, seed))
			defer level.destroy(&data)
			seen := make([]bool, len(data.tiles.cells))
			queue := make([]grid.Position, len(data.tiles.cells))
			defer delete(seen)
			defer delete(queue)
			tail := 1
			queue[0] = data.player_spawn
			seen[data.player_spawn.y*data.tiles.width+data.player_spawn.x] = true
			for head := 0; head < tail; head += 1 {
				for offset in ([4]grid.Position{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
					q := grid.Position{queue[head].x+offset.x, queue[head].y+offset.y}
					tile, ok := level.tile_at(&data, q)
					if !ok || !level.is_walkable(tile.kind) { continue }
					if abs(int(level.height_at(&data, q))-int(level.height_at(&data, queue[head]))) > 1 { continue }
					at := q.y*data.tiles.width+q.x
					if seen[at] { continue }
					seen[at] = true
					queue[tail] = q
					tail += 1
				}
			}
			for cave in w.caves[:w.cave_count] {
				p := w.sites[cave.site].position
				tile, _ := level.tile_at(&data, p)
				testing.expectf(t, level.is_walkable(tile.kind), "%v: the arch at %v is not floor", biome, p)
				// The cell in front of the doorway, or (on the mountain) the path itself.
				on_mountain := mountain_present(&w) && p == mountain_cell(level.mountain_path_cell(1.75))
				front := p if on_mountain else grid.Position{p.x, p.y+1}
				testing.expectf(t, seen[front.y*data.tiles.width+front.x], "%v seed %d: the arch at %v cannot be walked to", biome, seed, p)
			}
		}
	}
}

@(private = "file")
cave_world :: proc(t: ^testing.T, w: ^World, data: ^level.Level, p: ^game.Player, biome: campaign.Biome) -> game.Room {
	room := test_world(t, w, data, p, biome)
	game.end_expedition_encounter(&room)
	room.phase = .Loot
	return room
}

// Going into a cave puts the open map away and stamps the cave; coming out brings it back, every tile and height, and the player
// stands at the arch again.
@(test)
test_a_cave_is_entered_and_left_and_the_open_map_comes_back_as_it_was :: proc(t: ^testing.T) {
	for biome in CAVE_BIOMES {
		w: World
		data: level.Level
		p: game.Player
		room := cave_world(t, &w, &data, &p, biome)
		defer level.destroy(&data)
		defer game.destroy_room(&room)
		testing.expect(t, w.cave_count >= 1)
		outer := new(Outer_Map)
		defer free(outer)
		before_tiles := slice.clone(data.tiles.cells[:])
		before_heights := slice.clone(data.heights[:])
		defer delete(before_tiles)
		defer delete(before_heights)
		arch := w.sites[w.caves[0].site].position
		room.player.position = grid.Position{arch.x, arch.y+1}
		testing.expect(t, enter_cave(&w, &data, &room, outer, 0))
		testing.expect_value(t, w.in_cave, 1)
		arrival, ok := cave_arrival(&w)
		testing.expect(t, ok && room.player.position == arrival)
		plan := level.cave_plan(w.caves[0].seed)
		origin := cave_origin(&w)
		for y in 0..<data.tiles.height {
			for x in 0..<data.tiles.width {
				tile, _ := level.tile_at(&data, {x, y})
				inside := x >= origin.x && y >= origin.y && x < origin.x+level.CAVE_WIDTH && y < origin.y+level.CAVE_HEIGHT
				if !inside { testing.expect_value(t, tile.kind, level.Tile_Kind.Void); continue }
				if (grid.Position{x, y}) == arrival { testing.expect_value(t, tile.kind, level.Tile_Kind.Player_Spawn); continue }
				testing.expect_value(t, tile.kind, level.Tile_Kind.Wall if plan.rows[y-origin.y][x-origin.x] == '#' else level.Tile_Kind.Floor)
			}
		}
		testing.expect(t, !level.has_heights(&data), "a cave is flat")
		// Not twice.
		testing.expect(t, !enter_cave(&w, &data, &room, outer, 0))
		testing.expect(t, exit_cave(&w, &data, &room, outer))
		testing.expect_value(t, w.in_cave, 0)
		testing.expect_value(t, room.player.position, grid.Position{arch.x, arch.y+1})
		testing.expect(t, slice.equal(before_tiles, data.tiles.cells[:]), "the tiles are as they were")
		testing.expect(t, slice.equal(before_heights, data.heights[:]) || (len(before_heights) == 0 && len(data.heights) == 0), "the heights are as they were")
		testing.expect(t, !exit_cave(&w, &data, &room, outer), "out already")
	}
}

// A fight stops the crossing, and a cave's groups and drops are only where the player is: the open map's groups sleep in the
// cave, and its sites do nothing.
@(test)
test_a_fight_stops_the_crossing_and_groups_and_drops_belong_to_where_the_player_is :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	p: game.Player
	room := cave_world(t, &w, &data, &p, .Egypt)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	outer := new(Outer_Map)
	defer free(outer)
	arch := w.sites[w.caves[0].site].position
	room.player.position = {arch.x, arch.y+1}
	_ = game.begin_expedition_encounter(&room)
	testing.expect(t, !enter_cave(&w, &data, &room, outer, 0), "no crossing in a fight")
	game.end_expedition_encounter(&room)
	room.phase = .Loot
	testing.expect(t, enter_cave(&w, &data, &room, outer, 0))
	testing.expect(t, in_scope(&w, 1) && !in_scope(&w, 0) && !in_scope(&w, 2))
	testing.expect_value(t, nearest_site(&w, room.player.position), -1)
	// A tick in the cave next to its first group never wakes a group of the open map.
	cave_group := -1
	for group, i in w.groups[:w.group_count] { if group.cave == 1 && cave_group < 0 { cave_group = i } }
	testing.expect(t, cave_group >= 0)
	room.player.position = w.groups[cave_group].members[0].enemy.position
	room.player.position.x -= 1
	for _ in 0..<20 { tick(&w, &room, 0.1) }
	for group, i in w.groups[:w.group_count] {
		if group.cave == 0 { testing.expectf(t, !group.active, "group %d of the open map woke up in the cave", i) }
	}
	// And the biome's ground is gone: nothing slows or burns in a cave.
	testing.expect_value(t, ground(&w, room.player.position), Terrain.Plain)
	testing.expect_value(t, room.player.tactical.config.expedition_biome, u8(255))
}

// A checkpoint taken in a cave restores in it: the cave's tiles, the open map put away, the groups, the place of the return.
@(test)
test_a_checkpoint_in_a_cave_comes_back_in_the_cave_with_the_open_map_kept :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	p: game.Player
	room := cave_world(t, &w, &data, &p, .Inferno)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	outer := new(Outer_Map)
	defer free(outer)
	arch := w.sites[w.caves[0].site].position
	room.player.position = {arch.x, arch.y+1}
	open_tiles := slice.clone(data.tiles.cells[:])
	defer delete(open_tiles)
	testing.expect(t, enter_cave(&w, &data, &room, outer, 0))
	s := new(Snapshot)
	defer free(s)
	testing.expect(t, capture(&w, &room, s, outer))
	testing.expect(t, valid_snapshot(s))
	// A snapshot in a cave without the map put away is not one.
	bad := new(Snapshot)
	defer free(bad)
	testing.expect(t, !capture(&w, &room, bad, nil))
	w2: World
	data2: level.Level
	p2: game.Player
	room2: game.Room
	outer2 := new(Outer_Map)
	defer free(outer2)
	testing.expect(t, restore(s, &w2, &data2, &p2, &room2, outer2))
	defer level.destroy(&data2)
	defer game.destroy_room(&room2)
	testing.expect_value(t, w2.in_cave, 1)
	testing.expect_value(t, w2.cave_return, w.cave_return)
	testing.expect(t, slice.equal(data.tiles.cells[:], data2.tiles.cells[:]), "the cave's tiles")
	testing.expect(t, slice.equal(outer.kinds[:], outer2.kinds[:]) && slice.equal(outer.heights[:], outer2.heights[:]), "the open map put away")
	// Leaving from the restored game gives the open map of before, and the spawn tile is where it was.
	testing.expect(t, exit_cave(&w2, &data2, &room2, outer2))
	testing.expect(t, slice.equal(open_tiles, data2.tiles.cells[:]), "the open map comes back")
	testing.expect_value(t, data2.player_spawn, data.player_spawn)
	// A checkpoint of a cave with a cave number out of range is not one.
	s.world.in_cave = s.world.cave_count+1
	testing.expect(t, !valid_snapshot(s))
}

// What drops in a cave stays in it: its experience and the items left there are the cave's, and leaving takes the player to the
// open map's own.
@(test)
test_what_drops_in_a_cave_belongs_to_the_cave :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	p: game.Player
	room := cave_world(t, &w, &data, &p, .West)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	outer := new(Outer_Map)
	defer free(outer)
	arch := w.sites[w.caves[0].site].position
	room.player.position = {arch.x, arch.y+1}
	open_drops := w.drop_count
	testing.expect(t, enter_cave(&w, &data, &room, outer, 0))
	add_xp_drop(&w, room.player.position, 6)
	testing.expect(t, add_drop(&w, room.player.position, campaign.make_item(.Healing)))
	testing.expect_value(t, w.drop_count, open_drops+2)
	for drop in w.drops[open_drops:w.drop_count] { testing.expect_value(t, drop.cave, u8(1)) }
	testing.expect(t, exit_cave(&w, &data, &room, outer))
	for drop in w.drops[open_drops:w.drop_count] { testing.expect(t, !in_scope(&w, drop.cave)) }
	// A cave's secret is its two drops, gone once they are taken.
	testing.expect(t, !cave_looted(&w, 0))
}
