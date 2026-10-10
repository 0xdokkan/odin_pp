package puzzle

import "core:testing"
import gfx "../../engine/gfx"
import host "../../engine/host"
import input "../../engine/input"
import rng "../../engine/rng"

// Puzzles are ~100 KB, so tests keep them on the heap (test threads have
// small stacks).
@(private = "file")
load :: proc(t: ^testing.T, rows: []string) -> ^Puzzle {
	b, s, err := parse_level(rows)
	testing.expect_value(t, err, Parse_Error.None)
	p := new(Puzzle)
	puzzle_init(p, b, s)
	return p
}

@(private = "file")
at :: proc(p: ^Puzzle, x, y: int) -> int {
	c, ok := cell_at(&p.board, x, y)
	assert(ok)
	return c
}

@(private = "file")
crate_on :: proc(p: ^Puzzle, x, y: int) -> bool {
	return crate_slot(&p.state, at(p, x, y)) >= 0
}

@(test)
test_push_moves_crate_and_player :: proc(t: ^testing.T) {
	p := load(t, {
		"#######",
		"#@$..o#",
		"#######",
	})
	defer free(p)
	r := apply_move(p, .Right)
	testing.expect(t, r.moved && r.pushed)
	testing.expect_value(t, r.crate, 0)
	testing.expect_value(t, int(p.state.player), at(p, 2, 1))
	testing.expect(t, crate_on(p, 3, 1))
	testing.expect_value(t, p.moves, 1)
	testing.expect(t, !r.solved)
	apply_move(p, .Right)
	r = apply_move(p, .Right)
	testing.expect(t, r.solved && r.sigil_filled)
	testing.expect(t, solved(p))
}

@(test)
test_blocked_pushes_leave_state_untouched :: proc(t: ^testing.T) {
	p := load(t, {
		"########",
		"#@$$..o#",
		"#.....o#",
		"#.$#...#",
		"########",
	})
	defer free(p)
	before := p.state
	// Two crates in a row cannot be pushed.
	r := apply_move(p, .Right)
	testing.expect(t, !r.moved)
	testing.expect_value(t, p.state, before)
	testing.expect_value(t, p.moves, 0)
	testing.expect_value(t, p.history_len, 0)
	// Walls stop the player, and a crate against a wall cannot be pushed.
	testing.expect(t, apply_move(p, .Down).moved)
	testing.expect(t, apply_move(p, .Down).moved)
	testing.expect(t, !apply_move(p, .Down).moved)
	testing.expect(t, !apply_move(p, .Left).moved)
	r = apply_move(p, .Right)
	testing.expect(t, !r.moved, "crate at (2,3) cannot go into the wall at (3,3)")
	testing.expect(t, crate_on(p, 2, 3))
}

@(test)
test_crate_slides_on_ice_until_blocked :: proc(t: ^testing.T) {
	p := load(t, {
		"##########",
		"#@$~~~~.o#",
		"#..~~~~#.#",
		"#.$~~~~#o#",
		"##########",
	})
	defer free(p)
	r := apply_move(p, .Right)
	testing.expect(t, r.pushed && r.crate_slid)
	// Slides over the ice and stops on the first plain floor tile.
	testing.expect_value(t, r.crate_to, at(p, 7, 1))
	testing.expect(t, crate_on(p, 7, 1))
	testing.expect_value(t, int(p.state.player), at(p, 2, 1))
	// Lower row: the wall stops the crate on the last ice tile.
	p.state.player = u8(at(p, 1, 3))
	r = apply_move(p, .Right)
	testing.expect(t, r.crate_slid)
	testing.expect_value(t, r.crate_to, at(p, 6, 3))
}

@(test)
test_player_slides_and_stops_at_obstacles :: proc(t: ^testing.T) {
	p := load(t, {
		"#########",
		"#@~~~~$.#",
		"#.~~~~..#",
		"#o.....o#",
		"#.$.....#",
		"#########",
	})
	defer free(p)
	r := apply_move(p, .Right)
	testing.expect(t, r.moved && r.player_slid && !r.pushed)
	// Stops on the ice right before the crate, without pushing it.
	testing.expect_value(t, int(p.state.player), at(p, 5, 1))
	testing.expect(t, crate_on(p, 6, 1))
	// Back across the ice: the slide ends on the first floor tile.
	r = apply_move(p, .Left)
	testing.expect(t, r.player_slid)
	testing.expect_value(t, int(p.state.player), at(p, 1, 1))
	// Down: across the ice row below, stopping on the floor after it.
	p.state.player = u8(at(p, 4, 1))
	r = apply_move(p, .Down)
	testing.expect_value(t, int(p.state.player), at(p, 4, 3))
	testing.expect(t, r.player_slid)
}

@(test)
test_pushed_crate_and_player_slide_together :: proc(t: ^testing.T) {
	q := load(t, {
		"########",
		"#.=%~~.#",
		"#o.....#",
		"########",
	})
	defer free(q)
	// Player and crate both on ice: the crate slides off to the floor and
	// the player glides behind it, stopping against it.
	rq := apply_move(q, .Right)
	testing.expect(t, rq.crate_slid && rq.player_slid)
	testing.expect_value(t, rq.crate_to, at(q, 6, 1))
	testing.expect_value(t, int(q.state.player), at(q, 5, 1))

	p := load(t, {
		"#########",
		"#.@$~~~.#",
		"#..~~~~.#",
		"#o......#",
		"#########",
	})
	defer free(p)
	r := apply_move(p, .Right)
	testing.expect(t, r.crate_slid)
	testing.expect_value(t, r.crate_to, at(p, 7, 1))
	// (3,1) is floor, so the player stops where the crate was.
	testing.expect_value(t, int(p.state.player), at(p, 3, 1))
	r = apply_move(p, .Right)
	// Now the player steps onto ice and slides up to the crate.
	testing.expect(t, r.player_slid)
	testing.expect_value(t, int(p.state.player), at(p, 6, 1))
}

@(test)
test_gate_opens_only_while_plate_pressed :: proc(t: ^testing.T) {
	p := load(t, {
		"##########",
		"#@$^|..o.#",
		"#...#....#",
		"#..$#....#",
		"##########",
	})
	defer free(p)
	testing.expect(t, !gates_open(&p.board, &p.state))
	r := apply_move(p, .Right)
	// Crate onto the plate: the gate opens.
	testing.expect(t, r.pushed && r.gates_opened)
	testing.expect(t, gates_open(&p.board, &p.state))
	// The crate can now be pushed into the gate, but then the plate is free
	// and the player (no longer holding it) cannot follow into the gate.
	r = apply_move(p, .Right)
	testing.expect(t, r.moved, "crate from the plate into the gate: the player now presses the plate")
	testing.expect(t, crate_on(p, 4, 1))
	testing.expect(t, gates_open(&p.board, &p.state))
	r = apply_move(p, .Right)
	testing.expect(t, !r.moved, "leaving the plate closes the gate the player would enter")
	testing.expect(t, crate_on(p, 4, 1))
}

@(test)
test_player_cannot_step_off_plate_onto_its_gate :: proc(t: ^testing.T) {
	p := load(t, {
		"########",
		"#.!|..o#",
		"#.$#...#",
		"########",
	})
	defer free(p)
	testing.expect(t, gates_open(&p.board, &p.state))
	r := apply_move(p, .Right)
	testing.expect(t, !r.moved)
	r = apply_move(p, .Left)
	testing.expect(t, r.moved && r.gates_closed)
}

@(test)
test_two_plates_need_two_weights :: proc(t: ^testing.T) {
	p := load(t, {
		"#########",
		"#^.$..|o#",
		"#..$..#.#",
		"#^...@#$#",
		"#########",
	})
	defer free(p)
	testing.expect_value(t, pressed_plates(&p.board, &p.state), 0)
	p.state.crates[0] = u8(at(p, 1, 1))
	testing.expect_value(t, pressed_plates(&p.board, &p.state), 1)
	testing.expect(t, !gates_open(&p.board, &p.state))
	p.state.player = u8(at(p, 1, 3))
	testing.expect(t, gates_open(&p.board, &p.state))
}

@(test)
test_closed_gate_stops_a_slide :: proc(t: ^testing.T) {
	p := load(t, {
		"##########",
		"#@$~~~|.o#",
		"#....^#..#",
		"#.....#.$#",
		"##########",
	})
	defer free(p)
	r := apply_move(p, .Right)
	testing.expect(t, r.crate_slid)
	testing.expect_value(t, r.crate_to, at(p, 5, 1))
}

@(test)
test_win_needs_every_sigil_and_allows_spare_crates :: proc(t: ^testing.T) {
	p := load(t, {
		"########",
		"#@$.o..#",
		"#.$....#",
		"#......#",
		"########",
	})
	defer free(p)
	testing.expect_value(t, p.board.sigil_count, 1)
	testing.expect_value(t, int(p.state.crate_count), 2)
	apply_move(p, .Right)
	r := apply_move(p, .Right)
	testing.expect(t, r.solved)
	testing.expect_value(t, covered_sigils(&p.board, &p.state), 1)
}

@(test)
test_undo_redo_restart_restore_exact_states :: proc(t: ^testing.T) {
	p := load(t, {
		"#########",
		"#.......#",
		"#.$~~~.o#",
		"#@..$.o.#",
		"#.......#",
		"#########",
	})
	defer free(p)
	start := p.state
	trail: [6]State
	dirs := [?]Dir{.Up, .Right, .Down, .Right, .Right, .Up}
	for d, i in dirs {
		testing.expect(t, apply_move(p, d).moved)
		trail[i] = p.state
	}
	moves := p.moves
	for i := len(dirs) - 1; i > 0; i -= 1 {
		testing.expect(t, undo(p))
		testing.expect_value(t, p.state, trail[i-1])
	}
	testing.expect(t, undo(p))
	testing.expect_value(t, p.state, start)
	testing.expect_value(t, p.moves, 0)
	testing.expect(t, !undo(p))
	for i in 0..<len(dirs) {
		testing.expect(t, redo(p))
		testing.expect_value(t, p.state, trail[i])
	}
	testing.expect(t, !redo(p))
	testing.expect_value(t, p.moves, moves)
	// Restart goes home and is itself undoable.
	testing.expect(t, restart(p))
	testing.expect_value(t, p.state, start)
	testing.expect_value(t, p.moves, 0)
	testing.expect(t, !restart(p))
	testing.expect(t, undo(p))
	testing.expect_value(t, p.state, trail[len(dirs)-1])
	testing.expect_value(t, p.moves, moves)
	// A new move clears the redo stack.
	testing.expect(t, undo(p))
	apply_move(p, .Left)
	testing.expect(t, !redo(p))
}

@(test)
test_history_overflow_drops_oldest :: proc(t: ^testing.T) {
	p := load(t, {
		"######",
		"#@...#",
		"#.$.o#",
		"######",
	})
	defer free(p)
	for i in 0..<HISTORY_CAP + 50 {
		apply_move(p, .Right if i%2 == 0 else .Left)
	}
	testing.expect_value(t, p.history_len, HISTORY_CAP)
	n := 0
	for undo(p) {
		n += 1
	}
	testing.expect_value(t, n, HISTORY_CAP)
}

@(test)
test_parse_rejects_bad_levels :: proc(t: ^testing.T) {
	check :: proc(t: ^testing.T, rows: []string, want: Parse_Error) {
		_, _, err := parse_level(rows)
		testing.expect_value(t, err, want)
	}
	check(t, {"#####", "#$.o#", "#####"}, .No_Player)
	check(t, {"#####", "#@.o#", "#####"}, .Too_Few_Crates)
	check(t, {"#####", "#@$.#", "#####"}, .No_Sigils)
	check(t, {"#####", "#@$o.", "#####"}, .Open_Edge)
	check(t, {"######", "#@$o|#", "######"}, .Gate_Without_Plate)
	check(t, {"#####", "#@$oX", "#####"}, .Bad_Char)
	check(t, {"#####", "#@$o#", "#@..#", "#####"}, .Many_Players)
}

@(test)
test_library_levels_are_valid_and_solvable_at_par :: proc(t: ^testing.T) {
	testing.expect(t, len(LEVELS) >= 12)
	ranks: [6]int
	for &level, i in LEVELS {
		b, s, err := parse_level(level.rows)
		testing.expectf(t, err == .None, "level %d %q: %v", i, level.name, err)
		if err != .None {
			continue
		}
		testing.expect(t, b.width <= MAX_W && b.height <= MAX_H)
		testing.expect(t, level.rank >= 1 && level.rank <= 5)
		ranks[level.rank] += 1
		st := s
		testing.expectf(t, !is_solved(&b, &st), "level %q starts solved", level.name)
		sol := solve(&b, s, 6_000_000)
		testing.expectf(t, sol.solved, "level %d %q unsolved (explored %d)", i, level.name, sol.explored)
		testing.expectf(t, sol.moves == level.par, "level %d %q: optimal %d, par %d", i, level.name, sol.moves, level.par)
		// Replaying the path really solves the level.
		p := new(Puzzle)
		puzzle_init(p, b, s)
		for d in sol.path {
			testing.expect(t, apply_move(p, d).moved)
		}
		testing.expect(t, solved(p))
		free(p)
		solution_destroy(&sol)
	}
	for r in 1..=5 {
		testing.expectf(t, ranks[r] > 0, "no level of rank %d", r)
	}
}

@(test)
test_dead_cell_pruning_keeps_optimum :: proc(t: ^testing.T) {
	for i in 0..<len(LEVELS) {
		level := &LEVELS[i]
		if level.rank > 2 {
			continue
		}
		b, s, _ := parse_level(level.rows)
		a := solve(&b, s, 2_000_000)
		c := solve(&b, s, 2_000_000, use_dead_cells = false)
		testing.expectf(t, a.solved == c.solved && a.moves == c.moves, "%q: %d vs %d", level.name, a.moves, c.moves)
		testing.expect(t, a.explored <= c.explored)
		solution_destroy(&a)
		solution_destroy(&c)
	}
}

@(test)
test_symmetries_preserve_par :: proc(t: ^testing.T) {
	for i in 0..<len(LEVELS) {
		level := &LEVELS[i]
		if level.rank > 2 {
			continue
		}
		b, s, _ := parse_level(level.rows)
		for tr in Transform {
			tb, ts := transform_level(b, s, tr)
			testing.expect_value(t, tb.sigil_count, b.sigil_count)
			sol := solve(&tb, ts, 2_000_000)
			testing.expectf(t, sol.solved && sol.moves == level.par, "%q under %v: %d", level.name, tr, sol.moves)
			solution_destroy(&sol)
		}
	}
}

@(test)
test_sequence_selection_is_deterministic :: proc(t: ^testing.T) {
	for challenge in ([?]bool{false, true}) {
		for seed in u64(1)..=u64(40) {
			a, na := plan_sequence(seed, challenge)
			b, nb := plan_sequence(seed, challenge)
			testing.expect_value(t, na, nb)
			testing.expect_value(t, a, b)
			if challenge {
				testing.expect_value(t, na, 1)
				testing.expect(t, LEVELS[a[0].index].par <= CHALLENGE_MAX_PAR)
			} else {
				testing.expect(t, na == 4)
			}
			for i in 0..<na {
				for j in i+1..<na {
					testing.expect(t, a[i].index != a[j].index, "a level repeats in a sequence")
				}
				if i > 0 {
					testing.expect(t, LEVELS[a[i].index].rank >= LEVELS[a[i-1].index].rank, "ranks must not fall")
				}
			}
		}
	}
	// Different seeds explore the library.
	seen: [len(LEVELS)]bool
	for seed in u64(0)..<200 {
		picks, n := plan_sequence(seed, false)
		for i in 0..<n {
			seen[picks[i].index] = true
		}
	}
	variety := 0
	for s in seen {
		if s {
			variety += 1
		}
	}
	testing.expect(t, variety >= len(LEVELS) - 4)
}

@(test)
test_random_soak_keeps_invariants :: proc(t: ^testing.T) {
	r := rng.create(99)
	for &level in LEVELS {
		p := new(Puzzle)
		b, s, _ := parse_level(level.rows)
		puzzle_init(p, b, s)
		crates := p.state.crate_count
		for step in 0..<2500 {
			roll := rng.below(&r, 10)
			switch {
			case roll < 7:
				apply_move(p, Dir(rng.below(&r, 4)))
			case roll < 9:
				undo(p)
			case:
				if rng.chance(&r, 0.1) {
					restart(p)
				} else {
					redo(p)
				}
			}
			st := &p.state
			testing.expect_value(t, st.crate_count, crates)
			inside := !walkable(p.board.tiles[st.player]) || crate_slot(st, int(st.player)) >= 0
			testing.expectf(t, !inside, "%q step %d: player inside a wall or crate", level.name, step)
			if inside {
				break
			}
			for i in 0..<int(st.crate_count) {
				testing.expect(t, walkable(p.board.tiles[st.crates[i]]))
				for j in i+1..<int(st.crate_count) {
					testing.expect(t, st.crates[i] != st.crates[j], "two crates share a cell")
				}
			}
			testing.expect(t, p.moves >= 0)
		}
		// Undo all the way back always reaches some earlier recorded state;
		// a restart then lands exactly on the start.
		restart(p)
		testing.expect_value(t, p.state, p.start)
		free(p)
	}
}

@(test)
test_stars_and_scores :: proc(t: ^testing.T) {
	testing.expect_value(t, level_stars(20, 20, 0), u8(3))
	testing.expect_value(t, level_stars(22, 20, 0), u8(3)) // slack of 2
	testing.expect_value(t, level_stars(23, 20, 0), u8(2))
	testing.expect_value(t, level_stars(30, 20, 0), u8(2))
	testing.expect_value(t, level_stars(31, 20, 0), u8(1))
	testing.expect_value(t, level_stars(100, 100, 0), u8(3))
	testing.expect_value(t, level_stars(110, 100, 0), u8(3)) // slack of par/10
	testing.expect_value(t, level_stars(20, 20, 1), u8(2))
	perfect := level_score(3, 20, 20, 0, 0)
	testing.expect_value(t, perfect, i64(500 + 750 + 750 + 250))
	testing.expect(t, level_score(3, 25, 20, 0, 0) < perfect)
	testing.expect(t, level_score(3, 20, 20, 10, 0) < perfect)
	testing.expect(t, level_score(3, 20, 20, 0, 1) < perfect)
	testing.expect(t, level_score(3, 500, 20, 400, 5) > 0)

	s := new(Session)
	defer free(s)
	s.count = 3
	s.results[0] = {cleared = true, stars = 3, score = 100}
	s.results[1] = {cleared = true, stars = 2, score = 50}
	s.results[2] = {cleared = true, stars = 2, score = 25}
	score, stars := session_score(s)
	testing.expect_value(t, score, i64(175))
	testing.expect_value(t, stars, u8(2)) // 7/3 = 2.33
	s.results[1].stars = 3
	_, stars = session_score(s)
	testing.expect_value(t, stars, u8(3)) // 8/3 = 2.67
}

@(test)
test_session_plays_through_and_torch_limits_challenge :: proc(t: ^testing.T) {
	s := new(Session)
	defer free(s)
	session_start(s, 7, false)
	testing.expect_value(t, s.torch_max, -1)
	for {
		p := &s.puzzle
		sol := solve(&p.board, p.state, 2_000_000)
		testing.expect(t, sol.solved)
		for d in sol.path {
			apply_move(p, d)
			testing.expect(t, !session_spend_torch(s))
		}
		solution_destroy(&sol)
		res := session_complete_level(s)
		testing.expect_value(t, res.stars, u8(3))
		if session_is_last(s) {
			break
		}
		session_load(s, s.current+1)
	}
	score, stars := session_score(s)
	testing.expect(t, score > 0)
	testing.expect_value(t, stars, u8(3))

	session_start(s, 7, true)
	testing.expect_value(t, s.count, 1)
	testing.expect_value(t, s.torch_max, torch_budget(s.par))
	testing.expect_value(t, torch_budget(20), 60)
	died := false
	for _ in 0..<s.torch_max {
		// Shuffle back and forth: moves that never solve anything.
		r := apply_move(&s.puzzle, .Left)
		if !r.moved {
			r = apply_move(&s.puzzle, .Right)
		}
		if !r.moved {
			r = apply_move(&s.puzzle, .Up)
		}
		if !r.moved {
			r = apply_move(&s.puzzle, .Down)
		}
		if session_spend_torch(s) {
			died = true
			break
		}
		undo(&s.puzzle) // undo never gives the light back
	}
	testing.expect(t, died)
	testing.expect_value(t, s.torch, 0)
}

@(test)
test_held_direction_repeats_after_delay :: proc(t: ^testing.T) {
	r: Repeat
	st: input.State(Action)
	dt := f32(1.0 / 100)
	feed :: proc(st: ^input.State(Action), down: bit_set[Action], dt: f32) {
		input.advance(st, input.Sample(Action){down = down}, dt)
	}
	fired := 0
	feed(&st, {.Right}, dt)
	a, ok := repeat_update(&r, &st, dt)
	testing.expect(t, ok && a == .Right)
	fired += 1
	// Held for one second: one initial press, then a repeat after 0.18 s and
	// every 0.09 s after that, about 10 more.
	for _ in 0..<99 {
		feed(&st, {.Right}, dt)
		if _, rep := repeat_update(&r, &st, dt); rep {
			fired += 1
		}
	}
	testing.expect(t, fired >= 9 && fired <= 12)
	// Releasing stops the repeat; a new press fires at once.
	feed(&st, {}, dt)
	_, ok = repeat_update(&r, &st, dt)
	testing.expect(t, !ok)
	feed(&st, {.Undo}, dt)
	a, ok = repeat_update(&r, &st, dt)
	testing.expect(t, ok && a == .Undo)
	// Restart never repeats.
	feed(&st, {}, dt)
	repeat_update(&r, &st, dt)
	feed(&st, {.Restart}, dt)
	a, ok = repeat_update(&r, &st, dt)
	testing.expect(t, ok && a == .Restart)
	for _ in 0..<60 {
		feed(&st, {.Restart}, dt)
		_, ok = repeat_update(&r, &st, dt)
		testing.expect(t, !ok)
	}
}

@(test)
test_sprite_rows_are_rectangular :: proc(t: ^testing.T) {
	check :: proc(t: ^testing.T, frames: []gfx.Frame_Rows, name: string) {
		w := len(frames[0][0])
		h := len(frames[0])
		for f in frames {
			testing.expectf(t, len(f) == h, "%s: frame height", name)
			for row in f {
				testing.expectf(t, len(row) == w, "%s: row %q has width %d, want %d", name, row, len(row), w)
			}
		}
	}
	check(t, FLOOR_ROWS[:], "floor")
	check(t, ICE_ROWS[:], "ice")
	check(t, SIGIL_ROWS[:], "sigil")
	check(t, PLATE_ROWS[:], "plate")
	check(t, GATE_SLOT_ROWS[:], "gate slot")
	check(t, GATE_BARS_ROWS[:], "gate bars")
	check(t, WALL_TOP_ROWS[:], "wall top")
	check(t, WALL_FRONT_ROWS[:], "wall front")
	check(t, CRATE_ROWS[:], "crate")
	check(t, HERO_ROWS[:], "hero")
	check(t, FLAME_ROWS[:], "flame")
	testing.expect_value(t, len(FLOOR_ROWS[0][0]), TILE_PX)
	testing.expect_value(t, len(WALL_FRONT_ROWS[0]), WALL_FRONT_PX)
}

@(test)
test_hint_line_is_tracked_while_followed :: proc(t: ^testing.T) {
	p := load(t, LEVELS[1].rows)
	defer free(p)
	h: Hint_Cache
	defer delete(h.path)
	sol := solve(&p.board, p.state, 100_000)
	h.path = sol.path
	h.state = p.state
	h.valid = true
	for i in 0..<3 {
		before := p.state
		apply_move(p, h.path[i])
		track_hint(&h, before, h.path[i], p.state)
	}
	testing.expect(t, h.valid)
	testing.expect_value(t, h.index, 3)
	before := p.state
	wrong := dir_opposite(h.path[3])
	if apply_move(p, wrong).moved {
		track_hint(&h, before, wrong, p.state)
		testing.expect(t, !h.valid)
	}
}

// The game layer without a window: sprites stay empty and only `step` runs,
// so phases, celebrations, level changes and the autoplay are exercised.
@(private = "file")
headless_game :: proc(config: host.Minigame_Config) -> ^Game {
	g := new(Game)
	g.canvas = {0, 0, 960, 540}
	game_reset(g, config)
	return g
}

@(private = "file")
headless_free :: proc(g: ^Game) {
	delete(g.hint.path)
	delete(g.demo.path)
	free(g)
}

@(private = "file")
run_until_done :: proc(g: ^Game, frame: ^host.Frame, max_seconds: f32) -> host.Round_Status {
	for _ in 0..<int(max_seconds*60) {
		status := game_step(g, frame, true)
		if status != .Playing {
			return status
		}
	}
	return .Playing
}

@(test)
test_game_autoplay_clears_a_free_play_run :: proc(t: ^testing.T) {
	for seed in ([2]u64{11, 12}) {
		g := headless_game({seed = seed})
		defer headless_free(g)
		testing.expect_value(t, g.phase, Phase.Enter)
		frame := host.Frame{dt = 1.0 / 60, canvas = g.canvas}
		// Paused frames hold everything still.
		for _ in 0..<30 {
			testing.expect_value(t, game_step(g, &frame, false), host.Round_Status.Playing)
		}
		testing.expect_value(t, g.phase, Phase.Enter)
		testing.expect_value(t, g.phase_time, f32(0))
		g.demo.enabled = true
		g.demo.limit = -1
		status := run_until_done(g, &frame, 600)
		testing.expect_value(t, status, host.Round_Status.Won)
		score, stars := game_score(g)
		testing.expect_value(t, stars, u8(3))
		testing.expect(t, score > 0)
		for i in 0..<g.session.count {
			testing.expect(t, g.session.results[i].cleared)
			testing.expect_value(t, g.session.results[i].moves, g.session.results[i].par)
		}
	}
}

@(test)
test_game_challenge_is_lost_when_the_torch_dies :: proc(t: ^testing.T) {
	g := headless_game({seed = 4, challenge = true})
	defer headless_free(g)
	frame := host.Frame{dt = 1.0 / 60, canvas = g.canvas}
	for g.phase == .Enter {
		game_step(g, &frame, true)
	}
	s := &g.session
	testing.expect_value(t, s.torch, torch_budget(s.par))
	// Hints are refused in a challenge.
	execute(g, &frame, .Hint)
	testing.expect_value(t, s.hints, 0)
	testing.expect(t, g.view.message_time > 0)
	for _ in 0..<10_000 {
		if g.phase != .Play {
			break
		}
		for d in Dir {
			before := s.puzzle.moves
			do_move(g, &frame, d)
			if s.puzzle.moves != before {
				break
			}
		}
		if g.phase == .Play {
			execute(g, &frame, .Undo)
		}
	}
	testing.expect_value(t, g.phase, Phase.Snuffed)
	testing.expect_value(t, s.torch, 0)
	testing.expect_value(t, run_until_done(g, &frame, 5), host.Round_Status.Lost)
	_, stars := game_score(g)
	testing.expect_value(t, stars, u8(0))
}

@(test)
test_game_hint_points_along_a_solution :: proc(t: ^testing.T) {
	g := headless_game({seed = 2})
	defer headless_free(g)
	frame := host.Frame{dt = 1.0 / 60, canvas = g.canvas}
	for g.phase == .Enter {
		game_step(g, &frame, true)
	}
	p := &g.session.puzzle
	execute(g, &frame, .Hint)
	testing.expect_value(t, g.session.hints, 1)
	testing.expect(t, g.view.hint_time > 0)
	// Following every hint solves the level, reusing the cached line.
	for _ in 0..<500 {
		if solved(p) {
			break
		}
		execute(g, &frame, .Hint)
		do_move(g, &frame, g.view.hint_dir)
	}
	testing.expect(t, solved(p))
	testing.expect_value(t, g.phase, Phase.Clear)
	testing.expect_value(t, g.result.stars, u8(2)) // hints cap the level at 2
}

@(test)
test_queued_command_waits_for_the_animation :: proc(t: ^testing.T) {
	g := headless_game({seed = 1})
	defer headless_free(g)
	frame := host.Frame{dt = 1.0 / 60, canvas = g.canvas}
	for g.phase == .Enter {
		game_step(g, &frame, true)
	}
	p := &g.session.puzzle
	sol := solve(&p.board, p.state, 100_000)
	defer solution_destroy(&sol)
	execute(g, &frame, Action(sol.path[0]))
	testing.expect_value(t, p.moves, 1)
	testing.expect(t, view_busy(&g.view, int(p.state.crate_count)))
	queue_command(g, Action(sol.path[1]))
	game_step(g, &frame, true)
	testing.expect_value(t, p.moves, 1) // still animating
	for _ in 0..<30 {
		game_step(g, &frame, true)
	}
	testing.expect_value(t, p.moves, 2)
	testing.expect(t, !g.has_queued)
}
