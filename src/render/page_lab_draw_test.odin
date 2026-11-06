package render

import "core:testing"
import rl "vendor:raylib"

@(private)
page_lab_test_quad :: proc(model: ^Page_Lab_Model, p: [4]rl.Vector3, surface: Page_Lab_Surface) {
	first := u32(model.vertex_count)
	for point in p { model.vertices[model.vertex_count] = {position = point}; model.vertex_count += 1 }
	model.triangles[model.triangle_count] = {indices = {first, first+1, first+2}, surface = surface}
	model.triangles[model.triangle_count+1] = {indices = {first, first+2, first+3}, surface = surface}
	model.triangle_count += 2
}

// Synthetic fixtures isolate the picker from the model generator: a box-based
// fallback would fill the arch opening and fail this test.
@(test)
test_page_lab_picker_keeps_arch_open_and_chooses_nearest_surface :: proc(t: ^testing.T) {
	model := new(Page_Lab_Model)
	defer free(model)
	page_lab_test_quad(model, {{-2, 0, 0}, {-1, 0, 0}, {-1, 3, 0}, {-2, 3, 0}}, .Arch)
	page_lab_test_quad(model, {{1, 0, 0}, {2, 0, 0}, {2, 3, 0}, {1, 3, 0}}, .Arch)
	page_lab_test_quad(model, {{-1, 2, 0}, {1, 2, 0}, {1, 3, 0}, {-1, 3, 0}}, .Arch)
	page_lab_test_quad(model, {{-.4, .2, 1}, {.4, .2, 1}, {.4, 1.8, 1}, {-.4, 1.8, 1}}, .Enemy)
	open := page_lab_pick(model, {position = {0, 1, -2}, direction = {0, 0, 1}})
	testing.expect(t, open.hit && open.surface == .Enemy && abs(open.distance-3) < .00001)
	post := page_lab_pick(model, {position = {-1.5, 1, -2}, direction = {0, 0, 1}})
	testing.expect(t, post.hit && post.surface == .Arch && abs(post.distance-2) < .00001)
	beam := page_lab_pick(model, {position = {0, 2.5, -2}, direction = {0, 0, 1}})
	testing.expect(t, beam.hit && beam.surface == .Arch)
	empty := page_lab_pick(model, {position = {.8, 1, -2}, direction = {0, 0, 1}})
	testing.expect(t, !empty.hit)
	back := page_lab_pick(model, {position = {0, 1, 2}, direction = {0, 0, -4}})
	testing.expect(t, back.hit && back.surface == .Enemy && abs(back.distance-1) < .00001)
}

@(test)
test_page_lab_picker_roof_visibility_and_hidden_avatar_match_draw :: proc(t: ^testing.T) {
	model := new(Page_Lab_Model)
	defer free(model)
	page_lab_test_quad(model, {{-2, 0, -2}, {-2, 0, 2}, {2, 0, 2}, {2, 0, -2}}, .Page)
	page_lab_test_quad(model, {{-.5, 1, -.5}, {-.5, 1, .5}, {.5, 1, .5}, {.5, 1, -.5}}, .Hero)
	page_lab_test_quad(model, {{-1, 2, -1}, {-1, 2, 1}, {1, 2, 1}, {1, 2, -1}}, .Roof)
	ray := rl.Ray{position = {0, 3, 0}, direction = {0, -1, 0}}
	covered := page_lab_pick(model, ray)
	testing.expect(t, covered.hit && covered.surface == .Roof && abs(covered.distance-1) < .00001)
	revealed := page_lab_pick(model, ray, false)
	testing.expect(t, revealed.hit && revealed.surface == .Hero && abs(revealed.point.y-1) < .00001)
	eye := page_lab_pick(model, ray, false, true)
	testing.expect(t, eye.hit && eye.surface == .Page && abs(eye.distance-3) < .00001)
	testing.expect(t, !page_lab_surface_visible(.Roof, false, false))
	testing.expect(t, !page_lab_surface_visible(.Hero, true, true))
	testing.expect(t, page_lab_surface_visible(.Enemy, false, true))
}

@(test)
test_page_lab_picker_bridge_has_space_below_and_rejects_degenerate_faces :: proc(t: ^testing.T) {
	model := new(Page_Lab_Model)
	defer free(model)
	page_lab_test_quad(model, {{-1, 2, -1}, {-1, 2, 1}, {1, 2, 1}, {1, 2, -1}}, .Bridge)
	page_lab_test_quad(model, {{-.3, .2, .5}, {.3, .2, .5}, {.3, 1.5, .5}, {-.3, 1.5, .5}}, .Object)
	below := page_lab_pick(model, {position = {0, 1, -3}, direction = {0, 0, 1}})
	testing.expect(t, below.hit && below.surface == .Object && abs(below.distance-3.5) < .00001)
	above := page_lab_pick(model, {position = {0, 3, 0}, direction = {0, -1, 0}})
	testing.expect(t, above.hit && above.surface == .Bridge)
	_, degenerate := page_lab_ray_triangle({position = {0, 1, -3}, direction = {0, 0, 1}}, {{}, {}, {}})
	testing.expect(t, !degenerate)
	testing.expect(t, !page_lab_pick(model, {position = {0, 1, 0}, direction = {}}).hit)
}

@(test)
test_page_lab_projected_shadow_clips_to_real_receiver_and_follows_pose :: proc(t: ^testing.T) {
	receiver := [3]rl.Vector3{{0, 0, 0}, {0, 0, 3}, {3, 0, 0}}
	caster := [3]rl.Vector3{{.1, 1, .1}, {1.4, 1, .1}, {.1, 1, 1.4}}
	polygon, count := page_lab_project_shadow(caster, receiver)
	testing.expect(t, count >= 3)
	for p in polygon[:count] {
		testing.expect(t, abs(p.y-.003) < .00001)
		testing.expect(t, p.x >= -.00001 && p.z >= -.00001 && p.x+p.z <= 3.00001)
	}
	moved := caster
	for &p in moved { p.x += 8 }
	_, moved_count := page_lab_project_shadow(moved, receiver)
	testing.expect(t, moved_count == 0)
	_, self_count := page_lab_project_shadow(receiver, receiver)
	testing.expect(t, self_count == 0)
	// A sloping page receives the same projection on its own plane, not y=0.
	slope := [3]rl.Vector3{{0, 0, 0}, {0, 0, 3}, {3, 1.5, 0}}
	sloped, sloped_count := page_lab_project_shadow(caster, slope)
	testing.expect(t, sloped_count >= 3)
	n := rl.Vector3Normalize(rl.Vector3CrossProduct(slope[1]-slope[0], slope[2]-slope[0]))
	for p in sloped[:sloped_count] { testing.expect(t, abs(rl.Vector3DotProduct(p-slope[0], n)-.003) < .0001) }
	// Bounds include every projected point for every receiver height in range.
	bounds := page_lab_shadow_bounds(caster, 0, 1.5)
	for p in sloped[:sloped_count] {
		testing.expect(t, p.x >= bounds.lo.x-.004 && p.x <= bounds.hi.x+.004)
		testing.expect(t, p.z >= bounds.lo.y-.004 && p.z <= bounds.hi.y+.004)
	}
}

// Integration with the actual cut sheet: no substitute quads or rectangular
// colliders. In particular, the bridge and roof lift their source page away;
// hiding a roof must not invent a floor in the resulting cutout.
@(test)
test_page_lab_built_model_picks_arch_roof_and_page_beside_bridge :: proc(t: ^testing.T) {
	model := new(Page_Lab_Model)
	defer free(model)
	page_lab_build(model, {})
	testing.expect(t, !model.overflow && model.triangle_count > 0)

	a := PAGE_LAB_ARCH_ORIGIN
	through_arch := page_lab_pick(model, {position = {a.x, 1, a.z+2}, direction = {0, -.15, -1}})
	testing.expect(t, through_arch.hit && through_arch.surface == .Page,
		"The ray passes through the real arch aperture and reaches the page behind it")
	testing.expect(t, through_arch.point.z < a.z-1 && abs(through_arch.point.y) < .0001)
	post := page_lab_pick(model, {position = {a.x+1, 1, a.z+2}, direction = {0, 0, -1}})
	testing.expect(t, post.hit && post.surface == .Arch, "The actual side of the arch still intercepts the ray")
	crown := page_lab_pick(model, {position = {a.x, 1.9, a.z+2}, direction = {0, 0, -1}})
	testing.expect(t, crown.hit && crown.surface == .Arch, "The opening does not remove the arch crown")

	r := PAGE_LAB_ROOF_ORIGIN
	roof_ray := rl.Ray{position = {r.x+2, 3, r.z}, direction = {-1, -.8, 0}}
	closed := page_lab_pick(model, roof_ray, true)
	revealed := page_lab_pick(model, roof_ray, false)
	testing.expect(t, closed.hit && closed.surface == .Roof)
	testing.expect(t, revealed.hit && revealed.surface == .Page && revealed.distance > closed.distance,
		"Removing the roof reveals the real page farther along this oblique ray")
	testing.expect(t, revealed.point.x < r.x-1.25 && abs(revealed.point.y) < .0001)
	cut := page_lab_pick(model, {position = {r.x, 3, r.z}, direction = {0, -1, 0}}, false)
	testing.expect(t, !cut.hit, "The removed roof leaves its genuine source cutout empty")

	b := PAGE_LAB_BRIDGE_ORIGIN
	deck := page_lab_pick(model, {position = {b.x, 3, b.z}, direction = {0, -1, 0}})
	testing.expect(t, deck.hit && deck.surface == .Bridge && abs(deck.point.y-1.05) < .001)
	underside := page_lab_pick(model, {position = {b.x, .4, b.z}, direction = {0, 1, 0}})
	testing.expect(t, underside.hit && underside.surface == .Bridge, "The same deck triangles are pickable from below")
	below := page_lab_pick(model, {position = {b.x, .4, b.z}, direction = {0, -1, 0}})
	testing.expect(t, !below.hit, "There is no invented page beneath the lifted bridge strip")
	beside := page_lab_pick(model, {position = {b.x, .4, b.z}, direction = {1, -.2, 0}})
	testing.expect(t, beside.hit && beside.surface == .Page && abs(beside.point.x-(b.x+2)) < .001,
		"A ray below the deck passes through open space and reaches the page where it exists")
}

@(test)
test_page_lab_shadow_spatial_queries_equal_brute_force_without_duplicates :: proc(t: ^testing.T) {
	model := new(Page_Lab_Model)
	state := new(Page_Lab_Draw_Context)
	defer free(model)
	defer free(state)
	queries := [?]Page_Lab_Shadow_Bounds{
		{lo = {2.7, 8}, hi = {3.3, 10}},
		{lo = {7.5, 8.5}, hi = {8.5, 9.5}},
		{lo = {-10, -10}, hi = {30, 30}},
		{lo = {4, 4}, hi = {4, 4}},
		{lo = {17, 1}, hi = {18, 2}},
		{lo = {16, 12}, hi = {16, 12}},
		{lo = {-1, -1}, hi = {0, 0}},
	}
	for pose in ([4]Page_Lab_Pose{{}, {act = .Climb, time = .63}, {act = .Turn, time = 1.3}, {act = .Climb, time = 3.5}}) {
		page_lab_build(model, pose)
		low, high, found := page_lab_shadow_index(state, model)
		testing.expect(t, found && low <= high && state.shadow_index_ready,
			"The actual model fits the fixed spatial index")
		for bounds, query_index in queries {
			// Stamps must also remain correct after wrapping, not just on frame one.
			if query_index == 2 { state.shadow_generation = max(u32) }
			candidates, tested := page_lab_shadow_query(state, bounds)
			seen: [PAGE_LAB_MAX_TRIANGLES]bool
			unique := true
			for id in candidates { unique = unique && !seen[id]; seen[id] = true }
			testing.expect(t, unique && tested <= state.shadow_receiver_count)
			expected := 0
			equal := true
			for triangle, i in model.triangles[:model.triangle_count] {
				if triangle.surface != .Page { equal = equal && !seen[i]; continue }
				// Independently derive the padded light-plane bounds from the real
				// vertices, including negative projected Z on the raised terrain.
				a := model.vertices[triangle.indices[0]].position
				first := rl.Vector2{a.x-PAGE_LAB_LIGHT.x*a.y/PAGE_LAB_LIGHT.y, a.z-PAGE_LAB_LIGHT.z*a.y/PAGE_LAB_LIGHT.y}
				lo, hi := first, first
				magnitude := f32(1)
				for id in triangle.indices {
					p := model.vertices[id].position
					q := rl.Vector2{p.x-PAGE_LAB_LIGHT.x*p.y/PAGE_LAB_LIGHT.y, p.z-PAGE_LAB_LIGHT.z*p.y/PAGE_LAB_LIGHT.y}
					lo.x = min(lo.x, q.x); lo.y = min(lo.y, q.y)
					hi.x = max(hi.x, q.x); hi.y = max(hi.y, q.y)
					magnitude = max(magnitude, abs(p.x)+abs(PAGE_LAB_LIGHT.x*p.y/PAGE_LAB_LIGHT.y), abs(p.z)+abs(PAGE_LAB_LIGHT.z*p.y/PAGE_LAB_LIGHT.y))
				}
				padding := magnitude*PAGE_LAB_SHADOW_BOUND_EPSILON
				lo -= {padding, padding}; hi += {padding, padding}
				overlap := hi.x >= bounds.lo.x && hi.y >= bounds.lo.y && lo.x <= bounds.hi.x && lo.y <= bounds.hi.y
				if overlap { expected += 1 }
				equal = equal && seen[i] == overlap
			}
			testing.expect(t, equal && len(candidates) == expected,
				"Spatial queries retain exactly the pairs from scanning every light-plane AABB")
		}
	}
}

@(test)
test_page_lab_shadow_index_fallback_keeps_receivers_outside_lab_bounds :: proc(t: ^testing.T) {
	model := new(Page_Lab_Model)
	state := new(Page_Lab_Draw_Context)
	defer free(model)
	defer free(state)
	page_lab_test_quad(model, {{20, 0, 0}, {20, 0, 2}, {22, 0, 2}, {22, 0, 0}}, .Page)
	_, _, found := page_lab_shadow_index(state, model)
	testing.expect(t, found && !state.shadow_index_ready)
	candidates, tested := page_lab_shadow_query(state, {lo = {20.5, .5}, hi = {21.5, 1.5}})
	testing.expect(t, len(candidates) == 2 && tested == 2 && candidates[0] != candidates[1],
		"An unindexable receiver falls back to exact scanning rather than losing its shadow")
}
