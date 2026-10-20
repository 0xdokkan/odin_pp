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

	canvas_point, inside := window_to_canvas(&viewport, {960, 540})
	testing.expect(t, inside)
	expect_vec2(t, canvas_point, {480, 270})

	_, outside := window_to_canvas(&viewport, {-1, 20})
	testing.expect(t, !outside)
}
