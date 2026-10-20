package render

import rl "vendor:raylib"
import tween "../engine/tween"

// Resting solids closer than this are pushed apart (world units).
POLYHEDRAL_REST_CLEARANCE :: f32(0.005)
POLYHEDRAL_REST_STEP :: f32(0.02)

// Reuse the baked cosmetic throw as a motion path. A constant local rotation
// maps its resting orientation to the committed result: numbers never change
// on a face during the fall. Correct support height for the actual solid so a
// tetrahedron or dodecahedron never inherits the cube's floating/penetrating base.
polyhedral_dice_pose :: proc(die: ^Polyhedral_Die, throw: ^Dice_Throw, index: int,
	progress: f32, result: i32) -> (position: rl.Vector3, orientation: rl.Quaternion) {
	orientation = 1
	if die == nil || throw == nil || index < 0 || index >= throw.count { return }
	frame := sample_dice_throw(throw, progress)
	final := sample_dice_throw(throw, 1)
	rest := polyhedral_result_orientation(die, result)
	local := (1/final.orientations[index])*rest
	orientation = rl.QuaternionNormalize(frame.orientations[index]*local)
	body := Dice_Physics_Body{position = frame.positions[index], orientation = frame.orientations[index]}
	clearance := max(f32(0), body.position.y-dice_physics_support_height(&body))
	position = frame.positions[index]
	position.y = clearance+polyhedral_support_height(die, orientation)
	return
}

// How deep any corner of one solid sinks into the other (0 when apart). The
// faces of a convex die bound it, so a corner inside every face plane is inside.
@(private)
polyhedral_overlap :: proc(die: ^Polyhedral_Die, a: rl.Vector3, a_rotation: rl.Quaternion,
	b: rl.Vector3, b_rotation: rl.Quaternion) -> (depth: f32) {
	if die == nil { return }
	for pass in 0..<2 {
		from, from_rotation, into, into_rotation := a, a_rotation, b, b_rotation
		if pass == 1 { from, from_rotation, into, into_rotation = b, b_rotation, a, a_rotation }
		for vertex in die.vertices[:die.vertex_count] {
			local := rl.Vector3RotateByQuaternion(rl.Vector3RotateByQuaternion(vertex, from_rotation)+from-into, 1/into_rotation)
			inside := f32(1e9)
			for face in die.faces[:die.face_count] {
				inside = min(inside, rl.Vector3DotProduct(face.normal, face.center-local))
			}
			depth = max(depth, inside)
		}
	}
	return
}

// The throw is baked for unit cubes. A D10, D12 or D20 reaches past its cube,
// so three of them can come to rest inside each other: these floor offsets
// part the resting solids, and the pose eases into them while the dice settle.
// Cosmetic only, like the throw; a single die or a clear pool never moves.
@(private)
polyhedral_rest_offsets :: proc(die: ^Polyhedral_Die, throw: ^Dice_Throw, results: [3]i32, count: int) -> (offsets: [3]rl.Vector3) {
	if die == nil || throw == nil || count < 2 || count > throw.count { return }
	rest, positions: [3]rl.Vector3
	rotations: [3]rl.Quaternion
	for index in 0..<count {
		rest[index], rotations[index] = polyhedral_dice_pose(die, throw, index, 1, results[index])
		positions[index] = rest[index]
	}
	for _ in 0..<64 {
		moved := false
		for a in 0..<count {
			for b in a+1..<count {
				if polyhedral_overlap(die, positions[a], rotations[a], positions[b], rotations[b]) <= POLYHEDRAL_REST_CLEARANCE { continue }
				// Apart along the floor, away from each other's centres.
				push := rl.Vector3{positions[b].x-positions[a].x, 0, positions[b].z-positions[a].z}
				push = rl.Vector3Normalize(push)*POLYHEDRAL_REST_STEP if rl.Vector3Length(push) > 0.0001 else rl.Vector3{POLYHEDRAL_REST_STEP, 0, 0}
				positions[a] -= push
				positions[b] += push
				moved = true
			}
		}
		if !moved { break }
	}
	for index in 0..<count { offsets[index] = positions[index]-rest[index] }
	return
}

// 0 in flight, 1 at rest: the parting happens during the last settle.
@(private)
polyhedral_rest_settle :: proc(progress: f32) -> f32 {
	u := (dice_progress(progress)-DICE_THIRD_IMPACT_PROGRESS)/(DICE_PHYSICS_REVEAL_PROGRESS-DICE_THIRD_IMPACT_PROGRESS)
	return tween.smoothstep(clamp(u, f32(0), f32(1)))
}
