package render

import "core:testing"
import game "../game"
import grid "../engine/grid"
import world "../expedition"
import level "../level"

@(test)
test_cyber_contact_cache_rejects_isolated_props_and_tracks_changed_wall_runs :: proc(t:^testing.T) {
	data,ok:=level.create(20,20,{.Floor});testing.expect(t,ok);defer level.destroy(&data)
	room:=game.Room{level_data=&data};w:=world.World{biome=.Cyber}
	cache:Expedition_Floor_Data;defer destroy_expedition_floor_data(&cache)
	for d,side in ([4]grid.Position{{x=-1},{x=1},{y=-1},{y=1}}) {
		at:=grid.Position{x=10+d.x,y=10+d.y}
		tangent:=grid.Position{x=d.y,y=d.x}
		a,b:=grid.offset(at,tangent.x,tangent.y),grid.offset(at,-tangent.x,-tangent.y)
		_=level.set_tile(&data,at,{.Wall})
		testing.expect(t,refresh_expedition_floor_data(&cache,&room,&w))
		testing.expect(t,cache.pixels[10*20+10].b>>4==0,"An isolated prop must not acquire a square contact frame")
		_=level.set_tile(&data,a,{.Wall});_=level.set_tile(&data,b,{.Wall})
		testing.expect(t,refresh_expedition_floor_data(&cache,&room,&w))
		testing.expect_value(t,cache.pixels[10*20+10].b>>4,u8(1<<uint(side)))
		w.clock+=123;w.beat+=7
		testing.expect(t,!refresh_expedition_floor_data(&cache,&room,&w))
		_=level.set_tile(&data,a,{.Floor})
		testing.expect(t,refresh_expedition_floor_data(&cache,&room,&w))
		testing.expect_value(t,cache.pixels[10*20+10].b>>4,u8(0))
		_=level.set_tile(&data,at,{.Floor});_=level.set_tile(&data,b,{.Floor})
	}
}
