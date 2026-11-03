package game

import grid "../engine/grid"
import level "../level"

// THE ARCHERS' REAL ARROWS (docs/piano-succo.md, Fase 3). On its shot's beat an
// archer looses an arrow from its cell along the line it aimed; the arrow flies
// ENEMY_ARROW_SPEED cells a world second, at most ENEMY_ARROW_RANGE cells, and
// strikes the first thing on its way as it enters that cell: a wall or a
// cover stops it, the player takes the archer's blow, another foe takes its
// damage. No defence of the keys answers it: one steps out of its line.
// RIFLESSO, the Stegosauro and the sword's guard still turn it back as it
// lands (the user's choices of 2026-11-01, behind the eyes too; the Spine
// have nothing against it).
//
// The arrows fly on the world's seconds (tactical_advance_clock): a shadow, a
// cast, a defence or a die hold them as they hold the world. Their seconds are
// flown out by world commands (resolve_enemy_flights, as the Pinball's roll)
// and at every beat's start, before the beat: no beat ever passes an arrow.
// The bombers' bombs (enemy_bomb.odin) fly on the same clock.

ENEMY_ARROW_SPEED :: f32(8)
ENEMY_ARROW_RANGE :: 8
MAX_ENEMY_ARROWS :: 8
@(private = "file")
ENEMY_ARROW_EPSILON :: f32(0.00001)
// A flight's batch stops short of a full log.
@(private = "file")
ENEMY_ARROW_EVENT_HEADROOM :: 24

// Small: the room keeps them inline, under its stack budget (event_test.odin).
Enemy_Arrow :: struct {
	// Its archer's cell as it loosed (x, y, layer) and one cell along its line.
	origin: [3]i16,
	step: [2]i8,
	// Cells entered so far.
	reached: u8,
	// The archer that loosed it.
	shooter: u32,
	damage: i32,
	// Cells flown from the origin's centre.
	flown: f32,
}

Enemy_Arrows :: struct {
	items: [MAX_ENEMY_ARROWS]Enemy_Arrow,
	count: i32,
	// World seconds not flown out yet.
	pending: f32,
}

// An arrow's origin and step as the board's positions.
enemy_arrow_origin :: proc(arrow: Enemy_Arrow) -> grid.Position {
	return {x = int(arrow.origin.x), y = int(arrow.origin.y), layer = i8(arrow.origin.z)}
}

enemy_arrow_step :: proc(arrow: Enemy_Arrow) -> grid.Position {
	return {x = int(arrow.step.x), y = int(arrow.step.y)}
}

// The arrow of a line from `origin` along `step` (a course to read, no flight).
enemy_arrow_line :: proc(origin, step: grid.Position) -> Enemy_Arrow {
	return {origin = {i16(origin.x), i16(origin.y), i16(origin.layer)}, step = {i8(step.x), i8(step.y)}}
}

// The `k`th cell of an arrow's line (0: its origin).
enemy_arrow_cell :: proc(arrow: Enemy_Arrow, k: int) -> grid.Position {
	return grid.offset(enemy_arrow_origin(arrow), int(arrow.step.x)*k, int(arrow.step.y)*k)
}

// Where an arrow stands now, in cells from its origin's centre, its seconds
// still waiting included (the board draws it there).
enemy_arrow_distance :: proc(room: ^Room, arrow: Enemy_Arrow) -> f32 {
	if room == nil { return arrow.flown }
	return min(arrow.flown+room.arrows.pending*ENEMY_ARROW_SPEED, f32(ENEMY_ARROW_RANGE))
}

// Whether a cell stops an arrow flying from `origin`: off the board, a wall,
// a cover, the rock between layers.
@(private = "file")
enemy_arrow_blocked :: proc(room: ^Room, origin, cell: grid.Position) -> bool {
	if room.level_data == nil || !level.layer_contains(room.level_data, cell) || cell_blocks_line_of_sight(room, cell) { return true }
	if room_has_layers(room) {
		if _, blocked := room_line_blocker(room, origin, cell, true); blocked { return true }
	}
	return false
}

// Whether an arrow from `origin` that landed in `cell` with no one there
// struck what stops it (it sticks in that wall or cover), not the floor at
// its range's end (it falls there).
enemy_arrow_struck_wall :: proc(room: ^Room, origin, cell: grid.Position) -> bool {
	return room != nil && enemy_arrow_blocked(room, origin, cell)
}

// The cell where an arrow loosed along `step` from `origin` would end: the
// first that stops it, or its range's last.
enemy_arrow_course_end :: proc(room: ^Room, origin, step: grid.Position) -> (cell: grid.Position, cells: int) {
	arrow := enemy_arrow_line(origin, step)
	for k in 1..=ENEMY_ARROW_RANGE {
		cell = enemy_arrow_cell(arrow, k)
		cells = k
		if enemy_arrow_blocked(room, origin, cell) { return }
	}
	return
}

// Whether `enemy`'s attack flies as a real arrow: an archer's, at a foe (not
// at a barrel).
enemy_attack_is_arrow :: proc(enemy: ^Enemy, intent: ^Enemy_Intent) -> bool {
	return enemy != nil && intent != nil && enemy.archetype == .Archer && intent.kind == .Attack && intent.target_object == 0
}

// The archer's shot on its beat: the arrow leaves its cell along the line it
// aimed. False when it cannot (no line, no room for another arrow).
@(private)
loose_enemy_arrow :: proc(room: ^Room, enemy: ^Enemy, intent: ^Enemy_Intent, pulse: ^Pulse_Report) -> bool {
	if room == nil || enemy == nil || intent == nil || pulse == nil || intent.threatened_cell_count <= 0 ||
	   room.arrows.count >= MAX_ENEMY_ARROWS { return false }
	aim := intent.threatened_cells[0]
	step, _, aligned := orthogonal_step_and_distance(enemy.position, aim)
	if !aligned || step == {} { return false }
	arrow := enemy_arrow_line(enemy.position, step)
	arrow.shooter, arrow.damage = enemy.id, intent.damage
	room.arrows.items[room.arrows.count] = arrow
	room.arrows.count += 1
	end, _ := enemy_arrow_course_end(room, enemy.position, step)
	record_event(&pulse.events, {kind = .Arrow_Loosed, source = enemy_entity(enemy.id), target = PLAYER_ENTITY,
		from_position = enemy.position, to_position = end, amount = intent.damage})
	return true
}

// The world's seconds reach the arrows and the bombs in flight.
@(private)
tactical_flight_tick :: proc(room: ^Room, seconds: f32) {
	if room == nil || !(seconds > 0) { return }
	if room.arrows.count > 0 { room.arrows.pending += seconds }
	if room.bombs.count > 0 { room.bombs.pending += seconds }
	if room.player != nil && room.player.tactical.spiders.count > 0 { room.player.tactical.spiders.pending += seconds }
	if room.player != nil { room.player.tactical.queen_wait = max(0, room.player.tactical.queen_wait-seconds) }
}

// Seconds wait to be flown and nothing holds the world: the controller
// commits the flight (resolve_enemy_flights) as a world command.
tactical_flights_due :: proc(room: ^Room) -> bool {
	if room == nil || room.player == nil || room.phase != .Combat || room.tactical_pulse.pending || room.qte.kind != .None ||
	   room.player.tactical.cast_remaining > 0 { return false }
	spiders := &room.player.tactical.spiders
	return (room.arrows.count > 0 && room.arrows.pending > ENEMY_ARROW_EPSILON) ||
	       (room.bombs.count > 0 && room.bombs.pending > ENEMY_ARROW_EPSILON) ||
	       (spiders.count > 0 && spiders.pending > ENEMY_ARROW_EPSILON) || queen_is_due(room)
}

// The seconds waiting, flown out into room.recent_events: every arrow's and
// bomb's landing, in order.
resolve_enemy_flights :: proc(room: ^Room) -> bool {
	if !tactical_flights_due(room) { return false }
	clear_event_log(room.recent_events)
	pulse: Pulse_Report
	fly_enemy_flights(room, &pulse)
	append_event_log(room.recent_events, &pulse.events)
	collect_loot_in_magnet_range(room)
	if room.phase != .Combat {
		sync_deck_with_room_phase(room)
		tactical_end_combat(room)
	}
	return true
}

// The arrows and the bombs fly their seconds waiting into `pulse` (a world
// command's, or a beat's before the beat: `beat` lands every bomb).
@(private)
fly_enemy_flights :: proc(room: ^Room, pulse: ^Pulse_Report, beat := false) {
	fly_enemy_arrows(room, pulse)
	if room.phase == .Combat { fly_enemy_bombs(room, pulse, beat) }
	if room.phase == .Combat { run_spiderlings(room, pulse) }
	if room.phase == .Combat { queen_strike(room, pulse) }
}

@(private)
fly_enemy_arrows :: proc(room: ^Room, pulse: ^Pulse_Report) {
	a := &room.arrows
	if a.count == 0 { a.pending = 0; return }
	distance := a.pending*ENEMY_ARROW_SPEED
	a.pending = 0
	for index := i32(0); index < a.count; {
		arrow := &a.items[index]
		arrow.flown += distance
		stopped := false
		for !stopped && int(arrow.reached) < ENEMY_ARROW_RANGE && f32(arrow.reached)+0.5 <= arrow.flown &&
		    pulse.events.count <= MAX_GAME_EVENTS-ENEMY_ARROW_EVENT_HEADROOM {
			arrow.reached += 1
			stopped = enemy_arrow_enters(room, arrow^, enemy_arrow_cell(arrow^, int(arrow.reached)), pulse)
			if room.phase != .Combat { return }
		}
		// At its range's end it falls.
		if !stopped && int(arrow.reached) >= ENEMY_ARROW_RANGE {
			record_event(&pulse.events, {kind = .Arrow_Landed, source = enemy_entity(arrow.shooter), target = SYSTEM_ENTITY,
				from_position = enemy_arrow_origin(arrow^), to_position = enemy_arrow_cell(arrow^, int(arrow.reached))})
			stopped = true
		}
		if stopped {
			a.items[index] = a.items[a.count-1]
			a.count -= 1
			continue
		}
		index += 1
	}
}

// An arrow entering `cell`: whether it stops there.
@(private = "file")
enemy_arrow_enters :: proc(room: ^Room, arrow: Enemy_Arrow, cell: grid.Position, pulse: ^Pulse_Report) -> bool {
	source := enemy_entity(arrow.shooter)
	origin := enemy_arrow_origin(arrow)
	// An arrow passing over a nest takes its seconds, and flies on.
	spider_nests_under_blow(room, {cell}, source, &pulse.events)
	if enemy_arrow_blocked(room, origin, cell) {
		record_event(&pulse.events, {kind = .Arrow_Landed, source = source, target = SYSTEM_ENTITY, from_position = origin, to_position = cell})
		return true
	}
	blow := Enemy_Intent{kind = .Attack, origin = origin, destination = origin, damage = arrow.damage,
		threatened_cell_count = 1, planned_pulse = room.pulse_count}
	blow.threatened_cells[0] = cell
	if !tactical_player_intangible(room) && enemy_blow_reaches_player(room, &blow, true) {
		record_event(&pulse.events, {kind = .Arrow_Landed, source = source, target = PLAYER_ENTITY, from_position = origin, to_position = cell})
		enemy_arrow_strikes_player(room, arrow, &blow, pulse)
		return true
	}
	if foe_index, found := enemy_index_at(room, cell); found && !enemy_is_out_of_play(room, room.enemies[foe_index].id) {
		foe := enemy_entity(room.enemies[foe_index].id)
		record_event(&pulse.events, {kind = .Arrow_Landed, source = source, target = foe, from_position = origin, to_position = cell})
		if _, alive := enemy_index_by_id(room, arrow.shooter); !alive { source = SYSTEM_ENTITY }
		action := make_action(.Trigger, source, entity_target(foe), .Entity)
		if add_effect(&action, damage_effect(foe, arrow.damage)) {
			report := resolve_action(room, &action)
			merge_action_report(pulse, &report)
		}
		return true
	}
	return false
}

// The archer's blow, landing with its arrow: the sword's guard, RIFLESSO or
// the Stegosauro turn it back, else it wounds (and the biome's status).
@(private = "file")
enemy_arrow_strikes_player :: proc(room: ^Room, arrow: Enemy_Arrow, blow: ^Enemy_Intent, pulse: ^Pulse_Report) {
	source := enemy_entity(arrow.shooter)
	shooter_index, alive := enemy_index_by_id(room, arrow.shooter)
	if alive {
		// The guard faces where the arrow came from, not where its archer went.
		shooter := room.enemies[shooter_index]
		shooter.position = enemy_arrow_origin(arrow)
		if sword_parry_blow(room, &shooter, blow, true, pulse) { return }
		if deflect_enemy_blow(room, source, shooter.position, blow, true, pulse) { return }
	} else {
		source = SYSTEM_ENTITY
	}
	action := make_action(.Attack if alive else .Trigger, source, entity_target(PLAYER_ENTITY), .Opponent if alive else .Entity)
	added := add_effect(&action, damage_effect(PLAYER_ENTITY, arrow.damage))
	assert(added)
	report := resolve_action(room, &action)
	merge_action_report(pulse, &report)
	if alive && room.player.tactical.config.expedition && report.damage_dealt > 0 && room.player.health > 0 {
		biome := room.player.tactical.config.expedition_biome
		if biome == 2 || biome == 7 {
			status_action := make_action(.Trigger, source, entity_target(PLAYER_ENTITY), .Opponent)
			add_effect(&status_action, apply_status_effect(PLAYER_ENTITY, .Poison if biome == 2 else .Burn, 1, 0))
			status_report := resolve_action(room, &status_action)
			merge_action_report(pulse, &status_report)
		}
	}
}

// The line an archer's aimed arrow will fly from where it stands: its step.
enemy_arrow_aim_step :: proc(enemy: ^Enemy) -> (step: grid.Position, ok: bool) {
	if enemy == nil || enemy.intent.threatened_cell_count <= 0 { return }
	step, _, ok = orthogonal_step_and_distance(enemy.position, enemy.intent.threatened_cells[0])
	return step, ok && step != {}
}
