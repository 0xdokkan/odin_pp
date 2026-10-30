package render

import "core:math"
import "core:testing"
import game "../game"
import level "../level"
import view "../engine/view"

// PINBALL behind the player's eyes (first_person.odin): the ball keeps its
// foe's place on the board with the camera in his eyes, the crosshair never
// warms over the ball (the AK's shots pass through it), and it fades as it
// nears the eye, gone at it; off the view it always shows whole.
@(test)
test_pinball_ball_fades_at_the_eye_behind_his_eyes :: proc(t: ^testing.T) {
	data: level.Level
	player: game.Player
	room := pinball_view_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer game.destroy_room(&room)
	snapshot: Room_Presentation
	renderer := shadow_view_test_renderer(&data, &snapshot)
	defer free(renderer)
	defer destroy_renderer_world_playback(renderer)
	foe := game.enemy_entity(room.enemies[0].id)
	play := game.play_card(&room, player.deck.hand[0].id, game.entity_target(foe))
	testing.expect_value(t, play.result, game.Card_Play_Result.Played)
	game.tactical_tick(&room, player.tactical.cast_remaining, true, false)
	testing.expect(t, game.tactical_pinball_active(&room) && !game.tactical_is_casting(&room))
	update_tactical_view(renderer, &room, {}, false)
	b := &renderer.tactical.pinball
	testing.expect(t, b.active && b.made == 1 && tactical_pinball_holds(renderer, foe))
	// Off the view the ball shows whole, wherever it is.
	testing.expect_value(t, pinball_eye_opacity(renderer, pinball_centre_at(b.at)), f32(1))
	// Behind his eyes, the dive over (the sprite clock paces it here).
	testing.expect(t, game.tactical_begin_first_person(&room, 20))
	shadow_view_test_frame(renderer, &room, 0)
	shadow_view_test_frame(renderer, &room, 1)
	f := &renderer.tactical.first_person
	testing.expect(t, f.engaged && first_person_amount(renderer) == 1 && tactical_pinball_holds(renderer, foe))
	// The ball two cells north of him, the view on it: the crosshair finds the
	// wall past it, never the ball.
	testing.expect_value(t, room.pinball.run, f64(0))
	room.pinball.origin, room.pinball.cell = {6, 4}, {x = 6, y = 4}
	if index, found := game.enemy_index_by_id(&room, foe.id); found { room.enemies[index].position = {x = 6, y = 4} }
	f.yaw, f.pitch = -math.PI/2, 0
	shadow_view_test_frame(renderer, &room, 1.0/60.0)
	testing.expect(t, b.at == view.Vec2{6, 4} && f.aimed == .Solid)
	testing.expect_value(t, pinball_eye_opacity(renderer, pinball_centre_at(b.at)), f32(1))
	// Beside him it has begun to fade; over him it is gone.
	beside := pinball_eye_opacity(renderer, pinball_centre_at({7, 6}))
	testing.expect(t, beside > 0 && beside < 1)
	testing.expect_value(t, pinball_eye_opacity(renderer, pinball_centre_at({6, 6})), f32(0))
}
