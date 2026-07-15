package render

import "core:testing"
import view "../view"

@(test)
test_defeat_restart_bounds_are_centered_and_inside_canvas :: proc(t: ^testing.T) {
	bounds := defeat_restart_bounds(960, 540)

	testing.expect_value(t, bounds.width, DEFEAT_RESTART_WIDTH)
	testing.expect_value(t, bounds.height, DEFEAT_RESTART_HEIGHT)
	testing.expect_value(t, bounds.x+bounds.width*0.5, f32(480))
	testing.expect(t, bounds.x >= 0 && bounds.y >= 0)
	testing.expect(t, bounds.x+bounds.width <= 960)
	testing.expect(t, bounds.y+bounds.height <= 540)
}

@(test)
test_defeat_restart_hit_test_accepts_button_and_rejects_outside :: proc(t: ^testing.T) {
	bounds := defeat_restart_bounds(960, 540)
	center := view.Vec2{
		x = bounds.x+bounds.width*0.5,
		y = bounds.y+bounds.height*0.5,
	}

	testing.expect(t, defeat_restart_at_point(960, 540, center))
	testing.expect(t, defeat_restart_at_point(960, 540, {x = bounds.x, y = bounds.y}))
	testing.expect(t, !defeat_restart_at_point(960, 540, {x = bounds.x-1, y = center.y}))
	testing.expect(t, !defeat_restart_at_point(960, 540, {
		x = center.x,
		y = bounds.y+bounds.height+1,
	}))
}
