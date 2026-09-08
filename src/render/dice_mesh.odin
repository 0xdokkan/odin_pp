package render

import "core:math"
import rl "vendor:raylib"

DICE_BEVEL :: f32(0.08)
DICE_BODY_TRIANGLES :: 44
DICE_PIP_SEGMENTS :: 16
DICE_BODY_COLOR :: rl.Color{235, 38, 43, 255}
DICE_PIP_COLOR :: rl.Color{8, 8, 10, 255}
DICE_VIEW_DIRECTION :: rl.Vector3{0, 0.8, 0.6}
DICE_SCREEN_UP :: rl.Vector3{0, 0.6, -0.8}

Dice_Mesh_Triangle :: struct {points: [3]rl.Vector3, normal: rl.Vector3}
Dice_Bevel_Mesh :: struct {triangles: [DICE_BODY_TRIANGLES]Dice_Mesh_Triangle, count: int}
Dice_Numbering :: struct {values: [6]i32, u, v: [6]rl.Vector3, dominant_face: int}

dice_face_basis :: proc(face: i32) -> (normal, u, v: rl.Vector3) {
	switch clamp(face, i32(1), i32(6)) {
	case 1: return {0, 0, 1}, {1, 0, 0}, {0, 1, 0}
	case 2: return {1, 0, 0}, {0, 0, -1}, {0, 1, 0}
	case 3: return {0, 1, 0}, {1, 0, 0}, {0, 0, -1}
	case 4: return {0, -1, 0}, {1, 0, 0}, {0, 0, 1}
	case 5: return {-1, 0, 0}, {0, 0, 1}, {0, 1, 0}
	case 6: return {0, 0, -1}, {-1, 0, 0}, {0, 1, 0}
	}
	unreachable()
}

dice_pip_positions :: proc(raw_face: i32) -> (positions: [6]rl.Vector2, count: int) {
	face := clamp(raw_face, i32(1), i32(6))
	s: f32 = 0.23
	switch face {
	case 1: positions[0] = {0, 0}
	case 2, 3:
		positions[0], positions[1] = {-s, s}, {s, -s}
		positions[2] = {0, 0}
	case 4, 5:
		positions[0], positions[1] = {-s, s}, {s, -s}
		positions[2], positions[3] = {s, s}, {-s, -s}
		positions[4] = {0, 0}
	case 6:
		positions[0], positions[1] = {-s, s}, {s, -s}
		positions[2], positions[3] = {s, s}, {-s, -s}
		positions[4], positions[5] = {-s, 0}, {s, 0}
	}
	return positions, int(face)
}

dice_mesh_triangle :: proc(mesh: ^Dice_Bevel_Mesh, a, b, c, outward: rl.Vector3) {
	assert(mesh.count < len(mesh.triangles))
	normal := rl.Vector3Normalize(rl.Vector3CrossProduct(b-a, c-a))
	points := [3]rl.Vector3{a, b, c}
	if rl.Vector3DotProduct(normal, outward) < 0 {points[1], points[2] = points[2], points[1]; normal = -normal}
	mesh.triangles[mesh.count] = {points = points, normal = normal}
	mesh.count += 1
}

dice_mesh_quad :: proc(mesh: ^Dice_Bevel_Mesh, a, b, c, d, normal: rl.Vector3) {
	dice_mesh_triangle(mesh, a, b, c, normal)
	dice_mesh_triangle(mesh, a, c, d, normal)
}

// Closed geometry: six inset squares, twelve edge bevels, eight corner bevels.
// Built once, then transformed without allocating memory during playback.
build_dice_bevel_mesh :: proc() -> (mesh: Dice_Bevel_Mesh) {
	h := f32(0.5)-DICE_BEVEL
	for face in i32(1)..=6 {
		n, u, v := dice_face_basis(face)
		center := n*0.5
		dice_mesh_quad(&mesh, center-u*h-v*h, center+u*h-v*h, center+u*h+v*h, center-u*h+v*h, n)
	}
	for a in 0..<3 {
		for b in a+1..<3 {
			along := 3-a-b
			for sa in ([2]f32{-1, 1}) {
				for sb in ([2]f32{-1, 1}) {
					p, q: rl.Vector3
					p[a], p[b], p[along] = sa*0.5, sb*h, -h
					q[a], q[b], q[along] = sa*h, sb*0.5, -h
					r, s := q, p
					r[along], s[along] = h, h
					n := rl.Vector3{}
					n[a], n[b] = sa, sb
					dice_mesh_quad(&mesh, p, q, r, s, n)
				}
			}
		}
	}
	for x in ([2]f32{-1, 1}) {
		for y in ([2]f32{-1, 1}) {
			for z in ([2]f32{-1, 1}) {
				dice_mesh_triangle(&mesh, {x*0.5, y*h, z*h}, {x*h, y*0.5, z*h}, {x*h, y*h, z*0.5}, {x, y, z})
			}
		}
	}
	return
}

dice_rotate_numbering_basis :: proc(vector, sn, su, sv, tn, tu, tv: rl.Vector3) -> rl.Vector3 {
	return tn*rl.Vector3DotProduct(vector, sn)+tu*rl.Vector3DotProduct(vector, su)+tv*rl.Vector3DotProduct(vector, sv)
}

// A proper rotation of the entire numbering, chosen before playback from the
// final orientation. Opposites and pip tangent axes stay fixed throughout flight.
dice_numbering_for_result :: proc(final_orientation: rl.Quaternion, result: i32) -> (numbering: Dice_Numbering) {
	best := f32(-2)
	for face in i32(1)..=6 {
		n, _, _ := dice_face_basis(face)
		score := rl.Vector3DotProduct(rl.Vector3RotateByQuaternion(n, final_orientation), DICE_VIEW_DIRECTION)
		if score > best {best, numbering.dominant_face = score, int(face)-1}
	}
	sn, su, sv := dice_face_basis(result)
	tn, tu, tv := dice_face_basis(i32(numbering.dominant_face+1))
	for value in i32(1)..=6 {
		n, u, v := dice_face_basis(value)
		nn := dice_rotate_numbering_basis(n, sn, su, sv, tn, tu, tv)
		uu := dice_rotate_numbering_basis(u, sn, su, sv, tn, tu, tv)
		vv := dice_rotate_numbering_basis(v, sn, su, sv, tn, tu, tv)
		for face in i32(1)..=6 {
			physical_n, _, _ := dice_face_basis(face)
			if rl.Vector3DotProduct(physical_n, nn) > 0.99 {
				numbering.values[face-1], numbering.u[face-1], numbering.v[face-1] = value, uu, vv
				break
			}
		}
	}
	return
}

dice_lit_face_color :: proc(normal: rl.Vector3) -> rl.Color {
	light := rl.Vector3Normalize(rl.Vector3{-0.45, 0.82, 0.35})
	diffuse := max(f32(0), rl.Vector3DotProduct(normal, light))
	reflection := normal*(2*rl.Vector3DotProduct(normal, light))-light
	specular := math.pow(max(f32(0), rl.Vector3DotProduct(reflection, DICE_VIEW_DIRECTION)), f32(18))*0.24
	brightness := 0.62+diffuse*0.38
	return {u8(min(f32(255), 235*brightness+255*specular)), u8(min(f32(255), 38*brightness+190*specular)),
		u8(min(f32(255), 43*brightness+190*specular)), 255}
}

draw_dice_mesh :: proc(mesh: ^Dice_Bevel_Mesh, position: rl.Vector3, orientation: rl.Quaternion, numbering: ^Dice_Numbering) {
	for triangle in mesh.triangles[:mesh.count] {
		normal := rl.Vector3RotateByQuaternion(triangle.normal, orientation)
		a := rl.Vector3RotateByQuaternion(triangle.points[0], orientation)+position
		b := rl.Vector3RotateByQuaternion(triangle.points[1], orientation)+position
		c := rl.Vector3RotateByQuaternion(triangle.points[2], orientation)+position
		rl.DrawTriangle3D(a, b, c, dice_lit_face_color(normal))
	}
	for face in 0..<6 {
		normal, _, _ := dice_face_basis(i32(face+1))
		u, v := numbering.u[face], numbering.v[face]
		pips, count := dice_pip_positions(numbering.values[face])
		for pip in pips[:count] {
			center := normal*0.502+u*pip.x+v*pip.y
			world := rl.Vector3RotateByQuaternion(center, orientation)+position
			for segment in 0..<DICE_PIP_SEGMENTS {
				a, b := f32(segment)*2*math.PI/DICE_PIP_SEGMENTS, f32(segment+1)*2*math.PI/DICE_PIP_SEGMENTS
				va, vb := center+(u*math.cos(a)+v*math.sin(a))*0.068, center+(u*math.cos(b)+v*math.sin(b))*0.068
				rl.DrawTriangle3D(world, rl.Vector3RotateByQuaternion(va, orientation)+position,
					rl.Vector3RotateByQuaternion(vb, orientation)+position, DICE_PIP_COLOR)
			}
		}
	}
}
