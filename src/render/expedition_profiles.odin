package render

import "core:c"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// Authored cut-paper outlines, clockwise in local x/y, with at most 32
// corners. Ear clipping preserves concave notches instead of filling them
// with a triangle fan. Fixed scratch storage also serves the immediate
// fallback; the ordinary world path bakes these faces once per chunk.
@(private)
ink_profile_cross :: proc(a,b,c:rl.Vector2)->f32 {return (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)}

@(private)
ink_profile_triangles :: proc(profile:[]rl.Vector2)->(indices:[90]int,count:int) {
	n:=len(profile);if n<3 || n>32 {return}
	remaining:[32]int;for i in 0..<n {remaining[i]=i}
	for n>3 {
		found:=false
		for i in 0..<n {
			a,b,d:=remaining[(i+n-1)%n],remaining[i],remaining[(i+1)%n]
			if ink_profile_cross(profile[a],profile[b],profile[d])>=-.000001 {continue}
			inside:=false
			for j in 0..<n {
				p:=remaining[j];if p==a || p==b || p==d {continue}
				if ink_profile_cross(profile[a],profile[b],profile[p])<=.000001 &&
				   ink_profile_cross(profile[b],profile[d],profile[p])<=.000001 &&
				   ink_profile_cross(profile[d],profile[a],profile[p])<=.000001 {inside=true;break}
			}
			if inside {continue}
			indices[count],indices[count+1],indices[count+2]=a,b,d;count+=3
			for j in i..<n-1 {remaining[j]=remaining[j+1]};n-=1;found=true;break
		}
		// Invalid/self-intersecting outlines must never yield partial solids.
		if !found {count=0;return}
	}
	if ink_profile_cross(profile[remaining[0]],profile[remaining[1]],profile[remaining[2]])>=-.000001 {count=0;return}
	indices[count],indices[count+1],indices[count+2]=remaining[0],remaining[1],remaining[2];count+=3
	return
}

@(private)
ink_profile :: proc(pass:Ink_Pass,base:rl.Vector3,profile:[]rl.Vector2,scale:rl.Vector2,depth,yaw:f32,fill,side,edge:rl.Color) {
	indices,count:=ink_profile_triangles(profile);if count==0 {return}
	front,back:[32]rl.Vector3
	for p,i in profile {
		front[i]=cyber_point(base,{p.x*scale.x,p.y*scale.y,depth*.5},yaw)
		back[i]=cyber_point(base,{p.x*scale.x,p.y*scale.y,-depth*.5},yaw)
	}
	if pass.mode==.Fill || pass.mode==.Bake {
		if pass.mode==.Fill {_=rlgl.CheckRenderBatchLimit(c.int(count*2+len(profile)*6));rlgl.Begin(rlgl.TRIANGLES)}
		for i:=0;i<count;i+=3 {
			a,b,d:=indices[i],indices[i+1],indices[i+2]
			ink_triangle(pass,front[a],front[d],front[b],fill)
			ink_triangle(pass,back[a],back[b],back[d],fill)
		}
		for a in 0..<len(profile) {
			b:=(a+1)%len(profile)
			ink_triangle(pass,back[a],front[a],front[b],side)
			ink_triangle(pass,back[a],front[b],back[b],side)
		}
		if pass.mode==.Fill {rlgl.End()}
	}
	if edge.a==0 {return}
	// The expedition camera keeps its +x/+z azimuth (also in reflection).
	// Stroke only the facing ring, avoiding doubled edges on thin sheets.
	ring:=front if math.cos(yaw)-math.sin(yaw)>=0 else back
	for i in 0..<len(profile) {ink_line(pass,ring[i],ring[(i+1)%len(profile)],edge)}
}

// Eight broad faces, restrained bevel and no nested trim. The chosen cut is
// bounded by the authored footprint; cardinal orientation preserves cells.
@(private)
ink_chamfer_box :: proc(pass:Ink_Pass,base:rl.Vector3,half:rl.Vector2,height,yaw:f32,fill,cap,edge:rl.Color,cut:f32=.08) {
	a:=cyber_chamfer_ring(base,half,cut,yaw)
	b:=cyber_chamfer_ring(base+{0,height,0},half,cut,yaw)
	ink_solid(pass,a[:],b[:],fill,cap,{})
	if edge.a==0 {return}
	// The outer perimeter carries ink; no line around each bevel face.
	for i in 0..<8 {ink_line(pass,b[i],b[(i+1)%8],edge)}
	for i in ([4]int{1,3,5,7}) {ink_line(pass,a[i],b[i],edge)}
}

// A broad leaf carries one painted midrib. Both points are within a fixed
// profile, so its grounded stem never becomes a platform or collision pad.
@(private)
ink_leaf :: proc(pass:Ink_Pass,base:rl.Vector3,width,height,yaw,lean:f32,fill:rl.Color) {
	profile:=[8]rl.Vector2{{-.06,0},{-.26,.18},{-.94,.47},{-.78,.78},{lean,1},
		{.70,.81},{.82,.48},{.12,.10}}
	ink_profile(pass,base,profile[:],{width,height},.028,yaw,fill,EXPEDITION_PAPER_EDGE,EXPEDITION_PAPER_INK)
	ink_line(pass,cyber_point(base,{0,.05*height,.020},yaw),cyber_point(base,{lean*width*.62,.82*height,.020},yaw),ink_scale(fill,.48))
}
