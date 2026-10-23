package render

import rl "vendor:raylib"
import game "../game"
import grid "../engine/grid"
import level "../level"

// THE STRUCTURES IN THE LAB'S DIORAMA (Fase 6 of docs/piano-griglia.md). Each cell of a
// structure is an ordinary tile (a wall, a fence, a door, floor); this draws what stands
// on it. A building is in three parts: the envelope (walls, colonnade and roof, which
// fade as the robot comes near, structure_view.odin), the inside (the floor, always
// there) and the outline on the ground (always there). Complex objects are drawn whole.

STRUCTURE_FENCE_HEIGHT :: f32(0.5)

@(private)
structure_wall_height :: proc(id: level.Structure_Id, plan_cell: level.Plan_Cell) -> f32 {
	if plan_cell == .Fence {
		if id == .Fountain { return 0.42 }
		return STRUCTURE_FENCE_HEIGHT
	}
	switch id {
	case .Statue: return 0.55
	case .Machine: return 1.05
	case .Ruin: return 1.1
	case .Cottage, .Hut, .Temple: return DIORAMA_WALL_HEIGHT
	case .Cart, .Fountain, .Pen, .Count: return DIORAMA_WALL_HEIGHT
	}
	return DIORAMA_WALL_HEIGHT
}

// The first cell of the structure in row order: the one that draws its extras once.
@(private = "file")
first_cell :: proc(data: ^level.Level, index: int) -> grid.Position {
	placed := data.structures[index]
	plan := &data.structure_plans[index]
	for y in 0..<plan.height {
		for x in 0..<plan.width {
			if level.plan_at(plan, x, y) != .Outside { return {placed.origin.x+x, placed.origin.y+y} }
		}
	}
	return placed.origin
}

// The middle of the structure's footprint on the ground.
@(private = "file")
footprint_center :: proc(data: ^level.Level, index: int) -> rl.Vector3 {
	placed := data.structures[index]
	plan := &data.structure_plans[index]
	return {f32(placed.origin.x)+f32(plan.width)*0.5, 0, f32(placed.origin.y)+f32(plan.height)*0.5}
}

// What a structure adds to its cells, drawn once with the first one: a statue's figure,
// a fountain's water, a cart's wheels, a machine's lights.
@(private = "file")
draw_structure_extras :: proc(renderer: ^Renderer, data: ^level.Level, index: int, opacity: f32) {
	id := data.structures[index].id
	middle := footprint_center(data, index)
	tint := structure_tint(id)
	glow := structure_color_alpha(DIORAMA_GLOW, opacity)
	#partial switch id {
	case .Statue:
		draw_resin_cube(renderer, middle+rl.Vector3{0, 1.05, 0}, 0.42, 1.0, 0.42, structure_color_alpha(tint, opacity))
		draw_resin_cube(renderer, middle+rl.Vector3{0, 1.7, 0}, 0.34, 0.34, 0.34, structure_color_alpha(RESIN_CAP, opacity))
	case .Fountain:
		rl.DrawCube(middle+rl.Vector3{0, 0.22, 0}, 1.5, 0.05, 1.5, {70, 150, 200, u8(190*opacity)})
		rl.DrawCube(middle+rl.Vector3{0, 0.55, 0}, 0.16, 0.6, 0.16, structure_color_alpha(RESIN_CAP, opacity))
	case .Machine:
		for i in 0..<3 {
			rl.DrawCube(middle+rl.Vector3{(f32(i)-1)*0.8, 1.1, 0.42}, 0.2, 0.08, 0.05, glow)
		}
		rl.DrawCube(middle+rl.Vector3{0, 1.24, 0}, 0.5, 0.14, 0.5, structure_color_alpha(DIORAMA_EDGE, opacity))
	case .Cart:
		for side in ([2]f32{-1, 1}) {
			rl.DrawCube(middle+rl.Vector3{side*0.6, 0.22, 0.34}, 0.32, 0.32, 0.06, structure_color_alpha(RESIN_DARK, opacity))
			rl.DrawCube(middle+rl.Vector3{side*0.6, 0.22, -0.34}, 0.32, 0.32, 0.06, structure_color_alpha(RESIN_DARK, opacity))
		}
	case .Temple:
		// The altar's flame, in the middle of the courtyard.
		rl.DrawCube(middle+rl.Vector3{0, 0.9, 0}, 0.12, 0.28, 0.12, {240, 180, 90, u8(210*opacity)})
	}
}

// The body of one wall or fence cell of a structure, `opacity` of the way there.
@(private)
draw_structure_cell :: proc(renderer: ^Renderer, room: ^game.Room, cell: grid.Position, index: int) {
	data := room.level_data
	plan_cell := level.structure_plan_cell(data, index, cell)
	if plan_cell != .Wall && plan_cell != .Fence { return }
	id := data.structures[index].id
	opacity := structure_opacity(renderer, data, index)
	if opacity <= 0.02 { return }
	p := rl.Vector3{f32(cell.x)+0.5, 0, f32(cell.y)+0.5}
	h := structure_wall_height(id, plan_cell)
	body := structure_color_alpha(structure_tint(id), opacity)
	edge := structure_color_alpha(DIORAMA_EDGE, opacity)
	cap := structure_color_alpha(RESIN_CAP, opacity)
	if plan_cell == .Fence {
		// A low wall with a rail: the sight passes over it.
		draw_resin_cube(renderer, p+rl.Vector3{0, h*0.5, 0}, 0.78, h, 0.78, body)
		draw_resin_cube(renderer, p+rl.Vector3{0, h+0.04, 0}, 0.86, 0.08, 0.86, cap)
	} else {
		draw_resin_cube(renderer, p+rl.Vector3{0, h*0.5, 0}, 0.91, h, 0.91, body)
		draw_resin_cube(renderer, p+rl.Vector3{0, h-0.04, 0}, 0.97, 0.12, 0.97, edge)
		draw_resin_cube(renderer, p+rl.Vector3{0, h+0.065, 0}, 0.88, 0.11, 0.88, cap)
	}
	if cell == first_cell(data, index) { draw_structure_extras(renderer, data, index, opacity) }
}

// A building's roof: a slab over its whole footprint, with the envelope's opacity.
@(private)
draw_structure_roof :: proc(renderer: ^Renderer, room: ^game.Room, index: int) {
	data := room.level_data
	if index < 0 || index >= len(data.structures) { return }
	opacity := structure_opacity(renderer, data, index)
	if opacity <= 0.02 { return }
	placed := data.structures[index]
	plan := &data.structure_plans[index]
	id := placed.id
	color := structure_color_alpha(structure_tint(id), opacity)
	cap := structure_color_alpha(RESIN_CAP, opacity)
	h := DIORAMA_WALL_HEIGHT
	for y in 0..<plan.height {
		for x in 0..<plan.width {
			// A door is open to the sky: only the cells with a wall or a floor under them have a roof.
			cell := level.plan_at(plan, x, y)
			if cell == .Outside || cell == .Door { continue }
			p := rl.Vector3{f32(placed.origin.x+x)+0.5, h+0.12, f32(placed.origin.y+y)+0.5}
			draw_resin_cube(renderer, p, 1.0, 0.12, 1.0, color)
			rl.DrawCube(p+rl.Vector3{0, 0.07, 0}, 0.9, 0.02, 0.9, cap)
		}
	}
}

// The outline of every building on the ground, and a patch on each door: always there,
// even where the envelope is gone.
@(private)
draw_structure_outlines :: proc(renderer: ^Renderer, room: ^game.Room) {
	data := room.level_data
	if data == nil { return }
	for index in 0..<len(data.structures) {
		placed := data.structures[index]
		if !level.structure_is_building(placed.id) { continue }
		plan := &data.structure_plans[index]
		glow := rl.Color{98, 192, 229, 220}
		for y in 0..<plan.height {
			for x in 0..<plan.width {
				cell := level.plan_at(plan, x, y)
				if cell == .Outside { continue }
				if !tactical_cell_on_screen(renderer, {placed.origin.x+x, placed.origin.y+y}) { continue }
				x0, z0 := f32(placed.origin.x+x), f32(placed.origin.y+y)
				if cell == .Door { rl.DrawCube({x0+0.5, 0.025, z0+0.5}, 0.9, 0.02, 0.9, {98, 192, 229, 90}) }
				// A side facing outside the footprint is a side of the outline.
				for side in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
					if level.plan_at(plan, x+side.x, y+side.y) != .Outside { continue }
					a := rl.Vector3{x0+0.5+f32(side.x)*0.5-f32(side.y)*0.5, 0.04, z0+0.5+f32(side.y)*0.5-f32(side.x)*0.5}
					b := rl.Vector3{x0+0.5+f32(side.x)*0.5+f32(side.y)*0.5, 0.04, z0+0.5+f32(side.y)*0.5+f32(side.x)*0.5}
					rl.DrawLine3D(a, b, glow)
				}
			}
		}
	}
}

// The cells outside the structure the robot is inside are darker: a veil over the tile.
@(private)
structure_outside_dim :: proc(renderer: ^Renderer, room: ^game.Room, cell: grid.Position, tile: level.Tile) {
	views := &renderer.tactical.structures
	if views.inside < 0 || views.inside >= views.count { return }
	if owner, owned := level.structure_index_at(room.level_data, cell); owned && owner == views.inside { return }
	height := f32(0.14)
	if tile.kind == .Wall { height = DIORAMA_WALL_HEIGHT+0.2 }
	rl.DrawCube({f32(cell.x)+0.5, height*0.5-0.04, f32(cell.y)+0.5}, 1.0, height, 1.0, {4, 6, 14, 150})
}


// The envelope of each building that is not whole goes in the sorted pass with the actors:
// its walls and colonnade cell by cell, and its roof as one piece.
@(private)
collect_structure_entries :: proc(renderer: ^Renderer, room: ^game.Room, entries: ^[dynamic]Tactical_Alpha_Entry) {
	data := room.level_data
	views := &renderer.tactical.structures
	for index in 0..<min(len(data.structures), views.count) {
		if !level.structure_is_building(data.structures[index].id) { continue }
		opacity := views.opacity[index]
		if opacity <= 0.02 { continue }
		placed := data.structures[index]
		plan := &data.structure_plans[index]
		if opacity < 0.995 {
			for y in 0..<plan.height {
				for x in 0..<plan.width {
					cell := level.plan_at(plan, x, y)
					if cell != .Wall && cell != .Fence { continue }
					position := grid.Position{placed.origin.x+x, placed.origin.y+y}
					if tactical_cell_on_screen(renderer, position) && tactical_render_visible(renderer, position) {
						append(entries, Tactical_Alpha_Entry{kind = .Wall, position = {f32(position.x), f32(position.y)}})
					}
				}
			}
		}
		if views.roof[index] {
			middle := footprint_center(data, index)
			append(entries, Tactical_Alpha_Entry{kind = .Roof, attack = i32(index), position = {middle.x-0.5, middle.z-0.5}})
		}
	}
}
