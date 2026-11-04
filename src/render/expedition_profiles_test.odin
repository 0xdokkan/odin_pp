package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"

@(test)
test_print_profile_preserves_concave_notch_area_and_winding :: proc(t:^testing.T) {
	// A U-shaped sheet: a triangle fan would incorrectly cover its open bay.
	p:=[8]rl.Vector2{{0,0},{0,3},{1,3},{1,1},{2,1},{2,3},{3,3},{3,0}}
	indices,count:=ink_profile_triangles(p[:])
	testing.expect_value(t,count,(len(p)-2)*3)
	area:=f32(0)
	for i:=0;i<count;i+=3 {
		a,b,c:=p[indices[i]],p[indices[i+1]],p[indices[i+2]]
		cross:=ink_profile_cross(a,b,c)
		testing.expect(t,cross<0);area-=cross*.5
		center:=(a+b+c)/3
		testing.expect(t,!(center.x>1 && center.x<2 && center.y>1))
	}
	testing.expect(t,abs(area-7)<.00001)
}

@(test)
test_profile_extrusion_respects_lift_and_cardinal_orientation :: proc(t:^testing.T) {
	p:=[6]rl.Vector2{{-.4,0},{-.4,.7},{-.2,1},{.25,.9},{.4,.7},{.4,0}}
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	for yaw in ([4]f32{0,math.PI/2,math.PI,3*math.PI/2}) {
		clear(&b.vertices);clear(&b.lines)
		ink_profile({mode=.Bake,builder=&b,lift=2},{3,0,4},p[:],{1,1.5},.12,yaw,CYBER_CREAM,CYBER_BODY,EXPEDITION_PAPER_INK)
		cyber_test_mesh(t,&b)
		grounded:=false
		for v in b.vertices {
			testing.expect(t,abs(v.position.x-3)<=.401 && abs(v.position.z-4)<=.401)
			testing.expect(t,v.position.y>=2 && v.position.y<=3.5)
			if v.position.y==2 {grounded=true}
		}
		testing.expect(t,grounded)
		testing.expect_value(t,len(b.lines),len(p))
	}
}

@(test)
test_profile_rejects_reversed_outline_without_partial_geometry :: proc(t:^testing.T) {
	p:=[4]rl.Vector2{{0,0},{1,0},{1,1},{0,1}}
	_,count:=ink_profile_triangles(p[:]);testing.expect_value(t,count,0)
	_,count=ink_profile_triangles(p[:3]);testing.expect_value(t,count,0)
	line:=[3]rl.Vector2{{0,0},{1,0},{2,0}}
	_,count=ink_profile_triangles(line[:]);testing.expect_value(t,count,0)
}
