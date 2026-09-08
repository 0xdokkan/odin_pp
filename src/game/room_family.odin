package game

import level "../level"

ROOM_FAMILY_SEED_SALT :: u64(0x32BE59BD9B4E0195)

room_family_for_node :: proc(node: ^Run_Node, previous_family: level.Room_Family = .Scattered) -> level.Room_Family {
	if node == nil { return .Scattered }
	families := [4]level.Room_Family{.Pillars, .Ring, .Twin_Courts, .Asymmetric}
	choices: [4]level.Room_Family
	count := 0
	for family in families {
		if family == previous_family { continue }
		choices[count] = family
		count += 1
	}
	seed := derive_room_stream_seed(node.room_seed, ROOM_FAMILY_SEED_SALT)
	return choices[seed%u64(count)]
}
