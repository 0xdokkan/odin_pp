package ui

import "core:c"
import "core:math"
import rl "vendor:raylib"

ROUND_SEGMENTS :: 6

// Executes this frame's commands; call once, after all widgets.
render :: proc(ctx: ^Context) {
	theme := ctx.theme
	sizes := TEXT_PIXELS
	for i in 0..<ctx.command_count {
		cmd := &ctx.commands[i]
		switch cmd.kind {
		case .Fill:
			if cmd.roundness > 0 {
				rl.DrawRectangleRounded(cmd.rect, cmd.roundness, ROUND_SEGMENTS, cmd.color)
			} else {
				rl.DrawRectangleRec(cmd.rect, cmd.color)
			}
		case .Outline:
			if cmd.roundness > 0 {
				rl.DrawRectangleRoundedLinesEx(cmd.rect, cmd.roundness, ROUND_SEGMENTS, cmd.thickness, cmd.color)
			} else {
				rl.DrawRectangleLinesEx(cmd.rect, cmd.thickness, cmd.color)
			}
		case .Text:
			font := theme.fonts[cmd.size] if theme.has_fonts else rl.GetFontDefault()
			ctext := cstring_temp(cmd.text)
			position := rl.Vector2{math.round(cmd.rect.x), math.round(cmd.rect.y)}
			rl.DrawTextEx(font, ctext, position, sizes[cmd.size], theme.spacing, cmd.color)
		case .Scissor_Begin:
			rl.BeginScissorMode(c.int(cmd.rect.x), c.int(cmd.rect.y), c.int(cmd.rect.width), c.int(cmd.rect.height))
		case .Scissor_End:
			rl.EndScissorMode()
		case .Star:
			draw_star({cmd.rect.x + cmd.rect.width*0.5, cmd.rect.y + cmd.rect.height*0.5}, min(cmd.rect.width, cmd.rect.height)*0.5, cmd.color)
		}
	}
	ctx.command_count = 0
}

// Immediate text drawing outside the command buffer, for HUD numbers drawn in
// world passes. Uses the theme font when available.
draw_text :: proc(theme: ^Theme, text: string, position: [2]f32, size := Text_Size.Body, color := rl.WHITE,
	shadow := true) {
	font := theme.fonts[size] if theme != nil && theme.has_fonts else rl.GetFontDefault()
	pixels := text_pixels(size)
	ctext := cstring_temp(text)
	p := rl.Vector2{math.round(position.x), math.round(position.y)}
	if shadow {
		// The shadow fades with the text, so animated labels stay clean.
		rl.DrawTextEx(font, ctext, p + {2, 2}, pixels, 1, rl.Color{0, 0, 0, u8(160 * f32(color.a) / 255)})
	}
	rl.DrawTextEx(font, ctext, p, pixels, 1, color)
}

draw_text_centered :: proc(theme: ^Theme, text: string, center: [2]f32, size := Text_Size.Body, color := rl.WHITE,
	shadow := true) {
	m := measure(theme, text, size)
	draw_text(theme, text, center - m*0.5, size, color, shadow)
}

// Filled five-pointed star, point up.
draw_star :: proc(center: [2]f32, radius: f32, color: rl.Color) {
	points: [10]rl.Vector2
	for i in 0..<10 {
		r := radius if i%2 == 0 else radius*0.45
		a := -math.PI/2 + f32(i)*math.PI/5
		points[i] = {center.x + math.cos(a)*r, center.y + math.sin(a)*r}
	}
	for i in 0..<10 {
		// Counter-clockwise on screen (y down) for raylib's triangle culling.
		rl.DrawTriangle(center, points[(i+1)%10], points[i], color)
	}
}
