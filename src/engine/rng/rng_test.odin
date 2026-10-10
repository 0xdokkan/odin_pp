package rng

import "core:testing"

@(test)
test_same_seed_gives_same_sequence :: proc(t: ^testing.T) {
	a := create(42)
	b := create(42)
	for _ in 0..<64 {
		testing.expect_value(t, next_u64(&a), next_u64(&b))
	}
}

@(test)
test_zero_seed_does_not_stick_at_zero :: proc(t: ^testing.T) {
	r := from_state(0)
	testing.expect(t, next_u64(&r) != 0)
	z := create(0)
	testing.expect(t, z.state != 0)
}

@(test)
test_derive_separates_domains :: proc(t: ^testing.T) {
	testing.expect(t, derive(1, 0) != derive(1, 1))
	testing.expect(t, derive(1, 0) != derive(2, 0))
	testing.expect_value(t, derive(7, 3), derive(7, 3))
}

@(test)
test_int_range_is_inclusive_and_bounded :: proc(t: ^testing.T) {
	r := create(9)
	seen: [5]bool
	for _ in 0..<2000 {
		v := int_range(&r, -2, 2)
		testing.expect(t, v >= -2 && v <= 2)
		seen[v+2] = true
	}
	for hit in seen {
		testing.expect(t, hit)
	}
	testing.expect_value(t, int_range(&r, 5, 5), 5)
	testing.expect_value(t, int_range(&r, 5, 1), 5)
}

@(test)
test_float01_stays_in_unit_interval :: proc(t: ^testing.T) {
	r := create(3)
	for _ in 0..<5000 {
		v := float01(&r)
		testing.expect(t, v >= 0 && v < 1)
	}
}

@(test)
test_weighted_index_skips_non_positive_weights :: proc(t: ^testing.T) {
	r := create(11)
	weights := []int{0, 3, -4, 1}
	counts: [4]int
	for _ in 0..<4000 {
		index, ok := weighted_index(&r, weights)
		testing.expect(t, ok)
		counts[index] += 1
	}
	testing.expect_value(t, counts[0], 0)
	testing.expect_value(t, counts[2], 0)
	testing.expect(t, counts[1] > counts[3]*2)
	_, none := weighted_index(&r, []int{0, -1})
	testing.expect(t, !none)
}

@(test)
test_shuffle_is_a_permutation :: proc(t: ^testing.T) {
	r := create(5)
	items := [8]int{0, 1, 2, 3, 4, 5, 6, 7}
	shuffle(&r, items[:])
	seen: [8]bool
	for v in items {
		seen[v] = true
	}
	for hit in seen {
		testing.expect(t, hit)
	}
}

@(test)
test_unit_disc_points_are_inside :: proc(t: ^testing.T) {
	r := create(77)
	for _ in 0..<500 {
		p := unit_disc(&r)
		testing.expect(t, p.x*p.x+p.y*p.y <= 1)
	}
}
