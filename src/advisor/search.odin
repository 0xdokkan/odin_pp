package advisor

import "base:runtime"
import game "../game"
import grid "../engine/grid"

// THE SEARCH (docs/piano-ia.md, Fase 2, «Come sceglie»). From the snapshot of the real room it tries every first move
// on the rehearsal, then the best replies, deeper and deeper (iterative deepening): every branch is played by the
// rules themselves (play_move, frame_room), then by the fast rule on to the horizon, and the evaluation weighs its end.
// Every round finished gives a whole advice, better than the round before: the search may stop at any node.
//
// Determinism: the work is counted in nodes, never in milliseconds; every node is rebuilt from the snapshot (copy-make)
// and its moves played again, in a fixed order, the first of equals winning. However the nodes are cut into frames,
// the same root gives the same advice after the same nodes.

// The world's frame inside a try: the game's own seconds, a thirtieth at a time.
SIM_STEP :: f32(1.0/30.0)
// The horizon, then the long one when there is time (the user's 3 s up to 6 s).
HORIZON_SHORT :: f32(3)
HORIZON_LONG :: f32(6)
// A branch's moves the search chooses itself (the rest is the fast rule's), and how many of the best it follows at the
// third move.
MAX_DEPTH :: 3
BEAM :: 3
MAX_CANDIDATES :: 16
// The same situation seen again (the transposition table): its slots.
TABLE_SLOTS :: 1 << 13

// The rounds, in order: every first move, every reply, the best three's third moves; then the same at the long horizon.
Round :: struct { depth: int, horizon: f32 }
@(rodata) ROUNDS := [?]Round{{1, HORIZON_SHORT}, {2, HORIZON_SHORT}, {3, HORIZON_SHORT}, {2, HORIZON_LONG}, {3, HORIZON_LONG}}

// What the advice says to do, for the marks.
Advice_Kind :: enum u8 { None, Step, Bump, Dodge, Diagonal, Wait, Defend, Key }

Advice :: struct {
	valid: bool,
	kind: Advice_Kind,
	move: Move,
	// The cell to step or land on, or the foe's to strike.
	cell: grid.Position,
	value: f32,
	// The round it comes from, and the nodes spent on this root so far.
	depth: int,
	horizon: f32,
	nodes: int,
	// The root's situation (discrete_fingerprint).
	root: u64,
	// Given at once from the last search's thinking ahead (pondering), before this root's first round.
	pondered: bool,
}

@(private)
Table_Entry :: struct { key: u64, value: f32, used: bool }

@(private)
Reply :: struct { kind: Advice_Kind, cell: grid.Position }

Search :: struct {
	snapshot: Snapshot,
	rehearsal: Rehearsal,
	ready, rooted, done: bool,
	facts: Root_Facts,
	// The first moves (at the root) and the replies (every later move: the board's own thirteen).
	candidates: [MAX_CANDIDATES]Move,
	candidate_count: int,
	replies: [MAX_CANDIDATES]Move,
	reply_count: int,
	// Every first move: whether the rules take it, what it is for the marks, the situation right after it.
	legal: [MAX_CANDIDATES]bool,
	described: [MAX_CANDIDATES]Reply,
	children: [MAX_CANDIDATES]u64,
	// This round's and the round before's values of every first move; the replies' values at the round of two moves.
	values, previous: [MAX_CANDIDATES]f32,
	reply_values: [MAX_CANDIDATES][MAX_CANDIDATES]f32,
	reply_described: [MAX_CANDIDATES][MAX_CANDIDATES]Reply,
	beam: [BEAM]int,
	beam_count: int,
	beam_replies: [BEAM][BEAM]int,
	beam_reply_count: [BEAM]int,
	round, cursor: int,
	// The nodes spent on this root, and the work they cost (a long horizon's node costs two).
	nodes, work: int,
	advice: Advice,
	// In the process's own memory: too large for a thread's stack.
	table: []Table_Entry,
	table_hits: int,
}

search_init :: proc(s: ^Search) -> bool {
	s^ = {}
	if !snapshot_init(&s.snapshot) { return false }
	if !rehearsal_init(&s.rehearsal) { snapshot_destroy(&s.snapshot); return false }
	table, failed := make([]Table_Entry, TABLE_SLOTS, runtime.heap_allocator())
	if failed != nil { rehearsal_destroy(&s.rehearsal); snapshot_destroy(&s.snapshot); return false }
	s.table = table
	s.ready = true
	return true
}

search_destroy :: proc(s: ^Search) {
	if !s.ready { return }
	rehearsal_destroy(&s.rehearsal)
	snapshot_destroy(&s.snapshot)
	delete(s.table, runtime.heap_allocator())
	s^ = {}
}

// The board's moves in their fixed order: wait first (the safe and the cheap), then the steps north, east, south,
// west (a step into a foe is the bump), the dodges, the diagonals.
@(private)
board_moves :: proc(out: ^[MAX_CANDIDATES]Move) -> (count: int) {
	out[count] = {kind = .Wait}; count += 1
	for direction in game.Move_Direction { out[count] = {kind = .Step, direction = direction}; count += 1 }
	for direction in game.Move_Direction { out[count] = {kind = .Dodge, direction = direction}; count += 1 }
	for offset in ([4]grid.Position{{x = -1, y = -1}, {x = 1, y = -1}, {x = -1, y = 1}, {x = 1, y = 1}}) {
		out[count] = {kind = .Diagonal, offset = offset}; count += 1
	}
	return
}

// The first moves of a root: with the defence keys up, every defence the player has (the dodge in every direction);
// with a key awaited, the key; else the board's moves.
@(private)
root_moves :: proc(room: ^game.Room, out: ^[MAX_CANDIDATES]Move) -> (count: int) {
	q := room.qte
	switch {
	case q.kind == .Defense && !q.selected:
		for mode in game.Defense_Mode {
			if mode not_in q.defenses { continue }
			if mode == .Dodge {
				for direction in game.Move_Direction { out[count] = {kind = .Defend, defense = mode, direction = direction}; count += 1 }
			} else {
				out[count] = {kind = .Defend, defense = mode, succeed = true}; count += 1
			}
		}
	case q.kind == .Defense && q.mode == .Dodge:
		for direction in game.Move_Direction { out[count] = {kind = .Key, direction = direction}; count += 1 }
	case q.kind != .None:
		out[count] = {kind = .Key, direction = q.keys[q.progress]}; count += 1
	case:
		count = board_moves(out)
	}
	return
}

// A new root: the real room photographed (only read), the rehearsal on it, the rounds from the first.
search_root :: proc(s: ^Search, real: ^game.Room) -> bool {
	if !s.ready || !snapshot_take(&s.snapshot, real) || !rehearsal_begin(&s.rehearsal, &s.snapshot) { s.rooted = false; return false }
	s.rooted, s.done = true, false
	s.facts = root_facts(&s.snapshot.room)
	s.candidate_count = root_moves(&s.snapshot.room, &s.candidates)
	s.reply_count = board_moves(&s.replies)
	s.round, s.cursor, s.nodes, s.work, s.table_hits = 0, 0, 0, 0, 0
	s.legal = {}
	s.described = {}
	s.children = {}
	for &entry in s.table { entry = {} }
	for &v in s.values { v = NO_VALUE }
	s.previous = s.values
	s.advice = {root = discrete_fingerprint(&s.snapshot.room)}
	return true
}

// A branch not played: a move the rules refused, or a slot no round filled.
NO_VALUE :: f32(-1e30)

// What a move is, for the marks, on the room where it is about to be played.
describe :: proc(room: ^game.Room, move: Move) -> (reply: Reply) {
	p := room.player.position
	switch move.kind {
	case .Step:
		cell := game.add_position(p, game.direction_offset(move.direction))
		_, foe := game.enemy_index_at(room, cell)
		return {kind = .Bump if foe else .Step, cell = cell}
	case .Dodge:
		cell, _ := game.tactical_dodge_destination(room, move.direction)
		return {kind = .Dodge, cell = cell}
	case .Diagonal: return {kind = .Diagonal, cell = game.add_position(p, move.offset)}
	case .Wait: return {kind = .Wait, cell = p}
	case .Defend:
		if move.defense == .Dodge { return {kind = .Defend, cell = game.add_position(p, game.direction_offset(move.direction))} }
		return {kind = .Defend, cell = p}
	case .Key:
		if room.qte.kind == .Diagonal { return {kind = .Key, cell = room.qte.destination} }
		return {kind = .Key, cell = game.add_position(p, game.direction_offset(move.direction))}
	case .Card, .Refocus: return {kind = .None, cell = p}
	}
	return
}

// THE TEMPO: a blow struck sooner is worth a little more than the same blow at the horizon (the user's «uccidere più
// in fretta», a little more aggressive), so that of two branches doing the same within the horizon the quicker wins.
// Every frame and every move, the life the foes lost and the foes fallen since the last look, weighed by the time left.
@(thread_local, private)
tempo_health: i32
@(thread_local, private)
tempo_foes: int
@(thread_local)
try_tempo: f32

@(private)
tempo_begin :: proc(room: ^game.Room) {
	try_tempo, tempo_health, tempo_foes = 0, 0, len(room.enemies)
	for enemy in room.enemies { tempo_health += max(0, enemy.health) }
}

@(private)
tempo_note :: proc(room: ^game.Room, at, horizon: f32) {
	health := i32(0)
	for enemy in room.enemies { health += max(0, enemy.health) }
	left := max(f32(0), 1-at/horizon)
	if health < tempo_health { try_tempo += TEMPO_WEIGHT*DAMAGE_WEIGHT*f32(tempo_health-health)*left }
	if len(room.enemies) < tempo_foes { try_tempo += TEMPO_WEIGHT*KILL_VALUE*f32(tempo_foes-len(room.enemies))*left }
	tempo_health, tempo_foes = health, len(room.enemies)
}

// The world runs after a move: always its frame (a command is a frame's), then on until the player is free again, the
// fight is over or the horizon is reached. The seconds it ran; `at` is when the move was made.
@(private)
run_after_move :: proc(room: ^game.Room, at, horizon: f32) -> (ran: f32) {
	tempo_note(room, at, horizon)
	left := horizon-at
	frame_room(room, SIM_STEP, .Best)
	ran = SIM_STEP
	tempo_note(room, at+ran, horizon)
	for ran < left {
		if room.phase != .Combat || player_dead(room) || player_free(room) { return }
		frame_room(room, SIM_STEP, .Best)
		ran += SIM_STEP
		tempo_note(room, at+ran, horizon)
	}
	return
}

// The fast rule plays on to the horizon.
@(private)
playout :: proc(room: ^game.Room, elapsed: ^f32, horizon: f32) {
	for elapsed^ < horizon && room.phase == .Combat && !player_dead(room) {
		if player_free(room) {
			if !play_move(room, fast_move(room)) { play_move(room, {kind = .Wait}) }
			elapsed^ += run_after_move(room, elapsed^, horizon)
		} else {
			frame_room(room, SIM_STEP, .Best)
			elapsed^ += SIM_STEP
			tempo_note(room, elapsed^, horizon)
		}
	}
}

@(private)
Path_Result :: enum u8 { Played, Refused }

// One branch on a fresh rehearsal: its moves (the first may be refused: then the branch is not one), then the fast rule
// to the horizon. Its value; the situation right after the first move; what the first two are, for the marks.
@(private)
play_path :: proc(s: ^Search, path: []Move, horizon: f32) -> (value: f32, result: Path_Result, child: u64, first, second: Reply) {
	room := rehearsal_room(&s.rehearsal)
	context.allocator = try_allocator(&s.rehearsal)
	context.temp_allocator = context.allocator
	elapsed: f32
	try_risk = 0
	tempo_begin(room)
	// With the defence keys up the world waits for the answer: the first move is the answer.
	if room.qte.kind == .None { elapsed = run_room_until_free(room, SIM_STEP, horizon, .Best); tempo_note(room, elapsed, horizon) }
	for move, k in path {
		if room.phase != .Combat || player_dead(room) || !player_free(room) && room.qte.kind == .None || elapsed >= horizon { break }
		if k == 0 { first = describe(room, move) }
		if k == 1 { second = describe(room, move) }
		if !play_move(room, move) { return NO_VALUE, .Refused, 0, first, second }
		if k == 0 { child = discrete_fingerprint(room) }
		elapsed += run_after_move(room, elapsed, horizon)
	}
	// The table keeps what the fast rule's playout gives from here on: the risk and the tempo run so far are this
	// branch's own.
	key := state_fingerprint(room) ~ u64(horizon*1000) ~ (u64(elapsed*1000) << 20)
	slot := &s.table[key & (TABLE_SLOTS-1)]
	own := try_tempo-try_risk
	if slot.used && slot.key == key { s.table_hits += 1; return slot.value+own, .Played, child, first, second }
	playout(room, &elapsed, horizon)
	value = evaluate(room, &s.facts, elapsed, try_risk)+try_tempo
	slot^ = {key = key, value = value-own, used = true}
	return value, .Played, child, first, second
}

// One node: a branch played, a parry's two halves weighed equally (the user's «media pesata»: a real hand gets its key
// in time half the times, a proposal).
@(private)
play_node :: proc(s: ^Search, path: []Move, horizon: f32) -> (value: f32, result: Path_Result, child: u64, first, second: Reply) {
	if path[0].kind == .Defend && path[0].defense == .Parry {
		lucky, missed: f32
		path[0].succeed = true
		lucky, result, child, first, second = play_path(s, path, horizon)
		if result == .Refused { return }
		path[0].succeed = false
		missed, _, _, _, _ = play_path(s, path, horizon)
		path[0].succeed = true
		return (lucky+missed)/2, result, child, first, second
	}
	return play_path(s, path, horizon)
}

// The nodes of the current round, how many.
@(private)
round_size :: proc(s: ^Search) -> int {
	switch ROUNDS[s.round].depth {
	case 1: return s.candidate_count
	case 2: return s.candidate_count*s.reply_count
	}
	return s.beam_count*BEAM*s.reply_count
}

// A round begins: its values from nothing, or, for the third move, the round of two's at this horizon, and the best
// three first moves with each its best three replies.
@(private)
begin_round :: proc(s: ^Search) {
	s.previous = s.values
	depth := ROUNDS[s.round].depth
	if depth == 2 {
		for &row in s.reply_values { for &v in row { v = NO_VALUE } }
		for i in 0..<s.candidate_count { s.values[i] = NO_VALUE }
	}
	if depth == 3 {
		s.beam_count = 0
		taken: [MAX_CANDIDATES]bool
		for b in 0..<BEAM {
			best := -1
			for i in 0..<s.candidate_count {
				if !s.legal[i] || taken[i] || s.previous[i] <= NO_VALUE { continue }
				if best < 0 || s.previous[i] > s.previous[best]+TIE { best = i }
			}
			if best < 0 { break }
			taken[best] = true
			s.beam[b] = best
			s.beam_count += 1
			s.beam_reply_count[b] = 0
			used: [MAX_CANDIDATES]bool
			for k in 0..<BEAM {
				reply := -1
				for j in 0..<s.reply_count {
					if used[j] || s.reply_values[best][j] <= NO_VALUE { continue }
					if reply < 0 || s.reply_values[best][j] > s.reply_values[best][reply]+TIE { reply = j }
				}
				if reply < 0 { break }
				used[reply] = true
				s.beam_replies[b][k] = reply
				s.beam_reply_count[b] += 1
			}
		}
	}
}

// Two values closer than this are equal: the first in the fixed order wins.
TIE :: f32(1e-3)

// A round over: the best first move is the advice.
@(private)
finish_round :: proc(s: ^Search) {
	round := ROUNDS[s.round]
	best := -1
	for i in 0..<s.candidate_count {
		if !s.legal[i] || s.values[i] <= NO_VALUE { continue }
		if best < 0 || s.values[i] > s.values[best]+TIE { best = i }
	}
	if best >= 0 {
		s.advice = {valid = true, kind = s.described[best].kind, move = s.candidates[best], cell = s.described[best].cell,
			value = s.values[best], depth = round.depth, horizon = round.horizon, nodes = s.nodes, root = s.advice.root}
	}
	s.round += 1
	s.cursor = 0
	if s.round == len(ROUNDS) || best < 0 { s.done = true; return }
	// The longer horizon starts its rounds afresh.
	if ROUNDS[s.round].horizon != round.horizon { s.values = {}; for &v in s.values { v = NO_VALUE } }
	begin_round(s)
}

// One node of the current round, in the fixed order.
@(private)
step_node :: proc(s: ^Search) {
	round := ROUNDS[s.round]
	path: [MAX_DEPTH]Move
	switch round.depth {
	case 1:
		i := s.cursor
		path[0] = s.candidates[i]
		value, result, child, first, _ := play_node(s, path[:1], round.horizon)
		s.legal[i] = result == .Played
		// What the first move is, for the marks, on the root as the move finds it.
		s.described[i] = first
		s.children[i] = child
		s.values[i] = value if s.legal[i] else NO_VALUE
	case 2:
		i, j := s.cursor/s.reply_count, s.cursor%s.reply_count
		if !s.legal[i] { return }
		path[0], path[1] = s.candidates[i], s.replies[j]
		value, result, _, _, second := play_node(s, path[:2], round.horizon)
		if result == .Refused { return }
		s.reply_values[i][j] = value
		s.reply_described[i][j] = second
		s.values[i] = max(s.values[i], value)
	case 3:
		per_beam := BEAM*s.reply_count
		b, rest := s.cursor/per_beam, s.cursor%per_beam
		k, j := rest/s.reply_count, rest%s.reply_count
		if k >= s.beam_reply_count[b] { return }
		i := s.beam[b]
		path[0], path[1], path[2] = s.candidates[i], s.replies[s.beam_replies[b][k]], s.replies[j]
		value, result, _, _, _ := play_node(s, path[:3], round.horizon)
		if result == .Refused { return }
		s.values[i] = max(s.values[i], value)
	}
	s.nodes += 1
	s.work += 2 if round.horizon > HORIZON_SHORT else 1
}

// Up to `work` of work (a node at the short horizon is one, at the long one two). Whether the search is over.
search_step :: proc(s: ^Search, work: int) -> bool {
	if !s.rooted { return true }
	start := s.work
	for !s.done && s.work-start < work {
		if s.cursor >= round_size(s) { finish_round(s); continue }
		step_node(s)
		s.cursor += 1
	}
	return s.done
}

// The best reply to every first move, from the round of two moves (for thinking ahead: search_pondered).
@(private)
best_reply :: proc(s: ^Search, i: int) -> (j: int, found: bool) {
	j = -1
	for r in 0..<s.reply_count {
		if s.reply_values[i][r] <= NO_VALUE { continue }
		if j < 0 || s.reply_values[i][r] > s.reply_values[i][j]+TIE { j = r }
	}
	return j, j >= 0
}

// THINKING AHEAD (pondering): the root's situation is the one right after a first move this search tried; its best
// reply is the advice at once, before the new root's first round.
search_pondered :: proc(s: ^Search, root: u64) -> (advice: Advice, found: bool) {
	if !s.rooted || s.round < 2 { return }
	for i in 0..<s.candidate_count {
		if !s.legal[i] || s.children[i] != root { continue }
		j := best_reply(s, i) or_continue
		reply := s.reply_described[i][j]
		return {valid = true, kind = reply.kind, move = s.replies[j], cell = reply.cell, value = s.reply_values[i][j],
			depth = 1, horizon = HORIZON_SHORT, root = root, pondered = true}, true
	}
	return
}

// The whole search on one root, at once (the tests, the tournament, the measures): `work` at most.
search_whole :: proc(s: ^Search, real: ^game.Room, work: int) -> Advice {
	if !search_root(s, real) { return {} }
	search_step(s, work)
	return s.advice
}

// THE FINGERPRINTS. The discrete one: what a player sees change (cells, life, energy, hand, foes and their intents,
// the beats, the defence keys); the pilot starts a new root when it changes. The state one adds the seconds (to the
// hundredth), for the table of the situations already seen.
@(private)
mix :: proc(h: ^u64, v: u64) { h^ = (h^ ~ v)*0x100000001b3 }

discrete_fingerprint :: proc(room: ^game.Room) -> u64 {
	h := u64(0xcbf29ce484222325)
	p := room.player
	mix(&h, u64(room.phase))
	mix(&h, u64(i64(p.position.x)) << 32 | u64(u32(p.position.y)))
	mix(&h, u64(p.position.layer))
	mix(&h, u64(u32(p.health)))
	mix(&h, u64(u32(p.deck.energy)))
	for card in p.deck.hand[:p.deck.hand_count] { mix(&h, u64(card.id)) }
	mix(&h, u64(p.tactical.dodge_recovery))
	mix(&h, u64(p.tactical.encounter_beats))
	mix(&h, room.pulse_count)
	mix(&h, u64(room.qte.kind) | u64(room.qte.selected) << 8 | u64(room.qte.progress) << 16 | u64(room.qte.enemy_id) << 32)
	for enemy in room.enemies {
		mix(&h, u64(enemy.id))
		mix(&h, u64(i64(enemy.position.x)) << 32 | u64(u32(enemy.position.y)))
		mix(&h, u64(u32(enemy.health)))
		mix(&h, u64(enemy.intent.kind) | u64(enemy.intent.windup) << 8)
		mix(&h, u64(i64(enemy.intent.destination.x)) << 32 | u64(u32(enemy.intent.destination.y)))
	}
	mix(&h, u64(len(room.loot)))
	return h
}

state_fingerprint :: proc(room: ^game.Room) -> u64 {
	h := discrete_fingerprint(room)
	p := room.player
	hundredth :: proc(v: f32) -> u64 { return u64(i64(v*100)) }
	mix(&h, u64(p.tactical.facing))
	mix(&h, hundredth(p.tactical.action_remaining))
	mix(&h, hundredth(p.tactical.clock_fraction))
	mix(&h, u64(p.tactical.queued_beats))
	mix(&h, u64(p.tactical.phase))
	mix(&h, hundredth(room.qte.remaining))
	for enemy in room.enemies { mix(&h, hundredth(enemy.tactical_cooldown) | u64(enemy.recovery_pulses) << 32) }
	return h
}
