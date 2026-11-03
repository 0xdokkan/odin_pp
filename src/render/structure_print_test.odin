package render

import "core:testing"
import "core:math"
import rl "vendor:raylib"
import level "../level"
import game "../game"

@(test)
test_building_print_sheets_join_without_internal_faces_or_changed_footprint :: proc(t:^testing.T) {
	plan:=level.Plan{width=2,height=1}
	plan.cells[0]=.Wall;plan.cells[1]=.Wall
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	for x in 0..<2 {structure_print_cell({mode=.Bake,builder=&b},&plan,x,0,{f32(x)+.5,0,.5},2,false,CYBER_CAP,CYBER_CREAM)}
	testing.expect_value(t,len(b.vertices),288)
	for v in b.vertices {
		testing.expect(t,v.position.x>=0 && v.position.x<=2 && v.position.z>=0 && v.position.z<=1 && v.position.y>=0 && v.position.y<=2)
		testing.expect(t,!(v.position.x==1 && abs(v.normal.x)>.9),"Joined cells must not contain duplicate internal faces")
		testing.expect(t,(v.print_uv.x>=4 && v.print_uv.x<=5) || (v.print_uv.x>=0 && v.print_uv.x<=1))
	}
	clear(&b.vertices)
	plan.cells[0]=.Floor;plan.cells[1]=.Floor
	for x in 0..<2 {structure_print_cell({mode=.Bake,builder=&b},&plan,x,0,{f32(x)+.5,2,.5},STRUCTURE_ROOF_THICKNESS,true,CYBER_CAP,CYBER_CREAM)}
	testing.expect_value(t,len(b.vertices),48)
	for v in b.vertices {
		if v.normal.y>.9 {testing.expect(t,v.print_uv.x>=8 && v.print_uv.x<=9)}
		testing.expect(t,v.position.y>=2 && v.position.y<=2+STRUCTURE_ROOF_THICKNESS)
	}
}

// Test the actual authored vertices in every supported transform. A drawer
// or shelf at the centre of a free cell would look like a new obstacle even
// though the simulation still lets the robot walk through it.
@(test)
test_cyber_building_furniture_stays_on_real_walls_and_preserves_free_corridor :: proc(t:^testing.T) {
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	for id in ([2]level.Structure_Id{.Hut,.Cottage}) {
		for rotation in 0..<4 {for mirror in ([2]bool{false,true}) {
			placed:=level.Placed_Structure{id=id,origin={x=20,y=20},rotation=u8(rotation),mirror=mirror}
			frame:=cyber_building_frame(placed);plan:=level.placed_plan(placed)
			clear(&b.vertices)
			draw_cyber_building_print({mode=.Bake,builder=&b},placed,false)
			testing.expect(t,len(b.vertices)>300,"The cutaway must retain its furnished wall illustration")
			testing.expect(t,len(b.vertices)<1800,"Immediate envelope geometry has a fixed bounded batch")
			for v in b.vertices {
				x,z:=v.position.x-20,v.position.z-20
				testing.expect(t,x>=-.04 && x<=f32(plan.width)+.04 && z>=-.04 && z<=f32(plan.height)+.04)
				testing.expect(t,v.position.y>=0 && v.position.y<=DIORAMA_WALL_HEIGHT,"No roof remnants survive the inside cutaway")
				testing.expect(t,abs(rl.Vector3LengthSqr(v.normal)-1)<.001)
				if v.position.y<.04 {continue} // Printed floor marks, never a raised carpet or stand.
				wall_distance:=f32(100)
				for y in 0..<plan.height {for px in 0..<plan.width {
					if level.plan_at(&plan,px,y)!=.Wall {continue}
					dx:=max(f32(px)-x,0,x-f32(px+1));dz:=max(f32(y)-z,0,z-f32(y+1))
					wall_distance=min(wall_distance,math.sqrt(dx*dx+dz*dz))
				}}
				testing.expect(t,wall_distance<.04,"Furniture must be printed on occupied wall faces, not placed in the corridor")
			}
			// The canonical front door maps into the transformed plan itself.
			door:=cyber_building_point(frame,{2.5,0,frame.depth-.5})
			testing.expect_value(t,level.plan_at(&plan,int(math.floor(door.x))-20,int(math.floor(door.z))-20),level.Plan_Cell.Door)
		}}
	}
}

@(private="file")
cyber_building_test_above :: proc(point:rl.Vector2,vertices:[]Expedition_Baked_Vertex)->bool {
	for i:=0;i<len(vertices);i+=3 {
		a,b,c:=vertices[i].position,vertices[i+1].position,vertices[i+2].position
		if a.y<=DIORAMA_WALL_HEIGHT || b.y<=DIORAMA_WALL_HEIGHT || c.y<=DIORAMA_WALL_HEIGHT {continue}
		// Barycentric projection: side faces have zero area and cannot roof
		// over a cell; a folded top face must actually cover the test point.
		den:=(b.z-c.z)*(a.x-c.x)+(c.x-b.x)*(a.z-c.z)
		if abs(den)<.00001 {continue}
		u:=((b.z-c.z)*(point.x-c.x)+(c.x-b.x)*(point.y-c.z))/den
		v:=((c.z-a.z)*(point.x-c.x)+(a.x-c.x)*(point.y-c.z))/den
		if u>=-.0001 && v>=-.0001 && u+v<=1.0001 {return true}
	}
	return false
}

@(test)
test_cyber_folded_roof_matches_actual_plan_and_disappears_inside :: proc(t:^testing.T) {
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	for id in ([2]level.Structure_Id{.Hut,.Cottage}) {
		for rotation in 0..<4 {for mirror in ([2]bool{false,true}) {
			placed:=level.Placed_Structure{id=id,origin={x=20,y=20},rotation=u8(rotation),mirror=mirror}
			frame:=cyber_building_frame(placed);plan:=level.placed_plan(placed)
			clear(&b.vertices)
			draw_cyber_building_roof({mode=.Bake,builder=&b},frame)
			low,high:=f32(100),f32(-100)
			for v in b.vertices {
				testing.expect(t,v.position.x>=20 && v.position.x<=20+f32(plan.width) && v.position.z>=20 && v.position.z<=20+f32(plan.height),"The folded roof cannot overhang a new free cell")
				low,high=min(low,v.position.y),max(high,v.position.y)
			}
			testing.expect(t,high-low>.5,"The shelter has a folded shoulder profile rather than another flat slab")
			for y in 0..<plan.height {for x in 0..<plan.width {
				covered:=cyber_building_test_above({20+f32(x)+.5,20+f32(y)+.5},b.vertices[:])
				cell:=level.plan_at(&plan,x,y)
				testing.expect(t,covered==(cell!=.Door && cell!=.Outside),"The real door remains open to the sky")
			}}
			data:=level.Level{}
			append(&data.structures,placed);append(&data.structure_plans,plan)
			defer {delete(data.structures);delete(data.structure_plans)}
			inside:=cyber_building_point(frame,{2.5,0,1.5})
			visibility:=game.structure_visibility(&data,0,{inside.x,inside.z})
			testing.expect(t,visibility.inside && !visibility.roof && visibility.opacity==1)
			clear(&b.vertices)
			draw_cyber_building_print({mode=.Bake,builder=&b},placed,visibility.roof)
			for v in b.vertices {testing.expect(t,v.position.y<=DIORAMA_WALL_HEIGHT,"Inside must not retain a floating cornice or vent")}
		}}
	}
}
