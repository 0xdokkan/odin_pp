package advisor

import game "../game"

// THE SIMULATOR (docs/piano-ia.md, Fase 1). A move is the very command the game would carry out, through the same
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
}

Move :: struct {
	kind: Move_Kind,
	direction: game.Move_Direction,
	// Card: the card in hand and its target.
	card_id: u32,
	target: game.Target,
}

// What the copy's player does when the defence keys come up (game.offer_defense_qte). Fase 1: nothing, as a player who
// presses no key (the window runs out and the blow lands); the best defence is Fase 2's.
Defense_Policy :: enum u8 { None }

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
	}
	return
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
		room.qte.remaining = max(f32(0), room.qte.remaining-dt)
		if room.qte.remaining <= 0 { game.resolve_qte(room, false) }
		return
	}
	if !drain_pulses(room) { return }
	game.tactical_tick(room, dt, true, false)
	if !drain_pulses(room) { return }
	for _ in 0..<WORLD_BATCHES {
		if !game.tactical_lasso_due(room) || !game.resolve_lasso_spin(room) { break }
	}
	for _ in 0..<WORLD_BATCHES {
		if !game.tactical_pinball_due(room) || !game.resolve_pinball_roll(room) { break }
	}
	for _ in 0..<WORLD_BATCHES {
		if !game.tactical_flights_due(room) || !game.resolve_enemy_flights(room) { break }
	}
	if game.tactical_tick(room, 0, true, false) && room.player.tactical.remaining <= 0 {
		if game.tactical_expire_window(room) { room.player.tactical.metrics.timeouts += 1 }
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
