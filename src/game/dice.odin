package game

import rng "../engine/rng"

DICE_SEED_SALT :: u64(0x8CB92BA72F3D8DD7)
DEFAULT_DICE_SEED :: u64(0xDB4F0B9175AE2165)

MAX_ROLL_DICE :: 3

// Every dice card climbs the same ladder: upgrade level n rolls DICE_LADDER[n].
// An upgrade of a dice card changes only its die, so the ladder's top is also
// the most a dice card can be upgraded; the number of dice never changes.
DICE_LADDER :: [6]i32{4, 6, 8, 10, 12, 20}
MAX_DICE_UPGRADE_LEVEL :: i32(len(DICE_LADDER)-1)
MAX_DIE_SIDES :: i32(20)
// A face of at least this value is a success, whatever the die (Prismatic Barrage).
DICE_SUCCESS_THRESHOLD :: i32(4)

Dice_Roll :: struct {
	faces: [MAX_ROLL_DICE]i32,
	total: i32,
	// The die every face was rolled on: one of DICE_LADDER.
	sides: i32,
	// An i32 like the faces: the roll stays 24 bytes. Every Game_Event carries
	// one, and the fixed event logs sit just under their stack budget.
	count: i32,
}

@(private)
dice_sides_are_valid :: proc(sides: i32) -> bool {
	for step in DICE_LADDER {
		if sides == step { return true }
	}
	return false
}

validate_dice_roll :: proc(roll: ^Dice_Roll) -> bool {
	if roll == nil || roll.count < 1 || roll.count > MAX_ROLL_DICE || !dice_sides_are_valid(roll.sides) {
		return false
	}
	total: i32
	for face in roll.faces[:roll.count] {
		if face < 1 || face > roll.sides { return false }
		total += face
	}
	for face in roll.faces[roll.count:] {
		if face != 0 { return false }
	}
	return roll.total == total
}

// Pattern queries consume no random state; presentation may use the logged pool.
dice_success_count :: proc(roll: ^Dice_Roll, threshold: i32 = DICE_SUCCESS_THRESHOLD) -> int {
	if !validate_dice_roll(roll) || threshold < 1 || threshold > roll.sides { return 0 }
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

@(private)
validate_dice_state :: proc(dice: ^Dice_State) -> bool {
	return dice != nil && dice.random_state != 0
}

// Call only on staged state. Preview and targeting never access this stream.
roll_die :: proc(dice: ^Dice_State, sides: i32) -> (face: i32, ok: bool) {
	if sides < 2 || sides > MAX_DIE_SIDES || !validate_dice_state(dice) || dice.roll_count == max(u64) {
		return 0, false
	}
	// Rejection sampling removes modulo bias; the counter counts dice, not samples.
	value := rng.below_state(&dice.random_state, u64(sides))
	dice.roll_count += 1
	return i32(value)+1, true
}

// A pool is one transaction. Even exhaustion on its final die leaves the source
// stream untouched; roll_count remains the number of individual dice committed.
roll_dice_pool :: proc(dice: ^Dice_State, count: int, sides: i32) -> (roll: Dice_Roll, ok: bool) {
	if count < 1 || count > MAX_ROLL_DICE || !dice_sides_are_valid(sides) || !validate_dice_state(dice) ||
	   u64(count) > max(u64)-dice.roll_count {
		return {}, false
	}
	staged := dice^
	roll.count, roll.sides = i32(count), sides
	for index in 0..<count {
		face, rolled := roll_die(&staged, sides)
		if !rolled { return {}, false }
		roll.faces[index] = face
		roll.total += face
	}
	dice^ = staged
	return roll, true
}

// The die a dice card rolls at an upgrade level: a D4 at level 0, one ladder
// step per upgrade. 0 for a card without dice or a level beyond the ladder.
card_die_sides :: proc(card: Card_Id, upgrade_level: i32) -> i32 {
	if card_dice_count(card) == 0 || upgrade_level < 0 || upgrade_level > MAX_DICE_UPGRADE_LEVEL { return 0 }
	// The Dinosauro's die names a dinosaur: a d4 at every level (its upgrades are seconds).
	if card == .Dinosaur { return RIDE_DIE_SIDES }
	ladder := DICE_LADDER
	return ladder[upgrade_level]
}

// The one roll of a played dice card: card_dice_count dice of its level's die.
// Every card listed by card_dice_count rolls here, so a new dice card inherits
// the ladder, the upgrade cap, the texts and the presentation.
roll_card_dice :: proc(dice: ^Dice_State, card: Card_Instance) -> (Dice_Roll, bool) {
	return roll_dice_pool(dice, card_dice_count(card.definition_id), card_die_sides(card.definition_id, card.upgrade_level))
}
