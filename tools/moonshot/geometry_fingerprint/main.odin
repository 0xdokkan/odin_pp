// Headless equivalence probe: ordered authoritative geometry only. Run the same
// source against each renderer revision and compare its complete stdout.
package main

import "core:fmt"
import "core:os"
import render "../../../src/render"
import rl "vendor:raylib"

// Explicit little-endian words avoid struct padding, allocator/scratch state,
// native endianness and formatting of floating-point decimal values.
hash_word :: proc(hash: ^u64, word: u64) {
	for byte in 0..<8 { hash^ = (hash^ ~ u64(u8(word>>u32(byte*8))))*1099511628211 }
}

hash_float :: proc(hash: ^u64, value: f32) { hash_word(hash, u64(transmute(u32)value)) }

hash_color :: proc(hash: ^u64, value: rl.Color) {
	hash_word(hash, u64(value.r)); hash_word(hash, u64(value.g))
	hash_word(hash, u64(value.b)); hash_word(hash, u64(value.a))
}

geometry_hash :: proc(m: ^render.Page_Lab_Model) -> (hash: u64) {
	hash = 14695981039346656037
	hash_word(&hash, 1); hash_word(&hash, u64(m.vertex_count))
	for v in m.vertices[:m.vertex_count] {
		hash_float(&hash, v.position.x); hash_float(&hash, v.position.y); hash_float(&hash, v.position.z)
		hash_float(&hash, v.sheet.x); hash_float(&hash, v.sheet.y)
	}
	hash_word(&hash, 2); hash_word(&hash, u64(m.triangle_count))
	for triangle in m.triangles[:m.triangle_count] {
		for index in triangle.indices { hash_word(&hash, u64(index)) }
		hash_word(&hash, u64(triangle.surface))
		hash_color(&hash, triangle.front); hash_color(&hash, triangle.back)
	}
	hash_word(&hash, 3); hash_word(&hash, u64(m.cut_edge_count))
	for edge in m.cut_edges[:m.cut_edge_count] {
		for index in edge.indices { hash_word(&hash, u64(index)) }
		hash_word(&hash, u64(edge.surface))
	}
	hash_word(&hash, 4); hash_word(&hash, u64(m.hinge_count))
	for hinge in m.hinges[:m.hinge_count] {
		for index in hinge.indices { hash_word(&hash, u64(index)) }
		hash_word(&hash, u64(hinge.surface))
	}
	return
}

record_pose :: proc(m: ^render.Page_Lab_Model, kind: string, index: int, pose: render.Page_Lab_Pose, aggregate: ^u64) -> bool {
	render.page_lab_build(m, pose)
	valid := render.page_lab_validate(m)
	hash := geometry_hash(m)
	hash_word(aggregate, u64(pose.act)); hash_float(aggregate, pose.time); hash_word(aggregate, hash)
	fmt.printf("%s,%d,%v,%08x,%d,%d,%d,%d,%v,%016x\n", kind, index, pose.act, transmute(u32)pose.time,
		m.vertex_count, m.triangle_count, m.cut_edge_count, m.hinge_count, valid, hash)
	return valid
}

probe :: proc() -> int {
	if len(os.args) != 1 { fmt.eprintln("Il probe geometrico non accetta argomenti."); return 2 }
	m := new(render.Page_Lab_Model); defer free(m)
	aggregate := u64(14695981039346656037)
	complete := true
	count := 0
	fmt.println("kind,index,act,time_bits,vertices,triangles,cuts,hinges,valid,hash")
	for act in render.Page_Lab_Act {
		for frame in 0..<240 {
			valid := record_pose(m, "frame", frame, {act = act, time = f32(frame)/60}, &aggregate)
			complete = complete && valid; count += 1
		}
	}
	// PAGE_LAB_SHOTS: camera/print-only variants intentionally repeat the pose.
	poses := [?]render.Page_Lab_Pose{
		{}, {}, {act = .Walk, time = .7}, {act = .Walk, time = .7},
		{act = .Turn, time = 1.3}, {act = .Climb, time = 2.5}, {act = .Climb, time = 2.5},
		{act = .Mount, time = 2}, {act = .Death, time = 1.4}, {act = .Death, time = 3.2},
		{act = .Arrow, time = 1.4}, {act = .Bomb, time = 1.4}, {act = .Flight, time = 1.4},
		{}, {}, {}, {}, {act = .Walk, time = .7}, {act = .Walk, time = .7}, {}, {}, {}, {}, {}, {},
	}
	#assert(len(poses) == 25)
	for pose, index in poses {
		valid := record_pose(m, "native", index, pose, &aggregate)
		complete = complete && valid; count += 1
	}
	fmt.printf("PAGE LAB GEOMETRY FINGERPRINT version=1 samples=%d complete=%v aggregate=%016x\n", count, complete, aggregate)
	return 0 if complete else 2
}

main :: proc() {
	status := probe()
	if status != 0 { os.exit(status) }
}
