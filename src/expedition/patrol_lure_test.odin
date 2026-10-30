package expedition

import "core:testing"
import grid "../engine/grid"
import game "../game"
import level "../level"

@(test)
test_patrol_lure_routes_around_cover_waits_then_returns_and_survives_save :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player;room:=test_world(t,&w,&data,&p)
	defer level.destroy(&data);defer game.destroy_room(&room)
	w.site_count=0;w.group_count=3;room.phase=.Loot
	for y in 8..=35 {for x in 10..=45 {_=level.set_tile(&data,{x = x, y = y},{.Floor})}}
	w.groups[0]={anchor={x = 31, y = 18},patrol=true,count=1,site= -1}
	w.groups[1]={anchor={x = 24, y = 18},patrol=true,count=1,site= -1,members={0={enemy={position={x = 24, y = 18},health=5,max_health=5,attack=2,archetype=.Chaser},alive=true}}}
	w.groups[2]={anchor={x = 27, y = 11},count=1,site= -1,members={0={enemy={position={x = 27, y = 11},health=5,max_health=5,attack=2,archetype=.Chaser},alive=true}}}
	for y in 12..=24 {_=level.set_tile(&data,{x = 28, y = y},{.Wall})}
	goal:=level_position(32,18);testing.expect(t,lure_patrol(&w,&room,goal))
	g:=&w.groups[1];home:=g.anchor;testing.expect_value(t,g.lure_phase,Patrol_Lure_Phase.Seeking)
	testing.expect_value(t,w.groups[0].lure_phase,Patrol_Lure_Phase.None)
	for _ in 0..<3 {tick(&w,&room,1.4)}
	testing.expect(t,g.members[0].enemy.position!=home)
	snapshot:=new(Snapshot);defer free(snapshot);testing.expect(t,capture(&w,&room,snapshot))
	w2:World;data2:level.Level;p2:game.Player;room2:game.Room
	testing.expect(t,restore(snapshot,&w2,&data2,&p2,&room2));defer level.destroy(&data2);defer game.destroy_room(&room2)
	testing.expect_value(t,w2.groups[1].lure_phase,g.lure_phase);testing.expect_value(t,w2.groups[1].lure_until,g.lure_until)
	arrived,returned:=false,false
	for _ in 0..<80 {
		tick(&w2,&room2,1.4)
		g2:=&w2.groups[1];position:=g2.members[0].enemy.position
		tile,_:=level.tile_at(&data2,position);testing.expect(t,tile.kind!=.Wall)
		testing.expect(t,position!=w2.groups[2].members[0].enemy.position && position!=p2.position)
		if g2.lure_phase==.Waiting {arrived=true;testing.expect(t,distance(position,goal)<=2)}
		if g2.lure_phase==.None {returned=true;testing.expect(t,distance(position,home)<=3);break}
	}
	testing.expect(t,arrived && returned);testing.expect_value(t,w2.groups[1].anchor,home)
}

@(test)
test_patrol_lure_expires_when_enclosed_and_cannot_select_active_or_distant_groups :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player;room:=test_world(t,&w,&data,&p)
	defer level.destroy(&data);defer game.destroy_room(&room)
	w.site_count=0;w.group_count=1;room.phase=.Loot
	g:=&w.groups[0];g^={anchor={x = 30, y = 30},patrol=true,count=1,site= -1,members={0={enemy={position={x = 30, y = 30},health=5,max_health=5,attack=2,archetype=.Chaser},alive=true}}}
	_=level.set_tile(&data,{x = 35, y = 30},{.Floor})
	g.active=true;testing.expect(t,!lure_patrol(&w,&room,{x = 35, y = 30}));g.active=false
	testing.expect(t,!lure_patrol(&w,&room,{x = 100, y = 100}))
	for y in 29..=31 {for x in 29..=31 {_=level.set_tile(&data,{x = x, y = y},{.Wall})}}
	_=level.set_tile(&data,{x = 30, y = 30},{.Floor});testing.expect(t,lure_patrol(&w,&room,{x = 35, y = 30}))
	w.clock=g.lure_until+.01;tick(&w,&room,.01)
	testing.expect_value(t,g.lure_phase,Patrol_Lure_Phase.None);testing.expect_value(t,g.members[0].enemy.position,level_position(30,30))
}

@(test)
test_lured_patrol_engagement_uses_arrival_area_instead_of_old_leash :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player;room:=test_world(t,&w,&data,&p)
	defer level.destroy(&data);defer game.destroy_room(&room)
	w.site_count=0;w.group_count=1;room.phase=.Loot;p.position={x = 42, y = 25}
	for y in 15..=35 {for x in 15..=65 {_=level.set_tile(&data,{x = x, y = y},{.Floor})}}
	g:=&w.groups[0];g^={anchor={x = 20, y = 25},patrol=true,count=1,site= -1,members={0={enemy={position={x = 20, y = 25},health=5,max_health=5,attack=2,archetype=.Chaser},alive=true}}}
	original:=g.anchor;testing.expect(t,lure_patrol(&w,&room,{x = 40, y = 25}))
	for _ in 0..<25 {tick(&w,&room,1.4);if g.lure_phase==.Waiting {break}}
	testing.expect_value(t,g.lure_phase,Patrol_Lure_Phase.Waiting)
	testing.expect(t,distance(p.position,original)>12)
	arrived:=g.members[0].enemy.position
	testing.expect(t,engage(&w,&room,0));testing.expect_value(t,g.anchor,arrived)
	testing.expect_value(t,g.lure_phase,Patrol_Lure_Phase.None)
	tick(&w,&room,.01)
	testing.expect(t,g.active && room.phase==.Combat && len(room.enemies)==1)
	testing.expect_value(t,room.enemies[0].position,arrived)
}

@(private)
level_position :: proc(x,y:int)->grid.Position {return {x = x, y = y}}
