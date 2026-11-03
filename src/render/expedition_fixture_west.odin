package render

import "core:math"
import rl "vendor:raylib"

// Shares the press's density, four-frame raster and owner, but its drawing
// is a wooden reciprocating saw with exposed wheel, belt, log and blade.
WEST_WORKSHOP_PRINT_Y :: CYBER_WORKSHOP_ATLAS_HEIGHT
WEST_WORKSHOP_SECONDARY_Y :: WEST_WORKSHOP_PRINT_Y+CYBER_PRESS_HEIGHT
WORKSHOP_PRINT_HEIGHT :: WEST_WORKSHOP_SECONDARY_Y+FIXTURE_CELL

@(private)
west_sawmill_art :: proc(frame:int)->(m:Expedition_Paper) {
	m.cutout=true;p:=fixture_art_palette(.West)
	iron:=rl.Color{78,91,97,255};steel:=rl.Color{182,194,189,255}
	// The splayed feet are actual parts of the frame, never a backing plate.
	for side in ([2]f32{-1,1}) {
		leg:=[4]rl.Vector2{{side*.42,0},{side*.28,.62},{side*.18,.62},{side*.28,0}}
		paper_polygon(&m,leg[:],p.shade)
	}
	post:=[4]rl.Vector2{{-.40,.30},{-.33,2.43},{-.17,2.48},{-.22,.31}}
	paper_polygon(&m,post[:],p.body)
	paper_limb(&m,{-.31,.67},{-.25,2.31},.025,p.light,false)
	right:=[4]rl.Vector2{{.22,.32},{.19,2.35},{.34,2.42},{.40,.33}}
	paper_polygon(&m,right[:],p.body)
	paper_limb(&m,{.31,.72},{.28,2.28},.023,p.shade,false)
	header:=[6]rl.Vector2{{-.43,2.32},{-.42,2.51},{-.20,2.65},{.39,2.56},{.43,2.38},{.23,2.29}}
	paper_polygon(&m,header[:],p.body)
	top:=[4]rl.Vector2{{-.36,2.50},{-.19,2.59},{.31,2.52},{.16,2.44}}
	paper_polygon(&m,top[:],p.light,false)
	paper_disc(&m,.20,2.43,.055,.045,iron)
	// Two belt runs connect differently sized pulleys; no glowing machine.
	paper_limb(&m,{-.36,.53},{-.40,1.83},.048,p.shade)
	paper_limb(&m,{-.04,.53},{.12,1.83},.043,p.shade)
	paper_disc(&m,-.17,.53,.17,.17,iron)
	paper_disc(&m,-.17,.53,.12,.12,p.body,false)
	paper_disc(&m,-.14,1.83,.29,.29,iron)
	paper_disc(&m,-.14,1.83,.245,.245,p.body,false)
	phase:=[4]f32{0,.35,.85,1.20}
	angle:=phase[clamp(frame,0,3)]
	for i in 0..<4 {
		a:=angle+f32(i)*math.PI*.5
		d:=rl.Vector2{math.cos(a),math.sin(a)}
		paper_limb(&m,rl.Vector2{-.14,1.83}+d*.04,rl.Vector2{-.14,1.83}+d*.205,.043,p.light,false)
	}
	paper_disc(&m,-.14,1.83,.065,.065,p.shade)
	paper_disc(&m,-.15,1.845,.025,.025,steel,false)
	stroke:=[4]f32{0,.08,.18,.06};drop:=stroke[clamp(frame,0,3)]
	paper_limb(&m,{-.14,1.83},{.18,2.14-drop},.055,iron)
	// Carriage and saw table are drawn in three-quarter perspective.
	table:=[4]rl.Vector2{{-.46,.94},{-.29,1.06},{.45,1.00},{.29,.89}}
	paper_polygon(&m,table[:],p.light)
	paper_box(&m,-.43,.80,.80,.13,p.body)
	paper_limb(&m,{-.33,.85},{.12,.84},.022,p.shade,false)
	// A real log occupies the work slot; end grain explains its orientation.
	paper_box(&m,-.37,1.05,.68,.21,p.body)
	paper_limb(&m,{-.31,1.19},{.21,1.19},.028,p.light,false)
	paper_disc(&m,.29,1.15,.12,.14,p.light)
	paper_disc(&m,.29,1.15,.073,.092,p.body,false)
	paper_disc(&m,.29,1.15,.035,.045,p.light,false)
	// The silver blade has deliberately large teeth, visible at play scale.
	paper_box(&m,.13,1.10-drop,.07,1.08,steel)
	for i in 0..<6 {
		y:=1.16-drop+f32(i)*.145
		paper_tri(&m,{.20,y},{.255,y+.045},{.20,y+.09},steel,false)
	}
	paper_box(&m,.10,2.14-drop,.14,.095,iron)
	paper_box(&m,.11,1.01-drop,.13,.10,iron)
	// One painted maker's lozenge, beneath the work area, avoids a UI label.
	paper_disc(&m,.15,.57,.12,.085,p.accent)
	paper_limb(&m,{.10,.54},{.18,.61},.025,p.light,false)
	return
}

@(private)
west_workshop_secondary_art :: proc(role:int)->(m:Expedition_Paper) {
	m.cutout=true;p:=fixture_art_palette(.West);iron:=rl.Color{82,96,99,255}
	if role==0 {
		// Incoming logs: three unequal courses, broad and low on the floor.
		for row in 0..<3 {
			x:=-.42+f32(row%2)*.07;y:=.02+f32(row)*.22
			paper_box(&m,x,y,.69,.20,p.body)
			paper_limb(&m,{x+.05,y+.14},{x+.53,y+.14},.025,p.shade,false)
			paper_disc(&m,x+.69,y+.10,.12,.10,p.light)
			paper_disc(&m,x+.69,y+.10,.067,.055,p.body,false)
		}
	} else if role==1 {
		for side in ([2]f32{-1,1}) {paper_limb(&m,{side*.39,.025},{side*.26,.59},.09,p.shade)}
		paper_box(&m,-.43,.48,.86,.12,p.body)
		top:=[4]rl.Vector2{{-.46,.61},{-.29,.72},{.44,.67},{.28,.57}}
		paper_polygon(&m,top[:],p.light)
		saw:=[4]rl.Vector2{{-.34,.73},{-.23,.84},{.21,.79},{.25,.72}}
		paper_polygon(&m,saw[:],iron)
		paper_disc(&m,.27,.79,.10,.085,p.accent)
		paper_disc(&m,.27,.79,.052,.04,p.light,false)
		fixture_round(&m,-.27,.68,.18,.22,p.body,p.shade,p.light)
	} else {
		// Finished boards lean in a braced storage rack, with a hanging square.
		for side in ([2]f32{-1,1}) {paper_limb(&m,{side*.39,.025},{side*.29,1.27},.075,p.shade)}
		for i in 0..<3 {
			x:=-.26+f32(i)*.18;h:=1.16+f32(i%2)*.23
			board:=[4]rl.Vector2{{x,.11},{x-.07,h},{x+.07,h+.035},{x+.14,.11}}
			paper_polygon(&m,board[:],p.light if i==1 else p.body)
			paper_limb(&m,{x+.065,.29},{x+.02,h-.15},.018,p.shade,false)
		}
		paper_box(&m,-.37,.34,.74,.08,p.shade)
		paper_limb(&m,{-.29,.59},{.30,.96},.05,p.shade)
		paper_limb(&m,{.18,1.12},{.31,1.12},.04,iron)
		paper_limb(&m,{.31,1.12},{.31,.91},.04,iron)
	}
	lowest:=f32(100)
	for &part in m.parts[:m.count] {for point in part.points[:part.count] {lowest=min(lowest,point.y)}}
	for &part in m.parts[:m.count] {for &point in part.points[:part.count] {point.y-=lowest}}
	return
}

// Shared packing keeps the six existing GPU IDs stable. West's paper uses
// unused columns beside the Cyber stock rather than another large texture.
@(private)
west_secondary_paper_source :: proc(role:int)->rl.Rectangle {
	return {f32((2+role%2)*FIXTURE_CELL),f32((role/2)*FIXTURE_CELL),FIXTURE_CELL,FIXTURE_CELL}
}
