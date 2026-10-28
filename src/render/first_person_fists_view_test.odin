package render

import "core:math"
import "core:testing"
import game "../game"
import level "../level"

// FIRST PERSON BRAWLER on the board (first_person_fists.odin): the eye rides the
// free body a little behind it, never inside a wall, with the fists' wider view;
// as the view ends it settles back on his cell; a glove goes out over its
// punch's landing time and comes back.
@(test)
test_first_person_fists_eye_rides_the_body :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := first_person_view_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	f := &renderer.tactical.first_person
	shadow_view_test_frame(renderer, &room, 0.02)
	testing.expect(t, game.tactical_begin_first_person(&room, 20, .Fists))
	for _ in 0..<60 {
		shadow_view_test_frame(renderer, &room, 0.02)
		if f.amount >= 1 { break }
	}
	testing.expect(t, f.engaged && f.amount == 1)
	// The body moved free off his cell's centre: the eye over it, a little behind.
	room.first_person.fists.body = {6.8, 6.3}
	shadow_view_test_frame(renderer, &room, 0.02)
	back := [2]f32{-math.cos(f.yaw), -math.sin(f.yaw)}
	want := [2]f32{6.8, 6.3}+back*FIRST_PERSON_FISTS_EYE_BACK
	testing.expectf(t, abs(f.eye.x-want.x) < 1e-3 && abs(f.eye.z-want.y) < 1e-3, "eye %v, want %v", f.eye, want)
	testing.expect(t, abs(renderer.tactical.camera.fovy-FIRST_PERSON_FISTS_FOV) < 1e-3, "not the fists' view")
	// Backed up to the room's edge, the eye never goes into the wall.
	f.yaw = 0
	room.first_person.fists.body = {1.35, 6.5}
	shadow_view_test_frame(renderer, &room, 0.02)
	testing.expect(t, f.eye.x >= 1, "the eye went into the wall")
	// The view over: the eye settles on his cell's centre.
	room.first_person.fists.body = {6.8, 6.3}
	shadow_view_test_frame(renderer, &room, 0.02)
	room.first_person.remaining = 0.01
	game.tactical_first_person_tick(&room, 0.02)
	for _ in 0..<10 { shadow_view_test_frame(renderer, &room, 0.02) }
	testing.expect(t, !f.engaged)
	testing.expect(t, abs(f.eye.x-6.5) < 1e-3 && abs(f.eye.z-6.5) < 1e-3, "the eye did not settle on his cell")
}

@(test)
test_first_person_glove_goes_out_and_back :: proc(t: ^testing.T) {
	for punch in ([4]game.First_Person_Punch{.Jab, .Cross, .Left_Hook, .Right_Hook}) {
		rules := game.FISTS_PUNCHES[punch]
		testing.expect_value(t, first_person_glove_reach(punch, 0), f32(0))
		testing.expect_value(t, first_person_glove_reach(punch, rules.land), f32(1))
		testing.expect(t, first_person_glove_reach(punch, rules.land*0.5) > 0 && first_person_glove_reach(punch, rules.land*0.5) < 1)
		testing.expect_value(t, first_person_glove_reach(punch, rules.recover), f32(0))
	}
	testing.expect_value(t, first_person_glove_reach(.None, 0.1), f32(0))
}
