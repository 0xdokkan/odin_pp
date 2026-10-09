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
CARD_KIND_COUNT :: int(game.Card_Id.Count)
NO_ENEMY_DISTANCE :: -1
MAX_OBSERVED_ENTITIES :: game.MAX_ENEMIES_PER_ROOM+1

Command_Descriptor :: struct {
	valid:                       bool,
	has_card:                    bool,
	card_id:                     u32,
	card_definition:             game.Card_Id,
	card_upgrade_level:          i32,
	card_cost:                   i32,
	targeting_valid:             bool,
	planned_affected_enemies:    int,
	planned_movement_cells:      int,
}

Command_Snapshot :: struct {
	valid:                  bool,
	pulse_count:            u64,
	health:                 i32,
	energy:                 i32,
	position:               grid.Position,
	nearest_enemy_distance: int,
	has_adjacent_enemy:     bool,
	strike_available:       bool,
	heavy_blow_available:   bool,
}

Command_Sample :: struct {
	valid:                    bool,
	kind:                     Command_Kind,
	committed:                bool,
	complete:                 bool,
	has_card:                 bool,
	card_id:                  u32,
	card_definition:          game.Card_Id,
	card_upgrade_level:       i32,
	card_cost:                i32,
	targeting_valid:          bool,
	planned_affected_enemies: int,
	actual_affected_enemies:  int,
	planned_movement_cells:   int,
	card_movement_cells:      int,
	pulse_delta:              u64,
	health_before:            i32,
	health_after:             i32,
	energy_before:            i32,
	energy_after:             i32,
	nearest_distance_before:  int,
	nearest_distance_after:   int,
	player_damage_to_enemies: i64,
	card_damage_to_enemies:   i64,
	indirect_damage_to_enemies: i64,
	damage_taken:             i64,
	damage_absorbed_by_player: i64,
	damage_absorbed_by_enemies: i64,
	energy_spent:             i64,
	energy_restored:          i64,
	energy_wasted:            i64,
	enemy_attack_misses:      u64,
	poison_applications:      u64,
	card_poison_applications: u64,
	poison_ticks:             u64,
	poison_potential_damage:  i64,
	poison_damage_to_enemies: i64,
	poison_damage_to_player:  i64,
	poison_damage_absorbed:   i64,
	player_movement_cells:    u64,
	enemy_movement_cells:     u64,
	forced_enemy_movement_cells: u64,
	trap_triggers_on_player:  u64,
	trap_triggers_on_enemies: u64,
	trap_damage_to_player:    i64,
	trap_damage_to_enemies:   i64,
	card_trap_triggers_on_enemies: u64,
	object_hazard_triggers_on_player:  u64,
	object_hazard_triggers_on_enemies: u64,
	object_hazard_damage_to_player:    i64,
	object_hazard_damage_to_enemies:   i64,
	refocus_retained:         u64,
	refocus_discarded:        u64,
	refocus_exhausted:        u64,
	events_observed:          u64,
	events_dropped:           u64,
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
	incomplete_commands:             u64,

	card_attempted:                  [CARD_KIND_COUNT]u64,
	card_committed:                  [CARD_KIND_COUNT]u64,
	card_rejected:                   [CARD_KIND_COUNT]u64,
	card_damage_to_enemies:          [CARD_KIND_COUNT]i64,
	card_energy_spent:               [CARD_KIND_COUNT]i64,
	card_planned_targets:            [CARD_KIND_COUNT]u64,
	card_actual_targets:             [CARD_KIND_COUNT]u64,
	card_max_planned_targets:        [CARD_KIND_COUNT]u64,
	card_max_actual_targets:         [CARD_KIND_COUNT]u64,
	card_poison_applications:        [CARD_KIND_COUNT]u64,
	card_movement_cells:             [CARD_KIND_COUNT]u64,
	card_trap_triggers_on_enemies:   [CARD_KIND_COUNT]u64,

	poison_applications:             u64,
	poison_ticks:                    u64,
	poison_potential_damage:         i64,
	poison_damage_to_enemies:        i64,
	poison_damage_to_player:         i64,
	poison_damage_absorbed:          i64,
	player_movement_cells:           u64,
	enemy_movement_cells:            u64,
	forced_enemy_movement_cells:     u64,
	trap_triggers_on_player:         u64,
	trap_triggers_on_enemies:        u64,
	trap_damage_to_player:           i64,
	trap_damage_to_enemies:          i64,
	object_hazard_triggers_on_player:  u64,
	object_hazard_triggers_on_enemies: u64,
	object_hazard_damage_to_player:    i64,
	object_hazard_damage_to_enemies:   i64,
	refocus_retained:                u64,
	refocus_discarded:               u64,
	refocus_exhausted:               u64,

	melee_full_option_opportunities: u64,
	melee_bump_choices:              u64,
	melee_strike_choices:            u64,
	melee_heavy_blow_choices:        u64,
	melee_other_choices:             u64,

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

has_adjacent_enemy :: proc(room: ^game.Room, position: grid.Position) -> bool {
	if room == nil {
		return false
	}
	for enemy in room.enemies {
		if manhattan_distance(position, enemy.position) == 1 {
			return true
		}
	}
	return false
}

affordable_card_is_in_hand :: proc(room: ^game.Room, definition_id: game.Card_Id) -> bool {
	if room == nil || room.player == nil {
		return false
	}
	deck := &room.player.deck
	definition, found := game.card_definition_by_id(definition_id)
	if !found || deck.energy < definition.cost {
		return false
	}
	for index in 0..<deck.hand_count {
		if deck.hand[index].definition_id == definition_id {
			return true
		}
	}
	return false
}

capture_card_descriptor :: proc(
	room: ^game.Room,
	card_id: u32,
	target: game.Target,
) -> (descriptor: Command_Descriptor, ok: bool) {
	if room == nil || room.player == nil || room.phase != .Combat {
		return
	}
	hand_index, found := game.hand_card_index_by_id(&room.player.deck, card_id)
	if !found {
		return
	}
	card := room.player.deck.hand[hand_index]
	definition, definition_found := game.card_definition_by_id(card.definition_id, game.tactical_enabled(room))
	if !definition_found {
		return
	}
	descriptor = {
		valid = true,
		has_card = true,
		card_id = card.id,
		card_definition = card.definition_id,
		card_upgrade_level = card.upgrade_level,
		card_cost = definition.cost,
	}

	request, has_request := game.card_target_request_from_target(room, definition, target)
	if !has_request {
		return descriptor, true
	}
	evaluation := game.evaluate_card_targeting(room, card, request)
	if evaluation.error != .None {
		return descriptor, true
	}
	descriptor.targeting_valid = true
	for index in 0..<definition.effect_count {
		planned_targets := 0
		switch definition.effects[index].target {
		case .Chosen_Entity:
			if target.kind == .Entity && target.entity.kind == .Enemy {
				planned_targets = 1
			}
		case .Each_Enemy:
			for enemy in room.enemies { if game.tactical_card_enemy_in_area(room, card.definition_id, enemy.position) { planned_targets += 1 } }
		case .Each_Affected_Enemy:
			planned_targets = evaluation.query.enemy_count
		case .Player, .Count:
		}
		descriptor.planned_affected_enemies = max(
			descriptor.planned_affected_enemies,
			planned_targets,
		)
	}
	if evaluation.has_movement && game.movement_query_is_clear(&evaluation.movement) {
		descriptor.planned_movement_cells = evaluation.movement.count
	}
	return descriptor, true
}

capture_command_snapshot :: proc(room: ^game.Room) -> (snapshot: Command_Snapshot, ok: bool) {
	if room == nil || room.player == nil || room.phase != .Combat {
		return
	}
	adjacent_enemy := has_adjacent_enemy(room, room.player.position)
	snapshot = {
		valid = true,
		pulse_count = room.pulse_count,
		health = room.player.health,
		energy = room.player.deck.energy,
		position = room.player.position,
		nearest_enemy_distance = nearest_enemy_distance(room, room.player.position),
		has_adjacent_enemy = adjacent_enemy,
		strike_available = adjacent_enemy && affordable_card_is_in_hand(room, .Strike),
		heavy_blow_available = adjacent_enemy && affordable_card_is_in_hand(room, .Heavy_Blow),
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
		case .Trap, .Object, .System:
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

add_observed_entity :: proc(
	entities: ^[MAX_OBSERVED_ENTITIES]game.Entity_Ref,
	count: ^int,
	entity: game.Entity_Ref,
) -> bool {
	if entities == nil || count == nil || count^ < 0 || count^ >= len(entities^) {
		return false
	}
	for index in 0..<count^ {
		if entities[index] == entity {
			return false
		}
	}
	entities[count^] = entity
	count^ += 1
	return true
}

observe_command_detailed :: proc(
	metrics: ^Combat_Metrics,
	snapshot: Command_Snapshot,
	resolved_kind: Command_Kind,
	descriptor: Command_Descriptor,
	committed: bool,
	room: ^game.Room,
) -> (sample: Command_Sample, ok: bool) {
	if metrics == nil || room == nil || room.player == nil || !snapshot.valid ||
	   !command_kind_is_valid(resolved_kind) || room.pulse_count < snapshot.pulse_count ||
	   room.recent_events.count < 0 || room.recent_events.count > game.MAX_GAME_EVENTS {
		return
	}
	sample = {
		valid = true,
		kind = resolved_kind,
		committed = committed,
		complete = true,
		has_card = descriptor.has_card,
		card_id = descriptor.card_id,
		card_definition = descriptor.card_definition,
		card_upgrade_level = descriptor.card_upgrade_level,
		card_cost = descriptor.card_cost,
		targeting_valid = descriptor.targeting_valid,
		planned_affected_enemies = descriptor.planned_affected_enemies,
		planned_movement_cells = descriptor.planned_movement_cells,
		health_before = snapshot.health,
		health_after = room.player.health,
		energy_before = snapshot.energy,
		energy_after = room.player.deck.energy,
		nearest_distance_before = snapshot.nearest_enemy_distance,
		nearest_distance_after = nearest_enemy_distance(room, room.player.position),
	}

	kind_index := int(resolved_kind)
	metrics.commands_attempted[kind_index] += 1
	if !committed {
		metrics.commands_rejected[kind_index] += 1
		if sample.has_card {
			card_index := int(sample.card_definition)
			if card_index >= 0 && card_index < CARD_KIND_COUNT {
				metrics.card_attempted[card_index] += 1
				metrics.card_rejected[card_index] += 1
			}
		}
		return sample, true
	}
	metrics.commands_committed[kind_index] += 1
	record_distance_sample(metrics, snapshot.nearest_enemy_distance)

	command_damage_taken: i64
	direct_damage_before := metrics.direct_player_damage_to_enemies
	energy_spent_before := metrics.energy_spent
	energy_wasted_before := metrics.energy_wasted
	misses_before := metrics.enemy_attack_misses
	pulse_events_before := metrics.pulse_events
	integrity_mismatches_before := metrics.integrity_mismatches
	card_scope := false
	card_targets: [MAX_OBSERVED_ENTITIES]game.Entity_Ref
	card_target_count := 0
	poison_targets: [MAX_OBSERVED_ENTITIES]game.Entity_Ref
	poison_target_count := 0
	for index in 0..<room.recent_events.count {
		event := room.recent_events.events[index]
		if event.kind == .Card_Played && resolved_kind == .Play_Card &&
		   (!sample.has_card || event.card_id == sample.card_id) {
			if !sample.has_card {
				sample.has_card = true
				sample.card_id = event.card_id
				sample.card_definition = event.card_definition
				sample.card_upgrade_level = event.card_upgrade_level
				sample.card_cost = event.amount
			}
			card_scope = true
		}

		command_damage_taken += observe_event(metrics, event)
		sample.events_observed += 1
		#partial switch event.kind {
		case .Damaged:
			amount := i64(max(event.amount, 0))
			if event.target.kind == .Player {
				sample.damage_taken += amount
			} else if event.target.kind == .Enemy {
				if event.source.kind == .Player {
					sample.player_damage_to_enemies += amount
					if card_scope {
						sample.card_damage_to_enemies += amount
					}
				} else {
					sample.indirect_damage_to_enemies += amount
				}
			}
			if event.source.kind == .Trap {
				if event.target.kind == .Player {
					sample.trap_damage_to_player += amount
				} else if event.target.kind == .Enemy {
					sample.trap_damage_to_enemies += amount
				}
			}
			if event.source.kind == .Object {
				if event.target.kind == .Player {
					sample.object_hazard_damage_to_player += amount
				} else if event.target.kind == .Enemy {
					sample.object_hazard_damage_to_enemies += amount
				}
			}
			if event.has_status_cause && event.status_cause == .Poison {
				add_observed_entity(&poison_targets, &poison_target_count, event.target)
				sample.poison_potential_damage += amount
				if event.target.kind == .Player {
					sample.poison_damage_to_player += amount
				} else if event.target.kind == .Enemy {
					sample.poison_damage_to_enemies += amount
				}
			}
		case .Damage_Absorbed:
			amount := i64(max(event.amount, 0))
			if event.target.kind == .Player {
				sample.damage_absorbed_by_player += amount
			} else if event.target.kind == .Enemy {
				sample.damage_absorbed_by_enemies += amount
			}
			if event.has_status_cause && event.status_cause == .Poison {
				add_observed_entity(&poison_targets, &poison_target_count, event.target)
				sample.poison_potential_damage += amount
				sample.poison_damage_absorbed += amount
			}
		case .Card_Played:
			sample.energy_spent += i64(max(event.amount, 0))
		case .Pulse_Advanced:
			sample.energy_restored += i64(max(event.energy_restored, 0))
			sample.energy_wasted += i64(max(event.energy_wasted, 0))
		case .Attack_Missed:
			if event.source.kind == .Enemy && event.target.kind == .Player {
				sample.enemy_attack_misses += 1
			}
		case .Status_Applied:
			if event.status == .Poison {
				sample.poison_applications += 1
				if card_scope {
					sample.card_poison_applications += 1
				}
			}
		case .Movement_Step, .Moved:
			if event.target.kind == .Player {
				sample.player_movement_cells += 1
			} else if event.target.kind == .Enemy {
				sample.enemy_movement_cells += 1
				if event.source.kind == .Player {
					sample.forced_enemy_movement_cells += 1
				}
			}
			if card_scope && event.source.kind == .Player {
				sample.card_movement_cells += 1
			}
		case .Trap_Triggered:
			if event.target.kind == .Player {
				sample.trap_triggers_on_player += 1
			} else if event.target.kind == .Enemy {
				sample.trap_triggers_on_enemies += 1
				if card_scope {
					sample.card_trap_triggers_on_enemies += 1
				}
			}
		case .Hazard_Triggered:
			if event.source.kind == .Object {
				if event.target.kind == .Player {
					sample.object_hazard_triggers_on_player += 1
				} else if event.target.kind == .Enemy {
					sample.object_hazard_triggers_on_enemies += 1
				}
			}
		case .Card_Refocused:
			switch event.to_card_zone {
			case .Hand:
				sample.refocus_retained += 1
			case .Discard:
				sample.refocus_discarded += 1
			case .Exhaust:
				sample.refocus_exhausted += 1
			case .Draw, .Resolving, .Count:
			}
		}
		if card_scope && event.target.kind == .Enemy {
			add_observed_entity(&card_targets, &card_target_count, event.target)
		}
		if card_scope && event.kind == .Card_Moved && event.card_id == sample.card_id &&
		   event.from_card_zone == .Resolving {
			card_scope = false
		}
	}
	sample.actual_affected_enemies = card_target_count
	sample.poison_ticks = u64(poison_target_count)
	dropped_events := u64(max(room.recent_events.dropped_count, 0))
	sample.events_dropped = dropped_events
	if dropped_events > 0 {
		sample.complete = false
	}
	metrics.events_dropped += dropped_events
	metrics.direct_damage_by_command[kind_index] +=
		metrics.direct_player_damage_to_enemies-direct_damage_before
	metrics.damage_taken_by_command[kind_index] += command_damage_taken
	metrics.energy_spent_by_command[kind_index] += metrics.energy_spent-energy_spent_before
	metrics.energy_wasted_by_command[kind_index] += metrics.energy_wasted-energy_wasted_before
	metrics.misses_by_command[kind_index] += metrics.enemy_attack_misses-misses_before

	pulse_delta := room.pulse_count-snapshot.pulse_count
	sample.pulse_delta = pulse_delta
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
	if metrics.integrity_mismatches > integrity_mismatches_before {
		sample.complete = false
	}
	if !sample.complete {
		metrics.incomplete_commands += 1
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

	metrics.poison_applications += sample.poison_applications
	metrics.poison_ticks += sample.poison_ticks
	metrics.poison_potential_damage += sample.poison_potential_damage
	metrics.poison_damage_to_enemies += sample.poison_damage_to_enemies
	metrics.poison_damage_to_player += sample.poison_damage_to_player
	metrics.poison_damage_absorbed += sample.poison_damage_absorbed
	metrics.player_movement_cells += sample.player_movement_cells
	metrics.enemy_movement_cells += sample.enemy_movement_cells
	metrics.forced_enemy_movement_cells += sample.forced_enemy_movement_cells
	metrics.trap_triggers_on_player += sample.trap_triggers_on_player
	metrics.trap_triggers_on_enemies += sample.trap_triggers_on_enemies
	metrics.trap_damage_to_player += sample.trap_damage_to_player
	metrics.trap_damage_to_enemies += sample.trap_damage_to_enemies
	metrics.object_hazard_triggers_on_player += sample.object_hazard_triggers_on_player
	metrics.object_hazard_triggers_on_enemies += sample.object_hazard_triggers_on_enemies
	metrics.object_hazard_damage_to_player += sample.object_hazard_damage_to_player
	metrics.object_hazard_damage_to_enemies += sample.object_hazard_damage_to_enemies
	metrics.refocus_retained += sample.refocus_retained
	metrics.refocus_discarded += sample.refocus_discarded
	metrics.refocus_exhausted += sample.refocus_exhausted

	if sample.has_card {
		card_index := int(sample.card_definition)
		if card_index >= 0 && card_index < CARD_KIND_COUNT {
			planned_targets := u64(max(sample.planned_affected_enemies, 0))
			actual_targets := u64(max(sample.actual_affected_enemies, 0))
			metrics.card_attempted[card_index] += 1
			metrics.card_committed[card_index] += 1
			metrics.card_damage_to_enemies[card_index] += sample.card_damage_to_enemies
			metrics.card_energy_spent[card_index] += sample.energy_spent
			metrics.card_planned_targets[card_index] += planned_targets
			metrics.card_actual_targets[card_index] += actual_targets
			metrics.card_max_planned_targets[card_index] = max(
				metrics.card_max_planned_targets[card_index],
				planned_targets,
			)
			metrics.card_max_actual_targets[card_index] = max(
				metrics.card_max_actual_targets[card_index],
				actual_targets,
			)
			metrics.card_poison_applications[card_index] += sample.card_poison_applications
			metrics.card_movement_cells[card_index] += u64(max(sample.card_movement_cells, 0))
			metrics.card_trap_triggers_on_enemies[card_index] +=
				sample.card_trap_triggers_on_enemies
		}
	}

	if snapshot.has_adjacent_enemy && snapshot.strike_available &&
	   snapshot.heavy_blow_available {
		metrics.melee_full_option_opportunities += 1
		if resolved_kind == .Bump_Attack {
			metrics.melee_bump_choices += 1
		} else if resolved_kind == .Play_Card && sample.has_card &&
		          sample.card_definition == .Strike {
			metrics.melee_strike_choices += 1
		} else if resolved_kind == .Play_Card && sample.has_card &&
		          sample.card_definition == .Heavy_Blow {
			metrics.melee_heavy_blow_choices += 1
		} else {
			metrics.melee_other_choices += 1
		}
	}
	return sample, true
}

observe_command :: proc(
	metrics: ^Combat_Metrics,
	snapshot: Command_Snapshot,
	resolved_kind: Command_Kind,
	committed: bool,
	room: ^game.Room,
) -> bool {
	_, ok := observe_command_detailed(metrics, snapshot, resolved_kind, {}, committed, room)
	return ok
}
