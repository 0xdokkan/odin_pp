package render

import "core:testing"
import rl "vendor:raylib"

@(test)
test_page_lab_prepared_mask_samples_match_direct_shape_predicates :: proc(t: ^testing.T) {
	m := new(Page_Lab_Model); defer free(m)
	samples := new(Page_Lab_Shape_Samples); defer free(samples)
	for act in Page_Lab_Act {
		for seconds in ([3]f32{.63, 1.3, 3.99}) {
			m.pose = {act = act, time = seconds}
			m.x_count, m.y_count, m.overflow = 0, 0, false
			page_lab_axes(m)
			if !testing.expect(t, !m.overflow) { return }
			page_lab_prepare_shape_samples(m, samples)
			page_lab_fill_sampled_cells(m, samples)
			for y in 0..<m.y_count-1 { for x in 0..<m.x_count-1 {
				point := rl.Vector2{(m.xs[x]+m.xs[x+1])*.5, (m.ys[y]+m.ys[y+1])*.5}
				expected := page_lab_surface_at(m.pose, point)
				actual := page_lab_sampled_surface_at(samples, m.pose, x, y)
				if !testing.expectf(t, actual == expected, "%v %.6f cell %d/%d: prepared %v, direct %v", act, seconds, x, y, actual, expected) { return }
				if !testing.expectf(t, m.cells[y*PAGE_LAB_AXIS_X+x] == expected, "%v %.6f cell %d/%d: regional fill differs from direct classification", act, seconds, x, y) { return }
			} }
		}
	}
}

@(test)
test_page_lab_classification_bounds_include_wing_beyond_refinement_width :: proc(t: ^testing.T) {
	r := page_lab_refinement({}, .Flight)
	point := rl.Vector2{r.origin.x+1.315, r.origin.z-1.374}
	testing.expect(t, page_lab_shape({}, .Flight, point))
	testing.expect(t, point.x > r.origin.x+r.width, "The axis rectangle alone is not a conservative shape bound")
	lo, hi := page_lab_shape_bounds(r)
	testing.expect(t, point.x >= lo.x && point.x <= hi.x && point.y >= lo.y && point.y <= hi.y)
}
