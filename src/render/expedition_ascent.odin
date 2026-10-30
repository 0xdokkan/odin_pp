package render

import "core:math"
import rl "vendor:raylib"
import campaign "../campaign"
import world "../expedition"
import game "../game"
import grid "../engine/grid"

// Static, allocation-free architecture. Emissive marks are deliberate signs
// and instruments; the broad faces remain solid materials in every Ink_Pass.
@(private)
Ascent_Material :: struct {body,cap,trim,dark,accent,secondary:rl.Color}
@(private)
ascent_material :: proc(b:campaign.Biome)->(m:Ascent_Material,ok:bool) {
	#partial switch b {
	case .City:return {{34,30,48,255},{59,54,73,255},{84,79,97,255},{12,16,29,255},{240,60,161,254},{65,207,226,254}},true
	case .Snow:return {{41,59,75,255},{111,133,146,255},{87,112,132,255},{20,34,48,255},{117,214,242,254},{222,185,119,254}},true
	case .Sky:return {{107,112,133,255},{137,140,146,255},{156,119,58,255},{45,52,76,255},{240,211,140,254},{231,157,202,254}},true
	case .Space:return {{29,29,51,255},{63,67,93,255},{91,105,127,255},{10,13,28,255},{126,96,242,254},{63,172,248,254}},true
	case .Secret:return {{19,19,29,255},{40,39,52,255},{133,100,43,255},{7,9,17,255},{208,174,92,254},{169,194,238,254}},true
	case:return {},false
	}
}

@(private)
ascent_mark :: proc(pass:Ink_Pass,base,a,b:rl.Vector3,yaw:f32,color:rl.Color) {
	ink_line(pass,cyber_point(base,a,yaw),cyber_point(base,b,yaw),color)
}

@(private)
ascent_panel :: proc(pass:Ink_Pass,base:rl.Vector3,yaw,height,width:f32,m:Ascent_Material,neon:rl.Color) {
	ink_box(pass,base,{width,.012},height,yaw,m.dark,m.dark,{})
	for row in 0..<3 {
		y:=height*(.22+f32(row)*.25)
		ascent_mark(pass,base,{-width*.70,y,.014},{width*(.6 if row!=1 else .1),y,.014},yaw,neon)
	}
}

// Layered, irregular five-sided rocks with a distinct upper material.
@(private)
ascent_rock :: proc(pass:Ink_Pass,p:rl.Vector3,radius,height,phase:f32,m:Ascent_Material,h:u32,snow:bool=false) {
	a,b,c:[5]rl.Vector3
	for i in 0..<5 {
		angle:=phase+f32(i)*math.TAU/5
		r:=radius*(.82+.035*f32((h>>u32(i*4))%5))
		o:=rl.Vector3{math.cos(angle)*r,0,math.sin(angle)*r}
		a[i]=p+o;b[i]=p+o*.88+{.03*radius,height*.63,-.02*radius}
		c[i]=p+o*.27+{-.06*radius,height,.08*radius}
	}
	ink_solid(pass,a[:],b[:],m.body,m.body,{},shade=.12)
	ink_solid(pass,b[:],c[:],m.cap,m.cap,{},shade=.13)
	if snow {
		for i in 0..<5 {a[i]=c[i];b[i]=c[i]+{0,.055,0}}
		ink_solid(pass,a[:],b[:],m.cap,m.cap,{})
	} else {ink_line(pass,b[1],c[1],ink_scale(m.accent,.5))}
}

@(private)
ascent_crystal :: proc(pass:Ink_Pass,p:rl.Vector3,radius,height,yaw:f32,m:Ascent_Material) {
	ink_frustum(pass,p,radius*.52,radius,height*.70,5,yaw,m.body,m.cap,{},shade=.13)
	ink_frustum(pass,p+{0,height*.70,0},radius,0,height*.30,5,yaw,m.cap,m.cap,{},shade=.16)
	a:=p+{math.cos(yaw)*radius*.52,0,math.sin(yaw)*radius*.52}
	b:=p+{math.cos(yaw)*radius,height*.70,math.sin(yaw)*radius}
	ink_line(pass,a,b,ink_scale(m.accent,.7))
}

// Compact theatre-flat skyline: readable roofs, recessed windows and one
// projecting sign, all inside the blocked square rather than across a lane.
@(private)
ascent_city_building :: proc(pass:Ink_Pass,p:rl.Vector3,height:f32,h:u32,m:Ascent_Material) {
	ink_box(pass,p,{.46,.45},height,0,m.body,m.cap,{})
	ink_box(pass,p+{0,height,0},{.48,.47},.09,0,m.trim,m.cap,{})
	ink_box(pass,p+{-.16,height+.09,-.10},{.18,.17},.26,0,m.dark,m.trim,{})
	ink_box(pass,p+{.25,height+.09,.18},{.09,.13},.13,0,m.trim,m.cap,{})
	for side in 0..<2 {
		yaw:=f32(side)*math.PI/2
		for row in 0..<3 {
			y:=.25+f32(row)*(height-.5)/3
			for col in 0..<2 {
				x:=f32(col)*.39-.20
				ink_box(pass,cyber_point(p,{x,y,.453},yaw),{.13,.003},.22,yaw,m.dark,m.dark,{})
				if (h+u32(row+col+side))%3==0 {ascent_mark(pass,p,{x-.09,y+.17,.459},{x+.09,y+.17,.459},yaw,m.secondary)}
			}
		}
	}
	ascent_panel(pass,p+{.30,.54,.47},0,min(height-.64,.75),.09,m,m.accent)
}

@(private)
ascent_column :: proc(pass:Ink_Pass,p:rl.Vector3,height,yaw:f32,m:Ascent_Material) {
	ink_box(pass,p,{.46,.46},.13,yaw,m.body,m.cap,{})
	ink_box(pass,p+{0,.13,0},{.35,.35},.10,yaw,m.trim,m.trim,{})
	ink_frustum(pass,p+{0,.23,0},.27,.235,max(height-.47,.10),8,yaw+math.PI/8,m.body,m.cap,{},shade=.08)
	ink_box(pass,p+{0,height-.24,0},{.35,.35},.12,yaw,m.trim,m.trim,{})
	ink_box(pass,p+{0,height-.12,0},{.46,.46},.12,yaw,m.cap,m.cap,{})
}

@(private)
ascent_cube :: proc(pass:Ink_Pass,p:rl.Vector3,half,height,yaw:f32,m:Ascent_Material) {
	ink_box(pass,p,{half,half},height,yaw,m.body,m.cap,{})
	ink_box(pass,p+{0,height*.18,0},{half+.008,half+.008},.045,yaw,m.trim,m.trim,{})
	ink_box(pass,p+{0,height-.07,0},{half+.008,half+.008},.045,yaw,m.trim,m.trim,{})
	ascent_mark(pass,p,{-half*.55,height*.54,half+.01},{half*.55,height*.54,half+.01},yaw,m.accent)
}

// The boulder on top of its hill (expedition/complex.odin, the Memoria's mark 'O'): Sisyphus' stone as the mount remembers
// it, grey and faceted, gold in its seams; a little higher than a cell, and wider in its middle than at its foot.
@(private)
draw_expedition_boulder :: proc(pass:Ink_Pass,cell:grid.Position) {
	p:=rl.Vector3{f32(cell.x)+.5,0,f32(cell.y)+.5}
	// As dark as the biome's own stone (Ascent_Material): its light makes it grey, a pale one burns to white.
	stone,cap:=rl.Color{46,44,54,255},rl.Color{68,65,74,255}
	gold:=ink_edge({243,203,115,255},.8)
	RINGS :: [4][2]f32{{.30,0},{.50,.36},{.42,.74},{.17,1.02}}
	rings:[4][6]rl.Vector3
	for ring,k in RINGS {
		for i in 0..<6 {
			angle:=.35+f32(i)*math.TAU/6+f32(k)*.27
			r:=ring[0]*(.9+.08*f32((i*7+k*3)%3))
			rings[k][i]=p+{math.cos(angle)*r,ring[1],math.sin(angle)*r}
		}
	}
	ink_solid(pass,rings[0][:],rings[1][:],stone,stone,{},shade=.14)
	ink_solid(pass,rings[1][:],rings[2][:],stone,stone,{},shade=.14)
	ink_solid(pass,rings[2][:],rings[3][:],cap,cap,{},shade=.12)
	// The seams: round its widest ring, and two up over it.
	for i in 0..<6 {ink_line(pass,rings[1][i],rings[1][(i+1)%6],gold)}
	for i in ([2]int{0,3}) {ink_line(pass,rings[1][i],rings[2][i],gold);ink_line(pass,rings[2][i],rings[3][i],gold)}
}

@(private)
draw_expedition_ascent_outdoor :: proc(pass:Ink_Pass,w:^world.World,cell:grid.Position)->bool {
	m,ok:=ascent_material(w.biome);if !ok {return false}
	if index,mark:=world.complex_at(w,cell);index>0 && mark=='O' {draw_expedition_boulder(pass,cell);return true}
	p:=rl.Vector3{f32(cell.x)+.5,0,f32(cell.y)+.5};h:=expedition_cell_hash(cell,u32(w.biome)+157)
	phase:=f32(h%17)*.23
	#partial switch w.biome {
	case .City:ascent_city_building(pass,p,1.6+f32((h>>5)%5)*.28,h,m)
	case .Snow:
		ascent_rock(pass,p+{-.06,0,-.04},.41,1.15+f32(h%5)*.27,phase,m,h,true)
		ascent_crystal(pass,p+{.27,0,.26},.17,.65+f32(h%3)*.14,phase,m)
		ascent_rock(pass,p+{-.28,0,.28},.16,.38,phase+.7,m,h>>4,true)
	case .Sky:
		if h%3==0 {
			ink_box(pass,p,{.45,.45},.20,0,m.body,m.cap,{})
			ascent_crystal(pass,p+{0,.66,0},.31,1.1,phase,m)
			for side in ([2]f32{-1,1}) {ink_box(pass,p+{side*.36,.20,0},{.055,.20},.47,0,m.trim,m.trim,{})}
		} else {ascent_column(pass,p,1.15+f32(h%5)*.33,0,m)}
	case .Space:
		ascent_rock(pass,p+{-.08,0,-.06},.38,.67+f32(h%3)*.15,phase,m,h)
		ascent_crystal(pass,p+{.20,.06,.21},.22,1.02+f32((h>>3)%4)*.25,phase,m)
		ascent_crystal(pass,p+{-.27,.04,.28},.13,.64,phase+.7,m)
	case .Secret:
		ink_box(pass,p,{.45,.45},.14,0,m.body,m.trim,{})
		ascent_cube(pass,p+{0,.14,0},.31,.74,math.PI/4,m)
		ascent_cube(pass,p+{0,1.12,0},.24,.48,0,m)
		if h%2==0 {ink_box(pass,p+{0,1.81,0},{.115,.115},.23,math.PI/4,m.trim,m.cap,{})}
	}
	return true
}

@(private)
draw_expedition_ascent_wall :: proc(pass:Ink_Pass,room:^game.Room,w:^world.World,site:^world.Site,cell:grid.Position,design:world.Site_Cell)->bool {
	m,ok:=ascent_material(w.biome);if !ok {return false}
	p:=rl.Vector3{f32(cell.x)+.5,0,f32(cell.y)+.5};height:=expedition_site_wall_height(design)
	h:=expedition_cell_hash(cell,u32(w.biome));yaw:=f32(site.orientation%4)*math.PI/2
	if w.biome==.Sky && (design.wall_height>=2.19 || (abs(design.local.x)+abs(design.local.y))%4==0) {
		ascent_column(pass,p,max(height,.85),yaw,m);return true
	}
	ink_box(pass,p,{.495,.495},height,0,m.body,m.cap,{})
	#partial switch w.biome {
	case .City:
		ink_box(pass,p+{0,height,0},{.498,.498},.08,0,m.trim,m.cap,{})
		if h%4==0 {ink_box(pass,p+{0,height+.08,0},{.24,.29},.19,0,m.dark,m.trim,{})}
	case .Snow:
		ink_box(pass,p+{0,height-.09,0},{.498,.498},.15,0,m.cap,m.cap,{})
		ink_box(pass,p,{.498,.498},.16,0,m.trim,m.trim,{})
	case .Sky:
		ink_box(pass,p+{0,height-.14,0},{.498,.498},.08,0,m.trim,m.trim,{})
		ink_box(pass,p+{0,height-.06,0},{.498,.498},.10,0,m.cap,m.cap,{})
	case .Space:
		ink_box(pass,p+{0,height-.10,0},{.46,.46},.16,0,m.trim,m.cap,{})
	case .Secret:
		ink_box(pass,p+{0,height-.10,0},{.498,.498},.06,0,m.trim,m.trim,{})
		ink_box(pass,p+{0,.16,0},{.498,.498},.035,0,m.trim,m.trim,{})
	}
	for direction in ([4]grid.Position{{x = 0, y = 1},{x = 1, y = 0},{x = 0, y = -1},{x = -1, y = 0}}) {
		if expedition_wall_joined(room,site,game.add_position(cell,direction),height) {continue}
		face:=math.atan2(f32(-direction.x),f32(direction.y))
		#partial switch w.biome {
		case .City:
			for row in 0..<2 {
				y:=.19+f32(row)*height*.36
				ink_box(pass,cyber_point(p,{0,y,.496},face),{.32,.002},height*.24,face,m.dark,m.dark,{})
				ascent_mark(pass,p,{-.24,y+.06,.499},{.20,y+.06,.499},face,m.secondary if h%3==0 else ink_scale(m.accent,.55))
			}
		case .Snow:
			for row in 0..<2 {ink_box(pass,cyber_point(p,{0,.24+f32(row)*height*.30,.496},face),{.42,.002},.07,face,m.trim,m.trim,{})}
			if h%4==0 {ascent_mark(pass,p,{-.12,.17,.499},{.14,height-.18,.499},face,m.accent)}
		case .Sky:
			ink_box(pass,cyber_point(p,{0,.20,.496},face),{.33,.002},max(height-.44,.12),face,m.dark,m.dark,{})
			ascent_mark(pass,p,{-.21,height-.20,.499},{.21,height-.20,.499},face,ink_scale(m.accent,.6))
		case .Space:
			ink_box(pass,cyber_point(p,{0,.22,.496},face),{.29,.002},max(height-.45,.12),face,m.dark,m.dark,{})
			ascent_mark(pass,p,{-.23,.30,.499},{.23,.30,.499},face,m.secondary)
			ascent_mark(pass,p,{-.23,.30,.499},{-.23,height-.25,.499},face,ink_scale(m.accent,.65))
		case .Secret:
			ink_box(pass,cyber_point(p,{0,.25,.496},face),{.27,.002},max(height-.52,.10),face,m.dark,m.dark,{})
			ascent_mark(pass,p,{-.14,height*.46,.499},{0,height*.63,.499},face,m.accent)
			ascent_mark(pass,p,{0,height*.63,.499},{.14,height*.46,.499},face,m.accent)
		}
	}
	return true
}

@(private)
draw_expedition_ascent_gate :: proc(pass:Ink_Pass,w:^world.World,pa,pb:rl.Vector3)->bool {
	m,ok:=ascent_material(w.biome);if !ok {return false}
	length:=rl.Vector3Distance(pa,pb);if length<.01 {return true}
	p:=(pa+pb)*.5;yaw:=math.atan2(pb.z-pa.z,pb.x-pa.x)
	ink_box(pass,p,{length*.5+.43,.34},.22,yaw,m.body,m.cap,{})
	#partial switch w.biome {
	case .City:
		ink_box(pass,p+{0,.22,0},{length*.5+.46,.40},.10,yaw,m.trim,m.cap,{})
		ascent_panel(pass,cyber_point(p,{0,.04,.355},yaw),yaw,.30,min(length*.28,1.25),m,m.accent)
	case .Snow:
		ink_box(pass,p+{0,.22,0},{length*.5+.46,.38},.10,yaw,m.cap,m.cap,{})
		for side in ([2]f32{-1,1}) {ascent_mark(pass,p,{side*(length*.5-.2),.04,.35},{side*(length*.5-.2),.20,.35},yaw,m.accent)}
	case .Sky:
		ink_box(pass,p+{0,.22,0},{length*.5+.46,.40},.08,yaw,m.trim,m.trim,{})
		ink_box(pass,p+{0,.30,0},{length*.5+.48,.43},.09,yaw,m.cap,m.cap,{})
		ascent_mark(pass,p,{-length*.25,.18,.345},{length*.25,.18,.345},yaw,m.accent)
	case .Space:
		for side in ([2]f32{-1,1}) {
			ink_box(pass,cyber_point(p,{side*length*.32,.22,0},yaw),{.23,.28},.15,yaw,m.trim,m.cap,{})
			ascent_mark(pass,p,{side*length*.32-.14,.17,.345},{side*length*.32+.14,.17,.345},yaw,m.secondary)
		}
	case .Secret:
		ink_box(pass,p+{0,.22,0},{length*.5+.45,.37},.06,yaw,m.trim,m.trim,{})
		for side in ([2]f32{-1,1}) {ascent_mark(pass,p,{side*.20,.05,.345},{side*.20,.18,.345},yaw,m.accent)}
	}
	return true
}

@(private)
ascent_plinth :: proc(pass:Ink_Pass,p:rl.Vector3,yaw:f32,m:Ascent_Material) {
	ink_box(pass,p,{.46,.44},.14,yaw,m.body,m.cap,{})
	ink_box(pass,p+{0,.14,0},{.34,.32},.14,yaw,m.trim,m.cap,{})
}

@(private)
ascent_book :: proc(pass:Ink_Pass,p:rl.Vector3,yaw:f32,m:Ascent_Material,small:bool=false) {
	r:=f32(.17) if small else .27
	for side in ([2]f32{-1,1}) {
		a:=cyber_point(p,{0,0,0},yaw);b:=cyber_point(p,{side*r,.05,0},yaw)
		cyber_link(pass,a,b,{.018,r*.68},m.cap,m.cap)
		ascent_mark(pass,p,{side*.04,.025,.03},{side*(r-.025),.065,.03},yaw,m.accent)
	}
}

@(private)
ascent_telescope :: proc(pass:Ink_Pass,p:rl.Vector3,yaw:f32,m:Ascent_Material,dish:bool=false) {
	ascent_plinth(pass,p,yaw,m)
	ink_frustum(pass,p+{0,.28,0},.12,.10,.60,6,yaw,m.trim,m.trim,{})
	if dish {
		a,b:[8]rl.Vector3;axis:=rl.Vector3{.16,.24,0};right,up:=cyber_link_basis({},axis)
		for i in 0..<8 {
			phase:=f32(i)*math.TAU/8;o:=right*math.cos(phase)+up*math.sin(phase)
			a[i]=cyber_point(p,{0,.90,0}+o*.08,yaw);b[i]=cyber_point(p,{0,.90,0}+axis+o*.27,yaw)
		}
		ink_solid(pass,a[:],b[:],m.trim,m.dark,{})
		cyber_link(pass,cyber_point(p,{.16,1.14,0},yaw),cyber_point(p,{.25,1.32,0},yaw),{.018,.018},m.trim,m.cap)
	} else {
		a:=cyber_point(p,{-.24,.94,-.10},yaw);b:=cyber_point(p,{.24,1.31,.10},yaw)
		cyber_link(pass,a,b,{.13,.12},m.body,m.trim)
		cyber_link(pass,b,cyber_point(p,{.27,1.333,.112},yaw),{.145,.135},m.dark,m.dark)
		ascent_mark(pass,p,{-.15,1.07,.01},{.15,1.30,.13},yaw,m.secondary)
	}
	ink_box(pass,cyber_point(p,{-.25,.34,.29},yaw),{.14,.05},.22,yaw,m.dark,m.cap,{})
}

@(private)
ascent_astrolabe :: proc(pass:Ink_Pass,p:rl.Vector3,yaw:f32,m:Ascent_Material) {
	ascent_plinth(pass,p,yaw,m)
	ink_frustum(pass,p+{0,.28,0},.18,.11,.44,6,yaw,m.body,m.trim,{})
	for i in 0..<8 {
		a,b:=f32(i)*math.TAU/8,f32(i+1)*math.TAU/8
		cyber_link(pass,cyber_point(p,{math.cos(a)*.31,1.10+math.sin(a)*.31,0},yaw),
			cyber_point(p,{math.cos(b)*.31,1.10+math.sin(b)*.31,0},yaw),{.025,.035},m.trim,m.trim)
	}
	ascent_crystal(pass,p+{0,.89,0},.11,.36,yaw,m)
}

@(private)
ascent_creator_archive :: proc(pass:Ink_Pass,p:rl.Vector3,yaw:f32,m:Ascent_Material) {
	ascent_plinth(pass,p,yaw,m)
	ink_box(pass,p+{0,.28,0},{.31,.27},.38,yaw,m.body,m.cap,{})
	ink_box(pass,p+{0,.66,0},{.44,.35},.08,yaw,m.trim,m.cap,{})
	ascent_book(pass,cyber_point(p,{-.19,.77,.07},yaw),yaw,m,true)
	// The creator's miniature robot stands beside the open record book.
	r:=cyber_point(p,{.22,.75,-.12},yaw)
	ink_box(pass,r,{.075,.065},.19,yaw,m.trim,m.trim,{})
	ink_box(pass,r+{0,.21,0},{.105,.09},.15,yaw,m.cap,m.cap,{})
	ascent_mark(pass,r,{-.065,.30,.095},{.065,.30,.095},yaw,m.secondary)
	for side in ([2]f32{-1,1}) {cyber_link(pass,cyber_point(r,{side*.10,.16,0},yaw),cyber_point(r,{side*.13,.04,0},yaw),{.025,.025},m.trim,m.trim)}
	for i in 0..<3 {ascent_mark(pass,p,{-.19,.37+f32(i)*.08,.275},{.19,.37+f32(i)*.08,.275},yaw,m.accent)}
}

@(private)
draw_expedition_ascent_fixture :: proc(pass:Ink_Pass,w:^world.World,site:^world.Site)->bool {
	m,ok:=ascent_material(w.biome);if !ok {return false}
	if site.state==.Resolved {m.accent=ink_scale(m.accent,.42);m.secondary=ink_scale(m.secondary,.55)}
	p:=rl.Vector3{f32(site.position.x)+.5,0,f32(site.position.y)+.5};yaw:=f32(site.orientation%4)*math.PI/2
	if site.kind==.Trial || site.kind==.Tunnel {
		ink_frustum(pass,p,.46,.46,.018,8,yaw+math.PI/8,m.body,m.cap,{})
		for i in 0..<3 {ascent_mark(pass,p,{-.30,.024,f32(i-1)*.18},{.30,.024,f32(i-1)*.18},yaw,m.accent if site.kind==.Trial else m.secondary)}
		return true
	}
	if site.kind==.Boss {
		for side in ([2]f32{-1,1}) {
			q:=cyber_point(p,{side*2,0,0},yaw)
			if w.biome==.Sky {ascent_column(pass,q,3.4,yaw,m)}
			else {
				ink_box(pass,q,{.46,.46},.22,yaw,m.body,m.trim,{})
				ink_box(pass,q+{0,.22,0},{.37,.36},2.98,yaw,m.body,m.cap,{})
				ink_box(pass,q+{0,3.20,0},{.47,.45},.20,yaw,m.trim,m.cap,{})
				ascent_mark(pass,q,{-side*.25,.43,.368},{-side*.25,3.06,.368},yaw,m.accent)
				if w.biome==.Snow {ascent_crystal(pass,q+{0,3.4,0},.25,.54,yaw,m)}
				if w.biome==.Secret {ascent_cube(pass,q+{0,3.4,0},.24,.42,yaw+math.PI/4,m)}
			}
		}
		_=draw_expedition_ascent_gate(pass,w,cyber_point(p,{-2,3.25,0},yaw),cyber_point(p,{2,3.25,0},yaw))
		return true
	}
	if site.kind==.Cache {
		ascent_plinth(pass,p,yaw,m)
		ink_box(pass,p+{0,.28,0},{.40,.35},.48,yaw,m.body,m.cap,{})
		ink_box(pass,p+{0,.76,0},{.43,.38},.12,yaw,m.cap,m.cap,{})
		for side in ([2]f32{-1,1}) {ink_box(pass,cyber_point(p,{side*.25,.35,.36},yaw),{.035,.018},.32,yaw,m.trim,m.trim,{})}
		ascent_mark(pass,p,{-.11,.60,.38},{.11,.60,.38},yaw,m.accent)
		if w.biome==.City {ascent_panel(pass,cyber_point(p,{0,.90,0},yaw),yaw,.43,.32,m,m.secondary)}
		if w.biome==.Snow {ascent_crystal(pass,cyber_point(p,{.28,.88,-.16},yaw),.12,.29,yaw,m)}
		if w.biome==.Sky {ink_frustum(pass,p+{0,.88,0},.28,0,.19,4,yaw+math.PI/4,m.trim,m.trim,{})}
		if w.biome==.Space {ink_box(pass,p+{0,.88,0},{.24,.18},.12,yaw,m.dark,m.trim,{})}
		if w.biome==.Secret {ascent_cube(pass,p+{0,.88,0},.16,.32,yaw+math.PI/4,m)}
		return true
	}
	if site.kind==.Spring {
		ink_frustum(pass,p,.46,.43,.18,8,yaw+math.PI/8,m.body,m.cap,{})
		ink_frustum(pass,p+{0,.18,0},.36,.39,.17,8,yaw+math.PI/8,m.trim,m.trim,{})
		ink_frustum(pass,p+{0,.351,0},.30,.30,.015,8,yaw+math.PI/8,m.dark,m.dark,{})
		if w.biome==.City || w.biome==.Space {
			ink_box(pass,cyber_point(p,{0,.36,-.20},yaw),{.09,.10},.47,yaw,m.body,m.cap,{})
			cyber_link(pass,cyber_point(p,{0,.80,-.20},yaw),cyber_point(p,{0,.80,.08},yaw),{.055,.055},m.trim,m.cap)
			ascent_mark(pass,p,{0,.76,.09},{0,.39,.09},yaw,m.secondary)
		} else {
			ascent_crystal(pass,p+{0,.58,0},.13,.38,yaw,m)
			for side in ([2]f32{-1,1}) {ascent_mark(pass,p,{side*.30,.40,-.12},{side*.30,.40,.12},yaw,m.accent)}
		}
		return true
	}
	#partial switch w.biome {
	case .City:
		ascent_plinth(pass,p,yaw,m)
		ink_box(pass,p+{0,.28,0},{.34,.30},.63,yaw,m.body,m.cap,{})
		if site.kind==.Workshop {
			ink_box(pass,p+{0,.91,0},{.43,.36},.08,yaw,m.trim,m.cap,{})
			for side in ([2]f32{-1,1}) {ink_frustum(pass,cyber_point(p,{side*.23,.99,0},yaw),.12,.12,.19,6,yaw,m.dark,m.trim,{})}
			cyber_link(pass,cyber_point(p,{-.25,1.23,.10},yaw),cyber_point(p,{.25,1.23,.10},yaw),{.04,.04},m.trim,m.cap)
		} else {
			ink_box(pass,cyber_point(p,{0,.91,-.09},yaw),{.34,.19},.61,yaw,m.body,m.cap,{})
			ascent_panel(pass,cyber_point(p,{0,1.03,.112},yaw),yaw,.33,.25,m,m.secondary if site.kind==.Archive else m.accent)
			ink_box(pass,cyber_point(p,{0,.88,.25},yaw),{.30,.08},.06,yaw,m.trim,m.cap,{})
			if site.kind==.Memory {for side in ([2]f32{-1,1}) {ink_box(pass,cyber_point(p,{side*.23,.42,.305},yaw),{.07,.008},.25,yaw,m.dark,m.dark,{})}}
			if site.kind==.Nest {ascent_mark(pass,p,{-.21,.50,.306},{.21,.50,.306},yaw,m.accent)}
		}
	case .Snow:
		ascent_plinth(pass,p,yaw,m)
		if site.kind==.Nest {
			ascent_crystal(pass,p+{0,.28,0},.31,1.25,yaw,m)
			ascent_crystal(pass,cyber_point(p,{.27,.28,.26},yaw),.13,.58,yaw+.3,m)
		} else if site.kind==.Workshop {
			ink_box(pass,p+{0,.28,0},{.33,.30},.70,yaw,m.body,m.cap,{})
			ascent_panel(pass,cyber_point(p,{0,.46,.313},yaw),yaw,.26,.23,m,m.secondary)
			for side in ([2]f32{-1,1}) {ink_box(pass,cyber_point(p,{side*.26,.98,0},yaw),{.045,.23},.09,yaw,m.trim,m.cap,{})}
		} else {
			for side in ([2]f32{-1,1}) {ink_box(pass,cyber_point(p,{side*.32,.28,0},yaw),{.075,.17},.83,yaw,m.body,m.trim,{})}
			ink_box(pass,p+{0,1.11,0},{.45,.29},.13,yaw,m.cap,m.cap,{})
			if site.kind==.Memory {ink_frustum(pass,p+{0,.77,0},.18,.09,.24,6,yaw,m.trim,m.cap,{})}
			else {ink_box(pass,p+{0,.35,0},{.23,.14},.55,yaw,m.trim,m.cap,{});ascent_book(pass,p+{0,.93,0},yaw,m)}
		}
	case .Sky:
		if site.kind==.Workshop {ascent_astrolabe(pass,p,yaw,m)}
		else {
			ascent_plinth(pass,p,yaw,m)
			ink_frustum(pass,p+{0,.28,0},.24,.18,.49,6,yaw,m.body,m.trim,{})
			if site.kind==.Archive {ink_box(pass,p+{0,.77,0},{.36,.25},.08,yaw,m.trim,m.cap,{});ascent_book(pass,p+{0,.89,0},yaw,m)}
			else if site.kind==.Memory {ascent_crystal(pass,p+{0,1.02,0},.22,.55,yaw,m)}
			else {ink_frustum(pass,p+{0,.77,0},.34,.27,.18,8,yaw,m.trim,m.cap,{});ascent_crystal(pass,p+{0,1.08,0},.10,.40,yaw,m)}
		}
	case .Space:
		if site.kind==.Archive || site.kind==.Memory {ascent_telescope(pass,p,yaw,m,site.kind==.Memory)}
		else {
			ascent_plinth(pass,p,yaw,m)
			ink_frustum(pass,p+{0,.28,0},.24,.18,.72,6,yaw,m.body,m.cap,{})
			if site.kind==.Workshop {
				for side in ([2]f32{-1,1}) {
					ink_box(pass,cyber_point(p,{side*.32,.89,0},yaw),{.13,.27},.04,yaw,m.dark,m.dark,{})
					ascent_mark(pass,p,{side*.32,.936,-.22},{side*.32,.936,.22},yaw,m.secondary)
				}
				cyber_link(pass,p+{0,1,0},p+{0,1.36,0},{.018,.018},m.trim,m.trim)
			} else {ascent_crystal(pass,p+{0,1.15,0},.21,.45,yaw,m)}
		}
	case .Secret:
		if site.kind==.Archive {ascent_creator_archive(pass,p,yaw,m)}
		else if site.kind==.Workshop {ascent_astrolabe(pass,p,yaw,m)}
		else {
			ascent_plinth(pass,p,yaw,m)
			ascent_cube(pass,p+{0,.28,0},.28,.60,yaw+math.PI/4,m)
			ascent_cube(pass,p+{0,1.04,0},.18,.36,yaw,m)
			if site.kind==.Memory {ascent_book(pass,p+{0,1.52,0},yaw,m,true)}
		}
	}
	return true
}
