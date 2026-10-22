package memoryarcade

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import host "../engine/host"
import ui "../engine/ui"

INK :: rl.Color{19,23,33,255}
PAPER :: rl.Color{245,236,210,255}
CYAN :: rl.Color{102,230,247,255}
PINK :: rl.Color{251,90,163,255}
GOLD :: rl.Color{255,199,92,255}

point :: proc(a: rl.Rectangle, x,y: f32) -> rl.Vector2 { return {a.x+x*a.width,a.y+y*a.height} }
line :: proc(a: rl.Rectangle, x,y,xx,yy: f32, width: f32, color: rl.Color) {
	rl.DrawLineEx(point(a,x,y),point(a,xx,yy),width,color)
}

// raylib culls clockwise screen triangles; artwork helpers accept either
// winding so a changed silhouette cannot silently disappear.
triangle :: proc(a,b,c: rl.Vector2, color: rl.Color) {
	if (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)>0 { rl.DrawTriangle(a,c,b,color) }
	else { rl.DrawTriangle(a,b,c,color) }
}

draw_backdrop :: proc(a: rl.Rectangle, time: f32, color: rl.Color) {
	rl.DrawRectangleGradientV(i32(a.x),i32(a.y),i32(a.width),i32(a.height),rl.Color{8,12,23,255},rl.Color{24,14,29,255})
	for i in 0..<45 {
		x:=f32((i*137+29)%997)/997*a.width
		y:=f32((i*79+31)%431)/431*a.height
		alpha:=u8(45+30*(1+math.sin(time*0.45+f32(i))))
		c:=color; c.a=alpha
		rl.DrawRectangleRec({x,y,2,2},c)
	}
}

// A tiny printed cutout vocabulary. Dark ink, a warm paper edge and an
// offset shadow distinguish the actors from the texture-free neon world.
Paper_Kind :: enum { Robot, Bike, Dino, Cowboy, Horse, Tree, Yeti, Helicopter, Tank, Panda }
draw_paper :: proc(kind: Paper_Kind, origin_x,origin_y,scale: f32, tint: rl.Color, mirror:=false, angle:f32=0) {
	rows: []string
	switch kind {
	case .Robot: rows=[]string{"   ####   ","  #TTTT#  ","  #C##C#  ","   ####   "," ##TTTT## ","#T#TTTT#T#","## TTTT ##","   ####   ","  TT  TT  ","  ##  ##  "}
	case .Bike: rows=[]string{"      ##    ","     #TT#   ","     ####   ","   ##TT#    ","  TTTTT###  ","##CCCCCCCC##","#TT######TT#"," ###    ### "}
	case .Dino: rows=[]string{"       ###### ","      #TTTTTT#","      #TT#TTT#","     ##TTTT###","    #TTTTT#   ","#  #TTTTTT### ","####TTTTT#    "," #TTTTTTT#    ","  ##TTTT#     ","    ##T##     ","    #T# #T#   ","    ### ###   "}
	case .Cowboy: rows=[]string{"    TTTT    ","  TTTTTTTT  ","    ####    ","    #CC#    ","    ####    ","  ##TTTT####","  #TTTTTCCCC","  ##TTTT##  ","   #TTTT#   ","   ##  ##   ","  ###  ###  "}
	case .Horse: rows=[]string{"         ##  ","        #TT# ","    ##  #TTT#","    ##  #TT##","   #TT###TT# "," ###TTTTTTT# ","#TTTTTTTTT#  ","###TTTTTT#   ","  #T#  #T#   ","  #T#  #T#   ","  ###  ###   "}
	case .Tree: rows=[]string{"     T     ","    TTT    ","   TTTTT   ","    TTT    ","  TTTTTTT  ","   TTTTT   "," TTTTTTTTT ","TTTTTTTTTTT","    ###    ","    ###    "}
	case .Yeti: rows=[]string{"    ####    ","  ##TTTT##  "," #TT#CC#TT# ","#TTT####TTT#","#TTTTTTTTTT#","#TTTTTTTTTT#","###TTTTTT###","  #TTTTTT#  ","  #TT##TT#  ","  #######   "}
	case .Helicopter: rows=[]string{" CCCCCCCCCCCCC ","       #       ","      ####     "," ##  #TTCC#    ","#TT###TTCCC#   "," ##TTTTTTTTT#  ","   #########   ","     #   #     ","   #########   "}
	case .Tank: rows=[]string{"     ###      ","    #TTT######","   ##TTTTTTTTT","  #TTTTTT###  "," #TTTTTTTTT#  ","############# ","#C#C#C#C#C#C# "," ############ "}
	case .Panda: rows=[]string{"   #######  ","  #CCCCCCC# "," #CC#CCC#CC#","#TTTTTTTTTT#","#TTTTTTTTTT#","#CCTTTTTTCC#","############"," ##      ## "}
	}
	w:=f32(len(rows[0]))*scale; h:=f32(len(rows))*scale
	rlgl.PushMatrix()
	rlgl.Translatef(origin_x+w*.5,origin_y+h*.5,0)
	rlgl.Rotatef(angle,0,0,1)
	rlgl.Translatef(-w*.5,-h*.5,0)
	defer rlgl.PopMatrix()
	x,y:=f32(0),f32(0)
	rl.DrawEllipse(i32(x+w*0.5+4),i32(y+h+4),w*0.5,scale*1.5,rl.Color{0,0,0,60})
	for row,yy in rows {
		for ch,xx in row {
			if ch==' ' { continue }
			px:=f32(len(row)-1-xx) if mirror else f32(xx)
			rl.DrawRectangleRec({x+px*scale-1.5,y+f32(yy)*scale-1.5,scale+3,scale+3},PAPER)
		}
	}
	for row,yy in rows {
		for ch,xx in row {
			if ch==' ' { continue }
			px:=f32(len(row)-1-xx) if mirror else f32(xx)
			c:=INK if ch=='#' else (CYAN if ch=='C' else tint)
			rl.DrawRectangleRec({x+px*scale,y+f32(yy)*scale,scale,scale},c)
		}
	}
}

draw_horizon :: proc(a: rl.Rectangle, tint: rl.Color, time: f32, snow:=false) {
	bg:=rl.Color{18,27,43,255} if snow else rl.Color{19,15,31,255}
	rl.DrawRectangleRec(a,bg)
	for i in 0..<8 {
		x:=f32(i)*0.18-0.2
		h:=f32((i*7)%5)*0.025+0.1
		c:=rl.Color{49,65,84,255} if snow else rl.Color{40,27,43,255}
		triangle(point(a,x,0.4),point(a,x+0.1,0.10+h),point(a,x+0.25,0.4),c)
		line(a,x,0.4,x+0.1,0.10+h,1,tint)
		line(a,x+0.1,0.10+h,x+0.25,0.4,1,rl.Color{tint.r,tint.g,tint.b,70})
		if snow { triangle(point(a,x+0.07,0.20+h),point(a,x+0.1,0.10+h),point(a,x+0.14,0.20+h),PAPER) }
	}
	rl.DrawRectangleRec({a.x,a.y+a.height*0.4,a.width,a.height*0.6},rl.Color{9,18,30,255})
	for i in 0..<17 {
		x:=f32(i)/16
		line(a,0.5+(x-0.5)*0.1,0.4,x,1,1,rl.Color{41,52,68,255})
	}
	for i in 0..<10 {
		t:=f32(i)/10+math.mod(time*0.05,0.1)
		y:=0.4+t*t*0.6
		line(a,0,y,1,y,1,rl.Color{39,48,64,255})
	}
	line(a,0,0.4,1,0.4,2,tint)
}

draw_cycles :: proc(g: ^Game, f: ^host.Frame, a: rl.Rectangle) {
	s:=&g.state
	cell:=min(a.width/f32(GRID_W),a.height/f32(GRID_H))
	ox:=a.x+(a.width-cell*GRID_W)/2; oy:=a.y+(a.height-cell*GRID_H)/2
	colors:=[4]rl.Color{CYAN,PINK,GOLD,{179,233,108,255}}
	for y in 0..<GRID_H {
		for x in 0..<GRID_W {
			v:=s.grid[y*GRID_W+x]
			c:=rl.Color{15,25,38,255}
			if v>0 { c=colors[v-1]; c.a=170 }
			rl.DrawRectangleRec({ox+f32(x)*cell+1,oy+f32(y)*cell+1,cell-2,cell-2},c)
			if v>0 { rl.DrawRectangleRec({ox+f32(x)*cell+cell*0.35,oy+f32(y)*cell+cell*0.35,cell*0.3,cell*0.3},PAPER) }
		}
	}
	rl.DrawRectangleLinesEx({ox-1,oy-1,cell*GRID_W+2,cell*GRID_H+2},2,PINK)
	for c,i in s.cycles {
		if !c.alive { continue }
		x:=ox+f32(c.pos.x)*cell; y:=oy+f32(c.pos.y)*cell
		rl.DrawCircleV({x+cell/2,y+cell/2},cell*0.9,rl.Color{colors[i].r,colors[i].g,colors[i].b,50})
		rl.DrawRectangleRec({x-1,y-1,cell+2,cell+2},PAPER)
		rl.DrawRectangleRec({x+1,y+1,cell-2,cell-2},colors[i])
		d:=dir_delta(c.dir)
		rl.DrawLineEx({x+cell/2,y+cell/2},{x+cell/2+f32(d.x)*cell*0.8,y+cell/2+f32(d.y)*cell*0.8},2,INK)
	}
	ui.draw_text(f.theme,"TU / CIANO",{a.x+12,a.y+10},.Small,CYAN)
}

draw_showdown :: proc(g: ^Game, f: ^host.Frame, a: rl.Rectangle) {
	s:=&g.state
	draw_horizon(a,GOLD,s.time)
	rl.DrawCircleV(point(a,0.5,0.24),a.height*0.11,rl.Color{245,159,65,255})
	for i in 0..<5 {
		x:=f32(i)*0.23-0.02
		p:=point(a,x,0.36)
		rl.DrawRectangleRec({p.x,p.y,a.width*0.16,a.height*0.27},rl.Color{42,31,34,255})
		line(a,x,0.36,x+0.16,0.36,3,GOLD)
		for j in 0..<3 { line(a,x+0.035+f32(j)*0.042,0.41,x+0.035+f32(j)*0.042,0.61,6,INK) }
	}
	line(a,0.02,0.81,0.98,0.81,2,GOLD)
	scale:=a.height/100
	draw_paper(.Robot,a.x+a.width*0.18,a.y+a.height*0.81-scale*10,scale,CYAN)
	draw_paper(.Cowboy,a.x+a.width*0.72,a.y+a.height*0.81-scale*11,scale,GOLD,true)
	if s.fired && s.round_pause>1.1 && !s.early {
		line(a,0.26,0.59,0.74,0.59,3,PAPER)
	}
	label:="ASPETTA"
	color:=GOLD
	if s.clock>=s.cue && s.round_pause<=0 { label="ESTRAI!"; color=CYAN }
	if s.round_pause>0 {
		if s.early { label="TROPPO PRESTO"; color=PINK } else if s.fired { label=fmt.tprintf("%.0f ms",s.reaction*1000); color=CYAN } else { label="TI HA PRECEDUTO"; color=PINK }
	}
	box:=rl.Rectangle{a.x+a.width*0.3,a.y+a.height*0.39,a.width*0.4,52}
	rl.DrawRectangleRec(box,INK)
	rl.DrawRectangleLinesEx(box,2,color)
	ui.draw_text_fit(f.theme,label,box,.Title,color,.Center)
	ui.draw_text_fit(f.theme,fmt.tprintf("DUELLO %d / 5     VINTI %d",min(s.duel+1,5),s.duel_wins),{a.x,a.y+14,a.width,24},.Body,PAPER,.Center)
}

draw_trex :: proc(g: ^Game, f: ^host.Frame, a: rl.Rectangle) {
	s:=&g.state
	draw_horizon(a,rl.Color{154,219,75,255},s.time)
	for i in 0..<13 {
		x:=math.mod(f32(i)*0.13-s.time*0.035+20,1.3)-0.15
		p:=point(a,x,0.27)
		line(a,x+0.04,0.65,x+0.04,0.27,8,rl.Color{36,53,45,255})
			triangle({p.x-30,p.y+55},{p.x+30,p.y-30},{p.x+90,p.y+55},rl.Color{34,71,54,255})
	}
	line(a,0,0.79,1,0.79,3,rl.Color{173,234,85,255})
	scale:=a.height/110
	draw_paper(.Dino,a.x-10+f32(3-s.health)*16,a.y+a.height*0.78-scale*17,scale*1.45,rl.Color{139,180,75,255})
	py:=s.pos.y*a.height
	if g.duck && s.pos.y>=0.77 { py+=scale*3; scale*=0.7 }
	if s.invincible<=0 || int(s.time*16)%2==0 {
		draw_paper(.Robot,a.x+s.pos.x*a.width-scale*5,a.y+py-scale*10,scale,CYAN)
	}
	for o in s.obstacles {
		if !o.active { continue }
		p:=point(a,o.pos.x,o.pos.y)
		switch o.kind {
		case 0:
			triangle({p.x-20,p.y},{p.x,p.y-45},{p.x+22,p.y},rl.Color{68,95,69,255})
			rl.DrawTriangleLines({p.x-20,p.y},{p.x,p.y-45},{p.x+22,p.y},GOLD)
		case 1:
			rl.DrawRectangleRec({p.x-27,p.y-24,54,25},PAPER)
			rl.DrawRectangleRec({p.x-25,p.y-22,50,21},rl.Color{100,75,48,255})
		case:
			triangle({p.x-33,p.y-18},{p.x,p.y+8},{p.x+30,p.y-18},PAPER)
			triangle({p.x-27,p.y-16},{p.x,p.y+4},{p.x+25,p.y-16},PINK)
		}
	}
	ui.draw_text_fit(f.theme,fmt.tprintf("SERIE  %d",s.combo),{a.x+14,a.y+26,180,24},.Small,CYAN,.Left)
}

draw_karaoke :: proc(g: ^Game, f: ^host.Frame, a: rl.Rectangle) {
	s:=&g.state
	// A skyline, wet street and four illuminated vocal tracks.
	for i in 0..<16 {
		x:=f32(i)/16
		h:=f32((i*11)%7)*0.035+0.15
		rl.DrawRectangleRec({a.x+x*a.width,a.y+a.height*(0.5-h),a.width/18,a.height*h},rl.Color{31,24,51,255})
		line(a,x,0.5-h,x,0.5,1,PINK)
	}
	left:=a.x+a.width*0.29; width:=a.width*0.43; lane:=width/4
	colors:=[4]rl.Color{CYAN,PINK,GOLD,{172,136,255,255}}
	for i in 0..<4 {
		x:=left+f32(i)*lane
		rl.DrawRectangleRec({x,a.y,lane-3,a.height},rl.Color{18,24,39,240})
		rl.DrawLineEx({x,a.y},{x,a.y+a.height},1,colors[i])
		box:=rl.Rectangle{x+5,a.y+a.height*0.81,lane-12,38}
		rl.DrawRectangleRec(box,colors[i])
		labels:=[4]string{"A","S","D","F"}
		ui.draw_text_fit(f.theme,labels[i],box,.Large,INK,.Center)
	}
	line(a,0.29,0.8,0.72,0.8,4,PAPER)
	for n in s.notes {
		if n.judgement!=0 { continue }
		y:=a.y+a.height*(0.8-(n.time-s.time)*0.36)
		if y<a.y-20 || y>a.y+a.height { continue }
		x:=left+f32(n.lane)*lane+7
		rl.DrawRectangleRec({x-2,y-2,lane-16,16},PAPER)
		rl.DrawRectangleRec({x,y,lane-20,12},colors[n.lane])
	}
	draw_paper(.Robot,a.x+a.width*0.08,a.y+a.height*0.55,a.height/95,CYAN)
	line(a,0.17,0.64,0.2,0.53,5,PAPER)
	rl.DrawCircleV(point(a,0.2,0.53),8,PINK)
	ui.draw_text_fit(f.theme,fmt.tprintf("%d",s.combo),{a.x+a.width*0.75,a.y+a.height*0.30,a.width*0.22,64},.Title,CYAN,.Center)
	ui.draw_text_fit(f.theme,"COMBO",{a.x+a.width*0.75,a.y+a.height*0.43,a.width*0.22,30},.Small,PAPER,.Center)
	if s.flash>0 {
		label:="PRECISO" if s.judgement==3 else ("BUONO" if s.judgement==2 else "MANCATA")
		ui.draw_text_fit(f.theme,label,{a.x+a.width*0.75,a.y+a.height*0.55,a.width*0.22,30},.Body,PINK if s.judgement<0 else GOLD,.Center)
	}
	ui.draw_text_fit(f.theme,fmt.tprintf("%d / 64",s.judged),{a.x+a.width*0.75,a.y+20,a.width*0.22,28},.Body,PAPER,.Center)
}

draw_helicopter :: proc(g: ^Game, f: ^host.Frame, a: rl.Rectangle) {
	s:=&g.state
	draw_horizon(a,rl.Color{124,156,71,255},s.time)
	for i in 0..<25 {
		x:=math.mod(f32(i)*0.133-s.time*0.018+20,1.2)-0.1
		y:=0.36+f32(i%5)*0.09
		p:=point(a,x,y)
		draw_paper(.Tree,p.x,p.y,1.4+f32(i%3)*0.4,rl.Color{59,95,60,255})
	}
	for o in s.obstacles {
		if !o.active { continue }
		p:=point(a,o.pos.x,o.pos.y)
		kind:=Paper_Kind.Tank if o.kind==0 else (.Helicopter if o.kind==1 else .Robot)
		draw_paper(kind,p.x-24,p.y-20,3,rl.Color{184,178,100,255})
		color:=PINK if o.timer<1.2 else GOLD
		rl.DrawCircleLinesV(p,35,color)
		rl.DrawRing(p,37,40,-90,-90+360*clamp(o.timer/4,0,1),40,color)
	}
	// Door frame and mounted gun are foreground cutouts, not a second HUD.
	rl.DrawRectangleRec({a.x,a.y,20,a.height},rl.Color{47,52,57,255})
	rl.DrawRectangleRec({a.x+a.width-20,a.y,20,a.height},rl.Color{47,52,57,255})
	line(a,0,0.02,1,0.02,12,rl.Color{55,61,65,255})
	line(a,0.58,1,0.53,0.78,26,PAPER)
	line(a,0.58,1,0.53,0.78,20,rl.Color{55,64,66,255})
	if s.shot_timer>0.1 {
		line(a,0.53,0.78,s.aim.x,s.aim.y,2,GOLD)
		rl.DrawCircleV(point(a,0.53,0.78),18,rl.Color{255,205,94,160})
	}
	p:=point(a,s.aim.x,s.aim.y)
	rl.DrawCircleLinesV(p,12,CYAN)
	rl.DrawLineEx({p.x-20,p.y},{p.x-7,p.y},2,PAPER)
	rl.DrawLineEx({p.x+7,p.y},{p.x+20,p.y},2,PAPER)
	rl.DrawLineEx({p.x,p.y-20},{p.x,p.y-7},2,PAPER)
	rl.DrawLineEx({p.x,p.y+7},{p.x,p.y+20},2,PAPER)
	ui.draw_text_fit(f.theme,"RICARICA" if s.reload_timer>0 else fmt.tprintf("%02d / 16",s.ammo),{a.x+30,a.y+a.height-42,180,30},.Large,GOLD,.Left)
}

draw_descent :: proc(g: ^Game, f: ^host.Frame, a: rl.Rectangle) {
	s:=&g.state
	draw_horizon(a,CYAN,s.time,true)
	rl.DrawTriangle(point(a,0.33,0.2),point(a,0.02,1),point(a,0.98,1),rl.Color{175,204,215,255})
	rl.DrawTriangle(point(a,0.33,0.2),point(a,0.98,1),point(a,0.67,0.2),rl.Color{192,215,222,255})
	for i in 0..<14 {
		y:=math.mod(f32(i)/14+s.time*0.13,1)
		line(a,0.05,y,0.02,y+0.05,2,rl.Color{84,140,159,120})
		line(a,0.95,y,0.98,y+0.05,2,rl.Color{84,140,159,120})
	}
	for o in s.obstacles {
		if !o.active { continue }
		p:=slope_point(a,o.pos.x,o.pos.y)
		if o.kind==4 {
			span:=a.width*0.115*(0.34+0.62*o.pos.y)
			rl.DrawLineEx({p.x-span,p.y},{p.x-span,p.y-35},3,INK)
			rl.DrawLineEx({p.x+span,p.y},{p.x+span,p.y-35},3,INK)
			rl.DrawLineEx({p.x-span,p.y-32},{p.x+span,p.y-32},4,CYAN)
		} else {
			scale:=2+2.5*o.pos.y
			draw_paper(.Tree,p.x-5.5*scale,p.y-10*scale,scale,rl.Color{51,103,97,255})
		}
	}
	p:=slope_point(a,s.pos.x,s.pos.y)
	rl.DrawLineEx(slope_point(a,s.pos.x-0.018,s.pos.y+0.02),slope_point(a,s.pos.x-0.03-s.velocity.x*0.1,s.pos.y+0.15),2,rl.Color{117,166,185,255})
	rl.DrawLineEx(slope_point(a,s.pos.x+0.018,s.pos.y+0.02),slope_point(a,s.pos.x+0.03-s.velocity.x*0.1,s.pos.y+0.15),2,rl.Color{117,166,185,255})
	rl.DrawLineEx({p.x-12,p.y+7},{p.x-6+s.velocity.x*12,p.y-19},5,PINK)
	rl.DrawLineEx({p.x+10,p.y+7},{p.x+16+s.velocity.x*12,p.y-19},5,PINK)
	if s.invincible<=0 || int(s.time*16)%2==0 { draw_paper(.Robot,p.x-17,p.y-39,3.5,CYAN) }
	draw_paper(.Yeti,a.x+a.width*0.47,a.y+a.height*0.91,a.height/115,PAPER)
	ui.draw_text(f.theme,fmt.tprintf("PORTALI %d",s.hits),{a.x+14,a.y+28},.Small,CYAN)
}

slope_point :: proc(a: rl.Rectangle,x,y: f32) -> rl.Vector2 {
	return point(a,0.5+(x-0.5)*(0.34+0.62*y),0.2+y*0.8)
}
