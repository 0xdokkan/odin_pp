package ui

import "core:testing"
import input "../input"

@(private = "file")
nav :: proc(actions: bit_set[Nav]) -> input.Sample(Nav) {
	s := input.Sample(Nav){down = actions}
	for a in actions {
		s.value[a] = 1
	}
	return s
}

@(test)
test_rect_cut_layout :: proc(t: ^testing.T) {
	r := Rect{0, 0, 100, 50}
	top := cut_top(&r, 10)
	left := cut_left(&r, 30)
	testing.expect_value(t, top, Rect{0, 0, 100, 10})
	testing.expect_value(t, left, Rect{0, 10, 30, 40})
	testing.expect_value(t, r, Rect{30, 10, 70, 40})
	testing.expect_value(t, column(Rect{0, 0, 100, 10}, 4, 3, 4), Rect{78, 0, 22, 10})
	testing.expect_value(t, centered_item(Rect{0, 0, 100, 10}, 2, 1, 20, 10), Rect{55, 0, 20, 10})
	testing.expect_value(t, cell(Rect{0, 0, 20, 20}, 2, 2, 3), Rect{10, 10, 10, 10})
}

@(test)
test_button_click_requires_enabled_press_and_release_inside :: proc(t: ^testing.T) {
	theme := default_theme()
	r := Rect{10, 10, 100, 30}
	for enabled in ([2]bool{true, false}) {
		ctx := create(&theme)
		defer destroy(ctx)
		begin(ctx, Pointer{position = {20, 20}, inside = true, pressed = true, down = true}, {}, 0.016)
		testing.expect(t, !button(ctx, r, "Ok", enabled = enabled))
		end(ctx)
		begin(ctx, Pointer{position = {25, 20}, inside = true, released = true}, {}, 0.016)
		testing.expect_value(t, button(ctx, r, "Ok", enabled = enabled), enabled)
		end(ctx)
		// A press outside followed by release inside never belongs to this button.
		begin(ctx, Pointer{position = {300, 300}, inside = true, pressed = true, down = true}, {}, 0.016)
		button(ctx, r, "Ok", enabled = enabled)
		end(ctx)
		begin(ctx, Pointer{position = {25, 20}, inside = true, released = true}, {}, 0.016)
		testing.expect(t, !button(ctx, r, "Ok", enabled = enabled))
		end(ctx)
	}
}

@(test)
test_keyboard_focus_cycles_and_confirms :: proc(t: ^testing.T) {
	theme := default_theme()
	ctx := create(&theme)
	defer destroy(ctx)
	rects := [3]Rect{{0, 0, 10, 10}, {0, 20, 10, 10}, {0, 40, 10, 10}}
	frame :: proc(ctx: ^Context, rects: [3]Rect, actions: bit_set[Nav]) -> int {
		begin(ctx, Pointer{}, nav(actions), 0.016)
		clicked := -1
		for r, i in rects {
			if button(ctx, r, "x") {
				clicked = i
			}
		}
		end(ctx)
		return clicked
	}
	frame(ctx, rects, {.Down})
	testing.expect_value(t, ctx.focus, 0)
	frame(ctx, rects, {})
	frame(ctx, rects, {.Up})
	testing.expect_value(t, ctx.focus, 2) // wraps around
	frame(ctx, rects, {})
	testing.expect_value(t, frame(ctx, rects, {.Confirm}), 2)
}

@(test)
test_slider_steps_with_keyboard_and_clamps :: proc(t: ^testing.T) {
	theme := default_theme()
	ctx := create(&theme)
	defer destroy(ctx)
	value := f32(0.5)
	r := Rect{0, 0, 200, 30}
	set_focus(ctx, 0)
	begin(ctx, Pointer{}, nav({.Right}), 0)
	testing.expect(t, slider(ctx, r, "Vol", &value, 0, 1, 0.25))
	end(ctx)
	testing.expect_value(t, value, f32(0.75))
	testing.expect_value(t, ctx.focus, 0) // Right was consumed, focus stays
	for _ in 0..<5 {
		begin(ctx, Pointer{}, nav({}), 0)
		slider(ctx, r, "Vol", &value, 0, 1, 0.25)
		end(ctx)
		begin(ctx, Pointer{}, nav({.Right}), 0)
		slider(ctx, r, "Vol", &value, 0, 1, 0.25)
		end(ctx)
	}
	testing.expect_value(t, value, f32(1))
}

@(test)
test_paragraph_wraps_on_word_boundaries :: proc(t: ^testing.T) {
	theme := default_theme()
	ctx := create(&theme)
	defer destroy(ctx)
	begin(ctx, Pointer{}, {}, 0)
	// Without fonts each Small glyph is 8 px wide; 96 px fits twelve glyphs.
	h := paragraph(ctx, Rect{0, 0, 96, 200}, "uno due tre quattro", .Small)
	testing.expect_value(t, ctx.command_count, 2)
	testing.expect_value(t, ctx.commands[0].text, "uno due tre")
	testing.expect_value(t, ctx.commands[1].text, "quattro")
	testing.expect(t, h > 30)
}

@(test)
test_command_buffer_overflow_is_counted :: proc(t: ^testing.T) {
	theme := default_theme()
	ctx := create(&theme)
	defer destroy(ctx)
	begin(ctx, Pointer{}, {}, 0)
	for _ in 0..<MAX_COMMANDS+5 {
		fill(ctx, Rect{}, {})
	}
	testing.expect_value(t, ctx.command_count, MAX_COMMANDS)
	testing.expect_value(t, ctx.dropped, 5)
}

@(test)
test_ellipsize_respects_width_and_utf8 :: proc(t: ^testing.T) {
	theme := default_theme()
	// Without fonts Small glyphs are 8 px: 80 px fits ten bytes.
	testing.expect_value(t, ellipsize(&theme, "breve", 80, .Small), "breve")
	cut := ellipsize(&theme, "una frase troppo lunga", 80, .Small)
	testing.expect_value(t, cut, "una fra...")
	accented := ellipsize(&theme, "perché però", 72, .Small)
	testing.expect(t, len(accented) <= 9)
	testing.expect(t, accented[len(accented)-3:] == "...")
	testing.expect_value(t, ellipsize(&theme, "long", 8, .Small), "")
}

@(test)
test_covered_scene_cannot_take_pointer_keyboard_or_focus :: proc(t: ^testing.T) {
	theme := default_theme()
	ctx := create(&theme)
	defer destroy(ctx)
	r := Rect{10, 10, 200, 30}
	set_focus(ctx, 0)
	begin(ctx, Pointer{position = {20, 20}, inside = true, pressed = true, down = true}, nav({.Confirm, .Back, .Down}), 0.016)
	testing.expect(t, set_interactive(ctx, false))
	testing.expect(t, !button(ctx, r, "Covered"))
	testing.expect(t, !back_pressed(ctx) && !confirm_pressed(ctx))
	testing.expect_value(t, ctx.focus_count, 0)
	set_focus(ctx, 3)
	end(ctx)
	testing.expect_value(t, ctx.focus, 0)
	testing.expect(t, !set_interactive(ctx, true))
	testing.expect(t, confirm_pressed(ctx))
}

@(test)
test_scene_change_cancels_press_and_preserves_held_key :: proc(t: ^testing.T) {
	theme := default_theme()
	ctx := create(&theme)
	defer destroy(ctx)
	r := Rect{10, 10, 100, 30}
	begin(ctx, Pointer{position = {20, 20}, inside = true, pressed = true, down = true}, nav({.Confirm}), 0.016)
	button(ctx, r, "Old scene")
	end(ctx)
	cancel_interaction(ctx)
	begin(ctx, Pointer{position = {20, 20}, inside = true, released = true}, nav({.Confirm}), 0.016)
	testing.expect(t, !button(ctx, r, "New scene"))
	testing.expect(t, !confirm_pressed(ctx))
	end(ctx)
	begin(ctx, Pointer{position = {20, 20}, inside = true, pressed = true, down = true}, {}, 0.016)
	button(ctx, r, "New scene")
	end(ctx)
	begin(ctx, Pointer{position = {20, 20}, inside = true, released = true}, {}, 0.016)
	testing.expect(t, button(ctx, r, "New scene"))
	end(ctx)
}

@(test)
test_hud_dock_keeps_safe_edges_on_both_canvas_sizes :: proc(t: ^testing.T) {
	for width in ([?]f32{960, 1280}) {
		canvas := Rect{30, 20, width, 540}
		cols := hud_columns(canvas)
		testing.expect_value(t, cols[0].x, canvas.x + HUD_MARGIN)
		testing.expect_value(t, cols[2].x + cols[2].width, canvas.x + canvas.width - HUD_MARGIN)
		for rect, i in cols {
			testing.expect_value(t, rect.y, canvas.y + HUD_MARGIN)
			testing.expect_value(t, rect.height, f32(HUD_TOP_HEIGHT))
			if i > 0 {
				testing.expect_value(t, rect.x - (cols[i-1].x + cols[i-1].width), f32(HUD_GAP))
			}
		}
	}
}
