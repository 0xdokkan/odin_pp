package render

import "core:math"
import rl "vendor:raylib"
import campaign "../campaign"
import world "../expedition"
import game "../game"
import grid "../engine/grid"
import level "../level"

// Small authored groups live in the existing architecture chunk. A 4x4
// region has at most one candidate, with quiet regions between groups.
// Selection never reads actors, animation time, encounters or game RNG.
@(private)
expedition_ground_art_selected :: proc(data:^level.Level,w:^world.World,cell:grid.Position)->(hash:u32,selected:bool) {
	if data==nil || w==nil || cell.layer!=grid.GROUND_LAYER {return}
	patch:=grid.Position{x = cell.x/4,y = cell.y/4}
	hash=expedition_cell_hash(patch,0x6172+u32(w.biome))
	if hash%3==0 || cell.x%4!=int((hash>>3)%4) || cell.y%4!=int((hash>>7)%4) {return}
	tile,ok:=level.tile_at(data,cell);if !ok || tile.kind!=.Floor {return}
	if data.has_player_spawn && world.distance(cell,data.player_spawn)<=2 {return}
	if _,inside:=level.structure_index_at(data,cell);inside {return}
	terrain:=game.expedition_terrain(u8(w.biome),cell)
	if terrain!=.Plain && terrain!=.Grass && terrain!=.Sand && terrain!=.Snow {return}
	// Doorways, map edges and drop-offs keep their full visible floor.
	beside_wall:=false
	for d in ([4]grid.Position{{x = 1},{x = -1},{y = 1},{y = -1}}) {
		adjacent,found:=level.tile_at(data,game.add_position(cell,d))
		if !found || adjacent.kind==.Void || adjacent.kind==.Door || adjacent.kind==.Exit || adjacent.kind==.Player_Spawn {return}
		beside_wall=beside_wall || adjacent.kind==.Wall || adjacent.kind==.Fence
	}
	if index,design:=world.site_at(w,cell);index>=0 {
		// Courtyard life gathers beside real walls. Platforms, approaches,
		// gates and the interaction's central breathing space remain clear.
		if !beside_wall || world.distance(cell,w.sites[index].position)<=4 {return}
		if design.surface!=.Courtyard && design.surface!=.Garden && design.surface!=.Ruin {return}
	}
	return hash,true
}

// Every vertex follows the sculpted surface, including ramps. point_ground
// takes cell-centred coordinates, while mesh vertices use world coordinates.
@(private)
ground_art_triangle :: proc(pass:Ink_Pass,a,b,c:rl.Vector3,color:rl.Color) {
	p,q,r:=a,b,c
	p.y+=point_ground({p.x-.5,p.z-.5})+.003
	q.y+=point_ground({q.x-.5,q.z-.5})+.003
	r.y+=point_ground({r.x-.5,r.z-.5})+.003
	ink_triangle(pass,p,q,r,color)
}

@(private)
ground_art_leaf :: proc(pass:Ink_Pass,root:rl.Vector3,width,length,height,yaw:f32,ink,fill:rl.Color) {
	points:=[4]rl.Vector3{{0,0,0},{-width,height*.52,length*.44},{width*.17,height,length},{width,height*.48,length*.48}}
	for &p in points {p=cyber_point(root,p,yaw)}
	ground_art_triangle(pass,points[0],points[1],points[2],ink)
	ground_art_triangle(pass,points[0],points[2],points[3],ink)
	// A broad painted half-leaf leaves a stable dark edge and central vein.
	a:=cyber_point(root,{0,.004,length*.11},yaw)
	b:=cyber_point(root,{-width*.68,height*.52+.004,length*.46},yaw)
	c:=cyber_point(root,{width*.10,height*.88+.004,length*.88},yaw)
	ground_art_triangle(pass,a,b,c,fill)
}

@(private)
ground_art_stone :: proc(pass:Ink_Pass,base:rl.Vector3,width,depth,height,yaw:f32,ink,fill:rl.Color) {
	profile:=[5]rl.Vector2{{-.88,-.32},{-.30,-.84},{.76,-.62},{1,.38},{-.53,.80}}
	peak:=base+rl.Vector3{width*.07,height,depth*.02}
	for v,i in profile {
		u:=profile[(i+1)%len(profile)]
		a:=cyber_point(base,{v.x*width,0,v.y*depth},yaw)
		b:=cyber_point(base,{u.x*width,0,u.y*depth},yaw)
		ground_art_triangle(pass,a,peak,b,fill if i<2 else ink)
	}
}

@(private)
ground_art_chip :: proc(pass:Ink_Pass,base:rl.Vector3,width,length,yaw:f32,ink,fill:rl.Color) {
	// A torn, slightly curled scrap; three points lift its edge by 3 cm.
	a:=cyber_point(base,{-width,0,-length*.45},yaw)
	b:=cyber_point(base,{-width*.65,.025,length*.53},yaw)
	c:=cyber_point(base,{width*.75,.035,length*.39},yaw)
	d:=cyber_point(base,{width,.004,-length*.39},yaw)
	ground_art_triangle(pass,a,b,c,ink);ground_art_triangle(pass,a,c,d,ink)
	ground_art_triangle(pass,a+{width*.13,.004,length*.12},b+{width*.13,.004,-length*.12},c+{-width*.13,.004,-length*.08},fill)
}

@(private)
expedition_ground_art_cell :: proc(builder:^Expedition_Geometry_Builder,biome:campaign.Biome,cell:grid.Position,hash:u32) {
	pass:=Ink_Pass{mode=.Bake,builder=builder}
	base:=rl.Vector3{f32(cell.x)+.46+f32((hash>>12)%3)*.04,0,f32(cell.y)+.46+f32((hash>>15)%3)*.04}
	yaw:=f32((hash>>18)%8)*math.PI/4
	#partial switch biome {
	case .Cyber:
		ground_art_leaf(pass,base,.07,.31,.105,yaw,{35,96,87,255},{91,155,103,255})
		ground_art_leaf(pass,base+{.07,0,-.03},.055,.23,.07,yaw+2.0,{35,96,87,255},{156,180,104,255})
		ground_art_chip(pass,base+{-.13,0,.13},.06,.14,yaw-.6,{142,90,76,255},{222,147,105,255})
	case .West:
		for i in 0..<3 {ground_art_leaf(pass,base+{f32(i-1)*.045,0,0},.027,.22+f32(i%2)*.07,.10-f32(i)*.018,yaw+f32(i)*1.4,{139,98,57,255},{209,164,78,255})}
		ground_art_stone(pass,base+{-.15,0,-.14},.085,.07,.045,yaw,{154,101,68,255},{220,157,95,255})
	case .Jungle:
		ground_art_leaf(pass,base,.11,.32,.09,yaw,{41,103,64,255},{113,171,72,255})
		ground_art_leaf(pass,base+{.05,0,-.04},.085,.25,.07,yaw+2.3,{41,103,64,255},{174,187,92,255})
		ground_art_stone(pass,base+{-.15,0,.10},.06,.075,.04,yaw,{101,121,67,255},{175,182,104,255})
	case .City:
		ground_art_chip(pass,base,.12,.30,yaw,{110,101,146,255},{213,172,177,255})
		ground_art_chip(pass,base+{-.15,0,.13},.07,.18,yaw+1.7,{89,123,148,255},{158,190,195,255})
	case .Egypt:
		ground_art_stone(pass,base,.15,.12,.08,yaw,{168,132,74,255},{226,186,119,255})
		ground_art_stone(pass,base+{-.17,0,.16},.07,.09,.04,yaw+.6,{168,132,74,255},{240,207,145,255})
		ground_art_leaf(pass,base+{.13,0,.08},.022,.20,.025,yaw+1.1,{151,116,70,255},{196,160,91,255})
	case .Vietnam:
		for i in 0..<3 {ground_art_leaf(pass,base+{f32(i-1)*.04,0,0},.045,.28,.105-f32(i)*.02,yaw+f32(i)*1.9,{71,111,55,255},{140,167,79,255})}
	case .Snow:
		ground_art_stone(pass,base,.13,.11,.085,yaw,{109,155,178,255},{208,226,224,255})
		ground_art_stone(pass,base+{-.15,0,.15},.07,.075,.045,yaw+.7,{134,175,195,255},{225,233,225,255})
		ground_art_leaf(pass,base+{.11,0,.05},.019,.21,.03,yaw+1.7,{116,130,147,255},{166,160,157,255})
	case .Inferno:
		for i in 0..<3 {ground_art_stone(pass,base+{f32(i-1)*.12,0,f32(i%2)*.16},.09-f32(i)*.01,.10,.07-f32(i)*.015,yaw+f32(i),{91,57,80,255},{166,102,105,255})}
	case .Gothic:
		ground_art_leaf(pass,base,.095,.30,.06,yaw,{100,80,109,255},{160,113,126,255})
		ground_art_leaf(pass,base+{-.10,0,.10},.06,.22,.035,yaw+2.1,{100,80,109,255},{188,149,130,255})
	case .Sky:
		ground_art_leaf(pass,base,.055,.33,.07,yaw,{177,158,174,255},{235,209,181,255})
		ground_art_leaf(pass,base+{-.11,0,.10},.035,.24,.035,yaw+2.0,{177,158,174,255},{245,228,198,255})
	case .Space:
		ground_art_stone(pass,base,.13,.10,.105,yaw,{101,79,156,255},{161,139,201,255})
		ground_art_chip(pass,base+{-.13,0,.16},.06,.20,yaw+1.1,{78,126,158,255},{133,182,197,255})
	case .Secret:
		ground_art_chip(pass,base,.09,.28,yaw,{148,115,87,255},{218,178,111,255})
		ground_art_leaf(pass,base+{-.12,0,.14},.075,.23,.055,yaw+1.9,{108,83,137,255},{174,141,172,255})
	}
}
