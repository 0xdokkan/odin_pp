package canvas

import "core:testing"

@(test)
test_scissor_uses_target_pixels_once_and_flips_y :: proc(t:^testing.T) {
	// Logical960x540 rendered into a2560x1440 Retina canvas.
	clip:=scissor_pixels(18,110,658,365,{2560,1440},{f32(2560)/960,f32(1440)/540})
	testing.expect_value(t,clip,Pixel_Rect{48,173,1755,974})
	// A window overlay is in1280x800 window points, not canvas units.
	clip=scissor_pixels(10,20,100,50,{2560,1600},{2,2})
	testing.expect_value(t,clip,Pixel_Rect{20,1460,200,100})
}

@(test)
test_scissor_rounds_outward_and_clamps_negative_or_offscreen_bounds :: proc(t:^testing.T) {
	testing.expect_value(t,scissor_pixels(.25,.25,10,10,{100,80},{1.5,1.5}),Pixel_Rect{0,64,16,16})
	testing.expect_value(t,scissor_pixels(-5,-3,12,9,{100,80},{2,2}),Pixel_Rect{0,68,14,12})
	testing.expect_value(t,scissor_pixels(80,60,40,40,{100,80},{1,1}),Pixel_Rect{80,0,20,20})
	testing.expect_value(t,scissor_pixels(120,0,10,10,{100,80},{1,1}).width,0)
	testing.expect_value(t,scissor_pixels(10,10,-1,1,{100,80},{1,1}),Pixel_Rect{})
}
