package game

import "core:testing"
import level "../level"

@(private = "file")
challenge_fixture :: proc(t: ^testing.T, seed: u64) -> (^Run_State, ^Room, ^level.Level) {
	run := new(Run_State)
	created: bool
	run^, created = create_run({max_health = 22, attack = 2, defense = 1},
		{layer_count = 7, min_nodes_per_middle_layer = 2, max_nodes_per_middle_layer = 3}, seed)
	testing.expect(t, created)
	data := new(level.Level)
	data^ = create_test_level(t)
	room := new(Room)
	room_ok: bool
	room^, room_ok = create_room(data, &run.player, {})
	testing.expect(t, room_ok)
	// The first node is a combat node; an empty room starts in Loot.
	node, _ := current_run_node(run)
	node.kind = .Combat
	run.phase = .In_Room
	room.phase = .Loot
	return run, room, data
}

@(private = "file")
challenge_cleanup :: proc(run: ^Run_State, room: ^Room, data: ^level.Level) {
	destroy_room(room)
	level.destroy(data)
	destroy_run(run)
	free(room)
	free(data)
	free(run)
}

@(test)
test_minigame_challenge_is_offered_once_per_cleared_room :: proc(t: ^testing.T) {
	run, room, data := challenge_fixture(t, 0xC0FFEE)
	defer challenge_cleanup(run, room, data)
	testing.expect(t, minigame_challenge_available(run, room))
	challenge, ok := begin_minigame_challenge(run, room, 5)
	testing.expect(t, ok)
	testing.expect(t, challenge.minigame >= 0 && challenge.minigame < 5)
	testing.expect(t, !minigame_challenge_available(run, room))
	_, again := begin_minigame_challenge(run, room, 5)
	testing.expect(t, !again)
}

@(test)
test_minigame_challenge_requires_loot_phase_and_a_catalog :: proc(t: ^testing.T) {
	run, room, data := challenge_fixture(t, 7)
	defer challenge_cleanup(run, room, data)
	_, empty := begin_minigame_challenge(run, room, 0)
	testing.expect(t, !empty)
	testing.expect(t, !room.minigame_challenge_attempted)
	room.phase = .Combat
	testing.expect(t, !minigame_challenge_available(run, room))
}

@(test)
test_minigame_challenge_choice_is_deterministic :: proc(t: ^testing.T) {
	a_run, a_room, a_data := challenge_fixture(t, 99)
	defer challenge_cleanup(a_run, a_room, a_data)
	b_run, b_room, b_data := challenge_fixture(t, 99)
	defer challenge_cleanup(b_run, b_room, b_data)
	a, _ := begin_minigame_challenge(a_run, a_room, 5)
	b, _ := begin_minigame_challenge(b_run, b_room, 5)
	testing.expect_value(t, a, b)
}

@(test)
test_minigame_challenge_does_not_scale_with_depth_or_elite_rooms :: proc(t: ^testing.T) {
	a_run, a_room, a_data := challenge_fixture(t, 99)
	defer challenge_cleanup(a_run, a_room, a_data)
	a, ok := begin_minigame_challenge(a_run, a_room, 5)
	testing.expect(t, ok)
	for kind in ([2]Node_Kind{.Combat, .Elite}) {
		for depth in ([3]int{0, 3, 6}) {
			b_run, b_room, b_data := challenge_fixture(t, 99)
			defer challenge_cleanup(b_run, b_room, b_data)
			node, _ := current_run_node(b_run)
			// Hold the room seed fixed: depth and room kind may not add a
			// difficulty modifier to the generated challenge or its receipt.
			node.depth = depth
			node.kind = kind
			b, started := begin_minigame_challenge(b_run, b_room, 5)
			testing.expect(t, started)
			testing.expect_value(t, b, a)
			testing.expect_value(t, b.seed, mix_room_seed(node.room_seed ~ MINIGAME_CHALLENGE_SALT))
			testing.expect_value(t, settle_minigame_challenge(b_run, b_room, b, .Won, 2), i32(12))
		}
	}
}

@(test)
test_minigame_challenge_pays_only_wins_by_stars :: proc(t: ^testing.T) {
	run, room, data := challenge_fixture(t, 3)
	defer challenge_cleanup(run, room, data)
	start := run.player.gold
	challenge, ok := begin_minigame_challenge(run, room, 5)
	testing.expect(t, ok)
	testing.expect_value(t, minigame_challenge_gold(.Lost, 3), i32(0))
	testing.expect_value(t, minigame_challenge_gold(.Abandoned, 2), i32(0))
	testing.expect_value(t, minigame_challenge_gold(.Won, 9), i32(18))
	testing.expect_value(t, settle_minigame_challenge(run, room, challenge, .Won, 3), i32(18))
	testing.expect_value(t, settle_minigame_challenge(run, room, challenge, .Won, 3), i32(0))
	testing.expect_value(t, run.player.gold, start+18)
	testing.expect(t, !room.minigame_challenge_pending)
}

@(test)
test_minigame_challenge_rejects_stale_or_unrelated_receipts :: proc(t: ^testing.T) {
	run, room, data := challenge_fixture(t, 12)
	defer challenge_cleanup(run, room, data)
	start := run.player.gold
	testing.expect_value(t, settle_minigame_challenge(run, room, {}, .Won, 3), i32(0))
	challenge, ok := begin_minigame_challenge(run, room, 5)
	testing.expect(t, ok)
	unrelated := challenge
	unrelated.seed ~= 1
	testing.expect_value(t, settle_minigame_challenge(run, room, unrelated, .Won, 3), i32(0))
	testing.expect(t, room.minigame_challenge_pending)
	room.phase = .Combat
	testing.expect_value(t, settle_minigame_challenge(run, room, challenge, .Won, 3), i32(0))
	room.phase = .Loot
	original_node := run.current_node
	run.current_node = INVALID_NODE_ID
	testing.expect_value(t, settle_minigame_challenge(run, room, challenge, .Won, 3), i32(0))
	run.current_node = original_node
	testing.expect_value(t, run.player.gold, start)
	testing.expect_value(t, settle_minigame_challenge(run, room, challenge, .Won, 2), i32(12))
}

@(test)
test_minigame_challenge_loss_and_abandon_consume_the_receipt :: proc(t: ^testing.T) {
	for outcome in ([2]Minigame_Challenge_Outcome{.Lost, .Abandoned}) {
		run, room, data := challenge_fixture(t, 14)
		defer challenge_cleanup(run, room, data)
		start := run.player.gold
		challenge, ok := begin_minigame_challenge(run, room, 5)
		testing.expect(t, ok)
		testing.expect_value(t, settle_minigame_challenge(run, room, challenge, outcome, 3), i32(0))
		testing.expect(t, !room.minigame_challenge_pending)
		testing.expect_value(t, settle_minigame_challenge(run, room, challenge, .Won, 3), i32(0))
		testing.expect_value(t, run.player.gold, start)
	}
}
