package expedition

import "core:fmt"
import "core:slice"
import "core:testing"
import campaign "../campaign"
import game "../game"
import grid "../engine/grid"
import level "../level"

// What a biome's relief looks like in numbers: the tallest cell and the share of cells above ground.
@(private = "file")
relief_numbers :: proc(data: ^level.Level) -> (tallest: int, raised_percent: int) {
	raised := 0
	for steps in data.heights {
		tallest = max(tallest, int(steps))
		if steps > 0 { raised += 1 }
	}
	if len(data.heights) > 0 { raised_percent = raised*100/len(data.heights) }
	return
}

// Every biome has a relief of its own, tall enough to see and walk over, and the same one at every run.
@(test)
test_every_biome_has_a_relief_of_its_own_and_the_same_at_every_run :: proc(t: ^testing.T) {
	for biome in campaign.Biome {
		if biome == .Count { continue }
		a, b: World
		first, second: level.Level
		testing.expect(t, generate(&a, &first, biome, 1))
		testing.expect(t, generate(&b, &second, biome, 987654321))
		defer level.destroy(&first)
		defer level.destroy(&second)
		testing.expectf(t, level.has_heights(&first), "%v has a relief", biome)
		testing.expect(t, slice.equal(first.heights[:], second.heights[:]), "the relief does not depend on the seed")
		tallest, raised := relief_numbers(&first)
		fmt.printfln("relief %v: tallest %d steps, %d%% of the cells above ground", biome, tallest, raised)
		testing.expectf(t, tallest >= 2, "%v: the tallest cell is %d steps", biome, tallest)
		testing.expectf(t, raised >= 2, "%v: only %d%% of the map is raised", biome, raised)
		testing.expect(t, tallest <= int(RELIEF_MAX))
	}
}

// The sites, the spawn and the patrols' ground stay level, and a robot can walk from the spawn to every
// site and to the exit climbing a step at a time.
@(test)
test_the_ground_that_matters_is_level_and_every_site_and_the_exit_can_be_walked_to :: proc(t: ^testing.T) {
	for biome in campaign.Biome {
		if biome == .Count { continue }
		w: World
		data: level.Level
		testing.expect(t, generate(&w, &data, biome, 5))
		defer level.destroy(&data)
		// The spawn's square is level (where there is ground).
		spawn_height := level.height_at(&data, data.player_spawn)
		uneven := 0
		for dy in -8..=8 {
			for dx in -8..=8 {
				cell := grid.Position{data.player_spawn.x+dx, data.player_spawn.y+dy}
				tile, ok := level.tile_at(&data, cell)
				if ok && tile.kind != .Void && level.height_at(&data, cell) != spawn_height { uneven += 1 }
			}
		}
		testing.expectf(t, uneven == 0, "%v: %d cells of the spawn's square are not level", biome, uneven)
		// Each site is level inside its bounds.
		uneven = 0
		for &site in w.sites[:w.site_count] {
			low, high := site_bounds(&site)
			base := level.height_at(&data, site.position)
			for y in low.y..=high.y {
				for x in low.x..=high.x {
					tile, ok := level.tile_at(&data, {x, y})
					if ok && tile.kind != .Void && level.height_at(&data, {x, y}) != base { uneven += 1 }
				}
			}
		}
		testing.expectf(t, uneven == 0, "%v: %d cells of the sites are not level", biome, uneven)
		// Walk from the spawn a step at a time.
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
		for site in w.sites[:w.site_count] {
			near := false
			for dy in -3..=3 {
				for dx in -3..=3 {
					p := grid.Position{site.position.x+dx, site.position.y+dy}
					if p.x >= 0 && p.y >= 0 && p.x < data.tiles.width && p.y < data.tiles.height { near = near || seen[p.y*data.tiles.width+p.x] }
				}
			}
			testing.expectf(t, near, "%v: the site at %v cannot be walked to", biome, site.position)
		}
		for tile, at in data.tiles.cells {
			if tile.kind == .Exit { testing.expectf(t, seen[at], "%v: the exit cannot be walked to", biome) }
		}
		// Nothing walkable is left out by a cliff.
		stranded := 0
		for tile, at in data.tiles.cells {
			if level.is_walkable(tile.kind) && !seen[at] { stranded += 1 }
		}
		if biome != .Sky { testing.expectf(t, stranded == 0, "%v: %d walkable cells cannot be reached by walking", biome, stranded) }
	}
}

// The smooth ground has no cliff of its own: neighbouring cells are at most a step apart, but at the edge
// of a plateau (a cliff of the plateaus' own) in the biomes that have them.
@(test)
test_the_smooth_biomes_have_no_cliffs_at_all :: proc(t: ^testing.T) {
	for biome in ([?]campaign.Biome{.Jungle, .Egypt, .Vietnam, .Gothic, .Sky, .Space, .Secret}) {
		w: World
		data: level.Level
		testing.expect(t, generate(&w, &data, biome, 2))
		defer level.destroy(&data)
		width := data.tiles.width
		cliffs := 0
		for y in 0..<data.tiles.height {
			for x in 0..<width {
				here := data.tiles.cells[y*width+x].kind
				if here == .Void { continue }
				for step in ([2][2]int{{1, 0}, {0, 1}}) {
					nx, ny := x+step.x, y+step.y
					if nx >= width || ny >= data.tiles.height || data.tiles.cells[ny*width+nx].kind == .Void { continue }
					if abs(int(data.heights[ny*width+nx])-int(data.heights[y*width+x])) > 1 { cliffs += 1 }
				}
			}
		}
		testing.expectf(t, cliffs == 0, "%v has %d cliffs", biome, cliffs)
	}
}

// The biomes with plateaus have cliffs, each with a stair beside it: a plateau's top can be walked to.
@(test)
test_the_biomes_with_plateaus_have_cliffs_and_a_stair_up_each :: proc(t: ^testing.T) {
	for biome in ([?]campaign.Biome{.Cyber, .West, .City, .Snow, .Inferno}) {
		w: World
		data: level.Level
		testing.expect(t, generate(&w, &data, biome, 2))
		defer level.destroy(&data)
		tallest, _ := relief_numbers(&data)
		testing.expectf(t, tallest >= 2, "%v has plateaus", biome)
	}
}

// The relief is saved with the world: restoring a snapshot brings the heights back, and a snapshot
// without any (a save from before the relief) restores flat, its tiles as they were.
@(test)
test_the_relief_is_saved_and_an_old_snapshot_loads_flat :: proc(t: ^testing.T) {
	w: World
	data: level.Level
	p: game.Player
	room := test_world(t, &w, &data, &p, .Egypt)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	testing.expect(t, level.has_heights(&data))
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
	testing.expect(t, slice.equal(data.heights[:], data2.heights[:]), "the same relief")
	// An old snapshot has no heights: the map is flat, and nothing else changed.
	s.heights = {}
	w3: World
	data3: level.Level
	p3: game.Player
	room3: game.Room
	testing.expect(t, restore(s, &w3, &data3, &p3, &room3))
	defer level.destroy(&data3)
	defer game.destroy_room(&room3)
	testing.expect(t, !level.has_heights(&data3), "flat")
	for tile, at in data.tiles.cells { testing.expect_value(t, data3.tiles.cells[at], tile) }
}
