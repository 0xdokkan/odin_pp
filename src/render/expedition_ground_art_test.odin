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

@(test)
test_ground_art_is_sparse_deterministic_and_preserves_hazards_and_interactions :: proc(t:^testing.T) {
	data,ok:=level.create(32,32,{.Floor});testing.expect(t,ok);defer level.destroy(&data)
	w:=new(world.World);defer free(w)
	for biome in campaign.Biome {
		if biome==.Count {continue};w.biome=biome
		blocks:[64]bool;count:=0
		chosen:grid.Position
		for y in 1..<31 {for x in 1..<31 {
			cell:=grid.Position{x = x,y = y}
			h,selected:=expedition_ground_art_selected(&data,w,cell)
			w.clock+=.13;w.seed+=719
			h2,again:=expedition_ground_art_selected(&data,w,cell)
			testing.expect(t,h==h2 && selected==again)
			if !selected {continue}
			index:=(y/4)*8+x/4
			testing.expect(t,!blocks[index],"At most one small illustration per 4x4 region")
			blocks[index]=true;count+=1;chosen=cell
			terrain:=game.expedition_terrain(u8(biome),cell)
			testing.expect(t,terrain==.Plain || terrain==.Grass || terrain==.Sand || terrain==.Snow)
		}}
		testing.expect(t,count>0 && count<64)
		data.has_player_spawn=true;data.player_spawn=chosen
		_,selected:=expedition_ground_art_selected(&data,w,chosen);testing.expect(t,!selected)
		data.has_player_spawn=false
		_=level.set_tile(&data,chosen,{.Door})
		_,selected=expedition_ground_art_selected(&data,w,chosen);testing.expect(t,!selected)
		_=level.set_tile(&data,chosen,{.Floor})
		w.site_count=1;w.sites[0]={kind=.Workshop,position=chosen,active=true,layout_version=world.SITE_LAYOUT_VERSION}
		_,selected=expedition_ground_art_selected(&data,w,chosen);testing.expect(t,!selected)
		// A real courtyard wall may gather a low group; the open courtyard
		// itself and the central workstation must remain clear.
		w.sites[0].position=grid.offset(chosen,-8,-8)
		_,selected=expedition_ground_art_selected(&data,w,chosen);testing.expect(t,!selected)
		adjacent:=grid.offset(chosen,1,0);_=level.set_tile(&data,adjacent,{.Wall})
		_,selected=expedition_ground_art_selected(&data,w,chosen);testing.expect(t,selected)
		_=level.set_tile(&data,adjacent,{.Floor})
		w.site_count=0
	}
}

@(test)
test_ground_art_stays_low_and_rooted_on_ramps_without_resources_or_lights :: proc(t:^testing.T) {
	data,ok:=level.create(12,12,{.Floor});testing.expect(t,ok);defer level.destroy(&data)
	for y in 0..<12 {for x in 0..<12 {level.set_height(&data,{x = x,y = y},i32(x))}}
	set_board_level(&data);defer set_board_level(nil)
	builder,again:Expedition_Geometry_Builder
	defer {delete(builder.vertices);delete(builder.lines);delete(again.vertices);delete(again.lines)}
	for biome in campaign.Biome {
		if biome==.Count {continue}
		for variant in u32(0)..<16 {
			clear(&builder.vertices);clear(&builder.lines);clear(&again.vertices);clear(&again.lines)
			cell:=grid.Position{x = 4,y = 5};hash:=expedition_cell_hash(cell,variant)
			expedition_ground_art_cell(&builder,biome,cell,hash)
			expedition_ground_art_cell(&again,biome,cell,hash)
			testing.expect(t,slice.equal(builder.vertices[:],again.vertices[:]))
			testing.expect(t,len(builder.vertices)>0 && len(builder.vertices)<=48)
			testing.expect_value(t,len(builder.lines),0)
			rooted:=false
			for v in builder.vertices {
				testing.expect(t,v.position.x>4 && v.position.x<5 && v.position.z>5 && v.position.z<6)
				above:=v.position.y-point_ground({v.position.x-.5,v.position.z-.5})
				testing.expect(t,above>=.0029 && above<.12,"Art follows the slope and cannot become visual cover")
				rooted=rooted || abs(above-.003)<.0001
				testing.expect(t,abs(rl.Vector3LengthSqr(v.normal)-1)<.0001 && !math.is_nan(v.normal.y))
			}
			testing.expect(t,rooted,"Every group has contact with the actual floor")
		}
	}
}
