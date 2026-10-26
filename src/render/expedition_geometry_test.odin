package render

import "core:math"
import "core:fmt"
import "core:slice"
import "core:testing"
import rl "vendor:raylib"
import campaign "../campaign"
import world "../expedition"
import game "../game"
import grid "../engine/grid"
import level "../level"

@(test)
test_expedition_architecture_key_ignores_animation_camera_and_combat :: proc(t:^testing.T) {
	data,ok:=level.create(32,32,{.Floor});testing.expect(t,ok);defer level.destroy(&data)
	w:=new(world.World);defer free(w)
	w.biome=.Cyber;w.site_count=1
	w.sites[0]={position={x = 16, y = 16},kind=.Archive,layout_version=world.SITE_LAYOUT_VERSION,active=true}
	p:=game.Player{position={x = 5, y = 5}};room:=game.Room{level_data=&data,player=&p}
	r:=new(Renderer);defer free(r)
	key:=expedition_geometry_key(&room,w)
	for i in 0..<120 {
		w.clock=f32(i)*.25;w.beat=u64(i);w.seed=u64(i);w.lane_warning=i%2==0
		w.sites[0].wave=i%3;p.position={x = i%16, y = i%23}
		room.phase=.Combat if i%2==0 else .Loot
		r.canvas_width=960+f32(i);r.canvas_height=540
		r.tactical.camera.position={f32(i),12,25};r.tactical.camera.target={f32(i),0,5}
		testing.expect_value(t,expedition_geometry_key(&room,w),key)
	}
}

@(test)
test_expedition_architecture_key_invalidates_geometry_site_activation_and_layout :: proc(t:^testing.T) {
	data,ok:=level.create(32,32,{.Floor});testing.expect(t,ok);defer level.destroy(&data)
	w:=new(world.World);defer free(w)
	w.biome=.Cyber;w.site_count=1
	w.sites[0]={position={x = 16, y = 16},kind=.Archive,layout_version=world.SITE_LAYOUT_VERSION}
	room:=game.Room{level_data=&data}
	previous:=expedition_geometry_key(&room,w)
	_=level.set_tile(&data,{x = 3, y = 3},{.Wall})
	next:=expedition_geometry_key(&room,w);testing.expect(t,next!=previous);previous=next
	for change in 0..<9 {
		switch change {
		case 0:w.sites[0].active=true
		case 1:w.sites[0].state=.Resolved
		case 2:w.sites[0].orientation=1
		case 3:w.sites[0].position.x+=1
		case 4:w.sites[0].layout_version=0
		case 5:w.sites[0].kind=.Workshop
		case 6:w.biome=.City
		case 7:w.sites[0].secret=true
		case 8:w.boss_defeated=true
		}
		next=expedition_geometry_key(&room,w);testing.expect(t,next!=previous);previous=next
	}
	// Reusing a Level allocation for a different world must not reuse VBOs.
	level.destroy(&data);data,ok=level.create(32,32,{.Floor});testing.expect(t,ok)
	next=expedition_geometry_key(&room,w);testing.expect(t,next!=previous);previous=next
	level.destroy(&data);data,ok=level.create(10,10,{.Floor});testing.expect(t,ok)
	testing.expect(t,expedition_geometry_key(&room,w)!=previous)
}

@(test)
test_expedition_chunk_bakes_only_its_walls_without_gpu_and_stays_deterministic :: proc(t:^testing.T) {
	data,ok:=level.create(10,10,{.Floor});testing.expect(t,ok);defer level.destroy(&data)
	w:=new(world.World);defer free(w);w.biome=.City
	r:=new(Renderer);defer free(r)
	room:=game.Room{level_data=&data}
	for p in ([4]grid.Position{{x = 0, y = 0},{x = 7, y = 7},{x = 8, y = 8},{x = 9, y = 9}}) {_=level.set_tile(&data,p,{.Wall})}
	builder:Expedition_Geometry_Builder;defer {delete(builder.vertices);delete(builder.lines)}
	expedition_build_chunk(r,&room,w,{x = 0, y = 0},&builder)
	testing.expect(t,len(builder.vertices)>0 && len(builder.vertices)<=1800)
	testing.expect(t,len(builder.lines)>0 && len(builder.lines)<=32)
	for v in builder.vertices {
		testing.expect(t,v.position.x>=0 && v.position.x<8 && v.position.z>=0 && v.position.z<8)
		testing.expect(t,abs(rl.Vector3LengthSqr(v.normal)-1)<.00001)
		for value in v.position {testing.expect(t,!math.is_nan(value) && !math.is_inf(value))}
	}
	vertices:=make([]Expedition_Baked_Vertex,len(builder.vertices));defer delete(vertices);copy(vertices,builder.vertices[:])
	lines:=make([]Expedition_Baked_Line,len(builder.lines));defer delete(lines);copy(lines,builder.lines[:])
	w.clock=123;w.seed=456;r.tactical.camera.position={100,50,40}
	clear(&builder.vertices);clear(&builder.lines)
	expedition_build_chunk(r,&room,w,{x = 0, y = 0},&builder)
	testing.expect_value(t,len(builder.vertices),len(vertices));testing.expect_value(t,len(builder.lines),len(lines))
	for v,i in builder.vertices {testing.expect_value(t,v,vertices[i])}
	for line,i in builder.lines {testing.expect_value(t,line,lines[i])}
	clear(&builder.vertices);clear(&builder.lines)
	expedition_build_chunk(r,&room,w,{x = 8, y = 8},&builder)
	testing.expect(t,len(builder.vertices)>0 && len(builder.vertices)<=1800)
	for v in builder.vertices {testing.expect(t,v.position.x>=8 && v.position.x<10 && v.position.z>=8 && v.position.z<10)}
}

@(test)
test_expedition_chunk_excludes_active_fixture_and_restores_dormant_cover :: proc(t:^testing.T) {
	data,ok:=level.create(32,32,{.Floor});testing.expect(t,ok);defer level.destroy(&data)
	w:=new(world.World);defer free(w);w.biome=.City;w.site_count=1
	w.sites[0]={kind=.Archive,position={x = 16, y = 16},layout_version=world.SITE_LAYOUT_VERSION,active=true}
	_=level.set_tile(&data,{x = 16, y = 16},{.Wall})
	r:=new(Renderer);defer free(r);expedition_gather_sites(r,w,{x = 0, y = 0},{x = 31, y = 31})
	room:=game.Room{level_data=&data}
	builder:Expedition_Geometry_Builder;defer {delete(builder.vertices);delete(builder.lines)}
	expedition_build_chunk(r,&room,w,{x = 16, y = 16},&builder)
	testing.expect_value(t,len(builder.vertices),0);testing.expect_value(t,len(builder.lines),0)
	w.sites[0].active=false
	expedition_build_chunk(r,&room,w,{x = 16, y = 16},&builder)
	testing.expect(t,len(builder.vertices)>0 && len(builder.vertices)<=600)
	testing.expect(t,len(builder.lines)>0 && len(builder.lines)<=16)
	for v in builder.vertices {
		testing.expect(t,v.position.x>=16 && v.position.x<17 && v.position.z>=16 && v.position.z<17)
		testing.expect(t,v.position.y>=0 && v.position.y<2)
		testing.expect(t,abs(rl.Vector3LengthSqr(v.normal)-1)<.00001)
	}
	clear(&builder.vertices);clear(&builder.lines);w.sites[0].active=true
	expedition_build_chunk(r,&room,w,{x = 16, y = 16},&builder)
	testing.expect_value(t,len(builder.vertices),0)
}

@(test)
test_expedition_chunk_frustum_keeps_mirrored_geometry_and_reveal_reach :: proc(t:^testing.T) {
	for projection in ([2]rl.CameraProjection{.PERSPECTIVE,.ORTHOGRAPHIC}) {
		camera:=rl.Camera3D{position={0,4,10},target={0,-2,0},up={0,1,0},projection=projection,fovy=45 if projection==.PERSPECTIVE else 8}
		frustum:=tactical_draw_frustum(camera,960,540)
		chunk:=Expedition_Geometry_Chunk{center={0,5,0},radius=.2,ready=true}
		testing.expect(t,!expedition_chunk_visible(&frustum,&chunk,false))
		testing.expect(t,expedition_chunk_visible(&frustum,&chunk,true))
		projected:=rl.GetWorldToScreenEx({0,-5,0},camera,960,540)
		testing.expect(t,projected.x>=0 && projected.x<=960 && projected.y>=0 && projected.y<=540)
		chunk.center={100,5,0};testing.expect(t,!expedition_chunk_visible(&frustum,&chunk,true))
		chunk.center={0,4,20};testing.expect(t,!expedition_chunk_visible(&frustum,&chunk,false))
	}
	material:=new(Expedition_Material);defer free(material)
	material.reveal_point_count=1;material.actors[0]={8,8};material.toward_camera={0,1}
	testing.expect(t,expedition_occludes(material,{8,14},2,7))
	testing.expect(t,!expedition_occludes(material,{8,1},2,7))
	testing.expect(t,!expedition_occludes(material,{24,14},2,7))
	material.reveal_point_count=0
	testing.expect(t,!expedition_occludes(material,{8,14},2,7))
}

@(test)
test_expedition_geometry_releases_cpu_lines_and_resets_cache_identity :: proc(t:^testing.T) {
	for failed in ([2]bool{false,true}) {
		cache:=Expedition_Architecture_Cache{ready=!failed,failed=failed,rebuilds=3,uploads=12,columns=2,rows=1}
		cache.chunks=make([]Expedition_Geometry_Chunk,2)
		for &chunk,i in cache.chunks {chunk.lines=make([]Expedition_Baked_Line,3);chunk.ready=!failed || i==0}
		for &chunk,i in cache.sites {
			chunk.lines=make([]Expedition_Baked_Line,1+i%3)
			chunk.ready=!failed || i<2;chunk.center={f32(i),2,4};chunk.radius=7
		}
		// A failed upload leaves its copied CPU lines beside earlier completed
		// chunks. Both remain owned by the cache until invalidation/shutdown.
		// Empty meshes exercise that ownership without a native context.
		destroy_expedition_geometry(&cache)
		testing.expect(t,!cache.ready && !cache.failed && len(cache.chunks)==0 && raw_data(cache.chunks)==nil)
		testing.expect_value(t,cache.key,Expedition_Architecture_Key{})
		testing.expect(t,cache.rebuilds==0 && cache.uploads==0 && cache.columns==0 && cache.rows==0)
		for &site in cache.sites {
			testing.expect(t,!site.ready && len(site.lines)==0 && raw_data(site.lines)==nil)
			testing.expect(t,site.mesh.vertexCount==0 && site.radius==0 && site.center==rl.Vector3{})
		}
		destroy_expedition_geometry(&cache)
	}
}

@(test)
test_expedition_all_biomes_static_site_bake_is_complete_bounded_and_clock_independent :: proc(t:^testing.T) {
	w:=new(world.World);defer free(w)
	a,b:Expedition_Geometry_Builder
	defer {delete(a.vertices);delete(a.lines);delete(b.vertices);delete(b.lines)}
	for biome in campaign.Biome.Cyber..<campaign.Biome.Count {for kind in world.Site_Kind {for orientation in u8(0)..<4 {
		w.biome=biome;w.boss_defeated=true
		site:=world.Site{position={x = 32, y = 32},kind=kind,orientation=orientation,active=true,layout_version=world.SITE_LAYOUT_VERSION}
		clear(&a.vertices);clear(&a.lines);clear(&b.vertices);clear(&b.lines)
		draw_expedition_site_static({mode=.Bake,builder=&a},w,&site)
		// A defeated boss must not accidentally bake the rotating exit ring.
		w.clock+=.13;w.beat+=11;w.seed+=31;site.wave+=1;site.seed+=23
		draw_expedition_site_static({mode=.Bake,builder=&b},w,&site)
		identical:=slice.equal(a.vertices[:],b.vertices[:]) && slice.equal(a.lines[:],b.lines[:])
		// A cave's mouth is the opening the relief leaves in its massif (expedition_terrain.odin): only its arch of light.
		if kind==.Cave {
			testing.expectf(t,identical && len(a.vertices)==0 && len(a.lines)>0,"%v Cave rotation%d: vertices%d lines%d",biome,orientation,len(a.vertices),len(a.lines))
			continue
		}
		valid:=len(a.vertices)>0 && len(a.vertices)%3==0 && len(a.vertices)<=6000 && len(a.lines)<=128
		lo,hi:=world.site_bounds(&site);minimum_height:=max(f32)
		for v in a.vertices {
			valid=valid && v.position.x>=f32(lo.x) && v.position.x<=f32(hi.x+1) && v.position.z>=f32(lo.y) && v.position.z<=f32(hi.y+1)
			valid=valid && v.position.y>=0 && v.position.y<6 && abs(rl.Vector3LengthSqr(v.normal)-1)<.001 && v.color.a==255
			for component in v.position {valid=valid && !math.is_nan(component) && !math.is_inf(component)}
			minimum_height=min(minimum_height,v.position.y)
		}
		for i:=0;i+2<len(a.vertices);i+=3 {
			p,q,r:=a.vertices[i],a.vertices[i+1],a.vertices[i+2]
			n:=rl.Vector3CrossProduct(q.position-p.position,r.position-p.position)
			valid=valid && rl.Vector3LengthSqr(n)>.00000000001 && rl.Vector3DotProduct(n,p.normal)>0
		}
		for line in a.lines {
			valid=valid && line.color.a>0 && rl.Vector3DistanceSqr(line.a,line.b)>.000001
			for p in ([2]rl.Vector3{line.a,line.b}) {for component in p {valid=valid && !math.is_nan(component) && !math.is_inf(component)}}
		}
		// Gate lintels alone are all overhead. A low base confirms the
		// fixture dispatch contributed real geometry for each of the 9 kinds.
		testing.expect(t,valid && identical && minimum_height<=.05,
			fmt.tprintf("%v %v rotation%d: valid%v stable%v minY%.3f vertices%d lines%d",biome,kind,orientation,valid,identical,minimum_height,len(a.vertices),len(a.lines)))
	}}}
}

@(test)
test_expedition_chunk_reveal_uses_full_extent_across_actor_plane :: proc(t:^testing.T) {
	m:=new(Expedition_Material);defer free(m)
	m.reveal_point_count=1;m.actors[0]={10,10};m.toward_camera={0,1}
	// Its center is behind the actor, but an 8-cell radius reaches well in
	// front. Testing the center alone must not leave its front wall opaque.
	chunk:=Expedition_Geometry_Chunk{center={10,1,8},radius=8,ready=true}
	testing.expect(t,expedition_chunk_revealed(m,&chunk))
	chunk.center={30,1,8};testing.expect(t,!expedition_chunk_revealed(m,&chunk))
	chunk.center={10,1,-10};testing.expect(t,!expedition_chunk_revealed(m,&chunk))
	chunk.center={10,1,35};testing.expect(t,!expedition_chunk_revealed(m,&chunk))
	chunk.center={10,1,8};chunk.radius=.2;testing.expect(t,!expedition_chunk_revealed(m,&chunk))
	chunk.radius=8;m.reveal_point_count=0;testing.expect(t,!expedition_chunk_revealed(m,&chunk))
	m.reveal_point_count=1;m.reflection_pass=true;testing.expect(t,!expedition_chunk_revealed(m,&chunk))
	testing.expect(t,!expedition_chunk_revealed(nil,&chunk))
}
