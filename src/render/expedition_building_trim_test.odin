package render

import "core:fmt"
import "core:testing"
import campaign "../campaign"
import level "../level"
import rl "vendor:raylib"

@(test)
test_expedition_building_trim_keeps_doors_and_inside_roof_cut_across_transforms :: proc(t:^testing.T) {
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	for biome in campaign.Biome {for id in ([3]level.Structure_Id{.Hut,.Cottage,.Temple}) {
		for rotation in 0..<4 {for mirror in ([2]bool{false,true}) {
			placed:=level.Placed_Structure{id=id,origin={x=7,y=7},rotation=u8(rotation),mirror=mirror}
			plan:=level.placed_plan(placed);data:=level.Level{}
			append(&data.structures,placed);append(&data.structure_plans,plan)
			clear(&b.vertices);clear(&b.lines)
			draw_expedition_envelope_solids({mode=.Bake,builder=&b},&data,0,false,biome)
			valid:=true
			for v in b.vertices {
				p:=v.position-rl.Vector3{7,0,7}
				valid=valid && p.y>=0 && p.y<=DIORAMA_WALL_HEIGHT && abs(rl.Vector3LengthSqr(v.normal)-1)<.001
				// Dedicated illustrations project at most .04 beyond their wall.
				distance:=f32(100)
				for y in 0..<plan.height {for x in 0..<plan.width {
					cell:=level.plan_at(&plan,x,y);if cell!=.Wall && cell!=.Fence {continue}
					dx:=max(f32(x)-p.x,0,p.x-f32(x+1));dz:=max(f32(y)-p.z,0,p.z-f32(y+1))
					distance=min(distance,dx*dx+dz*dz)
				}}
				if p.y>.04 {valid=valid && distance<.0016}
			}
			testing.expectf(t,valid,"%v %v rotation%d mirror%v: trim occupies a free cell or remains above the roof cut",biome,id,rotation,mirror)
			delete(data.structures);delete(data.structure_plans)
		}}
	}}
}

@(test)
test_expedition_building_trim_retains_bounded_complete_envelope :: proc(t:^testing.T) {
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	for biome in ([3]campaign.Biome{.Cyber,.West,.Jungle}) {for id in ([3]level.Structure_Id{.Hut,.Cottage,.Temple}) {
		placed:=level.Placed_Structure{id=id};data:=level.Level{}
		append(&data.structures,placed);append(&data.structure_plans,level.placed_plan(placed))
		counts:[2]int
		for roof,i in ([2]bool{false,true}) {
			clear(&b.vertices);clear(&b.lines)
			draw_expedition_envelope_solids({mode=.Bake,builder=&b},&data,0,roof,biome)
			counts[i]=len(b.vertices)
			testing.expect(t,len(b.vertices)<6000,"Whole envelope remains bounded separately from its dedicated print's <1800 budget")
		}
		fmt.printf("BUILDING ENVELOPE %v %v inside=%d outside=%d vertices\n",biome,id,counts[0],counts[1])
		delete(data.structures);delete(data.structure_plans)
	}}
}
