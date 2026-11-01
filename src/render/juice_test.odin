package render

import "core:testing"
import rl "vendor:raylib"
import game "../game"
import level "../level"
import view "../engine/view"

// THE JUICE (juice.odin): the trauma adds up to one and wears away in
// JUICE_TRAUMA_SECONDS; the profile's strength scales it, and at 0 nothing shakes.
@(test)
test_the_trauma_adds_up_wears_away_and_follows_the_strength :: proc(t: ^testing.T) {
	renderer := new(Renderer)
	defer free(renderer)
	juice_shake(renderer, 0.4)
	juice_shake(renderer, 0.4)
	testing.expect(t, abs(renderer.juice.trauma-0.8) < 1e-6)
	juice_shake(renderer, 0.9)
	testing.expect_value(t, renderer.juice.trauma, f32(1))
	for _ in 0..<int(JUICE_TRAUMA_SECONDS*60)+2 { _ = update_juice(renderer, 1.0/60) }
	testing.expect_value(t, renderer.juice.trauma, f32(0))
	set_renderer_juice_strength(renderer, 0.5)
	juice_shake(renderer, 0.4)
	testing.expect(t, abs(renderer.juice.trauma-0.2) < 1e-6)
	set_renderer_juice_strength(renderer, 0)
	renderer.juice.trauma = 0
	juice_shake(renderer, 1)
	testing.expect_value(t, renderer.juice.trauma, f32(0))
	testing.expect(t, !juice_hit_stop(renderer, 0.06))
	testing.expect(t, !renderer_hit_stopped(renderer))
}

// The shaken camera keeps its forward (the free walk's directions read it),
// moves at most JUICE_SHAKE_OFFSET cells and is still with no trauma.
@(test)
test_the_shaken_camera_keeps_its_forward_and_its_bounds :: proc(t: ^testing.T) {
	camera := rl.Camera3D{position = {4, 9, 12}, target = {4, 0, 3}, up = {0, 1, 0}, fovy = 45}
	testing.expect_value(t, juice_camera(camera, 0, 1.5), camera)
	forward := rl.Vector3Normalize(camera.target-camera.position)
	moved := false
	for step in 0..<120 {
		shaken := juice_camera(camera, 1, f64(step)/60)
		testing.expect(t, rl.Vector3Distance(rl.Vector3Normalize(shaken.target-shaken.position), forward) < 1e-5)
		testing.expect(t, rl.Vector3Distance(shaken.position, camera.position) <= JUICE_SHAKE_OFFSET*1.5+1e-5)
		testing.expect(t, abs(rl.Vector3Length(shaken.up)-1) < 1e-4)
		moved = moved || rl.Vector3Distance(shaken.position, camera.position) > 0.01
	}
	testing.expect(t, moved)
}

// A hit-stop holds the pictures: no cue moves and the world gains no time;
// the shake's clock goes on; a second one inside JUICE_HIT_STOP_GAP is refused.
@(test)
test_a_hit_stop_holds_the_cues_and_gives_the_world_no_time :: proc(t: ^testing.T) {
	renderer := new(Renderer)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	renderer.timeline.count = 1
	renderer.timeline.cues[0] = {kind = .Damage, duration = 0.5}
	testing.expect(t, juice_hit_stop(renderer, 0.06))
	testing.expect(t, !juice_hit_stop(renderer, 0.06))
	clock := renderer.juice.clock
	for _ in 0..<3 {
		_ = update_renderer_frame_timeline(renderer, 1.0/60)
		testing.expect(t, renderer.frame_had_hit_stop && renderer.frame_had_cinematic)
		testing.expect_value(t, renderer.frame_simulation_dt, f32(0))
		testing.expect_value(t, renderer.timeline.cues[0].elapsed, f32(0))
	}
	testing.expect(t, renderer.juice.clock > clock)
	for _ in 0..<2 { _ = update_renderer_frame_timeline(renderer, 1.0/60) }
	testing.expect(t, !renderer_hit_stopped(renderer))
	_ = update_renderer_frame_timeline(renderer, 1.0/60)
	testing.expect(t, !renderer.frame_had_hit_stop && renderer.timeline.cues[0].elapsed > 0)
	// Inside the gap a new one is refused; after it, accepted.
	testing.expect(t, !juice_hit_stop(renderer, 0.06))
	for _ in 0..<int(JUICE_HIT_STOP_GAP*60)+1 { _ = update_juice(renderer, 1.0/60) }
	testing.expect(t, juice_hit_stop(renderer, 0.06))
	// Never longer than JUICE_HIT_STOP_MAX.
	renderer.juice = {}
	testing.expect(t, juice_hit_stop(renderer, 5))
	testing.expect_value(t, renderer.juice.hold, JUICE_HIT_STOP_MAX)
}

// The aim reads the camera before it shakes: the cell under the mouse is the
// same however hard the board shakes, while the drawn camera moves.
@(test)
test_the_aim_does_not_shake :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := card_range_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	bounds := tactical_world_bounds(renderer)
	mouse := view.Vec2{bounds.x+bounds.width*0.5, bounds.y+bounds.height*0.45}
	update_tactical_view(renderer, &room, mouse, true)
	steady, cell, hovered := renderer.tactical.camera, renderer.hovered_cell, renderer.has_hovered_cell
	testing.expect(t, hovered)
	renderer.juice.trauma, renderer.juice.clock = 1, 0.37
	update_tactical_view(renderer, &room, mouse, true)
	testing.expect(t, renderer.has_hovered_cell && renderer.hovered_cell == cell)
	testing.expect(t, rl.Vector3Distance(renderer.tactical.camera.position, steady.position) > 0.001)
}
