package render

import "core:math"
import rl "vendor:raylib"
import gfx "../engine/gfx"
import view "../engine/view"
import campaign "../campaign"
import world "../expedition"
import game "../game"

// These are wardrobe pieces attached to the existing animated paper rigs.
// Their palette and silhouette tell the biome; the carried weapon tells role.
expedition_enemy_tint :: proc(b:campaign.Biome)->rl.Color {
	if b>=.Count {return rl.WHITE}
	colors:=[campaign.Biome]rl.Color{
		.Cyber={189,207,235,255},.West={245,207,160,255},.Jungle={190,233,143,255},.City={244,183,226,255},
		.Egypt={248,220,161,255},.Vietnam={193,213,154,255},.Snow={183,224,249,255},.Inferno={249,156,111,255},
		.Gothic={193,207,181,255},.Sky={248,222,233,255},.Space={202,177,249,255},.Secret={241,226,185,255},.Count=rl.WHITE,
	};return colors[b]
}

@(private)
costume_gun :: proc(m:^Expedition_Paper,length:f32,color:rl.Color) {
	paper_box(m,.18,.47,length,.09,color);paper_box(m,.22,.35,.1,.18,{105,76,56,255});paper_box(m,.21+length,.47,.05,.1,EXPEDITION_PAPER_INK,false)
}
@(private)
costume_shield :: proc(m:^Expedition_Paper,c:rl.Color) {
	p:=[5]rl.Vector2{{-.62,.7},{-.31,.7},{-.29,.4},{-.46,.26},{-.64,.4}};paper_polygon(m,p[:],c)
	paper_limb(m,{-.46,.62},{-.46,.35},.035,EXPEDITION_PAPER_EDGE,false)
}
@(private)
costume_staff :: proc(m:^Expedition_Paper,c:rl.Color) {
	paper_limb(m,{.42,.16},{.42,1.1},.045,{131,102,66,255});paper_disc(m,.42,1.12,.1,.1,c)
}
@(private)
costume_horns :: proc(m:^Expedition_Paper,c:rl.Color) {
	paper_tri(m,{-.22,.92},{-.39,1.21},{-.12,1.04},c);paper_tri(m,{.12,1.04},{.39,1.21},{.22,.92},c)
}

expedition_enemy_costume_art :: proc(b:campaign.Biome,role:game.Enemy_Archetype,time:f32)->(m:Expedition_Paper) {
	ink:=EXPEDITION_PAPER_INK;paper:=EXPEDITION_PAPER_EDGE;c:=expedition_color(b);boss:=role==.Demolitionist
	switch b {
	case .Cyber:
		paper_box(&m,-.23,.43,.46,.29,{55,66,85,255});paper_box(&m,-.18,.91,.36,.14,{58,71,91,255})
		paper_box(&m,-.13,.95,.26,.035,c,false);paper_box(&m,-.055,.53,.11,.1,c,false)
		if role==.Chaser {for side in ([2]f32{-1,1}) {paper_limb(&m,{side*.18,.49},{side*.53,.32},.055,{107,128,147,255});paper_limb(&m,{side*.53,.32},{side*.59,.17},.045,{107,128,147,255})}}
		if role==.Archer {costume_gun(&m,.42,{96,132,160,255});paper_limb(&m,{-.16,1.03},{-.18,1.23},.025,c,false);paper_disc(&m,-.18,1.23,.04,.04,c,false)}
		if role==.Brute {for i in 0..<4 {paper_limb(&m,{-.23+f32(i)*.12,.49},{-.16+f32(i)*.12,.67},.04,{245,193,66,255},false)}}
		if role==.Bomber {paper_disc(&m,.34,.55,.19,.19,{73,79,95,255});paper_disc(&m,.34,.55,.06,.06,c,false)}
		if role==.Custodian {costume_shield(&m,{65,140,190,230})}
		if boss {for i in 0..<5 {x:=-.3+f32(i)*.15;paper_box(&m,x,1.01,.07,.18+f32(i%2)*.12,{127,150,183,255});paper_disc(&m,x+.035,1.22+f32(i%2)*.12,.035,.035,c,false)};paper_box(&m,-.3,.42,.6,.27,{67,82,108,255})}
	case .West:
		hat:=rl.Color{160,110,67,255} if !boss else rl.Color{44,41,46,255}
		paper_box(&m,-.37,.96,.74,.075,hat);paper_box(&m,-.22,1.02,.44,.2,hat);paper_box(&m,-.22,1.02,.44,.045,{80,47,37,255},false)
		paper_tri(&m,{-.18,.84},{.18,.84},{.04,.65},{189,58,49,255});paper_box(&m,-.23,.4,.46,.065,{106,66,40,255})
		if role==.Archer || boss {costume_gun(&m,.28,{188,194,195,255})}
		if role==.Chaser {paper_limb(&m,{.28,.45},{.44,.69},.06,{179,181,169,255})}
		if role==.Brute {costume_horns(&m,{222,207,170,255});paper_disc(&m,0,.82,.24,.11,{86,74,69,255})}
		if role==.Bomber {for i in 0..<3 {paper_box(&m,.27+f32(i)*.07,.47,.06,.24,{194,65,49,255})};paper_limb(&m,{.39,.72},{.44,.83},.02,{251,197,86,255},false)}
		if role==.Custodian {costume_shield(&m,{119,90,57,255});for i in 0..<5 {a:=f32(i)*math.PI*2/5;paper_tri(&m,{-.1,.62},{-.1+math.cos(a)*.1,.62+math.sin(a)*.1},{-.1+math.cos(a+.5)*.05,.62+math.sin(a+.5)*.05},{244,193,65,255},false)}}
		if boss {paper_tri(&m,{-.38,.74},{.29,.74},{-.2,.29},{152,72,46,255});paper_limb(&m,{-.3,.57},{.03,.46},.045,{232,178,91,255},false)}
	case .Jungle:
		paper_disc(&m,0,.91,.28,.17,{124,164,72,255});paper_box(&m,.13,.84,.27,.12,{152,185,83,255});paper_disc(&m,.08,.96,.035,.028,{246,202,65,255},false)
		for i in 0..<3 {paper_tri(&m,{-.25+f32(i)*.12,.99},{-.22+f32(i)*.12,1.17},{-.12+f32(i)*.12,1.0},{205,131,71,255})}
		if role==.Chaser {paper_tri(&m,{-.21,.5},{-.72,.42},{-.24,.64},{119,160,69,255});paper_limb(&m,{.24,.45},{.4,.6},.055,paper)}
		if role==.Archer {for i in 0..<3 {paper_disc(&m,.41+f32(i)*.09,.88+math.sin(time*3+f32(i))*.03,.035,.035,{166,226,72,255},false)}}
		if role==.Brute {paper_disc(&m,-.05,.88,.35,.3,{170,142,67,255});costume_horns(&m,paper);paper_tri(&m,{.17,.86},{.48,.94},{.19,.98},paper)}
		if role==.Bomber {for side in ([2]f32{-1,1}) {paper_tri(&m,{side*.15,.72},{side*.77,1.08+math.sin(time*4)*.04},{side*.47,.48},{164,118,86,255})}}
		if role==.Custodian {costume_shield(&m,{99,128,67,255});for i in 0..<4 {paper_tri(&m,{-.63,.37+f32(i)*.09},{-.79,.4+f32(i)*.09},{-.61,.45+f32(i)*.09},paper)}}
		if boss {paper_box(&m,-.24,.83,.69,.27,{123,153,69,255});for i in 0..<5 {x:=.04+f32(i)*.07;paper_tri(&m,{x,.86},{x+.04,.86},{x+.02,.8},paper,false)}}
	case .City:
		paper_box(&m,-.24,.46,.48,.28,{42,47,70,255});paper_box(&m,-.24,.96,.48,.065,{240,118,182,255});paper_tri(&m,{-.25,.99},{-.45,1.1},{-.26,.92},{240,118,182,255})
		paper_tri(&m,{-.23,.74},{-.02,.47},{-.04,.76},paper);paper_tri(&m,{.23,.74},{.02,.47},{.04,.76},paper)
		if role==.Chaser {paper_limb(&m,{.3,.32},{.52,.9},.075,{173,132,84,255})}
		if role==.Archer {costume_gun(&m,.24,{159,169,186,255})}
		if role==.Brute {paper_disc(&m,0,.58,.31,.23,{221,169,139,255});paper_box(&m,-.34,.37,.68,.12,{87,63,109,255});paper_disc(&m,0,1.11,.1,.08,ink)}
		if role==.Bomber {paper_box(&m,.31,.45,.14,.23,{91,154,100,255});paper_box(&m,.35,.68,.06,.11,{192,211,164,255});paper_tri(&m,{.32,.77},{.4,1.03+math.sin(time*9)*.04},{.45,.76},{255,171,67,255})}
		if role==.Custodian {costume_shield(&m,{53,61,82,255})}
		if boss {paper_box(&m,-.31,.38,.62,.35,{230,217,196,255});paper_limb(&m,{.35,.28},{.62,.95},.045,{206,220,222,255});paper_box(&m,-.19,1.01,.38,.1,ink);paper_disc(&m,.1,.91,.05,.045,ink,false)}
	case .Egypt:
		p:=[6]rl.Vector2{{-.31,.74},{-.27,1.05},{-.14,1.2},{.14,1.2},{.27,1.05},{.31,.74}};paper_polygon(&m,p[:],{221,174,64,255})
		paper_box(&m,-.14,.79,.28,.24,{165,128,83,255});for side in ([2]f32{-1,1}) {for i in 0..<4 {paper_box(&m,side*.21-.035,.8+f32(i)*.08,.07,.035,{58,123,156,255},false)}}
		if role==.Chaser {for i in 0..<4 {paper_limb(&m,{-.22,.43+f32(i)*.065},{.22,.49+f32(i)*.065},.04,{220,211,178,255},false)}}
		if role==.Archer {costume_staff(&m,{80,177,193,255})}
		if role==.Brute {paper_box(&m,-.32,.42,.64,.31,{172,156,117,255});paper_limb(&m,{.38,.27},{.38,.85},.09,{181,164,128,255})}
		if role==.Bomber {paper_disc(&m,0,.61,.31,.28,{66,125,144,255});paper_limb(&m,{0,.37},{0,.88},.035,{235,192,77,255},false)}
		if role==.Custodian {costume_shield(&m,{191,163,96,255})}
		if boss {paper_box(&m,-.21,1.08,.42,.2,{234,190,70,255});paper_disc(&m,0,1.3,.065,.11,{56,169,184,255});costume_staff(&m,{239,197,74,255});paper_box(&m,-.3,.51,.6,.14,{59,139,163,255})}
	case .Vietnam:
		paper_box(&m,-.23,.42,.46,.32,{99,124,74,255});paper_disc(&m,0,1.02,.3,.14,{108,131,78,255});paper_box(&m,-.33,.96,.66,.045,{127,148,88,255})
		for i in 0..<3 {paper_box(&m,-.18+f32(i)*.13,.51,.09,.1,{66,87,56,255},false)}
		if role==.Archer {costume_gun(&m,.53,{74,84,67,255});paper_box(&m,.43,.59,.15,.045,ink,false)}
		if role==.Brute {costume_gun(&m,.62,{77,89,72,255});paper_box(&m,.4,.29,.2,.22,{153,137,70,255})}
		if role==.Bomber {paper_disc(&m,.33,.53,.1,.14,{124,137,77,255});paper_limb(&m,{.33,.65},{.4,.73},.025,paper,false)}
		if role==.Custodian {paper_box(&m,-.24,1.02,.48,.09,{68,86,59,255});paper_disc(&m,0,1.08,.04,.04,{241,195,75,255},false)}
		if boss {paper_disc(&m,0,.68,.55,.31,{107,129,79,255});paper_box(&m,.15,.71,.24,.16,{116,195,204,255});paper_limb(&m,{0,.93},{0,1.19},.06,ink);paper_limb(&m,{-.76,1.21},{.76,1.21},.035,{170,187,147,255});paper_limb(&m,{-.4,.36},{.42,.36},.04,paper)}
	case .Snow:
		paper_disc(&m,0,.94,.3,.26,{201,225,226,255});paper_box(&m,-.15,.82,.3,.2,{89,123,149,255});paper_box(&m,-.24,.43,.48,.12,{176,213,226,255})
		if role==.Chaser {costume_horns(&m,{201,225,226,255});paper_tri(&m,{-.12,.91},{.2,.78},{.17,.98},{215,231,229,255})}
		if role==.Archer {costume_staff(&m,{128,215,250,255})}
		if role==.Brute {paper_disc(&m,-.3,.65,.15,.24,paper);paper_disc(&m,.3,.65,.15,.24,paper)}
		if role==.Bomber {paper_disc(&m,.34,.55,.23,.23,{225,242,243,255});paper_limb(&m,{.22,.63},{.4,.48},.025,{151,197,215,255},false)}
		if role==.Custodian {costume_shield(&m,{145,208,232,255})}
		if boss {for i in 0..<5 {x:=-.3+f32(i)*.15;paper_tri(&m,{x,1.08},{x+.06,1.37+f32(i%2)*.07},{x+.12,1.08},{139,212,242,255})}}
	case .Inferno:
		costume_horns(&m,{219,172,109,255});paper_box(&m,-.23,.43,.46,.26,{117,58,47,255})
		paper_disc(&m,-.09,.94,.045,.025,{255,200,73,255},false);paper_disc(&m,.09,.94,.045,.025,{255,200,73,255},false)
		if role==.Chaser || boss {for side in ([2]f32{-1,1}) {paper_tri(&m,{side*.18,.74},{side*.58,1.04},{side*.6,.51},{136,55,55,255})}}
		if role==.Archer {costume_staff(&m,{255,151,52,255})}
		if role==.Brute {paper_box(&m,-.35,.56,.7,.21,{84,70,66,255})}
		if role==.Bomber {paper_disc(&m,.3,.53,.18,.19,{235,104,43,255});paper_tri(&m,{.21,.69},{.29,.98+math.sin(time*7)*.04},{.43,.65},{255,197,68,255})}
		if role==.Custodian {costume_shield(&m,{106,70,66,255})}
		if boss {paper_box(&m,-.3,1.01,.6,.12,{155,94,56,255});paper_disc(&m,0,1.16,.08,.14,{255,188,66,255})}
	case .Gothic:
		if role==.Chaser {paper_tri(&m,{-.32,.78},{-.47,.31},{.27,.41},{174,190,166,160});paper_disc(&m,0,.98,.18,.16,{215,221,199,255});paper_disc(&m,-.07,.99,.04,.045,ink,false);paper_disc(&m,.07,.99,.04,.045,ink,false)}
		if role==.Archer {paper_box(&m,-.31,1.01,.62,.06,{85,75,58,255});paper_box(&m,-.2,1.06,.4,.16,{85,75,58,255});costume_gun(&m,.47,{116,110,88,255})}
		if role==.Brute {paper_box(&m,.22,.42,.36,.14,{176,124,68,255});paper_disc(&m,.57,.49,.22,.1,{185,190,180,255});for i in 0..<5 {paper_tri(&m,{.42+f32(i)*.07,.56},{.45+f32(i)*.07,.63},{.47+f32(i)*.07,.56},ink,false)}}
		if role==.Bomber {paper_limb(&m,{.34,.47},{.34,.83},.04,{139,125,85,255});paper_box(&m,.24,.39,.2,.24,{181,149,76,255});paper_box(&m,.29,.45,.1,.13,{255,201,99,255},false)}
		if role==.Custodian {paper_box(&m,-.34,1.02,.68,.065,{135,119,76,255});paper_tri(&m,{-.24,1.06},{0,1.35},{.23,1.06},{135,119,76,255});costume_shield(&m,{98,105,81,255})}
		if boss {paper_disc(&m,0,.98,.22,.22,{227,219,189,255});for side in ([2]f32{-1,1}) {paper_disc(&m,side*.09,1.02,.045,.065,ink,false)};paper_box(&m,-.07,.86,.14,.045,ink,false);paper_limb(&m,{.32,.32},{.46,.8},.07,{200,204,193,255})}
	case .Sky:
		for side in ([2]f32{-1,1}) {for i in 0..<3 {paper_tri(&m,{side*.19,.68},{side*(.58+f32(i)*.07),.98+f32(i)*.1+math.sin(time*3)*.03},{side*.25,.5+f32(i)*.08},{224,213,225,255})}}
		paper_disc(&m,0,1.2,.23,.055,{245,211,131,255});paper_disc(&m,0,1.2,.15,.025,ink,false)
		if role==.Archer {costume_staff(&m,{198,167,225,255})}
		if role==.Brute {paper_disc(&m,-.28,.59,.17,.19,{208,218,231,255});paper_disc(&m,.28,.59,.17,.19,{208,218,231,255})}
		if role==.Bomber {paper_disc(&m,.35,.55,.16,.19,{245,183,130,255})}
		if role==.Custodian {costume_shield(&m,{220,188,219,255})}
		if boss {for i in 0..<4 {paper_disc(&m,0,1.24+f32(i)*.08,.28-f32(i)*.035,.022,{246,219,148,255},false)};paper_box(&m,-.2,.49,.4,.14,{186,147,190,255})}
	case .Space:
		paper_disc(&m,0,.95,.31,.27,{106,97,159,255});paper_disc(&m,0,.95,.24,.2,{69,86,128,255},false);paper_limb(&m,{-.16,1.05},{-.06,1.1},.035,{193,232,249,255},false)
		paper_box(&m,-.23,.43,.46,.29,{125,112,175,255});paper_disc(&m,0,.6,.055,.055,{149,230,243,255},false)
		if role==.Chaser {costume_horns(&m,{134,186,165,255})}
		if role==.Archer {costume_gun(&m,.39,{175,163,217,255})}
		if role==.Brute {paper_box(&m,-.4,.53,.2,.24,{138,130,183,255});paper_box(&m,.2,.53,.2,.24,{138,130,183,255})}
		if role==.Bomber {paper_disc(&m,.34,.52,.18,.18,{131,108,177,255});for i in 0..<5 {a:=f32(i)*math.PI*2/5;paper_limb(&m,{.34,.52},{.34+math.cos(a)*.25,.52+math.sin(a)*.25},.03,{211,185,245,255},false)}}
		if role==.Custodian {costume_shield(&m,{106,144,184,255})}
		if boss {paper_disc(&m,0,.71,.65,.19,{171,163,203,255});paper_disc(&m,0,.89,.32,.22,{93,141,171,255});for i in 0..<5 {paper_disc(&m,-.43+f32(i)*.21,.67,.045,.035,{189,239,220,255},false)}}
	case .Secret:
		paper_box(&m,-.23,.46,.46,.29,{185,167,132,255});paper_disc(&m,0,1.15,.25,.035,{239,214,158,255})
		paper_tri(&m,{-.15,.61},{0,.8},{.15,.61},{248,223,163,255});paper_box(&m,-.035,.5,.07,.14,{245,218,152,255},false)
		if role==.Archer {costume_staff(&m,{245,219,156,255})}
		if role==.Brute || role==.Custodian {costume_shield(&m,{175,161,137,255})}
		if role==.Brute {paper_box(&m,.28,.53,.23,.24,{174,153,116,255});paper_limb(&m,{.39,.22},{.39,.53},.055,{223,193,134,255})}
		if role==.Bomber {paper_disc(&m,.32,.57,.16,.16,{222,189,117,255})}
		if boss {paper_box(&m,-.24,.88,.48,.24,paper);paper_box(&m,-.2,.92,.4,.14,{77,88,100,255},false);paper_limb(&m,{.36,.25},{.36,1.14},.07,{222,184,99,255});paper_tri(&m,{.3,1.13},{.36,1.4},{.43,1.13},ink)}
	case .Count:
	}
	return
}

@(private)
draw_expedition_costume :: proc(renderer:^Renderer,b:campaign.Biome,role:game.Enemy_Archetype,position:view.Vec2,entity:game.Entity_Ref,time:f32,opacity:f32=1) {
	if role>=.Count || opacity<=0 {return}
	key:=sprite_key_for_enemy(role);at,lift:=living_card_position(renderer,entity,key,position)
	height:f32=1.2
	if character,ok:=flipbook_character(key);ok {height=gfx.LIVING_SHEETS[character].world_height}
	mirror:=false;turn_width:f32=1
	if character,ok:=flipbook_character(key);ok && renderer.tactical.living_state!=nil {
		if actor:=living_find(renderer,entity,character);actor!=nil {
			mirror=actor.facing_left
			turn:=(renderer.sprite_assets.elapsed-actor.turn_started)/LIVING_TURN_SECONDS
			if actor.turn_started>=0 && turn<1 {turn_width=max(f32(.04),abs(f32(math.cos(turn*math.PI))));if turn<.5 {mirror=!mirror}}
		}
	}
	art:=expedition_enemy_costume_art(b,role,time)
	right:=flipbook_camera_right(renderer);normal:=rl.Vector3Normalize(rl.Vector3CrossProduct(right,{0,1,0}))
	base:=rl.Vector3{at.x+.5,.035+lift,at.y+.5}+normal*.065
	draw_expedition_paper(renderer,&art,base,height,mirror,opacity,turn_width)
}

@(private)
draw_expedition_costumes :: proc(renderer:^Renderer,room:^game.Room,w:^world.World) {
	for actor in renderer.tactical.snapshot.enemies[:renderer.tactical.snapshot.enemy_count] {
		if !actor.visible || actor.health<=0 || game.enemy_is_out_of_play(room,actor.entity.id) || !tactical_cell_on_screen(renderer,{x = int(actor.position.x), y = int(actor.position.y)}) {continue}
		if terrain_hides_actor(renderer,actor.position) {continue}
		draw_expedition_costume(renderer,w.biome,actor.archetype,actor.position,actor.entity,w.clock,actor.opacity)
	}
	for &group,g in w.groups[:w.group_count] {for &member,i in group.members[:group.count] {
		if !member.alive || member.deployed || !world.in_scope(w,group.cave) || !tactical_cell_on_screen(renderer,member.enemy.position) {continue}
		if world.ground(w,member.enemy.position)==.Grass && world.distance(room.player.position,member.enemy.position)>3 {continue}
		if terrain_hides_actor(renderer,{f32(member.enemy.position.x),f32(member.enemy.position.y)}) {continue}
		draw_expedition_costume(renderer,w.biome,member.enemy.archetype,expedition_patrol_shown(renderer,g,i,member.enemy.position),game.SYSTEM_ENTITY,w.clock)
	}}
}
