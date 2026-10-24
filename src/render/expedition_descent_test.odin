package render

import "core:fmt"
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
descent_test_mesh_valid :: proc(b:^Expedition_Geometry_Builder)->bool {
	if len(b.vertices)==0 || len(b.vertices)%3!=0 {return false}
	for v in b.vertices {
		for f in v.position {if math.is_nan(f) || math.is_inf(f) {return false}}
		if abs(rl.Vector3Length(v.normal)-1)>.001 || v.color.a!=255 {return false}
	}
	for i:=0;i<len(b.vertices);i+=3 {
		a,b,c:=b.vertices[i],b.vertices[i+1],b.vertices[i+2]
		n:=rl.Vector3CrossProduct(b.position-a.position,c.position-a.position)
		if rl.Vector3LengthSqr(n)<.00000000001 || rl.Vector3DotProduct(n,a.normal)<=0 {return false}
	}
	for l in b.lines {
		if l.color.a==0 || rl.Vector3DistanceSqr(l.a,l.b)<.000001 {return false}
		for p in ([2]rl.Vector3{l.a,l.b}) {for f in p {if math.is_nan(f) || math.is_inf(f) {return false}}}
	}
	return true
}

@(private)
descent_test_in_cell :: proc(p:rl.Vector3,cell:grid.Position)->bool {
	return p.x>=f32(cell.x)-.001 && p.x<=f32(cell.x+1)+.001 && p.z>=f32(cell.y)-.001 && p.z<=f32(cell.y+1)+.001 && p.y>=0
}

@(test)
test_descent_outdoor_is_bounded_static_and_has_sparse_real_emitters :: proc(t:^testing.T) {
	w:=new(world.World);defer free(w)
	a,b:Expedition_Geometry_Builder
	defer {delete(a.vertices);delete(a.lines);delete(b.vertices);delete(b.lines)}
	pass,again:=Ink_Pass{mode=.Bake,builder=&a},Ink_Pass{mode=.Bake,builder=&b}
	for biome in ([3]campaign.Biome{.West,.Egypt,.Inferno}) {
		w.biome=biome
		variants:[61]bool
		for i in 0..<96 {
			cell:=grid.Position{i*13%61,i*17%59}
			clear(&a.vertices);clear(&a.lines);clear(&b.vertices);clear(&b.lines)
			handled:=draw_expedition_descent_outdoor(pass,w,cell)
			w.clock+=19;w.beat+=7;w.seed+=41
			handled_again:=draw_expedition_descent_outdoor(again,w,cell)
			testing.expect(t,handled && handled_again)
			testing.expect(t,slice.equal(a.vertices[:],b.vertices[:]) && slice.equal(a.lines[:],b.lines[:]))
			testing.expect(t,descent_test_mesh_valid(&a),fmt.tprintf("%v outdoor %v",biome,cell))
			inside:=true
			for v in a.vertices {inside=inside && descent_test_in_cell(v.position,cell) && v.position.y<2.8}
			for line in a.lines {inside=inside && descent_test_in_cell(line.a,cell) && descent_test_in_cell(line.b,cell)}
			testing.expect(t,inside)
			testing.expect(t,len(a.vertices)<900 && len(a.lines)<=4)
			variants[len(a.vertices)%61]=true
		}
		count:=0;for present in variants {if present {count+=1}}
		if biome!=.Inferno {testing.expect(t,count>=2)}
	}
	// The dispatcher declines other biomes without appending any geometry.
	w.biome=.Cyber;clear(&a.vertices);clear(&a.lines)
	handled:=draw_expedition_descent_outdoor(pass,w,{2,2})
	testing.expect(t,!handled && len(a.vertices)==0 && len(a.lines)==0)
}

@(test)
test_descent_all_site_walls_fit_blocked_cells_with_finite_outward_normals :: proc(t:^testing.T) {
	w:=new(world.World);defer free(w)
	data,created:=level.create(65,65,{.Floor});testing.expect(t,created);defer level.destroy(&data)
	room:=game.Room{level_data=&data}
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	pass:=Ink_Pass{mode=.Bake,builder=&b}
	for biome in ([3]campaign.Biome{.West,.Egypt,.Inferno}) {for kind in world.Site_Kind {if kind==.Cave {continue};for orientation in u8(0)..<4 {
		w.biome=biome
		site:=world.Site{kind=kind,position={32,32},orientation=orientation,active=true,layout_version=world.SITE_LAYOUT_VERSION}
		for &tile in data.tiles.cells {tile={.Floor}}
		lo,hi:=world.site_bounds(&site)
		for y in lo.y..=hi.y {for x in lo.x..=hi.x {
			cell:=grid.Position{x,y};d:=world.site_cell(&site,cell)
			if d.wall {_=level.set_tile(&data,cell,{.Wall})}
		}}
		walls,peak:=0,0;valid,inside,handled:=true,true,true
		for y in lo.y..=hi.y {for x in lo.x..=hi.x {
			cell:=grid.Position{x,y};d:=world.site_cell(&site,cell)
			if !d.wall || d.fixture {continue}
			clear(&b.vertices);clear(&b.lines)
			handled=draw_expedition_descent_wall(pass,&room,w,&site,cell,d) && handled
			valid=valid && descent_test_mesh_valid(&b);walls+=1;peak=max(peak,len(b.vertices))
			for v in b.vertices {inside=inside && descent_test_in_cell(v.position,cell)}
			for line in b.lines {inside=inside && descent_test_in_cell(line.a,cell) && descent_test_in_cell(line.b,cell)}
		}}
		testing.expect(t,walls>10 && handled && valid && inside && peak<600,
			fmt.tprintf("%v %v rotation%d: walls%d vertices%d valid%v inside%v",biome,kind,orientation,walls,peak,valid,inside))
	}}}
}

@(test)
test_descent_fixtures_match_rotated_layout_and_leave_trial_tunnel_walkable :: proc(t:^testing.T) {
	w:=new(world.World);defer free(w)
	a,b:Expedition_Geometry_Builder;defer {delete(a.vertices);delete(a.lines);delete(b.vertices);delete(b.lines)}
	pass,again:=Ink_Pass{mode=.Bake,builder=&a},Ink_Pass{mode=.Bake,builder=&b}
	for biome in ([3]campaign.Biome{.West,.Egypt,.Inferno}) {for kind in world.Site_Kind {if kind==.Cave {continue};for orientation in u8(0)..<4 {
		w.biome=biome
		site:=world.Site{kind=kind,position={32,32},orientation=orientation,active=true,layout_version=world.SITE_LAYOUT_VERSION}
		clear(&a.vertices);clear(&a.lines);clear(&b.vertices);clear(&b.lines)
		handled:=draw_expedition_descent_fixture(pass,w,&site)
		w.clock+=21;w.beat+=3;w.seed+=13;site.wave+=1;site.seed+=51
		again_handled:=draw_expedition_descent_fixture(again,w,&site)
		testing.expect(t,handled && again_handled && slice.equal(a.vertices[:],b.vertices[:]) && slice.equal(a.lines[:],b.lines[:]))
		testing.expect(t,descent_test_mesh_valid(&a),fmt.tprintf("%v %v rotation%d",biome,kind,orientation))
		inside:=true
		for v in a.vertices {
			if kind==.Trial || kind==.Tunnel {inside=inside && v.position.y<=.025 && descent_test_in_cell(v.position,site.position);continue}
			if kind==.Boss && v.position.y>=3.22 {continue}
			cell:=grid.Position{int(math.floor(v.position.x)),int(math.floor(v.position.z))}
			d:=world.site_cell(&site,cell);inside=inside && d.fixture && d.wall && v.position.y>=0
		}
		testing.expect(t,inside && len(a.vertices)<1500 && len(a.lines)<24,fmt.tprintf("%v %v rotation%d inside%v vertices%d",biome,kind,orientation,inside,len(a.vertices)))
		if kind==.Trial || kind==.Tunnel {for line in a.lines {testing.expect(t,line.a.y<=.025 && line.b.y<=.025)}}
	}}}
}

@(test)
test_descent_gate_clearance_and_collect_match_cached_emissive_geometry :: proc(t:^testing.T) {
	w:=new(world.World);defer free(w)
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	pass:=Ink_Pass{mode=.Bake,builder=&b}
	for biome in ([3]campaign.Biome{.West,.Egypt,.Inferno}) {for kind in world.Site_Kind {if kind==.Cave {continue};for orientation in u8(0)..<4 {
		w.biome=biome
		site:=world.Site{kind=kind,position={32,32},orientation=orientation,active=true,layout_version=world.SITE_LAYOUT_VERSION}
		decor:=world.site_decor_anchors(&site)
		for i:=0;i+1<decor.count;i+=2 {
			a,b:=decor.items[i],decor.items[i+1];if a.kind!=.Gatepost || b.kind!=.Gatepost {break}
			pa:=rl.Vector3{f32(a.position.x)+.5,a.height*.85,f32(a.position.y)+.5}
			pb:=rl.Vector3{f32(b.position.x)+.5,b.height*.85,f32(b.position.y)+.5}
			clear(&pass.builder.vertices);clear(&pass.builder.lines)
			handled:=draw_expedition_descent_gate(pass,w,pa,pb)
			testing.expect(t,handled && descent_test_mesh_valid(pass.builder))
			clearance:=true
			for v in pass.builder.vertices {clearance=clearance && v.position.y>=1.84}
			testing.expect(t,clearance && len(pass.builder.vertices)<600)
		}
		clear(&b.vertices);clear(&b.lines)
		handled:=draw_expedition_descent_fixture(pass,w,&site)
		edges:=Expedition_Edges{light_focus={32.5,1,32.5}}
		collected:=draw_expedition_descent_fixture({mode=.Collect,edges=&edges},w,&site)
		testing.expect(t,handled && collected && edges.emitter_count<=len(b.lines))
		for emitter in edges.emitters[:edges.emitter_count] {
			found:=false
			for line in b.lines {found=found || (line.a==emitter.a && line.b==emitter.b)}
			testing.expect(t,found && rl.Vector3LengthSqr(emitter.radiance)>0)
		}
		if kind!=.Workshop || biome!=.West {testing.expect(t,edges.emitter_count>0)}
	}}}
}

@(test)
test_descent_wall_details_only_occupy_exposed_faces :: proc(t:^testing.T) {
	w:=new(world.World);defer free(w)
	data,created:=level.create(65,65,{.Floor});testing.expect(t,created);defer level.destroy(&data)
	room:=game.Room{level_data=&data}
	site:=world.Site{kind=.Trial,position={32,32},active=true,layout_version=world.SITE_LAYOUT_VERSION}
	cell:=grid.Position{43,36};design:=world.site_cell(&site,cell)
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	pass:=Ink_Pass{mode=.Bake,builder=&b}
	for biome in ([3]campaign.Biome{.West,.Egypt,.Inferno}) {
		w.biome=biome
		for &tile in data.tiles.cells {tile={.Floor}}
		_=level.set_tile(&data,cell,{.Wall})
		clear(&b.vertices);clear(&b.lines)
		handled:=draw_expedition_descent_wall(pass,&room,w,&site,cell,design)
		exposed:=len(b.vertices)
		for offset in ([4]grid.Position{{0,1},{0,-1},{1,0},{-1,0}}) {_=level.set_tile(&data,game.add_position(cell,offset),{.Wall})}
		clear(&b.vertices);clear(&b.lines)
		closed:=draw_expedition_descent_wall(pass,&room,w,&site,cell,design)
		testing.expect(t,handled && closed && len(b.vertices)<exposed && len(b.lines)==0)
	}
}
