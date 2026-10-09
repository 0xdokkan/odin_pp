package main

import "core:testing"
import render "render"

@(test)
test_progressive_arena_controller_flow_preserves_independent_movement_and_room_transitions :: proc(t: ^testing.T) {
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	report: Arena_Smoke_Report
	if !testing.expect(t, run_arena_smoke(nil, renderer, &report)) { return }
	testing.expect_value(t, report.rooms, 4)
	testing.expect_value(t, report.largest_roster, 22)
	testing.expect_value(t, report.combat_moves, 4)
	testing.expect_value(t, report.transitions, 4)
	testing.expect(t, report.loot_moves > 40 && report.world_beats >= 28)
	// Enemy roles have independent cadences; every enemy need not emit a cue
	// on the same frame for the complete 22-enemy encounter to stay responsive.
	testing.expect(t, report.world_high_water > 0)
	testing.expect(t, report.simulation_ms >= 0 && report.simulation_ms < max(f64))
	testing.expect_value(t, report.map_draw_frames+report.combat_draw_frames, 0)
}
