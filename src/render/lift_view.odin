package render

import "core:math"
import rl "vendor:raylib"
import game "../game"
import grid "../engine/grid"
import level "../level"

// THE LIFTS ON THE BOARD (game/lift.odin; Fase 7 of docs/piano-profondita.md). Each shaft has a frame, four posts up
// from its lower landing to over its upper one and a beam across their tops, with two cables down to the platform at
// its height, gliding on the way (it sets off and stops gently). A landing its platform is away from shows it: the
// shaft's dark mouth up top, a yellow and black frame below, so that a step there reads as a call. A rider is drawn on
// the platform (board_lift_riders, entity_point_ground).
//
// A shortcut's gate (level.Gate): shut, iron bars across its passage, over the Fence its cell is, with a yellow lever on
// the side it opens from; open, only its two posts.

@(private = "file")
LIFT_POST :: rl.Color{122, 136, 154, 255}
@(private = "file")
LIFT_DECK :: rl.Color{184, 190, 200, 255}
@(private = "file")
LIFT_HAZARD :: rl.Color{232, 186, 48, 255}
@(private = "file")
LIFT_CABLE :: rl.Color{44, 48, 56, 255}
@(private = "file")
GATE_IRON :: rl.Color{48, 54, 64, 255}
// How far over its upper landing a shaft's beam stands, in drawn units.
@(private = "file")
LIFT_MAST :: f32(0.75)

// Where platform `index` is this frame, in drawn units, and its column.
@(private)
lift_platform_ground :: proc(room: ^game.Room, index: int) -> (ground: f32, column: grid.Position) {
	lift := room.level_data.lifts[index]
	platform := room.lifts.platforms[index]
	to := lift.ends[platform.at]
	if !platform.moving { return cell_ground(to), to }
	t := game.lift_platform_progress(room, index)
	t = t*t*(3-2*t)
	return math.lerp(cell_ground(lift.ends[1-platform.at]), cell_ground(to), t), to
}

// A thin frame round the cell at (x, z), at `ground`: the hazard's yellow, with black corners.
@(private = "file")
draw_lift_hazard :: proc(renderer: ^Renderer, x, z, ground: f32) {
	for side in 0..<4 {
		horizontal := side%2 == 0
		offset := f32(0.43) if side < 2 else f32(-0.43)
		center := rl.Vector3{x, ground+0.015, z+offset} if horizontal else rl.Vector3{x+offset, ground+0.015, z}
		draw_resin_cube(renderer, center, 0.9 if horizontal else 0.06, 0.03, 0.06 if horizontal else 0.9, LIFT_HAZARD)
	}
	for corner in ([4][2]f32{{-0.43, -0.43}, {0.43, -0.43}, {0.43, 0.43}, {-0.43, 0.43}}) {
		draw_resin_cube(renderer, {x+corner.x, ground+0.02, z+corner.y}, 0.08, 0.035, 0.08, {20, 20, 24, 255})
	}
}

// Every lift of the room: frames, cables, platforms, and the landings their platforms are away from.
@(private)
draw_board_lifts :: proc(renderer: ^Renderer, room: ^game.Room) {
	if room == nil || room.level_data == nil { return }
	for i in 0..<room.lifts.count {
		lift := room.level_data.lifts[i]
		low, high := lift.ends[0], lift.ends[1]
		if cell_ground(low) > cell_ground(high) { low, high = high, low }
		if !tactical_cell_on_screen(renderer, low) { continue }
		x, z := f32(low.x)+0.5, f32(low.y)+0.5
		bottom, mast := cell_ground(low), cell_ground(high)+LIFT_MAST
		for corner in ([4][2]f32{{-0.46, -0.46}, {0.46, -0.46}, {0.46, 0.46}, {-0.46, 0.46}}) {
			draw_resin_cube(renderer, {x+corner.x, (bottom+mast)*0.5, z+corner.y}, 0.09, mast-bottom, 0.09, LIFT_POST)
		}
		draw_resin_cube(renderer, {x, mast, z}, 1.0, 0.1, 0.12, LIFT_HAZARD)
		draw_resin_cube(renderer, {x, mast, z}, 0.12, 0.1, 1.0, LIFT_HAZARD)
		ground, _ := lift_platform_ground(room, i)
		draw_resin_cube(renderer, {x, ground-0.05, z}, 0.86, 0.1, 0.86, LIFT_DECK)
		draw_lift_hazard(renderer, x, z, ground-0.01)
		for side in ([2]f32{-0.3, 0.3}) {
			draw_resin_cube(renderer, {x+side, (ground+mast)*0.5, z}, 0.025, mast-ground, 0.025, LIFT_CABLE)
		}
		for end in 0..<2 {
			landing := lift.ends[end]
			if !game.lift_landing_shut(room, landing) { continue }
			at := cell_ground(landing)
			if landing == high {
				rl.DrawCube({x, at+0.012, z}, 0.84, 0.02, 0.84, {6, 8, 12, 235})
			} else {
				draw_lift_hazard(renderer, x, z, at)
			}
		}
	}
	for gate in room.level_data.gates { draw_board_gate(renderer, room, gate) }
}

// One gate: its posts, and shut its bars and lever.
@(private = "file")
draw_board_gate :: proc(renderer: ^Renderer, room: ^game.Room, gate: level.Gate) {
	if !tactical_cell_on_screen(renderer, gate.cell) { return }
	_, open, _ := level.gate_at(room.level_data, gate.cell)
	ground := cell_ground(gate.cell)
	x, z := f32(gate.cell.x)+0.5, f32(gate.cell.y)+0.5
	// The passage runs from the lever to the gate; the bars stand across it.
	along := [2]f32{f32(gate.cell.x-gate.lever.x), f32(gate.cell.y-gate.lever.y)}
	across := [2]f32{-along.y, along.x}
	height := f32(0.95)
	for side in ([2]f32{-0.46, 0.46}) {
		draw_resin_cube(renderer, {x+across.x*side, ground+height*0.5, z+across.y*side}, 0.1, height, 0.1, LIFT_POST)
	}
	if open { return }
	for i in 0..<5 {
		offset := f32(i-2)*0.17
		draw_resin_cube(renderer, {x+across.x*offset, ground+height*0.5, z+across.y*offset}, 0.045, height, 0.045, GATE_IRON)
	}
	rail := [3]f32{0.92 if abs(across.x) > 0 else 0.05, 0.06, 0.92 if abs(across.y) > 0 else 0.05}
	draw_resin_cube(renderer, {x, ground+height, z}, rail.x, rail.y, rail.z, GATE_IRON)
	// The lever, on the side the gate opens from.
	lever := rl.Vector3{x-along.x*0.42+across.x*0.3, ground+0.3, z-along.y*0.42+across.y*0.3}
	draw_resin_cube(renderer, lever, 0.08, 0.6, 0.08, LIFT_POST)
	draw_resin_cube(renderer, lever+{0, 0.32, 0}, 0.14, 0.14, 0.14, LIFT_HAZARD)
}
