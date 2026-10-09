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
	testing.expect(t, challenge.difficulty >= 0 && challenge.difficulty <= 2)
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
test_minigame_challenge_pays_only_wins_by_stars :: proc(t: ^testing.T) {
	run, room, data := challenge_fixture(t, 3)
	defer challenge_cleanup(run, room, data)
	start := run.player.gold
	testing.expect_value(t, settle_minigame_challenge(run, .Lost, 3), i32(0))
	testing.expect_value(t, settle_minigame_challenge(run, .Abandoned, 2), i32(0))
	testing.expect_value(t, settle_minigame_challenge(run, .Won, 3), i32(18))
	testing.expect_value(t, settle_minigame_challenge(run, .Won, 9), i32(18))
	testing.expect_value(t, run.player.gold, start+36)
	testing.expect_value(t, minigame_challenge_difficulty(0, .Combat), 0)
	testing.expect_value(t, minigame_challenge_difficulty(6, .Combat), 2)
	testing.expect_value(t, minigame_challenge_difficulty(3, .Elite), 2)
}
