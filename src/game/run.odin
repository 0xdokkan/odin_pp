package game

import "core:math/rand"

MAX_NODE_CONNECTIONS :: 3
SPECIAL_NODE_KIND_COUNT :: 4
MAX_RUN_MAP_LAYERS :: 128
MAX_RUN_MAP_NODES  :: 2+(MAX_RUN_MAP_LAYERS-2)*MAX_NODE_CONNECTIONS

ROOM_SEED_SALT     :: u64(0x8CB92BA72F3D8DD7)
ROOM_SEED_ID_MIX   :: u64(0x9E3779B97F4A7C15)
ROOM_SEED_KIND_MIX :: u64(0xD1B54A32D192ED03)
ROOM_SEED_DEPTH_MIX :: u64(0x94D049BB133111EB)
DEFAULT_ROOM_SEED  :: u64(0xA0761D6478BD642F)
MAP_TOPOLOGY_SEED_SALT :: u64(0xD6E8FEB86659FD93)
MAP_KIND_SEED_SALT     :: u64(0xA5A3564E27F8862D)
SPECIAL_KIND_SEED_SALT :: u64(0x9E3779B185EBCA87)

Node_Id :: distinct int

INVALID_NODE_ID :: Node_Id(-1)

Node_Kind :: enum {
	Combat,
	Elite,
	Boss,
	Shop,
	Rest,
	Event,
	Treasure,
	Count,
}

SPECIAL_NODE_KINDS :: [SPECIAL_NODE_KIND_COUNT]Node_Kind{
	.Shop,
	.Rest,
	.Event,
	.Treasure,
}

node_kind_is_valid :: proc(kind: Node_Kind) -> bool {
	return int(kind) >= 0 && int(kind) < int(Node_Kind.Count)
}

node_kind_has_room :: proc(kind: Node_Kind) -> bool {
	return kind == .Combat || kind == .Elite || kind == .Boss
}

node_kind_is_special :: proc(kind: Node_Kind) -> bool {
	return kind == .Shop || kind == .Rest || kind == .Event || kind == .Treasure
}

special_node_kind_for_depth :: proc(seed: u64, depth: int) -> (Node_Kind, bool) {
	if depth <= 0 {
		return .Count, false
	}
	offset := int(mix_room_seed(seed~SPECIAL_KIND_SEED_SALT)%SPECIAL_NODE_KIND_COUNT)
	kinds := SPECIAL_NODE_KINDS
	return kinds[(depth-1+offset)%SPECIAL_NODE_KIND_COUNT], true
}

node_kind_name :: proc(kind: Node_Kind) -> string {
	switch kind {
	case .Combat:
		return "Combat"
	case .Elite:
		return "Elite"
	case .Boss:
		return "Boss"
	case .Shop:
		return "Shop"
	case .Rest:
		return "Rest"
	case .Event:
		return "Event"
	case .Treasure:
		return "Treasure"
	case .Count:
	}
	return "Unknown"
}

Run_Phase :: enum {
	In_Room,
	Reward,
	Shop,
	Rest,
	Event,
	Treasure,
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
	case .Shop:
		return "Shop"
	case .Rest:
		return "Rest"
	case .Event:
		return "Event"
	case .Treasure:
		return "Treasure"
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
	shop:               Shop_State,
	shop_random_state:  u64,
	rest:                Rest_Node_State,
	route_event:         Route_Event_State,
	treasure:            Treasure_Node_State,
}

Run_Transition :: enum {
	Invalid,
	Reward,
	Choose_Path,
	Victory,
	Defeat,
}

Node_Entry_Result :: enum {
	Invalid,
	In_Room,
	Shop,
	Rest,
	Event,
	Treasure,
}

valid_run_map_config :: proc(config: Run_Map_Config) -> bool {
	return config.layer_count >= 3 && config.layer_count <= MAX_RUN_MAP_LAYERS &&
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

	topology_random_state: rand.Xoshiro256_Random_State
	topology_generator := rand.xoshiro256_random_generator(&topology_random_state)
	rand.reset_u64(seed~MAP_TOPOLOGY_SEED_SALT, topology_generator)

	append_layer(&result, 0, 1, .Combat)
	for depth in 1..<config.layer_count-1 {
		node_count := rand.int_range(
			config.min_nodes_per_middle_layer,
			config.max_nodes_per_middle_layer+1,
			topology_generator,
		)
		append_layer(&result, depth, node_count, .Combat)
	}
	append_layer(&result, config.layer_count-1, 1, .Boss)

	for depth in 0..<config.layer_count-1 {
		connect_layers(&result, depth, topology_generator)
	}

	kind_random_state: rand.Xoshiro256_Random_State
	kind_generator := rand.xoshiro256_random_generator(&kind_random_state)
	rand.reset_u64(seed~MAP_KIND_SEED_SALT, kind_generator)
	for depth in 1..<config.layer_count-1 {
		start := result.layer_starts[depth]
		count := result.layer_counts[depth]
		special_lane := rand.int_range(0, count, kind_generator)
		special_kind, special_kind_ok := special_node_kind_for_depth(seed, depth)
		assert(special_kind_ok)
		for lane in 0..<count {
			index := start+lane
			if lane == special_lane {
				result.nodes[index].kind = special_kind
			} else if rand.int_range(0, 6, kind_generator) == 0 {
				result.nodes[index].kind = .Elite
			}
		}
	}
	for &node in result.nodes {
		node.room_seed = derive_node_room_seed(seed, node.id, node.kind, node.depth)
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
	   len(run_map.nodes) > MAX_RUN_MAP_NODES ||
	   len(run_map.layer_starts) < 3 || len(run_map.layer_starts) > MAX_RUN_MAP_LAYERS ||
	   len(run_map.layer_starts) != len(run_map.layer_counts) {
		return false
	}

	incoming: [MAX_RUN_MAP_NODES]int
	reachable: [MAX_RUN_MAP_NODES]bool
	reachable[0] = true

	for depth in 0..<len(run_map.layer_starts) {
		start := run_map.layer_starts[depth]
		count := run_map.layer_counts[depth]
		if count <= 0 || start < 0 || start > len(run_map.nodes) ||
		   count > len(run_map.nodes)-start {
			return false
		}
		if depth > 0 {
			previous_start := run_map.layer_starts[depth-1]
			previous_count := run_map.layer_counts[depth-1]
			if start != previous_start+previous_count {
				return false
			}
		}

		special_count := 0
		room_count := 0
		expected_special := Node_Kind.Count
		is_first_layer := depth == 0
		is_last_layer := depth == len(run_map.layer_starts)-1
		if !is_first_layer && !is_last_layer {
			expected_ok: bool
			expected_special, expected_ok = special_node_kind_for_depth(run_map.seed, depth)
			if !expected_ok {
				return false
			}
		}

		for lane in 0..<count {
			index := start+lane
			node := &run_map.nodes[index]
			if !node_kind_is_valid(node.kind) || int(node.id) != index || node.depth != depth ||
			   node.room_seed == 0 ||
			   node.room_seed != derive_node_room_seed(run_map.seed, node.id, node.kind, node.depth) ||
			   node.lane != lane || node.lane_count != count ||
			   node.outgoing_count < 0 || node.outgoing_count > MAX_NODE_CONNECTIONS {
				return false
			}
			if is_first_layer {
				if node.kind != .Combat {
					return false
				}
			} else if is_last_layer {
				if node.kind != .Boss {
					return false
				}
			} else if node_kind_is_special(node.kind) {
				if node.kind != expected_special {
					return false
				}
				special_count += 1
			} else if node.kind == .Combat || node.kind == .Elite {
				room_count += 1
			} else {
				return false
			}
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
				if target_start < 0 || target_count <= 0 ||
				   target_start > len(run_map.nodes) || target_count > len(run_map.nodes)-target_start {
					return false
				}
				target_end := target_start+target_count
				if target_index < 0 || target_index >= len(run_map.nodes) ||
				   target_index < target_start || target_index >= target_end ||
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
		if !is_first_layer && !is_last_layer &&
		   (special_count != 1 || room_count != count-1 || room_count <= 0) {
			return false
		}
	}
	last_layer := len(run_map.layer_starts)-1
	last_start := run_map.layer_starts[last_layer]
	last_count := run_map.layer_counts[last_layer]
	if last_start < 0 || last_count <= 0 || last_start > len(run_map.nodes) ||
	   last_count > len(run_map.nodes)-last_start || last_start+last_count != len(run_map.nodes) {
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
	result.shop_random_state = normalized_shop_seed(seed~SHOP_SEED_SALT)
	assert(validate_run_state(&result))
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
	if run == nil || run.phase != .Choose_Path || !validate_run_state(run) {
		return nil
	}
	node, ok := current_run_node(run)
	if !ok {
		return nil
	}
	if node.outgoing_count < 0 || node.outgoing_count > MAX_NODE_CONNECTIONS {
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

enter_node :: proc(run: ^Run_State, id: Node_Id) -> Node_Entry_Result {
	if !can_choose_node(run, id) {
		return .Invalid
	}
	node, ok := node_at(run, id)
	if !ok || node.entered || node.cleared {
		return .Invalid
	}

	entry_result := Node_Entry_Result.Invalid
	next_phase := Run_Phase.In_Room
	next_shop: Shop_State
	next_shop_random_state := run.shop_random_state
	next_rest: Rest_Node_State
	next_event: Route_Event_State
	next_treasure: Treasure_Node_State
	switch node.kind {
	case .Combat, .Elite, .Boss:
		entry_result = .In_Room
		next_phase = .In_Room
	case .Shop:
		shop_ok: bool
		next_shop, shop_ok = build_shop_state_for_node(run, node, &next_shop_random_state)
		if !shop_ok {
			return .Invalid
		}
		entry_result = .Shop
		next_phase = .Shop
	case .Rest:
		rest_ok: bool
		next_rest, rest_ok = build_rest_node_state(&run.player, node)
		if !rest_ok {
			return .Invalid
		}
		entry_result = .Rest
		next_phase = .Rest
	case .Event:
		event_ok: bool
		next_event, event_ok = build_route_event_state(&run.player, node)
		if !event_ok {
			return .Invalid
		}
		entry_result = .Event
		next_phase = .Event
	case .Treasure:
		treasure_ok: bool
		next_treasure, treasure_ok = build_treasure_node_state(node)
		if !treasure_ok {
			return .Invalid
		}
		entry_result = .Treasure
		next_phase = .Treasure
	case .Count:
		return .Invalid
	}

	current_before := run.current_node
	shop_before := run.shop
	shop_random_state_before := run.shop_random_state
	rest_before := run.rest
	event_before := run.route_event
	treasure_before := run.treasure
	phase_before := run.phase
	entered_before := node.entered

	run.current_node = id
	run.shop = next_shop
	run.shop_random_state = next_shop_random_state
	run.rest = next_rest
	run.route_event = next_event
	run.treasure = next_treasure
	run.phase = next_phase
	node.entered = true
	if !validate_run_state(run) {
		node.entered = entered_before
		run.current_node = current_before
		run.shop = shop_before
		run.shop_random_state = shop_random_state_before
		run.rest = rest_before
		run.route_event = event_before
		run.treasure = treasure_before
		run.phase = phase_before
		return .Invalid
	}
	return entry_result
}

choose_node :: proc(run: ^Run_State, id: Node_Id) -> bool {
	return enter_node(run, id) != .Invalid
}

finish_room :: proc(run: ^Run_State, room_phase: Room_Phase) -> Run_Transition {
	if run == nil || run.phase != .In_Room || !validate_run_state(run) {
		return .Invalid
	}
	node, ok := current_run_node(run)
	if !ok || !node_kind_has_room(node.kind) || node.cleared {
		return .Invalid
	}
	if room_phase == .Defeat {
		finish_deck_combat(&run.player.deck)
		run.phase = .Defeat
		assert(validate_run_state(run))
		return .Defeat
	}
	if room_phase != .Complete {
		return .Invalid
	}

	deck_before := run.player.deck
	finish_deck_combat(&run.player.deck)
	node.cleared = true
	run.cleared_count += 1
	if node.outgoing_count == 0 {
		if node.kind != .Boss {
			run.player.deck = deck_before
			node.cleared = false
			run.cleared_count -= 1
			return .Invalid
		}
		run.phase = .Victory
		assert(validate_run_state(run))
		return .Victory
	}
	if node.kind != .Combat && node.kind != .Elite {
		run.player.deck = deck_before
		node.cleared = false
		run.cleared_count -= 1
		return .Invalid
	}
	started_reward := begin_card_reward(run)
	if !started_reward {
		run.player.deck = deck_before
		node.cleared = false
		run.cleared_count -= 1
		return .Invalid
	}
	return .Reward
}
