package render

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import level "../level"

// Cyber shelters are still traversable wall volumes. Their furniture is an
// illustration registered to the real inner wall, not a solid in a free cell.
// A single canonical composition follows the plan's mirror and quarter turns.
// No textures, dynamic arrays or cosmetic clocks are required by this pass.
Cyber_Building_Frame :: struct {
	placed: level.Placed_Structure,
	width, depth: f32,
}

CYBER_BUILDING_PRINT_OFFSET :: f32(.012)
CYBER_BUILDING_ROOF_RISE :: f32(.44)

@(private)
cyber_building_frame :: proc(placed:level.Placed_Structure)->Cyber_Building_Frame {
	definition:=level.structure_definition(placed.id)
	return {placed,f32(len(definition.rows[0])),f32(len(definition.rows))}
}

@(private)
cyber_building_point :: proc(frame:Cyber_Building_Frame,p:rl.Vector3)->rl.Vector3 {
	x,z:=p.x,p.z
	if frame.placed.mirror {x=frame.width-x}
	switch frame.placed.rotation%4 {
	case 1:x,z=frame.depth-z,x
	case 2:x,z=frame.width-x,frame.depth-z
	case 3:x,z=z,frame.width-x
	}
	return {f32(frame.placed.origin.x)+x,p.y,f32(frame.placed.origin.y)+z}
}

@(private)
cyber_building_triangle :: proc(pass:Ink_Pass,frame:Cyber_Building_Frame,a,b,c:rl.Vector3,color:rl.Color,uv:[3]rl.Vector2={{2,2},{2,2},{2,2}}) {
	pa,pb,pc:=cyber_building_point(frame,a),cyber_building_point(frame,b),cyber_building_point(frame,c)
	if frame.placed.mirror {ink_triangle(pass,pa,pc,pb,color,{uv[0],uv[2],uv[1]})}
	else {ink_triangle(pass,pa,pb,pc,color,uv)}
}

@(private)
cyber_building_quad :: proc(pass:Ink_Pass,frame:Cyber_Building_Frame,a,b,c,d:rl.Vector3,color:rl.Color,uv:[4]rl.Vector2={{2,2},{2,2},{2,2},{2,2}}) {
	cyber_building_triangle(pass,frame,a,b,c,color,{uv[0],uv[1],uv[2]})
	cyber_building_triangle(pass,frame,a,c,d,color,{uv[0],uv[2],uv[3]})
}

// The print plane's axes are chosen so u cross v points out of the wall.
// Tiny paint layers stay within 0.02 cells of that face, never at the middle
// of a walkable tile. The strongest outlines belong to the whole composition.
Cyber_Building_Print :: struct {origin,u,v:rl.Vector3}

@(private)
cyber_building_paint :: proc(pass:Ink_Pass,frame:Cyber_Building_Frame,plane:Cyber_Building_Print,box:rl.Rectangle,color:rl.Color,layer:f32=0) {
	n:=rl.Vector3CrossProduct(plane.u,plane.v)
	o:=plane.origin+n*layer
	a:=o+plane.u*box.x+plane.v*box.y
	b:=a+plane.u*box.width;c:=b+plane.v*box.height;d:=a+plane.v*box.height
	cyber_building_quad(pass,frame,a,b,c,d,color)
}

// An eight-corner pixel plate. The stepped corners are part of the outline,
// with broad ivory then dark printed fields rather than nested 3D trim boxes.
@(private)
cyber_building_plate :: proc(pass:Ink_Pass,frame:Cyber_Building_Frame,plane:Cyber_Building_Print,box:rl.Rectangle,color:rl.Color,layer:f32=0) {
	k:=f32(.08)
	points:=[8]rl.Vector2{{box.x+k,box.y},{box.x+box.width-k,box.y},{box.x+box.width,box.y+k},
		{box.x+box.width,box.y+box.height-k},{box.x+box.width-k,box.y+box.height},
		{box.x+k,box.y+box.height},{box.x,box.y+box.height-k},{box.x,box.y+k}}
	n:=rl.Vector3CrossProduct(plane.u,plane.v);o:=plane.origin+n*layer
	for i in 1..<7 {
		cyber_building_triangle(pass,frame,o+plane.u*points[0].x+plane.v*points[0].y,
			o+plane.u*points[i].x+plane.v*points[i].y,o+plane.u*points[i+1].x+plane.v*points[i+1].y,color)
	}
}

@(private)
cyber_building_roof_y :: proc(frame:Cyber_Building_Frame,x:f32)->f32 {
	return DIORAMA_WALL_HEIGHT+STRUCTURE_ROOF_THICKNESS+CYBER_BUILDING_ROOF_RISE*clamp(min(x,frame.width-x)/.5,0,1)
}

// Folded shoulders belong to the roof and vanish with it. The opening above
// the actual Door cell is retained: the entrance is never capped by a fake
// wall, lintel or a slab projecting outside the original occupied footprint.
@(private)
draw_cyber_building_roof :: proc(pass:Ink_Pass,frame:Cyber_Building_Frame) {
	canonical:=frame.placed;canonical.rotation=0;canonical.mirror=false
	plan:=level.placed_plan(canonical)
	for z in 0..<plan.height {for x in 0..<plan.width {
		cell:=level.plan_at(&plan,x,z)
		if cell==.Outside || cell==.Door {continue}
		xs:=[3]f32{f32(x),f32(x)+.5,f32(x+1)}
		// Splitting at the half-cell shoulder is exact; adjacent roof cells
		// share vertices and UVs so the roof has no visible cell grid.
		for part in 0..<2 {
			x0,x1:=xs[part],xs[part+1];z0,z1:=f32(z),f32(z+1)
			y0,y1:=cyber_building_roof_y(frame,x0),cyber_building_roof_y(frame,x1)
			uv:=[4]rl.Vector2{{8+x0/frame.width,z0/frame.depth},{8+x0/frame.width,z1/frame.depth},
				{8+x1/frame.width,z1/frame.depth},{8+x1/frame.width,z0/frame.depth}}
			cyber_building_quad(pass,frame,{x0,y0,z0},{x0,y0,z1},{x1,y1,z1},{x1,y1,z0},CYBER_CREAM,uv)
		}
		for direction in ([4][2]int{{1,0},{0,1},{-1,0},{0,-1}}) {
			next:=level.plan_at(&plan,x+direction.x,z+direction.y)
			if next!=.Outside && next!=.Door {continue}
			// Bottom-to-top winding is the same as the wall's exposed face.
			p:=rl.Vector3{f32(x)+.5,DIORAMA_WALL_HEIGHT,f32(z)+.5}
			t:=rl.Vector3{f32(direction.y)*.5,0,-f32(direction.x)*.5}
			o:=rl.Vector3{f32(direction.x)*.5,0,f32(direction.y)*.5}
			a,b:=p+o-t,p+o+t
			mid:=(a+b)*.5
			for span in ([2][2]rl.Vector3{{a,mid},{mid,b}}) {
				at,bt:=span[0],span[1];at.y=cyber_building_roof_y(frame,at.x);bt.y=cyber_building_roof_y(frame,bt.x)
				u0:=span[0].z/frame.depth if direction.x!=0 else span[0].x/frame.width
				u1:=span[1].z/frame.depth if direction.x!=0 else span[1].x/frame.width
				cyber_building_quad(pass,frame,span[0],at,bt,span[1],CYBER_BODY,{{u0,0},{u0,1},{u1,1},{u1,0}})
			}
		}
	}}
	// One service strip and two broad radiator slots read at the normal camera.
	// Flat print on the upper plane, not an extra obstacle or stacked roof.
	y:=cyber_building_roof_y(frame,frame.width*.5)+CYBER_BUILDING_PRINT_OFFSET
	roof:=Cyber_Building_Print{{0,y,frame.depth},{1,0,0},{0,0,-1}}
	cyber_building_paint(pass,frame,roof,{.72,frame.depth-.55,frame.width-1.44,.16},CYBER_RECESS)
	cyber_building_paint(pass,frame,roof,{.85,frame.depth-.51,frame.width-1.70,.05},CYBER_YELLOW,.003)
	for z in ([2]f32{1.35,1.65}) {
		cyber_building_plate(pass,frame,roof,{1.0,z,frame.width-2,.20},CYBER_RECESS)
		cyber_building_paint(pass,frame,roof,{1.13,z+.07,frame.width-2.26,.06},CYBER_METAL,.003)
	}
}

@(private)
draw_cyber_building_facade :: proc(pass:Ink_Pass,frame:Cyber_Building_Frame) {
	width,depth:=frame.width,frame.depth
	front:=Cyber_Building_Print{{0,0,depth+CYBER_BUILDING_PRINT_OFFSET},{1,0,0},{0,1,0}}
	// Both plans have their door at canonical x=2. The markings sit wholly
	// on the two neighbouring wall cells, leaving that opening visibly clear.
	for x in ([2]f32{1.80,3.04}) {
		cyber_building_paint(pass,frame,front,{x,.12,.16,1.29},CYBER_RECESS)
		cyber_building_paint(pass,frame,front,{x+.035,.20,.09,1.12},CYBER_YELLOW,.003)
		for y in ([3]f32{.40,.73,1.06}) {cyber_building_paint(pass,frame,front,{x+.035,y,.09,.05},CYBER_RECESS,.006)}
	}
	// The left facade houses a service hatch and a distinct cyan readout.
	cyber_building_plate(pass,frame,front,{.20,.17,1.35,1.16},CYBER_RECESS)
	cyber_building_plate(pass,frame,front,{.26,.23,1.23,1.04},CYBER_CREAM,.003)
	cyber_building_paint(pass,frame,front,{.38,.67,.99,.43},CYBER_RECESS,.006)
	cyber_building_paint(pass,frame,front,{.46,.75,.83,.27},CYBER_SCREEN,.009)
	cyber_building_paint(pass,frame,front,{.51,.82,.30,.07},CYBER_CREAM,.012)
	cyber_building_paint(pass,frame,front,{.45,.38,.51,.10},CYBER_BODY,.006)
	cyber_building_paint(pass,frame,front,{1.13,.36,.10,.15},CYBER_RED_FACE,.006)
	// Broad side windows are drawn as one bay on each facade, not per cell.
	for side in 0..<2 {
		plane:=Cyber_Building_Print{{-CYBER_BUILDING_PRINT_OFFSET,0,0},{0,0,1},{0,1,0}}
		if side==1 {plane={{width+CYBER_BUILDING_PRINT_OFFSET,0,depth},{0,0,-1},{0,1,0}}}
		cyber_building_plate(pass,frame,plane,{.65,.52,depth-1.30,.77},CYBER_RECESS)
		cyber_building_plate(pass,frame,plane,{.72,.59,depth-1.44,.63},CYBER_CREAM,.003)
		cyber_building_paint(pass,frame,plane,{.83,.69,depth-1.66,.43},CYBER_BODY,.006)
		cyber_building_paint(pass,frame,plane,{1.0,.90,.38,.09},CYBER_SCREEN,.009)
		cyber_building_paint(pass,frame,plane,{1.14,.99,.38,.05},CYBER_SCREEN,.009)
		cyber_building_paint(pass,frame,plane,{.83,.28,depth-1.66,.10},CYBER_RECESS)
	}
}

@(private)
draw_cyber_building_interior :: proc(pass:Ink_Pass,frame:Cyber_Building_Frame) {
	width,depth:=frame.width,frame.depth
	back:=Cyber_Building_Print{{0,0,1+CYBER_BUILDING_PRINT_OFFSET},{1,0,0},{0,1,0}}
	// A workbench printed directly on the back wall, with a continuous top,
	// drawers, monitor and a clear free lane from the real door into the room.
	cyber_building_plate(pass,frame,back,{1.10,.12,width-2.20,1.30},CYBER_RECESS)
	cyber_building_paint(pass,frame,back,{1.18,.20,width-2.36,.42},CYBER_BODY,.003)
	cyber_building_paint(pass,frame,back,{1.15,.64,width-2.30,.12},CYBER_CREAM,.003)
	cyber_building_paint(pass,frame,back,{1.30,.85,.97,.47},CYBER_CREAM,.003)
	cyber_building_paint(pass,frame,back,{1.37,.92,.83,.33},CYBER_SCREEN,.006)
	cyber_building_paint(pass,frame,back,{1.48,1.02,.46,.06},CYBER_RECESS,.009)
	cyber_building_paint(pass,frame,back,{1.48,1.12,.27,.05},CYBER_RECESS,.009)
	cyber_building_paint(pass,frame,back,{1.70,.76,.18,.09},CYBER_CREAM,.003)
	for x:=f32(1.32);x<width-1.38;x+=.60 {
		cyber_building_paint(pass,frame,back,{x,.28,.39,.22},CYBER_RECESS,.006)
		cyber_building_paint(pass,frame,back,{x+.11,.41,.17,.04},CYBER_CREAM,.009)
	}
	// Tools occupy the right inner face rather than crowding the monitor.
	// The compact cottage receives two; the hut keeps its three existing tools.
	right:=Cyber_Building_Print{{width-1-CYBER_BUILDING_PRINT_OFFSET,0,1},{0,0,1},{0,1,0}}
	cyber_building_plate(pass,frame,right,{.10,.72,depth-2.20,.64},CYBER_RECESS)
	for i in 0..<(3 if width>4 else 2) {
		x:=f32(.22)+f32(i)*.30
		cyber_building_paint(pass,frame,right,{x,.90,.07,.23},CYBER_CREAM,.003)
		cyber_building_paint(pass,frame,right,{x-.055,1.10,.18,.06},CYBER_CREAM,.003)
		cyber_building_paint(pass,frame,right,{x-.015,.80,.10,.15},CYBER_YELLOW if i==1 else CYBER_BODY,.006)
	}
	// A shallow service locker belongs to the inner wall beside the real
	// doorway, opposite the bench. It cannot narrow the entrance or corridor.
	front:=Cyber_Building_Print{{width,0,depth-1-CYBER_BUILDING_PRINT_OFFSET},{-1,0,0},{0,1,0}}
	cyber_building_plate(pass,frame,front,{width-1.88,.20,.76,.96},CYBER_RECESS)
	cyber_building_paint(pass,frame,front,{width-1.81,.27,.62,.82},CYBER_BODY,.003)
	cyber_building_paint(pass,frame,front,{width-1.39,.54,.06,.22},CYBER_CREAM,.006)
	cyber_building_paint(pass,frame,front,{width-1.72,.94,.25,.05},CYBER_CREAM,.006)
	// Storage is on the left inner face. Its depth is paint; no geometry
	// extends into the corridor or the door's cell.
	left:=Cyber_Building_Print{{1+CYBER_BUILDING_PRINT_OFFSET,0,depth-1},{0,0,-1},{0,1,0}}
	span:=depth-2.18
	cyber_building_plate(pass,frame,left,{.09,.18,span,1.13},CYBER_RECESS)
	for y,row in ([2]f32{.30,.78}) {
		cyber_building_paint(pass,frame,left,{.16,y,span-.14,.08},CYBER_CREAM,.003)
		for x:=f32(.23);x<span-.16;x+=.42 {
			cyber_building_paint(pass,frame,left,{x,y+.08,.27,.28},CYBER_YELLOW if row==0 else CYBER_BODY,.003)
			cyber_building_paint(pass,frame,left,{x+.055,y+.19,.16,.04},CYBER_RECESS,.006)
		}
	}
	// Only a few painted route dashes lie on the existing floor. No plinth,
	// carpet rectangle, floor height change or apparent new obstruction.
	floor:=Cyber_Building_Print{{0,.018,depth-1},{1,0,0},{0,0,-1}}
	for z:=f32(.16);z<depth-2.2;z+=.65 {
		cyber_building_paint(pass,frame,floor,{2.13,z,.09,.23},CYBER_BODY)
		cyber_building_paint(pass,frame,floor,{2.78,z,.09,.23},CYBER_BODY)
	}
}

@(private)
draw_cyber_building_print :: proc(pass:Ink_Pass,placed:level.Placed_Structure,with_roof:bool) {
	if pass.mode!=.Fill && pass.mode!=.Bake {return}
	frame:=cyber_building_frame(placed)
	if pass.mode==.Fill {_=rlgl.CheckRenderBatchLimit(1800);rlgl.Begin(rlgl.TRIANGLES)}
	draw_cyber_building_facade(pass,frame)
	draw_cyber_building_interior(pass,frame)
	if with_roof {draw_cyber_building_roof(pass,frame)}
	if pass.mode==.Fill {rlgl.End()}
}
