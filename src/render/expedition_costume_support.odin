package render

import "core:math"
import rl "vendor:raylib"
import campaign "../campaign"
import game "../game"
import gfx "../engine/gfx"
import view "../engine/view"

// Match the bolder raster cut used by expedition actors and machinery. Keep
// this out of the generic paper defaults: the hub uses the same drawing kit.
@(private)
EXPEDITION_COSTUME_BORDER_SCALE :: f32(1.6)
@(private)
EXPEDITION_COSTUME_INK_MARGIN :: f32(.070)*EXPEDITION_COSTUME_BORDER_SCALE
@(private)
EXPEDITION_COSTUME_IVORY_MARGIN :: f32(.053)*EXPEDITION_COSTUME_BORDER_SCALE

// CPU-only, immutable after first use of each outfit. The material owns this
// cache (including in borrowed renderers), and frees it with its other assets.
// No GPU objects, per-frame envelope generation, or simulation RNG.
@(private)
Expedition_Costume_Assets :: struct {
	ready:[int(campaign.Biome.Count)][int(game.Enemy_Archetype.Count)]bool,
	support:[int(campaign.Biome.Count)][int(game.Enemy_Archetype.Count)]Expedition_Paper,
}

@(private)
costume_cross :: proc(a,b,c:rl.Vector2)->f32 {d,e:=b-a,c-a;return d.x*e.y-d.y*e.x}

@(private)
costume_convex_envelope :: proc(input:[]rl.Vector2)->(part:Expedition_Paper_Part) {
	points:[156]rl.Vector2;n:=0
	for p in input {
		at:=n
		for at>0 && (points[at-1].x>p.x || points[at-1].x==p.x && points[at-1].y>p.y) {
			points[at]=points[at-1];at-=1
		}
		points[at]=p;n+=1
	}
	unique:=0
	for i in 0..<n {
		if unique>0 && points[i]==points[unique-1] {continue}
		points[unique]=points[i];unique+=1
	}
	hull:[312]rl.Vector2;k:=0
	for p in points[:unique] {
		for k>=2 && costume_cross(hull[k-2],hull[k-1],p)<=0 {k-=1}
		hull[k]=p;k+=1
	}
	lower:=k
	for i:=unique-2;i>=0;i-=1 {
		p:=points[i]
		for k>lower && costume_cross(hull[k-2],hull[k-1],p)<=0 {k-=1}
		hull[k]=p;k+=1
	}
	k-=1
	assert(k>=3 && k<=len(part.points),"costume support must fit the convex paper-piece budget")
	part.count=k;part.edge=true;part.color=EXPEDITION_PAPER_EDGE
	copy(part.points[:],hull[:k])
	return
}

@(private)
build_expedition_costume_support :: proc(b:campaign.Biome,role:game.Enemy_Archetype)->(support:Expedition_Paper) {
	// Each authored moving part has one sine at 3, 4, 7 or 9 rad/s. Include
	// both exact extrema of every frequency; convex envelopes contain every
	// intermediate pose, not just a sampled film. Tests enforce containment.
	times:=[13]f32{0,math.PI/6,math.PI/2,math.PI/8,3*math.PI/8,math.PI/14,3*math.PI/14,math.PI/18,math.PI/6,
		(math.PI/2-1)/3,(3*math.PI/2-1)/3,(math.PI/2-2)/3,(3*math.PI/2-2)/3}
	poses:[13]Expedition_Paper
	for time,i in times {poses[i]=expedition_enemy_costume_art(b,role,time)}
	support.count=poses[0].count;support.cutout=true
	for i in 0..<support.count {
		points:[156]rl.Vector2;n:=0
		for &pose in poses {
			assert(pose.count==support.count,"costume animation must preserve authored part topology")
			for p in pose.parts[i].points[:pose.parts[i].count] {points[n]=p;n+=1}
		}
		support.parts[i]=costume_convex_envelope(points[:n])
	}
	return
}

@(private)
expedition_costume_support :: proc(m:^Expedition_Material,b:campaign.Biome,role:game.Enemy_Archetype)->^Expedition_Paper {
	if m==nil || b==.Cyber || b>=.Count || role>=.Count {return nil}
	if m.costumes==nil {m.costumes=new(Expedition_Costume_Assets)}
	if !m.costumes.ready[int(b)][int(role)] {
		m.costumes.support[int(b)][int(role)]=build_expedition_costume_support(b,role)
		m.costumes.ready[int(b)][int(role)]=true
	}
	return &m.costumes.support[int(b)][int(role)]
}

@(private)
draw_expedition_costume_sheet :: proc(right:rl.Vector3,support,print:^Expedition_Paper,base:rl.Vector3,scale:f32,mirror:bool,opacity,width:f32) {
	normal:=rl.Vector3Normalize(rl.Vector3CrossProduct(right,{0,1,0}))
	// Both facings belong to one stationary sheet. Only the printed wardrobe
	// turns or animates, exactly as the underlying living rig does.
	for pass in 0..<2 {
		border:=EXPEDITION_COSTUME_INK_MARGIN if pass==0 else EXPEDITION_COSTUME_IVORY_MARGIN
		color:=EXPEDITION_PAPER_INK if pass==0 else EXPEDITION_PAPER_EDGE
		for flip in ([2]f32{-1,1}) {for &part,i in support.parts[:support.count] {
			draw_cutout_piece(&part,base,right,normal,scale,flip,1,border,-.004+f32(pass)*.002,color_with_opacity(color,opacity),true,i)
		}}
	}
	flip:=f32(-1) if mirror else 1
	for &part,i in print.parts[:print.count] {
		depth:=.0001*f32(i)
		if part.edge {draw_cutout_piece(&part,base,right,normal,scale,flip,width,.022,depth,color_with_opacity(EXPEDITION_PAPER_INK,opacity))}
		draw_cutout_piece(&part,base,right,normal,scale,flip,width,0,depth+.0005,color_with_opacity(part.color,opacity))
	}
}

// Picking uses the same expanded support polygons, including its stationary
// opposite-facing weapon/hat lobes, rather than an enlarged rectangular hitbox.
@(private)
expedition_costume_support_hit :: proc(support:^Expedition_Paper,ray:rl.Ray,base,right:rl.Vector3,scale:f32)->(distance:f32,hit:bool) {
	distance=1e30
	for flip in ([2]f32{-1,1}) {for &part,i in support.parts[:support.count] {
		vertices:[12]rl.Vector3
		for j in 0..<part.count {
			width:=EXPEDITION_COSTUME_INK_MARGIN*(.94+f32((i*7+j*11)%5)*.035)
			p:=paper_cut_vertex(&part,j,width)
			vertices[j]=base+right*(p.x*scale*flip)+rl.Vector3{0,max(p.y,0)*scale,0}
		}
		for j in 1..<part.count-1 {
			a,b,c:=vertices[0],vertices[j],vertices[j+1]
			forward:=rl.GetRayCollisionTriangle(ray,a,b,c)
			backward:=rl.GetRayCollisionTriangle(ray,a,c,b)
			for collision in ([2]rl.RayCollision{forward,backward}) {
				if collision.hit && collision.distance<distance {distance=collision.distance;hit=true}
			}
		}
	}}
	return
}

@(private)
expedition_costume_hit :: proc(renderer:^Renderer,key:Sprite_Key,position:view.Vec2,entity:game.Entity_Ref,ray:rl.Ray)->(f32,bool) {
	v:=&renderer.tactical
	if !v.expedition || v.outline_mode==.Hologram || key<.Chaser || key>.Demolitionist {return 0,false}
	role:=game.Enemy_Archetype(int(key)-int(Sprite_Key.Chaser))
	support:=expedition_costume_support(v.expedition_material,campaign.Biome(v.expedition_biome),role)
	if support==nil {return 0,false}
	height:=f32(1.2)
	if character,ok:=flipbook_character(key);ok {height=gfx.LIVING_SHEETS[character].world_height}
	at,lift:=living_card_position(renderer,entity,key,position)
	right:=flipbook_camera_right(renderer);normal:=rl.Vector3Normalize(rl.Vector3CrossProduct(right,{0,1,0}))
	base:=rl.Vector3{at.x+.5,.035+lift,at.y+.5}+normal*.061
	return expedition_costume_support_hit(support,ray,base,right,height)
}
