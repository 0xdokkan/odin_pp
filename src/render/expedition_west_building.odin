package render

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import level "../level"

// The shared building transform and paint primitives map the actual Hut /
// Cottage plan. West owns its pitched silhouette and woodworking illustration.
// All furniture is paint against occupied walls; the existing roof visibility
// remains responsible for the complete removable gable.
WEST_BUILDING_WOOD :: rl.Color{190,128,70,255}
WEST_BUILDING_CAP :: rl.Color{235,187,111,255}
WEST_BUILDING_INK :: rl.Color{82,57,40,255}
WEST_BUILDING_PAINT :: rl.Color{66,107,97,255}
WEST_BUILDING_LIGHT :: rl.Color{230,213,165,255}
WEST_BUILDING_ROOF :: rl.Color{174,85,55,255}

@(private)
west_building_roof_y :: proc(frame:Cyber_Building_Frame,x:f32)->f32 {
	return DIORAMA_WALL_HEIGHT+.12+.85*(1-abs(x-frame.width*.5)/(frame.width*.5))
}

@(private)
draw_west_building_roof :: proc(pass:Ink_Pass,frame:Cyber_Building_Frame) {
	canonical:=frame.placed;canonical.rotation=0;canonical.mirror=false
	plan:=level.placed_plan(canonical)
	for z in 0..<plan.height {for x in 0..<plan.width {
		cell:=level.plan_at(&plan,x,z)
		if cell==.Outside || cell==.Door {continue}
		xs:=[3]f32{f32(x),f32(x)+.5,f32(x+1)}
		for part in 0..<2 {
			x0,x1:=xs[part],xs[part+1];z0,z1:=f32(z),f32(z+1)
			y0,y1:=west_building_roof_y(frame,x0),west_building_roof_y(frame,x1)
			uv:=[4]rl.Vector2{{8+x0/frame.width,z0/frame.depth},{8+x0/frame.width,z1/frame.depth},
				{8+x1/frame.width,z1/frame.depth},{8+x1/frame.width,z0/frame.depth}}
			fill:=WEST_BUILDING_ROOF if x0<frame.width*.5 else rl.Color{204,120,72,255}
			cyber_building_quad(pass,frame,{x0,y0,z0},{x0,y0,z1},{x1,y1,z1},{x1,y1,z0},fill,uv)
		}
		for direction in ([4][2]int{{1,0},{0,1},{-1,0},{0,-1}}) {
			next:=level.plan_at(&plan,x+direction.x,z+direction.y)
			if next!=.Outside && next!=.Door {continue}
			p:=rl.Vector3{f32(x)+.5,DIORAMA_WALL_HEIGHT,f32(z)+.5}
			t:=rl.Vector3{f32(direction.y)*.5,0,-f32(direction.x)*.5};o:=rl.Vector3{f32(direction.x)*.5,0,f32(direction.y)*.5}
			a,b:=p+o-t,p+o+t;mid:=(a+b)*.5
			for span in ([2][2]rl.Vector3{{a,mid},{mid,b}}) {
				at,bt:=span[0],span[1];at.y=west_building_roof_y(frame,at.x);bt.y=west_building_roof_y(frame,bt.x)
				cyber_building_quad(pass,frame,span[0],at,bt,span[1],WEST_BUILDING_PAINT)
			}
		}
	}}
	// Three broad shingle courses, drawn across each sloped face. They stop
	// before the door's row, so no decorative roof can close the real opening.
	for z:=f32(.65);z<frame.depth-1.12;z+=.73 {
		for span in ([2]rl.Vector2{{.16,frame.width*.5},{frame.width*.5,frame.width-.16}}) {
			y0,y1:=west_building_roof_y(frame,span.x)+.012,west_building_roof_y(frame,span.y)+.012
			cyber_building_quad(pass,frame,{span.x,y0,z},{span.x,y0,z+.035},{span.y,y1,z+.035},{span.y,y1,z},WEST_BUILDING_INK)
		}
	}
}

@(private)
west_building_stroke :: proc(pass:Ink_Pass,frame:Cyber_Building_Frame,plane:Cyber_Building_Print,a,b:rl.Vector2,width:f32,color:rl.Color,layer:f32=.003) {
	d:=rl.Vector2Normalize(b-a);n:=rl.Vector2{-d.y,d.x}*width*.5
	o:=plane.origin+rl.Vector3CrossProduct(plane.u,plane.v)*layer
	points:=[4]rl.Vector2{a-n,b-n,b+n,a+n}
	cyber_building_quad(pass,frame,o+plane.u*points[0].x+plane.v*points[0].y,o+plane.u*points[1].x+plane.v*points[1].y,
		o+plane.u*points[2].x+plane.v*points[2].y,o+plane.u*points[3].x+plane.v*points[3].y,color)
}

@(private)
draw_west_building_facade :: proc(pass:Ink_Pass,frame:Cyber_Building_Frame) {
	w,d:=frame.width,frame.depth
	front:=Cyber_Building_Print{{0,0,d+.012},{1,0,0},{0,1,0}}
	// A pair of timber jambs mark the real x=2 doorway. No lintel spans it.
	for x in ([2]f32{1.80,3.03}) {
		cyber_building_paint(pass,frame,front,{x,.04,.17,1.38},WEST_BUILDING_INK)
		cyber_building_paint(pass,frame,front,{x+.035,.08,.10,1.30},WEST_BUILDING_LIGHT,.003)
	}
	// Shop shutter with an offset crossbrace: plain painted timber, not a
	// screen or a relabelled Cyber service panel.
	cyber_building_paint(pass,frame,front,{.18,.28,1.36,1.00},WEST_BUILDING_INK)
	cyber_building_paint(pass,frame,front,{.23,.33,1.26,.90},WEST_BUILDING_PAINT,.003)
	for y in ([3]f32{.53,.76,.99}) {cyber_building_paint(pass,frame,front,{.27,y,1.18,.025},WEST_BUILDING_INK,.006)}
	west_building_stroke(pass,frame,front,{.32,.40},{1.36,1.14},.09,WEST_BUILDING_LIGHT,.009)
	// The broad side facade has a single large four-pane window plus planks.
	for side in 0..<2 {
		plane:=Cyber_Building_Print{{-.012,0,0},{0,0,1},{0,1,0}}
		if side==1 {plane={{w+.012,0,d},{0,0,-1},{0,1,0}}}
		for y in ([3]f32{.27,.69,1.11}) {cyber_building_paint(pass,frame,plane,{.09,y,d-.18,.025},WEST_BUILDING_INK)}
		cyber_building_paint(pass,frame,plane,{.65,.42,d-1.30,.88},WEST_BUILDING_INK,.003)
		cyber_building_paint(pass,frame,plane,{.72,.49,d-1.44,.74},WEST_BUILDING_LIGHT,.006)
		cyber_building_paint(pass,frame,plane,{.79,.56,d-1.58,.60},WEST_BUILDING_PAINT,.009)
		cyber_building_paint(pass,frame,plane,{d*.5-.035,.56,.07,.60},WEST_BUILDING_LIGHT,.012)
		cyber_building_paint(pass,frame,plane,{.79,.84,d-1.58,.06},WEST_BUILDING_LIGHT,.012)
	}
	// The rear is often the first facade seen from the workshop. Its broad
	// plank joints and two diagonal braces keep it readable from that side too.
	rear:=Cyber_Building_Print{{w,0,-.012},{-1,0,0},{0,1,0}}
	for y in ([3]f32{.30,.69,1.08}) {
		cyber_building_paint(pass,frame,rear,{.08,y,w-.16,.035},WEST_BUILDING_INK)
	}
	for x in ([2]f32{.16,w-.33}) {
		cyber_building_paint(pass,frame,rear,{x,.05,.17,1.31},WEST_BUILDING_INK,.003)
		cyber_building_paint(pass,frame,rear,{x+.045,.08,.08,1.25},WEST_BUILDING_CAP,.006)
	}
	for span in ([2]rl.Vector2{{.46,w*.5-.12},{w*.5+.12,w-.46}}) {
		west_building_stroke(pass,frame,rear,{span.x,.16},{span.y,1.21},.15,WEST_BUILDING_INK,.006)
		west_building_stroke(pass,frame,rear,{span.x,.20},{span.y,1.25},.075,WEST_BUILDING_CAP,.009)
		cyber_building_paint(pass,frame,rear,{span.x+.06,.80,.13,.055},WEST_BUILDING_INK,.003)
	}
}

@(private)
draw_west_building_interior :: proc(pass:Ink_Pass,frame:Cyber_Building_Frame) {
	w,d:=frame.width,frame.depth
	back:=Cyber_Building_Print{{0,0,1.012},{1,0,0},{0,1,0}}
	// A trestle bench, lower drawer and long saw are painted on the rear
	// wall. The only 3D volume remains the wall itself.
	cyber_building_paint(pass,frame,back,{1.10,.54,w-2.20,.17},WEST_BUILDING_INK)
	cyber_building_paint(pass,frame,back,{1.13,.59,w-2.26,.09},WEST_BUILDING_LIGHT,.003)
	for x in ([2]f32{1.23,w-1.39}) {
		west_building_stroke(pass,frame,back,{x+.07,.56},{x-.03,.10},.10,WEST_BUILDING_INK)
	}
	cyber_building_paint(pass,frame,back,{1.40,.25,w-2.80,.24},WEST_BUILDING_PAINT,.003)
	cyber_building_paint(pass,frame,back,{w*.5-.12,.38,.24,.035},WEST_BUILDING_LIGHT,.006)
	west_building_stroke(pass,frame,back,{1.28,1.04},{w-1.35,1.16},.16,WEST_BUILDING_INK)
	west_building_stroke(pass,frame,back,{1.34,1.07},{w-1.39,1.18},.085,WEST_BUILDING_LIGHT,.003)
	cyber_building_paint(pass,frame,back,{w-1.51,.94,.21,.33},WEST_BUILDING_WOOD,.006)
	for x:=f32(1.43);x<w-1.6;x+=.22 {
		cyber_building_paint(pass,frame,back,{x,.96,.075,.10},WEST_BUILDING_INK,.006)
	}
	// Tall stock and two shelves on the inner side: narrow enough for the
	// cottage, with more materials in the larger hut. No free cell is filled.
	left:=Cyber_Building_Print{{1.012,0,d-1},{0,0,-1},{0,1,0}}
	span:=d-2
	for y in ([2]f32{.23,.83}) {
		cyber_building_paint(pass,frame,left,{.07,y,span-.14,.075},WEST_BUILDING_INK)
		for x:=f32(.16);x<span-.21;x+=.31 {
			cyber_building_paint(pass,frame,left,{x,y+.075,.19,.30},WEST_BUILDING_CAP,.003)
			cyber_building_paint(pass,frame,left,{x+.03,y+.20,.13,.045},WEST_BUILDING_INK,.006)
		}
	}
	// The opposite wall carries a pegboard and two large hand tools. Every
	// quarter turn therefore exposes an inhabited wall, even when the bench
	// on the rear wall lies in the foreground and is occluded by its volume.
	right:=Cyber_Building_Print{{w-1.012,0,1},{0,0,1},{0,1,0}}
	cyber_building_paint(pass,frame,right,{.08,.38,span-.16,.93},WEST_BUILDING_INK)
	cyber_building_paint(pass,frame,right,{.12,.43,span-.24,.83},WEST_BUILDING_PAINT,.003)
	cyber_building_paint(pass,frame,right,{.15,1.10,span-.30,.065},WEST_BUILDING_LIGHT,.006)
	// Hammer: a thick timber handle and contrasting iron head.
	west_building_stroke(pass,frame,right,{.27,.55},{.30,1.04},.09,WEST_BUILDING_INK,.009)
	west_building_stroke(pass,frame,right,{.27,.57},{.30,1.04},.045,WEST_BUILDING_CAP,.012)
	cyber_building_paint(pass,frame,right,{.18,1.00,.28,.13},WEST_BUILDING_INK,.015)
	cyber_building_paint(pass,frame,right,{.19,1.055,.25,.055},WEST_BUILDING_LIGHT,.018)
	// A long saw beside it, with three strong teeth rather than fine texture.
	sx:=span-.33
	cyber_building_paint(pass,frame,right,{sx-.10,.50,.16,.54},WEST_BUILDING_INK,.009)
	cyber_building_paint(pass,frame,right,{sx-.065,.54,.10,.46},WEST_BUILDING_LIGHT,.012)
	for y in ([3]f32{.59,.74,.89}) {cyber_building_paint(pass,frame,right,{sx+.025,y,.075,.07},WEST_BUILDING_INK,.015)}
	cyber_building_paint(pass,frame,right,{sx-.13,1.04,.24,.15},WEST_BUILDING_CAP,.015)
	cyber_building_paint(pass,frame,right,{sx-.07,1.08,.12,.065},WEST_BUILDING_INK,.018)
	cyber_building_paint(pass,frame,right,{.08,.27,span-.16,.10},WEST_BUILDING_INK)
	cyber_building_paint(pass,frame,right,{.11,.31,span-.22,.045},WEST_BUILDING_CAP,.003)
	// Counterfacade: small stock and a hanging lantern on the solid panels
	// beside the actual x=2..3 door. Paint never crosses its opening.
	front:=Cyber_Building_Print{{w,0,d-1.012},{-1,0,0},{0,1,0}}
	stock_u:=w-1.87
	cyber_building_paint(pass,frame,front,{stock_u,.16,.72,1.10},WEST_BUILDING_INK)
	for x in ([3]f32{.045,.265,.485}) {
		cyber_building_paint(pass,frame,front,{stock_u+x,.21,.17,.99},WEST_BUILDING_CAP,.003)
		cyber_building_paint(pass,frame,front,{stock_u+x+.035,.28,.035,.55},WEST_BUILDING_WOOD,.006)
	}
	cyber_building_paint(pass,frame,front,{stock_u-.015,.43,.75,.10},WEST_BUILDING_PAINT,.009)
	cyber_building_paint(pass,frame,front,{stock_u-.015,.96,.75,.10},WEST_BUILDING_PAINT,.009)
	if w>4 {
		cyber_building_paint(pass,frame,front,{1.20,1.11,.56,.065},WEST_BUILDING_INK)
		cyber_building_paint(pass,frame,front,{1.43,.95,.07,.19},WEST_BUILDING_INK,.003)
		cyber_building_paint(pass,frame,front,{1.30,.49,.34,.50},WEST_BUILDING_INK,.006)
		cyber_building_paint(pass,frame,front,{1.35,.56,.24,.36},WEST_BUILDING_PAINT,.009)
		cyber_building_paint(pass,frame,front,{1.41,.61,.12,.24},WEST_BUILDING_LIGHT,.012)
		cyber_building_paint(pass,frame,front,{1.26,.48,.42,.075},WEST_BUILDING_CAP,.015)
	}
}

@(private)
draw_west_building_print :: proc(pass:Ink_Pass,placed:level.Placed_Structure,with_roof:bool) {
	if pass.mode!=.Fill && pass.mode!=.Bake {return}
	frame:=cyber_building_frame(placed)
	if pass.mode==.Fill {_=rlgl.CheckRenderBatchLimit(1800);rlgl.Begin(rlgl.TRIANGLES)}
	draw_west_building_facade(pass,frame)
	draw_west_building_interior(pass,frame)
	if with_roof {draw_west_building_roof(pass,frame)}
	if pass.mode==.Fill {rlgl.End()}
}
