package expedition

import "core:testing"
import game "../game"
import level "../level"

@(test)
test_inferno_eruption_cracks_floor_after_warning_and_persists_lava :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player;room:=test_world(t,&w,&data,&p,.Inferno)
	defer level.destroy(&data);defer game.destroy_room(&room)
	w.site_count=0;w.group_count=0;room.phase=.Loot;p.position={45,45}
	_=level.set_tile(&data,p.position,{.Floor})
	_=level.set_tile(&data,{46,45},{.Floor})
	_=level.set_tile(&data,{45,46},{.Wall})
	w.clock=6.99;w.beat=6
	testing.expect_value(t,game.expedition_ground(&room,p.position),game.Expedition_Terrain.Plain)
	tick(&w,&room,.02)
	testing.expect(t,w.lane_warning&&w.lane_vertical&&w.lane==45)
	testing.expect_value(t,w.lane_center,p.position)
	testing.expect(t,game.expedition_ground(&room,p.position)==.Plain,"Warning must leave time to move")
	warning:=new(Snapshot);defer free(warning)
	testing.expect(t,capture(&w,&room,warning))
	testing.expect(t,warning.world.lane_warning)
	tick(&w,&room,2)
	testing.expect(t,!w.lane_warning)
	testing.expect_value(t,game.expedition_ground(&room,p.position),game.Expedition_Terrain.Lava)
	wall,_:=level.tile_at(&data,{45,46});testing.expect_value(t,wall.kind,level.Tile_Kind.Wall)
	health:=p.health;tick(&w,&room,1)
	testing.expect(t,p.health==health-1,"Fractured lava damages standing explorers each beat")
	testing.expect(t,walk(&w,&room,{1,0}));health=p.health
	testing.expect(t,walk(&w,&room,{-1,0}));testing.expect(t,p.health==health-2,"Re-entering the persistent fracture applies lava entry damage")
	finished:=new(Snapshot);defer free(finished)
	testing.expect(t,capture(&w,&room,finished));testing.expect(t,valid_snapshot(finished))
	w2:World;data2:level.Level;p2:game.Player;room2:game.Room
	testing.expect(t,restore(finished,&w2,&data2,&p2,&room2))
	defer game.destroy_room(&room2);defer level.destroy(&data2)
	testing.expect_value(t,game.expedition_ground(&room2,p2.position),game.Expedition_Terrain.Lava)
	testing.expect(t,game.base_cell_is_walkable(&room2,p2.position),"Eruptions never disconnect the world with permanent void")
}

@(test)
test_inferno_eruption_preserves_service_sites_and_lane_range :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player;room:=test_world(t,&w,&data,&p,.Inferno)
	defer level.destroy(&data);defer game.destroy_room(&room)
	w.group_count=0;w.site_count=1;w.sites[0]={kind=.Workshop,active=true,position={45,45},group=-1}
	room.phase=.Loot;p.position={45,45};_=level.set_tile(&data,p.position,{.Floor})
	w.clock=8.95;w.beat=8;w.lane=45;w.lane_vertical=true;w.lane_warning=true;w.lane_center=p.position
	tick(&w,&room,.1)
	testing.expect_value(t,game.expedition_ground(&room,p.position),game.Expedition_Terrain.Plain)
	testing.expect(t,lane_contains(&w,{45,57})&&!lane_contains(&w,{45,58}))
	_=level.set_tile(&data,p.position,{.Player_Spawn})
	testing.expect(t,!game.expedition_fracture_floor(&room,p.position))
	_=level.set_tile(&data,p.position,{.Door});p.tactical.config.expedition_biome=0
	testing.expect(t,game.expedition_ground(&room,p.position)!=.Lava,"The marker cannot affect doors in other biomes")
}
