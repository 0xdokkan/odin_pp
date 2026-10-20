package render

import "core:c"
import rl "vendor:raylib"
import view "../engine/view"

// The pause menu over the board: resume, or go back to the main menu when the
// run was opened from it. The scene reads the choice under the mouse.
Pause_Choice :: enum u8 {None, Resume, Menu}

PAUSE_BUTTON_WIDTH :: f32(240)
PAUSE_BUTTON_HEIGHT :: f32(38)
PAUSE_BUTTON_GAP :: f32(10)

@(private)
pause_choice_bounds :: proc(renderer: ^Renderer, choice: Pause_Choice) -> rl.Rectangle {
	row := f32(int(choice)-1)
	return {renderer.canvas_width*0.5-PAUSE_BUTTON_WIDTH*0.5, renderer.canvas_height*0.5+row*(PAUSE_BUTTON_HEIGHT+PAUSE_BUTTON_GAP),
		PAUSE_BUTTON_WIDTH, PAUSE_BUTTON_HEIGHT}
}

pause_choice_at_point :: proc(renderer: ^Renderer, point: view.Vec2, menu: bool) -> Pause_Choice {
	if point_in_rectangle(point, pause_choice_bounds(renderer, .Resume)) { return .Resume }
	if menu && point_in_rectangle(point, pause_choice_bounds(renderer, .Menu)) { return .Menu }
	return .None
}

@(private)
draw_pause_menu :: proc(renderer: ^Renderer, hovered: Pause_Choice, menu: bool) {
	rl.DrawRectangle(0, 0, c.int(renderer.canvas_width), c.int(renderer.canvas_height), {3, 7, 12, 185})
	top := renderer.canvas_height*0.5-96
	title_width := gothic_text_width(renderer, "PAUSA", 32)
	gothic_text(renderer, "PAUSA", renderer.canvas_width*0.5-title_width*0.5, top, 32, GOTHIC_PAPER)
	draw_pause_button(renderer, pause_choice_bounds(renderer, .Resume), "P", "RIPRENDI", hovered == .Resume)
	if menu { draw_pause_button(renderer, pause_choice_bounds(renderer, .Menu), "F10", "MENU PRINCIPALE", hovered == .Menu) }
}

@(private = "file")
draw_pause_button :: proc(renderer: ^Renderer, bounds: rl.Rectangle, key, label: cstring, hovered: bool) {
	accent := GOTHIC_PAPER if hovered else GOTHIC_BLUE
	hud_frame(bounds, accent)
	if hovered { rl.DrawRectangleRec({bounds.x+2, bounds.y+2, bounds.width-4, bounds.height-4}, {50, 71, 91, 200}) }
	key_width := gothic_text_width(renderer, key, 12)+12
	rl.DrawRectangleRec({bounds.x+8, bounds.y+8, key_width, bounds.height-16}, accent)
	gothic_text(renderer, key, bounds.x+14, bounds.y+bounds.height*0.5-7, 12, GOTHIC_INK)
	gothic_text_fit(renderer, label, {bounds.x+key_width+18, bounds.y+bounds.height*0.5-9, bounds.width-key_width-26, 18}, 16, GOTHIC_PAPER)
}
