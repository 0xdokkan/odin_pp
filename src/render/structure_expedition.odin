package render

import "core:math"
import campaign "../campaign"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import world "../expedition"
import game "../game"
import grid "../engine/grid"
import level "../level"

// THE STRUCTURES IN THE EXPEDITIONS (Fase 6 of docs/piano-griglia.md), in the ink the
// architecture is drawn in. Complex objects have one cached mesh per structure;
// standalone fences remain baked into the 8x8 blocks. A building's envelope (walls, colonnade and roof) is not baked: it is
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
	_, owned := level.structure_index_at(data, cell)
	if !owned {
		if kind != .Fence { return false }
		// A shortcut's gate has its own bars (lift_view.odin).
		if _, _, gate := level.gate_at(data, cell); gate { return true }
		draw_expedition_loose_fence(pass,data,cell,w.biome)
		return true
	}
	// Buildings own their dynamic envelope; objects own one immutable mesh.
	// Neither belongs in a cell chunk, including objects spanning its border.
	return true
}

// A building remains a volume. Its sheets omit hidden faces and join their
// print domain across cells, so the facade and roof read as one illustration.
@(private)
structure_print_cell :: proc(pass:Ink_Pass,plan:^level.Plan,x,y:int,p:rl.Vector3,height:f32,roof:bool,fill,cap:rl.Color,wall_print:bool=true) {
	directions:=[4][2]int{{1,0},{0,1},{-1,0},{0,-1}}
	joined:[4]bool
	current:=level.plan_at(plan,x,y)
	for d,i in directions {
		next:=level.plan_at(plan,x+d.x,y+d.y)
		joined[i]=next!=.Outside && next!=.Door if roof else next==current
	}
	if pass.mode!=.Fill && pass.mode!=.Bake {return}
	// Authored Cyber/West illustrations are registered to the original faces.
	// They receive only a low painted footing; generic masonry also steps
	// back above the footing, leaving a coping and convex corner posts.
	exterior:[4]bool;reach:[4]f32
	for d,i in directions {
		exterior[i]=!roof && level.plan_at(plan,x+d.x,y+d.y)==.Outside
		reach[i]=.465 if wall_print && exterior[i] else .5
	}
	foot:=min(WALL_FOOTING,height*.2)
	coping:=min(WALL_LIP_DEPTH,height*.2)
	body_top:=height-coping if !roof && wall_print else height
	foot_body,foot_cap:=ink_scale(fill,.72),ink_scale(cap,.85)
	if pass.mode==.Fill {_=rlgl.CheckRenderBatchLimit(192);rlgl.Begin(rlgl.TRIANGLES)}
	for d,i in directions {
		if joined[i] {continue}
		normal:=rl.Vector3{f32(d.x),0,f32(d.y)};tangent:=rl.Vector3{f32(d.y),0,-f32(d.x)}
		a,b:=p+normal*.5-tangent*.5,p+normal*.5+tangent*.5
		ends:=[2]bool{!joined[(i+1)%4],!joined[(i+3)%4]}
		if roof {
			ink_paper_face(pass,a,a+{0,height,0},b+{0,height,0},b,fill,ends,wall_print=wall_print)
			continue
		}
		if wall_print || exterior[i] {
			// The lowest course is a restrained contact shadow in the same
			// geometry, not a decal or a new ground rectangle.
			ink_paper_face(pass,a,a+{0,.025,0},b+{0,.025,0},b,ink_scale(fill,.54),ends)
			ink_paper_face(pass,a+{0,.025,0},a+{0,foot,0},b+{0,foot,0},b+{0,.025,0},foot_body,ends)
		}
		start:=foot if wall_print || exterior[i] else 0
		ba:=p+normal*reach[i]-tangent*reach[(i+1)%4]+{0,start,0}
		bb:=p+normal*reach[i]+tangent*reach[(i+3)%4]+{0,start,0}
		ink_paper_face(pass,ba,ba+{0,body_top-start,0},bb+{0,body_top-start,0},bb,fill,ends,wall_print=wall_print)
		if wall_print {
			ink_paper_face(pass,a+{0,body_top,0},a+{0,height,0},b+{0,height,0},b+{0,body_top,0},cap,ends)
		}
	}
	uv:=[4]rl.Vector2{{0 if !joined[2] else .5,0 if !joined[3] else .5},
		{0 if !joined[2] else .5,1 if !joined[1] else .5},
		{1 if !joined[0] else .5,1 if !joined[1] else .5},
		{1 if !joined[0] else .5,0 if !joined[3] else .5}}
	if !roof && wall_print {
		top:=p+rl.Vector3{0,foot,0}
		a,b,c,d:=top+rl.Vector3{-.5,0,-.5},top+rl.Vector3{-.5,0,.5},top+rl.Vector3{.5,0,.5},top+rl.Vector3{.5,0,-.5}
		ink_triangle(pass,a,b,c,foot_cap,{uv[0],uv[1],uv[2]});ink_triangle(pass,a,c,d,foot_cap,{uv[0],uv[2],uv[3]})
	}
	if roof {for &v in uv {v.x+=8}}
	top:=p+rl.Vector3{0,height,0}
	a,b,c,d:=top+rl.Vector3{-.5,0,-.5},top+rl.Vector3{-.5,0,.5},top+rl.Vector3{.5,0,.5},top+rl.Vector3{.5,0,-.5}
	ink_triangle(pass,a,b,c,cap,{uv[0],uv[1],uv[2]});ink_triangle(pass,a,c,d,cap,{uv[0],uv[2],uv[3]})
	if pass.mode==.Fill {rlgl.End()}
	if !roof && wall_print {
		// Only convex exterior corners: no posts at an inner wall or doorway.
		for sx in ([2]int{-1,1}) {for sz in ([2]int{-1,1}) {
			xside:=0 if sx>0 else 2;zside:=1 if sz>0 else 3
			if !exterior[xside] || !exterior[zside] {continue}
			ink_box(pass,p+{f32(sx)*.43,foot,f32(sz)*.43},{.069,.069},body_top-foot,0,foot_body,cap,{})
		}}
	}
}

@(private)
structure_print_palette :: proc(b:campaign.Biome)->(body,cap:rl.Color) {
	if m,ok:=ascent_material(b);ok {return m.body,m.cap}
	#partial switch b {
	case .Cyber:return CYBER_CAP,CYBER_CREAM
	case .West:return DESCENT_WOOD,DESCENT_WOOD_CAP
	case .Egypt:return DESCENT_SAND,DESCENT_SAND_CAP
	case .Inferno:return DESCENT_BASALT,DESCENT_BASALT_CAP
	case .Jungle:return {70,139,111,255},{181,206,124,255}
	case .Vietnam:return {83,121,72,255},{193,193,114,255}
	case .Gothic:return {107,100,145,255},{190,174,198,255}
	}
	return EXPEDITION_INK,EXPEDITION_INK_TOP
}

// One building's solids: its walls and colonnade, and its roof over everything but the door.
@(private)
draw_expedition_envelope_solids :: proc(pass: Ink_Pass, data: ^level.Level, index: int, with_roof: bool, biome:campaign.Biome) {
	placed := data.structures[index]
	plan := &data.structure_plans[index]
	body,cap:=structure_print_palette(biome)
	cyber_room:=biome==.Cyber && (placed.id==.Hut || placed.id==.Cottage)
	west_room:=biome==.West && (placed.id==.Hut || placed.id==.Cottage)
	if west_room {body,cap=WEST_BUILDING_WOOD,WEST_BUILDING_CAP}
	for y in 0..<plan.height {
		for x in 0..<plan.width {
			cell := level.plan_at(plan, x, y)
			p := rl.Vector3{f32(placed.origin.x+x)+0.5, 0, f32(placed.origin.y+y)+0.5}
			switch cell {
			case .Wall: structure_print_cell(pass,plan,x,y,p,DIORAMA_WALL_HEIGHT,false,body,cap,wall_print=!cyber_room && !west_room)
			case .Fence:
				joined:[4]bool
				for d,i in ([4][2]int{{1,0},{0,1},{-1,0},{0,-1}}) {
					next:=level.plan_at(plan,x+d.x,y+d.y);joined[i]=next==.Fence || next==.Wall
				}
				expedition_fence(pass,p,joined,body,cap)
			case .Floor, .Use, .Door, .Outside:
			}
			if with_roof && !cyber_room && !west_room && (cell == .Wall || cell == .Fence || cell == .Floor || cell == .Use) {
				structure_print_cell(pass,plan,x,y,{p.x,DIORAMA_WALL_HEIGHT,p.z},STRUCTURE_ROOF_THICKNESS,true,body,cap)
			}
		}
	}
	if cyber_room {draw_cyber_building_print(pass,placed,with_roof)}
	if west_room {draw_west_building_print(pass,placed,with_roof)}
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
		draw_expedition_envelope_solids(solid, data, index, views.roof[index],w.biome)
	}
	rlgl.DrawRenderBatchActive()
	whole := f32(1)
	rl.SetShaderValue(m.reveal_shader, m.reveal_envelope, &whole, .FLOAT)
	rl.EndShaderMode()
	// The edges and the outline.
	begin_expedition_edges(renderer)
	edges := Ink_Pass{mode = .Edge, edges = &m.edges}
	color := EXPEDITION_PAPER_INK
	for index in near[:count] {
		edges.lift = cell_ground(data.structures[index].origin)
		draw_expedition_structure_outline(edges, data, index, ink_edge(color, 0.9))
	}
	end_expedition_edges(renderer)
}

// The buildings near the robot for the sun's passes (expedition_sun.odin), with the program already bound: their walls
// always, their roofs only while shown (inside, the sun comes in where the roof was lifted off).
@(private)
draw_expedition_structure_casters :: proc(renderer: ^Renderer, room: ^game.Room, w: ^world.World) {
	data := room.level_data
	views := &renderer.tactical.structures
	if data == nil { return }
	solid := Ink_Pass{mode = .Fill}
	// Objects normally cast from their cached VBOs. If one upload failed,
	// the visible architecture uses the immediate path for all objects;
	// keep the same solids in both sun maps without camera-frustum culling.
	m := renderer.tactical.expedition_material
	if m == nil || !m.geometry.ready {
		for placed, index in data.structures {
			if level.structure_is_building(placed.id) || !expedition_structure_near(data, index, room.player.position) { continue }
			solid.lift = cell_ground(expedition_structure_anchor(data, index))
			draw_expedition_structure_object(solid, data, index, w.biome)
		}
	}
	if views.count == 0 { return }
	for index in 0..<min(len(data.structures), views.count) {
		placed := data.structures[index]
		if !level.structure_is_building(placed.id) || world.distance(placed.origin, room.player.position) > 36 { continue }
		solid.lift = cell_ground(placed.origin)
		draw_expedition_envelope_solids(solid, data, index, views.roof[index], w.biome)
	}
}
