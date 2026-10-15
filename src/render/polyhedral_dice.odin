package render

import "core:math"
import rl "vendor:raylib"

// Tabletop geometry: the five Platonic solids and the ten congruent kites of
// a pentagonal trapezohedron. D100 is the tens die of the percentile pair.
Polyhedral_Die_Kind :: enum { D4, D6, D8, D10, D100, D12, D20, Count }
POLYHEDRAL_MAX_VERTICES :: 20
POLYHEDRAL_MAX_FACES :: 20
POLYHEDRAL_MAX_TRIANGLES :: 200
POLYHEDRAL_BEVEL :: f32(0.065)
Polyhedral_Face :: struct {
	vertices: [5]int,
	count: int,
	center, normal, u, v: rl.Vector3,
	value: i32,
}
Polyhedral_Die :: struct {
	kind: Polyhedral_Die_Kind,
	vertices: [POLYHEDRAL_MAX_VERTICES]rl.Vector3,
	vertex_count: int,
	faces: [POLYHEDRAL_MAX_FACES]Polyhedral_Face,
	face_count: int,
	triangles: [POLYHEDRAL_MAX_TRIANGLES]Dice_Mesh_Triangle,
	triangle_bevel: [POLYHEDRAL_MAX_TRIANGLES]bool,
	triangle_count: int,
}

polyhedral_die_for_sides :: proc(sides: int) -> Polyhedral_Die_Kind {
	switch sides {
	case 4: return .D4
	case 8: return .D8
	case 10: return .D10
	case 100: return .D100
	case 12: return .D12
	case 20: return .D20
	}
	return .D6
}

polyhedral_die_name :: proc(kind: Polyhedral_Die_Kind) -> cstring {
	switch kind {
	case .D4: return "D4"
	case .D6: return "D6"
	case .D8: return "D8"
	case .D10: return "D10"
	case .D100: return "D%"
	case .D12: return "D12"
	case .D20: return "D20"
	case .Count: return "?"
	}
	unreachable()
}

polyhedral_add_vertex :: proc(die: ^Polyhedral_Die, vertex: rl.Vector3) {
	assert(die.vertex_count < len(die.vertices))
	die.vertices[die.vertex_count] = vertex
	die.vertex_count += 1
}

polyhedral_sort_polygon :: proc(points: []rl.Vector3, center, normal: rl.Vector3) {
	u := rl.Vector3Normalize(points[0]-center)
	v := rl.Vector3CrossProduct(normal, u)
	for i in 1..<len(points) {
		point := points[i]
		angle := math.atan2(rl.Vector3DotProduct(point-center, v), rl.Vector3DotProduct(point-center, u))
		j := i
		for j > 0 {
			previous := points[j-1]-center
			if math.atan2(rl.Vector3DotProduct(previous, v), rl.Vector3DotProduct(previous, u)) <= angle {break}
			points[j], j = points[j-1], j-1
		}
		points[j] = point
	}
}

// Convex face extraction runs only during creation; coplanar supporting planes
// are merged into one polygon, so D10 stays ten kites, not twenty triangles.
polyhedral_build_faces :: proc(die: ^Polyhedral_Die) {
	epsilon :: f32(0.0001)
	for a in 0..<die.vertex_count-2 {
		for b in a+1..<die.vertex_count-1 {
			for c in b+1..<die.vertex_count {
				pa, pb, pc := die.vertices[a], die.vertices[b], die.vertices[c]
				cross := rl.Vector3CrossProduct(pb-pa, pc-pa)
				if rl.Vector3Length(cross) < epsilon {continue}
				n := rl.Vector3Normalize(cross)
				if rl.Vector3DotProduct(n, pa) < 0 {n = -n}
				distance := rl.Vector3DotProduct(n, pa)
				supporting := true
				for point in die.vertices[:die.vertex_count] {
					if rl.Vector3DotProduct(n, point)-distance > epsilon {supporting = false; break}
				}
				if !supporting {continue}
				duplicate := false
				for face in die.faces[:die.face_count] {
					if rl.Vector3DotProduct(n, face.normal) > 1-epsilon {duplicate = true; break}
				}
				if duplicate {continue}
				assert(die.face_count < len(die.faces))
				face := &die.faces[die.face_count]
				face.normal = n
				points: [5]rl.Vector3
				for point in die.vertices[:die.vertex_count] {
					if abs(rl.Vector3DotProduct(n, point)-distance) < epsilon {
						assert(face.count < len(points))
						points[face.count] = point
						face.center += point
						face.count += 1
					}
				}
				face.center /= f32(face.count)
				polyhedral_sort_polygon(points[:face.count], face.center, n)
				for point, index in points[:face.count] {
					for vertex, vertex_index in die.vertices[:die.vertex_count] {
						if point == vertex {face.vertices[index] = vertex_index; break}
					}
				}
				// A corner points to the top of each triangular/pentagonal label;
				// on the trapezohedron the pole is its unmistakable long corner.
				up_index := 0
				if die.kind == .D10 || die.kind == .D100 {
					for vertex_index, index in face.vertices[:face.count] {
						if abs(die.vertices[vertex_index].y) > abs(points[up_index].y) {up_index = index}
					}
				}
				face.v = rl.Vector3Normalize(points[up_index]-face.center)
				if die.kind == .D6 {face.v = rl.Vector3Normalize(points[1]-points[0])}
				face.u = rl.Vector3CrossProduct(face.v, n)
				die.face_count += 1
			}
		}
	}
}

polyhedral_assign_numbers :: proc(die: ^Polyhedral_Die) {
	if die.kind == .D4 {
		// Face values identify the opposite vertex; visible labels instead use
		// the three vertices on that face (top-read tetrahedral numbering).
		for &face in die.faces[:die.face_count] {
			for vertex in 0..<4 {
				included := false
				for index in face.vertices[:face.count] {if index == vertex {included = true}}
				if !included {face.value = i32(vertex+1)}
			}
		}
		return
	}
	assigned: [POLYHEDRAL_MAX_FACES]bool
	next := i32(1)
	for &face, index in die.faces[:die.face_count] {
		if assigned[index] {continue}
		other := -1
		for opposite, other_index in die.faces[:die.face_count] {
			if rl.Vector3DotProduct(face.normal, opposite.normal) < -0.999 {other = other_index; break}
		}
		assert(other >= 0)
		low, high := next, i32(die.face_count)+1-next
		if die.kind == .D10 || die.kind == .D100 {
			low, high = next-1, 10-next
			if die.kind == .D100 {low *= 10; high *= 10}
			if die.kind == .D10 && low == 0 {low = 10}
		}
		face.value, die.faces[other].value = low, high
		assigned[index], assigned[other] = true, true
		next += 1
	}
}

polyhedral_inset_vertex :: proc(die: ^Polyhedral_Die, face: Polyhedral_Face, index: int) -> rl.Vector3 {
	return die.vertices[index]*(1-POLYHEDRAL_BEVEL)+face.center*POLYHEDRAL_BEVEL
}

polyhedral_add_triangle :: proc(die: ^Polyhedral_Die, a, b, c: rl.Vector3, bevel: bool) {
	assert(die.triangle_count < len(die.triangles))
	normal := rl.Vector3Normalize(rl.Vector3CrossProduct(b-a, c-a))
	points := [3]rl.Vector3{a, b, c}
	if rl.Vector3DotProduct(normal, (a+b+c)/3) < 0 {points[1], points[2] = points[2], points[1]; normal = -normal}
	die.triangles[die.triangle_count] = {points = points, normal = normal}
	die.triangle_bevel[die.triangle_count] = bevel
	die.triangle_count += 1
}

polyhedral_bevel_mesh :: proc(die: ^Polyhedral_Die) {
	for face, face_index in die.faces[:die.face_count] {
		a := polyhedral_inset_vertex(die, face, face.vertices[0])
		for index in 1..<face.count-1 {
			polyhedral_add_triangle(die, a, polyhedral_inset_vertex(die, face, face.vertices[index]),
				polyhedral_inset_vertex(die, face, face.vertices[index+1]), false)
		}
		for index in 0..<face.count {
			va, vb := face.vertices[index], face.vertices[(index+1)%face.count]
			for other in die.faces[face_index+1:die.face_count] {
				has_a, has_b := false, false
				for other_vertex in 0..<other.count {
					vertex := other.vertices[other_vertex]
					has_a = has_a || vertex == va; has_b = has_b || vertex == vb
				}
				if !has_a || !has_b {continue}
				p, q := polyhedral_inset_vertex(die, face, va), polyhedral_inset_vertex(die, face, vb)
				r, s := polyhedral_inset_vertex(die, other, vb), polyhedral_inset_vertex(die, other, va)
				polyhedral_add_triangle(die, p, q, r, true)
				polyhedral_add_triangle(die, p, r, s, true)
			}
		}
	}
	for vertex, vertex_index in die.vertices[:die.vertex_count] {
		points: [5]rl.Vector3
		count := 0
		center := rl.Vector3{}
		for face in die.faces[:die.face_count] {
			for face_vertex in 0..<face.count {
				if face.vertices[face_vertex] != vertex_index {continue}
				points[count] = polyhedral_inset_vertex(die, face, vertex_index)
				center += points[count]
				count += 1
			}
		}
		center /= f32(count)
		polyhedral_sort_polygon(points[:count], center, rl.Vector3Normalize(vertex))
		for index in 1..<count-1 {polyhedral_add_triangle(die, points[0], points[index], points[index+1], true)}
	}
}

build_polyhedral_die :: proc(kind: Polyhedral_Die_Kind) -> (die: Polyhedral_Die) {
	die.kind = kind
	phi := (1+math.sqrt(f32(5)))/2
	switch kind {
	case .D4:
		for point in ([4]rl.Vector3{{1,1,1},{1,-1,-1},{-1,1,-1},{-1,-1,1}}) {
			polyhedral_add_vertex(&die, rl.Vector3Normalize(point)*0.79)
		}
	case .D6:
		for x in ([2]f32{-0.5,0.5}) {for y in ([2]f32{-0.5,0.5}) {for z in ([2]f32{-0.5,0.5}) {
			polyhedral_add_vertex(&die, {x,y,z})
		}}}
	case .D8:
		for axis in 0..<3 {for sign in ([2]f32{-1,1}) {
			point := rl.Vector3{}; point[axis] = sign*0.78; polyhedral_add_vertex(&die, point)
		}}
	case .D10, .D100:
		pole: f32 = 0.82
		ring: f32 = 0.68
		twist := math.cos(math.PI/f32(5))
		height := pole*(1-twist)/(1+twist)
		polyhedral_add_vertex(&die, {0,pole,0})
		polyhedral_add_vertex(&die, {0,-pole,0})
		for index in 0..<10 {
			angle := f32(index)*math.PI/5
			polyhedral_add_vertex(&die, {ring*math.cos(angle), height*(1 if index%2 == 0 else -1), ring*math.sin(angle)})
		}
	case .D12:
		for x in ([2]f32{-1,1}) {for y in ([2]f32{-1,1}) {for z in ([2]f32{-1,1}) {
			polyhedral_add_vertex(&die, rl.Vector3{x,y,z}*(0.79/math.sqrt(f32(3))))
		}}}
		for axis in 0..<3 {for a in ([2]f32{-1,1}) {for b in ([2]f32{-1,1}) {
			point := rl.Vector3{}; point[(axis+1)%3] = a/phi; point[(axis+2)%3] = b*phi
			polyhedral_add_vertex(&die, rl.Vector3Normalize(point)*0.79)
		}}}
	case .D20:
		for axis in 0..<3 {for a in ([2]f32{-1,1}) {for b in ([2]f32{-1,1}) {
			point := rl.Vector3{}; point[(axis+1)%3] = a; point[(axis+2)%3] = b*phi
			polyhedral_add_vertex(&die, rl.Vector3Normalize(point)*0.8)
		}}}
	case .Count: return
	}
	polyhedral_build_faces(&die)
	polyhedral_assign_numbers(&die)
	polyhedral_bevel_mesh(&die)
	return
}

polyhedral_face_for_result :: proc(die: ^Polyhedral_Die, result: i32) -> int {
	for face, index in die.faces[:die.face_count] {if face.value == result {return index}}
	return 0
}

// Numbering belongs to the solid permanently. Only its orientation changes to
// present the already committed game result. The final pose has a flat base.
polyhedral_result_orientation :: proc(die: ^Polyhedral_Die, result: i32) -> rl.Quaternion {
	if die == nil || die.face_count == 0 {return rl.Quaternion(1)}
	if die.kind == .D4 {
		vertex := die.vertices[clamp(int(result)-1,0,3)]
		rotation := rl.QuaternionFromVector3ToVector3(rl.Vector3Normalize(vertex), {0,1,0})
		// Show two slopes at rest so the apex-read tetrahedron keeps its depth.
		for face in die.faces[:die.face_count] {
			if face.value == result {continue}
			n := rl.Vector3RotateByQuaternion(face.normal, rotation)
			yaw := math.atan2(n.x, n.z)
			return rl.QuaternionFromAxisAngle({0,1,0}, math.PI*32/180-yaw)*rotation
		}
		return rotation
	}
	face := die.faces[polyhedral_face_for_result(die, result)]
	rotation := rl.QuaternionFromVector3ToVector3(face.normal, {0,1,0})
	up := rl.Vector3RotateByQuaternion(face.v, rotation)
	// On the top face the number reads up-screen, toward the back of the tray.
	yaw := math.atan2(up.x, up.z)
	return rl.QuaternionFromAxisAngle({0,1,0}, math.PI-yaw)*rotation
}

polyhedral_support_height :: proc(die: ^Polyhedral_Die, rotation: rl.Quaternion) -> (height: f32) {
	if die == nil {return}
	for triangle in die.triangles[:die.triangle_count] {
		for point in triangle.points {height = max(height, -rl.Vector3RotateByQuaternion(point, rotation).y)}
	}
	return
}

// A face's figures. The set's D10 reads 0-9, its 0 the 10, as the dice-set lab
// shows it; with `values` (the dice thrown in play) the 10 reads 10, as the
// cards name that face.
polyhedral_face_label :: proc(die: ^Polyhedral_Die, face: Polyhedral_Face, values := false) -> (digits: [2]int, count: int) {
	value := face.value
	if die.kind == .D10 && value == 10 && !values {value = 0}
	if die.kind == .D100 || value >= 10 {return {int(value/10), int(value%10)}, 2}
	return {int(value), 0}, 1
}
