package game

import "core:testing"

@(test)
test_dice_pool_matches_individual_rolls_and_keeps_face_order :: proc(t: ^testing.T) {
	for sides in DICE_LADDER {
		seen: [MAX_DIE_SIDES+1]bool
		for count in 1..=MAX_ROLL_DICE {
			// Face reachability belongs to the primitive, once per die. Other
			// pool sizes still cover ordering and identical stream consumption.
			seed_count := u64(256) if count == 1 else u64(32)
			for seed in u64(1)..=seed_count {
				pool_state := make_dice_state(seed)
				individual_state := pool_state
				pool, ok := roll_dice_pool(&pool_state, count, sides)
				if !testing.expect(t, ok && validate_dice_roll(&pool)) { continue }
				testing.expect_value(t, pool.count, i32(count))
				testing.expect_value(t, pool.sides, sides)
				total: i32
				for index in 0..<count {
					face, rolled := roll_die(&individual_state, sides)
					testing.expect(t, rolled)
					testing.expect_value(t, pool.faces[index], face)
					seen[pool.faces[index]] = true
					total += face
				}
				testing.expect_value(t, pool.total, total)
				testing.expect_value(t, pool_state, individual_state)
				testing.expect_value(t, pool_state.roll_count, u64(count))
			}
		}
		for face in 1..=sides { testing.expect(t, seen[face]) }
		for face in sides+1..=MAX_DIE_SIDES { testing.expect(t, !seen[face]) }
	}
}

@(test)
test_dice_pool_rejection_and_counter_exhaustion_are_transactional :: proc(t: ^testing.T) {
	state := make_dice_state(123)
	for count in ([3]int{-1, 0, MAX_ROLL_DICE+1}) {
		before := state
		pool, ok := roll_dice_pool(&state, count, 6)
		testing.expect(t, !ok)
		testing.expect_value(t, pool, Dice_Roll{})
		testing.expect_value(t, state, before)
	}
	// Only the ladder's dice exist: no D2, D7 or D100 pool.
	for sides in ([5]i32{0, 2, 7, 21, 100}) {
		before := state
		pool, ok := roll_dice_pool(&state, 1, sides)
		testing.expect(t, !ok)
		testing.expect_value(t, pool, Dice_Roll{})
		testing.expect_value(t, state, before)
	}
	state.roll_count = max(u64)-1
	before := state
	pool, ok := roll_dice_pool(&state, 2, 6)
	testing.expect(t, !ok)
	testing.expect_value(t, pool, Dice_Roll{})
	testing.expect_value(t, state, before)
	state.roll_count = max(u64)-u64(MAX_ROLL_DICE)
	pool, ok = roll_dice_pool(&state, MAX_ROLL_DICE, 20)
	testing.expect(t, ok && validate_dice_roll(&pool))
	testing.expect_value(t, state.roll_count, max(u64))
	before = state
	_, ok = roll_dice_pool(&state, 1, 4)
	testing.expect(t, !ok)
	testing.expect_value(t, state, before)
	_, ok = roll_dice_pool(nil, 1, 4)
	testing.expect(t, !ok)
	state = {}
	_, ok = roll_dice_pool(&state, 1, 4)
	testing.expect(t, !ok)
	testing.expect_value(t, state, Dice_State{})
}

@(test)
test_dice_pool_validation_rejects_bad_totals_faces_counts_and_hidden_tail :: proc(t: ^testing.T) {
	valid := Dice_Roll{faces = {2, 6, 0}, sides = 6, count = 2, total = 8}
	testing.expect(t, validate_dice_roll(&valid))
	testing.expect(t, !validate_dice_roll(nil))
	for corruption in 0..<9 {
		roll := valid
		switch corruption {
		case 0: roll.count = 0
		case 1: roll.count = MAX_ROLL_DICE+1
		case 2: roll.count = -1
		case 3: roll.faces[0] = 0
		case 4: roll.faces[0] = 7
		case 5: roll.total += 1
		case 6: roll.faces[2] = 1
		case 7: roll.sides = 4 // a six cannot sit on a D4
		case 8: roll.sides = 7
		}
		testing.expect(t, !validate_dice_roll(&roll))
	}
	big := Dice_Roll{faces = {20, 13, 0}, sides = 20, count = 2, total = 33}
	testing.expect(t, validate_dice_roll(&big))
}

@(test)
test_dice_cards_climb_the_ladder_from_d4_to_d20 :: proc(t: ^testing.T) {
	ladder := DICE_LADDER
	testing.expect_value(t, ladder, [6]i32{4, 6, 8, 10, 12, 20})
	testing.expect_value(t, MAX_DICE_UPGRADE_LEVEL, i32(5))
	for id in Card_Id {
		if id == .Count { continue }
		dice := card_dice_count(id) > 0
		// The Lazzo is no dice card, but its first hit grows five times only;
		// so do the Canna da Pesca's fishings (its heal stays a d4), the
		// Pinball's value and the First Person Shooter's seconds.
		top := MAX_DICE_UPGRADE_LEVEL if dice else (LASSO_MAX_UPGRADE_LEVEL if id == .Lasso else MAX_CARD_UPGRADE_LEVEL)
		if id == .Fishing_Rod { top = FISHING_ROD_MAX_UPGRADE_LEVEL }
		if id == .Pinball { top = PINBALL_MAX_UPGRADE_LEVEL }
		if id == .First_Person || id == .First_Person_Brawler || id == .First_Person_Fencer || id == .First_Person_Archer { top = FIRST_PERSON_MAX_UPGRADE_LEVEL }
		if id == .Marley_Party { top = MARLEY_MAX_UPGRADE_LEVEL }
		if id == .Flood_Wave { top = FLOOD_MAX_UPGRADE_LEVEL }
		if id == .Field_Cannon { top = CANNON_MAX_UPGRADE_LEVEL }
		if id == .Laser_Cannon { top = LASER_MAX_UPGRADE_LEVEL }
		if id == .Devouring_Hole { top = BLACK_HOLE_MAX_UPGRADE_LEVEL }
		testing.expect_value(t, card_max_upgrade_level(id), top)
		for level in i32(-1)..=MAX_CARD_UPGRADE_LEVEL {
			expected := i32(0)
			if dice && level >= 0 && level <= MAX_DICE_UPGRADE_LEVEL { expected = ladder[level] }
			// The Dinosauro rolls a d4 at every level.
			if id == .Dino_Ride && level >= 0 && level <= MAX_DICE_UPGRADE_LEVEL { expected = 4 }
			testing.expect_value(t, card_die_sides(id, level), expected)
		}
	}
}

@(test)
test_card_dice_roll_its_count_of_its_level_die_reproducibly :: proc(t: ^testing.T) {
	for id in ([5]Card_Id{.Fate_Strike, .Shock_Floor, .Sundering_Blow, .Twin_Venom, .Prismatic_Barrage}) {
		for level in i32(0)..=MAX_DICE_UPGRADE_LEVEL {
			card := Card_Instance{id = 1, definition_id = id, upgrade_level = level}
			sides := card_die_sides(id, level)
			// The primitive above owns exhaustive face reachability. Here the
			// contract is each card's count, upgrade die and unchanged RNG use.
			for seed in ([4]u64{1, 7, 123, 256}) {
				state := make_dice_state(seed)
				expected_state := state
				roll, ok := roll_card_dice(&state, card)
				expected, expected_ok := roll_dice_pool(&expected_state, card_dice_count(id), sides)
				testing.expect(t, ok && expected_ok && validate_dice_roll(&roll))
				testing.expect_value(t, roll, expected)
				testing.expect_value(t, state, expected_state)
				testing.expect_value(t, int(roll.count), card_dice_count(id))
				testing.expect_value(t, roll.sides, sides)
			}
		}
		over := Card_Instance{id = 1, definition_id = id, upgrade_level = MAX_DICE_UPGRADE_LEVEL+1}
		state := make_dice_state(7)
		before := state
		_, ok := roll_card_dice(&state, over)
		testing.expect(t, !ok)
		testing.expect_value(t, state, before)
	}
	state := make_dice_state(7)
	_, ok := roll_card_dice(&state, {id = 1, definition_id = .Strike})
	testing.expect(t, !ok)
}
