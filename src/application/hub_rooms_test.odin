package application

import "core:testing"
import campaign "../campaign"
import campaignui "../campaignui"
import game "../game"
import host "../engine/host"
import hubworld "../hubworld"

@(test)
test_the_mannequin_wears_the_gear_the_backpack_really_holds :: proc(t:^testing.T) {
	c:campaign.Campaign;campaign.initialize(&c);defer campaign.destroy(&c)
	empty:=hub_depot_view(&c)
	testing.expect(t,!empty.gear.has_weapon)
	for has in empty.gear.has_relic {testing.expect(t,!has)}
	c.backpack.weapon=campaign.make_item(.Weapon,1,i32(game.Weapon_Id.Storm_Pike))
	c.backpack.relics[0]=campaign.make_item(.Relic,1,i32(game.Relic_Id.Guard_Sigil))
	c.backpack.relics[2]=campaign.make_item(.Relic,1,i32(game.Relic_Id.Swift_Soles))
	view:=hub_depot_view(&c)
	testing.expect(t,view.gear.has_weapon)
	testing.expect_value(t,view.gear.weapon,i32(game.Weapon_Id.Storm_Pike))
	testing.expect(t,view.gear.has_relic[0] && !view.gear.has_relic[1] && view.gear.has_relic[2])
	testing.expect_value(t,view.gear.relic[0],i32(game.Relic_Id.Guard_Sigil))
	testing.expect_value(t,view.gear.relic[2],i32(game.Relic_Id.Swift_Soles))
	// Taking them off changes the mannequin at once.
	c.backpack.weapon={};c.backpack.relics[0]={}
	view=hub_depot_view(&c)
	testing.expect(t,!view.gear.has_weapon && !view.gear.has_relic[0] && view.gear.has_relic[2])
}

@(test)
test_the_crates_and_the_archive_follow_the_depot_and_the_cards_known :: proc(t:^testing.T) {
	c:campaign.Campaign;campaign.initialize(&c);defer campaign.destroy(&c)
	before:=hub_depot_view(&c)
	testing.expect(t,before.total>0 && before.discovered>0 && before.discovered<=before.total)
	testing.expect_value(t,before.stored,0)
	for _ in 0..<7 {campaign.depot_add(&c,campaign.make_item(.Healing,1))}
	// Seven potions may share cells, but the depot holds them somewhere.
	stored:=hub_depot_view(&c).stored
	testing.expect(t,stored>=1)
	for id in game.Card_Id.Strike..<game.Card_Id.Count {if !c.discovered[id] && campaign.discover(&c,id) {break}}
	after:=hub_depot_view(&c)
	testing.expect_value(t,after.discovered,before.discovered+1)
	testing.expect_value(t,after.total,before.total)
}

@(test)
test_each_depot_station_opens_its_panel_and_the_robot_comes_back_in_front_of_it :: proc(t:^testing.T) {
	h:=new(Campaign_Hub);defer free(h)
	hub_room_setup(h,.Depot)
	for station in 0..<hubworld.DEPOT_DOORS-1 {
		h.room_from=station
		hub_open_depot_panel(h,station)
		testing.expect_value(t,h.page,Hub_Page.Storage)
		testing.expect_value(t,h.inventory.panel,campaignui.Panel(station))
		hub_storage_closed(h)
		testing.expect_value(t,h.page,Hub_Page.Room)
		testing.expect_value(t,h.room_from,station)
		s:=h.room.stations[station]
		testing.expect(t,!hubworld.station_in_door(s,h.room_world.position,hubworld.DOOR_REARM_MARGIN),"outside the door")
		testing.expect(t,hubworld.station_distance(s,h.room_world.position)>=hubworld.ROBOT_RADIUS)
	}
}

@(test)
test_the_dissolve_leads_into_a_room_and_back_to_the_plaza_in_front_of_its_building :: proc(t:^testing.T) {
	h:=new(Campaign_Hub);defer free(h)
	h.page=.World;hubworld.place_at_centre(&h.plaza)
	frame:=host.Frame{dt=1.0/60.0}
	for room in ([2]Hub_Room{.Casino,.Depot}) {
		hub_fade_to(h,.Room,room)
		for _ in 0..<60 {hub_fade_update(h,&frame)}
		testing.expect_value(t,h.page,Hub_Page.Room)
		testing.expect_value(t,h.room_kind,room)
		testing.expect(t,!h.fade.active)
		testing.expect_value(t,h.room_world.position,hubworld.Vec2{})
		hub_fade_to(h,.Plaza,room)
		for _ in 0..<60 {hub_fade_update(h,&frame)}
		testing.expect_value(t,h.page,Hub_Page.World)
		building:=hub_room_building(room)
		testing.expect_value(t,h.plaza_from,building)
		testing.expect(t,!hubworld.in_door(building,h.plaza.position,hubworld.DOOR_REARM_MARGIN),"in front of the building, outside its door")
	}
}

@(test)
test_the_lit_cabinets_are_exactly_the_unlocked_ones :: proc(t:^testing.T) {
	c:campaign.Campaign;campaign.initialize(&c);defer campaign.destroy(&c)
	// Nothing won: no cabinet is lit and every place is covered, with nothing written on it.
	view:=hub_arcade_view(&c)
	testing.expect_value(t,view.count,0)
	room:=hubworld.arcade_room(view.count)
	for k in 0..<hubworld.ARCADE_SLOTS {
		testing.expect(t,room.stations[k].decor)
		testing.expect_value(t,room.stations[k].name,"")
		testing.expect_value(t,view.title[k],"")
	}
	// Win the biomes one by one: the lit ones are always those of hub_unlocked_arcades, in its order.
	for b in campaign.Biome.Cyber..<campaign.Biome.Count {
		c.won[b]=true
		indices,count:=hub_unlocked_arcades(&c)
		view=hub_arcade_view(&c)
		room=hubworld.arcade_room(view.count)
		testing.expect_value(t,view.count,count)
		for k in 0..<hubworld.ARCADE_SLOTS {
			testing.expect_value(t,room.stations[k].decor,k>=count)
			if k<count {
				testing.expect_value(t,view.game[k],indices[k])
				testing.expect(t,view.title[k]!="")
				game,ok:=hub_arcade_game(&c,k)
				testing.expect(t,ok && game==indices[k],"each cabinet opens its own minigame")
			} else {
				_,ok:=hub_arcade_game(&c,k)
				testing.expect(t,!ok,"a covered cabinet opens nothing")
			}
		}
	}
}

@(test)
test_a_biome_not_won_leaves_no_clue_in_the_hall :: proc(t:^testing.T) {
	c:campaign.Campaign;campaign.initialize(&c);defer campaign.destroy(&c)
	c.won[campaign.Biome.Cyber]=true
	view:=hub_arcade_view(&c)
	entries,n:=hub_biome_arcades(.Cyber)
	testing.expect_value(t,view.count,n)
	for k in 0..<view.count {testing.expect_value(t,view.game[k],entries[k])}
	// The other places say nothing: no name, no record, and no colour in the view.
	room:=hubworld.arcade_room(view.count)
	for k in view.count..<hubworld.ARCADE_SLOTS {
		testing.expect_value(t,view.title[k],"")
		testing.expect_value(t,view.record[k],"")
		testing.expect_value(t,view.stars[k],u8(0))
		testing.expect(t,room.stations[k].decor)
	}
}

@(test)
test_the_record_on_a_cabinet_follows_the_game_just_played_and_the_robot_comes_back_to_it :: proc(t:^testing.T) {
	h:=new(Campaign_Hub);defer free(h)
	campaign.initialize(&h.progress);defer campaign.destroy(&h.progress)
	for &won in h.progress.won {won=true}
	indices,count:=hub_unlocked_arcades(&h.progress)
	testing.expect(t,count>1)
	hub_room_setup(h,.Arcade)
	for station in 0..<count {
		view:=hub_arcade_view(&h.progress)
		testing.expect_value(t,view.record[station],"Nessun record")
		// The game is played, then the hub resumes: the record is there, the robot in front of the cabinet.
		campaign.record_result(&h.progress,indices[station],2468,3,true)
		h.page=.Room;h.in_game=true;h.room_from=station
		hub_resume(h,nil,"minigame",nil)
		view=hub_arcade_view(&h.progress)
		testing.expect_value(t,view.stars[station],u8(3))
		testing.expect(t,view.record[station]!="Nessun record")
		testing.expect_value(t,h.room_from,station)
		s:=h.room.stations[station]
		testing.expect(t,!hubworld.station_in_door(s,h.room_world.position,hubworld.DOOR_REARM_MARGIN),"outside the door")
		testing.expect(t,hubworld.station_distance(s,h.room_world.position)>=hubworld.ROBOT_RADIUS)
	}
}
