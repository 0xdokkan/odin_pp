package main

import "core:fmt"
import "core:math"
import app "app"
import engine "engine"
import fight "fight"
import render "render"
import shooter "shooter"
import rl "vendor:raylib"

m9_smoke_draw :: proc(window: ^app.Window, renderer: ^render.Renderer, session: ^M9_Session) {
	render.advance_sprite_assets(&renderer.sprite_assets,1.0/60.0)
	app.begin_canvas(window,render.RESIN_BACKGROUND)
	v:=m9_view(session)
	// A smoke snapshot depicts the completed simulation tick, not the old side
	// of an interpolation interval whose clock has just landed exactly on zero.
	v.alpha=1
	if session.mode==.FPS {render.draw_m9_fps(renderer,&session.fps,&session.previous_fps,v)}
	else {render.draw_m9_fight(renderer,&session.ring,v)}
	app.present(window,render.LETTERBOX_COLOR)
}

m9_smoke_capture :: proc(window: ^app.Window, renderer: ^render.Renderer, session: ^M9_Session, path: cstring) {
	// macOS screenshots read the last presented front buffer.
	for _ in 0..<3 {m9_smoke_draw(window,renderer,session)}
	rl.TakeScreenshot(path)
}

m9_smoke_tick :: proc(session: ^M9_Session, input: M9_Input = {focused=true}) {
	step_m9_session(session,f32(engine.FIXED_DT),input)
}

m9_smoke_fps_input :: proc(state: ^shooter.State) -> shooter.Input {
	input:=shooter.Input{fire_held=true,reload_pressed=state.player.ammo==0}
	for enemy in state.enemies[:state.enemy_count] {
		if enemy.health<=0 {continue}
		target:=engine.vec_add(enemy.position,{0,1.2,0})
		direction:=engine.vec_sub(target,shooter.eye_position(state))
		input.look_yaw=math.atan2(direction.x,direction.z)-state.player.yaw
		input.look_pitch=math.atan2(direction.y,math.sqrt(direction.x*direction.x+direction.z*direction.z))-state.player.pitch
		break
	}
	return input
}

run_m9_view_smoke :: proc(window: ^app.Window, renderer: ^render.Renderer) -> bool {
	if window==nil || renderer==nil {return false}
	s: M9_Session
	defer destroy_m9_session(&s)
	begin_m9_session(&s,.Arena,true,true)
	// Put two ordinary bodies on a clear lane and walk into the opponent.
	// This configures the scenario; all movement still uses normal controls.
	s.ring.fighters[0].position={-1,0,1}
	s.ring.fighters[1].position={1,0,1}
	for &fighter in s.ring.fighters {fighter.previous=fighter.position}
	fight.sync_fighters(&s.ring)
	for tick in 0..<150 {
		m9_smoke_tick(&s,{focused=true,ring={move={1,0,0}}})
		if tick%30==0 {m9_smoke_draw(window,renderer,&s)}
	}
	separation:=fight.distance_squared(s.ring.fighters[0].position,s.ring.fighters[1].position)
	if separation<4*fight.BODY_RADIUS*fight.BODY_RADIUS-0.001 ||
	   s.ring.fighters[0].position.x>=s.ring.fighters[1].position.x {
		fmt.eprintln("M9 smoke: arena body collision failed")
		return false
	}
	s.tools,s.debug=false,false
	m9_smoke_capture(window,renderer,&s,"odin_pp_m9_arena.png")
	step_m9_session(&s,0,{focused=true,control=.Ring})
	if s.mode!=.Ring {fmt.eprintln("M9 smoke: arena to ring transition failed");return false}
	// A real challenge with the regular AI and untouched health/move values.
	s.practice,s.ring.practice=false,false
	ring_captured:=false
	for tick in 0..<1800 {
		if s.ring.result!=.Active {break}
		distance:=fight.distance_squared(s.ring.fighters[0].position,s.ring.fighters[1].position)
		direction:=engine.vec_sub(s.ring.fighters[1].position,s.ring.fighters[0].position)
		m9_smoke_tick(&s,{focused=true,ring={move=direction,jab=distance<1.2*1.2 && s.ring.fighters[0].action==.Idle}})
		if !ring_captured && s.ring.landed_hits[0]>0 {
			m9_smoke_capture(window,renderer,&s,"odin_pp_m9_ring.png")
			ring_captured=true
		} else if tick%60==0 {m9_smoke_draw(window,renderer,&s)}
	}
	if s.ring.result!=.Won || !ring_captured {fmt.eprintln("M9 smoke: ring AI challenge did not end in victory");return false}
	step_m9_session(&s,0,{focused=true,control=.Leave})
	if s.mode!=.None {return false}
	// Four held poses of a real grab, plus a replay of the entire throw.
	begin_m9_session(&s,.Ring,true,true)
	s.ring.dummy=true
	s.ring.fighters[0].position={-0.5,0,0}
	s.ring.fighters[1].position={0.5,0,0}
	for &fighter in s.ring.fighters {fighter.previous=fighter.position}
	fight.sync_fighters(&s.ring)
	step_m9_session(&s,0,{focused=true,control=.Record})
	m9_smoke_tick(&s,{focused=true,ring={grab=true}})
	seen: [4]bool
	paths:=[4]cstring{"odin_pp_m9_ring_grab_0.png","odin_pp_m9_ring_grab_1.png","odin_pp_m9_ring_grab_2.png","odin_pp_m9_ring_grab_3.png"}
	for _ in 0..<150 {
		if s.ring.throw_active {
			pose:=fight.throw_pose(&s.ring)
			if !seen[pose] {
				seen[pose]=true
				s.debug=false
				m9_smoke_capture(window,renderer,&s,paths[pose])
			}
		}
		m9_smoke_tick(&s)
	}
	for captured in seen {if !captured {fmt.eprintln("M9 smoke: a grab pose was skipped");return false}}
	if s.ring.successful_throws!=1 {fmt.eprintln("M9 smoke: throw resolved incorrectly");return false}
	step_m9_session(&s,0,{focused=true,control=.Record})
	expected:=s.ring
	step_m9_session(&s,0,{focused=true,control=.Replay})
	for _ in 0..<200 {if !s.replaying {break};m9_smoke_tick(&s)}
	if s.replaying || s.ring!=expected {fmt.eprintln("M9 smoke: throw replay diverged");return false}
	s.debug=true
	m9_smoke_capture(window,renderer,&s,"odin_pp_m9_tools.png")
	step_m9_session(&s,0,{focused=true,control=.FPS})
	if s.mode!=.FPS || !s.paused {fmt.eprintln("M9 smoke: FPS entry was not paused for mouse capture");return false}
	s.tools,s.debug=false,false
	step_m9_session(&s,0,{focused=true,control=.Pause})
	// Let the AI start an honest telegraph before returning fire.
	for tick in 0..<300 {
		m9_smoke_tick(&s)
		windup:=false
		for enemy in s.fps.enemies[:s.fps.enemy_count] {windup=windup || enemy.phase==.Windup}
		if windup {break}
		if tick%60==0 {m9_smoke_draw(window,renderer,&s)}
	}
	m9_smoke_tick(&s,{focused=true,fps=m9_smoke_fps_input(&s.fps)})
	m9_smoke_capture(window,renderer,&s,"odin_pp_m9_fps.png")
	for tick in 0..<1800 {
		if s.fps.phase!=.Active {break}
		m9_smoke_tick(&s,{focused=true,fps=m9_smoke_fps_input(&s.fps)})
		if tick%60==0 {m9_smoke_draw(window,renderer,&s)}
	}
	if s.fps.phase!=.Won || s.fps.kills!=shooter.MAX_ENEMIES || s.fps.player.reserve>=30 {
		fmt.eprintln("M9 smoke: FPS wave, magazine or reload failed")
		return false
	}
	step_m9_session(&s,0,{focused=true,control=.Leave})
	if s.mode!=.None {return false}
	fmt.println("M9 native smoke PASS: continuous collision, AI ring victory, four grab poses, exact replay, FPS telegraph/reload/victory, mode return.")
	return true
}
