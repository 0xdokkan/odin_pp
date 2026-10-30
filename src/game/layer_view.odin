package game

import "core:math"
import grid "../engine/grid"
import level "../level"

// HOW THE LAYERS SHOW ROUND THE ROBOT (Fase 4 of docs/piano-profondita.md). Pure functions of the map's layers and
// of where the robot stands, like structure_visibility: the renderers only draw what they say, and they change no
// rule.
//
// - What stands over the robot's head on a layer above his (a bridge's deck, the rock over a cave) opens little by
//   little as he nears it, within LAYER_FADE_FAR cells, down to LAYER_FADE_MINIMUM next to him.
// - Under a vault (in a cave, rock over him) everything off his layer is darker, as outside a building; on a
//   layer over the ground (a bridge) what is under him is a little darker (the user's choice).
// - A figure that something drawn whole hides from the camera shows its outline.
//
// Positions are in cell coordinates: the cell (x, y) spans [x, x+1) by [y, y+1).

LAYER_FADE_FAR :: f32(6)
LAYER_FADE_MINIMUM :: f32(0.15)
// How much darker the outside of a cave is, and what is under a bridge.
LAYER_OUTSIDE_DIM :: f32(0.6)
LAYER_BELOW_DIM :: f32(0.25)
// The pieces at least this see-through let the pointer through.
LAYER_PICK_THROUGH :: f32(0.5)

// Where the robot stands, for the view: his point and his cell (with its layer).
Layer_Viewer :: struct {
	point: [2]f32,
	cell:  grid.Position,
}

@(private = "file")
distance_to_square :: proc(x, y: f32, cell_x, cell_y: int) -> f32 {
	dx := max(f32(cell_x)-x, 0, x-f32(cell_x+1))
	dy := max(f32(cell_y)-y, 0, y-f32(cell_y+1))
	return math.sqrt(dx*dx+dy*dy)
}

@(private = "file")
smooth :: proc(t: f32) -> f32 {
	k := clamp(t, 0, 1)
	return k*k*(3-2*k)
}

// The highest top of `cell`'s piece: its floor, in steps.
@(private = "file")
cell_top :: proc(m: ^level.Layer_Map, cell: grid.Position) -> i32 {
	return level.map_height(m, cell)
}

// How whole `cell` is drawn (1 whole): faded when it is on a layer above the viewer's, its top over his head, and
// within LAYER_FADE_FAR cells of him.
layer_cover_opacity :: proc(m: ^level.Layer_Map, viewer: Layer_Viewer, cell: grid.Position) -> f32 {
	if m == nil || cell.layer <= viewer.cell.layer || !level.kind_has_floor(level.map_tile(m, cell)) &&
	   cell.layer != grid.GROUND_LAYER { return 1 }
	if cell_top(m, cell) <= level.map_height(m, viewer.cell)+HEIGHT_EYE_STEPS { return 1 }
	d := distance_to_square(viewer.point.x, viewer.point.y, cell.x, cell.y)
	if d >= LAYER_FADE_FAR { return 1 }
	return 1-(1-LAYER_FADE_MINIMUM)*smooth((LAYER_FADE_FAR-d)/(LAYER_FADE_FAR-1))
}

// Whether the viewer is under a vault: on a layer under the ground, with rock over him.
layer_viewer_in_vault :: proc(m: ^level.Layer_Map, viewer: Layer_Viewer) -> bool {
	if m == nil || viewer.cell.layer >= grid.GROUND_LAYER { return false }
	column := level.column_of(m, viewer.cell.x, viewer.cell.y)
	return level.column_room_top(&column, level.map_height(m, viewer.cell)) < level.COLUMN_FAR
}

// How much darker `cell` is drawn (0 not at all): off the viewer's layer when he is under a vault; under his layer
// when he is on a layer over the ground.
layer_cell_dim :: proc(m: ^level.Layer_Map, viewer: Layer_Viewer, cell: grid.Position) -> f32 {
	if viewer.cell.layer > grid.GROUND_LAYER && cell.layer < viewer.cell.layer { return LAYER_BELOW_DIM }
	if cell.layer != viewer.cell.layer && layer_viewer_in_vault(m, viewer) { return LAYER_OUTSIDE_DIM }
	return 0
}

// The piece of column (x, y) that holds the height `steps` (a fraction), and whether it holds it: the floor that
// stands on the solid it is in (a bridge's deck is its bridge's, the rock over a cave and the ground under it are
// the ground's, a wall the column's ground cell). None where the height is free.
layer_solid_owner :: proc(m: ^level.Layer_Map, x, y: int, steps: f32) -> (owner: grid.Position, inside: bool) {
	column := level.column_of(m, x, y)
	for span in column.solids[:column.solid_count] {
		if f32(span.bottom) > steps || steps >= f32(span.top) { continue }
		owner = {x = x, y = y}
		for floor, i in column.floors[:column.floor_count] { if column.floor_heights[i] == span.top { owner = floor } }
		return owner, true
	}
	return
}

// Whether something drawn whole (or nearly: not see-through enough to let the pointer by) hides the figure at
// `target` (a point in drawn units) standing on `cell` from the camera at `eye`: the line between them passes
// inside a solid whose piece is not faded, the figure's own floor aside.
layer_figure_hidden :: proc(m: ^level.Layer_Map, viewer: Layer_Viewer, eye, target: [3]f32, cell: grid.Position) -> bool {
	if m == nil { return false }
	delta := target-eye
	length := math.sqrt(delta.x*delta.x+delta.z*delta.z)
	steps := int(length/0.2)
	for i in 1..<steps {
		t := f32(i)/f32(steps)
		p := eye+delta*t
		x, y := int(math.floor(p.x)), int(math.floor(p.z))
		if x < 0 || y < 0 || x >= m.width || y >= m.height { continue }
		// The figure's own floor never hides it; the deck over it does.
		owner, inside := layer_solid_owner(m, x, y, p.y/HEIGHT_STEP_DRAWN)
		if inside && owner != cell && layer_cover_opacity(m, viewer, owner) > LAYER_PICK_THROUGH { return true }
	}
	return false
}
