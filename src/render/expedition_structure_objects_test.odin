package render

import "core:math"
import "core:slice"
import "core:testing"
import campaign "../campaign"
import world "../expedition"
import game "../game"
import level "../level"
import rl "vendor:raylib"

// A wheel cannot borrow ink_solid's open ground-facing base: once rotated,
// that base is the face visible to the camera. Both ends need outward caps.
@(test)
test_expedition_horizontal_axles_close_both_ends_in_every_transform :: proc(t:^testing.T) {
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	for rotation in 0..<4 {for mirror in ([2]bool{false,true}) {
		frame:=cyber_building_frame({id=.Cart,origin={x=7,y=7},rotation=u8(rotation),mirror=mirror})
		a,c:=rl.Vector3{.97,.19,.075},rl.Vector3{.97,.19,.205}
		pa,pc:=cyber_building_point(frame,a),cyber_building_point(frame,c)
		axis:=rl.Vector3Normalize(pc-pa)
		clear(&b.vertices);object_axle({mode=.Bake,builder=&b},frame,a,c,.18,CYBER_RECESS,CYBER_CREAM)
		caps:[2]int;areas:[2]f32
		for i:=0;i<len(b.vertices);i+=3 {
			v,w,z:=b.vertices[i],b.vertices[i+1],b.vertices[i+2]
			facing:=rl.Vector3DotProduct(v.normal,axis)
			if abs(facing)<.999 {continue}
			end:=0 if facing<0 else 1;plane:=pa if end==0 else pc
			for vertex in ([3]Expedition_Baked_Vertex{v,w,z}) {
				testing.expect(t,abs(rl.Vector3DotProduct(vertex.position-plane,axis))<.00001)
				testing.expect_value(t,vertex.color,CYBER_CREAM)
			}
			cross:=rl.Vector3CrossProduct(w.position-v.position,z.position-v.position)
			testing.expect(t,rl.Vector3DotProduct(cross,v.normal)>0)
			caps[end]+=1;areas[end]+=rl.Vector3Length(cross)*.5
		}
		for count in caps {testing.expect(t,count==6,"Each octagonal end must be closed by six outward triangles")}
		for area in areas {testing.expect(t,abs(area-f32(4*.18*.18*math.sin(math.PI/4)))<.00001)}
	}}
}

// Check the actual occupied cells, not just the bounding rectangle: the
// rotated ruin has holes, and the pen's interior and gate must stay open.
@(private="file")
object_test_on_solid :: proc(plan:^level.Plan,p:rl.Vector3)->bool {
	for y in 0..<plan.height {for x in 0..<plan.width {
		cell:=level.plan_at(plan,x,y);if cell!=.Wall && cell!=.Fence {continue}
		if p.x>=f32(x)-.0001 && p.x<=f32(x+1)+.0001 && p.z>=f32(y)-.0001 && p.z<=f32(y+1)+.0001 {return true}
	}}
	return false
}

@(test)
test_expedition_objects_keep_every_plan_transform_solid_and_low_fences :: proc(t:^testing.T) {
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	for biome in campaign.Biome {for id in ([6]level.Structure_Id{.Cart,.Fountain,.Statue,.Machine,.Ruin,.Pen}) {
		for rotation in 0..<4 {for mirror in ([2]bool{false,true}) {
			if mirror && !level.structure_definition(id).mirror {continue}
			placed:=level.Placed_Structure{id=id,origin={x=7,y=7},rotation=u8(rotation),mirror=mirror}
			plan:=level.placed_plan(placed);data:=level.Level{}
			append(&data.structures,placed);append(&data.structure_plans,plan)
			clear(&b.vertices);clear(&b.lines)
			draw_expedition_structure_object({mode=.Bake,builder=&b},&data,0,biome)
			testing.expectf(t,len(b.vertices)>60 && len(b.vertices)<=3000,"%v %v: vertices %d",biome,id,len(b.vertices))
			valid:=true
			for v in b.vertices {
				p:=v.position-rl.Vector3{7,0,7}
				valid=valid && object_test_on_solid(&plan,p) && p.y>=0 && p.y<2
				valid=valid && abs(rl.Vector3LengthSqr(v.normal)-1)<.0001
				for n in v.position {valid=valid && !math.is_nan(n) && !math.is_inf(n)}
				if id==.Cart || id==.Pen {valid=valid && p.y<=STRUCTURE_FENCE_HEIGHT+.0001}
				if id==.Fountain {valid=valid && p.y<=.4201}
			}
			// Triangle centres catch faces that bridge a free plan cell even
			// when all their corners happen to land on an occupied boundary.
			for i:=0;i<len(b.vertices);i+=3 {
				p:=(b.vertices[i].position+b.vertices[i+1].position+b.vertices[i+2].position)/3-rl.Vector3{7,0,7}
				valid=valid && object_test_on_solid(&plan,p)
			}
			testing.expectf(t,valid,"%v %v rotation%d mirror%v: footprint, fence height or normal changed",biome,id,rotation,mirror)
			anchor:=expedition_structure_anchor(&data,0)
			testing.expect(t,level.plan_at(&plan,anchor.x-7,anchor.y-7)!=.Outside)
			delete(data.structures);delete(data.structure_plans)
		}}
	}}
}

@(test)
test_expedition_object_bake_is_deterministic_and_geometry_revision_tracks_lifecycle :: proc(t:^testing.T) {
	data,ok:=level.create(32,32,{.Floor});testing.expect(t,ok);defer level.destroy(&data)
	w:=new(world.World);defer free(w);w.biome=.Cyber
	room:=game.Room{level_data=&data};key:=expedition_geometry_key(&room,w)
	index,err:=level.place_structure(&data,.Machine,{x=7,y=7},1,true);testing.expect_value(t,err,level.Placement_Error.None)
	testing.expect(t,expedition_geometry_key(&room,w)!=key)
	a,b:Expedition_Geometry_Builder;defer {delete(a.vertices);delete(a.lines);delete(b.vertices);delete(b.lines)}
	draw_expedition_structure_object({mode=.Bake,builder=&a},&data,index,w.biome)
	w.clock=17;w.seed=81;w.beat=39
	draw_expedition_structure_object({mode=.Bake,builder=&b},&data,index,w.biome)
	testing.expect(t,slice.equal(a.vertices[:],b.vertices[:]) && slice.equal(a.lines[:],b.lines[:]))
	key=expedition_geometry_key(&room,w)
	testing.expect(t,level.remove_structure(&data,index))
	testing.expect(t,expedition_geometry_key(&room,w)!=key)
}

@(test)
test_expedition_structure_cache_releases_partial_and_complete_upload_ownership :: proc(t:^testing.T) {
	for failed in ([2]bool{false,true}) {
		cache:Expedition_Architecture_Cache
		cache.ready=!failed;cache.failed=failed
		for &chunk,i in cache.structures {
			chunk.lines=make([]Expedition_Baked_Line,1+i%3);chunk.ready=!failed || i<2
			chunk.center={1,2,3};chunk.radius=4
		}
		destroy_expedition_geometry(&cache)
		for chunk in cache.structures {testing.expect(t,!chunk.ready && chunk.lines==nil && chunk.radius==0 && chunk.center==rl.Vector3{})}
		testing.expect(t,!cache.ready && !cache.failed)
	}
}

@(test)
test_expedition_object_across_chunk_boundary_is_not_baked_into_either_cell_chunk :: proc(t:^testing.T) {
	data,ok:=level.create(24,24,{.Floor});testing.expect(t,ok);defer level.destroy(&data)
	set_board_level(&data);defer set_board_level(nil)
	_,err:=level.place_structure(&data,.Machine,{x=7,y=7},0,false);testing.expect_value(t,err,level.Placement_Error.None)
	w:=new(world.World);defer free(w);w.biome=.Cyber
	r:=new(Renderer);defer free(r)
	room:=game.Room{level_data=&data}
	b:Expedition_Geometry_Builder;defer {delete(b.vertices);delete(b.lines)}
	for y in ([2]int{0,8}) {for x in ([2]int{0,8}) {
		clear(&b.vertices);clear(&b.lines)
		expedition_build_chunk(r,&room,w,{x=x,y=y},&b)
		// The only geometry left in these floor chunks is flat scattered art.
		for v in b.vertices {testing.expect(t,v.position.y<.20)}
	}}
	clear(&b.vertices);clear(&b.lines)
	draw_expedition_structure_object({mode=.Bake,builder=&b},&data,0,w.biome)
	left,right:=false,false
	for v in b.vertices {left=left || v.position.x<8;right=right || v.position.x>8}
	testing.expect(t,left && right && len(b.vertices)>200)
}
