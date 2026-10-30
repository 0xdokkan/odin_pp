package expedition

import "core:testing"
import campaign "../campaign"
import game "../game"
import grid "../engine/grid"
import level "../level"

@(private = "file")
snow_world :: proc(t: ^testing.T, w: ^World, data: ^level.Level, seed: u64) {
	testing.expect(t, generate(w, data, .Snow, seed))
}

// The new Snow map has the spiral mountain at its fixed place, over the biome's base, the same at every run; no other
// biome does.
@(test)
test_the_snow_map_has_the_spiral_mountain_at_a_fixed_place :: proc(t: ^testing.T) {
	for seed in ([?]u64{1, 77, 123456789}) {
		w: World
		data: level.Level
		snow_world(t, &w, &data, seed)
		defer level.destroy(&data)
		testing.expect(t, mountain_present(&w))
		summit := mountain_cell(level.mountain_summit())
		testing.expect_value(t, int(level.height_at(&data, summit)), int(data.base)+level.MOUNTAIN_TOP)
		// The mountain's square is exactly the pure function's over the base, on open ground.
		wrong := 0
		for y in -level.MOUNTAIN_HALF..=level.MOUNTAIN_HALF {
			for x in -level.MOUNTAIN_HALF..=level.MOUNTAIN_HALF {
				cell := mountain_cell({x = x, y = y})
				tile, _ := level.tile_at(&data, cell)
				if int(level.height_at(&data, cell)) != int(data.base)+level.mountain_height({x = x, y = y}) || tile.kind != .Floor { wrong += 1 }
			}
		}
		testing.expectf(t, wrong == 0, "%d cells of the mountain are not as it is", wrong)
	}
	for biome in campaign.Biome {
		if biome == .Count || biome == .Snow { continue }
		w: World
		data: level.Level
		testing.expect(t, generate(&w, &data, biome, 1))
		defer level.destroy(&data)
		testing.expectf(t, !mountain_present(&w), "%v has no mountain", biome)
		testing.expect(t, int(level.height_at(&data, mountain_cell(level.mountain_summit()))) < level.MOUNTAIN_TOP)
	}
}

// The mountain is clear of every site, the spawn and every patrol's ground, and of the central band.
@(test)
test_the_mountain_is_clear_of_the_sites_and_the_spawn :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	snow_world(t, &w, &data, 3)
	defer level.destroy(&data)
	zone := mountain_zone()
	for &site in w.sites[:w.site_count] {
		// The cave halfway up the mountain is on it, as it should be.
		if site.kind == .Cave { continue }
		low, high := site_bounds(&site)
		testing.expectf(t, low.x > zone[1].x || high.x < zone[0].x || low.y > zone[1].y || high.y < zone[0].y, "the site at %v is on the mountain", site.position)
	}
	spawn := data.player_spawn
	testing.expect(t, spawn.x < zone[0].x || spawn.x > zone[1].x || spawn.y < zone[0].y || spawn.y > zone[1].y)
	size := w.side_length
	testing.expect(t, zone[0].y > size/2+3 || zone[1].y < size/2-3, "the central band is free")
	testing.expect(t, zone[1].y < size-4 && zone[0].x > 3, "the mountain is inside the map")
}

// From the spawn, a robot climbing a step at a time reaches the summit, along the path.
@(test)
test_the_summit_is_walked_to_from_the_spawn :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	snow_world(t, &w, &data, 5)
	defer level.destroy(&data)
	seen := make([]bool, len(data.tiles.cells))
	queue := make([]grid.Position, len(data.tiles.cells))
	defer delete(seen)
	defer delete(queue)
	tail := 1
	queue[0] = data.player_spawn
	seen[data.player_spawn.y*data.tiles.width+data.player_spawn.x] = true
	for head := 0; head < tail; head += 1 {
		for offset in ([4]grid.Position{{x = 1, y = 0}, {x = -1, y = 0}, {x = 0, y = 1}, {x = 0, y = -1}}) {
			q := grid.Position{x = queue[head].x+offset.x, y = queue[head].y+offset.y}
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
	summit := mountain_cell(level.mountain_summit())
	testing.expect(t, seen[summit.y*data.tiles.width+summit.x], "the summit cannot be walked to")
	midway := mountain_cell(level.mountain_midway())
	testing.expect(t, seen[midway.y*data.tiles.width+midway.x], "the halfway cell cannot be walked to")
}

// A patrol of two or three waits halfway up the path, each on a cell of it, and a relic lies at the top to be
// taken by hand.
@(test)
test_a_patrol_waits_halfway_up_and_a_relic_lies_at_the_top :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	snow_world(t, &w, &data, 9)
	defer level.destroy(&data)
	patrol := -1
	for group, i in w.groups[:w.group_count] {
		if group.patrol && distance(group.anchor, mountain_cell(level.mountain_midway())) <= 1 { patrol = i }
	}
	testing.expect(t, patrol >= 0, "a patrol at the halfway cell")
	if patrol >= 0 {
		group := &w.groups[patrol]
		testing.expect(t, group.count >= 2 && group.count <= 3)
		midway_height := int(level.height_at(&data, mountain_cell(level.mountain_midway())))
		for member in group.members[:group.count] {
			height := int(level.height_at(&data, member.enemy.position))
			testing.expectf(t, abs(height-midway_height) <= 8, "a patrol member at %v is %d steps, the path %d", member.enemy.position, height, midway_height)
			testing.expect(t, distance(member.enemy.position, group.anchor) <= 4)
		}
	}
	found := false
	for drop in w.drops[:w.drop_count] {
		if drop.position == mountain_cell(level.mountain_summit()) {
			found = true
			testing.expect_value(t, drop.item.kind, campaign.Item_Kind.Relic)
			testing.expect(t, drop.manual_only)
		}
	}
	testing.expect(t, found, "a relic at the summit")
}

// The path is packed snow with two icy stretches; the ground round the mountain is the Snow biome's.
@(test)
test_the_path_is_packed_snow_with_two_icy_stretches :: proc(t: ^testing.T) {
	icy, plain := 0, 0
	for y in -level.MOUNTAIN_HALF..=level.MOUNTAIN_HALF {
		for x in -level.MOUNTAIN_HALF..=level.MOUNTAIN_HALF {
			ground := game.expedition_terrain(u8(campaign.Biome.Snow), mountain_cell({x = x, y = y}))
			testing.expect(t, ground == .Ice || ground == .Plain)
			if ground == .Ice { icy += 1 } else { plain += 1 }
			testing.expect_value(t, ground == .Ice, level.mountain_icy({x = x, y = y}))
		}
	}
	testing.expect(t, icy >= 12 && plain > icy)
	// Another biome's ground is not the mountain's: no cell of the square is forced to Plain or Ice there.
	sand := 0
	for y in -level.MOUNTAIN_HALF..=level.MOUNTAIN_HALF {
		for x in -level.MOUNTAIN_HALF..=level.MOUNTAIN_HALF {
			if game.expedition_terrain(u8(campaign.Biome.Egypt), mountain_cell({x = x, y = y})) == .Sand { sand += 1 }
		}
	}
	testing.expect(t, sand > 0, "Egypt keeps its sand there")
}
