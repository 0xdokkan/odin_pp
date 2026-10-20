package game

import "core:slice"
import grid "../engine/grid"

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
	Bombard,
	Recover,
	Protect,
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
	protected_ally:        Entity_Ref,
	windup:                bool,
	target_object:         u32,
	push:                  bool,
	// M7: the seconds Rallentamento added when this intent was planned
	// (tactical_schedule_enemy); its countdown and ground warning include them.
	slowed:                i32,
}

@(private = "file")
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
	case .Bombard:
		return "Bombard"
	case .Recover:
		return "Recover"
	case .Protect:
		return "Protect"
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

@(private)
clear_enemy_intents :: proc(room: ^Room) {
	if room == nil {
		return
	}
	for &enemy in room.enemies {
		enemy.intent = {}
	}
}

@(private)
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
	slice.sort(ids[:count])
	return
}

@(private)
planned_cell_is_available :: proc(
	room: ^Room,
	positions: ^[MAX_ENEMIES_PER_ROOM]grid.Position,
	position_count, moving_index: int,
	target: grid.Position,
) -> bool {
	if room == nil || positions == nil || cell_blocks_movement(room, target) ||
	   target == room.player.position {
		return false
	}
	for index in 0..<position_count {
		if index != moving_index && positions[index] == target {
			return false
		}
	}
	return true
}

@(private)
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

@(private)
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

// Campo delle distanze statiche al player. Gli attori vengono considerati dalle
// prenotazioni del singolo passo, cosi le destinazioni restano ordinate per ID.
@(private = "file")
rebuild_enemy_path_distances :: proc(room: ^Room) {
	rebuild_tactical_enemy_distances(room, room.enemy_path_distances, .Melee)
}

@(private)
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
	origin_index, valid_origin := grid.index_of(&room.level_data.tiles, origin)
	if !valid_origin || room.enemy_path_distances[origin_index] < 0 {
		return intent
	}
	best_distance := room.enemy_path_distances[origin_index]
	steps := [?]grid.Position{first_step, second_step, {0, -1}, {1, 0}, {0, 1}, {-1, 0}}
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
		index, _ := grid.index_of(&room.level_data.tiles, target)
		distance := room.enemy_path_distances[index]
		if distance >= 0 { distance += enemy_terrain_danger(room, target) }
		if distance < 0 || distance >= best_distance {
			continue
		}
		best_distance = distance
		intent.kind = .Move
		intent.destination = target
		intent.path[0] = target
		intent.path_count = 1
	}
	return intent
}

@(private = "file")
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

@(private = "file")
brute_charge_damage :: proc(attack: i32) -> i32 {
	if attack > max(i32)/2 {
		return max(i32)
	}
	return attack*2
}

@(private)
plan_brute_intent :: proc(
	room: ^Room,
	enemy: ^Enemy,
	origin: grid.Position,
	predicted_positions: ^[MAX_ENEMIES_PER_ROOM]grid.Position,
	enemy_count, ordered_index: int,
	max_charge_range := BRUTE_MAX_CHARGE_RANGE,
) -> Enemy_Intent {
	assert(room != nil && room.player != nil && enemy != nil && predicted_positions != nil)
	player_position := room.player.position
	step, distance, aligned := orthogonal_step_and_distance(origin, player_position)
	if distance == 1 {
		return make_attack_intent(room, origin, player_position, enemy.attack)
	}
	if aligned && distance >= BRUTE_MIN_CHARGE_RANGE &&
	   distance <= max_charge_range &&
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

@(private)
validate_enemy_intent_structure :: proc(room: ^Room, intent: ^Enemy_Intent) -> bool {
	if room == nil || intent == nil || room.level_data == nil || room.phase != .Combat {
		return false
	}
	// Telegraphs remain committed across world beats until their own deadline.
	valid_plan_time := intent.planned_pulse > 0 && intent.planned_pulse <= room.pulse_count+1
	if intent.kind == .None || !valid_plan_time ||
	   intent.path_count < 0 || intent.path_count > MAX_ENEMY_INTENT_PATH_CELLS ||
	   intent.threatened_cell_count < 0 ||
	   intent.threatened_cell_count > MAX_ENEMY_INTENT_THREAT_CELLS {
		return false
	}

	switch intent.kind {
	case .None:
		return false
	case .Wait, .Recover:
		return intent.destination == intent.origin && intent.path_count == 0 &&
		       intent.threatened_cell_count == 0 && intent.damage == 0
	case .Protect:
		return intent.protected_ally.kind == .Enemy && intent.protected_ally.id != 0 &&
		       intent.path_count == 0 && intent.threatened_cell_count == 0 && intent.damage == 0 &&
		       abs(intent.origin.x-intent.destination.x)+abs(intent.origin.y-intent.destination.y) > 0 &&
		       abs(intent.origin.x-intent.destination.x)+abs(intent.origin.y-intent.destination.y) <= CUSTODIAN_PROTECT_RANGE &&
		       base_cell_is_walkable(room, intent.destination) && !obstacle_at(room, intent.destination)
	case .Move:
		if intent.path_count != 1 || intent.threatened_cell_count != 0 ||
		   intent.damage != 0 || intent.destination != intent.path[0] ||
		   abs(intent.origin.x-intent.destination.x)+
		   abs(intent.origin.y-intent.destination.y) != 1 {
			return false
		}
		// Movable grid objects are runtime blockers, not part of the committed
		// intent's immutable structure. Resolution rechecks them and emits
		// Move_Blocked if the board changed after planning.
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
	case .Bombard:
		if intent.path_count != 0 || intent.damage != TACTICAL_BOMB_DAMAGE ||
		   !base_cell_is_walkable(room, intent.destination) || obstacle_at(room, intent.destination) {
			return false
		}
		for cell, index in intent.threatened_cells[:intent.threatened_cell_count] {
			if !explosion_contains_cell(room, intent.destination, cell) ||
			   position_in_list(intent.threatened_cells[:index], cell) {
				return false
			}
		}
		for y in intent.destination.y-1..=intent.destination.y+1 {
			for x in intent.destination.x-1..=intent.destination.x+1 {
				cell := grid.Position{x, y}
				if explosion_contains_cell(room, intent.destination, cell) !=
				   enemy_intent_cell_is_threatened(intent, cell) {
					return false
				}
			}
		}
		return intent.threatened_cell_count > 0 && intent.threatened_cell_count <= 9
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

@(private)
validate_enemy_intent :: proc(room: ^Room, enemy: ^Enemy) -> bool {
	// M7 keeps a committed telegraph when a player pushes its owner. Its original
	// origin deliberately survives until the deadline so that the action misses.
	return enemy != nil && validate_enemy_intent_structure(room, &enemy.intent)
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
		// A foe out of play (the Lazzo's in the air, the Pinball's ball)
		// intends nothing.
		if enemy_is_out_of_play(room, enemy.id) {
			if enemy.intent.kind != .None { return false }
			continue
		}
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
	rebuild_enemy_path_distances(room)
	predicted_positions: [MAX_ENEMIES_PER_ROOM]grid.Position
	bomb_anchors: [MAX_ACTIVE_BOMBS]grid.Position
	bomb_anchor_count := 0
	for ordered_index in 0..<enemy_count {
		enemy_index, found := enemy_index_by_id(room, ids[ordered_index])
		assert(found)
		predicted_positions[ordered_index] = room.enemies[enemy_index].position
		// A foe out of play stands on no cell: the others plan through it.
		if enemy_is_out_of_play(room, ids[ordered_index]) { predicted_positions[ordered_index] = LASSO_NO_CELL }
	}

	for ordered_index in 0..<enemy_count {
		enemy_index, found := enemy_index_by_id(room, ids[ordered_index])
		assert(found)
		enemy := &room.enemies[enemy_index]
		// In the air it plans nothing: its next intent waits for its fall. The
		// ball plans nothing until it bursts.
		if enemy_is_out_of_play(room, enemy.id) {
			enemy.intent = {}
			continue
		}
		origin := predicted_positions[ordered_index]
		if enemy.intent.kind != .None && enemy.tactical_cooldown > 0 {
			// Reserve the same committed destination while other enemies plan; a
			// one-second world beat must not retarget a slower enemy's telegraph.
			if enemy.intent.kind == .Move || enemy.intent.kind == .Charge {
				predicted_positions[ordered_index] = enemy.intent.destination
			}
			if enemy.intent.kind == .Bombard {
				bomb_anchors[bomb_anchor_count] = enemy.intent.destination
				bomb_anchor_count += 1
			}
			continue
		}
		update_demolitionist_phase(enemy)
		if enemy.recovery_pulses > 0 {
			enemy.intent = make_wait_intent(room, origin)
			enemy.intent.kind = .Recover
			tactical_schedule_enemy(room, enemy)
			continue
		}
		if !enemy.bomb_ready && !enemy.aim_ready {
			if escape, fleeing := tactical_enemy_escape(room, origin, &predicted_positions, enemy_count, ordered_index); fleeing {
				enemy.intent = escape
				tactical_schedule_enemy(room, enemy)
				predicted_positions[ordered_index] = escape.destination
				continue
			}
		}
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
			intent = plan_tactical_archer(
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
		case .Bomber:
			intent = plan_tactical_bomber(room, enemy, origin, &predicted_positions,
				enemy_count, ordered_index, bomb_anchors[:bomb_anchor_count])
		case .Custodian:
			intent = plan_custodian_intent(room, enemy, origin, &predicted_positions,
				enemy_count, ordered_index)
		case .Demolitionist:
			intent = plan_demolitionist_intent(room, enemy, origin, &predicted_positions,
				enemy_count, ordered_index, bomb_anchors[:bomb_anchor_count])
		case .Count:
			unreachable()
		}
		if enemy.archetype == .Brute && intent.kind == .Attack {
			step, _, aligned := orthogonal_step_and_distance(origin, intent.threatened_cells[0])
			if aligned {
				center := intent.threatened_cells[0]
				for sign in ([?]int{-1, 1}) {
					cell := grid.Position{center.x+step.y*sign, center.y+step.x*sign}
					if grid.contains(&room.level_data.tiles, cell) && shape_cell_has_clear_path(room, origin, cell) {
						intent.threatened_cells[intent.threatened_cell_count] = cell
						intent.threatened_cell_count += 1
					}
				}
			}
		}
		if intent.kind == .Bombard {
			bomb_anchors[bomb_anchor_count] = intent.destination
			bomb_anchor_count += 1
		}
		if (enemy.archetype == .Brute || enemy.archetype == .Demolitionist) &&
		   (intent.kind == .Attack || intent.kind == .Charge) { intent.push = true }
		if intent.kind == .Move || intent.kind == .Charge {
			predicted_positions[ordered_index] = intent.destination
		}
		enemy.intent = intent
		tactical_schedule_enemy(room, enemy)
	}
	assert(validate_enemy_intents(room))
}

@(private)
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
		if cell_blocks_movement(room, position) || position == room.player.position {
			return false
		}
		if _, occupied := enemy_index_at(room, position, enemy_index); occupied {
			return false
		}
	}
	return true
}

// A miss on the player, or on the object a shot was aimed at (`target`).
@(private)
record_enemy_attack_miss :: proc(
	pulse: ^Pulse_Report,
	source: Entity_Ref,
	from_position, target_position: grid.Position,
	blow: ^Enemy_Intent = nil,
	ranged := false,
	target := PLAYER_ENTITY,
) {
	assert(pulse != nil)
	first := pulse.events.count
	record_event(&pulse.events, {
		kind = .Attack_Missed,
		source = source,
		target = target,
		from_position = from_position,
		to_position = target_position,
	})
	// A blow struck and missed still swings over its cells (or flies to them).
	// A blow never struck (an aim broken, a throw that never leaves the hand,
	// a charge parried before it ran) stays unmarked: the board shows none.
	if blow != nil {
		mark_attack_events(&pulse.events, first, source, target, from_position, target_position,
			blow.threatened_cells[:blow.threatened_cell_count], ranged)
	}
}

// Archers shoot and bombers throw; an object is struck from afar.
@(private = "file")
enemy_attack_is_ranged :: proc(enemy: ^Enemy, intent: ^Enemy_Intent) -> bool {
	return enemy.archetype == .Archer || enemy.archetype == .Bomber || intent.target_object != 0
}

// A confirmed attack and the blow after a charge share the same hit pipeline.
// Their callers own aiming, cancellation and movement; the blow owns Deflect,
// damage/reactions, attack cues and the tactical push, in that order.
@(private)
resolve_enemy_blow :: proc(room: ^Room, enemy: ^Enemy, intent: ^Enemy_Intent, ranged: bool, pulse: ^Pulse_Report) -> bool {
	source := enemy_entity(enemy.id)
	if deflect_enemy_blow(room, source, enemy.position, intent, ranged, pulse) {
		return room.phase != .Combat
	}
	action := make_action(.Attack, source, entity_target(PLAYER_ENTITY), .Opponent)
	added := add_effect(&action, damage_effect(PLAYER_ENTITY, intent.damage))
	assert(added)
	report := resolve_action(room, &action)
	assert(report.accepted)
	mark_attack_events(&report.events, 0, source, PLAYER_ENTITY, enemy.position, intent.threatened_cells[0],
		intent.threatened_cells[:intent.threatened_cell_count], ranged)
	merge_action_report(pulse, &report)
	resolve_tactical_enemy_push(room, source, intent, &report, pulse)
	return report.player_defeated || room.phase != .Combat
}

resolve_enemy_intents :: proc(room: ^Room, pulse: ^Pulse_Report, only_id: u32 = 0) {
	assert(room != nil && room.player != nil && pulse != nil)
	if room.phase != .Combat {
		return
	}

	ids, enemy_count := enemy_ids_in_planning_order(room)
	protected_ids: [MAX_ENEMIES_PER_ROOM]u32
	protected_count := 0
	// Support resolves before natural movement, so an ally's ordinary move cannot
	// cancel protection merely because it has a lower spawn ID. Player-forced
	// displacement has already happened and still breaks the frozen intent.
	for ordered_index in 0..<enemy_count {
		if only_id != 0 && ids[ordered_index] != only_id { continue }
		enemy_index, found := enemy_index_by_id(room, ids[ordered_index])
		if !found || room.enemies[enemy_index].intent.kind != .Protect || enemy_is_out_of_play(room, ids[ordered_index]) {
			continue
		}
		enemy := &room.enemies[enemy_index]
		assert(validate_enemy_intent_structure(room, &enemy.intent))
		protected_ids[protected_count] = enemy.id
		protected_count += 1
		if interrupt_staggered_enemy(room, enemy, pulse) { continue }
		source, slowed := enemy_entity(enemy.id), enemy.intent.slowed > 0
		resolve_custodian_protection(room, enemy, pulse)
		finish_enemy_action(room, source, slowed, pulse)
		if room.phase != .Combat {
			return
		}
	}
	for ordered_index in 0..<enemy_count {
		if only_id != 0 && ids[ordered_index] != only_id { continue }
		already_resolved := false
		for id in protected_ids[:protected_count] {
			if id == ids[ordered_index] {
				already_resolved = true
				break
			}
		}
		if already_resolved {
			continue
		}
		enemy_index, found := enemy_index_by_id(room, ids[ordered_index])
		// A foe out of play does nothing.
		if !found || enemy_is_out_of_play(room, ids[ordered_index]) {
			continue
		}
		enemy := &room.enemies[enemy_index]
		assert(validate_enemy_intent_structure(room, &enemy.intent))
		if interrupt_staggered_enemy(room, enemy, pulse) { continue }
		intent := enemy.intent
		enemy.intent = {}
		source := enemy_entity(enemy.id)
		// Whatever its intent turns into (a hit, a miss, a blocked step, a
		// wait), it was its owner's action: its poison and slow follow it, on
		// every way out of this iteration. A staggered enemy, interrupted
		// above, did not act.
		defer finish_enemy_action(room, source, intent.slowed > 0, pulse)

		switch intent.kind {
		case .None, .Protect:
			unreachable()
		case .Wait:
			begin_demolitionist_approach(enemy)
			continue
		case .Recover:
			enemy.recovery_pulses = max(i32(0), enemy.recovery_pulses-1)
			continue
		case .Bombard:
			pulse.enemy_actions += 1
			if intent.windup {
				enemy.bomb_ready = enemy.position == intent.origin
				enemy.bomb_anchor = intent.destination
				if !enemy.bomb_ready { enemy.recovery_pulses = 1; record_enemy_attack_miss(pulse, source, enemy.position, intent.destination) }
				continue
			}
			enemy.bomb_ready = false
			enemy.recovery_pulses = 1
			begin_demolitionist_offense(enemy, intent.kind)
			enemy.recovery_pulses = max(enemy.recovery_pulses, TACTICAL_BOMBER_RECOVERY)
			if enemy.position != intent.origin ||
			   (active_bomb_count(room) >= TACTICAL_BOMB_LIMIT || !enemy_has_lob_line(room, enemy.position, intent.destination)) ||
			   !spawn_bomb(room, source, intent.destination, &pulse.events) {
				record_enemy_attack_miss(pulse, source, enemy.position, intent.destination)
			}
			continue
		case .Attack:
			pulse.enemy_actions += 1
			if intent.windup {
				enemy.aim_ready = enemy.position == intent.origin
				enemy.aim_anchor = intent.threatened_cells[0]
				if !enemy.aim_ready { enemy.recovery_pulses = 1; record_enemy_attack_miss(pulse, source, enemy.position, enemy.aim_anchor) }
				continue
			}
			enemy.aim_ready = false
			begin_demolitionist_offense(enemy, intent.kind)
			enemy.recovery_pulses = max(i32(1), enemy.recovery_pulses)
			if intent.target_object != 0 {
				object_index, present := object_index_by_id(room, intent.target_object)
				if enemy.position != intent.origin || !present ||
				   room.objects[object_index].position != intent.threatened_cells[0] ||
				   !enemy_has_lob_line(room, enemy.position, intent.threatened_cells[0]) {
					// The ember is thrown all the same, at the cell its barrel stood on.
					record_enemy_attack_miss(pulse, source, enemy.position, intent.threatened_cells[0], &intent, true,
						object_entity(intent.target_object))
					continue
				}
				action := make_action(.Attack, source, entity_target(object_entity(intent.target_object)), .Entity)
				added := add_effect(&action, damage_effect(object_entity(intent.target_object), intent.damage))
				assert(added)
				report := resolve_action(room, &action)
				mark_attack_events(&report.events, 0, source, object_entity(intent.target_object), enemy.position,
					intent.threatened_cells[0], intent.threatened_cells[:1], true)
				merge_action_report(pulse, &report)
				if room.phase != .Combat { return }
				continue
			}
			ranged := enemy_attack_is_ranged(enemy, &intent)
			if room.tactical_pulse.cancel_attack == enemy.id {
				record_enemy_attack_miss(pulse, source, enemy.position, intent.threatened_cells[0], &intent, ranged)
				continue
			}
			if enemy.position != intent.origin ||
			   !enemy_intent_cell_is_threatened(&intent, room.player.position) ||
			   (enemy.archetype == .Archer &&
			    !has_clear_orthogonal_line(room, enemy.position, room.player.position)) {
				record_enemy_attack_miss(
					pulse,
					source,
					enemy.position,
					intent.threatened_cells[0],
					&intent,
					ranged,
				)
				continue
			}
			if resolve_enemy_blow(room, enemy, &intent, ranged, pulse) { return }
		case .Move:
			pulse.enemy_actions += 1
			begin_demolitionist_approach(enemy)
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
			enemy.recovery_pulses = 1
			begin_demolitionist_offense(enemy, intent.kind)
			enemy.recovery_pulses = max(i32(2), enemy.recovery_pulses)
			// Parried before it ran: the brute never left his cell, so no blow.
			if room.tactical_pulse.cancel_attack == enemy.id {
				record_enemy_attack_miss(pulse, source, enemy.position, intent.threatened_cells[0])
				continue
			}
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
					&intent,
				)
				continue
			}
			if resolve_enemy_blow(room, moved_enemy, &intent, false, pulse) { return }
		}
	}
}
