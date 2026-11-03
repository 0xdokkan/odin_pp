package integration
import run_session "../run"

import "core:log"
import "core:math/rand"
import "core:testing"
import "core:time"
import advisor "../advisor"
import game "../game"
import level "../level"
import render "../render"

// THE ADVISOR'S WORKER AND THE PILOT (docs/piano-ia.md, Fase 4): the search on its own thread gives the same advice as
// the search cut into slices; a search left half way leaves nothing behind; the game never waits for the thread; the
// advice of a first move the worker already tried is there in the same frame; the measures.

@(private = "file")
worker_test_arena :: proc(t: ^testing.T, data: ^level.Level, player: ^game.Player) -> game.Room {
	created: bool
	player^, created = game.create_player(run_session.DEMO_PLAYER_STATS)
	testing.expect(t, created)
	room, built := run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG, .IA)
	testing.expect(t, built)
	return room
}

// The worker's packet for the snapshot `generation`, once its search is over (`seconds` of real time at most).
@(private = "file")
worker_test_wait :: proc(w: ^advisor.Worker, generation: u64, seconds: f64 = 20) -> bool {
	start := time.tick_now()
	for time.duration_seconds(time.tick_since(start)) < seconds {
		advisor.worker_poll(w)
		if w.latest.generation == generation && w.latest.done { return true }
		time.sleep(time.Millisecond)
	}
	return false
}

// The work of a root in these tests: the first round and a part of the second, enough to tell two searches apart.
@(private = "file")
WORKER_TEST_WORK :: 120

// A hundred situations of a game played by random moves: the worker's advice for each is the search's own, cut into
// slices of the same work.
@(test)
test_advisor_worker_matches_the_slices :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := worker_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	w := advisor.worker_start()
	testing.expect(t, w != nil)
	if w == nil { return }
	defer advisor.worker_stop(w)
	w.cap = WORKER_TEST_WORK
	state := rand.create_u64(20261103)
	generator := rand.default_random_generator(&state)
	different := 0
	for situation in 0..<100 {
		if room.phase != .Combat { break }
		generation := advisor.worker_offer(w, &room)
		testing.expect(t, worker_test_wait(w, generation))
		sliced := advisor.search_whole(&search, &room, WORKER_TEST_WORK)
		if w.latest.advice != sliced {
			different += 1
			log.infof("situation %d: worker %v, slices %v", situation, w.latest.advice, sliced)
		}
		// The game goes on: a random move, then the world until the player is free.
		commands, count := run_session.advisor_move_commands(&room, {kind = .Step, direction = game.Move_Direction(rand.int_max(4, generator))})
		for command in commands[:count] { run_session.execute_gameplay_command(&room, command) }
		advisor_test_real_until_free(&room, advisor.SIM_STEP)
	}
	testing.expectf(t, different == 0, "the worker and the slices differ in %d situations", different)
}

// A search left half way for a new root leaves nothing behind: the new root's advice is the one of a search begun
// afresh.
@(test)
test_advisor_worker_leaves_a_search_cleanly :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := worker_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	w := advisor.worker_start()
	testing.expect(t, w != nil)
	if w == nil { return }
	defer advisor.worker_stop(w)
	for round in 0..<5 {
		first := advisor.worker_offer(w, &room)
		// Some of the first root's search, then a new root.
		for _ in 0..<2000 {
			advisor.worker_poll(w)
			if w.latest.generation == first && w.latest.nodes > 5+round*7 { break }
			time.sleep(100*time.Microsecond)
		}
		run_session.execute_gameplay_command(&room, {kind = .Wait, origin_phase = .Combat})
		advisor_test_real_until_free(&room, advisor.SIM_STEP)
		w.cap = WORKER_TEST_WORK
		second := advisor.worker_offer(w, &room)
		testing.expect(t, worker_test_wait(w, second))
		fresh := advisor.search_whole(&search, &room, WORKER_TEST_WORK)
		testing.expectf(t, w.latest.advice == fresh, "after a search left half way: %v, afresh: %v", w.latest.advice, fresh)
		w.cap = advisor.WORKER_WORK_CAP
	}
}

// THE PILOT, the worker held: the game never waits for it. Every frame stays short while the room changes under it;
// let go, the worker gives its advice. Then the measures: a frame of the pilot, the time from a change to the first
// advice, and thinking ahead: a first move other than the advised one, and the advice for it in the same frame.
@(test)
test_advisor_pilot_never_waits_and_thinks_ahead :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := worker_test_arena(t, &data, &player)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer run_session.advisor_pilot_release()
	room.player.tactical.ia_remaining = 999
	run_session.drive_advisor(&room, renderer, 0)
	run_session.advisor_pilot_hold(true)
	worst: f64
	for frame in 0..<180 {
		if frame%20 == 0 { run_session.execute_gameplay_command(&room, {kind = .Wait, origin_phase = .Combat}) }
		advisor_test_real_frame(&room, advisor.SIM_STEP)
		start := time.tick_now()
		run_session.drive_advisor(&room, renderer, advisor.SIM_STEP)
		worst = max(worst, time.duration_milliseconds(time.tick_since(start)))
	}
	log.infof("advisor pilot, worker held: the longest frame of the pilot %.3f ms", worst)
	testing.expectf(t, worst < 2, "the pilot waited for the worker: %.3f ms", worst)
	run_session.advisor_pilot_hold(false)

	// A change, and the first advice for it.
	advisor_test_real_until_free(&room, advisor.SIM_STEP)
	run_session.execute_gameplay_command(&room, {kind = .Wait, origin_phase = .Combat})
	advisor_test_real_until_free(&room, advisor.SIM_STEP)
	run_session.drive_advisor(&room, renderer, 0)
	root := advisor.discrete_fingerprint(&room)
	start := time.tick_now()
	for time.duration_seconds(time.tick_since(start)) < 10 {
		run_session.drive_advisor(&room, renderer, 0)
		if advice := run_session.advisor_current_advice(); advice.valid && advice.root == root { break }
		time.sleep(100*time.Microsecond)
	}
	first := time.duration_milliseconds(time.tick_since(start))
	log.infof("advisor pilot: the first advice %.1f ms after the change", first)
	testing.expect(t, run_session.advisor_current_advice().valid)

	// The search of this root over: a first move other than the advised one, as the copies play it (the world on until
	// the player is free, the reaction margin), then the pilot's very next frame.
	for time.duration_seconds(time.tick_since(start)) < 20 {
		run_session.drive_advisor(&room, renderer, 0)
		if p := run_session.advisor_pilot_packet(); p.done && p.root == root { break }
		time.sleep(time.Millisecond)
	}
	advised := run_session.advisor_current_advice().move
	for margin := f32(0); margin < advisor.REACTION_SECONDS; margin += advisor.SIM_STEP { advisor_test_real_frame(&room, advisor.SIM_STEP) }
	// A step the IA did not advise, onto a free cell (a wait would change nothing a player sees yet).
	deviation := advisor.Move{kind = .Wait}
	for direction in game.Move_Direction {
		if advised.kind == .Step && advised.direction == direction { continue }
		cell := game.add_position(room.player.position, game.direction_offset(direction))
		query := game.query_entity_movement(&room, game.PLAYER_ENTITY, cell)
		if _, foe := game.enemy_index_at(&room, cell); !foe && game.movement_query_is_clear(&query) { deviation = {kind = .Step, direction = direction}; break }
	}
	testing.expect(t, deviation.kind == .Step)
	commands, count := run_session.advisor_move_commands(&room, deviation)
	for command in commands[:count] { run_session.execute_gameplay_command(&room, command) }
	run_session.drive_advisor(&room, renderer, 0)
	advice := run_session.advisor_current_advice()
	testing.expectf(t, advice.valid && advice.pondered, "no advice in the frame after %v (advised %v): %v", deviation.kind, advised.kind, advice)
}
