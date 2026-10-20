package render

import "core:math"
import rl "vendor:raylib"

// Find two actual return contacts once after baking. Timing follows these
// contacts rather than compressing the second bounce into the quiet tail.
@(private)
prepare_dice_playback :: proc(throw: ^Dice_Throw) {
	if throw == nil { return }
	throw.rebound_frames = {}
	if throw.count < 1 || throw.count > DICE_PHYSICS_MAX_BODIES || throw.first_impact_frame < 1 { return }
	best_peak: f32
	for die in 0..<throw.count {
		touched := false
		peak: f32
		contacts: [2]int
		count := 0
		for index in throw.first_impact_frame..=throw.last_motion_frame {
			frame := &throw.frames[index]
			body := Dice_Physics_Body{position = frame.positions[die], orientation = frame.orientations[die]}
			clearance := body.position.y-dice_physics_support_height(&body)
			if clearance > 0.035 {
				if touched { peak = max(peak, clearance) }
				continue
			}
			if touched && peak >= 0.45 {
				contacts[count] = index
				count += 1
				if count == 2 {
					if peak > best_peak { throw.rebound_frames, best_peak = contacts, peak }
					break
				}
			}
			touched, peak = true, 0
		}
	}
}

sample_dice_throw :: proc(throw: ^Dice_Throw, progress: f32) -> Dice_Physics_Frame {
	if throw == nil || throw.count < 1 || throw.count > DICE_PHYSICS_MAX_BODIES { return {} }
	p := progress
	if math.is_nan(p) { p = 0 }
	p = clamp(p, f32(0), DICE_PHYSICS_REVEAL_PROGRESS)
	if p >= DICE_PHYSICS_REVEAL_PROGRESS { return throw.frames[DICE_THROW_FRAME_COUNT-1] }
	if p == 0 { return throw.frames[0] }
	if p == DICE_PHYSICS_IMPACT_PROGRESS { return throw.frames[throw.first_impact_frame] }
	first := f32(throw.first_impact_frame)
	last := f32(max(throw.first_impact_frame+1, throw.last_motion_frame))
	frame: f32
	if p <= DICE_PHYSICS_IMPACT_PROGRESS {
		frame = first*p/DICE_PHYSICS_IMPACT_PROGRESS
	} else if throw.rebound_frames[0] > throw.first_impact_frame &&
	          throw.rebound_frames[1] > throw.rebound_frames[0] && throw.rebound_frames[1] < throw.last_motion_frame {
		start, finish := first, f32(throw.rebound_frames[0])
		start_time, finish_time := DICE_PHYSICS_IMPACT_PROGRESS, DICE_SECOND_IMPACT_PROGRESS
		if p > DICE_SECOND_IMPACT_PROGRESS {
			start, finish = f32(throw.rebound_frames[0]), f32(throw.rebound_frames[1])
			start_time, finish_time = DICE_SECOND_IMPACT_PROGRESS, DICE_THIRD_IMPACT_PROGRESS
		}
		if p > DICE_THIRD_IMPACT_PROGRESS {
			start, finish = f32(throw.rebound_frames[1]), last
			start_time, finish_time = DICE_THIRD_IMPACT_PROGRESS, DICE_PHYSICS_REVEAL_PROGRESS
		}
		u := (p-start_time)/(finish_time-start_time)
		if p > DICE_THIRD_IMPACT_PROGRESS {
			// Match the incoming playback speed where possible, then ease to
			// zero at rest. Restrict the Hermite slope to keep time monotone.
			previous_span := f32(throw.rebound_frames[1]-throw.rebound_frames[0])
			slope := clamp(previous_span/(DICE_THIRD_IMPACT_PROGRESS-DICE_SECOND_IMPACT_PROGRESS)*
				(finish_time-start_time)/(finish-start), f32(0), f32(3))
			u = slope*u+(3-2*slope)*u*u+(slope-2)*u*u*u
		}
		frame = start+(finish-start)*u
	} else {
		u := (p-DICE_PHYSICS_IMPACT_PROGRESS)/(DICE_PHYSICS_REVEAL_PROGRESS-DICE_PHYSICS_IMPACT_PROGRESS)
		slope := min(first/(last-first), f32(3))
		curve := slope*u+(3-2*slope)*u*u+(slope-2)*u*u*u
		frame = first+(last-first)*curve
	}
	index := clamp(int(frame), 0, DICE_THROW_FRAME_COUNT-2)
	t := clamp(frame-f32(index), f32(0), f32(1))
	result: Dice_Physics_Frame
	for die in 0..<throw.count {
		result.positions[die] = throw.frames[index].positions[die]+(throw.frames[index+1].positions[die]-throw.frames[index].positions[die])*t
		result.orientations[die] = rl.QuaternionNormalize(rl.QuaternionSlerp(throw.frames[index].orientations[die], throw.frames[index+1].orientations[die], t))
	}
	return result
}
