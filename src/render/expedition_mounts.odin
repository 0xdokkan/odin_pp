package render

import "core:math"
import rl "vendor:raylib"
import campaign "../campaign"

@(private)
mount_wheel :: proc(m:^Expedition_Paper,x,y,r,time:f32,accent:rl.Color) {
	paper_disc(m,x,y,r,r,{27,30,38,255});paper_disc(m,x,y,r*.58,r*.58,{110,118,127,255},false)
	for i in 0..<3 {a:=time*8+f32(i)*math.PI*2/3;paper_limb(m,{x,y},{x+math.cos(a)*r*.52,y+math.sin(a)*r*.52},.035,accent,false)}
	paper_disc(m,x,y,.055,.055,accent,false)
}
@(private)
mount_legs :: proc(m:^Expedition_Paper,t:f32,long:bool,color:rl.Color) {
	for i in 0..<4 {
		x:=f32(-.61)+f32(i/2)*1.15+f32(i%2)*.12;phase:=t*7+f32(i%2)*math.PI+f32(i/2)*1.5
		y:f32=.63 if long else .45;foot:=rl.Vector2{x+math.sin(phase)*.13,.07+max(f32(0),math.cos(phase))*.07}
		paper_limb(m,{x,y},{x-.05+math.sin(phase)*.06,y*.48},.095,color)
		paper_limb(m,{x-.05+math.sin(phase)*.06,y*.48},foot,.085,color)
		paper_box(m,foot.x-.06,foot.y-.035,.18,.075,EXPEDITION_PAPER_INK,false)
	}
}
@(private)
mount_saddle :: proc(m:^Expedition_Paper,x,y:f32,accent:rl.Color) {
	paper_box(m,x-.26,y-.11,.52,.16,{74,43,43,255});paper_box(m,x-.18,y+.01,.36,.07,accent,false)
	paper_limb(m,{x-.12,y-.08},{x-.12,y-.3},.045,{222,178,106,255},false)
}

// Each ride is designed from a different silhouette, not only a palette swap.
// The dinosaur combat card deliberately uses an armored T-Rex instead of the
// Jungle expedition's low, long-crested parasaurolophus.
expedition_mount_art :: proc(b:campaign.Biome,time:f32,dinosaur:bool=false)->(m:Expedition_Paper) {
	m.cutout=true
	ink:=EXPEDITION_PAPER_INK;paper:=EXPEDITION_PAPER_EDGE;c:=expedition_color(b)
	if dinosaur {
		for i in 0..<2 {
			phase:=time*7+f32(i)*math.PI;x:=-.2+f32(i)*.32
			knee:=rl.Vector2{x-.12+math.sin(phase)*.07,.29};foot:=rl.Vector2{x+.05+math.sin(phase)*.17,.06+max(f32(0),math.cos(phase))*.04}
			paper_limb(&m,{x,.56},knee,.19,{103,132,63,255});paper_limb(&m,knee,foot,.12,{103,132,63,255});paper_box(&m,foot.x-.02,foot.y,.24,.07,{138,167,83,255})
		}
		paper_tri(&m,{-1.35,.44},{-.3,.46},{-.57,.89},{96,137,62,255})
		p:=[6]rl.Vector2{{-.65,.4},{.35,.4},{.68,.75},{.35,1.04},{-.32,.94},{-.72,.69}};paper_polygon(&m,p[:],{115,161,67,255})
		paper_limb(&m,{.43,.78},{.57,.59},.07,{116,153,70,255});paper_limb(&m,{.57,.59},{.71,.64},.055,{116,153,70,255})
		paper_box(&m,.42,.75,.25,.5,{133,171,74,255});paper_box(&m,.45,1.08,.79,.36,{146,182,81,255})
		paper_box(&m,.72,1.04,.46,.09,ink,false)
		for i in 0..<4 {x:=.76+f32(i)*.105;paper_tri(&m,{x,1.12},{x+.055,1.12},{x+.03,1.06},paper,false)}
		paper_disc(&m,.72,1.3,.045,.045,{255,197,77,255},false);paper_disc(&m,.73,1.3,.018,.03,ink,false)
		for i in 0..<4 {x:=f32(-.53)+f32(i)*.22;paper_tri(&m,{x,.93},{x+.12,1.13},{x+.2,.95},{229,168,71,255})}
		mount_saddle(&m,-.08,.86,{235,183,77,255});return
	}
	switch b {
	case .Cyber: // Long hover nacelles, open saddle and luminous exhaust.
		for side in ([2]f32{-1,1}) {x:=side*.8;paper_disc(&m,x,.27,.43,.14,{39,43,57,255});paper_box(&m,x-.24,.24,.48,.045,c,false)}
		paper_tri(&m,{-1.5,.43},{-.95,.57},{-.95,.32},color_with_opacity({116,230,255,255},.6+.3*math.sin(time*11)),false)
		p:=[5]rl.Vector2{{-1.13,.4},{.83,.4},{1.32,.63},{.12,.78},{-.98,.67}};paper_polygon(&m,p[:],{54,48,71,255})
		paper_limb(&m,{-.77,.56},{.86,.59},.06,c,false);paper_limb(&m,{.54,.72},{.58,1.02},.07,paper)
		paper_limb(&m,{.4,1.03},{.79,1.03},.055,ink);mount_saddle(&m,-.2,.79,c)
	case .West,.Gothic: // Horse; Gothic has a skeletal muzzle and funeral tack.
		coat:=rl.Color{153,93,61,255} if b==.West else rl.Color{49,46,61,255}
		mount_legs(&m,time,true,coat)
		paper_disc(&m,-.03,.65,.8,.27,coat);paper_limb(&m,{.5,.65},{.73,1.24},.28,coat)
		paper_disc(&m,.85,1.25,.33,.17,coat);paper_tri(&m,{.64,1.35},{.68,1.65},{.78,1.37},coat)
		paper_limb(&m,{-.76,.77},{-1.02,.25+math.sin(time*3)*.07},.12,ink)
		paper_limb(&m,{.55,.85},{.62,1.28},.12,ink,false);paper_disc(&m,.85,1.31,.028,.028,paper,false)
		paper_limb(&m,{1.02,1.17},{.18,.79},.025,{224,177,107,255},false);mount_saddle(&m,-.1,.92,c)
		if b==.Gothic {paper_box(&m,.88,1.15,.24,.1,paper,false);for i in 0..<3 {paper_box(&m,.92+f32(i)*.05,1.15,.02,.1,ink,false)};paper_tri(&m,{-.53,.81},{-.3,.3},{.37,.7},{127,40,59,255})}
	case .Jungle: // Parasaurolophus: long tail, small muzzle and swept crest.
		mount_legs(&m,time,false,{117,157,69,255});paper_tri(&m,{-1.5,.55},{-.4,.48},{-.48,.83},{112,151,61,255})
		paper_disc(&m,-.05,.62,.73,.28,{140,177,78,255});paper_limb(&m,{.48,.63},{.72,1.12},.23,{145,181,84,255})
		paper_disc(&m,.86,1.17,.28,.14,{158,189,92,255});paper_limb(&m,{.77,1.26},{.37,1.48},.13,{208,117,60,255})
		paper_disc(&m,.91,1.2,.028,.028,ink,false);paper_limb(&m,{-.64,.74},{.34,.75},.055,{207,210,114,255},false);mount_saddle(&m,-.1,.88,c)
	case .City: // 1980s motorcycle: two full wheels, chrome fork and tank.
		mount_wheel(&m,-.82,.28,.29,time,{216,225,224,255});mount_wheel(&m,.85,.28,.29,time,{216,225,224,255})
		paper_tri(&m,{-.81,.29},{-.1,.77},{.49,.29},{62,48,78,255});paper_limb(&m,{.48,.94},{.85,.28},.095,{198,213,217,255})
		paper_disc(&m,.13,.75,.47,.18,{224,67,151,255});paper_box(&m,-.57,.81,.49,.12,ink);paper_limb(&m,{.47,.93},{.74,1.05},.05,paper)
		paper_disc(&m,.68,.86,.12,.13,{255,231,143,255});paper_limb(&m,{-.84,.42},{-.17,.36},.07,{217,221,222,255})
	case .Egypt: // Camel hump, very long legs, downturned neck and woven blanket.
		mount_legs(&m,time,true,{191,148,87,255});paper_disc(&m,-.05,.76,.77,.23,{213,168,100,255})
		paper_disc(&m,-.13,1.0,.33,.38,{220,179,111,255});paper_limb(&m,{.53,.81},{.68,1.39},.2,{217,175,105,255})
		paper_disc(&m,.86,1.43,.3,.13,{224,185,120,255});paper_box(&m,1.05,1.31,.14,.15,{218,174,103,255})
		paper_disc(&m,.85,1.47,.025,.025,ink,false);paper_tri(&m,{.67,1.52},{.64,1.69},{.79,1.51},{205,155,90,255})
		paper_box(&m,-.52,.67,.84,.22,{45,132,152,255});paper_limb(&m,{-.42,.78},{.22,.78},.035,{238,190,76,255},false);mount_saddle(&m,-.08,1.29,{245,195,81,255})
	case .Vietnam: // Open jeep: square cabin, windshield, grille and spare wheel.
		mount_wheel(&m,-.82,.25,.26,time,{184,183,132,255});mount_wheel(&m,.8,.25,.26,time,{184,183,132,255})
		paper_box(&m,-1.06,.38,2.14,.42,{99,119,68,255});paper_box(&m,.45,.74,.67,.14,{126,140,79,255})
		paper_box(&m,-.84,.75,.25,.43,{100,119,70,255});paper_limb(&m,{.35,.8},{.22,1.27},.065,{192,200,157,255})
		paper_limb(&m,{-.66,1.27},{.24,1.27},.07,{110,128,80,255});paper_disc(&m,-1.08,.73,.17,.25,ink)
		paper_box(&m,1.02,.49,.11,.2,ink,false);paper_disc(&m,1.1,.73,.055,.08,{255,228,154,255},false);mount_saddle(&m,-.1,.84,{146,149,91,255})
	case .Snow: // Snowmobile: rear caterpillar tread and two swept skis.
		paper_disc(&m,-.48,.23,.67,.2,{43,57,72,255});for i in 0..<6 {paper_box(&m,-1+f32(i)*.19+math.sin(time*8)*.035,.08,.08,.27,{106,131,144,255},false)}
		paper_limb(&m,{.5,.52},{.77,.12},.065,{200,225,230,255});paper_limb(&m,{.2,.09},{1.28,.09},.1,{156,201,218,255});paper_limb(&m,{1.28,.09},{1.43,.22},.1,{156,201,218,255})
		p:=[5]rl.Vector2{{-.99,.43},{.8,.42},{1.12,.65},{.49,.92},{-.7,.76}};paper_polygon(&m,p[:],{211,79,58,255})
		paper_tri(&m,{.45,.91},{.29,1.18},{.74,1.02},{143,207,223,220});mount_saddle(&m,-.3,.8,{232,225,190,255})
	case .Inferno: // Cerberus: three separate muzzles, collars and ember eyes.
		mount_legs(&m,time,false,{77,49,49,255});paper_disc(&m,-.05,.59,.75,.25,{92,49,47,255})
		paper_limb(&m,{-.7,.73},{-1.1,1.04+math.sin(time*3)*.12},.12,{144,57,40,255})
		for i in 0..<3 {x:=.4+f32(i)*.27;y:=.91+f32(i%2)*.24;paper_limb(&m,{.37,.65},{x,y},.2,{115,55,44,255})}
		for i in 0..<3 {x:=.4+f32(i)*.27;y:=.91+f32(i%2)*.24;paper_disc(&m,x+.14,y,.22,.16,{132,64,48,255});paper_tri(&m,{x-.02,y+.1},{x+.02,y+.31},{x+.11,y+.13},ink);paper_disc(&m,x+.16,y+.04,.036,.026,{255,212,71,255},false);paper_limb(&m,{x-.05,y-.13},{x+.17,y-.13},.06,{243,152,45,255},false)}
		mount_saddle(&m,-.25,.84,{229,146,48,255})
	case .Sky: // Griffin: lion body, eagle beak, feathered animated wings.
		flap:=math.sin(time*3)*.15
		for side in ([2]f32{-1,1}) {for i in 0..<4 {x:=side*(.23+f32(i)*.22);paper_tri(&m,{side*.12,.83},{x+side*.47,1.67+flap-f32(i)*.1},{x,.86},{212+u8(i)*7,202+u8(i)*5,179+u8(i)*8,255})}}
		mount_legs(&m,time,false,{205,167,91,255});paper_disc(&m,-.05,.58,.69,.26,{208,166,91,255});paper_limb(&m,{.45,.68},{.67,1.04},.23,paper)
		paper_disc(&m,.76,1.17,.24,.22,paper);paper_tri(&m,{.9,1.21},{1.22,1.07},{.94,1.04},{229,179,69,255});paper_disc(&m,.81,1.24,.035,.03,ink,false);mount_saddle(&m,-.15,.83,{166,109,148,255})
	case .Space: // A ship ridden astride: open saddle, swept fins, engine plume.
		pulse:=.1+math.sin(time*12)*.045
		paper_tri(&m,{-1.45-pulse,.57},{-.9,.8},{-.9,.35},{170,113,255,190},false)
		paper_tri(&m,{-.4,.49},{-.96,1.21},{.57,.67},{104,87,155,255});paper_tri(&m,{-.4,.49},{-.97,.13},{.65,.52},{104,87,155,255})
		p:=[5]rl.Vector2{{-1.04,.47},{.78,.42},{1.43,.68},{.74,.86},{-.91,.81}};paper_polygon(&m,p[:],{179,187,213,255})
		paper_limb(&m,{-.65,.65},{.91,.65},.055,c,false);paper_box(&m,-1.09,.48,.16,.29,{66,70,101,255});mount_saddle(&m,-.14,.88,{137,97,214,255})
	case .Secret: // Sisyphus' remembered boulder: faceted, gold-seamed stone.
		paper_disc(&m,0,.55,.7,.53,{123,120,130,255},true,time*.2)
		paper_tri(&m,{-.57,.56},{-.11,1.02},{.13,.5},{156,151,153,255},false);paper_tri(&m,{.13,.5},{-.1,1.02},{.59,.78},{187,176,160,255},false)
		paper_limb(&m,{-.39,.26},{.13,.5},.025,{243,203,115,255},false);paper_limb(&m,{.13,.5},{.35,.97},.025,{243,203,115,255},false)
	case .Count:
	}
	return
}
