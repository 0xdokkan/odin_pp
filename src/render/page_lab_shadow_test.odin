package render

import "core:fmt"
import "core:testing"
import rl "vendor:raylib"

@(private)
page_lab_test_shadow_query_against_all_receivers :: proc(t: ^testing.T, state: ^Page_Lab_Draw_Context, caster: [3]rl.Vector3) -> (candidate_count, positive_count: int) {
	candidates, _ := page_lab_shadow_query(state, page_lab_shadow_light_bounds(caster))
	candidate_count = len(candidates)
	seen: [PAGE_LAB_MAX_TRIANGLES]bool
	for id in candidates { seen[id] = true }
	for id in state.shadow_receivers[:state.shadow_receiver_count] {
		receiver := &state.shadow_prepared[id]
		// This reference still recalculates its plane, edge normals and full
		// clipping for EVERY receiver, regardless of either broadphase.
		expected, expected_count := page_lab_project_shadow(caster, receiver.points)
		if expected_count > 0 {
			positive_count += 1
			testing.expectf(t, seen[id], "Light-plane index omitted receiver %d producing %d clipped vertices", id, expected_count)
		}
		if !seen[id] { continue }
		actual, actual_count := page_lab_project_shadow_prepared(caster, receiver)
		testing.expect_value(t, actual_count, expected_count)
		if actual_count != expected_count { continue }
		for p, i in actual[:actual_count] {
			testing.expectf(t, p == expected[i], "Prepared plane changed polygon vertex %d: %v != %v", i, p, expected[i])
		}
	}
	return
}

@(test)
test_page_lab_light_plane_and_prepared_shadows_equal_full_receiver_scan :: proc(t: ^testing.T) {
	model := new(Page_Lab_Model); defer free(model)
	state := new(Page_Lab_Draw_Context); defer free(state)
	poses := [?]Page_Lab_Pose{
		{}, {act = .Walk, time = .7}, {act = .Turn, time = 1.3},
		{act = .Climb, time = .63}, {act = .Climb, time = 2}, {act = .Climb, time = 3.983333},
		{act = .Death, time = 1.4}, {act = .Death, time = 3.2}, {act = .Flight, time = 1.4},
	}
	for pose in poses {
		page_lab_build(model, pose)
		low, high, found := page_lab_shadow_index(state, model)
		testing.expect(t, found && state.shadow_index_ready)
		counts, visited: [Page_Lab_Surface]int
		for triangle in model.triangles[:model.triangle_count] { counts[triangle.surface] += 1 }
		old_pairs, candidates, positives, casters := 0, 0, 0, 0
		for triangle in model.triangles[:model.triangle_count] {
			if triangle.surface == .Page { continue }
			index := visited[triangle.surface]; visited[triangle.surface] += 1
			stride := max(1, counts[triangle.surface]/12)
			if index%stride != 0 && index != counts[triangle.surface]-1 { continue }
			p, valid := page_lab_triangle_points(model, triangle)
			testing.expect(t, valid)
			selected, actual := page_lab_test_shadow_query_against_all_receivers(t, state, p)
			candidates += selected; positives += actual; casters += 1
			// Record a directly comparable count for the old height-expanded
			// XZ filter. These are counts, not GPU or frame-time measurements.
			old_bounds := page_lab_shadow_bounds(p, low, high)
			for id in state.shadow_receivers[:state.shadow_receiver_count] {
				points := state.shadow_prepared[id].points
				bounds := Page_Lab_Shadow_Bounds{lo = {points[0].x, points[0].z}, hi = {points[0].x, points[0].z}}
				for v in points {
					bounds.lo.x = min(bounds.lo.x, v.x); bounds.lo.y = min(bounds.lo.y, v.z)
					bounds.hi.x = max(bounds.hi.x, v.x); bounds.hi.y = max(bounds.hi.y, v.z)
				}
				if page_lab_bounds_overlap(old_bounds, bounds) { old_pairs += 1 }
			}
		}
		fmt.printf("PAGE LAB SHADOW EQUIVALENCE act=%v time=%.6f sampled_casters=%d receivers=%d old_xz_pairs=%d light_pairs=%d positive_pairs=%d\n",
			pose.act, pose.time, casters, state.shadow_receiver_count, old_pairs, candidates, positives)
	}
}

@(test)
test_page_lab_light_index_preserves_shadows_across_page_and_bin_boundaries :: proc(t: ^testing.T) {
	model := new(Page_Lab_Model); defer free(model)
	state := new(Page_Lab_Draw_Context); defer free(state)
	// Elevated page projects beyond X=16 and below Z=0. Its actual domain,
	// not the unprojected page rectangle, must be indexed.
	page_lab_test_quad(model, {{0, .6, 0}, {0, .6, 12}, {16, .6, 12}, {16, .6, 0}}, .Page)
	_, _, found := page_lab_shadow_index(state, model)
	testing.expect(t, found && state.shadow_index_ready)
	testing.expect(t, state.shadow_domain.lo.y < 0 && state.shadow_domain.hi.x > PAGE_LAB_SIZE.x)
	for origin in ([5]rl.Vector3{{0, .6, 0}, {15.99, .6, 0}, {0, .6, 11.99}, {15.99, .6, 11.99}, {8, .6, 6}}) {
		for shift in ([3]f32{-.000001, 0, .000001}) {
			caster := [3]rl.Vector3{origin+{shift, 0, 0}, origin+{.01+shift, 0, 0}, origin+{shift, 0, .01}}
			for &p in caster { p += PAGE_LAB_LIGHT*2 }
			_, positives := page_lab_test_shadow_query_against_all_receivers(t, state, caster)
			testing.expect(t, positives > 0, "Boundary contact still casts its original shadow")
		}
	}
	// A receiver outside the authored footprint still uses the exact fallback;
	// the cache and light bounds remain correct there too.
	model.vertex_count = 0; model.triangle_count = 0
	page_lab_test_quad(model, {{20, 1, 0}, {20, 1, 2}, {22, 1, 2}, {22, 1, 0}}, .Page)
	_, _, found = page_lab_shadow_index(state, model)
	testing.expect(t, found && !state.shadow_index_ready)
	caster := [3]rl.Vector3{{20.5, 1, .5}, {21, 1, .5}, {20.5, 1, 1}}
	for &p in caster { p += PAGE_LAB_LIGHT*2 }
	_, positives := page_lab_test_shadow_query_against_all_receivers(t, state, caster)
	testing.expect(t, positives > 0)
}

@(test)
test_page_lab_flat_polygon_preserves_shadow_and_edge_vertex_stream :: proc(t: ^testing.T) {
	// Distinct nonplanar values make a reversed index, repeated vertex or
	// changed winding observable. Cover every size accepted by the clip buffer.
	points: [12]rl.Vector3
	for &p, i in points { p = {f32(i)*.37, f32(i*i)*.13, f32(17-i)*.41} }
	for count in 3..=len(points) {
		vertices := 0
		for triangle in 0..<count-2 {
			actual := page_lab_polygon_triangle(points[:count], triangle)
			testing.expect_value(t, actual[0], points[0])
			testing.expect_value(t, actual[1], points[triangle+1])
			testing.expect_value(t, actual[2], points[triangle+2])
			vertices += len(actual)
		}
		testing.expect_value(t, vertices, 3*(count-2))
		testing.expect(t, vertices <= 30, "One reservation covers the largest fixed clip polygon")
	}
	a, b := rl.Vector3{1, 2, 3}, rl.Vector3{4, 6, 8}
	offset := rl.Vector3{.01, -.02, .03}
	quad := [4]rl.Vector3{a-offset, b-offset, b+offset, a+offset}
	old_edge_stream := [6]rl.Vector3{a-offset, b-offset, b+offset, a-offset, b+offset, a+offset}
	for triangle in 0..<2 {
		actual := page_lab_polygon_triangle(quad[:], triangle)
		for p, i in actual { testing.expect_value(t, p, old_edge_stream[triangle*3+i]) }
	}
	// Exercise the actual clipping output as well as authored edge quads.
	polygon, count := page_lab_project_shadow({{-.3, 1, .2}, {2.8, 1, -.4}, {1, 1, 3.2}}, {{0, 0, 0}, {0, 0, 3}, {3, 0, 0}})
	testing.expect(t, count > 3)
	for old_index in 1..<count-1 {
		old_triangle := [3]rl.Vector3{polygon[0], polygon[old_index], polygon[old_index+1]}
		testing.expect_value(t, page_lab_polygon_triangle(polygon[:count], old_index-1), old_triangle)
	}
}
