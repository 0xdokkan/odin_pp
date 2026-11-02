package render

import "core:math"
import "core:testing"
import rl "vendor:raylib"
import game "../game"
import grid "../engine/grid"
import level "../level"

// BENVENUTI A NAPOLI's club behind his back (first_person_club.odin;
// docs/piano-napoli.md, Fase 2).

// The view's frames until the camera stands behind him.
club_view_test_settle :: proc(renderer: ^Renderer, room: ^game.Room, frames := 60) {
	for _ in 0..<frames { shadow_view_test_frame(renderer, room, 0.02) }
}

// The camera flies behind his right shoulder and looks along the view through
// the pivot; his card stays whole; the keys turn with the view; the pitch is
// held within its own limits; the cell in front is marked.
@(test)
test_club_camera_stands_behind_his_right_shoulder :: proc(t: ^testing.T) {
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
	testing.expect(t, game.tactical_begin_first_person(&room, 30, .Club))
	club_view_test_settle(renderer, &room)
	testing.expect(t, f.engaged && f.amount == 1 && first_person_third_person(renderer))
	// The look came in a little down, the mark in sight.
	testing.expect_value(t, f.pitch, CLUB_START_PITCH)
	f.yaw, f.pitch = math.PI/2, 0
	club_view_test_settle(renderer, &room, 30)
	camera := renderer.tactical.camera
	look := rl.Vector3{0, 0, 1}
	right := rl.Vector3{-1, 0, 0}
	pivot := rl.Vector3{6.5, CLUB_PIVOT_HEIGHT, 6.5}+right*CLUB_PIVOT_RIGHT
	testing.expectf(t, rl.Vector3Distance(camera.position, pivot-look*CLUB_ARM) < 1e-3, "the camera at %v", camera.position)
	along := rl.Vector3Normalize(camera.target-camera.position)
	testing.expect(t, rl.Vector3Distance(along, look) < 1e-3)
	testing.expect(t, abs(camera.fovy-FIRST_PERSON_FOV) < 1e-4)
	// Half of his card shows: a foe in front of him shows through it.
	testing.expect(t, !first_person_hides_player(renderer) && abs(first_person_player_shown(renderer)-CLUB_CARD_SHOWN) < 1e-4)
	testing.expect_value(t, first_person_keys(renderer), game.first_person_key_directions(f.yaw))
	testing.expect_value(t, f.club.aimed, grid.Position{x = 6, y = 7})
	testing.expect(t, f.club.reaches)
	turn_first_person_view(renderer, 0, 2)
	testing.expect_value(t, f.pitch, CLUB_PITCH_UP)
	turn_first_person_view(renderer, 0, -5)
	testing.expect_value(t, f.pitch, -CLUB_PITCH_DOWN)
	// The HUD is the club's.
	testing.expect(t, first_person_hud_status(renderer) == FIRST_PERSON_HUD_STATUS_CLUB)
	testing.expect_value(t, string(first_person_countdown_text(room.first_person.remaining, f.weapon))[:3], "BAN")
}

// Backed against a wall the arm shortens at once and stops short of it, his
// card fading further (the club not drawn); turned away, it springs back slowly. All round a corner the
// camera never stands in a wall.
@(test)
test_club_camera_springs_off_the_walls :: proc(t: ^testing.T) {
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
	// Next to the wall stub at (8, 6), looking west: the wall behind him.
	room.player.position = {x = 7, y = 6}
	shadow_view_test_frame(renderer, &room, 0.02)
	testing.expect(t, game.tactical_begin_first_person(&room, 30, .Club))
	club_view_test_settle(renderer, &room)
	f.yaw, f.pitch = math.PI, 0
	shadow_view_test_frame(renderer, &room, 0.02)
	camera := renderer.tactical.camera.position
	testing.expectf(t, f.club.arm < 0.5 && camera.x < 8-0.1, "the arm %v, the camera at %v", f.club.arm, camera)
	testing.expect(t, first_person_player_shown(renderer) < CLUB_CARD_SHOWN && first_person_player_shown(renderer) >= CLUB_FADE_LEAST*CLUB_CARD_SHOWN-1e-4)
	// Turned east: open behind him; the arm comes back slowly.
	f.yaw = 0
	shadow_view_test_frame(renderer, &room, 0.02)
	testing.expectf(t, f.club.arm < 0.9, "the arm sprang back at once: %v", f.club.arm)
	club_view_test_settle(renderer, &room, 20)
	testing.expectf(t, abs(f.club.arm-CLUB_ARM) < 0.05, "the arm %v after 0.4 s", f.club.arm)
	testing.expect(t, abs(first_person_player_shown(renderer)-CLUB_CARD_SHOWN) < 1e-4)
	// In the corner at (1, 1), all the way round, looking a little down and up.
	room.player.position = {x = 1, y = 1}
	for pitch in ([3]f32{0, -CLUB_PITCH_DOWN, CLUB_PITCH_UP}) {
		for k in 0..<32 {
			f.yaw, f.pitch = f32(k)*2*math.PI/32, pitch
			shadow_view_test_frame(renderer, &room, 0.02)
			at := renderer.tactical.camera.position
			cell := grid.Position{x = int(math.floor(at.x)), y = int(math.floor(at.z))}
			testing.expectf(t, game.base_cell_is_walkable(&room, cell), "yaw %d/32 pitch %v: the camera at %v, in a wall", k, pitch, at)
		}
	}
}

// The spring: nearer at once, out over CLUB_ARM_RETURN_SECONDS (95% of the way).
@(test)
test_club_arm_springs_in_at_once_and_out_slowly :: proc(t: ^testing.T) {
	testing.expect_value(t, club_arm_ease(1.4, 0.4, 0.016), f32(0.4))
	testing.expect_value(t, club_arm_ease(0, 1.4, 0.016), f32(1.4))
	half := club_arm_ease(0.4, 1.4, 0.1)
	testing.expect(t, half > 0.4 && half < 1.2)
	whole := club_arm_ease(0.4, 1.4, CLUB_ARM_RETURN_SECONDS)
	testing.expect(t, whole >= 0.4+0.95*1.0-1e-3 && whole <= 1.4)
	// The swing's angle: at rest on his shoulder, raised back, down in front, back.
	testing.expect(t, club_swing_angle(false, 0) < 0)
	testing.expect(t, club_swing_angle(true, game.CLUB_WINDUP_SECONDS*0.99) < club_swing_angle(true, 0))
	testing.expect(t, club_swing_angle(true, game.CLUB_WINDUP_SECONDS+game.CLUB_RECOVER_SECONDS*0.12) > math.PI/2)
	testing.expect(t, abs(club_swing_angle(true, game.CLUB_SWING_SECONDS)-club_swing_angle(false, 0)) < 1e-4)
}
