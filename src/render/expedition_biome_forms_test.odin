package render

import "core:testing"
import rl "vendor:raylib"
import campaign "../campaign"

// Silhouette strokes and emitters have different costs and semantics. Keep
// the earlier sparse emitter budgets while separately bounding dark ink.
@(private)
biome_test_light_lines :: proc(lines:[]Expedition_Baked_Line)->(count:int) {
	for line in lines {if max(line.color.r,max(line.color.g,line.color.b))>=72 {count+=1}}
	return
}

@(test)
test_biome_workstations_stay_in_cell_and_ink_never_emits :: proc(t:^testing.T) {
	b:Expedition_Geometry_Builder
	defer {delete(b.vertices);delete(b.lines)}
	for biome in campaign.Biome {
		if biome==.Cyber || biome==.Count {continue}
		for orientation in 0..<4 {for column in 0..<3 {
			clear(&b.vertices);clear(&b.lines)
			yaw:=f32(orientation)*1.570796327
			draw_biome_workstation({mode=.Bake,builder=&b},{},yaw,biome,.756,column)
			testing.expect(t,len(b.vertices)>0 && len(b.vertices)<=600)
			for vertex in b.vertices {
				testing.expect(t,abs(vertex.position.x)<=.5001 && abs(vertex.position.z)<=.5001 && vertex.position.y>=0)
			}
			// The edge collector used by HDR accepts the original instruments,
			// while the extra illustrated outlines add no invented light.
			edges:=Expedition_Edges{}
			for line in b.lines {
				if max(line.color.r,max(line.color.g,line.color.b))>=72 {continue}
				expedition_collect_edge(&edges,line.a,line.b,line.color)
			}
			testing.expect_value(t,edges.emitter_count,0)
			for i:=0;i<len(b.vertices);i+=3 {
				a,c,d:=b.vertices[i],b.vertices[i+1],b.vertices[i+2]
				cross:=rl.Vector3CrossProduct(c.position-a.position,d.position-a.position)
				testing.expect(t,rl.Vector3DotProduct(cross,a.normal)>0)
			}
		}}
	}
}

@(test)
test_biome_pigment_two_sides_and_top_are_opaque_wound_and_nonemissive :: proc(t:^testing.T) {
	b:Expedition_Geometry_Builder
	defer {delete(b.vertices);delete(b.lines)}
	pigment:=rl.Color{200,150,100,255}
	for reversed in ([2]bool{false,true}) {
		shape:=[5]rl.Vector2{{-.2,0},{-.2,.3},{0,.4},{.2,.3},{.2,0}}
		if reversed {for i in 0..<2 {shape[i],shape[4-i]=shape[4-i],shape[i]}}
		clear(&b.vertices);clear(&b.lines)
		biome_print_face({mode=.Bake,builder=&b},{},shape[:],0,.6,pigment)
		testing.expect_value(t,len(b.vertices),18)
		for v in b.vertices {
			testing.expect(t,abs(abs(v.position.z)-.306)<.000001 && v.color.a==255)
			testing.expect(t,v.normal.z*v.position.z>0)
		}
		clear(&b.vertices)
		biome_print_top({mode=.Bake,builder=&b},{},shape[:],0,.7,pigment)
		testing.expect_value(t,len(b.vertices),9)
		for v in b.vertices {testing.expect(t,abs(v.position.y-.706)<.000001 && v.normal.y>.99)}
		testing.expect_value(t,len(b.lines),0)
		edges:=Expedition_Edges{}
		biome_print_face({mode=.Collect,edges=&edges},{},shape[:],0,.6,pigment)
		biome_print_top({mode=.Collect,edges=&edges},{},shape[:],0,.7,pigment)
		testing.expect_value(t,edges.emitter_count,0)
	}
}
