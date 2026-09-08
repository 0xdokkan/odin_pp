package render

import "core:testing"
import "core:math"
import game "../game"
import rl "vendor:raylib"

@(test)
test_dice_rebound_timing_keeps_second_flight_large_on_screen_at_playback_speeds :: proc(t: ^testing.T) {
	for count in 1..=3 {
		layout := dice_pool_layout(640, 360)
		dice := new(Dice_Renderer)
		roll := game.Dice_Roll{faces = {4, 0, 0}, count = count, total = 4}
		if count >= 2 {roll.faces[1], roll.total = 5, 9}
		if count == 3 {roll.faces[2], roll.total = 2, 11}
		prepare_dice_pool(dice, roll, 0x0C1E37E209629011, layout)
		throw := &dice.throw_state
		testing.expect(t, throw.rebound_frames[0] > throw.first_impact_frame && throw.rebound_frames[1] > throw.rebound_frames[0])
		for landmark, index in ([2]f32{DICE_SECOND_IMPACT_PROGRESS, DICE_THIRD_IMPACT_PROGRESS}) {
			sampled, contact := sample_dice_throw(throw, landmark), throw.frames[throw.rebound_frames[index]]
			for die in 0..<count {
				testing.expect(t, rl.Vector3Distance(sampled.positions[die], contact.positions[die]) < 0.00001)
				// Normalization may change the last bit; q and -q encode the same pose.
				testing.expect(t, min(abs(sampled.orientations[die]-contact.orientations[die]),
					abs(sampled.orientations[die]+contact.orientations[die])) < 0.00001)
			}
		}
		for fps in ([2]int{30, 60}) { for speed in ([3]f32{1, 2, 4}) {
			renderer := new(Renderer)
			renderer.playback_speed = speed
			id := game.Card_Id.Fate_Strike if count == 1 else game.Card_Id.Sundering_Blow if count == 2 else game.Card_Id.Prismatic_Barrage
			event := game.Game_Event{kind = .Dice_Rolled, source = game.PLAYER_ENTITY, card_id = 1,
				card_definition = id, dice_roll = roll, amount = roll.total}
			renderer.timeline.count = 1
			renderer.timeline.cues[0] = {kind = .Dice_Rolled, event = event, duration = presentation_cue_duration(.Dice_Rolled, event)}
			peak, visible := f32(0), 0
			for _ in 0..<fps*2 {
				update_renderer_frame_timeline(renderer, 1/f32(fps))
				cue, found := active_presentation_cue(&renderer.timeline)
				if !found {break}
				p := presentation_cue_progress(cue)
				if p < DICE_SECOND_IMPACT_PROGRESS || p > DICE_THIRD_IMPACT_PROGRESS {continue}
				frame := sample_dice_throw(throw, p)
				rise: f32
				for die in 0..<count {
					position := frame.positions[die]
					floor := dice_world_to_window(layout, rl.Vector3{position.x, 0.5, position.z})
					center := dice_world_to_window(layout, position)
					rise = max(rise, floor.y-center.y)
				}
				peak = max(peak, rise)
				if rise >= 12 {visible += 1}
			}
			testing.expectf(t, peak >= 20, "second bounce must visibly rise even at speed %v fps %v pool %v: %v pixels", speed, fps, count, peak)
			if speed == 1 {
				testing.expectf(t, visible >= fps/6, "second bounce needs visible flight, fps=%v pool=%v frames=%v", fps, count, visible)
			}
			testing.expect_value(t, renderer.timeline.update_failures, 0)
			free(renderer)
		} }
		free(dice)
	}
}

// Relative world-space rotation must move world up. Comparing the die's own
// up vectors alone would incorrectly count a yaw-only spin of a tilted die.
test_dice_playback_tumble_angle :: proc(before, after: rl.Quaternion) -> f32 {
	delta := rl.QuaternionNormalize(after*(1/before))
	up := rl.Vector3RotateByQuaternion({0, 1, 0}, delta)
	return math.acos(clamp(up.y, f32(-1), f32(1)))
}

@(test)
test_dice_playback_tumble_measure_rejects_frozen_and_yaw_only_dice :: proc(t: ^testing.T) {
	tilted := rl.QuaternionFromEuler(0.7, 0, 0.2)
	yawed := rl.QuaternionFromAxisAngle({0, 1, 0}, 1.2)*tilted
	tumbled := rl.QuaternionFromAxisAngle({1, 0, 0}, math.PI/4)*tilted
	testing.expect(t, test_dice_playback_tumble_angle(tilted, tilted) < 0.001)
	testing.expect(t, test_dice_playback_tumble_angle(tilted, yawed) < 0.001,
		"a tilted die rotating only around vertical Y must not satisfy the tumble regression")
	testing.expect(t, test_dice_playback_tumble_angle(tilted, tumbled) > math.PI/6)
}

@(test)
test_live_dice_show_substantial_xz_tumbling_in_both_rebound_flights :: proc(t: ^testing.T) {
	for count in 1..=3 {
		dice := new(Dice_Renderer)
		roll := game.Dice_Roll{faces = {4, 0, 0}, count = count, total = 4}
		if count >= 2 {roll.faces[1], roll.total = 5, 9}
		if count == 3 {roll.faces[2], roll.total = 2, 11}
		prepare_dice_pool(dice, roll, 0x0C1E37E209629011, dice_pool_layout(948, 1020, {0, 243, 948, 533.25}))
		throw := &dice.throw_state
		testing.expectf(t, throw.settled, "tumble playback fixture must settle, pool=%v", count)
		for fps in ([2]int{30, 60}) { for speed in ([3]f32{1, 2, 4}) {
			renderer := new(Renderer)
			renderer.playback_speed = speed
			id := game.Card_Id.Fate_Strike if count == 1 else game.Card_Id.Sundering_Blow if count == 2 else game.Card_Id.Prismatic_Barrage
			event := game.Game_Event{kind = .Dice_Rolled, source = game.PLAYER_ENTITY, card_id = 1,
				card_definition = id, dice_roll = roll, amount = roll.total}
			renderer.timeline.count = 1
			renderer.timeline.cues[0] = {kind = .Dice_Rolled, event = event, duration = presentation_cue_duration(.Dice_Rolled, event)}
			observed: [2][3][32]rl.Quaternion
			observed_count: [2][3]int
			largest_tumble: [2]f32
			for _ in 0..<fps*2 {
				update_renderer_frame_timeline(renderer, 1/f32(fps))
				cue, found := active_presentation_cue(&renderer.timeline)
				if !found {break}
				p := presentation_cue_progress(cue)
				if cue.elapsed < cue.duration*DICE_PHYSICS_IMPACT_PROGRESS || cue.elapsed > cue.duration*DICE_THIRD_IMPACT_PROGRESS {continue}
				flight := 0 if cue.elapsed < cue.duration*DICE_SECOND_IMPACT_PROGRESS else 1
				contact_pose := cue.elapsed == cue.duration*(DICE_PHYSICS_IMPACT_PROGRESS if flight == 0 else DICE_SECOND_IMPACT_PROGRESS)
				frame := sample_dice_throw(throw, p)
				for die in 0..<count {
					// The contact guard really displays this baseline. Subsequent
					// samples must be airborne; no quiet-tail correction gets credit.
					if contact_pose {
						observed[flight][die][0], observed_count[flight][die] = frame.orientations[die], 1
						continue
					}
					body := Dice_Physics_Body{position = frame.positions[die], orientation = frame.orientations[die]}
					if body.position.y-dice_physics_support_height(&body) <= 0.04 {continue}
					n := observed_count[flight][die]
					for previous in 0..<n {
						angle := test_dice_playback_tumble_angle(observed[flight][die][previous], frame.orientations[die])
						largest_tumble[flight] = max(largest_tumble[flight], angle)
					}
					assert(n < len(observed[flight][die]))
					observed[flight][die][n] = frame.orientations[die]
					observed_count[flight][die] += 1
				}
			}
			for angle, flight in largest_tumble {
				testing.expectf(t, angle >= math.PI/6,
					"rendered rebound %v needs a visible X/Z tumble, pool=%v speed=%v fps=%v angle=%v degrees",
					flight+1, count, speed, fps, angle*180/math.PI)
			}
			testing.expect_value(t, renderer.timeline.update_failures, 0)
			free(renderer)
		} }
		free(dice)
	}
}

@(test)
test_dice_settling_preserves_early_seconds_and_eases_continuously_to_rest :: proc(t: ^testing.T) {
	// A constant-speed recording makes changes to playback speed observable
	// without depending on a particular throw's collision sequence.
	throw := new(Dice_Throw)
	defer free(throw)
	throw.count, throw.first_impact_frame = 1, 60
	throw.rebound_frames = {90, 120}
	throw.last_motion_frame = 180
	for index in 0..<DICE_THROW_FRAME_COUNT {
		position := f32(min(index, throw.last_motion_frame))
		throw.frames[index].positions[0] = {position, 0.5, 0}
		throw.frames[index].orientations[0] = rl.QuaternionFromAxisAngle({1, 0, 0}, position*0.005)
	}
	duration := presentation_cue_duration(.Dice_Rolled, {})
	seconds := [7]f32{0, 0.324, 0.648, 0.810, 0.972, 1.098, 1.224}
	positions := [7]f32{0, 30, 60, 75, 90, 105, 120}
	for elapsed, index in seconds {
		frame := sample_dice_throw(throw, elapsed/duration)
		testing.expectf(t, abs(frame.positions[0].x-positions[index]) < 0.0001,
			"approved early time %v must keep the same pose: got %v, expected %v", elapsed, frame.positions[0].x, positions[index])
	}
	contact_time := f32(1.224)
	contact := sample_dice_throw(throw, contact_time/duration).positions[0].x
	dt := f32(0.001)
	before := sample_dice_throw(throw, (contact_time-dt)/duration).positions[0].x
	after := sample_dice_throw(throw, (contact_time+dt)/duration).positions[0].x
	testing.expect(t, abs((after-contact)/(contact-before)-1) < 0.03,
		"settling must inherit the second flight's playback speed at contact")
	rest_time := f32(1.596)
	previous := sample_dice_throw(throw, (rest_time-2.0/60.0)/duration)
	penultimate := sample_dice_throw(throw, (rest_time-1.0/60.0)/duration)
	final := sample_dice_throw(throw, DICE_PHYSICS_REVEAL_PROGRESS)
	last_step := final.positions[0].x-penultimate.positions[0].x
	previous_step := penultimate.positions[0].x-previous.positions[0].x
	testing.expect(t, last_step > 0 && last_step < previous_step*0.6,
		"the final visible steps must decelerate rather than stop at constant speed")
	testing.expect_value(t, final, sample_dice_throw(throw, 1))
	// A very short remaining recording requires the monotone slope limit.
	for last in ([2]int{180, 123}) {
		throw.last_motion_frame = last
		for index in last..<DICE_THROW_FRAME_COUNT {throw.frames[index] = throw.frames[last]}
		previous_position := contact
		for tick in 1..=240 {
			p := DICE_THIRD_IMPACT_PROGRESS+(DICE_PHYSICS_REVEAL_PROGRESS-DICE_THIRD_IMPACT_PROGRESS)*f32(tick)/240
			frame := sample_dice_throw(throw, p)
			testing.expect(t, frame.positions[0].x >= previous_position-0.00002 && frame.positions[0].x <= f32(last)+0.00002,
				"settling may never rewind or overshoot the recorded resting pose")
			previous_position = frame.positions[0].x
		}
	}
}

@(test)
test_live_dice_settling_displays_multiple_changing_poses_before_reveal :: proc(t: ^testing.T) {
	for count in 1..=3 {
		dice := new(Dice_Renderer)
		roll := game.Dice_Roll{faces = {4, 0, 0}, count = count, total = 4}
		if count >= 2 {roll.faces[1], roll.total = 5, 9}
		if count == 3 {roll.faces[2], roll.total = 2, 11}
		prepare_dice_pool(dice, roll, 0x0C1E37E209629011, dice_pool_layout(948, 1020, {0, 243, 948, 533.25}))
		throw := &dice.throw_state
		for fps in ([2]int{30, 60}) { for speed in ([3]f32{1, 2, 4}) {
			renderer := new(Renderer)
			renderer.playback_speed = speed
			id := game.Card_Id.Fate_Strike if count == 1 else game.Card_Id.Sundering_Blow if count == 2 else game.Card_Id.Prismatic_Barrage
			event := game.Game_Event{kind = .Dice_Rolled, source = game.PLAYER_ENTITY, card_id = 1,
				card_definition = id, dice_roll = roll, amount = roll.total}
			renderer.timeline.count = 1
			renderer.timeline.cues[0] = {kind = .Dice_Rolled, event = event, duration = presentation_cue_duration(.Dice_Rolled, event)}
			previous := sample_dice_throw(throw, DICE_THIRD_IMPACT_PROGRESS)
			changing_poses, settling_frames := 0, 0
			for _ in 0..<fps*3 {
				update_renderer_frame_timeline(renderer, 1/f32(fps))
				cue, found := active_presentation_cue(&renderer.timeline)
				if !found {break}
				p := presentation_cue_progress(cue)
				if p <= DICE_THIRD_IMPACT_PROGRESS {continue}
				if p >= DICE_PHYSICS_REVEAL_PROGRESS {break}
				frame := sample_dice_throw(throw, p)
				changed := false
				for die in 0..<count {
					rotation := min(abs(frame.orientations[die]-previous.orientations[die]),
						abs(frame.orientations[die]+previous.orientations[die]))
					changed = changed || rotation > 0.003 || rl.Vector3Distance(frame.positions[die], previous.positions[die]) > 0.01
				}
				if changed {changing_poses += 1}
				settling_frames += 1
				previous = frame
			}
			testing.expectf(t, changing_poses >= 2,
				"final settling needs multiple visible pose changes, pool=%v speed=%v fps=%v changes=%v frames=%v",
				count, speed, fps, changing_poses, settling_frames)
			testing.expect_value(t, renderer.timeline.update_failures, 0)
			free(renderer)
		} }
		free(dice)
	}
}
