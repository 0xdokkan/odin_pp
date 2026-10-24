package expedition

import campaign "../campaign"
import game "../game"
import grid "../engine/grid"
import level "../level"
import rng "../engine/rng"

// THE SPIRAL MOUNTAIN IN THE SNOW MAP (Fase 4 of docs/piano-griglia.md). The mountain itself is
// level.mountain_height (a pure function of the offset from its centre); here it is given a place on the
// map, a patrol on its path and a reward at the top. It stands in a gap of the map left by the sites, at
// the bottom left, in the new maps (side 192); an older, smaller map has none.

mountain_present :: proc(w: ^World) -> bool {
	return w.biome == .Snow && size(w) == map_size(.Snow)
}

// The square the mountain keeps level and clear, with two cells of margin, for the relief to leave alone.
mountain_zone :: proc() -> [2]grid.Position {
	c, h := level.MOUNTAIN_CENTER, level.MOUNTAIN_HALF+2
	return {{c.x-h, c.y-h}, {c.x+h, c.y+h}}
}

// The map cell at `offset` from the mountain's centre.
mountain_cell :: proc(offset: grid.Position) -> grid.Position {
	return {level.MOUNTAIN_CENTER.x+offset.x, level.MOUNTAIN_CENTER.y+offset.y}
}

// Raises the mountain, after the relief and before the inhabitants.
@(private)
apply_mountain :: proc(w: ^World, data: ^level.Level) {
	if mountain_present(w) { _ = level.mountain_stamp(data, level.MOUNTAIN_CENTER) }
}

// A patrol halfway up the path, and a relic at the top (picked up by hand: the cells below it are in
// reach on the lap beneath, a cliff away).
@(private)
add_mountain_inhabitants :: proc(w: ^World, data: ^level.Level, content: ^rng.Rng) {
	if !mountain_present(w) { return }
	midway := mountain_cell(level.mountain_midway())
	count := 2+int(rng.next_u64(content)%2)
	add_group(w, data, -1, midway, count, true, false)
	group := &w.groups[w.group_count-1]
	// The patrol stands along the path, a cell or so apart, and not on the laps above and below it.
	for i in 0..<group.count {
		group.members[i].enemy.position = mountain_cell(level.mountain_path_cell(f32(level.MOUNTAIN_LAPS)*0.5+f32(i)*0.04))
	}
	variant := 1+i32(rng.next_u64(content)%(u64(game.Relic_Id.Count)-1))
	_ = add_drop(w, mountain_cell(level.mountain_summit()), campaign.make_item(.Relic, 1, variant), manual_only = true)
}
