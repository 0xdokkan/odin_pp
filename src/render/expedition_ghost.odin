package render

import rl "vendor:raylib"
import grid "../engine/grid"
import level "../level"

// THE GHOST OF A STRUCTURE (Fase 7 of docs/piano-griglia.md): while the player is placing one, its footprint is laid on the
// ground where the mouse is, green where it can stand and red where it cannot, with a line round its edge, and a tick on
// each door. The scene says what and where (set_structure_ghost); this only draws.

Structure_Ghost :: struct {
	active:   bool,
	ok:       bool,
	id:       level.Structure_Id,
	origin:   grid.Position,
	rotation: u8,
	mirror:   bool,
}

set_structure_ghost :: proc(renderer: ^Renderer, ghost: Structure_Ghost) {
	renderer.tactical.structure_ghost = ghost
}

@(private)
draw_structure_ghost :: proc(renderer: ^Renderer) {
	ghost := renderer.tactical.structure_ghost
	if !ghost.active || ghost.id >= .Count { return }
	plan := level.placed_plan({id = ghost.id, origin = ghost.origin, rotation = ghost.rotation, mirror = ghost.mirror})
	fill := rl.Color{90, 230, 140, 105} if ghost.ok else rl.Color{240, 84, 76, 120}
	edge := rl.Color{170, 255, 200, 255} if ghost.ok else rl.Color{255, 150, 140, 255}
	for y in 0..<plan.height {
		for x in 0..<plan.width {
			cell := level.plan_at(&plan, x, y)
			if cell == .Outside { continue }
			at := grid.offset(ghost.origin, x, y)
			base := cell_ground(at)+0.07
			centre := rl.Vector3{f32(at.x)+0.5, base, f32(at.y)+0.5}
			rl.DrawCubeV(centre, {0.94, 0.03, 0.94}, fill)
			// A line along every side that has no neighbour inside the footprint.
			for side in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
				if level.plan_at(&plan, x+side.x, y+side.y) != .Outside { continue }
				a := rl.Vector3{centre.x+f32(side.x)*0.5-f32(side.y)*0.5, base+0.03, centre.z+f32(side.y)*0.5-f32(side.x)*0.5}
				b := rl.Vector3{centre.x+f32(side.x)*0.5+f32(side.y)*0.5, base+0.03, centre.z+f32(side.y)*0.5+f32(side.x)*0.5}
				rl.DrawLine3D(a, b, edge)
			}
			// A wall of the structure stands up as a low block, so that its shape reads.
			if cell == .Wall || cell == .Fence {
				height := f32(0.5) if cell == .Wall else f32(0.22)
				rl.DrawCubeV({centre.x, base+height*0.5, centre.z}, {0.8, height, 0.8}, rl.Color{fill.r, fill.g, fill.b, 70})
			}
		}
	}
}
