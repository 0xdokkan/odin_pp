package render

import "core:c"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import campaign "../campaign"

// Curated workshop furniture dresses only cells already occupied by low
// cover. Cosmetic variants use the local column, never the simulation RNG.
// All geometry is baked into the existing chunk owner; no textures or new
// resources are allocated, and no part crosses the occupied square.
@(private)
draw_biome_workstation :: proc(pass:Ink_Pass,p:rl.Vector3,yaw:f32,biome:campaign.Biome,height:f32,column:int) {
	variant:=abs(column)%3
	#partial switch biome {
	case .West:
		if variant==0 {descent_barrel(pass,p,.41,height);return}
		// Trestle bench with an open undercut and a planed, thick worktop.
		for side in ([2]f32{-1,1}) {
			profile:=[6]rl.Vector2{{-.12,0},{-.07,.68},{.07,.68},{.12,0},{.055,0},{0,.39}}
			ink_profile(pass,cyber_point(p,{side*.28,0,0},yaw),profile[:],{1,height},.61,yaw,DESCENT_WOOD,DESCENT_WOOD_CAP,EXPEDITION_PAPER_INK)
		}
		ink_chamfer_box(pass,p+{0,height*.68,0},{.47,.42},height*.22,yaw,DESCENT_WOOD,DESCENT_WOOD_CAP,{},.035)
		grain:=[8]rl.Vector2{{-.38,-.22},{-.16,-.19},{.17,-.23},{.38,-.18},{.38,-.21},{.17,-.26},{-.16,-.22},{-.38,-.25}}
		biome_print_top(pass,p,grain[:],yaw,height*.90,{151,88,54,255})
		knot:=[4]rl.Vector2{{-.25,.18},{-.17,.13},{-.09,.18},{-.17,.21}}
		biome_print_top(pass,p,knot[:],yaw,height*.90,{173,107,61,255})
		if variant==1 {
			// A broad handsaw and its brass grip rest above the occupied bench.
			profile:=[6]rl.Vector2{{-.28,0},{-.24,.14},{.24,.14},{.30,.04},{.20,0},{-.10,.025}}
			ink_profile(pass,cyber_point(p,{0,height*.90,.09},yaw),profile[:],{1,1},.035,yaw,DESCENT_IRON_CAP,DESCENT_IRON,EXPEDITION_PAPER_INK)
			ink_chamfer_box(pass,cyber_point(p,{.29,height*.94,.08},yaw),{.075,.045},.11,yaw,DESCENT_GOLD,DESCENT_WOOD_CAP,{},.025)
		} else {
			ink_chamfer_box(pass,p+{0,height*.90,0},{.27,.24},.18,yaw,DESCENT_IRON,DESCENT_IRON_CAP,{},.06)
			descent_axle(pass,cyber_point(p,{-.28,height+.08,.25},yaw),cyber_point(p,{.28,height+.08,.25},yaw),.025,DESCENT_IRON,DESCENT_GOLD)
		}
	case .Egypt:
		// Broad carved shoulders, a single stone tablet and sculptor's pot.
		profile:=[8]rl.Vector2{{-.39,0},{-.31,.68},{-.46,.80},{-.46,1},{.46,1},{.46,.80},{.31,.68},{.39,0}}
		ink_profile(pass,p,profile[:],{1,height},.71,yaw,DESCENT_SAND,DESCENT_SAND_CAP,EXPEDITION_PAPER_INK)
		wing:=[6]rl.Vector2{{-.25,height*.55},{-.13,height*.60},{0,height*.47},{.13,height*.60},{.25,height*.55},{0,height*.34}}
		biome_print_face(pass,p,wing[:],yaw,.71,{156,115,62,255})
		biome_print_stroke(pass,p,{0,height*.18},{0,height*.38},.025,yaw,.71,{64,146,136,255})
		if variant==0 {ink_frustum(pass,p+{0,height,0},.20,.14,.25,7,yaw,DESCENT_GOLD,DESCENT_SAND_CAP,{})}
		else if variant==1 {tablet:=BIOME_TABLET;ink_profile(pass,p+{0,height,0},tablet[:],{.23,.38},.14,yaw,DESCENT_SAND_CAP,DESCENT_GOLD,{})}
		else {descent_axle(pass,cyber_point(p,{-.28,height+.04,0},yaw),cyber_point(p,{.25,height+.04,.06},yaw),.035,DESCENT_IRON,DESCENT_GOLD)}
	case .Inferno:
		profile:=[8]rl.Vector2{{-.43,0},{-.45,.72},{-.27,1},{.10,.91},{.32,1},{.45,.68},{.39,.20},{.40,0}}
		ink_profile(pass,p,profile[:],{1,height},.77,yaw,DESCENT_BASALT,DESCENT_BASALT_CAP,EXPEDITION_PAPER_INK)
		// A painted soot plume is tied to the furnace mouth, without glow.
		soot:=[5]rl.Vector2{{-.17,height*.69},{-.14,height*.86},{.02,height*.90},{.20,height*.82},{.15,height*.69}}
		biome_print_face(pass,p,soot[:],yaw,.77,{67,46,67,255})
		ink_chamfer_box(pass,cyber_point(p,{0,.18,.392},yaw),{.28,.012},height*.45,yaw,DESCENT_EMBER,DESCENT_EMBER,{},.07)
		for x in ([3]f32{-.17,0,.17}) {ink_box(pass,cyber_point(p,{x,.17,.415},yaw),{.025,.018},height*.49,yaw,DESCENT_IRON,DESCENT_IRON_CAP,{})}
		if variant==1 {ink_frustum(pass,cyber_point(p,{-.22,height*.93,-.19},yaw),.12,.10,.43,6,yaw,DESCENT_BASALT,DESCENT_BASALT_CAP,{})}
	case .Jungle:
		// Carved blocks have rounded shoulders and low moss leaves, not
		// miniature recoloured industrial cabinets.
		profile:=[8]rl.Vector2{{-.40,0},{-.46,.30},{-.41,.81},{-.23,1},{.25,.94},{.43,.78},{.46,.28},{.38,0}}
		ink_profile(pass,p,profile[:],{1,height},.73,yaw,{70,139,111,255},{181,206,124,255},EXPEDITION_PAPER_INK)
		carving:=[6]rl.Vector2{{-.24,height*.40},{-.21,height*.28},{0,height*.20},{.22,height*.29},{.24,height*.40},{0,height*.32}}
		biome_print_face(pass,p,carving[:],yaw,.73,{35,89,78,255})
		biome_print_stroke(pass,p,{-.23,height*.76},{-.04,height*.81},.026,yaw,.73,{151,189,113,255})
		if variant==1 {
			for x in ([2]f32{-.16,.16}) {ink_chamfer_box(pass,cyber_point(p,{x,height*.56,.374},yaw),{.085,.015},.09,yaw,{24,65,56,255},{24,65,56,255},{},.03)}
		} else {dread_leaf(pass,p+{0,height,0},.30,.14,yaw+.4,{95,173,78,255})}
	case .Vietnam:
		ink_chamfer_box(pass,p,{.43,.37},height*.76,yaw,{83,121,72,255},{193,193,114,255},{},.09)
		ink_chamfer_box(pass,p+{0,height*.76,0},{.45,.40},height*.18,yaw,{50,88,69,255},{167,180,109,255},{},.09)
		handle:=[4]rl.Vector2{{-.14,height*.39},{-.14,height*.51},{.14,height*.51},{.14,height*.39}}
		biome_print_face(pass,p,handle[:],yaw,.74,{39,68,53,255})
		biome_print_stroke(pass,p,{-.08,height*.46},{.08,height*.46},.025,yaw,.754,{169,173,105,255})
		if variant==1 {descent_axle(pass,cyber_point(p,{0,height*.94,-.20},yaw),cyber_point(p,{0,height*1.65,-.20},yaw),.018,{56,70,65,255},{170,186,121,255})}
		else {ink_chamfer_box(pass,cyber_point(p,{0,height*.94,.02},yaw),{.20,.21},.21,yaw,{138,150,83,255},{201,196,122,255},{},.08)}
	case .Gothic:
		profile:=[6]rl.Vector2{{-.43,0},{-.40,.73},{-.25,1},{.24,1},{.41,.73},{.43,0}}
		ink_profile(pass,p,profile[:],{1,height},.69,yaw,{107,100,145,255},{190,174,198,255},EXPEDITION_PAPER_INK)
		niche:=[5]rl.Vector2{{-.14,height*.17},{-.14,height*.52},{0,height*.70},{.14,height*.52},{.14,height*.17}}
		biome_print_face(pass,p,niche[:],yaw,.69,{70,62,99,255})
		biome_print_stroke(pass,p,{0,height*.26},{0,height*.52},.027,yaw,.705,{192,163,123,255})
		if variant==1 {
			ink_frustum(pass,p+{0,height,0},.23,.17,.20,7,yaw,{68,64,92,255},{156,129,163,255},{})
		} else {
			ink_chamfer_box(pass,p+{0,height,0},{.25,.21},.055,yaw,{150,82,89,255},{223,206,167,255},{},.03)
			for side in ([2]f32{-1,1}) {ink_box(pass,cyber_point(p,{side*.12,height+.055,0},yaw),{.105,.18},.025,yaw,{230,213,179,255},{230,213,179,255},{})}
		}
	case .City,.Snow,.Sky,.Space,.Secret:
		m,_:=ascent_material(biome)
		// Secondary instruments illuminate their own print, not the floor.
		m.accent=ink_scale(m.accent,.42);m.secondary=ink_scale(m.secondary,.50)
		if biome==.Snow {
			profile:=[9]rl.Vector2{{-.43,0},{-.47,.32},{-.43,.77},{-.26,.98},{.02,1.08},{.28,.98},{.44,.74},{.47,.30},{.41,0}}
			ink_profile(pass,p,profile[:],{1,height},.72,yaw,m.body,m.cap,EXPEDITION_PAPER_INK)
		glint:=[4]rl.Vector2{{-.31,height*.62},{-.25,height*.79},{.07,height*.89},{-.03,height*.74}}
		biome_print_face(pass,p,glint[:],yaw,.72,{187,223,223,255})
		biome_print_stroke(pass,p,{.15,height*.73},{.29,height*.82},.025,yaw,.72,{217,233,222,255})
			if variant==1 {ascent_crystal(pass,cyber_point(p,{-.14,height*.90,0},yaw),.13,.35,yaw,m)}
			else {ink_chamfer_box(pass,cyber_point(p,{0,height*.34,.368},yaw),{.24,.012},.20,yaw,m.dark,m.trim,{},.065)}
		} else if biome==.Sky {
			ink_frustum(pass,p,.32,.23,height*.74,8,yaw,m.body,m.cap,{})
			ink_frustum(pass,p+{0,height*.74,0},.23,.43,height*.20,8,yaw,m.trim,m.cap,{})
			ascent_book(pass,p+{0,height,0},yaw,m,variant==1)
		} else if biome==.Secret {
			ascent_cube(pass,p,.33,height,yaw,m)
			ascent_crystal(pass,p+{0,height,0},.13,.28,yaw,m)
		} else {
			ink_chamfer_box(pass,p,{.43,.37},height*.86,yaw,m.body,m.cap,{},.11)
			ink_chamfer_box(pass,p+{0,height*.86,0},{.45,.39},height*.13,yaw,m.trim,m.cap,{},.11)
			if biome==.City {ascent_panel(pass,cyber_point(p,{0,height*.26,.382},yaw),yaw,height*.39,.27,m,m.secondary)}
			else {
				ink_frustum(pass,p+{0,height,0},.24,.17,.25,8,yaw,m.dark,m.trim,{})
				dial:=[6]rl.Vector2{{-.18,height*.24},{-.25,height*.43},{-.15,height*.65},{.16,height*.65},{.25,height*.43},{.18,height*.24}}
				biome_print_face(pass,p,dial[:],yaw,.74,m.dark)
				biome_print_stroke(pass,p,{-.04,height*.34},{.10,height*.56},.026,yaw,.754,m.trim)
			}
		}
	}
}

@(private)
BIOME_TABLET :: [7]rl.Vector2{{-1,0},{-.94,.70},{-.66,.94},{0,1},{.73,.90},{.96,.65},{1,0}}

// Opaque pigment on a real front/back plane. Triangulate the authored
// polygon directly: no nested geometry, texture lifetime or light emission.
// The 6 mm separation avoids depth fighting at all supported world scales.
@(private)
biome_print_face :: proc(pass:Ink_Pass,base:rl.Vector3,outline:[]rl.Vector2,yaw,depth:f32,color:rl.Color) {
	if pass.mode!=.Fill && pass.mode!=.Bake {return}
	shape,n:=biome_print_clockwise(outline);indices,count:=ink_profile_triangles(shape[:n]);if count==0 {return}
	if pass.mode==.Fill {_=rlgl.CheckRenderBatchLimit(c.int(count*2));rlgl.Begin(rlgl.TRIANGLES)}
	for side in ([2]f32{-1,1}) {
		for i:=0;i<count;i+=3 {
			a,b,d:=shape[indices[i]],shape[indices[i+1]],shape[indices[i+2]]
			pa:=cyber_point(base,{a.x,a.y,side*(depth*.5+.006)},yaw)
			pb:=cyber_point(base,{b.x,b.y,side*(depth*.5+.006)},yaw)
			pd:=cyber_point(base,{d.x,d.y,side*(depth*.5+.006)},yaw)
			if side>0 {ink_triangle(pass,pa,pd,pb,color)} else {ink_triangle(pass,pa,pb,pd,color)}
		}
	}
	if pass.mode==.Fill {rlgl.End()}
}

@(private)
biome_print_top :: proc(pass:Ink_Pass,base:rl.Vector3,outline:[]rl.Vector2,yaw,height:f32,color:rl.Color) {
	if pass.mode!=.Fill && pass.mode!=.Bake {return}
	shape,n:=biome_print_clockwise(outline);indices,count:=ink_profile_triangles(shape[:n]);if count==0 {return}
	if pass.mode==.Fill {_=rlgl.CheckRenderBatchLimit(c.int(count));rlgl.Begin(rlgl.TRIANGLES)}
	for i:=0;i<count;i+=3 {
		a,b,d:=shape[indices[i]],shape[indices[i+1]],shape[indices[i+2]]
		ink_triangle(pass,cyber_point(base,{a.x,height+.006,a.y},yaw),
			cyber_point(base,{b.x,height+.006,b.y},yaw),cyber_point(base,{d.x,height+.006,d.y},yaw),color)
	}
	if pass.mode==.Fill {rlgl.End()}
}

@(private)
biome_print_stroke :: proc(pass:Ink_Pass,base:rl.Vector3,a,b:rl.Vector2,width,yaw,depth:f32,color:rl.Color) {
	d:=rl.Vector2Normalize(b-a);cross:=rl.Vector2{-d.y,d.x}*(width*.5)
	outline:=[4]rl.Vector2{a+cross,b+cross,b-cross,a-cross}
	biome_print_face(pass,base,outline[:],yaw,depth,color)
}

// Authored pigments may be read clockwise or counterclockwise on paper;
// normalize their winding before emission so both faces keep valid normals.
@(private)
biome_print_clockwise :: proc(outline:[]rl.Vector2)->(shape:[32]rl.Vector2,count:int) {
	count=len(outline);if count<3 || count>32 {count=0;return}
	area:=f32(0)
	for p,i in outline {q:=outline[(i+1)%count];area+=p.x*q.y-q.x*p.y}
	for p,i in outline {shape[i]=outline[count-1-i] if area>0 else p}
	return
}
