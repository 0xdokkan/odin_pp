package render

import "core:testing"
import "core:slice"
import rl "vendor:raylib"
import grid "../engine/grid"

@(test)
test_cyber_press_culling_keeps_only_the_head_inside_the_frustum :: proc(t:^testing.T) {
	r:=new(Renderer);defer free(r)
	cell:=grid.Position{x=4,y=6}
	ground:=cell_ground(cell)
	// A narrow horizontal view only includes y=2.68..2.92. The normal
	// cell sphere stops at2.45, while the tall press's head remains visible.
	for perspective in ([2]bool{false,true}) {
		f:=&r.tactical.draw_frustum
		f^={valid=true,perspective=perspective,eye={4.5,ground+2.80,1.5},
			right={1,0,0},up={0,1,0},forward={0,0,1},horizontal=1,vertical=.12,
			horizontal_margin=1.414214,vertical_margin=1.007175}
		if perspective {f.vertical=.024;f.vertical_margin=1.000288}
		bounds:=rl.Rectangle{22,36,60,170}
		testing.expect(t,!tactical_cell_on_screen(r,cell),"default object culling must remain unchanged")
		testing.expect(t,expedition_fixture_hero_on_screen(r,cell,bounds),"visible press head must not disappear with its ground cell")
		f.eye.y+=4
		testing.expect(t,!expedition_fixture_hero_on_screen(r,cell,bounds),"hero still culls once all of its silhouette leaves view")
	}
}

@(test)
test_cyber_press_four_actions_share_grounded_unclipped_cutout :: proc(t:^testing.T) {
	drawings:=new([CYBER_PRESS_FRAMES][CYBER_PRESS_WIDTH*CYBER_PRESS_HEIGHT]rl.Color);defer free(drawings)
	for frame in 0..<CYBER_PRESS_FRAMES {
		art:=cyber_press_art(frame)
		for &part in art.parts[:art.count] {
			positive,negative:=false,false
			for a,i in part.points[:part.count] {
				b,c:=part.points[(i+1)%part.count],part.points[(i+2)%part.count]
				cross:=ink_profile_cross(a,b,c)
				if cross>.000001 {positive=true};if cross< -.000001 {negative=true}
				testing.expect(t,abs(a.x)<.5 && a.y>=0 && a.y<2.8)
			}
			testing.expect(t,!(positive && negative),"pixel raster requires convex print pieces")
		}
		drawings[frame]=cyber_press_raster(&art)
		if frame>0 {testing.expect(t,!slice.equal(drawings[frame-1][:],drawings[frame][:]),"preparation, press and recovery must differ")}
	}
	mask:=cyber_press_mask(drawings)
	feet:=0
	for value,i in mask {
		x,y:=i%CYBER_PRESS_WIDTH,i/CYBER_PRESS_WIDTH
		if y>=int(CYBER_PRESS_FEET) {testing.expect_value(t,value,u8(0));continue}
		if value>0 {testing.expect(t,x>0 && x<CYBER_PRESS_WIDTH-1 && y>0)}
		for frame in 0..<CYBER_PRESS_FRAMES {if drawings[frame][i].a>0 {testing.expect_value(t,value,u8(2))}}
		if y==int(CYBER_PRESS_FEET)-1 && value>0 {feet+=1}
	}
	testing.expect(t,feet>0 && feet<55)
	testing.expect_value(t,mask[(int(CYBER_PRESS_FEET)-1)*CYBER_PRESS_WIDTH+CYBER_PRESS_WIDTH/2],u8(0))
	when #config(CYBER_PRESS_PREVIEW,false) {
		w:=CYBER_PRESS_WIDTH*CYBER_PRESS_FRAMES
		pixels:=make([]rl.Color,w*CYBER_PRESS_HEIGHT);defer delete(pixels)
		for frame in 0..<CYBER_PRESS_FRAMES {for value,i in mask {
			color:=rl.Color{211,221,218,255}
			if value>0 {color=EXPEDITION_PAPER_INK if value==1 else EXPEDITION_PAPER_EDGE}
			if value==2 && drawings[frame][i].a>0 {color=drawings[frame][i]}
			pixels[(i/CYBER_PRESS_WIDTH)*w+frame*CYBER_PRESS_WIDTH+i%CYBER_PRESS_WIDTH]=color
		}}
		img:=rl.Image{data=raw_data(pixels),width=i32(w),height=CYBER_PRESS_HEIGHT,mipmaps=1,format=.UNCOMPRESSED_R8G8B8A8}
		testing.expect(t,rl.ExportImage(img,"build/cyber-scene/press-source.png"))
	}
}

@(test)
test_cyber_press_tall_quad_places_sole_at_ground_for_all_views :: proc(t:^testing.T) {
	for right in ([4]rl.Vector3{{1,0,0},{0,0,1},{-.7071068,0,.7071068},{.7071068,0,-.7071068}}) {
		for ground in ([3]f32{-3,0,2.5}) {
			base:=rl.Vector3{4.5,ground+.008,6.5}
			q:=expedition_fixture_quad(right,base,CYBER_PRESS_WIDTH,CYBER_PRESS_HEIGHT,CYBER_PRESS_FEET)
			a:=q[0]+(q[1]-q[0])*(CYBER_PRESS_FEET/CYBER_PRESS_HEIGHT)
			b:=q[3]+(q[2]-q[3])*(CYBER_PRESS_FEET/CYBER_PRESS_HEIGHT)
			testing.expect(t,rl.Vector3Distance((a+b)*.5,base)<.00001)
			testing.expect(t,abs(a.y-base.y)<.00001 && abs(b.y-base.y)<.00001)
		}
	}
}

@(test)
test_cyber_secondary_stations_are_distinct_and_keep_clear_cell_edges :: proc(t:^testing.T) {
	prior:[FIXTURE_CELL*FIXTURE_CELL]rl.Color
	for role in 0..<3 {
		art:=cyber_workshop_secondary_art(role);print:=cartoon_raster(&art)
		if role>0 {testing.expect(t,!slice.equal(prior[:],print[:]))};prior=print
		mask:=fixture_art_mask(&print,&print)
		for value,i in mask {
			x,y:=i%FIXTURE_CELL,i/FIXTURE_CELL
			if value>0 {testing.expect(t,x>0 && x<FIXTURE_CELL-1 && y>0 && y<int(CARTOON_FEET))}
		}
		for &part in art.parts[:art.count] {for p in part.points[:part.count] {testing.expect(t,abs(p.x)<=.5 && p.y>=0)}}
	}
}
