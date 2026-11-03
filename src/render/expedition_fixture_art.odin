package render

import rl "vendor:raylib"
import campaign "../campaign"
import world "../expedition"

// Original pixel drawings composed from the same authored convex print
// pieces as the actors. These are rasterized drawings, never screenshots of
// the solid renderer. Upload once; only the two-frame source rect changes.
FIXTURE_CELL :: CARTOON_CELL
FIXTURE_COLUMNS :: 12
FIXTURE_FRAMES :: 2
FIXTURE_KINDS :: 6
FIXTURE_COUNT :: 96
Expedition_Fixture_Assets :: struct {
	print,paper:rl.Texture2D,
	hero_print,hero_paper:rl.Texture2D,
	hero_mask:[CYBER_PRESS_WIDTH*CYBER_PRESS_HEIGHT]u8,
	west_mask:[CYBER_PRESS_WIDTH*CYBER_PRESS_HEIGHT]u8,
	hero_bounds:rl.Rectangle,
	west_bounds:rl.Rectangle,
	secondary_bounds:[3]rl.Rectangle,
	west_secondary_bounds:[3]rl.Rectangle,
	mask:[FIXTURE_COUNT][FIXTURE_CELL*FIXTURE_CELL]u8,
	top:[FIXTURE_COUNT]int,
}
Fixture_Art_Palette :: struct { light,body,shade,accent,signal:rl.Color }

@(private)
fixture_art_palette :: proc(b:campaign.Biome)->Fixture_Art_Palette {
	palettes:=[12]Fixture_Art_Palette{
		{{255,231,174,255},{33,137,198,255},{28,65,99,255},{239,83,65,255},{62,222,233,255}},
		{{244,207,140,255},{183,113,59,255},{104,66,48,255},{54,156,154,255},{245,178,53,255}},
		{{210,221,139,255},{93,150,112,255},{39,84,73,255},{233,143,60,255},{163,208,73,255}},
		{{244,219,171,255},{210,111,87,255},{68,75,101,255},{50,164,171,255},{247,194,74,255}},
		{{255,230,170,255},{214,167,88,255},{146,103,58,255},{44,156,155,255},{76,113,172,255}},
		{{224,213,140,255},{122,153,77,255},{49,89,68,255},{209,105,62,255},{232,192,91,255}},
		{{234,245,224,255},{117,194,212,255},{64,119,158,255},{228,109,104,255},{248,204,104,255}},
		{{245,184,139,255},{104,76,101,255},{57,44,68,255},{242,110,58,255},{255,207,78,255}},
		{{225,204,197,255},{130,110,151,255},{67,54,96,255},{183,78,101,255},{235,182,91,255}},
		{{255,238,192,255},{135,184,207,255},{67,105,148,255},{225,175,74,255},{234,127,114,255}},
		{{232,225,216,255},{134,128,178,255},{53,63,107,255},{83,204,215,255},{238,137,117,255}},
		{{241,231,176,255},{133,186,148,255},{80,76,115,255},{233,185,83,255},{217,139,178,255}},
	}
	return palettes[clamp(int(b),0,11)]
}

@(private)
fixture_art_index :: proc(b:campaign.Biome,kind:world.Site_Kind)->int {
	slot:=-1
	#partial switch kind {
	case .Nest:slot=0
	case .Cache:slot=1
	case .Archive:slot=2
	case .Workshop:slot=3
	case .Spring:slot=4
	case .Memory:slot=5
	}
	return clamp(int(b),0,11)*FIXTURE_KINDS+slot if slot>=0 else -1
}
@(private)
fixture_machine_art_index :: proc(b:campaign.Biome,bench:bool)->int {return 72+clamp(int(b),0,11)*2+(1 if bench else 0)}

@(private)
fixture_round :: proc(m:^Expedition_Paper,x,y,w,h:f32,fill,shade,light:rl.Color) {
	c:=min(w,h)*.12
	p:=[8]rl.Vector2{{x+c,y},{x+w-c,y+c*.4},{x+w,y+c*1.4},{x+w,y+h-c},
		{x+w-c,y+h},{x+c,y+h-c*.45},{x,y+h-c*1.45},{x,y+c}}
	paper_polygon(m,p[:],fill)
	// A sloped top and a broad right-hand plane are drawn into the pixels;
	// the world still receives a single flat cutout.
	right:=[4]rl.Vector2{{x+w*.75,y+c},{x+w-c*.4,y+c*1.4},{x+w-c*.4,y+h-c},{x+w*.75,y+h-c*1.7}}
	top:=[4]rl.Vector2{{x+c,y+h-c*1.5},{x+w*.75,y+h-c*1.7},{x+w-c,y+h-c*.4},{x+c,y+h-c*.45}}
	paper_polygon(m,right[:],shade,false);paper_polygon(m,top[:],light,false)
}

@(private)
fixture_wood_print :: proc(m:^Expedition_Paper,y:f32,p:Fixture_Art_Palette) {
	paper_limb(m,{-.34,y+.10},{-.11,y+.12},.018,p.shade,false)
	paper_limb(m,{-.08,y+.12},{.12,y+.08},.018,p.shade,false)
	paper_limb(m,{.16,y+.09},{.33,y+.10},.018,p.shade,false)
	paper_disc(m,.19,y+.25,.055,.028,p.shade,false)
	paper_disc(m,.19,y+.25,.026,.012,p.light,false)
}

@(private)
fixture_leaf_print :: proc(m:^Expedition_Paper,x,y,side:f32,p:Fixture_Art_Palette) {
	paper_limb(m,{x,0},{x+side*.035,y+.24},.03,p.shade)
	a:=[4]rl.Vector2{{x,y},{x-side*.06,y+.15},{x+side*.20,y+.27},{x+side*.22,y+.10}}
	paper_polygon(m,a[:],p.body)
	paper_limb(m,{x,y+.03},{x+side*.15,y+.20},.018,p.signal,false)
}

// Grounded bodies differ in silhouette and construction, not only pigment.
@(private)
fixture_body_print :: proc(m:^Expedition_Paper,b:campaign.Biome,p:Fixture_Art_Palette) {
	ink:=EXPEDITION_PAPER_INK
	switch b {
	case .Cyber:
		for side in ([2]f32{-1,1}) {fixture_round(m,side*.31-.10,0,.20,.17,p.shade,p.shade,p.body)}
		fixture_round(m,-.43,.12,.86,.64,p.light,p.body,EXPEDITION_PAPER_EDGE)
		paper_box(m,-.30,.23,.53,.33,p.body)
		paper_box(m,.33,.31,.06,.23,p.accent,false)
	case .West:
		for side in ([2]f32{-1,1}) {paper_limb(m,{side*.40,.02},{side*.29,.67},.11,p.shade)}
		fixture_round(m,-.44,.24,.88,.38,p.body,p.shade,p.light)
		fixture_wood_print(m,.27,p)
		paper_box(m,-.49,.61,.98,.09,p.light)
	case .Jungle:
		p0:=[8]rl.Vector2{{-.40,0},{-.47,.15},{-.42,.54},{-.28,.71},{.27,.68},{.44,.50},{.47,.12},{.36,0}}
		paper_polygon(m,p0[:],p.body)
		paper_tri(m,{.21,.03},{.43,.16},{.38,.51},p.shade,false)
		paper_limb(m,{-.27,.55},{-.04,.59},.04,p.light,false)
		fixture_leaf_print(m,-.40,.03,-1,p);fixture_leaf_print(m,.36,.04,1,p)
	case .City:
		for side in ([2]f32{-1,1}) {paper_disc(m,side*.32,.08,.105,.08,ink);paper_disc(m,side*.32,.08,.045,.035,p.light,false)}
		fixture_round(m,-.44,.14,.88,.53,p.body,p.shade,p.light)
		paper_box(m,-.34,.30,.64,.20,p.shade)
		paper_limb(m,{-.16,.40},{.12,.40},.035,p.light,false)
	case .Egypt:
		pillar:=[6]rl.Vector2{{-.43,0},{-.32,.58},{-.46,.72},{.46,.72},{.32,.58},{.43,0}}
		foot:=[4]rl.Vector2{pillar[0],pillar[1],pillar[4],pillar[5]}
		crown:=[4]rl.Vector2{pillar[1],pillar[2],pillar[3],pillar[4]}
		paper_polygon(m,foot[:],p.body);paper_polygon(m,crown[:],p.body)
		paper_tri(m,{.26,0},{.43,0},{.32,.58},p.shade,false)
		paper_box(m,-.44,.62,.88,.07,p.light,false)
		wing:=[6]rl.Vector2{{-.28,.42},{-.12,.46},{0,.32},{.12,.46},{.28,.42},{0,.18}}
		// The two halves are convex and leave a clean central carving.
		paper_tri(m,wing[0],wing[1],wing[5],p.accent,false)
		paper_tri(m,wing[3],wing[4],wing[5],p.accent,false)
		paper_disc(m,0,.36,.055,.055,p.signal)
	case .Vietnam:
		for side in ([2]f32{-1,1}) {
			paper_limb(m,{side*.37,0},{side*.32,.73},.075,p.body)
			for y in ([3]f32{.12,.32,.53}) {paper_box(m,side*.35-.045,y,.09,.035,p.light,false)}
		}
		paper_box(m,-.43,.53,.86,.12,p.light)
		fixture_round(m,-.32,.17,.64,.34,p.body,p.shade,p.light)
		paper_box(m,-.25,.23,.50,.07,p.shade,false)
	case .Snow:
		ice:=[8]rl.Vector2{{-.41,0},{-.49,.20},{-.44,.56},{-.23,.76},{.08,.80},{.39,.62},{.49,.24},{.39,0}}
		paper_polygon(m,ice[:],p.body)
		paper_tri(m,{-.43,.18},{-.23,.70},{-.10,.47},p.light,false)
		paper_tri(m,{.13,.08},{.39,.04},{.44,.55},p.shade,false)
		paper_limb(m,{-.17,.14},{-.04,.32},.025,p.light,false)
	case .Inferno:
		forge:=[8]rl.Vector2{{-.40,0},{-.48,.10},{-.45,.52},{-.29,.70},{.26,.70},{.46,.48},{.48,.10},{.38,0}}
		paper_polygon(m,forge[:],p.body)
		fixture_round(m,-.28,.12,.56,.37,p.shade,p.shade,p.accent)
		paper_disc(m,-.02,.27,.17,.13,p.accent,false)
		for x in ([3]f32{-.16,0,.16}) {paper_box(m,x-.02,.14,.04,.30,ink,false)}
		paper_limb(m,{-.26,.59},{.22,.59},.035,p.light,false)
	case .Gothic:
		for side in ([2]f32{-1,1}) {paper_box(m,side*.34-.07,0,.14,.24,p.shade)}
		fixture_round(m,-.43,.15,.86,.51,p.body,p.shade,p.light)
		niche:=[5]rl.Vector2{{-.21,.22},{-.21,.43},{0,.59},{.21,.43},{.21,.22}}
		paper_polygon(m,niche[:],p.shade)
		paper_disc(m,0,.34,.04,.05,p.accent,false)
	case .Sky:
		for side in ([2]f32{-1,1}) {paper_limb(m,{side*.39,0},{side*.18,.60},.09,p.accent)}
		paper_disc(m,0,.48,.34,.19,p.body)
		paper_disc(m,-.04,.51,.24,.10,p.light,false)
		paper_box(m,-.44,.63,.88,.09,p.accent)
	case .Space:
		for side in ([2]f32{-1,1}) {fixture_round(m,side*.31-.09,0,.18,.22,p.shade,p.shade,p.accent)}
		fixture_round(m,-.42,.14,.84,.56,p.light,p.body,EXPEDITION_PAPER_EDGE)
		paper_disc(m,-.04,.40,.24,.20,p.shade)
		paper_disc(m,-.04,.40,.16,.13,p.body,false)
		paper_box(m,.30,.32,.06,.22,p.accent,false)
	case .Secret:
		root:=[7]rl.Vector2{{-.43,0},{-.45,.33},{-.25,.58},{-.03,.48},{.19,.70},{.43,.32},{.39,0}}
		// Two crystalline convex masses deliberately meet above the floor.
		paper_polygon(m,root[:4],p.shade)
		paper_tri(m,root[0],root[3],root[6],p.shade)
		paper_polygon(m,root[3:],p.body)
		paper_limb(m,{-.28,.12},{-.14,.36},.035,p.accent,false)
		paper_limb(m,{.12,.17},{.25,.40},.035,p.light,false)
	case .Count:
	}
}

@(private)
fixture_display_print :: proc(m:^Expedition_Paper,x,y,w,h:f32,p:Fixture_Art_Palette,tick:int) {
	fixture_round(m,x-.035,y-.035,w+.07,h+.07,p.shade,p.shade,p.light)
	paper_box(m,x,y,w,h,p.signal,false)
	paper_box(m,x+w*.12,y+h*.68,w*.27,.025,p.light,false)
	paper_limb(m,{x+w*.12,y+h*.22},{x+w*.35,y+h*.51},.025,p.shade,false)
	paper_limb(m,{x+w*.35,y+h*.51},{x+w*.54,y+h*.32},.025,p.shade,false)
	paper_limb(m,{x+w*.54,y+h*.32},{x+w*.83,y+h*(.57 if tick==0 else .72)},.025,p.shade,false)
}

@(private)
fixture_book_print :: proc(m:^Expedition_Paper,x,y,scale:f32,p:Fixture_Art_Palette) {
	left:=[4]rl.Vector2{{x-.34*scale,y},{x-.31*scale,y+.24*scale},{x,y+.17*scale},{x,y-.07*scale}}
	right:=[4]rl.Vector2{{x,y-.07*scale},{x,y+.17*scale},{x+.31*scale,y+.25*scale},{x+.34*scale,y}}
	paper_polygon(m,left[:],p.light);paper_polygon(m,right[:],EXPEDITION_PAPER_EDGE)
	for i in 0..<2 {
		z:=y+(.04+f32(i)*.07)*scale
		paper_limb(m,{x-.23*scale,z+.04*scale},{x-.06*scale,z},.015,p.shade,false)
		paper_limb(m,{x+.06*scale,z},{x+.24*scale,z+.04*scale},.015,p.shade,false)
	}
}

@(private)
fixture_workshop_print :: proc(m:^Expedition_Paper,b:campaign.Biome,p:Fixture_Art_Palette,tick:int,variant:int) {
	if variant==2 && b!=.Cyber {
		// The neighbouring service bench is a different drawing, not another
		// copy of the central machine: storage plus a place-specific tool.
		if b==.West || b==.Vietnam {
			paper_limb(m,{-.32,.73},{.23,.88},.11,p.shade)
			paper_disc(m,.24,.89,.11,.10,p.accent)
			paper_disc(m,.24,.89,.055,.045,p.light,false)
			fixture_round(m,-.34,.74,.22,.26,p.body,p.shade,p.light)
		} else if b==.Gothic || b==.Sky {
			fixture_book_print(m,-.05,.81,1,p)
			paper_disc(m,.34,.80,.075,.10,p.accent)
		} else if b==.Jungle || b==.Egypt || b==.Snow || b==.Secret {
			tablet:=[5]rl.Vector2{{-.30,.71},{-.32,.99},{-.10,1.10},{.16,.98},{.20,.71}}
			paper_polygon(m,tablet[:],p.light)
			paper_limb(m,{-.18,.82},{.08,.92},.04,p.accent,false)
			paper_disc(m,.33,.79,.10,.10,p.body)
		} else {
			fixture_round(m,-.32,.72,.41,.30,p.body,p.shade,p.light)
			paper_disc(m,-.11,.88,.11,.10,p.shade)
			paper_limb(m,{-.11,.88},{-.05,.93},.025,p.light,false)
			paper_limb(m,{.22,.74},{.35,1.02},.07,p.accent)
		}
		return
	}
	switch b {
	case .Cyber:
		if variant==2 {
			fixture_round(m,-.38,.68,.76,.48,p.body,p.shade,p.light)
			paper_limb(m,{-.17,.76},{-.17,1.04},.06,p.light)
			paper_disc(m,-.17,1.04,.08,.07,p.light);paper_box(m,-.20,1.07,.06,.05,p.body,false)
			paper_limb(m,{.13,.78},{.22,1.04},.065,p.accent)
			paper_box(m,-.34,.67,.68,.07,p.accent)
			break
		}
		if variant==0 {fixture_display_print(m,-.22,.26,.36,.21,p,tick)}
		paper_limb(m,{.26,.73},{.12,1.30},.15,p.accent)
		paper_limb(m,{.12,1.30},{-.28,1.11},.13,p.accent)
		paper_limb(m,{-.28,1.11},{-.30,.91},.09,p.body)
		for point in ([3]rl.Vector2{{.26,.75},{.12,1.30},{-.28,1.11}}) {
			paper_disc(m,point.x,point.y,.105,.095,p.shade)
			paper_disc(m,point.x-.015,point.y+.012,.055,.05,p.light,false)
		}
		for side in ([2]f32{-1,1}) {paper_limb(m,{-.30+side*.035,.94},{-.30+side*.085,.85},.04,p.shade)}
		paper_limb(m,{.20,.88},{.11,1.20},.028,p.light,false)
	case .West:
		anvil:=[6]rl.Vector2{{-.42,.79},{-.48,.96},{.42,.96},{.28,.84},{.13,.81},{-.14,.79}}
		paper_polygon(m,anvil[:],p.shade)
		paper_box(m,-.17,.70,.34,.11,p.shade)
		paper_limb(m,{-.35,.97},{.25,.97},.025,p.light,false)
		paper_limb(m,{.27,.86},{.11,1.31},.055,p.body)
		fixture_round(m,-.03,1.24,.32,.13,p.shade,p.shade,p.light)
	case .Jungle:
		paper_limb(m,{-.20,.73},{.15,1.29},.10,p.shade)
		paper_disc(m,.17,1.30,.10,.07,p.light)
		bowl:=[6]rl.Vector2{{-.36,.94},{-.28,.72},{-.13,.67},{.20,.67},{.33,.74},{.40,.94}}
		paper_polygon(m,bowl[:],p.light)
		paper_disc(m,.02,.93,.37,.07,p.shade)
		paper_limb(m,{-.22,.76},{.13,.74},.028,p.body,false)
		fixture_leaf_print(m,.38,.75,-1,p)
	case .City:
		fixture_round(m,-.40,.68,.74,.47,p.light,p.body,EXPEDITION_PAPER_EDGE)
		fixture_display_print(m,-.30,.80,.40,.23,p,tick)
		paper_limb(m,{.34,.73},{.47,1.22},.055,p.shade)
		paper_disc(m,.47,1.25,.075,.075,p.accent)
		paper_box(m,-.24,.70,.44,.04,p.shade,false)
	case .Egypt:
		paper_limb(m,{.25,.72},{.08,1.24},.055,p.body)
		paper_box(m,-.04,1.20,.25,.12,p.shade)
		statue:=[6]rl.Vector2{{-.28,.73},{-.35,1.07},{-.22,1.29},{.02,1.33},{.18,1.07},{.13,.73}}
		paper_polygon(m,statue[:],p.light)
		paper_disc(m,-.08,1.14,.13,.10,p.body)
		paper_limb(m,{-.18,1.14},{-.06,1.14},.035,p.signal,false)
		paper_box(m,-.22,.87,.29,.08,p.accent,false)
	case .Vietnam:
		fixture_round(m,-.35,.67,.70,.43,p.body,p.shade,p.light)
		paper_limb(m,{.20,1.08},{.28,1.44},.025,p.shade)
		fixture_display_print(m,-.26,.83,.32,.17,p,tick)
		for y in ([3]f32{.77,.86,.95}) {paper_box(m,.13,y,.12,.025,p.shade,false)}
		paper_limb(m,{-.25,1.13},{.16,1.13},.045,p.light)
	case .Snow:
		paper_limb(m,{-.24,.76},{.12,1.26},.065,p.shade)
		paper_limb(m,{-.05,1.28},{.29,1.20},.095,p.accent)
		crystal:=[5]rl.Vector2{{-.26,.72},{-.34,1.03},{-.12,1.36},{.11,1.08},{.13,.75}}
		paper_polygon(m,crystal[:],p.light)
		paper_tri(m,{-.12,1.32},{.08,1.07},{-.05,.76},p.body,false)
		paper_limb(m,{-.24,1.04},{-.15,1.19},.025,EXPEDITION_PAPER_EDGE,false)
	case .Inferno:
		fixture_round(m,-.35,.65,.24,.66,p.body,p.shade,p.light)
		paper_box(m,-.39,1.25,.32,.10,p.shade)
		paper_tri(m,{.02,.73},{.23,1.21},{.39,.73},p.accent)
		paper_tri(m,{.15,.74},{.23,1.02},{.30,.74},p.signal,false)
		paper_limb(m,{.31,.74},{.46,1.18},.045,p.shade)
	case .Gothic:
		paper_box(m,-.42,.64,.84,.09,p.shade)
		fixture_book_print(m,-.06,.83,1,p)
		paper_box(m,.31,.73,.075,.45,p.light)
		paper_disc(m,.35,1.23,.05,.09,p.signal,false)
		paper_limb(m,{-.31,1.03},{-.20,1.34},.035,p.shade)
		paper_disc(m,-.19,1.36,.08,.055,p.accent)
	case .Sky:
		paper_limb(m,{-.04,.74},{.05,1.05},.075,p.shade)
		paper_limb(m,{-.35,.98},{.34,1.26},.20,p.accent)
		paper_limb(m,{-.30,1.03},{.28,1.27},.055,p.light,false)
		paper_disc(m,.35,1.27,.12,.15,p.shade)
		paper_disc(m,.35,1.27,.07,.09,p.signal,false)
		paper_disc(m,-.03,.91,.08,.08,p.accent)
	case .Space:
		paper_limb(m,{-.03,.70},{.10,.99},.10,p.shade)
		paper_disc(m,.04,1.13,.35,.23,p.light)
		paper_disc(m,.04,1.16,.25,.15,p.body,false)
		paper_limb(m,{.04,1.13},{-.19,1.37},.035,p.shade)
		paper_disc(m,-.20,1.38,.055,.055,p.accent)
		paper_box(m,-.21,.34,.31,.10,p.accent,false)
	case .Secret:
		for side in ([2]f32{-1,1}) {paper_limb(m,{side*.31,.57},{side*.39,1.05},.07,p.shade)}
		gem:=[5]rl.Vector2{{0,.73},{-.25,1.04},{-.16,1.31},{.13,1.39},{.27,1.05}}
		paper_polygon(m,gem[:],p.signal)
		paper_tri(m,{0,.77},{.13,1.35},{.24,1.05},p.accent,false)
		paper_limb(m,{-.13,1.05},{-.08,1.24},.03,p.light,false)
	case .Count:
	}
}

@(private)
expedition_fixture_art :: proc(b:campaign.Biome,kind:world.Site_Kind,time:f32=0,variant:int=0)->(m:Expedition_Paper) {
	m.cutout=true;p:=fixture_art_palette(b);ink:=EXPEDITION_PAPER_INK
	tick:=int(time*2)%2
	if kind==.Workshop && variant==1 && b==.Cyber {
		// The production module has a roller bed and an asymmetric arm mast.
		for side in ([2]f32{-1,1}) {paper_box(&m,side*.37-.065,0,.13,.25,p.shade)}
		fixture_round(&m,-.50,.20,1,.29,p.body,p.shade,p.light)
		paper_box(&m,-.42,.47,.84,.11,p.shade)
		for i in 0..<4 {paper_disc(&m,-.31+f32(i)*.21,.53,.09,.06,p.light)}
		paper_box(&m,.18,.56,.16,.20,p.body)
		paper_box(&m,-.42,.26,.73,.045,p.accent,false)
	} else {fixture_body_print(&m,b,p)}
	switch kind {
	case .Workshop:
		fixture_workshop_print(&m,b,p,tick,variant)
	case .Archive:
		if b==.Cyber || b==.City || b==.Space || b==.Vietnam {
			fixture_round(&m,-.42,.69,.84,.64,p.light,p.body,EXPEDITION_PAPER_EDGE)
			fixture_display_print(&m,-.31,.86,.57,.31,p,tick)
			paper_box(&m,-.28,.72,.52,.06,p.shade)
			for x in ([3]f32{-.19,-.02,.15}) {paper_box(&m,x,.73,.08,.025,p.light,false)}
		} else {
			fixture_round(&m,-.40,.68,.80,.61,p.body,p.shade,p.light)
			paper_box(&m,-.31,.77,.61,.40,p.shade)
			for i in 0..<4 {
				x:=-.27+f32(i)*.145;h:=.27+f32(i%2)*.08
				paper_box(&m,x,.79,.10,h,p.accent if i%2==0 else p.light)
				paper_box(&m,x+.02,.83,.06,.025,p.shade,false)
			}
			paper_box(&m,-.42,1.25,.84,.07,p.light)
		}
	case .Memory:
		if b==.Cyber || b==.Space || b==.City {
			fixture_round(&m,-.32,.68,.64,.66,p.light,p.body,EXPEDITION_PAPER_EDGE)
			paper_disc(&m,0,1.05,.23,.20,p.shade)
			paper_disc(&m,-.03,1.08,.14,.12,p.signal,false)
			paper_disc(&m,-.08,1.14,.05,.035,p.light,false)
			paper_box(&m,-.13,.74,.26,.055,p.accent,false)
		} else {
			paper_limb(&m,{0,.67},{0,1.07},.10,p.shade)
			fixture_book_print(&m,0,1.10,1.15,p)
			paper_limb(&m,{.16,.95},{.16,1.13},.045,p.accent,false)
		}
	case .Cache:
		// A curved lid and an actual central latch distinguish storage.
		lid:=[6]rl.Vector2{{-.45,.68},{-.45,.83},{-.29,1.03},{.27,1.03},{.45,.85},{.45,.68}}
		paper_polygon(&m,lid[:],p.body)
		paper_box(&m,-.34,.88,.64,.045,p.light,false)
		for side in ([2]f32{-1,1}) {paper_box(&m,side*.29-.035,.69,.07,.27,p.shade,false)}
		fixture_round(&m,-.09,.59,.18,.25,p.accent,p.shade,p.light)
		paper_disc(&m,0,.69,.025,.035,ink,false)
	case .Nest:
		// A readable entrance plus biome-specific crown, rooted as one object.
		fixture_round(&m,-.39,.63,.78,.51,p.body,p.shade,p.light)
		mouth:=[6]rl.Vector2{{-.25,.66},{-.25,.88},{-.13,1.05},{.12,1.05},{.25,.88},{.25,.66}}
		paper_polygon(&m,mouth[:],p.shade)
		for side in ([2]f32{-1,1}) {paper_box(&m,side*.13-.035,.89,.07,.055,p.accent,false)}
		if b==.Jungle || b==.Vietnam {fixture_leaf_print(&m,-.31,1.01,-1,p);fixture_leaf_print(&m,.26,1.02,1,p)}
		else if b==.Gothic || b==.Inferno {paper_tri(&m,{-.41,1.09},{0,1.42},{.41,1.09},p.shade);paper_disc(&m,0,1.21,.045,.05,p.accent,false)}
		else {for side in ([2]f32{-1,1}) {paper_limb(&m,{side*.31,1.07},{side*.39,1.35},.07,p.accent)}}
	case .Spring:
		// Neck, glass belly and liquid: no hovering gem above a tray.

		// Separate convex neck and belly keep the raster's convex contract.
		paper_disc(&m,0,.97,.29,.28,p.light)
		paper_box(&m,-.10,1.12,.20,.27,p.light)
		paper_disc(&m,0,.91,.22,.17,p.signal,false)
		paper_box(&m,-.14,1.32,.28,.08,p.accent)
		paper_limb(&m,{-.17,1.01},{-.12,1.11},.035,EXPEDITION_PAPER_EDGE,false)
	case .Trial,.Boss,.Tunnel,.Cave:
		// Reserved atlas entries have compact authored symbols. Their live
		// traversable architecture remains owned by the traversal renderer.
		paper_disc(&m,0,1.01,.32,.30,p.shade)
		paper_disc(&m,0,1.01,.23,.21,p.accent)
		paper_tri(&m,{-.08,.88},{.14,1.01},{-.08,1.15},p.light,false)
	}
	// Print and paper fit one occupied cell at the renderer's unit scale.
	// The narrowest stems still rasterize to two pixels, anchored at y=0.
	lowest:=f32(100)
	for &part in m.parts[:m.count] {for point in part.points[:part.count] {lowest=min(lowest,point.y)}}
	for &part in m.parts[:m.count] {for &point in part.points[:part.count] {point.x*=.80;point.y-=lowest}}
	return
}

@(private)
fixture_art_mask :: proc(a,b:^[FIXTURE_CELL*FIXTURE_CELL]rl.Color)->(mask:[FIXTURE_CELL*FIXTURE_CELL]u8) {
	for y in 0..<FIXTURE_CELL {for x in 0..<FIXTURE_CELL {
		if y>=int(CARTOON_FEET) {continue}
		distance:=100
		for dy in -8..=8 {for dx in -8..=8 {
			xx,yy:=x+dx,y+dy
			if xx<0 || xx>=FIXTURE_CELL || yy<0 || yy>=FIXTURE_CELL {continue}
			index:=yy*FIXTURE_CELL+xx
			if a[index].a>0 || b[index].a>0 {distance=min(distance,dx*dx+dy*dy)}
		}}
		cut:=1 if y>=int(CARTOON_FEET)-5 else 64
		if distance<=cut {mask[y*FIXTURE_CELL+x]=1 if distance>36 else 2}
	}}
	return
}

@(private)
create_expedition_fixture_art :: proc()->^Expedition_Fixture_Assets {
	assets:=new(Expedition_Fixture_Assets)
	w:=FIXTURE_COLUMNS*FIXTURE_CELL;rows:=(FIXTURE_COUNT+FIXTURE_COLUMNS-1)/FIXTURE_COLUMNS
	pixels:=make([]rl.Color,w*rows*FIXTURE_CELL*FIXTURE_FRAMES);defer delete(pixels)
	stock:=make([]rl.Color,w*rows*FIXTURE_CELL);defer delete(stock)
	for index in 0..<FIXTURE_COUNT {
		roles:=[FIXTURE_KINDS]world.Site_Kind{.Nest,.Cache,.Archive,.Workshop,.Spring,.Memory}
		biome:=campaign.Biome(index/FIXTURE_KINDS);kind:=roles[index%FIXTURE_KINDS];variant:=0
		if index>=72 {biome=campaign.Biome((index-72)/2);kind=.Workshop;variant=1+(index-72)%2}
		a:=expedition_fixture_art(biome,kind,0,variant);b:=expedition_fixture_art(biome,kind,.5,variant)
		first,second:=cartoon_raster(&a),cartoon_raster(&b)
		assets.mask[index]=fixture_art_mask(&first,&second);assets.top[index]=FIXTURE_CELL
		for value,i in assets.mask[index] {
			x,y:=i%FIXTURE_CELL,i/FIXTURE_CELL
			if value>0 {assets.top[index]=min(assets.top[index],y)}
			if value>0 {stock[(index/FIXTURE_COLUMNS*FIXTURE_CELL+y)*w+index%FIXTURE_COLUMNS*FIXTURE_CELL+x]=EXPEDITION_PAPER_INK if value==1 else EXPEDITION_PAPER_EDGE}
			for frame in 0..<FIXTURE_FRAMES {
				cell:=index*FIXTURE_FRAMES+frame
				color:=first[i] if frame==0 else second[i]
				if value==2 {pixels[(cell/FIXTURE_COLUMNS*FIXTURE_CELL+y)*w+cell%FIXTURE_COLUMNS*FIXTURE_CELL+x]=color}
			}
		}
	}
	img:=rl.Image{data=raw_data(pixels),width=i32(w),height=i32(rows*FIXTURE_CELL*FIXTURE_FRAMES),mipmaps=1,format=.UNCOMPRESSED_R8G8B8A8}
	assets.print=rl.LoadTextureFromImage(img)
	img={data=raw_data(stock),width=i32(w),height=i32(rows*FIXTURE_CELL),mipmaps=1,format=.UNCOMPRESSED_R8G8B8A8}
	assets.paper=rl.LoadTextureFromImage(img)
	if assets.print.id==0 || assets.paper.id==0 {destroy_expedition_fixture_art(assets);return nil}
	rl.SetTextureFilter(assets.print,.POINT);rl.SetTextureFilter(assets.paper,.POINT)
	if !create_cyber_press_art(assets) {destroy_expedition_fixture_art(assets);return nil}
	return assets
}

@(private)
destroy_expedition_fixture_art :: proc(assets:^Expedition_Fixture_Assets) {
	if assets==nil {return}
	if assets.hero_print.id!=0 {rl.UnloadTexture(assets.hero_print)}
	if assets.hero_paper.id!=0 {rl.UnloadTexture(assets.hero_paper)}
	if assets.print.id!=0 {rl.UnloadTexture(assets.print)}
	if assets.paper.id!=0 {rl.UnloadTexture(assets.paper)}
	free(assets)
}
