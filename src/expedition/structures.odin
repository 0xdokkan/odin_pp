package expedition

import grid "../engine/grid"
import level "../level"

// STRUCTURES IN THE EXPEDITIONS (Fase 6 of docs/piano-griglia.md): buildings and complex
// objects belong to a biome's fixed geography, like its islands and its sites: where they
// stand comes from the biome, never from the run's seed, so the same biome has the same
// ones at every run. For now only the first biome (Robotica cibernetica) has them, as the
// test biome the user chose. The generic parts (plans, turns, placement checks) are in
// level/structure.odin; this only says which structures go where.

MAX_WORLD_STRUCTURES :: 24

// Where a structure is wanted: its place on the map in percent, and how it is turned. If
// the exact place is not free (cover, a site, the spawn) the nearest free one is taken,
// searching round it in a fixed order.
Structure_Spot :: struct {
	id:       level.Structure_Id,
	x, y:     int,
	rotation: u8,
	mirror:   bool,
}

CYBER_STRUCTURES :: [?]Structure_Spot{
	{.Cottage, 14, 44, 0, false}, {.Hut, 20, 66, 1, false}, {.Temple, 30, 33, 0, false}, {.Pen, 12, 58, 0, false},
	{.Cart, 24, 56, 0, false}, {.Fountain, 36, 62, 0, false}, {.Statue, 29, 58, 0, false}, {.Machine, 40, 44, 0, false},
	{.Ruin, 34, 74, 0, false}, {.Cottage, 48, 36, 3, true}, {.Hut, 52, 60, 2, false}, {.Temple, 62, 40, 0, true},
	{.Cottage, 58, 78, 1, false}, {.Cart, 70, 56, 0, false},
}

// The farthest, in cells, a structure is moved from its wanted place to find a free one.
STRUCTURE_SEARCH_RADIUS :: 16

// Whether `cell` must be left clear: round a site (its plan and a margin), round the spawn and round
// a patrol's anchor.
@(private)
structure_keep_clear :: proc(user: rawptr, cell: grid.Position) -> bool {
	w := cast(^World)user
	for site in w.sites[:w.site_count] {
		half := site_layout(site.kind).half_extent
		if site.orientation%2 == 1 { half = {half.y, half.x} }
		if abs(cell.x-site.position.x) <= half.x+4 && abs(cell.y-site.position.y) <= half.y+4 { return true }
	}
	size := w.side_length
	if distance(cell, {7, size/2}) <= 9 { return true }
	for i in 0..<4 {
		if distance(cell, {size*(35+i*13)/100, size*(35+(i%2)*28)/100}) <= 7 { return true }
	}
	return false
}

// Places the structures wanted in biome `w.biome` on `data`, recording each in the world.
@(private)
place_structures :: proc(w: ^World, data: ^level.Level) {
	spots := CYBER_STRUCTURES
	if w.biome != .Cyber { return }
	size := w.side_length
	for spot in spots {
		if w.structure_count >= MAX_WORLD_STRUCTURES { break }
		wanted := grid.Position{spot.x*size/100, spot.y*size/100}
		placed := false
		for radius in 0..=STRUCTURE_SEARCH_RADIUS {
			for dy in -radius..=radius {
				for dx in -radius..=radius {
					if max(abs(dx), abs(dy)) != radius { continue }
					at := grid.Position{wanted.x+dx, wanted.y+dy}
					if _, err := level.place_structure(data, spot.id, at, spot.rotation, spot.mirror, structure_keep_clear, w); err == .None {
						w.structures[w.structure_count] = data.structures[len(data.structures)-1]
						w.structure_count += 1
						placed = true
					}
					if placed { break }
				}
				if placed { break }
			}
			if placed { break }
		}
	}
}
