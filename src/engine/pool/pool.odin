// Fixed-capacity object pool addressed by generational handles.
//
// A handle stays valid until its slot is freed; reusing the slot bumps the
// generation, so stale handles fail lookups instead of aliasing a new object.
// Storage is inline, so a pool is one allocation-free value.
package pool

Handle :: struct {
	index:      u32,
	generation: u32,
}

INVALID :: Handle{}

Pool :: struct($T: typeid, $N: int) where N > 0 {
	items:       [N]T,
	generations: [N]u32,
	alive:       [N]bool,
	free_list:   [N]u32,
	free_count:  int,
	high_water:  int,
	count:       int,
}

// Generation 0 is never handed out, so the zero Handle is always invalid.
insert :: proc(p: ^Pool($T, $N), value: T) -> (Handle, bool) {
	index: u32
	if p.free_count > 0 {
		p.free_count -= 1
		index = p.free_list[p.free_count]
	} else if p.high_water < N {
		index = u32(p.high_water)
		p.high_water += 1
	} else {
		return INVALID, false
	}
	p.generations[index] += 1
	if p.generations[index] == 0 {
		p.generations[index] = 1
	}
	p.items[index] = value
	p.alive[index] = true
	p.count += 1
	return Handle{index = index, generation = p.generations[index]}, true
}

valid :: proc(p: ^Pool($T, $N), h: Handle) -> bool {
	return h.generation != 0 && int(h.index) < N && p.alive[h.index] && p.generations[h.index] == h.generation
}

get :: proc(p: ^Pool($T, $N), h: Handle) -> ^T {
	if !valid(p, h) {
		return nil
	}
	return &p.items[h.index]
}

remove :: proc(p: ^Pool($T, $N), h: Handle) -> bool {
	if !valid(p, h) {
		return false
	}
	p.alive[h.index] = false
	p.items[h.index] = {}
	p.free_list[p.free_count] = h.index
	p.free_count += 1
	p.count -= 1
	return true
}

clear :: proc(p: ^Pool($T, $N)) {
	for i in 0..<p.high_water {
		if p.alive[i] {
			p.alive[i] = false
			p.items[i] = {}
		}
	}
	p.free_count = 0
	p.high_water = 0
	p.count = 0
}

full :: proc(p: ^Pool($T, $N)) -> bool {
	return p.count >= N
}

// Iteration: `for it := iterator(&p); value, handle in next(&it) { ... }`.
// Removing the current item while iterating is allowed.
Iterator :: struct($T: typeid, $N: int) {
	pool:  ^Pool(T, N),
	index: int,
}

iterator :: proc(p: ^Pool($T, $N)) -> Iterator(T, N) {
	return Iterator(T, N){pool = p}
}

next :: proc(it: ^Iterator($T, $N)) -> (value: ^T, handle: Handle, ok: bool) {
	for it.index < it.pool.high_water {
		i := it.index
		it.index += 1
		if it.pool.alive[i] {
			return &it.pool.items[i], Handle{index = u32(i), generation = it.pool.generations[i]}, true
		}
	}
	return nil, INVALID, false
}
