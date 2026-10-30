package app

import "core:testing"
import view "../view"
import input "../input"

@(test)
test_native_canvas_uses_framebuffer_pixels_but_mouse_remains_logical :: proc(t:^testing.T) {
	viewport,valid:=view.calculate_viewport(1280,800,960,540,.Fit)
	testing.expect(t,valid)
	for factor in 1..=2 {
		size,ok:=canvas_pixel_size(viewport,{1280,800},{1280*factor,800*factor},{960,540})
		testing.expect(t,ok)
		testing.expect_value(t,size,[2]int{1280*factor,720*factor})
		window:=Window{viewport=viewport,screen_size={1280,800},framebuffer_size={1280*factor,800*factor}}
		devices:=input.Device_Snapshot{mouse_position={640,400}}
		point,inside:=mouse_canvas_position(&window,&devices)
		testing.expect(t,inside)
		testing.expect_value(t,point,view.Vec2{480,270})
		devices.mouse_position={640,20}
		_,inside=mouse_canvas_position(&window,&devices)
		testing.expect(t,!inside)
	}
}

@(test)
test_canvas_resizes_for_monitor_dpi_and_integer_mode_without_changing_layout :: proc(t:^testing.T) {
	viewport,_:=view.calculate_viewport(1600,1000,960,540,.Integer)
	one,_:=canvas_pixel_size(viewport,{1600,1000},{1600,1000},{960,540})
	two,_:=canvas_pixel_size(viewport,{1600,1000},{3200,2000},{960,540})
	testing.expect_value(t,one,[2]int{960,540})
	testing.expect_value(t,two,[2]int{1920,1080})
	testing.expect_value(t,viewport.destination,view.Rect{320,230,960,540})
	_,minimized:=canvas_pixel_size(viewport,{1600,1000},{0,0},{960,540})
	testing.expect(t,!minimized)
}

@(test)
test_fixed_canvas_ignores_window_and_display_scaling :: proc(t:^testing.T) {
	viewport,_:=view.calculate_viewport(1100,760,960,540,.Fit)
	for factor in 1..=2 {
		size,ok:=canvas_target_size({1920,1080},viewport,{1100,760},{1100*factor,760*factor},{960,540})
		testing.expect(t,ok)
		testing.expect_value(t,size,[2]int{1920,1080})
	}
	// Without a fixed size the canvas follows the display, as before.
	native,ok:=canvas_target_size({},viewport,{1100,760},{2200,1520},{960,540})
	expected,_:=canvas_pixel_size(viewport,{1100,760},{2200,1520},{960,540})
	testing.expect(t,ok)
	testing.expect_value(t,native,expected)
}

@(test)
test_stretch_canvas_preserves_3d_projection_aspect_and_native_coverage :: proc(t:^testing.T) {
	viewport,_:=view.calculate_viewport(1200,800,960,540,.Stretch)
	size,valid:=canvas_pixel_size(viewport,{1200,800},{2400,1600},{960,540})
	testing.expect(t,valid)
	// The final viewport stretches both 2D and 3D together. Rendering directly
	// at2400x1600 would silently change BeginMode3D's camera to3:2.
	testing.expect_value(t,size,[2]int{2844,1600})
	testing.expect(t,size.x>=2400 && size.y>=1600)
	point,inside:=view.window_to_canvas(&viewport,{900,600})
	testing.expect(t,inside)
	testing.expect_value(t,point,view.Vec2{720,405})
}
