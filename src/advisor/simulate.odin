package advisor

import game "../game"
import grid "../engine/grid"

// THE SIMULATOR (docs/piano-ia.md, Fasi 1 e 2). A move is the very command the game would carry out, through the same
// procedures of the rules and in the same order as run.execute_gameplay_command; then the world runs, frame by frame,
// as the tactical controller runs it (run.step_tactical_controller): the beats, the arrows and bombs in flight, the
// Lazzo's and the Pinball's seconds, the window's end. The advisor cannot import `run` (run imports the advisor), so
// the order is written again here, and the integration test that plays the same game both ways keeps them alike.

Move_Kind :: enum u8 {
	// A step `direction`: into a foe it is the bump.
	Step,
	Dodge,
	Wait,
	Card,
	Refocus,
	// The diagonal step (Q, E and their keys: game.begin_diagonal_qte), towards `offset`, its two keys pressed.
	Diagonal,
	// The defence keys up (game.offer_defense_qte): `defense` chosen, then its key; a dodge lands `direction`. A parry
	// is half luck for a real hand (0.45 s for its key): `succeed` says which half this try plays.
	Defend,
	// A key of the defence keys already up: `direction` (the diagonal's next key, the defence's key, the dodge's landing).
	Key,
	// FERETRO: an arrow loosed at the foe `target` (its charges: Ctrl and a click).
	Shoot,
}

Move :: struct {
	kind: Move_Kind,
	direction: game.Move_Direction,
	// Card: the card in hand and its target.
	card_id: u32,
	target: game.Target,
	offset: grid.Position,
	defense: game.Defense_Mode,
	succeed: bool,
	// A later move of a branch (search.odin): the card in hand slot `slot` (from 1), on its best target then
	// (cards.odin, resolve_slot); 0 for a move given whole.
	slot: i8,
}

// What the copy's player does when the defence keys come up (game.offer_defense_qte) inside a try:
// - None: nothing, as a player who presses no key (the window runs out and the blow lands);
// - Best: the best answer, at once (Fase 2): the deflection when he has it (the blow comes back, nothing lands), else
//   the dodge onto a cell the blow does not reach, else the block. Never the parry inside a try: with the shield it
//   needs the block is always there, and a parry is half luck (the root weighs both halves: Move.succeed).
Defense_Policy :: enum u8 { None, Best }

// The risk a try has run so far, in points of the evaluation: the defence keys and the diagonals' keys a real hand
// may miss (the search sets it to nothing before every try; one a thread).
@(thread_local)
try_risk: f32
// The weight of a point of life in this try (the root's: context.odin; 0 before any search: the start's).
@(thread_local)
try_life_weight: f32

// One move carried out as the game carries out its command. Whether the game took it.
play :: proc(r: ^Rehearsal, move: Move) -> bool {
	context.allocator = try_allocator(r)
	context.temp_allocator = context.allocator
	return play_move(&r.room, move)
}

// The move on any room, through the rules alone (run.execute_gameplay_command's Move, Dodge, Wait, Play_Card and
// Refocus, with no beat claimed: the IA leaves the tick aside, the user's choice).
play_move :: proc(room: ^game.Room, move: Move) -> (committed: bool) {
	if room == nil || room.player == nil || room.phase != .Combat { return false }
	switch move.kind {
	case .Step:
		spent := room.player.tactical.beat_spent
		room.player.tactical.critical_next = game.tactical_claim_beat(room, 0)
		result := game.try_move_player(room, move.direction)
		room.player.tactical.critical_next = false
		if result != .Attacked { room.player.tactical.beat_spent = spent }
		committed = result != .Invalid_Phase && result != .Blocked
		if committed { room.player.tactical.facing = move.direction }
		if !committed { room.player.tactical.beat_spent = spent }
	case .Dodge:
		committed = game.try_dodge_player(room, move.direction)
	case .Wait:
		committed = game.wait_player_turn(room) != .Invalid_Phase
	case .Card:
		spent := room.player.tactical.beat_spent
		if game.tactical_card_claims_beat(room, move.card_id) {
			room.player.tactical.critical_next = game.tactical_claim_beat(room, 0)
		}
		room.aim, room.has_aim = .North, false
		report := game.play_card(room, move.card_id, move.target, move.direction)
		room.player.tactical.critical_next = false
		committed = game.card_play_was_committed(report.result)
		if !committed { room.player.tactical.beat_spent = spent }
	case .Refocus:
		committed = game.refocus_was_committed(game.refocus_player_hand(room).result)
	case .Diagonal:
		// run.execute_gameplay_command's Begin_Diagonal, then its two QTE_Key: the world stands still between them.
		committed = game.begin_diagonal_qte(room, move.offset)
		if committed {
			try_risk += DIAGONAL_RISK
			game.clear_event_log(room.recent_events)
			game.qte_key(room, room.qte.keys[0])
			if room.qte.kind == .Diagonal { game.clear_event_log(room.recent_events); game.qte_key(room, room.qte.keys[1]) }
		}
	case .Defend:
		committed = answer_defense(room, move.defense, move.direction, move.succeed)
	case .Shoot:
		// run.execute_gameplay_command's Shoot: never stamped with a beat.
		result := game.shoot_player_arrow(room, move.target.entity)
		committed = result != .Invalid_Phase && result != .Blocked
	case .Key:
		if room.qte.kind == .None || !room.qte.selected { return false }
		game.clear_event_log(room.recent_events)
		committed = game.qte_key(room, move.direction)
	}
	// As the game's own command ends (run.execute_gameplay_command).
	game.tactical_end_combat(room)
	return
}

// The defence keys answered: the defence `mode` chosen, then its key (run.execute_gameplay_command's Defense, then
// QTE_Key; a missed parry is its window run out, QTE_Fail). A dodge lands `direction`.
@(private)
answer_defense :: proc(room: ^game.Room, mode: game.Defense_Mode, direction: game.Move_Direction, succeed: bool) -> bool {
	// A real hand misses its keys now and then, and then every blow announced on his cell lands: their life, at that
	// chance (a parry weighs its own halves).
	damage := cell_threat(room, room.player.position)
	if index, found := game.enemy_index_by_id(room, room.qte.enemy_id); found { damage = max(damage, f32(room.enemies[index].intent.damage)) }
	if !game.select_defense(room, mode) { return false }
	weight := try_life_weight if try_life_weight > 0 else LIFE_WEIGHT_START
	if mode != .Parry { try_risk += MISS_CHANCE*weight*max(damage, 1) }
	game.clear_event_log(room.recent_events)
	switch {
	case mode == .Dodge: game.qte_key(room, direction)
	case succeed: game.qte_key(room, room.qte.keys[0])
	case: game.resolve_qte(room, false)
	}
	return true
}

// Whether a dodge of the defence keys may land `direction` and leave the blow behind: the rules' own landing (one
// cell, a walk: resolve_qte), outside the cells the blow reaches.
@(private)
dodge_lands_safe :: proc(room: ^game.Room, enemy: ^game.Enemy, direction: game.Move_Direction) -> bool {
	destination := game.add_position(room.player.position, game.direction_offset(direction))
	query := game.query_entity_movement(room, game.PLAYER_ENTITY, destination)
	if query.error != .None || game.step_height_blocked(room, room.player.position, destination) { return false }
	return enemy == nil || !game.enemy_intent_cell_is_threatened(&enemy.intent, destination)
}

// The best answer to the defence keys up now (Defense_Policy.Best): the deflection, else a dodge out of the blow,
// else the block. The tournament's simple rules answer with it too.
best_defense_move :: proc(room: ^game.Room) -> (move: Move, found: bool) {
	q := room.qte
	if q.kind != .Defense || q.selected { return }
	enemy: ^game.Enemy
	if index, alive := game.enemy_index_by_id(room, q.enemy_id); alive { enemy = &room.enemies[index] }
	if .Deflect in q.defenses { return {kind = .Defend, defense = .Deflect, succeed = true}, true }
	if .Dodge in q.defenses {
		for direction in game.Move_Direction {
			if dodge_lands_safe(room, enemy, direction) { return {kind = .Defend, defense = .Dodge, direction = direction, succeed = true}, true }
		}
	}
	if .Block in q.defenses { return {kind = .Defend, defense = .Block, succeed = true}, true }
	return
}

@(private)
answer_best_defense :: proc(room: ^game.Room) -> bool {
	move := best_defense_move(room) or_return
	return answer_defense(room, move.defense, move.direction, true)
}

// The controller's bound on a frame's beats (run.drain_tactical_world_commands) and on its batches of spins, rolls and
// flights (run.LASSO_SPIN_BATCHES, PINBALL_ROLL_BATCHES, ENEMY_FLIGHT_BATCHES).
WORLD_BATCHES :: 4

// The beats due, one foe a call, until none is pending or the defence keys stop the world.
@(private)
drain_pulses :: proc(room: ^game.Room) -> bool {
	budget := (max(0, room.player.tactical.queued_beats)+1)*(game.MAX_ENEMIES_PER_ROOM+2)
	for _ in 0..<budget {
		if room.qte.kind != .None { return false }
		if room.phase != .Combat || !room.tactical_pulse.pending { return true }
		if !game.continue_tactical_pulse(room) { return false }
		game.tactical_end_combat(room)
	}
	return room.qte.kind == .None && !room.tactical_pulse.pending
}

// One frame of `dt` world seconds, as the tactical controller runs it with no key pressed.
frame_room :: proc(room: ^game.Room, dt: f32, policy := Defense_Policy.None) {
	if room == nil || room.player == nil { return }
	if room.phase != .Combat { game.lift_tick(room, dt); return }
	if game.tactical_is_casting(room) {
		game.tactical_tick(room, dt, true, false)
		return
	}
	if room.qte.kind != .None {
		if policy == .Best && answer_best_defense(room) { game.tactical_end_combat(room); return }
		room.qte.remaining = max(f32(0), room.qte.remaining-dt)
		if room.qte.remaining <= 0 { game.resolve_qte(room, false); game.tactical_end_combat(room) }
		return
	}
	if !drain_pulses(room) { return }
	game.tactical_tick(room, dt, true, false)
	if !drain_pulses(room) { return }
	for _ in 0..<WORLD_BATCHES {
		if !game.tactical_lasso_due(room) || !game.resolve_lasso_spin(room) { break }
		game.tactical_end_combat(room)
	}
	for _ in 0..<WORLD_BATCHES {
		if !game.tactical_pinball_due(room) || !game.resolve_pinball_roll(room) { break }
		game.tactical_end_combat(room)
	}
	for _ in 0..<WORLD_BATCHES {
		if !game.tactical_flights_due(room) || !game.resolve_enemy_flights(room) { break }
		game.tactical_end_combat(room)
	}
	if game.tactical_tick(room, 0, true, false) && room.player.tactical.remaining <= 0 {
		if game.tactical_expire_window(room) { room.player.tactical.metrics.timeouts += 1 }
		game.tactical_end_combat(room)
	}
}

// Whether the player may act now: no defence keys up, no beat pending, and the rules let him step, strike or play.
player_free :: proc(room: ^game.Room) -> bool {
	if room == nil || room.player == nil || room.phase != .Combat { return false }
	if room.qte.kind != .None || room.tactical_pulse.pending || game.tactical_player_busy(room) || game.tactical_is_casting(room) { return false }
	return game.tactical_allows_action(room) || game.tactical_allows_movement(room) || game.tactical_allows_cards(room)
}

// The world runs `step` at a time until the player may act again, the fight ends, or `limit` world seconds have gone.
// The seconds it ran.
run_until_free :: proc(r: ^Rehearsal, step: f32, limit: f32 = 10, policy := Defense_Policy.None) -> f32 {
	context.allocator = try_allocator(r)
	context.temp_allocator = context.allocator
	return run_room_until_free(&r.room, step, limit, policy)
}

run_room_until_free :: proc(room: ^game.Room, step: f32, limit: f32 = 10, policy := Defense_Policy.None) -> (ran: f32) {
	if room == nil || !(step > 0) { return }
	for ran < limit {
		if room.phase != .Combat || player_free(room) { return }
		frame_room(room, step, policy)
		ran += step
	}
	return
}
