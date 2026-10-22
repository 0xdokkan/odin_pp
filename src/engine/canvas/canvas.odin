package canvas

import "core:c"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// The game lays out in logical units (the 960×540 canvas) while its render
// targets may hold many more pixels, up to the display's own. The scale lives
// in the projection, not the modelview: BeginMode3D pushes and EndMode3D pops
// the projection, and Mode2D only touches the modelview, so every 2D and 3D
// pass keeps drawing in logical units at the target's full resolution.
@(private)
active: [2]f32 = {1, 1}
@(private)
active_pixels: [2]int

Pixel_Rect :: struct {x,y,width,height:int}

// Convert top-left logical bounds to bottom-left framebuffer pixels. Round
// outward, then intersect the target: fractional DPI must not shave a row
// from text, and a negative/offscreen clip must not become a GL overflow.
scissor_pixels :: proc(x,y,width,height:f32,pixels:[2]int,unit_scale:[2]f32)->Pixel_Rect {
	if pixels.x<=0 || pixels.y<=0 || width<=0 || height<=0 || unit_scale.x<=0 || unit_scale.y<=0 {return {}}
	for value in ([6]f32{x,y,width,height,unit_scale.x,unit_scale.y}) {
		if math.is_nan(value) || math.is_inf(value) {return {}}
	}
	x0:=int(clamp(math.floor(f64(x)*f64(unit_scale.x)),0,f64(pixels.x)))
	y0:=int(clamp(math.floor(f64(y)*f64(unit_scale.y)),0,f64(pixels.y)))
	x1:=int(clamp(math.ceil((f64(x)+f64(width))*f64(unit_scale.x)),0,f64(pixels.x)))
	y1:=int(clamp(math.ceil((f64(y)+f64(height))*f64(unit_scale.y)),0,f64(pixels.y)))
	return {x0,pixels.y-y1,max(0,x1-x0),max(0,y1-y0)}
}

begin :: proc(target: rl.RenderTexture2D, logical_width, logical_height: f32) {
	rl.BeginTextureMode(target)
	use_logical_projection(target, logical_width, logical_height)
}

// For a target that is already bound.
use_logical_projection :: proc(target: rl.RenderTexture2D, logical_width, logical_height: f32) {
	if logical_width <= 0 || logical_height <= 0 || target.texture.width <= 0 || target.texture.height <= 0 { return }
	rlgl.MatrixMode(rlgl.PROJECTION)
	rlgl.LoadIdentity()
	rlgl.Ortho(0, f64(logical_width), f64(logical_height), 0, 0, 1)
	rlgl.MatrixMode(rlgl.MODELVIEW)
	rlgl.LoadIdentity()
	active = {f32(target.texture.width)/logical_width, f32(target.texture.height)/logical_height}
	active_pixels={int(target.texture.width),int(target.texture.height)}
}

// Render targets are not a stack in raylib. Restore the complete window
// viewport and projection after the final offscreen pass, rather than relying
// on cached DPI/projection state from EndTextureMode or BeginDrawing.
use_window_coordinates :: proc(screen,pixels:[2]int) {
	if screen.x<=0 || screen.y<=0 || pixels.x<=0 || pixels.y<=0 {active={1,1};active_pixels={};return}
	rlgl.DrawRenderBatchActive()
	rlgl.Viewport(0,0,c.int(pixels.x),c.int(pixels.y))
	rlgl.SetFramebufferWidth(c.int(pixels.x));rlgl.SetFramebufferHeight(c.int(pixels.y))
	rlgl.MatrixMode(rlgl.PROJECTION)
	rlgl.LoadIdentity()
	rlgl.Ortho(0,f64(screen.x),f64(screen.y),0,0,1)
	rlgl.MatrixMode(rlgl.MODELVIEW)
	rlgl.LoadIdentity()
	active={f32(pixels.x)/f32(screen.x),f32(pixels.y)/f32(screen.y)}
	active_pixels=pixels
}

// Target pixels per logical unit, for the target being drawn.
scale :: proc() -> [2]f32 { return active }

// Use GL framebuffer pixels directly. Raylib's window helper applies its own
// platform DPI scale; using it after conversion would double-scale overlays.
// EndScissorMode remains compatible (it flushes and disables the same GL test).
begin_scissor :: proc(x, y, width, height: f32) {
	clip:=scissor_pixels(x,y,width,height,active_pixels,active)
	rlgl.DrawRenderBatchActive()
	rlgl.EnableScissorTest()
	rlgl.Scissor(c.int(clip.x),c.int(clip.y),c.int(clip.width),c.int(clip.height))
}
