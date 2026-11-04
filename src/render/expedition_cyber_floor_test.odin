package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"
import world "../expedition"
import game "../game"
import campaign "../campaign"
import grid "../engine/grid"
import level "../level"

@(test)
test_cyber_floor_routes_follow_real_clear_workshop_approaches :: proc(t:^testing.T) {
	w:world.World;data:level.Level
	testing.expect(t,world.generate(&w,&data,.Cyber,77));defer level.destroy(&data)
	found:=false
	bends:=CYBER_FLOOR_BENDS
	for &site in w.sites[:w.site_count] {
		if site.kind!=.Workshop {continue};found=true
		// The uniform frame and the gameplay frame must agree, including all
		// quarter turns. Pigment never changes the underlying map geometry.
		for turn in 0..<4 {
			rotated:=site;rotated.orientation=u8(turn)
			for route,route_index in CYBER_FLOOR_ROUTES {
				for sample in 0..=40 {
					f:=f32(sample)/40
					q:=rl.Vector2{route.x+(route.z-route.x)*f,route.y+(route.w-route.y)*f}
					direction:=rl.Vector2{route.z-route.x,route.w-route.y}
					across:=rl.Vector2{-direction.y,direction.x}/rl.Vector2Length(direction)
					q+=across*bends[route_index]*math.sin(f*math.PI)
					local:=grid.Position{x = int(math.floor(q.x+.5)),y = int(math.floor(q.y+.5))}
					p:=world.site_world(&rotated,local)
					design:=world.site_cell(&rotated,p)
					testing.expect(t,design.inside && !design.wall && !design.fixture,"traffic pigment must follow actual clear approaches")
					// Also check the generated level, not only layout descriptors.
					if turn==int(site.orientation) {
						tile,ok:=level.tile_at(&data,p)
						testing.expect(t,ok && level.kind_has_floor(tile.kind) && tile.kind!=.Wall && tile.kind!=.Fence)
					}
				}
			}
		}
	}
	testing.expect(t,found)
}

@(test)
test_cyber_floor_workshop_frame_tracks_orientation_without_dynamic_state :: proc(t:^testing.T) {
	w:=world.World{biome=.Cyber,site_count=3}
	w.sites[0]={kind=.Archive,position={x = 20,y = 20},layout_version=world.SITE_LAYOUT_VERSION}
	w.sites[1]={kind=.Workshop,position={x = 40,y = 30},layout_version=world.SITE_LAYOUT_VERSION}
	w.sites[2]={kind=.Workshop,position={x = 70,y = 70},layout_version=0}
	for turn in 0..<4 {
		w.sites[1].orientation=u8(turn)
		frames,count:=cyber_floor_workshops(&w)
		testing.expect_value(t,count,1)
		for q in ([4]grid.Position{{x = 0,y = 11},{x = -12},{x = 6,y = 4},{x = -6,y = 6}}) {
			p:=world.site_world(&w.sites[1],q)
			d:=rl.Vector2{f32(p.x)+.5-frames[0].x,f32(p.y)+.5-frames[0].y}
			local:=rl.Vector2{d.x*frames[0].z+d.y*frames[0].w,-d.x*frames[0].w+d.y*frames[0].z}
			testing.expect_value(t,local,rl.Vector2{f32(q.x),f32(q.y)})
		}
		w.seed+=17;w.clock+=5;w.beat+=1;w.sites[1].active=!w.sites[1].active
		again,again_count:=cyber_floor_workshops(&w)
		testing.expect_value(t,again_count,count);testing.expect_value(t,again,frames)
	}
	w.biome=.Snow
	_,count:=cyber_floor_workshops(&w);testing.expect_value(t,count,0)
}

@(test)
test_workshop_stock_tag_preserves_hazards_and_site_precedence :: proc(t:^testing.T) {
	for biome in ([2]campaign.Biome{.Cyber,.West}) {
	data,ok:=level.create(64,64,{.Floor});testing.expect(t,ok);defer level.destroy(&data)
	w:=world.World{biome=biome,site_count=2}
	w.sites[0]={kind=.Spring,position={x = 38,y = 32},layout_version=world.SITE_LAYOUT_VERSION}
	w.sites[1]={kind=.Workshop,position={x = 30,y = 32},layout_version=world.SITE_LAYOUT_VERSION}
	_=level.set_tile(&data,{x = 26,y = 29},{.Wall})
	room:=game.Room{level_data=&data};cache:Expedition_Floor_Data;defer destroy_expedition_floor_data(&cache)
	revision:=data.geometry_revision
	testing.expect(t,refresh_expedition_floor_data(&cache,&room,&w))
	marked:=0
	for pixel,i in cache.pixels {
		p:=grid.Position{x = i%64,y = i/64};index,_:=world.site_at(&w,p)
		expected:=index>=0 && w.sites[index].kind==.Workshop
		testing.expect_value(t,(pixel.r&EXPEDITION_FLOOR_CYBER_WORKSHOP)!=0,expected)
		testing.expect_value(t,pixel.r&7,u8(data.tiles.cells[i].kind))
		testing.expect_value(t,pixel.g&15,u8(game.expedition_terrain(u8(biome),p)))
		if expected {marked+=1}
	}
	testing.expect(t,marked>0 && marked<25*23)
	testing.expect_value(t,data.geometry_revision,revision)
	w.clock=123;w.beat=90;w.sites[1].active=true
	testing.expect(t,!refresh_expedition_floor_data(&cache,&room,&w))
	w.biome=.Snow;testing.expect(t,refresh_expedition_floor_data(&cache,&room,&w))
	for pixel in cache.pixels {testing.expect_value(t,pixel.r&EXPEDITION_FLOOR_CYBER_WORKSHOP,u8(0))}
	}
}

@(test)
test_cyber_cliff_pigment_depth_keeps_exact_sloping_cap :: proc(t:^testing.T) {
	vertices:[dynamic]Expedition_Baked_Vertex;defer delete(vertices)
	for side in 0..<4 {
		clear(&vertices)
		testing.expect(t,terrain_wall(&vertices,8,12,side,{18,22},{2,5},0))
		// The existing eight triangles are retained; colour alone carries the
		// distance below each position of the slanted walkable upper edge.
		testing.expect_value(t,len(vertices),24)
		corners:=[4]rl.Vector2{{8,12},{9,12},{9,13},{8,13}}
		a,b:=corners[side],corners[(side+1)%4];axis:=b-a
		cap_count,deep_count:=0,0
		for v in vertices {
			along:=clamp(rl.Vector2DotProduct(rl.Vector2{v.position.x,v.position.z}-a,axis),0,1)
			cap:=(18+4*along)*game.HEIGHT_STEP_DRAWN
			depth:=cap-v.position.y
			testing.expect(t,depth>=-.00001)
			testing.expect(t,abs(f32(255-v.color.g)/127.5-min(depth,2))<.0081)
			testing.expect(t,abs(rl.Vector3Length(v.normal)-1)<.0001)
			if depth<.0001 {testing.expect_value(t,v.color.g,u8(255));cap_count+=1}
			if depth>.5 {deep_count+=1}
		}
		testing.expect(t,cap_count>0 && deep_count>0)
	}
}
