package render

import "core:math"
import "core:c"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import campaign "../campaign"
import game "../game"
import world "../expedition"
import grid "../engine/grid"
import level "../level"

// Whole objects own their meshes independently of the 8x8 terrain chunks.
// Canonical coordinates follow the same mirror/quarter-turn mapping as buildings.
// Every raised part stays on the plan's occupied cells; free cells remain empty.
@(private)
expedition_structure_anchor :: proc(data:^level.Level,index:int)->grid.Position {
	placed:=data.structures[index];plan:=&data.structure_plans[index]
	for y in 0..<plan.height {for x in 0..<plan.width {
		if level.plan_at(plan,x,y)!=.Outside {return grid.offset(placed.origin,x,y)}
	}}
	return placed.origin
}

@(private)
expedition_structure_near :: proc(data:^level.Level,index:int,p:grid.Position,reach:int=30)->bool {
	placed:=data.structures[index];plan:=&data.structure_plans[index]
	return p.x+reach>=placed.origin.x && p.x-reach<placed.origin.x+plan.width &&
		p.y+reach>=placed.origin.y && p.y-reach<placed.origin.y+plan.height
}

@(private)
object_box :: proc(pass:Ink_Pass,frame:Cyber_Building_Frame,p:rl.Vector3,half:rl.Vector2,height:f32,body,cap:rl.Color) {
	bottom,top:[4]rl.Vector3
	for o,i in ([4]rl.Vector2{{-half.x,-half.y},{half.x,-half.y},{half.x,half.y},{-half.x,half.y}}) {
		j:=3-i if frame.placed.mirror else i
		bottom[j]=cyber_building_point(frame,p+{o.x,0,o.y})
		top[j]=cyber_building_point(frame,p+{o.x,height,o.y})
	}
	ink_solid(pass,bottom[:],top[:],body,cap,{})
}

@(private)
object_axle :: proc(pass:Ink_Pass,frame:Cyber_Building_Frame,a,b:rl.Vector3,radius:f32,body,cap:rl.Color) {
	pa,pb:=cyber_building_point(frame,a),cyber_building_point(frame,b)
	right,up:=cyber_link_basis(pa,pb);bottom,top:[8]rl.Vector3
	for i in 0..<8 {
		angle:=f32(i)*math.TAU/8;o:=(right*math.cos(angle)+up*math.sin(angle))*radius
		bottom[i],top[i]=pa+o,pb+o
	}
	ink_solid(pass,bottom[:],top[:],body,cap,{})
	// ink_solid omits its bottom, appropriate for a box resting on the
	// ground. Axles are visible from either end after a quarter turn.
	if pass.mode==.Fill || pass.mode==.Bake {
		if pass.mode==.Fill {_=rlgl.CheckRenderBatchLimit(18);rlgl.Begin(rlgl.TRIANGLES)}
		for i in 1..<7 {ink_triangle(pass,bottom[0],bottom[i],bottom[i+1],cap)}
		if pass.mode==.Fill {rlgl.End()}
	}
}

@(private)
object_profile :: proc(pass:Ink_Pass,frame:Cyber_Building_Frame,p:rl.Vector3,profile:[]rl.Vector2,scale:rl.Vector2,depth:f32,body,cap:rl.Color) {
	indices,count:=ink_profile_triangles(profile);if count==0 {return}
	if pass.mode==.Fill {_=rlgl.CheckRenderBatchLimit(c.int(count*2+len(profile)*6));rlgl.Begin(rlgl.TRIANGLES)}
	front,back:[32]rl.Vector3
	for q,i in profile {front[i]=p+{q.x*scale.x,q.y*scale.y,depth*.5};back[i]=front[i]-{0,0,depth}}
	if pass.mode==.Fill || pass.mode==.Bake {
	for i:=0;i<count;i+=3 {
		a,b,d:=indices[i],indices[i+1],indices[i+2]
		cyber_building_triangle(pass,frame,front[a],front[d],front[b],body)
		cyber_building_triangle(pass,frame,back[a],back[b],back[d],body)
	}
	for a in 0..<len(profile) {
		b:=(a+1)%len(profile)
		cyber_building_quad(pass,frame,back[a],front[a],front[b],back[b],cap,{{0,0},{0,1},{1,1},{1,0}})
	}
	if pass.mode==.Fill {rlgl.End()}
	}
	if pass.mode!=.Fill {
		for i in 0..<len(profile) {ink_line(pass,cyber_building_point(frame,front[i]),cyber_building_point(frame,front[(i+1)%len(profile)]),EXPEDITION_PAPER_INK)}
	}
}

// Uneven masonry joins adjacent occupied cells without bridging the ruin's holes.
// Wall print tags retain the biome's courses on the broken vertical faces.
@(private)
object_broken_wall :: proc(pass:Ink_Pass,frame:Cyber_Building_Frame,plan:^level.Plan,x,y:int,height:f32,body,cap:rl.Color) {
	if pass.mode!=.Fill && pass.mode!=.Bake {return}
	joined:[4]bool
	for d,i in ([4][2]int{{1,0},{0,1},{-1,0},{0,-1}}) {joined[i]=level.plan_at(plan,x+d.x,y+d.y)==.Wall}
	reach:[4]f32
	for n,i in joined {reach[i]=.5 if n else .34}
	base:=rl.Vector3{f32(x)+.5,0,f32(y)+.5}
	bottom:=[4]rl.Vector3{base+{-reach[2],0,-reach[3]},base+{reach[0],0,-reach[3]},base+{reach[0],0,reach[1]},base+{-reach[2],0,reach[1]}}
	top:[4]rl.Vector3
	for q,i in bottom {top[i]=q+{0,height-f32((i+x+y)%3)*.10,0}}
	if pass.mode==.Fill {_=rlgl.CheckRenderBatchLimit(30);rlgl.Begin(rlgl.TRIANGLES)}
	for i in 0..<4 {
		j:=(i+1)%4
		cyber_building_quad(pass,frame,bottom[i],top[i],top[j],bottom[j],body,{{4,0},{4,1},{5,1},{5,0}})
	}
	cyber_building_quad(pass,frame,top[0],top[3],top[2],top[1],cap,{{0,0},{0,1},{1,1},{1,0}})
	if pass.mode==.Fill {rlgl.End()}
}

// Thin rails replace opaque fence cubes. Neighbours choose the connected arms;
// the centre post makes an isolated fence a readable obstacle as well.
@(private)
expedition_fence :: proc(pass:Ink_Pass,p:rl.Vector3,joined:[4]bool,body,cap:rl.Color,height:f32=STRUCTURE_FENCE_HEIGHT) {
	ink_box(pass,p,{.075,.075},height,0,body,cap,{})
	any:=false
	for n in joined {any=any || n}
	links:=joined
	if !any {links[0]=true;links[2]=true}
	for linked,i in links {
		if !linked {continue}
		x:=i==0 || i==2;sign:=f32(1) if i<2 else -1
		o:=rl.Vector3{.25*sign,0,0} if x else rl.Vector3{0,0,.25*sign}
		half:=rl.Vector2{.25,.045} if x else rl.Vector2{.045,.25}
		for y in ([2]f32{height*.25,height*.70}) {ink_box(pass,p+o+{0,y,0},half,height*.12,0,body,cap,{})}
	}
}

@(private)
draw_expedition_loose_fence :: proc(pass:Ink_Pass,data:^level.Level,cell:grid.Position,biome:campaign.Biome) {
	joined:[4]bool
	for d,i in ([4]grid.Position{{x=1,y=0},{x=0,y=1},{x=-1,y=0},{x=0,y=-1}}) {
		tile,ok:=level.tile_at(data,game.add_position(cell,d));joined[i]=ok && (tile.kind==.Fence || tile.kind==.Wall || tile.kind==.Door)
	}
	body,cap:=structure_print_palette(biome)
	expedition_fence(pass,{f32(cell.x)+.5,0,f32(cell.y)+.5},joined,body,cap)
}

@(private)
draw_expedition_structure_object :: proc(pass:Ink_Pass,data:^level.Level,index:int,biome:campaign.Biome) {
	placed:=data.structures[index]
	if level.structure_is_building(placed.id) {return}
	frame:=cyber_building_frame(placed);body,cap:=structure_print_palette(biome)
	dark:=ink_scale(body,.56)
	switch placed.id {
	case .Cart:
		// The wheels and the two protruding handles fit the original 2x1 plan.
		if biome==.Snow {
			for z in ([2]f32{.20,.80}) {
				runner:=[6]rl.Vector2{{-.84,0},{-.89,.12},{-.68,.21},{.74,.21},{.87,.10},{.74,0}}
				object_profile(pass,frame,{1,.025,z},runner[:],{1,1},.10,body,cap)
			}
		} else {
			for z in ([2]f32{.14,.86}) {
				object_axle(pass,frame,{.97,.19,z-.065},{.97,.19,z+.065},.18,dark,dark)
				object_axle(pass,frame,{.97,.19,z-.07},{.97,.19,z+.07},.065,cap,cap)
			}
		}
		object_box(pass,frame,{1.10,.22,.5},{.62,.31},.10,dark,cap)
		for z in ([2]f32{.20,.80}) {object_box(pass,frame,{1.10,.32,z},{.62,.045},.17,body,cap)}
		for x in ([2]f32{.52,1.68}) {object_box(pass,frame,{x,.32,.5},{.04,.26},.17,body,cap)}
		for z in ([2]f32{.31,.69}) {object_box(pass,frame,{.28,.23,z},{.23,.04},.075,body,cap)}
		// Industrial cargo has a lid and a painted control panel, wood carts stay open.
		if biome==.Cyber || biome==.Space || biome==.City {
			object_box(pass,frame,{1.10,.32,.5},{.46,.20},.13,body,cap)
			object_box(pass,frame,{1.28,.45,.5},{.10,.09},.025,CYBER_RED_FACE,CYBER_RED_FACE)
		}
	case .Fountain:
		// Four rim walls leave actual water visible, rather than a solid 2x2 cap.
		for z in ([2]f32{.17,1.83}) {object_box(pass,frame,{1,0,z},{.94,.11},.42,body,cap)}
		for x in ([2]f32{.17,1.83}) {object_box(pass,frame,{x,0,1},{.11,.72},.42,body,cap)}
		water:=rl.Color{71,153,183,255}
		if biome==.Inferno {water={233,123,63,255}}
		if biome==.Gothic || biome==.Secret {water={139,117,186,255}}
		if biome==.Snow || biome==.Sky {water={141,207,220,255}}
		object_box(pass,frame,{1,.23,1},{.71,.71},.025,water,water)
		object_box(pass,frame,{1,.255,1},{.16,.16},.075,body,cap)
		object_axle(pass,frame,{1,.33,1},{1,.42,1},.08,water,cap)
		for z in ([2]f32{.55,1.45}) {object_box(pass,frame,{1,.26,z},{.25,.018},.008,cap,cap)}
	case .Statue:
		object_box(pass,frame,{1,0,1},{.83,.76},.16,body,cap)
		object_box(pass,frame,{1,.16,1},{.62,.57},.19,body,cap)
		object_box(pass,frame,{1,.35,1},{.45,.43},.20,body,cap)
		// A figure carved from one broad profile, with a separate head and crossed arms.
		figure:=[12]rl.Vector2{{-.32,0},{-.39,.18},{-.31,.50},{-.48,.72},{-.40,.90},{-.19,.80},
			{.19,.80},{.40,.90},{.48,.72},{.31,.50},{.39,.18},{.32,0}}
		object_profile(pass,frame,{1,.55,1},figure[:],{1,1},.36,cap,body)
		object_axle(pass,frame,{1,1.46,.82},{1,1.46,1.18},.22,body,cap)
		if biome==.Egypt || biome==.Sky {object_box(pass,frame,{1,1.67,1},{.31,.20},.08,body,cap)}
		if biome==.Cyber || biome==.Space {object_box(pass,frame,{1,1.43,1.19},{.14,.022},.065,CYBER_SCREEN,CYBER_SCREEN)}
	case .Machine:
		// Broad engine/oven body, a taller stack and a side drive give the 3x2
		// object a distinct functional silhouette in every camera quarter turn.
		object_box(pass,frame,{1.5,0,1},{1.35,.82},.15,dark,cap)
		body_profile:=[6]rl.Vector2{{-1,0},{-1,.58},{-.70,.85},{.69,.85},{1,.57},{1,0}}
		object_profile(pass,frame,{1.55,.15,1},body_profile[:],{.93,.98},1.18,body,cap)
		if biome==.Cyber || biome==.Space || biome==.City {
			object_box(pass,frame,{.51,.15,1},{.26,.44},.90,body,cap)
			object_box(pass,frame,{1.62,.55,1.61},{.40,.025},.22,CYBER_RECESS,CYBER_SCREEN)
			for x in ([3]f32{1.20,1.60,2.0}) {object_box(pass,frame,{x,.22,1.61},{.10,.028},.09,CYBER_YELLOW,CYBER_YELLOW)}
		} else if biome==.Inferno || biome==.Gothic || biome==.Egypt {
			object_box(pass,frame,{.55,.15,.74},{.25,.27},.90,dark,cap)
			mouth:=[6]rl.Vector2{{-.37,0},{-.37,.32},{-.22,.47},{.22,.47},{.37,.32},{.37,0}}
			object_profile(pass,frame,{1.60,.23,1.604},mouth[:],{1,1},.018,dark,dark)
			object_box(pass,frame,{1.60,.25,1.62},{.27,.018},.09,{213,108,65,255},{237,176,93,255})
		} else {
			object_axle(pass,frame,{.48,.56,.45},{.48,.56,1.55},.42,body,cap)
			object_axle(pass,frame,{2.48,.55,.51},{2.48,.55,1.49},.37,body,cap)
			object_box(pass,frame,{1.5,.99,1},{.42,.58},.055,cap,cap)
		}
	case .Ruin:
		canonical:=placed;canonical.rotation=0;canonical.mirror=false;plan:=level.placed_plan(canonical)
		for y in 0..<plan.height {for x in 0..<plan.width {
			cell:=level.plan_at(&plan,x,y);if cell!=.Wall && cell!=.Fence {continue}
			h:=f32(.98)-f32((x+y*3)%4)*.14 if cell==.Wall else .36
			object_broken_wall(pass,frame,&plan,x,y,h,body,cap)
			object_box(pass,frame,{f32(x)+.75,.015,f32(y)+.87},{.17,.09},.11,body,cap)
		}}
	case .Pen:
		plan:=&data.structure_plans[index]
		for y in 0..<plan.height {for x in 0..<plan.width {
			if level.plan_at(plan,x,y)!=.Fence {continue}
			joined:[4]bool
			for d,i in ([4][2]int{{1,0},{0,1},{-1,0},{0,-1}}) {joined[i]=level.plan_at(plan,x+d.x,y+d.y)==.Fence}
			expedition_fence(pass,{f32(placed.origin.x+x)+.5,0,f32(placed.origin.y+y)+.5},joined,body,cap)
		}}
	case .Cottage,.Hut,.Temple,.Count:
	}
}

// Used only when GPU cache preparation fails. Whole-object culling avoids
// dropping a large object merely because its first occupied cell is offscreen.
@(private)
draw_expedition_object_fallback :: proc(pass:Ink_Pass,renderer:^Renderer,room:^game.Room,w:^world.World,layer:Ink_Layer,collect:bool=false) {
	data:=room.level_data;m:=renderer.tactical.expedition_material
	for placed,i in data.structures {
		if level.structure_is_building(placed.id) || !expedition_structure_near(data,i,room.player.position) {continue}
		anchor:=expedition_structure_anchor(data,i);plan:=&data.structure_plans[i]
		chunk:=Expedition_Geometry_Chunk{center={f32(placed.origin.x)+f32(plan.width)*.5,cell_ground(anchor)+1,f32(placed.origin.y)+f32(plan.height)*.5},
			radius=math.sqrt(f32(plan.width*plan.width+plan.height*plan.height))*.5+1}
		if !collect {
			if !expedition_chunk_visible(&renderer.tactical.draw_frustum,&chunk,m!=nil && m.reflection_pass) {continue}
			if layer!=.Edges && expedition_chunk_revealed(m,&chunk)!=(layer==.Revealed) {continue}
		}
		ground:=pass;ground.lift=cell_ground(anchor)
		draw_expedition_structure_object(ground,data,i,w.biome)
	}
}
