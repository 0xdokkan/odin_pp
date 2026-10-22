package application

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import campaign "../campaign"
import world "../expedition"
import ui "../engine/ui"
import render "../render"

// Small, rotating dioramas are made from the same ink-edged geometry as
// the worlds. Each arriving memory assembles one triangular face at a time.
@(private)
hub_draw_island :: proc(h:^Campaign_Hub,b:campaign.Biome,origin:rl.Vector3,theme:^ui.Theme=nil) {
	c:=render.expedition_color(b)
	if !h.progress.unlocked[b] {c={65,63,79,255}}
	turn:=h.clock*.09+f32(b)*.53
	formation:=f32(1)
	if h.new_islands[b] {formation=clamp((h.clock-h.revealed_at-f32(b)*.06)/2,0,1)}
	ink:=rl.Color{12,15,26,255}
	for i in 0..<8 {
		t:=clamp(formation*8-f32(i),0,1);if t<=0 {continue}
		a:=turn+f32(i)*math.PI/4;z:=turn+f32(i+1)*math.PI/4
		lift:=rl.Vector3{0,(1-t)*3,0}
		p:=origin+rl.Vector3{math.cos(a)*2,1.4,math.sin(a)*2}+lift
		q:=origin+rl.Vector3{math.cos(z)*2,1.4,math.sin(z)*2}+lift
		bottom:=origin+rl.Vector3{0,-1.7,0}+lift;center:=origin+{0,1.4,0}+lift
		face:=rl.Color{u8(19+i*2),u8(18+i*2),u8(31+i*2),255}
		rl.DrawTriangle3D(bottom,p,q,face);rl.DrawTriangle3D(bottom,q,p,face)
		rl.DrawTriangle3D(center,q,p,ink);rl.DrawTriangle3D(center,p,q,ink)
		rl.DrawLine3D(p,q,c);rl.DrawLine3D(p,bottom,{c.r/3,c.g/3,c.b/3,255})
	}
	if formation<1 {return}
	point:=proc(origin:rl.Vector3,angle,x,y,z:f32)->rl.Vector3 {return origin+{x*math.cos(angle)-z*math.sin(angle),y,x*math.sin(angle)+z*math.cos(angle)}}
	for i in 0..<5 {
		a:=f32(i)*1.26; x,z:=math.cos(a)*1.12,math.sin(a)*1.12
		p:=point(origin,turn,x,1.45,z);height:=f32(.45)+f32((i+int(b))%3)*.34
		#partial switch b {
		case .Cyber,.City:
			rl.DrawCubeV(p+{0,height*.5,0},{.48,height,.48},ink);rl.DrawCubeWiresV(p+{0,height*.5,0},{.48,height,.48},c)
			for j in 0..<3 {rl.DrawCubeV(p+{0,.15+f32(j)*.22,.25},{.27,.05,.025},c)}
		case .Egypt:
			rl.DrawCylinder(p,0,.65,height+.2,4,{36,27,22,255});rl.DrawCylinderWires(p,0,.65,height+.2,4,c)
		case .Jungle,.Vietnam:
			rl.DrawCylinder(p,.06,.1,.8,5,{83,62,39,255});rl.DrawCylinder(p+{0,.65,0},.1,.55,.65,5,c)
		case .Snow:
			rl.DrawCylinder(p,0,.65,height+.5,5,{105,145,166,255});rl.DrawCylinder(p+{0,(height+.5)*.72,0},0,.19,(height+.5)*.3,5,{233,233,213,255})
		case .West:
			rl.DrawCylinder(p,.09,.12,height+.2,5,c);rl.DrawCubeV(p+{.2,.35,0},{.4,.1,.12},c);rl.DrawCubeV(p+{.36,.48,0},{.1,.3,.12},c)
		case .Gothic:
			rl.DrawCubeV(p+{0,.3,0},{.15,.6,.13},c);rl.DrawCubeV(p+{0,.43,0},{.45,.12,.12},c)
		case .Sky:
			rl.DrawCylinder(p,.12,.13,.9,8,{190,181,163,255});rl.DrawCubeV(p+{0,.93,0},{.42,.1,.3},c)
		case .Inferno:
			rl.DrawCylinder(p,0,.35,height+.4,4,c);rl.DrawLine3D(p+{-.35,.02,0},p+{.35,.02,.3},{255,196,65,255})
		case .Space:
			rl.DrawSphereEx(p+{0,.28,0},.32,4,5,{70,60,89,255});rl.DrawSphereWires(p+{0,.28,0},.33,4,5,c)
		case .Secret:
			rl.DrawCubeV(p+{0,height*.5,0},{.13,height,.13},{215,205,182,255})
		}
	}
	if h.progress.won[b] {hub_draw_island_sign(h,b,origin,theme)}
}

// Print directly from the already owned UI font atlas. The board owns no
// render target or texture; glyph metrics retain the font's actual spacing.
@(private)
hub_sign_text :: proc(font:rl.Font,text:string,top,right,up,normal:rl.Vector3,width,height:f32) {
	if font.texture.id==0 || font.baseSize<=0 {return}
	advance:f32;count:=0
	for letter in text {
		glyph:=rl.GetGlyphInfo(font,letter);rec:=rl.GetGlyphAtlasRec(font,letter)
		advance+=(f32(glyph.advanceX) if glyph.advanceX>0 else rec.width)+1;count+=1
	}
	if count==0 {return};advance-=1
	scale:=min(height/f32(font.baseSize),width/max(advance,1))
	x:=-advance*scale*.5;pad:=f32(font.glyphPadding)
	rlgl.SetTexture(font.texture.id);rlgl.Begin(rlgl.QUADS);rlgl.Color4ub(33,32,36,255)
	for letter in text {
		glyph:=rl.GetGlyphInfo(font,letter);rect:=rl.GetGlyphAtlasRec(font,letter)
		if letter!=' ' && rect.width>0 && rect.height>0 {
			rec:=rl.Rectangle{rect.x-pad,rect.y-pad,rect.width+2*pad,rect.height+2*pad}
			p:=top+right*(x+(f32(glyph.offsetX)-pad)*scale)-up*((f32(glyph.offsetY)-pad)*scale)+normal*.025
			w,h:=rec.width*scale,rec.height*scale
			vertices:=[4]rl.Vector3{p-up*h,p+right*w-up*h,p+right*w,p}
			u0,v0:=rec.x/f32(font.texture.width),rec.y/f32(font.texture.height)
			u1,v1:=(rec.x+rec.width)/f32(font.texture.width),(rec.y+rec.height)/f32(font.texture.height)
			uv:=[4]rl.Vector2{{u0,v1},{u1,v1},{u1,v0},{u0,v0}}
			for v,i in vertices {rlgl.TexCoord2f(uv[i].x,uv[i].y);rlgl.Vertex3f(v.x,v.y,v.z)}
		}
		x+=((f32(glyph.advanceX) if glyph.advanceX>0 else rect.width)+1)*scale
	}
	rlgl.End();rlgl.SetTexture(0)
}

@(private)
hub_sign_polygon :: proc(points:[]rl.Vector2,center,right,up:rl.Vector3,scale:f32,color:rl.Color) {
	for i in 1..<len(points)-1 {
		a:=center+right*(points[0].x*scale)+up*(points[0].y*scale)
		b:=center+right*(points[i].x*scale)+up*(points[i].y*scale)
		c:=center+right*(points[i+1].x*scale)+up*(points[i+1].y*scale)
		rl.DrawTriangle3D(a,b,c,color)
	}
}

@(private)
hub_draw_island_sign :: proc(h:^Campaign_Hub,b:campaign.Biome,origin:rl.Vector3,theme:^ui.Theme) {
	cam:=hub_camera(h);forward:=rl.Vector3Normalize(cam.target-cam.position)
	right:=rl.Vector3Normalize(rl.Vector3CrossProduct(forward,cam.up));up:=rl.Vector3CrossProduct(right,forward);normal:=-forward
	center:=origin+rl.Vector3{0,3.35,0}+normal*.16
	rl.DrawCubeV(origin+{0,2.3,0},{.12,1.8,.12},{52,38,34,255})
	points:=[8]rl.Vector2{{-1.8,-.62},{1.72,-.65},{1.85,-.48},{1.82,.56},{1.64,.66},{-1.71,.63},{-1.84,.45},{-1.85,-.48}}
	hub_sign_polygon(points[:],center+right*.04-up*.04-normal*.04,right,up,1.035,{54,34,31,255})
	hub_sign_polygon(points[:],center-normal*.02,right,up,1.02,{155,125,83,255})
	hub_sign_polygon(points[:],center,right,up,1,{235,223,193,255})
	font:=theme.fonts[.Body] if theme!=nil && theme.has_fonts else rl.GetFontDefault()
	name:=world.metadata(b).boss
	split:=-1;best:=len(name)
	if len(name)>19 {for letter,i in name {if letter==' ' && abs(i-len(name)/2)<best {split=i;best=abs(i-len(name)/2)}}}
	// Transparent atlas margins must not write depth across adjacent glyphs.
	rlgl.DrawRenderBatchActive();rlgl.DisableDepthMask()
	if split>=0 {
		hub_sign_text(font,name[:split],center+up*.48,right,up,normal,3.22,.29)
		hub_sign_text(font,name[split+1:],center+up*.16,right,up,normal,3.22,.29)
	} else {hub_sign_text(font,name,center+up*.32,right,up,normal,3.22,.4)}
	rlgl.DrawRenderBatchActive();rlgl.EnableDepthMask()
	indices,n:=hub_biome_arcades(b);stars:=u8(0)
	for index in indices[:n] {if index>=0 && index<len(h.progress.records) {stars=max(stars,h.progress.records[index].best_stars)}}
	for i in 0..<3 {
		star:[10]rl.Vector2
		for j in 0..<10 {a:=f32(j)*math.PI/5+math.PI*.5;r:=f32(.17) if j%2==0 else .075;star[j]={math.cos(a)*r,math.sin(a)*r}}
		p:=center+right*(f32(i-1)*.47)-up*.39+normal*.027
		for layer in 0..<2 {
			scale:=f32(1.15) if layer==0 else .88
			color:=rl.Color{51,41,36,255} if layer==0 else (rl.Color{210,152,52,255} if i<int(stars) else rl.Color{191,182,159,255})
			star_center:=p+normal*(f32(layer)*.002)
			// A center fan follows the five concave notches of a printed star.
			for j in 0..<10 {a,z:=star[j],star[(j+1)%10];rl.DrawTriangle3D(star_center,star_center+(right*a.x+up*a.y)*scale,star_center+(right*z.x+up*z.y)*scale,color)}
		}
	}
}
