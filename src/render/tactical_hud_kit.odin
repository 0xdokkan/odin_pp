package render

import rl "vendor:raylib"
import ui "../engine/ui"
import view "../engine/view"

// One look for every in-run HUD surface: a dark resin plate with a coloured
// spine and small gothic corner brackets, one button with hover and disabled
// states, one chip for statuses and passives, one segmented meter.

HUD_FILL :: rl.Color{9, 14, 22, 236}
HUD_FILL_HOVER :: rl.Color{18, 29, 44, 246}
HUD_EDGE :: rl.Color{38, 52, 70, 255}
HUD_HIGHLIGHT :: rl.Color{78, 98, 124, 120}
HUD_TROUGH :: rl.Color{4, 7, 12, 255}
HUD_AMBER :: rl.Color{218, 169, 90, 255}
HUD_VENOM :: rl.Color{148, 166, 116, 255}
HUD_SHADE :: rl.Color{164, 144, 183, 255}
HUD_EMBER :: rl.Color{226, 122, 74, 255}
HUD_FROST :: rl.Color{142, 186, 214, 255}

@(private)
hud_ink :: proc(renderer:^Renderer)->rl.Color {return EXPEDITION_PAPER_INK if renderer.tactical.expedition else GOTHIC_PAPER}
@(private)
hud_muted :: proc(renderer:^Renderer)->rl.Color {return rl.Color{78,103,112,255} if renderer.tactical.expedition else GOTHIC_MUTED}

Tactical_Hud_Layout :: struct {
	vitals, pulse, commands: rl.Rectangle,
	map_button, refocus, dodge, character: rl.Rectangle,
}

// The three top columns shared with every minigame HUD (ui.hud_columns). The
// right column holds a 2x2 grid of commands; the board starts below the dock.
tactical_hud_layout :: proc(renderer: ^Renderer) -> (result: Tactical_Hud_Layout) {
	columns := ui.hud_columns({0, 0, renderer.canvas_width, renderer.canvas_height})
	result.vitals, result.pulse, result.commands = columns[0], columns[1], columns[2]
	compact:=tactical_hud_height(renderer)<TACTICAL_HUD_HEIGHT
	if compact {
		result.vitals.y,result.pulse.y,result.commands.y=8,8,8
		result.vitals.height,result.pulse.height,result.commands.height=52,52,52
	}
	c := result.commands
	inner := rl.Rectangle{c.x+8, c.y+7, c.width-16, c.height-14}
	w, h := (inner.width-6)*0.5, (inner.height-4)*0.5
	result.map_button = {inner.x, inner.y, w, h}
	result.refocus = {inner.x+w+6, inner.y, w, h}
	result.dodge = {inner.x, inner.y+h+4, w, h}
	result.character = {inner.x+w+6, inner.y+h+4, w, h}
	if compact {
		result.map_button={inner.x,c.y,w,24}
		result.refocus={inner.x+w+6,c.y,w,24}
		result.dodge={inner.x,c.y+28,w,24}
		result.character={inner.x+w+6,c.y+28,w,24}
	}
	if renderer.tactical.expedition && renderer.tactical.snapshot != nil && renderer.tactical.snapshot.phase != .Combat {
		result.character = result.refocus
	}
	return
}

hud_frame :: proc(bounds: rl.Rectangle, accent: rl.Color = GOTHIC_STEEL, paper:bool=false) {
	x, y, w, h := bounds.x, bounds.y, bounds.width, bounds.height
	if paper {
		rl.DrawRectangleRec({x+2,y+2,w,h},{37,48,53,48})
		rl.DrawRectangleRec(bounds,EXPEDITION_PAPER_EDGE)
		rl.DrawRectangleLinesEx(bounds,1,EXPEDITION_PAPER_INK)
		rl.DrawRectangleRec({x+3,y+3,2,h-6},accent)
		rl.DrawRectangleRec({x+5,y+2,w-8,1},{255,250,230,255})
		return
	}
	rl.DrawRectangleRec({x+3, y+4, w, h}, {0, 0, 0, 90})
	rl.DrawRectangleRec(bounds, HUD_FILL)
	rl.DrawRectangleLinesEx(bounds, 1, HUD_EDGE)
	rl.DrawRectangleRec({x+1, y+1, w-2, 1}, HUD_HIGHLIGHT)
	rl.DrawRectangleRec({x+1, y+3, 2, h-6}, accent)
	// Corner brackets, just outside the plate.
	bracket := ui.with_alpha(accent, 0.75)
	for corner in 0..<4 {
		cx := x-2 if corner%2 == 0 else x+w+1
		cy := y-2 if corner < 2 else y+h+1
		dx: f32 = 1 if corner%2 == 0 else -1
		dy: f32 = 1 if corner < 2 else -1
		rl.DrawRectangleRec({min(cx, cx+dx*6), cy, 7, 1}, bracket)
		rl.DrawRectangleRec({cx, min(cy, cy+dy*6), 1, 7}, bracket)
	}
}

@(private)
hud_bar :: proc(bounds: rl.Rectangle, value01: f32, color: rl.Color, segments: int = 0) {
	rl.DrawRectangleRec(bounds, HUD_TROUGH)
	inner := rl.Rectangle{bounds.x+1, bounds.y+1, bounds.width-2, bounds.height-2}
	fill := inner
	fill.width *= clamp(value01, 0, 1)
	if fill.width > 0 && fill.height > 0 {
		rl.DrawRectangleRec(fill, color)
		rl.DrawRectangleRec({fill.x, fill.y, fill.width, 1}, ui.mix_color(color, rl.WHITE, 0.35))
	}
	if segments > 1 {
		for index in 1..<segments {
			sx := inner.x+inner.width*f32(index)/f32(segments)
			rl.DrawRectangleRec({sx, inner.y, 1, inner.height}, {4, 7, 12, 200})
		}
	}
	rl.DrawRectangleLinesEx(bounds, 1, HUD_EDGE)
}

@(private)
hud_hovered :: proc(renderer: ^Renderer, bounds: rl.Rectangle) -> bool {
	v := &renderer.tactical
	return v.pointer_inside && point_in_rectangle(v.pointer, bounds)
}

// A key badge (keyboard) or none (mouse-only action); `detail` adds a second line.
hud_button :: proc(renderer: ^Renderer, bounds: rl.Rectangle, key, label: cstring, enabled: bool = true,
	accent: rl.Color = GOTHIC_BLUE, detail: cstring = nil) {
	hovered := enabled && hud_hovered(renderer, bounds)
	if renderer.tactical.expedition {
		rl.DrawRectangleRec(bounds,{244,229,194,255} if !hovered else rl.Color{219,239,232,255})
		rl.DrawRectangleLinesEx(bounds,1,EXPEDITION_PAPER_INK if enabled else hud_muted(renderer))
		left:=bounds.x+6
		if key!=nil {
			width:=max(f32(20),gothic_text_width(renderer,key,12)+6)
			rl.DrawRectangleRec({left,bounds.y+4,width,bounds.height-8},EXPEDITION_PAPER_INK)
			gothic_text_fit(renderer,key,{left+3,bounds.y+(bounds.height-15)*.5,width-5,16},12,EXPEDITION_PAPER_EDGE)
			left+=width+5
		}
		gothic_text_fit(renderer,label,{left,bounds.y+(bounds.height-17)*.5,bounds.x+bounds.width-left-4,18},12,hud_ink(renderer) if enabled else hud_muted(renderer))
		if detail!=nil {gothic_text_fit(renderer,detail,{left,bounds.y+bounds.height-12,bounds.x+bounds.width-left-4,12},9,hud_muted(renderer))}
		return
	}
	rl.DrawRectangleRec(bounds, HUD_FILL_HOVER if hovered else (HUD_FILL if enabled else rl.Color{10, 14, 20, 220}))
	rl.DrawRectangleLinesEx(bounds, 1, accent if hovered else (HUD_EDGE if enabled else rl.Color{26, 32, 42, 255}))
	rl.DrawRectangleRec({bounds.x+1, bounds.y+1, bounds.width-2, 1}, HUD_HIGHLIGHT)
	if hovered { rl.DrawRectangleRec({bounds.x+1, bounds.y+bounds.height-3, bounds.width-2, 2}, accent) }
	ink := GOTHIC_PAPER if enabled else GOTHIC_MUTED
	left := bounds.x+7
	if key != nil {
		key_width := max(f32(20), gothic_text_width(renderer, key, 12)+8)
		cap_bounds := rl.Rectangle{bounds.x+4, bounds.y+4, key_width, bounds.height-8}
		rl.DrawRectangleRec(cap_bounds, ink if enabled else GOTHIC_STEEL)
		rl.DrawRectangleRec({cap_bounds.x+1, cap_bounds.y+1, cap_bounds.width-2, 1}, rl.WHITE if enabled else GOTHIC_MUTED)
		gothic_text_fit(renderer, key, {cap_bounds.x+4, cap_bounds.y+(cap_bounds.height-15)*0.5, cap_bounds.width-6, 16}, 12, GOTHIC_INK)
		left = cap_bounds.x+cap_bounds.width+7
	}
	width := bounds.x+bounds.width-left-6
	if detail != nil {
		gothic_text_fit(renderer, label, {left, bounds.y+1, width, 14}, 12, ink)
		gothic_text_fit(renderer, detail, {left, bounds.y+14, width, 12}, 10, accent if enabled else GOTHIC_MUTED)
		return
	}
	if key == nil {
		text_width := min(width, gothic_text_width(renderer, label, 14))
		left = bounds.x+(bounds.width-text_width)*0.5
	}
	gothic_text_fit(renderer, label, {left, bounds.y+(bounds.height-17)*0.5, width, 18}, 14, ink)
}

@(private)
hud_chip :: proc(renderer: ^Renderer, bounds: rl.Rectangle, text: cstring, accent: rl.Color) {
	paper := renderer.tactical.expedition
	rl.DrawRectangleRec(bounds, rl.Color{244,229,194,255} if paper else rl.Color{14,21,31,232})
	rl.DrawRectangleLinesEx(bounds, 1, EXPEDITION_PAPER_INK if paper else rl.Color{30,41,56,255})
	rl.DrawRectangleRec({bounds.x+1, bounds.y+1, 2, bounds.height-2}, accent)
	gothic_text_fit(renderer, text, {bounds.x+6, bounds.y+(bounds.height-15)*0.5, bounds.width-9, 16}, 12, hud_ink(renderer) if paper else accent)
}

// Stored every frame by update_tactical_view, for hover states only.
tactical_hud_pointer :: proc(renderer: ^Renderer, pointer: view.Vec2, inside: bool) {
	renderer.tactical.pointer, renderer.tactical.pointer_inside = pointer, inside
}
