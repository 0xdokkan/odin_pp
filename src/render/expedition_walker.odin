package render

import "core:math"
import rl "vendor:raylib"
import game "../game"
import view "../engine/view"

// Exploration glides (expedition/roam.odin); encounters step by cells. The
// scene hands the walker over every frame, in board coordinates (a cell's
// corner, like every actor's position here).
set_expedition_walker :: proc(renderer:^Renderer,free:bool,position,velocity:view.Vec2,stride,dt:f32) {
	v:=&renderer.tactical
	v.expedition_free=free;v.expedition_free_position=position;v.expedition_free_velocity=velocity
	v.expedition_stride=stride
	if dt>0 && dt<1 {v.expedition_dt=dt}
}

// Smoothing needs the frame's real seconds; drivers that never set them
// (captures) get a nominal frame.
@(private)
expedition_frame_dt :: proc(renderer:^Renderer)->f32 {
	dt:=renderer.tactical.expedition_dt
	return dt if dt>0 else 1.0/60
}

// Snapshot override and the ease between gliding and stepping: when an
// encounter begins or ends the robot leaves from where it was last drawn.
@(private)
update_expedition_walker_view :: proc(renderer:^Renderer,refresh_only:bool) {
	v:=&renderer.tactical
	if !v.expedition {v.expedition_free=false;v.expedition_was_free=false;return}
	if v.expedition_free {v.snapshot.player.position=v.expedition_free_position}
	if refresh_only {return}
	if v.expedition_free!=v.expedition_was_free {
		v.expedition_was_free=v.expedition_free
		if v.expedition_player_drawn {
			jump:=v.expedition_player_shown-v.snapshot.player.position
			if abs(jump.x)+abs(jump.y)<3 {v.expedition_player_offset=jump}
		}
	}
	if !v.expedition_follow_ready {v.expedition_player_offset={};v.expedition_player_drawn=false}
	v.expedition_player_offset*=math.exp(-14*expedition_frame_dt(renderer))
	if abs(v.expedition_player_offset.x)+abs(v.expedition_player_offset.y)<.002 {v.expedition_player_offset={}}
}

// Where the expedition's robot stands: the free walker, or the card's step.
@(private)
expedition_player_position :: proc(renderer:^Renderer,key:Sprite_Key,position:view.Vec2)->(at:view.Vec2,lift:f32) {
	v:=&renderer.tactical
	if v.expedition_free {at,lift=position,tactical_lasso_lift(renderer,game.PLAYER_ENTITY)}
	else {at,lift=living_card_slide_position(renderer,game.PLAYER_ENTITY,key,position)}
	return at+v.expedition_player_offset,lift
}

@(private)
expedition_walker_speed :: proc(renderer:^Renderer)->f32 {
	velocity:=renderer.tactical.expedition_free_velocity
	return math.sqrt(velocity.x*velocity.x+velocity.y*velocity.y) if renderer.tactical.expedition_free else 0
}

// The robot turns toward the screen side it walks to, with the card's turn.
@(private)
expedition_walker_face :: proc(renderer:^Renderer,actor:^Living_Actor,now:f64) {
	if actor==nil || expedition_walker_speed(renderer)<.3 {return}
	velocity:=renderer.tactical.expedition_free_velocity
	living_face(actor,rl.Vector3DotProduct({velocity.x,0,velocity.y},flipbook_camera_right(renderer)),now)
}

// Legs and wheels follow the ground covered, not the clock: a halted mount
// stands still and a galloping one does not skate.
@(private)
expedition_gait_time :: proc(renderer:^Renderer,clock:f32)->f32 {
	v:=&renderer.tactical
	if !v.expedition_free {return clock}
	return clock*.08+v.expedition_stride*.27
}
