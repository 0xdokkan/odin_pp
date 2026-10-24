package render

import "core:math"
import rl "vendor:raylib"
import world "../expedition"
import game "../game"
import grid "../engine/grid"
import level "../level"

// Industrial modules are static, allocation-free geometry. Their only light
// sources are explicit seams and indicators; a chamfer is shaded metal, not
// another glowing outline. Every primitive follows Ink_Pass (including Bake).
CYBER_BODY :: rl.Color{22,23,27,255}
CYBER_CAP :: rl.Color{31,33,38,255}
CYBER_METAL :: rl.Color{45,47,52,255}
CYBER_RECESS :: rl.Color{8,9,12,255}
CYBER_RED :: rl.Color{242,22,30,254}
CYBER_RED_FACE :: rl.Color{105,12,18,255}
CYBER_SCREEN :: rl.Color{42,167,216,255}

@(private)
cyber_point :: proc(base,local:rl.Vector3,yaw:f32)->rl.Vector3 {
	cs,sn:=math.cos(yaw),math.sin(yaw)
	return base+{local.x*cs-local.z*sn,local.y,local.x*sn+local.z*cs}
}

@(private)
cyber_chamfer_ring :: proc(base:rl.Vector3,half:rl.Vector2,cut,yaw:f32)->(ring:[8]rl.Vector3) {
	b:=clamp(cut,0,min(half.x,half.y)*.8)
	q:=[8]rl.Vector2{{-half.x+b,-half.y},{half.x-b,-half.y},{half.x,-half.y+b},{half.x,half.y-b},
		{half.x-b,half.y},{-half.x+b,half.y},{-half.x,half.y-b},{-half.x,-half.y+b}}
	for p,i in q {ring[i]=cyber_point(base,{p.x,0,p.y},yaw)}
	return
}

// A broad flat cap, a bevel catching the key light, and a dark vertical body.
@(private)
cyber_case :: proc(pass:Ink_Pass,base:rl.Vector3,half:rl.Vector2,height,yaw:f32,fill:rl.Color=CYBER_BODY,cap:rl.Color=CYBER_CAP) {
	bevel:=min(f32(.065),min(height*.2,min(half.x,half.y)*.24))
	a:=cyber_chamfer_ring(base,half,bevel*1.4,yaw)
	b:=cyber_chamfer_ring(base+{0,height-bevel,0},half,bevel*1.4,yaw)
	c:=cyber_chamfer_ring(base+{0,height,0},half-{bevel,bevel},bevel*.5,yaw)
	ink_solid(pass,a[:],b[:],fill,fill,{})
	ink_solid(pass,b[:],c[:],cap,cap,{})
}

// Four-vertex cross-sections for links, pipes, and six-sided motor axles.
// The ring normal points against the axis, matching ink_solid's winding.
@(private)
cyber_link_basis :: proc(a,b:rl.Vector3)->(right,up:rl.Vector3) {
	axis:=rl.Vector3Normalize(b-a)
	reference:=rl.Vector3{0,0,1} if abs(axis.z)<.9 else rl.Vector3{0,1,0}
	right=rl.Vector3Normalize(rl.Vector3CrossProduct(axis,reference))
	up=rl.Vector3CrossProduct(right,axis)
	return
}

@(private)
cyber_link_rings :: proc(a,b:rl.Vector3,half:rl.Vector2)->(bottom,top:[4]rl.Vector3) {
	right,up:=cyber_link_basis(a,b)
	q:=[4]rl.Vector2{{-half.x,-half.y},{half.x,-half.y},{half.x,half.y},{-half.x,half.y}}
	for p,i in q {offset:=right*p.x+up*p.y;bottom[i],top[i]=a+offset,b+offset}
	return
}

@(private)
cyber_link :: proc(pass:Ink_Pass,a,b:rl.Vector3,half:rl.Vector2,fill:rl.Color=CYBER_BODY,cap:rl.Color=CYBER_METAL) {
	bottom,top:=cyber_link_rings(a,b,half)
	ink_solid(pass,bottom[:],top[:],fill,cap,{})
}

@(private)
cyber_axle :: proc(pass:Ink_Pass,a,b:rl.Vector3,radius:f32,cap:rl.Color=CYBER_METAL) {
	right,up:=cyber_link_basis(a,b)
	bottom,top:[6]rl.Vector3
	for i in 0..<6 {phase:=f32(i)*math.TAU/6;offset:=(right*math.cos(phase)+up*math.sin(phase))*radius;bottom[i],top[i]=a+offset,b+offset}
	ink_solid(pass,bottom[:],top[:],CYBER_BODY,cap,{})
}

@(private)
cyber_strip :: proc(pass:Ink_Pass,base,a,b:rl.Vector3,yaw:f32,color:rl.Color=CYBER_RED) {
	ink_line(pass,cyber_point(base,a,yaw),cyber_point(base,b,yaw),color)
}

@(private)
cyber_server :: proc(pass:Ink_Pass,base:rl.Vector3,height,yaw:f32,variant:u32=0) {
	cyber_case(pass,base,{.46,.44},.13,yaw)
	cyber_case(pass,base+{0,.13,0},{.36,.35},height-.13,yaw)
	// Recesses occupy the two camera-facing faces. An asymmetric top cap
	// and side cable make adjacent cabinets read as equipment, not pillars.
	ink_box(pass,cyber_point(base,{0,.3,.356},yaw),{.27,.006},height-.5,yaw,CYBER_RECESS,CYBER_RECESS,{})
	ink_box(pass,cyber_point(base,{.366,.35,0},yaw),{.006,.24},height-.62,yaw,CYBER_RECESS,CYBER_RECESS,{})
	for i in 0..<3 {
		y:=.42+f32(i)*.2
		ink_box(pass,cyber_point(base,{.06,y,.366},yaw),{.16,.008},.07,yaw,CYBER_RED_FACE,CYBER_RED_FACE,{})
		cyber_strip(pass,base,{-.1,y+.035,.377},{.22,y+.035,.377},yaw)
	}
	cyber_strip(pass,base,{.377,.48,-.15},{.377,height-.3,-.15},yaw,ink_scale(CYBER_RED,.6))
	cyber_strip(pass,base,{-.19,height-.25,.365},{-.09,height-.25,.365},yaw,CYBER_SCREEN)
	ink_box(pass,base+{0,height-.02,0},{.21,.22},.08,yaw,CYBER_RECESS,CYBER_METAL,{})
	if variant%2==0 {
		cyber_link(pass,cyber_point(base,{-.39,.16,-.21},yaw),cyber_point(base,{-.39,height*.68,-.21},yaw),{.025,.025})
		cyber_link(pass,cyber_point(base,{-.39,.16,-.21},yaw),cyber_point(base,{-.24,.16,-.30},yaw),{.025,.025})
	}
}

@(private)
cyber_rock :: proc(pass:Ink_Pass,base:rl.Vector3,radius,height,phase:f32,variant:u32,seam:bool=false) {
	bottom,middle,top:[5]rl.Vector3
	for i in 0..<5 {
		a:=phase+f32(i)*math.TAU/5
		r:=radius*(.84+.04*f32((variant>>u32(i*3))%4))
		o:=rl.Vector3{math.cos(a)*r,0,math.sin(a)*r}
		bottom[i]=base+o
		middle[i]=base+o*.92+{-.025*radius,height*.56,.035*radius}
		top[i]=base+o*.30+{.08*radius,height,-.12*radius}
	}
	ink_solid(pass,bottom[:],middle[:],CYBER_BODY,CYBER_CAP,{},shade=.16)
	ink_solid(pass,middle[:],top[:],CYBER_CAP,CYBER_METAL,{},shade=.2)
	if seam {ink_line(pass,middle[1],top[1],ink_scale(CYBER_RED,.45))}
}

@(private)
draw_expedition_cyber_outdoor :: proc(pass:Ink_Pass,cell:grid.Position) {
	base:=rl.Vector3{f32(cell.x)+.5,0,f32(cell.y)+.5};h:=expedition_cell_hash(cell,0xC7)
	if h%7>=5 {
		cyber_server(pass,base,1.55+f32((h>>4)%5)*.25,0,h)
		return
	}
	// The entire irregular pile fits the one blocked cell, including its
	// smaller fragments. No fake boulder stands on a traversable neighbour.
	phase:=f32(h%13)*.21
	cyber_rock(pass,base+{-.045,0,-.055},.40,.72+f32((h>>7)%4)*.18,phase,h,h%5==0)
	cyber_rock(pass,base+{.28,0,.27},.19,.45+f32(h%3)*.11,phase+.7,h>>3)
	cyber_rock(pass,base+{-.29,0,.25},.16,.31,phase+1.4,h>>6)
}

// A folded three-link industrial arm. Its whole horizontal footprint stays
// within the supporting blocked cell; even the open gripper clears aisles.
@(private)
cyber_robot_arm :: proc(pass:Ink_Pass,base:rl.Vector3,yaw:f32,mirror:f32=1) {
	cyber_case(pass,base,{.30,.22},.16,yaw)
	local:=[4]rl.Vector3{{-.24,.19,0},{.12,1.43,0},{.29,.98,0},{.13,.75,0}}
	points:[4]rl.Vector3
	for p,i in local {points[i]=cyber_point(base,{p.x*mirror,p.y,p.z},yaw)}
	for i in 0..<3 {
		cyber_link(pass,points[i],points[i+1],{.085 if i<2 else .045,.075},CYBER_METAL,CYBER_CAP)
		p:=local[i];p.x*=mirror
		cyber_axle(pass,cyber_point(base,p+{0,0,-.12},yaw),cyber_point(base,p+{0,0,.12},yaw),.13 if i<2 else .10)
		cyber_strip(pass,base,p+{-.055,0,.125},p+{.055,0,.125},yaw,ink_scale(CYBER_RED,.75))
	}
	for side in ([2]f32{-1,1}) {
		p:=local[3];p.x*=mirror
		cyber_link(pass,cyber_point(base,p+{side*.07,0,0},yaw),cyber_point(base,p+{side*.09,-.14,0},yaw),{.025,.04},CYBER_METAL)
	}
	cyber_strip(pass,base,{(local[0].x-.06)*mirror,local[0].y+.06,-.085},
		{(local[1].x-.06)*mirror,local[1].y-.05,-.085},yaw,ink_scale(CYBER_RED,.45))
}

@(private)
cyber_conveyor :: proc(pass:Ink_Pass,base:rl.Vector3,yaw:f32,arm:bool=false,mirror:f32=1) {
	cyber_case(pass,base,{.49,.45},.34,yaw)
	ink_box(pass,base+{0,.34,0},{.49,.32},.07,yaw,CYBER_RECESS,CYBER_RECESS,{})
	for i in 0..<5 {
		x:=f32(i-2)*.19
		cyber_axle(pass,cyber_point(base,{x,.43,-.31},yaw),cyber_point(base,{x,.43,.31},yaw),.065,CYBER_METAL)
	}
	for side in ([2]f32{-1,1}) {
		ink_box(pass,cyber_point(base,{0,.32,side*.39},yaw),{.49,.035},.19,yaw,CYBER_CAP,CYBER_METAL,{})
		cyber_strip(pass,base,{-.40,.38,side*.433},{.40,.38,side*.433},yaw,ink_scale(CYBER_RED,.6))
	}
	if arm {cyber_robot_arm(pass,cyber_point(base,{0,.48,0},yaw),yaw,mirror)}
	else {cyber_case(pass,base+{0,.50,0},{.16,.20},.22,yaw,CYBER_BODY,CYBER_CAP)}
}

@(private)
cyber_joined_wall :: proc(room:^game.Room,site:^world.Site,cell:grid.Position)->bool {
	tile,ok:=level.tile_at(room.level_data,cell)
	if !ok || tile.kind!=.Wall {return false}
	d:=world.site_cell(site,cell)
	return d.inside && !(d.fixture && site.active)
}

@(private)
draw_expedition_cyber_wall :: proc(pass:Ink_Pass,room:^game.Room,site:^world.Site,cell:grid.Position,design:world.Site_Cell) {
	base:=rl.Vector3{f32(cell.x)+.5,0,f32(cell.y)+.5};q:=design.local
	yaw:=f32(site.orientation%4)*math.PI/2
	if site.kind==.Workshop && q.x>=5 && q.x<=7 && abs(q.y)==5 {
		cyber_conveyor(pass,base,yaw,q.x!=6,-1 if q.x==7 else 1)
		return
	}
	if site.kind==.Nest && abs(q.x)==5 && abs(q.y)>=3 && abs(q.y)<=6 {
		// Three equipment bays and a breaker: an actual manufacturing aisle.
		if abs(q.y)%3==0 {cyber_server(pass,base,1.48,yaw,u32(abs(q.y)));return}
	}
	height:=expedition_site_wall_height(design)
	gate:=abs(design.wall_height-2.2)<.01
	if gate {height=2.12}
	cyber_case(pass,base,{.49,.49},height,0)
	ink_box(pass,base,{.495,.495},.10,0,CYBER_RECESS,CYBER_CAP,{})
	for direction in ([4]grid.Position{{0,1},{1,0},{0,-1},{-1,0}}) {
		if cyber_joined_wall(room,site,game.add_position(cell,direction)) {continue}
		face_yaw:=math.atan2(f32(-direction.x),f32(direction.y))
		detail:=(abs(q.x)+abs(q.y))%3==0 || gate
		if detail {
			ink_box(pass,cyber_point(base,{0,.19,.493},face_yaw),{.32,.005},height-.37,face_yaw,CYBER_RECESS,CYBER_RECESS,{})
			for i in 0..<3 {
				y:=height*.40+f32(i)*.13
				ink_box(pass,cyber_point(base,{0,y,.499},face_yaw),{.19,.003},.045,face_yaw,CYBER_METAL,CYBER_METAL,{})
			}
			cyber_strip(pass,base,{-.23,height-.30,.504},{.23,height-.30,.504},face_yaw)
			if gate {cyber_strip(pass,base,{-.34,.27,.504},{-.34,height-.24,.504},face_yaw,ink_scale(CYBER_RED,.7))}
		} else {
			// Recessed cable channels have short red sections, separated by dark
			// couplings; the whole wall never becomes a luminous wire cage.
			ink_box(pass,cyber_point(base,{0,.25,.493},face_yaw),{.46,.006},.11,face_yaw,CYBER_RECESS,CYBER_RECESS,{})
			cyber_strip(pass,base,{-.31,.30,.504},{.31,.30,.504},face_yaw,ink_scale(CYBER_RED,.6))
		}
	}
}

@(private)
draw_expedition_cyber_gate :: proc(pass:Ink_Pass,a,b:rl.Vector3) {
	mid:=(a+b)*.5;along:=rl.Vector3Normalize(b-a)
	length:=rl.Vector3Distance(a,b)
	yaw:=math.atan2(along.z,along.x)
	cyber_case(pass,mid,{length*.5+.42,.32},.24,yaw)
	ink_box(pass,mid+{0,.05,0},{length*.5-.12,.20},.06,yaw,CYBER_RECESS,CYBER_RECESS,{})
	// Tiny paired beacons on a solid lintel, rather than outlining its box.
	for side in ([2]f32{-1,1}) {
		cyber_strip(pass,mid,{side*(length*.5-.7),.10,.326},{side*(length*.5-.18),.10,.326},yaw)
	}
}

@(private)
cyber_console :: proc(pass:Ink_Pass,base:rl.Vector3,yaw:f32,archive:bool=false,secret:bool=false) {
	cyber_case(pass,base,{.46,.44},.14,yaw)
	cyber_case(pass,base+{0,.14,0},{.35,.32},.71,yaw)
	cyber_case(pass,cyber_point(base,{0,.85,-.06},yaw),{.37,.18},.60,yaw)
	ink_box(pass,cyber_point(base,{0,1.00,.126},yaw),{.28,.008},.32,yaw,CYBER_SCREEN,CYBER_SCREEN,{})
	cyber_strip(pass,base,{-.20,1.12,.14},{.15,1.12,.14},yaw,{106,216,247,254})
	ink_box(pass,cyber_point(base,{0,.75,.30},yaw),{.26,.07},.055,yaw,CYBER_METAL,CYBER_CAP,{})
	for i in 0..<3 {ink_box(pass,cyber_point(base,{f32(i-1)*.12,.808,.3},yaw),{.035,.035},.012,yaw,CYBER_RECESS,CYBER_RECESS,{})}
	color:=rl.Color{237,195,91,254} if secret else CYBER_RED
	cyber_strip(pass,base,{-.25,.35,.329},{-.25,.62,.329},yaw,color)
	if archive {ink_box(pass,base+{0,1.45,0},{.22,.11},.12,yaw,CYBER_RECESS,CYBER_CAP,{})}
}

@(private)
draw_expedition_cyber_fixture :: proc(pass:Ink_Pass,site:^world.Site,boss_defeated:bool) {
	base:=rl.Vector3{f32(site.position.x)+.5,0,f32(site.position.y)+.5}
	yaw:=f32(site.orientation%4)*math.PI/2
	accent:=ink_scale(CYBER_RED,.45) if site.state==.Resolved else CYBER_RED
	if site.secret {accent={237,195,91,254}}
	#partial switch site.kind {
	case .Archive,.Memory:
		cyber_console(pass,base,yaw,site.kind==.Archive,site.secret)
	case .Workshop:
		// The controller is part of the same blocked fixture as its arm.
		// Its operator display faces the fixed camera, independently of the
		// factory's entrance orientation; the square occupied cell is unchanged.
		control_yaw:=f32(0)
		cyber_case(pass,base,{.46,.44},.62,control_yaw)
		cyber_robot_arm(pass,base+{0,.62,0},control_yaw)
		ink_box(pass,base+{0,.15,.446},{.34,.008},.40,control_yaw,CYBER_RECESS,CYBER_RECESS,{})
		ink_box(pass,base+{0,.20,.458},{.28,.008},.28,control_yaw,CYBER_SCREEN,CYBER_SCREEN,{})
		cyber_strip(pass,base,{-.20,.34,.47},{.12,.34,.47},control_yaw,CYBER_SCREEN)
		for side in ([2]f32{-1,1}) {ink_box(pass,base+{side*.32,.46,.46},{.018,.008},.045,0,CYBER_METAL,CYBER_METAL,{})}
	case .Nest:
		cyber_case(pass,base,{.47,.46},.15,yaw)
		cyber_case(pass,base+{0,.15,0},{.39,.36},1.2,yaw)
		ink_box(pass,cyber_point(base,{0,.33,.367},yaw),{.27,.008},.66,yaw,CYBER_RECESS,CYBER_RECESS,{})
		for i in 0..<3 {cyber_strip(pass,base,{-.23,.42+f32(i)*.21,.38},{.23,.42+f32(i)*.21,.38},yaw,accent)}
		for side in ([2]f32{-1,1}) {ink_box(pass,cyber_point(base,{side*.32,1.33,0},yaw),{.06,.20},.33,yaw,CYBER_CAP,CYBER_METAL,{})}
		cyber_case(pass,base+{0,1.35,0},{.19,.22},.16,yaw,CYBER_RED_FACE,CYBER_CAP)
	case .Spring:
		ink_frustum(pass,base,.47,.47,.14,8,math.PI/8,CYBER_BODY,CYBER_CAP,{})
		ink_frustum(pass,base+{0,.14,0},.38,.28,.18,8,math.PI/8,CYBER_RED_FACE,CYBER_RED_FACE,{})
		ink_frustum(pass,base+{0,.32,0},.28,.17,.09,8,math.PI/8,CYBER_RED_FACE,CYBER_CAP,{})
		for side in ([2]f32{-1,1}) {cyber_strip(pass,base,{-.22,.21,side*.31},{.22,.21,side*.31},0,accent)}
		if site.state!=.Resolved {
			mint:=rl.Color{117,244,204,255}
			ink_frustum(pass,base+{0,.58,0},.12,.17,.12,6,0,mint,mint,{})
			ink_frustum(pass,base+{0,.70,0},.17,0,.13,6,0,mint,mint,{})
		}
	case .Cache:
		cyber_case(pass,base,{.46,.42},.66,yaw)
		cyber_case(pass,base+{0,.66,0},{.44,.40},.15,yaw,CYBER_METAL,CYBER_CAP)
		for side in ([2]f32{-1,1}) {ink_box(pass,cyber_point(base,{side*.28,.10,.427},yaw),{.045,.008},.54,yaw,CYBER_RECESS,CYBER_RECESS,{})}
		cyber_strip(pass,base,{-.14,.48,.44},{.14,.48,.44},yaw,accent)
	case .Boss:
		for side in ([2]f32{-1,1}) {
			p:=cyber_point(base,{side*2,0,0},yaw)
			cyber_case(pass,p,{.49,.46},.25,yaw)
			cyber_case(pass,p+{0,.25,0},{.40,.35},3.20,yaw)
			cyber_strip(pass,p,{-side*.29,.42,.358},{-side*.29,3.20,.358},yaw,accent)
			for i in 0..<4 {cyber_strip(pass,p,{-.13,.65+f32(i)*.22,.359},{.13,.65+f32(i)*.22,.359},yaw,ink_scale(accent,.65))}
		}
		cyber_case(pass,base+{0,3.23,0},{2.45,.36},.40,yaw)
		cyber_strip(pass,base,{-1.61,3.31,.37},{1.61,3.31,.37},yaw,{118,242,202,254} if boss_defeated else accent)
	case .Trial:
		// Open gameplay cells only receive a flush floor plate.
		ink_frustum(pass,base,.45,.45,.018,6,0,CYBER_BODY,CYBER_CAP,{})
		for side in ([2]f32{-1,1}) {cyber_strip(pass,base,{-.23,.025,side*.24},{.23,.025,side*.24},yaw,accent)}
	case .Tunnel:
		ink_box(pass,base+{0,.014,0},{.45,.45},.006,yaw,CYBER_RECESS,CYBER_RECESS,{})
		for i in 0..<4 {ink_box(pass,cyber_point(base,{0,.020,f32(i-2)*.15},yaw),{.36,.02},.004,yaw,CYBER_METAL,CYBER_METAL,{})}
		cyber_strip(pass,base,{-.36,.025,-.36},{.36,.025,-.36},yaw,accent)
	}
}
