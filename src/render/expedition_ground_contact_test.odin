package render

import "core:testing"
import rl "vendor:raylib"
import grid "../engine/grid"

// The cream container has a real recessed soil surface. Every leaf is rooted at that
// surface, while the whole object retains the blocked cell's original footprint.
@(test)
test_cyber_planter_has_recessed_soil_and_raised_roots :: proc(t: ^testing.T) {
	b: Expedition_Geometry_Builder
	defer { delete(b.vertices); delete(b.lines) }
	cell: grid.Position
	for expedition_cell_hash(cell, 0xC7)%7 >= 5 { cell.x += 1 }
	draw_expedition_cyber_outdoor({mode = .Bake, builder = &b}, cell)
	soil, rim, leaves := 0, 0, 0
	for v in b.vertices {
		testing.expect(t, v.position.x >= f32(cell.x) && v.position.x <= f32(cell.x+1))
		testing.expect(t, v.position.z >= f32(cell.y) && v.position.z <= f32(cell.y+1))
		if v.color == CYBER_RECESS && v.normal.y > .99 {
			soil += 1
			testing.expect(t, abs(v.position.y-.23) < .001)
		}
		if v.color == EXPEDITION_PAPER_EDGE && v.normal.y > .99 {
			rim += 1
			testing.expect(t, abs(v.position.y-.285) < .001)
		}
		if v.color == (rl.Color{29,143,79,255}) || v.color == (rl.Color{68,174,78,255}) || v.color == (rl.Color{126,199,61,255}) {
			leaves += 1
			testing.expect(t, v.position.y >= .23)
		}
	}
	testing.expect(t, soil > 0 && rim > 0 && leaves > 0)
}

@(test)
test_wall_corner_classification_preserves_cream_only_at_turns :: proc(t: ^testing.T) {
	for turn in 0..<4 {
		neighbours: [4]bool
		neighbours[turn], neighbours[(turn+1)%4] = true, true
		testing.expect(t, ink_wall_corner(neighbours))
		neighbours[(turn+1)%4] = false
		testing.expect(t, !ink_wall_corner(neighbours))
		neighbours[(turn+2)%4] = true
		testing.expect(t, !ink_wall_corner(neighbours))
	}
	testing.expect(t, !ink_wall_corner({}))
	testing.expect(t, !ink_wall_corner({true,true,true,true}))
}
