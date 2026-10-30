package render

import "core:math"
import rl "vendor:raylib"
import gfx "../engine/gfx"
import game "../game"
import view "../engine/view"

// The explorer's little salvaged robot is built from the same edged paper
// pieces as the biome wardrobes. Its bright monitor face stays readable at
// the fixed camera distance; joints and limbs follow the ordinary actor cues.
expedition_robot_art :: proc(time:f32,action:gfx.Living_Action=.Idle,progress:f32=0,mounted:bool=false)->(m:Expedition_Paper) {
	m.cutout=true
	ink:=EXPEDITION_PAPER_INK;paper:=EXPEDITION_PAPER_EDGE
	shell:=rl.Color{133,194,172,255};shade:=rl.Color{50,94,106,255};metal:=rl.Color{49,57,67,255}
	light:=rl.Color{111,243,237,255};orange:=rl.Color{219,137,73,255}
	swing:f32=0;bob:=math.sin(time*2.7)*.007
	if action==.Move_Side || action==.Move_Up || action==.Move_Down {swing=math.sin(progress*math.PI*4)*.105;bob=abs(math.sin(progress*math.PI*4))*.022}
	casting:=action==.Cast || action==.Channel || action==.Interact
	attack:=action==.Attack;guard:=action==.Block;hurt:=action==.Hurt || action==.Hurt_Back || action==.Stunned
	strike:=math.sin(clamp(progress,f32(0),f32(1))*math.PI)
	// The pack, aerial and folded cable sit behind the silhouette.
	paper_box(&m,-.29,.45+bob,.17,.33,orange)
	paper_box(&m,-.31,.48+bob,.035,.19,{159,94,56,255},false)
	paper_limb(&m,{-.14,1.04+bob},{-.2,1.24+bob},.025,metal)
	paper_disc(&m,-.2,1.24+bob,.04,.04,orange)
	// Two articulated legs, folded over the saddle when mounted.
	for side in ([2]f32{-1,1}) {
		hip:=rl.Vector2{side*.105,.43+bob}
		knee:=rl.Vector2{side*.13+swing*side*.6,.25};foot:=rl.Vector2{side*.14-swing*side,.07}
		if mounted {knee={side*.25,.32+bob};foot={side*.24,.17+bob}}
		paper_limb(&m,hip,knee,.09,metal);paper_disc(&m,knee.x,knee.y,.065,.055,orange)
		paper_limb(&m,knee,foot,.085,shade);paper_box(&m,foot.x-.075,foot.y-.04,.18,.075,shell)
		paper_box(&m,foot.x-.062,foot.y-.035,.15,.018,ink,false)
	}
	// Flat printed teal panels, an orange meter and cream registration marks.
	p:=[6]rl.Vector2{{-.22,.72+bob},{-.16,.8+bob},{.17,.8+bob},{.23,.71+bob},{.18,.43+bob},{-.18,.43+bob}}
	paper_polygon(&m,p[:],shell);paper_box(&m,-.18,.45+bob,.36,.065,shade,false)
	paper_box(&m,-.13,.72+bob,.25,.035,{226,210,164,255},false)
	paper_box(&m,-.115,.58+bob,.23,.14,{65,86,97,255});paper_box(&m,-.08,.62+bob,.12,.055,light,false)
	paper_box(&m,.063,.62+bob,.027,.055,orange,false)
	for side in ([2]f32{-1,1}) {paper_disc(&m,side*.15,.74+bob,.018,.018,paper,false)}
	// Telescoping arms: casting palm, punch and brace are distinct poses.
	for side in ([2]f32{-1,1}) {
		shoulder:=rl.Vector2{side*.23,.71+bob};elbow:=rl.Vector2{side*.31,.55+bob-swing*side*.4}
		hand:=rl.Vector2{side*.29,.41+bob+swing*side*.4}
		if mounted {elbow={side*.28,.61+bob};hand={side*.35,.57+bob}}
		if casting && side>0 {elbow={.35,.8+bob};hand={.4,.97+bob}}
		if attack && side>0 {elbow={.31+strike*.1,.66+bob};hand={.36+strike*.26,.72+bob}}
		if guard && side>0 {elbow={.28,.67+bob};hand={.1,.86+bob}}
		paper_disc(&m,shoulder.x,shoulder.y,.075,.075,shade)
		paper_limb(&m,shoulder,elbow,.07,metal);paper_disc(&m,elbow.x,elbow.y,.052,.052,orange)
		paper_limb(&m,elbow,hand,.07,shade);paper_box(&m,hand.x-.065,hand.y-.04,.13,.095,shell)
		if casting && side>0 {paper_disc(&m,hand.x,hand.y+.09,.07,.075,light);paper_tri(&m,{hand.x-.035,hand.y+.16},{hand.x+.035,hand.y+.16},{hand.x,hand.y+.23},paper,false)}
	}
	// Monitor head: beveled corners and the small asymmetry of a repaired ear.
	paper_box(&m,-.07,.77+bob,.14,.1,metal)
	paper_box(&m,-.31,.94+bob,.07,.13,orange);paper_box(&m,.24,.94+bob,.07,.13,shade)
	head:=[8]rl.Vector2{{-.25,.9+bob},{-.25,1.11+bob},{-.19,1.17+bob},{.19,1.17+bob},{.25,1.11+bob},{.25,.9+bob},{.2,.85+bob},{-.2,.85+bob}}
	paper_polygon(&m,head[:],shell);paper_box(&m,-.205,.91+bob,.41,.205,{35,55,69,255})
	paper_limb(&m,{-.18,1.09+bob},{-.07,1.09+bob},.018,{115,153,164,255},false)
	blink:=int(time*1.4)%13==12
	for side in ([2]f32{-1,1}) {
		x:=side*.1
		if hurt {paper_limb(&m,{x-.035,1.045+bob},{x+.035,.985+bob},.018,orange,false);paper_limb(&m,{x-.035,.985+bob},{x+.035,1.045+bob},.018,orange,false)}
		else {paper_box(&m,x-.035,1.0+bob,.07,.018 if blink else .066,light,false)}
	}
	paper_box(&m,-.035,.945+bob,.07,.018,light,false)
	if action==.Death {for &part in m.parts[:m.count] {for &point in part.points[:part.count] {point.y*=.55;point.x+=point.y*.45}}}
	return
}

@(private)
draw_expedition_robot :: proc(renderer:^Renderer,position:view.Vec2,opacity:f32) {
	v:=&renderer.tactical;at,lift:=living_card_position(renderer,game.PLAYER_ENTITY,.Player,position)
	v.expedition_player_shown=at;v.expedition_player_drawn=true
	now:=living_clock(renderer,game.PLAYER_ENTITY);action:=gfx.Living_Action.Idle;progress:f32=0;mirror:=false;turn_width:f32=1
	if actor:=living_find(renderer,game.PLAYER_ENTITY,.Pilgrim);actor!=nil {
		expedition_walker_face(renderer,actor,now)
		action,_=living_drawing(actor,now);mirror=actor.facing_left
		clip:=&gfx.LIVING_SHEETS[.Pilgrim].clips[action];seconds:=max(f64(.001),living_played_seconds(clip,actor.scale))
		progress=f32(clamp((now-actor.started)/seconds,0,1))
		turn:=living_turn_progress(actor,now)
		if actor.turn_started>=0 && turn<1 {turn_width=max(f32(.04),abs(f32(math.cos(turn*math.PI))));if turn<.5 {mirror=!mirror}}
	}
	// A glide has no step cue: the gait follows the ground actually covered.
	if expedition_walker_speed(renderer)>.3 && (action==.Idle || action==.Move_Side || action==.Move_Up || action==.Move_Down) {
		action=.Move_Side;progress=v.expedition_stride/1.8-math.floor(v.expedition_stride/1.8)
	}
	pose:=tactical_feedback_pose(renderer,.Player,position);shade,seen:=tactical_shadow_tint(renderer,game.PLAYER_ENTITY)
	if shade!=rl.WHITE {pose.tint=shade}
	art:=expedition_robot_art(f32(now),action,progress,v.expedition_mounted)
	for &part in art.parts[:art.count] {
		part.color.r=u8(u16(part.color.r)*u16(pose.tint.r)/255);part.color.g=u8(u16(part.color.g)*u16(pose.tint.g)/255);part.color.b=u8(u16(part.color.b)*u16(pose.tint.b)/255)
		for &point in part.points[:part.count] {point.y*=pose.scale_y;point.x+=pose.lean*point.y}
	}
	if v.expedition_mounted {lift+=.42+math.sin(v.expedition_clock*6)*.015}
	draw_expedition_paper(renderer,&art,{at.x+.5,.035+lift+pose.lift,at.y+.5},1.19 if v.expedition_mounted else 1.36,mirror,opacity*seen,turn_width)
}
