package application

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import artifacts "../devtools/artifacts"
import game "../game"
import grid "../engine/grid"
import host "../engine/host"
import input "../engine/input"
import level "../level"
import render "../render"
import run "../run"
import world "../expedition"

// Diagnostic only. One generated world and one initial placement; every
// following displacement goes through the existing scene's keyboard lane.
// Reuse the established eight-direction WASD controller and card click probe.
@(private)
Cyber_Walk_Capture :: struct {
	base: Cyber_Scene_Capture,
	total_frames, moving_frames: int,
	started, first_present: f64,
	geometry_id: u64,
	outside, relief: grid.Position,
	combat_group: int,
	combat_moved: bool,
	move_from, move_to: grid.Position,
	move_pending: bool,
	limit: string,
}

@(private)
cyber_walk_danger :: proc(w:^world.World,p:grid.Position)->bool {
	for &group in w.groups[:w.group_count] {
		if group.cave!=0 {continue}
		for member in group.members[:group.count] {
			if member.alive && world.distance(p,member.enemy.position)<=7 {return true}
		}
	}
	for site in w.sites[:w.site_count] {
		if site.active && site.kind==.Nest && site.state!=.Resolved &&
			world.distance(p,site.position)<=world.site_layout(site.kind).trigger_radius+1 {return true}
	}
	return false
}

// Ground-only diagnostic path. Real height steps and layer transitions are
// queried; a path through an underground shortcut cannot be reported as a
// continuous outdoor walk. Patrols remain live and can invalidate this plan.
@(private)
cyber_walk_tree :: proc(e:^run.Expedition_Session,start:grid.Position,avoid_foes:bool,parents,distances:[]int) {
	data:=e.rs.room.level_data;width:=data.tiles.width
	for &p in parents {p=-1};for &d in distances {d=-1}
	queue:=make([]int,len(parents));defer delete(queue)
	index,inside:=grid.cell_index(start,width,data.tiles.height);if !inside {return}
	parents[index]=index;distances[index]=0;queue[0]=index;head,tail:=0,1
	for head<tail {
		i:=queue[head];head+=1;from:=grid.Position{x=i%width,y=i/width}
		for d in ([4]grid.Position{{x=1},{x=-1},{y=1},{y=-1}}) {
			next,_:=game.layer_step(&e.rs.room,from,d)
			if next.layer!=0 {continue}
			j,ok:=grid.cell_index(next,width,data.tiles.height)
			if !ok || parents[j]>=0 || game.cell_blocks_movement(&e.rs.room,next) || game.step_height_blocked(&e.rs.room,from,next) {continue}
			if avoid_foes && cyber_walk_danger(&e.world,next) {continue}
			parents[j]=i;distances[j]=distances[i]+1;queue[tail]=j;tail+=1
		}
	}
}

@(private)
cyber_walk_target :: proc(s:^Cyber_Walk_Capture,e:^run.Expedition_Session,p:grid.Position,avoid_foes:bool=true) {
	b:=&s.base;data:=e.rs.room.level_data;width:=data.tiles.width
	parents:=make([]int,len(data.tiles.cells));defer delete(parents)
	distances:=make([]int,len(parents));defer delete(distances)
	cyber_walk_tree(e,e.rs.room.player.position,avoid_foes,parents,distances)
	goal,ok:=grid.cell_index(p,width,data.tiles.height)
	if !ok || parents[goal]<0 {s.limit="No real ground route to the next waypoint without entering another encounter";return}
	b.target=p;b.path_count=0;b.path_at=0;b.settled=0
	b.start=world.roam_center(e.rs.room.player.position);b.walking=true
	for at:=goal;parents[at]!=at;at=parents[at] {
		if b.path_count>=len(b.path) {s.limit="Ground route exceeds the diagnostic's 256-cell path bound";return}
		b.path[b.path_count]={x=at%width,y=at/width};b.path_count+=1
	}
	for i in 0..<b.path_count/2 {j:=b.path_count-1-i;b.path[i],b.path[j]=b.path[j],b.path[i]}
	fmt.printfln("CYBER WALK route stage=%d from=%v to=%v steps=%d avoid_foes=%v",b.stage,e.rs.room.player.position,p,b.path_count,avoid_foes)
}

// Select an existing accessible hut and a real relief viewpoint near it.
// Neither service nor terrain is moved to fit the capture.
@(private)
cyber_walk_select_places :: proc(s:^Cyber_Walk_Capture,e:^run.Expedition_Session) {
	b:=&s.base;data:=e.rs.room.level_data;width:=data.tiles.width
	parents:=make([]int,len(data.tiles.cells));defer delete(parents)
	distances:=make([]int,len(parents));defer delete(distances)
	cyber_walk_tree(e,e.rs.room.player.position,true,parents,distances)
	best:=1<<30;b.hut=-1
	for placed,index in data.structures {
		if placed.id!=.Hut {continue};plan:=&data.structure_plans[index]
		for y in 0..<plan.height {for x in 0..<plan.width {
			if level.plan_at(plan,x,y)!=.Door {continue}
			door:=grid.offset(placed.origin,x,y)
			for d in ([4]grid.Position{{x=1},{x=-1},{y=1},{y=-1}}) {
				if level.plan_at(plan,x+d.x,y+d.y)!=.Outside {continue}
				inner:=grid.offset(door,-d.x*2,-d.y*2)
				inside,valid:=grid.cell_index(inner,width,data.tiles.height)
				if !valid || distances[inside]<0 {continue}
				for reach in 6..=9 {
					outside:=grid.offset(door,d.x*reach,d.y*reach)
					at,ok:=grid.cell_index(outside,width,data.tiles.height)
					if !ok || distances[at]<0 || distances[at]>=best {continue}
					v:=game.structure_visibility(data,index,world.roam_center(outside))
					if v.stage!=.Far || !v.roof {continue}
					b.hut=index;b.door=door;b.outward=d;s.outside=outside;best=distances[at]
				}
			}
		}}
	}
	if b.hut<0 {s.limit="No existing hut is reachable without crossing an encounter in this seed";return}
	cyber_walk_tree(e,s.outside,true,parents,distances)
	best_score:=-1<<30;found:=false
	for y in 4..<data.tiles.height-4 {for x in 4..<width-4 {
		i:=y*width+x;if distances[i]<0 || distances[i]>60 {continue}
		low,high:=i32(1000),i32(-1000)
		for dy in -3..=3 {for dx in -3..=3 {
			h:=level.height_at(data,{x=x+dx,y=y+dy});low=min(low,h);high=max(high,h)
		}}
		if high-low<2 {continue}
		score:=int(high-low)*100-distances[i]*3
		if !found || score>best_score {s.relief={x=x,y=y};best_score=score;found=true}
	}}
	if !found {s.limit="No real relief viewpoint is safely reachable within 60 cells of the chosen hut";return}
	fmt.printfln("CYBER WALK places seed=%d workshop=%v hut=%d door=%v outside=%v relief=%v",e.world.seed,e.world.sites[b.workshop].position,b.hut,b.door,s.outside,s.relief)
}

@(private)
cyber_walk_combat_route :: proc(s:^Cyber_Walk_Capture,e:^run.Expedition_Session) {
	data:=e.rs.room.level_data;width:=data.tiles.width
	parents:=make([]int,len(data.tiles.cells));defer delete(parents)
	distances:=make([]int,len(parents));defer delete(distances)
	cyber_walk_tree(e,e.rs.room.player.position,false,parents,distances)
	best:=1<<30;target:grid.Position;s.combat_group=-1
	for &group,index in e.world.groups[:e.world.group_count] {
		if group.cave!=0 || group.boss {continue}
		for member in group.members[:group.count] {
			if !member.alive {continue}
			i,ok:=grid.cell_index(member.enemy.position,width,data.tiles.height)
			if ok && distances[i]>=0 && distances[i]<best {
				best=distances[i];target=member.enemy.position;s.combat_group=index
			}
		}
	}
	if s.combat_group<0 {s.limit="No real ground enemy group has a reachable approach";return}
	cyber_walk_target(s,e,target,false)
}

@(private)
cyber_walk_prepare :: proc(s:^Cyber_Walk_Capture,e:^run.Expedition_Session) {
	b:=&s.base;b.frames=0;b.settled=0;b.walking=false
	switch b.stage {
	case 1:cyber_walk_target(s,e,world.site_world(&e.world.sites[b.workshop],{x=0,y=2}))
	case 3:cyber_walk_target(s,e,world.site_world(&e.world.sites[b.workshop],{x=0,y=10}))
	case 4,7:cyber_walk_target(s,e,s.outside)
	case 5:cyber_walk_target(s,e,b.door)
	case 6:cyber_walk_target(s,e,grid.offset(b.door,-b.outward.x*2,-b.outward.y*2))
	case 8:cyber_walk_target(s,e,s.relief)
	case 9:cyber_walk_combat_route(s,e)
	}
}

@(private)
expedition_enable_cyber_walk_smoke :: proc(scene:^host.Scene) {
	s:=new(Cyber_Walk_Capture);s.base.wrapped=scene^;s.base.biome=.Cyber;s.started=rl.GetTime()
	e:=cast(^run.Expedition_Session)scene.data
	expedition_smoke_world(e,.Cyber) // exactly once, before frame 1
	e.world.mounted=false;e.site=-1;e.message_timer=0;e.map_open=false;e.inventory_open=false
	s.base.workshop=-1
	for site,index in e.world.sites[:e.world.site_count] {if site.kind==.Workshop {s.base.workshop=index;break}}
	assert(s.base.workshop>=0)
	e.rs.room.player.position=world.site_world(&e.world.sites[s.base.workshop],{x=0,y=10}) // only initial placement
	e.roam={};e.rs.iso_renderer.tactical.expedition_follow_ready=false
	s.geometry_id=e.rs.room.level_data.geometry_id
	cyber_walk_select_places(s,e)
	rl.SetWindowSize(960,540)
	scene^=host.Scene{name="cyber-walk-smoke",data=s,opaque=true,modal=true,
		update=cyber_walk_update,draw=cyber_walk_draw,after_present=cyber_walk_present,
		destroy=proc(data:rawptr){s:=cast(^Cyber_Walk_Capture)data;s.base.wrapped.destroy(s.base.wrapped.data);free(s)}}
}

@(private)
cyber_walk_update :: proc(data:rawptr,frame:^host.Frame) {
	s:=cast(^Cyber_Walk_Capture)data;b:=&s.base;e:=cast(^run.Expedition_Session)b.wrapped.data
	if frame.window!=nil {frame.window.fixed_canvas_size={960,540}}
	if s.limit!="" {return}
	if e.rs.room.level_data.geometry_id!=s.geometry_id {s.limit="World was replaced during the supposedly continuous route";return}
	if e.rs.room.phase==.Combat && b.stage<9 {s.limit="A live enemy engaged before the sightseeing route completed";return}
	if e.rs.room.phase==.Combat && b.stage==9 {b.stage=10;b.frames=0;b.walking=false;fmt.println("CYBER WALK naturally entered combat")}
	before:=e.rs.room.player.position;point:=e.roam.position;was_ready:=e.roam.ready;was_loot:=e.rs.room.phase==.Loot
	custom:=b.stage==2 && b.frames==60 || b.stage==10 && !s.combat_moved
	if custom {
		keys:=input.Device_Snapshot{focused=true};actual:=frame^
		actual.focused=true;actual.window_focused=true;actual.dt=1.0/60;actual.devices=&keys
		if b.stage==2 {keys.keys_pressed[.ESCAPE]=true}
		if b.stage==10 && b.frames%15==0 {
			step_keys:=[4]rl.KeyboardKey{.W,.D,.S,.A}
			for direction,index in game.MOVEMENT_KEY_DIRECTIONS {
				next,_:=game.layer_step(&e.rs.room,before,game.direction_offset(direction))
				if game.cell_blocks_movement(&e.rs.room,next) || game.step_height_blocked(&e.rs.room,before,next) {continue}
				if query:=game.query_entity_movement(&e.rs.room,game.PLAYER_ENTITY,next,.Traverse);query.error!=.None {continue}
				s.move_from=before;s.move_to=next;s.move_pending=true
				keys.keys_pressed[step_keys[index]]=true;keys.keys_down[step_keys[index]]=true;break
			}
		}
		b.wrapped.update(b.wrapped.data,&actual)
		// A beat-aligned key can commit several frames later. Keep the exact
		// requested step until its non-teleport player event is observed.
		if s.move_pending && e.rs.room.player.position==s.move_to && s.move_to!=s.move_from {
			for event in e.rs.room.recent_events.events[:e.rs.room.recent_events.count] {
				if (event.kind==.Moved || event.kind==.Movement_Step) && event.source==game.PLAYER_ENTITY &&
					event.from_position==s.move_from && event.to_position==s.move_to && !game.event_is_teleport(event) {
					s.combat_moved=true;fmt.printfln("CYBER WALK confirmed combat keyboard move: %v -> %v",s.move_from,s.move_to)
				}
			}
		}
	} else {cyber_scene_update(b,frame)}
	if was_ready && was_loot && e.rs.room.phase==.Loot {
		delta:=e.roam.position-point;distance:=math.sqrt(delta.x*delta.x+delta.y*delta.y)
		if distance>.25 {s.limit="An exploration displacement exceeded the real per-frame walking limit"}
		if distance>.001 {s.moving_frames+=1}
	}
	if b.stage==2 && b.frames==1 && e.site!=b.workshop {s.limit="E did not open the actual workshop"}
	if b.stage==2 && b.frames==61 && e.site>=0 {s.limit="Escape did not close the actual workshop"}
	if e.rs.room.phase==.Defeat || e.rs.room.player.health<=0 {s.limit="Live combat or terrain defeated the player before the route completed"}
}

@(private)
cyber_walk_draw :: proc(data:rawptr,frame:^host.Frame) {
	s:=cast(^Cyber_Walk_Capture)data;s.base.wrapped.draw(s.base.wrapped.data,frame)
}

@(private)
cyber_walk_capture :: proc(frame:^host.Frame,name:cstring) {
	artifacts.screenshot(fmt.ctprintf("odin_pp_cyber_walk_%s_native.png",name))
	assert(frame.window!=nil && frame.window.canvas.texture.width==960 && frame.window.canvas.texture.height==540)
	assert(artifacts.ensure_directory())
	image:=rl.LoadImageFromTexture(frame.window.canvas.texture);assert(rl.IsImageValid(image));defer rl.UnloadImage(image)
	rl.ImageFlipVertical(&image)
	assert(rl.ExportImage(image,fmt.ctprintf("%s/odin_pp_cyber_walk_%s_960.png",artifacts.DIRECTORY,name)))
}

@(private)
cyber_walk_present :: proc(data:rawptr,frame:^host.Frame) {
	s:=cast(^Cyber_Walk_Capture)data;b:=&s.base;e:=cast(^run.Expedition_Session)b.wrapped.data
	b.frames+=1;s.total_frames+=1
	if s.total_frames==1 {s.first_present=rl.GetTime()}
	if s.total_frames>=5400 && s.limit=="" {s.limit="90 seconds elapsed before all route, roof, card and combat movement checks completed"}
	if s.limit!="" {
		cyber_walk_capture(frame,"LIMIT")
		fmt.printfln("CYBER WALK LIMIT stage=%d simulation_seconds=%.2f wall_seconds=%.2f startup_seconds=%.2f moving_seconds=%.2f cell=%v reason=%s",b.stage,f64(s.total_frames)/60,rl.GetTime()-s.first_present,s.first_present-s.started,f64(s.moving_frames)/60,e.rs.room.player.position,s.limit)
		host.quit(frame);return
	}
	orbit:=e.rs.iso_renderer.tactical.world_orbit
	assert(abs(orbit.yaw-render.EXPEDITION_CAMERA_YAW)<.0001 && abs(orbit.pitch-render.EXPEDITION_CAMERA_PITCH)<.0001 && abs(orbit.distance-21)<.0001)
	if b.stage==10 && b.frames==1 {cyber_walk_capture(frame,"09_scontro")}
	if s.total_frames%120==0 {
		fmt.printfln("CYBER WALK trace frame=%d stage=%d cell=%v point=%v phase=%v path=%d/%d",s.total_frames,b.stage,e.rs.room.player.position,e.roam.position,e.rs.room.phase,b.path_at,b.path_count)
	}
	if b.walking && b.settled<25 {return}
	// Give the furnished interior six seconds to read before walking out.
	if b.frames<(360 if b.stage==10 || b.stage==6 else 180) {return}
	if b.stage==9 {s.limit="Reached the live group's approach but no encounter started";return}
	if b.stage==10 {
		if !s.combat_moved || !b.card_played {return}
		cyber_walk_capture(frame,"10_scontro_movimento")
		seconds:=f64(s.total_frames)/60
		fmt.printfln("CYBER WALK COMPLETE duration_in_60_90=%v simulation_seconds=%.2f wall_seconds=%.2f startup_seconds=%.2f moving_seconds=%.2f card=%v combat_move=%v seed=%d geometry_id=%d",seconds>=60 && seconds<=90,seconds,rl.GetTime()-s.first_present,s.first_present-s.started,f64(s.moving_frames)/60,b.card_played,s.combat_moved,e.world.seed,s.geometry_id)
		host.quit(frame);return
	}
	if b.walking {assert(e.rs.room.player.position==b.target)}
	if b.stage==4 || b.stage==6 || b.stage==7 {
		v:=game.structure_visibility(e.rs.room.level_data,b.hut,e.roam.position)
		assert(v.stage==.Inside && !v.roof if b.stage==6 else v.stage==.Far && v.roof)
	}
	names:=CYBER_SCENE_NAMES
	cyber_walk_capture(frame,fmt.ctprintf("%02d_%s",b.stage,names[b.stage]))
	fmt.printfln("CYBER WALK waypoint=%d complete cell=%v frame=%d",b.stage,e.rs.room.player.position,s.total_frames)
	b.stage+=1;cyber_walk_prepare(s,e)
}
