package render

import "core:c"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import canvas "../engine/canvas"

// Axis-aligned UI text, using raylib6's DrawTextEx/DrawTextCodepoint layout.
// Glyph decoding and lookup stay in raylib, including malformed UTF-8 and
// missing-character fallback. Only the final textured quad is clipped here.
// Reference: https://github.com/raysan5/raylib/blob/6.0/src/rtext.c
@(private)
Gothic_Glyph_Quad :: struct {source,destination:rl.Rectangle}
@(private)
Gothic_Glyph_Walk :: struct {
	font:rl.Font,
	text:string,
	position,offset:rl.Vector2,
	size,spacing,scale,line_advance:f32,
	byte_offset:int,
	line_advance_ready:bool,
}

@(private)
gothic_glyph_walk :: proc(font,fallback:rl.Font,text:cstring,position:rl.Vector2,size,spacing:f32)->Gothic_Glyph_Walk {
	selected:=font
	if selected.texture.id==0 {selected=fallback}
	if selected.texture.id==0 || !rl.IsFontValid(selected) || size<=0 {return {}}
	return {font=selected,text=string(text),position={math.round(position.x),math.round(position.y)},
		size=size,spacing=spacing,scale=size/f32(selected.baseSize)}
}

@(private)
gothic_glyph_next :: proc(w:^Gothic_Glyph_Walk)->(quad:Gothic_Glyph_Quad,ok:bool) {
	for w.byte_offset<len(w.text) {
		bytes:c.int
		codepoint:=rl.GetCodepointNext(cast(cstring)raw_data(w.text[w.byte_offset:]),&bytes)
		w.byte_offset+=int(bytes)
		index:=rl.GetGlyphIndex(w.font,codepoint)
		if codepoint=='\n' {
			if !w.line_advance_ready {
				// Raylib exposes a setter but no getter. At fontSize0 a
				// single newline measures precisely the current line gap.
				w.line_advance=w.size+rl.MeasureTextEx(w.font,"\n",0,0).y
				w.line_advance_ready=true
			}
			w.offset.y+=w.line_advance;w.offset.x=0
			continue
		}
		glyph:=w.font.glyphs[index];rec:=w.font.recs[index]
		at:=w.position+w.offset;pad:=f32(w.font.glyphPadding)
		quad.source={rec.x-pad,rec.y-pad,rec.width+2*pad,rec.height+2*pad}
		quad.destination={at.x+f32(glyph.offsetX)*w.scale-pad*w.scale,
			at.y+f32(glyph.offsetY)*w.scale-pad*w.scale,
			(rec.width+2*pad)*w.scale,(rec.height+2*pad)*w.scale}
		advance:=f32(glyph.advanceX) if glyph.advanceX!=0 else rec.width
		w.offset.x+=advance*w.scale+w.spacing
		if codepoint==' ' || codepoint=='\t' {continue}
		return quad,true
	}
	return
}

// Preserve the original scissor's whole-pixel coverage at fractional DPI.
// Convert the actual clamped framebuffer rectangle back to logical units;
// clipping directly against the requested bounds would shave edge pixels.
@(private)
gothic_text_clip_bounds :: proc(bounds:rl.Rectangle,pixels:[2]int,scale:[2]f32)->rl.Rectangle {
	p:=canvas.scissor_pixels(bounds.x,bounds.y,bounds.width,bounds.height,pixels,scale)
	if p.width==0 || p.height==0 {return {}}
	x0,y0:=f32(p.x)/scale.x,f32(pixels.y-p.y-p.height)/scale.y
	x1,y1:=f32(p.x+p.width)/scale.x,f32(pixels.y-p.y)/scale.y
	return {x0,y0,x1-x0,y1-y0}
}

@(private)
gothic_clip_glyph :: proc(quad:Gothic_Glyph_Quad,clip:rl.Rectangle)->(clipped:Gothic_Glyph_Quad,visible:bool) {
	d:=quad.destination
	if d.width<=0 || d.height<=0 || clip.width<=0 || clip.height<=0 {return}
	x0,y0:=max(d.x,clip.x),max(d.y,clip.y)
	x1,y1:=min(d.x+d.width,clip.x+clip.width),min(d.y+d.height,clip.y+clip.height)
	if x1<=x0 || y1<=y0 {return}
	// Most letters are wholly inside: retain their original values exactly.
	if x0==d.x && y0==d.y && x1==d.x+d.width && y1==d.y+d.height {return quad,true}
	s:=quad.source
	u0,v0:=(x0-d.x)/d.width,(y0-d.y)/d.height
	u1,v1:=(x1-d.x)/d.width,(y1-d.y)/d.height
	return {{s.x+u0*s.width,s.y+v0*s.height,(u1-u0)*s.width,(v1-v0)*s.height},
		{x0,y0,x1-x0,y1-y0}},true
}

@(private)
draw_gothic_text_clipped :: proc(font:rl.Font,text:cstring,bounds:rl.Rectangle,size,spacing:f32,color:rl.Color) {
	default_font:=rl.GetFontDefault()
	// The emergency bitmap font uses fractional texel ties at some sizes.
	// Keep its original scissor rasterization; the loaded Gothic atlases
	// use the batching path validated against their quantized coverage.
	if font.texture.id==0 || font.texture.id==default_font.texture.id {
		draw_gothic_text_scissored(font,text,bounds,size,spacing,color)
		return
	}
	w:=gothic_glyph_walk(font,{},text,{bounds.x,bounds.y},size,spacing)
	clip:=gothic_text_clip_bounds(bounds,{int(rlgl.GetFramebufferWidth()),int(rlgl.GetFramebufferHeight())},canvas.scale())
	if clip.width<=0 || clip.height<=0 {return}
	for {
		quad,more:=gothic_glyph_next(&w);if !more {break}
		q,visible:=gothic_clip_glyph(quad,clip);if !visible {continue}
		rl.DrawTexturePro(w.font.texture,q.source,q.destination,{},0,color)
	}
}

// Original path retained for controlled native A/B measurement.
@(private)
draw_gothic_text_scissored :: proc(font:rl.Font,text:cstring,bounds:rl.Rectangle,size,spacing:f32,color:rl.Color) {
	canvas.begin_scissor(bounds.x,bounds.y,bounds.width,bounds.height)
	rl.DrawTextEx(font,text,{math.round(bounds.x),math.round(bounds.y)},size,spacing,color)
	rl.EndScissorMode()
}
