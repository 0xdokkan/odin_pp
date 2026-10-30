package run

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import canvas_target "../engine/canvas"
import rlgl "vendor:raylib/rlgl"
import campaign "../campaign"
import world "../expedition"
import host "../engine/host"
import ui "../engine/ui"
import level "../level"
import grid "../engine/grid"
import render "../render"

// The miniature reads only terrain and public site knowledge. Neither enemy
// locations nor encounter RNG enter this presentation. Row merging preserves
// every wall, entrance and void cell while avoiding one cube per map tile.
HOLO_SIDE :: 256
// `height`: the cell's height band (hologram_band), which the map shows as shading and as contour lines; a pit dug under
// a raised map's base is below zero.
Hologram_Cell :: struct { ground, wall: u8, height: i16 }

// The heights up to HOLO_FLAT_STEPS are shown as they are; above them (the spiral mountain of the Snow is
// ninety-odd steps) six steps are one band, so that the map's relief stays in proportion and has a few
// contour lines, not ninety.
HOLO_FLAT_STEPS :: 12
HOLO_BAND_STEPS :: 6
hologram_band :: proc(steps:i32)->i16 {
	if steps<=HOLO_FLAT_STEPS {return i16(max(steps,-4*HOLO_FLAT_STEPS))}
	return i16(min(i32(255),HOLO_FLAT_STEPS+(steps-HOLO_FLAT_STEPS)/HOLO_BAND_STEPS))
}
// One plate of the stacked map: one layer of the map (Fase 8 of docs/piano-profondita.md).
Hologram_Geometry :: struct {
	width, height: int,
	// Whether the layer has a cell; the lowest band of its cells, which every prism of it reaches down under; the height
	// that is band 0 (the ground's: the map's base; another plate's: its lowest floor).
	present: bool,
	lowest: i16,
	reference: i32,
	cells: [HOLO_SIDE*HOLO_SIDE]Hologram_Cell,
}

// THE STACKED MAP (Fase 8 of docs/piano-profondita.md, the user's choice): every layer of the map that has a cell is a
// plate, one over the other in the layers' order, HOLO_PLATE_GAP of the map's side apart: the bridges over the ground,
// the open ground, the caves and the complexes' tunnels under it, the networks under those. One plate is shown whole, the
// one the robot is on when the map opens, and W and S (or the arrows) change it; the others are only their shapes, faint.
// All of the structure is drawn; of what is in it, only what the robot has been to (the caves' mouths found, the
// complexes and the networks' halls visited).
HOLO_PLATE_GAP :: .22
HOLO_PLATE_NAMES :: [level.LAYER_COUNT]string{"PROFONDO: RETI SOTTO TERRA","SOTTO: GROTTE E GALLERIE","TERRA: RILIEVO COMPLETO","SOPRA: PONTI E PASSERELLE"}

// Which of the map's layers have a cell: the plates of the stacked map. The ground always.
hologram_plates :: proc(data:^level.Level)->(present:[level.LAYER_COUNT]bool) {
	for layer in grid.LOWEST_LAYER..=grid.HIGHEST_LAYER {
		slot:=level.layer_slot(i8(layer))
		if layer==grid.GROUND_LAYER {present[slot]=true;continue}
		for tile in data.planes[slot].tiles {if level.kind_has_floor(tile.kind) || tile.kind==.Fence {present[slot]=true;break}}
	}
	return
}

// The plate next to `layer` in direction `step` (1 up, -1 down) that has a cell; `layer` if there is none that way.
hologram_next_plate :: proc(data:^level.Level,layer:i8,step:int)->i8 {
	present:=hologram_plates(data)
	for next:=int(layer)+step;next>=grid.LOWEST_LAYER && next<=grid.HIGHEST_LAYER;next+=step {
		if present[level.layer_slot(i8(next))] {return i8(next)}
	}
	return layer
}
Hologram_Area :: struct { visible:bool, center:rl.Vector3, radius:f32 }
HOLO_CODES :: [world.Site_Kind]string{.Nest="N",.Cache="C",.Archive="A",.Workshop="O",.Spring="F",.Trial="P",.Boss="B",.Memory="M",.Tunnel="T",.Cave="G"}

@(private)
hologram_area :: proc(site:^world.Site)->Hologram_Area {
	if !site.active || (site.secret && site.state==.Unvisited) {return {}}
	// Knowledge changes the signal, never turns a search area into a precise
	// POI pin. Half-cell gameplay centers cannot equal this coarse grid center.
	p:=site.position
	return {true,{f32(p.x/16*16+8),.8,f32(p.y/16*16+8)},13}
}

@(private)
hologram_camera :: proc(width,height:int)->rl.Camera3D {
	s:=f32(max(width,height));fovy:=s*1.46
	// Shift the optical center to the left map panel; the right is a fixed key.
	shift:=rl.Vector3{.7071068,0,-.7071068}*((480-346)*fovy/540)+rl.Vector3{-.394, .830, -.394}*(20*fovy/540)
	center:=rl.Vector3{f32(width)*.5,0,f32(height)*.5}+shift
	return {position=center+{s*.82,s*.78,s*.82},target=center,up={0,1,0},fovy=fovy,projection=.ORTHOGRAPHIC}
}

// The open ground's plate: its relief, its walls and the sites' courtyards. Heights count from the map's base
// (level.Level.base), as the board draws them; a pit dug under the base is below zero. The caves' rooms are the plate
// under it (hologram_plate).
@(private)
hologram_geometry :: proc(w:^world.World,data:^level.Level,out:^Hologram_Geometry) {
	out.width=min(data.tiles.width,HOLO_SIDE);out.height=min(data.tiles.height,HOLO_SIDE)
	out.present,out.lowest,out.reference=true,0,data.base
	for y:=0;y<out.height;y+=2 {for x:=0;x<out.width;x+=2 {
		ground:=u8(1)
		#partial switch world.terrain(w.biome,{x = x, y = y}) {
		case .Grass:ground=2
		case .Water,.Swamp:ground=3
		case .Ice,.Snow:ground=4
		case .Sand:ground=5
		case .Lava,.Electric:ground=6
		case .Bridge:ground=7
		case .Gravity:ground=8
		}
		for dy in 0..<min(2,out.height-y) {for dx in 0..<min(2,out.width-x) {
			px,py:=x+dx,y+dy;tile:=data.tiles.cells[py*data.tiles.width+px]
			c:=&out.cells[py*HOLO_SIDE+px];c^={}
			if tile.kind==.Void {continue}
			c.ground=ground;c.height=hologram_band(level.height_at(data,{x = px, y = py})-data.base)
			out.lowest=min(out.lowest,c.height)
			if w.biome==.Inferno && tile.kind==.Door {c.ground=6}
			// Scattered open-ground props stay low stubs: the courtyards, the
			// city blocks and the pyramid fields remain the landmarks.
			if tile.kind==.Wall {c.wall=6+u8((px/2+py/2)%3) if w.biome==.City || w.biome==.Egypt else 2+u8((px+py)%2)}
			if px==0 || py==0 || px==out.width-1 || py==out.height-1 {c.wall=min(c.wall,2)}
		}}
	}}
	for &site in w.sites[:w.site_count] {
		if site.layout_version!=world.SITE_LAYOUT_VERSION {continue}
		minimum,maximum:=world.site_bounds(&site)
		for y in max(0,minimum.y)..=min(out.height-1,maximum.y) {for x in max(0,minimum.x)..=min(out.width-1,maximum.x) {
			c:=&out.cells[y*HOLO_SIDE+x];if c.ground==0 {continue}
			design:=world.site_cell(&site,{x = x, y = y});if !design.inside {continue}
			c.ground=9
			#partial switch design.surface {
			case .Platform,.Threshold:c.ground=10
			case .Garden,.Pool:c.ground=11
			case .Arena:c.ground=12
			case .Ruin:c.ground=13
			case .Passage,.Approach:c.ground=14
			}
			if c.wall>0 {c.wall=u8(clamp(design.wall_height*3.2,3,12))}
		}}
	}
}

// One of the plates over or under the ground (Fase 8): the cells of `layer` one walks on, and its shut gates as low walls;
// heights count from its lowest floor. A cave's room, a complex's tunnel, a network and a bridge each have a colour.
@(private)
hologram_plate :: proc(w:^world.World,data:^level.Level,layer:i8,out:^Hologram_Geometry) {
	out.width=min(data.tiles.width,HOLO_SIDE);out.height=min(data.tiles.height,HOLO_SIDE)
	out.present,out.lowest,out.reference=false,0,0
	plane:=&data.planes[level.layer_slot(layer)]
	walked :: proc(kind:level.Tile_Kind)->bool {return level.kind_has_floor(kind) || kind==.Fence}
	// A plane keeps its heights only once one is not zero (level.set_height): ask the level.
	floor:=i32(max(i32))
	for y in 0..<out.height {for x in 0..<out.width {
		at:=y*data.tiles.width+x
		if at<len(plane.tiles) && walked(plane.tiles[at].kind) {floor=min(floor,level.height_at(data,{x = x, y = y, layer = layer}))}
	}}
	out.reference=floor
	for y in 0..<out.height {for x in 0..<out.width {
		c:=&out.cells[y*HOLO_SIDE+x];c^={}
		at:=y*data.tiles.width+x
		if at>=len(plane.tiles) || !walked(plane.tiles[at].kind) {continue}
		out.present=true
		c.height=hologram_band(level.height_at(data,{x = x, y = y, layer = layer})-floor)
		c.ground=19 if layer>grid.GROUND_LAYER else (18 if layer==world.NETWORK_LAYER else 15)
		if layer==world.COMPLEX_TUNNEL {if index,_:=world.complex_at(w,{x = x, y = y});index>0 {c.ground=17}}
		if plane.tiles[at].kind==.Fence {c.wall=3}
	}}
}

// A vertex of the map's drawing.
@(private)
Hologram_Vertex :: struct { position: rl.Vector3, color: rl.Color }

// THE MAP KEPT BETWEEN FRAMES (Fase 8, «prestazioni al massimo»): the plates are built once for a map, and their drawing
// (the plate shown whole, the faint tops of the others) goes to the video card once for the plate shown. Every frame
// draws only what is little or moves: the plate's base and the frames, the lines (a mesh cannot draw lines: they are
// sent from the list kept here), the search areas, the pins and the robot. Built again when the map's geometry or the
// world changes, and what is on the card when W or S shows another plate.
Hologram_Cache :: struct {
	ready: bool,
	geometry_id, revision, seed: u64,
	biome: campaign.Biome,
	present: [level.LAYER_COUNT]bool,
	plates: ^[level.LAYER_COUNT]Hologram_Geometry,
	// What is drawn for the plate `focus` shown: by plate, its triangles on the card (`meshes`), or, if the card did not
	// take them, the list sent vertex by vertex; and the lines of the plate shown.
	drawn: bool,
	focus: i8,
	tint: rl.Color,
	meshes: [level.LAYER_COUNT]rl.Mesh,
	triangles: [level.LAYER_COUNT][dynamic]Hologram_Vertex,
	lines: [dynamic]Hologram_Vertex,
}

@(private)
hologram_quad :: proc(out:^[dynamic]Hologram_Vertex,a,b,c,d:rl.Vector3,color:rl.Color) {
	for p in ([6]rl.Vector3{a,b,c,a,c,d}) {append(out,Hologram_Vertex{p,color})}
}

@(private)
hologram_prism :: proc(out:^[dynamic]Hologram_Vertex,x,z,width,depth,bottom,top:f32,c:rl.Color) {
	// The fixed overview camera sees the top, east and south. Explicit face
	// colors give the entire map a softly lit relief without shader ownership.
	a,b:=rl.Vector3{x,top,z},rl.Vector3{x+width,top,z}
	c0,d:=rl.Vector3{x+width,top,z+depth},rl.Vector3{x,top,z+depth}
	hologram_quad(out,a,d,c0,b,c)
	hologram_quad(out,d,{x,bottom,z+depth},{x+width,bottom,z+depth},c0,{u8(f32(c.r)*.43),u8(f32(c.g)*.51),u8(f32(c.b)*.65),c.a})
	hologram_quad(out,c0,{x+width,bottom,z+depth},{x+width,bottom,z},b,{u8(f32(c.r)*.64),u8(f32(c.g)*.74),u8(f32(c.b)*.83),c.a})
}

@(private)
hologram_line :: proc(out:^[dynamic]Hologram_Vertex,a,b:rl.Vector3,color:rl.Color) {append(out,Hologram_Vertex{a,color},Hologram_Vertex{b,color})}

// Sends vertices one by one, as rlgl.TRIANGLES or rlgl.LINES: the lines every frame, and the triangles the card did not take.
@(private)
hologram_send :: proc(vertices:[]Hologram_Vertex,mode:i32) {
	if len(vertices)==0 {return}
	rlgl.Begin(mode)
	for v in vertices {rlgl.Color4ub(v.color.r,v.color.g,v.color.b,v.color.a);rlgl.Vertex3f(v.position.x,v.position.y,v.position.z)}
	rlgl.End()
}

// Puts a plate's triangles on the video card; false if it does not take them (they are then sent every frame).
@(private)
hologram_upload :: proc(vertices:[]Hologram_Vertex,mesh:^rl.Mesh)->bool {
	n:=len(vertices)
	if n==0 {return false}
	mesh.vertexCount,mesh.triangleCount=i32(n),i32(n/3)
	mesh.vertices=cast([^]f32)rl.MemAlloc(u32(n*3*size_of(f32)))
	// Zeroed by MemAlloc: the default shader reads its one white pixel.
	mesh.texcoords=cast([^]f32)rl.MemAlloc(u32(n*2*size_of(f32)))
	mesh.colors=cast([^]u8)rl.MemAlloc(u32(n*4))
	if mesh.vertices==nil || mesh.texcoords==nil || mesh.colors==nil {rl.UnloadMesh(mesh^);mesh^={};return false}
	for v,i in vertices {
		mesh.vertices[i*3],mesh.vertices[i*3+1],mesh.vertices[i*3+2]=v.position.x,v.position.y,v.position.z
		mesh.colors[i*4],mesh.colors[i*4+1],mesh.colors[i*4+2],mesh.colors[i*4+3]=v.color.r,v.color.g,v.color.b,v.color.a
	}
	rl.UploadMesh(mesh,false)
	if mesh.vboId==nil || mesh.vboId[0]==0 {rl.UnloadMesh(mesh^);mesh^={};return false}
	// The card has them: the copies here are not needed any more.
	rl.MemFree(mesh.vertices);rl.MemFree(mesh.texcoords);rl.MemFree(mesh.colors)
	mesh.vertices,mesh.texcoords,mesh.colors=nil,nil,nil
	return true
}

// A plate's triangles, from the card with the default shader (the same one the vertices sent one by one are drawn
// with), or one by one if the card did not take them. What was sent before is drawn first, to keep the order.
@(private)
draw_hologram_triangles :: proc(cache:^Hologram_Cache,slot:int) {
	if cache.meshes[slot].vaoId==0 {hologram_send(cache.triangles[slot][:],rlgl.TRIANGLES);return}
	rlgl.DrawRenderBatchActive()
	maps:[rl.MAX_MATERIAL_MAPS]rl.MaterialMap
	maps[rl.MaterialMapIndex.ALBEDO].texture.id=rlgl.GetTextureIdDefault()
	maps[rl.MaterialMapIndex.ALBEDO].color=rl.WHITE
	rl.DrawMesh(cache.meshes[slot],{shader={id=rlgl.GetShaderIdDefault(),locs=rlgl.GetShaderLocsDefault()},maps=raw_data(maps[:])},rl.Matrix(1))
}

// Gives back what is drawn for the plate shown.
@(private)
hologram_release_drawing :: proc(cache:^Hologram_Cache) {
	for &mesh in cache.meshes {if mesh.vaoId!=0 || mesh.vboId!=nil {rl.UnloadMesh(mesh)};mesh={}}
	for &list in cache.triangles {delete(list);list=nil}
	clear(&cache.lines)
	cache.drawn=false
}

// Gives back all the map keeps: when the expedition closes.
hologram_release :: proc(cache:^Hologram_Cache) {
	hologram_release_drawing(cache)
	delete(cache.lines)
	free(cache.plates)
	cache^={}
}

// Gets the map ready to show `chosen` (the ground if that has no cell) and returns the plate shown: the plates are built
// again if the map or the world changed, what goes to the card if the plate shown changed too.
@(private)
hologram_prepare :: proc(cache:^Hologram_Cache,w:^world.World,data:^level.Level,chosen:i8,tint:rl.Color)->i8 {
	if cache.plates==nil {cache.plates=new([level.LAYER_COUNT]Hologram_Geometry)}
	if !cache.ready || cache.geometry_id!=data.geometry_id || cache.revision!=data.geometry_revision || cache.seed!=w.seed || cache.biome!=w.biome {
		cache.present=hologram_plates(data)
		for layer in grid.LOWEST_LAYER..=grid.HIGHEST_LAYER {
			slot:=level.layer_slot(i8(layer));if !cache.present[slot] {continue}
			if layer==grid.GROUND_LAYER {hologram_geometry(w,data,&cache.plates[slot])} else {hologram_plate(w,data,i8(layer),&cache.plates[slot])}
		}
		cache.ready,cache.drawn=true,false
		cache.geometry_id,cache.revision,cache.seed,cache.biome=data.geometry_id,data.geometry_revision,w.seed,w.biome
	}
	focus:=chosen if level.layer_in_range(chosen) && cache.present[level.layer_slot(chosen)] else i8(grid.GROUND_LAYER)
	if cache.drawn && cache.focus==focus && cache.tint==tint {return focus}
	hologram_release_drawing(cache)
	shown:=&cache.plates[level.layer_slot(focus)]
	side:=max(shown.width,shown.height)
	for layer in grid.LOWEST_LAYER..=grid.HIGHEST_LAYER {
		slot:=level.layer_slot(i8(layer));if !cache.present[slot] {continue}
		if i8(layer)==focus {build_hologram_geography(&cache.plates[slot],tint,focus!=grid.GROUND_LAYER,&cache.triangles[slot],&cache.lines)}
		else {build_hologram_ghost(&cache.plates[slot],hologram_lift(i8(layer),focus,side),&cache.triangles[slot])}
		// Without a window (the tests) there is no card: the list stays.
		if rl.IsWindowReady() && hologram_upload(cache.triangles[slot][:],&cache.meshes[slot]) {delete(cache.triangles[slot]);cache.triangles[slot]=nil}
	}
	cache.drawn,cache.focus,cache.tint=true,focus,tint
	return focus
}

// The colours of the cells: the biome's grounds, the sites' surfaces, a cave's room (15), the rock round it of before
// (16), a complex's tunnel (17), a network (18), a bridge over the ground (19).
@(private)
HOLO_PALETTE :: [20]rl.Color{{},{27,56,78,255},{36,77,90,255},{21,48,82,255},{61,103,128,255},{60,75,88,255},{84,75,104,255},{70,103,126,255},{65,63,105,255},{43,79,105,255},{76,127,149,255},{42,91,106,255},{50,83,112,255},{43,70,94,255},{62,101,125,255},{104,150,163,255},{16,30,46,255},{92,136,158,255},{80,118,170,255},{132,170,190,255}}

// A step of height on the map: more than the board's own, so that the relief reads from far.
@(private)
hologram_step :: proc(g:^Hologram_Geometry)->f32 {return f32(max(g.width,g.height))/160*.45}

// Higher ground is lighter.
@(private)
hologram_lighten :: proc(c:rl.Color,height:i16)->rl.Color {
	k:=1+.11*f32(clamp(height,0,HOLO_FLAT_STEPS))
	return {u8(min(f32(255),f32(c.r)*k)),u8(min(f32(255),f32(c.g)*k)),u8(min(f32(255),f32(c.b)*k)),c.a}
}

// How far over the plate shown (`focus`) the plate of `layer` is drawn: HOLO_PLATE_GAP of the map's side a layer.
@(private)
hologram_lift :: proc(layer,focus:i8,side:int)->f32 {return f32(int(layer)-int(focus))*f32(side)*HOLO_PLATE_GAP}

// What the plate shown is drawn with, kept (hologram_prepare): every cell a prism from under the plate's lowest band, the
// walls, and a contour line wherever the height changes. A plate of a few cells (`sparse`: a bridge, a hall, a gallery)
// has a glow round them, so that they read on the whole map. The plate shown is at the map's plane.
@(private)
build_hologram_geography :: proc(g:^Hologram_Geometry,tint:rl.Color,sparse:bool,triangles,lines:^[dynamic]Hologram_Vertex) {
	palette:=HOLO_PALETTE
	w,h:=f32(g.width),f32(g.height)
	step:=hologram_step(g)
	floor:=f32(g.lowest)*step
	if sparse {
		glow:=f32(max(g.width,g.height))/96
		for y in 0..<g.height {
			for x:=0;x<g.width; {
				c:=g.cells[y*HOLO_SIDE+x];start:=x;x+=1
				for x<g.width && (g.cells[y*HOLO_SIDE+x].ground>0)==(c.ground>0) {x+=1}
				if c.ground==0 {continue}
				hologram_quad(triangles,{f32(start)-glow,floor-2.9,f32(y)-glow},{f32(start)-glow,floor-2.9,f32(y)+1+glow},{f32(x)+glow,floor-2.9,f32(y)+1+glow},{f32(x)+glow,floor-2.9,f32(y)-glow},{88,170,206,70})
			}
		}
	}
	for y in 0..<g.height {
		for x:=0;x<g.width; {
			c:=g.cells[y*HOLO_SIDE+x];start:=x;x+=1
			for x<g.width && g.cells[y*HOLO_SIDE+x].ground==c.ground && g.cells[y*HOLO_SIDE+x].height==c.height {x+=1}
			if c.ground>0 {hologram_prism(triangles,f32(start),f32(y),f32(x-start),1,floor-1.4,f32(c.height)*step,hologram_lighten(palette[c.ground],c.height))}
		}
	}
	for y in 0..<g.height {
		for x:=0;x<g.width; {
			c:=g.cells[y*HOLO_SIDE+x];start:=x;x+=1
			for x<g.width && g.cells[y*HOLO_SIDE+x].wall==c.wall && g.cells[y*HOLO_SIDE+x].height==c.height {x+=1}
			if c.wall==0 {continue}
			height:=f32(c.wall)*f32(max(g.width,g.height))/160
			base:=f32(c.height)*step
			hologram_prism(triangles,f32(start),f32(y),f32(x-start),1,base,base+height,hologram_lighten({80,132,163,255},c.height))
		}
	}
	for y in 0..<g.height {for x:=0;x<g.width; {
		c:=g.cells[y*HOLO_SIDE+x];start:=x;x+=1
		for x<g.width && g.cells[y*HOLO_SIDE+x].wall==c.wall && g.cells[y*HOLO_SIDE+x].height==c.height {x+=1}
		if c.wall==0 {continue}
		height:=f32(c.wall)*f32(max(g.width,g.height))/160+f32(c.height)*step
		hologram_line(lines,{f32(start),height+.03,f32(y)+1},{f32(x),height+.03,f32(y)+1},{148,213,231,190})
	}}
	// Contour lines: a line wherever the ground changes height, at the higher side's level.
	for y in 0..<g.height {for x in 0..<g.width {
		c:=g.cells[y*HOLO_SIDE+x];if c.ground==0 {continue}
		if x+1<g.width {
			next:=g.cells[y*HOLO_SIDE+x+1]
			if next.ground>0 && next.height!=c.height {
				top:=f32(max(c.height,next.height))*step+.04
				hologram_line(lines,{f32(x+1),top,f32(y)},{f32(x+1),top,f32(y+1)},{176,230,244,150})
			}
		}
		if y+1<g.height {
			next:=g.cells[(y+1)*HOLO_SIDE+x]
			if next.ground>0 && next.height!=c.height {
				top:=f32(max(c.height,next.height))*step+.04
				hologram_line(lines,{f32(x),top,f32(y+1)},{f32(x+1),top,f32(y+1)},{176,230,244,150})
			}
		}
	}}
	for i:=0;i<=max(g.width,g.height);i+=16 {
		if i<=g.width {hologram_line(lines,{f32(i),.06,0},{f32(i),.06,h},{74,139,167,38})}
		if i<=g.height {hologram_line(lines,{0,.06,f32(i)},{w,.06,f32(i)},{74,139,167,38})}
	}
	for x:=0;x<=g.width;x+=16 {hologram_line(lines,{f32(x),floor-2.9,h+1},{f32(x),floor-2.9,h+3},{tint.r,tint.g,tint.b,160})}
}

// The plate shown, every frame: its base and its frame, what is kept of it (the glow, the prisms, the walls), its lines.
@(private)
draw_hologram_geography :: proc(cache:^Hologram_Cache,slot:int) {
	g:=&cache.plates[slot]
	w,h:=f32(g.width),f32(g.height)
	floor:=f32(g.lowest)*hologram_step(g)
	base:=make([dynamic]Hologram_Vertex,0,18,context.temp_allocator)
	hologram_prism(&base,-1,-1,w+2,h+2,floor-5,floor-3,{10,24,39,255})
	hologram_send(base[:],rlgl.TRIANGLES)
	rl.DrawCubeWires({w*.5,floor-3,h*.5},w+2,.1,h+2,{68,135,165,255})
	draw_hologram_triangles(cache,slot)
	hologram_send(cache.lines[:],rlgl.LINES)
}

// What one of the other plates is drawn with, kept, `lift` over or under the one shown: only the tops of its cells, faint.
@(private)
build_hologram_ghost :: proc(g:^Hologram_Geometry,lift:f32,triangles:^[dynamic]Hologram_Vertex) {
	palette:=HOLO_PALETTE
	step:=hologram_step(g)
	for y in 0..<g.height {
		for x:=0;x<g.width; {
			c:=g.cells[y*HOLO_SIDE+x];start:=x;x+=1
			for x<g.width && g.cells[y*HOLO_SIDE+x].ground==c.ground && g.cells[y*HOLO_SIDE+x].height==c.height {x+=1}
			if c.ground==0 {continue}
			top:=lift+f32(c.height)*step;color:=palette[c.ground]
			hologram_quad(triangles,{f32(start),top,f32(y)},{f32(start),top,f32(y)+1},{f32(x),top,f32(y)+1},{f32(x),top,f32(y)},{color.r,color.g,color.b,96})
		}
	}
}

// One of the other plates, every frame: its faint tops, kept, and its frame.
@(private)
draw_hologram_ghost :: proc(cache:^Hologram_Cache,layer:i8,lift:f32) {
	slot:=level.layer_slot(layer);g:=&cache.plates[slot]
	draw_hologram_triangles(cache,slot)
	w,h:=f32(g.width),f32(g.height)
	rl.DrawCubeWires({w*.5,lift+f32(g.lowest)*hologram_step(g),h*.5},w+2,.05,h+2,{68,135,165,110})
}

@(private)
hologram_signal_color :: proc(site:^world.Site)->rl.Color {
	if site.state==.Resolved {return {95,141,158,255}}
	if site.state==.Discovered {return {247,213,139,255}}
	return {108,205,236,255}
}

@(private)
draw_hologram_search_area :: proc(area:Hologram_Area,color:rl.Color,clock:f32) {
	for i in 0..<48 {
		a,b:=f32(i)*math.TAU/48,f32(i+1)*math.TAU/48
		p:=area.center+rl.Vector3{math.cos(a)*area.radius,0,math.sin(a)*area.radius}
		q:=area.center+rl.Vector3{math.cos(b)*area.radius,0,math.sin(b)*area.radius}
		if i%3!=2 {rl.DrawLine3D(p,q,color)}
		if i%12==0 {rl.DrawLine3D(p,p+{0,2,0},color)}
	}
	// The breathing fill belongs to the coarse search area, not the true site.
	a:=u8(12+5*math.sin(clock*1.6))
	for i in 0..<24 {
		u,v:=f32(i)*math.TAU/24,f32(i+1)*math.TAU/24
		p:=area.center+rl.Vector3{math.cos(u)*area.radius,0,math.sin(u)*area.radius}
		q:=area.center+rl.Vector3{math.cos(v)*area.radius,0,math.sin(v)*area.radius}
		rl.DrawTriangle3D(area.center,q,p,{color.r,color.g,color.b,a})
	}
}

@(private)
hologram_label_position :: proc(anchor:rl.Vector2,used:[]rl.Vector2)->rl.Vector2 {
	for radius in ([5]f32{0,19,33,47,61}) {for direction in 0..<8 {
		a:=f32(direction)*math.TAU/8
		p:=anchor+rl.Vector2{math.cos(a)*radius,math.sin(a)*radius}
		p.x=clamp(p.x,36,654);p.y=clamp(p.y,109,455)
		clear:=true
		for other in used {if rl.Vector2DistanceSqr(p,other)<26*26 {clear=false;break}}
		if clear {return p}
	}}
	return {clamp(anchor.x,36,654),clamp(anchor.y,109,455)}
}

@(private)
draw_hologram_badge :: proc(frame:^host.Frame,p:rl.Vector2,code:string,color:rl.Color,resolved:bool=false) {
	rl.DrawCircleV(p,10,{8,20,34,245});rl.DrawCircleLinesV(p,10,color)
	ui.draw_text_centered(frame.theme,code,p,.Small,color,false)
	if resolved {rl.DrawLineEx(p+{-7,8},p+{7,-8},1.5,{color.r,color.g,color.b,170})}
}

@(private)
draw_expedition_hologram :: proc(e:^Expedition_Session,frame:^host.Frame) {
	w:=&e.world;accent:=render.expedition_color(w.biome);codes:=HOLO_CODES
	rl.DrawRectangleRec({0,0,960,540},{3,9,18,254})
	rl.DrawCircleGradient({340,292},350,{12,53,82,160},{3,9,18,0})
	for y:=100;y<473;y+=4 {rl.DrawLine(18,i32(y),676,i32(y),{57,107,139,9})}
	ui.draw_text(frame.theme,"ATLANTE OLOGRAFICO",{26,18},.Title,{209,239,248,255})
	ui.draw_text(frame.theme,campaign.biome_name(w.biome),{28,55},.Body,accent)
	ui.draw_text(frame.theme,"TAB / ESC  chiudi",{769,29},.Small,{180,204,220,255})
	rl.DrawLineEx({26,82},{934,82},1,{61,106,133,230})
	// The plates: the ground and every layer that has a cell; the one shown is the one chosen (e.map_layer), the ground if
	// that has none. Kept between frames (Hologram_Cache).
	data:=&e.rs.level_data
	cache:=&e.hologram
	focus:=hologram_prepare(cache,w,data,e.map_layer,accent)
	present:=cache.present
	plates:=cache.plates
	count:=0
	for here in present {if here {count+=1}}
	names:=HOLO_PLATE_NAMES
	header:=names[level.layer_slot(focus)]
	if focus==grid.GROUND_LAYER {header=fmt.tprintf("%s  /  AREE DI RICERCA",header)}
	if count>1 {header=fmt.tprintf("%s      W S  CAMBIA PIANO (%d)",header,count)}
	ui.draw_text(frame.theme,header,{28,94},.Small,{115,173,196,255})
	geometry:=&plates[level.layer_slot(focus)]
	side:=max(geometry.width,geometry.height)
	camera:=hologram_camera(geometry.width,geometry.height)
	canvas_target.begin_scissor(18,110,658,365)
	rl.BeginMode3D(camera)
	draw_hologram_geography(cache,level.layer_slot(focus))
	rlgl.DrawRenderBatchActive();rlgl.DisableDepthMask()
	for layer in grid.LOWEST_LAYER..=grid.HIGHEST_LAYER {
		if i8(layer)==focus || !present[level.layer_slot(i8(layer))] {continue}
		draw_hologram_ghost(cache,i8(layer),hologram_lift(i8(layer),focus,side))
	}
	if focus==grid.GROUND_LAYER {
		for &site in w.sites[:w.site_count] {
			area:=hologram_area(&site);if area.visible {draw_hologram_search_area(area,hologram_signal_color(&site),w.clock)}
		}
	}
	rlgl.DrawRenderBatchActive();rlgl.EnableDepthMask()
	scale:=f32(side)/160;beam:=11*scale
	step:=scale*.45
	// A pin where something found is, on its plate when that is shown: a cave's mouth and a complex the robot has been to,
	// on the ground; a network's hall, on the deep plate. What the robot has not been to is not shown.
	pin:=proc(at:rl.Vector3,scale:f32,color:rl.Color) {
		rl.DrawCircle3D(at,1.4*scale,{1,0,0},90,color)
		rl.DrawLine3D(at,at+{0,4*scale,0},color)
	}
	band_at:=proc(plates:^[level.LAYER_COUNT]Hologram_Geometry,data:^level.Level,p:grid.Position)->f32 {
		return f32(hologram_band(level.height_at(data,p)-plates[level.layer_slot(p.layer)].reference))
	}
	if focus==grid.GROUND_LAYER {
		for cave in w.caves[:w.cave_count] {
			site:=&w.sites[cave.site];if site.state==.Unvisited {continue}
			mouth:=cave.place.mouth
			pin({f32(mouth.x)+.5,band_at(plates,data,mouth)*step+.1,f32(mouth.y)+.5},scale,hologram_signal_color(site))
		}
		for c in w.complexes[:w.complex_count] {
			if !c.visited {continue}
			width,height:=world.complex_size(world.complex_layout(c.kind))
			middle:=grid.offset(c.origin,width/2,height/2)
			pin({f32(middle.x)+.5,band_at(plates,data,middle)*step+.1,f32(middle.y)+.5},scale,{247,213,139,255})
		}
	}
	if focus==world.NETWORK_LAYER {
		plan:=world.network_plan(w.biome)
		for hall,i in plan.halls[:min(len(plan.halls),world.MAX_NETWORK_HALLS)] {
			if hall.crater!=.None || !w.network_visited[i] {continue}
			centre:=world.network_hall_centre(w,plan,i)
			pin({f32(centre.x)+.5,band_at(plates,data,centre)*step+.1,f32(centre.y)+.5},scale,{247,213,139,255})
		}
	}
	// The robot, on its plate, whichever is shown.
	p:=e.rs.room.player.position
	hero:=rl.Vector3{f32(p.x)+.5,hologram_lift(p.layer,focus,side)+band_at(plates,data,p)*step+.5,f32(p.y)+.5}
	rl.DrawCylinder(hero,scale,2*scale,2.5*scale,6,{255,244,207,255})
	rl.DrawLine3D(hero,hero+{0,beam,0},{255,244,207,255})
	rl.DrawSphereEx(hero+{0,beam,0},scale,4,6,{255,244,207,255})
	rl.EndMode3D();rl.EndScissorMode()
	used:[world.MAX_SITES+1]rl.Vector2;used_count:=1
	// On a plate over or under the one shown the robot can be out of the map's panel: its mark stays at the panel's edge.
	hero_screen:=rl.GetWorldToScreenEx(hero+{0,beam,0},camera,960,540)
	hero_screen={clamp(hero_screen.x,24,668),clamp(hero_screen.y,118,468)};used[0]=hero_screen
	rl.DrawCircleLinesV(hero_screen,5,{255,244,207,255})
	ui.draw_text(frame.theme,"TU",hero_screen+{9,-7},.Small,{255,244,207,255})
	for &site in w.sites[:w.site_count] {
		area:=hologram_area(&site);if !area.visible || focus!=grid.GROUND_LAYER {continue}
		anchor:=rl.GetWorldToScreenEx(area.center+{0,2,0},camera,960,540)
		label:=hologram_label_position(anchor,used[:used_count]);used[used_count]=label;used_count+=1
		color:=hologram_signal_color(&site)
		if rl.Vector2DistanceSqr(anchor,label)>4 {rl.DrawLineEx(anchor,label,1,{color.r,color.g,color.b,100})}
		draw_hologram_badge(frame,label,codes[site.kind],color,site.state==.Resolved)
	}
	// No world-space labels: every symbol has one stable, readable key row.
	rl.DrawRectangleRounded({694,99,240,374},.04,4,{11,24,39,245})
	ui.draw_text(frame.theme,"LEGENDA",{710,111},.Body,{206,230,241,255})
	ui.draw_text(frame.theme,"trovati / segnali",{790,140},.Small,{110,152,175,255})
	row:=0
	for kind in world.Site_Kind {
		total,found:=0,0
		for &site in w.sites[:w.site_count] {if site.kind!=kind || !hologram_area(&site).visible {continue};total+=1;if site.state!=.Unvisited {found+=1}}
		y:=f32(168+row*26);row+=1
		color:=rl.Color{147,192,212,255} if total>0 else rl.Color{71,95,113,255}
		draw_hologram_badge(frame,{719,y},codes[kind],color)
		name:=world.site_name(kind)
		if kind==.Boss {name="BOSS"}
		if kind==.Memory && total==0 {name="SEGRETO"}
		if kind==.Tunnel && total==0 {name="PASSAGGIO"}
		ui.draw_text(frame.theme,name,{737,y-7},.Small,color)
		ui.draw_text(frame.theme,fmt.tprintf("%d/%d",found,total),{891,y-7},.Small,color)
	}
	rl.DrawLine(710,409,917,409,{52,83,104,255})
	ui.draw_text(frame.theme,"I segreti appaiono solo",{710,421},.Small,{124,159,181,255})
	ui.draw_text(frame.theme,"dopo la scoperta.",{710,440},.Small,{124,159,181,255})
	rl.DrawLineEx({26,482},{934,482},1,{61,106,133,230})
	states:=[3]string{"Da esplorare","Scoperto","Risolto"}
	for color,i in ([3]rl.Color{{108,205,236,255},{247,213,139,255},{95,141,158,255}}) {
		x:=f32(33+i*186);rl.DrawCircleLinesV({x,500},5,color)
		ui.draw_text(frame.theme,states[i],{x+13,493},.Small,color)
	}
	ui.draw_text(frame.theme,fmt.tprintf("TU  %03d : %03d    %d x %d",p.x,p.y,geometry.width,geometry.height),{677,493},.Small,{255,233,188,255})
	ui.draw_text(frame.theme,"I cerchi indicano aree, mai posizioni esatte. Nessun tracciamento dei nemici.",{28,518},.Small,{116,155,180,255})
	if e.rs.room.phase==.Combat {ui.draw_text(frame.theme,"SCONTRO / TEMPO ATTIVO",{714,63},.Small,{245,159,112,255})}
}
