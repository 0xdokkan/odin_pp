package render

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import world "../expedition"
import game "../game"
import grid "../engine/grid"
import level "../level"

// THE STRUCTURES IN THE EXPEDITIONS (Fase 6 of docs/piano-griglia.md), in the ink the
// architecture is drawn in. Complex objects and fences are solids like the props, baked into
// the 8x8 blocks. A building's envelope (walls, colonnade and roof) is not baked: it is
// drawn every frame through the reveal program with the building's opacity, which dithers it
// away (an ordered stipple, no blending, no sorting), and its edges fade with it. The outline
// on the ground stays. While the robot is inside, everything outside the building is darker.

STRUCTURE_ROOF_THICKNESS :: f32(0.14)
STRUCTURE_INSIDE_DIM :: f32(0.5)

// How dark the outside is while the robot is in a building: eased in and out, with the
// footprint it applies to kept while it fades.
@(private)
update_structure_dim :: proc(renderer: ^Renderer, m: ^Expedition_Material) {
	views := &renderer.tactical.structures
	target := f32(0)
	if views.inside >= 0 && views.inside < views.count {
		target = STRUCTURE_INSIDE_DIM
	}
	if target > 0 {
		if room := renderer.tactical.structure_room_data; room != nil { m.dim_box = structure_footprint_box(room, views.inside) }
	} else if renderer.tactical.expedition_in_cave {
		// In a cave, as in a building: everything outside it is darker (Fase 4's rule, game.layer_cell_dim).
		target = game.LAYER_OUTSIDE_DIM
		m.dim_box = renderer.tactical.expedition_cave_box
	}
	dt := expedition_frame_dt(renderer)
	m.dim_amount += (target-m.dim_amount)*(1-math.exp(-6*dt))
	if m.dim_amount < 0.01 && target == 0 { m.dim_amount = 0 }
}

// The footprint (x0, z0, x1, z1) of a structure, for the dimming.
@(private)
structure_footprint_box :: proc(data: ^level.Level, index: int) -> rl.Vector4 {
	placed := data.structures[index]
	plan := &data.structure_plans[index]
	return {f32(placed.origin.x), f32(placed.origin.y), f32(placed.origin.x+plan.width), f32(placed.origin.y+plan.height)}
}

// A cell that is a structure's wall or fence, or a fence of its own: false if it is neither of those (the
// caller draws a wall as before). True when it was drawn here, or is left to the envelope pass.
@(private)
draw_expedition_structure_solid :: proc(pass: Ink_Pass, room: ^game.Room, w: ^world.World, cell: grid.Position, kind: level.Tile_Kind) -> bool {
	data := room.level_data
	index, owned := level.structure_index_at(data, cell)
	c := expedition_color(w.biome)
	p := rl.Vector3{f32(cell.x)+0.5, 0, f32(cell.y)+0.5}
	if !owned {
		if kind != .Fence { return false }
		ink_box(pass, p, {0.44, 0.44}, STRUCTURE_FENCE_HEIGHT, 0, EXPEDITION_INK, EXPEDITION_INK_TOP, ink_edge(c))
		return true
	}
	// A building's envelope is drawn by its own pass, with its opacity.
	if level.structure_is_building(data.structures[index].id) { return true }
	plan_cell := level.structure_plan_cell(data, index, cell)
	h := structure_wall_height(data.structures[index].id, plan_cell)
	half := rl.Vector2{0.44, 0.44} if plan_cell == .Fence else rl.Vector2{0.5, 0.5}
	ink_box(pass, p, half, h, 0, EXPEDITION_INK, EXPEDITION_INK_TOP, ink_edge(c))
	return true
}

// One building's solids: its walls and colonnade, and its roof over everything but the door.
@(private = "file")
draw_expedition_envelope_solids :: proc(pass: Ink_Pass, data: ^level.Level, index: int, with_roof: bool) {
	placed := data.structures[index]
	plan := &data.structure_plans[index]
	for y in 0..<plan.height {
		for x in 0..<plan.width {
			cell := level.plan_at(plan, x, y)
			p := rl.Vector3{f32(placed.origin.x+x)+0.5, 0, f32(placed.origin.y+y)+0.5}
			switch cell {
			case .Wall: ink_box(pass, p, {0.5, 0.5}, DIORAMA_WALL_HEIGHT, 0, EXPEDITION_INK, EXPEDITION_INK_TOP, {})
			case .Fence: ink_box(pass, p, {0.44, 0.44}, STRUCTURE_FENCE_HEIGHT, 0, EXPEDITION_INK, EXPEDITION_INK_TOP, {})
			case .Floor, .Use, .Door, .Outside:
			}
			if with_roof && (cell == .Wall || cell == .Fence || cell == .Floor || cell == .Use) {
				ink_box(pass, {p.x, DIORAMA_WALL_HEIGHT, p.z}, {0.5, 0.5}, STRUCTURE_ROOF_THICKNESS, 0, EXPEDITION_INK_TOP, EXPEDITION_INK_TOP, {})
			}
		}
	}
}

// The edges of a structure: the sides of a wall or fence that face open ground, along the top and the foot
// and up the corners, and the roof's outline. `opacity` fades them with the envelope.
@(private = "file")
draw_expedition_envelope_edges :: proc(pass: Ink_Pass, data: ^level.Level, index: int, color: rl.Color, with_roof: bool) {
	placed := data.structures[index]
	plan := &data.structure_plans[index]
	for y in 0..<plan.height {
		for x in 0..<plan.width {
			cell := level.plan_at(plan, x, y)
			if cell != .Wall && cell != .Fence { continue }
			top := DIORAMA_WALL_HEIGHT if cell == .Wall else STRUCTURE_FENCE_HEIGHT
			x0, z0 := f32(placed.origin.x+x), f32(placed.origin.y+y)
			for side in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
				joined := level.plan_at(plan, x+side.x, y+side.y) == cell
				if joined { continue }
				// The side's two ends.
				a := rl.Vector3{x0+0.5+f32(side.x)*0.5-f32(side.y)*0.5, 0, z0+0.5+f32(side.y)*0.5-f32(side.x)*0.5}
				b := rl.Vector3{x0+0.5+f32(side.x)*0.5+f32(side.y)*0.5, 0, z0+0.5+f32(side.y)*0.5+f32(side.x)*0.5}
				ink_line(pass, a+{0, top, 0}, b+{0, top, 0}, color)
				ink_line(pass, a, b, color)
				ink_line(pass, a, a+{0, top, 0}, color)
				ink_line(pass, b, b+{0, top, 0}, color)
			}
		}
	}
	if !with_roof { return }
	roof := DIORAMA_WALL_HEIGHT+STRUCTURE_ROOF_THICKNESS
	for y in 0..<plan.height {
		for x in 0..<plan.width {
			cell := level.plan_at(plan, x, y)
			if cell == .Outside || cell == .Door { continue }
			x0, z0 := f32(placed.origin.x+x), f32(placed.origin.y+y)
			for side in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
				next := level.plan_at(plan, x+side.x, y+side.y)
				if next != .Outside && next != .Door { continue }
				a := rl.Vector3{x0+0.5+f32(side.x)*0.5-f32(side.y)*0.5, roof, z0+0.5+f32(side.y)*0.5-f32(side.x)*0.5}
				b := rl.Vector3{x0+0.5+f32(side.x)*0.5+f32(side.y)*0.5, roof, z0+0.5+f32(side.y)*0.5+f32(side.x)*0.5}
				ink_line(pass, a, b, color)
			}
		}
	}
}

// The outline on the ground and the door's patch: always drawn, at full strength.
@(private = "file")
draw_expedition_structure_outline :: proc(pass: Ink_Pass, data: ^level.Level, index: int, color: rl.Color) {
	placed := data.structures[index]
	plan := &data.structure_plans[index]
	for y in 0..<plan.height {
		for x in 0..<plan.width {
			cell := level.plan_at(plan, x, y)
			if cell == .Outside { continue }
			x0, z0 := f32(placed.origin.x+x), f32(placed.origin.y+y)
			for side in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
				if level.plan_at(plan, x+side.x, y+side.y) != .Outside { continue }
				a := rl.Vector3{x0+0.5+f32(side.x)*0.5-f32(side.y)*0.5, 0.04, z0+0.5+f32(side.y)*0.5-f32(side.x)*0.5}
				b := rl.Vector3{x0+0.5+f32(side.x)*0.5+f32(side.y)*0.5, 0.04, z0+0.5+f32(side.y)*0.5+f32(side.x)*0.5}
				ink_line(pass, a, b, color)
			}
			if cell == .Door {
				// A cross on the door's cell.
				ink_line(pass, {x0+0.15, 0.04, z0+0.15}, {x0+0.85, 0.04, z0+0.85}, color)
				ink_line(pass, {x0+0.85, 0.04, z0+0.15}, {x0+0.15, 0.04, z0+0.85}, color)
			}
		}
	}
}

// Draws every building's envelope this frame, dithered by its opacity, then the edges and the ground
// outline. Not in the reflection pass.
@(private)
draw_expedition_structure_envelopes :: proc(renderer: ^Renderer, room: ^game.Room, w: ^world.World) {
	m := renderer.tactical.expedition_material
	data := room.level_data
	views := &renderer.tactical.structures
	if m == nil || m.reflection_pass || data == nil || views.count == 0 { return }
	near: [level.MAX_STRUCTURES_PER_LEVEL]int
	count := 0
	for index in 0..<min(len(data.structures), views.count) {
		placed := data.structures[index]
		if !level.structure_is_building(placed.id) || world.distance(placed.origin, room.player.position) > 36 { continue }
		near[count] = index
		count += 1
	}
	if count == 0 { return }
	// The solids, one building at a time so that each has its own opacity.
	begin_expedition_material(renderer, w, reveal = true)
	solid := Ink_Pass{mode = .Fill}
	for index in near[:count] {
		opacity := views.opacity[index]
		if opacity <= 0.02 { continue }
		rlgl.DrawRenderBatchActive()
		rl.SetShaderValue(m.reveal_shader, m.reveal_envelope, &opacity, .FLOAT)
		solid.lift = cell_ground(data.structures[index].origin)
		draw_expedition_envelope_solids(solid, data, index, views.roof[index])
	}
	rlgl.DrawRenderBatchActive()
	whole := f32(1)
	rl.SetShaderValue(m.reveal_shader, m.reveal_envelope, &whole, .FLOAT)
	rl.EndShaderMode()
	// The edges and the outline.
	begin_expedition_edges(renderer)
	edges := Ink_Pass{mode = .Edge, edges = &m.edges}
	color := expedition_color(w.biome)
	for index in near[:count] {
		opacity := views.opacity[index]
		edges.lift = cell_ground(data.structures[index].origin)
		if opacity > 0.05 {
			faded := ink_edge(color)
			faded.a = u8(clamp(f32(EXPEDITION_EDGE_ALPHA)*opacity, 1, f32(EXPEDITION_EDGE_ALPHA)))
			draw_expedition_envelope_edges(edges, data, index, faded, views.roof[index])
		}
		draw_expedition_structure_outline(edges, data, index, ink_edge(color, 0.9))
	}
	end_expedition_edges(renderer)
}
