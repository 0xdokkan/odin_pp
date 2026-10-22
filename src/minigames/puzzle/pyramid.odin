package puzzle

import "core:math"
import rl "vendor:raylib"
import gfx "../../engine/gfx"

// A paper ankh appears both on the masonry and on the movable sarcophagi.
draw_ankh :: proc(p:rl.Vector2,size:f32,c:rl.Color) {
	rl.DrawEllipseLines(i32(p.x),i32(p.y-size*.3),size*.22,size*.30,c)
	rl.DrawLineEx(p-{0,size*.05},p+{0,size*.65},max(1,size*.10),c)
	rl.DrawLineEx(p+{-size*.35,size*.18},p+{size*.35,size*.18},max(1,size*.10),c)
}

draw_pyramid_backdrop :: proc(canvas:rl.Rectangle,time:f32) {
	gfx.draw_vertical_gradient(canvas,{25,19,38,255},{72,43,41,255})
	for i in 0..<48 {
		p:=rl.Vector2{f32((i*193+11)%997)/997*canvas.width,f32((i*107+7)%521)/521*canvas.height*.65}
		rl.DrawCircleV(p,1,{222,191,123,100})
	}
	rl.DrawCircleV({canvas.width*.82,canvas.height*.25},canvas.height*.10,{192,119,76,150})
	for side in 0..<2 {
		x:=canvas.width*(.08 if side==0 else .92);y:=canvas.height*.78
		for step in 0..<7 {
			width:=canvas.width*(.25-f32(step)*.027)
			rl.DrawRectangleRec({x-width*.5,y-f32(step)*22,width,22},{73+u8(step)*3,49+u8(step)*2,56,255})
			rl.DrawLineEx({x-width*.5,y-f32(step)*22},{x+width*.5,y-f32(step)*22},1,{189,132,85,100})
		}
		// Tall obelisks outside the board never obscure the puzzle cells.
		ox:=canvas.width*(.025 if side==0 else .975)
		rl.DrawRectangleRec({ox-10,canvas.height*.35,20,canvas.height*.54},{39,37,49,255})
		rl.DrawRectangleLinesEx({ox-10,canvas.height*.35,20,canvas.height*.54},1,{198,154,90,200})
		for n in 0..<5 {draw_ankh({ox,canvas.height*.44+f32(n)*38},8,{221,177,96,180})}
	}
	for i in 0..<14 {
		x:=math.mod(f32(i)*87+time*5,canvas.width)
		y:=canvas.height*.9+math.sin(time*.3+f32(i))*12
		rl.DrawLineEx({x,y},{x+28,y},1,{226,157,102,35})
	}
}
