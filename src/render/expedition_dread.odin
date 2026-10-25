package render

import "core:math"
import rl "vendor:raylib"
import world "../expedition"
import game "../game"
import grid "../engine/grid"

// The fear route is built from bark, worn stone, field equipment and iron.
// Only moss, lamps and small indicators emit light. All geometry follows
// the same Ink_Pass path, including static-cache baking and light collection.
@(private)
Dread_Palette :: struct {stone,cap,wood,leaf,metal,dark,accent:rl.Color}

@(private)
dread_palette :: proc(w:^world.World)->(p:Dread_Palette,handled:bool) {
	if w==nil {return}
	#partial switch w.biome {
	case .Jungle:return {{57,66,48,255},{100,108,76,255},{65,49,33,255},{48,83,43,255},{142,137,102,255},{20,31,23,255},{157,194,69,254}},true
	case .Vietnam:return {{67,74,64,255},{110,115,91,255},{77,61,42,255},{61,85,43,255},{44,58,54,255},{19,28,25,255},{216,183,86,254}},true
	case .Gothic:return {{62,67,77,255},{112,119,125,255},{61,47,46,255},{66,87,70,255},{32,41,47,255},{17,21,29,255},{222,162,77,254}},true
	}
	return
}

// A four-sided pointed cap; unlike a collapsed top ring it emits no
// degenerate top triangles. It is also the roof of a lantern or tomb.
@(private)
dread_peak :: proc(pass:Ink_Pass,base:rl.Vector3,half:rl.Vector2,height,yaw:f32,fill:rl.Color) {
	a,b:[4]rl.Vector3
	for p,i in ([4]rl.Vector2{{-half.x,-half.y},{half.x,-half.y},{half.x,half.y},{-half.x,half.y}}) {
		a[i]=cyber_point(base,{p.x,0,p.y},yaw);b[i]=base+{0,height,0}
	}
	ink_solid(pass,a[:],b[:],fill,fill,{},apex=true,shade=.12)
}

@(private)
dread_leaf :: proc(pass:Ink_Pass,base:rl.Vector3,length,width,yaw:f32,color:rl.Color) {
	a,b:[4]rl.Vector3
	for q,i in ([4]rl.Vector3{{-width,0,0},{0,.07,-length},{width,0,0},{0,.04,length}}) {
		a[i]=cyber_point(base,q,yaw);b[i]=a[i]+{0,.025,0}
	}
	ink_solid(pass,a[:],b[:],ink_scale(color,.70),color,{})
}

@(private)
dread_lantern :: proc(pass:Ink_Pass,base:rl.Vector3,p:Dread_Palette) {
	ink_box(pass,base,{.075,.075},.045,0,p.metal,p.cap,{})
	glass:=rl.Color{p.accent.r,p.accent.g,p.accent.b,255}
	ink_box(pass,base+{0,.045,0},{.048,.048},.15,0,ink_scale(glass,.55),glass,{})
	dread_peak(pass,base+{0,.195,0},{.09,.09},.085,0,p.metal)
	ink_line(pass,base+{-.032,.075,.051},base+{.032,.165,.051},p.accent)
}

@(private)
dread_jungle_tree :: proc(pass:Ink_Pass,base:rl.Vector3,h:u32,p:Dread_Palette) {
	height:=2.25+f32(h%5)*.16;phase:=f32(h%13)*.27
	ink_frustum(pass,base,.18,.10,height*.86,5,phase,p.wood,ink_scale(p.wood,1.2),{},.18)
	for i in 0..<3 {
		a:=phase+f32(i)*math.TAU/3;d:=rl.Vector3{math.cos(a),0,math.sin(a)}
		cyber_link(pass,base+d*.34+{0,.07,0},base+d*.11+{0,.64,0},{.065,.06},p.wood,p.cap)
	}
	// A broad, flat-topped umbrella with offset lateral lobes. There is no
	// stack of conical crowns or apex: the prehistoric tree reads as a
	// spreading canopy, while its entire footprint still fits one cell.
	crown:=base+rl.Vector3{math.cos(phase)*.025,height*.82,math.sin(phase)*.025}
	leaf:=p.leaf
	for i in 0..<3 {
		a:=phase+f32(i)*math.TAU/3+.25;d:=rl.Vector3{math.cos(a),0,math.sin(a)}
		cyber_link(pass,base+{0,height*.57,0},crown+d*.29+{0,-.05,0},{.04,.045},p.wood,p.cap)
		if i<2 {
			at:=crown+d*.23+{0,-.13-f32(i)*.07,0}
			ink_frustum(pass,at,.13,.20,.09,5,a,ink_scale(leaf,.88),leaf,{},.16)
			ink_frustum(pass,at+{0,.09,0},.20,.13,.11,5,a,leaf,ink_scale(leaf,1.3),{},.12)
		}
		// Individual radial fronds break the polygonal rim without extending
		// into neighbouring walkable cells or becoming another cone tier.
		dread_leaf(pass,crown+d*.07+{0,.10,0},.37,.105,a+math.PI/2,ink_scale(leaf,1.3+f32(i%2)*.15))
	}
	ink_frustum(pass,crown,.31,.44,.12,7,phase,ink_scale(leaf,.88),leaf,{},.18)
	ink_frustum(pass,crown+{0,.12,0},.44,.32,.14,7,phase,leaf,ink_scale(leaf,1.4),{},.15)
}

@(private)
dread_jungle_fern :: proc(pass:Ink_Pass,base:rl.Vector3,h:u32,p:Dread_Palette) {
	ink_frustum(pass,base,.31,.18,.43,5,f32(h%7),p.stone,p.cap,{},.2)
	ink_frustum(pass,base+{0,.39,0},.07,.035,.7,5,0,p.wood,p.leaf,{})
	for i in 0..<5 {
		yaw:=f32(i)*math.TAU/5+f32(h%5)*.15
		dread_leaf(pass,base+{0,.65+f32(i%2)*.14,0},.45,.105,yaw,ink_scale(p.leaf,1.1+f32(i%2)*.3))
	}
	if h%3==0 {ink_line(pass,base+{-.18,.28,.24},base+{.16,.33,.25},p.accent)}
}

@(private)
dread_bamboo :: proc(pass:Ink_Pass,base:rl.Vector3,h:u32,p:Dread_Palette) {
	for i in 0..<3 {
		pos:=base+rl.Vector3{f32(i-1)*.18,0,.12 if i==1 else -.12}
		height:=1.9+f32((h>>u32(i*3))%5)*.2
		ink_frustum(pass,pos,.055,.04,height,5,f32(i),p.leaf,p.cap,{})
		for j in 1..<4 {ink_frustum(pass,pos+{0,height*f32(j)*.23,0},.064,.064,.035,5,f32(i),p.cap,p.cap,{})}
		dread_leaf(pass,pos+{0,height*.78,0},.25,.045,f32(i)*1.2,p.leaf)
		dread_leaf(pass,pos+{0,height*.94,0},.21,.04,f32(i)*1.2+.7,ink_scale(p.leaf,1.35))
	}
}

@(private)
dread_palm :: proc(pass:Ink_Pass,base:rl.Vector3,h:u32,p:Dread_Palette) {
	height:=2.15+f32(h%4)*.19
	ink_frustum(pass,base,.105,.065,height,6,.2,p.wood,p.cap,{},.14)
	for i in 0..<5 {
		a:=f32(i)*math.TAU/5
		dread_leaf(pass,base+{0,height-.13+f32(i%2)*.08,0},.46,.075,a,p.leaf)
	}
}

@(private)
dread_crate :: proc(pass:Ink_Pass,base:rl.Vector3,yaw:f32,p:Dread_Palette,stack:bool=false) {
	ink_box(pass,base,{.44,.39},.52,yaw,p.wood,p.cap,{})
	for side in ([2]f32{-1,1}) {
		ink_box(pass,cyber_point(base,{side*.27,0,.395},yaw),{.035,.009},.53,yaw,p.metal,p.metal,{})
		ink_box(pass,cyber_point(base,{side*.27,.52,0},yaw),{.035,.40},.025,yaw,p.metal,p.metal,{})
	}
	if stack {
		ink_box(pass,cyber_point(base,{-.13,.545,-.07},yaw),{.25,.26},.34,yaw,p.stone,p.cap,{})
		ink_box(pass,cyber_point(base,{-.13,.67,.195},yaw),{.13,.008},.10,yaw,p.cap,p.cap,{})
	} else {ink_box(pass,cyber_point(base,{0,.23,.406},yaw),{.11,.009},.11,yaw,p.cap,p.cap,{})}
}

@(private)
dread_grave :: proc(pass:Ink_Pass,base:rl.Vector3,yaw:f32,p:Dread_Palette,cross:bool=false) {
	ink_box(pass,base,{.42,.32},.16,yaw,p.stone,p.cap,{})
	if cross {
		ink_box(pass,base+{0,.16,0},{.065,.08},1.37,yaw,p.wood,p.cap,{})
		ink_box(pass,base+{0,1.07,0},{.35,.07},.12,yaw,p.wood,p.cap,{})
		ink_box(pass,cyber_point(base,{0,.32,.083},yaw),{.018,.006},1.10,yaw,p.cap,p.cap,{})
	} else {
		ink_box(pass,base+{0,.16,0},{.28,.13},.82,yaw,p.stone,p.cap,{})
		dread_peak(pass,base+{0,.98,0},{.28,.13},.29,yaw,p.cap)
		ink_box(pass,cyber_point(base,{0,.41,.136},yaw),{.015,.006},.40,yaw,p.dark,p.dark,{})
		ink_box(pass,cyber_point(base,{0,.66,.136},yaw),{.12,.006},.035,yaw,p.dark,p.dark,{})
	}
}

@(private)
dread_dead_tree :: proc(pass:Ink_Pass,base:rl.Vector3,h:u32,p:Dread_Palette) {
	ink_frustum(pass,base,.16,.065,1.9,5,f32(h%7),p.wood,p.cap,{})
	for side in ([2]f32{-1,1}) {
		cyber_link(pass,base+{0,.85,0},base+{side*.32,1.36,.13},{.045,.055},p.wood,p.cap)
		cyber_link(pass,base+{side*.32,1.36,.13},base+{side*.37,1.72,.08},{.025,.035},p.wood,p.cap)
	}
	cyber_link(pass,base+{0,1.49,0},base+{.17,2.2,-.18},{.035,.04},p.wood,p.cap)
}

@(private)
draw_expedition_dread_outdoor :: proc(pass:Ink_Pass,w:^world.World,cell:grid.Position)->bool {
	p,handled:=dread_palette(w);if !handled {return false}
	base:=rl.Vector3{f32(cell.x)+.5,0,f32(cell.y)+.5}
	h:=expedition_cell_hash(cell,u32(w.biome)+0xD3)
	#partial switch w.biome {
	case .Jungle:
		if h%4==0 {dread_jungle_fern(pass,base,h,p)} else {dread_jungle_tree(pass,base,h,p)}
	case .Vietnam:
		if h%7==0 {dread_crate(pass,base,0,p,true)}
		else if h%7==1 {dread_palm(pass,base,h,p)} else {dread_bamboo(pass,base,h,p)}
	case .Gothic:
		if h%4==0 {dread_dead_tree(pass,base,h,p)}
		else {dread_grave(pass,base,0 if h%2==0 else math.PI/2,p,h%3==0)}
	}
	return true
}

@(private)
dread_sandbags :: proc(pass:Ink_Pass,base:rl.Vector3,height,yaw:f32,p:Dread_Palette) {
	ink_box(pass,base,{.48,.43},.10,yaw,p.dark,p.stone,{})
	for row in 0..<3 {for side in ([2]f32{-1,1}) {
		x:=side*.24;y:=.10+f32(row)*(height-.1)/3
		bag:=p.cap if row%2==0 else ink_scale(p.cap,.83)
		ink_box(pass,cyber_point(base,{x,y,0},yaw),{.23,.42-f32(row)*.025},(height-.1)/3-.018,yaw,bag,ink_scale(bag,1.08),{})
		ink_box(pass,cyber_point(base,{x,y+.07,.425-f32(row)*.025},yaw),{.15,.005},.012,yaw,p.wood,p.wood,{})
	}}
}

@(private)
draw_expedition_dread_wall :: proc(pass:Ink_Pass,room:^game.Room,w:^world.World,site:^world.Site,cell:grid.Position,design:world.Site_Cell)->bool {
	p,handled:=dread_palette(w);if !handled {return false}
	base:=rl.Vector3{f32(cell.x)+.5,0,f32(cell.y)+.5};q:=design.local
	yaw:=f32(site.orientation%4)*math.PI/2
	height:=expedition_site_wall_height(design)
	gate:=abs(design.wall_height-2.2)<.01
	if gate {height=2.12}
	if w.biome==.Vietnam && height<1.15 && !design.fixture {
		dread_sandbags(pass,base,max(height,.55),yaw,p);return true
	}
	if w.biome==.Jungle && site.kind==.Nest && height<1.1 {
		ink_box(pass,base,{.47,.45},.16,0,p.stone,p.cap,{})
		for side in ([2]f32{-1,1}) {
			cyber_link(pass,cyber_point(base,{side*.28,.16,-.20},yaw),cyber_point(base,{side*.20,height+.15,.20},yaw),{.10,.085},p.metal,p.cap)
		}
		return true
	}
	wooden:=w.biome==.Gothic && (site.kind==.Workshop || site.kind==.Nest)
	stone:=p.wood if wooden else p.stone
	ink_box(pass,base,{.49,.49},height,0,stone,p.cap,{})
	ink_box(pass,base,{.495,.495},.10,0,p.dark,p.stone,{})
	ink_box(pass,base+{0,height-.08,0},{.495,.495},.10,0,p.cap,p.cap,{})
	for direction,i in ([4]grid.Position{{x = 0, y = 1},{x = 1, y = 0},{x = 0, y = -1},{x = -1, y = 0}}) {
		if expedition_wall_joined(room,site,game.add_position(cell,direction),expedition_site_wall_height(design)) {continue}
		face:=math.atan2(f32(-direction.x),f32(direction.y))
		// The camera-facing exposed faces carry the small details. Back faces
		// retain the same complete material and cap without redundant inserts.
		if i>=2 {continue}
		if w.biome==.Jungle {
			ink_box(pass,cyber_point(base,{0,height*.44,.494},face),{.47,.003},.025,face,p.dark,p.dark,{})
			ink_box(pass,cyber_point(base,{-.17,height*.71,.495},face),{.012,.003},height*.24,face,p.dark,p.dark,{})
			if (abs(q.x)+abs(q.y))%3==0 {
				cyber_link(pass,cyber_point(base,{-.28,.15,.45},face),cyber_point(base,{-.08,height-.12,.45},face),{.025,.025},p.wood,p.leaf)
				ink_line(pass,cyber_point(base,{.16,height-.06,.498},face),cyber_point(base,{.34,height-.06,.498},face),ink_scale(p.accent,.55))
			}
		} else if w.biome==.Vietnam {
			ink_box(pass,cyber_point(base,{0,height*.61,.494},face),{.32,.003},.13,face,p.dark,p.dark,{})
			ink_box(pass,cyber_point(base,{0,height*.61-.035,.495},face),{.36,.003},.035,face,p.cap,p.cap,{})
			if gate {ink_box(pass,cyber_point(base,{-.28,.30,.495},face),{.035,.003},.26,face,p.wood,p.wood,{})}
		} else if wooden {
			for x in ([3]f32{-.30,0,.30}) {ink_box(pass,cyber_point(base,{x,.13,.494},face),{.012,.003},height-.26,face,p.dark,p.dark,{})}
			cyber_link(pass,cyber_point(base,{-.40,.22,.46},face),cyber_point(base,{.40,height-.20,.46},face),{.025,.025},p.cap,p.wood)
		} else {
			ink_box(pass,cyber_point(base,{0,.25,.494},face),{.20,.003},height*.48,face,p.dark,p.dark,{})
			ink_box(pass,cyber_point(base,{0,.25,.498},face),{.016,.001},height*.48,face,p.metal,p.metal,{})
			dread_peak(pass,cyber_point(base,{0,.25+height*.48,.493},face),{.20,.004},height*.18,face,p.dark)
		}
	}
	return true
}

@(private)
draw_expedition_dread_gate :: proc(pass:Ink_Pass,w:^world.World,a,b:rl.Vector3)->bool {
	p,handled:=dread_palette(w);if !handled {return false}
	mid:=(a+b)*.5;length:=rl.Vector3Distance(a,b);axis:=rl.Vector3Normalize(b-a)
	yaw:=math.atan2(axis.z,axis.x)
	if w.biome==.Jungle {
		cyber_link(pass,a-{axis.x*.36,0,axis.z*.36},b+{axis.x*.36,0,axis.z*.36},{.16,.20},p.wood,p.cap)
		for side in ([2]f32{-1,1}) {
			pos:=cyber_point(mid,{side*(length*.5-.25),.19,0},yaw)
			dread_leaf(pass,pos,.30,.11,yaw+.4,p.leaf)
		}
	} else if w.biome==.Vietnam {
		ink_box(pass,mid,{length*.5+.39,.29},.20,yaw,p.wood,p.cap,{})
		ink_box(pass,mid+{0,.20,0},{length*.5+.42,.34},.055,yaw,p.metal,p.cap,{})
		dread_lantern(pass,cyber_point(mid,{length*.5-.12,-.22,.16},yaw),p)
	} else {
		peak:=mid+{0,.58,0}
		cyber_link(pass,a-axis*.35,peak,{.12,.21},p.wood,p.cap)
		cyber_link(pass,peak,b+axis*.35,{.12,.21},p.wood,p.cap)
		ink_box(pass,mid,{length*.5+.37,.16},.10,yaw,p.stone,p.cap,{})
		for side in ([2]f32{-1,1}) {dread_lantern(pass,cyber_point(mid,{side*(length*.5-.06),-.22,0},yaw),p)}
	}
	return true
}

@(private)
dread_idol :: proc(pass:Ink_Pass,base:rl.Vector3,yaw:f32,p:Dread_Palette) {
	ink_box(pass,base,{.44,.42},.17,yaw,p.stone,p.cap,{})
	ink_box(pass,base+{0,.17,0},{.28,.25},.68,yaw,p.stone,p.cap,{})
	ink_box(pass,base+{0,.85,0},{.35,.29},.43,yaw,p.stone,p.cap,{})
	ink_box(pass,base+{0,1.28,0},{.38,.31},.10,yaw,p.cap,p.cap,{})
	for side in ([2]f32{-1,1}) {
		ink_box(pass,cyber_point(base,{side*.18,1.04,.295},yaw),{.085,.007},.065,yaw,p.dark,p.dark,{})
	}
	ink_line(pass,cyber_point(base,{-.09,.95,.30},yaw),cyber_point(base,{.09,.95,.30},yaw),p.accent)
}

@(private)
dread_radio :: proc(pass:Ink_Pass,base:rl.Vector3,yaw:f32,p:Dread_Palette,archive:bool) {
	ink_box(pass,base,{.44,.40},.14,yaw,p.metal,p.cap,{})
	ink_box(pass,base+{0,.14,0},{.37,.31},1.20 if archive else .67,yaw,p.stone,p.cap,{})
	if archive {
		for i in 0..<4 {
			y:=.25+f32(i)*.25
			ink_box(pass,cyber_point(base,{0,y,.315},yaw),{.31,.007},.18,yaw,p.wood,p.cap,{})
			ink_box(pass,cyber_point(base,{0,y+.07,.325},yaw),{.095,.005},.04,yaw,p.cap,p.cap,{})
		}
	} else {
		for i in 0..<3 {ink_box(pass,cyber_point(base,{-.10,.30+f32(i)*.10,.316},yaw),{.18,.006},.025,yaw,p.dark,p.dark,{})}
		ink_box(pass,cyber_point(base,{.24,.39,.316},yaw),{.065,.006},.17,yaw,p.cap,p.cap,{})
		for side in ([2]f32{-1,1}) {cyber_link(pass,cyber_point(base,{side*.27,.80,-.16},yaw),cyber_point(base,{side*.31,1.58,-.16},yaw),{.012,.012},p.metal,p.cap)}
		ink_line(pass,cyber_point(base,{.20,.50,.326},yaw),cyber_point(base,{.28,.50,.326},yaw),p.accent)
	}
}

@(private)
dread_boss :: proc(pass:Ink_Pass,w:^world.World,base:rl.Vector3,yaw:f32,p:Dread_Palette) {
	for side in ([2]f32{-1,1}) {
		at:=cyber_point(base,{side*2,0,0},yaw)
		ink_box(pass,at,{.47,.45},.22,yaw,p.stone,p.cap,{})
		ink_box(pass,at+{0,.22,0},{.35,.32},3.10,yaw,p.wood if w.biome==.Vietnam else p.stone,p.cap,{})
		ink_box(pass,at+{0,3.10,0},{.43,.42},.22,yaw,p.cap,p.cap,{})
		if w.biome==.Jungle {
			for y in ([2]f32{1.1,2.1}) {ink_box(pass,cyber_point(at,{0,y,.326},yaw),{.24,.008},.16,yaw,p.dark,p.dark,{})}
			cyber_link(pass,cyber_point(at,{-side*.22,.25,-.23},yaw),cyber_point(at,{-side*.15,2.95,-.23},yaw),{.055,.06},p.wood,p.leaf)
		} else {
			dread_lantern(pass,cyber_point(at,{0,2.55,.37},yaw),p)
			if w.biome==.Gothic {ink_box(pass,cyber_point(at,{0,.60,.326},yaw),{.025,.008},1.5,yaw,p.metal,p.metal,{})}
		}
	}
	if w.biome==.Gothic {
		a,b:=cyber_point(base,{-2,3.32,0},yaw),cyber_point(base,{2,3.32,0},yaw)
		top:=base+{0,4.08,0}
		cyber_link(pass,a,top,{.12,.22},p.stone,p.cap);cyber_link(pass,top,b,{.12,.22},p.stone,p.cap)
		ink_frustum(pass,base+{0,3.35,0},.23,.12,.30,6,0,p.metal,p.cap,{})
	} else {
		ink_box(pass,base+{0,3.23,0},{2.44,.34},.30,yaw,p.wood,p.cap,{})
		if w.biome==.Jungle {ink_box(pass,base+{0,3.53,0},{.37,.29},.28,yaw,p.metal,p.cap,{})}
		else {ink_box(pass,base+{0,3.53,0},{.26,.21},.19,yaw,p.metal,p.cap,{})}
	}
}

@(private)
draw_expedition_dread_fixture :: proc(pass:Ink_Pass,w:^world.World,site:^world.Site)->bool {
	p,handled:=dread_palette(w);if !handled {return false}
	base:=rl.Vector3{f32(site.position.x)+.5,0,f32(site.position.y)+.5};yaw:=f32(site.orientation%4)*math.PI/2
	if site.state==.Resolved {p.accent=ink_scale(p.accent,.45)}
	if site.secret {p.accent={229,202,127,254}}
	if site.kind==.Boss {dread_boss(pass,w,base,yaw,p);return true}
	if site.kind==.Trial || site.kind==.Tunnel {
		ink_box(pass,base,{.44,.44},.018,yaw,p.dark,p.stone,{})
		if site.kind==.Trial {
			ink_frustum(pass,base+{0,.018,0},.34,.34,.006,6,yaw,p.cap,p.cap,{})
			for side in ([2]f32{-1,1}) {ink_line(pass,cyber_point(base,{-.20,.026,side*.20},yaw),cyber_point(base,{.20,.026,side*.20},yaw),p.accent)}
		} else {
			for i in 0..<4 {ink_box(pass,cyber_point(base,{0,.018,f32(i-2)*.15},yaw),{.35,.018},.006,yaw,p.wood,p.cap,{})}
		}
		return true
	}
	if site.kind==.Cache {
		if w.biome==.Vietnam {dread_crate(pass,base,yaw,p,true)}
		else if w.biome==.Jungle {
			ink_frustum(pass,base,.44,.37,.43,6,yaw,p.wood,p.cap,{})
			ink_box(pass,base+{0,.43,0},{.41,.33},.07,yaw,p.wood,p.cap,{})
			for side in ([2]f32{-1,1}) {cyber_link(pass,cyber_point(base,{side*.26,.07,-.27},yaw),cyber_point(base,{side*.26,.55,.27},yaw),{.035,.04},p.metal,p.cap)}
		} else {
			ink_box(pass,base,{.44,.36},.43,yaw,p.stone,p.cap,{})
			dread_peak(pass,base+{0,.43,0},{.45,.37},.23,yaw,p.cap)
			ink_box(pass,cyber_point(base,{0,.14,.367},yaw),{.018,.006},.25,yaw,p.metal,p.metal,{})
			ink_box(pass,cyber_point(base,{0,.29,.367},yaw),{.13,.006},.035,yaw,p.metal,p.metal,{})
		}
		return true
	}
	#partial switch w.biome {
	case .Jungle:
		#partial switch site.kind {
		case .Archive:dread_idol(pass,base,yaw,p)
		case .Memory:
			ink_box(pass,base,{.42,.35},.15,yaw,p.stone,p.cap,{})
			ink_box(pass,cyber_point(base,{-.12,.15,0},yaw),{.20,.17},1.31,yaw,p.stone,p.cap,{})
			ink_box(pass,cyber_point(base,{.23,.15,0},yaw),{.14,.17},.73,yaw,p.stone,p.cap,{})
			for i in 0..<3 {ink_line(pass,cyber_point(base,{-.25,.47+f32(i)*.23,.18},yaw),cyber_point(base,{.01,.47+f32(i)*.23,.18},yaw),ink_scale(p.accent,.6))}
		case .Nest:
			ink_frustum(pass,base,.46,.30,.32,8,0,p.wood,p.wood,{})
			for i in 0..<3 {
				a:=f32(i)*math.TAU/3;at:=base+rl.Vector3{math.cos(a)*.19,.28,math.sin(a)*.19}
				ink_frustum(pass,at,.10,.14,.18,5,a,p.metal,p.cap,{})
				ink_frustum(pass,at+{0,.18,0},.14,0,.19,5,a,p.metal,p.cap,{})
			}
		case .Workshop:
			ink_frustum(pass,base,.36,.29,.62,6,0,p.wood,p.cap,{})
			ink_box(pass,base+{0,.62,0},{.45,.37},.11,yaw,p.wood,p.cap,{})
			cyber_link(pass,cyber_point(base,{-.20,.74,0},yaw),cyber_point(base,{.18,1.30,0},yaw),{.035,.04},p.wood,p.cap)
			dread_peak(pass,cyber_point(base,{.15,1.10,0},yaw),{.19,.08},.28,yaw,p.metal)
		case .Spring:
			ink_frustum(pass,base,.46,.40,.22,8,math.PI/8,p.stone,p.cap,{})
			ink_frustum(pass,base+{0,.22,0},.32,.32,.018,8,math.PI/8,p.leaf,p.leaf,{})
			for i in 0..<3 {dread_leaf(pass,base+{0,.28+f32(i)*.11,0},.27,.075,f32(i)*1.1,ink_scale(p.leaf,1.3))}
		}
	case .Vietnam:
		#partial switch site.kind {
		case .Archive:dread_radio(pass,base,yaw,p,true)
		case .Nest:dread_radio(pass,base,yaw,p,false)
		case .Memory:
			// A field memorial: empty boots, an upright marker and a helmet.
			// It reads differently from the nest's active radio equipment.
			ink_box(pass,base,{.42,.36},.13,yaw,p.stone,p.cap,{})
			ink_box(pass,base+{0,.13,0},{.045,.06},1.11,yaw,p.wood,p.cap,{})
			for side in ([2]f32{-1,1}) {ink_box(pass,cyber_point(base,{side*.16,.13,.12},yaw),{.095,.17},.18,yaw,p.metal,p.cap,{})}
			ink_frustum(pass,base+{0,1.18,0},.28,.28,.055,8,yaw,p.metal,p.cap,{})
			ink_frustum(pass,base+{0,1.235,0},.235,.12,.17,8,yaw,p.stone,p.cap,{})
			ink_box(pass,cyber_point(base,{0,.83,.069},yaw),{.055,.008},.11,yaw,p.cap,p.cap,{})
		case .Spring:
			ink_box(pass,base,{.43,.40},.14,yaw,p.wood,p.cap,{})
			ink_frustum(pass,base+{0,.14,0},.32,.32,.76,8,0,p.stone,p.cap,{})
			for y in ([2]f32{.29,.73}) {ink_frustum(pass,base+{0,y,0},.333,.333,.045,8,0,p.metal,p.cap,{})}
			cyber_link(pass,cyber_point(base,{0,.29,.30},yaw),cyber_point(base,{0,.29,.43},yaw),{.04,.04},p.metal,p.cap)
		case .Workshop:
			ink_box(pass,base,{.43,.37},.18,yaw,p.wood,p.cap,{})
			ink_box(pass,base+{0,.18,0},{.35,.28},.45,yaw,p.metal,p.cap,{})
			for x in ([3]f32{-.22,0,.22}) {ink_frustum(pass,cyber_point(base,{x,.63,0},yaw),.085,.085,.30,6,0,p.stone,p.cap,{})}
			cyber_link(pass,cyber_point(base,{-.40,.45,.30},yaw),cyber_point(base,{.40,.45,.30},yaw),{.045,.045},p.metal,p.cap)
		}
	case .Gothic:
		#partial switch site.kind {
		case .Memory:dread_grave(pass,base,yaw,p,true)
		case .Nest:
			ink_box(pass,base,{.41,.32},.15,yaw,p.stone,p.cap,{})
			ink_box(pass,base+{0,.15,0},{.28,.21},1.12,yaw,p.wood,p.cap,{})
			dread_peak(pass,base+{0,1.27,0},{.28,.21},.28,yaw,p.wood)
			ink_box(pass,cyber_point(base,{0,.42,.218},yaw),{.025,.006},.65,yaw,p.metal,p.metal,{})
			ink_box(pass,cyber_point(base,{0,.85,.218},yaw),{.18,.006},.045,yaw,p.metal,p.metal,{})
			dread_lantern(pass,cyber_point(base,{.31,.15,.24},yaw),p)
		case .Archive:
			ink_box(pass,base,{.38,.35},.14,yaw,p.stone,p.cap,{})
			ink_box(pass,base+{0,.14,0},{.12,.13},.68,yaw,p.wood,p.cap,{})
			ink_box(pass,base+{0,.82,0},{.42,.29},.07,yaw,p.wood,p.wood,{})
			for side in ([2]f32{-1,1}) {ink_box(pass,cyber_point(base,{side*.19,.89,0},yaw),{.175,.24},.045,yaw,p.cap,p.cap,{})}
			ink_box(pass,base+{0,.90,0},{.015,.24},.05,yaw,p.metal,p.metal,{})
		case .Workshop:
			ink_box(pass,base,{.44,.41},.55,yaw,p.stone,p.cap,{})
			ink_box(pass,base+{0,.55,0},{.32,.28},.04,yaw,p.dark,p.dark,{})
			ink_box(pass,cyber_point(base,{-.25,.55,-.24},yaw),{.13,.12},1.04,yaw,p.wood,p.cap,{})
			for x in ([3]f32{-.16,0,.16}) {ink_box(pass,cyber_point(base,{x,.59,.13},yaw),{.07,.07},.06,yaw,{101,49,34,255},p.cap,{})}
			ink_line(pass,cyber_point(base,{-.15,.655,.19},yaw),cyber_point(base,{.15,.655,.19},yaw),{199,76,42,254})
		case .Spring:
			ink_frustum(pass,base,.45,.45,.44,8,math.PI/8,p.stone,p.cap,{})
			ink_frustum(pass,base+{0,.44,0},.31,.31,.012,8,math.PI/8,p.dark,p.dark,{})
			for side in ([2]f32{-1,1}) {ink_box(pass,cyber_point(base,{side*.33,.1,0},yaw),{.04,.06},1.15,yaw,p.wood,p.cap,{})}
			ink_box(pass,base+{0,1.25,0},{.42,.08},.09,yaw,p.wood,p.cap,{})
			cyber_link(pass,base+{0,.53,0},base+{0,1.25,0},{.012,.012},p.metal,p.metal)
		}
	}
	return true
}
