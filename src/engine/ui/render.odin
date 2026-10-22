package ui

import "core:math"
import rl "vendor:raylib"
import canvas_target "../canvas"

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
			canvas_target.begin_scissor(cmd.rect.x, cmd.rect.y, cmd.rect.width, cmd.rect.height)
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
	spacing := theme.spacing if theme != nil else 1
	if shadow {
		// The shadow fades with the text, so animated labels stay clean.
		rl.DrawTextEx(font, ctext, p + {2, 2}, pixels, spacing, rl.Color{0, 0, 0, u8(160 * f32(color.a) / 255)})
	}
	rl.DrawTextEx(font, ctext, p, pixels, spacing, color)
}

draw_text_centered :: proc(theme: ^Theme, text: string, center: [2]f32, size := Text_Size.Body, color := rl.WHITE,
	shadow := true) {
	m := measure(theme, text, size)
	draw_text(theme, text, center - m*0.5, size, color, shadow)
}

// Shrink through the existing font atlas before shortening text. Both the
// measured and drawn line use identical glyph spacing and pixel snapping.
draw_text_fit :: proc(theme: ^Theme, text: string, bounds: Rect, size := Text_Size.Body,
	color := rl.WHITE, align := Align.Left) {
	if bounds.width <= 0 || bounds.height <= 0 {
		return
	}
	chosen := size
	for chosen > .Small && (measure(theme, text, chosen).x > bounds.width || text_pixels(chosen) > bounds.height) {
		chosen = Text_Size(int(chosen)-1)
	}
	line := ellipsize(theme, text, bounds.width, chosen)
	m := measure(theme, line, chosen)
	x := bounds.x
	switch align {
	case .Left:
	case .Center:
		x += (bounds.width-m.x)*0.5
	case .Right:
		x += bounds.width-m.x
	}
	draw_text(theme, line, {x, bounds.y + (bounds.height-m.y)*0.5}, chosen, color)
}

// Immediate equivalents of the menu panel/meter for HUDs rendered in a world
// pass. Nil themes use the shared palette, without loading another font atlas.
hud_panel :: proc(theme: ^Theme, bounds: Rect, accent: Maybe(rl.Color) = nil) {
	p := theme.palette if theme != nil else GOTHIC_PALETTE
	rl.DrawRectangleRec({bounds.x+2, bounds.y+3, bounds.width, bounds.height}, p.shadow)
	rl.DrawRectangleRec(bounds, p.panel)
	rl.DrawRectangleLinesEx(bounds, 1, p.border)
	line := accent.? or_else p.focus
	rl.DrawRectangleRec({bounds.x+1, bounds.y+1, max(bounds.width-2, 0), 1}, with_alpha(line, 0.4))
}

hud_meter :: proc(theme: ^Theme, bounds: Rect, value01: f32, color: Maybe(rl.Color) = nil) {
	p := theme.palette if theme != nil else GOTHIC_PALETTE
	rl.DrawRectangleRec(bounds, p.background)
	inner := shrink(bounds, 1) if bounds.height >= 5 else bounds
	inner.width *= clamp(value01, 0, 1)
	if inner.width > 0 && inner.height > 0 {
		fill_color := color.? or_else p.accent
		rl.DrawRectangleRec(inner, fill_color)
		rl.DrawRectangleRec({inner.x, inner.y, inner.width, 1}, mix_color(fill_color, p.text, 0.3))
	}
	if bounds.height >= 5 {
		rl.DrawRectangleLinesEx(bounds, 1, p.border)
	}
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
