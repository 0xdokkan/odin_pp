package game

import grid "../grid"

CUSTODIAN_PROTECT_RANGE :: 2
CUSTODIAN_SHIELD_AMOUNT :: 3
CUSTODIAN_SHIELD_PULSES :: 2

custodian_shield_amount :: proc(room: ^Room) -> i32 { return 2 if tactical_enabled(room) else CUSTODIAN_SHIELD_AMOUNT }

custodian_has_support_line :: proc(room: ^Room, origin, target: grid.Position) -> bool {
	distance := abs(origin.x-target.x)+abs(origin.y-target.y)
	if distance <= 0 || distance > CUSTODIAN_PROTECT_RANGE {
		return false
	}
	path: [MAX_TARGETING_PATH_CELLS]grid.Position
	count, traced := trace_targeting_line(origin, target, &path)
	if !traced {
		return false
	}
	_, blocked := targeting_path_blocker(room, origin, &path, count)
	return !blocked
}

plan_custodian_intent :: proc(
	room: ^Room, enemy: ^Enemy, origin: grid.Position,
	predicted_positions: ^[MAX_ENEMIES_PER_ROOM]grid.Position,
	enemy_count, ordered_index: int,
) -> Enemy_Intent {
	// Stable target choice independent of unordered enemy removal. Protect the
	// ally closest to the player, favouring attackers over other custodians.
	best_id: u32
	best_score := max(int)
	for &ally in room.enemies {
		if ally.id == enemy.id || (tactical_enabled(room) && ally.archetype == .Custodian) || !custodian_has_support_line(room, origin, ally.position) {
			continue
		}
		shield, shielded := status_for_entity(room, enemy_entity(ally.id), .Shield)
		if shielded && shield.potency >= custodian_shield_amount(room) {
			continue
		}
		score := abs(ally.position.x-room.player.position.x)+abs(ally.position.y-room.player.position.y)
		if ally.archetype == .Custodian {
			score += len(room.level_data.tiles.cells)
		}
		if score < best_score || (score == best_score && ally.id < best_id) {
			best_score, best_id = score, ally.id
		}
	}
	if best_id != 0 {
		ally_index, _ := enemy_index_by_id(room, best_id)
		intent := make_wait_intent(room, origin)
		intent.kind = .Protect
		intent.protected_ally = enemy_entity(best_id)
		intent.destination = room.enemies[ally_index].position
		return intent
	}

	// Approach the nearest ally while sharing the ordinary movement reservation
	// rules. If cover blocks that approach, the existing player BFS is a fallback.
	ally_position: grid.Position
	best_distance := max(int)
	best_id = 0
	for ally in room.enemies {
		if ally.id == enemy.id || (tactical_enabled(room) && ally.archetype == .Custodian) {
			continue
		}
		distance := abs(origin.x-ally.position.x)+abs(origin.y-ally.position.y)
		if distance < best_distance || (distance == best_distance && ally.id < best_id) {
			best_distance, best_id, ally_position = distance, ally.id, ally.position
		}
	}
	if best_id != 0 && best_distance > 1 {
		intent := make_wait_intent(room, origin)
		steps := [?]grid.Position{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}
		for step in steps {
			target := add_position(origin, step)
			distance := abs(target.x-ally_position.x)+abs(target.y-ally_position.y)
			if distance >= best_distance || !planned_cell_is_available(room,
				predicted_positions, enemy_count, ordered_index, target) {
				continue
			}
			best_distance = distance
			intent.kind = .Move
			intent.destination = target
			intent.path[0] = target
			intent.path_count = 1
		}
		if intent.kind == .Move {
			return intent
		}
	}
	return plan_chaser_intent(room, enemy, origin, predicted_positions, enemy_count, ordered_index)
}

resolve_custodian_protection :: proc(room: ^Room, enemy: ^Enemy, pulse: ^Pulse_Report) {
	intent := enemy.intent
	source := enemy_entity(enemy.id)
	enemy.intent = {}
	enemy.recovery_pulses = 2 if tactical_enabled(room) else 1
	pulse.enemy_actions += 1
	ally_index, found := enemy_index_by_id(room, intent.protected_ally.id)
	if enemy.position != intent.origin || !found ||
	   room.enemies[ally_index].position != intent.destination ||
	   !custodian_has_support_line(room, enemy.position, intent.destination) {
		record_event(&pulse.events, {
			kind = .Attack_Missed,
			source = source,
			target = intent.protected_ally,
			from_position = enemy.position,
			to_position = intent.destination,
		})
		return
	}
	action := make_action(.Trigger, source, entity_target(intent.protected_ally), .Entity)
	// Enemy effects are followed by the same pulse's status tick.
	added := add_effect(&action, apply_status_effect(intent.protected_ally, .Shield,
		custodian_shield_amount(room), CUSTODIAN_SHIELD_PULSES+1))
	assert(added)
	report := resolve_action(room, &action)
	assert(report.accepted)
	merge_action_report(pulse, &report)
}
