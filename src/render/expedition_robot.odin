package render

import "core:math"
import rl "vendor:raylib"
import gfx "../engine/gfx"

// The approved monitor-headed explorer. The same source draws the hub's
// avatar and is rasterized into the expedition's immutable pixel atlas.
expedition_robot_art :: proc(time:f32,action:gfx.Living_Action=.Idle,progress:f32=0,mounted:bool=false)->(m:Expedition_Paper) {
	m.cutout=true
	shell:=rl.Color{255,191,89,255};shadow:=rl.Color{212,114,47,255};highlight:=rl.Color{255,232,165,255}
	blue:=rl.Color{16,136,194,255};deep:=rl.Color{21,49,76,255};cyan:=rl.Color{31,233,245,255};coral:=rl.Color{248,68,55,255}
	walking:=action==.Move_Side || action==.Move_Up || action==.Move_Down || action==.Dodge
	swing:=math.sin(progress*math.TAU*2)*.045 if walking else f32(0)
	bob:=abs(swing)*.3+math.sin(time*2.7)*.004
	strike:=math.sin(clamp(progress,0,1)*math.PI)
	casting:=action==.Cast || action==.Channel || action==.Interact
	// Soles lie on y=0. The drawing moves over these feet, inside its sheet.
	for side in ([2]f32{-1,1}) {
		hip:=rl.Vector2{side*.115,.38+bob};knee:=rl.Vector2{side*.15+swing*side,.23};foot:=rl.Vector2{side*.17-swing*side,.065}
		if mounted {knee={side*.25,.29+bob};foot={side*.26,.18+bob}}
		paper_limb(&m,hip,knee,.105,deep);paper_disc(&m,knee.x,knee.y,.075,.065,blue)
		paper_limb(&m,knee,foot,.09,deep);paper_box(&m,foot.x-.08,foot.y-.04,.16,.075,shell)
		paper_box(&m,foot.x-.11,foot.y-.065,.23,.11,blue)
		paper_box(&m,foot.x-.075,foot.y-.025,.13,.035,{59,158,186,255},false)
		paper_box(&m,foot.x-.055,foot.y-.06,.12,.025,shadow,false)
	}
	paper_box(&m,-.155,.30+bob,.31,.09,deep)
	paper_box(&m,-.19,.38+bob,.38,.35,shell)
	paper_box(&m,-.17,.39+bob,.34,.055,shadow,false)
	paper_box(&m,-.145,.65+bob,.28,.035,highlight,false)
	paper_box(&m,-.13,.46+bob,.26,.19,blue)
	paper_box(&m,-.08,.49+bob,.16,.13,deep,false)
	paper_box(&m,-.05,.52+bob,.10,.10,shell)
	paper_box(&m,-.035,.59+bob,.07,.02,highlight,false)
	for side in ([2]f32{-1,1}) {
		shoulder:=rl.Vector2{side*.24,.69+bob};elbow:=rl.Vector2{side*.31,.53+bob+swing*side};hand:=rl.Vector2{side*.32,.41+bob-swing*side}
		if casting && side>0 {elbow={.32,.68+bob};hand={.34,.81+bob}}
		if action==.Attack && side>0 {elbow={.32,.58+bob};hand={.34+strike*.13,.55+bob+strike*.1}}
		if action==.Block && side>0 {elbow={.27,.65+bob};hand={.17,.77+bob}}
		if mounted {elbow={side*.29,.58+bob};hand={side*.33,.55+bob}}
		paper_disc(&m,shoulder.x,shoulder.y,.085,.085,blue)
		paper_limb(&m,shoulder,elbow,.075,deep);paper_disc(&m,elbow.x,elbow.y,.06,.05,shell)
		paper_limb(&m,elbow,hand,.07,deep);paper_box(&m,hand.x-.075,hand.y-.055,.15,.12,blue)
		paper_box(&m,hand.x-.052,hand.y+.015,.08,.025,{65,165,191,255},false)
		paper_box(&m,hand.x-.05,hand.y-.07,.045,.065,coral);paper_box(&m,hand.x+.015,hand.y-.07,.045,.065,coral)
	}
	paper_box(&m,-.075,.72+bob,.15,.085,deep);paper_box(&m,-.04,.74+bob,.08,.028,coral,false)
	// Large face, small torso: cyan eyes remain readable at the game camera.
	for side in ([2]f32{-1,1}) {paper_box(&m,side*.29-.04,.92+bob,.08,.17,coral);paper_box(&m,side*.29-.025,1.025+bob,.04,.045,{255,143,96,255},false)}
	head:=[8]rl.Vector2{{-.275,.87+bob},{-.275,1.15+bob},{-.215,1.21+bob},{.215,1.21+bob},{.275,1.15+bob},{.275,.87+bob},{.22,.81+bob},{-.22,.81+bob}}
	paper_polygon(&m,head[:],shell)
	paper_box(&m,-.22,.83+bob,.44,.045,shadow,false);paper_box(&m,-.205,1.16+bob,.39,.026,highlight,false)
	paper_box(&m,-.215,.90+bob,.43,.235,deep)
	paper_box(&m,-.185,.92+bob,.37,.185,{16,38,50,255},false)
	for side in ([2]f32{-1,1}) {
		x:=side*.105
		if action==.Hurt || action==.Hurt_Back || action==.Stunned {paper_limb(&m,{x-.027,1.06+bob},{x+.027,1.00+bob},.018,coral,false);paper_limb(&m,{x-.027,1.00+bob},{x+.027,1.06+bob},.018,coral,false)}
		else {paper_box(&m,x-.023,1.005+bob,.046,.09,cyan,false)}
	}
	paper_box(&m,-.035,.94+bob,.07,.017,shell,false)
	paper_limb(&m,{0,1.20+bob},{0,1.37+bob},.028,blue)
	paper_disc(&m,0,1.38+bob,.05,.05,deep);paper_box(&m,-.025,1.36+bob,.05,.05,cyan,false)
	paper_box(&m,.18,1.195+bob,.035,.05,blue)
	// Compact body, generous monitor face: the reference's proportions,
	// keeping the same overall height and the soles exactly on the floor.
	for &part in m.parts[:m.count] {for &point in part.points[:part.count] {
		point.y=point.y*.83 if point.y<.8 else .664+(point.y-.8)*1.25
	}}
	if action==.Death {for &part in m.parts[:m.count] {for &point in part.points[:part.count] {point.y*=.55;point.x+=point.y*.30}}}
	return
}
