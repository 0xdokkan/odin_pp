package render

import "core:testing"
import "core:slice"
import rl "vendor:raylib"
import gfx "../engine/gfx"

@(test)
test_cartoon_label_bands_keep_head_space_independent_of_wide_lower_arms :: proc(t:^testing.T) {
	bounds:rl.Rectangle;bands:[CARTOON_LABEL_BANDS]rl.Rectangle
	// A narrow head above broad arms. Whole-sheet bounds would push the
	// health label away from the head; empty padded bands reserve nothing.
	for point in ([4][2]int{{40,15},{60,20},{20,50},{80,55}}) {
		x,y:=point[0],point[1]
		cartoon_include_pixel(&bounds,x,y)
		cartoon_include_pixel(&bands[y*CARTOON_LABEL_BANDS/CARTOON_CELL],x,y)
	}
	testing.expect_value(t,bounds,rl.Rectangle{20,15,61,41})
	testing.expect_value(t,bands[1],rl.Rectangle{40,15,21,6})
	testing.expect(t,bands[1].width<bounds.width)
	testing.expect_value(t,bands[0],rl.Rectangle{})
	testing.expect_value(t,bands[7],rl.Rectangle{})
}

@(test)
test_cartoon_paper_is_connected_without_a_floor_plate :: proc(t:^testing.T) {
	for actor in 0..<CARTOON_ACTORS {
		mask:=cartoon_paper_mask(actor)
		again:=cartoon_paper_mask(actor)
		testing.expect(t,slice.equal(mask[:],again[:]))
		queue:[CARTOON_CELL*CARTOON_CELL]int;visited:[CARTOON_CELL*CARTOON_CELL]bool
		count,first,grounded:=0,-1,0
		for value,i in mask {
			if value==0 {continue}
			count+=1;if first<0 {first=i}
			x,y:=i%CARTOON_CELL,i/CARTOON_CELL
			testing.expect(t,x>0 && x<CARTOON_CELL-1 && y>0 && f32(y)<CARTOON_FEET)
			if f32(y)==CARTOON_FEET-1 {grounded+=1}
		}
		testing.expect(t,count>100 && count<CARTOON_CELL*CARTOON_CELL/2)
		if actor!=7 {testing.expect(t,grounded>0 && grounded<CARTOON_CELL*4/5,"feet touch the floor without a full-width plaque")}
		if actor!=7 {testing.expect(t,mask[(int(CARTOON_FEET)-1)*CARTOON_CELL+CARTOON_CELL/2]==0,"the gap between the soles stays open")}
		if first<0 {continue}
		queue[0]=first;visited[first]=true;head,tail:=0,1
		for head<tail {
			i:=queue[head];head+=1;x,y:=i%CARTOON_CELL,i/CARTOON_CELL
			for dy in -1..=1 {for dx in -1..=1 {
				nx,ny:=x+dx,y+dy
				if nx<0 || nx>=CARTOON_CELL || ny<0 || ny>=CARTOON_CELL {continue}
				n:=ny*CARTOON_CELL+nx
				if mask[n]==0 || visited[n] {continue}
				visited[n]=true;queue[tail]=n;tail+=1
			}}
		}
		testing.expect(t,tail==count,"one continuous sheet, no detached backing fragments")
	}
}

@(test)
test_cartoon_drawings_have_bounded_palette_and_all_roles_animate :: proc(t:^testing.T) {
	for actor in 0..<CARTOON_ACTORS {
		idle_art:=cartoon_art(actor,.2,.Idle,0);idle:=cartoon_raster(&idle_art)
		moving_art:=cartoon_art(actor,.5,.Move_Side,.16);moving:=cartoon_raster(&moving_art)
		testing.expect(t,!slice.equal(idle[:],moving[:]))
		for action in gfx.Living_Action {for frame in 0..<CARTOON_FRAMES {
			progress:=f32(frame)/f32(CARTOON_FRAMES-1)
			art:=cartoon_art(actor,progress*2.4,action,progress)
			expect_expedition_art_safe(t,&art)
			pixels:=cartoon_raster(&art);count:=0
			for color in pixels {
				if color.a==0 {continue};count+=1
				found:=color==EXPEDITION_PAPER_INK
				for part in art.parts[:art.count] {found=found || part.color==color}
				testing.expect(t,found && color.a==255,"rasterization must not invent antialiasing colours")
			}
			testing.expect(t,count>100)
		}}
	}
}

@(test)
test_cartoon_picking_uses_the_visible_paper_mask_and_not_the_quad :: proc(t:^testing.T) {
	r:=new(Renderer);defer free(r)
	m:=new(Expedition_Material);defer free(m)
	assets:=new(Expedition_Cartoon_Assets);defer free(assets)
	r.tactical.expedition=true;r.tactical.expedition_material=m;m.cartoon=assets
	q:=Tactical_Billboard{key=.Player,cartoon=true,card_points={{0,2,0},{0,0,0},{2,0,0},{2,2,0}}}
	assets.mask[0]=cartoon_paper_mask(0)
	for mask,i in assets.mask[0] {
		uv:=rl.Vector2{(f32(i%CARTOON_CELL)+.5)/CARTOON_CELL,(f32(i/CARTOON_CELL)+.5)/CARTOON_CELL}
		ray:=rl.Ray{position={uv.x*2,(1-uv.y)*2,3},direction={0,0,-1}}
		distance,hit:=expedition_cartoon_hit(r,q,ray)
		testing.expect_value(t,hit,mask>0)
		if hit {testing.expect(t,abs(distance-3)<.00001)}
	}
}
