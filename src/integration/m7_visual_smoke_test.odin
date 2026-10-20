package integration
import devtools "../devtools"

import "core:testing"
import render "../render"

@(test)
test_m7_visual_probe_uses_real_actions_and_finishes_every_cue :: proc(t: ^testing.T) {
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	testing.expect(t, devtools.run_tactical_visual_smoke(nil, renderer))
}
