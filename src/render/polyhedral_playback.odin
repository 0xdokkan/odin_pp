package render

import rl "vendor:raylib"

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
