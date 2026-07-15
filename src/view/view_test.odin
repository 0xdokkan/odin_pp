package view

import "core:math"
import "core:testing"

approximately_equal :: proc(a, b: f32, epsilon: f32 = 0.001) -> bool {
	return math.abs(a-b) <= epsilon
}

expect_vec2 :: proc(t: ^testing.T, actual, expected: Vec2) {
	testing.expectf(t, approximately_equal(actual.x, expected.x), "x: expected %v, got %v", expected.x, actual.x)
	testing.expectf(t, approximately_equal(actual.y, expected.y), "y: expected %v, got %v", expected.y, actual.y)
}

@(test)
test_fit_viewport_preserves_aspect_ratio :: proc(t: ^testing.T) {
	viewport, ok := calculate_viewport(1600, 1000, 960, 540, .Fit)
	testing.expect(t, ok)

	testing.expect(t, approximately_equal(viewport.destination.width, 1600))
	testing.expect(t, approximately_equal(viewport.destination.height, 900))
	testing.expect(t, approximately_equal(viewport.destination.x, 0))
	testing.expect(t, approximately_equal(viewport.destination.y, 50))
	testing.expect(t, approximately_equal(viewport.scale_x, viewport.scale_y))
}

@(test)
test_integer_viewport_uses_whole_scale_when_possible :: proc(t: ^testing.T) {
	viewport, ok := calculate_viewport(1600, 1000, 960, 540, .Integer)
	testing.expect(t, ok)

	testing.expect_value(t, viewport.scale_x, f32(1))
	testing.expect_value(t, viewport.scale_y, f32(1))
	testing.expect_value(t, viewport.destination, Rect{x = 320, y = 230, width = 960, height = 540})
}

@(test)
test_stretch_viewport_and_mouse_conversion :: proc(t: ^testing.T) {
	viewport, ok := calculate_viewport(1920, 1080, 960, 540, .Stretch)
	testing.expect(t, ok)

	canvas_point, inside := window_to_canvas(&viewport, {x = 960, y = 540})
	testing.expect(t, inside)
	expect_vec2(t, canvas_point, {x = 480, y = 270})

	_, outside := window_to_canvas(&viewport, {x = -1, y = 20})
	testing.expect(t, !outside)
}

@(test)
test_isometric_projection_round_trip :: proc(t: ^testing.T) {
	projection := Isometric_Projection{tile_width = 64, tile_height = 32}

	expect_vec2(t, grid_point_to_world(&projection, {x = 1, y = 0}), {x = 32, y = 16})
	expect_vec2(t, grid_point_to_world(&projection, {x = 0, y = 1}), {x = -32, y = 16})

	grid_point := Vec2{x = 3.25, y = 4.75}
	world_point := grid_point_to_world(&projection, grid_point)
	expect_vec2(t, world_to_grid_point(&projection, world_point), grid_point)
}

@(test)
test_isometric_picking_uses_diamond_area :: proc(t: ^testing.T) {
	projection := Isometric_Projection{tile_width = 64, tile_height = 32}
	camera := make_camera({x = 100, y = 50})

	cell_center := grid_point_to_canvas(&camera, &projection, {x = 2.5, y = 3.5})
	cell := canvas_to_cell(&camera, &projection, cell_center)
	testing.expect_value(t, cell.x, 2)
	testing.expect_value(t, cell.y, 3)
}

@(test)
test_zoom_keeps_anchor_on_same_world_point :: proc(t: ^testing.T) {
	camera := make_camera({x = 400, y = 100})
	anchor := Vec2{x = 300, y = 220}
	before := canvas_to_world(&camera, anchor)

	set_zoom_around(&camera, anchor, 2)
	after := canvas_to_world(&camera, anchor)

	expect_vec2(t, after, before)
	testing.expect_value(t, camera.zoom, f32(2))
}
