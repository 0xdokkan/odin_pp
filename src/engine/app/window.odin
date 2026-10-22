package app

import "core:c"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import canvas_target "../canvas"
import view "../view"
import input "../input"

Window_Config :: struct {
	title:                                      cstring,
	initial_width, initial_height:              int,
	canvas_width, canvas_height:                int,
	minimum_window_width, minimum_window_height: int,
	target_fps:                                 int,
	initial_scale_mode:                          view.Scale_Mode,
	pixel_art: bool,
}

Window :: struct {
	config:       Window_Config,
	// Laid out in the config's logical canvas units, rasterized at the
	// display's own pixels: one canvas pixel per physical pixel on screen.
	canvas:       rl.RenderTexture2D,
	viewport:     view.Viewport,
	// Sampled outside render passes: GetRenderWidth/Height otherwise report
	// the currently bound offscreen target rather than the window framebuffer.
	screen_size, framebuffer_size: [2]int,
	requested_canvas_size: [2]int,
	canvas_degraded: bool,
	// rlgl retains this pointer, so it must not point into the Window returned
	// by value from open(). The buffers outlive every offscreen render pass.
	render_batch: ^rlgl.RenderBatch,
	scale_mode:   view.Scale_Mode,
	is_open:      bool,
}

open :: proc(config: Window_Config) -> (result: Window, ok: bool) {
	if config.initial_width <= 0 || config.initial_height <= 0 ||
	   config.canvas_width <= 0 || config.canvas_height <= 0 {
		return {}, false
	}

	rl.SetConfigFlags({.WINDOW_RESIZABLE, .WINDOW_HIGHDPI, .VSYNC_HINT, .MSAA_4X_HINT})
	rl.InitWindow(c.int(config.initial_width), c.int(config.initial_height), config.title)
	if !rl.IsWindowReady() {
		return {}, false
	}
	rl.SetExitKey(.KEY_NULL)

	result.config = config
	result.scale_mode = config.initial_scale_mode
	result.is_open = true
	rl.SetWindowMinSize(c.int(config.minimum_window_width), c.int(config.minimum_window_height))
	rl.SetTargetFPS(c.int(config.target_fps))

	set_scale_mode(&result, config.initial_scale_mode)
	if !rl.IsRenderTextureValid(result.canvas) {
		rl.CloseWindow()
		return {}, false
	}
	result.render_batch=load_window_render_batch()
	return result, true
}

@(private)
WINDOW_RENDER_BATCH_BUFFERS :: #config(WINDOW_RENDER_BATCH_BUFFERS,8)
#assert(WINDOW_RENDER_BATCH_BUFFERS>=0 && WINDOW_RENDER_BATCH_BUFFERS<=32)

@(private)
load_window_render_batch :: proc()->^rlgl.RenderBatch {
	when WINDOW_RENDER_BATCH_BUFFERS==0 {return nil}
	// Mirror raylib 6.0's rlglInit: the default shader optimizes normals out,
	// but each batch VAO must still bind attribute 2 for later lit shaders.
	// https://github.com/raysan5/raylib/blob/6.0/src/rlgl.h
	locations:=rlgl.GetShaderLocsDefault()
	if locations==nil {return nil}
	normal_index:=int(rl.ShaderLocationIndex.VERTEX_NORMAL)
	saved_normal:=locations[normal_index]
	locations[normal_index]=2
	batch:=rlgl.LoadRenderBatch(WINDOW_RENDER_BATCH_BUFFERS,8192)
	locations[normal_index]=saved_normal
	// The outer RenderBatch ABI is unchanged in raylib 6.0. Never dereference
	// its vertexBuffer through Odin's older rlVertexBuffer binding: native 6.0
	// owns a normals array and five VBOs, which only native unload may access.
	if batch.vertexBuffer==nil || batch.draws==nil {return nil}
	owned:=new(rlgl.RenderBatch);owned^=batch
	rlgl.SetRenderBatchActive(owned)
	return owned
}

// Display content scale is a UI preference, not a framebuffer measurement.
// This ratio also works when a platform ignores the high-DPI request or the
// window moves between monitors without changing its logical dimensions.
canvas_pixel_size :: proc(viewport:view.Viewport,screen,framebuffer,logical:[2]int)->(size:[2]int,ok:bool) {
	if screen.x<=0 || screen.y<=0 || framebuffer.x<=0 || framebuffer.y<=0 ||
	   logical.x<=0 || logical.y<=0 || viewport.destination.width<=0 || viewport.destination.height<=0 {return}
	width:=f64(viewport.destination.width)*f64(framebuffer.x)/f64(screen.x)
	height:=f64(viewport.destination.height)*f64(framebuffer.y)/f64(screen.y)
	if math.is_nan(width) || math.is_nan(height) || math.is_inf(width) || math.is_inf(height) {return}
	// BeginMode3D derives its aspect from this target. Keep the logical aspect
	// so a Stretch viewport stretches the final image, rather than changing
	// the camera independently of logical mouse picking. Both axes retain at
	// least native coverage; only the less stretched axis is supersampled.
	scale:=max(width/f64(logical.x),height/f64(logical.y))
	return {max(1,int(math.round(f64(logical.x)*scale))),max(1,int(math.round(f64(logical.y)*scale)))},true
}

@(private)
load_canvas :: proc(size:[2]int)->(target:rl.RenderTexture2D,ok:bool) {
	target=rl.LoadRenderTexture(c.int(size.x),c.int(size.y))
	if !rl.IsRenderTextureValid(target) || !rlgl.FramebufferComplete(target.id) {
		if target.id!=0 {rl.UnloadRenderTexture(target)}
		return {},false
	}
	rl.SetTextureWrap(target.texture,.CLAMP)
	return target,true
}

// Allocate before releasing the old canvas: a failed resize must not destroy
// the last usable frame. A failed native allocation is retried on size change,
// instead of allocating and logging the same failure every rendered frame.
@(private)
ensure_canvas :: proc(window: ^Window) {
	size,valid:=canvas_pixel_size(window.viewport,window.screen_size,window.framebuffer_size,{window.config.canvas_width,window.config.canvas_height})
	if !valid {return}
	if window.canvas.id!=0 && window.requested_canvas_size==size {return}
	window.requested_canvas_size=size
	if window.canvas.id!=0 && int(window.canvas.texture.width)==size.x && int(window.canvas.texture.height)==size.y {
		window.canvas_degraded=false;return
	}
	next,ok:=load_canvas(size)
	window.canvas_degraded=!ok
	if !ok {
		rl.TraceLog(.WARNING,"CANVAS: Native allocation failed; retaining the last canvas or using logical resolution")
		if window.canvas.id!=0 {return}
		fallback:=[2]int{window.config.canvas_width,window.config.canvas_height}
		if fallback==size {return}
		next,ok=load_canvas(fallback)
		if !ok {return}
	}
	if window.canvas.id != 0 { rl.UnloadRenderTexture(window.canvas) }
	window.canvas = next
	apply_canvas_filter(window)
}

@(private)
apply_canvas_filter :: proc(window: ^Window) {
	filter := rl.TextureFilter.BILINEAR
	if window.scale_mode == .Integer || window.config.pixel_art {
		filter = .POINT
	}
	if window.canvas.id != 0 { rl.SetTextureFilter(window.canvas.texture, filter) }
}

close :: proc(window: ^Window) {
	if window == nil || !window.is_open {
		return
	}
	rl.UnloadRenderTexture(window.canvas)
	if window.render_batch!=nil {
		rlgl.SetRenderBatchActive(nil)
		rlgl.UnloadRenderBatch(window.render_batch^)
		free(window.render_batch)
	}
	rl.CloseWindow()
	window^ = {}
}

should_close :: proc(window: ^Window) -> bool {
	return window == nil || !window.is_open || rl.WindowShouldClose()
}

set_scale_mode :: proc(window: ^Window, mode: view.Scale_Mode) {
	assert(window != nil)
	window.scale_mode = mode
	apply_canvas_filter(window)
	refresh_viewport(window)
}

refresh_viewport :: proc(window: ^Window) {
	assert(window != nil)
	screen:=[2]int{int(rl.GetScreenWidth()),int(rl.GetScreenHeight())}
	framebuffer:=[2]int{int(rl.GetRenderWidth()),int(rl.GetRenderHeight())}
	// Minimized or transitioning windows can temporarily have no drawable
	// area. Keep the previous coherent viewport and texture until restoration.
	if screen.x<=0 || screen.y<=0 || framebuffer.x<=0 || framebuffer.y<=0 {return}
	viewport, ok := view.calculate_viewport(
		screen.x,
		screen.y,
		window.config.canvas_width,
		window.config.canvas_height,
		window.scale_mode,
	)
	if !ok {return}
	window.viewport = viewport
	window.screen_size=screen;window.framebuffer_size=framebuffer
	ensure_canvas(window)
}

update_window_controls :: proc(window: ^Window, devices: ^input.Device_Snapshot) {
	assert(window != nil)

	if input.key_pressed(devices, .F1) {
		set_scale_mode(window, .Fit)
	} else if input.key_pressed(devices, .F2) {
		set_scale_mode(window, .Integer)
	} else if input.key_pressed(devices, .F3) {
		set_scale_mode(window, .Stretch)
	}

	if input.key_pressed(devices, .F11) {
		rl.ToggleBorderlessWindowed()
	}

	refresh_viewport(window)
}

mouse_canvas_position :: proc(window: ^Window, devices: ^input.Device_Snapshot) -> (view.Vec2, bool) {
	assert(window != nil)
	mouse := devices.mouse_position if devices != nil else [2]f32{}
	return view.window_to_canvas(&window.viewport, {mouse.x, mouse.y})
}

mouse_canvas_delta :: proc(window: ^Window, devices: ^input.Device_Snapshot) -> view.Vec2 {
	assert(window != nil)
	delta := input.mouse_delta(devices)
	if window.viewport.scale_x<=0 || window.viewport.scale_y<=0 {return {}}
	return view.Vec2{delta.x / window.viewport.scale_x, delta.y / window.viewport.scale_y}
}

begin_canvas :: proc(window: ^Window, clear_color: rl.Color) {
	assert(window != nil && window.is_open)
	canvas_target.begin(window.canvas, f32(window.config.canvas_width), f32(window.config.canvas_height))
	rl.ClearBackground(clear_color)
}

// Bind the canvas again after an offscreen pass drawn inside the canvas pass.
resume_canvas :: proc(window: ^Window) {
	assert(window != nil && window.is_open)
	canvas_target.begin(window.canvas, f32(window.config.canvas_width), f32(window.config.canvas_height))
}

// Window overlays are composed after the canvas, so they may cross letterbox
// margins without stretching with the game's viewport.
Window_Overlay :: proc(window: ^Window, data: rawptr)

present :: proc(window: ^Window, letterbox_color: rl.Color,
	overlay: Window_Overlay = nil, overlay_data: rawptr = nil) {
	assert(window != nil && window.is_open)
	rl.EndTextureMode()

	rl.BeginDrawing()
	canvas_target.use_window_coordinates(window.screen_size,window.framebuffer_size)
	rl.ClearBackground(letterbox_color)

	source := rl.Rectangle{
		x = 0,
		y = 0,
		width = cast(f32)window.canvas.texture.width,
		height = -cast(f32)window.canvas.texture.height,
	}
	destination := rl.Rectangle{
		x = window.viewport.destination.x,
		y = window.viewport.destination.y,
		width = window.viewport.destination.width,
		height = window.viewport.destination.height,
	}
	rl.DrawTexturePro(window.canvas.texture, source, destination, {}, 0, rl.WHITE)
	if overlay != nil { overlay(window, overlay_data) }
	rl.EndDrawing()
}
