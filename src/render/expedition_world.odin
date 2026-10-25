package render

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import world "../expedition"
import campaign "../campaign"
import game "../game"
import grid "../engine/grid"
import level "../level"
import view "../engine/view"

expedition_color :: proc(b: campaign.Biome) -> rl.Color { c:=world.metadata(b).color; return {c[0],c[1],c[2],255} }

@(private)
draw_expedition_tile :: proc(renderer:^Renderer,room:^game.Room,w:^world.World,cell:grid.Position,preview:^Card_Range_Preview) {
	tile,_:=level.tile_at(room.level_data,cell)
	if tile.kind==.Void {return}
	c:=expedition_color(w.biome); base:=rl.Vector3{f32(cell.x)+0.5,-0.12,f32(cell.y)+0.5}
	_,design:=expedition_site_near(renderer,w,cell)
	// The matte night floor of the reference; courtyards are a shade apart.
	ink:=rl.Color{9,11,18,255}
	if design.inside {
		#partial switch design.surface {
		case .Platform:ink={14,17,27,255}
		case .Approach,.Threshold:ink={10,12,20,255}
		case .Passage:ink={10,12,19,255}
		case .Garden:ink={9,14,18,255}
		case .Ruin:ink={10,12,20,255}
		}
	}
	rl.DrawCubeV(base,{1,0.22,1},ink)
	for d in ([4]grid.Position{{x = 1, y = 0},{x = -1, y = 0},{x = 0, y = 1},{x = 0, y = -1}}) {
		n,ok:=level.tile_at(room.level_data,game.add_position(cell,d))
		if !ok || n.kind==.Void {a:=base+rl.Vector3{f32(d.x)*.5,.13,f32(d.y)*.5};v:=rl.Vector3{f32(d.y)*.5,0,f32(d.x)*.5};rl.DrawLine3D(a-v,a+v,c)}
	}
	if tile.kind==.Wall {return}
	// Encounters tile the floor around the fighters: lighter tiles in the
	// biome's tint, the dark floor showing through as the joints.
	if near:=expedition_grid_weight(renderer.tactical.expedition_material,cell);near>.01 {
		tile_color:=rl.Color{u8(f32(ink.r)*.92+f32(c.r)*.08),u8(f32(ink.g)*.92+f32(c.g)*.08),u8(f32(ink.b)*.92+f32(c.b)*.08),u8(near*255)}
		rl.DrawCubeV(base+{0,.112,0},{.9,.006,.9},tile_color)
		rim:=color_with_opacity(c,near*.3);top:=base+rl.Vector3{0,.117,0}
		corners:=[4]rl.Vector3{top+{-.45,0,-.45},top+{.45,0,-.45},top+{.45,0,.45},top+{-.45,0,.45}}
		for i in 0..<4 {rl.DrawLine3D(corners[i],corners[(i+1)%4],rim)}
	}
	if design.inside && design.surface==.Platform {
		for d in ([4]grid.Position{{x = 1, y = 0},{x = -1, y = 0},{x = 0, y = 1},{x = 0, y = -1}}) {
			_,adjacent:=expedition_site_near(renderer,w,game.add_position(cell,d))
			if adjacent.surface!=.Platform {
				at:=base+rl.Vector3{f32(d.x)*.485,.14,f32(d.y)*.485}
				rl.DrawCubeV(at,{.02 if d.x!=0 else .97,.012,.02 if d.y!=0 else .97},ink_scale(c,.45))
			}
		}
	}

	ground:=game.expedition_ground(room,cell)
	color:rl.Color
	#partial switch ground {
	case .Electric:color={80,153,255,110}
	case .Grass:color={70,106,34,35}
	case .Sand:color={210,161,62,60}
	case .Water:color={72,114,108,105}
	case .Swamp:color={72,114,108,55}
	case .Ice:color={126,208,245,140}
	case .Snow:color={188,223,241,50}
	case .Lava:color={255,78,23,200}
	case .Bridge:color=color_with_opacity(c,.65 if w.beat%4<2 else .08)
	case .Gravity:color={164,90,240,100}
	}
	if color.a>0 {rl.DrawCubeV(base+{0,.13,0},{.9,.016,.9},color)}
	if ground==.Grass && (cell.x+cell.y)%3==0 {
		for blade in 0..<3 {offset:=f32(blade-1)*.13;rl.DrawLine3D(base+{offset,.13,0},base+{offset+.1,.45+f32(blade%2)*.19,.1},color_with_opacity(c,.65))}
	}
	if ground==.Gravity {rl.DrawCircle3D(base+{0,.15,0},.37,{1,0,0},90,c)}
	if w.biome==.Inferno && (tile.kind==.Door || (w.lane_warning && world.lane_contains(w,cell))) {
		glow:=rl.Color{255,175,48,255} if tile.kind==.Door else rl.Color{255,91,37,u8(120+100*math.sin(w.clock*9))}
		crack:=base+rl.Vector3{0,.16,0}
		rl.DrawLine3D(crack+{-.45,0,-.4},crack+{.14,0,-.08},glow)
		rl.DrawLine3D(crack+{.14,0,-.08},crack+{-.15,0,.2},glow)
		rl.DrawLine3D(crack+{-.15,0,.2},crack+{.42,0,.45},glow)
		rl.DrawLine3D(crack+{.14,0,-.08},crack+{.45,0,-.35},glow)
	}
	if w.lane_warning && world.lane_contains(w,cell) {
		rl.DrawCubeV(base+{0,.15,0},{.96,.025,.96},{255,102,59,u8(100+70*math.sin(w.clock*10))})
	}
	if renderer.tactical.expedition_material==nil && room.phase==.Combat && world.distance(cell,room.player.position)<=7 && tile.kind!=.Wall {
		// Preserve the local tiles even when the shader could not be built.
		p:=base+rl.Vector3{0,.115,0}
		rl.DrawCubeWires(p,.9,.005,.9,color_with_opacity(c,.35))
	}
}

// Sites whose floor plans reach the drawn region, gathered once a frame:
// floor and walls ask only these, never every site for every cell.
Expedition_Near_Sites :: struct { items:[world.MAX_SITES]u8, count:int }

@(private)
expedition_gather_sites :: proc(renderer:^Renderer,w:^world.World,lo,hi:grid.Position) {
	near:=&renderer.tactical.expedition_sites;near.count=0
	for &site,i in w.sites[:world.visible_sites(w)] {
		a,b:=world.site_bounds(&site)
		if b.x<lo.x || b.y<lo.y || a.x>hi.x || a.y>hi.y {continue}
		near.items[near.count]=u8(i);near.count+=1
	}
}

// world.site_at over the gathered sites, in the same order.
@(private)
expedition_site_near :: proc(renderer:^Renderer,w:^world.World,cell:grid.Position)->(index:int,design:world.Site_Cell) {
	near:=&renderer.tactical.expedition_sites
	for i in near.items[:near.count] {
		design=world.site_cell(&w.sites[i],cell)
		if design.inside {return int(i),design}
	}
	return -1,{}
}

// Sleeping patrols step a cell every beat or so; their cards glide there.
Expedition_Patrol_Glide :: struct {
	from, to, shown: [world.MAX_GROUPS*world.MAX_MEMBERS]view.Vec2,
	t: [world.MAX_GROUPS*world.MAX_MEMBERS]f32,
	ready: [world.MAX_GROUPS*world.MAX_MEMBERS]bool,
}

@(private)
update_expedition_patrol_glide :: proc(renderer:^Renderer,w:^world.World) {
	glide:=&renderer.tactical.expedition_patrols
	// A fresh map or a teleport: every card simply stands where it is.
	if !renderer.tactical.expedition_follow_ready {glide.ready={}}
	dt:=expedition_frame_dt(renderer)
	for &group,g in w.groups[:w.group_count] {for member,m in group.members[:group.count] {
		if !world.in_scope(w,group.cave) {continue}
		i:=g*world.MAX_MEMBERS+m
		target:=view.Vec2{f32(member.enemy.position.x),f32(member.enemy.position.y)}
		if !member.alive || member.deployed || !glide.ready[i] || abs(target.x-glide.to[i].x)+abs(target.y-glide.to[i].y)>2.5 {
			glide.from[i],glide.to[i],glide.shown[i],glide.t[i],glide.ready[i]=target,target,target,1,member.alive && !member.deployed
			continue
		}
		if target!=glide.to[i] {glide.from[i],glide.to[i],glide.t[i]=glide.shown[i],target,0}
		glide.t[i]=min(1,glide.t[i]+dt/.55)
		s:=glide.t[i]*glide.t[i]*(3-2*glide.t[i])
		glide.shown[i]=glide.from[i]+(glide.to[i]-glide.from[i])*s
	}}
}

@(private)
expedition_patrol_shown :: proc(renderer:^Renderer,group,member:int,fallback:grid.Position)->view.Vec2 {
	i:=group*world.MAX_MEMBERS+member
	glide:=&renderer.tactical.expedition_patrols
	if i>=0 && i<len(glide.ready) && glide.ready[i] {return glide.shown[i]}
	return {f32(fallback.x),f32(fallback.y)}
}

@(private)
draw_expedition_props :: proc(renderer:^Renderer,room:^game.Room,w:^world.World) {
	renderer.tactical.expedition_mounted=w.mounted || room.player.tactical.dinosaur_remaining>0
	renderer.tactical.expedition_clock=w.clock
	update_expedition_patrol_glide(renderer,w)

	for &group,g in w.groups[:w.group_count] {for m,i in group.members[:group.count] {
		if !m.alive || m.deployed || !world.in_scope(w,group.cave) || !tactical_cell_on_screen(renderer,m.enemy.position) {continue}
		if world.ground(w,m.enemy.position)==.Grass && world.distance(room.player.position,m.enemy.position)>3 {continue}
		tactical_billboard(renderer,sprite_key_for_enemy(m.enemy.archetype),expedition_patrol_shown(renderer,g,i,m.enemy.position),1)
	}}
	for drop in w.drops[:w.drop_count] {
		if !world.in_scope(w,drop.cave) || !tactical_cell_on_screen(renderer,drop.position) {continue}
		p:=rl.Vector3{f32(drop.position.x)+.5,.25+math.sin(w.clock*3+f32(drop.position.x))*.05,f32(drop.position.y)+.5}
		_,design:=world.site_at(w,drop.position)
		if design.fixture {p.y+=design.wall_height}
		color:=rl.Color{102,219,255,255} if drop.xp>0 else rl.Color{246,204,111,255}
		if drop.xp>0 {rl.DrawCubeV(p,{.19,.19,.19},color)}
		else {art:=expedition_loot_art(drop.item);draw_expedition_paper(renderer,&art,p-{0,.16,0},.8)}
		rl.DrawCircle3D(p-{0,.2,0},.25,{1,0,0},90,color_with_opacity(color,.5))
	}
	draw_expedition_costumes(renderer,room,w)
	if w.mounted || room.player.tactical.dinosaur_remaining>0 {draw_expedition_mount(renderer,w,room.player.tactical.dinosaur_remaining>0)}
	draw_structure_ghost(renderer)
}

@(private)
draw_expedition_mount :: proc(renderer:^Renderer,w:^world.World,dinosaur:bool=false) {
	p,travel_lift:=living_card_position(renderer,game.PLAYER_ENTITY,.Player,renderer.tactical.snapshot.player.position)
	art:=expedition_mount_art(w.biome,expedition_gait_time(renderer,w.clock),dinosaur)
	hover:=w.biome==.Cyber || w.biome==.Space || w.biome==.Sky
	lift:=f32(.02)+(.06+math.sin(w.clock*3)*.035 if hover else math.sin(w.clock*6)*.015)
	base:=rl.Vector3{p.x+.5,lift+travel_lift,p.y+.5}
	mirror:=false
	if renderer.tactical.living_state!=nil {if actor:=living_find(renderer,game.PLAYER_ENTITY,.Pilgrim);actor!=nil {mirror=actor.facing_left}}
	draw_expedition_paper(renderer,&art,base,.84,mirror)
}

draw_expedition_labels :: proc(renderer:^Renderer,room:^game.Room,w:^world.World) {
	c:=expedition_color(w.biome)
	for site in w.sites[:world.visible_sites(w)] {
		if !site.active || site.state==.Resolved || world.distance(room.player.position,site.position)>10 {continue}
		if site.secret && site.state==.Unvisited {continue}
		label_height:=f32(2.7) if w.biome==.Cyber && site.kind==.Workshop else 1.5
		p:=tactical_project(renderer,{f32(site.position.x)+.5,f32(site.position.y)+.5},label_height)
		draw_tactical_label(renderer,p,fmt.ctprintf("%s",world.site_name(site.kind)),"E  INTERAGISCI" if room.phase==.Loot && !w.mounted && world.distance(room.player.position,site.position)<=3 else "",c)
	}
	names:=world.metadata(w.biome).enemies
	for enemy in room.enemies {
		if !tactical_cell_on_screen(renderer,enemy.position) {continue}
		p:=tactical_project(renderer,{f32(enemy.position.x)+.5,f32(enemy.position.y)+.5},2)
		draw_tactical_label(renderer,p,fmt.ctprintf("%s",names[int(enemy.archetype)]),"",c)
	}
}
