package game

import grid "../grid"

ROOM_RECIPE_SEED_SALT :: u64(0x589965CC75374CC3)

Encounter_Kind :: enum { Standard, Powder_Keg, Escort, Assault, Demolitionist }

encounter_kind_name :: proc(kind: Encounter_Kind) -> string {
	switch kind {
	case .Standard: return "Skirmish"
	case .Powder_Keg: return "Powder Keg"
	case .Escort: return "Escort"
	case .Assault: return "Assault"
	case .Demolitionist: return "Demolitionist"
	}
	return "Skirmish"
}

encounter_kind_for_node :: proc(node: ^Run_Node) -> Encounter_Kind {
	if node.kind == .Boss { return .Demolitionist }
	if node.kind == .Combat && node.depth <= 1 { return .Powder_Keg }
	seed := derive_room_stream_seed(node.room_seed, ROOM_RECIPE_SEED_SALT)
	kinds := [3]Encounter_Kind{.Powder_Keg, .Escort, .Assault}
	return kinds[seed%3]
}

encounter_required_enemies :: proc(kind: Encounter_Kind) -> [2]Enemy_Archetype {
	switch kind {
	case .Standard: return {.Chaser, .Chaser}
	case .Powder_Keg: return {.Bomber, .Chaser}
	case .Escort: return {.Custodian, .Archer}
	case .Assault: return {.Brute, .Chaser}
	case .Demolitionist: return {.Demolitionist, .Bomber}
	}
	return {}
}

// A nearby pair creates an actual formation, with an unobstructed orthogonal link.
encounter_pair_has_clear_link :: proc(blueprint: ^Room_Blueprint, a, b: grid.Position) -> bool {
	distance := abs(a.x-b.x)+abs(a.y-b.y)
	if distance == 0 || distance > 2 || (a.x != b.x && a.y != b.y) { return false }
	midpoint := grid.Position{(a.x+b.x)/2, (a.y+b.y)/2}
	if distance == 2 && (!cell_is_walkable(&blueprint.level_data, midpoint) ||
	   position_in_list(blueprint.obstacles[:], midpoint)) { return false }
	return true
}

arrange_encounter_spawn_candidates :: proc(blueprint: ^Room_Blueprint, candidates: []grid.Position) -> bool {
	for a in 0..<len(candidates) {
		for b in a+1..<len(candidates) {
			if !encounter_pair_has_clear_link(blueprint, candidates[a], candidates[b]) { continue }
			candidates[0], candidates[a] = candidates[a], candidates[0]
			candidates[1], candidates[b] = candidates[b], candidates[1]
			return true
		}
	}
	return false
}

validate_blueprint_encounter :: proc(blueprint: ^Room_Blueprint) -> bool {
	node := Run_Node{id = blueprint.source_node, kind = blueprint.node_kind,
		depth = blueprint.node_depth, room_seed = blueprint.seed}
	if blueprint.encounter_kind != encounter_kind_for_node(&node) || len(blueprint.enemies) < 2 {
		return false
	}
	required := encounter_required_enemies(blueprint.encounter_kind)
	for archetype, index in required {
		if blueprint.enemies[index].archetype != archetype { return false }
	}
	for enemy, index in blueprint.enemies {
		if enemy.archetype == .Demolitionist && (blueprint.encounter_kind != .Demolitionist || index != 0) {
			return false
		}
	}
	if !encounter_pair_has_clear_link(blueprint, blueprint.enemies[0].position, blueprint.enemies[1].position) {
		return false
	}
	if blueprint.encounter_kind == .Escort {
		a, b := blueprint.enemies[0].position, blueprint.enemies[1].position
		for object in blueprint.objects {
			if object.position == (grid.Position{(a.x+b.x)/2, (a.y+b.y)/2}) { return false }
		}
	}
	return true
}
