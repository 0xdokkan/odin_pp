package combatdebug

import "core:encoding/json"
import "core:os"

import game "../game"

PLAYTEST_REPORT_SCHEMA_VERSION :: 1

Playtest_Command_Report :: struct {
	kind:          string,
	attempted:     u64,
	committed:     u64,
	rejected:      u64,
	direct_damage: i64,
	damage_taken:  i64,
	energy_spent:  i64,
	energy_wasted: i64,
	enemy_misses:  u64,
}

Playtest_Card_Report :: struct {
	card:                    game.Card_Id,
	name:                    string,
	attempted:               u64,
	committed:               u64,
	rejected:                u64,
	damage_to_enemies:       i64,
	energy_spent:            i64,
	planned_targets:         u64,
	actual_targets:          u64,
	maximum_planned_targets: u64,
	maximum_actual_targets:  u64,
	poison_applications:     u64,
	movement_cells:          u64,
	trap_triggers_on_enemies: u64,
}

Playtest_Command_Sample_Report :: struct {
	room_index: int,
	kind:       string,
	committed:  bool,
	complete:   bool,

	has_card:              bool,
	card_id:               u32,
	card:                  string,
	card_upgrade_level:    i32,
	card_cost:             i32,
	targeting_valid:       bool,
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
	damage_taken:               i64,
	damage_absorbed_by_player:  i64,
	damage_absorbed_by_enemies: i64,
	energy_spent:               i64,
	energy_restored:            i64,
	energy_wasted:              i64,
	enemy_attack_misses:        u64,

	poison_applications:       u64,
	card_poison_applications:  u64,
	poison_ticks:              u64,
	poison_potential_damage:   i64,
	poison_damage_to_enemies:  i64,
	poison_damage_to_player:   i64,
	poison_damage_absorbed:    i64,
	player_movement_cells:     u64,
	enemy_movement_cells:      u64,
	forced_enemy_movement_cells: u64,
	trap_triggers_on_player:     u64,
	trap_triggers_on_enemies:    u64,
	trap_damage_to_player:       i64,
	trap_damage_to_enemies:      i64,
	card_trap_triggers_on_enemies: u64,
	object_hazard_triggers_on_player:  u64,
	object_hazard_triggers_on_enemies: u64,
	object_hazard_damage_to_player:    i64,
	object_hazard_damage_to_enemies:   i64,
	refocus_retained:             u64,
	refocus_discarded:            u64,
	refocus_exhausted:            u64,
	events_observed:              u64,
	events_dropped:               u64,
}

Playtest_Metrics_Report :: struct {
	commands: [COMMAND_KIND_COUNT]Playtest_Command_Report,
	cards:    [CARD_KIND_COUNT]Playtest_Card_Report,

	pulses:               u64,
	pulse_events:         u64,
	events_observed:      u64,
	events_dropped:       u64,
	integrity_mismatches: u64,

	player_moves:        u64,
	enemy_moves:         u64,
	cards_played:        u64,
	refocuses:           u64,
	enemy_attack_misses: u64,

	direct_player_damage_to_enemies: i64,
	indirect_damage_to_enemies:      i64,
	damage_taken:                    i64,
	damage_absorbed:                 i64,
	energy_spent:                    i64,
	energy_restored:                 i64,
	energy_wasted:                   i64,
	incomplete_commands:             u64,

	poison_applications:          u64,
	poison_ticks:                 u64,
	poison_potential_damage:      i64,
	poison_damage_to_enemies:     i64,
	poison_damage_to_player:      i64,
	poison_damage_absorbed:       i64,
	player_movement_cells:        u64,
	enemy_movement_cells:         u64,
	forced_enemy_movement_cells:  u64,
	trap_triggers_on_player:      u64,
	trap_triggers_on_enemies:     u64,
	trap_damage_to_player:        i64,
	trap_damage_to_enemies:       i64,
	object_hazard_triggers_on_player:  u64,
	object_hazard_triggers_on_enemies: u64,
	object_hazard_damage_to_player:    i64,
	object_hazard_damage_to_enemies:   i64,
	refocus_retained:             u64,
	refocus_discarded:            u64,
	refocus_exhausted:            u64,

	melee_full_option_opportunities: u64,
	melee_bump_choices:              u64,
	melee_strike_choices:            u64,
	melee_heavy_blow_choices:        u64,
	melee_other_choices:             u64,

	maximum_no_damage_streak:      u64,
	maximum_equal_distance_streak: u64,
	has_distance_sample:           bool,
	minimum_enemy_distance:        int,
	maximum_enemy_distance:        int,
}

Playtest_Room_Report :: struct {
	room_index: int,
	node_id:    int,
	node_kind:  string,
	depth:      int,
	room_seed:  u64,

	initial_phase:     string,
	final_phase:       string,
	initial_pulse:     u64,
	final_pulse:       u64,
	initial_health:    i32,
	final_health:      i32,
	initial_energy:    i32,
	final_energy:      i32,
	combat_finished:   bool,
	integrity_complete: bool,
	metrics:            Playtest_Metrics_Report,
}

Playtest_Report :: struct {
	schema_version:     int,
	run_seed:           u64,
	outcome:            string,
	run_completed:      bool,
	integrity_complete: bool,
	rooms:              [dynamic]Playtest_Room_Report,
	commands:           [dynamic]Playtest_Command_Sample_Report,
	metrics:            Playtest_Metrics_Report,
}

playtest_command_kind_name :: proc(kind: Command_Kind) -> string {
	switch kind {
	case .Move:
		return "Move"
	case .Bump_Attack:
		return "Bump_Attack"
	case .Wait:
		return "Wait"
	case .Ability:
		return "Ability"
	case .Play_Card:
		return "Play_Card"
	case .Refocus:
		return "Refocus"
	case .Count:
	}
	return "Unknown"
}

playtest_run_outcome_name :: proc(outcome: Playtest_Run_Outcome) -> string {
	switch outcome {
	case .In_Progress:
		return "In_Progress"
	case .Victory:
		return "Victory"
	case .Defeat:
		return "Defeat"
	case .Abandoned:
		return "Abandoned"
	}
	return "Unknown"
}

playtest_card_name :: proc(card: game.Card_Id) -> string {
	definition, found := game.card_definition_by_id(card)
	if !found {
		return "Unknown"
	}
	return definition.name
}

playtest_command_sample_report :: proc(
	record: ^Playtest_Command_Record,
) -> (result: Playtest_Command_Sample_Report) {
	assert(record != nil)
	sample := &record.sample
	result = {
		room_index = record.room_index,
		kind = playtest_command_kind_name(sample.kind),
		committed = sample.committed,
		complete = sample.complete,
		has_card = sample.has_card,
		card_id = sample.card_id,
		card_upgrade_level = sample.card_upgrade_level,
		card_cost = sample.card_cost,
		targeting_valid = sample.targeting_valid,
		planned_affected_enemies = sample.planned_affected_enemies,
		actual_affected_enemies = sample.actual_affected_enemies,
		planned_movement_cells = sample.planned_movement_cells,
		card_movement_cells = sample.card_movement_cells,
		pulse_delta = sample.pulse_delta,
		health_before = sample.health_before,
		health_after = sample.health_after,
		energy_before = sample.energy_before,
		energy_after = sample.energy_after,
		nearest_distance_before = sample.nearest_distance_before,
		nearest_distance_after = sample.nearest_distance_after,
		player_damage_to_enemies = sample.player_damage_to_enemies,
		card_damage_to_enemies = sample.card_damage_to_enemies,
		indirect_damage_to_enemies = sample.indirect_damage_to_enemies,
		damage_taken = sample.damage_taken,
		damage_absorbed_by_player = sample.damage_absorbed_by_player,
		damage_absorbed_by_enemies = sample.damage_absorbed_by_enemies,
		energy_spent = sample.energy_spent,
		energy_restored = sample.energy_restored,
		energy_wasted = sample.energy_wasted,
		enemy_attack_misses = sample.enemy_attack_misses,
		poison_applications = sample.poison_applications,
		card_poison_applications = sample.card_poison_applications,
		poison_ticks = sample.poison_ticks,
		poison_potential_damage = sample.poison_potential_damage,
		poison_damage_to_enemies = sample.poison_damage_to_enemies,
		poison_damage_to_player = sample.poison_damage_to_player,
		poison_damage_absorbed = sample.poison_damage_absorbed,
		player_movement_cells = sample.player_movement_cells,
		enemy_movement_cells = sample.enemy_movement_cells,
		forced_enemy_movement_cells = sample.forced_enemy_movement_cells,
		trap_triggers_on_player = sample.trap_triggers_on_player,
		trap_triggers_on_enemies = sample.trap_triggers_on_enemies,
		trap_damage_to_player = sample.trap_damage_to_player,
		trap_damage_to_enemies = sample.trap_damage_to_enemies,
		card_trap_triggers_on_enemies = sample.card_trap_triggers_on_enemies,
		object_hazard_triggers_on_player = sample.object_hazard_triggers_on_player,
		object_hazard_triggers_on_enemies = sample.object_hazard_triggers_on_enemies,
		object_hazard_damage_to_player = sample.object_hazard_damage_to_player,
		object_hazard_damage_to_enemies = sample.object_hazard_damage_to_enemies,
		refocus_retained = sample.refocus_retained,
		refocus_discarded = sample.refocus_discarded,
		refocus_exhausted = sample.refocus_exhausted,
		events_observed = sample.events_observed,
		events_dropped = sample.events_dropped,
	}
	if sample.has_card {
		result.card = playtest_card_name(sample.card_definition)
	}
	return
}

combat_metrics_report :: proc(metrics: ^Combat_Metrics) -> (result: Playtest_Metrics_Report) {
	assert(metrics != nil)
	for index in 0..<COMMAND_KIND_COUNT {
		kind := Command_Kind(index)
		result.commands[index] = {
			kind = playtest_command_kind_name(kind),
			attempted = metrics.commands_attempted[index],
			committed = metrics.commands_committed[index],
			rejected = metrics.commands_rejected[index],
			direct_damage = metrics.direct_damage_by_command[index],
			damage_taken = metrics.damage_taken_by_command[index],
			energy_spent = metrics.energy_spent_by_command[index],
			energy_wasted = metrics.energy_wasted_by_command[index],
			enemy_misses = metrics.misses_by_command[index],
		}
	}
	for index in 0..<CARD_KIND_COUNT {
		card := game.Card_Id(index)
		result.cards[index] = {
			card = card,
			name = playtest_card_name(card),
			attempted = metrics.card_attempted[index],
			committed = metrics.card_committed[index],
			rejected = metrics.card_rejected[index],
			damage_to_enemies = metrics.card_damage_to_enemies[index],
			energy_spent = metrics.card_energy_spent[index],
			planned_targets = metrics.card_planned_targets[index],
			actual_targets = metrics.card_actual_targets[index],
			maximum_planned_targets = metrics.card_max_planned_targets[index],
			maximum_actual_targets = metrics.card_max_actual_targets[index],
			poison_applications = metrics.card_poison_applications[index],
			movement_cells = metrics.card_movement_cells[index],
			trap_triggers_on_enemies = metrics.card_trap_triggers_on_enemies[index],
		}
	}

	result.pulses = metrics.pulses
	result.pulse_events = metrics.pulse_events
	result.events_observed = metrics.events_observed
	result.events_dropped = metrics.events_dropped
	result.integrity_mismatches = metrics.integrity_mismatches
	result.player_moves = metrics.player_moves
	result.enemy_moves = metrics.enemy_moves
	result.cards_played = metrics.cards_played
	result.refocuses = metrics.refocuses
	result.enemy_attack_misses = metrics.enemy_attack_misses
	result.direct_player_damage_to_enemies = metrics.direct_player_damage_to_enemies
	result.indirect_damage_to_enemies = metrics.indirect_damage_to_enemies
	result.damage_taken = metrics.damage_taken
	result.damage_absorbed = metrics.damage_absorbed
	result.energy_spent = metrics.energy_spent
	result.energy_restored = metrics.energy_restored
	result.energy_wasted = metrics.energy_wasted
	result.incomplete_commands = metrics.incomplete_commands
	result.poison_applications = metrics.poison_applications
	result.poison_ticks = metrics.poison_ticks
	result.poison_potential_damage = metrics.poison_potential_damage
	result.poison_damage_to_enemies = metrics.poison_damage_to_enemies
	result.poison_damage_to_player = metrics.poison_damage_to_player
	result.poison_damage_absorbed = metrics.poison_damage_absorbed
	result.player_movement_cells = metrics.player_movement_cells
	result.enemy_movement_cells = metrics.enemy_movement_cells
	result.forced_enemy_movement_cells = metrics.forced_enemy_movement_cells
	result.trap_triggers_on_player = metrics.trap_triggers_on_player
	result.trap_triggers_on_enemies = metrics.trap_triggers_on_enemies
	result.trap_damage_to_player = metrics.trap_damage_to_player
	result.trap_damage_to_enemies = metrics.trap_damage_to_enemies
	result.object_hazard_triggers_on_player = metrics.object_hazard_triggers_on_player
	result.object_hazard_triggers_on_enemies = metrics.object_hazard_triggers_on_enemies
	result.object_hazard_damage_to_player = metrics.object_hazard_damage_to_player
	result.object_hazard_damage_to_enemies = metrics.object_hazard_damage_to_enemies
	result.refocus_retained = metrics.refocus_retained
	result.refocus_discarded = metrics.refocus_discarded
	result.refocus_exhausted = metrics.refocus_exhausted
	result.melee_full_option_opportunities = metrics.melee_full_option_opportunities
	result.melee_bump_choices = metrics.melee_bump_choices
	result.melee_strike_choices = metrics.melee_strike_choices
	result.melee_heavy_blow_choices = metrics.melee_heavy_blow_choices
	result.melee_other_choices = metrics.melee_other_choices
	result.maximum_no_damage_streak = metrics.maximum_no_damage_streak
	result.maximum_equal_distance_streak = metrics.maximum_equal_distance_streak
	result.has_distance_sample = metrics.has_distance_sample
	result.minimum_enemy_distance = metrics.minimum_enemy_distance
	result.maximum_enemy_distance = metrics.maximum_enemy_distance
	return
}

build_playtest_report :: proc(session: ^Playtest_Session) -> (report: Playtest_Report, ok: bool) {
	if session == nil || !session.finalized || session.active || session.room_active ||
	   session.outcome == .In_Progress {
		return
	}
	report.schema_version = PLAYTEST_REPORT_SCHEMA_VERSION
	report.run_seed = session.run_seed
	report.outcome = playtest_run_outcome_name(session.outcome)
	report.run_completed = session.outcome == .Victory || session.outcome == .Defeat
	report.integrity_complete = combat_metrics_integrity_complete(&session.aggregate)
	report.rooms = make([dynamic]Playtest_Room_Report, 0, len(session.rooms))
	for &summary in session.rooms {
		append(&report.rooms, Playtest_Room_Report{
			room_index = summary.room_index,
			node_id = summary.metadata.node_id,
			node_kind = game.node_kind_name(summary.metadata.node_kind),
			depth = summary.metadata.depth,
			room_seed = summary.metadata.room_seed,
			initial_phase = game.room_phase_name(summary.initial_phase),
			final_phase = game.room_phase_name(summary.final_phase),
			initial_pulse = summary.initial_pulse,
			final_pulse = summary.final_pulse,
			initial_health = summary.initial_health,
			final_health = summary.final_health,
			initial_energy = summary.initial_energy,
			final_energy = summary.final_energy,
			combat_finished = summary.combat_finished,
			integrity_complete = summary.integrity_complete,
			metrics = combat_metrics_report(&summary.metrics),
		})
	}
	report.commands = make([dynamic]Playtest_Command_Sample_Report, 0, len(session.commands))
	for &record in session.commands {
		append(&report.commands, playtest_command_sample_report(&record))
	}
	report.metrics = combat_metrics_report(&session.aggregate)
	return report, true
}

destroy_playtest_report :: proc(report: ^Playtest_Report) {
	if report == nil {
		return
	}
	delete(report.rooms)
	delete(report.commands)
	report^ = {}
}

marshal_playtest_report :: proc(
	session: ^Playtest_Session,
	pretty: bool = true,
) -> (data: []byte, ok: bool) {
	report, built := build_playtest_report(session)
	if !built {
		return
	}
	defer destroy_playtest_report(&report)
	encoded, marshal_error := json.marshal(report, {
		pretty = pretty,
		use_spaces = pretty,
		spaces = 2,
		use_enum_names = true,
	})
	return encoded, marshal_error == nil
}

write_playtest_report :: proc(
	session: ^Playtest_Session,
	path: string,
	pretty: bool = true,
) -> bool {
	if len(path) == 0 {
		return false
	}
	data, marshalled := marshal_playtest_report(session, pretty)
	if !marshalled {
		return false
	}
	defer delete(data)
	return os.write_entire_file(path, data) == nil
}
