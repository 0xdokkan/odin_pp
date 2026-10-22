package application

import "core:testing"
import "core:strings"
import campaign "../campaign"
import activities "../activities"
import host "../engine/host"
import ui "../engine/ui"

@(test)
test_hub_formation_only_animates_routes_unlocked_by_the_last_expedition :: proc(t:^testing.T) {
	h:=new(Campaign_Hub);defer free(h)
	campaign.initialize(&h.progress);defer campaign.destroy(&h.progress)
	h.progress.unlocked[campaign.Biome.City]=true
	h.departure_unlocked=h.progress.unlocked
	// City was already revealed but never visited; only the new Snow route forms.
	h.progress.unlocked[campaign.Biome.Snow]=true;h.clock=42
	hub_reveal_new_routes(h)
	testing.expect(t,!h.new_islands[campaign.Biome.City])
	testing.expect(t,h.new_islands[campaign.Biome.Snow])
	testing.expect_value(t,h.revealed_at,f32(42))
	h.departure_unlocked=h.progress.unlocked;h.clock=51
	hub_reveal_new_routes(h)
	for shown in h.new_islands {testing.expect(t,!shown)}
}

@(test)
test_hub_records_include_both_city_cabinets_without_secret_duplicates :: proc(t:^testing.T) {
	c:campaign.Campaign;campaign.initialize(&c);defer campaign.destroy(&c)
	_,n:=hub_unlocked_arcades(&c);testing.expect_value(t,n,0)
	c.won[campaign.Biome.City]=true
	indices,count:=hub_unlocked_arcades(&c)
	testing.expect_value(t,count,2)
	testing.expect_value(t,indices[0],activities.minigame_index_by_id("karaoke"))
	testing.expect_value(t,indices[1],activities.minigame_index_by_id("ring"))
	for &won in c.won {won=true}
	indices,count=hub_unlocked_arcades(&c)
	testing.expect_value(t,count,activities.MINIGAME_COUNT)
	seen:[activities.MINIGAME_COUNT]bool
	for index in indices[:count] {testing.expect(t,!seen[index]);seen[index]=true}
}

@(test)
test_hub_progress_reveals_only_known_secrets_and_pages_records :: proc(t:^testing.T) {
	h:=new(Campaign_Hub);defer free(h)
	campaign.initialize(&h.progress);defer campaign.destroy(&h.progress)
	campaign.discover_secret(&h.progress,.Cyber,12)
	campaign.discover_secret(&h.progress,.City,14)
	entries,count:=hub_known_secrets(&h.progress)
	testing.expect_value(t,count,2)
	testing.expect_value(t,entries[0],Hub_Secret{.Cyber,12})
	testing.expect_value(t,entries[1],Hub_Secret{.City,14})
	for &won in h.progress.won {won=true}
	ring:=activities.minigame_index_by_id("ring")
	campaign.record_result(&h.progress,ring,12345,3,true)
	indices,n:=hub_unlocked_arcades(&h.progress)
	ring_position:=0;for index,i in indices[:n] {if index==ring {ring_position=i}}
	h.progress_tab=1;h.progress_page=ring_position/4
	theme:=ui.default_theme();ctx:=ui.create(&theme);defer ui.destroy(ctx)
	frame:=host.Frame{canvas={0,0,960,540},ui=ctx}
	ui.begin(ctx,{}, {},0);hub_progress(h,&frame);ui.end(ctx)
	found_score,found_ring:=false,false
	for command in ctx.commands[:ctx.command_count] {
		found_score=found_score||strings.contains(command.text,"12345")
		found_ring=found_ring||command.text=="Il Ring delle Ombre"
	}
	testing.expect(t,found_score&&found_ring)
	h.arcade_page=1
	ui.begin(ctx,{}, {},0);hub_arcade(h,&frame);ui.end(ctx)
	play_buttons:=0;for command in ctx.commands[:ctx.command_count] {if command.text=="GIOCA" {play_buttons+=1}}
	testing.expect_value(t,play_buttons,4)
}
