package render

import "core:math"
import rl "vendor:raylib"

// Small convex paper pieces: geometry is independent of the graphics context,
// allowing silhouettes and animation bounds to be checked headlessly.
EXPEDITION_PAPER_PARTS :: 96
Expedition_Paper_Part :: struct { points:[12]rl.Vector2, count:int, color:rl.Color, edge:bool }
Expedition_Paper :: struct { parts:[EXPEDITION_PAPER_PARTS]Expedition_Paper_Part, count:int, cutout:bool }
EXPEDITION_PAPER_EDGE :: rl.Color{235,223,195,255}
EXPEDITION_PAPER_INK :: rl.Color{24,25,32,255}

@(private)
paper_polygon :: proc(model:^Expedition_Paper,points:[]rl.Vector2,color:rl.Color,edge:bool=true) {
	assert(len(points)>=3 && len(points)<=12 && model.count<EXPEDITION_PAPER_PARTS)
	p:=&model.parts[model.count];p.count=len(points);copy(p.points[:],points);p.color=color;p.edge=edge;model.count+=1
}
@(private)
paper_box :: proc(m:^Expedition_Paper,x,y,w,h:f32,c:rl.Color,edge:bool=true) {
	p:=[4]rl.Vector2{{x,y},{x+w,y},{x+w,y+h},{x,y+h}};paper_polygon(m,p[:],c,edge)
}
@(private)
paper_tri :: proc(m:^Expedition_Paper,a,b,c:rl.Vector2,color:rl.Color,edge:bool=true) {
	p:=[3]rl.Vector2{a,b,c};paper_polygon(m,p[:],color,edge)
}
@(private)
paper_disc :: proc(m:^Expedition_Paper,x,y,rx,ry:f32,c:rl.Color,edge:bool=true,phase:f32=0) {
	points:[10]rl.Vector2
	for i in 0..<len(points) {a:=f32(i)*math.PI*2/f32(len(points))+phase;points[i]={x+math.cos(a)*rx,y+math.sin(a)*ry}}
	paper_polygon(m,points[:],c,edge)
}
@(private)
paper_limb :: proc(m:^Expedition_Paper,a,b:rl.Vector2,width:f32,c:rl.Color,edge:bool=true) {
	d:=b-a;l:=math.sqrt(d.x*d.x+d.y*d.y);if l<0.001 {return};n:=rl.Vector2{-d.y/l,d.x/l}*(width*.5)
	points:=[4]rl.Vector2{a-n,b-n,b+n,a+n};paper_polygon(m,points[:],c,edge)
}

@(private)
draw_expedition_paper :: proc(renderer:^Renderer,m:^Expedition_Paper,base:rl.Vector3,scale:f32=1,mirror:bool=false,opacity:f32=1,horizontal_scale:f32=1) {
	if m.cutout {draw_expedition_cutout(renderer,m,base,scale,mirror,opacity,horizontal_scale);return}
	right:=flipbook_camera_right(renderer);normal:=rl.Vector3Normalize(rl.Vector3CrossProduct(right,{0,1,0}))
	flip:f32=-1 if mirror else 1
	for &part,i in m.parts[:m.count] {
		center:rl.Vector2;for p in part.points[:part.count] {center+=p};center/=f32(part.count)
		for layer in 0..<(3 if part.edge else 1) {
			expand:f32=.045 if layer==0 else (.018 if layer==1 else 0)
			color:=EXPEDITION_PAPER_EDGE if layer==0 else (EXPEDITION_PAPER_INK if layer==1 else part.color)
			if !part.edge {color=part.color;expand=0}
			color=color_with_opacity(color,opacity)
			vertices:[12]rl.Vector3
			for p,j in part.points[:part.count] {
				d:=p-center;l:=max(f32(.001),math.sqrt(d.x*d.x+d.y*d.y));q:=p+d*(expand/l)
				vertices[j]=base+right*(q.x*scale*flip*horizontal_scale)+rl.Vector3{0,q.y*scale,0}+normal*(.002*f32(i)+.0005*f32(layer))
			}
			for j in 1..<part.count-1 {
				rl.DrawTriangle3D(vertices[0],vertices[j],vertices[j+1],color)
				rl.DrawTriangle3D(vertices[0],vertices[j+1],vertices[j],color)
			}
		}
	}
}

// Offset a convex printed piece by a physical width. Adjacent edge normals
// keep thin legs as thick as the torso; radial scaling would pinch their border.
@(private)
paper_cut_vertex :: proc(part:^Expedition_Paper_Part,index:int,width:f32)->rl.Vector2 {
	p:=part.points[index]
	if width==0 {return p}
	prev:=part.points[(index+part.count-1)%part.count];next:=part.points[(index+1)%part.count]
	area:f32
	for a,i in part.points[:part.count] {b:=part.points[(i+1)%part.count];area+=a.x*b.y-a.y*b.x}
	orientation:f32=1 if area>=0 else -1
	a:=rl.Vector2Normalize(p-prev);b:=rl.Vector2Normalize(next-p)
	na:=rl.Vector2{a.y,-a.x}*orientation;nb:=rl.Vector2{b.y,-b.x}*orientation
	bisect:=rl.Vector2Normalize(na+nb)
	miter:=min(width/max(f32(.25),rl.Vector2DotProduct(bisect,na)),width*2.1)
	return p+bisect*miter
}

@(private)
draw_cutout_piece :: proc(part:^Expedition_Paper_Part,base,right,normal:rl.Vector3,scale,flip,horizontal_scale,width,depth:f32,color:rl.Color,rough:bool=false,index:int=0) {
	vertices:[12]rl.Vector3
	for _,j in part.points[:part.count] {
		// A stable, slightly uneven scissor edge, independent of frame time/RNG.
		w:=width*(.94+f32((index*7+j*11)%5)*.035) if rough else width
		q:=paper_cut_vertex(part,j,w)
		vertices[j]=base+right*(q.x*scale*flip*horizontal_scale)+rl.Vector3{0,q.y*scale,0}+normal*depth
	}
	for j in 1..<part.count-1 {
		rl.DrawTriangle3D(vertices[0],vertices[j],vertices[j+1],color)
		rl.DrawTriangle3D(vertices[0],vertices[j+1],vertices[j],color)
	}
}

// All cream silhouettes are drawn before any print, so overlapping pieces
// merge into one cut sheet instead of looking like separately edged metal.
@(private)
draw_expedition_cutout :: proc(renderer:^Renderer,m:^Expedition_Paper,base:rl.Vector3,scale:f32,mirror:bool,opacity,horizontal_scale:f32) {
	right:=flipbook_camera_right(renderer);normal:=rl.Vector3Normalize(rl.Vector3CrossProduct(right,{0,1,0}))
	flip:f32=-1 if mirror else 1
	for pass in 0..<3 {
		width:f32=.115 if pass==0 else (.102 if pass==1 else .097)
		color:=rl.Color{46,31,29,170} if pass==0 else (rl.Color{151,125,85,255} if pass==1 else EXPEDITION_PAPER_EDGE)
		offset:=right*.045+rl.Vector3{0,-.036,0} if pass==0 else (right*.018+rl.Vector3{0,-.013,0} if pass==1 else rl.Vector3{})
		for &part,i in m.parts[:m.count] {
			if !part.edge {continue}
			draw_cutout_piece(&part,base+offset*scale,right,normal,scale,flip,horizontal_scale,width,-.03+f32(pass)*.008,color_with_opacity(color,opacity),true,i)
		}
	}
	for &part,i in m.parts[:m.count] {
		depth:=.002*f32(i)
		if part.edge {draw_cutout_piece(&part,base,right,normal,scale,flip,horizontal_scale,.022,depth,color_with_opacity(EXPEDITION_PAPER_INK,opacity))}
		draw_cutout_piece(&part,base,right,normal,scale,flip,horizontal_scale,0,depth+.0005,color_with_opacity(part.color,opacity))
	}
}
