package main

import game "game"
import level "level"

demo_seed_with_room_family :: proc(seed: u64, family: level.Room_Family) -> (u64, bool) {
	for attempt in 0..<512 {
		candidate := seed+u64(attempt)
		node := game.Run_Node{id = 0, kind = .Combat, depth = 0,
			room_seed = game.derive_node_room_seed(candidate, 0, .Combat, 0)}
		if game.room_family_for_node(&node) == family { return candidate, true }
	}
	return 0, false
}
