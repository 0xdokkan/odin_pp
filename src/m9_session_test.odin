package main

import "core:encoding/json"
import "core:os"
import "core:testing"
import engine "engine"
import fight "fight"
import render "render"
import view "view"

@(test)
test_m9_session_edges_survive_zero_tick_and_are_consumed_once :: proc(t: ^testing.T) {
	s: M9_Session
	begin_m9_session(&s,.Ring,true,true)
	defer destroy_m9_session(&s)
	s.ring.dummy=true
	step_m9_session(&s,0,{focused=true,ring={jab=true}})
	testing.expect_value(t,s.ring.ticks,u64(0))
	testing.expect(t,s.pending.ring.jab)
	step_m9_session(&s,f32(engine.FIXED_DT*8),{focused=true})
	testing.expect_value(t,s.ring.ticks,u64(8))
	testing.expect_value(t,s.ring.fighters[0].move_serial,u32(1))
	testing.expect(t,!s.pending.ring.jab)
	for _ in 0..<60 {step_m9_session(&s,f32(engine.FIXED_DT),{focused=true})}
	testing.expect_value(t,s.ring.fighters[0].move_serial,u32(1))
	begin_m9_session(&s,.FPS,true,true)
	step_m9_session(&s,0,{focused=true,control=.Pause})
	s.fps.player.ammo=4
	step_m9_session(&s,0,{focused=true,fps={look_yaw=0.1,look_pitch=0.05,reload_pressed=true}})
	step_m9_session(&s,0,{focused=true,fps={look_yaw=0.2}})
	step_m9_session(&s,f32(engine.FIXED_DT*8),{focused=true})
	testing.expect(t,abs(s.fps.player.yaw-0.3)<0.00001)
	testing.expect(t,abs(s.fps.player.pitch-0.05)<0.00001)
	testing.expect_value(t,s.pending.fps.look_yaw,f32(0))
	testing.expect(t,!s.pending.fps.reload_pressed)
	testing.expect(t,s.fps.player.reload_remaining>1 && s.fps.player.reload_remaining<1.2)
}

@(test)
test_m9_session_pause_and_focus_drop_queued_actions :: proc(t: ^testing.T) {
	s: M9_Session
	begin_m9_session(&s,.Ring,true,true)
	defer destroy_m9_session(&s)
	s.ring.dummy=true
	step_m9_session(&s,0.005,{focused=true,ring={jab=true}})
	testing.expect(t,s.pending.ring.jab)
	step_m9_session(&s,10,{focused=false,ring={heavy=true}})
	testing.expect(t,s.paused)
	testing.expect_value(t,s.pending,M9_Tick_Input{})
	testing.expect_value(t,s.clock.accumulator,f64(0))
	before:=s.ring
	step_m9_session(&s,10,{focused=true,ring={grab=true}})
	testing.expect_value(t,s.ring,before)
	step_m9_session(&s,0,{focused=true,control=.Pause})
	step_m9_session(&s,f32(engine.FIXED_DT),{focused=true})
	testing.expect_value(t,s.ring.fighters[0].move_serial,u32(0))
	testing.expect_value(t,s.ring.ticks,u64(1))
	step_m9_session(&s,0,{focused=true,control=.Pause})
	step_m9_session(&s,0.5,{focused=true,control=.Step,ring={jab=true}})
	testing.expect(t,s.paused)
	testing.expect_value(t,s.ring.ticks,u64(2))
	testing.expect_value(t,s.ring.fighters[0].move_serial,u32(1))
	step_m9_session(&s,0,{focused=true,control=.Leave})
	testing.expect_value(t,s.mode,render.M9_Kind.None)
	testing.expect(t,!step_m9_session(&s,1,{focused=true}))
}

@(test)
test_m9_session_ring_and_fps_replay_restore_exact_simulations :: proc(t: ^testing.T) {
	s: M9_Session
	defer destroy_m9_session(&s)
	for kind in ([2]render.M9_Kind{.Ring,.FPS}) {
		begin_m9_session(&s,kind,true,true)
		if s.paused {step_m9_session(&s,0,{focused=true,control=.Pause})}
		step_m9_session(&s,0,{focused=true,control=.Record})
		for tick in 0..<240 {
			input:=M9_Input{focused=true,
				ring={move={0.3,0,0.1},jab=tick%40==0,guard=tick%80>50},
				fps={move_right=0.25,look_yaw=0.002,fire_held=tick%25<5,reload_pressed=tick==130}}
			step_m9_session(&s,f32(engine.FIXED_DT),input)
		}
		step_m9_session(&s,0,{focused=true,control=.Record})
		expected_ring,expected_fps:=s.ring,s.fps
		testing.expect_value(t,len(s.record),240)
		step_m9_session(&s,0,{focused=true,control=.Replay})
		for _ in 0..<300 {
			if !s.replaying {break}
			// Live commands cannot alter replay playback.
			step_m9_session(&s,f32(engine.FIXED_DT),{focused=true,ring={grab=true},fps={look_yaw=2}})
		}
		testing.expect(t,!s.replaying && s.paused)
		testing.expect_value(t,s.replay_at,240)
		if kind==.Ring {testing.expect_value(t,s.ring,expected_ring)}
		else {testing.expect_value(t,s.fps,expected_fps)}
	}
}

@(test)
test_m9_session_move_file_round_trip_and_invalid_set_is_atomic :: proc(t: ^testing.T) {
	temp_dir, temp_error := os.temp_directory(context.temp_allocator)
	testing.expect(t, temp_error == nil)
	path, join_error := os.join_path({temp_dir, "odin-pp-m9-moves-regression.json"}, context.temp_allocator)
	testing.expect(t, join_error == nil)
	defer os.remove(path)
	state:=fight.begin(true,true)
	move:=state.moves[.Jab]
	move.damage=4
	testing.expect(t,fight.set_move(&state,.Jab,move))
	testing.expect(t,save_m9_moves(path,&state))
	restored:=fight.begin(true,true)
	testing.expect(t,load_m9_moves(path,&restored))
	testing.expect_value(t,restored.moves,state.moves)
	before:=restored
	file:=M9_Move_File{1,state.moves[.Jab],state.moves[.Heavy],state.moves[.Grab]}
	file.jab.damage=6
	file.grab.radius=9
	bytes,error:=json.marshal(file)
	testing.expect(t,error==nil)
	defer delete(bytes)
	testing.expect(t,os.write_entire_file(path,bytes)==nil)
	testing.expect(t,!load_m9_moves(path,&restored))
	testing.expect_value(t,restored,before)
	testing.expect(t,os.write_entire_file(path,"{broken")==nil)
	testing.expect(t,!load_m9_moves(path,&restored))
	testing.expect_value(t,restored,before)
}

@(test)
test_m9_startup_tuning_preserves_cancel_timing_and_active_move :: proc(t: ^testing.T) {
	s: M9_Session
	begin_m9_session(&s,.Ring,true,true)
	defer destroy_m9_session(&s)
	s.ring.dummy=true
	step_m9_session(&s,f32(engine.FIXED_DT),{focused=true,ring={jab=true}})
	before:=s.ring.fighters[0].active_move
	for _ in 0..<4 {step_m9_session(&s,0,{focused=true,control=.Startup_Up})}
	tuned:=s.ring.moves[.Jab]
	testing.expect_value(t,tuned.startup,before.startup+4)
	testing.expect_value(t,tuned.cancel_from,tuned.startup+before.active)
	testing.expect_value(t,tuned.cancel_until-tuned.cancel_from,before.cancel_until-before.cancel_from)
	testing.expect_value(t,s.ring.fighters[0].active_move,before)
	for _ in 0..<4 {step_m9_session(&s,0,{focused=true,control=.Startup_Down})}
	testing.expect_value(t,s.ring.moves[.Jab],before)
}

@(test)
test_m9_session_mouse_controls_bounds_enablement_and_mode_lifecycle :: proc(t: ^testing.T) {
	renderer:=render.Renderer{canvas_width=960,canvas_height=540}
	s: M9_Session
	begin_m9_session(&s,.Arena,true,true)
	defer destroy_m9_session(&s)
	for control in render.M9_Control {
		v:=m9_view(&s)
		if !render.m9_control_enabled(v,control) {continue}
		bounds:=render.m9_control_bounds(&renderer,control)
		testing.expect(t,bounds.x>=0 && bounds.y>=0 && bounds.x+bounds.width<=960 && bounds.y+bounds.height<=540)
		center:=view.Vec2{bounds.x+bounds.width/2,bounds.y+bounds.height/2}
		testing.expect_value(t,render.m9_control_at_point(&renderer,v,center),control)
	}
	for control in ([3]render.M9_Control{.Ring,.FPS,.Arena}) {
		step_m9_session(&s,0,{focused=true,control=control})
		expected:=render.M9_Kind.Ring if control==.Ring else render.M9_Kind.FPS if control==.FPS else render.M9_Kind.Arena
		testing.expect_value(t,s.mode,expected)
		testing.expect_value(t,len(s.record),0)
	}
	step_m9_session(&s,0,{focused=true,control=.Record})
	testing.expect(t,!render.m9_control_enabled(m9_view(&s),.FPS))
	testing.expect(t,!render.m9_control_enabled(m9_view(&s),.Startup_Up))
	before:=s.mode
	step_m9_session(&s,0,{focused=true,control=.FPS})
	testing.expect_value(t,s.mode,before)
	step_m9_session(&s,0,{focused=true,control=.Leave})
	testing.expect_value(t,s.mode,render.M9_Kind.None)
}
