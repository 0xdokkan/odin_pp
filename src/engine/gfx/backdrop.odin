package gfx

import "core:math"
import rl "vendor:raylib"

draw_vertical_gradient :: proc(r: rl.Rectangle, top, bottom: rl.Color) {
	rl.DrawRectangleGradientV(i32(r.x), i32(r.y), i32(r.width), i32(r.height), top, bottom)
}

// Rolling silhouette layer for side-scrollers. `scroll` is the camera x times
// the layer's parallax factor; the shape repeats smoothly.
draw_hills :: proc(width, height, baseline, amplitude, scroll: f32, color: rl.Color, seed: f32 = 0) {
	step := f32(8)
	x := f32(0)
	for x < width + step {
		h := hill_height(x+scroll, amplitude, seed)
		h2 := hill_height(x+step+scroll, amplitude, seed)
		top_a := baseline - h
		top_b := baseline - h2
		rl.DrawTriangle({x, top_a}, {x, height}, {x + step, height}, color)
		rl.DrawTriangle({x, top_a}, {x + step, height}, {x + step, top_b}, color)
		x += step
	}
}

@(private)
hill_height :: proc "contextless" (x, amplitude, seed: f32) -> f32 {
	return amplitude * (0.55 + 0.25*math.sin(x*0.011+seed) + 0.15*math.sin(x*0.027+seed*2.1) + 0.05*math.sin(x*0.07+seed*3.7))
}

// Twinkling points on a dark sky; positions are a pure function of index.
draw_stars :: proc(width, height: f32, count: int, time: f32, scroll: f32 = 0) {
	for i in 0..<count {
		h := f32(i) * 12.9898
		sx := math.mod(abs(math.sin(h)*43758.5453)*width - scroll*0.05, width)
		if sx < 0 {
			sx += width
		}
		sy := math.mod(abs(math.sin(h*1.7)*24634.6345)*height, height)
		twinkle := 0.5 + 0.5*math.sin(time*2+h)
		a := u8(80 + 150*twinkle)
		rl.DrawRectangleRec({math.round(sx), math.round(sy), 2, 2}, rl.Color{230, 230, 255, a})
	}
}

// Darkens the canvas edges to focus the eye on the centre.
draw_vignette :: proc(width, height: f32, strength: f32 = 0.5) {
	a := u8(255 * clamp(strength, 0, 1))
	band := min(width, height) * 0.18
	clear := rl.Color{0, 0, 0, 0}
	dark := rl.Color{0, 0, 0, a}
	rl.DrawRectangleGradientV(0, 0, i32(width), i32(band), dark, clear)
	rl.DrawRectangleGradientV(0, i32(height-band), i32(width), i32(band), clear, dark)
	rl.DrawRectangleGradientH(0, 0, i32(band), i32(height), dark, clear)
	rl.DrawRectangleGradientH(i32(width-band), 0, i32(band), i32(height), clear, dark)
}

// Checkerboard floor for 2D top-down arenas.
draw_checker :: proc(r: rl.Rectangle, cell: f32, a, b: rl.Color) {
	cols := int(math.ceil(r.width / cell))
	rows := int(math.ceil(r.height / cell))
	for y in 0..<rows {
		for x in 0..<cols {
			color := a if (x+y)%2 == 0 else b
			rl.DrawRectangleRec({r.x + f32(x)*cell, r.y + f32(y)*cell, cell, cell}, color)
		}
	}
}

// Ring that grows and fades, for pickups and shockwaves.
draw_shockwave :: proc(center: Vec2, progress, max_radius: f32, color: rl.Color) {
	t := clamp(progress, 0, 1)
	radius := max_radius * t
	c := color
	c.a = u8(f32(color.a) * (1 - t))
	rl.DrawRing(center, max(radius-3, 0), radius, 0, 360, 32, c)
}

// Layered translucent discs approximating a glow.
draw_glow :: proc(center: Vec2, radius: f32, color: rl.Color) {
	for i in 0..<4 {
		k := 1 - f32(i)*0.22
		c := color
		c.a = u8(f32(color.a) * 0.18)
		rl.DrawCircleV(center, radius*k, c)
	}
}
