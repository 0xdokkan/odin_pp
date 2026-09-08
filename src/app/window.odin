package app

import "core:c"
import rl "vendor:raylib"
import view "../view"

Window_Config :: struct {
	title:                                      cstring,
	initial_width, initial_height:              int,
	canvas_width, canvas_height:                int,
	minimum_window_width, minimum_window_height: int,
	target_fps:                                 int,
	initial_scale_mode:                          view.Scale_Mode,
}

Window :: struct {
	config:       Window_Config,
	canvas:       rl.RenderTexture2D,
	viewport:     view.Viewport,
	scale_mode:   view.Scale_Mode,
	is_open:      bool,
}

open :: proc(config: Window_Config) -> (result: Window, ok: bool) {
	if config.initial_width <= 0 || config.initial_height <= 0 ||
	   config.canvas_width <= 0 || config.canvas_height <= 0 {
		return {}, false
	}

	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT, .MSAA_4X_HINT})
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

	result.canvas = rl.LoadRenderTexture(c.int(config.canvas_width), c.int(config.canvas_height))
	if !rl.IsRenderTextureValid(result.canvas) {
		rl.CloseWindow()
		return {}, false
	}
	rl.SetTextureWrap(result.canvas.texture, .CLAMP)

	set_scale_mode(&result, config.initial_scale_mode)
	refresh_viewport(&result)
	return result, true
}

close :: proc(window: ^Window) {
	if window == nil || !window.is_open {
		return
	}
	rl.UnloadRenderTexture(window.canvas)
	rl.CloseWindow()
	window^ = {}
}

should_close :: proc(window: ^Window) -> bool {
	return window == nil || !window.is_open || rl.WindowShouldClose()
}

set_scale_mode :: proc(window: ^Window, mode: view.Scale_Mode) {
	assert(window != nil)
	window.scale_mode = mode

	filter := rl.TextureFilter.BILINEAR
	if mode == .Integer {
		filter = .POINT
	}
	rl.SetTextureFilter(window.canvas.texture, filter)
	refresh_viewport(window)
}

refresh_viewport :: proc(window: ^Window) {
	assert(window != nil)
	viewport, ok := view.calculate_viewport(
		int(rl.GetScreenWidth()),
		int(rl.GetScreenHeight()),
		window.config.canvas_width,
		window.config.canvas_height,
		window.scale_mode,
	)
	assert(ok)
	window.viewport = viewport
}

update_window_controls :: proc(window: ^Window) {
	assert(window != nil)

	if rl.IsKeyPressed(.F1) {
		set_scale_mode(window, .Fit)
	} else if rl.IsKeyPressed(.F2) {
		set_scale_mode(window, .Integer)
	} else if rl.IsKeyPressed(.F3) {
		set_scale_mode(window, .Stretch)
	}

	if rl.IsKeyPressed(.F11) {
		rl.ToggleBorderlessWindowed()
	}

	refresh_viewport(window)
}

mouse_canvas_position :: proc(window: ^Window) -> (view.Vec2, bool) {
	assert(window != nil)
	mouse := rl.GetMousePosition()
	return view.window_to_canvas(&window.viewport, {x = mouse.x, y = mouse.y})
}

mouse_canvas_delta :: proc(window: ^Window) -> view.Vec2 {
	assert(window != nil)
	delta := rl.GetMouseDelta()
	return view.Vec2{
		x = delta.x / window.viewport.scale_x,
		y = delta.y / window.viewport.scale_y,
	}
}

begin_canvas :: proc(window: ^Window, clear_color: rl.Color) {
	assert(window != nil && window.is_open)
	rl.BeginTextureMode(window.canvas)
	rl.ClearBackground(clear_color)
}

// Window overlays are composed after the canvas, so they may cross letterbox
// margins without stretching with the game's viewport.
Window_Overlay :: proc(window: ^Window, data: rawptr)

present :: proc(window: ^Window, letterbox_color: rl.Color,
	overlay: Window_Overlay = nil, overlay_data: rawptr = nil) {
	assert(window != nil && window.is_open)
	rl.EndTextureMode()

	rl.BeginDrawing()
	rl.ClearBackground(letterbox_color)

	source := rl.Rectangle{
		x = 0,
		y = 0,
		width = cast(f32)window.config.canvas_width,
		height = -cast(f32)window.config.canvas_height,
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
