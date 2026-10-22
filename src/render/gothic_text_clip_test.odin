package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"

@(private)
Gothic_Clip_Test_Font :: struct {glyphs:[7]rl.GlyphInfo,recs:[7]rl.Rectangle}
@(private)
gothic_clip_test_font :: proc(f:^Gothic_Clip_Test_Font)->rl.Font {
	// Unordered charset, fallback deliberately not at index0, a nonzero
	// padding, negative overhang, Unicode and two zero-advance glyphs.
	f.glyphs={{value='A',offsetX=-1,offsetY=1,advanceX=8},
		{value='?',offsetX=1,offsetY=2,advanceX=7},
		{value='é',offsetX=1,offsetY=0,advanceX=9},
		{value='中',offsetX=0,offsetY=2,advanceX=0},
		{value=' ',advanceX=4},{value='\t',advanceX=0},
		{value='B',offsetX=2,advanceX=0}}
	f.recs={{10,10,6,9},{0,0,5,8},{20,10,7,10},{32,10,10,11},{0,20,3,2},{4,20,6,2},{48,10,5,8}}
	return {baseSize=10,glyphPadding=2,glyphCount=7,texture={id=1,width=64,height=32},
		recs=raw_data(f.recs[:]),glyphs=raw_data(f.glyphs[:])}
}

@(private)
gothic_clip_expect_rect :: proc(t:^testing.T,actual,expected:rl.Rectangle) {
	for difference in ([4]f32{actual.x-expected.x,actual.y-expected.y,actual.width-expected.width,actual.height-expected.height}) {
		testing.expect(t,abs(difference)<.00002)
	}
}

@(test)
test_gothic_clipped_text_layout_preserves_unicode_padding_advances_and_lines :: proc(t:^testing.T) {
	f:Gothic_Clip_Test_Font;font:=gothic_clip_test_font(&f)
	w:=gothic_glyph_walk(font,{},"A é中\tΩB\nA",{10.49,20.5},15,.5)
	line_step:=rl.MeasureTextEx(font,"\n",15,0).y-15
	expected:=[6]rl.Rectangle{{5.5,19.5,15,19.5},{27.5,18,16.5,21},{40,21,21,22.5},
		{66.5,21,13.5,18},{79,18,13.5,18},{5.5,19.5+line_step,15,19.5}}
	for dest,i in expected {
		q,ok:=gothic_glyph_next(&w);testing.expect(t,ok)
		gothic_clip_expect_rect(t,q.destination,dest)
		if i==0 || i==5 {testing.expect_value(t,q.source,(rl.Rectangle{8,8,10,13}))}
		if i==3 {testing.expect_value(t,q.source,(rl.Rectangle{-2,-2,9,12}))}
	}
	_,more:=gothic_glyph_next(&w);testing.expect(t,!more)
	testing.expect_value(t,w.byte_offset,len(w.text))
	testing.expect_value(t,w.line_advance,line_step)
	testing.expect_value(t,w.offset.x,f32(12.5))
}

@(test)
test_gothic_clipped_text_missing_font_glyphs_and_invalid_utf8_match_raylib :: proc(t:^testing.T) {
	f:Gothic_Clip_Test_Font;font:=gothic_clip_test_font(&f)
	w:=gothic_glyph_walk({},font,"A\xc3X\xffé",{-2.5,-3.49},10,0)
	testing.expect_value(t,w.font.texture.id,font.texture.id)
	testing.expect_value(t,w.position,(rl.Vector2{-3,-3}))
	// Invalid UTF-8 consumes one byte in raylib's decoder; missing X also
	// uses '?'. The final valid multibyte character must remain intact.
	expected_sources:=[5]rl.Rectangle{{8,8,10,13},{-2,-2,9,12},{-2,-2,9,12},{-2,-2,9,12},{18,8,11,14}}
	for expected in expected_sources {q,ok:=gothic_glyph_next(&w);testing.expect(t,ok);testing.expect_value(t,q.source,expected)}
	_,more:=gothic_glyph_next(&w);testing.expect(t,!more)
	w=gothic_glyph_walk({}, {},"A",{},10,1)
	_,more=gothic_glyph_next(&w);testing.expect(t,!more)
	w=gothic_glyph_walk(font,{},nil,{},10,1)
	_,more=gothic_glyph_next(&w);testing.expect(t,!more)
	w=gothic_glyph_walk(font,{},"",{},10,1)
	_,more=gothic_glyph_next(&w);testing.expect(t,!more)
}

@(test)
test_gothic_clipped_text_empty_lines_tabs_and_fractional_size :: proc(t:^testing.T) {
	f:Gothic_Clip_Test_Font;font:=gothic_clip_test_font(&f)
	for size in ([4]f32{10,13.75,18,32}) {for spacing in ([3]f32{0,.375,1}) {
		w:=gothic_glyph_walk(font,{},"\n A\n\n\tB",{3.6,5.2},size,spacing)
		step:=rl.MeasureTextEx(font,"\n",size,0).y-size;scale:=size/10
		first,ok:=gothic_glyph_next(&w);testing.expect(t,ok)
		gothic_clip_expect_rect(t,first.destination,{4+scale+spacing,5+step-scale,10*scale,13*scale})
		second,ok2:=gothic_glyph_next(&w);testing.expect(t,ok2)
		gothic_clip_expect_rect(t,second.destination,{4+6*scale+spacing,5+3*step-2*scale,9*scale,12*scale})
		_,more:=gothic_glyph_next(&w);testing.expect(t,!more)
	}}
}

@(test)
test_gothic_glyph_quad_clips_both_axes_and_keeps_uv_mapping :: proc(t:^testing.T) {
	quad:=Gothic_Glyph_Quad{{10,20,12,18},{-4,6,24,36}}
	q,ok:=gothic_clip_glyph(quad,{2,12,10,18});testing.expect(t,ok)
	gothic_clip_expect_rect(t,q.destination,{2,12,10,18})
	gothic_clip_expect_rect(t,q.source,{13,23,5,9})
	whole,visible:=gothic_clip_glyph(quad,{-100,-100,300,300})
	testing.expect(t,visible);testing.expect_value(t,whole,quad)
	for clip in ([5]rl.Rectangle{{20,6,1,36},{-5,6,1,36},{-4,42,24,1},{-4,5,24,1},{-4,6,0,36}}) {
		_,visible=gothic_clip_glyph(quad,clip);testing.expect(t,!visible)
	}
	// A cropped vertex must sample the same atlas coordinate as its point
	// on the original glyph. Check interiors as well as the four corners.
	for scale in ([4]f32{.625,1,1.375,2.6666667}) {
		original:=Gothic_Glyph_Quad{{7.25,11.5,13,19},{-2.75,4.125,13*scale,19*scale}}
		for inset in ([3]f32{.125,.75,1.25}) {
			clip:=original.destination;clip.x+=inset;clip.y+=inset;clip.width-=inset*2;clip.height-=inset*2
			cropped,show:=gothic_clip_glyph(original,clip);testing.expect(t,show)
			for uv in ([5]rl.Vector2{{},{1,0},{0,1},{1,1},{.37,.61}}) {
				at:=rl.Vector2{cropped.destination.x+uv.x*cropped.destination.width,cropped.destination.y+uv.y*cropped.destination.height}
				reference:=rl.Vector2{original.source.x+(at.x-original.destination.x)/original.destination.width*original.source.width,
					original.source.y+(at.y-original.destination.y)/original.destination.height*original.source.height}
				actual:=rl.Vector2{cropped.source.x+uv.x*cropped.source.width,cropped.source.y+uv.y*cropped.source.height}
				testing.expect(t,rl.Vector2Distance(reference,actual)<.00001)
			}
		}
	}
}

@(test)
test_gothic_text_cpu_clip_preserves_outward_physical_pixel_coverage :: proc(t:^testing.T) {
	clip:=gothic_text_clip_bounds({10.2,20.2,13.1,4.1},{2560,1440},{8.0/3,8.0/3})
	gothic_clip_expect_rect(t,clip,{10.125,19.875,13.5,4.5})
	for scale in ([4][2]f32{{1,1},{2,2},{2.6666667,2.6666667},{1.375,1.125}}) {
		bounds:=rl.Rectangle{-1.2,2.35,7.3,5.25}
		q:=gothic_text_clip_bounds(bounds,{200,120},scale)
		gothic_clip_expect_rect(t,q,{0,f32(math.floor(f64(bounds.y)*f64(scale.y))/f64(scale.y)),
			f32(math.ceil((f64(bounds.x)+f64(bounds.width))*f64(scale.x))/f64(scale.x)),
			f32((math.ceil((f64(bounds.y)+f64(bounds.height))*f64(scale.y))-math.floor(f64(bounds.y)*f64(scale.y)))/f64(scale.y))})
	}
	testing.expect_value(t,gothic_text_clip_bounds({98.5,48.5,20,20},{200,100},{2,2}),(rl.Rectangle{98.5,48.5,1.5,1.5}))
	for bounds in ([5]rl.Rectangle{{1,1,0,4},{1,1,4,-1},{201,0,1,1},{0,121,1,1},{-4,-4,2,2}}) {
		testing.expect_value(t,gothic_text_clip_bounds(bounds,{200,120},{1,1}),rl.Rectangle{})
	}
	testing.expect_value(t,gothic_text_clip_bounds({1,1,4,4},{200,120},{0,1}),rl.Rectangle{})
	testing.expect_value(t,gothic_text_clip_bounds({1,1,4,4},{0,0},{1,1}),rl.Rectangle{})
}
