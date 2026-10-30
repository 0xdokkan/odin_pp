package render

import "core:math"
import rl "vendor:raylib"
import game "../game"
import view "../engine/view"
import rlgl "vendor:raylib/rlgl"

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
	update_expedition_walker_motion(renderer)
}

// The walker's body language (the user's choice, 2026-10-30): it leans into a
// speed-up and back as it brakes, a little forward at speed
// (EXPEDITION_LEAN_*); the camera leads the walk by EXPEDITION_LOOK_SECONDS of
// it, at most EXPEDITION_LOOK_MAX cells; each footfall lifts a puff of dust.
EXPEDITION_LEAN_ACCEL :: f32(0.0032)
EXPEDITION_LEAN_SPEED :: f32(0.014)
EXPEDITION_LEAN_MAX :: f32(0.13)
EXPEDITION_LOOK_SECONDS :: f32(0.2)
EXPEDITION_LOOK_MAX :: f32(1.2)
EXPEDITION_DUST :: 10
EXPEDITION_DUST_SECONDS :: f32(0.45)
EXPEDITION_DUST_BEHIND :: f32(0.22)
// A footfall each this much of the ground covered (half the gait's 1.8).
EXPEDITION_FOOTFALL :: f32(0.9)

Expedition_Dust :: struct {
	puffs: [EXPEDITION_DUST]struct{at: view.Vec2, born: f64, used: bool},
	next: int,
	stride: f32,
}

@(private)
update_expedition_walker_motion :: proc(renderer:^Renderer) {
	v:=&renderer.tactical
	dt:=expedition_frame_dt(renderer)
	velocity:=v.expedition_free_velocity if v.expedition_free else view.Vec2{}
	accel:=(velocity-v.expedition_last_velocity)/max(dt,.001)
	v.expedition_last_velocity=velocity
	// Forward is the screen side it faces: its walk's side across the screen.
	right:=flipbook_camera_right(renderer)
	across:=velocity.x*right.x+velocity.y*right.z
	push:=accel.x*right.x+accel.y*right.z
	sign:=f32(1) if across>=0 else -1
	lean:=clamp(push*sign*EXPEDITION_LEAN_ACCEL+abs(across)*EXPEDITION_LEAN_SPEED,-EXPEDITION_LEAN_MAX,EXPEDITION_LEAN_MAX)
	if !v.expedition_free || v.expedition_mounted {lean=0}
	v.expedition_lean+=(lean-v.expedition_lean)*(1-math.exp(-12*dt))
	look:=velocity*EXPEDITION_LOOK_SECONDS
	if length:=math.sqrt(look.x*look.x+look.y*look.y);length>EXPEDITION_LOOK_MAX {look*=EXPEDITION_LOOK_MAX/length}
	v.expedition_look+=(look-v.expedition_look)*(1-math.exp(-4*dt))
	// The footfalls, by the ground covered.
	d:=&v.expedition_dust
	if !v.expedition_free || v.expedition_stride<d.stride {d.stride=v.expedition_stride}
	if v.expedition_free && expedition_walker_speed(renderer)>2 && v.expedition_stride-d.stride>=EXPEDITION_FOOTFALL {
		d.stride=v.expedition_stride
		// A little behind the feet, never over them.
		speed:=max(expedition_walker_speed(renderer),.001)
		d.puffs[d.next]={at=v.expedition_free_position-velocity/speed*EXPEDITION_DUST_BEHIND,born=renderer.sprite_assets.elapsed,used=true}
		d.next=(d.next+1)%len(d.puffs)
	}
}

// The footfalls' dust: flat paper-white puffs on the ground under the walker,
// growing and fading over EXPEDITION_DUST_SECONDS.
@(private)
draw_expedition_dust :: proc(renderer:^Renderer) {
	v:=&renderer.tactical
	now:=renderer.sprite_assets.elapsed
	for &puff in v.expedition_dust.puffs {
		if !puff.used {continue}
		t:=f32(now-puff.born)/EXPEDITION_DUST_SECONDS
		if t>=1 || t<0 {puff.used=false;continue}
		centre:=rl.Vector3{puff.at.x+.5,entity_point_ground(game.PLAYER_ENTITY,puff.at)+.04,puff.at.y+.5}
		radius:=.04+.12*t
		alpha:=u8(110*(1-t)*(1-t))
		SIDES::12
		rlgl.Begin(rlgl.TRIANGLES)
		rlgl.Color4ub(232,236,228,alpha)
		for k in 0..<SIDES {
			a0:=f32(k)*math.TAU/SIDES;a1:=f32(k+1)*math.TAU/SIDES
			rlgl.Vertex3f(centre.x,centre.y,centre.z)
			rlgl.Vertex3f(centre.x+math.cos(a1)*radius,centre.y,centre.z+math.sin(a1)*radius*.6)
			rlgl.Vertex3f(centre.x+math.cos(a0)*radius,centre.y,centre.z+math.sin(a0)*radius*.6)
		}
		rlgl.End()
	}
}

// Where the expedition's robot stands: the free walker, or the card's step.
@(private)
expedition_player_position :: proc(renderer:^Renderer,key:Sprite_Key,position:view.Vec2)->(at:view.Vec2,lift:f32) {
	v:=&renderer.tactical
	// Walking free the robot stands on the ground under it, the hill's or the mountain's (height_view.odin).
	if v.expedition_free {at,lift=position,tactical_lasso_lift(renderer,game.PLAYER_ENTITY)+entity_point_ground(game.PLAYER_ENTITY,position)}
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
