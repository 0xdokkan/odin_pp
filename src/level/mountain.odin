package level

import "core:math"
import grid "../engine/grid"

// THE SPIRAL MOUNTAIN (Fase 4 of docs/piano-griglia.md): a round mountain with a path of two cells'
// width that winds three times round it, up to a flat summit. A pure function of the offset from its
// centre, so the same mountain stands in every Snow expedition, in the lab and in a test alike.
//
// Along the path the ground rises a step for every cell walked (the height of a cell is the length of
// the path up to it), so a walker climbs a step at every step. Between one lap and the next there is a
// cliff of dozens of steps, a wall to a walker, so the only way up is the path itself. The outside is
// open, with no parapet: whatever is pushed off the path falls.

MOUNTAIN_LAPS   :: 3
// The path's width, which is also the distance between two laps.
MOUNTAIN_PATH   :: 2
// Radius of the outer edge of the first lap, in cells.
MOUNTAIN_OUTER  :: 9
// Half the side of the square that holds the whole mountain: nothing else is built in it.
MOUNTAIN_HALF   :: MOUNTAIN_OUTER+1
// The radius of the first lap's centre line; each lap is MOUNTAIN_PATH nearer the middle.
MOUNTAIN_START  :: f32(MOUNTAIN_OUTER)-f32(MOUNTAIN_PATH)*0.5
// Height of the summit, in steps: the length of the whole path along its centre line,
// 2*pi*(8*3-3*3) cells (a test keeps the two in step).
MOUNTAIN_TOP    :: 94
// Where the mountain stands on a Snow map of the current size (side 192); the path starts to the east of
// the centre (the angle 0) and winds towards the south.
MOUNTAIN_CENTER :: grid.Position{x = 24, y = 172}

// How far along the path a cell is, in laps (0 where it leaves the ground, MOUNTAIN_LAPS at the summit),
// and whether it is part of the mountain at all. A cell belongs to the lap whose centre line is nearest,
// and has the progress of that lap at its angle, whatever its radius: the cells across the path's width
// have one height.
mountain_progress :: proc(offset: grid.Position) -> (laps: f32, inside: bool) {
	x, y := f32(offset.x), f32(offset.y)
	radius := math.sqrt(x*x+y*y)
	if radius > f32(MOUNTAIN_OUTER)+0.5 { return 0, false }
	turn := math.atan2(y, x)/(2*math.PI)
	if turn < 0 { turn += 1 }
	reach := (MOUNTAIN_START-radius)/f32(MOUNTAIN_PATH)
	lap := math.round(reach-turn)
	return lap+turn, true
}

// The height at `laps` of progress, in steps: the path's length so far.
mountain_path_length :: proc(laps: f32) -> f32 {
	return 2*math.PI*(MOUNTAIN_START*laps-f32(MOUNTAIN_PATH)*laps*laps*0.5)
}

// The height of the mountain at `offset` from its centre, in steps (0 outside it).
mountain_height :: proc(offset: grid.Position) -> int {
	laps, inside := mountain_progress(offset)
	if !inside || laps < 0 { return 0 }
	if laps >= MOUNTAIN_LAPS { return MOUNTAIN_TOP }
	return min(MOUNTAIN_TOP, int(mountain_path_length(laps)))
}

// Cells of the path where the snow has frozen to ice: two stretches, one in the second lap and one in the
// third.
mountain_icy :: proc(offset: grid.Position) -> bool {
	laps, inside := mountain_progress(offset)
	if !inside || laps < 0 || laps >= MOUNTAIN_LAPS { return false }
	return (laps >= 1.15 && laps < 1.45) || (laps >= 2.2 && laps < 2.5)
}

// The cell of the path at `laps` of progress (the middle of its width).
mountain_path_cell :: proc(laps: f32) -> grid.Position {
	angle := 2*math.PI*(laps-math.floor(laps))
	radius := MOUNTAIN_START-laps*f32(MOUNTAIN_PATH)
	return {x = int(math.round(radius*math.cos(angle))), y = int(math.round(radius*math.sin(angle)))}
}

// The cell halfway up the climb, on the path, where a patrol waits.
mountain_midway :: proc() -> grid.Position {
	return mountain_path_cell(f32(MOUNTAIN_LAPS)*0.5)
}

// The cell nearest the middle at the top, where the reward lies.
mountain_summit :: proc() -> grid.Position {
	best := grid.Position{}
	best_distance := 1<<30
	for y in -MOUNTAIN_HALF..=MOUNTAIN_HALF {
		for x in -MOUNTAIN_HALF..=MOUNTAIN_HALF {
			if mountain_height({x = x, y = y}) != MOUNTAIN_TOP { continue }
			distance := x*x+y*y
			if distance < best_distance { best, best_distance = {x = x, y = y}, distance }
		}
	}
	return best
}

// Raises the mountain on `data`, centred at `centre`: every cell of its square is levelled to the
// mountain's height there, over the map's base (Level.base), and a wall or a prop on it is cleared (the
// mountain is built on open ground). False if the square does not fit in the map.
mountain_stamp :: proc(data: ^Level, centre: grid.Position) -> bool {
	if data == nil { return false }
	if centre.x-MOUNTAIN_HALF < 0 || centre.y-MOUNTAIN_HALF < 0 ||
	   centre.x+MOUNTAIN_HALF >= data.tiles.width || centre.y+MOUNTAIN_HALF >= data.tiles.height { return false }
	for y in -MOUNTAIN_HALF..=MOUNTAIN_HALF {
		for x in -MOUNTAIN_HALF..=MOUNTAIN_HALF {
			cell := grid.offset(centre, x, y)
			tile, _ := tile_at(data, cell)
			if tile.kind != .Void && tile.kind != .Floor { _ = set_tile(data, cell, {.Floor}) }
			if !set_height(data, cell, data.base+i32(mountain_height({x = x, y = y}))) { return false }
		}
	}
	return true
}
