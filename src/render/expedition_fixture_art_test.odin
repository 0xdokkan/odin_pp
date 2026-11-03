package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"
import campaign "../campaign"
import world "../expedition"

@(test)
test_fixture_drawings_are_convex_grounded_and_fit_their_atlas_cells :: proc(t:^testing.T) {
	when #config(FIXTURE_ART_PREVIEW,false) {fixture_export_art_preview(t)}
	for biome in campaign.Biome {if biome==.Count {continue};for kind in world.Site_Kind {
		for frame in 0..<FIXTURE_FRAMES {for variant in 0..<(3 if kind==.Workshop else 1) {
			art:=expedition_fixture_art(biome,kind,f32(frame)*.5,variant)
			testing.expect(t,art.count>0 && art.count<EXPEDITION_PAPER_PARTS)
			grounded:=false
			for &part in art.parts[:art.count] {
				positive,negative:=false,false
				for a,i in part.points[:part.count] {
					b,c:=part.points[(i+1)%part.count],part.points[(i+2)%part.count]
					cross:=ink_profile_cross(a,b,c)
					if cross>.000001 {positive=true};if cross< -.000001 {negative=true}
					testing.expect(t,abs(a.x)<=.51 && a.y>=0 && a.y<=1.5)
					if a.y==0 {grounded=true}
				}
				// The actor rasterizer requires convex print pieces. Testing the
				// actual drawings prevents invisible concave gaps in the sprite.
				testing.expect(t,!(positive && negative))
			}
			testing.expect(t,grounded)
		}}
	}}
}

// Explicit developer preview of the source atlas; gameplay evidence still
// comes from the native smoke cameras. No GPU or persistent texture needed.
@(private)
fixture_export_art_preview :: proc(t:^testing.T) {
	w,h:=FIXTURE_CELL*12,FIXTURE_CELL*8
	pixels:=make([]rl.Color,w*h);defer delete(pixels)
	for &color in pixels {color={214,219,215,255}}
	roles:=[6]world.Site_Kind{.Nest,.Cache,.Archive,.Workshop,.Spring,.Memory}
	for b in campaign.Biome {if b==.Count {continue};for row in 0..<8 {
		kind:=roles[row] if row<6 else world.Site_Kind.Workshop
		variant:=0 if row<6 else row-5
		art:=expedition_fixture_art(b,kind,0,variant)
		print:=cartoon_raster(&art);mask:=fixture_art_mask(&print,&print)
		for value,i in mask {
			if value==0 {continue}
			color:=EXPEDITION_PAPER_INK if value==1 else EXPEDITION_PAPER_EDGE
			if print[i].a>0 {color=print[i]}
			pixels[(row*FIXTURE_CELL+i/FIXTURE_CELL)*w+int(b)*FIXTURE_CELL+i%FIXTURE_CELL]=color
		}
	}}
	img:=rl.Image{data=raw_data(pixels),width=i32(w),height=i32(h),mipmaps=1,format=.UNCOMPRESSED_R8G8B8A8}
	testing.expect(t,rl.ExportImage(img,"build/moonshot/fixture-art-source.png"))
}

@(test)
test_fixture_cutout_contains_both_frames_without_paper_below_ground :: proc(t:^testing.T) {
	roles:=[6]world.Site_Kind{.Nest,.Cache,.Archive,.Workshop,.Spring,.Memory}
	for biome in campaign.Biome {if biome==.Count {continue};for kind in roles {
		for variant in 0..<(3 if kind==.Workshop else 1) {
			a:=expedition_fixture_art(biome,kind,0,variant)
			b:=expedition_fixture_art(biome,kind,.5,variant)
			first,second:=cartoon_raster(&a),cartoon_raster(&b)
			mask:=fixture_art_mask(&first,&second)
			opaque,feet:=0,0
			for value,i in mask {
				x,y:=i%FIXTURE_CELL,i/FIXTURE_CELL
				if y>=int(CARTOON_FEET) {testing.expect_value(t,value,u8(0));continue}
				if value>0 {testing.expect(t,x>0 && x<FIXTURE_CELL-1 && y>0,"paper contour must not be clipped by the atlas cell")}
				if first[i].a>0 || second[i].a>0 {testing.expect_value(t,value,u8(2));opaque+=1}
				if y==int(CARTOON_FEET)-1 && value>0 {feet+=1}
			}
			testing.expect(t,opaque>500 && feet>0 && feet<60)
		}
	}}
}

@(test)
test_fixture_atlas_indices_do_not_alias_site_roles_or_workshop_variants :: proc(t:^testing.T) {
	seen:[FIXTURE_COUNT]bool
	for b in campaign.Biome {if b==.Count {continue};for k in world.Site_Kind {
		index:=fixture_art_index(b,k)
		if index<0 {testing.expect(t,k==.Trial || k==.Boss || k==.Tunnel || k==.Cave);continue}
		testing.expect(t,index>=0 && index<FIXTURE_COUNT && !seen[index]);seen[index]=true
	}}
	for b in campaign.Biome {if b==.Count {continue};for bench in ([2]bool{false,true}) {
		index:=fixture_machine_art_index(b,bench)
		testing.expect(t,index>=0 && index<FIXTURE_COUNT && !seen[index]);seen[index]=true
	}}
	for present in seen {testing.expect(t,present)}
	// Atlas cell rows are integral; no source rectangle samples the gutter
	// or depends on a fractional rounding at either frame boundary.
	testing.expect_value(t,math.mod(f32(FIXTURE_COUNT*FIXTURE_FRAMES),f32(FIXTURE_COLUMNS)),f32(0))
}
