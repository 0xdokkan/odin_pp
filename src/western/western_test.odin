package western

import "core:testing"

FRAME :: f32(1.0/60.0)

// Steps through the intro so the ride starts at time zero.
ride_ready :: proc(seed: u64) -> State {
	s := begin(seed)
	for s.phase == .Intro { step(&s, FRAME, false) }
	return s
}

// Presses on the frame nearest to each tick, plus `late` seconds.
press_on_ticks :: proc(s: ^State, late: f32) {
	for s.phase == .Ride {
		target := tick_time(s.tick)+late
		// The step adds a frame before it reads the press.
		press := s.time+FRAME >= target-FRAME*0.5 && s.offsets[PLAYER] == NO_PRESS
		step(s, FRAME, press)
	}
}

@(test)
test_western_intro_runs_its_beats_then_the_ride :: proc(t: ^testing.T) {
	s := begin(7)
	cues: bit_set[Cue]
	for s.phase == .Intro {
		step(&s, FRAME, true)
		cues += s.cues
	}
	testing.expect(t, .Card_Slot in cues && .Gate in cues)
	testing.expect_value(t, s.phase, Phase.Ride)
	// Presses during the intro never count toward a tick.
	testing.expect_value(t, s.offsets[PLAYER], NO_PRESS)
	testing.expect_value(t, countdown(&s), COUNTDOWN_FROM)
}

@(test)
test_western_presses_on_the_tick_beat_the_rival :: proc(t: ^testing.T) {
	for seed in u64(1)..=20 {
		s := ride_ready(seed)
		press_on_ticks(&s, 0)
		testing.expect(t, s.won)
		testing.expect_value(t, s.coins[PLAYER], COINS_TO_WIN)
		for result in s.results[:s.resolved] { testing.expect(t, abs(result.offsets[PLAYER]) <= FRAME) }
		for s.phase == .Outro { step(&s, FRAME, false) }
		testing.expect_value(t, s.phase, Phase.Done)
	}
}

@(test)
test_western_without_presses_the_cowboy_takes_three_straight :: proc(t: ^testing.T) {
	s := ride_ready(3)
	cues: bit_set[Cue]
	ticks := 0
	for s.phase == .Ride {
		step(&s, FRAME, false)
		cues += s.cues
		if .Tick in s.cues { ticks += 1 }
	}
	testing.expect(t, !s.won && .Lose in cues && .Coin_Rival in cues && .Coin_Player not_in cues)
	testing.expect_value(t, s.coins, [2]int{0, COINS_TO_WIN})
	testing.expect_value(t, ticks, COINS_TO_WIN)
	testing.expect_value(t, countdown(&s), COUNTDOWN_FROM-COINS_TO_WIN)
}

@(test)
test_western_each_tick_takes_one_press_from_its_own_window :: proc(t: ^testing.T) {
	s := ride_ready(11)
	// Too early: the window for the first tick is not open yet.
	for s.time < tick_time(0)-PRESS_WINDOW-0.1 { step(&s, FRAME, false) }
	step(&s, FRAME, true)
	testing.expect_value(t, s.offsets[PLAYER], NO_PRESS)
	// Inside the window the first press counts and a second one changes nothing.
	for s.time < tick_time(0)-0.2 { step(&s, FRAME, false) }
	step(&s, FRAME, true)
	first := s.offsets[PLAYER]
	testing.expect(t, first < -0.15 && first > -0.25)
	step(&s, FRAME, true)
	testing.expect_value(t, s.offsets[PLAYER], first)
	for s.resolved == 0 { step(&s, FRAME, false) }
	testing.expect_value(t, s.results[0].offsets[PLAYER], first)
	testing.expect_value(t, s.results[0].winner, PLAYER if abs(first) <= abs(s.results[0].offsets[RIVAL]) else RIVAL)
}

@(test)
test_western_ties_favour_the_player_and_seeds_repeat :: proc(t: ^testing.T) {
	s := ride_ready(5)
	s.offsets = {0.1, -0.1}
	resolve(&s)
	testing.expect_value(t, s.results[0].winner, PLAYER)
	a, b := begin(42), begin(42)
	for _ in 0..<8 {
		testing.expect_value(t, a.rival_offset, b.rival_offset)
		testing.expect(t, abs(a.rival_offset) <= RIVAL_LIMIT)
		arm_rival(&a)
		arm_rival(&b)
	}
	// A frame hitch cannot skip a coin: the window still settles the tick.
	s = ride_ready(9)
	step(&s, tick_time(0)+PRESS_WINDOW+0.01, false)
	testing.expect_value(t, s.resolved, 1)
	testing.expect_value(t, s.results[0].winner, RIVAL)
}
