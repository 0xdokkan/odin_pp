package fight

import "core:testing"

tag_test_roster :: proc(healths: ..i32) -> (roster: Roster) {
	for health, index in healths {
		roster.entries[index] = {kind = index, enemy_id = u32(index+1), health = health, max_health = 9}
		roster.count += 1
	}
	roster.player_health, roster.player_max = 5, RING_PLAYER_HEALTH
	return
}

@(test)
test_tag_roster_seats_the_first_opponent_and_benches_the_rest :: proc(t: ^testing.T) {
	state := begin(false, false)
	apply_roster(&state, tag_test_roster(9, 6, 3))
	testing.expect_value(t, state.roster_count, 3)
	testing.expect_value(t, state.active, 0)
	testing.expect_value(t, state.fighters[1].health, i32(9))
	testing.expect_value(t, state.fighters[0].health, i32(5))
	testing.expect_value(t, state.fighters[0].max_health, RING_PLAYER_HEALTH)
	testing.expect(t, !roster_waiting(&state, 0) && roster_waiting(&state, 1) && roster_waiting(&state, 2))
	// A single opponent is the classic duel: no bench, no tags.
	solo := begin(false, false)
	apply_roster(&solo, tag_test_roster(4))
	testing.expect_value(t, solo.fighters[1].health, i32(4))
	testing.expect(t, !roster_replace_knockout(&solo))
}

@(test)
test_tag_knockout_brings_in_the_next_and_the_last_one_ends_the_match :: proc(t: ^testing.T) {
	state := begin(false, false)
	apply_roster(&state, tag_test_roster(9, 6))
	state.fighters[1].health = 0
	check_result(&state)
	testing.expect_value(t, state.result, Result.Active)
	testing.expect_value(t, state.active, 1)
	testing.expect(t, state.roster[0].ko)
	testing.expect_value(t, state.fighters[1].health, i32(6))
	testing.expect_value(t, state.tags, 1)
	// The newcomer enters at its own corner post, inside the ropes.
	testing.expect_value(t, state.fighters[1].position, tag_post(1))
	state.fighters[1].health = 0
	check_result(&state)
	testing.expect_value(t, state.result, Result.Won)
	outcome := roster_outcome(&state)
	testing.expect(t, outcome.entries[0].ko)
	testing.expect_value(t, outcome.entries[1].health, i32(0))
}

@(test)
test_tag_a_hurt_opponent_runs_to_a_fresh_ally_and_swaps :: proc(t: ^testing.T) {
	state := begin(false, false)
	apply_roster(&state, tag_test_roster(9, 9))
	state.tag_cooldown = 0
	// Healthy opponents never tag out.
	tick_tag(&state)
	testing.expect_value(t, state.tag_target, -1)
	state.fighters[1].health = 3
	tick_tag(&state)
	testing.expect_value(t, state.tag_target, 1)
	// The run itself: the opponent heads for the ally's post and slaps its hand.
	for _ in 0..<600 {
		tick(&state, {})
		if state.active == 1 { break }
	}
	testing.expect_value(t, state.active, 1)
	testing.expect_value(t, state.fighters[1].health, i32(9))
	testing.expect(t, roster_waiting(&state, 0))
	testing.expect_value(t, state.roster[0].health, i32(3))
	testing.expect_value(t, state.result, Result.Active)
	// Too hurt allies are not worth a tag.
	state.fighters[1].health = 2
	state.roster[0].health = 4
	state.tag_cooldown = 0
	state.tag_target = -1
	tick_tag(&state)
	testing.expect_value(t, state.tag_target, -1)
}
