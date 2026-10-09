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
test_button_click_requires_press_and_release_inside :: proc(t: ^testing.T) {
	theme := default_theme()
	ctx := create(&theme)
	defer destroy(ctx)
	r := Rect{10, 10, 100, 30}
	begin(ctx, Pointer{position = {20, 20}, inside = true, pressed = true, down = true}, {}, 0.016)
	testing.expect(t, !button(ctx, r, "Ok"))
	end(ctx)
	begin(ctx, Pointer{position = {25, 20}, inside = true, released = true}, {}, 0.016)
	testing.expect(t, button(ctx, r, "Ok"))
	end(ctx)
	// Press outside then release inside is not a click.
	begin(ctx, Pointer{position = {300, 300}, inside = true, pressed = true, down = true}, {}, 0.016)
	button(ctx, r, "Ok")
	end(ctx)
	begin(ctx, Pointer{position = {25, 20}, inside = true, released = true}, {}, 0.016)
	testing.expect(t, !button(ctx, r, "Ok"))
	end(ctx)
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
test_disabled_buttons_never_click :: proc(t: ^testing.T) {
	theme := default_theme()
	ctx := create(&theme)
	defer destroy(ctx)
	r := Rect{0, 0, 50, 20}
	begin(ctx, Pointer{position = {5, 5}, inside = true, pressed = true, down = true}, {}, 0)
	button(ctx, r, "x", enabled = false)
	end(ctx)
	begin(ctx, Pointer{position = {5, 5}, inside = true, released = true}, {}, 0)
	testing.expect(t, !button(ctx, r, "x", enabled = false))
	end(ctx)
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
	// Without fonts each Small glyph is 7 px wide; 84 px fits twelve glyphs.
	h := paragraph(ctx, Rect{0, 0, 84, 200}, "uno due tre quattro", .Small)
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
