package ui

import "core:strings"
import rl "vendor:raylib"
import input "../input"

Nav :: enum {
	Up,
	Down,
	Left,
	Right,
	Confirm,
	Back,
	Next,
}

Align :: enum u8 {
	Left,
	Center,
	Right,
}

Pointer :: struct {
	position: [2]f32,
	inside:   bool,
	pressed:  bool,
	down:     bool,
	released: bool,
}

Command_Kind :: enum u8 {
	Fill,
	Outline,
	Text,
	Scissor_Begin,
	Scissor_End,
	Star,
}

Draw_Command :: struct {
	kind:      Command_Kind,
	rect:      Rect,
	color:     rl.Color,
	roundness: f32,
	thickness: f32,
	text:      string,
	size:      Text_Size,
}

MAX_COMMANDS :: 2048

Context :: struct {
	theme:          ^Theme,
	pointer:        Pointer,
	press_origin:   [2]f32,
	press_valid:    bool,
	nav_map:        input.Action_Map(Nav),
	nav:            input.State(Nav),
	// Focus is the ordinal of a focusable widget in call order this frame.
	focus:          int,
	focus_count:    int,
	keyboard_mode:  bool,
	horizontal_used: bool,
	last_mouse:     [2]f32,
	commands:       [MAX_COMMANDS]Draw_Command,
	command_count:  int,
	dropped:        int,
	time:           f32,
	// A covered scene may still draw, but must not register or consume input.
	noninteractive: bool,
}

// Heap-allocated: the command buffer is large.
create :: proc(theme: ^Theme) -> ^Context {
	ctx := new(Context)
	ctx.theme = theme
	ctx.focus = -1
	ctx.nav_map = input.make_map(Nav)
	m := &ctx.nav_map
	input.bind_all(m, Nav.Up, input.key(.UP), input.key(.W), input.pad(.LEFT_FACE_UP), input.pad_axis(.LEFT_Y, false))
	input.bind_all(m, Nav.Down, input.key(.DOWN), input.key(.S), input.pad(.LEFT_FACE_DOWN), input.pad_axis(.LEFT_Y, true))
	input.bind_all(m, Nav.Left, input.key(.LEFT), input.key(.A), input.pad(.LEFT_FACE_LEFT), input.pad_axis(.LEFT_X, false))
	input.bind_all(m, Nav.Right, input.key(.RIGHT), input.key(.D), input.pad(.LEFT_FACE_RIGHT), input.pad_axis(.LEFT_X, true))
	input.bind_all(m, Nav.Confirm, input.key(.ENTER), input.key(.SPACE), input.pad(.RIGHT_FACE_DOWN), input.key(.KP_ENTER))
	// Backspace stays free for games (undo, delete); Esc and pad B go back.
	input.bind_all(m, Nav.Back, input.key(.ESCAPE), input.pad(.RIGHT_FACE_RIGHT))
	input.bind_all(m, Nav.Next, input.key(.TAB))
	return ctx
}

destroy :: proc(ctx: ^Context) {
	free(ctx)
}

// Maps the host frame for navigation and the left button; `mouse` is canvas space.
begin_frame :: proc(ctx: ^Context, mouse: [2]f32, inside: bool, dt: f32, devices: ^input.Device_Snapshot) {
	p := Pointer{
		position = mouse,
		inside   = inside,
		pressed  = inside && input.mouse_pressed(devices, .LEFT),
		down     = input.mouse_down(devices, .LEFT),
		released = input.mouse_released(devices, .LEFT),
	}
	begin(ctx, p, input.sample(&ctx.nav_map, devices), dt)
}

// Pure entry point used by tests and by begin_frame.
begin :: proc(ctx: ^Context, pointer: Pointer, nav: input.Sample(Nav), dt: f32) {
	ctx.pointer = pointer
	if pointer.pressed {
		ctx.press_origin = pointer.position
		ctx.press_valid = pointer.inside
	}
	input.advance(&ctx.nav, nav, dt)
	ctx.time += dt
	if pointer.position != ctx.last_mouse && pointer.inside {
		ctx.keyboard_mode = false
	}
	ctx.last_mouse = pointer.position
	if ctx.nav.pressed & {.Up, .Down, .Left, .Right, .Next} != {} {
		ctx.keyboard_mode = true
	}
	ctx.command_count = 0
	ctx.dropped = 0
	ctx.focus_count = 0
	ctx.horizontal_used = false
}

// Applies keyboard navigation collected during the frame.
end :: proc(ctx: ^Context) {
	if ctx.pointer.released || !ctx.pointer.down {
		ctx.press_valid = false
	}
	if ctx.noninteractive {
		return
	}
	if ctx.focus_count == 0 {
		ctx.focus = -1
		return
	}
	if ctx.focus >= ctx.focus_count {
		ctx.focus = ctx.focus_count - 1
	}
	step := 0
	if .Up in ctx.nav.pressed {
		step -= 1
	}
	if .Down in ctx.nav.pressed || .Next in ctx.nav.pressed {
		step += 1
	}
	if !ctx.horizontal_used {
		if .Left in ctx.nav.pressed {
			step -= 1
		}
		if .Right in ctx.nav.pressed {
			step += 1
		}
	}
	if step != 0 {
		if ctx.focus < 0 {
			ctx.focus = 0 if step > 0 else ctx.focus_count - 1
		} else {
			ctx.focus = (ctx.focus + step + ctx.focus_count) % ctx.focus_count
		}
	}
}

back_pressed :: proc(ctx: ^Context) -> bool {
	return !ctx.noninteractive && .Back in ctx.nav.pressed
}

confirm_pressed :: proc(ctx: ^Context) -> bool {
	return !ctx.noninteractive && .Confirm in ctx.nav.pressed
}

// Does not mutate sampled input or navigation focus. The host can draw a
// covered scene, then restore interactivity for the scene that owns input.
set_interactive :: proc(ctx: ^Context, enabled: bool) -> bool {
	previous := !ctx.noninteractive
	ctx.noninteractive = !enabled
	return previous
}

// A release belongs to the scene where its press began. Retain nav.down so a
// held confirmation key does not become a fresh press in the replacement scene.
cancel_interaction :: proc(ctx: ^Context) {
	ctx.press_valid = false
	ctx.focus = -1
	ctx.keyboard_mode = false
	ctx.nav.pressed = {}
	ctx.nav.released = {}
	ctx.nav.held_time = {}
	ctx.pointer.pressed = false
	ctx.pointer.down = false
	ctx.pointer.released = false
}

// Moves keyboard focus to a widget ordinal, e.g. the first menu entry.
set_focus :: proc(ctx: ^Context, ordinal: int) {
	if ctx.noninteractive {
		return
	}
	ctx.focus = ordinal
	ctx.keyboard_mode = true
}

@(private)
push :: proc(ctx: ^Context, cmd: Draw_Command) {
	if ctx.command_count >= MAX_COMMANDS {
		ctx.dropped += 1
		return
	}
	ctx.commands[ctx.command_count] = cmd
	ctx.command_count += 1
}

fill :: proc(ctx: ^Context, r: Rect, color: rl.Color, roundness: f32 = 0) {
	push(ctx, Draw_Command{kind = .Fill, rect = r, color = color, roundness = roundness})
}

outline :: proc(ctx: ^Context, r: Rect, color: rl.Color, thickness: f32 = 2, roundness: f32 = 0) {
	push(ctx, Draw_Command{kind = .Outline, rect = r, color = color, thickness = thickness, roundness = roundness})
}

clip_begin :: proc(ctx: ^Context, r: Rect) {
	push(ctx, Draw_Command{kind = .Scissor_Begin, rect = r})
}

clip_end :: proc(ctx: ^Context) {
	push(ctx, Draw_Command{kind = .Scissor_End})
}

// Draws `text` at a point (top-left of the line).
text_at :: proc(ctx: ^Context, position: [2]f32, text: string, size := Text_Size.Body, color: Maybe(rl.Color) = nil) {
	c := color.? or_else ctx.theme.palette.text
	m := measure(ctx.theme, text, size)
	push(ctx, Draw_Command{kind = .Text, rect = {position.x, position.y, m.x, m.y}, color = c, text = text, size = size})
}

// Single line, vertically centred in r and aligned horizontally.
label :: proc(ctx: ^Context, r: Rect, text: string, size := Text_Size.Body, color: Maybe(rl.Color) = nil,
	align := Align.Left) {
	m := measure(ctx.theme, text, size)
	x := r.x
	switch align {
	case .Left:
	case .Center:
		x = r.x + (r.width-m.x)*0.5
	case .Right:
		x = r.x + r.width - m.x
	}
	text_at(ctx, {x, r.y + (r.height-m.y)*0.5}, text, size, color)
}

// Word-wrapped text; returns the height used. Words are measured once each.
paragraph :: proc(ctx: ^Context, r: Rect, text: string, size := Text_Size.Body, color: Maybe(rl.Color) = nil,
	line_gap: f32 = 4) -> f32 {
	// Words are measured alone, so add the glyph spacing lost at both joins.
	space := measure(ctx.theme, " ", size).x + 2*ctx.theme.spacing
	line_height := text_pixels(size) + line_gap
	y := r.y
	remaining := text
	for raw_line in strings.split_lines_iterator(&remaining) {
		line_start := -1
		line_end := 0
		width := f32(0)
		rest := raw_line
		offset := 0
		for len(rest) > 0 {
			// Next word boundaries inside raw_line.
			i := 0
			for i < len(rest) && rest[i] == ' ' {
				i += 1
			}
			j := i
			for j < len(rest) && rest[j] != ' ' {
				j += 1
			}
			if i == j {
				break
			}
			word := rest[i:j]
			w := measure(ctx.theme, word, size).x
			if line_start >= 0 && width+space+w > r.width {
				text_at(ctx, {r.x, y}, raw_line[line_start:line_end], size, color)
				y += line_height
				line_start = -1
				width = 0
			}
			if line_start < 0 {
				line_start = offset + i
				width = w
			} else {
				width += space + w
			}
			line_end = offset + j
			offset += j
			rest = rest[j:]
		}
		if line_start >= 0 {
			text_at(ctx, {r.x, y}, raw_line[line_start:line_end], size, color)
		}
		y += line_height
	}
	return y - r.y
}

panel :: proc(ctx: ^Context, r: Rect, title := "", alt := false) -> Rect {
	p := ctx.theme.palette
	fill(ctx, Rect{r.x + 2, r.y + 3, r.width, r.height}, p.shadow, ctx.theme.roundness*0.5)
	fill(ctx, r, p.panel_alt if alt else p.panel, ctx.theme.roundness*0.5)
	outline(ctx, r, p.border, ctx.theme.border, ctx.theme.roundness*0.5)
	fill(ctx, Rect{r.x + 1, r.y + 1, max(r.width - 2, 0), 1}, with_alpha(p.focus, 0.24))
	inner := shrink(r, ctx.theme.padding)
	if title != "" {
		header := cut_top(&inner, text_pixels(.Large) + 6)
		label(ctx, header, title, .Large, p.text)
		fill(ctx, Rect{inner.x, inner.y, inner.width, 1}, p.border)
		inner.y += 8
		inner.height -= 8
	}
	return inner
}

Widget_State :: struct {
	ordinal:  int,
	hovered:  bool,
	focused:  bool,
	held:     bool,
	clicked:  bool,
}

// Registers a widget and resolves mouse and keyboard activation. Widgets that
// are not focusable (e.g. over a game that owns the keyboard) answer the mouse only.
interact :: proc(ctx: ^Context, r: Rect, enabled := true, focusable := true) -> Widget_State {
	s := Widget_State{ordinal = -1}
	if ctx.noninteractive {
		return s
	}
	if focusable {
		s.ordinal = ctx.focus_count
		ctx.focus_count += 1
	}
	if !enabled {
		return s
	}
	p := ctx.pointer
	s.hovered = p.inside && contains(r, p.position)
	if focusable && s.hovered && !ctx.keyboard_mode {
		ctx.focus = s.ordinal
	}
	s.focused = focusable && ctx.focus == s.ordinal
	s.held = s.hovered && p.down && ctx.press_valid && contains(r, ctx.press_origin)
	mouse_click := s.hovered && p.released && ctx.press_valid && contains(r, ctx.press_origin)
	key_click := s.focused && ctx.keyboard_mode && .Confirm in ctx.nav.pressed
	s.clicked = mouse_click || key_click
	return s
}

button :: proc(ctx: ^Context, r: Rect, text: string, enabled := true, primary := false,
	size := Text_Size.Body, focusable := true) -> bool {
	s := interact(ctx, r, enabled, focusable)
	p := ctx.theme.palette
	base := p.accent if primary else p.button
	color := base
	if !enabled {
		color = p.disabled
	} else if s.held {
		color = p.button_down
	} else if s.hovered || s.focused {
		color = mix_color(base, p.button_hover if !primary else p.focus, 0.6)
	}
	round := ctx.theme.roundness
	offset := f32(1) if s.held else 0
	body := Rect{r.x, r.y + offset, r.width, r.height}
	fill(ctx, Rect{r.x, r.y + 3, r.width, r.height}, p.shadow, round)
	fill(ctx, body, color, round)
	edge := p.focus if s.focused && enabled else p.border
	outline(ctx, body, edge, ctx.theme.border, round)
	fill(ctx, Rect{body.x + 1, body.y + 1, max(body.width - 2, 0), 1}, with_alpha(p.text, 0.12))
	text_color := p.accent_text if primary else p.text
	if !enabled {
		text_color = p.text_dim
	}
	label(ctx, body, text, size, text_color, .Center)
	return s.clicked
}

toggle :: proc(ctx: ^Context, r: Rect, text: string, value: ^bool) -> bool {
	s := interact(ctx, r)
	changed := s.clicked
	if s.focused && ctx.keyboard_mode && ctx.nav.pressed & {.Left, .Right} != {} {
		changed = true
		ctx.horizontal_used = true
	}
	if changed {
		value^ = !value^
	}
	p := ctx.theme.palette
	if s.hovered || s.focused {
		fill(ctx, r, with_alpha(p.button_hover, 0.5), ctx.theme.roundness)
	}
	box := Rect{r.x + r.width - r.height + 4, r.y + 4, r.height - 8, r.height - 8}
	fill(ctx, box, p.accent if value^ else p.button)
	outline(ctx, box, p.focus if s.focused else p.border, 1)
	if value^ {
		label(ctx, box, "+", .Body, p.accent_text, .Center)
	}
	label(ctx, Rect{r.x + 8, r.y, r.width - r.height - 8, r.height}, text, .Body, p.text)
	return changed
}

slider :: proc(ctx: ^Context, r: Rect, text: string, value: ^f32, low, high: f32, step: f32 = 0.05) -> bool {
	s := interact(ctx, r)
	old := value^
	track := Rect{r.x + r.width*0.45, r.y + r.height*0.5 - 3, r.width*0.5, 6}
	if s.held || (s.hovered && ctx.pointer.pressed) {
		t := clamp((ctx.pointer.position.x - track.x) / track.width, 0, 1)
		value^ = low + (high-low)*t
	}
	if s.focused && ctx.keyboard_mode {
		span := (high - low) * step
		if .Left in ctx.nav.pressed {
			value^ -= span
			ctx.horizontal_used = true
		}
		if .Right in ctx.nav.pressed {
			value^ += span
			ctx.horizontal_used = true
		}
	}
	value^ = clamp(value^, low, high)
	p := ctx.theme.palette
	if s.hovered || s.focused {
		fill(ctx, r, with_alpha(p.button_hover, 0.5), ctx.theme.roundness)
	}
	label(ctx, Rect{r.x + 8, r.y, r.width*0.4, r.height}, text, .Body, p.text)
	fill(ctx, track, p.button)
	t := (value^ - low) / (high - low) if high > low else 0
	fill(ctx, Rect{track.x, track.y, track.width * t, track.height}, p.accent)
	knob := Rect{track.x + track.width*t - 6, track.y - 6, 12, 18}
	fill(ctx, knob, p.focus if s.focused else p.text)
	return value^ != old
}

progress :: proc(ctx: ^Context, r: Rect, value01: f32, color: Maybe(rl.Color) = nil, back: Maybe(rl.Color) = nil) {
	p := ctx.theme.palette
	fill(ctx, r, back.? or_else p.background)
	inner := shrink(r, 2)
	inner.width *= clamp(value01, 0, 1)
	if inner.width > 0 {
		fill(ctx, inner, color.? or_else p.accent)
	}
	outline(ctx, r, p.border, 1)
}

// Selectable tile with a title, a subtitle and an accent stripe: the building
// block of the minigame launcher and of choice screens.
tile :: proc(ctx: ^Context, r: Rect, title, subtitle: string, accent: rl.Color, selected := false,
	enabled := true) -> bool {
	s := interact(ctx, r, enabled)
	p := ctx.theme.palette
	lift := f32(-1) if (s.hovered || s.focused) && enabled else 0
	body := Rect{r.x, r.y + lift, r.width, r.height}
	fill(ctx, Rect{r.x + 2, r.y + 3, r.width, r.height}, p.shadow, ctx.theme.roundness)
	fill(ctx, body, p.panel_alt if enabled else p.disabled, ctx.theme.roundness)
	stripe := body
	stripe.height = 2
	fill(ctx, stripe, accent if enabled else p.text_dim)
	edge := p.focus if (s.focused || selected) && enabled else p.border
	outline(ctx, body, edge, 1, ctx.theme.roundness)
	inner := shrink(body, 12)
	inner.y += 8
	inner.height -= 8
	head := cut_top(&inner, text_pixels(.Large) + 4)
	label(ctx, head, title, .Large, p.text if enabled else p.text_dim)
	// Long descriptions are cut at the tile's edge rather than spilling out.
	clip_begin(ctx, inner)
	paragraph(ctx, inner, subtitle, .Small, p.text_dim)
	clip_end(ctx)
	return s.clicked
}

// Five-pointed star centred in r (ratings, rewards).
star :: proc(ctx: ^Context, r: Rect, color: rl.Color) {
	push(ctx, Draw_Command{kind = .Star, rect = r, color = color})
}

// Translucent full-canvas veil behind modals.
dim :: proc(ctx: ^Context, canvas: Rect, alpha: f32 = 0.6) {
	fill(ctx, canvas, with_alpha(rl.BLACK, alpha))
}
