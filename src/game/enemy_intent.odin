package game

import grid "../grid"

MAX_ENEMY_INTENT_PATH_CELLS   :: 8
MAX_ENEMY_INTENT_THREAT_CELLS :: 16
ARCHER_MIN_ATTACK_RANGE       :: 2
ARCHER_MAX_ATTACK_RANGE       :: 5
BRUTE_MIN_CHARGE_RANGE        :: 2
BRUTE_MAX_CHARGE_RANGE        :: 4

Enemy_Intent_Kind :: enum {
	None,
	Wait,
	Move,
	Attack,
	Charge,
}

Enemy_Intent :: struct {
	kind:                  Enemy_Intent_Kind,
	origin:                grid.Position,
	destination:           grid.Position,
	path:                  [MAX_ENEMY_INTENT_PATH_CELLS]grid.Position,
	path_count:            int,
	threatened_cells:      [MAX_ENEMY_INTENT_THREAT_CELLS]grid.Position,
	threatened_cell_count: int,
	damage:                i32,
	planned_pulse:         u64,
}

enemy_intent_kind_name :: proc(kind: Enemy_Intent_Kind) -> string {
	switch kind {
	case .None:
		return "None"
	case .Wait:
		return "Wait"
	case .Move:
		return "Move"
	case .Attack:
		return "Attack"
	case .Charge:
		return "Charge"
	}
	return "Unknown"
}

enemy_intent_cell_is_threatened :: proc(intent: ^Enemy_Intent, position: grid.Position) -> bool {
	if intent == nil {
		return false
	}
	for index in 0..<intent.threatened_cell_count {
		if intent.threatened_cells[index] == position {
			return true
		}
	}
	return false
}

clear_enemy_intents :: proc(room: ^Room) {
	if room == nil {
		return
	}
	for &enemy in room.enemies {
		enemy.intent = {}
	}
}

enemy_ids_in_planning_order :: proc(room: ^Room) -> (
	ids: [MAX_ENEMIES_PER_ROOM]u32,
	count: int,
) {
	if room == nil {
		return
	}
	count = len(room.enemies)
	assert(count <= MAX_ENEMIES_PER_ROOM)
	for enemy, index in room.enemies {
		ids[index] = enemy.id
	}
	for index in 1..<count {
		id := ids[index]
		insert_at := index
		for insert_at > 0 && ids[insert_at-1] > id {
			ids[insert_at] = ids[insert_at-1]
			insert_at -= 1
		}
		ids[insert_at] = id
	}
	return
}

planned_cell_is_available :: proc(
	room: ^Room,
	positions: ^[MAX_ENEMIES_PER_ROOM]grid.Position,
	position_count, moving_index: int,
	target: grid.Position,
) -> bool {
	if room == nil || positions == nil || !base_cell_is_walkable(room, target) ||
	   obstacle_at(room, target) || target == room.player.position {
		return false
	}
	for index in 0..<position_count {
		if index != moving_index && positions[index] == target {
			return false
		}
	}
	return true
}

orthogonal_step_and_distance :: proc(origin, target: grid.Position) -> (
	step: grid.Position,
	distance: int,
	ok: bool,
) {
	delta_x := target.x-origin.x
	delta_y := target.y-origin.y
	if (delta_x == 0) == (delta_y == 0) {
		return
	}
	step = {x = sign(delta_x), y = sign(delta_y)}
	distance = abs(delta_x)+abs(delta_y)
	ok = true
	return
}

has_clear_orthogonal_line :: proc(room: ^Room, origin, target: grid.Position) -> bool {
	if room == nil {
		return false
	}
	_, distance, aligned := orthogonal_step_and_distance(origin, target)
	if !aligned {
		return false
	}
	path: [MAX_TARGETING_PATH_CELLS]grid.Position
	path_count, traced := trace_targeting_line(origin, target, &path)
	if !traced || path_count != distance {
		return false
	}
	_, blocked := targeting_path_blocker(room, origin, &path, path_count)
	return !blocked
}

make_wait_intent :: proc(room: ^Room, origin: grid.Position) -> Enemy_Intent {
	assert(room != nil)
	return {
		kind = .Wait,
		origin = origin,
		destination = origin,
		planned_pulse = room.pulse_count+1,
	}
}

make_attack_intent :: proc(
	room: ^Room,
	origin, target: grid.Position,
	damage: i32,
) -> Enemy_Intent {
	assert(room != nil && damage > 0)
	result := make_wait_intent(room, origin)
	result.kind = .Attack
	result.damage = damage
	result.threatened_cells[0] = target
	result.threatened_cell_count = 1
	return result
}

plan_chaser_intent :: proc(
	room: ^Room,
	enemy: ^Enemy,
	origin: grid.Position,
	predicted_positions: ^[MAX_ENEMIES_PER_ROOM]grid.Position,
	enemy_count, ordered_index: int,
) -> Enemy_Intent {
	assert(room != nil && room.player != nil && enemy != nil && predicted_positions != nil)
	delta_x := room.player.position.x-origin.x
	delta_y := room.player.position.y-origin.y
	if abs(delta_x)+abs(delta_y) == 1 {
		return make_attack_intent(room, origin, room.player.position, enemy.attack)
	}

	intent := make_wait_intent(room, origin)
	step_x := grid.Position{x = sign(delta_x), y = 0}
	step_y := grid.Position{x = 0, y = sign(delta_y)}
	first_step := step_x
	second_step := step_y
	if abs(delta_y) > abs(delta_x) {
		first_step, second_step = second_step, first_step
	}
	steps := [?]grid.Position{first_step, second_step}
	for step in steps {
		if step.x == 0 && step.y == 0 {
			continue
		}
		target := add_position(origin, step)
		if !planned_cell_is_available(
			room,
			predicted_positions,
			enemy_count,
			ordered_index,
			target,
		) {
			continue
		}
		intent.kind = .Move
		intent.destination = target
		intent.path[0] = target
		intent.path_count = 1
		break
	}
	return intent
}

plan_archer_intent :: proc(
	room: ^Room,
	enemy: ^Enemy,
	origin: grid.Position,
	predicted_positions: ^[MAX_ENEMIES_PER_ROOM]grid.Position,
	enemy_count, ordered_index: int,
) -> Enemy_Intent {
	assert(room != nil && room.player != nil && enemy != nil && predicted_positions != nil)
	player_position := room.player.position
	distance := abs(player_position.x-origin.x)+abs(player_position.y-origin.y)
	if distance == 1 {
		steps := [?]grid.Position{
			{x = 0, y = -1},
			{x = 1, y = 0},
			{x = 0, y = 1},
			{x = -1, y = 0},
		}
		intent := make_wait_intent(room, origin)
		best_distance := distance
		for step in steps {
			target := add_position(origin, step)
			if !planned_cell_is_available(
				room,
				predicted_positions,
				enemy_count,
				ordered_index,
				target,
			) {
				continue
			}
			candidate_distance := abs(player_position.x-target.x)+abs(player_position.y-target.y)
			if candidate_distance <= best_distance {
				continue
			}
			best_distance = candidate_distance
			intent.kind = .Move
			intent.destination = target
			intent.path[0] = target
			intent.path_count = 1
		}
		if intent.kind == .Move {
			return intent
		}
		return make_attack_intent(room, origin, player_position, enemy.attack)
	}

	_, _, aligned := orthogonal_step_and_distance(origin, player_position)
	if aligned && distance >= ARCHER_MIN_ATTACK_RANGE &&
	   distance <= ARCHER_MAX_ATTACK_RANGE &&
	   has_clear_orthogonal_line(room, origin, player_position) {
		return make_attack_intent(room, origin, player_position, enemy.attack)
	}
	return plan_chaser_intent(
		room,
		enemy,
		origin,
		predicted_positions,
		enemy_count,
		ordered_index,
	)
}

planned_path_is_available :: proc(
	room: ^Room,
	positions: ^[MAX_ENEMIES_PER_ROOM]grid.Position,
	position_count, moving_index: int,
	path: []grid.Position,
) -> bool {
	for position in path {
		if !planned_cell_is_available(
			room,
			positions,
			position_count,
			moving_index,
			position,
		) {
			return false
		}
	}
	return true
}

brute_charge_damage :: proc(attack: i32) -> i32 {
	if attack > max(i32)/2 {
		return max(i32)
	}
	return attack*2
}

plan_brute_intent :: proc(
	room: ^Room,
	enemy: ^Enemy,
	origin: grid.Position,
	predicted_positions: ^[MAX_ENEMIES_PER_ROOM]grid.Position,
	enemy_count, ordered_index: int,
) -> Enemy_Intent {
	assert(room != nil && room.player != nil && enemy != nil && predicted_positions != nil)
	player_position := room.player.position
	step, distance, aligned := orthogonal_step_and_distance(origin, player_position)
	if distance == 1 {
		return make_attack_intent(room, origin, player_position, enemy.attack)
	}
	if aligned && distance >= BRUTE_MIN_CHARGE_RANGE &&
	   distance <= BRUTE_MAX_CHARGE_RANGE &&
	   has_clear_orthogonal_line(room, origin, player_position) {
		intent := make_wait_intent(room, origin)
		intent.kind = .Charge
		for offset in 1..<distance {
			intent.path[intent.path_count] = {
				x = origin.x+step.x*offset,
				y = origin.y+step.y*offset,
			}
			intent.path_count += 1
		}
		if intent.path_count <= MAX_ENEMY_INTENT_PATH_CELLS &&
		   planned_path_is_available(
			room,
			predicted_positions,
			enemy_count,
			ordered_index,
			intent.path[:intent.path_count],
		) {
			intent.destination = intent.path[intent.path_count-1]
			intent.damage = brute_charge_damage(enemy.attack)
			intent.threatened_cells[0] = player_position
			intent.threatened_cell_count = 1
			return intent
		}
	}
	return plan_chaser_intent(
		room,
		enemy,
		origin,
		predicted_positions,
		enemy_count,
		ordered_index,
	)
}

validate_enemy_intent_structure :: proc(room: ^Room, intent: ^Enemy_Intent) -> bool {
	if room == nil || intent == nil || room.level_data == nil || room.phase != .Combat {
		return false
	}
	if intent.kind == .None ||
	   intent.planned_pulse != room.pulse_count+1 ||
	   intent.path_count < 0 || intent.path_count > MAX_ENEMY_INTENT_PATH_CELLS ||
	   intent.threatened_cell_count < 0 ||
	   intent.threatened_cell_count > MAX_ENEMY_INTENT_THREAT_CELLS {
		return false
	}

	switch intent.kind {
	case .None:
		return false
	case .Wait:
		return intent.destination == intent.origin && intent.path_count == 0 &&
		       intent.threatened_cell_count == 0 && intent.damage == 0
	case .Move:
		if intent.path_count != 1 || intent.threatened_cell_count != 0 ||
		   intent.damage != 0 || intent.destination != intent.path[0] ||
		   abs(intent.origin.x-intent.destination.x)+
		   abs(intent.origin.y-intent.destination.y) != 1 {
			return false
		}
		return base_cell_is_walkable(room, intent.destination) &&
		       !obstacle_at(room, intent.destination)
	case .Attack:
		if intent.destination != intent.origin || intent.path_count != 0 ||
		   intent.threatened_cell_count <= 0 || intent.damage <= 0 {
			return false
		}
		for position, index in intent.threatened_cells[:intent.threatened_cell_count] {
			if !grid.contains(&room.level_data.tiles, position) {
				return false
			}
			for previous_index in 0..<index {
				if intent.threatened_cells[previous_index] == position {
					return false
				}
			}
		}
		return true
	case .Charge:
		if intent.path_count <= 0 || intent.destination != intent.path[intent.path_count-1] ||
		   intent.threatened_cell_count <= 0 || intent.damage <= 0 {
			return false
		}
		previous := intent.origin
		charge_step := grid.Position{
			x = intent.path[0].x-intent.origin.x,
			y = intent.path[0].y-intent.origin.y,
		}
		if abs(charge_step.x)+abs(charge_step.y) != 1 {
			return false
		}
		for position, index in intent.path[:intent.path_count] {
			step := grid.Position{x = position.x-previous.x, y = position.y-previous.y}
			if step != charge_step || !base_cell_is_walkable(room, position) ||
			   obstacle_at(room, position) {
				return false
			}
			for previous_index in 0..<index {
				if intent.path[previous_index] == position {
					return false
				}
			}
			previous = position
		}
		for position, index in intent.threatened_cells[:intent.threatened_cell_count] {
			if !grid.contains(&room.level_data.tiles, position) {
				return false
			}
			for previous_index in 0..<index {
				if intent.threatened_cells[previous_index] == position {
					return false
				}
			}
		}
		return true
	}
	return false
}

validate_enemy_intent :: proc(room: ^Room, enemy: ^Enemy) -> bool {
	return enemy != nil && enemy.intent.origin == enemy.position &&
	       validate_enemy_intent_structure(room, &enemy.intent)
}

validate_enemy_intents :: proc(room: ^Room) -> bool {
	if room == nil {
		return false
	}
	if room.phase != .Combat {
		for &enemy in room.enemies {
			if enemy.intent.kind != .None {
				return false
			}
		}
		return true
	}
	for &enemy in room.enemies {
		if !validate_enemy_intent(room, &enemy) {
			return false
		}
	}
	return true
}

plan_enemy_intents :: proc(room: ^Room) {
	if room == nil || room.player == nil || room.phase != .Combat {
		clear_enemy_intents(room)
		return
	}

	ids, enemy_count := enemy_ids_in_planning_order(room)
	predicted_positions: [MAX_ENEMIES_PER_ROOM]grid.Position
	for ordered_index in 0..<enemy_count {
		enemy_index, found := enemy_index_by_id(room, ids[ordered_index])
		assert(found)
		predicted_positions[ordered_index] = room.enemies[enemy_index].position
	}

	for ordered_index in 0..<enemy_count {
		enemy_index, found := enemy_index_by_id(room, ids[ordered_index])
		assert(found)
		enemy := &room.enemies[enemy_index]
		origin := predicted_positions[ordered_index]
		intent: Enemy_Intent
		switch enemy.archetype {
		case .Chaser:
			intent = plan_chaser_intent(
				room,
				enemy,
				origin,
				&predicted_positions,
				enemy_count,
				ordered_index,
			)
		case .Archer:
			intent = plan_archer_intent(
				room,
				enemy,
				origin,
				&predicted_positions,
				enemy_count,
				ordered_index,
			)
		case .Brute:
			intent = plan_brute_intent(
				room,
				enemy,
				origin,
				&predicted_positions,
				enemy_count,
				ordered_index,
			)
		case .Count:
			unreachable()
		}
		if intent.kind == .Move || intent.kind == .Charge {
			predicted_positions[ordered_index] = intent.destination
		}
		enemy.intent = intent
	}
	assert(validate_enemy_intents(room))
}

enemy_charge_path_is_clear :: proc(
	room: ^Room,
	enemy_index: int,
	intent: ^Enemy_Intent,
) -> bool {
	if room == nil || intent == nil || enemy_index < 0 || enemy_index >= len(room.enemies) ||
	   room.enemies[enemy_index].position != intent.origin {
		return false
	}
	for index in 0..<intent.path_count {
		position := intent.path[index]
		if !base_cell_is_walkable(room, position) || obstacle_at(room, position) ||
		   position == room.player.position {
			return false
		}
		if _, occupied := enemy_index_at(room, position, enemy_index); occupied {
			return false
		}
	}
	return true
}

record_enemy_attack_miss :: proc(
	pulse: ^Pulse_Report,
	source: Entity_Ref,
	from_position, target_position: grid.Position,
) {
	assert(pulse != nil)
	record_event(&pulse.events, {
		kind = .Attack_Missed,
		source = source,
		target = PLAYER_ENTITY,
		from_position = from_position,
		to_position = target_position,
	})
}

resolve_enemy_intents :: proc(room: ^Room, pulse: ^Pulse_Report) {
	assert(room != nil && room.player != nil && pulse != nil)
	if room.phase != .Combat {
		return
	}

	ids, enemy_count := enemy_ids_in_planning_order(room)
	for ordered_index in 0..<enemy_count {
		enemy_index, found := enemy_index_by_id(room, ids[ordered_index])
		if !found {
			continue
		}
		enemy := &room.enemies[enemy_index]
		assert(validate_enemy_intent_structure(room, &enemy.intent))
		intent := enemy.intent
		enemy.intent = {}
		source := enemy_entity(enemy.id)

		switch intent.kind {
		case .None:
			unreachable()
		case .Wait:
			continue
		case .Attack:
			pulse.enemy_actions += 1
			if enemy.position != intent.origin ||
			   !enemy_intent_cell_is_threatened(&intent, room.player.position) {
				record_enemy_attack_miss(
					pulse,
					source,
					enemy.position,
					intent.threatened_cells[0],
				)
				continue
			}
			action := make_action(.Attack, source, entity_target(PLAYER_ENTITY), .Opponent)
			added := add_effect(&action, damage_effect(PLAYER_ENTITY, intent.damage))
			assert(added)
			report := resolve_action(room, &action)
			assert(report.accepted)
			merge_action_report(pulse, &report)
			if report.player_defeated || room.phase != .Combat {
				return
			}
		case .Move:
			pulse.enemy_actions += 1
			destination := intent.destination
			if enemy.position != intent.origin ||
			   !enemy_can_move_to(room, enemy_index, destination) {
				record_event(&pulse.events, {
					kind = .Move_Blocked,
					source = source,
					target = source,
					from_position = enemy.position,
					to_position = destination,
				})
				continue
			}
			action := make_action(.Move, source, cell_target(destination), .Walkable_Cell)
			added := add_effect(&action, move_effect(source, destination))
			assert(added)
			report := resolve_action(room, &action)
			assert(report.accepted)
			merge_action_report(pulse, &report)
			if room.phase != .Combat {
				return
			}
		case .Charge:
			pulse.enemy_actions += 1
			if !enemy_charge_path_is_clear(room, enemy_index, &intent) {
				record_event(&pulse.events, {
					kind = .Move_Blocked,
					source = source,
					target = source,
					from_position = enemy.position,
					to_position = intent.destination,
				})
				continue
			}
			move_action := make_action(.Move, source, cell_target(intent.destination), .Walkable_Cell)
			added_move := add_effect(&move_action, move_effect(source, intent.destination))
			assert(added_move)
			move_report := resolve_action(room, &move_action)
			assert(move_report.accepted)
			merge_action_report(pulse, &move_report)
			if room.phase != .Combat {
				return
			}
			moved_enemy_index, source_alive := enemy_index_by_id(room, source.id)
			if !source_alive {
				continue
			}
			moved_enemy := &room.enemies[moved_enemy_index]
			if !enemy_intent_cell_is_threatened(&intent, room.player.position) {
				record_enemy_attack_miss(
					pulse,
					source,
					moved_enemy.position,
					intent.threatened_cells[0],
				)
				continue
			}
			attack_action := make_action(.Attack, source, entity_target(PLAYER_ENTITY), .Opponent)
			added_attack := add_effect(&attack_action, damage_effect(PLAYER_ENTITY, intent.damage))
			assert(added_attack)
			attack_report := resolve_action(room, &attack_action)
			assert(attack_report.accepted)
			merge_action_report(pulse, &attack_report)
			if attack_report.player_defeated || room.phase != .Combat {
				return
			}
		}
	}
}
