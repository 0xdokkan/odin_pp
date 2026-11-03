package render

import "core:c"
import "core:math"
import "core:fmt"
import rl "vendor:raylib"
import campaign "../campaign"

WORKSHOP_STOCK_SIDE :: 1024
#assert(int(campaign.Biome.Cyber)==0 && int(campaign.Biome.West)==1)

@(private)
workshop_ground_smooth :: proc(lo,hi,value:f32)->f32 {
	t:=clamp((value-lo)/(hi-lo),0,1)
	return t*t*(3-2*t)
}

// Each biome's immutable painting is sampled once, not once per fragment.
// Coordinates address texel centres; border pigment matches the outside.
@(private)
workshop_ground_pixels :: proc(biome:campaign.Biome,side:int=WORKSHOP_STOCK_SIDE)->[]rl.Color {
	if side<=0 {return nil}
	pixels:=make([]rl.Color,side*side)
	aa:=f32(25)/f32(side)
	for y in 0..<side {for x in 0..<side {
		q:=rl.Vector2{(f32(x)+.5)/f32(side)*25-12.5,(f32(y)+.5)/f32(side)*23-11.5}
		pigment:rl.Vector3
		if biome==.West {pigment=west_workshop_ground_sample(q,aa)}
		else {pigment=cyber_workshop_ground_sample(q,aa)}
		pixels[y*side+x]={u8(math.round(clamp(pigment.x,0,1)*255)),u8(math.round(clamp(pigment.y,0,1)*255)),u8(math.round(clamp(pigment.z,0,1)*255)),255}
	}}
	return pixels
}

@(private)
ensure_workshop_stock :: proc(f:^Expedition_Floor,biome:campaign.Biome,allow_fallback:bool=false)->rl.Texture2D {
	if biome!=.Cyber && biome!=.West {return {}}
	i:=int(biome)
	if f.workshop_stock[i].id!=0 || f.workshop_failed[i] {return f.workshop_stock[i]}
	started:=rl.GetTime()
	encoded:=WORKSHOP_STOCK_CYBER_PNG if biome==.Cyber else WORKSHOP_STOCK_WEST_PNG
	img:=rl.LoadImageFromMemory(".png",raw_data(encoded),c.int(len(encoded)))
	fallback:[]rl.Color
	if img.data==nil || img.width!=WORKSHOP_STOCK_SIDE || img.height!=WORKSHOP_STOCK_SIDE {
		if img.data!=nil {rl.UnloadImage(img)}
		img={}
		if !allow_fallback {
			rl.TraceLog(.WARNING,"Workshop stock unavailable; procedural fallback is restricted to expedition loading")
			f.workshop_failed[i]=true;return {}
		}
		rl.TraceLog(.WARNING,"Workshop stock invalid; rebuilding the source painting during expedition loading")
		fallback=workshop_ground_pixels(biome)
		img={data=raw_data(fallback),width=WORKSHOP_STOCK_SIDE,height=WORKSHOP_STOCK_SIDE,mipmaps=1,format=.UNCOMPRESSED_R8G8B8A8}
	}
	defer {if fallback!=nil {delete(fallback)} else {rl.UnloadImage(img)}}
	baked:=rl.GetTime()
	f.workshop_stock[i]=rl.LoadTextureFromImage(img)
	if f.workshop_stock[i].id==0 {f.workshop_failed[i]=true;return {}}
	rl.GenTextureMipmaps(&f.workshop_stock[i])
	rl.SetTextureFilter(f.workshop_stock[i],.TRILINEAR)
	rl.SetTextureWrap(f.workshop_stock[i],.CLAMP)
	if #config(EXPEDITION_BENCHMARK,false) {fmt.printfln("EXPEDITION STOCK biome=%v decode_or_fallback_ms=%.3f upload_mips_ms=%.3f procedural_fallback=%v",biome,(baked-started)*1000,(rl.GetTime()-baked)*1000,fallback!=nil)}
	return f.workshop_stock[i]
}

// Load both immutable paintings while entering the expedition, before its first
// draw. The floor owns at most two textures, including mipmaps; draw-time calls
// only reuse them. A broken embedded image may fall back here, never mid-walk.
prepare_expedition_workshop_stock :: proc(renderer:^Renderer) {
	if renderer==nil || !expedition_floor_ready(renderer) {return}
	for biome in ([2]campaign.Biome{.Cyber,.West}) {
		_=ensure_workshop_stock(renderer.tactical.expedition_floor,biome,true)
	}
}
