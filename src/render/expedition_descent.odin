package render

import "core:math"
import rl "vendor:raylib"
import world "../expedition"
import game "../game"
import grid "../engine/grid"

// The descent keeps real, solid materials under the shared lighting. Only
// lamps, inscriptions and exposed lava seams emit light. All geometry is
// static and follows Ink_Pass, so cached walls and reflected fixtures agree.
DESCENT_WOOD :: rl.Color{66,38,24,255}
DESCENT_WOOD_CAP :: rl.Color{102,64,35,255}
DESCENT_IRON :: rl.Color{34,35,37,255}
DESCENT_IRON_CAP :: rl.Color{57,54,49,255}
DESCENT_SAND :: rl.Color{120,88,49,255}
DESCENT_SAND_CAP :: rl.Color{167,129,74,255}
DESCENT_GOLD :: rl.Color{149,108,37,255}
DESCENT_BASALT :: rl.Color{25,24,28,255}
DESCENT_BASALT_CAP :: rl.Color{48,43,46,255}
DESCENT_EMBER :: rl.Color{123,32,12,255}
DESCENT_AMBER :: rl.Color{255,151,42,254}
DESCENT_TURQUOISE :: rl.Color{61,205,188,254}
DESCENT_LAVA :: rl.Color{255,93,23,254}
DESCENT_DARK :: rl.Color{11,13,15,255}

@(private)
descent_handles :: proc(w:^world.World)->bool {
	return w!=nil && (w.biome==.West || w.biome==.Egypt || w.biome==.Inferno)
}

@(private)
descent_accent :: proc(w:^world.World,site:^world.Site=nil)->rl.Color {
	c:=DESCENT_AMBER
	if w.biome==.Egypt {c=DESCENT_TURQUOISE}
	if w.biome==.Inferno {c=DESCENT_LAVA}
	if site!=nil {
		if site.secret {c={245,216,140,254}}
		if site.state==.Resolved {c=ink_scale(c,.38)}
	}
	return c
}

// A coloured six-sided axle, used for winches, seals and barrel hoops. It
// shares the same outward winding as the rectangular link primitive.
@(private)
descent_axle :: proc(pass:Ink_Pass,a,b:rl.Vector3,radius:f32,fill,cap:rl.Color) {
	right,up:=cyber_link_basis(a,b)
	bottom,top:[6]rl.Vector3
	for i in 0..<6 {
		angle:=f32(i)*math.TAU/6;o:=(right*math.cos(angle)+up*math.sin(angle))*radius
		bottom[i],top[i]=a+o,b+o
	}
	ink_solid(pass,bottom[:],top[:],fill,cap,{})
}

// Form a thin face detail in local space before rotating it. Choosing a
// world-space link basis would turn its wider dimension into wall thickness
// on the east/west faces and make it protrude into a walkable neighbour.
@(private)
descent_face_link :: proc(pass:Ink_Pass,base,a,b:rl.Vector3,yaw:f32,half:rl.Vector2,fill,cap:rl.Color) {
	bottom,top:=cyber_link_rings(a,b,half)
	for &point in bottom {point=cyber_point(base,point,yaw)}
	for &point in top {point=cyber_point(base,point,yaw)}
	ink_solid(pass,bottom[:],top[:],fill,cap,{})
}

// An open octagonal basin, rather than a solid cylinder painted as water.
// The rim has a real inner wall and a narrow horizontal lip, all in one cell.
@(private)
descent_basin :: proc(pass:Ink_Pass,base:rl.Vector3,radius,height:f32,fill,cap,water:rl.Color) {
	ink_frustum(pass,base,radius*.91,radius*.91,.06,8,math.PI/8,fill,cap,{})
	for i in 0..<8 {
		a,b:=f32(i)*math.TAU/8+math.PI/8,f32(i+1)*math.TAU/8+math.PI/8
		p:=base+rl.Vector3{math.cos(a)*radius,0,math.sin(a)*radius}
		q:=base+rl.Vector3{math.cos(b)*radius,0,math.sin(b)*radius}
		mid:=(p+q)*.5;length:=rl.Vector3Distance(p,q)
		ink_box(pass,mid,{length*.5+.005,.045},height,math.atan2(q.z-p.z,q.x-p.x),fill,cap,{})
	}
	ink_frustum(pass,base+{0,height*.45,0},radius-.075,radius-.075,.012,8,math.PI/8,water,water,{})
}

@(private)
descent_barrel :: proc(pass:Ink_Pass,base:rl.Vector3,radius,height:f32,iron:bool=false) {
	wood,cap:=DESCENT_WOOD,DESCENT_WOOD_CAP
	if iron {wood,cap=DESCENT_IRON,DESCENT_IRON_CAP}
	ink_frustum(pass,base,radius*.82,radius,height*.35,8,math.PI/8,wood,cap,{})
	ink_frustum(pass,base+{0,height*.35,0},radius,radius*.82,height*.65,8,math.PI/8,wood,cap,{})
	for y in ([2]f32{.15,.73}) {
		r:=radius*(.92 if y<.5 else .91)
		ink_frustum(pass,base+{0,height*y,0},r,r,height*.075,8,math.PI/8,DESCENT_IRON,DESCENT_IRON_CAP,{})
	}
	ink_box(pass,base+{radius*.24,height,0},{radius*.12,radius*.09},.018,0,DESCENT_IRON,DESCENT_IRON,{})
}

@(private)
descent_mesa :: proc(pass:Ink_Pass,base:rl.Vector3,radius,height,phase:f32) {
	// Flat-topped, terraced sandstone; the darker strata remain opaque.
	bottom:=rl.Color{94,47,29,255};middle:=rl.Color{139,73,39,255};top:=rl.Color{167,98,53,255}
	ink_frustum(pass,base,radius,radius*.91,height*.42,6,phase,bottom,middle,{},shade=.12)
	ink_frustum(pass,base+{0,height*.42,0},radius*.94,radius*.90,height*.10,6,phase,middle,top,{})
	ink_frustum(pass,base+{0,height*.52,0},radius*.80,radius*.68,height*.39,6,phase,bottom,middle,{},shade=.12)
	ink_frustum(pass,base+{0,height*.91,0},radius*.72,radius*.66,height*.09,6,phase,top,top,{})
}

@(private)
descent_cactus :: proc(pass:Ink_Pass,base:rl.Vector3,height,yaw:f32) {
	green:=rl.Color{43,62,44,255};tip:=rl.Color{69,85,48,255}
	ink_frustum(pass,base,.14,.11,height,6,math.PI/6,green,tip,{},shade=.1)
	ink_frustum(pass,base+{0,height,0},.11,0,.13,6,math.PI/6,green,tip,{})
	for side in ([2]f32{-1,1}) {
		y:=height*(.40 if side<0 else .58)
		a:=cyber_point(base,{0,y,0},yaw);b:=cyber_point(base,{side*.32,y,0},yaw)
		descent_axle(pass,a,b,.085,green,tip)
		ink_frustum(pass,b,.085,.075,.40,6,math.PI/6,green,tip,{})
		ink_frustum(pass,b+{0,.40,0},.075,0,.10,6,math.PI/6,green,tip,{})
	}
	ink_frustum(pass,base+{.25,0,.26},.13,.08,.16,5,.3,DESCENT_WOOD_CAP,DESCENT_SAND,{})
}

@(private)
descent_obelisk :: proc(pass:Ink_Pass,base:rl.Vector3,height,yaw:f32,accent:rl.Color) {
	ink_box(pass,base,{.43,.43},.14,yaw,DESCENT_SAND,DESCENT_SAND_CAP,{})
	ink_box(pass,base+{0,.14,0},{.31,.31},height-.48,yaw,DESCENT_SAND,DESCENT_SAND_CAP,{})
	ink_frustum(pass,base+{0,height-.34,0},.4384,0,.34,4,yaw+math.PI/4,DESCENT_GOLD,DESCENT_SAND_CAP,{})
	cyber_strip(pass,base,{0,.40,.314},{0,height-.52,.314},yaw,accent)
	for i in 0..<2 {cyber_strip(pass,base,{-.11,.59+f32(i)*.36,.314},{.11,.59+f32(i)*.36,.314},yaw,accent)}
}

@(private)
descent_column :: proc(pass:Ink_Pass,base:rl.Vector3,height:f32,accent:rl.Color,broken:bool=false) {
	ink_box(pass,base,{.43,.43},.13,0,DESCENT_SAND,DESCENT_SAND_CAP,{})
	ink_frustum(pass,base+{0,.13,0},.32,.26,height-.37,8,math.PI/8,DESCENT_SAND,DESCENT_SAND_CAP,{},shade=.1)
	if !broken {
		ink_frustum(pass,base+{0,height-.24,0},.26,.43,.16,8,math.PI/8,DESCENT_GOLD,DESCENT_SAND_CAP,{})
		ink_box(pass,base+{0,height-.08,0},{.45,.45},.08,0,DESCENT_SAND,DESCENT_SAND_CAP,{})
	} else {
		ink_frustum(pass,base+{0,height-.24,0},.26,.19,.19,5,.35,DESCENT_SAND_CAP,DESCENT_SAND_CAP,{})
	}
	mark_y:=height*.6
	mark_radius:=.32-.06*((mark_y-.13)/(height-.37))
	front:=mark_radius*math.cos(f32(math.PI/8))+.003
	ink_line(pass,base+{-.09,mark_y,front},base+{.09,mark_y,front},accent)
}

@(private)
descent_basalt :: proc(pass:Ink_Pass,base:rl.Vector3,height:f32,variant:u32) {
	ink_frustum(pass,base+{-.10,0,-.08},.36,.32,height,6,0,DESCENT_BASALT,DESCENT_BASALT_CAP,{},shade=.14)
	ink_frustum(pass,base+{.28,0,.20},.20,.19,height*.48,6,math.PI/6,DESCENT_BASALT,DESCENT_BASALT_CAP,{})
	ink_frustum(pass,base+{-.24,0,.30},.16,.14,height*.30,6,math.PI/6,DESCENT_BASALT,DESCENT_BASALT_CAP,{})
	if variant%3==0 {
		// Follow an actual front face of the central prism, not an outline.
		front:=math.sqrt(f32(3))*.5
		a:=base+rl.Vector3{-.10,.13,-.08+front*(.36-.04*.13/height)+.003}
		b:=base+rl.Vector3{-.01,height*.48,-.08+front*(.36-.04*.48)+.003}
		c:=base+rl.Vector3{-.11,height*.78,-.08+front*(.36-.04*.78)+.003}
		ink_line(pass,a,b,ink_scale(DESCENT_LAVA,.75));ink_line(pass,b,c,DESCENT_LAVA)
	}
}

@(private)
draw_expedition_descent_outdoor :: proc(pass:Ink_Pass,w:^world.World,cell:grid.Position)->bool {
	if !descent_handles(w) {return false}
	p:=rl.Vector3{f32(cell.x)+.5,0,f32(cell.y)+.5};h:=expedition_cell_hash(cell,u32(w.biome)+0xD3)
	#partial switch w.biome {
	case .West:
		if h%7<4 {descent_mesa(pass,p,.47,1.05+f32((h>>5)%5)*.22,f32(h%13)*.12)}
		else if h%7<6 {descent_cactus(pass,p,1.55+f32((h>>4)%4)*.19,f32(h%4)*math.PI/2)}
		else {descent_barrel(pass,p+{-.22,0,-.18},.25,.88);descent_barrel(pass,p+{.25,0,.23},.21,.65)}
	case .Egypt:
		if h%5==0 {descent_obelisk(pass,p,1.9+f32((h>>6)%4)*.19,0,ink_scale(DESCENT_TURQUOISE,.6))}
		else if h%5==1 {descent_column(pass,p,1.10+f32((h>>3)%3)*.26,{},true)}
		else {
			for i in 0..<3 {
				half:=.46-f32(i)*.11
				ink_box(pass,p+{0,f32(i)*.25,0},{half,half},.25,0,DESCENT_SAND,DESCENT_SAND_CAP,{})
			}
			ink_frustum(pass,p+{0,.75,0},.34,0,.48,4,math.PI/4,DESCENT_SAND,DESCENT_SAND_CAP,{})
		}
	case .Inferno:descent_basalt(pass,p,1.1+f32((h>>5)%6)*.23,h)
	}
	return true
}

@(private)
draw_expedition_descent_wall :: proc(pass:Ink_Pass,room:^game.Room,w:^world.World,site:^world.Site,cell:grid.Position,design:world.Site_Cell)->bool {
	if !descent_handles(w) {return false}
	p:=rl.Vector3{f32(cell.x)+.5,0,f32(cell.y)+.5};q:=design.local
	plain_height:=expedition_site_wall_height(design);gate:=abs(design.wall_height-2.2)<.01
	height:=2.12 if gate else plain_height
	h:=expedition_cell_hash(cell,0xD7)
	if w.biome==.West && site.kind==.Workshop && q.x>=5 && q.x<=7 && abs(q.y)==5 {
		descent_barrel(pass,p,.44,.85,abs(q.x)%2==0)
		return true
	}
	if w.biome==.Egypt && gate {descent_column(pass,p,height,descent_accent(w));return true}
	fill,cap:=DESCENT_WOOD,DESCENT_WOOD_CAP
	if w.biome==.Egypt {fill,cap=DESCENT_SAND,DESCENT_SAND_CAP}
	if w.biome==.Inferno {fill,cap=DESCENT_BASALT,DESCENT_BASALT_CAP}
	ink_box(pass,p,{.475,.475},height,0,fill,cap,{})
	ink_box(pass,p,{.49,.49},.12,0,ink_scale(fill,.72),cap,{})
	if w.biome!=.Inferno {
		ink_box(pass,p+{0,height-.09,0},{.49,.49},.09,0,cap,cap,{})
	} else {
		for i in 0..<3 {
			o:=rl.Vector3{-.23+f32(i)*.23,height-.13,-.12 if i!=1 else .23}
			ink_frustum(pass,p+o,.21,.19,.18+f32((h>>u32(i*3))%3)*.10,6,math.PI/6,fill,cap,{})
		}
	}
	for direction in ([4]grid.Position{{x = 0, y = 1},{x = 1, y = 0},{x = 0, y = -1},{x = -1, y = 0}}) {
		if expedition_wall_joined(room,site,game.add_position(cell,direction),plain_height) {continue}
		yaw:=math.atan2(f32(-direction.x),f32(direction.y))
		#partial switch w.biome {
		case .West:
			for side in ([2]f32{-1,1}) {ink_box(pass,cyber_point(p,{side*.34,.12,.479},yaw),{.04,.014},height-.22,yaw,cap,cap,{})}
			descent_face_link(pass,p,{-.29,.22,.48},{.29,height-.21,.48},yaw,{.025,.012},DESCENT_IRON,DESCENT_IRON_CAP)
			if gate {cyber_strip(pass,p,{-.13,height-.31,.496},{.13,height-.31,.496},yaw,DESCENT_AMBER)}
		case .Egypt:
			for i in 1..=2 {ink_box(pass,cyber_point(p,{0,height*f32(i)/3,.478},yaw),{.43,.006},.026,yaw,ink_scale(fill,.55),ink_scale(fill,.55),{})}
			ink_box(pass,cyber_point(p,{.13,height*.34,.479},yaw),{.012,.006},height*.30,yaw,ink_scale(fill,.55),fill,{})
			if (abs(q.x)+abs(q.y))%4==0 {cyber_strip(pass,p,{-.20,height-.20,.49},{.20,height-.20,.49},yaw,ink_scale(DESCENT_TURQUOISE,.65))}
		case .Inferno:
			a:=cyber_point(p,{-.12,.13,.491},yaw);b:=cyber_point(p,{.09,height*.49,.491},yaw);c:=cyber_point(p,{-.03,height-.12,.491},yaw)
			descent_face_link(pass,p,{-.12,.13,.481},{.09,height*.49,.481},yaw,{.025,.006},DESCENT_EMBER,DESCENT_EMBER)
			descent_face_link(pass,p,{.09,height*.49,.481},{-.03,height-.12,.481},yaw,{.020,.006},DESCENT_EMBER,DESCENT_EMBER)
			if gate || h%3==0 {ink_line(pass,a,b,DESCENT_LAVA);ink_line(pass,b,c,ink_scale(DESCENT_LAVA,.7))}
		}
	}
	return true
}

@(private)
draw_expedition_descent_gate :: proc(pass:Ink_Pass,w:^world.World,pa,pb:rl.Vector3)->bool {
	if !descent_handles(w) {return false}
	p:=(pa+pb)*.5;delta:=pb-pa;length:=rl.Vector3Length(delta);yaw:=math.atan2(delta.z,delta.x)
	#partial switch w.biome {
	case .West:
		ink_box(pass,p,{length*.5+.40,.25},.24,yaw,DESCENT_WOOD,DESCENT_WOOD_CAP,{})
		for side in ([2]f32{-1,1}) {
			ink_box(pass,cyber_point(p,{side*(length*.5-.18),-.02,0},yaw),{.10,.27},.28,yaw,DESCENT_IRON,DESCENT_IRON_CAP,{})
			cyber_strip(pass,p,{side*.23,.07,.259},{side*.75,.07,.259},yaw,ink_scale(DESCENT_AMBER,.65))
		}
	case .Egypt:
		ink_box(pass,p,{length*.5+.43,.32},.27,yaw,DESCENT_SAND,DESCENT_SAND_CAP,{})
		ink_box(pass,p+{0,.27,0},{length*.5+.46,.36},.10,yaw,DESCENT_GOLD,DESCENT_SAND_CAP,{})
		for i in -2..=2 {cyber_strip(pass,p,{f32(i)*.24,.09,.327},{f32(i)*.24,.21,.327},yaw,DESCENT_TURQUOISE)}
	case .Inferno:
		cyber_case(pass,p,{length*.5+.43,.32},.29,yaw,DESCENT_BASALT,DESCENT_BASALT_CAP)
		for side in ([2]f32{-1,1}) {
			cyber_strip(pass,p,{side*.15,.09,.326},{side*(length*.5-.12),.12,.326},yaw,ink_scale(DESCENT_LAVA,.70))
			ink_frustum(pass,cyber_point(p,{side*(length*.5),.27,0},yaw),.17,0,.36,5,0,DESCENT_BASALT,DESCENT_BASALT_CAP,{})
		}
	}
	return true
}

@(private)
descent_anvil :: proc(pass:Ink_Pass,p:rl.Vector3,yaw:f32,hot:bool=false) {
	ink_frustum(pass,p,.34,.31,.44,7,.2,DESCENT_BASALT if hot else DESCENT_WOOD,DESCENT_BASALT_CAP if hot else DESCENT_WOOD_CAP,{})
	ink_box(pass,p+{0,.44,0},{.25,.21},.09,yaw,DESCENT_IRON,DESCENT_IRON_CAP,{})
	ink_box(pass,p+{0,.53,0},{.13,.13},.20,yaw,DESCENT_IRON,DESCENT_IRON_CAP,{})
	ink_box(pass,cyber_point(p,{-.07,.73,0},yaw),{.30,.18},.12,yaw,DESCENT_IRON,DESCENT_IRON_CAP,{})
	a,b:=cyber_point(p,{.23,.79,0},yaw),cyber_point(p,{.46,.79,0},yaw)
	bottom,top:=cyber_link_rings(a,b,{.06,.14});for &v in top {v=b}
	ink_solid(pass,bottom[:],top[:],DESCENT_IRON,DESCENT_IRON_CAP,{},true)
	// The hammer rests within the same blocked workstation cell.
	cyber_link(pass,cyber_point(p,{-.29,.08,.29},yaw),cyber_point(p,{-.18,.49,.29},yaw),{.025,.025},DESCENT_WOOD,DESCENT_WOOD_CAP)
	ink_box(pass,cyber_point(p,{-.18,.47,.29},yaw),{.13,.065},.09,yaw,DESCENT_IRON,DESCENT_IRON_CAP,{})
	if hot {cyber_strip(pass,p,{-.26,.853,.06},{.11,.853,.06},yaw,ink_scale(DESCENT_LAVA,.7))}
}

@(private)
descent_west_fixture :: proc(pass:Ink_Pass,p:rl.Vector3,site:^world.Site,accent:rl.Color) {
	yaw:=f32(site.orientation%4)*math.PI/2
	#partial switch site.kind {
	case .Nest:
		// Powder magazine: barrels behind a small boarded, iron-bound front.
		descent_barrel(pass,cyber_point(p,{-.23,0,-.10},yaw),.23,1.00)
		descent_barrel(pass,cyber_point(p,{.24,0,-.10},yaw),.22,.87)
		ink_box(pass,cyber_point(p,{0,.12,.25},yaw),{.44,.14},.45,yaw,DESCENT_WOOD,DESCENT_WOOD_CAP,{})
		for side in ([2]f32{-1,1}) {ink_box(pass,cyber_point(p,{side*.30,.12,.397},yaw),{.045,.008},.45,yaw,DESCENT_IRON,DESCENT_IRON_CAP,{})}
		cyber_strip(pass,p,{-.12,.40,.414},{.12,.40,.414},yaw,accent)
	case .Cache:
		ink_box(pass,p,{.45,.37},.53,yaw,DESCENT_WOOD,DESCENT_WOOD_CAP,{})
		cyber_case(pass,p+{0,.53,0},{.45,.37},.18,yaw,DESCENT_WOOD,DESCENT_WOOD_CAP)
		for side in ([2]f32{-1,1}) {
			ink_box(pass,cyber_point(p,{side*.29,.04,.379},yaw),{.045,.009},.56,yaw,DESCENT_IRON,DESCENT_IRON_CAP,{})
			ink_box(pass,cyber_point(p,{side*.29,.711,0},yaw),{.045,.34},.025,yaw,DESCENT_IRON,DESCENT_IRON_CAP,{})
		}
		ink_box(pass,cyber_point(p,{0,.34,.391},yaw),{.08,.025},.17,yaw,DESCENT_GOLD,DESCENT_GOLD,{})
		cyber_strip(pass,p,{-.05,.43,.42},{.05,.43,.42},yaw,accent)
	case .Archive:
		// Telegraph desk: printed message, copper key, spool and tall insulator.
		ink_box(pass,p,{.43,.34},.58,yaw,DESCENT_WOOD,DESCENT_WOOD_CAP,{})
		ink_box(pass,cyber_point(p,{0,.62,-.20},yaw),{.35,.045},.53,yaw,DESCENT_WOOD,DESCENT_WOOD_CAP,{})
		ink_box(pass,cyber_point(p,{0,.72,-.149},yaw),{.28,.006},.32,yaw,{171,145,96,255},{171,145,96,255},{})
		for i in 0..<3 {ink_box(pass,cyber_point(p,{-.03,.78+f32(i)*.08,-.141},yaw),{.19-f32(i%2)*.04,.003},.015,yaw,DESCENT_WOOD,DESCENT_WOOD,{})}
		ink_box(pass,cyber_point(p,{.12,.58,.15},yaw),{.14,.075},.06,yaw,DESCENT_GOLD,DESCENT_GOLD,{})
		descent_axle(pass,cyber_point(p,{-.22,.65,.12},yaw),cyber_point(p,{-.22,.65,.28},yaw),.085,DESCENT_IRON,DESCENT_GOLD)
		ink_box(pass,cyber_point(p,{.38,0,-.27},yaw),{.045,.045},1.60,yaw,DESCENT_WOOD,DESCENT_WOOD_CAP,{})
		ink_frustum(pass,cyber_point(p,{.38,1.58,-.27},yaw),.07,.06,.11,6,0,DESCENT_IRON,DESCENT_GOLD,{})
		cyber_strip(pass,p,{-.10,1.03,-.136},{.14,1.03,-.136},yaw,accent)
	case .Workshop:descent_anvil(pass,p,yaw)
	case .Spring:
		descent_basin(pass,p,.41,.49,DESCENT_SAND,DESCENT_SAND_CAP,{29,79,86,255})
		for side in ([2]f32{-1,1}) {ink_box(pass,cyber_point(p,{side*.34,.38,0},yaw),{.045,.07},1.03,yaw,DESCENT_WOOD,DESCENT_WOOD_CAP,{})}
		ink_box(pass,p+{0,1.41,0},{.43,.09},.11,yaw,DESCENT_WOOD,DESCENT_WOOD_CAP,{})
		descent_axle(pass,cyber_point(p,{-.30,1.17,0},yaw),cyber_point(p,{.30,1.17,0},yaw),.06,DESCENT_IRON,DESCENT_IRON_CAP)
		cyber_link(pass,p+{0,.73,0},p+{0,1.17,0},{.012,.012},DESCENT_WOOD_CAP,DESCENT_WOOD_CAP)
		ink_frustum(pass,p+{0,.57,0},.10,.14,.19,6,0,DESCENT_WOOD,DESCENT_IRON_CAP,{})
		cyber_strip(pass,p,{-.14,1.45,.096},{.14,1.45,.096},yaw,accent)
	case .Memory:
		// A frontier memorial and its brass sheriff star, printed as solid metal.
		ink_box(pass,p,{.44,.36},.13,yaw,DESCENT_SAND,DESCENT_SAND_CAP,{})
		cyber_case(pass,p+{0,.13,0},{.30,.19},1.24,yaw,DESCENT_SAND,DESCENT_SAND_CAP)
		descent_axle(pass,cyber_point(p,{0,.97,.195},yaw),cyber_point(p,{0,.97,.225},yaw),.19,DESCENT_GOLD,DESCENT_GOLD)
		for i in 0..<3 {cyber_strip(pass,p,{-.16,.41+f32(i)*.12,.20},{.16,.41+f32(i)*.12,.20},yaw,accent)}
	case .Trial,.Tunnel,.Boss:
		// Walkable seals and the rotated portal are shared below.
	}
}

@(private)
descent_egypt_inscription :: proc(pass:Ink_Pass,p:rl.Vector3,yaw:f32,height:f32,accent:rl.Color) {
	// A recessed tablet with a sun, a reed and a small angular inscription.
	ink_box(pass,cyber_point(p,{0,.30,.308},yaw),{.24,.007},height-.58,yaw,ink_scale(DESCENT_SAND,.55),DESCENT_SAND,{})
	cyber_strip(pass,p,{0,.44,.319},{0,height-.37,.319},yaw,accent)
	cyber_strip(pass,p,{-.14,height-.45,.319},{.14,height-.45,.319},yaw,accent)
	cyber_strip(pass,p,{-.13,.61,.319},{.10,.79,.319},yaw,ink_scale(accent,.65))
}

@(private)
descent_egypt_fixture :: proc(pass:Ink_Pass,p:rl.Vector3,site:^world.Site,accent:rl.Color) {
	yaw:=f32(site.orientation%4)*math.PI/2
	#partial switch site.kind {
	case .Nest:
		// Upright sarcophagus: stepped plinth, broad headdress and carved mask.
		ink_box(pass,p,{.45,.42},.14,yaw,DESCENT_SAND,DESCENT_SAND_CAP,{})
		cyber_case(pass,p+{0,.14,0},{.33,.29},1.30,yaw,DESCENT_SAND,DESCENT_SAND_CAP)
		ink_box(pass,p+{0,1.19,0},{.40,.30},.35,yaw,DESCENT_GOLD,DESCENT_SAND_CAP,{})
		ink_box(pass,cyber_point(p,{0,1.21,.307},yaw),{.18,.012},.22,yaw,DESCENT_SAND_CAP,DESCENT_SAND_CAP,{})
		for side in ([2]f32{-1,1}) {cyber_strip(pass,p,{side*.07,1.34,.325},{side*.13,1.34,.325},yaw,accent)}
		for y in ([3]f32{.40,.63,.86}) {ink_box(pass,cyber_point(p,{0,y,.301},yaw),{.24,.008},.055,yaw,DESCENT_GOLD,DESCENT_GOLD,{})}
	case .Cache:
		ink_box(pass,p,{.46,.38},.47,yaw,DESCENT_SAND,DESCENT_SAND_CAP,{})
		cyber_case(pass,p+{0,.47,0},{.46,.38},.20,yaw,DESCENT_GOLD,DESCENT_SAND_CAP)
		for side in ([2]f32{-1,1}) {ink_box(pass,cyber_point(p,{side*.29,.07,.386},yaw),{.035,.008},.41,yaw,DESCENT_GOLD,DESCENT_GOLD,{})}
		descent_axle(pass,cyber_point(p,{0,.38,.39},yaw),cyber_point(p,{0,.38,.415},yaw),.10,DESCENT_GOLD,DESCENT_GOLD)
		cyber_strip(pass,p,{-.08,.38,.421},{.08,.38,.421},yaw,accent)
	case .Archive:
		ink_box(pass,p,{.44,.41},.14,yaw,DESCENT_SAND,DESCENT_SAND_CAP,{})
		ink_box(pass,p+{0,.14,0},{.34,.30},1.24,yaw,DESCENT_SAND,DESCENT_SAND_CAP,{})
		ink_box(pass,p+{0,1.38,0},{.40,.35},.12,yaw,DESCENT_GOLD,DESCENT_SAND_CAP,{})
		descent_egypt_inscription(pass,p,yaw,1.38,accent)
	case .Workshop:
		// Stone carver's altar: a falcon sculpture and a bronze chisel.
		ink_box(pass,p,{.42,.37},.13,yaw,DESCENT_SAND,DESCENT_SAND_CAP,{})
		ink_box(pass,p+{0,.13,0},{.29,.26},.50,yaw,DESCENT_SAND,DESCENT_SAND_CAP,{})
		ink_box(pass,p+{0,.63,0},{.44,.39},.12,yaw,DESCENT_GOLD,DESCENT_SAND_CAP,{})
		ink_frustum(pass,p+{0,.75,0},.16,.11,.31,6,0,DESCENT_SAND,DESCENT_SAND_CAP,{})
		ink_box(pass,p+{0,1.03,0},{.13,.13},.17,yaw,DESCENT_GOLD,DESCENT_SAND_CAP,{})
		for side in ([2]f32{-1,1}) {cyber_link(pass,cyber_point(p,{side*.09,.99,0},yaw),cyber_point(p,{side*.34,.83,0},yaw),{.055,.08},DESCENT_SAND,DESCENT_GOLD)}
		cyber_link(pass,cyber_point(p,{-.27,.77,.24},yaw),cyber_point(p,{.16,.78,.24},yaw),{.018,.02},DESCENT_IRON,DESCENT_GOLD)
		cyber_strip(pass,p,{-.22,.65,.398},{.22,.65,.398},yaw,accent)
	case .Spring:
		descent_basin(pass,p,.42,.38,DESCENT_SAND,DESCENT_SAND_CAP,{28,98,105,255})
		ink_frustum(pass,p+{0,.20,0},.09,.12,.28,6,0,DESCENT_GOLD,DESCENT_GOLD,{})
		ink_frustum(pass,p+{0,.48,0},.12,.25,.11,6,math.PI/6,DESCENT_GOLD,DESCENT_SAND_CAP,{})
		for side in ([2]f32{-1,1}) {cyber_strip(pass,p,{side*.31,.39,-.15},{side*.31,.39,.15},yaw,accent)}
	case .Memory:descent_obelisk(pass,p,1.92,yaw,accent)
	case .Trial,.Tunnel,.Boss:
	}
}

@(private)
descent_inferno_fixture :: proc(pass:Ink_Pass,p:rl.Vector3,site:^world.Site,accent:rl.Color) {
	yaw:=f32(site.orientation%4)*math.PI/2
	#partial switch site.kind {
	case .Nest:
		// Furnace mouth and short horns, visibly distinct from a loot chest.
		cyber_case(pass,p,{.45,.41},1.02,yaw,DESCENT_BASALT,DESCENT_BASALT_CAP)
		ink_box(pass,cyber_point(p,{0,.25,.418},yaw),{.29,.008},.55,yaw,DESCENT_EMBER,DESCENT_EMBER,{})
		for i in -1..=1 {ink_box(pass,cyber_point(p,{f32(i)*.17,.23,.432},yaw),{.025,.015},.61,yaw,DESCENT_IRON,DESCENT_IRON_CAP,{})}
		for side in ([2]f32{-1,1}) {
			ink_frustum(pass,cyber_point(p,{side*.27,1.02,0},yaw),.17,0,.49,5,0,DESCENT_BASALT,DESCENT_BASALT_CAP,{})
			cyber_strip(pass,p,{side*.09,.31,.445},{side*.09,.69,.445},yaw,accent)
		}
	case .Cache:
		cyber_case(pass,p,{.45,.39},.55,yaw,DESCENT_BASALT,DESCENT_BASALT_CAP)
		cyber_case(pass,p+{0,.55,0},{.45,.39},.19,yaw,DESCENT_IRON,DESCENT_IRON_CAP)
		for side in ([2]f32{-1,1}) {ink_box(pass,cyber_point(p,{side*.27,.10,.398},yaw),{.035,.008},.51,yaw,DESCENT_IRON,DESCENT_IRON_CAP,{})}
		cyber_strip(pass,p,{-.16,.46,.41},{.16,.46,.41},yaw,accent)
		cyber_strip(pass,p,{0,.30,.41},{0,.61,.41},yaw,accent)
	case .Archive:
		ink_frustum(pass,p,.46,.43,.15,6,math.PI/6,DESCENT_BASALT,DESCENT_BASALT_CAP,{})
		cyber_case(pass,p+{0,.15,0},{.34,.25},1.31,yaw,DESCENT_BASALT,DESCENT_BASALT_CAP)
		ink_box(pass,cyber_point(p,{0,.38,.257},yaw),{.25,.007},.80,yaw,DESCENT_DARK,DESCENT_DARK,{})
		cyber_strip(pass,p,{0,.46,.269},{0,1.13,.269},yaw,accent)
		for side in ([2]f32{-1,1}) {cyber_strip(pass,p,{0,.82,.269},{side*.19,1.04,.269},yaw,accent)}
	case .Workshop:
		// Smith's anvil next to a squat chimney; no decoration enters an aisle.
		descent_anvil(pass,p,yaw,true)
		cyber_case(pass,cyber_point(p,{-.25,0,-.25},yaw),{.17,.17},1.45,yaw,DESCENT_BASALT,DESCENT_BASALT_CAP)
		ink_box(pass,cyber_point(p,{-.25,1.45,-.25},yaw),{.20,.20},.12,yaw,DESCENT_IRON,DESCENT_IRON_CAP,{})
		cyber_strip(pass,p,{-.31,.99,-.072},{-.19,.99,-.072},yaw,accent)
	case .Spring:
		descent_basin(pass,p,.41,.41,DESCENT_BASALT,DESCENT_BASALT_CAP,{24,77,80,255})
		// Healing keeps the mint signal used by the other springs, rather
		// than disguising a usable source as damaging lava.
		if site.state!=.Resolved {
			ink_frustum(pass,p+{0,.43,0},.06,.15,.19,6,0,{84,181,151,255},{118,220,184,255},{})
			ink_frustum(pass,p+{0,.62,0},.15,0,.20,6,0,{84,181,151,255},{118,220,184,255},{})
		}
		for side in ([2]f32{-1,1}) {cyber_strip(pass,p,{side*.30,.42,-.12},{side*.30,.42,.12},yaw,ink_scale(accent,.55))}
	case .Memory:
		ink_frustum(pass,p,.44,.41,.16,6,0,DESCENT_BASALT,DESCENT_BASALT_CAP,{})
		for side in ([2]f32{-1,1}) {
			cyber_case(pass,cyber_point(p,{side*.19,.16,0},yaw),{.16,.23},1.22+side*.14,yaw,DESCENT_BASALT,DESCENT_BASALT_CAP)
			cyber_strip(pass,p,{side*.055,.26,.235},{side*.055,1.22+side*.14,.235},yaw,accent)
		}
	case .Trial,.Tunnel,.Boss:
	}
}

@(private)
descent_portal :: proc(pass:Ink_Pass,w:^world.World,p:rl.Vector3,yaw:f32,accent:rl.Color) {
	for side in ([2]f32{-1,1}) {
		q:=cyber_point(p,{side*2,0,0},yaw)
		#partial switch w.biome {
		case .West:
			ink_box(pass,q,{.43,.39},.18,yaw,DESCENT_IRON,DESCENT_IRON_CAP,{})
			ink_box(pass,q+{0,.18,0},{.32,.30},3.15,yaw,DESCENT_WOOD,DESCENT_WOOD_CAP,{})
			for y in ([3]f32{.30,1.31,2.71}) {ink_box(pass,q+{0,y,0},{.35,.33},.15,yaw,DESCENT_IRON,DESCENT_IRON_CAP,{})}
			for y in ([2]f32{2.13,2.46}) {
				descent_axle(pass,cyber_point(q,{0,y,.31},yaw),cyber_point(q,{0,y,.355},yaw),.12,DESCENT_IRON,DESCENT_GOLD)
				cyber_strip(pass,q,{-.075,y,.36},{.075,y,.36},yaw,accent)
			}
		case .Egypt:
			ink_box(pass,q,{.48,.45},.16,yaw,DESCENT_SAND,DESCENT_SAND_CAP,{})
			ink_frustum(pass,q+{0,.16,0},.60,.46,3.12,4,yaw+math.PI/4,DESCENT_SAND,DESCENT_SAND_CAP,{})
			ink_box(pass,q+{0,3.28,0},{.47,.42},.18,yaw,DESCENT_GOLD,DESCENT_SAND_CAP,{})
			cyber_strip(pass,q,{0,.55,.417},{0,2.70,.349},yaw,accent)
		case .Inferno:
			ink_frustum(pass,q,.47,.43,.18,6,0,DESCENT_BASALT,DESCENT_BASALT_CAP,{})
			ink_frustum(pass,q+{0,.18,0},.40,.33,3.12,6,yaw,DESCENT_BASALT,DESCENT_BASALT_CAP,{},shade=.12)
			ink_frustum(pass,q+{0,3.30,0},.33,0,.57,5,0,DESCENT_BASALT,DESCENT_BASALT_CAP,{})
			cyber_strip(pass,q,{-.09,.39,.348},{.05,1.72,.323},yaw,accent)
			cyber_strip(pass,q,{.05,1.72,.323},{-.05,3.11,.296},yaw,accent)
		}
	}
	fill,cap:=DESCENT_WOOD,DESCENT_WOOD_CAP
	if w.biome==.Egypt {fill,cap=DESCENT_SAND,DESCENT_SAND_CAP}
	if w.biome==.Inferno {fill,cap=DESCENT_BASALT,DESCENT_BASALT_CAP}
	// Actor-height geometry is confined to the two rotated layout supports.
	// Only this lintel and its ornament span the walkable portal opening.
	ink_box(pass,p+{0,3.23,0},{2.45,.33},.34,yaw,fill,cap,{})
	if w.biome==.West {
		ink_box(pass,p+{0,3.57,0},{1.00,.27},.20,yaw,DESCENT_IRON,DESCENT_IRON_CAP,{})
		for i in -2..=2 {ink_box(pass,cyber_point(p,{f32(i)*.28,3.64,.278},yaw),{.07,.008},.08,yaw,DESCENT_GOLD,DESCENT_GOLD,{})}
	} else if w.biome==.Egypt {
		ink_box(pass,p+{0,3.57,0},{2.47,.37},.13,yaw,DESCENT_GOLD,DESCENT_SAND_CAP,{})
		descent_axle(pass,cyber_point(p,{0,3.85,-.06},yaw),cyber_point(p,{0,3.85,.10},yaw),.21,DESCENT_GOLD,DESCENT_GOLD)
		for side in ([2]f32{-1,1}) {cyber_link(pass,cyber_point(p,{side*.19,3.82,0},yaw),cyber_point(p,{side*.76,3.74,0},yaw),{.035,.12},DESCENT_GOLD,DESCENT_SAND_CAP)}
	} else {
		for side in ([2]f32{-1,1}) {ink_frustum(pass,cyber_point(p,{side*.64,3.57,0},yaw),.22,0,.38,5,0,DESCENT_BASALT,DESCENT_BASALT_CAP,{})}
	}
	cyber_strip(pass,p,{-.71,3.39,.34},{.71,3.39,.34},yaw,{116,224,181,254} if w.boss_defeated else accent)
}

@(private)
draw_expedition_descent_fixture :: proc(pass:Ink_Pass,w:^world.World,site:^world.Site)->bool {
	if !descent_handles(w) {return false}
	p:=rl.Vector3{f32(site.position.x)+.5,0,f32(site.position.y)+.5}
	yaw:=f32(site.orientation%4)*math.PI/2;accent:=descent_accent(w,site)
	if site.kind==.Boss {descent_portal(pass,w,p,yaw,accent);return true}
	if site.kind==.Trial || site.kind==.Tunnel {
		// These centers are walkable in the authoritative layout. All detail
		// remains flush, including the closed mining hatch or ritual seal.
		fill:=DESCENT_WOOD if w.biome==.West else (DESCENT_SAND if w.biome==.Egypt else DESCENT_BASALT)
		ink_box(pass,p+{0,.008,0},{.44,.44},.009,yaw,fill,fill,{})
		if site.kind==.Tunnel {
			for i in 0..<4 {ink_box(pass,cyber_point(p,{0,.018,f32(i)*.18-.27},yaw),{.36,.025},.004,yaw,DESCENT_IRON,DESCENT_IRON_CAP,{})}
			cyber_strip(pass,p,{-.18,.024,.36},{.18,.024,.36},yaw,accent)
		} else {
			for i in 0..<4 {
				a:=f32(i)*math.PI/2+math.PI/4
				ink_line(pass,p+{math.cos(a)*.20,.024,math.sin(a)*.20},p+{math.cos(a)*.41,.024,math.sin(a)*.41},accent)
			}
		}
		return true
	}
	#partial switch w.biome {
	case .West:descent_west_fixture(pass,p,site,accent)
	case .Egypt:descent_egypt_fixture(pass,p,site,accent)
	case .Inferno:descent_inferno_fixture(pass,p,site,accent)
	}
	return true
}
