package combatdebug

import game "../game"
import grid "../grid"

Command_Kind :: enum {
	Move,
	Bump_Attack,
	Wait,
	Ability,
	Play_Card,
	Refocus,
	Count,
}

COMMAND_KIND_COUNT :: int(Command_Kind.Count)
NO_ENEMY_DISTANCE :: -1

Command_Snapshot :: struct {
	valid:                  bool,
	pulse_count:            u64,
	health:                 i32,
	energy:                 i32,
	position:               grid.Position,
	nearest_enemy_distance: int,
}

Combat_Metrics :: struct {
	commands_attempted: [COMMAND_KIND_COUNT]u64,
	commands_committed: [COMMAND_KIND_COUNT]u64,
	commands_rejected:  [COMMAND_KIND_COUNT]u64,
	direct_damage_by_command: [COMMAND_KIND_COUNT]i64,
	damage_taken_by_command:  [COMMAND_KIND_COUNT]i64,
	energy_spent_by_command:   [COMMAND_KIND_COUNT]i64,
	energy_wasted_by_command:  [COMMAND_KIND_COUNT]i64,
	misses_by_command:         [COMMAND_KIND_COUNT]u64,
	pulses:             u64,
	pulse_events:       u64,
	events_observed:    u64,
	events_dropped:     u64,
	integrity_mismatches: u64,

	player_moves: u64,
	enemy_moves:  u64,
	cards_played: u64,
	refocuses:    u64,
	enemy_attack_misses: u64,

	direct_player_damage_to_enemies: i64,
	indirect_damage_to_enemies:      i64,
	damage_taken:                    i64,
	damage_absorbed:                 i64,
	energy_spent:                    i64,
	energy_restored:                 i64,
	energy_wasted:                   i64,

	current_no_damage_streak:     u64,
	maximum_no_damage_streak:     u64,
	current_equal_distance_streak: u64,
	maximum_equal_distance_streak: u64,

	has_distance_sample: bool,
	minimum_enemy_distance: int,
	maximum_enemy_distance: int,
}

command_kind_is_valid :: proc(kind: Command_Kind) -> bool {
	return kind >= .Move && kind < .Count
}

manhattan_distance :: proc(a, b: grid.Position) -> int {
	return abs(a.x-b.x)+abs(a.y-b.y)
}

nearest_enemy_distance :: proc(room: ^game.Room, position: grid.Position) -> int {
	if room == nil || len(room.enemies) == 0 {
		return NO_ENEMY_DISTANCE
	}
	result := manhattan_distance(position, room.enemies[0].position)
	for index in 1..<len(room.enemies) {
		result = min(result, manhattan_distance(position, room.enemies[index].position))
	}
	return result
}

capture_command_snapshot :: proc(room: ^game.Room) -> (snapshot: Command_Snapshot, ok: bool) {
	if room == nil || room.player == nil || room.phase != .Combat {
		return
	}
	snapshot = {
		valid = true,
		pulse_count = room.pulse_count,
		health = room.player.health,
		energy = room.player.deck.energy,
		position = room.player.position,
		nearest_enemy_distance = nearest_enemy_distance(room, room.player.position),
	}
	return snapshot, true
}

record_distance_sample :: proc(metrics: ^Combat_Metrics, distance: int) {
	if metrics == nil || distance == NO_ENEMY_DISTANCE {
		return
	}
	if !metrics.has_distance_sample {
		metrics.has_distance_sample = true
		metrics.minimum_enemy_distance = distance
		metrics.maximum_enemy_distance = distance
		return
	}
	metrics.minimum_enemy_distance = min(metrics.minimum_enemy_distance, distance)
	metrics.maximum_enemy_distance = max(metrics.maximum_enemy_distance, distance)
}

observe_event :: proc(metrics: ^Combat_Metrics, event: game.Game_Event) -> (damage_taken: i64) {
	assert(metrics != nil)
	metrics.events_observed += 1
	#partial switch event.kind {
	case .Damaged:
		amount := i64(max(event.amount, 0))
		if event.target.kind == .Player {
			metrics.damage_taken += amount
			damage_taken += amount
		} else if event.target.kind == .Enemy {
			if event.source.kind == .Player {
				metrics.direct_player_damage_to_enemies += amount
			} else {
				metrics.indirect_damage_to_enemies += amount
			}
		}
	case .Damage_Absorbed:
		if event.target.kind == .Player {
			metrics.damage_absorbed += i64(max(event.amount, 0))
		}
	case .Moved:
		switch event.target.kind {
		case .Player:
			metrics.player_moves += 1
		case .Enemy:
			metrics.enemy_moves += 1
		case .Trap, .System:
		}
	case .Attack_Missed:
		if event.source.kind == .Enemy && event.target.kind == .Player {
			metrics.enemy_attack_misses += 1
		}
	case .Card_Played:
		metrics.cards_played += 1
		metrics.energy_spent += i64(max(event.amount, 0))
	case .Hand_Refocused:
		metrics.refocuses += 1
	case .Pulse_Advanced:
		metrics.pulse_events += 1
		metrics.energy_restored += i64(max(event.energy_restored, 0))
		metrics.energy_wasted += i64(max(event.energy_wasted, 0))
	}
	return
}

observe_command :: proc(
	metrics: ^Combat_Metrics,
	snapshot: Command_Snapshot,
	resolved_kind: Command_Kind,
	committed: bool,
	room: ^game.Room,
) -> bool {
	if metrics == nil || room == nil || room.player == nil || !snapshot.valid ||
	   !command_kind_is_valid(resolved_kind) || room.pulse_count < snapshot.pulse_count ||
	   room.recent_events.count < 0 || room.recent_events.count > game.MAX_GAME_EVENTS {
		return false
	}

	kind_index := int(resolved_kind)
	metrics.commands_attempted[kind_index] += 1
	if !committed {
		metrics.commands_rejected[kind_index] += 1
		return true
	}
	metrics.commands_committed[kind_index] += 1
	record_distance_sample(metrics, snapshot.nearest_enemy_distance)

	command_damage_taken: i64
	direct_damage_before := metrics.direct_player_damage_to_enemies
	energy_spent_before := metrics.energy_spent
	energy_wasted_before := metrics.energy_wasted
	misses_before := metrics.enemy_attack_misses
	pulse_events_before := metrics.pulse_events
	for index in 0..<room.recent_events.count {
		command_damage_taken += observe_event(metrics, room.recent_events.events[index])
	}
	dropped_events := u64(max(room.recent_events.dropped_count, 0))
	metrics.events_dropped += dropped_events
	metrics.direct_damage_by_command[kind_index] +=
		metrics.direct_player_damage_to_enemies-direct_damage_before
	metrics.damage_taken_by_command[kind_index] += command_damage_taken
	metrics.energy_spent_by_command[kind_index] += metrics.energy_spent-energy_spent_before
	metrics.energy_wasted_by_command[kind_index] += metrics.energy_wasted-energy_wasted_before
	metrics.misses_by_command[kind_index] += metrics.enemy_attack_misses-misses_before

	pulse_delta := room.pulse_count-snapshot.pulse_count
	metrics.pulses += pulse_delta
	command_pulse_events := metrics.pulse_events-pulse_events_before
	if command_pulse_events > pulse_delta {
		metrics.integrity_mismatches += 1
	} else if command_pulse_events < pulse_delta {
		// Every accepted combat command currently advances zero or one pulse. A
		// missing marker is explainable only when this command also reports drops.
		missing_markers := pulse_delta-command_pulse_events
		if missing_markers > dropped_events {
			metrics.integrity_mismatches += 1
		}
	}

	after_distance := nearest_enemy_distance(room, room.player.position)
	record_distance_sample(metrics, after_distance)
	if pulse_delta > 0 && command_damage_taken == 0 {
		metrics.current_no_damage_streak += pulse_delta
		metrics.maximum_no_damage_streak = max(
			metrics.maximum_no_damage_streak,
			metrics.current_no_damage_streak,
		)
	} else if pulse_delta > 0 {
		metrics.current_no_damage_streak = 0
	}

	if resolved_kind == .Move && pulse_delta == 1 && command_damage_taken == 0 &&
	   snapshot.nearest_enemy_distance != NO_ENEMY_DISTANCE &&
	   after_distance == snapshot.nearest_enemy_distance {
		metrics.current_equal_distance_streak += 1
		metrics.maximum_equal_distance_streak = max(
			metrics.maximum_equal_distance_streak,
			metrics.current_equal_distance_streak,
		)
	} else {
		metrics.current_equal_distance_streak = 0
	}
	return true
}
