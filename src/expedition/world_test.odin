package expedition

import "core:testing"
import "core:slice"
import campaign "../campaign"
import game "../game"
import grid "../engine/grid"
import level "../level"

@(private)
test_world :: proc(t:^testing.T,w:^World,data:^level.Level,p:^game.Player,b:campaign.Biome=.Cyber)->game.Room {
	testing.expect(t,generate(w,data,b,42))
	player,ok:=game.create_player({100,5,0});testing.expect(t,ok);p^=player
	room,created:=game.create_room(data,p,{room_seed=42});testing.expect(t,created)
	testing.expect(t,game.configure_expedition_combat(&room))
	p.tactical.config.expedition_biome=u8(b);p.tactical.config.low_gravity=b==.Space
	return room
}

@(test)
test_expedition_geography_is_seed_independent_and_all_sites_reachable :: proc(t:^testing.T) {
	for biome in campaign.Biome {
		if biome==.Count {continue}
		a,b:World; first,second:level.Level
		testing.expect(t,generate(&a,&first,biome,1));testing.expect(t,generate(&b,&second,biome,9999))
		testing.expect(t,slice.equal(first.tiles.cells[:],second.tiles.cells[:]))
		// The caves a run has are the run's (cave_test.odin); every other site is the biome's.
		for site,i in a.sites[:a.site_count] {if site.kind!=.Cave {testing.expect_value(t,site.position,b.sites[i].position)}}
		{
			seen:=make([]bool,len(first.tiles.cells));queue:=make([]grid.Position,len(first.tiles.cells));defer delete(seen);defer delete(queue);tail:=1;queue[0]=first.player_spawn
			seen[first.player_spawn.y*first.tiles.width+first.player_spawn.x]=true
			voids:=0
			for tile in first.tiles.cells {if tile.kind==.Void {voids+=1}}
			if biome==.Sky {testing.expect(t,voids>1000)}
			for head:=0;head<tail;head+=1 {
				for offset in ([4]grid.Position{{x = 1, y = 0},{x = -1, y = 0},{x = 0, y = 1},{x = 0, y = -1}}) {
					q:=game.add_position(queue[head],offset);tile,ok:=level.tile_at(&first,q)
					if !ok || !level.is_walkable(tile.kind) || abs(int(level.height_at(&first,q))-int(level.height_at(&first,queue[head])))>1 {continue}
					i:=q.y*first.tiles.width+q.x;if seen[i] {continue};seen[i]=true;queue[tail]=q;tail+=1
				}
			}
			for site in a.sites[:a.site_count] {
				reachable:=false
				for dy in -3..=3 {for dx in -3..=3 {p:=grid.offset(site.position, dx, dy);if p.x>=0 && p.y>=0 && p.x<first.tiles.width && p.y<first.tiles.height {reachable=reachable || seen[p.y*first.tiles.width+p.x]}}}
				testing.expect(t,reachable)
			}
			for tile,i in first.tiles.cells {if tile.kind==.Exit {testing.expect(t,seen[i])}}
		}
		level.destroy(&first);level.destroy(&second)
	}
}

@(test)
test_expedition_leash_preserves_damage_and_finite_groups_never_respawn :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player;room:=test_world(t,&w,&data,&p)
	defer level.destroy(&data);defer game.destroy_room(&room)
	g:=&w.groups[0];p.position=grid.offset(g.anchor, -4, 0)
	testing.expect(t,engage(&w,&room,0));testing.expect(t,len(room.enemies)>0)
	room.enemies[0].health-=2;remaining:=room.enemies[0].health
	p.position=data.player_spawn;tick(&w,&room,0.1)
	testing.expect(t,!g.active);testing.expect_value(t,g.members[0].enemy.health,remaining)
	p.position=grid.offset(g.anchor, -4, 0);testing.expect(t,engage(&w,&room,0))
	testing.expect_value(t,room.enemies[0].health,remaining)
	clear(&room.enemies);xp:=sync(&w,&room)
	testing.expect(t,xp>0);testing.expect_value(t,sync(&w,&room),i32(0))
	testing.expect(t,!engage(&w,&room,0))
	for member in g.members[:g.count] {testing.expect(t,!member.alive && !member.deployed)}
}

@(test)
test_expedition_nest_pauses_waves_outside_radius_and_resumes_once :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player;room:=test_world(t,&w,&data,&p)
	defer level.destroy(&data);defer game.destroy_room(&room)
	s:=&w.sites[0];testing.expect_value(t,s.kind,Site_Kind.Nest)
	w.mounted=true;p.position=site_world(s,{x = -1, y = 0});tick(&w,&room,0.1)
	testing.expect(t,!w.mounted)
	testing.expect_value(t,s.wave,1);first_group:=s.group
	clear(&room.enemies);sync(&w,&room);p.position=data.player_spawn;tick(&w,&room,0.1)
	testing.expect_value(t,s.wave,1)
	p.position=site_world(s,{x = -1, y = 0});tick(&w,&room,0.1)
	testing.expect_value(t,s.wave,2);testing.expect(t,s.group!=first_group)
	count:=w.group_count;tick(&w,&room,0.1);testing.expect_value(t,w.group_count,count)
	clear(&room.enemies);sync(&w,&room);tick(&w,&room,0.1)
	testing.expect_value(t,s.state,Site_State.Resolved);testing.expect(t,s.reward_pending)
}

@(test)
test_authored_final_nest_wave_resumes_after_leash_with_damage_preserved :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player;room:=test_world(t,&w,&data,&p)
	defer level.destroy(&data);defer game.destroy_room(&room)
	s:=&w.sites[0];s.waves=1;p.position=site_world(s,{x = -1, y = 0})
	tick(&w,&room,.01);testing.expect_value(t,s.wave,1)
	g:=&w.groups[s.group];testing.expect(t,g.active && len(room.enemies)>0)
	room.enemies[0].health-=2;remaining:=room.enemies[0].health;sync(&w,&room)
	p.position=data.player_spawn;tick(&w,&room,.01)
	testing.expect(t,!g.active && len(room.enemies)==0 && room.phase==.Loot)
	p.position=site_world(s,{x = -1, y = 0});tick(&w,&room,.01)
	testing.expect(t,g.active && len(room.enemies)>0);testing.expect_value(t,room.enemies[0].health,remaining)
	testing.expect_value(t,s.wave,1)
	clear(&room.enemies);sync(&w,&room);tick(&w,&room,.01)
	testing.expect(t,s.state==.Resolved && s.reward_pending && len(room.enemies)==0)
}

@(test)
test_partial_group_deployment_recovers_when_blocker_clears_without_duplicates :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player;room:=test_world(t,&w,&data,&p)
	defer level.destroy(&data);defer game.destroy_room(&room)
	g:=&w.groups[0];g.site= -1;g.anchor={x = 40, y = 40};g.count=2
	g.members[0].enemy.position={x = 36, y = 40};g.members[1].enemy.position={x = 40, y = 40};p.position={x = 35, y = 40}
	for y in 37..=43 {for x in 37..=43 {_=level.set_tile(&data,{x = x, y = y},{.Wall})}}
	_=level.set_tile(&data,{x = 36, y = 40},{.Floor});_=level.set_tile(&data,p.position,{.Floor})
	testing.expect(t,engage(&w,&room,0));testing.expect_value(t,len(room.enemies),1)
	first_id:=room.enemies[0].id;testing.expect(t,g.members[0].deployed && !g.members[1].deployed && g.members[1].alive)
	_=level.set_tile(&data,{x = 40, y = 40},{.Floor});testing.expect(t,engage(&w,&room,0))
	testing.expect_value(t,len(room.enemies),2);testing.expect_value(t,room.enemies[0].id,first_id)
	testing.expect(t,room.enemies[1].id!=first_id && !engage(&w,&room,0))
	ordered_remove(&room.enemies,0);sync(&w,&room)
	testing.expect(t,!g.members[0].alive && !engage(&w,&room,0));testing.expect_value(t,len(room.enemies),1)
}

@(test)
test_tunnel_exit_avoids_solid_tiles_and_hidden_traps :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player;room:=test_world(t,&w,&data,&p,.Vietnam)
	defer level.destroy(&data);defer game.destroy_room(&room)
	anchor:=grid.Position{x = size(&w)-14, y = 16};_=level.set_tile(&data,anchor,{.Wall})
	for dy in -1..=1 {for dx in -1..=1 {
		if dx==0 && dy==0 {continue}
		q:=grid.offset(anchor, dx, dy);_=level.set_tile(&data,q,{.Floor})
		append(&room.traps,game.Trap{id=room.next_trap_id,position=q,damage=4,armed=true});room.next_trap_id+=1
	}}
	exit,ok:=tunnel_destination(&w,&room);testing.expect(t,ok && distance(exit,anchor)>=2)
	testing.expect(t,!game.cell_blocks_movement(&room,exit))
	for trap in room.traps {testing.expect(t,exit!=trap.position)}
}

@(test)
test_expedition_snapshot_restores_dynamic_terrain_and_exact_room_state :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player;room:=test_world(t,&w,&data,&p)
	defer level.destroy(&data);defer game.destroy_room(&room)
	p.position={x = w.groups[0].anchor.x-4, y = w.groups[0].anchor.y};testing.expect(t,engage(&w,&room,0))
	room.enemies[0].health-=1;room.enemies[0].boss_cycle=7
	room.tactical_pulse.deferred_draws=2;p.deck.energy=37;p.tactical.energy_fraction=0.6
	_=level.set_tile(&data,{x = 8, y = 8},{.Void});append(&room.obstacles,game.Obstacle{{x = 9, y = 9}})
	room.ground.pool[42]=3;w.clock=31.25;w.beat=31
	snapshot:=new(Snapshot);defer free(snapshot)
	testing.expect(t,capture(&w,&room,snapshot));testing.expect(t,valid_snapshot(snapshot))
	w2:World;data2:level.Level;p2:game.Player;room2:game.Room
	testing.expect(t,restore(snapshot,&w2,&data2,&p2,&room2));defer level.destroy(&data2);defer game.destroy_room(&room2)
	testing.expect_value(t,p2,p);testing.expect_value(t,w2,w)
	testing.expect(t,slice.equal(room2.enemies[:],room.enemies[:]));testing.expect(t,slice.equal(room2.obstacles[:],room.obstacles[:]))
	testing.expect(t,slice.equal(data2.tiles.cells[:],data.tiles.cells[:]));testing.expect(t,slice.equal(room2.ground.pool,room.ground.pool))
	testing.expect_value(t,room2.tactical_pulse,room.tactical_pulse)
	// The reconstruction owns independent storage and references its new owners.
	testing.expect(t,room2.player==&p2 && room2.level_data==&data2)
	room2.enemies[0].health-=1;testing.expect(t,room2.enemies[0].health!=room.enemies[0].health)
	room.tactical_pulse.pending=true;testing.expect(t,!capture(&w,&room,snapshot))
	testing.expect_value(t,snapshot.player.deck.energy,i32(37))
	snapshot.enemy_count=game.MAX_ENEMIES_PER_ROOM+1;testing.expect(t,!valid_snapshot(snapshot))
}

@(test)
test_expedition_space_nest_finishes_all_waves_without_member_overflow :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player;room:=test_world(t,&w,&data,&p,.Space)
	defer level.destroy(&data);defer game.destroy_room(&room)
	for &site,i in w.sites[:w.site_count] {if i!=0 {site.active=false}}
	for &group in w.groups[:w.group_count] {for &member in group.members[:group.count] {member.alive=false}}
	s:=&w.sites[0];p.position=s.position
	for wave in 1..=s.waves {
		tick(&w,&room,0.1);testing.expect_value(t,s.wave,wave)
		testing.expect(t,w.groups[s.group].count<=MAX_MEMBERS)
		clear(&room.enemies);sync(&w,&room)
	}
	testing.expect_value(t,s.state,Site_State.Resolved)
	before:=w.clock;p.tactical.cast_remaining=1
	tick(&w,&room,1);testing.expect_value(t,w.clock,before)
}

@(test)
test_expedition_vietnam_traps_trigger_in_exploration_and_persist_disarmed :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player;room:=test_world(t,&w,&data,&p,.Vietnam)
	defer level.destroy(&data);defer game.destroy_room(&room)
	prepare_room(&w,&room);testing.expect(t,len(room.traps)>0)
	count:=len(room.traps);prepare_room(&w,&room);testing.expect_value(t,len(room.traps),count)
	trap:=room.traps[0].position;p.position=grid.offset(trap, -1, 0);_=level.set_tile(&data,p.position,{.Floor})
	w.mounted=true;before:=p.health
	testing.expect(t,walk(&w,&room,{x = 1, y = 0}));testing.expect_value(t,p.health,before-4)
	testing.expect(t,!room.traps[0].armed && !w.mounted)
	snapshot:=new(Snapshot);defer free(snapshot);testing.expect(t,capture(&w,&room,snapshot))
	testing.expect(t,!snapshot.traps[0].armed)
}

@(test)
test_expedition_full_drop_capacity_preserves_and_restores_pending_xp :: proc(t:^testing.T) {
	w:World;data:level.Level;p:game.Player;room:=test_world(t,&w,&data,&p)
	defer level.destroy(&data);defer game.destroy_room(&room)
	p.position={x = w.groups[0].anchor.x-4, y = w.groups[0].anchor.y};testing.expect(t,engage(&w,&room,0))
	// The map's own drops first (a complex's secret, complex.odin), then as many as there is room for.
	for _ in w.drop_count..<MAX_DROPS {testing.expect(t,add_drop(&w,p.position,campaign.make_item(.Credits,1)))}
	clear(&room.enemies);earned:=sync(&w,&room)
	testing.expect(t,earned>0);testing.expect_value(t,w.pending_xp,earned)
	testing.expect_value(t,w.drop_count,MAX_DROPS);testing.expect_value(t,sync(&w,&room),i32(0))
	snapshot:=new(Snapshot);defer free(snapshot)
	testing.expect(t,capture(&w,&room,snapshot));testing.expect(t,valid_snapshot(snapshot))
	w2:World;data2:level.Level;p2:game.Player;room2:game.Room
	testing.expect(t,restore(snapshot,&w2,&data2,&p2,&room2));defer game.destroy_room(&room2);defer level.destroy(&data2)
	testing.expect_value(t,w2.pending_xp,earned)
	w2.drop_count-=1;testing.expect_value(t,sync(&w2,&room2),i32(0))
	testing.expect_value(t,w2.pending_xp,i32(0));testing.expect_value(t,w2.drop_count,MAX_DROPS)
	stored:i32;for drop in w2.drops[:w2.drop_count] {stored+=drop.xp}
	testing.expect_value(t,stored,earned)
	sync(&w2,&room2);again:i32;for drop in w2.drops[:w2.drop_count] {again+=drop.xp};testing.expect_value(t,again,earned)
}

@(test)
test_expedition_xp_coalesces_nearby_without_stealing_item_drop_slots :: proc(t:^testing.T) {
	w:=World{biome=.Cyber,reward_site=-1}
	add_xp_drop(&w,{x = 5, y = 5},2);add_xp_drop(&w,{x = 7, y = 5},3)
	testing.expect_value(t,w.drop_count,1);testing.expect_value(t,w.drops[0].xp,i32(5))
	add_xp_drop(&w,{x = 30, y = 30},2);testing.expect_value(t,w.drop_count,2)
}

@(test)
test_expedition_outdoor_props_never_enclose_open_floor :: proc(t:^testing.T) {
	for biome in campaign.Biome {
		if biome==.Count {continue}
		w:World;data:level.Level
		testing.expect(t,generate(&w,&data,biome,7))
		// A walk a step at a time, across the layers too: up a complex's ramp, over its bridges, up its lifts (complex.odin).
		seen:=level.layer_reach(&data,data.player_spawn)
		props,stranded:=0,0
		for tile,i in data.tiles.cells {
			p:=grid.Position{x = i%data.tiles.width, y = i/data.tiles.width}
			if _,design:=site_at(&w,p);design.inside {continue}
			// A massif's top is rock over a cave: no one walks there (cave.odin).
			if cave_rock(&w,p) {continue}
			if tile.kind==.Wall {props+=1}
			if tile.kind!=.Wall && tile.kind!=.Fence && tile.kind!=.Void && !seen[level.layer_reach_index(&data,p)] {stranded+=1}
		}
		// The Sky has no props: its archipelago keeps a few unbridged islets
		// by design, and the site test above covers every site's approach.
		if biome!=.Sky {
			testing.expectf(t,stranded==0,"%v: %d open cells cannot be reached",biome,stranded)
			testing.expectf(t,props>200,"%v: only %d outdoor props",biome,props)
		}
		delete(seen);level.destroy(&data)
	}
}
