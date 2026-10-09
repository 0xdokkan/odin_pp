package pool

import "core:testing"

@(test)
test_zero_handle_is_invalid :: proc(t: ^testing.T) {
	p: Pool(int, 4)
	testing.expect(t, !valid(&p, INVALID))
	testing.expect(t, get(&p, INVALID) == nil)
}

@(test)
test_stale_handle_fails_after_slot_reuse :: proc(t: ^testing.T) {
	p: Pool(int, 2)
	a, _ := insert(&p, 10)
	testing.expect(t, remove(&p, a))
	b, _ := insert(&p, 20)
	testing.expect_value(t, b.index, a.index)
	testing.expect(t, !valid(&p, a))
	testing.expect(t, get(&p, a) == nil)
	testing.expect_value(t, get(&p, b)^, 20)
	testing.expect(t, !remove(&p, a))
}

@(test)
test_pool_refuses_inserts_when_full :: proc(t: ^testing.T) {
	p: Pool(int, 2)
	_, ok1 := insert(&p, 1)
	_, ok2 := insert(&p, 2)
	_, ok3 := insert(&p, 3)
	testing.expect(t, ok1 && ok2 && !ok3)
	testing.expect(t, full(&p))
}

@(test)
test_iterator_visits_live_items_and_tolerates_removal :: proc(t: ^testing.T) {
	p: Pool(int, 8)
	for i in 0..<6 {
		insert(&p, i)
	}
	sum := 0
	it := iterator(&p)
	for value, handle in next(&it) {
		if value^%2 == 0 {
			remove(&p, handle)
		} else {
			sum += value^
		}
	}
	testing.expect_value(t, sum, 1+3+5)
	testing.expect_value(t, p.count, 3)
	clear(&p)
	testing.expect_value(t, p.count, 0)
}
