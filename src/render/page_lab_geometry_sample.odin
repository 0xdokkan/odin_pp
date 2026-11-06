package render

import "core:math"
import rl "vendor:raylib"

// One authority for the original axis refinement. Bounds for classification
// expand this rectangle, without adding or moving any of its sampled axes.
@(private)
Page_Lab_Refinement :: struct {
	origin: rl.Vector3,
	width, depth, end_y: f32,
}

@(private)
page_lab_refinement :: proc(pose: Page_Lab_Pose, surface: Page_Lab_Surface) -> (r: Page_Lab_Refinement) {
	r.origin = page_lab_origin(pose, surface)
	r.width, r.depth = .75, 2.125
	switch surface {
	case .Hero: r.width = 1.25; r.depth = 2.6875 if pose.act == .Mount else 2.4375
	case .Enemy: r.width = 1.3125; r.depth = 2.625
	case .Arch: r.width = 1.25
	case .Bridge: r.width = .75; r.depth = 3
	case .Roof: r.width = 1.25; r.depth = 2.5
	case .Flight: r.width = 1.3125
	case .Page, .Object, .Arrow, .Bomb:
	}
	r.end_y = r.origin.z
	if surface == .Bridge { r.end_y += 1.5 }
	if surface == .Roof { r.end_y += 1.25 }
	return
}

@(private)
page_lab_shape_bounds :: proc(r: Page_Lab_Refinement) -> (lo, hi: rl.Vector2) {
	// Flight's widest analytic wing tends to 1.31875, just beyond its 1.3125
	// refinement width. One original step includes it and floating-point borders;
	// the unchanged shape predicate still decides ownership of every visited cell.
	lo = {r.origin.x-r.width-PAGE_LAB_STEP, r.end_y-r.depth-PAGE_LAB_STEP}
	hi = {r.origin.x+r.width+PAGE_LAB_STEP, r.end_y+PAGE_LAB_STEP}
	return
}

// Mask coordinates separate into X and Y. Sample the original source-pixel
// formula at each axis midpoint once, preserving its f32 operations and floor.
// The immutable CPU atlas is acquired once per build, never per sheet cell.
@(private)
Page_Lab_Shape_Samples :: struct {
	origins: [Page_Lab_Surface]rl.Vector3,
	xs: [PAGE_LAB_AXIS_X]f32,
	ys: [PAGE_LAB_AXIS_Y]f32,
	pixel_x: [2][PAGE_LAB_AXIS_X]int,
	pixel_y: [2][PAGE_LAB_AXIS_Y]int,
	masks: [2]^[CARTOON_CELL*CARTOON_CELL]u8,
}

@(private)
page_lab_prepare_shape_samples :: proc(m: ^Page_Lab_Model, samples: ^Page_Lab_Shape_Samples) {
	for surface in Page_Lab_Surface { samples.origins[surface] = page_lab_origin(m.pose, surface) }
	for x in 0..<m.x_count-1 { samples.xs[x] = (m.xs[x]+m.xs[x+1])*.5 }
	for y in 0..<m.y_count-1 { samples.ys[y] = (m.ys[y]+m.ys[y+1])*.5 }
	cache := page_lab_print_cpu()
	for surface, actor in ([2]Page_Lab_Surface{.Hero, .Enemy}) {
		sample := page_lab_print_sample(m.pose, surface, 0)
		samples.masks[actor] = &cache.masks[sample.actor]
		for x in 0..<m.x_count-1 {
			pixel := page_lab_print_source_pixel(sample, {samples.xs[x], 0})
			samples.pixel_x[actor][x] = int(math.floor(pixel.x))
		}
		for y in 0..<m.y_count-1 {
			pixel := page_lab_print_source_pixel(sample, {0, samples.ys[y]})
			samples.pixel_y[actor][y] = int(math.floor(pixel.y))
		}
	}
}

@(private)
page_lab_sampled_mask :: proc(samples: ^Page_Lab_Shape_Samples, actor, x, y: int) -> bool {
	px, py := samples.pixel_x[actor][x], samples.pixel_y[actor][y]
	if px < 0 || py < 0 || px >= CARTOON_CELL || py >= int(CARTOON_FEET) { return false }
	return samples.masks[actor][py*CARTOON_CELL+px] != 0
}

@(private)
page_lab_sampled_shape_at :: proc(samples: ^Page_Lab_Shape_Samples, pose: Page_Lab_Pose, surface: Page_Lab_Surface, x, y: int) -> bool {
	point := rl.Vector2{samples.xs[x], samples.ys[y]}
	known, covered := false, false
	if surface == .Hero || surface == .Enemy {
		known = true
		covered = page_lab_sampled_mask(samples, int(surface)-int(Page_Lab_Surface.Hero), x, y)
	}
	return page_lab_shape_at(pose, surface, point, samples.origins[surface], known, covered)
}

@(private)
page_lab_sampled_surface_at :: proc(samples: ^Page_Lab_Shape_Samples, pose: Page_Lab_Pose, x, y: int) -> Page_Lab_Surface {
	for surface in Page_Lab_Surface.Hero..=Page_Lab_Surface.Flight {
		if page_lab_sampled_shape_at(samples, pose, surface, x, y) { return surface }
	}
	return .Page
}

@(private)
page_lab_sample_range :: proc(values: []f32, lower, upper: f32) -> (lo, hi: int) {
	for lo < len(values) && values[lo] < lower { lo += 1 }
	hi = lo
	for hi < len(values) && values[hi] <= upper { hi += 1 }
	return
}

@(private)
page_lab_fill_sampled_cells :: proc(m: ^Page_Lab_Model, samples: ^Page_Lab_Shape_Samples) {
	m.cells = {}
	// First matching surface wins, exactly as in page_lab_surface_at. Only the
	// cell-classification traversal changes; the later row-major mesh stays intact.
	for surface in Page_Lab_Surface.Hero..=Page_Lab_Surface.Flight {
		lo, hi := page_lab_shape_bounds(page_lab_refinement(m.pose, surface))
		x0, x1 := page_lab_sample_range(samples.xs[:m.x_count-1], lo.x, hi.x)
		y0, y1 := page_lab_sample_range(samples.ys[:m.y_count-1], lo.y, hi.y)
		for y in y0..<y1 { for x in x0..<x1 {
			index := y*PAGE_LAB_AXIS_X+x
			if m.cells[index] != .Page { continue }
			if page_lab_sampled_shape_at(samples, m.pose, surface, x, y) { m.cells[index] = surface }
		} }
	}
}
