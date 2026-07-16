package game

import "core:math/rand"
import grid "../grid"
import level "../level"

ROOM_LAYOUT_SEED_SALT    :: u64(0xE7037ED1A0B428DB)
ROOM_ENCOUNTER_SEED_SALT :: u64(0x8EBC6AF09C88C6E3)

MAX_GENERATED_TRAPS     :: 16
MAX_GENERATED_OBSTACLES :: 32
MAX_ENEMY_BUDGET_COST   :: 3

Encounter_Generation_Config :: struct {
	enemy_budget:       int,
	max_enemies:        int,
	trap_count:         int,
	obstacle_count:     int,
	player_safe_radius: int,
	exit_safe_radius:   int,
	enemy_health:       i32,
	enemy_attack:       i32,
	trap_damage:        i32,
}

Room_Generation_Profile :: struct {
	level_config:     level.Room_Generation_Config,
	encounter_config: Encounter_Generation_Config,
}

Room_Blueprint_Error :: enum {
	None,
	Invalid_Node,
	Invalid_Profile,
	Level_Generation_Failed,
	Insufficient_Spawn_Cells,
	Insufficient_Obstacle_Cells,
	Invalid_Blueprint,
}

Room_Blueprint :: struct {
	seed:          u64,
	source_node:   Node_Id,
	node_kind:     Node_Kind,
	node_depth:    int,
	profile:       Room_Generation_Profile,
	level_data:    level.Level,
	exit_position: grid.Position,
	enemies:       [dynamic]Enemy_Spawn,
	traps:         [dynamic]Trap_Spawn,
	obstacles:     [dynamic]grid.Position,
}

derive_room_stream_seed :: proc(room_seed, salt: u64) -> u64 {
	result := mix_room_seed(room_seed~salt)
	if result == 0 {
		return mix_room_seed(DEFAULT_ROOM_SEED~salt)
	}
	return result
}

valid_encounter_generation_config :: proc(config: Encounter_Generation_Config) -> bool {
	return config.enemy_budget > 0 &&
	       config.max_enemies > 0 && config.max_enemies <= MAX_ENEMIES_PER_ROOM &&
	       config.enemy_budget <= config.max_enemies*MAX_ENEMY_BUDGET_COST &&
	       config.trap_count >= 0 && config.trap_count <= MAX_GENERATED_TRAPS &&
	       config.obstacle_count >= 0 && config.obstacle_count <= MAX_GENERATED_OBSTACLES &&
	       config.player_safe_radius >= 0 && config.exit_safe_radius >= 0 &&
	       config.enemy_health > 0 && config.enemy_attack > 0 && config.trap_damage > 0
}

room_generation_profile :: proc(node: ^Run_Node) -> (result: Room_Generation_Profile, ok: bool) {
	if node == nil || int(node.id) < 0 || node.depth < 0 || node.room_seed == 0 ||
	   !node_kind_has_room(node.kind) {
		return {}, false
	}

	result.level_config = {
		width = 15,
		height = 9,
		wall_density_percent = 7,
		spawn_clearance_radius = 1,
		exit_center_radius = 2,
		exit_clearance_radius = 1,
		min_spawn_exit_distance = 6,
		min_walkable_percent = 68,
		max_attempts = 64,
	}
	depth := node.depth
	switch node.kind {
	case .Combat:
		result.encounter_config = {
			enemy_budget = min(8, 3+depth/2),
			max_enemies = 6,
			trap_count = min(3, 1+depth/3),
			obstacle_count = min(4, 2+depth/4),
			player_safe_radius = 2,
			exit_safe_radius = 1,
			enemy_health = i32(4+depth/3),
			enemy_attack = i32(2+depth/4),
			trap_damage = i32(3+depth/3),
		}
	case .Elite:
		result.level_config.width = 17
		result.level_config.height = 10
		result.level_config.wall_density_percent = 9
		result.level_config.min_spawn_exit_distance = 7
		result.encounter_config = {
			enemy_budget = min(12, 6+depth/2),
			max_enemies = 8,
			trap_count = min(5, 3+depth/4),
			obstacle_count = min(6, 4+depth/4),
			player_safe_radius = 2,
			exit_safe_radius = 1,
			enemy_health = i32(5+depth/3),
			enemy_attack = i32(3+depth/4),
			trap_damage = i32(4+depth/3),
		}
	case .Boss:
		result.level_config.width = 19
		result.level_config.height = 11
		result.level_config.wall_density_percent = 10
		result.level_config.spawn_clearance_radius = 2
		result.level_config.exit_center_radius = 1
		result.level_config.min_spawn_exit_distance = 8
		result.level_config.min_walkable_percent = 72
		result.encounter_config = {
			enemy_budget = min(16, 10+depth/2),
			max_enemies = 9,
			trap_count = min(6, 4+depth/4),
			obstacle_count = min(7, 5+depth/4),
			player_safe_radius = 3,
			exit_safe_radius = 2,
			enemy_health = i32(6+depth/3),
			enemy_attack = i32(3+depth/4),
			trap_damage = i32(5+depth/3),
		}
	case .Shop, .Rest, .Event, .Treasure, .Count:
		return {}, false
	}
	return result, valid_encounter_generation_config(result.encounter_config)
}

destroy_room_blueprint :: proc(blueprint: ^Room_Blueprint) {
	if blueprint == nil {
		return
	}
	delete(blueprint.enemies)
	delete(blueprint.traps)
	delete(blueprint.obstacles)
	level.destroy(&blueprint.level_data)
	blueprint^ = {}
}

room_blueprint_content :: proc(blueprint: ^Room_Blueprint) -> Room_Content {
	if blueprint == nil {
		return {}
	}
	return {
		enemies = blueprint.enemies[:],
		traps = blueprint.traps[:],
		obstacles = blueprint.obstacles[:],
	}
}

position_in_list :: proc(positions: []grid.Position, position: grid.Position) -> bool {
	for current in positions {
		if current == position {
			return true
		}
	}
	return false
}

cell_is_walkable :: proc(level_data: ^level.Level, position: grid.Position) -> bool {
	tile, found := level.tile_at(level_data, position)
	return found && level.is_walkable(tile.kind)
}

cell_is_blocked :: proc(
	position: grid.Position,
	blockers: []grid.Position,
	extra_blocker: grid.Position,
	has_extra_blocker: bool,
) -> bool {
	return (has_extra_blocker && position == extra_blocker) || position_in_list(blockers, position)
}

all_unblocked_walkable_cells_are_connected :: proc(
	level_data: ^level.Level,
	blockers: []grid.Position,
	extra_blocker: grid.Position = {},
	has_extra_blocker := false,
) -> bool {
	if level_data == nil || len(level_data.tiles.cells) == 0 {
		return false
	}
	cell_count := len(level_data.tiles.cells)
	visited := make([]bool, cell_count)
	defer delete(visited)
	queue := make([]grid.Position, cell_count)
	defer delete(queue)

	start: grid.Position
	has_start := false
	open_count := 0
	for tile, index in level_data.tiles.cells {
		position, valid := grid.position_of(&level_data.tiles, index)
		assert(valid)
		if !level.is_walkable(tile.kind) ||
		   cell_is_blocked(position, blockers, extra_blocker, has_extra_blocker) {
			continue
		}
		open_count += 1
		if !has_start {
			start = position
			has_start = true
		}
	}
	if !has_start {
		return false
	}

	start_index, valid := grid.index_of(&level_data.tiles, start)
	assert(valid)
	visited[start_index] = true
	queue[0] = start
	head, tail := 0, 1
	reachable_count := 0
	directions := [?]grid.Position{
		{x = 0, y = -1},
		{x = 1, y = 0},
		{x = 0, y = 1},
		{x = -1, y = 0},
	}
	for head < tail {
		current := queue[head]
		head += 1
		reachable_count += 1
		for direction in directions {
			next := grid.Position{x = current.x+direction.x, y = current.y+direction.y}
			next_index, inside := grid.index_of(&level_data.tiles, next)
			if !inside || visited[next_index] || !cell_is_walkable(level_data, next) ||
			   cell_is_blocked(next, blockers, extra_blocker, has_extra_blocker) {
				continue
			}
			visited[next_index] = true
			queue[tail] = next
			tail += 1
		}
	}
	return reachable_count == open_count
}

grid_distance :: proc(a, b: grid.Position) -> int {
	return max(abs(a.x-b.x), abs(a.y-b.y))
}

position_is_safe_from_room_anchors :: proc(
	position, player_spawn, exit_position: grid.Position,
	config: Encounter_Generation_Config,
) -> bool {
	return grid_distance(position, player_spawn) > config.player_safe_radius &&
	       grid_distance(position, exit_position) > config.exit_safe_radius
}

enemy_archetype_budget_cost :: proc(archetype: Enemy_Archetype) -> int {
	switch archetype {
	case .Chaser:
		return 1
	case .Archer:
		return 2
	case .Brute:
		return 3
	case .Count:
	}
	return max(int)
}

random_feasible_archetype :: proc(
	remaining_budget, remaining_slots: int,
	generator: rand.Generator,
) -> (Enemy_Archetype, bool) {
	if remaining_budget <= 0 || remaining_slots <= 0 {
		return {}, false
	}
	affordable: [int(Enemy_Archetype.Count)]Enemy_Archetype
	affordable_count := 0
	for archetype_index in 0..<int(Enemy_Archetype.Count) {
		archetype := Enemy_Archetype(archetype_index)
		cost := enemy_archetype_budget_cost(archetype)
		if cost > remaining_budget {
			continue
		}
		budget_after := remaining_budget-cost
		slots_after := remaining_slots-1
		if budget_after > 0 && (slots_after <= 0 || budget_after > slots_after*MAX_ENEMY_BUDGET_COST) {
			continue
		}
		affordable[affordable_count] = archetype
		affordable_count += 1
	}
	if affordable_count == 0 {
		return {}, false
	}
	return affordable[rand.int_range(0, affordable_count, generator)], true
}

enemy_stats_for_archetype :: proc(
	config: Encounter_Generation_Config,
	archetype: Enemy_Archetype,
) -> (health, attack: i32) {
	health = config.enemy_health
	attack = config.enemy_attack
	switch archetype {
	case .Chaser:
	case .Archer:
		health = max(i32(1), health-1)
	case .Brute:
		health += 3
		attack += 1
	case .Count:
		unreachable()
	}
	return
}

generate_obstacles :: proc(
	blueprint: ^Room_Blueprint,
	candidates: []grid.Position,
) -> bool {
	assert(blueprint != nil)
	desired_count := blueprint.profile.encounter_config.obstacle_count
	for candidate in candidates {
		if len(blueprint.obstacles) >= desired_count {
			break
		}
		if all_unblocked_walkable_cells_are_connected(
			&blueprint.level_data,
			blueprint.obstacles[:],
			candidate,
			true,
		) {
			append(&blueprint.obstacles, candidate)
		}
	}
	return len(blueprint.obstacles) == desired_count
}

validate_room_blueprint :: proc(blueprint: ^Room_Blueprint) -> bool {
	if blueprint == nil || blueprint.seed == 0 || int(blueprint.source_node) < 0 ||
	   blueprint.node_depth < 0 || !valid_encounter_generation_config(blueprint.profile.encounter_config) {
		return false
	}
	source_node := Run_Node{
		id = blueprint.source_node,
		kind = blueprint.node_kind,
		depth = blueprint.node_depth,
		room_seed = blueprint.seed,
	}
	expected_profile, profile_ok := room_generation_profile(&source_node)
	if !profile_ok || expected_profile != blueprint.profile {
		return false
	}
	level_report := level.validate_generated_room(&blueprint.level_data, blueprint.profile.level_config)
	if level_report.error != .None || level_report.exit_position != blueprint.exit_position ||
	   !all_unblocked_walkable_cells_are_connected(&blueprint.level_data, blueprint.obstacles[:]) {
		return false
	}

	config := blueprint.profile.encounter_config
	player_spawn := blueprint.level_data.player_spawn
	if len(blueprint.enemies) == 0 || len(blueprint.enemies) > config.max_enemies ||
	   len(blueprint.enemies) > MAX_ENEMIES_PER_ROOM || len(blueprint.traps) != config.trap_count ||
	   len(blueprint.obstacles) != config.obstacle_count {
		return false
	}

	for obstacle, index in blueprint.obstacles {
		if !cell_is_walkable(&blueprint.level_data, obstacle) ||
		   !position_is_safe_from_room_anchors(obstacle, player_spawn, blueprint.exit_position, config) ||
		   position_in_list(blueprint.obstacles[:index], obstacle) {
			return false
		}
	}

	budget_used := 0
	for enemy, index in blueprint.enemies {
		if enemy.archetype >= .Count {
			return false
		}
		budget_used += enemy_archetype_budget_cost(enemy.archetype)
		expected_health, expected_attack := enemy_stats_for_archetype(config, enemy.archetype)
		if enemy.health != expected_health || enemy.attack != expected_attack ||
		   !cell_is_walkable(&blueprint.level_data, enemy.position) ||
		   !position_is_safe_from_room_anchors(enemy.position, player_spawn, blueprint.exit_position, config) ||
		   position_in_list(blueprint.obstacles[:], enemy.position) {
			return false
		}
		for previous in 0..<index {
			if blueprint.enemies[previous].position == enemy.position {
				return false
			}
		}
	}
	if budget_used != config.enemy_budget {
		return false
	}

	for trap, index in blueprint.traps {
		if trap.damage != config.trap_damage || !cell_is_walkable(&blueprint.level_data, trap.position) ||
		   !position_is_safe_from_room_anchors(trap.position, player_spawn, blueprint.exit_position, config) ||
		   position_in_list(blueprint.obstacles[:], trap.position) {
			return false
		}
		for enemy in blueprint.enemies {
			if enemy.position == trap.position {
				return false
			}
		}
		for previous in 0..<index {
			if blueprint.traps[previous].position == trap.position {
				return false
			}
		}
	}
	return true
}

generate_room_blueprint :: proc(node: ^Run_Node) -> (result: Room_Blueprint, err: Room_Blueprint_Error) {
	profile, profile_ok := room_generation_profile(node)
	if !profile_ok {
		return {}, .Invalid_Node
	}
	if !valid_encounter_generation_config(profile.encounter_config) {
		return {}, .Invalid_Profile
	}

	result.seed = node.room_seed
	result.source_node = node.id
	result.node_kind = node.kind
	result.node_depth = node.depth
	result.profile = profile
	layout_seed := derive_room_stream_seed(node.room_seed, ROOM_LAYOUT_SEED_SALT)
	level_data, level_error := level.generate_room(profile.level_config, layout_seed)
	if level_error != .None {
		return {}, .Level_Generation_Failed
	}
	result.level_data = level_data
	exit_position, has_exit := find_exit(&result.level_data)
	if !has_exit {
		destroy_room_blueprint(&result)
		return {}, .Invalid_Blueprint
	}
	result.exit_position = exit_position

	cell_capacity := len(result.level_data.tiles.cells)
	result.enemies = make([dynamic]Enemy_Spawn, 0, profile.encounter_config.max_enemies)
	result.traps = make([dynamic]Trap_Spawn, 0, profile.encounter_config.trap_count)
	result.obstacles = make([dynamic]grid.Position, 0, profile.encounter_config.obstacle_count)
	candidates := make([dynamic]grid.Position, 0, cell_capacity)
	defer delete(candidates)
	for tile, index in result.level_data.tiles.cells {
		if !level.is_walkable(tile.kind) {
			continue
		}
		position, valid := grid.position_of(&result.level_data.tiles, index)
		assert(valid)
		if position_is_safe_from_room_anchors(
			position,
			result.level_data.player_spawn,
			result.exit_position,
			profile.encounter_config,
		) {
			append(&candidates, position)
		}
	}

	random_state: rand.Xoshiro256_Random_State
	generator := rand.xoshiro256_random_generator(&random_state)
	encounter_seed := derive_room_stream_seed(node.room_seed, ROOM_ENCOUNTER_SEED_SALT)
	rand.reset_u64(encounter_seed, generator)
	enemy_archetypes: [MAX_ENEMIES_PER_ROOM]Enemy_Archetype
	enemy_archetype_count := 0
	remaining_budget := profile.encounter_config.enemy_budget
	if node.kind == .Boss {
		enemy_archetypes[enemy_archetype_count] = .Brute
		enemy_archetype_count += 1
		remaining_budget -= enemy_archetype_budget_cost(.Brute)
	}
	for remaining_budget > 0 {
		remaining_slots := profile.encounter_config.max_enemies-enemy_archetype_count
		archetype, found := random_feasible_archetype(
			remaining_budget,
			remaining_slots,
			generator,
		)
		if !found {
			destroy_room_blueprint(&result)
			return {}, .Invalid_Profile
		}
		enemy_archetypes[enemy_archetype_count] = archetype
		enemy_archetype_count += 1
		remaining_budget -= enemy_archetype_budget_cost(archetype)
	}

	rand.shuffle(candidates[:], generator)
	if !generate_obstacles(&result, candidates[:]) {
		destroy_room_blueprint(&result)
		return {}, .Insufficient_Obstacle_Cells
	}

	spawn_candidates := make([dynamic]grid.Position, 0, len(candidates))
	defer delete(spawn_candidates)
	for candidate in candidates {
		if !position_in_list(result.obstacles[:], candidate) {
			append(&spawn_candidates, candidate)
		}
	}
	rand.shuffle(spawn_candidates[:], generator)

	spawn_index := 0
	for archetype_index in 0..<enemy_archetype_count {
		if spawn_index >= len(spawn_candidates) {
			destroy_room_blueprint(&result)
			return {}, .Insufficient_Spawn_Cells
		}
		archetype := enemy_archetypes[archetype_index]
		health, attack := enemy_stats_for_archetype(profile.encounter_config, archetype)
		append(&result.enemies, Enemy_Spawn{
			position = spawn_candidates[spawn_index],
			health = health,
			attack = attack,
			archetype = archetype,
		})
		spawn_index += 1
	}

	for _ in 0..<profile.encounter_config.trap_count {
		if spawn_index >= len(spawn_candidates) {
			destroy_room_blueprint(&result)
			return {}, .Insufficient_Spawn_Cells
		}
		append(&result.traps, Trap_Spawn{
			position = spawn_candidates[spawn_index],
			damage = profile.encounter_config.trap_damage,
		})
		spawn_index += 1
	}
	if !validate_room_blueprint(&result) {
		destroy_room_blueprint(&result)
		return {}, .Invalid_Blueprint
	}
	return result, .None
}
