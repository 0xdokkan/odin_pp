package arena

import "core:math"
import rl "vendor:raylib"
import gfx "../../engine/gfx"

// The cabinet shares the original rules and collision geometry. This orbital
// dressing reads world coordinates only; it never advances either RNG stream.
draw_orbital_void :: proc(width, height, time: f32) {
	gfx.draw_vertical_gradient({0,0,width,height},{4,7,20,255},{20,9,37,255})
	for i in 0..<85 {
		x:=f32((i*193+31)%997)/997*width;y:=f32((i*277+59)%991)/991*height
		a:=u8(85+65*(0.5+0.5*math.sin(time*0.6+f32(i))))
		rl.DrawCircleV({x,y},1 if i%7!=0 else 2,{156,215,245,a})
	}
	c:=Vec2{width*.84,height*.24}
	rl.DrawCircleV(c,height*.17,{32,40,73,255})
	rl.DrawCircleLinesV(c,height*.17,{78,137,175,255})
	rl.DrawEllipseLines(i32(c.x),i32(c.y),height*.26,height*.046,{92,161,192,180})
}

orbital_markings :: proc(w:^World) {
	for y in 1..<MAP_H-1 {for x in 1..<MAP_W-1 {
		if !open_cell(w,x,y) {continue}
		p:=cell_center(x,y)
		if x%6==0 {
			rl.DrawRectangleRec({p.x-TILE*.5+2,p.y-TILE*.5+3,2,TILE-6},{50,189,211,125})
		}
		if x%5==0&&y%4==0 {
			for n in 0..<3 {rl.DrawRectangleRec({p.x-7+f32(n)*5,p.y-5,2,10},{105,137,155,150})}
		}
	}}
	// Landing-pad cross replaces the old occult centrepiece.
	c:=player_start()
	rl.DrawCircleV(c,90,{32,51,68,255})
	rl.DrawRing(c,87,90,0,360,64,{79,165,185,220})
	rl.DrawRectangleRec({c.x-35,c.y-6,70,12},{110,185,200,160})
	rl.DrawRectangleRec({c.x-6,c.y-35,12,70},{110,185,200,160})
}

draw_orbital_enemy :: proc(e:^Enemy,feet:Vec2,scale:f32,squash:Vec2) {
	c:=feet-Vec2{0,e.radius+4}
	r:=e.radius*1.18
	ink:=rl.Color{13,20,33,255};paper:=rl.Color{236,235,212,255}
	col:=enemy_color(e.kind)
	if e.flash>0 {col=rl.WHITE}
	switch e.kind {
	case .Chaser,.Shard:
		for sign in ([2]f32{-1,1}) {
			rl.DrawLineEx(c+{sign*r*.65,0},c+{sign*r*1.3,r*.6},4,paper)
			rl.DrawLineEx(c+{sign*r*1.3,r*.6},c+{sign*r*1.1,r},3,col)
		}
		rl.DrawPoly(c,6,r*squash.y,30,paper);rl.DrawPoly(c,6,r*.83*squash.y,30,col)
		rl.DrawRectangleRec({c.x-r*.58,c.y-r*.28,r*1.16,r*.38},ink)
		for sign in ([2]f32{-1,1}) {rl.DrawCircleV(c+{sign*r*.32,-r*.12},2,{119,253,219,255})}
	case .Caster:
		rl.DrawEllipse(i32(c.x),i32(c.y+5),r*1.4,r*.4,paper)
		rl.DrawEllipse(i32(c.x),i32(c.y+3),r*1.3,r*.3,col)
		rl.DrawCircleV(c,r*.67,paper);rl.DrawCircleV(c,r*.5,{74,160,185,255})
		rl.DrawLineEx(c,c+e.facing*(r+9),5,paper)
	case .Charger:
		for sign in ([2]f32{-1,1}) {
			rl.DrawRectangleRec({c.x+sign*r*.8-5,c.y-r*.7,10,r*1.65},paper)
			rl.DrawRectangleRec({c.x+sign*r*.8-3,c.y-r*.6,6,r*1.5},ink)
		}
		rl.DrawPoly(c,4,r*1.1,45,paper);rl.DrawPoly(c,4,r*.88,45,col)
		rl.DrawLineEx(c,c+e.facing*(r+9),7,paper);rl.DrawLineEx(c,c+e.facing*(r+10),3,ink)
	case .Splitter:
		for n in 0..<8 {
			a:=f32(n)*math.TAU/8+e.age*.5
			d:=Vec2{math.cos(a),math.sin(a)}
			rl.DrawLineEx(c+d*r*.65,c+d*r*1.25,4,paper)
		}
		rl.DrawPoly(c,8,r,22.5,paper);rl.DrawPoly(c,8,r*.78,22.5,col)
		rl.DrawCircleV(c,r*.3,ink);rl.DrawCircleV(c,r*.16,{255,124,96,255})
	case .Boss:
		rl.DrawEllipse(i32(c.x),i32(c.y),r*1.65,r*.62,paper)
		rl.DrawEllipse(i32(c.x),i32(c.y),r*1.5,r*.48,col)
		rl.DrawPoly(c-{0,r*.35},6,r*.8,30,paper)
		rl.DrawPoly(c-{0,r*.35},6,r*.65,30,{41,90,130,255})
		for n in -2..=2 {rl.DrawCircleV(c+{f32(n)*r*.5,r*.2},3,{118,249,221,255})}
	}
}
