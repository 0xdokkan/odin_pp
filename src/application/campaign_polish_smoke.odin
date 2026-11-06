package application

import "core:fmt"
import "core:os"
import rl "vendor:raylib"
import artifacts "../devtools/artifacts"
import host "../engine/host"
import grid "../engine/grid"
import input "../engine/input"
import game "../game"
import run "../run"
import render "../render"

// A native QA route through the existing expedition, not a separate ruleset.
// The usual smoke owns an unsaved campaign. Only its initial encounter and
// device inputs are staged; countdowns, costumes and panels use the real scene.
@(private)
Expedition_Polish_Capture :: struct {
	wrapped: host.Scene,
	frame, captured: int,
	target: u32,
	intent_origin: grid.Position,
	watching, complete: bool,
}

@(private)
expedition_enable_polish_smoke :: proc(scene: ^host.Scene) {
	s := new(Expedition_Polish_Capture)
	s.wrapped = scene^
	e := cast(^run.Expedition_Session)scene.data
	expedition_smoke_workshop(e,.West)
	room := &e.rs.room
	started := game.begin_expedition_encounter(room)
	expedition_polish_require(started,"native polish smoke did not enter combat")
	// Put one real Chaser in front of the player, where its costume remains
	// visible. The AI chooses the attack and advances its own countdown.
	placed := false
	for offset in ([5]grid.Position{{y=1},{x=1,y=1},{x=-1,y=1},{y=2},{x=1,y=2}}) {
		cell := game.add_position(room.player.position,offset)
		if game.cell_blocks_movement(room,cell) { continue }
		if _,ok := game.spawn_enemy(room,{position=cell,health=20,attack=1,archetype=.Chaser});ok {
			placed = true
			break
		}
	}
	expedition_polish_require(placed,"no foreground cell for the native polish smoke")
	rl.SetWindowSize(1280,720)
	scene^ = {name="expedition-smoke", data=s, opaque=true, modal=true,
		update=expedition_polish_update, draw=expedition_polish_draw,
		after_present=expedition_polish_present, destroy=expedition_polish_destroy}
}

@(private)
expedition_polish_require :: proc(ok: bool, message: string) {
	if !ok { fmt.eprintln("EXPEDITION POLISH FAILED:",message); os.exit(2) }
}

@(private)
expedition_polish_update :: proc(data: rawptr, frame: ^host.Frame) {
	s := cast(^Expedition_Polish_Capture)data
	e := cast(^run.Expedition_Session)s.wrapped.data
	f := frame^
	devices := input.Device_Snapshot{focused=true}
	f.devices, f.dt, f.focused, f.window_focused = &devices, 1.0/60.0, true, true
	f.mouse, f.mouse_inside = {-1,-1}, false
	// Deliberate keyboard edges: no held gameplay key crosses these panels.
	key: rl.KeyboardKey
	switch s.frame {
	case 5:key=.Z
	case 10:key=.ESCAPE
	case 15:key=.U
	case 20:key=.ESCAPE
	case 25,30:key=.TAB
	case 35:
		f.focused, f.window_focused, devices.focused = false,false,false
	}
	if key != rl.KeyboardKey(0) { devices.keys_pressed[key], devices.keys_down[key] = true,true }
	s.wrapped.update(s.wrapped.data,&f)
	switch s.frame {
	case 5,15:expedition_polish_require(e.inventory_open,"inventory/character did not open")
	case 10,20:expedition_polish_require(!e.inventory_open,"inventory/character did not close")
	case 25:expedition_polish_require(e.map_open,"map did not open")
	case 30:expedition_polish_require(!e.map_open,"map did not close")
	case 35:expedition_polish_require(!e.rs.gameplay_buffer.has_pending,"focus retained pending input")
	}
	if key != rl.KeyboardKey(0) || s.frame == 35 {
		fmt.printf("EXPEDITION POLISH INPUT frame=%d key=%v inventory=%v map=%v pending=%v\n",s.frame,key,e.inventory_open,e.map_open,e.rs.gameplay_buffer.has_pending)
	}
}

@(private)
expedition_polish_draw :: proc(data: rawptr, frame: ^host.Frame) {
	s := cast(^Expedition_Polish_Capture)data
	s.wrapped.draw(s.wrapped.data,frame)
}

@(private)
expedition_polish_present :: proc(data: rawptr, frame: ^host.Frame) {
	s := cast(^Expedition_Polish_Capture)data
	e := cast(^run.Expedition_Session)s.wrapped.data
	room, r := &e.rs.room, &e.rs.iso_renderer
	if s.frame >= 40 {
		for &enemy in room.enemies {
			if enemy.archetype != .Chaser || enemy.intent.kind != .Attack { continue }
			left := game.tactical_enemy_seconds(room,&enemy)
			total := game.tactical_enemy_intent_seconds(&enemy)
			if !s.watching {
				if left < total*.8 { continue }
				s.target, s.intent_origin, s.watching = enemy.id, enemy.intent.origin, true
			}
			if enemy.id != s.target { continue }
			expedition_polish_require(enemy.intent.origin == s.intent_origin,"tracked attack changed before its peak")
			capture := s.captured == 0 || s.captured == 1 && left <= total*.5 || s.captured == 2 && left <= render.FOE_GLOW_PEAK
			if !capture { break }
			color, amount := render.foe_glow(r,game.enemy_entity(enemy.id))
			expedition_polish_require(amount > 0 && color == render.FOE_GLOW_RED,"actual attack has no red glow")
			if s.captured == 2 { expedition_polish_require(amount == 1,"final attack window did not reach full glow") }
			fmt.printf("EXPEDITION POLISH GLOW capture=%d frame=%d enemy=%d left=%.6f total=%.6f amount=%.6f color=%v\n",s.captured,s.frame,enemy.id,left,total,amount,color)
			artifacts.screenshot(fmt.ctprintf("odin_pp_polish_glow_West_%d.png",s.captured))
			for actor in r.tactical.snapshot.enemies[:r.tactical.snapshot.enemy_count] {
				if actor.entity != game.enemy_entity(enemy.id) { continue }
				at := render.tactical_project(r,{actor.position.x+.5,actor.position.y+.5},1)
				artifacts.screenshot(fmt.ctprintf("odin_pp_polish_glow_West_%d_detail.png",s.captured),
					{(at.x-85)/r.canvas_width,(at.y-105)/r.canvas_height,170/r.canvas_width,190/r.canvas_height})
				break
			}
			s.captured += 1
			break
		}
	}
	s.frame += 1
	if s.captured == 3 { s.complete = true; fmt.println("EXPEDITION POLISH COMPLETE: real panels, focus and three stages of one attack"); host.quit(frame) }
	else if s.frame >= 1200 { expedition_polish_require(false,"attack countdown captures timed out") }
}

@(private)
expedition_polish_destroy :: proc(data: rawptr) {
	s := cast(^Expedition_Polish_Capture)data
	complete := s.complete
	s.wrapped.destroy(s.wrapped.data)
	free(s)
	if !complete { fmt.eprintln("EXPEDITION POLISH INCOMPLETE"); os.exit(2) }
}
