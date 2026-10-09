package game

import grid "../grid"

// The first two route layers retain the compact introductory encounter. Later
// tiers grow footprint and roster together; depth cannot grow either unboundedly.
tactical_arena_tier :: proc(depth: int) -> int {
	return clamp(depth/2, 0, 3)
}

configure_progressive_tactical_arena :: proc(profile: ^Room_Generation_Profile, node: ^Run_Node) {
	tier := tactical_arena_tier(node.depth)
	if tier == 0 { return }
	layout := &profile.level_config
	encounter := &profile.encounter_config
	layout.width = 17+8*tier
	layout.height = 11+6*tier
	layout.complexity = tier
	layout.min_spawn_exit_distance = 7+3*tier
	encounter.target_enemies = 4+4*tier
	encounter.trap_count = 2+2*tier
	encounter.obstacle_count = 4+4*tier
	encounter.object_count = 4+2*tier
	switch node.kind {
	case .Elite:
		layout.width += 2
		layout.height += 1
		encounter.target_enemies += 2
		encounter.trap_count += 1
		encounter.obstacle_count += 2
		encounter.object_count += 2
	case .Boss:
		layout.width += 4
		layout.height += 2
		encounter.target_enemies += 4 if tier < 3 else 6
		encounter.trap_count += 2
		encounter.obstacle_count += 4
		encounter.object_count += 4
	case .Combat:
	case .Shop, .Rest, .Event, .Treasure, .Count:
		unreachable()
	}
	encounter.max_enemies = encounter.target_enemies
	// Mean role cost two; the unique boss costs six instead of the usual two.
	encounter.enemy_budget = encounter.target_enemies*2+(4 if node.kind == .Boss else 0)
}

progressive_encounter_required_roles :: proc(blueprint: ^Room_Blueprint) -> (roles: [5]Enemy_Archetype, count: int) {
	if blueprint.profile.encounter_config.target_enemies == 0 { return }
	roles = {.Chaser, .Archer, .Bomber, .Custodian, .Brute}
	count = 4 if tactical_arena_tier(blueprint.node_depth) == 1 else 5
	return
}

// After the initial recipe pair, groups of three occupy successive sectors.
// Local role scoring still selects cover, firing lanes and open charge routes.
progressive_encounter_sector_score :: proc(blueprint: ^Room_Blueprint, index: int, position: grid.Position) -> int {
	if blueprint.profile.encounter_config.target_enemies == 0 { return 0 }
	sectors := [?]grid.Position{{-1, -1}, {1, 1}, {-1, 1}, {1, -1}, {0, -1}, {0, 1}, {-1, 0}, {1, 0}}
	sector := sectors[((index-2)/3)%len(sectors)]
	width, height := blueprint.level_data.tiles.width, blueprint.level_data.tiles.height
	anchor := grid.Position{width/2+sector.x*(width/2-4), height/2+sector.y*(height/2-3)}
	return -(abs(position.x-anchor.x)+abs(position.y-anchor.y))*12
}
