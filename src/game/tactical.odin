package game

import grid "../engine/grid"

// Recovery leaves only walking; Stunned (an exhausted window) only cards;
// Shadow (Movimento Ombra, tactical_shadow.odin) only the shadow's own steps,
// with the whole world frozen.
Tactical_Phase :: enum { Decision, Recovery, Resolving, Stunned, Shadow }
Tactical_Config :: struct {
	timer_seconds: int,
	vision_size: int,
	qte_seconds: f32,
	// Timed actions: an action lasts its cost in real time instead of spending
	// it at once (tactical_clock.odin).
	timed_actions: bool,
	// The shrinking window: each window that runs out leaves the next a second
	// shorter, down to a stun (tactical_clock.odin).
	shrinking_window: bool,
}
// The bare rules, which the regression probes are written against.
DEFAULT_TACTICAL_CONFIG :: Tactical_Config{timer_seconds = 20, vision_size = 7, qte_seconds = 1.2}
// The game as it is played: actions last their cost, the window shrinks.
GAME_TACTICAL_CONFIG :: Tactical_Config{timer_seconds = 20, vision_size = 7, qte_seconds = 1.2,
	timed_actions = true, shrinking_window = true}
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
	// With timed actions, the player's own action still running (seconds);
	// the world clock runs through it as usual.
	action_remaining, action_duration: f32,
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
	// The shrinking window (tactical_clock.odin): the window the current
	// recovery or stun leads to, cards played toward the next won second and
	// the seconds won in this window, and how many stuns this room has dealt.
	next_budget: int,
	cards_toward_second, won_seconds: int,
	stuns: int,
	stun_duration: f32,
	// Movimento Ombra (tactical_shadow.odin): the phase the shadow interrupted,
	// its own real-time clock, the current step's lockout, the cell the body
	// sank on (player.position stays there), the shadow's cell and the one it
	// left, the shadow beats already rewarded and the steps taken.
	shadow_resume: Tactical_Phase,
	shadow_remaining, shadow_duration: f32,
	shadow_step_remaining: f32,
	shadow_origin, shadow_position, shadow_from: grid.Position,
	shadow_beats_spent: bit_set[0..<8; u8],
	shadow_steps: int,
	// DADO DEL DESTINO: the die its loaded bumps roll, the one of the last
	// card played (player_charges.odin); a new room forgets it with the charges.
	fate_sides: i32,
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

@(private)
valid_tactical_config :: proc(config: Tactical_Config) -> bool {
	return config.timer_seconds >= 1 && config.timer_seconds <= 60 &&
	       valid_tactical_vision(config.vision_size) && config.qte_seconds >= 0.2 && config.qte_seconds <= 5
}

configure_tactical :: proc(player: ^Player, config: Tactical_Config) -> bool {
	if player == nil || !valid_tactical_config(config) { return false }
	player.tactical = {config = config, budget = config.timer_seconds,
		remaining = f32(config.timer_seconds), facing = .South}
	return true
}

// Startup/restart may construct a room before applying clock configuration.
// Rebuild its first telegraphs before any action occurs.
configure_tactical_room :: proc(room: ^Room, config: Tactical_Config) -> bool {
	if room == nil || room.level_data == nil || !configure_tactical(room.player, config) { return false }
	for &enemy in room.enemies { enemy.bomb_ready = false; enemy.bomb_anchor = {}; enemy.intent = {}; enemy.tactical_cooldown = 0 }
	plan_enemy_intents(room)
	return true
}

// The player is still performing a timed action, or a shadow step, or swings
// the Lazzo's foe round him (he is its pivot).
tactical_player_busy :: proc(room: ^Room) -> bool {
	return room != nil && room.player != nil && room.phase == .Combat &&
	       (room.player.tactical.action_remaining > 0 || tactical_shadow_step_busy(room) || room.lasso.active)
}

tactical_is_recovering :: proc(room: ^Room) -> bool {
	return room != nil && room.player != nil && room.phase == .Combat && room.player.tactical.phase == .Recovery
}

tactical_is_stunned :: proc(room: ^Room) -> bool {
	return room != nil && room.player != nil && room.phase == .Combat && room.player.tactical.phase == .Stunned
}

// Recovery and stun both stand between two windows.
@(private)
tactical_between_windows :: proc(s: ^Tactical_State) -> bool {
	return s.phase == .Recovery || s.phase == .Stunned
}

// Called only after a new room has been successfully built. Keep configuration
// and run telemetry, but give each encounter its own window counter.
@(private)
begin_tactical_room :: proc(room: ^Room) {
	if room == nil || room.player == nil { return }
	tactical_reset_room_clock(&room.player.tactical)
	room.player.tactical.cycle = 0
	room.player.tactical.fate_sides = 0
	for &enemy in room.enemies { enemy.tactical_cooldown = 0 }
}

// Reset clock-local state at a room boundary. Configuration, facing, the
// room's cycle count and run telemetry have different lifetimes and stay.
@(private = "file")
tactical_reset_room_clock :: proc(s: ^Tactical_State) {
	s.phase = .Decision
	s.budget = s.config.timer_seconds
	s.remaining = f32(s.budget)
	tactical_reset_window_pressure(s)
	s.dodge_recovery = 0
	s.clock_fraction = 0
	s.queued_beats = 0
	s.cast_remaining, s.cast_duration = 0, 0
	s.action_remaining, s.action_duration = 0, 0
	tactical_reset_beats(s)
	tactical_reset_shadow(s)
}

tactical_end_combat :: proc(room: ^Room) {
	if room == nil || room.player == nil || room.phase == .Combat { return }
	tactical_reset_room_clock(&room.player.tactical)
	room.tactical_pulse = {}
	room.qte = {}
	// End only combat activities. Terrain, devices, fishing and shot history
	// still belong to this room; they are not part of an exclusive takeover.
	room.lasso = {}
	room.pinball = {}
	room.first_person.active, room.first_person.trigger = false, false
}

@(private = "file")
tactical_finish_cycle_pulse :: proc(room: ^Room, forced: bool) {
	s := &room.player.tactical
	s.dodge_recovery = max(0, s.dodge_recovery-1)
	if forced { s.metrics.forced_pulses += 1 }
	// Only the beat's own Resolving hands the window back: no pulse ever
	// finishes inside a shadow, and none may end one.
	if s.phase == .Resolving { s.phase = .Decision }
	tactical_queue_next_beat(room)
	tactical_finish_recovery(room)
}

// Clock input is supplied by the app; this module never reads wall time.
// Returning true requests an explicit timeout command, at most once per frame.
tactical_tick :: proc(room: ^Room, dt: f32, available: bool, hologram: bool) -> bool {
	clock := tactical_clock_mode(room, available)
	if clock == .Paused { return false }
	if clock == .Shadow { tactical_shadow_tick(room, dt); return false }
	s := &room.player.tactical
	if clock == .Cast {
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
		if tactical_between_windows(s) { tactical_finish_recovery(room); return false }
		return true
	}
	if !(dt > 0) { return false }
	// A timed action runs on the same real seconds as the window.
	if s.action_remaining > 0 {
		s.action_remaining = max(f32(0), s.action_remaining-dt)
		if s.action_remaining < 0.00001 { s.action_remaining = 0 }
	}
	elapsed := min(dt, max(f32(0), s.remaining))
	before := s.clock_fraction
	tactical_advance_clock(room, elapsed)
	tactical_note_beat_time(s, before, elapsed)
	// The Lazzo spins on the same seconds; the controller spins them out.
	tactical_lasso_tick(room, elapsed)
	s.metrics.decision_seconds += f64(elapsed)
	if hologram { s.metrics.hologram_seconds += f64(elapsed) }
	if tactical_between_windows(s) { tactical_finish_recovery(room); return false }
	return s.remaining <= 0 && !room.tactical_pulse.pending
}

// Each continuation owns one bounded event log. Only elapsed world time queues
// beats: calling this repeatedly cannot accelerate or complete recovery.
continue_tactical_pulse :: proc(room: ^Room) -> bool {
	if room == nil || room.player == nil || room.phase != .Combat || room.qte.kind != .None { return false }
	p := &room.tactical_pulse
	s := &room.player.tactical
	if !p.pending { return false }
	clear_event_log(room.recent_events)
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
				// A foe out of play (the Lazzo's, the Pinball's) does nothing.
				if !found || enemy_is_out_of_play(room, id) { continue }
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
		append_event_log(room.recent_events, &pulse.events)
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
	append_event_log(room.recent_events, &pulse.events)
	if room.phase != .Combat {
		// A pulse already started still emits its terminal marker exactly once.
		pulse = {}
		finish_combat_pulse(room, &pulse)
		append_event_log(room.recent_events, &pulse.events)
		collect_loot_in_magnet_range(room)
		tactical_finish_cycle_pulse(room, p.forced)
		sync_deck_with_room_phase(room)
		tactical_end_combat(room)
	}
	return true
}

@(private)
tactical_refill :: proc(room: ^Room) {
	p := &room.tactical_pulse
	deck := &room.player.deck
	for p.deferred_draws > 0 || (p.refill && deck.hand_count < deck.rules.hand_size) {
		card, drawn := draw_card(deck)
		if !drawn { break }
		record_card_draw(room.recent_events, card)
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

@(private)
tactical_room_opaque :: proc(data: rawptr, position: grid.Position) -> bool {
	return cell_blocks_line_of_sight(cast(^Room)data, position)
}

tactical_cell_visible :: proc(room: ^Room, position: grid.Position) -> bool {
	if room == nil || room.player == nil || room.level_data == nil { return false }
	if !grid.contains(&room.level_data.tiles, position) { return false }
	s := &room.player.tactical
	if s.config.vision_size == 0 { return true }
	origin := tactical_view_origin(room)
	return tactical_in_footprint(tactical_vision_size(s.config, &room.player.statuses), s.facing, origin, position) &&
		tactical_line_visible(origin, position, tactical_room_opaque, room)
}

tactical_target_visible :: proc(room: ^Room, target: Target) -> bool {
	if room == nil || room.player == nil { return true }
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
	if room == nil || room.player == nil || room.phase != .Combat || !tactical_allows_action(room) ||
	   abs(offset.x) != 1 || abs(offset.y) != 1 { return false }
	destination := add_position(room.player.position, offset)
	query := query_entity_movement(room, PLAYER_ENTITY, destination)
	if query.error != .None { return false }
	clear_event_log(room.recent_events)
	room.qte = {kind = .Diagonal, remaining = room.player.tactical.config.qte_seconds,
		destination = destination, length = 2, selected = true,
		keys = {(.West if offset.x < 0 else .East), (.North if offset.y < 0 else .South)}}
	room.player.tactical.metrics.qte_attempts += 1
	return true
}

offer_defense_qte :: proc(room: ^Room, enemy: ^Enemy) -> bool {
	// A stunned player cannot defend: only cards are left.
	if tactical_is_stunned(room) { return false }
	intent := &enemy.intent
	if enemy_is_staggered(room, enemy) || intent.windup || (intent.kind != .Attack && intent.kind != .Charge) || intent.target_object != 0 || enemy.position != intent.origin ||
	   !enemy_intent_cell_is_threatened(intent, room.player.position) ||
	   (enemy.archetype == .Archer && !has_clear_orthogonal_line(room, enemy.position, room.player.position)) { return false }
	if intent.kind == .Charge {
		index, found := enemy_index_by_id(room, enemy.id)
		if !found || !enemy_charge_path_is_clear(room, index, intent) { return false }
	}
	// RIFLESSO answers this blow by itself (deflect_enemy_blow): no defence to choose.
	if player_charges(room, .Deflect) > 0 { return false }
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
	if room == nil || room.player == nil || room.qte.kind == .None { return false }
	success := requested_success
	q := room.qte
	room.qte = {}
	clear_event_log(room.recent_events)
	// One report for the dodge's bite and the pulse a terminal answer ends.
	pulse: Pulse_Report
	if q.kind == .Diagonal {
		if success {
			action := make_action(.Move, PLAYER_ENTITY, cell_target(q.destination), .Walkable_Cell)
			added := add_effect(&action, move_effect(PLAYER_ENTITY, q.destination))
			assert(added)
			report := resolve_action(room, &action)
			success = report.accepted
			append_event_log(room.recent_events, &report.events)
		}
		finish_player_combat_command(room)
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
				append_event_log(room.recent_events, &report.events)
			case .Parry, .Deflect:
				p.cancel_attack = q.enemy_id
				action := make_action(.Trigger, PLAYER_ENTITY, entity_target(enemy_entity(enemy.id)), .Opponent)
				damage := i32(2) if q.mode == .Parry else enemy.intent.damage
				added := add_effect(&action, damage_effect(enemy_entity(enemy.id), damage))
				assert(added)
				report := resolve_action(room, &action)
				append_event_log(room.recent_events, &report.events)
			case .Dodge:
				destination := add_position(room.player.position, direction_offset(dodge_direction))
				action := make_action(.Move, PLAYER_ENTITY, cell_target(destination), .Walkable_Cell)
				added := add_effect(&action, move_effect(PLAYER_ENTITY, destination))
				assert(added)
				report := resolve_action(room, &action)
				success = report.accepted
				append_event_log(room.recent_events, &report.events)
				if success {
					start_tactical_dodge_recovery(room)
					room.player.tactical.facing = dodge_direction
					// A dodge is the player's action, whichever key starts it: his
					// poison bites. Block, parry and deflect answer a blow only.
					tick_poison_on_action(room, PLAYER_ENTITY, &pulse)
					append_event_log(room.recent_events, &pulse.events)
					pulse = {}
				}
			}
		}
	}
	if success { room.player.tactical.metrics.qte_successes += 1 }
	else { room.player.tactical.metrics.qte_failures += 1 }
	if q.kind == .Defense && room.phase != .Combat && room.tactical_pulse.started {
		finish_combat_pulse(room, &pulse)
		append_event_log(room.recent_events, &pulse.events)
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
