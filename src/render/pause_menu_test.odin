package render

import "core:testing"

@(test)
test_pause_menu_resumes_and_goes_back_to_the_main_menu :: proc(t: ^testing.T) {
	renderer := new(Renderer)
	defer free(renderer)
	renderer.canvas_width, renderer.canvas_height = 1280, 720
	resume := pause_choice_bounds(renderer, .Resume)
	menu := pause_choice_bounds(renderer, .Menu)
	testing.expect(t, menu.y >= resume.y+resume.height && rectangle_center(resume).x == 640)
	testing.expect_value(t, pause_choice_at_point(renderer, rectangle_center(resume), true), Pause_Choice.Resume)
	testing.expect_value(t, pause_choice_at_point(renderer, rectangle_center(menu), true), Pause_Choice.Menu)
	// Opened without the main menu (a run started from the command line).
	testing.expect_value(t, pause_choice_at_point(renderer, rectangle_center(menu), false), Pause_Choice.None)
	testing.expect_value(t, pause_choice_at_point(renderer, {5, 5}, true), Pause_Choice.None)
}

@(test)
test_defeat_offers_restart_main_menu_and_quit :: proc(t: ^testing.T) {
	restart := defeat_choice_bounds(960, 540, .Restart, true)
	testing.expect(t, restart == defeat_restart_bounds(960, 540))
	testing.expect_value(t, rectangle_center(restart).x, f32(480))
	testing.expect(t, restart.x >= 0 && restart.y >= 0)
	testing.expect(t, restart.x+restart.width <= 960 && restart.y+restart.height <= 540)
	testing.expect(t, defeat_restart_at_point(960, 540, rectangle_center(restart)))
	testing.expect(t, defeat_restart_at_point(960, 540, {restart.x, restart.y}))
	testing.expect(t, !defeat_restart_at_point(960, 540, {restart.x-1, rectangle_center(restart).y}))
	testing.expect(t, !defeat_restart_at_point(960, 540, {rectangle_center(restart).x, restart.y+restart.height+1}))
	menu := defeat_choice_bounds(960, 540, .Menu, true)
	quit := defeat_choice_bounds(960, 540, .Quit, true)
	testing.expect(t, menu.y > restart.y && quit.y > menu.y && quit.y+quit.height <= 540)
	testing.expect_value(t, defeat_choice_at_point(960, 540, rectangle_center(restart), true), Defeat_Choice.Restart)
	testing.expect_value(t, defeat_choice_at_point(960, 540, rectangle_center(menu), true), Defeat_Choice.Menu)
	testing.expect_value(t, defeat_choice_at_point(960, 540, rectangle_center(quit), true), Defeat_Choice.Quit)
	// Without a main menu, quitting takes the menu's place.
	quit_alone := defeat_choice_bounds(960, 540, .Quit, false)
	testing.expect(t, quit_alone == menu)
	testing.expect_value(t, defeat_choice_at_point(960, 540, rectangle_center(menu), false), Defeat_Choice.Quit)
	testing.expect_value(t, defeat_choice_at_point(960, 540, {0, 0}, true), Defeat_Choice.None)
}
