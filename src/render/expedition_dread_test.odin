package render

import "core:math"
import "core:slice"
import "core:testing"
import rl "vendor:raylib"
import campaign "../campaign"
import world "../expedition"
import game "../game"
import grid "../engine/grid"
import level "../level"

@(private)
DREAD_TEST_BIOMES :: [3]campaign.Biome{.Jungle,.Vietnam,.Gothic}

@(private)
dread_test_mesh :: proc(t:^testing.T,b:^Expedition_Geometry_Builder) {
	testing.expect(t,len(b.vertices)>0 && len(b.vertices)%3==0)
	finite,unit,opaque,wound,nonzero,lines:=true,true,true,true,true,true
	for v in b.vertices {
		for component in v.position {finite=finite && !math.is_nan(component) && !math.is_inf(component)}
		unit=unit && abs(rl.Vector3Length(v.normal)-1)<.001
		opaque=opaque && v.color.a==255
	}
	for i:=0;i<len(b.vertices);i+=3 {
		a,c,d:=b.vertices[i],b.vertices[i+1],b.vertices[i+2]
		cross:=rl.Vector3CrossProduct(c.position-a.position,d.position-a.position)
		nonzero=nonzero && rl.Vector3LengthSqr(cross)>.0000000001
		wound=wound && rl.Vector3DotProduct(cross,a.normal)>0
	}
	for l in b.lines {lines=lines && l.color.a>0 && rl.Vector3DistanceSqr(l.a,l.b)>.000001}
	testing.expect(t,finite,"positions remain finite")
	testing.expect(t,unit,"unit normals survive the cached/reflected material")
	testing.expect(t,opaque,"solid materials stay opaque")
	testing.expect(t,wound && nonzero,"outward triangles have no collapsed caps")
	testing.expect(t,lines,"only actual nonzero light marks are collected")
}

@(test)
test_dread_outdoor_silhouettes_are_bounded_cheap_and_cache_stable :: proc(t:^testing.T) {
	w:=new(world.World);defer free(w)
	b,again:Expedition_Geometry_Builder
	defer {delete(b.vertices);delete(b.lines);delete(again.vertices);delete(again.lines)}
	for biome in DREAD_TEST_BIOMES {
		w.biome=biome;short,tall:=0,0
		for i in 0..<96 {
			cell:=grid.Position{i*7%61,i*13%59}
			clear(&b.vertices);clear(&b.lines);clear(&again.vertices);clear(&again.lines)
			testing.expect(t,draw_expedition_dread_outdoor({mode=.Bake,builder=&b},w,cell))
			w.clock+=.13;w.seed+=123;w.boss_defeated=!w.boss_defeated
			testing.expect(t,draw_expedition_dread_outdoor({mode=.Bake,builder=&again},w,cell))
			testing.expect(t,slice.equal(b.vertices[:],again.vertices[:]) && slice.equal(b.lines[:],again.lines[:]))
			dread_test_mesh(t,&b)
			high:=f32(0);bounded:=true
			for v in b.vertices {
				bounded=bounded && v.position.x>=f32(cell.x) && v.position.x<=f32(cell.x+1)
				bounded=bounded && v.position.z>=f32(cell.y) && v.position.z<=f32(cell.y+1)
				bounded=bounded && v.position.y>=0 && v.position.y<3.2
				high=max(high,v.position.y)
			}
			testing.expect(t,bounded,"decorative vegetation and graves stay inside their blocked cell")
			testing.expect(t,len(b.vertices)<=900 && len(b.lines)<=1)
			if high<1.9 {short+=1} else {tall+=1}
		}
		testing.expect(t,short>5 && tall>5,"each biome has both tall and low outdoor forms")
	}
	// A cone apex collapses the highest ring to one point. The jungle tree
	// instead keeps a wide, flat upper crown in every deterministic variant.
	w.biome=.Jungle;p,_:=dread_palette(w)
	for h in u32(0)..<65 {
		clear(&b.vertices);clear(&b.lines)
		dread_jungle_tree({mode=.Bake,builder=&b},{},h,p)
		dread_test_mesh(t,&b)
		high:=f32(0);for v in b.vertices {high=max(high,v.position.y)}
		lo,hi:=rl.Vector2{1,1},rl.Vector2{-1,-1}
		for v in b.vertices {
			if abs(v.position.y-high)>.0001 {continue}
			lo.x=min(lo.x,v.position.x);lo.y=min(lo.y,v.position.z)
			hi.x=max(hi.x,v.position.x);hi.y=max(hi.y,v.position.z)
		}
		testing.expect(t,hi.x-lo.x>.55 && hi.y-lo.y>.55,"jungle treetops are broad flat crowns, never fir-tree apexes")
		testing.expect(t,len(b.vertices)<900)
	}
}

@(test)
test_dread_site_walls_follow_real_collision_and_vertex_budget :: proc(t:^testing.T) {
	w:=new(world.World);defer free(w)
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	for biome in DREAD_TEST_BIOMES {
		data:level.Level;testing.expect(t,world.generate(w,&data,biome,0xD3EAD))
		room:=game.Room{level_data=&data};walls,low_covers:=0,0
		seen:[world.Site_Kind]bool
		for &site in w.sites[:w.site_count] {
			lo,hi:=world.site_bounds(&site)
			for y in lo.y..=hi.y {for x in lo.x..=hi.x {
				cell:=grid.Position{x,y};d:=world.site_cell(&site,cell);tile,ok:=level.tile_at(&data,cell)
				if !ok || tile.kind!=.Wall || !d.inside || (d.fixture && site.active) {continue}
				clear(&b.vertices);clear(&b.lines)
				testing.expect(t,draw_expedition_dread_wall({mode=.Bake,builder=&b},&room,w,&site,cell,d))
				dread_test_mesh(t,&b);walls+=1;seen[site.kind]=true
				bounded:=true
				for v in b.vertices {
					bounded=bounded && v.position.x>=f32(x)-.00001 && v.position.x<=f32(x+1)+.00001
					bounded=bounded && v.position.z>=f32(y)-.00001 && v.position.z<=f32(y+1)+.00001
					bounded=bounded && v.position.y>=0 && v.position.y<2.3
				}
				testing.expect(t,bounded,"facade relief and sandbags cannot enter a walkable neighbour")
				testing.expect(t,len(b.vertices)<=600 && len(b.lines)<=2)
				if expedition_site_wall_height(d)<1.15 {low_covers+=1}
			}}
		}
		level.destroy(&data)
		testing.expect(t,walls>500 && low_covers>10)
		for kind in world.Site_Kind {testing.expect(t,seen[kind],"every POI layout has tested walls")}
	}
}

@(test)
test_dread_all_fixtures_keep_rotated_portals_and_walkable_centres_clear :: proc(t:^testing.T) {
	w:=new(world.World);defer free(w)
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	for biome in DREAD_TEST_BIOMES {w.biome=biome
		for kind in world.Site_Kind {for orientation in u8(0)..<4 {
			site:=world.Site{kind=kind,position={32,32},orientation=orientation,active=true,layout_version=world.SITE_LAYOUT_VERSION}
			clear(&b.vertices);clear(&b.lines)
			testing.expect(t,draw_expedition_dread_fixture({mode=.Bake,builder=&b},w,&site))
			dread_test_mesh(t,&b)
			testing.expect(t,len(b.vertices)<=1000 && len(b.lines)<=4)
			bounded:=true
			for v in b.vertices {
				if kind==.Trial || kind==.Tunnel {bounded=bounded && v.position.y<=.026;continue}
				// Only the overhead boss lintel bridges the walkable opening.
				// Its rotated support columns must match the actual layout.
				if kind==.Boss && v.position.y>=3.22 {continue}
				cell:=grid.Position{int(math.floor(v.position.x)),int(math.floor(v.position.z))}
				d:=world.site_cell(&site,cell);bounded=bounded && d.fixture && d.wall
			}
			testing.expect(t,bounded,"solid fixture geometry belongs to blocked cells in every orientation")
		}}
	}
}

@(test)
test_dread_poi_functions_have_distinct_silhouettes_beyond_palette :: proc(t:^testing.T) {
	w:=new(world.World);defer free(w)
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	for biome in DREAD_TEST_BIOMES {w.biome=biome
		shapes:[world.Site_Kind][]rl.Vector3
		for kind in world.Site_Kind {
			site:=world.Site{kind=kind,position={32,32},active=true,layout_version=world.SITE_LAYOUT_VERSION}
			clear(&b.vertices);clear(&b.lines)
			testing.expect(t,draw_expedition_dread_fixture({mode=.Bake,builder=&b},w,&site))
			shapes[kind]=make([]rl.Vector3,len(b.vertices))
			for v,i in b.vertices {shapes[kind][i]=v.position}
		}
		for kind in world.Site_Kind {for other in world.Site_Kind {
			if kind>=other {continue}
			testing.expect(t,!slice.equal(shapes[kind],shapes[other]),"radio, archive, memorial and other POIs cannot be recoloured duplicates")
		}}
		for shape in shapes {delete(shape)}
	}
}

@(test)
test_dread_gate_beams_leave_walking_clearance_at_all_orientations :: proc(t:^testing.T) {
	w:=new(world.World);defer free(w)
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	for biome in DREAD_TEST_BIOMES {w.biome=biome
		for orientation in 0..<4 {
			yaw:=f32(orientation)*math.PI/2;base:=rl.Vector3{32.5,1.88,32.5}
			a,bp:=cyber_point(base,{-3,0,0},yaw),cyber_point(base,{3,0,0},yaw)
			clear(&b.vertices);clear(&b.lines)
			testing.expect(t,draw_expedition_dread_gate({mode=.Bake,builder=&b},w,a,bp))
			dread_test_mesh(t,&b);bounded:=true
			for v in b.vertices {
				local:=cyber_point({},v.position-base,-yaw)
				bounded=bounded && abs(local.x)<3.5 && abs(local.z)<.5 && local.y>=-.25 && local.y<.9
			}
			testing.expect(t,bounded,"lintels and hanging lights stay above the passage")
			testing.expect(t,len(b.vertices)<400 && len(b.lines)<=2)
		}
	}
}

@(test)
test_dread_cached_lines_match_live_light_collection_and_ignore_cosmetic_state :: proc(t:^testing.T) {
	w:=new(world.World);defer free(w)
	b,again:Expedition_Geometry_Builder
	defer {delete(b.vertices);delete(b.lines);delete(again.vertices);delete(again.lines)}
	for biome in DREAD_TEST_BIOMES {w.biome=biome
		for kind in world.Site_Kind {for state in ([2]world.Site_State{.Discovered,.Resolved}) {
			site:=world.Site{kind=kind,state=state,position={32,32},orientation=1,active=true,secret=state==.Resolved,layout_version=world.SITE_LAYOUT_VERSION}
			clear(&b.vertices);clear(&b.lines);clear(&again.vertices);clear(&again.lines)
			testing.expect(t,draw_expedition_dread_fixture({mode=.Bake,builder=&b},w,&site))
			w.clock+=.1;w.seed+=17;w.boss_defeated=!w.boss_defeated;site.wave+=1
			testing.expect(t,draw_expedition_dread_fixture({mode=.Bake,builder=&again},w,&site))
			testing.expect(t,slice.equal(b.vertices[:],again.vertices[:]) && slice.equal(b.lines[:],again.lines[:]))
			expected:=Expedition_Edges{light_focus={32.5,1,32.5}};actual:=expected
			for line in b.lines {expedition_collect_edge(&expected,line.a,line.b,line.color)}
			testing.expect(t,draw_expedition_dread_fixture({mode=.Collect,edges=&actual},w,&site))
			testing.expect_value(t,actual.emitter_count,expected.emitter_count)
			testing.expect(t,slice.equal(actual.emitters[:actual.emitter_count],expected.emitters[:expected.emitter_count]))
			testing.expect(t,slice.equal(actual.emitter_distances[:actual.emitter_count],expected.emitter_distances[:expected.emitter_count]))
		}}
	}
}

@(test)
test_dread_dispatch_declines_other_biomes_without_geometry_or_gpu :: proc(t:^testing.T) {
	w:=new(world.World);defer free(w)
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	pass:=Ink_Pass{mode=.Bake,builder=&b}
	for biome in campaign.Biome {
		if biome==.Jungle || biome==.Vietnam || biome==.Gothic {continue}
		w.biome=biome
		testing.expect(t,!draw_expedition_dread_outdoor(pass,w,{0,0}))
		testing.expect(t,!draw_expedition_dread_wall(pass,nil,w,nil,{0,0},{}))
		testing.expect(t,!draw_expedition_dread_gate(pass,w,{0,2,0},{3,2,0}))
		testing.expect(t,!draw_expedition_dread_fixture(pass,w,nil))
	}
	testing.expect(t,!draw_expedition_dread_outdoor(pass,nil,{0,0}))
	testing.expect(t,len(b.vertices)==0 && len(b.lines)==0)
}
