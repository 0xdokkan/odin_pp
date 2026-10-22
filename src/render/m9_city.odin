package render

import rl "vendor:raylib"
import gfx "../engine/gfx"

// Cabinet-only scenery; all buildings stand outside the physical ring.
draw_m9_city_sky :: proc(w,h:f32) {
	gfx.draw_vertical_gradient({0,0,w,h},{11,9,35,255},{51,17,48,255})
	rl.DrawCircleV({w*.76,h*.28},h*.15,{102,46,91,255})
	for i in 0..<6 {rl.DrawRectangleRec({w*.60,h*(.28+f32(i)*.024),w*.33,h*.008},{23,15,43,255})}
	for i in 0..<42 {rl.DrawCircleV({f32((i*163+7)%997)/997*w,f32((i*59+5)%397)/397*h*.5},1,{168,176,216,120})}
}

draw_m9_city_rooftop :: proc() {
	for side in ([2]f32{-1,1}) {
		for n in 0..<5 {
			h:=2.8+f32((n*7)%5)*.7
			x:=side*(6.2+f32(n)*1.0);z:=-6.7-f32(n%3)*1.7
			rl.DrawCube({x,h*.5-1.1,z},1.6,h,1.6,{25+u8(n)*4,26,48+u8(n)*3,255})
			for row in 0..<int(h/.5) {for col in 0..<3 {
				if (row*3+col+n)%4==0 {continue}
				p:=rl.Vector3{x-.48+f32(col)*.48,-.8+f32(row)*.5,z+.81}
				rl.DrawCube(p,.19,.26,.025,{210,112,167,255} if (n+col)%2==0 else {94,166,195,255})
			}}
			// Vertical shop signs and television aerials.
			p:=rl.Vector3{x-side*.82,h*.55,z+.6}
			rl.DrawCube(p,.12,h*.58,.48,{244,82,167,255} if n%2==0 else {77,219,222,255})
			for k in 0..<4 {rl.DrawCube(p+{0,(f32(k)-1.5)*.25,.25},.15,.06,.025,{240,229,211,255})}
			rl.DrawCylinderEx({x,h-1.1,z},{x,h-.2,z},.025,.025,4,{131,127,153,255})
			rl.DrawLine3D({x-.5,h-.4,z},{x+.5,h-.4,z},{165,148,175,255})
		}
		// Rain gutters and reflected cyan/pink light under the rooftop apron.
		rl.DrawCube({side*4.91,-.32,0},.035,.07,9.4,{245,93,176,255} if side<0 else {67,218,228,255})
		rl.DrawLine3D({side*4.8,1.7,-4.8},{side*6.6,3.5,-7.2},{89,71,104,255})
	}
	// A small rooftop vending machine remains beyond the back boundary.
	rl.DrawCube({-1.6,.65,-5.8},1.0,1.9,.7,{151,45,91,255})
	rl.DrawCube({-1.6,.98,-5.43},.76,.75,.035,{52,116,154,255})
	for row in 0..<2 {for col in 0..<3 {rl.DrawCube({-1.85+f32(col)*.25,.83+f32(row)*.28,-5.4},.10,.18,.04,{242,220,154,255})}}
	rl.DrawCube({-1.6,.13,-5.42},.58,.17,.03,{21,25,43,255})
}
