package render

import "core:c"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import world "../expedition"
import game "../game"
import grid "../engine/grid"
import level "../level"

// Ink solids keep their biome silhouettes; outward face normals let the HDR
// material light each fold. Neon edges are batched analytic ribbons instead
// of driver-dependent GL lines and retain their shape over a revealed actor.
Ink_Mode :: enum u8 { Fill, Edge, Collect, Bake }
// `lift` raises everything the pass draws (the height of the ground it stands on).
Ink_Pass :: struct { mode:Ink_Mode, edges:^Expedition_Edges, builder:^Expedition_Geometry_Builder, lift:f32 }

EXPEDITION_INK :: rl.Color{22,26,38,255}
EXPEDITION_INK_TOP :: rl.Color{18,21,31,255}
// Faces turned to the left of the fixed camera catch the light.
@(private="file")
INK_LIGHT :: rl.Vector2{-.7071,.7071}

@(private)
ink_edge :: proc(color:rl.Color,strength:f32=1)->rl.Color {
	return {u8(min(f32(255),f32(color.r)*strength)),u8(min(f32(255),f32(color.g)*strength)),u8(min(f32(255),f32(color.b)*strength)),EXPEDITION_EDGE_ALPHA}
}

@(private)
ink_scale :: proc(color:rl.Color,k:f32)->rl.Color {
	return {u8(clamp(f32(color.r)*k,0,255)),u8(clamp(f32(color.g)*k,0,255)),u8(clamp(f32(color.b)*k,0,255)),color.a}
}

@(private="file")
ink_vertex :: proc(p:rl.Vector3) {rlgl.Vertex3f(p.x,p.y,p.z)}

@(private)
ink_face_normal :: proc(a,b,c:rl.Vector3)->rl.Vector3 {return rl.Vector3Normalize(rl.Vector3CrossProduct(b-a,c-a))}

@(private="file")
ink_triangle :: proc(pass:Ink_Pass,a,b,c:rl.Vector3,color:rl.Color) {
	n:=ink_face_normal(a,b,c);up:=rl.Vector3{0,pass.lift,0}
	if pass.mode==.Bake {
		for p in ([3]rl.Vector3{a,b,c}) {append(&pass.builder.vertices,Expedition_Baked_Vertex{p+up,n,color})}
		return
	}
	rlgl.Normal3f(n.x,n.y,n.z)
	ink_vertex(a+up);ink_vertex(b+up);ink_vertex(c+up)
}

// A convex solid between a bottom ring and a top ring (an apex when `apex`).
// `shade` tints the side faces by their facing, for the bright canopies.
@(private)
ink_solid :: proc(pass:Ink_Pass,bottom,top:[]rl.Vector3,fill,cap,edge:rl.Color,apex:bool=false,shade:f32=0,bottom_edges:bool=true) {
	n:=len(bottom);if n<3 || len(top)!=n {return}
	if pass.mode==.Fill || pass.mode==.Bake {
		center:rl.Vector3;for p in bottom {center+=p};center/=f32(n)
		if pass.mode==.Fill {_=rlgl.CheckRenderBatchLimit(c.int(n*6+n*3));rlgl.Begin(rlgl.TRIANGLES)}
		for i in 0..<n {
			j:=(i+1)%n;color:=fill
			if shade!=0 {
				out:=(bottom[i]+bottom[j])*.5-center;l:=math.sqrt(out.x*out.x+out.z*out.z)
				if l>.0001 {color=ink_scale(fill,1+shade*(out.x*INK_LIGHT.x+out.z*INK_LIGHT.y)/l)}
			}
			if pass.mode==.Fill {rlgl.Color4ub(color.r,color.g,color.b,color.a)}
			ink_triangle(pass,bottom[i],top[j],bottom[j],color)
			if !apex {ink_triangle(pass,bottom[i],top[i],top[j],color)}
		}
		if !apex {
			if pass.mode==.Fill {rlgl.Color4ub(cap.r,cap.g,cap.b,cap.a)}
			for i in 1..<n-1 {ink_triangle(pass,top[0],top[i+1],top[i],cap)}
		}
		if pass.mode==.Fill {rlgl.End();return}
	}
	for i in 0..<n {
		j:=(i+1)%n
		if bottom_edges {ink_line(pass,bottom[i],bottom[j],edge)}
		if !apex {ink_line(pass,top[i],top[j],edge)}
		ink_line(pass,bottom[i],top[i],edge)
	}
}

// A ring of `sides` points; `lean` shears the top like a tilted grave cross.
@(private)
ink_frustum :: proc(pass:Ink_Pass,base:rl.Vector3,r0,r1,height:f32,sides:int,phase:f32,fill,cap,edge:rl.Color,shade:f32=0,lean:rl.Vector2={}) {
	bottom,top:[12]rl.Vector3;n:=clamp(sides,3,12)
	for i in 0..<n {
		a:=phase+f32(i)*math.TAU/f32(n);d:=rl.Vector3{math.cos(a),0,math.sin(a)}
		bottom[i]=base+d*r0;top[i]=base+d*r1+{lean.x*height,height,lean.y*height}
	}
	ink_solid(pass,bottom[:n],top[:n],fill,cap,edge,r1<=0,shade)
}

// A box of half extents `half` (x, z), turned by `yaw`.
@(private)
ink_box :: proc(pass:Ink_Pass,base:rl.Vector3,half:rl.Vector2,height,yaw:f32,fill,cap,edge:rl.Color,lean:rl.Vector2={}) {
	bottom,top:[4]rl.Vector3;cs,sn:=math.cos(yaw),math.sin(yaw)
	corners:=[4]rl.Vector2{{-half.x,-half.y},{half.x,-half.y},{half.x,half.y},{-half.x,half.y}}
	for o,i in corners {
		bottom[i]=base+{o.x*cs-o.y*sn,0,o.x*sn+o.y*cs}
		top[i]=bottom[i]+{lean.x*height,height,lean.y*height}
	}
	ink_solid(pass,bottom[:],top[:],fill,cap,edge)
}

@(private)
ink_line :: proc(pass:Ink_Pass,from,to:rl.Vector3,color:rl.Color) {
	if pass.mode==.Fill || color.a==0 {return}
	a,b:=from+rl.Vector3{0,pass.lift,0},to+rl.Vector3{0,pass.lift,0}
	if pass.mode==.Bake {append(&pass.builder.lines,Expedition_Baked_Line{a,b,color});return}
	if pass.mode==.Collect {expedition_collect_edge(pass.edges,a,b,color);return}
	draw_expedition_ribbon(pass.edges,a,b,color)
}

@(private)
expedition_cell_hash :: proc(cell:grid.Position,salt:u32=0)->u32 {
	h:=u32(cell.x)*0x8da6b343 ~ u32(cell.y)*0xd8163841 ~ salt*0x9e3779b9
	h~=h>>15;h*=0x2c1b3c6d;h~=h>>12;h*=0x297a2d39;h~=h>>15
	return h
}

// Open-ground cover keeps each biome's own silhouette: monoliths, mesas,
// pyramids, trees, peaks, crosses and city blocks.
@(private)
draw_expedition_outdoor_prop :: proc(pass:Ink_Pass,w:^world.World,cell:grid.Position) {
	if w.biome==.Cyber {draw_expedition_cyber_outdoor(pass,cell);return}
	if draw_expedition_descent_outdoor(pass,w,cell) || draw_expedition_dread_outdoor(pass,w,cell) || draw_expedition_ascent_outdoor(pass,w,cell) {return}
	p:=rl.Vector3{f32(cell.x)+.5,0,f32(cell.y)+.5};c:=expedition_color(w.biome)
	h:=expedition_cell_hash(cell,u32(w.biome))
	edge:=ink_edge(c)
	#partial switch w.biome {
	case .Jungle,.Vietnam:
		height:=f32(1.5)+f32((h>>4)%3)*.2
		trunk:=rl.Color{17,24,21,255}
		ink_frustum(pass,p,.1,.07,height,5,f32(h%7),trunk,trunk,ink_edge(trunk))
		leaf:=ink_scale(c,.68)
		ink_frustum(pass,p+{0,height*.42,0},.62,0,.82,5,f32(h%11)*.6,leaf,leaf,ink_edge(leaf,.78),.18)
	case .Egypt:
		ink_frustum(pass,p,.7,0,1.3+f32((h>>4)%4)*.22,4,math.PI/4,EXPEDITION_INK,EXPEDITION_INK,edge)
	case .Snow:
		ink_frustum(pass,p,.44,0,2+f32((h>>4)%5)*.25,4,math.PI/4+f32(h%5)*.08,EXPEDITION_INK,EXPEDITION_INK,edge)
	case .Inferno:
		ink_frustum(pass,p,.56,0,1.25+f32((h>>4)%4)*.25,4,math.PI/4+f32(h%5)*.1,EXPEDITION_INK,EXPEDITION_INK,edge)
	case .Space:
		ink_frustum(pass,p,.46,0,1.4+f32((h>>4)%5)*.3,4,f32(h%13)*.24,EXPEDITION_INK,EXPEDITION_INK,edge)
	case .Gothic:
		// Crooked grave crosses: a dark post and a pale lit crossbar.
		height:=f32(1.6)+f32((h>>4)%3)*.2
		lean:=rl.Vector2{(f32(h%9)-4)*.04,(f32((h>>8)%9)-4)*.04}
		yaw:=f32(0) if (h>>12)%2==0 else math.PI/2
		post:=rl.Color{28,24,28,255}
		ink_box(pass,p,{.085,.085},height,yaw,post,post,ink_edge(post),lean)
		bar:=height*.7
		ink_box(pass,p+{lean.x*bar,bar,lean.y*bar},{.33,.065},.12,yaw+(f32(h%5)-2)*.06,ink_scale(c,.95),ink_scale(c,.8),ink_edge(c))
	case .City:
		ink_box(pass,p,{.48,.48},1+f32((h>>4)%5)*.42,0,EXPEDITION_INK,EXPEDITION_INK_TOP,edge)
	case:
		half:=.28+f32(h%4)*.03
		ink_box(pass,p,{half,half},1.3+f32((h>>4)%8)*.24,0,EXPEDITION_INK,EXPEDITION_INK_TOP,edge)
	}
}

// Only walls of the same courtyard and height share an outline. Asking that
// one site keeps the edge pass from scanning every site for every neighbour.
@(private)
expedition_wall_joined :: proc(room:^game.Room,site:^world.Site,cell:grid.Position,height:f32)->bool {
	tile,ok:=level.tile_at(room.level_data,cell)
	if !ok || tile.kind!=.Wall {return false}
	design:=world.site_cell(site,cell)
	if !design.inside || (design.fixture && site.active) {return false}
	return abs(expedition_site_wall_height(design)-height)<.01
}

@(private)
expedition_site_wall_height :: proc(design:world.Site_Cell)->f32 {return design.wall_height*.72}

// Courtyard walls read as continuous masonry: joined cells share one
// outline, folds keep their edge, and the biome's neon runs along the caps.
@(private)
draw_expedition_site_wall :: proc(pass:Ink_Pass,room:^game.Room,w:^world.World,site:^world.Site,cell:grid.Position,design:world.Site_Cell) {
	if w.biome==.Cyber {draw_expedition_cyber_wall(pass,room,site,cell,design);return}
	if draw_expedition_descent_wall(pass,room,w,site,cell,design) || draw_expedition_dread_wall(pass,room,w,site,cell,design) || draw_expedition_ascent_wall(pass,room,w,site,cell,design) {return}
	p:=rl.Vector3{f32(cell.x)+.5,0,f32(cell.y)+.5};c:=expedition_color(w.biome)
	height:=expedition_site_wall_height(design)
	if pass.mode==.Fill || pass.mode==.Bake {
		ink_box(pass,p,{.5,.5},height,0,EXPEDITION_INK,EXPEDITION_INK_TOP,{})
		if pass.mode==.Fill {return}
	}
	edge:=ink_edge(c)
	sides:=[4]grid.Position{{1,0},{0,1},{-1,0},{0,-1}}
	joined:[4]bool
	for d,i in sides {joined[i]=expedition_wall_joined(room,site,game.add_position(cell,d),height)}
	for d,i in sides {
		if joined[i] {continue}
		// The face toward an open neighbour: its cap and its foot.
		t:=rl.Vector3{f32(d.y),0,-f32(d.x)}*.5;o:=rl.Vector3{f32(d.x),0,f32(d.y)}*.5
		ink_line(pass,p+o-t+{0,height,0},p+o+t+{0,height,0},edge)
		ink_line(pass,p+o-t,p+o+t,ink_edge(c,.55))
	}
	for corner in ([4]grid.Position{{1,1},{-1,1},{-1,-1},{1,-1}}) {
		x:=joined[0] if corner.x>0 else joined[2]
		z:=joined[1] if corner.y>0 else joined[3]
		d:=expedition_wall_joined(room,site,game.add_position(cell,corner),height)
		// Straight runs and fully enclosed corners hide the seam; convex
		// corners and inner folds keep it.
		if (x!=z && !d) || (x && z && d) {continue}
		// A fold is shared by up to three cells: the first in row order draws it.
		vertex:=grid.Position{cell.x+(1 if corner.x>0 else 0),cell.y+(1 if corner.y>0 else 0)}
		owner:=cell
		for o in ([4]grid.Position{{-1,-1},{0,-1},{-1,0},{0,0}}) {
			q:=game.add_position(vertex,o)
			if q==cell || expedition_wall_joined(room,site,q,height) {owner=q;break}
		}
		if owner!=cell {continue}
		q:=p+rl.Vector3{f32(corner.x),0,f32(corner.y)}*.5
		ink_line(pass,q,q+{0,height,0},edge)
	}
}

// Solids standing in front of a revealed actor go through the reveal
// program; every other solid, and every edge, through the plain ink one.
Ink_Layer :: enum u8 { Solid, Revealed, Edges }

@(private="file")
ink_layer_skips :: proc(layer:Ink_Layer,m:^Expedition_Material,center:rl.Vector2,half_width:f32=.5)->bool {
	if m!=nil && m.reflection_pass {return layer==.Revealed}
	return layer!=.Edges && expedition_occludes(m,center,half_width)!=(layer==.Revealed)
}

// CPU-only prepass. The lighting program receives actual geometry segments
// from this frame before any solid is shaded, with no simulation/RNG reads.
@(private)
collect_expedition_edges :: proc(renderer:^Renderer,room:^game.Room,w:^world.World) {
	m:=renderer.tactical.expedition_material;if m==nil {return}
	e:=&m.edges;e.emitter_count=0;e.light_focus=renderer.tactical.camera.target
	e.emission=3 if w.biome==.Cyber || w.biome==.West || w.biome==.Egypt else EXPEDITION_EDGE_EMISSION
	pass:=Ink_Pass{mode=.Collect,edges=e};p:=room.player.position
	if prepare_expedition_geometry(renderer,room,w) {
		collect_expedition_cached_edges(renderer,room,w)
		draw_expedition_site_architecture(.Edges,renderer,room,w,true,true)
		return
	}
	// draw_tactical_world gathers the wider floor/site cache before this pass.
	for y in max(0,p.y-26)..<min(room.level_data.tiles.height,p.y+27) {
		for x in max(0,p.x-26)..<min(room.level_data.tiles.width,p.x+27) {
			cell:=grid.Position{x,y};tile,_:=level.tile_at(room.level_data,cell);if tile.kind!=.Wall && tile.kind!=.Fence {continue}
			ground:=pass;ground.lift=cell_ground(cell)
			if draw_expedition_structure_solid(ground,room,w,cell,tile.kind) {continue}
			site_index,design:=expedition_site_near(renderer,w,cell)
			if design.fixture && site_index>=0 && w.sites[site_index].active {continue}
			if design.inside {draw_expedition_site_wall(ground,room,w,&w.sites[site_index],cell,design)}
			else {draw_expedition_outdoor_prop(ground,w,cell)}
		}
	}
	draw_expedition_site_architecture(.Edges,renderer,room,w,true)
}

@(private)
draw_expedition_architecture :: proc(renderer:^Renderer,room:^game.Room,w:^world.World) {
	if draw_expedition_cached_architecture(renderer,room,w) {return}
	p:=room.player.position;m:=renderer.tactical.expedition_material
	rlgl.DrawRenderBatchActive();rlgl.DisableBackfaceCulling()
	defer {rlgl.DrawRenderBatchActive();rlgl.EnableBackfaceCulling()}
	for layer in Ink_Layer {
		if layer==.Revealed && (m==nil || m.reveal_point_count==0 || m.reflection_pass) {continue}
		if layer==.Edges {begin_expedition_edges(renderer)}
		else {begin_expedition_material(renderer,w,reveal=layer==.Revealed)}
		pass:=Ink_Pass{mode=.Edge if layer==.Edges else .Fill,edges=&m.edges if m!=nil else nil}
		for y in max(0,p.y-26)..<min(room.level_data.tiles.height,p.y+27) {
			for x in max(0,p.x-26)..<min(room.level_data.tiles.width,p.x+27) {
				cell:=grid.Position{x,y};tile,_:=level.tile_at(room.level_data,cell)
				if (tile.kind!=.Wall && tile.kind!=.Fence) || ((m==nil || !m.reflection_pass) && !tactical_cell_on_screen(renderer,cell)) {continue}
				if ink_layer_skips(layer,m,{f32(x)+.5,f32(y)+.5}) {continue}
				ground:=pass;ground.lift=cell_ground(cell)
				if draw_expedition_structure_solid(ground,room,w,cell,tile.kind) {continue}
				site_index,design:=expedition_site_near(renderer,w,cell)
				// Active fixtures own a bespoke prop below; dormant ruins remain visible cover.
				if design.fixture && site_index>=0 && w.sites[site_index].active {continue}
				if design.inside {draw_expedition_site_wall(ground,room,w,&w.sites[site_index],cell,design)}
				else {draw_expedition_outdoor_prop(ground,w,cell)}
			}
		}
		draw_expedition_site_architecture(layer,renderer,room,w)
		if layer==.Edges {end_expedition_edges(renderer)}
		else {rlgl.DrawRenderBatchActive();rl.EndShaderMode()}
	}
	draw_expedition_structure_envelopes(renderer,room,w)
}

// One immutable site mesh contains its gates and authored fixture. The same
// dispatch serves the immediate fallback and the CPU-only bake pass.
@(private)
draw_expedition_site_static :: proc(pass_in:Ink_Pass,w:^world.World,site:^world.Site,layer:Ink_Layer=.Edges,m:^Expedition_Material=nil) {
	pass:=pass_in;pass.lift=cell_ground(site.position)
	decor:=world.site_decor_anchors(site)
	for i:=0;i+1<decor.count;i+=2 {
		a,b:=decor.items[i],decor.items[i+1]
		if a.kind!=.Gatepost || b.kind!=.Gatepost {break}
		top:=.85*a.height
		pa:=rl.Vector3{f32(a.position.x)+.5,top,f32(a.position.y)+.5}
		pb:=rl.Vector3{f32(b.position.x)+.5,top,f32(b.position.y)+.5}
		mid:=(pa+pb)*.5;span:=rl.Vector2{abs(pa.x-pb.x)*.5+.45,abs(pa.z-pb.z)*.5+.45}
		if ink_layer_skips(layer,m,{mid.x,mid.z},max(span.x,span.y)) {continue}
		if w.biome==.Cyber {draw_expedition_cyber_gate(pass,pa,pb);continue}
		if draw_expedition_descent_gate(pass,w,pa,pb) || draw_expedition_dread_gate(pass,w,pa,pb) || draw_expedition_ascent_gate(pass,w,pa,pb) {continue}
	}
	p:=rl.Vector2{f32(site.position.x)+.5,f32(site.position.y)+.5}
	if ink_layer_skips(layer,m,p,2.3 if site.kind==.Boss else .5) {return}
	if w.biome==.Cyber {draw_expedition_cyber_fixture(pass,site,w.boss_defeated);return}
	if draw_expedition_descent_fixture(pass,w,site) || draw_expedition_dread_fixture(pass,w,site) || draw_expedition_ascent_fixture(pass,w,site) {return}
}

// Animation is never stored in a mesh. The exit continues to move even when
// every architectural solid is reused unchanged by both camera passes.
@(private)
draw_expedition_site_dynamic :: proc(pass_in:Ink_Pass,w:^world.World,site:^world.Site) {
	pass:=pass_in;pass.lift=cell_ground(site.position)
	if pass.mode==.Fill || site.kind!=.Boss || !w.boss_defeated {return}
	p:=rl.Vector3{f32(site.position.x)+.5,0,f32(site.position.y)+.5}
	phase:=w.clock*24*math.PI/180;cs,sn:=math.cos(phase),math.sin(phase)
	for i in 0..<48 {
		a,z:=f32(i)*math.TAU/48,f32(i+1)*math.TAU/48
		from:=p+rl.Vector3{math.sin(a)*cs*1.3,1.6+math.cos(a)*1.3,-math.sin(a)*sn*1.3}
		to:=p+rl.Vector3{math.sin(z)*cs*1.3,1.6+math.cos(z)*1.3,-math.sin(z)*sn*1.3}
		ink_line(pass,from,to,{133,255,203,EXPEDITION_EDGE_ALPHA})
	}
}

@(private)
draw_expedition_site_architecture :: proc(layer:Ink_Layer,renderer:^Renderer,room:^game.Room,w:^world.World,collect:bool=false,dynamic_only:bool=false) {
	m:=renderer.tactical.expedition_material
	pass:=Ink_Pass{mode=.Edge if layer==.Edges else .Fill,edges=&m.edges if m!=nil else nil}
	if collect {pass.mode=.Collect}
	for &site in w.sites[:w.site_count] {
		if !site.active || world.distance(site.position,room.player.position)>30 {continue}
		if !dynamic_only {draw_expedition_site_static(pass,w,&site,layer,m)}
		draw_expedition_site_dynamic(pass,w,&site)
	}
}
