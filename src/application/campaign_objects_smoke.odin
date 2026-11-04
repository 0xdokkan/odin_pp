package application

import "core:fmt"
import rl "vendor:raylib"
import artifacts "../devtools/artifacts"
import campaign "../campaign"
import world "../expedition"
import game "../game"
import grid "../engine/grid"
import host "../engine/host"
import level "../level"
import render "../render"
import run "../run"

// Standalone QA driver: it also compiles against the pre-redesign renderer.
// The fixture uses the real placement API and unchanged rules on a flat map.
// No new object meshes, actor shader fields or other proposal-only APIs are used.
@(private)
OBJECT_SMOKE_BIOMES :: [5]campaign.Biome{.Cyber,.West,.Snow,.Egypt,.Inferno}
@(private)
OBJECT_SMOKE_KINDS :: [6]level.Structure_Id{.Cart,.Fountain,.Statue,.Machine,.Ruin,.Pen}
@(private)
OBJECT_SMOKE_ACTOR_SHADOW :: #config(EXPEDITION_ACTOR_SHADOW,true)
@(private)
Objects_Capture :: struct {
	wrapped:host.Scene,
	stage,frames:int,
	actor_shadow,force_fallback:bool,
	object_index:int,
	biome:campaign.Biome,
	kind:level.Structure_Id,
	rotation:u8,
	walker:[2]f32,
	cache:[2]u64,
}

@(private)
expedition_enable_objects_smoke :: proc(scene:^host.Scene,actor_shadow:bool=false,force_fallback:bool=false) {
	s:=new(Objects_Capture);s.wrapped=scene^;s.actor_shadow=actor_shadow;s.force_fallback=force_fallback
	rl.SetWindowSize(960,540)
	objects_smoke_prepare(s,cast(^run.Expedition_Session)scene.data)
	scene^=host.Scene{name="objects-smoke",data=s,opaque=true,modal=true,
		update=objects_smoke_update,draw=objects_smoke_draw,after_present=objects_smoke_present,
		destroy=proc(data:rawptr){s:=cast(^Objects_Capture)data;s.wrapped.destroy(s.wrapped.data);free(s)}}
}

// A flat staging map, not a generated-world change. All before/after captures
// have identical map/seed, real occupied tiles and original camera settings.
@(private)
objects_smoke_room :: proc(e:^run.Expedition_Session,biome:campaign.Biome) {
	game.destroy_room(&e.rs.room);level.destroy(&e.rs.level_data)
	data,ok:=level.create(40,40,{.Floor});assert(ok,"Cannot create the object QA map")
	data.player_spawn={x=20,y=26};data.has_player_spawn=true
	_=level.set_tile(&data,data.player_spawn,{.Player_Spawn})
	_=level.set_tile(&data,{x=3,y=3},{.Exit})
	e.rs.level_data=data
	player,created:=game.create_player({max_health=32,attack=2,defense=1});assert(created)
	e.rs.run_state.player=player
	room,ready:=game.create_room(&e.rs.level_data,&e.rs.run_state.player,{room_seed=e.rs.run_seed});assert(ready)
	e.rs.room=room
	assert(game.configure_expedition_combat(&e.rs.room))
	game.end_expedition_encounter(&e.rs.room)
	e.world={biome=biome,side_length=40,seed=e.rs.run_seed,reward_site=-1,last_health=32}
	e.rs.room.player.tactical.config.expedition_biome=u8(biome)
	e.rs.room.player.tactical.config.low_gravity=biome==.Space
	e.world.mounted=false;e.message_timer=0;e.site=-1
	e.map_open=false;e.inventory_open=false;e.character_open=false;e.paused=false;e.placing=false
	e.roam={};e.rs.iso_renderer.tactical.expedition_follow_ready=false
	render.clear_event_animations(&e.rs.iso_renderer)
}

@(private)
objects_smoke_prepare :: proc(s:^Objects_Capture,e:^run.Expedition_Session) {
	s.frames=0;s.cache={}
	if s.actor_shadow {
		s.biome=.Cyber if s.stage<3 else .West;s.kind=.Hut;s.rotation=0
	} else {
		biomes,kinds:=OBJECT_SMOKE_BIOMES,OBJECT_SMOKE_KINDS
		s.biome=biomes[s.stage/12]
		s.kind=kinds[(s.stage/2)%6];s.rotation=u8(s.stage%2)
	}
	objects_smoke_room(e,s.biome)
	data:=e.rs.room.level_data
	if s.actor_shadow {
		// A real 2.6-unit courtyard wall, using its existing site description
		// and ordinary blocking Wall tiles. The inactive site adds no fixture.
		// Unlike a nearby building, this wall does not fade merely by distance.
		e.world.site_count=1
		e.world.sites[0]={kind=.Boss,position={x=10,y=20},layout_version=world.SITE_LAYOUT_VERSION,active=false}
		for y in 16..=24 {
			cell:=grid.Position{x=22,y=y}
			design:=world.site_cell(&e.world.sites[0],cell)
			assert(design.wall && design.wall_height==2.6)
			assert(level.set_tile(data,cell,{.Wall}))
		}
		// The sun travels east/north; the middle position crosses the
		// projected edge at roughly half the robot's height. All three
		// centres clear the same real collision wall by more than its radius.
		positions:=[3]f32{23.35,23.85,24.55}
		s.walker={positions[s.stage%3],19.6}
		e.rs.room.player.position=world.roam_cell(s.walker)
		assert(game.begin_expedition_encounter(&e.rs.room))
		for p,i in ([6]grid.Position{{x=23,y=21},{x=24,y=22},{x=25,y=20},{x=26,y=21},{x=25,y=18},{x=26,y=17}}) {
			_,spawned:=game.spawn_enemy(&e.rs.room,{position=p,health=20,attack=1,archetype=game.Enemy_Archetype(i)})
			assert(spawned,"Actor shadow probe needs all six actual enemy roles")
		}
		// End the deck exchange but retain the actors. The update below
		// advances only presentation, so AI, damage and glow stay frozen.
		game.end_expedition_encounter(&e.rs.room)
	} else {
		index,err:=level.place_structure(data,s.kind,{x=18,y=18},s.rotation,false)
		assert(err==.None,"QA object placement must obey the real footprint/collision rules")
		s.object_index=index;e.world.structure_count=1;e.world.structures[0]=data.structures[index]
		plan:=&data.structure_plans[index]
		e.rs.room.player.position={x=18+plan.width/2,y=18+plan.height+2}
		s.walker=world.roam_center(e.rs.room.player.position)
	}
	assert(!game.cell_blocks_movement(&e.rs.room,e.rs.room.player.position))
	e.roam.position=s.walker;e.roam.cell=e.rs.room.player.position;e.roam.ready=true
	render.set_expedition_walker(&e.rs.iso_renderer,true,{s.walker.x-.5,s.walker.y-.5},{},0,1.0/60)
}

@(private)
objects_smoke_update :: proc(data:rawptr,frame:^host.Frame) {
	s:=cast(^Objects_Capture)data;e:=cast(^run.Expedition_Session)s.wrapped.data
	if frame.window!=nil {frame.window.fixed_canvas_size={960,540}}
	// Exercise the existing cache-failure path after this scene's key has been
	// established. Resources retain their normal owner and are freed on rebuild.
	if s.force_fallback && s.frames==15 {
		m:=e.rs.iso_renderer.tactical.expedition_material;assert(m!=nil)
		m.geometry.ready=false;m.geometry.failed=true;m.sun.drawn=false
	}
	e.rs.frame_input.focused=true;e.rs.frame_time=1.0/60
	render.set_living_cards(&e.rs.iso_renderer,true)
	render.set_expedition_walker(&e.rs.iso_renderer,true,{s.walker.x-.5,s.walker.y-.5},{},0,1.0/60)
	render.update_tactical_atmosphere(&e.rs.iso_renderer,1.0/60)
	_=render.update_renderer_frame_timeline(&e.rs.iso_renderer,1.0/60)
}

@(private)
objects_smoke_draw :: proc(data:rawptr,frame:^host.Frame) {
	s:=cast(^Objects_Capture)data;s.wrapped.draw(s.wrapped.data,frame)
}

// Export the actual 960x540 canvas, not a resized framebuffer. Render textures
// have the opposite row direction from image files; only that orientation is fixed.
@(private)
objects_smoke_canvas :: proc(frame:^host.Frame,name:cstring) {
	assert(frame.window!=nil && frame.window.canvas.texture.width==960 && frame.window.canvas.texture.height==540)
	assert(artifacts.ensure_directory())
	image:=rl.LoadImageFromTexture(frame.window.canvas.texture)
	assert(rl.IsImageValid(image));defer rl.UnloadImage(image)
	rl.ImageFlipVertical(&image)
	assert(rl.ExportImage(image,fmt.ctprintf("%s/%s",artifacts.DIRECTORY,name)))
}

@(private)
objects_smoke_present :: proc(data:rawptr,frame:^host.Frame) {
	s:=cast(^Objects_Capture)data;e:=cast(^run.Expedition_Session)s.wrapped.data
	s.frames+=1
	m:=e.rs.iso_renderer.tactical.expedition_material
	if s.frames==20 {
		assert(m!=nil && m.sun.ready && m.sun.active,"Object gallery requires working native sun maps")
		s.cache={m.geometry.rebuilds,m.geometry.uploads}
	}
	if s.frames<45 {return}
	assert(m!=nil && s.cache==[2]u64{m.geometry.rebuilds,m.geometry.uploads},"A stationary object must not rebuild or upload geometry")
	if s.force_fallback {assert(m.geometry.failed && !m.geometry.ready && m.sun.drawn,"Forced fallback must still draw both sun maps")}
	orbit:=e.rs.iso_renderer.tactical.world_orbit
	assert(abs(orbit.yaw-render.EXPEDITION_CAMERA_YAW)<.0001 && abs(orbit.pitch-render.EXPEDITION_CAMERA_PITCH)<.0001 && abs(orbit.distance-21)<.0001,
		"Object captures must use the approved gameplay camera")
	if s.actor_shadow {
		mode:="on" if OBJECT_SMOKE_ACTOR_SHADOW else "off"
		artifacts.screenshot(fmt.ctprintf("odin_pp_actor_shadow_%s_%v_%d_native.png",mode,s.biome,s.stage%3))
		objects_smoke_canvas(frame,fmt.ctprintf("odin_pp_actor_shadow_%s_%v_%d_960.png",mode,s.biome,s.stage%3))
		fmt.printfln("ACTOR SHADOW QA flag=%v biome=%v position=%v enemies=%d AI=frozen camera=(%.6f,%.6f,%.2f)",
			OBJECT_SMOKE_ACTOR_SHADOW,s.biome,s.walker,len(e.rs.room.enemies),orbit.yaw,orbit.pitch,orbit.distance)
	} else {
		artifacts.screenshot(fmt.ctprintf("odin_pp_objects_%v_%v_r%d_native.png",s.biome,s.kind,s.rotation))
		objects_smoke_canvas(frame,fmt.ctprintf("odin_pp_objects_%v_%v_r%d_960.png",s.biome,s.kind,s.rotation))
		fmt.printfln("OBJECT QA stage=%d biome=%v kind=%v rotation=%d seed=%d camera=(%.6f,%.6f,%.2f) maps=%d uploads=%d",
			s.stage,s.biome,s.kind,s.rotation,e.world.seed,orbit.yaw,orbit.pitch,orbit.distance,m.sun.renders,m.geometry.uploads)
		if s.force_fallback {fmt.println("OBJECT QA forced_cache_failure=true immediate_casters=true")}
	}
	s.stage+=1
	if s.stage>=(6 if s.actor_shadow else (12 if s.force_fallback else 60)) {host.quit(frame);return}
	objects_smoke_prepare(s,e)
}
