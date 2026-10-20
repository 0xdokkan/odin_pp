package combatdebug

import game "../game"
import grid "../engine/grid"

Max_Distance_Policy_State :: struct {
	has_last_direction: bool,
	last_direction:     game.Move_Direction,
}

Kiting_Decision :: struct {
	valid:     bool,
	kind:      Command_Kind,
	direction: game.Move_Direction,
}

Kiting_Score :: struct {
	hazard_damage:   i64,
	threat_count:     int,
	minimum_distance: int,
	total_distance:   int,
	continues_heading: bool,
	order:             int,
}

predicted_enemy_position :: proc(enemy: ^game.Enemy) -> grid.Position {
	assert(enemy != nil)
	switch enemy.intent.kind {
	case .Move, .Charge:
		return enemy.intent.destination
	case .None, .Wait, .Attack, .Bombard, .Recover, .Protect:
		return enemy.position
	}
	unreachable()
}

candidate_is_legal :: proc(room: ^game.Room, position: grid.Position) -> bool {
	query := game.query_entity_movement(room, game.PLAYER_ENTITY, position)
	return game.movement_query_is_clear(&query)
}

score_candidate :: proc(
	room: ^game.Room,
	position: grid.Position,
	direction: game.Move_Direction,
	is_move: bool,
	order: int,
	state: ^Max_Distance_Policy_State,
) -> (score: Kiting_Score, ok: bool) {
	if room == nil || room.player == nil || len(room.enemies) == 0 {
		return
	}
	if is_move {
		if !candidate_is_legal(room, position) {
			return
		}
		if index, found := game.trap_index_at(room, position); found && room.traps[index].armed {
			score.hazard_damage += i64(room.traps[index].damage)
		}
		if index, found := game.object_index_at(room, position); found {
			definition, valid := game.grid_object_definition(room.objects[index].kind)
			if valid && definition.hazardous {
				score.hazard_damage += i64(definition.hazard_damage)
			}
		}
	} else if position != room.player.position {
		return
	}
	score.order = order
	if room.modifier.kind != .None && room.modifier.activation_pulse != 0 &&
	   room.modifier.activation_pulse <= room.pulse_count+1 &&
	   game.room_modifier_contains_cell(&room.modifier, position) {
		score.hazard_damage += i64(room.modifier.damage)
	}
	for object in room.objects {
		if object.detonation_pulse != 0 && object.detonation_pulse <= room.pulse_count+1 &&
		   game.explosion_contains_cell(room, object.position, position) {
			score.hazard_damage += i64(game.EXPLOSIVE_DAMAGE)
		}
	}
	score.continues_heading = is_move && state != nil && state.has_last_direction &&
	                          direction == state.last_direction
	for &enemy, index in room.enemies {
		if enemy.intent.kind != .Bombard && game.enemy_intent_cell_is_threatened(&enemy.intent, position) {
			score.threat_count += 1
		}
		distance := manhattan_distance(position, predicted_enemy_position(&enemy))
		if index == 0 || distance < score.minimum_distance {
			score.minimum_distance = distance
		}
		score.total_distance += distance
	}
	return score, true
}

score_is_better :: proc(candidate, current: Kiting_Score) -> bool {
	if candidate.hazard_damage != current.hazard_damage {
		return candidate.hazard_damage < current.hazard_damage
	}
	if candidate.threat_count != current.threat_count {
		return candidate.threat_count < current.threat_count
	}
	if candidate.minimum_distance != current.minimum_distance {
		return candidate.minimum_distance > current.minimum_distance
	}
	if candidate.total_distance != current.total_distance {
		return candidate.total_distance > current.total_distance
	}
	if candidate.continues_heading != current.continues_heading {
		return candidate.continues_heading
	}
	return candidate.order < current.order
}

choose_max_distance_command :: proc(
	room: ^game.Room,
	state: ^Max_Distance_Policy_State,
) -> (decision: Kiting_Decision) {
	if room == nil || room.player == nil || room.phase != .Combat || len(room.enemies) == 0 {
		return
	}
	directions := [?]game.Move_Direction{.North, .East, .South, .West}
	best_score: Kiting_Score
	has_best := false
	for direction, order in directions {
		position := game.add_position(room.player.position, game.direction_offset(direction))
		score, valid := score_candidate(room, position, direction, true, order, state)
		if !valid || (has_best && !score_is_better(score, best_score)) {
			continue
		}
		has_best = true
		best_score = score
		decision = {valid = true, kind = .Move, direction = direction}
	}

	wait_score, wait_valid := score_candidate(
		room,
		room.player.position,
		.North,
		false,
		len(directions),
		state,
	)
	if wait_valid && (!has_best || score_is_better(wait_score, best_score)) {
		return {valid = true, kind = .Wait}
	}
	return decision
}

command_kind_for_move :: proc(
	room: ^game.Room,
	direction: game.Move_Direction,
) -> (kind: Command_Kind, ok: bool) {
	if room == nil || room.player == nil || (room.phase != .Combat && room.phase != .Loot) {
		return
	}
	if room.phase == .Combat {
		target := game.add_position(room.player.position, game.direction_offset(direction))
		if _, found := game.enemy_index_at(room, target); found {
			return .Bump_Attack, true
		}
	}
	return .Move, true
}
