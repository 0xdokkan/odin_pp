package western

// 6 RANCH 7: a western duel on horseback inside a thought bubble. After the
// ranch gate opens, both riders gallop down their own lane while a countdown
// strikes whole seconds. At every tick one coin goes to whoever pressed
// closest to it; the first to three coins wins. The simulation is pure: the
// host feeds real seconds and the press edge, and reads the cues for sound.

Phase :: enum u8 {
	Intro,
	Ride,
	Outro,
	Done,
}

Cue :: enum u8 {
	Card_Slot,
	Gate,
	Tick,
	Press,
	Coin_Player,
	Coin_Rival,
	Win,
	Lose,
}

PLAYER :: 0
RIVAL :: 1

// Intro beats, in seconds from the bubble's appearance.
INTRO_POP :: f32(0.3)
INTRO_CARD_SIX :: f32(0.55)
INTRO_CARD_SEVEN :: f32(0.8)
INTRO_CARD_FLIGHT :: f32(0.95)
INTRO_SIGN :: INTRO_CARD_SEVEN+INTRO_CARD_FLIGHT
INTRO_DOORS :: f32(2.25)
INTRO_DOORS_OPEN :: f32(3.0)
INTRO_RIDERS :: f32(3.1)
INTRO_SECONDS :: f32(4.3)

// The ride: a short lead-in, then one tick per second counting down.
RIDE_LEAD :: f32(1.4)
COUNTDOWN_FROM :: 5
COINS_TO_WIN :: 3
// A press belongs to the tick within half a second of it.
PRESS_WINDOW :: f32(0.5)
// The rival's press lands at the sum of two uniform draws in +-RIVAL_SPREAD:
// usually within a tenth of a second, never beyond RIVAL_LIMIT.
RIVAL_SPREAD :: f32(0.15)
RIVAL_LIMIT :: f32(0.45)
OUTRO_SECONDS :: f32(2.6)
OUTRO_CLOSE :: f32(0.35)

NO_PRESS :: f32(99)

Tick_Result :: struct {
	winner: int,
	offsets: [2]f32,
	// Ride time at which the coin was awarded.
	at: f32,
}

State :: struct {
	phase: Phase,
	// Seconds in the current phase.
	time: f32,
	// The next tick to resolve, and the presses gathered for it.
	tick: int,
	offsets: [2]f32,
	rival_offset: f32,
	coins: [2]int,
	results: [COUNTDOWN_FROM]Tick_Result,
	resolved: int,
	won: bool,
	// What happened during the last step, for sound and effects.
	cues: bit_set[Cue],
	rng: u64,
}

begin :: proc(seed: u64) -> (s: State) {
	s.rng = seed if seed != 0 else 0x6A5D_7E57_0000_0007
	s.offsets = {NO_PRESS, NO_PRESS}
	arm_rival(&s)
	return
}

// Ride time of a tick: the countdown leaves COUNTDOWN_FROM at the first one.
tick_time :: proc(index: int) -> f32 {
	return RIDE_LEAD+f32(index)
}

// The number on the countdown sign during the ride.
countdown :: proc(s: ^State) -> int {
	if s.phase == .Intro { return COUNTDOWN_FROM }
	if s.phase != .Ride { return COUNTDOWN_FROM-s.resolved }
	struck := 0
	for struck < COUNTDOWN_FROM && s.time >= tick_time(struck) { struck += 1 }
	return COUNTDOWN_FROM-struck
}

next_random :: proc(s: ^State) -> f32 {
	// splitmix64
	s.rng += 0x9E37_79B9_7F4A_7C15
	z := s.rng
	z = (z ~ (z >> 30))*0xBF58_476D_1CE4_E5B9
	z = (z ~ (z >> 27))*0x94D0_49BB_1331_11EB
	z = z ~ (z >> 31)
	return f32(z >> 40)/f32(1 << 24)
}

arm_rival :: proc(s: ^State) {
	a, b := next_random(s), next_random(s)
	s.rival_offset = clamp((a-0.5)*2*RIVAL_SPREAD+(b-0.5)*2*RIVAL_SPREAD, -RIVAL_LIMIT, RIVAL_LIMIT)
}

crossed :: proc(before, after, mark: f32) -> bool {
	return before < mark && after >= mark
}

step :: proc(s: ^State, dt: f32, press: bool) {
	s.cues = {}
	if s.phase == .Done { return }
	before := s.time
	s.time += max(dt, 0)
	switch s.phase {
	case .Intro:
		if crossed(before, s.time, INTRO_CARD_SIX+INTRO_CARD_FLIGHT) || crossed(before, s.time, INTRO_SIGN) { s.cues += {.Card_Slot} }
		if crossed(before, s.time, INTRO_DOORS) { s.cues += {.Gate} }
		if s.time >= INTRO_SECONDS {
			s.phase = .Ride
			s.time = 0
		}
	case .Ride:
		ride(s, before, press)
	case .Outro:
		if s.time >= OUTRO_SECONDS { s.phase = .Done }
	case .Done:
	}
}

ride :: proc(s: ^State, before: f32, press: bool) {
	t := tick_time(s.tick)
	if crossed(before, s.time, t) { s.cues += {.Tick} }
	// Earlier presses belong to a tick already settled and are spent.
	if press && s.time >= t-PRESS_WINDOW && s.offsets[PLAYER] == NO_PRESS {
		s.offsets[PLAYER] = s.time-t
		s.cues += {.Press}
	}
	if s.offsets[RIVAL] == NO_PRESS && s.time >= t+s.rival_offset { s.offsets[RIVAL] = s.rival_offset }
	// A tick settles once it struck and both pressed, or when its window closes.
	both := s.offsets[PLAYER] != NO_PRESS && s.offsets[RIVAL] != NO_PRESS
	if s.time >= t && (both || s.time >= t+PRESS_WINDOW) { resolve(s) }
}

resolve :: proc(s: ^State) {
	p, r := s.offsets[PLAYER], s.offsets[RIVAL]
	// The rival always presses; ties go to the player.
	winner := PLAYER if p != NO_PRESS && abs(p) <= abs(r) else RIVAL
	if s.resolved < COUNTDOWN_FROM {
		s.results[s.resolved] = {winner = winner, offsets = {p, r}, at = s.time}
		s.resolved += 1
	}
	s.coins[winner] += 1
	s.cues += {.Coin_Player if winner == PLAYER else .Coin_Rival}
	s.tick += 1
	s.offsets = {NO_PRESS, NO_PRESS}
	arm_rival(s)
	if s.coins[winner] >= COINS_TO_WIN || s.tick >= COUNTDOWN_FROM {
		s.won = s.coins[PLAYER] > s.coins[RIVAL]
		s.cues += {.Win if s.won else .Lose}
		s.phase = .Outro
		s.time = 0
	}
}
