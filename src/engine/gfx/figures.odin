package gfx

import "core:c"
import "core:math"
import rl "vendor:raylib"

// The same cutouts as the tactical game. Border and illustration are separate
// textures, so a held paper pose can surround a moving pixel illustration.
Paper_Figures :: struct {
	texture, border: rl.Texture2D,
	sources: [16]rl.Rectangle,
}

PAPER_FIGURE_CELL :: 160
PAPER_FIGURE_HEIGHT :: 140
PAPER_FIGURE_PAD :: 9

paper_figures_create :: proc() -> Paper_Figures {
	bytes := #load("../../../assets/gothic/figures-v2.png")
	image := rl.LoadImageFromMemory(".png", raw_data(bytes), c.int(len(bytes)))
	if image.data == nil { return {} }
	defer rl.UnloadImage(image)
	colors := rl.LoadImageColors(image)
	defer rl.UnloadImageColors(colors)
	sheet := rl.GenImageColor(PAPER_FIGURE_CELL*4, PAPER_FIGURE_CELL*4, rl.BLANK)
	border := rl.GenImageColor(PAPER_FIGURE_CELL*4, PAPER_FIGURE_CELL*4, rl.BLANK)
	defer rl.UnloadImage(sheet)
	defer rl.UnloadImage(border)
	figures: Paper_Figures
	columns := [5]int{0, 320, 640, 940, 1254}
	rows := [5]int{0, 350, 675, 923, 1254}
	for index in 0..<16 {
		left, right := columns[index%4]*int(image.width)/1254, columns[index%4+1]*int(image.width)/1254
		top, bottom := rows[index/4]*int(image.height)/1254, rows[index/4+1]*int(image.height)/1254
		x0, y0, x1, y1 := right, bottom, left, top
		for y in top..<bottom { for x in left..<right {
			if colors[y*int(image.width)+x].a > 32 {
				x0, y0, x1, y1 = min(x0,x), min(y0,y), max(x1,x), max(y1,y)
			}
		} }
		if x1 < x0 || y1 < y0 { continue }
		crop := rl.ImageFromImage(image, {f32(x0),f32(y0),f32(x1-x0+1),f32(y1-y0+1)})
		scale := f32(PAPER_FIGURE_HEIGHT)/f32(max(crop.width,crop.height))
		w,h := max(i32(1),i32(f32(crop.width)*scale)),max(i32(1),i32(f32(crop.height)*scale))
		rl.ImageResizeNN(&crop,w,h)
		pixels := rl.LoadImageColors(crop)
		base_x,base_y := index%4*PAPER_FIGURE_CELL,index/4*PAPER_FIGURE_CELL
		// Nine pixels of padding prevent the thick border crossing atlas cells.
		fw,fh := int(w)+PAPER_FIGURE_PAD*2,int(h)+PAPER_FIGURE_PAD*2
		figures.sources[index] = {f32(base_x),f32(base_y),f32(fw),f32(fh)}
		distance := make([]int, fw*fh, context.temp_allocator)
		for y in 0..<fh { for x in 0..<fw {
			px,py:=x-PAPER_FIGURE_PAD,y-PAPER_FIGURE_PAD
			distance[y*fw+x]=1000
			if px>=0 && py>=0 && px<int(w) && py<int(h) {
				pixel:=pixels[py*int(w)+px]
				pixel.a=255 if pixel.a>80 else 0
				if pixel.a>0 { distance[y*fw+x]=0 }
				rl.ImageDrawPixel(&sheet,i32(base_x+x),i32(base_y+y),pixel)
			}
		} }
		// Linear two-pass chamfer dilation: loading the shared art stays cheap.
		for y in 0..<fh { for x in 0..<fw {
			i:=y*fw+x
			if x>0 { distance[i]=min(distance[i],distance[i-1]+3) }
			if y>0 {
				distance[i]=min(distance[i],distance[i-fw]+3)
				if x>0 { distance[i]=min(distance[i],distance[i-fw-1]+4) }
				if x+1<fw { distance[i]=min(distance[i],distance[i-fw+1]+4) }
			}
		} }
		for y:=fh-1;y>=0;y-=1 { for x:=fw-1;x>=0;x-=1 {
			i:=y*fw+x
			if x+1<fw { distance[i]=min(distance[i],distance[i+1]+3) }
			if y+1<fh {
				distance[i]=min(distance[i],distance[i+fw]+3)
				if x>0 { distance[i]=min(distance[i],distance[i+fw-1]+4) }
				if x+1<fw { distance[i]=min(distance[i],distance[i+fw+1]+4) }
			}
			if distance[i]<=24 {
				ink:=rl.Color{13,20,30,255}
				if distance[i]<=18 { ink={224,218,199,255} }
				rl.ImageDrawPixel(&border,i32(base_x+x),i32(base_y+y),ink)
			}
		} }
		rl.UnloadImageColors(pixels)
		rl.UnloadImage(crop)
	}
	figures.texture=rl.LoadTextureFromImage(sheet)
	figures.border=rl.LoadTextureFromImage(border)
	rl.SetTextureFilter(figures.texture,.POINT)
	rl.SetTextureFilter(figures.border,.POINT)
	return figures
}

paper_figures_destroy :: proc(figures: ^Paper_Figures) {
	if figures.texture.id!=0 { rl.UnloadTexture(figures.texture) }
	if figures.border.id!=0 { rl.UnloadTexture(figures.border) }
	figures^={}
}

paper_figure_source :: proc(figures: ^Paper_Figures,index:int,flip:=false) -> rl.Rectangle {
	source:=figures.sources[clamp(index,0,15)]
	// DrawBillboardPro samples x and x+width directly. Unlike DrawTexturePro,
	// it does not move the origin when width is negative: start at the right
	// edge to mirror this cell rather than reading the preceding atlas cell.
	if flip { source.x += source.width; source.width = -source.width }
	return source
}

paper_figure_size :: proc(figures: ^Paper_Figures,index:int,height:f32) -> Vec2 {
	source:=paper_figure_source(figures,index)
	// Height describes the illustration, not its transparent border gutter.
	// Centering this quad at feet+height/2 keeps the illustrated soles grounded.
	scale:=height/max(source.height-2*PAPER_FIGURE_PAD,1)
	return {source.width*scale,source.height*scale}
}

// Quantized idle motion gives the detached border a held animation pose.
paper_figure_billboard :: proc(figures: ^Paper_Figures,cam:rl.Camera3D,index:int,feet:Vec3,height:f32,
	flip:=false,tint:=rl.WHITE,time:f32=0) {
	if figures.texture.id==0 { return }
	size:=paper_figure_size(figures,index,height)
	source:=paper_figure_source(figures,index,flip)
	center:=feet+Vec3{0,height*0.5,0}
	pose:=math.floor(time*5)/5
	border_center:=center+Vec3{0,math.sin(pose*2)*height*0.006,0}
	rl.DrawBillboardPro(cam,figures.border,source,border_center,{0,1,0},size,size*0.5,0,rl.WHITE)
	rl.DrawBillboardPro(cam,figures.texture,source,center,{0,1,0},size,size*0.5,0,tint)
}
