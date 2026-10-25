package render

import "core:math"
import "core:slice"
import "core:testing"
import rl "vendor:raylib"
import world "../expedition"
import game "../game"
import grid "../engine/grid"
import level "../level"

@(private)
cyber_test_mesh :: proc(t:^testing.T,b:^Expedition_Geometry_Builder) {
	testing.expect(t,len(b.vertices)>0 && len(b.vertices)%3==0)
	for v in b.vertices {
		for component in v.position {testing.expect(t,!math.is_nan(component) && !math.is_inf(component))}
		testing.expect(t,abs(rl.Vector3Length(v.normal)-1)<.001)
		testing.expect_value(t,v.color.a,u8(255))
	}
	for i:=0;i<len(b.vertices);i+=3 {
		a,c,d:=b.vertices[i],b.vertices[i+1],b.vertices[i+2]
		cross:=rl.Vector3CrossProduct(c.position-a.position,d.position-a.position)
		testing.expect(t,rl.Vector3LengthSqr(cross)>.0000000001)
		testing.expect(t,rl.Vector3DotProduct(cross,a.normal)>0)
	}
	for l in b.lines {testing.expect(t,l.color.a>0 && rl.Vector3DistanceSqr(l.a,l.b)>.000001)}
}

@(test)
test_cyber_outdoor_modules_are_deterministic_bounded_and_selectively_lit :: proc(t:^testing.T) {
	b,again:Expedition_Geometry_Builder
	defer {delete(b.vertices);delete(b.lines);delete(again.vertices);delete(again.lines)}
	pass:=Ink_Pass{mode=.Bake,builder=&b}
	other:=Ink_Pass{mode=.Bake,builder=&again}
	rocks,servers:=0,0
	for i in 0..<96 {
		cell:=grid.Position{x = i*7%61, y = i*13%59}
		clear(&b.vertices);clear(&b.lines);clear(&again.vertices);clear(&again.lines)
		draw_expedition_cyber_outdoor(pass,cell)
		draw_expedition_cyber_outdoor(other,cell)
		testing.expect(t,slice.equal(b.vertices[:],again.vertices[:]) && slice.equal(b.lines[:],again.lines[:]))
		cyber_test_mesh(t,&b)
		for v in b.vertices {
			testing.expect(t,v.position.x>=f32(cell.x) && v.position.x<=f32(cell.x+1))
			testing.expect(t,v.position.z>=f32(cell.y) && v.position.z<=f32(cell.y+1))
			testing.expect(t,v.position.y>=0 && v.position.y<2.8)
		}
		// A few hundred cached vertices, at most five actual luminous marks.
		testing.expect(t,len(b.vertices)<=700 && len(b.lines)<=5)
		if len(b.lines)>1 {servers+=1} else {rocks+=1}
	}
	testing.expect(t,rocks>40 && servers>10)
}

@(test)
test_cyber_links_and_chamfers_keep_outward_normals_at_all_orientations :: proc(t:^testing.T) {
	for yaw in ([4]f32{0,math.PI/2,math.PI,math.PI*1.5}) {
		base:=rl.Vector3{3,2,4}
		ring:=cyber_chamfer_ring(base,{.49,.36},.07,yaw)
		top:=ring;for &point in top {point.y+=1}
		for i in 0..<8 {
			j:=(i+1)%8;n:=ink_face_normal(ring[i],top[j],ring[j])
			testing.expect(t,rl.Vector3DotProduct(n,(ring[i]+ring[j])*.5-base)>0)
		}
		testing.expect(t,ink_face_normal(top[0],top[2],top[1]).y>.99)
	}
	for ends in ([4][2]rl.Vector3{{{0,0,0},{0,1,0}},{{0,0,0},{1,0,0}},{{0,0,0},{0,0,1}},{{-.17,.19,0},{-.12,1.05,0}}}) {
		a,b:=cyber_link_rings(ends[0],ends[1],{.085,.075})
		axis:=rl.Vector3Normalize(ends[1]-ends[0])
		testing.expect(t,rl.Vector3DotProduct(ink_face_normal(b[0],b[2],b[1]),axis)>.999)
		for i in 0..<4 {
			j:=(i+1)%4;n:=ink_face_normal(a[i],b[j],a[j])
			testing.expect(t,rl.Vector3DotProduct(n,(a[i]+a[j])*.5-ends[0])>0)
		}
	}
}

@(test)
test_cyber_arm_has_readable_elbow_height_without_entering_adjacent_cells :: proc(t:^testing.T) {
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	pass:=Ink_Pass{mode=.Bake,builder=&b}
	for yaw in ([4]f32{0,math.PI/2,math.PI,math.PI*1.5}) {for mirror in ([2]f32{-1,1}) {
		clear(&b.vertices);clear(&b.lines)
		cyber_robot_arm(pass,{},yaw,mirror)
		high:=f32(0)
		for v in b.vertices {
			high=max(high,v.position.y)
			testing.expect(t,abs(v.position.x)<.5 && abs(v.position.z)<.5 && v.position.y>=0)
		}
		testing.expect(t,high>=1.45 && high<=1.60)
		testing.expect(t,len(b.vertices)<=450 && len(b.lines)==4)
	}}
}

@(test)
test_cyber_site_walls_and_factory_arms_stay_on_actual_blocked_cells :: proc(t:^testing.T) {
	w:=new(world.World);defer free(w)
	data:level.Level;testing.expect(t,world.generate(w,&data,.Cyber,0xC0FFEE));defer level.destroy(&data)
	room:=game.Room{level_data=&data}
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	pass:=Ink_Pass{mode=.Bake,builder=&b}
	walls,conveyors:=0,0
	for &site in w.sites[:w.site_count] {
		lo,hi:=world.site_bounds(&site)
		for y in lo.y..=hi.y {for x in lo.x..=hi.x {
			cell:=grid.Position{x = x, y = y};d:=world.site_cell(&site,cell);tile,ok:=level.tile_at(&data,cell)
			if !ok || tile.kind!=.Wall || !d.inside || (d.fixture && site.active) {continue}
			clear(&b.vertices);clear(&b.lines)
			draw_expedition_cyber_wall(pass,&room,&site,cell,d)
			cyber_test_mesh(t,&b);walls+=1
			for v in b.vertices {
				testing.expect(t,v.position.x>=f32(x)-.006 && v.position.x<=f32(x+1)+.006)
				testing.expect(t,v.position.z>=f32(y)-.006 && v.position.z<=f32(y+1)+.006)
			}
			testing.expect(t,len(b.vertices)<=1600 && len(b.lines)<=16)
			if site.kind==.Workshop && d.local.x>=5 && d.local.x<=7 && abs(d.local.y)==5 {conveyors+=1;testing.expect(t,len(b.vertices)>400)}
		}}
	}
	testing.expect(t,walls>500 && conveyors==6)
}

@(test)
test_cyber_fixtures_preserve_walkable_centers_and_rotated_boss_opening :: proc(t:^testing.T) {
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	pass:=Ink_Pass{mode=.Bake,builder=&b}
	for kind in world.Site_Kind {if kind==.Cave {continue};for orientation in u8(0)..<4 {
		site:=world.Site{kind=kind,position={x = 32, y = 32},orientation=orientation,active=true,layout_version=world.SITE_LAYOUT_VERSION}
		clear(&b.vertices);clear(&b.lines)
		draw_expedition_cyber_fixture(pass,&site,false)
		cyber_test_mesh(t,&b)
		testing.expect(t,len(b.vertices)<1600 && len(b.lines)<24)
		for v in b.vertices {
			if kind==.Trial || kind==.Tunnel {testing.expect(t,v.position.y<=.026);continue}
			// The boss lintel is overhead; all geometry within actor height
			// must still occupy one of the two real rotated portal supports.
			if kind==.Boss && v.position.y>=3.22 {continue}
			cell:=grid.Position{x = int(math.floor(v.position.x)), y = int(math.floor(v.position.z))}
			d:=world.site_cell(&site,cell)
			testing.expect(t,d.fixture && d.wall)
		}
	}}
}
