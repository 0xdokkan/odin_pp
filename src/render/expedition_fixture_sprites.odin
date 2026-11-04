package render

import "core:math"
import "core:c"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import world "../expedition"
import game "../game"
import grid "../engine/grid"
import level "../level"

// Alpha-tested paper writes depth only where the cut exists. A transparent
// atlas cell must never leave a rectangular occluder in front of an actor.
@(private)
FIXTURE_FRAGMENT :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform int fixtureLinear;
out vec4 finalColor;
void main() {
    vec4 ink=texture(texture0,fragTexCoord);
    if(ink.a<.5) discard;
    finalColor=ink*fragColor*colDiffuse;
    if(fixtureLinear!=0) finalColor.rgb=pow(max(finalColor.rgb,vec3(0.)),vec3(2.2));
}`

@(private)
expedition_fixture_is_sprite :: proc(kind:world.Site_Kind)->bool {
	return kind==.Nest || kind==.Cache || kind==.Archive || kind==.Workshop || kind==.Spring || kind==.Memory
}

@(private)
expedition_workshop_is_sprite :: proc(site:^world.Site,design:world.Site_Cell)->bool {
	return site.kind==.Workshop && design.inside && design.wall && !design.fixture && design.wall_height<1.1
}

@(private)
expedition_workshop_sprite_cells :: proc(site:^world.Site)->(cells:[64]grid.Position,count:int) {
	if site.kind!=.Workshop || site.layout_version!=world.SITE_LAYOUT_VERSION {return}
	lo,hi:=world.site_bounds(site)
	for y in lo.y..=hi.y {for x in lo.x..=hi.x {
		cell:=grid.Position{x=x,y=y,layer=site.position.layer}
		if !expedition_workshop_is_sprite(site,world.site_cell(site,cell)) {continue}
		assert(count<len(cells),"workshop paper cover storage exhausted")
		cells[count]=cell;count+=1
	}}
	return
}

@(private)
ensure_expedition_fixture_sprites :: proc(m:^Expedition_Material)->bool {
	if m==nil {return false}
	if m.fixtures_attempted {return m.fixtures!=nil && m.fixture_shader.id!=0}
	m.fixtures_attempted=true
	m.fixtures=create_expedition_fixture_art()
	if m.fixtures==nil {return false}
	m.fixture_shader=rl.LoadShaderFromMemory(nil,FIXTURE_FRAGMENT)
	if m.fixture_shader.id==0 {destroy_expedition_fixture_art(m.fixtures);m.fixtures=nil;return false}
	m.fixture_linear=rl.GetShaderLocation(m.fixture_shader,"fixtureLinear")
	for &mask,index in m.fixtures.mask {m.fixture_bounds[index]=expedition_fixture_mask_bounds(&mask)}
	return true
}

@(private)
expedition_fixture_mask_bounds :: proc(mask:^[FIXTURE_CELL*FIXTURE_CELL]u8)->rl.Rectangle {
	left,top,right,bottom:=FIXTURE_CELL,FIXTURE_CELL,0,0
	for value,i in mask {if value>0 {
		x,y:=i%FIXTURE_CELL,i/FIXTURE_CELL
		left=min(left,x);top=min(top,y);right=max(right,x+1);bottom=max(bottom,y+1)
	}}
	if right<=left || bottom<=top {return {}}
	return {f32(left),f32(top),f32(right-left),f32(bottom-top)}
}

@(private)
expedition_fixture_overlaps_actor :: proc(renderer:^Renderer,points:[4]rl.Vector3,pixels:rl.Rectangle,width:f32=FIXTURE_CELL,height:f32=FIXTURE_CELL)->bool {
	if pixels.width<=0 || pixels.height<=0 {return false}
	left,top,right,bottom:=max(f32),max(f32),-max(f32),-max(f32)
	for uv in ([4]rl.Vector2{{pixels.x,pixels.y},{pixels.x+pixels.width,pixels.y},
		{pixels.x,pixels.y+pixels.height},{pixels.x+pixels.width,pixels.y+pixels.height}}) {
		p:=points[0]+(points[3]-points[0])*(uv.x/width)+(points[1]-points[0])*(uv.y/height)
		screen:=tactical_project(renderer,{p.x,p.z},p.y)
		left=min(left,screen.x);right=max(right,screen.x);top=min(top,screen.y);bottom=max(bottom,screen.y)
	}
	bounds:=rl.Rectangle{left,top,right-left,bottom-top}
	snapshot:=renderer.tactical.snapshot
	if snapshot==nil {return false}
	if actor,ok:=tactical_actor_screen_bounds(renderer,&snapshot.player);ok && rl.CheckCollisionRecs(bounds,actor) {return true}
	for &enemy in snapshot.enemies[:snapshot.enemy_count] {
		if actor,ok:=tactical_actor_screen_bounds(renderer,&enemy);ok && rl.CheckCollisionRecs(bounds,actor) {return true}
	}
	return false
}

// Matches the authored 60px/unit artwork. Only transparent margins exceed the
// occupied cell; the opaque print is confined to x +/- .5 by the asset tests.
@(private)
expedition_fixture_quad :: proc(right:rl.Vector3,base:rl.Vector3,width:f32=FIXTURE_CELL,height:f32=FIXTURE_CELL,feet:f32=CARTOON_FEET)->[4]rl.Vector3 {
	scale:=f32(1)/CARTOON_PIXELS
	bottom:=base-rl.Vector3{0,(height-feet)*scale,0}
	half:=right*(width*.5*scale);top:=rl.Vector3{0,height*scale,0}
	return {bottom-half+top,bottom-half,bottom+half,bottom+half+top}
}

@(private)
expedition_fixture_hero_on_screen :: proc(renderer:^Renderer,cell:grid.Position,bounds:rl.Rectangle)->bool {
	if bounds.width<=0 || bounds.height<=0 {return true}
	// Enclose the opaque stock, including its eight-pixel margin. Centering
	// x on the occupied cell keeps this conservative at every camera yaw.
	half_x:=max(abs(bounds.x-CYBER_PRESS_WIDTH*.5),abs(bounds.x+bounds.width-CYBER_PRESS_WIDTH*.5))/CARTOON_PIXELS
	half_y:=bounds.height*.5/CARTOON_PIXELS
	center:=.008+(CYBER_PRESS_FEET-bounds.y-bounds.height*.5)/CARTOON_PIXELS
	return tactical_cell_on_screen(renderer,cell,center,math.sqrt(half_x*half_x+half_y*half_y))
}

// `caster`: only the paper's silhouette, with the bound program, for the sun's depth (expedition_sun.odin). The card
// faces the camera as it is drawn, so its shadow is the very cut the player sees.
@(private)
draw_expedition_fixture_sprite :: proc(renderer:^Renderer,w:^world.World,cell:grid.Position,index:int,resolved:bool=false,caster:bool=false) {
	m:=renderer.tactical.expedition_material
	west:=w.biome==.West
	hero:=(w.biome==.Cyber || west) && index==fixture_art_index(w.biome,.Workshop)
	if !m.reflection_pass && !caster {
		on_screen:=expedition_fixture_hero_on_screen(renderer,cell,m.fixtures.west_bounds if west else m.fixtures.hero_bounds) if hero else tactical_cell_on_screen(renderer,cell)
		if !on_screen || !tactical_render_visible(renderer,cell) {return}
	}
	base:=rl.Vector3{f32(cell.x)+.5,cell_ground(cell)+.008,f32(cell.y)+.5}
	right:=flipbook_camera_right(renderer)
	secondary:=(w.biome==.Cyber || west) && index>=FIXTURE_COUNT
	width:=f32(CYBER_PRESS_WIDTH) if hero else FIXTURE_CELL
	height:=f32(CYBER_PRESS_HEIGHT) if hero else FIXTURE_CELL
	feet:=CYBER_PRESS_FEET if hero else CARTOON_FEET
	points:=expedition_fixture_quad(right,base,width,height,feet)
	phase:=f32(expedition_cell_hash(cell,17)%19)*.13
	frame:=0 if resolved else int(math.floor(w.clock*1.4+phase))%FIXTURE_FRAMES
	print_index:=index*FIXTURE_FRAMES+frame
	q:=Tactical_Billboard{points=points,card_points=points,cartoon=true}
	bounds:rl.Rectangle
	if hero {
		press_frame:=0 if resolved else int(math.floor(w.clock*1.3))%CYBER_PRESS_FRAMES
		q.texture=m.fixtures.hero_print;q.card=m.fixtures.hero_paper
		q.source={f32(press_frame*CYBER_PRESS_WIDTH),WEST_WORKSHOP_PRINT_Y if west else 0,width,height}
		q.card_a={CYBER_PRESS_WIDTH if west else 0,0,width,height}
		bounds=m.fixtures.west_bounds if west else m.fixtures.hero_bounds
	} else if secondary {
		role:=clamp(index-FIXTURE_COUNT,0,2)
		q.texture=m.fixtures.hero_print;q.card=m.fixtures.hero_paper
		q.source={f32(role*FIXTURE_CELL),WEST_WORKSHOP_SECONDARY_Y if west else CYBER_PRESS_HEIGHT,FIXTURE_CELL,FIXTURE_CELL}
		q.card_a=west_secondary_paper_source(role) if west else q.source
		bounds=m.fixtures.west_secondary_bounds[role] if west else m.fixtures.secondary_bounds[role]
	} else {
		q.texture=m.fixtures.print;q.card=m.fixtures.paper
		q.source={f32(print_index%FIXTURE_COLUMNS*FIXTURE_CELL),f32(print_index/FIXTURE_COLUMNS*FIXTURE_CELL),FIXTURE_CELL,FIXTURE_CELL}
		q.card_a={f32(index%FIXTURE_COLUMNS*FIXTURE_CELL),f32(index/FIXTURE_COLUMNS*FIXTURE_CELL),FIXTURE_CELL,FIXTURE_CELL}
		bounds=m.fixture_bounds[index]
	}
	if caster {
		if q.card.id==0 {return}
		uv:=[4]rl.Vector2{{0,0},{0,1},{1,1},{1,0}}
		rlgl.SetTexture(q.card.id)
		rlgl.Begin(rlgl.QUADS)
		rlgl.Color4ub(255,255,255,255)
		for point,i in q.card_points {
			rlgl.TexCoord2f((q.card_a.x+uv[i].x*q.card_a.width)/f32(q.card.width),(q.card_a.y+uv[i].y*q.card_a.height)/f32(q.card.height))
			rlgl.Vertex3f(point.x,point.y,point.z)
		}
		rlgl.End()
		rlgl.SetTexture(0)
		return
	}
	faded:=!m.reflection_pass && expedition_occludes(m,{base.x,base.z},.5) && expedition_fixture_overlaps_actor(renderer,points,bounds,width,height)
	if faded {rlgl.DrawRenderBatchActive();rlgl.DisableDepthMask()}
	draw_tactical_billboard_quad(renderer,q,{base.x,base.z},.28 if faded else 1,rl.Color{188,193,181,255} if resolved else rl.WHITE)
	if faded {rlgl.DrawRenderBatchActive();rlgl.EnableDepthMask()}
}

// These ten existing cover cells form input, processing and storage groups.
// The canonical arrangement rotates with the site and is shared by the colour
// and sun passes. No new cell, billboard, atlas slot or simulation role is added.
@(private)
expedition_workshop_art_index :: proc(w:^world.World,q:grid.Position)->int {
	if w.biome==.Cyber {
		if q.x<0 {
			if q.y<0 {return FIXTURE_COUNT+(2 if abs(q.y)==7 else 0)}
			return FIXTURE_COUNT+(1 if q.y==6 else 0)
		}
		if q.x==5 {return FIXTURE_COUNT}
		if q.x==6 {return FIXTURE_COUNT+1}
		if q.x==7 {return FIXTURE_COUNT+(2 if q.y>0 else 0)}
	} else if w.biome==.West {
		if q.x==5 {return FIXTURE_COUNT}
		if q.x==6 {return FIXTURE_COUNT+1}
		if q.x<0 {return FIXTURE_COUNT+(2 if abs(q.y)==7 else 0)}
		if q.x==7 {return FIXTURE_COUNT+2}
	}
	return fixture_machine_art_index(w.biome,q.x<0 || q.x==6)
}

// Gameplay still uses the original Site/Wall cells and E interaction; these
// drawings add no hitbox, actor, selectable object, or navigation state.
@(private)
draw_expedition_fixture_sprites :: proc(renderer:^Renderer,room:^game.Room,w:^world.World) {
	m:=renderer.tactical.expedition_material
	if !ensure_expedition_fixture_sprites(m) {
		// Keep an executable fallback if the GPU rejects an atlas upload.
		pass:=Ink_Pass{mode=.Fill}
		for &site in w.sites[:world.visible_sites(w)] {
			if world.distance(site.position,room.player.position)>30 {continue}
			if site.active && expedition_fixture_is_sprite(site.kind) {
				pass.lift=cell_ground(site.position)
				if w.biome==.Cyber {draw_expedition_cyber_fixture(pass,&site,w.boss_defeated)}
				else {_=draw_expedition_descent_fixture(pass,w,&site) || draw_expedition_dread_fixture(pass,w,&site) || draw_expedition_ascent_fixture(pass,w,&site)}
			}
			cells,count:=expedition_workshop_sprite_cells(&site)
			for cell in cells[:count] {
				tile,ok:=level.tile_at(room.level_data,cell)
				if !ok || (tile.kind!=.Wall && tile.kind!=.Fence) {continue}
				pass.lift=cell_ground(cell);design:=world.site_cell(&site,cell)
				if w.biome==.Cyber {draw_expedition_cyber_wall(pass,room,&site,cell,design)}
				else {_=draw_expedition_descent_wall(pass,room,w,&site,cell,design) || draw_expedition_dread_wall(pass,room,w,&site,cell,design) || draw_expedition_ascent_wall(pass,room,w,&site,cell,design)}
			}
		}
		return
	}
	rlgl.DrawRenderBatchActive();rlgl.DisableBackfaceCulling()
	rl.BeginShaderMode(m.fixture_shader)
	linear:=c.int(1) if m.reflection_pass else 0
	rl.SetShaderValue(m.fixture_shader,m.fixture_linear,&linear,.INT)
	defer {rlgl.DrawRenderBatchActive();rl.EndShaderMode();rlgl.EnableBackfaceCulling()}
	for &site in w.sites[:world.visible_sites(w)] {
		if world.distance(site.position,room.player.position)>30 {continue}
		if site.active && expedition_fixture_is_sprite(site.kind) {
			draw_expedition_fixture_sprite(renderer,w,site.position,fixture_art_index(w.biome,site.kind),site.state==.Resolved)
		}
		// Exactly the same authored-cell predicate that skips a baked solid;
		// bounded fixed storage, and actual tiles rechecked after destruction.
		cells,count:=expedition_workshop_sprite_cells(&site)
		for cell in cells[:count] {
			tile,ok:=level.tile_at(room.level_data,cell)
			if !ok || (tile.kind!=.Wall && tile.kind!=.Fence) {continue}
			q:=world.site_local(&site,cell)
			index:=expedition_workshop_art_index(w,q)
			draw_expedition_fixture_sprite(renderer,w,cell,index)
		}
	}
}

// The paper fixtures near the robot for the sun's depth, with the alpha-tested program bound (expedition_sun.odin):
// the same cells and drawings as draw_expedition_fixture_sprites, silhouettes only.
@(private)
draw_expedition_fixture_casters :: proc(renderer:^Renderer,room:^game.Room,w:^world.World) {
	m:=renderer.tactical.expedition_material
	if !ensure_expedition_fixture_sprites(m) {return}
	for &site in w.sites[:world.visible_sites(w)] {
		if world.distance(site.position,room.player.position)>30 {continue}
		if site.active && expedition_fixture_is_sprite(site.kind) {
			draw_expedition_fixture_sprite(renderer,w,site.position,fixture_art_index(w.biome,site.kind),site.state==.Resolved,caster=true)
		}
		cells,count:=expedition_workshop_sprite_cells(&site)
		for cell in cells[:count] {
			tile,ok:=level.tile_at(room.level_data,cell)
			if !ok || (tile.kind!=.Wall && tile.kind!=.Fence) {continue}
			q:=world.site_local(&site,cell)
			index:=expedition_workshop_art_index(w,q)
			draw_expedition_fixture_sprite(renderer,w,cell,index,caster=true)
		}
	}
}

// Local signals retain one physical source instead of the removed box edges.
// They contribute to HDR lighting, while the authored screen is the visible
// origin on the paper. No decorative global bloom or new simulation clocks.
@(private)
collect_expedition_fixture_sprite_light :: proc(pass:Ink_Pass,w:^world.World,site:^world.Site) {
	if pass.mode!=.Collect || site.state==.Resolved {return}
	if site.kind!=.Workshop && site.kind!=.Archive && site.kind!=.Memory {return}
	if w.biome!=.Cyber {return}
	y:=f32(.36) if site.kind==.Workshop else (1.02 if site.kind==.Archive else 1.05)
	p:=rl.Vector3{f32(site.position.x)+.5,y,f32(site.position.y)+.5}
	c:=world.metadata(w.biome).color
	ink_line(pass,p+{-.06,0,0},p+{.06,0,0},{c[0],c[1],c[2],EXPEDITION_EDGE_ALPHA})
}
