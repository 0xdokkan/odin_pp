package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import engine "engine"
import fight "fight"
import shooter "shooter"
import render "render"
import view "view"
import rl "vendor:raylib"

M9_MAX_RECORD_TICKS :: 18000
M9_MOVES_PATH :: "odin_pp_moves.json"
M9_Tick_Input :: struct {ring: fight.Input, fps: shooter.Input}
M9_Input :: struct {
	focused: bool,
	control: render.M9_Control,
	ring: fight.Input,
	fps: shooter.Input,
}
M9_Session :: struct {
	mode: render.M9_Kind,
	practice, tools, paused, debug: bool,
	clock: engine.Fixed_Clock,
	ring: fight.State,
	fps, previous_fps: shooter.State,
	selected_move: fight.Action,
	level_index: int,
	pending: M9_Tick_Input,
	record: [dynamic]M9_Tick_Input,
	record_ring: fight.State,
	record_fps: shooter.State,
	record_mode: render.M9_Kind,
	recording, replaying: bool,
	replay_at: int,
	cursor_captured, fire_latched: bool,
	status: string,
}

destroy_m9_session :: proc(s: ^M9_Session) {
	if s == nil {return}
	delete(s.record)
	s^ = {}
}

m9_reset :: proc(s: ^M9_Session) {
	s.clock, s.pending = {}, {}
	if s.mode == .FPS {
		s.fps = shooter.create(s.level_index)
		s.previous_fps = s.fps
	} else {
		moves := s.ring.moves
		s.ring = fight.begin(s.practice,s.mode == .Arena)
		if s.mode == .Arena || s.level_index%2 != 0 {
			level := engine.create_courtyard_level()
			if s.mode == .Arena && s.level_index%2 != 0 {level=engine.create_gallery_level()}
			s.ring.world = level.world
			for &fighter,i in s.ring.fighters {fighter.position=level.spawns[i];fighter.previous=fighter.position}
			for i in 0..<2 {engine.add_actor(&s.ring.world,fight.collision_body(&s.ring,i))}
		}
		for action in ([3]fight.Action{.Jab,.Heavy,.Grab}) {
			if fight.move_valid(moves[action]) {fight.set_move(&s.ring,action,moves[action])}
		}
	}
}

begin_m9_session :: proc(s: ^M9_Session, mode: render.M9_Kind, practice: bool = true, tools: bool = false) {
	destroy_m9_session(s)
	s.mode,s.practice,s.tools,s.debug = mode,practice,tools,tools
	s.selected_move=.Jab
	s.paused=mode == .FPS
	m9_reset(s)
}

m9_view :: proc(s: ^M9_Session) -> render.M9_View {
	return {kind=s.mode,practice=s.practice,tools=s.tools,paused=s.paused,debug=s.debug,
		alpha=engine.clock_alpha(&s.clock),steps=int(s.clock.ticks),recorded=len(s.record),replay_at=s.replay_at,
		recording=s.recording,replaying=s.replaying,captured=s.cursor_captured,fps_active=s.fps.phase == .Active,
		move=s.selected_move,status=s.status}
}

M9_Move_File :: struct {version: int, jab,heavy,grab: fight.Move_Def}

save_m9_moves :: proc(path: string, state: ^fight.State) -> bool {
	file := M9_Move_File{1,state.moves[.Jab],state.moves[.Heavy],state.moves[.Grab]}
	bytes,error := json.marshal(file)
	if error != nil {return false}
	defer delete(bytes)
	temporary := fmt.tprintf("%s.tmp",path)
	defer os.remove(temporary)
	if os.write_entire_file(temporary,bytes) != nil {return false}
	return os.rename(temporary,path) == nil
}

load_m9_moves :: proc(path: string, state: ^fight.State) -> bool {
	bytes,error := os.read_entire_file(path,context.allocator)
	if error != nil {return false}
	defer delete(bytes)
	if len(bytes)>16384 {return false}
	file: M9_Move_File
	if json.unmarshal(bytes,&file) != nil || file.version != 1 ||
	   !fight.move_valid(file.jab) || !fight.move_valid(file.heavy) || !fight.move_valid(file.grab) {return false}
	// Validate on a copy: a malformed definition cannot partially change a set.
	staged := state^
	if !fight.set_move(&staged,.Jab,file.jab) || !fight.set_move(&staged,.Heavy,file.heavy) || !fight.set_move(&staged,.Grab,file.grab) {return false}
	state^=staged
	return true
}

m9_control :: proc(s: ^M9_Session, control: render.M9_Control) -> bool {
	if !render.m9_control_enabled(m9_view(s),control) {return false}
	switch control {
	case .Leave: s.mode=.None; s.paused=true; s.pending={}; s.clock.accumulator=0
	case .Pause: s.paused=!s.paused; s.pending={}; s.clock.accumulator=0
	case .Resume_FPS:
		s.paused=false; s.pending={}; s.clock.accumulator=0
		s.fire_latched=true // The click enters the scene; release before firing.
	case .Debug: s.debug=!s.debug
	case .Step: return true
	case .Reset: m9_reset(s)
	case .Arena,.Ring,.FPS:
		mode := render.M9_Kind.Arena if control == .Arena else render.M9_Kind.Ring if control == .Ring else render.M9_Kind.FPS
		begin_m9_session(s,mode,true,s.tools)
	case .Level: s.level_index=(s.level_index+1)%2; m9_reset(s)
	case .Move:
		s.selected_move=.Heavy if s.selected_move == .Jab else .Grab if s.selected_move == .Heavy else .Jab
	case .Startup_Down,.Startup_Up,.Damage_Down,.Damage_Up:
		move := s.ring.moves[s.selected_move]
		if control == .Startup_Down || control == .Startup_Up {
			startup := clamp(move.startup+(-1 if control == .Startup_Down else 1),1,60)
			// Keep cancels at the same offset into recovery when tuning startup.
			if move.cancel_from >= 0 {
				move.cancel_from+=startup-move.startup
				move.cancel_until+=startup-move.startup
			}
			move.startup=startup
		} else {move.damage=clamp(move.damage+(-1 if control == .Damage_Down else 1),i32(1),i32(12))}
		s.status="Mossa aggiornata al prossimo attacco." if fight.set_move(&s.ring,s.selected_move,move) else "Tempi incompatibili con la finestra combo."
	case .Save: s.status="Mosse salvate in odin_pp_moves.json" if save_m9_moves(M9_MOVES_PATH,&s.ring) else "Salvataggio mosse non riuscito."
	case .Load: s.status="Mosse caricate." if load_m9_moves(M9_MOVES_PATH,&s.ring) else "File mosse assente o non valido: dati preservati."
	case .Dummy: s.ring.dummy=!s.ring.dummy
	case .Record:
		s.recording=!s.recording
		if s.recording {
			clear(&s.record)
			s.record_ring,s.record_fps,s.record_mode=s.ring,s.fps,s.mode
			s.pending={}
			s.status="Registrazione degli input di simulazione."
		} else {s.status="Registrazione pronta: REPLAY ripete gli stessi input."}
	case .Replay:
		s.ring,s.fps,s.mode=s.record_ring,s.record_fps,s.record_mode
		s.previous_fps=s.fps
		s.replaying,s.replay_at,s.paused=true,0,false
		s.clock,s.pending={},{}
	case .None:
	}
	return false
}

m9_tick :: proc(s: ^M9_Session, input: M9_Tick_Input) {
	command := input
	if s.replaying {
		if s.replay_at>=len(s.record) {s.replaying=false;s.paused=true;return}
		command=s.record[s.replay_at]; s.replay_at+=1
	} else if s.recording {
		if len(s.record)<M9_MAX_RECORD_TICKS {append(&s.record,command)}
		else {s.recording=false;s.status="Limite registrazione: 5 minuti. Replay disponibile."}
	}
	if s.mode == .FPS {
		s.previous_fps=s.fps
		shooter.step(&s.fps,command.fps)
	} else {fight.tick(&s.ring,command.ring)}
	if s.replaying && s.replay_at>=len(s.record) {s.replaying=false;s.paused=true;s.status="Replay completato."}
}

// The sole owner of free-mode time and inputs. No renderer queue can stall a
// fighter. Edges survive zero-tick frames and are consumed once during catchup.
step_m9_session :: proc(s: ^M9_Session, dt: f32, input: M9_Input) -> bool {
	if s == nil || s.mode == .None {return false}
	if !input.focused {
		s.paused=true; s.pending={}
		engine.advance_clock(&s.clock,0,true)
		return true
	}
	single := m9_control(s,input.control)
	if s.mode == .None {return true}
	if (s.paused && !single) || input.control != .None && !single {
		s.pending={}; engine.advance_clock(&s.clock,0,true)
		return true
	}
	s.pending.ring.move=input.ring.move
	s.pending.ring.guard=input.ring.guard
	s.pending.ring.jab=s.pending.ring.jab || input.ring.jab
	s.pending.ring.heavy=s.pending.ring.heavy || input.ring.heavy
	s.pending.ring.dodge=s.pending.ring.dodge || input.ring.dodge
	s.pending.ring.grab=s.pending.ring.grab || input.ring.grab
	s.pending.fps.move_forward,s.pending.fps.move_right=input.fps.move_forward,input.fps.move_right
	s.pending.fps.fire_held=s.pending.fps.fire_held || input.fps.fire_held
	s.pending.fps.reload_pressed=s.pending.fps.reload_pressed || input.fps.reload_pressed
	if engine.finite(input.fps.look_yaw) {s.pending.fps.look_yaw+=input.fps.look_yaw}
	if engine.finite(input.fps.look_pitch) {s.pending.fps.look_pitch+=input.fps.look_pitch}
	steps := 1 if single else engine.advance_clock(&s.clock,f64(dt))
	if single {s.clock.ticks+=1}
	for step in 0..<steps {
		m9_tick(s,s.pending)
		s.pending.ring.jab,s.pending.ring.heavy,s.pending.ring.dodge,s.pending.ring.grab=false,false,false,false
		s.pending.fps.reload_pressed=false
		s.pending.fps.fire_held=input.fps.fire_held
		s.pending.fps.look_yaw,s.pending.fps.look_pitch=0,0
		if s.paused {
			s.clock.ticks-=u64(steps-step-1)
			s.clock.accumulator=0
			break
		}
	}
	return true
}

update_m9_cursor :: proc(s: ^M9_Session) {
	want := s.mode == .FPS && !s.paused && !s.replaying && s.fps.phase == .Active && rl.IsWindowFocused()
	if want == s.cursor_captured {return}
	s.cursor_captured=want
	s.fire_latched=true
	if want {rl.DisableCursor()} else {rl.EnableCursor()}
	rl.GetMouseDelta() // Drop the mode-change warp; it is never an aim command.
}

sample_m9_input :: proc(s: ^M9_Session, renderer: ^render.Renderer, mouse: view.Vec2, inside: bool) -> M9_Input {
	input := M9_Input{focused=rl.IsWindowFocused()}
	if !input.focused {return input}
	if rl.IsKeyPressed(.ESCAPE) {input.control=.Pause;return input}
	if !s.cursor_captured && inside && rl.IsMouseButtonPressed(.LEFT) {
		input.control=render.m9_control_at_point(renderer,m9_view(s),mouse)
		if input.control != .None {return input}
	}
	x := f32(1) if rl.IsKeyDown(.D) else f32(0)
	x-=1 if rl.IsKeyDown(.A) else 0
	z := f32(1) if rl.IsKeyDown(.S) else f32(0)
	z-=1 if rl.IsKeyDown(.W) else 0
	input.ring={move={x,0,z},jab=rl.IsKeyPressed(.ONE),heavy=rl.IsKeyPressed(.TWO),grab=rl.IsKeyPressed(.THREE),
		dodge=rl.IsKeyPressed(.SPACE),guard=rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)}
	if s.mode == .FPS && s.cursor_captured {
		delta := rl.GetMouseDelta()
		if !rl.IsMouseButtonDown(.LEFT) {s.fire_latched=false}
		input.fps={move_forward=-z,move_right=x,look_yaw=-delta.x*0.0025,look_pitch=-delta.y*0.0025,
			fire_held=rl.IsMouseButtonDown(.LEFT) && !s.fire_latched,reload_pressed=rl.IsKeyPressed(.R)}
	}
	return input
}
