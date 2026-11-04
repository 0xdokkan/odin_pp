package application

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import artifacts "../devtools/artifacts"
import game "../game"
import campaign "../campaign"
import grid "../engine/grid"
import host "../engine/host"
import input "../engine/input"
import level "../level"
import render "../render"
import run "../run"
import world "../expedition"

// A bounded native walkthrough of the real Cyber map. Relocations only set
// up separate acts; the entrance/interior/exit transitions use actual WASD,
// the expedition update, continuous movement, collisions and interaction.
@(private)
Cyber_Scene_Capture :: struct {
	wrapped:host.Scene,
	stage,frames,settled:int,
	workshop,hut:int,
	door,outward:grid.Position,
	target:grid.Position,
	path:[256]grid.Position,
	path_count,path_at:int,
	walking:bool,
	start:[2]f32,
	atlas:[6]u32,
	stock:u32,
	biome:campaign.Biome,
	card_probe:u32,
	card_target:grid.Position,
	card_played:bool,
}

@(private)
CYBER_SCENE_NAMES :: [12]string{
	"officina_ingresso","officina_percorso","officina_interazione","officina_uscita",
	"rifugio_fuori","rifugio_soglia","rifugio_dentro","rifugio_uscita",
	"rilievo","scontro","scontro_movimento","officina_lato",
}

@(private)
expedition_enable_cyber_scene_smoke :: proc(scene:^host.Scene,biome:campaign.Biome=.Cyber) {
	s:=new(Cyber_Scene_Capture);s.wrapped=scene^;s.biome=biome
	e:=cast(^run.Expedition_Session)scene.data
	rl.SetWindowSize(1024,576)
	cyber_scene_prepare(s,e)
	scene^=host.Scene{name="cyber-scene-smoke",data=s,opaque=true,modal=true,
		update=cyber_scene_update,draw=cyber_scene_draw,after_present=cyber_scene_present,
		destroy=proc(data:rawptr){s:=cast(^Cyber_Scene_Capture)data;s.wrapped.destroy(s.wrapped.data);free(s)}}
}

@(private)
cyber_scene_set_target :: proc(s:^Cyber_Scene_Capture,e:^run.Expedition_Session,p:grid.Position) {
	assert(!game.cell_blocks_movement(&e.rs.room,p),"Cyber walkthrough target is blocked")
	s.target=p;s.walking=true;s.start=world.roam_center(e.rs.room.player.position)
	s.settled=0
	s.path_count=0;s.path_at=0
	if s.stage>=5 && s.stage<=7 {
		// Walk round the real outside props instead of pushing a straight
		// line through them. Only the test driver chooses the waypoints;
		// ordinary keyboard input and collision still perform every step.
		data:=e.rs.room.level_data;width:=data.tiles.width
		parents:=make([]int,len(data.tiles.cells));defer delete(parents)
		queue:=make([]int,len(parents));defer delete(queue)
		for &parent in parents {parent=-1}
		start:=e.rs.room.player.position.y*width+e.rs.room.player.position.x
		goal:=p.y*width+p.x
		parents[start]=start;queue[0]=start;head,tail:=0,1
		for head<tail && parents[goal]<0 {
			i:=queue[head];head+=1
			from:=grid.Position{x=i%width,y=i/width}
			for d in ([4]grid.Position{{x=1},{x=-1},{y=1},{y=-1}}) {
				next:=game.add_position(from,d)
				if next.x<0 || next.y<0 || next.x>=width || next.y>=data.tiles.height {continue}
				j:=next.y*width+next.x
				if parents[j]>=0 || game.cell_blocks_movement(&e.rs.room,next) || game.step_height_blocked(&e.rs.room,from,next) {continue}
				parents[j]=i;queue[tail]=j;tail+=1
			}
		}
		assert(parents[goal]>=0,"No real walking route between building and outside target")
		for at:=goal;at!=start;at=parents[at] {
			assert(s.path_count<len(s.path),"Building walkthrough route exceeded its bound")
			s.path[s.path_count]={x=at%width,y=at/width};s.path_count+=1
		}
		for i in 0..<s.path_count/2 {j:=s.path_count-1-i;s.path[i],s.path[j]=s.path[j],s.path[i]}
	}
}

@(private)
cyber_scene_prepare :: proc(s:^Cyber_Scene_Capture,e:^run.Expedition_Session) {
	s.frames=0;s.settled=0;s.walking=false
	switch s.stage {
	case 0,11:
		expedition_smoke_workshop(e,s.biome)
		s.workshop=-1
		for site,i in e.world.sites[:e.world.site_count] {if site.kind==.Workshop {s.workshop=i;break}}
		assert(s.workshop>=0,"Cyber map has no workshop")
		e.rs.room.player.position=world.site_world(&e.world.sites[s.workshop],{x=0,y=10})
		e.roam={};e.rs.iso_renderer.tactical.expedition_follow_ready=false
		if s.stage==11 {
			e.rs.room.player.position=world.site_world(&e.world.sites[s.workshop],{x=-5,y=1})
			e.rs.iso_renderer.tactical.world_orbit.yaw-=.6
		}
	case 1:cyber_scene_set_target(s,e,world.site_world(&e.world.sites[s.workshop],{x=0,y=2}))
	case 2: // E is injected by the ordinary update below.
	case 3:
		e.site=-1
		cyber_scene_set_target(s,e,world.site_world(&e.world.sites[s.workshop],{x=0,y=10}))
	case 4:
		expedition_smoke_structures(e,0,s.biome);e.roam={}
		s.hut=-1;data:=e.rs.room.level_data
		for placed,i in data.structures {if placed.id==.Hut {s.hut=i;break}}
		assert(s.hut>=0,"Cyber map has no hut")
		placed:=data.structures[s.hut];plan:=&data.structure_plans[s.hut]
		for y in 0..<plan.height {for x in 0..<plan.width {
			if level.plan_at(plan,x,y)!=.Door {continue}
			s.door=grid.offset(placed.origin,x,y)
			for d in ([4]grid.Position{{x=1},{x=-1},{y=1},{y=-1}}) {
				if level.plan_at(plan,x+d.x,y+d.y)==.Outside {s.outward=d}
			}
		}}
	case 5:cyber_scene_set_target(s,e,s.door)
	case 6:cyber_scene_set_target(s,e,grid.offset(s.door,-s.outward.x*2,-s.outward.y*2))
	case 7:cyber_scene_set_target(s,e,grid.offset(s.door,s.outward.x*6,s.outward.y*6))
	case 8:expedition_smoke_relief(e,s.biome);e.roam={}
	case 9:expedition_smoke_cartoon(e,s.biome);e.roam={}
	case 10:
	}
}

@(private)
cyber_scene_update :: proc(data:rawptr,frame:^host.Frame) {
	s:=cast(^Cyber_Scene_Capture)data;e:=cast(^run.Expedition_Session)s.wrapped.data
	keys:=input.Device_Snapshot{focused=true}
	actual:=frame^;actual.focused=true;actual.window_focused=true
	actual.dt=1.0/60
	if s.walking {
		world.roam_sync(&e.roam,&e.rs.room)
		for s.path_at<s.path_count && rl.Vector2Distance(rl.Vector2(world.roam_center(s.path[s.path_at])),rl.Vector2(e.roam.position))<.13 {s.path_at+=1}
		next:=s.path[s.path_at] if s.path_at<s.path_count else s.target
		delta:=world.roam_center(next)-e.roam.position
		distance:=math.sqrt(delta.x*delta.x+delta.y*delta.y)
		if s.path_at>=s.path_count && distance<.19 {s.settled+=1} else {
			s.settled=0
			camera:=e.rs.iso_renderer.tactical.camera
			forward:=[2]f32{camera.target.x-camera.position.x,camera.target.z-camera.position.z}
			length:=math.sqrt(forward.x*forward.x+forward.y*forward.y)
			if length>.001 {
				forward/=length;right:=[2]f32{-forward.y,forward.x}
				// Choose the nearest of the eight directions an actual keyboard
				// can express; feedback corrects the camera's oblique yaw.
				best:=f32(-2);side,ahead:=0,0
				for y in -1..=1 {for x in -1..=1 {
					if x==0 && y==0 {continue}
					wish:=right*f32(x)+forward*f32(y)
					score:=(wish.x*delta.x+wish.y*delta.y)/math.sqrt(wish.x*wish.x+wish.y*wish.y)/distance
					if score>best {best=score;side=x;ahead=y}
				}}
				keys.keys_down[.D]=side>0;keys.keys_down[.A]=side<0
				keys.keys_down[.W]=ahead>0;keys.keys_down[.S]=ahead<0
			}
		}
	}
	if s.stage==2 && s.frames==0 {keys.keys_pressed[.E]=true}
	if s.stage==10 {
		// Select a genuinely legal offensive card with its hand shortcut,
		// then click its real projected ground target. No damage is injected.
		if !s.card_played && s.frames%15==0 {
			hotkeys:=[8]rl.KeyboardKey{.ONE,.TWO,.THREE,.FOUR,.FIVE,.SIX,.SEVEN,.EIGHT}
			room:=&e.rs.room
			found:for card,i in room.player.deck.hand[:min(8,room.player.deck.hand_count)] {
				definition,ok:=game.card_definition_by_id(card.definition_id)
				if !ok || game.card_is_room_tool(card.definition_id) {continue}
				for enemy in room.enemies {
					if enemy.health<=0 {continue}
					evaluation:=game.evaluate_card_targeting(room,card,game.card_target_request_at(definition,enemy.position))
					hits:=game.card_hit_enemies(room,card,&evaluation)
					if hits.count==0 {continue}
					s.card_probe=card.id;s.card_target=enemy.position
					keys.keys_pressed[hotkeys[i]]=true
					break found
				}
			}
		} else if !s.card_played && s.card_probe!=0 && s.frames%15==1 {
			p:=render.tactical_project(&e.rs.iso_renderer,{f32(s.card_target.x)+.5,f32(s.card_target.y)+.5})
			actual.mouse={p.x,p.y};actual.mouse_inside=true
			keys.buttons_pressed[.LEFT]=true;keys.buttons_down[.LEFT]=true
		}
		if s.card_played && s.frames<100 {keys.keys_down[.W]=true;keys.keys_down[.D]=true}
	}
	actual.devices=&keys
	s.wrapped.update(s.wrapped.data,&actual)
	if s.stage==10 && s.card_probe!=0 && !s.card_played {
		in_hand:=false
		for card in e.rs.room.player.deck.hand[:e.rs.room.player.deck.hand_count] {in_hand=in_hand || card.id==s.card_probe}
		if !in_hand {s.card_played=true;fmt.printfln("CYBER SCENE card played through keyboard and mouse: id=%d target=%v",s.card_probe,s.card_target)}
	}
}

@(private)
cyber_scene_draw :: proc(data:rawptr,frame:^host.Frame) {
	s:=cast(^Cyber_Scene_Capture)data;s.wrapped.draw(s.wrapped.data,frame)
}

@(private)
cyber_scene_present :: proc(data:rawptr,frame:^host.Frame) {
	s:=cast(^Cyber_Scene_Capture)data;e:=cast(^run.Expedition_Session)s.wrapped.data
	s.frames+=1
	prefix:="cyber" if s.biome==.Cyber else "west"
	if s.frames==899 {fmt.printfln("ILLUSTRATED SCENE blocked biome=%v stage=%d target=%v actual=%v path=%d/%d",s.biome,s.stage,s.target,e.roam.position,s.path_at,s.path_count)}
	assert(s.frames<900,"Native Cyber walkthrough failed to reach a target through the real collisions")
	if s.walking && (s.frames==30 || s.frames==60 || s.frames==90) {
		artifacts.screenshot(fmt.ctprintf("odin_pp_%s_scene_%02d_motion_%03d.png",prefix,s.stage,s.frames))
	}
	if s.walking && s.settled<25 {return}
	if s.frames<(180 if s.stage==10 else 60) {return}
	if s.walking {
		assert(e.rs.room.player.position==s.target,"Keyboard walkthrough missed its target cell")
		delta:=e.roam.position-s.start
		assert(delta.x*delta.x+delta.y*delta.y>1,"The walkthrough must move, not only redraw a relocated actor")
	}
	if s.stage==2 {assert(e.site==s.workshop,"E did not open the actual workshop interaction")}
	if s.stage==10 {assert(s.card_played,"Cyber combat walkthrough did not play a card through the real input path")}
	if s.stage>=4 && s.stage<=7 {
		v:=game.structure_visibility(e.rs.room.level_data,s.hut,e.roam.position)
		if s.stage==6 {assert(v.stage==.Inside && !v.roof,"Walking inside did not remove the roof")}
		if s.stage==4 || s.stage==7 {assert(v.stage==.Far && v.roof,"The exterior roof did not return")}
		fmt.printfln("CYBER SCENE building stage=%d visibility=%v roof=%v position=%v",s.stage,v.stage,v.roof,e.roam.position)
	}
	if s.stage==0 {
		m:=e.rs.iso_renderer.tactical.expedition_material
		s.atlas={m.cartoon.print.id,m.cartoon.paper.id,m.fixtures.print.id,m.fixtures.paper.id,m.fixtures.hero_print.id,m.fixtures.hero_paper.id}
		s.stock=e.rs.iso_renderer.tactical.expedition_floor.workshop_stock[int(s.biome)].id
		assert(s.stock!=0,"Precomputed workshop painting missing")
		stock:=e.rs.iso_renderer.tactical.expedition_floor.workshop_stock[int(s.biome)]
		assert(stock.width==1024 && stock.height==1024 && stock.mipmaps==11,"Workshop painting needs complete filtering levels")
		assert(render.expedition_render_smoke_check(&e.rs.iso_renderer),"Cyber HDR contract failed")
	}
	if s.stage==3 {
		m:=e.rs.iso_renderer.tactical.expedition_material
		assert(s.atlas==[6]u32{m.cartoon.print.id,m.cartoon.paper.id,m.fixtures.print.id,m.fixtures.paper.id,m.fixtures.hero_print.id,m.fixtures.hero_paper.id},"Walking or interaction rebuilt the immutable atlases")
		assert(s.stock==e.rs.iso_renderer.tactical.expedition_floor.workshop_stock[int(s.biome)].id,"Walking or interaction rebuilt the static ground painting")
	}
	names:=CYBER_SCENE_NAMES
	artifacts.screenshot(fmt.ctprintf("odin_pp_%s_scene_%02d_%s.png",prefix,s.stage,names[s.stage]))
	fmt.printfln("ILLUSTRATED SCENE biome=%v complete stage=%d name=%s frames=%d cell=%v",s.biome,s.stage,names[s.stage],s.frames,e.rs.room.player.position)
	s.stage+=1
	if s.stage>=len(CYBER_SCENE_NAMES) {host.quit(frame);return}
	cyber_scene_prepare(s,e)
}
