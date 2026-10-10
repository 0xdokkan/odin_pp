package puzzle

import rng "../../engine/rng"

// A round: the planned sequence of levels, the level in play and the results
// so far. Pure like the rules, so selection and scoring are tested headless.

MAX_SEQUENCE :: 5

Level_Pick :: struct {
	index:     int, // into LEVELS
	transform: Transform,
}

Level_Result :: struct {
	cleared: bool,
	moves:   int,
	par:     int,
	undos:   int,
	hints:   int,
	stars:   u8,
	score:   i64,
}

Session :: struct {
	seed:       u64,
	challenge:  bool,
	picks:      [MAX_SEQUENCE]Level_Pick,
	count:      int,
	current:    int,
	results:    [MAX_SEQUENCE]Level_Result,
	puzzle:     Puzzle,
	par:        int,
	hints:      int, // hints taken on the current level
	// Challenge only: moves left before the torch goes out. Undo does not
	// give light back, otherwise the limit could be dodged.
	torch:      int,
	torch_max:  int,
}

// Free play climbs through ranks; a challenge is one mid-sized level.
@(private)
sequence_ranks :: proc(challenge: bool) -> (ranks: [MAX_SEQUENCE]int, count: int) {
	if challenge {
		ranks[0] = 3
		return ranks, 1
	}
	ranks = {1, 2, 3, 4, 0}
	return ranks, 4
}

// A challenge interrupts a run, so its level stays short.
CHALLENGE_MAX_PAR :: 62

// Deterministic for a (seed, challenge) pair. A level never
// repeats within a sequence; mirrored or rotated variants keep par intact.
plan_sequence :: proc(seed: u64, challenge: bool) -> (picks: [MAX_SEQUENCE]Level_Pick, count: int) {
	ranks, n := sequence_ranks(challenge)
	max_par := CHALLENGE_MAX_PAR if challenge else 0
	r := rng.create(rng.derive(seed, 0x51C1))
	used: [len(LEVELS)]bool
	for slot in 0..<n {
		// Widen the rank window until something unused turns up; the par cap
		// is dropped only as a last resort.
		chosen := -1
		search: for capped in ([?]bool{true, false}) {
			for spread in 0..<5 {
				candidates: [len(LEVELS)]int
				found := 0
				for &level, i in LEVELS {
					fits := !capped || max_par == 0 || level.par <= max_par
					if !used[i] && fits && abs(level.rank-ranks[slot]) <= spread {
						candidates[found] = i
						found += 1
					}
				}
				if found > 0 {
					chosen = candidates[rng.below(&r, u64(found))]
					break search
				}
			}
		}
		if chosen < 0 {
			break
		}
		used[chosen] = true
		picks[count] = Level_Pick{index = chosen, transform = pick_transform(&r, chosen)}
		count += 1
	}
	// A widened window may borrow from a neighbouring rank: keep the climb.
	for i in 1..<count {
		v := picks[i]
		j := i
		for j > 0 && LEVELS[picks[j-1].index].rank > LEVELS[v.index].rank {
			picks[j] = picks[j-1]
			j -= 1
		}
		picks[j] = v
	}
	return
}

// Quarter turns are only used when the rotated room still fits and stays
// wider than tall, which suits the 16:9 screen.
@(private)
pick_transform :: proc(r: ^rng.Rng, level: int) -> Transform {
	b, _, err := parse_level(LEVELS[level].rows)
	if err != .None {
		return .Identity
	}
	options: [8]Transform
	n := 0
	for t in Transform {
		if transform_swaps_axes(t) && (b.height > MAX_W || b.width > MAX_H || b.height < b.width) {
			continue
		}
		options[n] = t
		n += 1
	}
	return options[rng.below(r, u64(n))]
}

session_start :: proc(s: ^Session, seed: u64, challenge: bool) {
	s.seed = seed
	s.challenge = challenge
	s.picks, s.count = plan_sequence(seed, challenge)
	s.results = {}
	session_load(s, 0)
}

// Replaces the plan with one level, used by the preview harness and tests.
session_force_level :: proc(s: ^Session, level: int, transform := Transform.Identity) {
	s.picks = {}
	s.picks[0] = Level_Pick{index = clamp(level, 0, len(LEVELS) - 1), transform = transform}
	s.count = 1
	s.results = {}
	session_load(s, 0)
}

session_load :: proc(s: ^Session, index: int) {
	s.current = clamp(index, 0, max(s.count-1, 0))
	pick := s.picks[s.current]
	def := LEVELS[pick.index]
	b, st, err := parse_level(def.rows)
	assert(err == .None, "library levels are validated by the tests")
	b, st = transform_level(b, st, pick.transform)
	puzzle_init(&s.puzzle, b, st)
	s.par = def.par
	s.hints = 0
	s.torch_max = torch_budget(def.par) if s.challenge else -1
	s.torch = s.torch_max
}

// Undone moves still count against the fixed challenge allowance.
torch_budget :: proc(par: int) -> int {
	return par*5/2 + 10
}

session_level :: proc(s: ^Session) -> ^Level_Def {
	return &LEVELS[s.picks[s.current].index]
}

session_is_last :: proc(s: ^Session) -> bool {
	return s.current >= s.count - 1
}

// Spends light for a move that happened; true when the torch just died
// without the level being solved.
session_spend_torch :: proc(s: ^Session) -> bool {
	if s.torch_max < 0 {
		return false
	}
	s.torch = max(s.torch-1, 0)
	return s.torch == 0 && !solved(&s.puzzle)
}

// Records the solved level; the caller advances with session_load.
session_complete_level :: proc(s: ^Session) -> Level_Result {
	p := &s.puzzle
	level := session_level(s)
	res := Level_Result{
		cleared = true,
		moves   = p.moves,
		par     = s.par,
		undos   = p.undos,
		hints   = s.hints,
	}
	res.stars = level_stars(p.moves, s.par, s.hints)
	res.score = level_score(level.rank, p.moves, s.par, p.undos, s.hints)
	s.results[s.current] = res
	return res
}

// Slack keeps 3 stars reachable for players a couple of moves off optimal.
par_slack :: proc(par: int) -> int {
	return max(2, par/10)
}

// 3 = within par + slack, 2 = within 1.5x par, 1 = solved. A hint caps the
// level at 2 stars.
level_stars :: proc(moves, par, hints: int) -> u8 {
	stars: u8 = 1
	if moves <= par+par_slack(par) {
		stars = 3
	} else if moves*2 <= par*3 {
		stars = 2
	}
	if hints > 0 {
		stars = min(stars, 2)
	}
	return stars
}

// Base by rank, up to +750 for efficiency (full at par, nothing at 2x par),
// +250 for a perfect solution, small costs for undos and hints.
level_score :: proc(rank, moves, par, undos, hints: int) -> i64 {
	base := 500 + 250*rank
	p := max(par, 1)
	efficiency := clamp(f32(2*p-moves)/f32(p), 0, 1)
	bonus := int(750 * efficiency)
	if moves <= par {
		bonus += 250
	}
	total := base + bonus - 5*undos - 200*hints
	return i64(max(total, base/4))
}

// Free play stars are the rounded average over the sequence (a level not
// cleared counts as 0); a challenge has a single level.
session_score :: proc(s: ^Session) -> (score: i64, stars: u8) {
	sum := 0
	for i in 0..<s.count {
		r := s.results[i]
		score += r.score
		sum += int(r.stars)
	}
	if s.count > 0 {
		stars = u8(clamp((2*sum + s.count) / (2*s.count), 0, 3))
	}
	return
}
