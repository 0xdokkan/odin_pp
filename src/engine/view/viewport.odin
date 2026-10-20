package view

import "core:math"

Vec2 :: [2]f32

Rect :: struct {
	x, y:          f32,
	width, height: f32,
}

Scale_Mode :: enum {
	Fit,
	Integer,
	Stretch,
}

Viewport :: struct {
	destination:      Rect,
	scale_x, scale_y: f32,
}

scale_mode_name :: proc(mode: Scale_Mode) -> string {
	switch mode {
	case .Fit:
		return "Fit"
	case .Integer:
		return "Integer"
	case .Stretch:
		return "Stretch"
	}
	return "Unknown"
}

calculate_viewport :: proc(
	window_width, window_height: int,
	canvas_width, canvas_height: int,
	mode: Scale_Mode,
) -> (result: Viewport, ok: bool) {
	if window_width <= 0 || window_height <= 0 || canvas_width <= 0 || canvas_height <= 0 {
		return {}, false
	}

	window_w := cast(f32)window_width
	window_h := cast(f32)window_height
	canvas_w := cast(f32)canvas_width
	canvas_h := cast(f32)canvas_height

	switch mode {
	case .Fit:
		scale := min(window_w/canvas_w, window_h/canvas_h)
		result.scale_x = scale
		result.scale_y = scale
	case .Integer:
		fit_scale := min(window_w/canvas_w, window_h/canvas_h)
		scale := fit_scale
		if fit_scale >= 1 {
			scale = math.floor(fit_scale)
		}
		result.scale_x = scale
		result.scale_y = scale
	case .Stretch:
		result.scale_x = window_w / canvas_w
		result.scale_y = window_h / canvas_h
	}

	result.destination.width = canvas_w * result.scale_x
	result.destination.height = canvas_h * result.scale_y
	result.destination.x = (window_w-result.destination.width) * 0.5
	result.destination.y = (window_h-result.destination.height) * 0.5
	return result, true
}

contains_window_point :: proc(viewport: ^Viewport, point: Vec2) -> bool {
	if viewport == nil {
		return false
	}
	return point.x >= viewport.destination.x &&
		point.y >= viewport.destination.y &&
		point.x < viewport.destination.x+viewport.destination.width &&
		point.y < viewport.destination.y+viewport.destination.height
}

window_to_canvas :: proc(viewport: ^Viewport, point: Vec2) -> (canvas_point: Vec2, ok: bool) {
	if !contains_window_point(viewport, point) || viewport.scale_x <= 0 || viewport.scale_y <= 0 {
		return {}, false
	}

	return Vec2{
		(point.x-viewport.destination.x) / viewport.scale_x,
		(point.y-viewport.destination.y) / viewport.scale_y,
	}, true
}
