package combatdebug

import game "../game"

Playtest_Run_Outcome :: enum {
	In_Progress,
	Victory,
	Defeat,
	Abandoned,
}

Playtest_Room_Metadata :: struct {
	node_id:   int,
	node_kind: game.Node_Kind,
	depth:     int,
	room_seed: u64,
}

Playtest_Room_Summary :: struct {
	room_index: int,
	metadata:   Playtest_Room_Metadata,

	initial_phase:  game.Room_Phase,
	final_phase:    game.Room_Phase,
	initial_pulse:  u64,
	final_pulse:    u64,
	initial_health: i32,
	final_health:   i32,
	initial_energy: i32,
	final_energy:   i32,
	combat_finished: bool,
	integrity_complete: bool,

	metrics: Combat_Metrics,
}

Playtest_Active_Room :: struct {
	metadata: Playtest_Room_Metadata,

	initial_phase:  game.Room_Phase,
	initial_pulse:  u64,
	initial_health: i32,
	initial_energy: i32,
	metrics:        Combat_Metrics,
}

Playtest_Command_Record :: struct {
	room_index: int,
	sample:     Command_Sample,
}

Playtest_Session :: struct {
	active:    bool,
	finalized: bool,
	run_seed:  u64,
	outcome:   Playtest_Run_Outcome,

	room_active: bool,
	active_room: Playtest_Active_Room,
	rooms:       [dynamic]Playtest_Room_Summary,
	commands:    [dynamic]Playtest_Command_Record,
	aggregate:   Combat_Metrics,
}

playtest_room_metadata :: proc(node: ^game.Run_Node) -> (metadata: Playtest_Room_Metadata, ok: bool) {
	if node == nil || int(node.id) < 0 || !game.node_kind_has_room(node.kind) ||
	   node.depth < 0 || node.room_seed == 0 {
		return
	}
	metadata = {
		node_id = int(node.id),
		node_kind = node.kind,
		depth = node.depth,
		room_seed = node.room_seed,
	}
	return metadata, true
}

playtest_room_metadata_is_valid :: proc(metadata: Playtest_Room_Metadata) -> bool {
	return metadata.node_id >= 0 && game.node_kind_has_room(metadata.node_kind) &&
	       metadata.depth >= 0 && metadata.room_seed != 0
}

begin_playtest_session :: proc(session: ^Playtest_Session, run_seed: u64) -> bool {
	if session == nil || session.active || session.finalized || session.rooms != nil {
		return false
	}
	session.active = true
	session.run_seed = run_seed
	session.outcome = .In_Progress
	session.rooms = make([dynamic]Playtest_Room_Summary, 0, 8)
	session.commands = make([dynamic]Playtest_Command_Record, 0, 128)
	return true
}

destroy_playtest_session :: proc(session: ^Playtest_Session) {
	if session == nil {
		return
	}
	delete(session.rooms)
	delete(session.commands)
	session^ = {}
}

begin_playtest_room :: proc(
	session: ^Playtest_Session,
	metadata: Playtest_Room_Metadata,
	room: ^game.Room,
) -> bool {
	if session == nil || !session.active || session.finalized || session.room_active ||
	   !playtest_room_metadata_is_valid(metadata) || room == nil || room.player == nil ||
	   room.phase != .Combat {
		return false
	}
	session.room_active = true
	session.active_room = {
		metadata = metadata,
		initial_phase = room.phase,
		initial_pulse = room.pulse_count,
		initial_health = room.player.health,
		initial_energy = room.player.deck.energy,
	}
	return true
}

playtest_room_metrics :: proc(session: ^Playtest_Session) -> (metrics: ^Combat_Metrics, ok: bool) {
	if session == nil || !session.active || session.finalized || !session.room_active {
		return
	}
	return &session.active_room.metrics, true
}

observe_playtest_sample :: proc(session: ^Playtest_Session, sample: Command_Sample) -> bool {
	if session == nil || !session.active || session.finalized || !session.room_active ||
	   !sample.valid || !command_kind_is_valid(sample.kind) {
		return false
	}
	append(&session.commands, Playtest_Command_Record{
		room_index = len(session.rooms),
		sample = sample,
	})
	return true
}

observe_playtest_command :: proc(
	session: ^Playtest_Session,
	snapshot: Command_Snapshot,
	resolved_kind: Command_Kind,
	committed: bool,
	room: ^game.Room,
) -> bool {
	metrics, ok := playtest_room_metrics(session)
	return ok && observe_command(metrics, snapshot, resolved_kind, committed, room)
}

observe_playtest_command_detailed :: proc(
	session: ^Playtest_Session,
	snapshot: Command_Snapshot,
	resolved_kind: Command_Kind,
	descriptor: Command_Descriptor,
	committed: bool,
	room: ^game.Room,
) -> (sample: Command_Sample, ok: bool) {
	metrics, has_active_room := playtest_room_metrics(session)
	if !has_active_room {
		return
	}
	observed, observation_ok := observe_command_detailed(
		metrics,
		snapshot,
		resolved_kind,
		descriptor,
		committed,
		room,
	)
	if !observation_ok || !observe_playtest_sample(session, observed) {
		return
	}
	return observed, true
}

merge_combat_metrics :: proc(target: ^Combat_Metrics, source: ^Combat_Metrics) {
	assert(target != nil && source != nil)
	for index in 0..<COMMAND_KIND_COUNT {
		target.commands_attempted[index] += source.commands_attempted[index]
		target.commands_committed[index] += source.commands_committed[index]
		target.commands_rejected[index] += source.commands_rejected[index]
		target.direct_damage_by_command[index] += source.direct_damage_by_command[index]
		target.damage_taken_by_command[index] += source.damage_taken_by_command[index]
		target.energy_spent_by_command[index] += source.energy_spent_by_command[index]
		target.energy_wasted_by_command[index] += source.energy_wasted_by_command[index]
		target.misses_by_command[index] += source.misses_by_command[index]
	}
	for index in 0..<CARD_KIND_COUNT {
		target.card_attempted[index] += source.card_attempted[index]
		target.card_committed[index] += source.card_committed[index]
		target.card_rejected[index] += source.card_rejected[index]
		target.card_damage_to_enemies[index] += source.card_damage_to_enemies[index]
		target.card_energy_spent[index] += source.card_energy_spent[index]
		target.card_planned_targets[index] += source.card_planned_targets[index]
		target.card_actual_targets[index] += source.card_actual_targets[index]
		target.card_max_planned_targets[index] = max(
			target.card_max_planned_targets[index],
			source.card_max_planned_targets[index],
		)
		target.card_max_actual_targets[index] = max(
			target.card_max_actual_targets[index],
			source.card_max_actual_targets[index],
		)
		target.card_poison_applications[index] += source.card_poison_applications[index]
		target.card_movement_cells[index] += source.card_movement_cells[index]
		target.card_trap_triggers_on_enemies[index] +=
			source.card_trap_triggers_on_enemies[index]
	}

	target.pulses += source.pulses
	target.pulse_events += source.pulse_events
	target.events_observed += source.events_observed
	target.events_dropped += source.events_dropped
	target.integrity_mismatches += source.integrity_mismatches
	target.player_moves += source.player_moves
	target.enemy_moves += source.enemy_moves
	target.cards_played += source.cards_played
	target.refocuses += source.refocuses
	target.enemy_attack_misses += source.enemy_attack_misses
	target.direct_player_damage_to_enemies += source.direct_player_damage_to_enemies
	target.indirect_damage_to_enemies += source.indirect_damage_to_enemies
	target.damage_taken += source.damage_taken
	target.damage_absorbed += source.damage_absorbed
	target.energy_spent += source.energy_spent
	target.energy_restored += source.energy_restored
	target.energy_wasted += source.energy_wasted
	target.incomplete_commands += source.incomplete_commands
	target.poison_applications += source.poison_applications
	target.poison_ticks += source.poison_ticks
	target.poison_potential_damage += source.poison_potential_damage
	target.poison_damage_to_enemies += source.poison_damage_to_enemies
	target.poison_damage_to_player += source.poison_damage_to_player
	target.poison_damage_absorbed += source.poison_damage_absorbed
	target.player_movement_cells += source.player_movement_cells
	target.enemy_movement_cells += source.enemy_movement_cells
	target.forced_enemy_movement_cells += source.forced_enemy_movement_cells
	target.trap_triggers_on_player += source.trap_triggers_on_player
	target.trap_triggers_on_enemies += source.trap_triggers_on_enemies
	target.trap_damage_to_player += source.trap_damage_to_player
	target.trap_damage_to_enemies += source.trap_damage_to_enemies
	target.object_hazard_triggers_on_player += source.object_hazard_triggers_on_player
	target.object_hazard_triggers_on_enemies += source.object_hazard_triggers_on_enemies
	target.object_hazard_damage_to_player += source.object_hazard_damage_to_player
	target.object_hazard_damage_to_enemies += source.object_hazard_damage_to_enemies
	target.refocus_retained += source.refocus_retained
	target.refocus_discarded += source.refocus_discarded
	target.refocus_exhausted += source.refocus_exhausted
	target.melee_full_option_opportunities += source.melee_full_option_opportunities
	target.melee_bump_choices += source.melee_bump_choices
	target.melee_strike_choices += source.melee_strike_choices
	target.melee_heavy_blow_choices += source.melee_heavy_blow_choices
	target.melee_other_choices += source.melee_other_choices
	target.maximum_no_damage_streak = max(
		target.maximum_no_damage_streak,
		source.maximum_no_damage_streak,
	)
	target.maximum_equal_distance_streak = max(
		target.maximum_equal_distance_streak,
		source.maximum_equal_distance_streak,
	)

	if source.has_distance_sample {
		if !target.has_distance_sample {
			target.has_distance_sample = true
			target.minimum_enemy_distance = source.minimum_enemy_distance
			target.maximum_enemy_distance = source.maximum_enemy_distance
		} else {
			target.minimum_enemy_distance = min(
				target.minimum_enemy_distance,
				source.minimum_enemy_distance,
			)
			target.maximum_enemy_distance = max(
				target.maximum_enemy_distance,
				source.maximum_enemy_distance,
			)
		}
	}
}

combat_metrics_integrity_complete :: proc(metrics: ^Combat_Metrics) -> bool {
	return metrics != nil && metrics.events_dropped == 0 && metrics.integrity_mismatches == 0 &&
	       metrics.incomplete_commands == 0
}

finish_playtest_room :: proc(session: ^Playtest_Session, room: ^game.Room) -> bool {
	if session == nil || !session.active || session.finalized || !session.room_active ||
	   room == nil || room.player == nil || room.pulse_count < session.active_room.initial_pulse {
		return false
	}

	summary := Playtest_Room_Summary{
		room_index = len(session.rooms),
		metadata = session.active_room.metadata,
		initial_phase = session.active_room.initial_phase,
		final_phase = room.phase,
		initial_pulse = session.active_room.initial_pulse,
		final_pulse = room.pulse_count,
		initial_health = session.active_room.initial_health,
		final_health = room.player.health,
		initial_energy = session.active_room.initial_energy,
		final_energy = room.player.deck.energy,
		combat_finished = room.phase != .Combat,
		integrity_complete = combat_metrics_integrity_complete(&session.active_room.metrics),
		metrics = session.active_room.metrics,
	}
	append(&session.rooms, summary)
	merge_combat_metrics(&session.aggregate, &session.active_room.metrics)
	session.room_active = false
	session.active_room = {}
	return true
}

finish_playtest_session :: proc(
	session: ^Playtest_Session,
	outcome: Playtest_Run_Outcome,
	active_room: ^game.Room = nil,
) -> bool {
	if session == nil || !session.active || session.finalized || outcome == .In_Progress {
		return false
	}
	if session.room_active && (active_room == nil || !finish_playtest_room(session, active_room)) {
		return false
	}
	session.active = false
	session.finalized = true
	session.outcome = outcome
	return true
}
