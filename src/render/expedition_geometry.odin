package render

import "core:c"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import world "../expedition"
import game "../game"
import grid "../engine/grid"
import level "../level"

// One upload per static 8x8 region. The cache belongs to the view's material;
// camera, combat, window resize and the cosmetic clock never invalidate it.
EXPEDITION_GEOMETRY_CHUNK :: 8
Expedition_Baked_Vertex :: struct { position,normal:rl.Vector3, color:rl.Color }
Expedition_Baked_Line :: struct { a,b:rl.Vector3, color:rl.Color }
Expedition_Geometry_Builder :: struct {
	vertices:[dynamic]Expedition_Baked_Vertex,
	lines:[dynamic]Expedition_Baked_Line,
}
Expedition_Geometry_Chunk :: struct {
	mesh:rl.Mesh,
	lines:[]Expedition_Baked_Line,
	center:rl.Vector3,
	radius:f32,
	ready:bool,
}
Expedition_Architecture_Key :: struct {
	geometry_id,revision:u64,
	width,height:int,
	biome:u8,
	sites:[world.MAX_SITES]Expedition_Floor_Site_Key,
	active:[world.MAX_SITES]bool,
	secret:[world.MAX_SITES]bool,
	states:[world.MAX_SITES]world.Site_State,
	site_count:int,
	boss_defeated:bool,
}
Expedition_Architecture_Cache :: struct {
	key:Expedition_Architecture_Key,
	chunks:[]Expedition_Geometry_Chunk,
	sites:[world.MAX_SITES]Expedition_Geometry_Chunk,
	columns,rows:int,
	lo,hi:grid.Position,
	ready,failed:bool,
	rebuilds,uploads:u64,
}

@(private)
expedition_geometry_key :: proc(room:^game.Room,w:^world.World)->(key:Expedition_Architecture_Key) {
	data:=room.level_data
	key.geometry_id=data.geometry_id;key.revision=data.geometry_revision
	key.width=data.tiles.width;key.height=data.tiles.height;key.biome=u8(w.biome)
	key.sites=expedition_floor_site_keys(w);key.site_count=clamp(world.visible_sites(w),0,world.MAX_SITES)
	key.boss_defeated=w.boss_defeated
	for site,i in w.sites[:key.site_count] {key.active[i]=site.active;key.secret[i]=site.secret;key.states[i]=site.state}
	return
}

@(private)
destroy_expedition_geometry :: proc(cache:^Expedition_Architecture_Cache) {
	for &chunk in cache.chunks {
		if chunk.mesh.vertexCount>0 {rl.UnloadMesh(chunk.mesh)}
		delete(chunk.lines)
	}
	for &chunk in cache.sites {
		if chunk.mesh.vertexCount>0 {rl.UnloadMesh(chunk.mesh)}
		delete(chunk.lines)
	}
	delete(cache.chunks);cache^={}
}

@(private)
expedition_build_chunk :: proc(renderer:^Renderer,room:^game.Room,w:^world.World,origin:grid.Position,builder:^Expedition_Geometry_Builder) {
	pass:=Ink_Pass{mode=.Bake,builder=builder}
	for y in origin.y..<min(origin.y+EXPEDITION_GEOMETRY_CHUNK,room.level_data.tiles.height) {
		for x in origin.x..<min(origin.x+EXPEDITION_GEOMETRY_CHUNK,room.level_data.tiles.width) {
			cell:=grid.Position{x,y};tile,_:=level.tile_at(room.level_data,cell)
			if tile.kind!=.Wall && tile.kind!=.Fence {continue}
			ground:=pass;ground.lift=cell_ground(cell)
			if draw_expedition_structure_solid(ground,room,w,cell,tile.kind) {continue}
			site_index,design:=expedition_site_near(renderer,w,cell)
			if design.fixture && site_index>=0 && w.sites[site_index].active {continue}
			if design.inside {draw_expedition_site_wall(ground,room,w,&w.sites[site_index],cell,design)}
			else {draw_expedition_outdoor_prop(ground,w,cell)}
		}
	}
}

@(private)
expedition_upload_chunk :: proc(chunk:^Expedition_Geometry_Chunk,builder:^Expedition_Geometry_Builder,origin:grid.Position)->bool {
	chunk.lines=make([]Expedition_Baked_Line,len(builder.lines));copy(chunk.lines,builder.lines[:])
	if len(builder.vertices)==0 {chunk.center={f32(origin.x)+4,0,f32(origin.y)+4};chunk.ready=true;return true}
	mesh:=&chunk.mesh;n:=len(builder.vertices)
	mesh.vertexCount=c.int(n);mesh.triangleCount=c.int(n/3)
	mesh.vertices=cast([^]f32)rl.MemAlloc(c.uint(n*3*size_of(f32)))
	mesh.normals=cast([^]f32)rl.MemAlloc(c.uint(n*3*size_of(f32)))
	mesh.colors=cast([^]u8)rl.MemAlloc(c.uint(n*4))
	if mesh.vertices==nil || mesh.normals==nil || mesh.colors==nil {
		rl.UnloadMesh(mesh^);mesh^={};return false
	}
	minimum,maximum:=builder.vertices[0].position,builder.vertices[0].position
	for v,i in builder.vertices {
		for axis in 0..<3 {
			mesh.vertices[i*3+axis]=v.position[axis];mesh.normals[i*3+axis]=v.normal[axis]
			minimum[axis]=min(minimum[axis],v.position[axis]);maximum[axis]=max(maximum[axis],v.position[axis])
		}
		mesh.colors[i*4]=v.color.r;mesh.colors[i*4+1]=v.color.g;mesh.colors[i*4+2]=v.color.b;mesh.colors[i*4+3]=v.color.a
	}
	chunk.center=(minimum+maximum)*.5;chunk.radius=rl.Vector3Distance(minimum,maximum)*.5+.1
	rl.UploadMesh(mesh,false)
	if mesh.vboId==nil || mesh.vboId[0]==0 {rl.UnloadMesh(mesh^);mesh^={};return false}
	chunk.ready=true
	return true
}

@(private)
prepare_expedition_geometry :: proc(renderer:^Renderer,room:^game.Room,w:^world.World)->bool {
	m:=renderer.tactical.expedition_material
	if m==nil || !rl.IsWindowReady() {return false}
	cache:=&m.geometry;key:=expedition_geometry_key(room,w)
	if cache.failed && cache.key==key {return false}
	if !cache.ready || cache.key!=key {
		rebuilds,uploads:=cache.rebuilds,cache.uploads
		destroy_expedition_geometry(cache)
		cache.key=key;cache.rebuilds=rebuilds+1;cache.uploads=uploads
		cache.columns=(key.width+EXPEDITION_GEOMETRY_CHUNK-1)/EXPEDITION_GEOMETRY_CHUNK
		cache.rows=(key.height+EXPEDITION_GEOMETRY_CHUNK-1)/EXPEDITION_GEOMETRY_CHUNK
		cache.chunks=make([]Expedition_Geometry_Chunk,cache.columns*cache.rows);cache.ready=true
	}
	p:=room.player.position
	cache.lo={max(0,p.x-26)/EXPEDITION_GEOMETRY_CHUNK,max(0,p.y-26)/EXPEDITION_GEOMETRY_CHUNK}
	cache.hi={min(cache.columns-1,(p.x+26)/EXPEDITION_GEOMETRY_CHUNK),min(cache.rows-1,(p.y+26)/EXPEDITION_GEOMETRY_CHUNK)}
	builder:Expedition_Geometry_Builder
	defer {delete(builder.vertices);delete(builder.lines)}
	for y in cache.lo.y..=cache.hi.y {for x in cache.lo.x..=cache.hi.x {
		chunk:=&cache.chunks[y*cache.columns+x];if chunk.ready {continue}
		clear(&builder.vertices);clear(&builder.lines)
		origin:=grid.Position{x*EXPEDITION_GEOMETRY_CHUNK,y*EXPEDITION_GEOMETRY_CHUNK}
		expedition_build_chunk(renderer,room,w,origin,&builder)
		rlgl.DrawRenderBatchActive()
		if !expedition_upload_chunk(chunk,&builder,origin) {cache.ready=false;cache.failed=true;return false}
		cache.uploads+=1
	}}
	for &site,i in w.sites[:key.site_count] {
		chunk:=&cache.sites[i]
		if chunk.ready || !site.active || world.distance(site.position,p)>30 {continue}
		clear(&builder.vertices);clear(&builder.lines)
		draw_expedition_site_static({mode=.Bake,builder=&builder},w,&site)
		rlgl.DrawRenderBatchActive()
		if !expedition_upload_chunk(chunk,&builder,site.position) {cache.ready=false;cache.failed=true;return false}
		cache.uploads+=1
	}
	return true
}

@(private)
collect_expedition_cached_edges :: proc(renderer:^Renderer,room:^game.Room,w:^world.World) {
	m:=renderer.tactical.expedition_material;cache:=&m.geometry
	for y in cache.lo.y..=cache.hi.y {for x in cache.lo.x..=cache.hi.x {
		for line in cache.chunks[y*cache.columns+x].lines {expedition_collect_edge(&m.edges,line.a,line.b,line.color)}
	}}
	for site,i in w.sites[:cache.key.site_count] {
		if !site.active || world.distance(site.position,room.player.position)>30 {continue}
		for line in cache.sites[i].lines {expedition_collect_edge(&m.edges,line.a,line.b,line.color)}
	}
}

@(private)
expedition_chunk_visible :: proc(f:^Tactical_Draw_Frustum,chunk:^Expedition_Geometry_Chunk,reflection:bool)->bool {
	if !f.valid {return true}
	center:=chunk.center;if reflection {center.y=-center.y}
	delta:=center-f.eye;radius:=chunk.radius
	z:=rl.Vector3DotProduct(delta,f.forward)
	if z+radius<=0 {return false}
	x,y:=abs(rl.Vector3DotProduct(delta,f.right)),abs(rl.Vector3DotProduct(delta,f.up))
	if !f.perspective {return x<=f.horizontal+radius && y<=f.vertical+radius}
	return x<=z*f.horizontal+radius*f.horizontal_margin && y<=z*f.vertical+radius*f.vertical_margin
}

@(private)
expedition_chunk_revealed :: proc(m:^Expedition_Material,chunk:^Expedition_Geometry_Chunk)->bool {
	if m==nil || m.reflection_pass {return false}
	for actor in m.actors[:m.reveal_point_count] {
		d:=rl.Vector2{chunk.center.x,chunk.center.z}-actor
		along:=d.x*m.toward_camera.x+d.y*m.toward_camera.y
		side:=abs(d.x*m.toward_camera.y-d.y*m.toward_camera.x)
		// A whole cached mesh may straddle the actor even with its center
		// behind them. The fragment shader makes the exact depth/screen cut.
		if along>-.6-chunk.radius && along<5+chunk.radius && side<1.3+chunk.radius {return true}
	}
	return false
}

@(private)
draw_expedition_cached_architecture :: proc(renderer:^Renderer,room:^game.Room,w:^world.World)->bool {
	m:=renderer.tactical.expedition_material
	if m==nil || !m.geometry.ready {return false}
	cache:=&m.geometry
	rlgl.DrawRenderBatchActive();rlgl.DisableBackfaceCulling()
	defer {rlgl.DrawRenderBatchActive();rlgl.EnableBackfaceCulling()}
	maps:[12]rl.MaterialMap;maps[0].color=rl.WHITE
	for layer in Ink_Layer {
		if layer==.Revealed && (m.reveal_point_count==0 || m.reflection_pass) {continue}
		if layer==.Edges {begin_expedition_edges(renderer)}
		else {begin_expedition_material(renderer,w,reveal=layer==.Revealed)}
		shader:=m.reveal_shader if layer==.Revealed else m.shader
		if layer!=.Edges && m.reflection_pass {
			// VBOs retain original world-space vertices; only their MVP mirrors.
			// Immediate geometry below is pretransformed by rlgl and needs 1.
			mirror:=f32(0);rl.SetShaderValue(shader,m.light_uniforms.mirror,&mirror,.FLOAT)
		}
		for y in cache.lo.y..=cache.hi.y {for x in cache.lo.x..=cache.hi.x {
			chunk:=&cache.chunks[y*cache.columns+x]
			if !chunk.ready || !expedition_chunk_visible(&renderer.tactical.draw_frustum,chunk,m.reflection_pass) {continue}
			if layer==.Edges {
				for line in chunk.lines {draw_expedition_ribbon(&m.edges,line.a,line.b,line.color)}
				continue
			}
			revealed:=expedition_chunk_revealed(m,chunk)
			if revealed!=(layer==.Revealed) {continue}
			if chunk.mesh.vertexCount>0 {rl.DrawMesh(chunk.mesh,{shader=shader,maps=raw_data(maps[:])},rl.Matrix(1))}
		}}
		for site,i in w.sites[:cache.key.site_count] {
			if !site.active || world.distance(site.position,room.player.position)>30 {continue}
			chunk:=&cache.sites[i]
			if !chunk.ready || !expedition_chunk_visible(&renderer.tactical.draw_frustum,chunk,m.reflection_pass) {continue}
			if layer==.Edges {
				for line in chunk.lines {draw_expedition_ribbon(&m.edges,line.a,line.b,line.color)}
				continue
			}
			revealed:=expedition_chunk_revealed(m,chunk)
			if revealed!=(layer==.Revealed) {continue}
			if chunk.mesh.vertexCount>0 {rl.DrawMesh(chunk.mesh,{shader=shader,maps=raw_data(maps[:])},rl.Matrix(1))}
		}
		if layer!=.Edges && m.reflection_pass {mirror:=f32(1);rl.SetShaderValue(shader,m.light_uniforms.mirror,&mirror,.FLOAT)}
		draw_expedition_site_architecture(layer,renderer,room,w,dynamic_only=true)
		if layer==.Edges {end_expedition_edges(renderer)}
		else {rlgl.DrawRenderBatchActive();rl.EndShaderMode()}
	}
	draw_expedition_structure_envelopes(renderer,room,w)
	return true
}
