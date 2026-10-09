package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"

@(test)
test_polyhedral_solids_have_canonical_faces_planarity_and_manifold_edges :: proc(t: ^testing.T) {
	face_counts := [Polyhedral_Die_Kind.Count]int{4,6,8,10,10,12,20}
	corner_counts := [Polyhedral_Die_Kind.Count]int{3,4,3,4,4,5,3}
	vertex_counts := [Polyhedral_Die_Kind.Count]int{4,8,6,12,12,20,12}
	for kind in Polyhedral_Die_Kind.D4..<Polyhedral_Die_Kind.Count {
		die := build_polyhedral_die(kind)
		testing.expect_value(t,die.face_count,face_counts[kind])
		testing.expect_value(t,die.vertex_count,vertex_counts[kind])
		edges: [POLYHEDRAL_MAX_VERTICES][POLYHEDRAL_MAX_VERTICES]int
		first_area: f32 = 0
		first_edge: f32 = 0
		for face in die.faces[:die.face_count] {
			testing.expect_value(t,face.count,corner_counts[kind])
			testing.expect(t,rl.Vector3DotProduct(face.normal,face.center)>0)
			testing.expect(t,abs(rl.Vector3Length(face.normal)-1)<0.0001)
			area: f32 = 0
			for index in 0..<face.count {
				a,b := face.vertices[index],face.vertices[(index+1)%face.count]
				pa,pb := die.vertices[a],die.vertices[b]
				testing.expect(t,abs(rl.Vector3DotProduct(pa-face.center,face.normal))<0.0001)
				testing.expect(t,rl.Vector3DotProduct(rl.Vector3CrossProduct(pa-face.center,pb-face.center),face.normal)>0)
				edges[min(a,b)][max(a,b)] += 1
				area += rl.Vector3Length(rl.Vector3CrossProduct(pa-face.center,pb-face.center))*0.5
				edge := rl.Vector3Distance(pa,pb)
				if first_edge == 0 {first_edge = edge}
				if kind != .D10 && kind != .D100 {testing.expect(t,abs(first_edge-edge)<0.0001)}
			}
			if first_area == 0 {first_area = area}
			testing.expect(t,abs(area-first_area)<0.0001,"All scoring faces must have equal area")
		}
		edge_count := 0
		for a in 0..<die.vertex_count {for b in a+1..<die.vertex_count {
			if edges[a][b] == 0 {continue}
			testing.expect_value(t,edges[a][b],2)
			edge_count += 1
		}}
		testing.expect_value(t,die.vertex_count-edge_count+die.face_count,2)
	}
}

@(test)
test_polyhedral_bevels_are_closed_outward_without_degenerate_triangles :: proc(t: ^testing.T) {
	for kind in Polyhedral_Die_Kind.D4..<Polyhedral_Die_Kind.Count {
		die := build_polyhedral_die(kind)
		vertices: [100]rl.Vector3
		vertex_count := 0
		edges: [100][100]int
		directions: [100][100]int
		for triangle in die.triangles[:die.triangle_count] {
			indices: [3]int
			for point,index in triangle.points {
				found := false
				for vertex,existing in vertices[:vertex_count] {
					if rl.Vector3Distance(vertex,point)<0.00001 {indices[index],found = existing,true; break}
				}
				if !found {indices[index] = vertex_count; vertices[vertex_count] = point; vertex_count += 1}
			}
			cross := rl.Vector3CrossProduct(triangle.points[1]-triangle.points[0],triangle.points[2]-triangle.points[0])
			testing.expect(t,rl.Vector3Length(cross)>0.00001)
			testing.expect(t,rl.Vector3DotProduct(cross,triangle.normal)>0)
			testing.expect(t,rl.Vector3DotProduct(triangle.normal,(triangle.points[0]+triangle.points[1]+triangle.points[2])/3)>0)
			for index in 0..<3 {
				a,b := indices[index],indices[(index+1)%3]
				edges[min(a,b)][max(a,b)] += 1
				directions[min(a,b)][max(a,b)] += 1 if a<b else -1
			}
		}
		edge_count := 0
		for a in 0..<vertex_count {for b in a+1..<vertex_count {
			if edges[a][b] == 0 {continue}
			testing.expect_value(t,edges[a][b],2)
			testing.expect_value(t,directions[a][b],0)
			edge_count += 1
		}}
		testing.expect_value(t,vertex_count-edge_count+die.triangle_count,2)
	}
}

@(test)
test_polyhedral_fixed_numbering_and_result_pose_never_repaint_faces :: proc(t: ^testing.T) {
	for kind in Polyhedral_Die_Kind.D4..<Polyhedral_Die_Kind.Count {
		die := build_polyhedral_die(kind)
		original := die
		seen: [100]int
		for face in die.faces[:die.face_count] {
			testing.expect(t,face.value>=0 && face.value<100)
			seen[face.value] += 1
		}
		for face in die.faces[:die.face_count] {
			testing.expect_value(t,seen[face.value],1)
			rotation := polyhedral_result_orientation(&die,face.value)
			support := polyhedral_support_height(&die,rotation)
			testing.expect(t,support>0.1 && support<1)
			contact_points := 0
			for triangle in die.triangles[:die.triangle_count] {for vertex in triangle.points {
				world := rl.Vector3RotateByQuaternion(vertex,rotation)
				testing.expect(t,world.y+support>=-0.00001)
				if abs(world.y+support)<0.00001 {contact_points += 1}
			}}
			testing.expect(t,contact_points>=3,"Every settled result rests on a face")
			if kind == .D4 {
				up := rl.Vector3RotateByQuaternion(rl.Vector3Normalize(die.vertices[face.value-1]),rotation)
				testing.expect(t,up.y>0.9999)
			} else {
				result_face := die.faces[polyhedral_face_for_result(&die,face.value)]
				testing.expect(t,rl.Vector3RotateByQuaternion(result_face.normal,rotation).y>0.9999)
				testing.expect(t,rl.Vector3RotateByQuaternion(result_face.v,rotation).z< -0.9999)
			}
		}
		testing.expect_value(t,die,original)
	}
}

@(test)
test_polyhedral_d4_repeats_vertex_value_and_percentile_has_tens :: proc(t: ^testing.T) {
	d4 := build_polyhedral_die(.D4)
	for vertex in 0..<4 {
		count := 0
		for face in d4.faces[:d4.face_count] {for index in 0..<face.count {
			if face.vertices[index] == vertex {count += 1}
		}}
		testing.expect_value(t,count,3)
	}
	for kind in ([2]Polyhedral_Die_Kind{.D10,.D100}) {
		die := build_polyhedral_die(kind)
		seen: [10]bool
		for face in die.faces[:die.face_count] {
			digits,count := polyhedral_face_label(&die,face)
			value := digits[0] if count == 1 else digits[0]*10+digits[1]
			if kind == .D100 {testing.expect_value(t,count,2); testing.expect_value(t,value%10,0); value /= 10}
			testing.expect(t,!seen[value]); seen[value] = true
			for opposite in die.faces[:die.face_count] {
				if rl.Vector3DotProduct(face.normal,opposite.normal)> -0.999 {continue}
				other,_ := polyhedral_face_label(&die,opposite)
				testing.expect_value(t,value+other[0],9)
			}
		}
	}
}

@(test)
test_polyhedral_tumbling_support_is_finite_and_clears_floor :: proc(t: ^testing.T) {
	for kind in Polyhedral_Die_Kind.D4..<Polyhedral_Die_Kind.Count {
		die := build_polyhedral_die(kind)
		for step in 0..<40 {
			rotation := rl.QuaternionFromEuler(f32(step)*0.23,f32(step)*0.71,f32(step)*0.39)
			support := polyhedral_support_height(&die,rotation)
			testing.expect(t,!math.is_nan(support) && support>0 && support<1)
			for triangle in die.triangles[:die.triangle_count] {for point in triangle.points {
				testing.expect(t,rl.Vector3RotateByQuaternion(point,rotation).y+support>=-0.00001)
			}}
		}
	}
}
