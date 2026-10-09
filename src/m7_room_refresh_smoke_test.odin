package main

import "core:testing"
import render "render"

@(test)
test_m7_room_refresh_probe_uses_generated_rooms_and_real_transitions :: proc(t: ^testing.T) {
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	testing.expect(t, run_m7_room_refresh_smoke(nil, renderer))
}
