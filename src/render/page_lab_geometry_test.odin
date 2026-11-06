package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"

@(test)
test_page_lab_all_acts_are_one_cut_sheet_without_nonfinite_poses :: proc(t: ^testing.T) {
	m:=new(Page_Lab_Model); defer free(m)
	for act in Page_Lab_Act {
		for seconds in ([5]f32{0, .63, 1.5, 2.9, 4}) {
			page_lab_build(m, {act=act, time=seconds})
			testing.expectf(t, !m.overflow, "act %v time %.2f exceeds a fixed buffer", act, seconds)
			testing.expectf(t, page_lab_validate(m), "act %v time %.2f breaks the shared sheet", act, seconds)
			testing.expect(t, m.cut_edge_count>0 && m.hinge_count>0)
		}
	}
}

@(test)
test_page_lab_cutouts_replace_page_triangles_and_keep_two_foot_roots :: proc(t: ^testing.T) {
	m:=new(Page_Lab_Model); defer free(m)
	page_lab_build(m, {})
	testing.expect(t, page_lab_validate(m))
	left, right, gap:=false, false, false
	for hinge in m.hinges[:m.hinge_count] {
		if hinge.surface!=.Hero { continue }
		mid:=(m.vertices[hinge.indices[0]].sheet+m.vertices[hinge.indices[1]].sheet)*.5
		left=left || mid.x<PAGE_LAB_HERO_ORIGIN.x-.08
		right=right || mid.x>PAGE_LAB_HERO_ORIGIN.x+.08
		gap=gap || abs(mid.x-PAGE_LAB_HERO_ORIGIN.x)<.08
	}
	testing.expect(t, left && right && !gap, "Two soles share the sheet, without a plate bridging them")
	// Every source cell has exactly one owner. No full floor is drawn under the lifted silhouette.
	page_area, flap_area:=f64(0), f64(0)
	for triangle in m.triangles[:m.triangle_count] {
		a,b,c:=m.vertices[triangle.indices[0]].sheet,m.vertices[triangle.indices[1]].sheet,m.vertices[triangle.indices[2]].sheet
		u,v:=b-a,c-a; area:=abs(f64(u.x*v.y-u.y*v.x))*.5
		if triangle.surface==.Page { page_area+=area } else { flap_area+=area }
	}
	testing.expect(t, flap_area>5 && page_area<192-5)
	testing.expect(t, abs(page_area+flap_area-192)<.01)
	// A point inside the chest's original sheet silhouette must belong to the chest, not to Page.
	point:=rl.Vector2{PAGE_LAB_OBJECT_ORIGIN.x, PAGE_LAB_OBJECT_ORIGIN.z-.4}
	for triangle in m.triangles[:m.triangle_count] {
		if triangle.surface!=.Page { continue }
		a,b,c:=m.vertices[triangle.indices[0]].sheet,m.vertices[triangle.indices[1]].sheet,m.vertices[triangle.indices[2]].sheet
		u,v,w:=b-a,c-a,point-a
		d:=u.x*v.y-u.y*v.x
		beta:=(w.x*v.y-w.y*v.x)/d; gamma:=(u.x*w.y-u.y*w.x)/d
		testing.expect(t, !(beta>.0001 && gamma>.0001 && beta+gamma<.9999), "Page covers a cutout")
	}
}

@(test)
test_page_lab_bridge_and_roof_have_two_page_roots_and_open_arch :: proc(t: ^testing.T) {
	m:=new(Page_Lab_Model); defer free(m)
	page_lab_build(m, {})
	bridge_lo, bridge_hi, roof_lo, roof_hi:=false, false, false, false
	for hinge in m.hinges[:m.hinge_count] {
		p:=m.vertices[hinge.indices[0]].sheet
		if hinge.surface==.Bridge {
			bridge_lo=bridge_lo || p.y<PAGE_LAB_BRIDGE_ORIGIN.z
			bridge_hi=bridge_hi || p.y>PAGE_LAB_BRIDGE_ORIGIN.z
		}
		if hinge.surface==.Roof {
			roof_lo=roof_lo || p.x<PAGE_LAB_ROOF_ORIGIN.x
			roof_hi=roof_hi || p.x>PAGE_LAB_ROOF_ORIGIN.x
		}
	}
	testing.expect(t, bridge_lo && bridge_hi && roof_lo && roof_hi)
	testing.expect(t, !page_lab_shape({}, .Arch, {PAGE_LAB_ARCH_ORIGIN.x, PAGE_LAB_ARCH_ORIGIN.z-.8}), "The arch aperture is empty")
	testing.expect(t, page_lab_shape({}, .Arch, {PAGE_LAB_ARCH_ORIGIN.x+1.0, PAGE_LAB_ARCH_ORIGIN.z-.8}))
}

@(test)
test_page_lab_death_closes_exactly_into_its_cut_and_mount_stays_attached :: proc(t: ^testing.T) {
	m:=new(Page_Lab_Model); defer free(m)
	page_lab_build(m, {act=.Death, time=3})
	testing.expect(t, page_lab_validate(m))
	for triangle in m.triangles[:m.triangle_count] {
		if triangle.surface!=.Hero { continue }
		for id in triangle.indices {
			v:=m.vertices[id]
			testing.expect(t, abs(v.position.y)<.0001 && abs(v.position.x-v.sheet.x)<.0001 && abs(v.position.z-v.sheet.y)<.0001)
		}
	}
	page_lab_build(m, {act=.Mount, time=2})
	testing.expect(t, page_lab_validate(m))
	contacts:=0
	for hinge in m.hinges[:m.hinge_count] { if hinge.surface==.Hero { contacts+=1 } }
	testing.expect(t, contacts>=4)
}

@(test)
test_page_lab_climb_uses_real_level_ramp_and_rebuild_is_repeatable :: proc(t: ^testing.T) {
	m:=new(Page_Lab_Model); defer free(m)
	pose:=Page_Lab_Pose{act=.Climb, time=2}
	anchor:=page_lab_hero_anchor(pose)
	testing.expect(t, abs(anchor.x-6.5)<.0001 && abs(anchor.y-.24)<.0001)
	page_lab_build(m, pose)
	testing.expect(t, page_lab_validate(m))
	vertices, triangles, hinges, cuts:=m.vertex_count,m.triangle_count,m.hinge_count,m.cut_edge_count
	first:=m.vertices[0]
	page_lab_build(m, {act=.Walk, time=.63})
	page_lab_build(m, pose)
	testing.expect_value(t, m.vertex_count, vertices); testing.expect_value(t, m.triangle_count, triangles)
	testing.expect_value(t, m.hinge_count, hinges); testing.expect_value(t, m.cut_edge_count, cuts)
	testing.expect_value(t, m.vertices[0], first)
	for hinge in m.hinges[:m.hinge_count] {
		for id in hinge.indices {
			v:=m.vertices[id]
			testing.expect(t, abs(v.position.y-page_lab_ground_height(pose, {v.position.x,v.position.z}))<.0001)
		}
	}
}

@(test)
test_page_lab_validation_rejects_broken_indices_and_nonfinite_input :: proc(t: ^testing.T) {
	m:=new(Page_Lab_Model); defer free(m)
	page_lab_build(m, {})
	testing.expect(t, page_lab_validate(m))
	m.triangles[0].indices[0]=u32(m.vertex_count)
	testing.expect(t, !page_lab_validate(m))
	page_lab_build(m, {time=math.INF_F32})
	testing.expect(t, m.overflow && !page_lab_validate(m))
}

@(test)
test_page_lab_print_does_not_change_color_across_quad_diagonals :: proc(t: ^testing.T) {
	m := new(Page_Lab_Model); defer free(m)
	page_lab_build(m, {})
	i := 0
	for i < m.triangle_count {
		a := m.triangles[i]
		if a.surface == .Page || a.surface == .Bridge || a.surface == .Roof { i += 1; continue }
		testing.expect(t, i+1 < m.triangle_count)
		b := m.triangles[i+1]
		testing.expect_value(t, a.surface, b.surface)
		testing.expect_value(t, a.front, b.front)
		testing.expect_value(t, a.back, b.back)
		i += 2
	}
}

@(test)
test_page_lab_climb_end_keeps_each_cut_connected_to_its_own_roots :: proc(t: ^testing.T) {
	m := new(Page_Lab_Model); defer free(m)
	page_lab_build(m, {act = .Climb, time = 4})
	page_lab_test_sheet_details(t, m)
}

@(private)
page_lab_test_sheet_details :: proc(t: ^testing.T, m: ^Page_Lab_Model) {
	testing.expect(t, !m.overflow)
	for i in 0..<m.vertex_count { m.parents[i] = u32(i) }
	for triangle, index in m.triangles[:m.triangle_count] {
		ids := triangle.indices
		for id in ids {
			vertex := m.vertices[id]
			expected := page_lab_position(m.pose, triangle.surface, vertex.sheet)
			testing.expectf(t, rl.Vector3DistanceSqr(vertex.position, expected) < 1e-10,
				"Triangle %d (%v) shares another flap's vertex %d at %v: got %v, expected %v",
				index, triangle.surface, id, vertex.sheet, vertex.position, expected)
		}
		a, b, c := m.vertices[ids[0]], m.vertices[ids[1]], m.vertices[ids[2]]
		cross := rl.Vector3CrossProduct(b.position-a.position, c.position-a.position)
		testing.expectf(t, rl.Vector3LengthSqr(cross) >= 1e-14, "Degenerate triangle %d (%v), sheet %v %v %v", index, triangle.surface, a.sheet, b.sheet, c.sheet)
		root := page_lab_find(m, ids[0])
		m.parents[page_lab_find(m, ids[1])] = root
		m.parents[page_lab_find(m, ids[2])] = root
	}
	root := page_lab_find(m, 0)
	for vertex, i in m.vertices[:m.vertex_count] {
		testing.expectf(t, page_lab_find(m, u32(i)) == root, "Detached vertex %d at sheet %v, position %v, component %d", i, vertex.sheet, vertex.position, page_lab_find(m, u32(i)))
	}
	testing.expectf(t, page_lab_validate(m), "%v %.6f is a single cut sheet (vertices %d, triangles %d, hinges %d, axes %d/%d)", m.pose.act, m.pose.time, m.vertex_count, m.triangle_count, m.hinge_count, m.x_count, m.y_count)
}

@(test)
test_page_lab_native_capture_poses_and_every_act_frame_keep_one_sheet :: proc(t: ^testing.T) {
	m := new(Page_Lab_Model); defer free(m)
	// The 25 poses from PAGE_LAB_SHOTS, including exact times between the
	// original coarse samples. Camera/print-only variants share a sheet pose.
	poses := [?]Page_Lab_Pose{
		{}, {}, {act = .Walk, time = .7}, {act = .Walk, time = .7},
		{act = .Turn, time = 1.3}, {act = .Climb, time = 2.5}, {act = .Climb, time = 2.5},
		{act = .Mount, time = 2}, {act = .Death, time = 1.4}, {act = .Death, time = 3.2},
		{act = .Arrow, time = 1.4}, {act = .Bomb, time = 1.4}, {act = .Flight, time = 1.4},
		{}, {}, {}, {}, {act = .Walk, time = .7}, {act = .Walk, time = .7}, {}, {}, {}, {}, {}, {},
	}
	#assert(len(poses) == 25)
	diagnosed := false
	for pose, i in poses {
		page_lab_build(m, pose)
		valid := page_lab_validate(m)
		testing.expectf(t, valid, "Native shot %d: %v %.6f breaks the sheet (overflow=%v)", i, pose.act, pose.time, m.overflow)
		if !valid && !diagnosed { page_lab_test_sheet_details(t, m); diagnosed = true }
	}
	for act in Page_Lab_Act {
		for frame in 0..<240 {
			pose := Page_Lab_Pose{act = act, time = f32(frame)/60}
			page_lab_build(m, pose)
			valid := page_lab_validate(m)
			testing.expectf(t, valid, "Continuous act %v frame %d, time %.6f breaks the sheet (overflow=%v)", act, frame, pose.time, m.overflow)
			if !valid && !diagnosed { page_lab_test_sheet_details(t, m); diagnosed = true }
		}
	}
}

@(test)
test_page_lab_enclosed_blank_stock_joins_only_its_own_cutout :: proc(t: ^testing.T) {
	m := new(Page_Lab_Model); defer free(m)
	m.x_count = 6; m.y_count = 6
	for y in 1..=3 { for x in 1..=3 { m.cells[y*PAGE_LAB_AXIS_X+x] = .Enemy } }
	m.cells[2*PAGE_LAB_AXIS_X+2] = .Page
	page_lab_close_enclosed_stock(m)
	testing.expect(t, !m.overflow)
	testing.expect_value(t, page_lab_cell(m, 2, 2), Page_Lab_Surface.Enemy)
	testing.expect_value(t, page_lab_cell(m, 0, 2), Page_Lab_Surface.Page)
	// A channel to the sheet boundary is a real cut aperture and stays open.
	m.cells[2*PAGE_LAB_AXIS_X+1] = .Page
	m.cells[2*PAGE_LAB_AXIS_X+2] = .Page
	page_lab_close_enclosed_stock(m)
	testing.expect(t, !m.overflow)
	testing.expect_value(t, page_lab_cell(m, 2, 2), Page_Lab_Surface.Page)
	// A trapped piece between two silhouettes is a layout error, never a weld.
	m.cells[2*PAGE_LAB_AXIS_X+1] = .Hero
	page_lab_close_enclosed_stock(m)
	testing.expect(t, m.overflow)
}

@(test)
test_page_lab_climb_keeps_animated_cutouts_separate_in_the_source_page :: proc(t: ^testing.T) {
	m := new(Page_Lab_Model); defer free(m)
	for step in 0..=16 {
		page_lab_build(m, {act = .Climb, time = f32(step)*.25})
		testing.expectf(t, page_lab_validate(m), "Climb %.2f is one sheet", m.pose.time)
		for y in 0..<m.y_count-1 { for x in 0..<m.x_count-1 {
			surface := page_lab_cell(m, x, y)
			if surface == .Page { continue }
			// Even a shared corner would weld independent silhouettes. This
			// includes the enemy's head beside Flight and its arm beside Object.
			for dy in -1..=1 { for dx in -1..=1 {
				neighbour := page_lab_cell(m, x+dx, y+dy)
				testing.expectf(t, neighbour == .Page || neighbour == surface,
					"Climb %.2f: %v touches %v at sheet (%f, %f)", m.pose.time, surface, neighbour, m.xs[x], m.ys[y])
			} }
		} }
	}
}

@(test)
test_page_lab_conflicting_cutout_nodes_are_rejected_instead_of_welded :: proc(t: ^testing.T) {
	m := new(Page_Lab_Model); defer free(m)
	m.xs[0] = 9; m.ys[0] = 4
	page_lab_vertex(m, 0, 0, .Hero)
	testing.expect(t, !m.overflow)
	page_lab_vertex(m, 0, 0, .Enemy)
	testing.expect(t, m.overflow, "Independent cutouts cannot share the same flap vertex slot")
}
