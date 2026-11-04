package render

import "core:math"
import rl "vendor:raylib"

CYBER_PRESS_WIDTH :: FIXTURE_CELL
CYBER_PRESS_HEIGHT :: 208
CYBER_PRESS_FEET :: f32(206)
CYBER_PRESS_FRAMES :: 4
CYBER_WORKSHOP_ATLAS_HEIGHT :: CYBER_PRESS_HEIGHT+FIXTURE_CELL

@(private)
cyber_workshop_secondary_art :: proc(role:int)->(m:Expedition_Paper) {
	m.cutout=true;p:=fixture_art_palette(.Cyber)
	if role==0 {
		// Incoming housing and an unassembled motor: short, broad cargo.
		for side in ([2]f32{-1,1}) {paper_box(&m,side*.30-.07,0,.14,.13,p.shade)}
		fixture_round(&m,-.43,.10,.86,.49,p.body,p.shade,p.light)
		paper_box(&m,-.34,.27,.64,.07,p.light,false)
		paper_box(&m,-.08,.17,.15,.26,p.accent)
		paper_disc(&m,-.17,.68,.20,.18,p.shade)
		paper_disc(&m,-.17,.68,.12,.11,p.light,false)
		paper_disc(&m,-.17,.68,.055,.055,p.body,false)
		fixture_round(&m,.10,.59,.24,.19,p.light,p.body,EXPEDITION_PAPER_EDGE)
	} else if role==1 {
		// The processing run is low enough to see its rollers and material.
		for side in ([2]f32{-1,1}) {paper_limb(&m,{side*.39,.025},{side*.33,.39},.09,p.shade)}
		fixture_round(&m,-.46,.23,.92,.25,p.body,p.shade,p.light)
		paper_box(&m,-.42,.46,.84,.13,p.shade)
		for i in 0..<4 {paper_disc(&m,-.31+f32(i)*.21,.53,.085,.065,p.light)}
		paper_box(&m,-.42,.30,.74,.04,p.light,false)
		fixture_round(&m,-.10,.61,.24,.22,p.light,p.body,EXPEDITION_PAPER_EDGE)
		paper_box(&m,-.04,.65,.09,.10,p.accent,false)
	} else {
		// Storage is a tall open rack, visually different from every tool.
		for side in ([2]f32{-1,1}) {paper_box(&m,side*.35-.045,0,.09,1.42,p.light)}
		paper_box(&m,-.31,.16,.62,1.18,p.shade)
		for row in 0..<3 {
			y:=.14+f32(row)*.39
			paper_box(&m,-.41,y,.82,.07,p.body)
			fixture_round(&m,-.27,y+.09,.21,.25,p.body,p.shade,p.light)
			fixture_round(&m,.05,y+.09,.23,.19,p.light,p.body,EXPEDITION_PAPER_EDGE)
			paper_box(&m,-.22,y+.19,.08,.035,p.signal,false)
		}
		paper_box(&m,-.40,1.37,.80,.07,p.body)
	}
	lowest:=f32(100)
	for &part in m.parts[:m.count] {for point in part.points[:part.count] {lowest=min(lowest,point.y)}}
	for &part in m.parts[:m.count] {for &point in part.points[:part.count] {point.y-=lowest}}
	return
}

// A repair press, authored at the actor's pixel density. Height and working
// cavity give the main interaction priority; its feet still occupy one cell.
@(private)
cyber_press_art :: proc(frame:int)->(m:Expedition_Paper) {
	m.cutout=true;p:=fixture_art_palette(.Cyber);ink:=EXPEDITION_PAPER_INK
	for side in ([2]f32{-1,1}) {fixture_round(&m,side*.31-.10,0,.20,.18,p.shade,p.shade,p.body)}
	fixture_round(&m,-.41,.14,.82,.51,p.light,p.body,EXPEDITION_PAPER_EDGE)
	// The right plane and sloped shoulders are illustration, not geometry.
	paper_box(&m,-.30,.27,.44,.23,p.body)
	paper_box(&m,.24,.29,.07,.21,p.accent,false)
	fixture_display_print(&m,-.24,.31,.30,.13,p,frame%2)
	fixture_round(&m,-.42,.61,.18,1.65,p.light,p.body,EXPEDITION_PAPER_EDGE)
	fixture_round(&m,.25,.61,.18,1.65,p.light,p.body,EXPEDITION_PAPER_EDGE)
	chamber:=[4]rl.Vector2{{-.24,.67},{-.24,2.06},{.25,2.11},{.25,.72}}
	paper_polygon(&m,chamber[:],p.shade)
	paper_limb(&m,{-.18,.78},{-.18,1.98},.025,p.body,false)
	paper_limb(&m,{.16,.83},{.16,1.93},.025,p.body,false)
	head:=[8]rl.Vector2{{-.44,2.04},{-.45,2.44},{-.33,2.63},{.12,2.71},
		{.36,2.61},{.45,2.43},{.43,2.06},{.28,1.98}}
	paper_polygon(&m,head[:],p.accent)
	top:=[4]rl.Vector2{{-.33,2.53},{.11,2.61},{.32,2.55},{-.24,2.45}}
	paper_polygon(&m,top[:],p.light,false)
	side:=[4]rl.Vector2{{.27,2.06},{.42,2.11},{.43,2.41},{.27,2.48}}
	paper_polygon(&m,side[:],p.body,false)
	// One large pressure dial, two signal blocks, and an unmistakable ram.
	paper_disc(&m,-.10,2.30,.18,.18,p.shade)
	paper_disc(&m,-.10,2.30,.13,.13,p.light,false)
	needle:=rl.Vector2{-.18,2.34} if frame<2 else rl.Vector2{-.03,2.38}
	paper_limb(&m,{-.10,2.30},needle,.025,ink,false)
	paper_box(&m,.15,2.20,.07,.13,p.signal,false)
	stroke:=[CYBER_PRESS_FRAMES]f32{0,.12,.40,.10}
	ram:=1.64-stroke[clamp(frame,0,CYBER_PRESS_FRAMES-1)]
	paper_box(&m,-.075,ram,.15,2.06-ram,p.light)
	fixture_round(&m,-.20,ram-.14,.40,.17,{244,185,58,255},p.body,p.light)
	fixture_round(&m,-.24,.73,.48,.14,p.body,p.shade,p.light)
	// The small workpiece remains in the bay. The support envelope is stable.
	fixture_round(&m,-.12,.87,.24,.22,p.body,p.shade,p.light)
	paper_box(&m,-.055,.92,.08,.08,p.signal,false)
	for x in ([2]f32{-.34,.34}) {paper_box(&m,x-.022,1.18,.045,.48,p.accent,false)}
	// A small authored enlargement keeps the press primary without changing
	// pixel density, the occupied cell, the atlas dimensions or the quad.
	for &part in m.parts[:m.count] {for &point in part.points[:part.count] {
		point.x*=1.06;point.y*=1.02
	}}
	return
}

@(private)
cyber_press_raster :: proc(art:^Expedition_Paper)->(pixels:[CYBER_PRESS_WIDTH*CYBER_PRESS_HEIGHT]rl.Color) {
	for &part in art.parts[:art.count] {
		points:[12]rl.Vector2;lo:=rl.Vector2{CYBER_PRESS_WIDTH,CYBER_PRESS_HEIGHT};hi:=rl.Vector2{}
		for p,i in part.points[:part.count] {
			points[i]={f32(CYBER_PRESS_WIDTH)*.5+p.x*CARTOON_PIXELS,CYBER_PRESS_FEET-p.y*CARTOON_PIXELS}
			lo={min(lo.x,points[i].x),min(lo.y,points[i].y)};hi={max(hi.x,points[i].x),max(hi.y,points[i].y)}
		}
		for pass in 0..<(2 if part.edge else 1) {
			width:=f32(.85) if part.edge && pass==0 else 0
			color:=EXPEDITION_PAPER_INK if width>0 else part.color
			for y in max(0,int(math.floor(lo.y-1)))..=min(CYBER_PRESS_HEIGHT-1,int(math.ceil(hi.y+1))) {
				for x in max(0,int(math.floor(lo.x-1)))..=min(CYBER_PRESS_WIDTH-1,int(math.ceil(hi.x+1))) {
					p:=rl.Vector2{f32(x)+.5,f32(y)+.5};positive,negative:=false,false
					for a,i in points[:part.count] {
						b:=points[(i+1)%part.count];d:=b-a
						cross:=d.x*(p.y-a.y)-d.y*(p.x-a.x);tolerance:=width*rl.Vector2Length(d)
						if cross>tolerance {positive=true};if cross< -tolerance {negative=true}
					}
					if !(positive && negative) {pixels[y*CYBER_PRESS_WIDTH+x]=color}
				}
			}
		}
	}
	return
}

@(private)
cyber_press_mask :: proc(drawings:^[CYBER_PRESS_FRAMES][CYBER_PRESS_WIDTH*CYBER_PRESS_HEIGHT]rl.Color)->(mask:[CYBER_PRESS_WIDTH*CYBER_PRESS_HEIGHT]u8) {
	for y in 0..<int(CYBER_PRESS_FEET) {for x in 0..<CYBER_PRESS_WIDTH {
		distance:=100
		for dy in -8..=8 {for dx in -8..=8 {
			xx,yy:=x+dx,y+dy
			if xx<0 || xx>=CYBER_PRESS_WIDTH || yy<0 || yy>=CYBER_PRESS_HEIGHT {continue}
			for frame in 0..<CYBER_PRESS_FRAMES {if drawings[frame][yy*CYBER_PRESS_WIDTH+xx].a>0 {distance=min(distance,dx*dx+dy*dy)}}
		}}
		cut:=1 if y>=int(CYBER_PRESS_FEET)-5 else 64
		if distance<=cut {mask[y*CYBER_PRESS_WIDTH+x]=1 if distance>36 else 2}
	}}
	return
}

@(private)
create_cyber_press_art :: proc(assets:^Expedition_Fixture_Assets)->bool {
	drawings:=new([CYBER_PRESS_FRAMES][CYBER_PRESS_WIDTH*CYBER_PRESS_HEIGHT]rl.Color);defer free(drawings)
	for frame in 0..<CYBER_PRESS_FRAMES {art:=cyber_press_art(frame);drawings[frame]=cyber_press_raster(&art)}
	assets.hero_mask=cyber_press_mask(drawings)
	w:=CYBER_PRESS_WIDTH*CYBER_PRESS_FRAMES
	print:=make([]rl.Color,w*WORKSHOP_PRINT_HEIGHT);defer delete(print)
	stock:=make([]rl.Color,w*CYBER_WORKSHOP_ATLAS_HEIGHT);defer delete(stock)
	left,top,right,bottom:=CYBER_PRESS_WIDTH,CYBER_PRESS_HEIGHT,0,0
	for value,i in assets.hero_mask {
		if value==0 {continue};x,y:=i%CYBER_PRESS_WIDTH,i/CYBER_PRESS_WIDTH
		left=min(left,x);top=min(top,y);right=max(right,x+1);bottom=max(bottom,y+1)
		stock[y*w+x]=EXPEDITION_PAPER_INK if value==1 else EXPEDITION_PAPER_EDGE
		if value==2 {for frame in 0..<CYBER_PRESS_FRAMES {print[y*w+frame*CYBER_PRESS_WIDTH+x]=drawings[frame][i]}}
	}
	assets.hero_bounds={f32(left),f32(top),f32(right-left),f32(bottom-top)}
	for role in 0..<3 {
		art:=cyber_workshop_secondary_art(role);drawing:=cartoon_raster(&art);mask:=fixture_art_mask(&drawing,&drawing)
		assets.secondary_bounds[role]=expedition_fixture_mask_bounds(&mask)
		for value,i in mask {
			if value==0 {continue};x,y:=i%FIXTURE_CELL,i/FIXTURE_CELL
			at:=(CYBER_PRESS_HEIGHT+y)*w+role*FIXTURE_CELL+x
			stock[at]=EXPEDITION_PAPER_INK if value==1 else EXPEDITION_PAPER_EDGE
			if value==2 {print[at]=drawing[i]}
		}
	}
	// West uses another print row, but its immutable stock fits the empty
	// columns of the original paper texture. Cyber pixels stay byte-identical.
	for frame in 0..<CYBER_PRESS_FRAMES {art:=west_sawmill_art(frame);drawings[frame]=cyber_press_raster(&art)}
	assets.west_mask=cyber_press_mask(drawings)
	left,top,right,bottom=CYBER_PRESS_WIDTH,CYBER_PRESS_HEIGHT,0,0
	for value,i in assets.west_mask {
		if value==0 {continue};x,y:=i%CYBER_PRESS_WIDTH,i/CYBER_PRESS_WIDTH
		left=min(left,x);top=min(top,y);right=max(right,x+1);bottom=max(bottom,y+1)
		stock[y*w+CYBER_PRESS_WIDTH+x]=EXPEDITION_PAPER_INK if value==1 else EXPEDITION_PAPER_EDGE
		if value==2 {for frame in 0..<CYBER_PRESS_FRAMES {print[(WEST_WORKSHOP_PRINT_Y+y)*w+frame*CYBER_PRESS_WIDTH+x]=drawings[frame][i]}}
	}
	assets.west_bounds={f32(left),f32(top),f32(right-left),f32(bottom-top)}
	for role in 0..<3 {
		art:=west_workshop_secondary_art(role);drawing:=cartoon_raster(&art);mask:=fixture_art_mask(&drawing,&drawing)
		assets.west_secondary_bounds[role]=expedition_fixture_mask_bounds(&mask)
		paper_source:=west_secondary_paper_source(role)
		for value,i in mask {
			if value==0 {continue};x,y:=i%FIXTURE_CELL,i/FIXTURE_CELL
			paper_at:=(int(paper_source.y)+y)*w+int(paper_source.x)+x
			stock[paper_at]=EXPEDITION_PAPER_INK if value==1 else EXPEDITION_PAPER_EDGE
			if value==2 {print[(WEST_WORKSHOP_SECONDARY_Y+y)*w+role*FIXTURE_CELL+x]=drawing[i]}
		}
	}
	img:=rl.Image{data=raw_data(print),width=i32(w),height=WORKSHOP_PRINT_HEIGHT,mipmaps=1,format=.UNCOMPRESSED_R8G8B8A8}
	assets.hero_print=rl.LoadTextureFromImage(img)
	img={data=raw_data(stock),width=i32(w),height=CYBER_WORKSHOP_ATLAS_HEIGHT,mipmaps=1,format=.UNCOMPRESSED_R8G8B8A8}
	assets.hero_paper=rl.LoadTextureFromImage(img)
	if assets.hero_print.id==0 || assets.hero_paper.id==0 {return false}
	rl.SetTextureFilter(assets.hero_print,.POINT);rl.SetTextureFilter(assets.hero_paper,.POINT)
	return true
}
