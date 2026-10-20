package render

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

DICE_BEVEL :: f32(0.08)
DICE_BODY_TRIANGLES :: 44
DICE_BODY_COLOR :: rl.Color{235, 38, 43, 255}
DICE_PIP_COLOR :: rl.Color{8, 8, 10, 255}
DICE_VIEW_DIRECTION :: rl.Vector3{0, 0.8, 0.6}
DICE_SCREEN_UP :: rl.Vector3{0, 0.6, -0.8}

Dice_Mesh_Triangle :: struct {points: [3]rl.Vector3, normal: rl.Vector3}
Dice_Bevel_Mesh :: struct {triangles: [DICE_BODY_TRIANGLES]Dice_Mesh_Triangle, count: int}

@(private = "file")
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

@(private)
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

@(private = "file")
dice_mesh_triangle :: proc(mesh: ^Dice_Bevel_Mesh, a, b, c, outward: rl.Vector3) {
	assert(mesh.count < len(mesh.triangles))
	normal := rl.Vector3Normalize(rl.Vector3CrossProduct(b-a, c-a))
	points := [3]rl.Vector3{a, b, c}
	if rl.Vector3DotProduct(normal, outward) < 0 {points[1], points[2] = points[2], points[1]; normal = -normal}
	mesh.triangles[mesh.count] = {points = points, normal = normal}
	mesh.count += 1
}

@(private = "file")
dice_mesh_quad :: proc(mesh: ^Dice_Bevel_Mesh, a, b, c, d, normal: rl.Vector3) {
	dice_mesh_triangle(mesh, a, b, c, normal)
	dice_mesh_triangle(mesh, a, c, d, normal)
}

// Closed geometry: six inset squares, twelve edge bevels, eight corner bevels.
// Built once, then transformed without allocating memory during playback.
@(private)
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

// The canonical polyhedron's material coordinates and transformed vertex.
@(private)
resin_die_vertex :: proc(local, position: rl.Vector3, orientation: rl.Quaternion) {
	world := rl.Vector3RotateByQuaternion(local, orientation)+position
	rlgl.TexCoord2f(local.x+local.z+0.5, local.y+local.z*0.5+0.5)
	rlgl.Vertex3f(world.x, world.y, world.z)
}
