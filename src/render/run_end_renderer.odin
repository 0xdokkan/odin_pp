package render

import "core:c"
import "core:fmt"
import rl "vendor:raylib"
import game "../game"
import view "../view"

DEFEAT_RESTART_WIDTH  :: f32(220)
DEFEAT_RESTART_HEIGHT :: f32(42)
DEFEAT_BUTTON_GAP     :: f32(10)

// After a defeat: try again, go back to the main menu (when the run was opened
// from it) or quit the game.
Defeat_Choice :: enum u8 {None, Restart, Menu, Quit}

defeat_restart_bounds :: proc(canvas_width, canvas_height: f32) -> rl.Rectangle {
	return {
		x = (canvas_width-DEFEAT_RESTART_WIDTH)*0.5,
		y = canvas_height*0.59,
		width = DEFEAT_RESTART_WIDTH,
		height = DEFEAT_RESTART_HEIGHT,
	}
}

defeat_restart_at_point :: proc(
	canvas_width, canvas_height: f32,
	point: view.Vec2,
) -> bool {
	return point_in_rectangle(point, defeat_restart_bounds(canvas_width, canvas_height))
}

// The buttons stack under the restart one; without a menu, quit moves up.
defeat_choice_bounds :: proc(canvas_width, canvas_height: f32, choice: Defeat_Choice, menu: bool) -> rl.Rectangle {
	bounds := defeat_restart_bounds(canvas_width, canvas_height)
	row := f32(0)
	#partial switch choice {
	case .Menu: row = 1
	case .Quit: row = 2 if menu else 1
	}
	bounds.y += row*(DEFEAT_RESTART_HEIGHT+DEFEAT_BUTTON_GAP)
	return bounds
}

defeat_choice_at_point :: proc(canvas_width, canvas_height: f32, point: view.Vec2, menu: bool) -> Defeat_Choice {
	for choice in ([3]Defeat_Choice{.Restart, .Menu, .Quit}) {
		if choice == .Menu && !menu { continue }
		if point_in_rectangle(point, defeat_choice_bounds(canvas_width, canvas_height, choice, menu)) { return choice }
	}
	return .None
}

draw_defeat_overlay :: proc(
	run: ^game.Run_State,
	canvas_width, canvas_height: f32,
	hovered: Defeat_Choice, menu := false, theme: ^Renderer = nil,
) {
	assert(run != nil && run.phase == .Defeat)
	menu_rectangle(theme, 0, 0, c.int(canvas_width), c.int(canvas_height), rl.Color{8, 10, 12, 210})

	title: cstring = "DEFEAT"
	title_size: c.int = 42
	title_width := menu_measure_text(theme, title, title_size)
	menu_text(theme,
		title,
		c.int(canvas_width*0.5)-title_width/2,
		c.int(canvas_height*0.31),
		title_size,
		rl.Color{235, 91, 91, 255},
	)

	summary := fmt.ctprintf("STANZE SUPERATE  %d" if menu_themed(theme) else "ROOMS CLEARED  %d", run.cleared_count)
	summary_size: c.int = 16
	summary_width := menu_measure_text(theme, summary, summary_size)
	menu_text(theme,
		summary,
		c.int(canvas_width*0.5)-summary_width/2,
		c.int(canvas_height*0.46),
		summary_size,
		rl.Color{203, 211, 207, 255},
	)

	labels := [Defeat_Choice]cstring{.None = "", .Restart = "RESTART", .Menu = "MAIN MENU", .Quit = "QUIT GAME"}
	for choice in ([3]Defeat_Choice{.Restart, .Menu, .Quit}) {
		if choice == .Menu && !menu { continue }
		bounds := defeat_choice_bounds(canvas_width, canvas_height, choice, menu)
		fill := rl.Color{42, 47, 50, 255}
		outline := rl.Color{147, 158, 158, 255}
		if hovered == choice {
			fill = rl.Color{62, 70, 72, 255}
			outline = rl.Color{255, 247, 237, 255}
		}
		menu_rectangle_rec(theme, bounds, fill)
		menu_outline(theme, bounds, 2, outline)
		label := labels[choice]
		font_size: c.int = 18
		label_width := menu_measure_text(theme, label, font_size)
		menu_text(theme,
			label,
			c.int(bounds.x+bounds.width*0.5)-label_width/2,
			c.int(bounds.y+bounds.height*0.5)-font_size/2,
			font_size,
			rl.Color{255, 247, 237, 255},
		)
	}
}
