package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"

// Verify the actual rendered vertices along the baked throw, not just the
// support helper in isolation. Every scoring value must survive the rotation
// mapping, including all D4 tips and percentile 00.
@(test)
test_polyhedral_playback_all_results_clear_the_tray_and_reveal_the_committed_value :: proc(t: ^testing.T) {
	throw := new(Dice_Throw)
	defer free(throw)
	build_dice_throw(throw,3,0xC4A0,12)
	testing.expect(t,throw.settled)
	for kind in Polyhedral_Die_Kind.D4..<Polyhedral_Die_Kind.Count {
		die := build_polyhedral_die(kind)
		for face,index in die.faces[:die.face_count] {
			body_index := index%throw.count
			for progress in ([9]f32{0,0.09,DICE_PHYSICS_IMPACT_PROGRESS,0.30,0.46,0.63,DICE_PHYSICS_REVEAL_PROGRESS,0.94,1}) {
				position,orientation := polyhedral_dice_pose(&die,throw,body_index,progress,face.value)
				minimum_y := f32(math.F32_MAX)
				for triangle in die.triangles[:die.triangle_count] {
					for vertex in triangle.points {
						world := rl.Vector3RotateByQuaternion(vertex,orientation)+position
						minimum_y = min(minimum_y,world.y)
					}
				}
				testing.expectf(t,minimum_y>=-0.00002,"floor penetration: kind=%v result=%v progress=%v",kind,face.value,progress)
				testing.expect(t,abs(abs(orientation)-1)<0.00001)
				if progress == 0 {testing.expect(t,minimum_y>5,"The model must begin in the air, not snap to the tray")}
				if progress < DICE_PHYSICS_REVEAL_PROGRESS {continue}
				testing.expect(t,minimum_y<0.003,"Revealed dice must rest on the tray without floating")
				contact_count := 0
				for triangle in die.triangles[:die.triangle_count] {for vertex in triangle.points {
					world := rl.Vector3RotateByQuaternion(vertex,orientation)+position
					if world.y-minimum_y<0.0001 {contact_count += 1}
				}}
				testing.expect(t,contact_count>=3,"A result needs a flat face in contact with the tray")
				rest := polyhedral_result_orientation(&die,face.value)
				for axis in ([3]rl.Vector3{{1,0,0},{0,1,0},{0,0,1}}) {
					testing.expect(t,rl.Vector3Distance(rl.Vector3RotateByQuaternion(axis,orientation),
						rl.Vector3RotateByQuaternion(axis,rest))<0.00001)
				}
				if kind == .D4 {
					apex := rl.Vector3RotateByQuaternion(rl.Vector3Normalize(die.vertices[face.value-1]),orientation)
					testing.expect(t,apex.y>0.9999)
				} else {testing.expect(t,rl.Vector3RotateByQuaternion(face.normal,orientation).y>0.9999)}
			}
		}
	}
}

@(test)
test_polyhedral_playback_is_stateless_deterministic_and_does_not_change_numbering :: proc(t: ^testing.T) {
	throw,original_throw := new(Dice_Throw),new(Dice_Throw)
	defer free(throw)
	defer free(original_throw)
	build_dice_throw(throw,3,0x7151,14.39)
	original_throw^ = throw^
	for kind in Polyhedral_Die_Kind.D4..<Polyhedral_Die_Kind.Count {
		die := build_polyhedral_die(kind)
		original_die := die
		result := die.faces[die.face_count-1].value
		for index in 0..<throw.count {
			initial_frame := sample_dice_throw(throw,0)
			_,initial_orientation := polyhedral_dice_pose(&die,throw,index,0,result)
			for step in 0..=45 {
				progress := f32(step)/45
				position,orientation := polyhedral_dice_pose(&die,throw,index,progress,result)
				// Another specimen/result, queried backwards in time, must not
				// mutate either the physical path or the solid's face numbering.
				polyhedral_dice_pose(&die,throw,(index+1)%throw.count,1-progress,die.faces[0].value)
				repeated_position,repeated_orientation := polyhedral_dice_pose(&die,throw,index,progress,result)
				testing.expect_value(t,position,repeated_position)
				testing.expect_value(t,orientation,repeated_orientation)
				frame := sample_dice_throw(throw,progress)
				testing.expect_value(t,position.x,frame.positions[index].x)
				testing.expect_value(t,position.z,frame.positions[index].z)
				// The model inherits the same rigid rotation throughout flight;
				// there is no late interpolation that turns a wrong result over.
				motion := frame.orientations[index]*(1/initial_frame.orientations[index])
				for axis in ([3]rl.Vector3{{1,0,0},{0,1,0},{0,0,1}}) {
					expected := rl.Vector3RotateByQuaternion(rl.Vector3RotateByQuaternion(axis,initial_orientation),motion)
					testing.expect(t,rl.Vector3Distance(rl.Vector3RotateByQuaternion(axis,orientation),expected)<0.00001)
				}
			}
		}
		testing.expect_value(t,die,original_die)
	}
	testing.expect_value(t,throw^,original_throw^)
}
