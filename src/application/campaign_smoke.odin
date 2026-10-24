package application

import "core:fmt"
import "core:os"
import "core:slice"
import "core:time"
import rl "vendor:raylib"
import artifacts "../devtools/artifacts"
import campaign "../campaign"
import campaignui "../campaignui"
import world "../expedition"
import run "../run"
import render "../render"
import game "../game"
import grid "../engine/grid"
import level "../level"
import host "../engine/host"
import hubworld "../hubworld"
import arcade "../memoryarcade"
import activities "../activities"

hub_prepare_unsaved_expedition :: proc(h:^Campaign_Hub) {
	campaign.destroy(&h.progress);campaign.initialize(&h.progress)
	h.slot=0;h.page=.Galaxy;h.path="";h.smoke_expedition=false
	_=campaign.begin_run(&h.progress,.Cyber,h.options.seed)
	// The one-shot startup is separate from the screenshot driver.
	h.first_frame=true
}

@(private)
Hub_Capture :: struct { kind:int, frames:int }

@(private)
hub_after_present :: proc(data:rawptr,frame:^host.Frame) {
	h:=cast(^Campaign_Hub)data
	if h.smoke_world {hub_world_smoke(h,frame);return}
	if !h.smoke {return}
	h.smoke_frame+=1
	if h.smoke_frame%35!=0 {return}
	stage:=h.smoke_frame/35-1
	names:=[11]string{"galassia","deposito","progressi","record","cabinati","cabinati_vicino","casino","memorie","galassia_completa","galassia_city","slot"}
	if stage<len(names) {artifacts.screenshot(fmt.ctprintf("odin_pp_hub_%s.png",names[stage]))}
	switch stage {
	case 0:
		campaign.depot_add(&h.progress,campaign.make_item(.Relic,1,i32(game.Relic_Id.Guard_Sigil)))
		campaign.grid_add(&h.progress.backpack.grid,campaign.make_item(.Healing,3))
		h.page=.Storage
	case 1:
		campaign.discover_secret(&h.progress,.Cyber,12);campaign.discover_secret(&h.progress,.Cyber,13)
		campaign.discover_secret(&h.progress,.Cyber,14);campaign.discover_secret(&h.progress,.City,14)
		h.page=.Progress
	case 2:
		for b in campaign.Biome.Cyber..<campaign.Biome.Count {h.progress.won[b]=true;h.progress.unlocked[b]=true}
		for i in 0..<activities.MINIGAME_COUNT {campaign.record_result(&h.progress,i,i64(1250+i*175),u8(1+i%3),true)}
		h.progress_tab=1;h.progress_page=1
	case 3:hub_room_setup(h,.Arcade);h.page=.Room
	case 4:hubworld.room_place_before(&h.room,&h.room_world,0);h.room_camera={-6,-3}
	case 5:hub_room_setup(h,.Casino);h.page=.Room
	case 6:h.page=.Memories;h.progress.normal_ending=true
	case 7:h.page=.Galaxy
	case 8:h.selected=.City
	case 9:
		h.page=.Slots
		for &status in h.slot_status {status=.Missing}
		h.slot_status[0]=.Loaded;h.slot_date[0]=time.to_unix_seconds(time.now());h.slot_wins[0]=11;h.slot_biomes[0]=11;h.slot_time[0]=3600
	case 10:
		scene:=arcade.casino_create_demo(.Ranch,h.options.seed);scene.after_present=casino_smoke_after_present;host.push(frame,scene)
	}
}

@(private)
casino_smoke_after_present :: proc(data:rawptr,frame:^host.Frame) {
	// The hub is frozen under the table, so the host frame supplies a stable
	// elapsed capture interval. Each demo owns an isolated wallet.
	if frame.index%60!=0 {return}
	artifacts.screenshot("odin_pp_hub_casino_table.png")
	host.quit(frame)
}

EXPEDITION_BENCHMARK :: #config(EXPEDITION_BENCHMARK,false)
EXPEDITION_BENCHMARK_LAST :: #config(EXPEDITION_BENCHMARK_LAST,50)
#assert(EXPEDITION_BENCHMARK_LAST>=0 && EXPEDITION_BENCHMARK_LAST<=50)
@(private)
EXPEDITION_BENCHMARK_WARMUP :: 20
@(private)
EXPEDITION_BENCHMARK_SAMPLES :: 120
@(private)
EXPEDITION_BENCHMARK_WALK_SAMPLES :: 240
@(private)
Expedition_Benchmark :: struct {
	frame_ms,draw_ms:[EXPEDITION_BENCHMARK_WALK_SAMPLES]f64,
	scene_sum:[5]f64,
	world_sum:[10]f64,
	geometry_start,geometry_measured:[2]u64,
	count,post_count:int,
	post_sum:render.Expedition_Post_Timing,
}
Expedition_Capture :: struct {
	wrapped:host.Scene,
	frame,stage,held,measured:int,
	seconds,draw_ms:f64,
	benchmark:Expedition_Benchmark,
}
@(private)
EXPEDITION_SMOKE_WALK :: 25
@(private)
EXPEDITION_SMOKE_ENGAGE :: 26
@(private)
EXPEDITION_SMOKE_CENTER :: 27
@(private)
EXPEDITION_SMOKE_WORKSHOP :: EXPEDITION_SMOKE_CENTER+12
// "This one can be hit" over a fight in four biomes of different tints (the last
// is the one whose own tint is violet, where the halo turns acid green).
@(private)
EXPEDITION_SMOKE_HITS :: EXPEDITION_SMOKE_WORKSHOP+12
@(private)
EXPEDITION_SMOKE_HIT_BIOMES :: [4]campaign.Biome{.Snow, .West, .Jungle, .Space}
// Buildings and objects (level/structure.odin) in the first biome: the robot walks up to a hut
// (6, 4, 2 and 1 cell from its door, on the threshold, inside, outside again), then the objects.
@(private)
EXPEDITION_SMOKE_STRUCTURES :: EXPEDITION_SMOKE_HITS+4
@(private)
EXPEDITION_SMOKE_STRUCTURE_STEPS :: 8
// The relief of every biome (Fase 3): the robot stands where the ground is most uneven.
@(private)
EXPEDITION_SMOKE_RELIEF :: EXPEDITION_SMOKE_STRUCTURES+8
@(private)
EXPEDITION_SMOKE_RELIEF_COUNT :: 12
// The map's hologram with the relief (shading and contour lines) in three biomes.
@(private)
EXPEDITION_SMOKE_HOLOGRAMS :: EXPEDITION_SMOKE_RELIEF+EXPEDITION_SMOKE_RELIEF_COUNT
@(private)
EXPEDITION_SMOKE_HOLOGRAM_BIOMES :: [3]campaign.Biome{.Egypt, .Snow, .Sky}
// A fight on two levels in the Snow: the robot on a plateau, a foe on the ground below.
@(private)
EXPEDITION_SMOKE_TWO_LEVELS :: EXPEDITION_SMOKE_HOLOGRAMS+3
// The Snow's spiral mountain (Fase 4): the robot at eight places of the climb, on the path and behind the mountain.
@(private)
EXPEDITION_SMOKE_MOUNTAIN :: EXPEDITION_SMOKE_TWO_LEVELS+1
@(private)
EXPEDITION_SMOKE_MOUNTAIN_STEPS :: 8
@(private)
EXPEDITION_SMOKE_STRUCTURE_NAMES :: [EXPEDITION_SMOKE_STRUCTURE_STEPS]string{"6","4","2","1","soglia","dentro","fuori","oggetti"}

@(private)
expedition_benchmark_geometry :: proc(e:^run.Expedition_Session)->[2]u64 {
	m:=e.rs.iso_renderer.tactical.expedition_material
	if m==nil {return {}}
	return {m.geometry.rebuilds,m.geometry.uploads}
}

// Frame intervals include real update, submission, presentation and any
// driver stalls. The post breakdown is CPU submission time, never GPU time.
// Statistics and captures happen after the final measured sample; the next
// stage discards its warmup, so neither contaminates the reported interval.
@(private)
expedition_benchmark_present :: proc(s:^Expedition_Capture,e:^run.Expedition_Session,frame:^host.Frame)->bool {
	if s.held<=EXPEDITION_BENCHMARK_WARMUP {
		if s.held==EXPEDITION_BENCHMARK_WARMUP {s.benchmark.geometry_measured=expedition_benchmark_geometry(e)}
		return false
	}
	b:=&s.benchmark;target:=EXPEDITION_BENCHMARK_SAMPLES
	if s.stage==EXPEDITION_SMOKE_WALK || s.stage==EXPEDITION_SMOKE_ENGAGE {target=EXPEDITION_BENCHMARK_WALK_SAMPLES}
	b.frame_ms[b.count]=f64(rl.GetFrameTime())*1000;b.draw_ms[b.count]=s.draw_ms;b.count+=1
	scene:=e.draw_timing;draw:=e.rs.iso_renderer.tactical.draw_timing
	for ms,i in ([5]f64{scene.view_ms,scene.world_ms,scene.hud_hand_ms,scene.map_ms,scene.effect_ms}) {b.scene_sum[i]+=ms}
	for ms,i in ([10]f64{draw.prepare_ms,draw.cache_lights_ms,draw.reflection_ms,draw.floor_ms,draw.architecture_resolve_ms,
		draw.objects_ms,draw.ground_ms,draw.target_details_ms,draw.paper_ms,draw.surface_labels_ms}) {b.world_sum[i]+=ms}
	if surface:=e.rs.iso_renderer.tactical.surface;surface!=nil && surface.post!=nil {
		p:=surface.post.timing
		b.post_sum.reflection_ms+=p.reflection_ms;b.post_sum.reflection_blur_ms+=p.reflection_blur_ms
		b.post_sum.bloom_ms+=p.bloom_ms;b.post_sum.resolve_ms+=p.resolve_ms;b.post_count+=1
	}
	if b.count<target {return false}
	ordered:=b.frame_ms;values:=ordered[:b.count];slice.sort(values)
	total:f64;for ms in values {total+=ms}
	mean:=total/f64(b.count);median:=(values[(b.count-1)/2]+values[b.count/2])*.5
	p95:=values[(b.count*95+99)/100-1];maximum:=values[b.count-1]
	draw_ordered:=b.draw_ms;draw_values:=draw_ordered[:b.count];slice.sort(draw_values)
	draw_total:f64;for ms in draw_values {draw_total+=ms}
	draw_mean:=draw_total/f64(b.count);draw_p95:=draw_values[(b.count*95+99)/100-1]
	post_divisor:=f64(max(b.post_count,1));p:=b.post_sum
	pixels:=[2]int{}
	if frame.window!=nil {pixels={int(frame.window.canvas.texture.width),int(frame.window.canvas.texture.height)}}
	fmt.printf("EXPEDITION BENCHMARK stage=%d biome=%d canvas_px=%dx%d samples=%d warmup=%d mean_ms=%.3f median_ms=%.3f p95_ms=%.3f max_ms=%.3f mean_fps=%.2f\n",
		s.stage,int(e.world.biome),pixels.x,pixels.y,b.count,EXPEDITION_BENCHMARK_WARMUP,mean,median,p95,maximum,1000/max(mean,.000001))
	fmt.printf("CPU SUBMISSION stage=%d samples=%d wrapped_draw_mean_ms=%.3f wrapped_draw_p95_ms=%.3f reflection_ms=%.3f reflection_blur_ms=%.3f bloom_ms=%.3f resolve_ms=%.3f (post means; not GPU timings)\n",
		s.stage,b.post_count,draw_mean,draw_p95,p.reflection_ms/post_divisor,p.reflection_blur_ms/post_divisor,p.bloom_ms/post_divisor,p.resolve_ms/post_divisor)
	frame_divisor:=f64(b.count)
	fmt.printf("CPU SCENE stage=%d view_ms=%.3f world_ms=%.3f hud_hand_ms=%.3f map_ms=%.3f effect_ms=%.3f (means; nested scopes, not GPU timings)\n",
		s.stage,b.scene_sum[0]/frame_divisor,b.scene_sum[1]/frame_divisor,b.scene_sum[2]/frame_divisor,b.scene_sum[3]/frame_divisor,b.scene_sum[4]/frame_divisor)
	fmt.printf("CPU WORLD stage=%d prepare_ms=%.3f cache_lights_ms=%.3f reflection_ms=%.3f floor_ms=%.3f architecture_resolve_ms=%.3f objects_ms=%.3f ground_ms=%.3f target_details_ms=%.3f paper_ms=%.3f surface_labels_ms=%.3f (means; nested scopes, not GPU timings)\n",
		s.stage,b.world_sum[0]/frame_divisor,b.world_sum[1]/frame_divisor,b.world_sum[2]/frame_divisor,b.world_sum[3]/frame_divisor,b.world_sum[4]/frame_divisor,
		b.world_sum[5]/frame_divisor,b.world_sum[6]/frame_divisor,b.world_sum[7]/frame_divisor,b.world_sum[8]/frame_divisor,b.world_sum[9]/frame_divisor)
	geometry:=expedition_benchmark_geometry(e)
	fmt.printf("GEOMETRY CACHE stage=%d rebuilds_total=%d uploads_total=%d rebuilds_stage_delta=%d uploads_stage_delta=%d rebuilds_measured_delta=%d uploads_measured_delta=%d counter_reset=%v\n",
		s.stage,geometry[0],geometry[1],i64(geometry[0])-i64(b.geometry_start[0]),i64(geometry[1])-i64(b.geometry_start[1]),
		i64(geometry[0])-i64(b.geometry_measured[0]),i64(geometry[1])-i64(b.geometry_measured[1]),
		geometry[0]<b.geometry_start[0] || geometry[1]<b.geometry_start[1])
	b^={}
	return true
}

// A fresh world of biome `b` for the per-biome captures, mounted.
@(private)
expedition_smoke_world :: proc(e:^run.Expedition_Session,b:campaign.Biome) {
	game.destroy_room(&e.rs.room);level.destroy(&e.rs.level_data)
	_=world.generate(&e.world,&e.rs.level_data,b,e.rs.run_seed)
	player,_:=game.create_player({max_health=32,attack=2,defense=1});e.rs.run_state.player=player
	room,_:=game.create_room(&e.rs.level_data,&e.rs.run_state.player,{room_seed=e.rs.run_seed});e.rs.room=room
	_=game.configure_expedition_combat(&e.rs.room);game.end_expedition_encounter(&e.rs.room)
	world.prepare_room(&e.world,&e.rs.room)
	e.rs.room.player.tactical.config.expedition_biome=u8(b);e.rs.room.player.tactical.config.low_gravity=b==.Space
	e.world.mounted=true
	e.rs.iso_renderer.tactical.expedition_follow_ready=false
	render.clear_event_animations(&e.rs.iso_renderer)
}

// A fight on the spot: foes on the open cells beside the player, the combat begun
// and a card chosen that would hit one of them, so the board marks it.
@(private)
expedition_smoke_hits :: proc(e:^run.Expedition_Session) {
	room:=&e.rs.room;player:=room.player
	// The nearest cell whose four neighbours are all open ground.
	open_around :: proc(room:^game.Room,p:grid.Position)->bool {
		if game.cell_blocks_movement(room,p) {return false}
		for offset in ([4]grid.Position{{1,0},{0,1},{-1,0},{0,-1}}) {if game.cell_blocks_movement(room,game.add_position(p,offset)) {return false}}
		return true
	}
	if !open_around(room,player.position) {
		found:=false
		search:for radius in 1..=12 {for dy in -radius..=radius {for dx in -radius..=radius {
			if max(abs(dx),abs(dy))!=radius {continue}
			p:=game.add_position(player.position,{dx,dy})
			if open_around(room,p) {player.position=p;found=true;break search}
		}}}
		assert(found,"no open ground near the player for the hit marks")
		e.rs.iso_renderer.tactical.expedition_follow_ready=false
	}
	// Foes join a room already in combat (game.spawn_enemy).
	assert(game.begin_expedition_encounter(room),"the hit marks' fight did not begin")
	placed:=0
	for offset in ([4]grid.Position{{1,0},{0,1},{-1,0},{0,-1}}) {
		cell:=game.add_position(player.position,offset)
		if game.cell_blocks_movement(room,cell) {continue}
		if _,ok:=game.spawn_enemy(room,{position=cell,health=40,attack=1,archetype=.Chaser});ok {placed+=1}
	}
	assert(placed>0,"no open cell beside the player for the hit marks")
	// The first card of the hand some valid cast of which hits a foe.
	for card in player.deck.hand[:player.deck.hand_count] {
		definition,found:=game.card_definition_by_id(card.definition_id)
		if !found || game.card_is_room_tool(card.definition_id) {continue}
		for dy in -3..=3 {for dx in -3..=3 {
			cell:=game.add_position(player.position,{dx,dy})
			evaluation:=game.evaluate_card_targeting(room,card,game.card_target_request_at(definition,cell))
			hits:=game.card_hit_enemies(room,card,&evaluation)
			if hits.count>0 {e.rs.card_interaction.selected_card_id=card.id;return}
		}}
	}
	assert(false,"no card of the hand hits a foe")
}

// Eight open cells west of a resting patrol: walking east engages it.
@(private)
expedition_smoke_before_patrol :: proc(e:^run.Expedition_Session) {
	w:=&e.world;room:=&e.rs.room
	for &group in w.groups[:w.group_count] {
		if !group.patrol || group.active {continue}
		for member in group.members[:group.count] {
			if !member.alive || member.deployed {continue}
			p:=grid.Position{member.enemy.position.x-8,member.enemy.position.y}
			clear:=true
			for x in p.x..<member.enemy.position.x {clear=clear && !game.cell_blocks_movement(room,{x,p.y})}
			if !clear {continue}
			room.player.position=p;e.rs.iso_renderer.tactical.expedition_follow_ready=false
			return
		}
	}
}

// The robot just behind a courtyard wall, for the see-through capture.
@(private)
expedition_smoke_behind_wall :: proc(e:^run.Expedition_Session) {
	w:=&e.world;room:=&e.rs.room
	for &site in w.sites[:w.site_count] {
		// The boss lair has the tallest walls, which hide the whole robot.
		if !site.active || site.kind!=.Boss {continue}
		lo,hi:=world.site_bounds(&site)
		for y in lo.y..=hi.y {for x in lo.x..=hi.x {
			p:=grid.Position{x,y}
			if game.cell_blocks_movement(room,p) {continue}
			// The camera looks from +x/+z: a wall row there hides the robot.
			_,a:=world.site_at(w,{x,y+1});_,b:=world.site_at(w,{x+1,y+1})
			if !a.wall || !b.wall || a.fixture || b.fixture || a.wall_height<2.5 || b.wall_height<2.5 {continue}
			room.player.position=p;e.rs.iso_renderer.tactical.expedition_follow_ready=false
			game.end_expedition_encounter(room);clear(&room.enemies)
			return
		}}
	}
}

expedition_enable_smoke :: proc(scene:^host.Scene) {
	when EXPEDITION_BENCHMARK {
		rl.SetTargetFPS(0);rl.ClearWindowState({.VSYNC_HINT})
		fmt.printfln("EXPEDITION BENCHMARK: target_fps=0 vsync_hint=%v; no screenshots or GPU readbacks; presented-frame intervals plus CPU submission timings.",rl.IsWindowState({.VSYNC_HINT}))
	}
	state:=new(Expedition_Capture);state.wrapped=scene^
	// ODIN_PP_SMOKE_ONLY=hits starts at the hit marks' fights, to work on them.
	if only,_:=os.lookup_env("ODIN_PP_SMOKE_ONLY",context.temp_allocator);only=="hits" {state.stage=EXPEDITION_SMOKE_HITS-1}
	scene^=host.Scene{name="expedition-smoke",data=state,opaque=true,modal=true,update=expedition_capture_update,draw=expedition_capture_draw,after_present=expedition_capture_present,destroy=proc(data:rawptr){s:=cast(^Expedition_Capture)data;s.wrapped.destroy(s.wrapped.data);free(s)}}
}

@(private)
expedition_capture_update :: proc(data:rawptr,frame:^host.Frame) {
	s:=cast(^Expedition_Capture)data;e:=cast(^run.Expedition_Session)s.wrapped.data
	when EXPEDITION_BENCHMARK {
		if s.held==0 {s.benchmark.geometry_start=expedition_benchmark_geometry(e)}
	}
	if (s.stage==EXPEDITION_SMOKE_WALK || s.stage==EXPEDITION_SMOKE_ENGAGE) && frame.devices!=nil {
		// The real scene walks with held keys: free roaming end to end, then
		// on foot toward the boss until its lair engages the robot.
		keys:=frame.devices^
		if s.stage==EXPEDITION_SMOKE_WALK {keys.keys_down[.W]=true;keys.keys_down[.D]=true}
		else {keys.keys_down[.S]=true;keys.keys_down[.D]=true}
		walk:=frame^;walk.devices=&keys
		s.wrapped.update(s.wrapped.data,&walk)
		when !EXPEDITION_BENCHMARK {
			if s.held%15==0 {fmt.printfln("walk %d/%d: position %.3f %.3f cell %v phase %v mounted %v dt %.4f",s.stage,s.held,e.roam.position.x,e.roam.position.y,e.rs.room.player.position,e.rs.room.phase,e.world.mounted,frame.dt)}
		}
		return
	}
	e.rs.frame_input.focused=true;e.rs.frame_time=frame.dt
	render.set_living_cards(&e.rs.iso_renderer,true)
	render.update_tactical_atmosphere(&e.rs.iso_renderer,frame.dt)
	_=render.update_renderer_frame_timeline(&e.rs.iso_renderer,frame.dt)
	if e.inventory_open {_=campaignui.update_inventory(e.progress,e.rs.room.player,&e.inventory,frame,false,false)}
}
@(private)
expedition_capture_draw :: proc(data:rawptr,frame:^host.Frame) {
	s:=cast(^Expedition_Capture)data
	when EXPEDITION_BENCHMARK {
		started:=rl.GetTime();s.wrapped.draw(s.wrapped.data,frame);s.draw_ms=(rl.GetTime()-started)*1000
	} else {s.wrapped.draw(s.wrapped.data,frame)}
}
@(private)
expedition_capture_present :: proc(data:rawptr,frame:^host.Frame) {
	s:=cast(^Expedition_Capture)data;e:=cast(^run.Expedition_Session)s.wrapped.data
	// Walking stages run the real scene long enough to cross several cells.
	s.frame+=1;s.held+=1
	when EXPEDITION_BENCHMARK {
		if !expedition_benchmark_present(s,e,frame) {return}
	} else {
		if s.held>5 {s.measured+=1;s.seconds+=f64(rl.GetFrameTime())}
		if s.held<(150 if s.stage==EXPEDITION_SMOKE_WALK || s.stage==EXPEDITION_SMOKE_ENGAGE else 35) {return}
		if s.measured>0 {fmt.printf("RENDER TIMING: stage %d, %d frames, %.2f ms/frame\n",s.stage,s.measured,s.seconds*1000/f64(s.measured))}
	}
	s.held=0
	s.measured=0;s.seconds=0
	when !EXPEDITION_BENCHMARK {
		if s.stage==0 || s.stage==4 || s.stage==24 {assert(render.expedition_render_smoke_check(&e.rs.iso_renderer),"Native HDR/bloom/reflection validation failed")}
		names:=[7]string{"bioma","ologramma","mount","zaino","personaggio","scontro","tana"}
		if s.stage<7 {artifacts.screenshot(fmt.ctprintf("odin_pp_expedition_%s.png",names[s.stage]))}
		else if s.stage<19 {artifacts.screenshot(fmt.ctprintf("odin_pp_expedition_bioma_%02d.png",s.stage-7))}
		else if s.stage<23 {artifacts.screenshot(fmt.ctprintf("odin_pp_expedition_poi_%02d.png",s.stage-19))}
		else if s.stage==23 {artifacts.screenshot("odin_pp_expedition_ologramma_grande.png")}
		else if s.stage==24 {artifacts.screenshot("odin_pp_expedition_dietro_muro.png")}
		else if s.stage==EXPEDITION_SMOKE_WALK {artifacts.screenshot("odin_pp_expedition_camminata.png")}
		else if s.stage==EXPEDITION_SMOKE_ENGAGE {artifacts.screenshot("odin_pp_expedition_ingaggio.png")}
		else if s.stage==EXPEDITION_SMOKE_WORKSHOP {artifacts.screenshot("odin_pp_expedition_officina_cyber.png")}
		else if s.stage>=EXPEDITION_SMOKE_HITS && s.stage<EXPEDITION_SMOKE_HITS+4 {
			names:=[4]string{"neve","far_west","giungla","spazio"}
			artifacts.screenshot(fmt.ctprintf("odin_pp_expedition_bersagli_%s.png",names[s.stage-EXPEDITION_SMOKE_HITS]))
		} else if s.stage==EXPEDITION_SMOKE_TWO_LEVELS {
			artifacts.screenshot("odin_pp_expedition_scontro_livelli.png")
		} else if s.stage>=EXPEDITION_SMOKE_MOUNTAIN && s.stage<EXPEDITION_SMOKE_MOUNTAIN+EXPEDITION_SMOKE_MOUNTAIN_STEPS {
			artifacts.screenshot(fmt.ctprintf("odin_pp_expedition_montagna_%d.png",s.stage-EXPEDITION_SMOKE_MOUNTAIN))
		} else if s.stage>=EXPEDITION_SMOKE_HOLOGRAMS && s.stage<EXPEDITION_SMOKE_HOLOGRAMS+3 {
			artifacts.screenshot(fmt.ctprintf("odin_pp_expedition_ologramma_rilievo_%d.png",s.stage-EXPEDITION_SMOKE_HOLOGRAMS))
		} else if s.stage>=EXPEDITION_SMOKE_RELIEF && s.stage<EXPEDITION_SMOKE_RELIEF+EXPEDITION_SMOKE_RELIEF_COUNT {
			artifacts.screenshot(fmt.ctprintf("odin_pp_expedition_rilievo_%02d.png",s.stage-EXPEDITION_SMOKE_RELIEF))
		} else if s.stage>=EXPEDITION_SMOKE_STRUCTURES && s.stage<EXPEDITION_SMOKE_STRUCTURES+EXPEDITION_SMOKE_STRUCTURE_STEPS {
			names:=EXPEDITION_SMOKE_STRUCTURE_NAMES
			artifacts.screenshot(fmt.ctprintf("odin_pp_expedition_edificio_%s.png",names[s.stage-EXPEDITION_SMOKE_STRUCTURES]))
		} else if s.stage>EXPEDITION_SMOKE_WORKSHOP {artifacts.screenshot(fmt.ctprintf("odin_pp_expedition_officina_%02d.png",s.stage-EXPEDITION_SMOKE_WORKSHOP))}
		else {artifacts.screenshot(fmt.ctprintf("odin_pp_expedition_centro_%02d.png",s.stage-EXPEDITION_SMOKE_CENTER))}
	}
	when EXPEDITION_BENCHMARK {
		if s.stage>=EXPEDITION_BENCHMARK_LAST {host.quit(frame);return}
	}
	s.stage+=1
	switch s.stage {
	case 1:e.map_open=true
	case 2:e.map_open=false;e.world.mounted=true
	case 3:
		rl.SetWindowSize(1100,760)
		e.world.mounted=false;e.inventory_open=true
		campaign.grid_add(&e.progress.backpack.grid,campaign.make_item(.Healing,3))
		campaign.grid_add(&e.progress.backpack.grid,campaign.make_item(.Credits,45))
		campaign.grid_add(&e.progress.backpack.grid,campaign.make_item(.Relic,1,i32(game.Relic_Id.Guard_Sigil)))
	case 4:e.inventory.panel=.Character;e.progress.run.points=3
	case 5:
		rl.SetWindowSize(1280,720)
		e.inventory_open=false;e.rs.room.player.position=world.site_world(&e.world.sites[e.world.groups[0].site],{-4,0})
		_=world.engage(&e.world,&e.rs.room,0)
	case 6:
		game.end_expedition_encounter(&e.rs.room);clear(&e.rs.room.enemies)
		e.rs.room.player.position=e.rs.room.exit_position;e.world.boss_defeated=true
	case:
		if s.stage>=7 && s.stage<19 {
			expedition_smoke_world(e,campaign.Biome(s.stage-7))
			e.rs.room.player.position=world.site_world(&e.world.sites[2],{-5,0})
		} else if s.stage>=EXPEDITION_SMOKE_CENTER && s.stage<EXPEDITION_SMOKE_CENTER+12 {
			// The framing of the biome reference captures: the map's center, mounted.
			expedition_smoke_world(e,campaign.Biome(s.stage-EXPEDITION_SMOKE_CENTER))
			side:=world.size(&e.world);e.rs.room.player.position={side/2,side/2}
		} else if s.stage>=19 && s.stage<23 {
			indices:=[4]int{2,0,11,3}
			e.world.mounted=false
			e.rs.room.player.position=world.site_world(&e.world.sites[indices[s.stage-19]],{-5,0})
			e.rs.iso_renderer.tactical.expedition_follow_ready=false
			e.message_timer=0
			if s.stage==20 {
				e.rs.room.player.position=world.site_world(&e.world.sites[0],{-2,0})
				world.tick(&e.world,&e.rs.room,.1)
			} else {game.end_expedition_encounter(&e.rs.room);clear(&e.rs.room.enemies)}
		} else if s.stage==23 {rl.SetWindowSize(1024,768);e.map_open=true}
		else if s.stage==24 {rl.SetWindowSize(1280,720);e.map_open=false;expedition_smoke_behind_wall(e)}
		else if s.stage==EXPEDITION_SMOKE_WALK {e.rs.room.player.position=e.rs.room.exit_position;e.rs.room.player.position.x-=8;e.rs.iso_renderer.tactical.expedition_follow_ready=false;e.world.mounted=true}
		else if s.stage==EXPEDITION_SMOKE_ENGAGE {e.world.mounted=false;expedition_smoke_before_patrol(e)}
		else if s.stage>=EXPEDITION_SMOKE_HITS && s.stage<EXPEDITION_SMOKE_HITS+4 {
			biomes:=EXPEDITION_SMOKE_HIT_BIOMES
			expedition_smoke_world(e,biomes[s.stage-EXPEDITION_SMOKE_HITS]);e.world.mounted=false;e.message_timer=0
			expedition_smoke_hits(e)
		} else if s.stage>=EXPEDITION_SMOKE_WORKSHOP && s.stage<EXPEDITION_SMOKE_WORKSHOP+12 {
			expedition_smoke_world(e,campaign.Biome(s.stage-EXPEDITION_SMOKE_WORKSHOP));e.world.mounted=false;e.message_timer=0
			for &site in e.world.sites[:e.world.site_count] {
				if site.kind!=.Workshop {continue}
				for local in ([3]grid.Position{{0,2},{1,1},{-5,0}}) {
					p:=world.site_world(&site,local)
					if !game.cell_blocks_movement(&e.rs.room,p) {e.rs.room.player.position=p;break}
				}
				break
			}
		} else if s.stage>=EXPEDITION_SMOKE_STRUCTURES && s.stage<EXPEDITION_SMOKE_STRUCTURES+EXPEDITION_SMOKE_STRUCTURE_STEPS {
			expedition_smoke_structures(e,s.stage-EXPEDITION_SMOKE_STRUCTURES)
		} else if s.stage>=EXPEDITION_SMOKE_RELIEF && s.stage<EXPEDITION_SMOKE_RELIEF+EXPEDITION_SMOKE_RELIEF_COUNT {
			expedition_smoke_relief(e,campaign.Biome(s.stage-EXPEDITION_SMOKE_RELIEF))
		} else if s.stage>=EXPEDITION_SMOKE_HOLOGRAMS && s.stage<EXPEDITION_SMOKE_HOLOGRAMS+3 {
			biomes:=EXPEDITION_SMOKE_HOLOGRAM_BIOMES
			expedition_smoke_world(e,biomes[s.stage-EXPEDITION_SMOKE_HOLOGRAMS]);e.world.mounted=false;e.message_timer=0;e.map_open=true
		} else if s.stage==EXPEDITION_SMOKE_TWO_LEVELS {e.map_open=false;expedition_smoke_two_levels(e)}
		else if s.stage>=EXPEDITION_SMOKE_MOUNTAIN && s.stage<EXPEDITION_SMOKE_MOUNTAIN+EXPEDITION_SMOKE_MOUNTAIN_STEPS {expedition_smoke_mountain(e,s.stage-EXPEDITION_SMOKE_MOUNTAIN)}
		else if s.stage>=EXPEDITION_SMOKE_MOUNTAIN+EXPEDITION_SMOKE_MOUNTAIN_STEPS {host.quit(frame)}
	}
}

// The robot in the biome's most uneven place: the walkable cell whose 7 by 7 neighbourhood spans the most steps,
// the nearest to the spawn if there are several.
@(private)
expedition_smoke_relief :: proc(e:^run.Expedition_Session,biome:campaign.Biome) {
	expedition_smoke_world(e,biome);e.world.mounted=false;e.message_timer=0
	data:=e.rs.room.level_data
	best,best_range,best_distance:=grid.Position{},-1,1<<30
	for y in 14..<data.tiles.height-14 {for x in 14..<data.tiles.width-14 {
		cell:=grid.Position{x,y};tile,_:=level.tile_at(data,cell)
		if !level.is_walkable(tile.kind) || game.cell_blocks_movement(&e.rs.room,cell) {continue}
		low,high:=i32(1000),i32(-1)
		for dy in -3..=3 {for dx in -3..=3 {
			h:=level.height_at(data,{x+dx,y+dy});low=min(low,h);high=max(high,h)
		}}
		// The tallest relief first, then the nearer to the middle of the map.
		spread:=int(high-low)*100+int(high);distance:=world.distance(cell,{data.tiles.width/2,data.tiles.height/2})
		if spread>best_range || (spread==best_range && distance<best_distance) {best,best_range,best_distance=cell,spread,distance}
	}}
	e.rs.room.player.position=best
	e.rs.iso_renderer.tactical.expedition_follow_ready=false
}

// One step of the mountain's act: the robot at `step` of eight places of the climb (the first at the foot, the last
// at the top). The first step also checks the map: the mountain, its patrol, its relic and the walk to the top.
@(private)
expedition_smoke_mountain :: proc(e:^run.Expedition_Session,step:int) {
	if step==0 {
		expedition_smoke_world(e,.Snow);e.world.mounted=false;e.message_timer=0
		assert(world.mountain_present(&e.world),"the Snow has no mountain")
		summit:=world.mountain_cell(level.mountain_summit())
		assert(int(level.height_at(e.rs.room.level_data,summit))==level.MOUNTAIN_TOP,"the mountain has no summit")
		found:=false
		for drop in e.world.drops[:e.world.drop_count] {if drop.position==summit && drop.item.kind==.Relic {found=true}}
		assert(found,"no relic at the summit")
		patrol:=false
		for group in e.world.groups[:e.world.group_count] {
			if group.patrol && world.distance(group.anchor,world.mountain_cell(level.mountain_midway()))<=1 {patrol=true}
		}
		assert(patrol,"no patrol halfway up the mountain")
	}
	laps:=f32(step)*f32(level.MOUNTAIN_LAPS)/f32(EXPEDITION_SMOKE_MOUNTAIN_STEPS-1)
	laps=clamp(laps,0.05,f32(level.MOUNTAIN_LAPS)-0.05)
	e.rs.room.player.position=world.mountain_cell(level.mountain_path_cell(laps))
	if step==EXPEDITION_SMOKE_MOUNTAIN_STEPS-1 {e.rs.room.player.position=world.mountain_cell(level.mountain_summit())}
	e.rs.iso_renderer.tactical.expedition_follow_ready=false
}

// A fight on two levels: the robot on a Snow plateau, one foe on the ground three steps or more below.
@(private)
expedition_smoke_two_levels :: proc(e:^run.Expedition_Session) {
	expedition_smoke_world(e,.Snow);e.world.mounted=false;e.message_timer=0
	data:=e.rs.room.level_data
	high_cell,low_cell,best:=grid.Position{},grid.Position{},1<<30
	for y in 14..<data.tiles.height-14 {for x in 14..<data.tiles.width-14 {
		cell:=grid.Position{x,y}
		if level.height_at(data,cell)<4 || game.cell_blocks_movement(&e.rs.room,cell) {continue}
		for dy in -3..=3 {for dx in -3..=3 {
			other:=grid.Position{x+dx,y+dy}
			if abs(dx)+abs(dy)<2 || level.height_at(data,other)>1 || game.cell_blocks_movement(&e.rs.room,other) {continue}
			distance:=world.distance(cell,{data.tiles.width/2,data.tiles.height/2})
			if distance<best {high_cell,low_cell,best=cell,other,distance}
		}}
	}}
	assert(best<1<<30,"the Snow has no plateau to fight over")
	e.rs.room.player.position=high_cell
	if e.rs.room.phase!=.Combat {_=game.begin_expedition_encounter(&e.rs.room)}
	_,_=game.spawn_enemy(&e.rs.room,{position=low_cell,health=10,attack=2,archetype=.Chaser})
	e.rs.iso_renderer.tactical.expedition_follow_ready=false
}

// One step of the structures' act: where the robot stands and what the building should be doing.
@(private)
expedition_smoke_structures :: proc(e:^run.Expedition_Session,step:int) {
	if step==0 {expedition_smoke_world(e,.Cyber);e.world.mounted=false;e.message_timer=0}
	data:=e.rs.room.level_data
	hut:=-1
	for placed,i in data.structures {if placed.id==.Hut {hut=i;break}}
	assert(hut>=0,"the first biome has no hut")
	placed:=data.structures[hut];plan:=&data.structure_plans[hut]
	door,outward:=grid.Position{},grid.Position{}
	for y in 0..<plan.height {for x in 0..<plan.width {
		if level.plan_at(plan,x,y)!=.Door {continue}
		door={placed.origin.x+x,placed.origin.y+y}
		for d in ([4]grid.Position{{1,0},{-1,0},{0,1},{0,-1}}) {if level.plan_at(plan,x+d.x,y+d.y)==.Outside {outward=d}}
	}}
	at:grid.Position
	expected:game.Structure_Stage
	switch step {
	case 0:at,expected=grid.Position{door.x+outward.x*6,door.y+outward.y*6},.Far
	case 1:at,expected=grid.Position{door.x+outward.x*4,door.y+outward.y*4},.Approaching
	case 2:at,expected=grid.Position{door.x+outward.x*2,door.y+outward.y*2},.Approaching
	case 3:at,expected=grid.Position{door.x+outward.x,door.y+outward.y},.Threshold
	case 4:at,expected=door,.Threshold
	case 5:at,expected=grid.Position{door.x-outward.x*2,door.y-outward.y*2},.Inside
	case 6:at,expected=grid.Position{door.x+outward.x*4,door.y+outward.y*4},.Approaching
	case:
		// Round the objects: next to the first one that is not a building.
		expected=.Far
		for other,i in data.structures {
			if level.structure_is_building(other.id) {continue}
			for d in ([6]grid.Position{{-3,0},{3,0},{0,-3},{0,3},{-4,1},{4,-1}}) {
				p:=game.add_position(other.origin,d)
				if !game.cell_blocks_movement(&e.rs.room,p) {at=p;break}
			}
			_=i;break
		}
	}
	e.rs.room.player.position=at
	e.rs.iso_renderer.tactical.expedition_follow_ready=false
	if step<7 {
		view:=game.structure_visibility(data,hut,{f32(at.x)+.5,f32(at.y)+.5})
		assert(view.stage==expected,"the hut is not in the stage the act expects")
		if view.stage==.Inside {assert(view.opacity==1 && !view.roof,"inside, the walls are whole and the roof hidden")}
	}
}
