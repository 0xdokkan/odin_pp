package expedition

import grid "../engine/grid"
import game "../game"
import level "../level"

// All coordinates here describe actual gameplay geometry. The renderer may
// dress the stone/concrete/wood differently by biome, but a Wall is always
// backed by the very same tile that stops movement and line of sight.
SITE_LAYOUT_VERSION :: u8(1)
Site_Surface :: enum u8 { None, Approach, Courtyard, Platform, Passage, Garden, Arena, Ruin, Pool, Threshold }
Site_Cell :: struct {
	inside, wall, fixture: bool,
	surface: Site_Surface,
	local: grid.Position,
	// Visual slab/structure height; actors remain on the tactical ground.
	slab_height, wall_height: f32,
}
Site_Layout :: struct {
	half_extent: grid.Position,
	entrances: [4]grid.Position,
	entrance_count: int,
	spawn_lanes: [3]grid.Position,
	spawn_count: int,
	trigger_radius, encounter_radius: int,
}
Site_Decor_Kind :: enum u8 { Gatepost, Pillar, Light, Terminal, Basin, Spawn, Broken_Arch }
Site_Decor :: struct { kind:Site_Decor_Kind, position:grid.Position, height:f32 }
Site_Decor_Set :: struct { items:[16]Site_Decor, count:int }

site_layout :: proc(kind:Site_Kind)->(d:Site_Layout) {
	d.trigger_radius=8;d.encounter_radius=16
	switch kind {
	case .Nest:
		d.half_extent={13,12};d.entrances={{-13,0},{13,0},{-4,-12},{5,12}};d.entrance_count=4
		d.spawn_lanes={{8,-6},{8,6},{0,-7}};d.spawn_count=3
	case .Cache:
		d.half_extent={11,10};d.entrances={{-11,0},{-5,10},{},{}};d.entrance_count=2
		d.spawn_lanes={{5,-2},{5,2},{6,0}};d.spawn_count=3
	case .Archive:
		d.half_extent={14,12};d.entrances={{-14,0},{0,12},{5,-12},{}};d.entrance_count=3
	case .Workshop:
		d.half_extent={12,11};d.entrances={{-12,0},{0,11},{0,-11},{}};d.entrance_count=3
	case .Spring:
		d.half_extent={12,12};d.entrances={{-12,0},{12,0},{0,-12},{0,12}};d.entrance_count=4
	case .Trial:
		d.half_extent={14,13};d.entrances={{-14,0},{14,0},{0,-13},{0,13}};d.entrance_count=4
		d.spawn_lanes={{7,-6},{7,6},{0,-8}};d.spawn_count=3
	case .Boss:
		d.half_extent={14,14};d.entrances={{-14,0},{-6,-14},{6,14},{}};d.entrance_count=3
		d.spawn_lanes={{4,0},{8,-8},{8,8}};d.spawn_count=3;d.encounter_radius=20
	case .Memory:
		d.half_extent={10,10};d.entrances={{-10,0},{0,10},{0,-10},{}};d.entrance_count=3
	case .Tunnel:
		d.half_extent={11,10};d.entrances={{-11,0},{11,0},{},{}};d.entrance_count=2
	}
	return
}

site_rotate :: proc(p:grid.Position,orientation:u8)->grid.Position {
	switch orientation%4 {
	case 0:return p
	case 1:return {-p.y,p.x}
	case 2:return {-p.x,-p.y}
	case 3:return {p.y,-p.x}
	}
	return p
}

site_local :: proc(site:^Site,p:grid.Position)->grid.Position {return site_rotate({p.x-site.position.x,p.y-site.position.y},(4-site.orientation%4)%4)}
site_world :: proc(site:^Site,p:grid.Position)->grid.Position {return game.add_position(site.position,site_rotate(p,site.orientation))}

@(private)
site_gatepost :: proc(kind:Site_Kind,entry:grid.Position,side:int)->grid.Position {
	spread:=4 if kind==.Boss else 3
	if abs(entry.x)>abs(entry.y) {return {entry.x-clamp(entry.x,-1,1)*2,entry.y+spread*side}}
	return {entry.x+spread*side,entry.y-clamp(entry.y,-1,1)*2}
}

site_bounds :: proc(site:^Site)->(minimum,maximum:grid.Position) {
	d:=site_layout(site.kind);half:=d.half_extent
	if site.orientation%2==1 {half={half.y,half.x}}
	return {site.position.x-half.x,site.position.y-half.y},{site.position.x+half.x,site.position.y+half.y}
}

site_cell :: proc(site:^Site,p:grid.Position)->(cell:Site_Cell) {
	if site==nil || site.layout_version!=SITE_LAYOUT_VERSION {return}
	q:=site_local(site,p);d:=site_layout(site.kind);x,y:=q.x,q.y;ax,ay:=abs(x),abs(y)
	if ax>d.half_extent.x || ay>d.half_extent.y {return}
	cell={inside=true,surface=.Courtyard,local=q,slab_height=.025,wall_height=1.8}
	if ax>d.half_extent.x-2 || ay>d.half_extent.y-2 {cell.surface=.Approach}
	switch site.kind {
	case .Nest:
		cell.wall=(ax==11 && ay<=10) || (ay==10 && ax<=11)
		if (ax==11 && ay<=2) || (y== -10 && x>= -5 && x<= -2) || (y==10 && x>=3 && x<=6) {cell.wall=false;cell.surface=.Threshold}
		if (ax==5 && ay>=3 && ay<=6) || (y== -8 && x>= -5 && x<= -3) {cell.wall=true;cell.wall_height=1.15}
		if ax<=3 && ay<=3 {cell.surface=.Platform}
		if x>=6 && ay>=4 && ay<=8 {cell.surface=.Passage}
	case .Cache:
		cell.wall=(ax==8 && ay<=8) || (ay==8 && ax<=8)
		if (x== -8 && ay<=2) || (y==8 && x>= -6 && x<= -3) {cell.wall=false;cell.surface=.Threshold}
		if (x== -3 && ay>=2 && ay<=5) || (x>=2 && x<=4 && ay==4) {cell.wall=true;cell.wall_height=1.15}
		if x>= -1 && x<=5 && ay<=2 {cell.surface=.Platform}
		if ay==6 || x== -5 {cell.surface=.Passage}
	case .Archive:
		cell.surface=.Ruin
		cell.wall=(ax==11 && ay>=3 && ay<=9) || (ay==9 && ax<=9 && !(x>= -1 && x<=1) && !(x>=4 && x<=6))
		if (ay==5 && ax>=3 && ax<=7) || (x==6 && ay==2) {cell.wall=true;cell.wall_height=1.2}
		if ay<=2 {cell.surface=.Approach}
		if x>= -2 && x<=4 && ay<=3 {cell.surface=.Platform}
	case .Workshop:
		cell.wall=(x==9 && ay<=9) || (ay==9 && x>= -8 && x<=9 && ax>2)
		if (x>=5 && x<=7 && ay==5) || (x== -7 && ay>=6 && ay<=7) {cell.wall=true;cell.wall_height=1.05}
		if ax<=5 && ay<=4 {cell.surface=.Platform}
		if x<= -6 && ay<=3 {cell.surface=.Approach}
	case .Spring:
		cell.surface=.Garden
		cell.wall=(ax==8 && (ay==4 || ay==7)) || (ay==8 && ax>=3 && ax<=5)
		cell.wall_height=1.4
		if ax<=2 && ay<=2 {cell.surface=.Pool}
		else if ax<=4 && ay<=4 {cell.surface=.Platform}
		else if ax<=1 || ay<=1 {cell.surface=.Passage}
	case .Trial:
		cell.surface=.Arena
		cell.wall=(ax==11 && ay<=10) || (ay==10 && ax<=11)
		if (ax==11 && ay<=2) || (ay==10 && ax<=2) {cell.wall=false;cell.surface=.Threshold}
		if ax>=4 && ax<=5 && ay>=4 && ay<=5 {cell.wall=true;cell.wall_height=1.25}
		if ax<=2 && ay<=2 {cell.surface=.Platform}
	case .Boss:
		cell.surface=.Arena;cell.wall_height=2.6
		cell.wall=(ax==12 && ay<=12) || (ay==12 && ax<=12)
		if (x== -12 && ay<=3) || (y== -12 && x>= -8 && x<= -4) || (y==12 && x>=4 && x<=8) {cell.wall=false;cell.surface=.Threshold}
		if (ax>=6 && ax<=7 && ay>=5 && ay<=6) || (x== -9 && ay>=7 && ay<=9) {cell.wall=true;cell.wall_height=1.4}
		if x<= -8 && ay<=3 {cell.surface=.Approach}
		if ax<=4 && ay<=4 {cell.surface=.Platform}
	case .Memory:
		cell.surface=.Ruin;cell.wall_height=1.2
		cell.wall=(ax==7 && ay>=3 && ay<=7) || (ay==7 && ax>=3 && ax<=5) || (ax==4 && y== -3)
		if ax<=2 && ay<=2 {cell.surface=.Platform}
	case .Tunnel:
		cell.surface=.Passage;cell.wall_height=2.1
		cell.wall=(ay==7 && ax<=8) || (ax==8 && ay>=3 && ay<=7) || (ax==3 && ay>=3 && ay<=5)
		if ax<=2 && ay<=2 {cell.surface=.Platform}
	}
	for entry in d.entrances[:d.entrance_count] {for side in ([2]int{-1,1}) {
		if q==site_gatepost(site.kind,entry,side) {cell.wall=true;cell.wall_height=2.2}
	}}
	if q=={} && site.kind!=.Trial && site.kind!=.Boss && site.kind!=.Tunnel {
		cell.fixture,cell.wall=true,true
		cell.wall_height=1.3 if site.kind==.Archive || site.kind==.Memory else (.7 if site.kind==.Cache || site.kind==.Workshop else 1)
	}
	if site.kind==.Boss && ay==0 && ax==2 {cell.fixture,cell.wall=true,true;cell.wall_height=3.4}
	if cell.surface==.Platform {cell.slab_height=.055}
	return
}

site_at :: proc(w:^World,p:grid.Position)->(index:int,cell:Site_Cell) {
	if w!=nil {for &site,i in w.sites[:w.site_count] {cell=site_cell(&site,p);if cell.inside {return i,cell}}}
	return -1,{}
}

site_decor_anchors :: proc(site:^Site)->(set:Site_Decor_Set) {
	if site==nil || site.layout_version!=SITE_LAYOUT_VERSION {return}
	d:=site_layout(site.kind)
	for entry in d.entrances[:d.entrance_count] {
		for side in ([2]int{-1,1}) {p:=site_gatepost(site.kind,entry,side);set.items[set.count]={.Gatepost,site_world(site,p),2.2};set.count+=1}
	}
	set.items[set.count]={.Basin if site.kind==.Spring else .Terminal,site.position,1.3};set.count+=1
	for spawn in d.spawn_lanes[:d.spawn_count] {set.items[set.count]={.Spawn,site_world(site,spawn),.1};set.count+=1}
	return
}

@(private)
stamp_site :: proc(data:^level.Level,site:^Site) {
	minimum,maximum:=site_bounds(site)
	for y in minimum.y..=maximum.y {for x in minimum.x..=maximum.x {
		p:=grid.Position{x,y};cell:=site_cell(site,p);if !cell.inside {continue}
		_=level.set_tile(data,p,{.Wall if cell.wall else .Floor})
	}}
}

@(private)
site_spawn_position :: proc(site:^Site,wave,member:int)->grid.Position {
	d:=site_layout(site.kind)
	if d.spawn_count==0 {return game.add_position(site.position,{member%3-1,member/3-1})}
	lane:=d.spawn_lanes[wave%d.spawn_count]
	// Alternating spawn wings leave the ritual center and all exits free.
	return site_world(site,game.add_position(lane,{member%3-1,member/3-1}))
}
