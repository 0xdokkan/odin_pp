package render

import "core:testing"
import "core:math"
import game "../game"

@(test)
test_frame_hitch_cannot_skip_dice_rebounds_even_when_entering_from_another_cue :: proc(t: ^testing.T) {
	for duration in ([2]f32{DICE_CUE_DURATION, 0.3}) { for leading_card in ([2]bool{false, true}) {
		renderer := new(Renderer)
		renderer.playback_speed = 4
		dice_index := 1 if leading_card else 0
		renderer.timeline.count = dice_index+1
		if leading_card {
			// Already presented card cue; its remaining time must carry into dice
			// through the same frame update that receives the hitch.
			renderer.timeline.cues[0] = {kind = .Spell_Launched, started = true, duration = 0.1, elapsed = 0.09,
				event = {card_definition = .Fate_Strike}}
		}
		renderer.timeline.cues[dice_index] = {kind = .Dice_Rolled, duration = duration,
			event = {kind = .Dice_Rolled, card_definition = .Fate_Strike, source = game.PLAYER_ENTITY,
				amount = 4, dice_roll = {faces = {4, 0, 0}, total = 4, count = 1}}}
		testing.expect(t, !update_renderer_frame_timeline(renderer, 0.9))
		cue, found := active_presentation_cue(&renderer.timeline)
		testing.expect(t, found && cue.kind == .Dice_Rolled && cue.started)
		if found {
			testing.expect(t, presentation_cue_progress(cue) <= DICE_MAX_FRAME_PROGRESS+0.0001)
			cue.elapsed = cue.duration*DICE_PHYSICS_IMPACT_PROGRESS
			update_renderer_frame_timeline(renderer, 0.9)
			testing.expect(t, presentation_cue_progress(cue) < DICE_SECOND_IMPACT_PROGRESS,
				"the next rendered frame must still belong to the first bounce")
			cue.elapsed = cue.duration*DICE_SECOND_IMPACT_PROGRESS
			update_renderer_frame_timeline(renderer, 0.9)
			testing.expect(t, presentation_cue_progress(cue) < DICE_THIRD_IMPACT_PROGRESS,
				"a hitch cannot swallow the second bounce either")
		}
		// Explicit replay completion remains instantaneous for smoke checks.
		testing.expect(t, update_renderer_event_timeline(renderer, 1000))
		testing.expect(t, !renderer_timeline_is_busy(renderer))
		testing.expect_value(t, renderer.timeline.update_failures, 0)
		free(renderer)
	} }
}

@(test)
test_frame_playback_keeps_normal_speed_without_a_hitch :: proc(t: ^testing.T) {
	for speed in ([3]f32{1, 2, 4}) {
		renderer := new(Renderer)
		renderer.playback_speed = speed
		renderer.timeline.count = 1
		renderer.timeline.cues[0] = {kind = .Dice_Rolled, duration = DICE_CUE_DURATION,
			event = {kind = .Dice_Rolled, card_definition = .Fate_Strike, source = game.PLAYER_ENTITY,
				amount = 4, dice_roll = {faces = {4, 0, 0}, total = 4, count = 1}}}
		update_renderer_frame_timeline(renderer, 1.0/60.0)
		testing.expect_value(t, renderer.timeline.cues[0].elapsed, f32(1.0/60.0)*speed)
		free(renderer)
	}
}

@(test)
test_live_dice_expose_each_floor_contact_once_at_all_normal_speeds :: proc(t: ^testing.T) {
	for speed in ([3]f32{1, 2, 4}) {
		renderer := new(Renderer)
		defer free(renderer)
		renderer.playback_speed = speed
		renderer.timeline.count = 1
		renderer.timeline.cues[0] = {kind = .Dice_Rolled, duration = DICE_CUE_DURATION,
			event = {kind = .Dice_Rolled, card_definition = .Fate_Strike, source = game.PLAYER_ENTITY,
				amount = 4, dice_roll = {faces = {4, 0, 0}, total = 4, count = 1}}}
		landmarks := [3]f32{DICE_PHYSICS_IMPACT_PROGRESS, DICE_SECOND_IMPACT_PROGRESS, DICE_THIRD_IMPACT_PROGRESS}
		exposed: [3]int
		frames := 0
		previous: f32
		nominal_frames := int(math.ceil(DICE_CUE_DURATION/(f32(1.0/60.0)*speed)))
		for renderer_timeline_is_busy(renderer) && frames < nominal_frames+8 {
			update_renderer_frame_timeline(renderer, 1.0/60.0)
			frames += 1
			cue, found := active_presentation_cue(&renderer.timeline)
			if !found {break}
			testing.expect(t, cue.elapsed > previous, "an exact contact must resume on the next frame")
			for landmark, index in landmarks {
				at := cue.duration*landmark
				if previous < at && cue.elapsed >= at {
					testing.expect_value(t, cue.elapsed, at)
				}
				if cue.elapsed == at {exposed[index] += 1}
			}
			previous = cue.elapsed
		}
		for count in exposed {testing.expect_value(t, count, 1)}
		testing.expect(t, !renderer_timeline_is_busy(renderer))
		testing.expect(t, frames >= nominal_frames && frames <= nominal_frames+3,
			"three contact holds add at most three nominal video frames")
		testing.expect_value(t, renderer.timeline.update_failures, 0)
	}
}

@(test)
test_live_dice_contact_landmarks_survive_repeated_hitches_and_compression :: proc(t: ^testing.T) {
	for duration in ([2]f32{DICE_CUE_DURATION, 0.3}) {
		renderer := new(Renderer)
		defer free(renderer)
		renderer.playback_speed = 4
		renderer.timeline.count = 2
		renderer.timeline.cues[0] = {kind = .Spell_Launched, started = true, duration = 0.1, elapsed = 0.09,
			event = {card_definition = .Fate_Strike}}
		renderer.timeline.cues[1] = {kind = .Dice_Rolled, duration = duration,
			event = {kind = .Dice_Rolled, card_definition = .Fate_Strike, source = game.PLAYER_ENTITY,
				amount = 4, dice_roll = {faces = {4, 0, 0}, total = 4, count = 1}}}
		landmarks := [3]f32{DICE_PHYSICS_IMPACT_PROGRESS, DICE_SECOND_IMPACT_PROGRESS, DICE_THIRD_IMPACT_PROGRESS}
		exposed: [3]int
		previous: f32
		for _ in 0..<24 {
			update_renderer_frame_timeline(renderer, 0.9)
			cue, found := active_presentation_cue(&renderer.timeline)
			if !found {break}
			testing.expect(t, cue.kind == .Dice_Rolled && cue.elapsed > previous)
			testing.expect(t, (cue.elapsed-previous)/duration <= DICE_MAX_FRAME_PROGRESS+0.000001)
			for landmark, index in landmarks {
				at := duration*landmark
				if previous < at && cue.elapsed >= at {testing.expect_value(t, cue.elapsed, at)}
				if cue.elapsed == at {exposed[index] += 1}
			}
			previous = cue.elapsed
		}
		for count in exposed {testing.expect_value(t, count, 1)}
		testing.expect(t, !renderer_timeline_is_busy(renderer), "the contact guard must finish despite persistent hitches")
	}
}
