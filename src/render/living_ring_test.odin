package render

import "core:testing"
import game "../game"

@(test)
test_living_ring_colour_follows_the_intent :: proc(t: ^testing.T) {
	enemy := game.Enemy{position = {x = 5, y = 5}}
	expect_kind :: proc(t: ^testing.T, enemy: ^game.Enemy, intent: game.Enemy_Intent, want: Living_Ring_Kind, loc := #caller_location) {
		enemy.intent = intent
		testing.expectf(t, living_ring_kind(enemy) == want, "%v: got %v, want %v", intent.kind, living_ring_kind(enemy), want, loc = loc)
	}
	front := game.Enemy_Intent{kind = .Attack, threatened_cell_count = 1}
	front.threatened_cells[0] = {x = 6, y = 5}
	expect_kind(t, &enemy, front, .Strike)
	// A cleave also takes the cells beside the one in front: still a blow.
	cleave := front
	cleave.threatened_cells[1], cleave.threatened_cells[2], cleave.threatened_cell_count = {x = 6, y = 4}, {x = 6, y = 6}, 3
	expect_kind(t, &enemy, cleave, .Strike)
	shot := game.Enemy_Intent{kind = .Attack, threatened_cell_count = 1}
	shot.threatened_cells[0] = {x = 9, y = 5}
	expect_kind(t, &enemy, shot, .Ranged)
	aim := front
	aim.windup = true
	expect_kind(t, &enemy, aim, .Ranged)
	barrel := front
	barrel.target_object = 3
	expect_kind(t, &enemy, barrel, .Ranged)
	expect_kind(t, &enemy, {kind = .Charge}, .Strike)
	expect_kind(t, &enemy, {kind = .Bombard}, .Ranged)
	expect_kind(t, &enemy, {kind = .Move}, .Move)
	expect_kind(t, &enemy, {kind = .Protect}, .Protect)
	for idle in ([3]game.Enemy_Intent_Kind{.None, .Wait, .Recover}) { expect_kind(t, &enemy, {kind = idle}, .None) }
	// Every announced kind has a colour of its own, and gold is the player's.
	for a in Living_Ring_Kind {
		for b in Living_Ring_Kind {
			if a != b && a != .None && b != .None { testing.expect(t, living_ring_color(a) != living_ring_color(b)) }
		}
	}
	testing.expect(t, living_ring_color(.Beat) == TACTICAL_FEEDBACK_CRITICAL)
}

// An enemy's ring closes over its action's countdown and touches the card as it
// acts; the player's closes over each second of the tick.
@(test)
test_living_rings_close_on_the_action_and_on_the_tick :: proc(t: ^testing.T) {
	player: game.Player

	room := game.Room{player = &player, phase = .Combat}
	open, on := living_beat_open(&room)
	testing.expect(t, on && open == 1)
	player.tactical.clock_fraction = 0.25
	open, on = living_beat_open(&room)
	testing.expect(t, on && abs(open-0.75) < 1e-5)
	enemy := game.Enemy{archetype = .Chaser, intent = {kind = .Move}, tactical_cooldown = 3}
	testing.expect(t, abs(living_ring_open(&room, &enemy)-11.0/12) < 1e-5)
	enemy.tactical_cooldown = 1
	player.tactical.clock_fraction = 0.75
	testing.expect(t, abs(living_ring_open(&room, &enemy)-1.0/12) < 1e-5)
	enemy.tactical_cooldown = 0
	testing.expect(t, living_ring_open(&room, &enemy) == 0)
	// Out of combat there is no tick to beat.
	room.phase = .Loot
	_, on = living_beat_open(&room)
	testing.expect(t, !on)
}
