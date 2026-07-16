package game

import "core:math/rand"

MAX_NODE_CONNECTIONS :: 3

ROOM_SEED_SALT     :: u64(0x8CB92BA72F3D8DD7)
ROOM_SEED_ID_MIX   :: u64(0x9E3779B97F4A7C15)
ROOM_SEED_KIND_MIX :: u64(0xD1B54A32D192ED03)
ROOM_SEED_DEPTH_MIX :: u64(0x94D049BB133111EB)
DEFAULT_ROOM_SEED  :: u64(0xA0761D6478BD642F)

Node_Id :: distinct int

INVALID_NODE_ID :: Node_Id(-1)

Node_Kind :: enum {
	Combat,
	Elite,
	Boss,
}

node_kind_name :: proc(kind: Node_Kind) -> string {
	switch kind {
	case .Combat:
		return "Combat"
	case .Elite:
		return "Elite"
	case .Boss:
		return "Boss"
	}
	return "Unknown"
}

Run_Phase :: enum {
	In_Room,
	Reward,
	Choose_Path,
	Victory,
	Defeat,
}

run_phase_name :: proc(phase: Run_Phase) -> string {
	switch phase {
	case .In_Room:
		return "In Room"
	case .Reward:
		return "Reward"
	case .Choose_Path:
		return "Choose Path"
	case .Victory:
		return "Victory"
	case .Defeat:
		return "Defeat"
	}
	return "Unknown"
}

Run_Map_Config :: struct {
	layer_count:                       int,
	min_nodes_per_middle_layer:        int,
	max_nodes_per_middle_layer:        int,
}

Run_Node :: struct {
	id:               Node_Id,
	kind:             Node_Kind,
	depth:            int,
	room_seed:        u64,
	lane:             int,
	lane_count:       int,
	outgoing:         [MAX_NODE_CONNECTIONS]Node_Id,
	outgoing_count:   int,
	entered:          bool,
	cleared:          bool,
}

mix_room_seed :: proc(value: u64) -> u64 {
	result := value
	result = (result~(result >> 30))*0xBF58476D1CE4E5B9
	result = (result~(result >> 27))*0x94D049BB133111EB
	return result~(result >> 31)
}

derive_node_room_seed :: proc(run_seed: u64, id: Node_Id, kind: Node_Kind, depth: int) -> u64 {
	assert(int(id) >= 0 && depth >= 0)
	value := run_seed~ROOM_SEED_SALT
	value ~= u64(int(id)+1)*ROOM_SEED_ID_MIX
	value ~= u64(int(kind)+1)*ROOM_SEED_KIND_MIX
	value ~= u64(depth+1)*ROOM_SEED_DEPTH_MIX
	result := mix_room_seed(value)
	if result == 0 {
		return DEFAULT_ROOM_SEED
	}
	return result
}

Run_Map :: struct {
	seed:         u64,
	nodes:        [dynamic]Run_Node,
	layer_starts: [dynamic]int,
	layer_counts: [dynamic]int,
}

Run_State :: struct {
	player:        Player,
	route_map:     Run_Map,
	current_node:  Node_Id,
	phase:         Run_Phase,
	cleared_count: int,
	seed:          u64,
	card_reward:        Card_Reward_State,
	reward_random_state: u64,
}

Run_Transition :: enum {
	Invalid,
	Reward,
	Choose_Path,
	Victory,
	Defeat,
}

valid_run_map_config :: proc(config: Run_Map_Config) -> bool {
	return config.layer_count >= 3 &&
	       config.min_nodes_per_middle_layer >= 2 &&
	       config.max_nodes_per_middle_layer >= config.min_nodes_per_middle_layer &&
	       config.max_nodes_per_middle_layer <= MAX_NODE_CONNECTIONS
}

append_layer :: proc(run_map: ^Run_Map, depth, node_count: int, kind: Node_Kind) {
	assert(run_map != nil && node_count > 0)
	start := len(run_map.nodes)
	append(&run_map.layer_starts, start)
	append(&run_map.layer_counts, node_count)

	for lane in 0..<node_count {
		append(&run_map.nodes, Run_Node{
			id = Node_Id(len(run_map.nodes)),
			kind = kind,
			depth = depth,
			lane = lane,
			lane_count = node_count,
		})
	}
}

connect_nodes :: proc(run_map: ^Run_Map, source_id, target_id: Node_Id) -> bool {
	if run_map == nil {
		return false
	}
	source_index := int(source_id)
	target_index := int(target_id)
	if source_index < 0 || source_index >= len(run_map.nodes) ||
	   target_index < 0 || target_index >= len(run_map.nodes) {
		return false
	}

	source := &run_map.nodes[source_index]
	if source.outgoing_count >= MAX_NODE_CONNECTIONS {
		return false
	}
	for index in 0..<source.outgoing_count {
		if source.outgoing[index] == target_id {
			return false
		}
	}

	source.outgoing[source.outgoing_count] = target_id
	source.outgoing_count += 1
	return true
}

sort_connections_by_lane :: proc(run_map: ^Run_Map, source_id: Node_Id) {
	assert(run_map != nil)
	source := &run_map.nodes[int(source_id)]
	for index in 1..<source.outgoing_count {
		current := source.outgoing[index]
		position := index
		for position > 0 {
			previous := source.outgoing[position-1]
			if run_map.nodes[int(previous)].lane <= run_map.nodes[int(current)].lane {
				break
			}
			source.outgoing[position] = previous
			position -= 1
		}
		source.outgoing[position] = current
	}
}

has_incoming_from_layer :: proc(run_map: ^Run_Map, target_id: Node_Id, source_start, source_count: int) -> bool {
	assert(run_map != nil)
	for source_index in source_start..<source_start+source_count {
		source := &run_map.nodes[source_index]
		for outgoing_index in 0..<source.outgoing_count {
			if source.outgoing[outgoing_index] == target_id {
				return true
			}
		}
	}
	return false
}

connect_layers :: proc(run_map: ^Run_Map, depth: int, generator: rand.Generator) {
	assert(run_map != nil && depth >= 0 && depth+1 < len(run_map.layer_starts))
	source_start := run_map.layer_starts[depth]
	source_count := run_map.layer_counts[depth]
	target_start := run_map.layer_starts[depth+1]
	target_count := run_map.layer_counts[depth+1]

	for source_offset in 0..<source_count {
		candidates := [MAX_NODE_CONNECTIONS]int{0, 1, 2}
		rand.shuffle(candidates[:target_count], generator)
		desired_count := min(target_count, 2)
		if target_count == MAX_NODE_CONNECTIONS && rand.int_range(0, 4, generator) == 0 {
			desired_count = MAX_NODE_CONNECTIONS
		}
		for candidate_index in 0..<desired_count {
			source_id := Node_Id(source_start+source_offset)
			target_id := Node_Id(target_start+candidates[candidate_index])
			connected := connect_nodes(run_map, source_id, target_id)
			assert(connected)
		}
	}

	for target_offset in 0..<target_count {
		target_id := Node_Id(target_start+target_offset)
		if has_incoming_from_layer(run_map, target_id, source_start, source_count) {
			continue
		}

		best_source := -1
		best_distance := max(int)
		for source_offset in 0..<source_count {
			source := &run_map.nodes[source_start+source_offset]
			if source.outgoing_count >= MAX_NODE_CONNECTIONS {
				continue
			}
			distance := abs(source.lane*(target_count-1)-target_offset*(source_count-1))
			if distance < best_distance {
				best_source = source_start+source_offset
				best_distance = distance
			}
		}
		assert(best_source >= 0)
		connected := connect_nodes(run_map, Node_Id(best_source), target_id)
		assert(connected)
	}

	for source_index in source_start..<source_start+source_count {
		sort_connections_by_lane(run_map, Node_Id(source_index))
	}
}

generate_run_map :: proc(config: Run_Map_Config, seed: u64) -> (result: Run_Map, ok: bool) {
	if !valid_run_map_config(config) {
		return {}, false
	}

	result.nodes = make([dynamic]Run_Node, 0, config.layer_count*config.max_nodes_per_middle_layer)
	result.layer_starts = make([dynamic]int, 0, config.layer_count)
	result.layer_counts = make([dynamic]int, 0, config.layer_count)
	result.seed = seed

	random_state: rand.Xoshiro256_Random_State
	generator := rand.xoshiro256_random_generator(&random_state)
	rand.reset_u64(seed, generator)

	append_layer(&result, 0, 1, .Combat)
	for depth in 1..<config.layer_count-1 {
		node_count := rand.int_range(
			config.min_nodes_per_middle_layer,
			config.max_nodes_per_middle_layer+1,
			generator,
		)
		start := len(result.nodes)
		append_layer(&result, depth, node_count, .Combat)
		for index in start..<len(result.nodes) {
			if rand.int_range(0, 6, generator) == 0 {
				result.nodes[index].kind = .Elite
			}
		}
	}
	append_layer(&result, config.layer_count-1, 1, .Boss)
	for &node in result.nodes {
		node.room_seed = derive_node_room_seed(seed, node.id, node.kind, node.depth)
	}

	for depth in 0..<config.layer_count-1 {
		connect_layers(&result, depth, generator)
	}

	if !validate_run_map(&result) {
		destroy_run_map(&result)
		return {}, false
	}
	return result, true
}

destroy_run_map :: proc(run_map: ^Run_Map) {
	if run_map == nil {
		return
	}
	delete(run_map.nodes)
	delete(run_map.layer_starts)
	delete(run_map.layer_counts)
	run_map^ = {}
}

validate_run_map :: proc(run_map: ^Run_Map) -> bool {
	if run_map == nil || len(run_map.nodes) == 0 ||
	   len(run_map.layer_starts) < 3 ||
	   len(run_map.layer_starts) != len(run_map.layer_counts) {
		return false
	}

	incoming := make([]int, len(run_map.nodes))
	defer delete(incoming)
	reachable := make([]bool, len(run_map.nodes))
	defer delete(reachable)
	reachable[0] = true

	for depth in 0..<len(run_map.layer_starts) {
		start := run_map.layer_starts[depth]
		count := run_map.layer_counts[depth]
		if count <= 0 || start < 0 || start+count > len(run_map.nodes) {
			return false
		}
		if depth > 0 && start != run_map.layer_starts[depth-1]+run_map.layer_counts[depth-1] {
			return false
		}

		for lane in 0..<count {
			index := start+lane
			node := &run_map.nodes[index]
			if int(node.id) != index || node.depth != depth ||
			   node.room_seed == 0 ||
			   node.room_seed != derive_node_room_seed(run_map.seed, node.id, node.kind, node.depth) ||
			   node.lane != lane || node.lane_count != count ||
			   node.outgoing_count < 0 || node.outgoing_count > MAX_NODE_CONNECTIONS {
				return false
			}
			is_last_layer := depth == len(run_map.layer_starts)-1
			if (is_last_layer && node.outgoing_count != 0) ||
			   (!is_last_layer && node.outgoing_count == 0) {
				return false
			}

			for outgoing_index in 0..<node.outgoing_count {
				target_index := int(node.outgoing[outgoing_index])
				target_start := 0
				target_count := 0
				if depth+1 < len(run_map.layer_starts) {
					target_start = run_map.layer_starts[depth+1]
					target_count = run_map.layer_counts[depth+1]
				}
				if target_index < 0 || target_index >= len(run_map.nodes) ||
				   target_index < target_start || target_index >= target_start+target_count ||
				   run_map.nodes[target_index].depth != depth+1 {
					return false
				}
				for duplicate_index in 0..<outgoing_index {
					if node.outgoing[duplicate_index] == node.outgoing[outgoing_index] {
						return false
					}
				}
				incoming[target_index] += 1
				if reachable[index] {
					reachable[target_index] = true
				}
			}
		}
	}
	last_layer := len(run_map.layer_starts)-1
	if run_map.layer_starts[last_layer]+run_map.layer_counts[last_layer] != len(run_map.nodes) {
		return false
	}

	if run_map.layer_starts[0] != 0 || run_map.layer_counts[0] != 1 ||
	   run_map.layer_counts[len(run_map.layer_counts)-1] != 1 ||
	   run_map.nodes[len(run_map.nodes)-1].kind != .Boss {
		return false
	}
	for index in 1..<len(run_map.nodes) {
		if incoming[index] == 0 || !reachable[index] {
			return false
		}
	}
	return incoming[0] == 0
}

create_run :: proc(stats: Player_Stats, config: Run_Map_Config, seed: u64) -> (result: Run_State, ok: bool) {
	player, player_ok := create_player(stats)
	if !player_ok {
		return {}, false
	}
	reseeded := reseed_deck(&player.deck, seed~0xD1B54A32D192ED03)
	assert(reseeded)
	run_map, map_ok := generate_run_map(config, seed)
	if !map_ok {
		return {}, false
	}

	result.player = player
	result.route_map = run_map
	result.current_node = result.route_map.nodes[0].id
	result.route_map.nodes[0].entered = true
	result.phase = .In_Room
	result.seed = seed
	result.reward_random_state = normalized_card_reward_seed(seed~CARD_REWARD_SEED_SALT)
	return result, true
}

destroy_run :: proc(run: ^Run_State) {
	if run == nil {
		return
	}
	destroy_run_map(&run.route_map)
	run^ = {}
}

node_at :: proc(run: ^Run_State, id: Node_Id) -> (^Run_Node, bool) {
	if run == nil {
		return nil, false
	}
	index := int(id)
	if index < 0 || index >= len(run.route_map.nodes) {
		return nil, false
	}
	return &run.route_map.nodes[index], true
}

current_run_node :: proc(run: ^Run_State) -> (^Run_Node, bool) {
	if run == nil {
		return nil, false
	}
	return node_at(run, run.current_node)
}

available_nodes :: proc(run: ^Run_State) -> []Node_Id {
	if run == nil || run.phase != .Choose_Path {
		return nil
	}
	node, ok := current_run_node(run)
	if !ok {
		return nil
	}
	return node.outgoing[:node.outgoing_count]
}

can_choose_node :: proc(run: ^Run_State, id: Node_Id) -> bool {
	for available in available_nodes(run) {
		if available == id {
			return true
		}
	}
	return false
}

choose_node :: proc(run: ^Run_State, id: Node_Id) -> bool {
	if !can_choose_node(run, id) {
		return false
	}
	node, ok := node_at(run, id)
	assert(ok)
	run.current_node = id
	run.phase = .In_Room
	node.entered = true
	return true
}

finish_room :: proc(run: ^Run_State, room_phase: Room_Phase) -> Run_Transition {
	if run == nil || run.phase != .In_Room {
		return .Invalid
	}
	if room_phase == .Defeat {
		finish_deck_combat(&run.player.deck)
		run.phase = .Defeat
		return .Defeat
	}
	if room_phase != .Complete {
		return .Invalid
	}

	node, ok := current_run_node(run)
	assert(ok && !node.cleared)
	finish_deck_combat(&run.player.deck)
	node.cleared = true
	run.cleared_count += 1
	if node.outgoing_count == 0 {
		run.phase = .Victory
		return .Victory
	}
	started_reward := begin_card_reward(run)
	assert(started_reward)
	return .Reward
}
