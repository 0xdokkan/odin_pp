package main

import "core:testing"
import render "render"

@(test)
test_m7_recovery_walks_and_action_gates_use_one_second_at_every_playback_speed :: proc(t: ^testing.T) {
	for speed in ([2]f32{1, 4}) {
		renderer := new(render.Renderer)
		defer free(renderer)
		defer render.destroy_renderer_world_playback(renderer)
		testing.expect(t, render.set_renderer_playback_speed(renderer, speed))
		testing.expect(t, run_m7_recovery_smoke(nil, renderer))
	}
}
