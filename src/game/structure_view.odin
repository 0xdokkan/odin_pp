package game

import "core:math"
import level "../level"

// HOW SEE-THROUGH A BUILDING IS (Fase 6 of docs/piano-griglia.md), from where the robot
// is. A pure function of the building's plan and the robot's position, so it is tested
// without a window; the renderers only draw what it says, and it changes no rule: the
// walls always stop the step and the sight.
//
//   far (5 cells or more from the building)   the building is whole
//   approaching                               more see-through the nearer the robot
//   on the threshold (a cell from a door)     the envelope is gone, the inside shows
//   inside (on a floor cell of the building)  the walls are whole again, the roof hidden
//   beside a wall with no door                never fainter than the minimum
//
// Positions are in cell coordinates: the cell (x, y) spans [x, x+1) by [y, y+1).

STRUCTURE_FADE_FAR :: f32(5)
// Within this distance of a door the envelope is gone, and it returns by STRUCTURE_DOOR_RAMP.
STRUCTURE_FADE_DOOR :: f32(1)
STRUCTURE_DOOR_RAMP :: f32(3)
STRUCTURE_FADE_MINIMUM :: f32(0.25)

Structure_Stage :: enum u8 { Far, Approaching, Threshold, Inside }

Structure_Visibility :: struct {
	stage:   Structure_Stage,
	// How whole the envelope (walls and roof) is drawn: 1 whole, 0 gone.
	opacity: f32,
	// The roof is drawn (it is hidden while the robot is inside).
	roof:    bool,
	// The robot is inside: everything outside the building is drawn darker.
	inside:  bool,
}

// How far the point (x, y) is from the cell (cell_x, cell_y)'s square.
@(private = "file")
distance_to_cell :: proc(x, y: f32, cell_x, cell_y: int) -> f32 {
	dx := max(f32(cell_x)-x, 0, x-f32(cell_x+1))
	dy := max(f32(cell_y)-y, 0, y-f32(cell_y+1))
	return math.sqrt(dx*dx+dy*dy)
}

@(private = "file")
smooth :: proc(t: f32) -> f32 {
	k := clamp(t, 0, 1)
	return k*k*(3-2*k)
}

structure_visibility :: proc(data: ^level.Level, index: int, robot: [2]f32) -> (view: Structure_Visibility) {
	view = {stage = .Far, opacity = 1, roof = true}
	if data == nil || index < 0 || index >= len(data.structures) { return }
	placed := data.structures[index]
	plan := &data.structure_plans[index]
	cell_x, cell_y := int(math.floor(robot.x)), int(math.floor(robot.y))
	here := level.plan_at(plan, cell_x-placed.origin.x, cell_y-placed.origin.y)
	if here == .Floor || here == .Use {
		return {stage = .Inside, opacity = 1, roof = false, inside = true}
	}
	wall_d, door_d := f32(1e9), f32(1e9)
	has_door := false
	for y in 0..<plan.height {
		for x in 0..<plan.width {
			cell := level.plan_at(plan, x, y)
			if cell == .Outside { continue }
			d := distance_to_cell(robot.x, robot.y, placed.origin.x+x, placed.origin.y+y)
			wall_d = min(wall_d, d)
			if cell == .Door { door_d = min(door_d, d); has_door = true }
		}
	}
	// A cell from a door, or on it: the envelope is gone.
	if has_door && door_d <= STRUCTURE_FADE_DOOR { return {stage = .Threshold, opacity = 0, roof = true} }
	if wall_d >= STRUCTURE_FADE_FAR { return }
	// Whole at five cells, the minimum beside a wall; and gone only near a door.
	fade := 1-(1-STRUCTURE_FADE_MINIMUM)*smooth((STRUCTURE_FADE_FAR-wall_d)/(STRUCTURE_FADE_FAR-1))
	gate := f32(1)
	if has_door { gate = smooth((door_d-STRUCTURE_FADE_DOOR)/(STRUCTURE_DOOR_RAMP-STRUCTURE_FADE_DOOR)) }
	return {stage = .Approaching, opacity = fade*gate, roof = true}
}
