package main

import "core:testing"
import render "render"

@(test)
test_m7_visual_probe_uses_real_actions_and_finishes_every_cue :: proc(t: ^testing.T) {
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	testing.expect(t, run_m7_visual_smoke(nil, renderer))
}
