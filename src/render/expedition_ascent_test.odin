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
ASCENT_TEST_BIOMES :: [5]campaign.Biome{.City,.Snow,.Sky,.Space,.Secret}

@(private)
ascent_test_mesh :: proc(t:^testing.T,b:^Expedition_Geometry_Builder) {
	valid:=len(b.vertices)>0 && len(b.vertices)%3==0
	for v in b.vertices {
		for component in v.position {valid=valid && !math.is_nan(component) && !math.is_inf(component)}
		valid=valid && abs(rl.Vector3Length(v.normal)-1)<.001 && v.color.a==255
	}
	for i:=0;i+2<len(b.vertices);i+=3 {
		a,c,d:=b.vertices[i],b.vertices[i+1],b.vertices[i+2]
		cross:=rl.Vector3CrossProduct(c.position-a.position,d.position-a.position)
		valid=valid && rl.Vector3LengthSqr(cross)>.0000000001 && rl.Vector3DotProduct(cross,a.normal)>0
	}
	for line in b.lines {
		for point in ([2]rl.Vector3{line.a,line.b}) {for component in point {valid=valid && !math.is_nan(component) && !math.is_inf(component)}}
		valid=valid && line.color.a>0 && rl.Vector3DistanceSqr(line.a,line.b)>.000001
	}
	testing.expect(t,valid,"Non-finite, degenerate or inward-facing ascent mesh")
}

@(private)
ascent_test_cell_contains :: proc(cell:grid.Position,p:rl.Vector3)->bool {
	return p.x>=f32(cell.x)-.00001 && p.x<=f32(cell.x+1)+.00001 &&
	       p.z>=f32(cell.y)-.00001 && p.z<=f32(cell.y+1)+.00001 && p.y>=0
}

@(test)
test_ascent_outdoor_five_biomes_are_deterministic_bounded_and_economical :: proc(t:^testing.T) {
	w:=new(world.World);defer free(w)
	b,again:Expedition_Geometry_Builder
	defer {delete(b.vertices);delete(b.lines);delete(again.vertices);delete(again.lines)}
	pass,other:=Ink_Pass{mode=.Bake,builder=&b},Ink_Pass{mode=.Bake,builder=&again}
	for biome in ASCENT_TEST_BIOMES {for i in 0..<64 {
		cell:=grid.Position{i*7%61-30,i*13%59-29};w.biome=biome
		clear(&b.vertices);clear(&b.lines);clear(&again.vertices);clear(&again.lines)
		testing.expect(t,draw_expedition_ascent_outdoor(pass,w,cell))
		w.clock+=23;w.seed+=711
		testing.expect(t,draw_expedition_ascent_outdoor(other,w,cell))
		testing.expect(t,slice.equal(b.vertices[:],again.vertices[:]) && slice.equal(b.lines[:],again.lines[:]))
		ascent_test_mesh(t,&b)
		contained:=true
		for v in b.vertices {contained=contained && ascent_test_cell_contains(cell,v.position) && v.position.y<4}
		for line in b.lines {contained=contained && ascent_test_cell_contains(cell,line.a) && ascent_test_cell_contains(cell,line.b)}
		testing.expect(t,contained,"Outdoor geometry extends beyond its real blocked cell")
		testing.expect(t,len(b.vertices)<=900 && len(b.lines)<=12)
	}}
}

@(test)
test_ascent_site_walls_all_kinds_and_rotations_follow_collision_and_budget :: proc(t:^testing.T) {
	w:=new(world.World);defer free(w)
	data,ok:=level.create(80,80,{.Floor});testing.expect(t,ok);defer level.destroy(&data)
	room:=game.Room{level_data=&data}
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	pass:=Ink_Pass{mode=.Bake,builder=&b};count:=0
	for kind in world.Site_Kind {for orientation in u8(0)..<4 {
		site:=world.Site{kind=kind,position={40,40},orientation=orientation,active=true,layout_version=world.SITE_LAYOUT_VERSION}
		lo,hi:=world.site_bounds(&site)
		for y in 20..<61 {for x in 20..<61 {_=level.set_tile(&data,{x,y},{.Floor})}}
		for y in lo.y..=hi.y {for x in lo.x..=hi.x {
			p:=grid.Position{x,y};if world.site_cell(&site,p).wall {_=level.set_tile(&data,p,{.Wall})}
		}}
		for biome in ASCENT_TEST_BIOMES {
			w.biome=biome
			for y in lo.y..=hi.y {for x in lo.x..=hi.x {
				cell:=grid.Position{x,y};design:=world.site_cell(&site,cell)
				if !design.wall || design.fixture {continue}
				clear(&b.vertices);clear(&b.lines)
				testing.expect(t,draw_expedition_ascent_wall(pass,&room,w,&site,cell,design))
				ascent_test_mesh(t,&b);count+=1
				contained:=true
				for v in b.vertices {contained=contained && ascent_test_cell_contains(cell,v.position)}
				for line in b.lines {contained=contained && ascent_test_cell_contains(cell,line.a) && ascent_test_cell_contains(cell,line.b)}
				testing.expect(t,contained,"Site wall enters an adjacent gameplay cell")
				testing.expect(t,len(b.vertices)<=600 && len(b.lines)<=12)
			}}
		}
	}}
	testing.expect(t,count>10000)
}

@(test)
test_ascent_fixtures_all_biomes_kinds_rotations_preserve_walkable_space :: proc(t:^testing.T) {
	w:=new(world.World);defer free(w)
	b,again:Expedition_Geometry_Builder
	defer {delete(b.vertices);delete(b.lines);delete(again.vertices);delete(again.lines)}
	pass,other:=Ink_Pass{mode=.Bake,builder=&b},Ink_Pass{mode=.Bake,builder=&again}
	for biome in ASCENT_TEST_BIOMES {for kind in world.Site_Kind {for orientation in u8(0)..<4 {for state in world.Site_State {
		w.biome=biome
		site:=world.Site{kind=kind,state=state,position={32,32},orientation=orientation,active=true,layout_version=world.SITE_LAYOUT_VERSION}
		clear(&b.vertices);clear(&b.lines);clear(&again.vertices);clear(&again.lines)
		testing.expect(t,draw_expedition_ascent_fixture(pass,w,&site))
		w.clock+=7;w.seed+=13
		testing.expect(t,draw_expedition_ascent_fixture(other,w,&site))
		testing.expect(t,slice.equal(b.vertices[:],again.vertices[:]) && slice.equal(b.lines[:],again.lines[:]))
		ascent_test_mesh(t,&b)
		testing.expect(t,len(b.vertices)<=1000 && len(b.lines)<=18)
		contained:=true
		for v in b.vertices {contained=contained && ascent_test_fixture_point(&site,v.position)}
		for line in b.lines {contained=contained && ascent_test_fixture_point(&site,line.a) && ascent_test_fixture_point(&site,line.b)}
		testing.expect(t,contained,"Fixture blocks walkable space or rotated boss opening")
	}}}}
}

@(private)
ascent_test_fixture_point :: proc(site:^world.Site,p:rl.Vector3)->bool {
	if site.kind==.Trial || site.kind==.Tunnel {return p.y<=.026 && ascent_test_cell_contains(site.position,p)}
	if site.kind==.Boss && p.y>=3.24 {return p.y<4.2}
	cell:=grid.Position{int(math.floor(p.x)),int(math.floor(p.z))}
	d:=world.site_cell(site,cell)
	return p.y>=0 && d.fixture && d.wall
}

@(test)
test_ascent_gates_remain_overhead_and_emit_same_cached_light_segments :: proc(t:^testing.T) {
	w:=new(world.World);defer free(w)
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	for biome in ASCENT_TEST_BIOMES {for orientation in 0..<4 {
		w.biome=biome;clear(&b.vertices);clear(&b.lines)
		yaw:=f32(orientation)*math.PI/2;p:=rl.Vector3{32.5,2.1,32.5}
		a,c:=cyber_point(p,{-3,0,0},yaw),cyber_point(p,{3,0,0},yaw)
		testing.expect(t,draw_expedition_ascent_gate({mode=.Bake,builder=&b},w,a,c))
		ascent_test_mesh(t,&b)
		for v in b.vertices {
			local:=cyber_point({},v.position-p,-yaw)
			testing.expect(t,abs(local.x)<=3.5 && abs(local.z)<=.5 && local.y>=0 && local.y<=.5)
		}
		testing.expect(t,len(b.vertices)<=180 && len(b.lines)>0)
		edges:=Expedition_Edges{light_focus=p}
		testing.expect(t,draw_expedition_ascent_gate({mode=.Collect,edges=&edges},w,a,c))
		testing.expect_value(t,edges.emitter_count,len(b.lines))
		for emitter in edges.emitters[:edges.emitter_count] {
			found:=false
			for line in b.lines {if emitter.a==line.a && emitter.b==line.b {found=true;break}}
			testing.expect(t,found,"Collect and Bake disagree about luminous geometry")
		}
	}}
}

@(test)
test_ascent_dispatch_leaves_other_biomes_to_their_own_architecture :: proc(t:^testing.T) {
	w:=new(world.World);defer free(w)
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	pass:=Ink_Pass{mode=.Bake,builder=&b};site:=world.Site{}
	for biome in campaign.Biome {
		_,supported:=ascent_material(biome);if supported {continue}
		w.biome=biome
		testing.expect(t,!draw_expedition_ascent_outdoor(pass,w,{}))
		testing.expect(t,!draw_expedition_ascent_wall(pass,nil,w,&site,{},{}))
		testing.expect(t,!draw_expedition_ascent_gate(pass,w,{},{1,0,0}))
		testing.expect(t,!draw_expedition_ascent_fixture(pass,w,&site))
	}
	testing.expect(t,len(b.vertices)==0 && len(b.lines)==0)
}
