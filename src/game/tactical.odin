package game

import grid "../grid"

Tactical_Phase :: enum { Decision, Recovery, Resolving }
Tactical_Config :: struct {
	enabled: bool,
	timer_seconds: int,
	vision_size: int,
	qte_seconds: f32,
}
DEFAULT_TACTICAL_CONFIG :: Tactical_Config{true, 20, 7, 1.2}
MAX_TACTICAL_VISION :: 9
TACTICAL_DODGE_RECOVERY :: 2

valid_tactical_vision :: proc(size: int) -> bool {
	return size == 0 || size == 2 || size == 3 || size == 5 || size == 7 || size == 9
}
Tactical_Metrics :: struct {
	decisions, timeouts, pauses, forced_pulses: u64,
	qte_attempts, qte_successes, qte_failures, hologram_opens: u64,
	decision_seconds, hologram_seconds: f64,
}
Tactical_State :: struct {
	config: Tactical_Config,
	phase: Tactical_Phase,
	// Decision pressure belongs to the current room; metrics span the run.
	budget, cycle: int,
	remaining: f32,
	// Casting spends pulse time gradually, without advancing the world clock.
	cast_remaining, cast_duration: f32,
	// World time advances in bounded one-second beats; animations never add time.
	clock_fraction: f32,
	queued_beats: int,
	facing: Move_Direction,
	dodge_recovery: int,
	metrics: Tactical_Metrics,
	// On-beat criticals (tactical_beat.odin): beats crossed by real time in
	// this room, seconds since the last one, the last beat rewarded, and the
	// one-shot flags read by the critical action.
	beat_index, beat_spent: u32,
	beat_age: f32,
	critical_next, critical_card: bool,
}
Tactical_Pulse :: struct {
	pending, started, forced: bool,
	ids: [MAX_ENEMIES_PER_ROOM]u32,
	count, cursor, deferred_draws: int,
	refill, exhaust_relic: bool,
	defense_answered: u32,
	cancel_attack: u32,
}
QTE_Kind :: enum { None, Diagonal, Defense }
Defense_Mode :: enum { Block, Parry, Deflect, Dodge }
QTE_State :: struct {
	kind: QTE_Kind,
	remaining: f32,
	keys: [2]Move_Direction,
	length, progress: int,
	destination: grid.Position,
	enemy_id: u32,
	defenses: bit_set[Defense_Mode],
	mode: Defense_Mode,
	selected: bool,
}

configure_tactical :: proc(player: ^Player, config: Tactical_Config) -> bool {
	if player == nil || config.timer_seconds < 1 || config.timer_seconds > 60 ||
	   !valid_tactical_vision(config.vision_size) ||
	   !(config.qte_seconds >= 0.2 && config.qte_seconds <= 5) { return false }
	player.tactical = {config = config, budget = config.timer_seconds,
		remaining = f32(config.timer_seconds), facing = .South}
	return true
}

// Startup/restart may construct a room before applying CLI mode options.
// Rebuild its first telegraphs with the chosen rules before any action occurs.
configure_tactical_room :: proc(room: ^Room, config: Tactical_Config) -> bool {
	if room == nil || room.level_data == nil || !configure_tactical(room.player, config) { return false }
	for &enemy in room.enemies { enemy.bomb_ready = false; enemy.bomb_anchor = {}; enemy.intent = {}; enemy.tactical_cooldown = 0 }
	plan_enemy_intents(room)
	return true
}

tactical_enabled :: proc(room: ^Room) -> bool {
	return room != nil && room.player != nil && room.player.tactical.config.enabled
}

tactical_allows_action :: proc(room: ^Room) -> bool {
	if !tactical_enabled(room) || room.phase != .Combat { return true }
	s := &room.player.tactical
	return !room.tactical_pulse.pending && room.qte.kind == .None && s.remaining > 0 && s.cast_remaining <= 0 &&
	       s.phase == .Decision
}

tactical_is_recovering :: proc(room: ^Room) -> bool {
	return tactical_enabled(room) && room.phase == .Combat && room.player.tactical.phase == .Recovery
}

tactical_allows_movement :: proc(room: ^Room) -> bool {
	if !tactical_is_recovering(room) { return tactical_allows_action(room) }
	return !room.tactical_pulse.pending && room.qte.kind == .None
}

// Called only after a new room has been successfully built. Keep configuration
// and run telemetry, but give each encounter its own window counter.
begin_tactical_room :: proc(room: ^Room) {
	if !tactical_enabled(room) { return }
	s := &room.player.tactical
	s.phase = .Decision
	s.budget = s.config.timer_seconds
	s.remaining = f32(s.budget)
	s.cycle = 0
	s.dodge_recovery = 0
	s.clock_fraction = 0
	s.queued_beats = 0
	s.cast_remaining, s.cast_duration = 0, 0
	tactical_reset_beats(s)
	for &enemy in room.enemies { enemy.tactical_cooldown = 0 }
}

tactical_end_combat :: proc(room: ^Room) {
	if !tactical_enabled(room) || room.phase == .Combat { return }
	s := &room.player.tactical
	s.budget = s.config.timer_seconds
	s.phase = .Decision
	s.remaining = f32(s.budget)
	s.dodge_recovery = 0
	s.clock_fraction = 0
	s.queued_beats = 0
	s.cast_remaining, s.cast_duration = 0, 0
	tactical_reset_beats(s)
	room.tactical_pulse = {}
	room.qte = {}
}

tactical_finish_cycle_pulse :: proc(room: ^Room, forced: bool) {
	s := &room.player.tactical
	s.dodge_recovery = max(0, s.dodge_recovery-1)
	if forced { s.metrics.forced_pulses += 1 }
	if s.phase != .Recovery { s.phase = .Decision }
	tactical_queue_next_beat(room)
	tactical_finish_recovery(room)
}

// Clock input is supplied by the app; this module never reads wall time.
// Returning true requests an explicit timeout command, at most once per frame.
tactical_tick :: proc(room: ^Room, dt: f32, available: bool, hologram: bool) -> bool {
	if !tactical_enabled(room) || room.phase != .Combat || !available ||
	   room.tactical_pulse.pending || room.qte.kind != .None { return false }
	s := &room.player.tactical
	if s.phase != .Decision && s.phase != .Recovery { return false }
	if s.cast_remaining > 0 {
		elapsed := min(max(f32(0), dt), s.cast_remaining)
		s.cast_remaining = max(f32(0), s.cast_remaining-elapsed)
		if s.cast_remaining < 0.00001 { s.cast_remaining = 0 }
		charged := min(elapsed, s.remaining)
		s.remaining = max(f32(0), s.remaining-charged)
		if s.remaining < 0.00001 { s.remaining = 0 }
		s.metrics.decision_seconds += f64(charged)
		if s.cast_remaining == 0 { tactical_refill(room) }
		// Remainder belongs to the next controller frame: no world catch-up
		// after a cinematic or a long frame can surprise the player.
		return s.cast_remaining == 0 && s.remaining == 0
	}
	// The final charged beat can finish on a zero-delta controller frame. A
	// deadline already reached must still publish its explicit timeout command.
	if s.remaining <= 0 {
		if s.phase == .Recovery { tactical_finish_recovery(room); return false }
		return true
	}
	if !(dt > 0) { return false }
	elapsed := min(dt, max(f32(0), s.remaining))
	before := s.clock_fraction
	tactical_advance_clock(room, elapsed)
	tactical_note_beat_time(s, before, elapsed)
	s.metrics.decision_seconds += f64(elapsed)
	if hologram { s.metrics.hologram_seconds += f64(elapsed) }
	if s.phase == .Recovery { tactical_finish_recovery(room); return false }
	return s.remaining <= 0 && !room.tactical_pulse.pending
}

// Each continuation owns one bounded event log. Only elapsed world time queues
// beats: calling this repeatedly cannot accelerate or complete recovery.
continue_tactical_pulse :: proc(room: ^Room) -> bool {
	if !tactical_enabled(room) || room.phase != .Combat || room.qte.kind != .None { return false }
	p := &room.tactical_pulse
	s := &room.player.tactical
	if !p.pending { return false }
	clear_event_log(&room.recent_events)
	pulse: Pulse_Report
	if !p.started {
		p.started = true
		s.queued_beats = max(0, s.queued_beats-1)
		for &enemy in room.enemies { enemy.tactical_cooldown = max(f32(0), enemy.tactical_cooldown-1) }
		resolve_due_explosives(room, &pulse)
		resolve_due_room_modifier(room, &pulse)
		ids, count := enemy_ids_in_planning_order(room)
		for protect_pass in 0..<2 {
			for id in ids[:count] {
				index, found := enemy_index_by_id(room, id)
				if !found { continue }
				// Stagger interrupts committed telegraphs before its status expires,
				// even when this enemy's ordinary cadence is not due yet.
				if room.enemies[index].tactical_cooldown > 0 && !enemy_is_staggered(room, &room.enemies[index]) { continue }
				protect := room.enemies[index].intent.kind == .Protect
				if protect != (protect_pass == 0) { continue }
				p.ids[p.count] = id
				p.count += 1
			}
		}
	} else if p.cursor < p.count {
		id := p.ids[p.cursor]
		if index, found := enemy_index_by_id(room, id); found {
			if id != p.defense_answered && offer_defense_qte(room, &room.enemies[index]) { return true }
			staggered := enemy_is_staggered(room, &room.enemies[index])
			resolve_enemy_intents(room, &pulse, id)
			if staggered {
				if remaining_index, present := enemy_index_by_id(room, id); present {
					// A card must leave at least one actionable second of exposure
					// after its own charged seconds have finished resolving.
					room.enemies[remaining_index].recovery_pulses = max(room.enemies[remaining_index].recovery_pulses, i32(s.queued_beats+1))
				}
			}
		}
		p.cursor += 1
	} else {
		finish_combat_pulse(room, &pulse)
		append_event_log(&room.recent_events, &pulse.events)
		collect_loot_in_magnet_range(room)
		forced := p.forced
		p.pending = false
		p.started = false
		p.count = 0
		p.cursor = 0
		p.defense_answered = 0
		p.cancel_attack = 0
		tactical_finish_cycle_pulse(room, forced)
		if room.phase == .Combat { tactical_refill(room) }
		sync_deck_with_room_phase(room)
		tactical_end_combat(room)
		return true
	}
	append_event_log(&room.recent_events, &pulse.events)
	if room.phase != .Combat {
		// A pulse already started still emits its terminal marker exactly once.
		pulse = {}
		finish_combat_pulse(room, &pulse)
		append_event_log(&room.recent_events, &pulse.events)
		collect_loot_in_magnet_range(room)
		tactical_finish_cycle_pulse(room, p.forced)
		sync_deck_with_room_phase(room)
		tactical_end_combat(room)
	}
	return true
}

tactical_refill :: proc(room: ^Room) {
	p := &room.tactical_pulse
	deck := &room.player.deck
	for p.deferred_draws > 0 || (p.refill && deck.hand_count < deck.rules.hand_size) {
		card, drawn := draw_card(deck)
		if !drawn { break }
		record_refocus_draw(&room.recent_events, card)
		p.deferred_draws = max(0, p.deferred_draws-1)
	}
	if p.exhaust_relic { apply_card_relics(room, .Exhaust, nil) }
	p.deferred_draws = 0
	p.refill = false
	p.exhaust_relic = false
}

// Shared by authoritative gameplay and the renderer's animated snapshot.
tactical_in_footprint :: proc(size: int, facing: Move_Direction, origin, position: grid.Position) -> bool {
	dx, dy := position.x-origin.x, position.y-origin.y
	if size == 0 { return true }
	if abs(dx) > size/2 || abs(dy) > size/2 { return false }
	if size == 2 {
		offset := direction_offset(facing)
		min_x := -1 if offset.x < 0 else 0
		min_y := -1 if offset.y < 0 else 0
		return dx >= min_x && dx <= min_x+1 && dy >= min_y && dy <= min_y+1
	}
	return true
}

// Visible endpoints include walls; intermediate blockers and closed corners
// hide what lies behind them. There is deliberately no explored-cell storage.
tactical_line_visible :: proc(origin, destination: grid.Position,
	opaque: proc(rawptr, grid.Position) -> bool, data: rawptr) -> bool {
	cell := origin
	dx, dy := abs(destination.x-origin.x), abs(destination.y-origin.y)
	sx := 1 if destination.x > origin.x else -1
	sy := 1 if destination.y > origin.y else -1
	error := dx-dy
	for cell != destination {
		next := cell
		twice := 2*error
		if twice > -dy { error -= dy; next.x += sx }
		if twice < dx { error += dx; next.y += sy }
		if next.x != cell.x && next.y != cell.y &&
		   opaque(data, {next.x, cell.y}) && opaque(data, {cell.x, next.y}) { return false }
		if next != destination && opaque(data, next) { return false }
		cell = next
	}
	return true
}

tactical_room_opaque :: proc(data: rawptr, position: grid.Position) -> bool {
	return cell_blocks_line_of_sight(cast(^Room)data, position)
}

tactical_cell_visible :: proc(room: ^Room, position: grid.Position) -> bool {
	if room == nil || room.player == nil || room.level_data == nil { return false }
	if !grid.contains(&room.level_data.tiles, position) { return false }
	s := &room.player.tactical
	if !s.config.enabled || s.config.vision_size == 0 { return true }
	origin := room.player.position
	return tactical_in_footprint(tactical_vision_size(s.config, &room.player.statuses), s.facing, origin, position) &&
		tactical_line_visible(origin, position, tactical_room_opaque, room)
}

tactical_target_visible :: proc(room: ^Room, target: Target) -> bool {
	if !tactical_enabled(room) { return true }
	switch target.kind {
	case .None: return true
	case .Cell: return tactical_cell_visible(room, target.cell)
	case .Entity:
		if target.entity == PLAYER_ENTITY { return true }
		position, found := entity_position(room, target.entity)
		return found && tactical_cell_visible(room, position)
	}
	return false
}

begin_diagonal_qte :: proc(room: ^Room, offset: grid.Position) -> bool {
	if !tactical_enabled(room) || room.phase != .Combat || !tactical_allows_action(room) ||
	   abs(offset.x) != 1 || abs(offset.y) != 1 { return false }
	destination := add_position(room.player.position, offset)
	query := query_entity_movement(room, PLAYER_ENTITY, destination)
	if query.error != .None { return false }
	clear_event_log(&room.recent_events)
	room.qte = {kind = .Diagonal, remaining = room.player.tactical.config.qte_seconds,
		destination = destination, length = 2, selected = true,
		keys = {(.West if offset.x < 0 else .East), (.North if offset.y < 0 else .South)}}
	room.player.tactical.metrics.qte_attempts += 1
	return true
}

offer_defense_qte :: proc(room: ^Room, enemy: ^Enemy) -> bool {
	intent := &enemy.intent
	if enemy_is_staggered(room, enemy) || intent.windup || (intent.kind != .Attack && intent.kind != .Charge) || intent.target_object != 0 || enemy.position != intent.origin ||
	   !enemy_intent_cell_is_threatened(intent, room.player.position) ||
	   (enemy.archetype == .Archer && !has_clear_orthogonal_line(room, enemy.position, room.player.position)) { return false }
	if intent.kind == .Charge {
		index, found := enemy_index_by_id(room, enemy.id)
		if !found || !enemy_charge_path_is_clear(room, index, intent) { return false }
	}
	defenses: bit_set[Defense_Mode]
	if _, found := status_for_entity(room, PLAYER_ENTITY, .Shield); found { defenses += {.Block, .Parry} }
	if _, found := status_for_entity(room, PLAYER_ENTITY, .Thorns); found && enemy.archetype == .Archer { defenses += {.Deflect} }
	if tactical_dodge_ready(room) && tactical_dodge_has_landing(room) { defenses += {.Dodge} }
	if card(defenses) == 0 { return false }
	room.qte = {kind = .Defense, remaining = room.player.tactical.config.qte_seconds,
		enemy_id = enemy.id, defenses = defenses, length = 1}
	room.player.tactical.metrics.qte_attempts += 1
	return true
}

select_defense :: proc(room: ^Room, mode: Defense_Mode) -> bool {
	q := &room.qte
	if q.kind != .Defense || q.selected || mode not_in q.defenses { return false }
	q.mode = mode
	q.selected = true
	q.keys[0] = Move_Direction((room.pulse_count+u64(q.enemy_id))%4)
	// Parry is harder; selecting it does not refill the original deadline.
	if mode == .Parry { q.remaining = min(q.remaining, f32(0.45)) }
	return true
}

resolve_qte :: proc(room: ^Room, requested_success: bool, dodge_direction: Move_Direction = .North) -> bool {
	if !tactical_enabled(room) || room.qte.kind == .None { return false }
	success := requested_success
	q := room.qte
	room.qte = {}
	clear_event_log(&room.recent_events)
	if q.kind == .Diagonal {
		if success {
			action := make_action(.Move, PLAYER_ENTITY, cell_target(q.destination), .Walkable_Cell)
			added := add_effect(&action, move_effect(PLAYER_ENTITY, q.destination))
			assert(added)
			report := resolve_action(room, &action)
			success = report.accepted
			append_event_log(&room.recent_events, &report.events)
		}
		_, _ = finish_player_combat_command(room)
	} else {
		p := &room.tactical_pulse
		p.defense_answered = q.enemy_id
		index, found := enemy_index_by_id(room, q.enemy_id)
		if !q.selected || !found { success = false }
		if success {
			enemy := room.enemies[index]
			switch q.mode {
			case .Block:
				action := make_action(.Trigger, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
				added := add_effect(&action, apply_status_effect(PLAYER_ENTITY, .Shield, 2, 1))
				assert(added)
				report := resolve_action(room, &action)
				append_event_log(&room.recent_events, &report.events)
			case .Parry, .Deflect:
				p.cancel_attack = q.enemy_id
				action := make_action(.Trigger, PLAYER_ENTITY, entity_target(enemy_entity(enemy.id)), .Opponent)
				damage := i32(2) if q.mode == .Parry else enemy.intent.damage
				added := add_effect(&action, damage_effect(enemy_entity(enemy.id), damage))
				assert(added)
				report := resolve_action(room, &action)
				append_event_log(&room.recent_events, &report.events)
			case .Dodge:
				destination := add_position(room.player.position, direction_offset(dodge_direction))
				action := make_action(.Move, PLAYER_ENTITY, cell_target(destination), .Walkable_Cell)
				added := add_effect(&action, move_effect(PLAYER_ENTITY, destination))
				assert(added)
				report := resolve_action(room, &action)
				success = report.accepted
				append_event_log(&room.recent_events, &report.events)
				if success { start_tactical_dodge_recovery(room); room.player.tactical.facing = dodge_direction }
			}
		}
	}
	if success { room.player.tactical.metrics.qte_successes += 1 }
	else { room.player.tactical.metrics.qte_failures += 1 }
	if q.kind == .Defense && room.phase != .Combat && room.tactical_pulse.started {
		pulse: Pulse_Report
		finish_combat_pulse(room, &pulse)
		append_event_log(&room.recent_events, &pulse.events)
		collect_loot_in_magnet_range(room)
		tactical_finish_cycle_pulse(room, room.tactical_pulse.forced)
	}
	sync_deck_with_room_phase(room)
	tactical_end_combat(room)
	return true
}

qte_key :: proc(room: ^Room, direction: Move_Direction) -> bool {
	q := &room.qte
	if q.kind == .None || !q.selected { return false }
	if q.kind == .Defense && q.mode == .Dodge { return resolve_qte(room, true, direction) }
	if direction != q.keys[q.progress] { return resolve_qte(room, false) }
	q.progress += 1
	if q.progress == q.length { return resolve_qte(room, true) }
	return true
}
