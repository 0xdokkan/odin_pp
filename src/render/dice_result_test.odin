package render

import "core:testing"
import game "../game"

@(test)
test_dice_results_reveal_only_counted_faces_and_delay_pair_bonus :: proc(t: ^testing.T) {
	roll := game.Dice_Roll{faces = {3, 4, 6}, total = 13, count = 3}
	totals := [4]i32{0, 3, 7, 13}
	highest := [4]i32{0, 3, 4, 6}
	reveals := DICE_POOL_REVEAL_TIMES
	for p, index in ([4]f32{reveals[0]-0.001, reveals[0], reveals[1], reveals[2]}) {
		state := dice_total_state(roll, p)
		testing.expect_value(t, state.revealed, index)
		testing.expect_value(t, state.visible_successes, i32(max(0, index-1)))
		testing.expect_value(t, state.visible_total, totals[index])
		testing.expect_value(t, state.visible_highest, highest[index])
	}
	roll = {faces = {4, 4, 0}, total = 8, count = 2}
	testing.expect(t, !dice_total_state(roll, reveals[1]-0.001).visible_pair)
	testing.expect(t, dice_total_state(roll, reveals[1]).visible_pair)
	roll = {faces = {4, 5, 0}, total = 9, count = 2}
	testing.expect(t, !dice_total_state(roll, 1).visible_pair)
}

@(test)
test_dice_settling_keeps_result_spacing_and_final_reading_time :: proc(t: ^testing.T) {
	duration := presentation_cue_duration(.Dice_Rolled, {})
	testing.expect(t, abs(duration-2.1) < 0.00001)
	reveals := DICE_POOL_REVEAL_TIMES
	testing.expect_value(t, reveals[0], DICE_PHYSICS_REVEAL_PROGRESS)
	testing.expect(t, abs(duration*(reveals[0]-DICE_THIRD_IMPACT_PROGRESS)-0.372) < 0.00001)
	for index in 1..<3 {
		testing.expect(t, abs(duration*(reveals[index]-reveals[index-1])-0.108) < 0.00001)
	}
	testing.expect(t, abs(duration*DICE_POOL_REVEAL_STEP-0.108) < 0.00001)
	testing.expect(t, abs(duration*(1-DICE_POOL_COMPLETE_PROGRESS)-0.180) < 0.00001)
	roll := game.Dice_Roll{faces = {2, 5, 6}, total = 13, count = 3}
	for elapsed := f32(0); elapsed < duration; elapsed += 1.0/240.0 {
		p := elapsed/duration
		state := dice_total_state(roll, p)
		if p < DICE_PHYSICS_REVEAL_PROGRESS {
			testing.expect_value(t, state.revealed, 0)
		}
		if state.complete {
			testing.expect_value(t, state.revealed, roll.count)
			testing.expect_value(t, state.visible_total, roll.total)
			for transfer in state.transfer_progress {testing.expect(t, transfer > 0.999)}
		}
	}
	// Existing capture points still show a settled single die and full pool.
	testing.expect(t, f32(0.84) > DICE_PHYSICS_REVEAL_PROGRESS)
	testing.expect(t, dice_total_state(roll, 0.94).complete)
}
