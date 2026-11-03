package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"
import level "../level"
import game "../game"

@(test)
test_west_building_furniture_remains_on_walls_in_every_transform :: proc(t:^testing.T) {
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	for id in ([2]level.Structure_Id{.Hut,.Cottage}) {
		for rotation in 0..<4 {for mirror in ([2]bool{false,true}) {
			placed:=level.Placed_Structure{id=id,origin={x=20,y=20},rotation=u8(rotation),mirror=mirror}
			plan:=level.placed_plan(placed)
			clear(&b.vertices);draw_west_building_print({mode=.Bake,builder=&b},placed,false)
			testing.expect(t,len(b.vertices)>250 && len(b.vertices)<1800)
			for v in b.vertices {
				x,z:=v.position.x-20,v.position.z-20
				testing.expect(t,x>=-.04 && x<=f32(plan.width)+.04 && z>=-.04 && z<=f32(plan.height)+.04)
				testing.expect(t,v.position.y>=0 && v.position.y<=DIORAMA_WALL_HEIGHT)
				testing.expect(t,abs(rl.Vector3LengthSqr(v.normal)-1)<.001)
				distance:=f32(100)
				for y in 0..<plan.height {for px in 0..<plan.width {
					if level.plan_at(&plan,px,y)!=.Wall {continue}
					dx:=max(f32(px)-x,0,x-f32(px+1));dz:=max(f32(y)-z,0,z-f32(y+1))
					distance=min(distance,math.sqrt(dx*dx+dz*dz))
				}}
				testing.expect(t,distance<.04,"The saw, shelves and benches must stay on walls, never occupy the free interior")
			}
		}}
	}
}

// The native north-facing hut exposed two undecorated inner walls. Require
// useful painted area on all four inward faces, so furniture remains visible
// when the building rotates or the foreground wall hides the rear bench.
@(test)
test_west_interior_has_readable_illustration_from_every_wall_direction :: proc(t:^testing.T) {
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	for id in ([2]level.Structure_Id{.Hut,.Cottage}) {
		frame:=cyber_building_frame({id=id})
		clear(&b.vertices);draw_west_building_interior({mode=.Bake,builder=&b},frame)
		areas:[4]f32
		for i:=0;i<len(b.vertices);i+=3 {
			a,bv,c:=b.vertices[i],b.vertices[i+1],b.vertices[i+2]
			area:=rl.Vector3Length(rl.Vector3CrossProduct(bv.position-a.position,c.position-a.position))*.5
			for direction,side in ([4]rl.Vector3{{1,0,0},{-1,0,0},{0,0,1},{0,0,-1}}) {
				if rl.Vector3DotProduct(a.normal,direction)>.99 {areas[side]+=area}
			}
		}
		for area in areas {testing.expect(t,area>.25,"Each inner wall needs a readable tool, stock or furniture illustration")}
		clear(&b.vertices);draw_west_building_print({mode=.Bake,builder=&b},frame.placed,true)
		testing.expect(t,len(b.vertices)<1800,"The complete hut or cottage must fit its reserved draw batch")
	}
}

@(private)
west_building_roof_covers :: proc(p:rl.Vector2,vertices:[]Expedition_Baked_Vertex)->bool {
	for i:=0;i<len(vertices);i+=3 {
		a,b,c:=vertices[i].position,vertices[i+1].position,vertices[i+2].position
		if a.y<=DIORAMA_WALL_HEIGHT || b.y<=DIORAMA_WALL_HEIGHT || c.y<=DIORAMA_WALL_HEIGHT {continue}
		den:=(b.z-c.z)*(a.x-c.x)+(c.x-b.x)*(a.z-c.z)
		if abs(den)<.00001 {continue}
		u:=((b.z-c.z)*(p.x-c.x)+(c.x-b.x)*(p.y-c.z))/den
		v:=((c.z-a.z)*(p.x-c.x)+(a.x-c.x)*(p.y-c.z))/den
		if u>=-.0001 && v>=-.0001 && u+v<=1.0001 {return true}
	}
	return false
}

@(test)
test_west_gabled_roof_retains_exact_plan_and_existing_inside_visibility :: proc(t:^testing.T) {
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	for id in ([2]level.Structure_Id{.Hut,.Cottage}) {
		for rotation in 0..<4 {for mirror in ([2]bool{false,true}) {
			placed:=level.Placed_Structure{id=id,origin={x=20,y=20},rotation=u8(rotation),mirror=mirror}
			frame:=cyber_building_frame(placed);plan:=level.placed_plan(placed)
			clear(&b.vertices);draw_west_building_roof({mode=.Bake,builder=&b},frame)
			lo,hi:=f32(100),f32(-100)
			for v in b.vertices {
				testing.expect(t,v.position.x>=20 && v.position.x<=20+f32(plan.width) && v.position.z>=20 && v.position.z<=20+f32(plan.height))
				lo,hi=min(lo,v.position.y),max(hi,v.position.y)
			}
			testing.expect(t,hi-lo>.75,"The West roof must retain its full pitched silhouette")
			for y in 0..<plan.height {for x in 0..<plan.width {
				covered:=west_building_roof_covers({20+f32(x)+.5,20+f32(y)+.5},b.vertices[:])
				cell:=level.plan_at(&plan,x,y)
				testing.expect(t,covered==(cell!=.Door && cell!=.Outside),"No roof paint or gable may bridge the true doorway")
			}}
			data:=level.Level{};append(&data.structures,placed);append(&data.structure_plans,plan)
			defer {delete(data.structures);delete(data.structure_plans)}
			inside:=cyber_building_point(frame,{2.5,0,1.5})
			visibility:=game.structure_visibility(&data,0,{inside.x,inside.z})
			testing.expect(t,visibility.inside && !visibility.roof)
			clear(&b.vertices);draw_west_building_print({mode=.Bake,builder=&b},placed,visibility.roof)
			for v in b.vertices {testing.expect(t,v.position.y<=DIORAMA_WALL_HEIGHT)}
		}}
	}
}
