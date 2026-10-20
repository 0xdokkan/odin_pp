package render

import "core:fmt"
import rl "vendor:raylib"
import view "../engine/view"
import fight "../fight"

M9_Kind :: enum {None, Arena, Ring, FPS}
M9_Control :: enum {None, Leave, Pause, Resume_FPS, Step, Debug, Reset, Arena, Ring, FPS, Level, Move,
	Startup_Down, Startup_Up, Damage_Down, Damage_Up, Save, Load, Record, Replay, Dummy}
M9_View :: struct {
	kind: M9_Kind,
	practice, tools, paused, debug, recording, replaying, captured: bool,
	hosted: bool,
	fps_active: bool,
	alpha: f32,
	steps, recorded, replay_at: int,
	move: fight.Action,
	status: string,
}

m9_control_bounds :: proc(renderer: ^Renderer, control: M9_Control) -> rl.Rectangle {
	w,h := renderer.canvas_width,renderer.canvas_height
	switch control {
	case .Leave: return {w-150,16,132,27}
	case .Pause: return {w-294,16,132,27}
	case .Resume_FPS: return {w/2-210,h/2-60,420,84}
	case .Step: return {20,h-86,96,25}
	case .Debug: return {126,h-86,112,25}
	case .Reset: return {248,h-86,96,25}
	case .Level: return {354,h-86,110,25}
	case .Record: return {474,h-86,118,25}
	case .Replay: return {602,h-86,110,25}
	case .Dummy: return {722,h-86,218,25}
	case .Arena: return {20,50,100,24}
	case .Ring: return {130,50,100,24}
	case .FPS: return {240,50,100,24}
	case .Move: return {20,h-52,142,25}
	case .Startup_Down: return {173,h-52,31,25}
	case .Startup_Up: return {272,h-52,31,25}
	case .Damage_Down: return {317,h-52,31,25}
	case .Damage_Up: return {408,h-52,31,25}
	case .Save: return {454,h-52,110,25}
	case .Load: return {574,h-52,110,25}
	case .None: return {}
	}
	return {}
}

m9_control_enabled :: proc(v: M9_View, control: M9_Control) -> bool {
	switch control {
	case .None: return false
	case .Leave,.Pause: return true
	case .Resume_FPS: return v.kind == .FPS && v.fps_active && v.paused && !v.captured && !v.replaying
	case .Step: return v.tools && v.paused && !v.replaying
	case .Debug: return v.tools
	case .Arena,.Ring,.FPS: return v.practice && !v.recording && !v.replaying
	case .Reset,.Level: return v.tools && v.practice && !v.recording && !v.replaying
	case .Replay: return v.tools && v.recorded>0 && !v.recording && !v.replaying
	case .Record: return v.tools && !v.replaying
	case .Move,.Startup_Down,.Startup_Up,.Damage_Down,.Damage_Up,.Save,.Load,.Dummy:
		return v.tools && v.kind != .FPS && !v.recording && !v.replaying
	}
	return false
}

m9_control_at_point :: proc(renderer: ^Renderer, v: M9_View, point: view.Vec2) -> M9_Control {
	for control in M9_Control {
		if m9_control_enabled(v,control) && point_in_rectangle(point,m9_control_bounds(renderer,control)) {return control}
	}
	return .None
}

@(private)
m9_move_name :: proc(action: fight.Action) -> cstring {
	switch action {
	case .Idle: return "PRONTO"
	case .Jab: return "PUGNO"
	case .Heavy: return "PESANTE"
	case .Guard: return "PARATA"
	case .Dodge: return "SCHIVATA"
	case .Grab: return "PRESA"
	case .Hurt: return "STORDITO"
	case .Thrown: return "LANCIATO"
	}
	return ""
}

@(private)
draw_m9_controls :: proc(renderer: ^Renderer, v: M9_View, moves: ^[fight.Action]fight.Move_Def = nil) {
	w,h := renderer.canvas_width,renderer.canvas_height
	if v.practice {
		controls := [3]M9_Control{.Arena,.Ring,.FPS}
		for label,index in ([3]cstring{"ARENA LIBERA","RING","FPS"}) {
			control := controls[index]
			m8_mouse_button(renderer,m9_control_bounds(renderer,control),label,m9_control_enabled(v,control))
		}
	}
	m8_mouse_button(renderer,m9_control_bounds(renderer,.Pause),"RIPRENDI" if v.paused else "PAUSA")
	m8_mouse_button(renderer,m9_control_bounds(renderer,.Leave),"TORNA")
	if v.tools {
		rl.DrawRectangleRec({10,h-94,w-20,87},{8,14,23,246})
		controls := [7]M9_Control{.Step,.Debug,.Reset,.Level,.Record,.Replay,.Dummy}
		labels := [7]cstring{"1 TICK","COLLISIONI","RESET","LIVELLO","FERMA REC" if v.recording else "REGISTRA","REPLAY","CAMBIA AVVERSARIO"}
		for control,i in controls {m8_mouse_button(renderer,m9_control_bounds(renderer,control),labels[i],m9_control_enabled(v,control))}
		if moves != nil && v.kind != .FPS {
			m8_mouse_button(renderer,m9_control_bounds(renderer,.Move),m9_move_name(v.move),m9_control_enabled(v,.Move))
			for control in ([4]M9_Control{.Startup_Down,.Startup_Up,.Damage_Down,.Damage_Up}) {
				up := control == .Startup_Up || control == .Damage_Up
				m8_mouse_button(renderer,m9_control_bounds(renderer,control),"+" if up else "-",m9_control_enabled(v,control))
			}
			gothic_text(renderer,fmt.ctprintf("%df",moves[v.move].startup),212,h-47,13,GOTHIC_BLUE)
			gothic_text(renderer,fmt.ctprintf("%d HP",moves[v.move].damage),354,h-47,13,GOTHIC_RED)
			m8_mouse_button(renderer,m9_control_bounds(renderer,.Save),"SALVA MOSSE",m9_control_enabled(v,.Save))
			m8_mouse_button(renderer,m9_control_bounds(renderer,.Load),"CARICA",m9_control_enabled(v,.Load))
		}
		gothic_text_fit(renderer,fmt.ctprintf("%s / TICK %d / %d INPUT", "REPLAY" if v.replaying else "REC" if v.recording else "LAB",v.steps,v.recorded),{702,h-48,w-724,18},12,GOTHIC_BLUE)
	}
	if len(v.status)>0 {gothic_text_fit(renderer,fmt.ctprintf("%s",v.status),{20,80,w-40,18},12,GOTHIC_BLUE)}
}
