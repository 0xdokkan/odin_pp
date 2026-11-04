package render

import "core:math"
import rl "vendor:raylib"
import gfx "../engine/gfx"
import game "../game"
import view "../engine/view"

// Authored procedural drawings baked once into nearest-filtered pixel art.
// Owned by Expedition_Material, destroyed with it. The atlas is immutable;
// only the clip/frame index changes during play. No per-frame image uploads.
@(private)
// Extra transparent padding accommodates the broad stock around aerials
// without shrinking the drawing or changing its 60px/world-unit scale.
CARTOON_CELL :: 104
@(private)
CARTOON_PIXELS :: f32(60)
@(private)
CARTOON_FEET :: f32(102)
@(private)
CARTOON_FRAMES :: 6
@(private)
CARTOON_COLUMNS :: 24
@(private)
CARTOON_ACTORS :: 8 // robot, six enemy roles, seated robot
@(private)
CARTOON_LABEL_BANDS :: 8
@(private)
Expedition_Cartoon_Assets :: struct {
	print, paper: rl.Texture2D,
	mask: [CARTOON_ACTORS][CARTOON_CELL*CARTOON_CELL]u8,
	top: [CARTOON_ACTORS]int,
	bounds: [CARTOON_ACTORS]rl.Rectangle,
	label_bands: [CARTOON_ACTORS][CARTOON_LABEL_BANDS]rl.Rectangle,
}

// Pixel-space occupied extents, gathered with the immutable stock upload.
// Empty bands remain zero rectangles; UI never scans masks during a frame.
@(private)
cartoon_include_pixel :: proc(bounds:^rl.Rectangle,x,y:int) {
	px,py:=f32(x),f32(y)
	if bounds.width<=0 || bounds.height<=0 {bounds^={px,py,1,1};return}
	right,bottom:=max(bounds.x+bounds.width,px+1),max(bounds.y+bounds.height,py+1)
	bounds.x=min(bounds.x,px);bounds.y=min(bounds.y,py)
	bounds.width=right-bounds.x;bounds.height=bottom-bounds.y
}

// The six roles have their own whole silhouettes, not armour floating over
// an unrelated gothic figure. Palette, joints and ink match the explorer.
@(private)
expedition_cyber_actor_art :: proc(role:game.Enemy_Archetype,time:f32,action:gfx.Living_Action=.Idle,progress:f32=0)->(m:Expedition_Paper) {
	m.cutout=true
	ink:=EXPEDITION_PAPER_INK;red:=rl.Color{244,62,55,255};light:=rl.Color{255,145,83,255}
	blue:=rl.Color{22,128,193,255};screen:=rl.Color{29,235,245,255};cream:=EXPEDITION_PAPER_EDGE
	phase:=progress*math.TAU
	walking:=action==.Move_Side || action==.Move_Up || action==.Move_Down || action==.Dodge
	step:=math.sin(phase*2)*.055 if walking else f32(0)
	bob:=abs(step)*.28+math.sin(time*2.7)*.007
	punch:=math.sin(progress*math.PI)*.16 if action==.Attack || action==.Cast else f32(0)
	if role==.Chaser {
		// Low four-legged maintenance crab: clear space between its feet.
		for side in ([2]f32{-1,1}) {for leg in 0..<2 {
			a:=rl.Vector2{side*.20,.48+bob};b:=rl.Vector2{side*(.34+f32(leg)*.12),.32+step*side-punch*.7}
			foot:=rl.Vector2{side*(.32+f32(leg)*.20)+step*side,.04}
			paper_limb(&m,a,b,.095,red);paper_disc(&m,b.x,b.y,.065,.065,light)
			paper_limb(&m,b,foot,.065,blue);paper_box(&m,foot.x-.055,0,.11,.085,ink)
		}}
		paper_box(&m,-.26,.36+bob,.52,.31,red)
		paper_box(&m,-.19,.46+bob,.38,.12,ink);paper_box(&m,-.15,.49+bob,.06,.055,screen,false);paper_box(&m,.09,.49+bob,.06,.055,screen,false)
		paper_box(&m,-.12,.68+bob,.24,.05,light);paper_box(&m,-.04,.69+bob,.08,.03,cream,false)
	} else {
		wide:=f32(.32) if role==.Brute || role==.Demolitionist else .23
		for side in ([2]f32{-1,1}) {
			hip:=rl.Vector2{side*wide*.55,.42+bob};knee:=rl.Vector2{side*wide*.72+step*side,.24}
			foot:=rl.Vector2{side*wide*.82-step*side,.045}
			paper_limb(&m,hip,knee,.12,ink);paper_disc(&m,knee.x,knee.y,.085,.07,red)
			paper_limb(&m,knee,foot,.09,blue);paper_box(&m,foot.x-.09,0,.20,.10,red)
			paper_box(&m,foot.x-.065,.025,.12,.025,light,false)
		}
		paper_box(&m,-wide,.39+bob,wide*2,.39,red)
		paper_box(&m,-wide+.04,.69+bob,wide*2-.08,.045,light,false)
		paper_box(&m,-.13,.47+bob,.26,.20,blue);paper_box(&m,-.055,.53+bob,.11,.09,{245,184,65,255})
		for side in ([2]f32{-1,1}) {
			x:=side*(wide+.06);hand:=rl.Vector2{x+side*(.06+punch),.40+bob+punch*.8+step*side}
			paper_disc(&m,x,.72+bob,.09,.09,light);paper_limb(&m,{x,.68+bob},hand,.10,ink)
			paper_box(&m,hand.x-.075,hand.y-.06,.15,.13,red)
		}
		head:=[8]rl.Vector2{{-.25,.88+bob},{-.25,1.08+bob},{-.18,1.16+bob},{.18,1.16+bob},{.25,1.08+bob},{.25,.88+bob},{.18,.81+bob},{-.18,.81+bob}}
		paper_polygon(&m,head[:],red);paper_box(&m,-.185,.89+bob,.37,.19,ink)
		for side in ([2]f32{-1,1}) {paper_box(&m,side*.10-.025,.95+bob,.05,.075,screen,false)}
		paper_box(&m,-.13,1.10+bob,.21,.025,light,false)
		if role==.Archer {for side in ([2]f32{-1,1}) {
			// Paired cannons and aerials fill the stable backing in both
			// directions; an empty mirrored weapon lobe reads as torn paper.
			paper_box(&m,side*.38-.16,.47,.32,.10,blue)
			paper_box(&m,side*.54-.025,.46,.05,.12,ink)
			paper_box(&m,side*.38-.075,.54,.15,.025,screen,false)
			paper_limb(&m,{side*.15,1.14},{side*.17,1.33},.028,ink);paper_disc(&m,side*.17,1.34,.045,.045,screen)
		}}
		if role==.Brute {for side in ([2]f32{-1,1}) {paper_box(&m,side*.4-.11,.63+bob,.22,.22,red);paper_box(&m,side*.4-.075,.77+bob,.15,.035,cream,false)}}
		if role==.Bomber {for side in ([2]f32{-1,1}) {
			paper_disc(&m,side*.34,.53,.20,.22,ink);paper_disc(&m,side*.34,.53,.12,.13,{255,190,35,255})
			paper_limb(&m,{side*.34,.74},{side*.40,.84},.035,ink);paper_disc(&m,side*.40,.86,.045,.055,light,false)
		}}
		if role==.Custodian {for side in ([2]f32{-1,1}) {
			p:=[5]rl.Vector2{{side*.62,.7},{side*.31,.7},{side*.29,.4},{side*.46,.26},{side*.64,.4}}
			paper_polygon(&m,p[:],blue);paper_box(&m,side*.46-.03,.40,.06,.22,screen,false)
		}}
		if role==.Demolitionist {for i in 0..<3 {x:=f32(i-1)*.15;paper_box(&m,x-.035,1.14,.07,.15+f32(i%2)*.08,{242,181,63,255});paper_disc(&m,x,1.31+f32(i%2)*.08,.045,.045,screen)}}
	}
	if action==.Hurt || action==.Hurt_Back || action==.Stunned {
		for &part in m.parts[:m.count] {if part.color==screen {part.color=cream}}
	}
	if action==.Death {for &part in m.parts[:m.count] {for &point in part.points[:part.count] {point.y*=.55;point.x+=point.y*.18}}}
	return
}

@(private)
cartoon_art :: proc(actor:int,time:f32,action:gfx.Living_Action,progress:f32)->Expedition_Paper {
	if actor==0 || actor==7 {return expedition_robot_art(time,action,progress,actor==7)}
	return expedition_cyber_actor_art(game.Enemy_Archetype(actor-1),time,action,progress)
}

// Pixel centers are evaluated against convex polygons; edges are dilated
// on the integer grid afterwards. This produces actual pixel art, including
// diagonal stairs, at the same density for every actor and every pose.
@(private)
cartoon_raster :: proc(art:^Expedition_Paper)->(pixels:[CARTOON_CELL*CARTOON_CELL]rl.Color) {
	for &part in art.parts[:art.count] {
		points:[12]rl.Vector2;lo:=rl.Vector2{CARTOON_CELL,CARTOON_CELL};hi:=rl.Vector2{}
		for p,i in part.points[:part.count] {
			points[i]={f32(CARTOON_CELL)*.5+p.x*CARTOON_PIXELS,CARTOON_FEET-p.y*CARTOON_PIXELS}
			lo={min(lo.x,points[i].x),min(lo.y,points[i].y)};hi={max(hi.x,points[i].x),max(hi.y,points[i].y)}
		}
		// A one-pixel printed ink contour per articulated piece.
		for pass in 0..<(2 if part.edge else 1) {
			width:=f32(.85) if part.edge && pass==0 else 0
			color:=EXPEDITION_PAPER_INK if width>0 else part.color
			for y in max(0,int(math.floor(lo.y-1)))..=min(CARTOON_CELL-1,int(math.ceil(hi.y+1))) {
				for x in max(0,int(math.floor(lo.x-1)))..=min(CARTOON_CELL-1,int(math.ceil(hi.x+1))) {
					p:=rl.Vector2{f32(x)+.5,f32(y)+.5};positive,negative:=false,false
					for a,i in points[:part.count] {
						b:=points[(i+1)%part.count];d:=b-a
						cross:=d.x*(p.y-a.y)-d.y*(p.x-a.x);tolerance:=width*rl.Vector2Length(d)
						if cross>tolerance {positive=true};if cross< -tolerance {negative=true}
					}
					if !(positive && negative) {pixels[y*CARTOON_CELL+x]=color}
				}
			}
		}
	}
	return
}

@(private)
cartoon_paper_mask :: proc(actor:int)->(mask:[CARTOON_CELL*CARTOON_CELL]u8) {
	art:=cartoon_art(actor,0,.Idle,0);pixels:=cartoon_raster(&art)
	for y in 0..<CARTOON_CELL {for x in 0..<CARTOON_CELL {
		// No paper beneath the soles, even for a wide crab or the heavy robot.
		if f32(y)>=CARTOON_FEET {continue}
		distance:=100
		for dy in -7..=7 {for dx in -7..=7 {
			px,py:=x+dx,y+dy
			if px<0 || px>=CARTOON_CELL || py<0 || py>=CARTOON_CELL {continue}
			if pixels[py*CARTOON_CELL+px].a>0 || pixels[py*CARTOON_CELL+CARTOON_CELL-1-px].a>0 {distance=min(distance,dx*dx+dy*dy)}
		}}
		// At the soles the cut follows each foot closely. Broad dilation
		// here would bridge the gap and accidentally make a white baseplate.
		cut:=1 if f32(y)>=CARTOON_FEET-3 else 49
		if distance<=cut {mask[y*CARTOON_CELL+x]=1 if distance>25 else 2}
	}}
	return
}

@(private)
create_expedition_cartoon :: proc(m:^Expedition_Material)->bool {
	if m.cartoon!=nil {return m.cartoon.print.id!=0 && m.cartoon.paper.id!=0}
	assets:=new(Expedition_Cartoon_Assets);m.cartoon=assets
	count:=CARTOON_ACTORS*len(gfx.Living_Action)*CARTOON_FRAMES
	w,h:=CARTOON_COLUMNS*CARTOON_CELL,((count+CARTOON_COLUMNS-1)/CARTOON_COLUMNS)*CARTOON_CELL
	pixels:=make([]rl.Color,w*h);defer delete(pixels)
	stock:=make([]rl.Color,CARTOON_ACTORS*CARTOON_CELL*CARTOON_CELL);defer delete(stock)
	for actor in 0..<CARTOON_ACTORS {
		assets.mask[actor]=cartoon_paper_mask(actor)
		assets.top[actor]=CARTOON_CELL
		for value,i in assets.mask[actor] {
			x,y:=i%CARTOON_CELL,i/CARTOON_CELL
			if value>0 {assets.top[actor]=min(assets.top[actor],y)}
			if value>0 {
				cartoon_include_pixel(&assets.bounds[actor],x,y)
				cartoon_include_pixel(&assets.label_bands[actor][y*CARTOON_LABEL_BANDS/CARTOON_CELL],x,y)
				stock[y*CARTOON_ACTORS*CARTOON_CELL+actor*CARTOON_CELL+x]=EXPEDITION_PAPER_INK if value==1 else EXPEDITION_PAPER_EDGE
			}
		}
		for action in gfx.Living_Action {for frame in 0..<CARTOON_FRAMES {
			progress:=f32(frame)/f32(CARTOON_FRAMES-1)
			art:=cartoon_art(actor,progress*2.4,action,progress);drawing:=cartoon_raster(&art)
			index:=(actor*len(gfx.Living_Action)+int(action))*CARTOON_FRAMES+frame
			x0,y0:=index%CARTOON_COLUMNS*CARTOON_CELL,index/CARTOON_COLUMNS*CARTOON_CELL
			for color,i in drawing {
				if assets.mask[actor][i]==2 {pixels[(y0+i/CARTOON_CELL)*w+x0+i%CARTOON_CELL]=color}
			}
		}}
	}
	img:=rl.Image{data=raw_data(pixels),width=i32(w),height=i32(h),mipmaps=1,format=.UNCOMPRESSED_R8G8B8A8}
	assets.print=rl.LoadTextureFromImage(img)
	img={data=raw_data(stock),width=CARTOON_ACTORS*CARTOON_CELL,height=CARTOON_CELL,mipmaps=1,format=.UNCOMPRESSED_R8G8B8A8}
	assets.paper=rl.LoadTextureFromImage(img)
	rl.SetTextureFilter(assets.print,.POINT);rl.SetTextureFilter(assets.paper,.POINT)
	return assets.print.id!=0 && assets.paper.id!=0
}

@(private)
destroy_expedition_cartoon :: proc(m:^Expedition_Material) {
	if m.cartoon==nil {return}
	rl.UnloadTexture(m.cartoon.print);rl.UnloadTexture(m.cartoon.paper);free(m.cartoon);m.cartoon=nil
}

@(private)
expedition_cartoon_actor :: proc(renderer:^Renderer,key:Sprite_Key)->(index:int,ok:bool) {
	if !renderer.tactical.expedition || renderer.tactical.outline_mode==.Hologram {return}
	if key==.Player {return 7 if renderer.tactical.expedition_mounted else 0,true}
	if renderer.tactical.expedition_biome==0 && key>=.Chaser && key<=.Demolitionist {return int(key)-int(Sprite_Key.Chaser)+1,true}
	return
}

@(private)
expedition_cartoon_geometry :: proc(renderer:^Renderer,key:Sprite_Key,position:view.Vec2,entity:game.Entity_Ref)->(q:Tactical_Billboard,ok:bool) {
	index,valid:=expedition_cartoon_actor(renderer,key)
	if !valid || !expedition_material_ready(renderer) || !create_expedition_cartoon(renderer.tactical.expedition_material) {return}
	v:=&renderer.tactical;assets:=v.expedition_material.cartoon
	now:=living_clock(renderer,entity);action:=gfx.Living_Action.Idle;progress:=f32(now/2.4-math.floor(now/2.4));width:=f32(1)
	character,_:=flipbook_character(key);actor:=living_find(renderer,entity,character)
	if actor!=nil {
		if key==.Player {expedition_walker_face(renderer,actor,now)}
		action,_=living_drawing(actor,now);q.mirror=actor.facing_left
		clip:=&gfx.LIVING_SHEETS[character].clips[action]
		seconds:=max(.001,living_played_seconds(clip,actor.scale))
		// living_drawing also falls back to the base after a one-shot ends.
		started:=actor.base_started
		if actor.action!=.Idle && action==actor.action && now>=actor.started {started=actor.started}
		elapsed:=(now-started)/seconds
		progress=f32(elapsed-math.floor(elapsed)) if clip.loop else f32(clamp(elapsed,0,1))
		turn:=living_turn_progress(actor,now)
		if actor.turn_started>=0 && turn<1 {width=max(f32(.04),abs(f32(math.cos(turn*math.PI))));if turn<.5 {q.mirror=!q.mirror}}
	}
	if key==.Player && expedition_walker_speed(renderer)>.3 && (action==.Idle || action==.Move_Side || action==.Move_Up || action==.Move_Down) {
		action=.Move_Side;progress=v.expedition_stride/1.8-math.floor(v.expedition_stride/1.8)
	}
	frame:=clamp(int(progress*f32(CARTOON_FRAMES)),0,CARTOON_FRAMES-1)
	cell:=(index*len(gfx.Living_Action)+int(action))*CARTOON_FRAMES+frame
	q.texture=assets.print;q.source={f32(cell%CARTOON_COLUMNS*CARTOON_CELL),f32(cell/CARTOON_COLUMNS*CARTOON_CELL),CARTOON_CELL,CARTOON_CELL}
	q.cartoon=true;q.key=key;q.card=assets.paper;q.card_a={f32(index*CARTOON_CELL),0,CARTOON_CELL,CARTOON_CELL}
	scales:=[CARTOON_ACTORS]f32{1.36,1.36,1.30,1.48,1.30,1.35,1.48,1.19}
	scale:=scales[index]/CARTOON_PIXELS
	at,lift:=living_card_position(renderer,entity,key,position)
	if key==.Player {v.expedition_player_shown=at;v.expedition_player_drawn=true;if v.expedition_mounted {lift+=.42}}
	base:=rl.Vector3{at.x+.5,lift+.008,at.y+.5}
	base.y-=tactical_shadow_depth(renderer,entity)*1.7
	right:=flipbook_camera_right(renderer);up:=rl.Vector3{0,1,0}
	bottom:=base-up*((CARTOON_CELL-CARTOON_FEET)*scale)
	top:=up*(CARTOON_CELL*scale);half:=right*(CARTOON_CELL*.5*scale)
	// Walking free it leans into its speed-up and back as it brakes (expedition_walker.odin).
	if key==.Player && v.expedition_free {top+=right*(v.expedition_lean*CARTOON_CELL*scale)}
	q.card_points={bottom-half+top,bottom-half,bottom+half,bottom+half+top}
	// Only the print narrows when it turns. The backing stays anchored.
	half*=width
	q.points={bottom-half+top,bottom-half,bottom+half,bottom+half+top}
	if fall:=living_fall(actor,now);fall>0 {topple_card_points(&q.points,v.camera,fall);topple_card_points(&q.card_points,v.camera,fall)}
	return q,true
}

@(private)
expedition_cartoon_hit :: proc(renderer:^Renderer,q:Tactical_Billboard,ray:rl.Ray)->(distance:f32,hit:bool) {
	collision:=rl.GetRayCollisionQuad(ray,q.card_points[0],q.card_points[1],q.card_points[2],q.card_points[3])
	if !collision.hit {return}
	uv:=card_hit_uv(q.card_points,collision.point)
	x,y:=clamp(int(uv.x*CARTOON_CELL),0,CARTOON_CELL-1),clamp(int(uv.y*CARTOON_CELL),0,CARTOON_CELL-1)
	index,_:=expedition_cartoon_actor(renderer,q.key)
	if renderer.tactical.expedition_material.cartoon.mask[index][y*CARTOON_CELL+x]==0 {return}
	return collision.distance,true
}
