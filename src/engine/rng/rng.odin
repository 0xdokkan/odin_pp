// Deterministic random streams shared by every game mode.
//
// One stream is a single u64 of state, so it can be copied, staged and
// committed like any other value. `next_u64` is xorshift64*, the generator the
// roguelike already used for deck, dice and economy; `derive` is the
// splitmix64 finaliser used to give every domain an independent seed.
package rng

Rng :: struct {
	state: u64,
}

GOLDEN_GAMMA :: 0x9E3779B97F4A7C15

// splitmix64 finaliser: a bijective, well mixed hash of one u64.
mix :: proc "contextless" (value: u64) -> u64 {
	z := value
	z = (z ~ (z >> 30)) * 0xBF58476D1CE4E5B9
	z = (z ~ (z >> 27)) * 0x94D049BB133111EB
	return z ~ (z >> 31)
}

// Seeds for separate domains (map, loot, AI...) stay independent even when the
// root seed is small or the salts are consecutive.
derive :: proc "contextless" (seed: u64, salt: u64) -> u64 {
	return mix(seed + GOLDEN_GAMMA*(salt+1))
}

// xorshift has a fixed point at zero, so a zero seed is remapped.
create :: proc "contextless" (seed: u64) -> Rng {
	state := mix(seed)
	if state == 0 {
		state = GOLDEN_GAMMA
	}
	return Rng{state = state}
}

// Uses an already mixed, non-zero state verbatim. Kept for streams whose exact
// sequence is pinned by saved seeds and tests.
from_state :: proc "contextless" (state: u64) -> Rng {
	return Rng{state = state if state != 0 else GOLDEN_GAMMA}
}

next_u64 :: proc "contextless" (r: ^Rng) -> u64 {
	x := r.state
	x ~= x >> 12
	x ~= x << 25
	x ~= x >> 27
	r.state = x
	return x * 0x2545F4914F6CDD1D
}

next_u32 :: proc "contextless" (r: ^Rng) -> u32 {
	return u32(next_u64(r) >> 32)
}

// Uniform in [0, bound) without modulo bias. bound must be positive.
below :: proc "contextless" (r: ^Rng, bound: u64) -> u64 {
	if bound <= 1 {
		return 0
	}
	// Reject the low `2^64 mod bound` values so every residue is equally likely.
	threshold := (0 - bound) % bound
	for {
		value := next_u64(r)
		if value >= threshold {
			return value % bound
		}
	}
}

// Uniform integer in [low, high], inclusive on both ends.
int_range :: proc "contextless" (r: ^Rng, low, high: int) -> int {
	if high <= low {
		return low
	}
	span := u64(high - low) + 1
	return low + int(below(r, span))
}

// Uniform float in [0, 1) with 24 bits of precision.
float01 :: proc "contextless" (r: ^Rng) -> f32 {
	return f32(next_u64(r) >> 40) * (1.0 / f32(1 << 24))
}

float_range :: proc "contextless" (r: ^Rng, low, high: f32) -> f32 {
	return low + (high-low)*float01(r)
}

// Uniform in [-1, 1).
float_signed :: proc "contextless" (r: ^Rng) -> f32 {
	return float01(r)*2 - 1
}

chance :: proc "contextless" (r: ^Rng, probability: f32) -> bool {
	if probability <= 0 {
		return false
	}
	if probability >= 1 {
		return true
	}
	return float01(r) < probability
}

// Fisher-Yates with unbiased draws.
shuffle :: proc(r: ^Rng, items: []$T) {
	for i := len(items) - 1; i > 0; i -= 1 {
		j := int(below(r, u64(i) + 1))
		items[i], items[j] = items[j], items[i]
	}
}

pick :: proc(r: ^Rng, items: []$T) -> (T, bool) {
	if len(items) == 0 {
		return {}, false
	}
	return items[below(r, u64(len(items)))], true
}

// Index chosen with probability proportional to its weight. Non-positive
// weights are never chosen; returns false when no weight is positive.
weighted_index :: proc(r: ^Rng, weights: []int) -> (int, bool) {
	total: u64
	for weight in weights {
		if weight > 0 {
			total += u64(weight)
		}
	}
	if total == 0 {
		return -1, false
	}
	roll := below(r, total)
	for weight, index in weights {
		if weight <= 0 {
			continue
		}
		if roll < u64(weight) {
			return index, true
		}
		roll -= u64(weight)
	}
	return -1, false
}

// Point uniformly distributed inside the unit disc.
unit_disc :: proc "contextless" (r: ^Rng) -> [2]f32 {
	for {
		p := [2]f32{float_signed(r), float_signed(r)}
		if p.x*p.x+p.y*p.y <= 1 {
			return p
		}
	}
}
