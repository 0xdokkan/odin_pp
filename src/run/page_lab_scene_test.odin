package run

import "core:testing"
import ui "../engine/ui"
import render "../render"

@(test)
test_page_lab_space_pauses_without_activating_the_focused_button :: proc(t: ^testing.T) {
	s := new(Page_Lab_Scene)
	defer free(s)
	theme := ui.default_theme()
	ctx := ui.create(&theme)
	defer ui.destroy(ctx)
	ctx.keyboard_mode = true
	ctx.focus = 0
	ctx.nav.pressed = {.Confirm}
	page_lab_scene_pause_key(s, ctx, true)
	testing.expect(t, s.paused)
	testing.expect(t, !ui.button(ctx, {0, 0, 100, 30}, "Torna"))
	ctx.focus_count = 0
	ctx.nav.pressed = {.Confirm}
	page_lab_scene_pause_key(s, ctx, false)
	testing.expect(t, s.paused)
	testing.expect(t, ui.button(ctx, {0, 0, 100, 30}, "Torna"), "Enter/pad confirmation remains available")
	page_lab_scene_pause_key(s, ctx, true)
	testing.expect(t, !s.paused)
}

@(test)
test_page_lab_print_animates_on_an_unchanged_support_and_pauses_with_it :: proc(t: ^testing.T) {
	s := new(Page_Lab_Scene)
	defer free(s)
	pose := page_lab_scene_geometry_pose(s.pose)
	page_lab_scene_advance(s, .5)
	testing.expect(t, s.print_clock == .5)
	testing.expect_value(t, page_lab_scene_geometry_pose(s.pose), pose)
	s.paused = true
	before := s.pose
	page_lab_scene_advance(s, .5)
	testing.expect(t, s.print_clock == .5 && s.pose == before)
	s.paused = false
	s.pose.act = .Death
	page_lab_scene_advance(s, .5)
	testing.expect(t, s.print_clock == 1)
	testing.expect_value(t, page_lab_scene_geometry_pose(s.pose), render.Page_Lab_Pose{act = .Death, time = 1})
}
