package application

import "core:fmt"
import campaign "../campaign"
import game "../game"
import grid "../engine/grid"
import world "../expedition"
import render "../render"
import run "../run"
import artifacts "../devtools/artifacts"

@(private)
expedition_smoke_workshop :: proc(e:^run.Expedition_Session,biome:campaign.Biome) {
	expedition_smoke_world(e,biome);e.world.mounted=false;e.message_timer=0
	for &site in e.world.sites[:e.world.site_count] {
		if site.kind!=.Workshop {continue}
		for local in ([3]grid.Position{{x = 0,y = 2},{x = 1,y = 1},{x = -5,y = 0}}) {
			p:=world.site_world(&site,local)
			if !game.cell_blocks_movement(&e.rs.room,p) {e.rs.room.player.position=p;break}
		}
		break
	}
}

// All six Cyber roles in an actual workshop. Only the smoke's encounter is
// staged: terrain, camera, collision, drawing and subsequent AI are live.
@(private)
expedition_smoke_cartoon :: proc(e:^run.Expedition_Session,biome:campaign.Biome=.Cyber) {
	expedition_smoke_world(e,biome)
	e.map_open=false;e.inventory_open=false;e.world.mounted=false;e.message_timer=0
	room:=&e.rs.room
	for &site in e.world.sites[:e.world.site_count] {
		if site.kind!=.Workshop {continue}
		p:=world.site_world(&site,{x = 0,y = 2})
		if !game.cell_blocks_movement(room,p) {room.player.position=p;break}
	}
	started:=game.begin_expedition_encounter(room)
	assert(started,"The native cartoon smoke must enter combat")
	offsets:=[6]grid.Position{{x = -3,y = 0},{x = -2,y = 2},{x = 0,y = 3},{x = 2,y = 2},{x = 3,y = 0},{x = 0,y = -3}}
	for offset,i in offsets {
		placed:=false
		search:for radius in 0..=4 {for dy in -radius..=radius {for dx in -radius..=radius {
			if max(abs(dx),abs(dy))!=radius {continue}
			cell:=grid.offset(game.add_position(room.player.position,offset),dx,dy)
			if game.cell_blocks_movement(room,cell) || cell==room.player.position {continue}
			if _,ok:=game.spawn_enemy(room,{position=cell,health=20,attack=1,archetype=game.Enemy_Archetype(i)});ok {placed=true;break search}
		}}}
		assert(placed,"No free cell for an actor role in the native smoke")
	}
}

// Actual framebuffer details of each role, including the walking/attacking
// presentations. No synthetic image is used as rendering evidence.
@(private)
expedition_capture_cartoon_details :: proc(e:^run.Expedition_Session,step:int,biome:campaign.Biome=.Cyber) {
	r:=&e.rs.iso_renderer
	for actor,i in r.tactical.snapshot.enemies[:min(6,r.tactical.snapshot.enemy_count)] {
		p:=render.tactical_project(r,{actor.position.x+.5,actor.position.y+.5},1)
		name:=fmt.ctprintf("odin_pp_cartoncino_ruolo_%d_%d.png",i,step) if biome==.Cyber else fmt.ctprintf("odin_pp_costumi_%v_ruolo_%d_%d.png",biome,i,step)
		artifacts.screenshot(name,
			{(p.x-65)/r.canvas_width,(p.y-85)/r.canvas_height,130/r.canvas_width,155/r.canvas_height})
	}
}
