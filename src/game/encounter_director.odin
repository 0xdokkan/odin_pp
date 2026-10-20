package game

import grid "../engine/grid"

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

@(private)
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
@(private = "file")
encounter_pair_has_clear_link :: proc(blueprint: ^Room_Blueprint, a, b: grid.Position) -> bool {
	distance := abs(a.x-b.x)+abs(a.y-b.y)
	if distance == 0 || distance > 2 || (a.x != b.x && a.y != b.y) { return false }
	midpoint := grid.Position{(a.x+b.x)/2, (a.y+b.y)/2}
	if distance == 2 && (!cell_is_walkable(&blueprint.level_data, midpoint) ||
	   position_in_list(blueprint.obstacles[:], midpoint)) { return false }
	return true
}

@(private)
arrange_encounter_spawn_candidates :: proc(blueprint: ^Room_Blueprint, candidates: []grid.Position) -> bool {
	required := encounter_required_enemies(blueprint.encounter_kind)
	scores_a := make([]int, len(candidates))
	scores_b := make([]int, len(candidates))
	defer delete(scores_a)
	defer delete(scores_b)
	// Only eight cells can form the required orthogonal distance-one/two pair.
	// Index them once rather than comparing every pair in a large arena.
	candidate_indices := make([]int, len(blueprint.level_data.tiles.cells))
	defer delete(candidate_indices)
	for candidate, index in candidates {
		cell, valid := grid.index_of(&blueprint.level_data.tiles, candidate)
		assert(valid)
		candidate_indices[cell] = index+1
		scores_a[index] = encounter_role_position_score(blueprint, required[0], candidate)
		scores_b[index] = encounter_role_position_score(blueprint, required[1], candidate)
	}
	best_a, best_b, best_score := -1, -1, -100000
	for a in 0..<len(candidates) {
		for step in ([?]grid.Position{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}) {
			for distance in 1..=2 {
				position := grid.Position{candidates[a].x+step.x*distance, candidates[a].y+step.y*distance}
				cell, valid := grid.index_of(&blueprint.level_data.tiles, position)
				if !valid || candidate_indices[cell] == 0 { continue }
				b := candidate_indices[cell]-1
				if !encounter_pair_has_clear_link(blueprint, candidates[a], candidates[b]) { continue }
				score := scores_a[a]+scores_b[b]
				// Preserve the original ascending a/b tie order and seeded layouts.
				if score > best_score || (score == best_score && a == best_a && b < best_b) {
					best_a, best_b, best_score = a, b, score
				}
			}
		}
	}
	if best_a < 0 { return false }
	candidates[0], candidates[best_a] = candidates[best_a], candidates[0]
	if best_b == 0 { best_b = best_a }
	candidates[1], candidates[best_b] = candidates[best_b], candidates[1]
	return true
}

@(private)
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
	roles, count := progressive_encounter_required_roles(blueprint)
	for role in roles[:count] {
		found := false
		for enemy in blueprint.enemies { if enemy.archetype == role { found = true; break } }
		if !found { return false }
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

@(private)
encounter_position_open :: proc(blueprint: ^Room_Blueprint, position: grid.Position, extra_blocker: grid.Position = {-1, -1}) -> bool {
	if position == extra_blocker || !cell_is_walkable(&blueprint.level_data, position) ||
	   position_in_list(blueprint.obstacles[:], position) { return false }
	for object in blueprint.objects {
		if object.position == position { return false }
	}
	return true
}

@(private)
encounter_position_lanes :: proc(blueprint: ^Room_Blueprint, position: grid.Position, extra_blocker: grid.Position = {-1, -1}) -> (neighbors, longest, cover: int) {
	directions := [4]grid.Position{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}
	for direction in directions {
		next := grid.Position{position.x+direction.x, position.y+direction.y}
		if encounter_position_open(blueprint, next, extra_blocker) {
			neighbors += 1
		} else if next.x > 0 && next.y > 0 && next.x < blueprint.level_data.tiles.width-1 &&
		          next.y < blueprint.level_data.tiles.height-1 {
			cover += 1
		}
		length := 0
		for _ in 0..<6 {
			if !encounter_position_open(blueprint, next, extra_blocker) { break }
			length += 1
			next = {next.x+direction.x, next.y+direction.y}
		}
		longest = max(longest, length)
	}
	return
}

@(private = "file")
encounter_role_position_score :: proc(blueprint: ^Room_Blueprint, archetype: Enemy_Archetype, position: grid.Position) -> int {
	neighbors, lane, cover := encounter_position_lanes(blueprint, position)
	spawn := blueprint.level_data.player_spawn
	distance := abs(position.x-spawn.x)+abs(position.y-spawn.y)
	switch archetype {
	case .Archer:
		// Cover is useful only with two open approaches: no protected cul-de-sac snipers.
		return cover*16+neighbors*3+min(lane, 4)*2+min(distance, 7) if neighbors >= 2 else -1000
	case .Brute, .Demolitionist:
		return min(lane, 4)*12+neighbors*2-min(distance, 12) if lane >= 3 else -1000
	case .Custodian:
		return cover*4+neighbors*2-min(distance, 10)
	case .Bomber:
		return neighbors*3-abs(distance-6)*2
	case .Chaser:
		return neighbors*2-distance*2
	case .Count:
		return -1000
	}
	return -1000
}

@(private)
arrange_role_spawn_candidate :: proc(blueprint: ^Room_Blueprint, candidates: []grid.Position, start: int, archetype: Enemy_Archetype) {
	best, best_score := start, -100000
	for index in start..<len(candidates) {
		score := encounter_role_position_score(blueprint, archetype, candidates[index])
		score += progressive_encounter_sector_score(blueprint, start, candidates[index])
		for enemy in blueprint.enemies {
			if grid_distance(enemy.position, candidates[index]) <= 1 { score -= 5 }
		}
		if score > best_score { best, best_score = index, score }
	}
	candidates[start], candidates[best] = candidates[best], candidates[start]
}

@(private)
object_preserves_enemy_lanes :: proc(blueprint: ^Room_Blueprint, candidate: grid.Position) -> bool {
	for enemy in blueprint.enemies {
		if enemy.archetype != .Archer && enemy.archetype != .Brute && enemy.archetype != .Demolitionist { continue }
		neighbors, lane, _ := encounter_position_lanes(blueprint, enemy.position, candidate)
		if enemy.archetype == .Archer && neighbors < 2 { return false }
		if (enemy.archetype == .Brute || enemy.archetype == .Demolitionist) && lane < 3 { return false }
	}
	return true
}
