package puzzle

import "core:slice"

// Breadth-first search over single moves, so the first solution found has
// the minimum move count: this is how each library level gets its par, and
// the in-game hint reuses it with a small budget.

Solution :: struct {
	solved:   bool,
	moves:    int,
	explored: int, // distinct states visited
	path:     [dynamic]Dir,
}

solution_destroy :: proc(s: ^Solution) {
	delete(s.path)
	s^ = {}
}

// Crates are interchangeable, so slots are sorted before packing; with at most
// 7 crates on a 192-cell board, player + crates fit one u64.
state_key :: proc(s: State) -> u64 {
	sorted := s.crates
	n := int(s.crate_count)
	// Insertion sort: at most 7 items, and it runs for every visited state.
	for i in 1..<n {
		v := sorted[i]
		j := i
		for j > 0 && sorted[j-1] > v {
			sorted[j] = sorted[j-1]
			j -= 1
		}
		sorted[j] = v
	}
	key := u64(s.player)
	for i in 0..<n {
		key = key<<8 | u64(sorted[i])
	}
	return key
}

// Cells from which a lone crate can never reach a sigil, however the other
// pieces are arranged. Reachability is over-approximated (gates count as
// open, every ice cell along a slide may be a stopping point), so a crate on
// a dead cell is a certain deadlock and the search may prune it.
dead_cells :: proc(b: ^Board) -> (dead: [MAX_CELLS]bool) {
	cells := b.width * b.height
	live: [MAX_CELLS]bool
	// Fixed point: a cell is live when a push from it can stop on a live cell.
	for i in 0..<cells {
		live[i] = b.tiles[i] == .Sigil
	}
	changed := true
	for changed {
		changed = false
		for i in 0..<cells {
			if live[i] || !walkable(b.tiles[i]) {
				continue
			}
			search: for d in Dir {
				behind, ok_b := neighbor(b, i, dir_opposite(d))
				if !ok_b || !walkable(b.tiles[behind]) {
					continue
				}
				at := i
				for {
					next, ok := neighbor(b, at, d)
					if !ok || !walkable(b.tiles[next]) {
						break
					}
					at = next
					if live[at] {
						live[i] = true
						changed = true
						break search
					}
					if b.tiles[at] != .Ice {
						break
					}
				}
			}
		}
	}
	for i in 0..<cells {
		dead[i] = walkable(b.tiles[i]) && !live[i]
	}
	return
}

@(private)
Search_Node :: struct {
	state:  State,
	parent: i32,
	dir:    Dir,
}

// Explores at most `budget` distinct states. Scratch memory comes from
// context.allocator and is released before returning; the path is allocated
// with `allocator`. `use_dead_cells = false` disables pruning (for tests).
solve :: proc(b: ^Board, start: State, budget: int, allocator := context.allocator, use_dead_cells := true) -> Solution {
	result := Solution{path = make([dynamic]Dir, allocator)}
	first := start
	if is_solved(b, &first) {
		result.solved = true
		result.explored = 1
		return result
	}
	dead := dead_cells(b)
	// Spare crates (e.g. plate weights) may rest anywhere, so the dead-cell
	// test only holds when every crate must end on a sigil.
	prune := use_dead_cells && int(start.crate_count) == b.sigil_count
	nodes := make([dynamic]Search_Node, 0, 1024)
	defer delete(nodes)
	seen := make(map[u64]struct{})
	defer delete(seen)
	append(&nodes, Search_Node{state = start, parent = -1})
	seen[state_key(start)] = {}
	head := 0
	for head < len(nodes) {
		current := nodes[head]
		for d in Dir {
			next, r := simulate(b, current.state, d)
			if !r.moved {
				continue
			}
			if prune && r.pushed && dead[r.crate_to] {
				continue
			}
			key := state_key(next)
			if key in seen {
				continue
			}
			if len(seen) >= budget {
				result.explored = len(seen)
				return result
			}
			seen[key] = {}
			append(&nodes, Search_Node{state = next, parent = i32(head), dir = d})
			if r.solved {
				result.solved = true
				result.explored = len(seen)
				at := i32(len(nodes) - 1)
				for at > 0 {
					append(&result.path, nodes[at].dir)
					at = nodes[at].parent
				}
				slice.reverse(result.path[:])
				result.moves = len(result.path)
				return result
			}
		}
		head += 1
	}
	result.explored = len(seen)
	return result
}
