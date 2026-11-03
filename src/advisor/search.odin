package advisor

import "base:runtime"
import game "../game"
import grid "../engine/grid"

// THE SEARCH (docs/piano-ia.md, Fasi 2 e 3, «Come sceglie»). From the snapshot of the real room it tries every first move
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
// The first moves: the board's 13, the refocus, an arrow at every foe, the hand's cards on their targets.
MAX_CANDIDATES :: 64
// The later moves: the board's 13, the refocus, and the card in every slot of the hand on its best target.
MAX_REPLIES :: 13+1+game.MAX_HAND_CAPACITY
// The same situation seen again (the transposition table): its slots.
TABLE_SLOTS :: 1 << 13

// THE REACTION MARGIN (docs/piano-ia.md, «Come ricalcola»): between the advice shown and the key pressed a real hand
// takes a moment. Every branch lets the world run this long after the player is free before its first move, so that
// an advice holds for a player who does not press at the very instant.
REACTION_SECONDS :: f32(0.15)

// The rounds, in order: every first move, every reply, the best three's third moves; then the same at the long horizon.
Round :: struct { depth: int, horizon: f32 }
@(rodata) ROUNDS := [?]Round{{1, HORIZON_SHORT}, {2, HORIZON_SHORT}, {3, HORIZON_SHORT}, {2, HORIZON_LONG}, {3, HORIZON_LONG}}

// What the advice says to do, for the marks.
Advice_Kind :: enum u8 { None, Step, Bump, Dodge, Diagonal, Wait, Defend, Key, Card, Refocus, Shoot, Activate, Equip }

Advice :: struct {
	valid: bool,
	kind: Advice_Kind,
	move: Move,
	// The cell to step or land on, the foe's to strike, the card's target.
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
	// The life its line loses by the horizon (a mean over dice and halves), and whether one of them dies.
	loss: f32,
	dies: bool,
}

@(private)
Table_Entry :: struct { key: u64, value: f32, loss: f32, dies, used: bool }

// What a move is for the marks, and the move itself as played (a hand slot's card made whole).
@(private)
Reply :: struct { kind: Advice_Kind, cell: grid.Position, move: Move }

// THINKING AHEAD: the situation right after a first move (its discrete fingerprint), the best reply to it, and what
// that first move loses in its best line (the warning, when the player does it against the advice).
Ponder :: struct { child: u64, advice: Advice, loss: f32, dies: bool }

Search :: struct {
	// Its own snapshot (search_root), and the one the rounds read: its own, or one lent by the worker (search_root_from).
	snapshot: Snapshot,
	source: ^Snapshot,
	rehearsal: Rehearsal,
	ready, rooted, done: bool,
	facts: Root_Facts,
	// The first moves (at the root) and the replies (every later move).
	candidates: [MAX_CANDIDATES]Move,
	candidate_count: int,
	replies: [MAX_REPLIES]Move,
	reply_count: int,
	// Every first move: whether the rules take it, what it is for the marks, the situation right after it.
	legal: [MAX_CANDIDATES]bool,
	described: [MAX_CANDIDATES]Reply,
	children: [MAX_CANDIDATES]u64,
	// This round's and the round before's values of every first move; the replies' values at the round of two moves.
	values, previous: [MAX_CANDIDATES]f32,
	// The life lost in the line that gave each first move its value, and whether it dies.
	losses: [MAX_CANDIDATES]f32,
	dies: [MAX_CANDIDATES]bool,
	// [first move][reply], in the process's own memory (reply_value, reply_reply).
	reply_values: []f32,
	reply_described: []Reply,
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
	// The dice that give each face (cards.odin).
	faces: Dice_Faces,
	// Thinking ahead, from the last round of two moves finished: every first move's situation and best reply.
	ponder: [MAX_CANDIDATES]Ponder,
	ponder_count: int,
}

@(private)
reply_value :: proc(s: ^Search, i, j: int) -> ^f32 { return &s.reply_values[i*MAX_REPLIES+j] }
@(private)
reply_reply :: proc(s: ^Search, i, j: int) -> ^Reply { return &s.reply_described[i*MAX_REPLIES+j] }

search_init :: proc(s: ^Search) -> bool {
	s^ = {}
	if !snapshot_init(&s.snapshot) { return false }
	if !rehearsal_init(&s.rehearsal) { snapshot_destroy(&s.snapshot); return false }
	heap := runtime.heap_allocator()
	table, failed := make([]Table_Entry, TABLE_SLOTS, heap)
	values, failed_values := make([]f32, MAX_CANDIDATES*MAX_REPLIES, heap)
	replies, failed_replies := make([]Reply, MAX_CANDIDATES*MAX_REPLIES, heap)
	if failed != nil || failed_values != nil || failed_replies != nil {
		delete(table, heap); delete(values, heap); delete(replies, heap)
		rehearsal_destroy(&s.rehearsal); snapshot_destroy(&s.snapshot)
		return false
	}
	s.table, s.reply_values, s.reply_described = table, values, replies
	dice_faces_find(&s.faces)
	s.ready = true
	return true
}

search_destroy :: proc(s: ^Search) {
	if !s.ready { return }
	rehearsal_destroy(&s.rehearsal)
	snapshot_destroy(&s.snapshot)
	heap := runtime.heap_allocator()
	delete(s.table, heap)
	delete(s.reply_values, heap)
	delete(s.reply_described, heap)
	s^ = {}
}

// The board's moves in their fixed order: wait first (the safe and the cheap), then the steps north, east, south,
// west (a step into a foe is the bump), the dodges, the diagonals.
@(private)
board_moves :: proc(out: []Move) -> (count: int) {
	out[count] = {kind = .Wait}; count += 1
	for direction in game.Move_Direction { out[count] = {kind = .Step, direction = direction}; count += 1 }
	for direction in game.Move_Direction { out[count] = {kind = .Dodge, direction = direction}; count += 1 }
	for offset in ([4]grid.Position{{x = -1, y = -1}, {x = 1, y = -1}, {x = -1, y = 1}, {x = 1, y = 1}}) {
		out[count] = {kind = .Diagonal, offset = offset}; count += 1
	}
	return
}

// The first moves of a root: with the defence keys up, every defence the player has (the dodge in every direction);
// with a key awaited, the key; else the board's moves, then the refocus, an arrow at every foe (Feretro's charges), and
// the hand's cards on their targets, the cheaper first (cards.odin). At equal worth the first wins: no card, then the
// cheaper card.
@(private)
root_moves :: proc(room: ^game.Room, out: []Move) -> (count: int) {
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
	case game.tactical_shadow_active(room):
		// MOVIMENTO OMBRA: the world stands still; the shadow steps, or its seconds run out where it stands.
		out[count] = {kind = .Wait}; count += 1
		for direction in game.Move_Direction { out[count] = {kind = .Step, direction = direction}; count += 1 }
	case:
		count = board_moves(out)
		out[count] = {kind = .Refocus}; count += 1
		// The Tesla coils on the board, the reserve weapon: when there are.
		for object in room.objects {
			if object.kind == .Tesla_Coil { out[count] = {kind = .Activate}; count += 1; break }
		}
		if room.player.equipment.reserve.id != .None { out[count] = {kind = .Equip}; count += 1 }
		if game.player_charges(room, .Arrows) > 0 {
			for enemy in room.enemies {
				if count == len(out) { break }
				out[count] = {kind = .Shoot, target = game.entity_target(game.enemy_entity(enemy.id))}; count += 1
			}
		}
		count += card_plays(room, out[count:])
	}
	return
}

// The later moves: the board's, the refocus, the card in every slot of the hand.
@(private)
reply_moves :: proc(out: []Move) -> (count: int) {
	count = board_moves(out)
	out[count] = {kind = .Refocus}; count += 1
	for slot in 1..=game.MAX_HAND_CAPACITY { out[count] = {kind = .Card, slot = i8(slot)}; count += 1 }
	return
}

// A new root: the real room photographed (only read), the rehearsal on it, the rounds from the first.
search_root :: proc(s: ^Search, real: ^game.Room, game_context: Game_Context = {}) -> bool {
	if !s.ready || !snapshot_take(&s.snapshot, real, game_context) { s.rooted = false; return false }
	return search_root_from(s, &s.snapshot)
}

// A new root on a snapshot already taken (the worker's, taken by the game's thread): read only, and kept as it is until
// the next root.
search_root_from :: proc(s: ^Search, snapshot: ^Snapshot) -> bool {
	if !s.ready || !rehearsal_begin(&s.rehearsal, snapshot) { s.rooted = false; return false }
	s.source = snapshot
	s.rooted, s.done = true, false
	s.facts = root_facts(&snapshot.room, snapshot.game_context)
	// The first moves are those of the moment the player is free again (a root is often taken while his last move
	// still plays, when the rules let no card be played): on a rehearsal run on to it, as every branch runs.
	{
		room := rehearsal_room(&s.rehearsal)
		context.allocator = try_allocator(&s.rehearsal)
		context.temp_allocator = context.allocator
		room.player.dice = game.make_dice_state(DICE_SEED)
		reach_root(room, HORIZON_LONG)
		s.candidate_count = root_moves(room, s.candidates[:])
	}
	s.reply_count = reply_moves(s.replies[:])
	s.round, s.cursor, s.nodes, s.work, s.table_hits = 0, 0, 0, 0, 0
	s.legal = {}
	s.described = {}
	s.children = {}
	s.ponder_count = 0
	for &entry in s.table { entry = {} }
	for &v in s.values { v = NO_VALUE }
	s.previous = s.values
	s.advice = {root = discrete_fingerprint(&snapshot.room)}
	return true
}

// The world run on from the root to its first move: until the player is free, then the reaction margin. With the
// defence keys up the world waits for the answer: nothing runs. The seconds it ran.
@(private)
reach_root :: proc(room: ^game.Room, horizon: f32) -> (ran: f32) {
	if room.qte.kind != .None { return }
	ran = run_room_until_free(room, SIM_STEP, horizon, .Best)
	for margin := f32(0); margin < REACTION_SECONDS && ran < horizon && room.phase == .Combat && !player_dead(room); margin += SIM_STEP {
		if room.qte.kind != .None { break }
		frame_room(room, SIM_STEP, .Best)
		ran += SIM_STEP
	}
	return
}

// A branch not played: a move the rules refused, or a slot no round filled.
NO_VALUE :: f32(-1e30)

// What a move is, for the marks, on the room where it is about to be played (the move kept with it).
describe :: proc(room: ^game.Room, move: Move) -> (reply: Reply) {
	reply = describe_kind(room, move)
	reply.move = move
	return
}

@(private)
describe_kind :: proc(room: ^game.Room, move: Move) -> (reply: Reply) {
	p := room.player.position
	// In the shadow the steps are the shadow's.
	if game.tactical_shadow_active(room) { p = room.player.tactical.shadow_position }
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
	case .Card: return {kind = .Card, cell = target_cell(room, move.target), move = move}
	case .Refocus: return {kind = .Refocus, cell = p, move = move}
	case .Shoot: return {kind = .Shoot, cell = target_cell(room, move.target), move = move}
	case .Activate: return {kind = .Activate, cell = p, move = move}
	case .Equip: return {kind = .Equip, cell = p, move = move}
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

// A branch played: its value, the life it lost by the horizon and whether the player died; the situation right after
// the first move; what the first two moves are, for the marks.
@(private)
Path :: struct {
	value, loss: f32,
	dies: bool,
	result: Path_Result,
	child: u64,
	first, second: Reply,
}

// One branch on a fresh rehearsal: its moves (the first may be refused: then the branch is not one), then the fast rule
// to the horizon. The try rolls `dice`, never the player's own (the IA does not know the faces).
@(private)
play_path :: proc(s: ^Search, path: []Move, horizon: f32, dice: game.Dice_State) -> (out: Path) {
	room := rehearsal_room(&s.rehearsal)
	context.allocator = try_allocator(&s.rehearsal)
	context.temp_allocator = context.allocator
	room.player.dice = dice
	try_risk = 0
	try_life_weight = s.facts.life_weight
	tempo_begin(room)
	// With the defence keys up the world waits for the answer: the first move is the answer.
	elapsed := reach_root(room, horizon)
	tempo_note(room, elapsed, horizon)
	refocused := false
	for planned, k in path {
		if room.phase != .Combat || player_dead(room) || !player_free(room) && room.qte.kind == .None || elapsed >= horizon { break }
		move := planned
		// A hand slot's card: the card there now, on its best target; an empty slot is no move.
		if move.slot > 0 {
			resolved, ok := resolve_slot(room, move)
			if !ok { out.value, out.result = NO_VALUE, .Refused; return }
			move = resolved
		}
		if k == 0 { out.first = describe(room, move) }
		if k == 0 { refocused = move.kind == .Refocus }
		if k == 1 { out.second = describe(room, move) }
		if !play_move(room, move) { out.value, out.result = NO_VALUE, .Refused; return }
		if k == 0 { out.child = discrete_fingerprint(room) }
		elapsed += run_after_move(room, elapsed, horizon)
	}
	// Turning the hand first gives a beat away: what can be done now, a kill, a step out of a line, comes before it. A device
	// fetched that way counts for what it does within the horizon, not for what it will do past it.
	if refocused { try_risk += max(objects_value(room)-s.facts.devices, 0) }
	// The table keeps what the fast rule's playout gives from here on: the risk and the tempo run so far are this
	// branch's own.
	key := state_fingerprint(room) ~ u64(horizon*1000) ~ (u64(elapsed*1000) << 20)
	slot := &s.table[key & (TABLE_SLOTS-1)]
	own := try_tempo-try_risk
	if slot.used && slot.key == key {
		s.table_hits += 1
		out.value, out.loss, out.dies = slot.value+own, slot.loss, slot.dies
		return
	}
	playout(room, &elapsed, horizon)
	out.value = evaluate(room, &s.facts, elapsed, try_risk)+try_tempo
	out.loss = f32(s.facts.health-max(0, room.player.health))
	out.dies = player_dead(room)
	slot^ = {key = key, value = out.value-own, loss = out.loss, dies = out.dies, used = true}
	return
}

// One node: a branch played. A parry's two halves are weighed equally (the user's «media pesata»: a real hand gets its
// key in time half the times, a proposal); a first card with dice is played on every face of its die (or on fixed
// rolls of its dice) and the ways weighed equally. How many tries it took.
@(private)
play_node :: proc(s: ^Search, path: []Move, horizon: f32) -> (out: Path, tries: int) {
	neutral := game.make_dice_state(DICE_SEED)
	if path[0].kind == .Defend && path[0].defense == .Parry {
		path[0].succeed = true
		out = play_path(s, path, horizon, neutral)
		if out.result == .Refused { return out, 1 }
		path[0].succeed = false
		missed := play_path(s, path, horizon, neutral)
		path[0].succeed = true
		out.value, out.loss, out.dies = (out.value+missed.value)/2, (out.loss+missed.loss)/2, out.dies || missed.dies
		return out, 2
	}
	ways, sides, many := dice_ways(&s.source.room, path[0], &s.faces)
	if ways <= 1 { return play_path(s, path, horizon, neutral), 1 }
	value, loss: f32
	for k in 0..<ways {
		way := play_path(s, path, horizon, dice_way(&s.faces, k, sides, many))
		if way.result == .Refused { way.value = NO_VALUE; return way, k+1 }
		if k == 0 { out = way }
		value += way.value
		loss += way.loss
		out.dies = out.dies || way.dies
	}
	out.value, out.loss = value/f32(ways), loss/f32(ways)
	return out, ways
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
		for &v in s.reply_values { v = NO_VALUE }
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
			used: [MAX_REPLIES]bool
			for k in 0..<BEAM {
				reply := -1
				for j in 0..<s.reply_count {
					if used[j] || reply_value(s, best, j)^ <= NO_VALUE { continue }
					if reply < 0 || reply_value(s, best, j)^ > reply_value(s, best, reply)^+TIE { reply = j }
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
			value = s.values[best], depth = round.depth, horizon = round.horizon, nodes = s.nodes, root = s.advice.root,
			loss = s.losses[best], dies = s.dies[best]}
	}
	// A round of two moves over: the best reply to every first move, ready for thinking ahead.
	if round.depth == 2 {
		s.ponder_count = 0
		for i in 0..<s.candidate_count {
			if !s.legal[i] || s.children[i] == 0 { continue }
			j := best_reply(s, i) or_continue
			reply := reply_reply(s, i, j)^
			s.ponder[s.ponder_count] = {child = s.children[i], advice = {valid = true, kind = reply.kind, move = reply.move,
				cell = reply.cell, value = reply_value(s, i, j)^, depth = 1, horizon = round.horizon, root = s.children[i], pondered = true},
				loss = s.losses[i], dies = s.dies[i]}
			s.ponder_count += 1
		}
	}
	s.round += 1
	s.cursor = 0
	if s.round == len(ROUNDS) || best < 0 { s.done = true; return }
	// The longer horizon starts its rounds afresh.
	if ROUNDS[s.round].horizon != round.horizon { s.values = {}; for &v in s.values { v = NO_VALUE } }
	begin_round(s)
}

// A first move's value raised by a deeper line, and that line's loss kept with it.
@(private)
improve :: proc(s: ^Search, i: int, out: Path) {
	if out.value <= s.values[i] { return }
	s.values[i], s.losses[i], s.dies[i] = out.value, out.loss, out.dies
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
		out, tries := play_node(s, path[:1], round.horizon)
		s.work += tries*(2 if round.horizon > HORIZON_SHORT else 1)
		s.legal[i] = out.result == .Played
		// What the first move is, for the marks, on the root as the move finds it.
		s.described[i] = out.first
		s.children[i] = out.child
		s.values[i] = out.value if s.legal[i] else NO_VALUE
		s.losses[i], s.dies[i] = out.loss, out.dies
	case 2:
		i, j := s.cursor/s.reply_count, s.cursor%s.reply_count
		if !s.legal[i] { return }
		path[0], path[1] = s.candidates[i], s.replies[j]
		out, tries := play_node(s, path[:2], round.horizon)
		s.work += tries*(2 if round.horizon > HORIZON_SHORT else 1)
		if out.result == .Refused { return }
		reply_value(s, i, j)^ = out.value
		reply_reply(s, i, j)^ = out.second
		improve(s, i, out)
	case 3:
		per_beam := BEAM*s.reply_count
		b, rest := s.cursor/per_beam, s.cursor%per_beam
		k, j := rest/s.reply_count, rest%s.reply_count
		if k >= s.beam_reply_count[b] { return }
		i := s.beam[b]
		path[0], path[1], path[2] = s.candidates[i], s.replies[s.beam_replies[b][k]], s.replies[j]
		out, tries := play_node(s, path[:3], round.horizon)
		s.work += tries*(2 if round.horizon > HORIZON_SHORT else 1)
		if out.result == .Refused { return }
		improve(s, i, out)
	}
	s.nodes += 1
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
		if reply_value(s, i, r)^ <= NO_VALUE { continue }
		if j < 0 || reply_value(s, i, r)^ > reply_value(s, i, j)^+TIE { j = r }
	}
	return j, j >= 0
}

// THINKING AHEAD (pondering): the root's situation is the one right after a first move this search tried; its best
// reply is the advice at once, before the new root's first round.
search_pondered :: proc(s: ^Search, root: u64) -> (advice: Advice, found: bool) {
	if !s.rooted { return }
	return ponder_lookup(s.ponder[:s.ponder_count], root)
}

ponder_lookup :: proc(table: []Ponder, root: u64) -> (advice: Advice, found: bool) {
	for entry in table { if entry.child == root { return entry.advice, true } }
	return
}

// The whole search on one root, at once (the tests, the tournament, the measures): `work` at most.
search_whole :: proc(s: ^Search, real: ^game.Room, work: int, game_context: Game_Context = {}) -> Advice {
	if !search_root(s, real, game_context) { return {} }
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
	// The dice a try rolls (its own, never the player's): the same situation with other dice plays otherwise.
	mix(&h, p.dice.random_state)
	mix(&h, p.dice.roll_count)
	for enemy in room.enemies { mix(&h, hundredth(enemy.tactical_cooldown) | u64(enemy.recovery_pulses) << 32) }
	return h
}
