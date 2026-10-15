package render

import "core:math"
import "core:c"
import "core:fmt"
import engine "../engine"
import fight "../fight"
import ui "../engine/ui"
import rl "vendor:raylib"

// A moulded diorama, not an extra collision layer. All ornaments stay below
// the playing surface or outside the four physical walls of the ring.
begin_m9_ring_lighting :: proc(renderer: ^Renderer, camera: rl.Camera3D) -> bool {
	v := &renderer.tactical
	if v.light_shader.id == 0 {return false}
	eye, light := camera.position, rl.Vector3{-1.5,5,1.5}
	mode: c.int = 0
	clear := f32(0.20)
	lights := [4]rl.Vector4{{-4.6,1.2,-4.6,0.8},{4.6,1.2,-4.6,0.8},{-4.6,1.2,4.6,0.45},{4.6,1.2,4.6,0.45}}
	rl.SetShaderValue(v.light_shader,v.light_eye_location,&eye,.VEC3)
	rl.SetShaderValue(v.light_shader,v.light_position_location,&light,.VEC3)
	rl.SetShaderValue(v.light_shader,v.light_hologram_location,&mode,.INT)
	rl.SetShaderValue(v.light_shader,v.light_clear_location,&clear,.FLOAT)
	rl.SetShaderValueV(v.light_shader,v.light_accents_location,raw_data(lights[:]),.VEC4,4)
	rl.BeginShaderMode(v.light_shader)
	return true
}

draw_m9_ring_stage :: proc(renderer: ^Renderer, world: ^engine.World) {
	extent := m9_world_extent(world)
	x,z := extent.x,extent.y
	// Stepped edges, undercut and cap catch the same glossy light as the run.
	draw_resin_cube(renderer,{0,-0.76,0},x*2+1.05,0.22,z*2+1.05,RESIN_DARK)
	draw_resin_cube(renderer,{0,-0.51,0},x*2+0.74,0.44,z*2+0.74,{24,34,48,255})
	draw_resin_cube(renderer,{0,-0.265,0},x*2+0.86,0.10,z*2+0.86,RESIN_CAP)
	draw_resin_cube(renderer,{0,-0.12,0},x*2+0.55,0.19,z*2+0.55,RESIN_DARK)
	draw_resin_cube(renderer,{0,-0.04,0},x*2,0.08,z*2,{39,51,69,255})
	// Large inset panels read as a continuous fighting surface rather than
	// actionable grid cells. Their joints are fine and deliberately low contrast.
	for row in 0..<3 {for column in 0..<3 {
		px := (f32(column)-1)*(x*2/3)
		pz := (f32(row)-1)*(z*2/3)
		tint := rl.Color{45,58,76,255} if (row+column)%2 == 0 else rl.Color{41,54,72,255}
		draw_resin_cube(renderer,{px,-0.015,pz},x*2/3-0.02,0.025,z*2/3-0.02,tint)
	}}
	for sign in ([2]f32{-1,1}) {
		draw_resin_cube(renderer,{0,-0.255,sign*(z+0.432)},x*2-0.35,0.032,0.018,{55,98,139,255})
		draw_resin_cube(renderer,{sign*(x+0.432),-0.255,0},0.018,0.032,z*2-0.35,{55,98,139,255})
		for n in -3..=3 {
			p := f32(n)*1.25
			draw_resin_cube(renderer,{p,-0.53,sign*(z+0.377)},0.27,0.25,0.038,RESIN_DARK)
			draw_resin_cube(renderer,{sign*(x+0.377),-0.53,p},0.038,0.25,0.27,RESIN_DARK)
		}
	}
	for px in ([2]f32{-4.55,4.55}) {for pz in ([2]f32{-4.55,4.55}) {
		p := rl.Vector3{px,0,pz}
		draw_resin_cube(renderer,p+rl.Vector3{0,0.12,0},0.55,0.24,0.55,RESIN_CAP)
		draw_resin_cube(renderer,p+rl.Vector3{0,0.82,0},0.31,1.30,0.31,RESIN_WALL)
		for height in ([3]f32{0.45,0.87,1.29}) {
			draw_resin_cube(renderer,p+rl.Vector3{0,height,0},0.38,0.095,0.38,RESIN_CAP)
		}
		draw_resin_cube(renderer,p+rl.Vector3{0,1.53,0},0.44,0.16,0.44,RESIN_DARK)
		draw_resin_cube(renderer,p+rl.Vector3{0,1.64,0},0.28,0.075,0.28,{97,165,213,255})
		draw_resin_cube(renderer,p+rl.Vector3{0,1.74,0},0.14,0.16,0.14,RESIN_CAP)
		// Narrow indigo inlay keeps the front posts visually light.
		rl.DrawCube(p+rl.Vector3{0,1.01,0.163},0.045,0.48,0.012,{67,127,176,255})
	}}
	// The rear architecture is outside the playable walls. It frames a
	// suspended room without hiding the fighters behind interior scenery.
	for sign in ([2]f32{-1,1}) {
		p := rl.Vector3{sign*3.4,0,-z-1.12}
		draw_resin_cube(renderer,p+rl.Vector3{0,-0.4,0},0.85,0.45,0.85,RESIN_DARK)
		draw_resin_cube(renderer,p+rl.Vector3{0,0.55,0},0.56,1.50,0.56,RESIN_WALL)
		draw_resin_cube(renderer,p+rl.Vector3{0,1.35,0},0.73,0.16,0.73,RESIN_CAP)
		draw_resin_cube(renderer,p+rl.Vector3{0,1.48,0},0.42,0.12,0.42,{53,104,149,255})
		for i in 0..<3 {
			draw_resin_cube(renderer,p+rl.Vector3{f32(i-1)*0.15,1.61+f32(i%2)*0.13,0},0.07,0.23,0.07,{103,170,219,255})
		}
	}
}

// The three ropes remain attached to the physical perimeter. Front ropes are
// lower contrast to keep paper figures and attack cues easy to distinguish.
draw_m9_ring_ropes :: proc(world: ^engine.World) {
	for solid in world.solids[:world.solid_count] {
		a,b := m9_vector(solid.bounds.min),m9_vector(solid.bounds.max)
		center,size := (a+b)*0.5,b-a
		along_x := size.x>size.z
		near_camera := center.z>0 if along_x else center.x>0
		color := rl.Color{62,84,111,255} if near_camera else rl.Color{105,131,161,255}
		for y in ([3]f32{0.43,0.85,1.27}) {
			p,q := center,center
			p.y,q.y=y,y
			if along_x {p.x=-4.55;q.x=4.55} else {p.z=-4.55;q.z=4.55}
			rl.DrawCylinderEx(p,q,0.018,0.018,5,color)
		}
	}
}

// Telegraph the actual startup/active/recovery phases, with no new timers and
// no guessed AI windows. Short angular strokes preserve the paper aesthetic.
draw_m9_fight_cues :: proc(state: ^fight.State) {
	for actor,index in state.fighters {
		p := m9_vector(actor.position)
		p.y=0.035
		color := GOTHIC_BLUE if index == 0 else GOTHIC_RED
		draw_tactical_rune(p,0.42,0,color)
		if actor.action == .Guard {
			front := p+m9_vector(actor.facing)*0.53
			side := rl.Vector3{-actor.facing.z,0,actor.facing.x}*0.32
			rl.DrawLine3D(front-side,front+rl.Vector3{0,1.25,0}-side*0.5,GOTHIC_BLUE)
			rl.DrawLine3D(front+side,front+rl.Vector3{0,1.25,0}+side*0.5,GOTHIC_BLUE)
			rl.DrawLine3D(front+rl.Vector3{0,1.25,0}-side*0.5,front+rl.Vector3{0,1.25,0}+side*0.5,GOTHIC_BLUE)
		}
		if !fight.is_move(actor.action) || actor.action == .Dodge {continue}
		if actor.action_tick>=actor.active_move.startup+actor.active_move.active {continue}
		facing := math.atan2(actor.facing.z,actor.facing.x)
		radius := actor.active_move.reach+actor.active_move.radius
		cue := color_with_opacity(color,0.45) if actor.action_tick<actor.active_move.startup else color
		for segment in 0..<6 {
			a := facing-0.5+f32(segment)/6
			b := a+0.10
			rl.DrawLine3D(p+rl.Vector3{math.cos(a)*radius,0,math.sin(a)*radius},p+rl.Vector3{math.cos(b)*radius,0,math.sin(b)*radius},cue)
		}
	}
	if state.throw_active {
		pose := fight.throw_pose(state)
		attacker := m9_vector(state.fighters[state.throw_attacker].position)
		victim := m9_vector(state.fighters[state.throw_victim].position)
		if pose<=1 {
			facing := m9_vector(state.fighters[state.throw_attacker].facing)
			side := rl.Vector3{-facing.z,0,facing.x}
			for sign in ([2]f32{-1,1}) {
				a := attacker+rl.Vector3{0,0.82,0}+side*(sign*0.19)+facing*0.13
				b := victim+rl.Vector3{0,0.78,0}+side*(sign*0.19)
				rl.DrawCylinderEx(a,b,0.063,0.056,4,GOTHIC_INK)
				rl.DrawCylinderEx(a+rl.Vector3{0,0.007,0},b+rl.Vector3{0,0.007,0},0.044,0.041,4,GOTHIC_PAPER)
			}
		} else if pose == 3 {draw_tactical_rune({victim.x,0.035,victim.z},0.8,0,GOTHIC_BLUE)}
	}
	if state.hit_flash_ticks>0 {
		p := m9_vector(state.last_hit_position)
		p.y=max(p.y,f32(0.10))
		color := GOTHIC_BLUE if state.last_hit_blocked else GOTHIC_PAPER
		for i in 0..<7 {
			a := f32(i)*math.PI*2/7
			direction := rl.Vector3{math.cos(a),0.15+f32(i%3)*0.18,math.sin(a)}
			rl.DrawLine3D(p+direction*0.12,p+direction*0.40,color)
		}
	}
}

m9_ring_hint :: proc(state: ^fight.State) -> (cstring,rl.Color) {
	if state.result == .Won {return "AVVERSARI SCONFITTI" if state.roster_count > 1 else "CAMPIONE SCONFITTO",GOTHIC_BLUE}
	if state.tag_flash_ticks > 0 {return "TAG! CAMBIO SUL RING",GOTHIC_PAPER}
	if state.tag_target >= 0 {return "CORRE A DARE IL CAMBIO / FERMALO",GOTHIC_RED}
	if state.result == .Lost {return "LA SFIDA FINISCE QUI",GOTHIC_RED}
	if state.throw_active {
		names := [4]cstring{"PRESA A DUE MANI","SOLLEVA","LANCIA","IMPATTO"}
		return names[fight.throw_pose(state)],GOTHIC_PAPER
	}
	enemy := &state.fighters[1]
	if fight.is_move(enemy.action) && enemy.action != .Dodge {
		if enemy.action_tick<enemy.active_move.startup {return "ATTACCO IN ARRIVO / SCHIVA O PARA",GOTHIC_RED}
		if enemy.action_tick>=enemy.active_move.startup+enemy.active_move.active {return "CAMPIONE IN RECUPERO / CONTRATTACCA",GOTHIC_BLUE}
	}
	if state.roster_count > 1 {return "BATTILI TUTTI / UNO ALLA VOLTA",GOTHIC_MUTED}
	return "BATTI IL CAMPIONE / CERCA LA PRESA",GOTHIC_MUTED
}

draw_m9_fight_hud :: proc(renderer: ^Renderer, state: ^fight.State, v: M9_View) {
	w,h := renderer.canvas_width,renderer.canvas_height
	gothic_text(renderer,"ARENA DELLE OMBRE" if v.kind == .Arena else "IL RING DELLE OMBRE",20,16,22,GOTHIC_PAPER)
	if !v.practice {gothic_text(renderer,"QUADRATO DI TESLA / TAG MATCH" if state.roster_count > 1 else "PROVA DELLA TORRE / DUELLO",21,44,11,GOTHIC_MUTED)}
	for actor,i in state.fighters {
		x := f32(20) if i == 0 else w-246
		tactical_hud_panel({x,105,226,55},GOTHIC_BLUE if i == 0 else GOTHIC_RED)
		gothic_text(renderer,"IL VIANDANTE" if i == 0 else m9_opponent_name(state,state.active),x+10,111,14,GOTHIC_PAPER)
		gothic_text_fit(renderer,fmt.ctprintf("%d / %d",actor.health,actor.max_health),{x+155,111,61,18},14,GOTHIC_MUTED)
		ui.hud_meter(nil,{x+10,133,206,5},f32(actor.health)/f32(max(actor.max_health,1)),GOTHIC_RED)
		detail := fmt.ctprintf("%s / %df",m9_move_name(actor.action),actor.action_tick) if v.tools else m9_move_name(actor.action)
		gothic_text(renderer,detail,x+10,143,11,GOTHIC_BLUE if i == 0 else GOTHIC_MUTED)
	}
	// Tag match: one pip per opponent, lit while they can still fight.
	if state.roster_count > 1 {
		standing := 0
		for index in 0..<state.roster_count {
			down := state.roster[index].ko
			if !down {standing += 1}
			gothic_inlay(w-232+f32(index)*16,170,5,GOTHIC_STEEL if down else GOTHIC_RED)
		}
		gothic_text(renderer,fmt.ctprintf("%d IN PIEDI",standing),w-226+f32(state.roster_count)*16,163,11,GOTHIC_MUTED)
	}
	status,accent := m9_ring_hint(state)
	gothic_text_fit(renderer,status,{w*0.5-190,116,380,20},12,accent)
	if v.paused && !v.hosted {gothic_text_fit(renderer,"PAUSA / LA RUN RESTA SOSPESA",{w*0.5-175,141,350,16},11,GOTHIC_BLUE)}
	gothic_text_fit(renderer,"WASD MUOVI   1 PUGNO   2 PESANTE   3 PRESA   SPAZIO SCHIVA   SHIFT PARATA",{20,h-121 if v.tools else h-30,w-40,18},12,GOTHIC_MUTED)
	if state.result != .Active && !v.hosted {
		result_accent := GOTHIC_BLUE if state.result == .Won else GOTHIC_RED
		tactical_hud_panel({w*0.5-190,h*0.5-38,380,78},result_accent)
		gothic_text_fit(renderer,"VITTORIA" if state.result == .Won else "SCONFITTA",{w*0.5-170,h*0.5-26,340,25},24,GOTHIC_PAPER)
		gothic_text_fit(renderer,"LA TORRE RICORDA LA TUA PROVA" if state.result == .Won else "RITORNA ALLA STANZA PER CONTINUARE",{w*0.5-170,h*0.5+6,340,20},12,GOTHIC_MUTED)
	}
}
