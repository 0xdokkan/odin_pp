package render

import "core:testing"
import "core:slice"
import rl "vendor:raylib"

@(test)
test_west_sawmill_actions_keep_one_grounded_card_and_clear_atlas_edges :: proc(t:^testing.T) {
	drawings:=new([CYBER_PRESS_FRAMES][CYBER_PRESS_WIDTH*CYBER_PRESS_HEIGHT]rl.Color);defer free(drawings)
	for frame in 0..<CYBER_PRESS_FRAMES {
		art:=west_sawmill_art(frame)
		for &part in art.parts[:art.count] {
			positive,negative:=false,false
			for a,i in part.points[:part.count] {
				b,c:=part.points[(i+1)%part.count],part.points[(i+2)%part.count]
				cross:=ink_profile_cross(a,b,c)
				if cross>.000001 {positive=true};if cross< -.000001 {negative=true}
				testing.expect(t,abs(a.x)<.5 && a.y>=0 && a.y<2.8)
			}
			testing.expect(t,!(positive && negative),"source must remain convex for the shared raster")
		}
		drawings[frame]=cyber_press_raster(&art)
		if frame>0 {testing.expect(t,!slice.equal(drawings[frame-1][:],drawings[frame][:]))}
	}
	mask:=cyber_press_mask(drawings);feet:=0
	for value,i in mask {
		x,y:=i%CYBER_PRESS_WIDTH,i/CYBER_PRESS_WIDTH
		if y>=int(CYBER_PRESS_FEET) {testing.expect_value(t,value,u8(0));continue}
		if value>0 {testing.expect(t,x>0 && x<CYBER_PRESS_WIDTH-1 && y>0)}
		for frame in 0..<CYBER_PRESS_FRAMES {if drawings[frame][i].a>0 {testing.expect_value(t,value,u8(2))}}
		if y==int(CYBER_PRESS_FEET)-1 && value>0 {feet+=1}
	}
	testing.expect(t,feet>0 && feet<55)
	testing.expect_value(t,mask[(int(CYBER_PRESS_FEET)-1)*CYBER_PRESS_WIDTH+CYBER_PRESS_WIDTH/2],u8(0))
	when #config(WEST_SAWMILL_PREVIEW,false) {
		w:=CYBER_PRESS_WIDTH*CYBER_PRESS_FRAMES
		pixels:=make([]rl.Color,w*CYBER_WORKSHOP_ATLAS_HEIGHT);defer delete(pixels)
		for &pixel in pixels {pixel={216,218,199,255}}
		for frame in 0..<CYBER_PRESS_FRAMES {for value,i in mask {
			if value==0 {continue}
			color:=EXPEDITION_PAPER_INK if value==1 else EXPEDITION_PAPER_EDGE
			if value==2 && drawings[frame][i].a>0 {color=drawings[frame][i]}
			pixels[(i/CYBER_PRESS_WIDTH)*w+frame*CYBER_PRESS_WIDTH+i%CYBER_PRESS_WIDTH]=color
		}}
		for role in 0..<3 {
			art:=west_workshop_secondary_art(role);drawing:=cartoon_raster(&art);cut:=fixture_art_mask(&drawing,&drawing)
			for value,i in cut {
				if value==0 {continue}
				color:=EXPEDITION_PAPER_INK if value==1 else EXPEDITION_PAPER_EDGE
				if value==2 && drawing[i].a>0 {color=drawing[i]}
				pixels[(CYBER_PRESS_HEIGHT+i/FIXTURE_CELL)*w+role*FIXTURE_CELL+i%FIXTURE_CELL]=color
			}
		}
		img:=rl.Image{data=raw_data(pixels),width=i32(w),height=CYBER_WORKSHOP_ATLAS_HEIGHT,mipmaps=1,format=.UNCOMPRESSED_R8G8B8A8}
		testing.expect(t,rl.ExportImage(img,"build/west-scene/sawmill-source.png"))
	}
}

@(test)
test_west_workshop_stock_uses_only_unoccupied_cyber_atlas_regions :: proc(t:^testing.T) {
	cyber:=[4]rl.Rectangle{{0,0,CYBER_PRESS_WIDTH,CYBER_PRESS_HEIGHT},
		{0,CYBER_PRESS_HEIGHT,FIXTURE_CELL,FIXTURE_CELL},{FIXTURE_CELL,CYBER_PRESS_HEIGHT,FIXTURE_CELL,FIXTURE_CELL},
		{FIXTURE_CELL*2,CYBER_PRESS_HEIGHT,FIXTURE_CELL,FIXTURE_CELL}}
	west:=[4]rl.Rectangle{{CYBER_PRESS_WIDTH,0,CYBER_PRESS_WIDTH,CYBER_PRESS_HEIGHT},
		west_secondary_paper_source(0),west_secondary_paper_source(1),west_secondary_paper_source(2)}
	for a,i in west {
		testing.expect(t,a.x>=0 && a.y>=0 && a.x+a.width<=CYBER_PRESS_WIDTH*CYBER_PRESS_FRAMES && a.y+a.height<=CYBER_WORKSHOP_ATLAS_HEIGHT)
		for b in cyber {testing.expect(t,!rl.CheckCollisionRecs(a,b),"West may not overwrite any Cyber paper pixels")}
		for j in 0..<i {testing.expect(t,!rl.CheckCollisionRecs(a,west[j]))}
	}
}

@(test)
test_west_secondary_stock_is_distinct_grounded_and_bounded :: proc(t:^testing.T) {
	prior:[FIXTURE_CELL*FIXTURE_CELL]rl.Color
	for role in 0..<3 {
		art:=west_workshop_secondary_art(role);drawing:=cartoon_raster(&art)
		if role>0 {testing.expect(t,!slice.equal(prior[:],drawing[:]))};prior=drawing
		mask:=fixture_art_mask(&drawing,&drawing)
		feet:=0
		for value,i in mask {
			x,y:=i%FIXTURE_CELL,i/FIXTURE_CELL
			if value>0 {testing.expect(t,x>0 && x<FIXTURE_CELL-1 && y>0 && y<int(CARTOON_FEET))}
			if value>0 && y==int(CARTOON_FEET)-1 {feet+=1}
		}
		testing.expect(t,feet>0 && feet<60)
		for &part in art.parts[:art.count] {for p in part.points[:part.count] {testing.expect(t,abs(p.x)<=.5 && p.y>=0)}}
	}
}
