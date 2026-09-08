package game

DICE_SEED_SALT :: u64(0x8CB92BA72F3D8DD7)
DEFAULT_DICE_SEED :: u64(0xDB4F0B9175AE2165)

MAX_ROLL_DICE :: 3

Dice_Roll :: struct {
	faces: [MAX_ROLL_DICE]i32,
	total: i32,
	count: int,
}

validate_dice_roll :: proc(roll: ^Dice_Roll) -> bool {
	if roll == nil || roll.count < 1 || roll.count > MAX_ROLL_DICE {
		return false
	}
	total: i32
	for face in roll.faces[:roll.count] {
		if face < 1 || face > 6 { return false }
		total += face
	}
	for face in roll.faces[roll.count:] {
		if face != 0 { return false }
	}
	return roll.total == total
}

// Pattern queries consume no random state; presentation may use the logged pool.
dice_success_count :: proc(roll: ^Dice_Roll, threshold: i32 = 4) -> int {
	if threshold < 1 || threshold > 6 || !validate_dice_roll(roll) { return 0 }
	successes := 0
	for face in roll.faces[:roll.count] {
		if face >= threshold { successes += 1 }
	}
	return successes
}

dice_has_pair :: proc(roll: ^Dice_Roll) -> bool {
	if !validate_dice_roll(roll) { return false }
	for first in 0..<roll.count {
		for second in first+1..<roll.count {
			if roll.faces[first] == roll.faces[second] { return true }
		}
	}
	return false
}

Dice_State :: struct {
	random_state: u64,
	roll_count: u64,
}

make_dice_state :: proc(seed: u64) -> Dice_State {
	state := mix_room_seed(seed~DICE_SEED_SALT)
	return {random_state = state if state != 0 else DEFAULT_DICE_SEED}
}

validate_dice_state :: proc(dice: ^Dice_State) -> bool {
	return dice != nil && dice.random_state != 0
}

// Call only on staged state. Preview and targeting never access this stream.
roll_d6 :: proc(dice: ^Dice_State) -> (face: i32, ok: bool) {
	if !validate_dice_state(dice) || dice.roll_count == max(u64) {
		return 0, false
	}
	// Rejection sampling removes modulo bias; the counter counts dice, not samples.
	for {
		value := dice.random_state
		value ~= value >> 12
		value ~= value << 25
		value ~= value >> 27
		dice.random_state = value
		value *= 0x2545F4914F6CDD1D
		if value < u64(4) { continue }
		dice.roll_count += 1
		return i32(value%6)+1, true
	}
}

// A pool is one transaction. Even exhaustion on its final die leaves the source
// stream untouched; roll_count remains the number of individual dice committed.
roll_d6_pool :: proc(dice: ^Dice_State, count: int) -> (roll: Dice_Roll, ok: bool) {
	if count < 1 || count > MAX_ROLL_DICE || !validate_dice_state(dice) ||
	   u64(count) > max(u64)-dice.roll_count {
		return {}, false
	}
	staged := dice^
	roll.count = count
	for index in 0..<count {
		face, rolled := roll_d6(&staged)
		if !rolled { return {}, false }
		roll.faces[index] = face
		roll.total += face
	}
	dice^ = staged
	return roll, true
}
