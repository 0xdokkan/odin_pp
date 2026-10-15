package game

import "core:math"
import "core:testing"
import level "../level"

// PINBALL and FIRST PERSON SHOOTER together. The view begins while the ball
// rolls, and behind his eyes the ball rolls on with the view's own world
// seconds; meanwhile no card is played, so no second ball. The AK's shots pass
// through the ball (out of play: no body for them) to the foe behind it, and
// the ball's foe never takes them.
@(test)
test_pinball_rolls_on_behind_his_eyes_and_the_ak_shoots_through_it :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {7, 6}, health = 30, attack = 1}, {position = {9, 6}, health = 40, attack = 1},
		{position = {6, 2}, health = 40, attack = 1}}
	room := first_person_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	for enemy in room.enemies { lasso_test_hold(&room, enemy.id) }
	ball, behind := lasso_test_foe(&room, {7, 6}), lasso_test_foe(&room, {9, 6})
	testing.expect_value(t, pinball_test_strike(t, &room, ball).result, Card_Play_Result.Played)
	testing.expect(t, room.pinball.active && !tactical_is_casting(&room))
	// Behind his eyes while it rolls; no card meanwhile.
	testing.expect(t, tactical_can_begin_first_person(&room))
	testing.expect_value(t, first_person_test_play(t, &room).result, Card_Play_Result.Played)
	testing.expect(t, tactical_first_person_active(&room) && room.pinball.active && !tactical_allows_cards(&room))
	// East through the ball's cell: the AK meets the foe behind it.
	east := First_Person_Aim{yaw = 0}
	shot := first_person_trace(&room, player.position, east)
	testing.expect(t, shot.hit == .Foe && shot.target == enemy_entity(behind))
	struck := lasso_test_health(&room, behind)
	testing.expect_value(t, first_person_test_fire(&room, 1.0/60.0, 1.0/60.0, east), 1)
	testing.expect_value(t, lasso_test_health(&room, behind), struck-FIRST_PERSON_SHOT_DAMAGE)
	testing.expect_value(t, lasso_test_health(&room, ball), i32(30))
	// A second of the world's: the view's seconds and the ball's go together.
	left, rolled := room.first_person.remaining, pinball_rolled(&room.pinball)
	testing.expect(t, abs(pinball_test_roll(t, &room, 1, 1.0/60.0)-1) < 1e-4)
	testing.expect(t, abs(left-room.first_person.remaining-1) < 1e-3)
	testing.expect(t, abs(pinball_rolled(&room.pinball)-rolled-1) < 1e-3)
	testing.expect(t, tactical_first_person_active(&room) && room.pinball.active)
	// Straight at the ball wherever it has rolled: never the ball.
	p := pinball_position(&room.pinball)
	at := First_Person_Aim{yaw = f32(math.atan2(p.y-f64(player.position.y), p.x-f64(player.position.x)))}
	testing.expect(t, first_person_trace(&room, player.position, at).target != enemy_entity(ball))
	testing.expect_value(t, lasso_test_health(&room, ball), i32(30))
}

// The ball's burst is a kill of the player's: the last foe falling clears the
// room, and the view behind his eyes ends with the fight.
@(test)
test_pinball_burst_of_the_last_foe_ends_the_view :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {7, 6}, health = 30, attack = 1}}
	room := first_person_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, pinball_test_strike(t, &room, room.enemies[0].id).result, Card_Play_Result.Played)
	testing.expect_value(t, first_person_test_play(t, &room).result, Card_Play_Result.Played)
	testing.expect(t, tactical_first_person_active(&room) && room.pinball.active)
	// Half a second left of its twenty.
	testing.expect_value(t, room.pinball.run, f64(0))
	room.pinball.before = PINBALL_SECONDS-0.5
	pinball_test_roll(t, &room, 1, 1.0/60.0)
	testing.expect(t, !room.pinball.active && len(room.enemies) == 0)
	testing.expect_value(t, room.phase, Room_Phase.Loot)
	testing.expect(t, !tactical_first_person_active(&room) && !room.first_person.active)
}
