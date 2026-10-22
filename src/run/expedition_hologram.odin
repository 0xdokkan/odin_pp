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
import render "../render"

// The miniature reads only terrain and public site knowledge. Neither enemy
// locations nor encounter RNG enter this presentation. Row merging preserves
// every wall, entrance and void cell while avoiding one cube per map tile.
HOLO_SIDE :: 256
Hologram_Cell :: struct { ground, wall: u8 }
Hologram_Geometry :: struct {
	width, height: int,
	cells: [HOLO_SIDE*HOLO_SIDE]Hologram_Cell,
}
Hologram_Area :: struct { visible:bool, center:rl.Vector3, radius:f32 }
HOLO_CODES :: [world.Site_Kind]string{.Nest="N",.Cache="C",.Archive="A",.Workshop="O",.Spring="F",.Trial="P",.Boss="B",.Memory="M",.Tunnel="T"}

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

@(private)
hologram_geometry :: proc(w:^world.World,data:^level.Level,out:^Hologram_Geometry) {
	out.width=min(data.tiles.width,HOLO_SIDE);out.height=min(data.tiles.height,HOLO_SIDE)
	for y:=0;y<out.height;y+=2 {for x:=0;x<out.width;x+=2 {
		ground:=u8(1)
		#partial switch world.terrain(w.biome,{x,y}) {
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
			c.ground=ground
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
			design:=world.site_cell(&site,{x,y});if !design.inside {continue}
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

@(private)
hologram_quad :: proc(a,b,c,d:rl.Vector3,color:rl.Color) {
	rlgl.Begin(rlgl.TRIANGLES);rlgl.Color4ub(color.r,color.g,color.b,color.a)
	for p in ([6]rl.Vector3{a,b,c,a,c,d}) {rlgl.Vertex3f(p.x,p.y,p.z)}
	rlgl.End()
}

@(private)
hologram_prism :: proc(x,z,width,depth,bottom,top:f32,c:rl.Color) {
	// The fixed overview camera sees the top, east and south. Explicit face
	// colors give the entire map a softly lit relief without shader ownership.
	a,b:=rl.Vector3{x,top,z},rl.Vector3{x+width,top,z}
	c0,d:=rl.Vector3{x+width,top,z+depth},rl.Vector3{x,top,z+depth}
	hologram_quad(a,d,c0,b,c)
	hologram_quad(d,{x,bottom,z+depth},{x+width,bottom,z+depth},c0,{u8(f32(c.r)*.43),u8(f32(c.g)*.51),u8(f32(c.b)*.65),c.a})
	hologram_quad(c0,{x+width,bottom,z+depth},{x+width,bottom,z},b,{u8(f32(c.r)*.64),u8(f32(c.g)*.74),u8(f32(c.b)*.83),c.a})
}

@(private)
draw_hologram_geography :: proc(g:^Hologram_Geometry,tint:rl.Color) {
	palette:=[15]rl.Color{{},{27,56,78,255},{36,77,90,255},{21,48,82,255},{61,103,128,255},{60,75,88,255},{84,75,104,255},{70,103,126,255},{65,63,105,255},{43,79,105,255},{76,127,149,255},{42,91,106,255},{50,83,112,255},{43,70,94,255},{62,101,125,255}}
	w,h:=f32(g.width),f32(g.height)
	hologram_prism(-1,-1,w+2,h+2,-5,-3,{10,24,39,255})
	rl.DrawCubeWires({w*.5,-3,h*.5},w+2,.1,h+2,{68,135,165,255})
	for y in 0..<g.height {
		for x:=0;x<g.width; {
			c:=g.cells[y*HOLO_SIDE+x];start:=x;x+=1
			for x<g.width && g.cells[y*HOLO_SIDE+x].ground==c.ground {x+=1}
			if c.ground>0 {hologram_prism(f32(start),f32(y),f32(x-start),1,-1.4,0,palette[c.ground])}
		}
	}
	for y in 0..<g.height {
		for x:=0;x<g.width; {
			c:=g.cells[y*HOLO_SIDE+x];start:=x;x+=1
			for x<g.width && g.cells[y*HOLO_SIDE+x].wall==c.wall {x+=1}
			if c.wall==0 {continue}
			height:=f32(c.wall)*f32(max(g.width,g.height))/160
			hologram_prism(f32(start),f32(y),f32(x-start),1,0,height,{80,132,163,255})
		}
	}
	// Keep triangle and line batches contiguous; alternating them per wall
	// would turn a whole-map overview into thousands of tiny GL draw calls.
	for y in 0..<g.height {for x:=0;x<g.width; {
		c:=g.cells[y*HOLO_SIDE+x];start:=x;x+=1
		for x<g.width && g.cells[y*HOLO_SIDE+x].wall==c.wall {x+=1}
		if c.wall==0 {continue}
		height:=f32(c.wall)*f32(max(g.width,g.height))/160
		rl.DrawLine3D({f32(start),height+.03,f32(y)+1},{f32(x),height+.03,f32(y)+1},{148,213,231,190})
	}}
	for i:=0;i<=max(g.width,g.height);i+=16 {
		if i<=g.width {rl.DrawLine3D({f32(i),.06,0},{f32(i),.06,h},{74,139,167,38})}
		if i<=g.height {rl.DrawLine3D({0,.06,f32(i)},{w,.06,f32(i)},{74,139,167,38})}
	}
	for x:=0;x<=g.width;x+=16 {rl.DrawLine3D({f32(x),-2.9,h+1},{f32(x),-2.9,h+3},{tint.r,tint.g,tint.b,160})}
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
	ui.draw_text(frame.theme,"RILIEVO COMPLETO  /  AREE DI RICERCA",{28,94},.Small,{115,173,196,255})
	geometry:Hologram_Geometry;hologram_geometry(w,&e.rs.level_data,&geometry)
	camera:=hologram_camera(geometry.width,geometry.height)
	canvas_target.begin_scissor(18,110,658,365)
	rl.BeginMode3D(camera)
	draw_hologram_geography(&geometry,accent)
	rlgl.DrawRenderBatchActive();rlgl.DisableDepthMask()
	for &site in w.sites[:w.site_count] {
		area:=hologram_area(&site);if area.visible {draw_hologram_search_area(area,hologram_signal_color(&site),w.clock)}
	}
	rlgl.DrawRenderBatchActive();rlgl.EnableDepthMask()
	p:=e.rs.room.player.position;hero:=rl.Vector3{f32(p.x)+.5,.5,f32(p.y)+.5}
	scale:=f32(max(geometry.width,geometry.height))/160;beam:=11*scale
	rl.DrawCylinder(hero,scale,2*scale,2.5*scale,6,{255,244,207,255})
	rl.DrawLine3D(hero,hero+{0,beam,0},{255,244,207,255})
	rl.DrawSphereEx(hero+{0,beam,0},scale,4,6,{255,244,207,255})
	rl.EndMode3D();rl.EndScissorMode()
	used:[world.MAX_SITES+1]rl.Vector2;used_count:=1
	hero_screen:=rl.GetWorldToScreenEx(hero+{0,beam,0},camera,960,540);used[0]=hero_screen
	rl.DrawCircleLinesV(hero_screen,5,{255,244,207,255})
	ui.draw_text(frame.theme,"TU",hero_screen+{9,-7},.Small,{255,244,207,255})
	for &site in w.sites[:w.site_count] {
		area:=hologram_area(&site);if !area.visible {continue}
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
