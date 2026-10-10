package main

import host "engine/host"
import input "engine/input"
import engine "engine"
import fight "fight"
import render "render"

// One scene for the menu and the room challenge. Only the caller settles
// run unlocks; standalone retries can never mutate the roguelike profile.
Ring_Input_Action :: enum { Left, Right, Forward, Back, Jab, Heavy, Grab, Dodge, Guard }
Ring_Minigame :: struct {
	session: M9_Session,
	renderer: ^render.Renderer,
	assets_ready, demo: bool,
	actions: input.Action_Map(Ring_Input_Action),
	controls: input.State(Ring_Input_Action),
	gate: input.Resume_Gate(Ring_Input_Action),
}

ring_minigame_info :: proc() -> host.Minigame_Info {
	return {id="ring", title="Il Ring delle Ombre", genre="Duello 3D",
		tagline="Sfida il campione. Schiva il colpo, spezza la guardia e chiudi con una presa. Nella run, le vittorie sbloccano carte.",
		controls="WASD / stick: muovi   1 / X: pugno   2 / Y: pesante\n3 / RB: presa   Spazio / A: schiva   Shift / LB: para",
		accent=render.GOTHIC_BLUE, create=ring_minigame_create}
}

ring_minigame_actions :: proc() -> input.Action_Map(Ring_Input_Action) {
	m := input.make_map(Ring_Input_Action)
	input.bind_all(&m,Ring_Input_Action.Left,input.key(.A),input.key(.LEFT),input.pad_axis(.LEFT_X,false))
	input.bind_all(&m,Ring_Input_Action.Right,input.key(.D),input.key(.RIGHT),input.pad_axis(.LEFT_X,true))
	input.bind_all(&m,Ring_Input_Action.Forward,input.key(.W),input.key(.UP),input.pad_axis(.LEFT_Y,false))
	input.bind_all(&m,Ring_Input_Action.Back,input.key(.S),input.key(.DOWN),input.pad_axis(.LEFT_Y,true))
	input.bind_all(&m,Ring_Input_Action.Jab,input.key(.ONE),input.pad(.RIGHT_FACE_LEFT))
	input.bind_all(&m,Ring_Input_Action.Heavy,input.key(.TWO),input.pad(.RIGHT_FACE_UP))
	input.bind_all(&m,Ring_Input_Action.Grab,input.key(.THREE),input.pad(.RIGHT_TRIGGER_1))
	input.bind_all(&m,Ring_Input_Action.Dodge,input.key(.SPACE),input.pad(.RIGHT_FACE_DOWN))
	input.bind_all(&m,Ring_Input_Action.Guard,input.key(.LEFT_SHIFT),input.key(.RIGHT_SHIFT),input.pad(.LEFT_TRIGGER_1))
	return m
}

ring_minigame_create :: proc(config: host.Minigame_Config) -> host.Scene {
	g := new(Ring_Minigame)
	g.renderer = new(render.Renderer)
	g.actions = ring_minigame_actions()
	return host.minigame_scene(ring_minigame_info(), {
		data=g, reset=ring_minigame_reset, step=ring_minigame_step, draw=ring_minigame_draw,
		score=ring_minigame_score, destroy=ring_minigame_destroy, music=.Action,
	}, config)
}

ring_minigame_reset :: proc(data: rawptr, config: host.Minigame_Config) {
	g := cast(^Ring_Minigame)data
	begin_m9_session(&g.session,.Ring,false,false)
	input.suspend(&g.controls,&g.gate)
}

ring_minigame_command :: proc(g: ^Ring_Minigame, sample: input.Sample(Ring_Input_Action), dt: f32) -> fight.Input {
	if input.advance_resumable(&g.controls,&g.gate,sample,dt,bit_set[Ring_Input_Action]{}) {return {}}
	v := input.vector(&g.controls,Ring_Input_Action.Left,Ring_Input_Action.Right,Ring_Input_Action.Forward,Ring_Input_Action.Back)
	return {move={v.x,0,v.y}, jab=.Jab in g.controls.pressed, heavy=.Heavy in g.controls.pressed,
		grab=.Grab in g.controls.pressed, dodge=.Dodge in g.controls.pressed, guard=.Guard in g.controls.down}
}

ring_minigame_bot :: proc(state: ^fight.State) -> fight.Input {
	distance := fight.distance_squared(state.fighters[0].position,state.fighters[1].position)
	return {move=engine.vec_sub(state.fighters[1].position,state.fighters[0].position),
		jab=distance<1.2*1.2 && state.fighters[0].action==.Idle}
}

ring_minigame_advance :: proc(g: ^Ring_Minigame, dt: f32, playing: bool, command: fight.Input) -> host.Round_Status {
	if !playing {
		input.suspend(&g.controls,&g.gate)
		step_m9_session(&g.session,0,{focused=false})
	} else {
		g.session.paused=false
		step_m9_session(&g.session,dt,{focused=true,ring=command})
	}
	switch g.session.ring.result {
	case .Active: return .Playing
	case .Won: return .Won
	case .Lost: return .Lost
	}
	return .Playing
}

ring_minigame_step :: proc(data: rawptr, frame: ^host.Frame, playing: bool) -> host.Round_Status {
	g := cast(^Ring_Minigame)data
	command: fight.Input
	if playing && frame.focused {
		command=ring_minigame_bot(&g.session.ring) if g.demo else ring_minigame_command(g,input.sample(&g.actions),frame.dt)
	}
	render.advance_sprite_assets(&g.renderer.sprite_assets,frame.dt)
	return ring_minigame_advance(g,frame.dt,playing && frame.focused,command)
}

ring_minigame_draw :: proc(data: rawptr, frame: ^host.Frame) {
	g := cast(^Ring_Minigame)data
	r := g.renderer
	r.canvas_width,r.canvas_height=frame.canvas.width,frame.canvas.height
	if !g.assets_ready {
		r.tactical.enabled=true
		render.create_tactical_assets(r)
		g.assets_ready=true
	}
	v := m9_view(&g.session)
	v.hosted=true
	render.draw_m9_fight(r,&g.session.ring,v)
}

ring_minigame_score :: proc(data: rawptr) -> (i64,u8) {
	g := cast(^Ring_Minigame)data
	s := &g.session.ring
	if s.result != .Won {return i64(s.landed_hits[0]*50),0}
	health := s.fighters[0].health
	stars := u8(3) if health>=6 else u8(2) if health>=3 else u8(1)
	return 1000+i64(health)*100+i64(s.successful_throws)*150,stars
}

ring_minigame_destroy :: proc(data: rawptr) {
	g := cast(^Ring_Minigame)data
	if g.assets_ready {render.destroy_tactical_assets(g.renderer)}
	free(g.renderer)
	destroy_m9_session(&g.session)
	free(g)
}
