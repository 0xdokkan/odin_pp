package gfx

import "core:testing"
import physics "../physics"

@(test)
test_face_count_hides_shared_faces :: proc(t: ^testing.T) {
	m, _ := physics.voxel_map_create(4, 4, 4, 1)
	defer physics.voxel_map_destroy(&m)
	physics.voxel_set(&m, 1, 1, 1, 1)
	testing.expect_value(t, count_voxel_faces(&m).faces, 6)
	physics.voxel_set(&m, 2, 1, 1, 1)
	testing.expect_value(t, count_voxel_faces(&m).faces, 10)
}

@(test)
test_closed_maps_skip_the_outer_shell :: proc(t: ^testing.T) {
	m, _ := physics.voxel_map_create(2, 1, 1, 1, outside = 1)
	defer physics.voxel_map_destroy(&m)
	physics.voxel_set(&m, 0, 0, 0, 1)
	// Only the face toward the empty neighbour is visible.
	testing.expect_value(t, count_voxel_faces(&m).faces, 1)
}

@(test)
test_face_winding_points_outward :: proc(t: ^testing.T) {
	for face in 0..<6 {
		corners := face_corners(face, {0, 0, 0}, 1)
		e1 := corners[1] - corners[0]
		e2 := corners[2] - corners[0]
		n := Vec3{e1.y*e2.z - e1.z*e2.y, e1.z*e2.x - e1.x*e2.z, e1.x*e2.y - e1.y*e2.x}
		d := face_offset(face)
		dot := n.x*f32(d.x) + n.y*f32(d.y) + n.z*f32(d.z)
		testing.expectf(t, dot > 0, "face %v winds inward", face)
	}
}

@(test)
test_anim_frame_loops_and_clamps :: proc(t: ^testing.T) {
	testing.expect_value(t, anim_frame(1.25, 4, 2, 3), 2+5%3)
	testing.expect_value(t, anim_frame(10, 4, 0, 3, loop = false), 2)
	testing.expect_value(t, anim_frame(10, 4, 7, 1), 7)
}

@(test)
test_wall_uvs_stand_upright :: proc(t: ^testing.T) {
	for face in ([4]int{0, 1, 4, 5}) {
		testing.expect_value(t, face_uv(face, {0, 1, 0})[1], f32(0))
		testing.expect_value(t, face_uv(face, {0, 0, 0})[1], f32(1))
	}
	testing.expect_value(t, face_uv(2, {1, 1, 0}), [2]f32{1, 0})
}
