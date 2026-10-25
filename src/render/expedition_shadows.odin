package render

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import world "../expedition"
import game "../game"
import view "../engine/view"

// A feathered contact shadow grounds the printed cards without lighting or
// tinting their paper. Only visible actors are visited, never the map cells.
// It lies on the sculpted ground, over the highest point under its rim, so a
// slope never covers it.
@(private)
expedition_paper_shadow :: proc(at:view.Vec2,radius:f32=.37,opacity:f32=.38) {
	center:=rl.Vector3{at.x+.5,rim_ground(at,radius)+.024,at.y+.5}
	_=rlgl.CheckRenderBatchLimit(48)
	rlgl.Begin(rlgl.TRIANGLES)
	for i in 0..<16 {
		a,b:=f32(i)*math.TAU/16,f32(i+1)*math.TAU/16
		rlgl.Color4ub(0,0,0,u8(opacity*255));rlgl.Vertex3f(center.x,center.y,center.z)
		rlgl.Color4ub(0,0,0,0)
		rlgl.Vertex3f(center.x+math.cos(b)*radius,center.y,center.z+math.sin(b)*radius*.8)
		rlgl.Vertex3f(center.x+math.cos(a)*radius,center.y,center.z+math.sin(a)*radius*.8)
	}
	rlgl.End()
}

@(private)
draw_expedition_contact_shadows :: proc(renderer:^Renderer,room:^game.Room,w:^world.World) {
	s:=renderer.tactical.snapshot;if s==nil {return}
	rlgl.DrawRenderBatchActive();rlgl.DisableDepthMask()
	defer {rlgl.DrawRenderBatchActive();rlgl.EnableDepthMask()}
	// The shadow fades with how high an actor is over the ground under it, not with the ground's own height.
	if s.player.visible {
		p,lift:=living_card_position(renderer,game.PLAYER_ENTITY,.Player,s.player.position)
		expedition_paper_shadow(p,.54 if renderer.tactical.expedition_mounted else .36,.40/(1+max(lift-point_ground(p),0)))
	}
	for actor in s.enemies[:s.enemy_count] {
		if !actor.visible || actor.health<=0 {continue}
		p,lift:=living_card_position(renderer,actor.entity,sprite_key_for_enemy(actor.archetype),actor.position)
		expedition_paper_shadow(p,.40,.38/(1+max(lift-point_ground(p),0)))
	}
	for &group,g in w.groups[:w.group_count] {for member,i in group.members[:group.count] {
		if !member.alive || member.deployed || !world.in_scope(w,group.cave) || !tactical_cell_on_screen(renderer,member.enemy.position) {continue}
		if world.ground(w,member.enemy.position)==.Grass && world.distance(room.player.position,member.enemy.position)>3 {continue}
		expedition_paper_shadow(expedition_patrol_shown(renderer,g,i,member.enemy.position))
	}}
}
