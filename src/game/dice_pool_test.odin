package game

import "core:testing"

@(test)
test_dice_pool_matches_individual_rolls_and_keeps_face_order :: proc(t: ^testing.T) {
	for count in 1..=MAX_ROLL_DICE {
		for seed in u64(1)..=u64(32) {
			pool_state := make_dice_state(seed)
			individual_state := pool_state
			pool, ok := roll_d6_pool(&pool_state, count)
			testing.expect(t, ok && validate_dice_roll(&pool))
			testing.expect_value(t, pool.count, count)
			total: i32
			for index in 0..<count {
				face, rolled := roll_d6(&individual_state)
				testing.expect(t, rolled)
				testing.expect_value(t, pool.faces[index], face)
				total += face
			}
			testing.expect_value(t, pool.total, total)
			testing.expect_value(t, pool_state, individual_state)
			testing.expect_value(t, pool_state.roll_count, u64(count))
		}
	}
}

@(test)
test_dice_pool_rejection_and_counter_exhaustion_are_transactional :: proc(t: ^testing.T) {
	state := make_dice_state(123)
	for count in ([3]int{-1, 0, MAX_ROLL_DICE+1}) {
		before := state
		pool, ok := roll_d6_pool(&state, count)
		testing.expect(t, !ok)
		testing.expect_value(t, pool, Dice_Roll{})
		testing.expect_value(t, state, before)
	}
	state.roll_count = max(u64)-1
	before := state
	pool, ok := roll_d6_pool(&state, 2)
	testing.expect(t, !ok)
	testing.expect_value(t, pool, Dice_Roll{})
	testing.expect_value(t, state, before)
	state.roll_count = max(u64)-u64(MAX_ROLL_DICE)
	pool, ok = roll_d6_pool(&state, MAX_ROLL_DICE)
	testing.expect(t, ok && validate_dice_roll(&pool))
	testing.expect_value(t, state.roll_count, max(u64))
	before = state
	_, ok = roll_d6_pool(&state, 1)
	testing.expect(t, !ok)
	testing.expect_value(t, state, before)
	_, ok = roll_d6_pool(nil, 1)
	testing.expect(t, !ok)
	state = {}
	_, ok = roll_d6_pool(&state, 1)
	testing.expect(t, !ok)
	testing.expect_value(t, state, Dice_State{})
}

@(test)
test_dice_pool_validation_rejects_bad_totals_faces_counts_and_hidden_tail :: proc(t: ^testing.T) {
	valid := Dice_Roll{faces = {2, 6, 0}, count = 2, total = 8}
	testing.expect(t, validate_dice_roll(&valid))
	testing.expect(t, !validate_dice_roll(nil))
	for corruption in 0..<7 {
		roll := valid
		switch corruption {
		case 0: roll.count = 0
		case 1: roll.count = MAX_ROLL_DICE+1
		case 2: roll.count = -1
		case 3: roll.faces[0] = 0
		case 4: roll.faces[0] = 7
		case 5: roll.total += 1
		case 6: roll.faces[2] = 1
		}
		testing.expect(t, !validate_dice_roll(&roll))
	}
}
