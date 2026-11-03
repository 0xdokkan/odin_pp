package render

import "core:testing"

// Her run takes the first part of its cue, then she has arrived.
@(test)
test_queen_runs_in_the_first_part_of_her_cue :: proc(t: ^testing.T) {
	testing.expect_value(t, queen_run_progress(0), f32(0))
	testing.expect_value(t, queen_run_progress(QUEEN_RUN_PART), f32(1))
	testing.expect_value(t, queen_run_progress(1), f32(1))
}

// Her lean (queen_view.odin): none before her blow, all of it a quarter of the way in, none at its end.
@(test)
test_queen_leans_into_her_blow_and_back :: proc(t: ^testing.T) {
	testing.expect_value(t, queen_lean(0), f32(0))
	testing.expect_value(t, queen_lean(0.25), f32(1))
	testing.expect_value(t, queen_lean(1), f32(0))
	testing.expect(t, queen_lean(0.1) < queen_lean(0.2) && queen_lean(0.5) > queen_lean(0.8))
}
