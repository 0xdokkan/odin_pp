package game

import "core:math"
import grid "../engine/grid"

// LAZZO. The card's two seconds are the throw (a cast, the world still): the
// rope catches one foe within LASSO_RANGE cells (the game's Chebyshev range),
// in sight and in the line the cards trace, lifts it off the floor and pulls
// it onto its ring around the player. Every enemy archetype can be caught,
// including bosses and minibosses; range and line of sight still apply.
//
// The ring of radius r is every cell a true circle of r cells around the
// centre of the player's cell passes through (lasso_ring): 8r cells, each an
// arc of the circle, each next a side neighbour of the one before. The radius
// is fixed at the throw: the largest from LASSO_MAX_RADIUS down to 1 whose own
// ring holds no solid cell (a wall, the room's edge, cover, a blocking object;
// the foe flies over whatever stands inside its ring). A wall four cells away
// in a straight line gives 3. When even the first ring holds one (the player
// beside a wall, every ring crossing it) the radius is 1 and the swung foe
// smashes into the solid cells it meets: the only way it ever touches one.
//
// The spin starts at the foe's own direction from the player and turns
// counter-clockwise (on a north-up map), speeding up as a lasso does: the
// first turn takes LASSO_FIRST_TURN_SECONDS, each next one LASSO_TURN_SPEEDUP
// of the one before, never faster than LASSO_FASTEST_TURN_SECONDS (8 turns a
// second, from the 17th; a lone unhurt foe of 60 falls after 60 turns, in
// 12.03 s). It runs on the world's own seconds: the window, the enemies'
// intents and blows, Bruciatura and the fires go on all the while, and only
// what stops the world (a cast, a defence prompt, a cinematic die, a pause)
// stops it too. The spin is stepped from one event to the next (a cell's edge,
// a full turn), never by frames: no cell, hit or smash is skipped at any speed.
//
// Each contact advances this lasso's strength n (the card's amount, then one
// more each time). When the swung foe enters a ring cell holding another foe,
// both take n, the player's damage, and the struck one is knocked back n cells
// radially away from the player (snapped to the eight directions) under the
// game's push rules: a wall, an obstacle or an actor stops it, and pools,
// fires and traps act on every cell it enters. A smash is a hit n too, on the
// swung foe alone, and the spin bounces back. Every full turn (2 pi of travel,
// either way) takes LASSO_TURN_DAMAGE from it.
// Inside the ring the rope pushes to the first ring cell along that radial
// direction, stopping earlier if blocked, regardless of the hit's strength.
// Neither foe takes direct damage and there is no damage/reaction cue. Ground
// effects along the push still apply. Each interior foe is swept once per
// turn; being pushed onto the ring cannot make that same pass a damaging hit.
//
// The player is its pivot and is busy: no steps, bumps, cards or arrows while
// it spins (and, as ever, nothing is kept for later). Enemy blows reach him as
// usual, with the defence prompt and RIFLESSO. Any move of his (a dodge, the
// prompt's dodge, a push, a teleport) lets go (release_lasso): the foe falls on
// the cell under it, or the nearest free one, and starts a fresh intent with no
// daze (in the middle of a beat, as that beat ends). While held it is in the
// air (enemy_index_at finds it on no cell): it takes no action (so its Veleno
// never bites and its Rallentamento never wears), nothing on the floor reaches
// it (pools, fires, traps, shock floors, explosions, the room's hazard), others
// walk under it; Bruciatura still bites at each new window. The rope holds
// until it dies: then it goes slack and the body falls (a normal death, the
// room cleared if it was the last foe).

LASSO_RANGE :: 4
LASSO_MAX_RADIUS :: i32(4)
LASSO_MAX_RING_CELLS :: 8*int(LASSO_MAX_RADIUS)
LASSO_MAX_UPGRADE_LEVEL :: i32(5)
// The speed of the spin: the first turn's seconds, each next turn this share
// of the one before (12% faster), down to the fastest.
LASSO_FIRST_TURN_SECONDS :: f64(0.9)
LASSO_TURN_SPEEDUP :: f64(0.88)
LASSO_FASTEST_TURN_SECONDS :: f64(0.125)
LASSO_TURN_DAMAGE :: i32(1)
LASSO_EPSILON :: f64(1e-9)
// A spin batch reserves room for the ring contact plus every interior foe
// sharing that direction (at most radius contacts). Each reserves two wounds
// and their guards, a push and its cell effects, a fall and its loot.
LASSO_EVENT_HEADROOM :: 96*int(LASSO_MAX_RADIUS)
LASSO_MAX_SWEEP_TARGETS :: (2*int(LASSO_MAX_RADIUS)+1)*(2*int(LASSO_MAX_RADIUS)+1)
// A guard on one batch's steps (each crosses one edge or one turn at most).
LASSO_MAX_STEPS :: 100_000
// Where the planner sees a foe held in the air: on no cell of any board.
LASSO_NO_CELL :: grid.Position{x = -1000, y = -1000}

// One cell of a ring: its offset from the player's cell and the angles where
// the circle enters and leaves it (radians, `to` above `from`; the arc
// through angle 0 is the ring's last and ends past 2 pi).
Lasso_Arc :: struct {
	cell: grid.Position,
	from, to: f64,
}

Lasso_State :: struct {
	active: bool,
	enemy_id: u32,
	// The player's cell at the throw (he never leaves it while it holds), the
	// ring's radius and whether its first ring was walled (smashes).
	centre: grid.Position,
	radius: i32,
	smash: bool,
	arcs: [LASSO_MAX_RING_CELLS]Lasso_Arc,
	arc_count: int,
	// The arc the swung foe is over, how far along it (0 at `from`, 1 at
	// `to`) and its way round: +1 the angle growing (clockwise on a north-up
	// map), -1 shrinking.
	arc: int,
	along: f64,
	direction: i32,
	// Full turns made, the radians left of the current one, the hits so far
	// and the first hit's number.
	turns, hits, first_hit: i32,
	turn_left: f64,
	// World seconds not spun yet (tactical_lasso_tick), and whether the spin
	// has begun (its first batch enters the cell the foe was pulled onto).
	pending: f64,
	started: bool,
	// Where the rope caught it.
	caught_from: grid.Position,
	// Interior contacts in this turn. The disk fits in this many board cells;
	// an outward push must not immediately hit the same foe again.
	swept_ids: [LASSO_MAX_SWEEP_TARGETS]u32,
	swept_count: int,
}

@(private)
lasso_effect :: proc(target: Entity_Ref, first_hit: i32) -> Effect {
	return {kind = .Lasso, target = target, amount = first_hit}
}

// A foe the Lazzo holds in the air.
enemy_is_lassoed :: proc(room: ^Room, id: u32) -> bool {
	return room != nil && room.lasso.active && id != 0 && room.lasso.enemy_id == id
}

tactical_lasso_active :: proc(room: ^Room) -> bool {
	return room != nil && room.lasso.active && room.phase == .Combat
}

lasso_wrap :: proc(angle: f64) -> f64 {
	a := math.mod(angle, math.TAU)
	if a < 0 { a += math.TAU }
	return a
}

// The ring of `radius`: its 8*radius arcs in order of angle (x to the east,
// y to the south), from the first after angle 0. The circle crosses a cell's
// edge where x or y is a half integer; it never passes a corner (the sum of
// two odd squares is never 4r^2), so each cell is one arc and each next cell
// a side neighbour.
lasso_ring :: proc(radius: i32) -> (arcs: [LASSO_MAX_RING_CELLS]Lasso_Arc, count: int) {
	if radius < 1 || radius > LASSO_MAX_RADIUS { return }
	r := f64(radius)
	crossings: [LASSO_MAX_RING_CELLS]f64
	n := 0
	for k in 0..<int(radius) {
		for side in ([2]f64{-1, 1}) {
			edge := (f64(k)+0.5)*side
			x := math.acos(edge/r)
			y := math.asin(edge/r)
			for angle in ([4]f64{x, -x, y, math.PI-y}) {
				crossings[n] = lasso_wrap(angle)
				n += 1
			}
		}
	}
	for index in 1..<n {
		value := crossings[index]
		at := index
		for at > 0 && crossings[at-1] > value {
			crossings[at] = crossings[at-1]
			at -= 1
		}
		crossings[at] = value
	}
	for index in 0..<n {
		from := crossings[index]
		to := crossings[(index+1)%n]
		if index == n-1 { to += math.TAU }
		middle := (from+to)*0.5
		arcs[index] = {cell = {x = int(math.floor(r*math.cos(middle)+0.5)), y = int(math.floor(r*math.sin(middle)+0.5))}, from = from, to = to}
	}
	return arcs, n
}

// A cell the rope's foe cannot pass: off the board, a wall or the void, cover,
// a blocking object.
lasso_cell_is_solid :: proc(room: ^Room, cell: grid.Position) -> bool {
	return room == nil || room.level_data == nil || !grid.contains(&room.level_data.tiles, cell) || cell_blocks_movement(room, cell)
}

@(private = "file")
lasso_ring_is_clear :: proc(room: ^Room, centre: grid.Position, radius: i32) -> bool {
	arcs, count := lasso_ring(radius)
	for arc in arcs[:count] {
		if lasso_cell_is_solid(room, add_position(centre, arc.cell)) { return false }
	}
	return true
}

// The radius a lasso thrown from `centre` spins at: the largest, from
// LASSO_MAX_RADIUS down to 1, whose own ring holds no solid cell; when every
// ring holds one, 1 and `smash`.
lasso_radius :: proc(room: ^Room, centre: grid.Position) -> (radius: i32, smash: bool) {
	for r := LASSO_MAX_RADIUS; r >= 1; r -= 1 {
		if lasso_ring_is_clear(room, centre, r) { return r, false }
	}
	return 1, true
}

// The arc of the ring that holds `angle`, and how far along it.
lasso_locate :: proc(arcs: []Lasso_Arc, angle: f64) -> (arc: int, along: f64) {
	theta := lasso_wrap(angle)
	for a, index in arcs {
		t := theta if theta >= a.from else theta+math.TAU
		if t >= a.from && t < a.to { return index, (t-a.from)/(a.to-a.from) }
	}
	return max(len(arcs)-1, 0), 0.5
}

// The board cell under arc `index` of the ring.
lasso_arc_cell :: proc(state: ^Lasso_State, index: int) -> grid.Position {
	if state.arc_count <= 0 { return state.centre }
	return add_position(state.centre, state.arcs[(index%state.arc_count+state.arc_count)%state.arc_count].cell)
}

// The free arc nearest arc `from` along the ring, the spin's way first on a
// tie (`direction`); not ok when every cell of the ring is solid.
lasso_nearest_free_arc :: proc(room: ^Room, state: ^Lasso_State, from: int, direction: i32) -> (arc: int, ok: bool) {
	n := state.arc_count
	if n <= 0 { return }
	if !lasso_cell_is_solid(room, lasso_arc_cell(state, from)) { return from, true }
	for step in 1..<n {
		for way in ([2]int{int(direction), -int(direction)}) {
			candidate := ((from+way*step)%n+n)%n
			if !lasso_cell_is_solid(room, lasso_arc_cell(state, candidate)) { return candidate, true }
		}
	}
	return
}

// Why the Lazzo cannot take `target` now (.None: it can): no foe, a rope
// already out, or a ring with no free cell to swing it on.
lasso_target_error :: proc(room: ^Room, target: Target) -> Card_Compile_Error {
	if room == nil || room.player == nil || room.level_data == nil { return .Invalid_Room }
	if target.kind != .Entity || target.entity.kind != .Enemy { return .Invalid_Target }
	_, found := enemy_index_by_id(room, target.entity.id)
	if !found || enemy_is_out_of_play(room, target.entity.id) { return .Invalid_Target }
	if room.lasso.active { return .Target_Blocked }
	state: Lasso_State
	state.centre = room.player.position
	state.radius, state.smash = lasso_radius(room, state.centre)
	state.arcs, state.arc_count = lasso_ring(state.radius)
	if _, free := lasso_nearest_free_arc(room, &state, 0, -1); !free { return .Target_Blocked }
	return .None
}

// The throw (apply_effect): the foe off the floor and onto its ring, at its
// own direction from the player, its intent dropped; the spin begins with the
// world's next seconds.
@(private)
begin_lasso :: proc(room: ^Room, target: Entity_Ref, first_hit: i32, report: ^Action_Report) -> bool {
	if report == nil || lasso_target_error(room, entity_target(target)) != .None { return false }
	index, _ := enemy_index_by_id(room, target.id)
	enemy := &room.enemies[index]
	state := Lasso_State{active = true, enemy_id = enemy.id, centre = room.player.position, direction = -1,
		first_hit = max(i32(1), first_hit), turn_left = math.TAU, caught_from = enemy.position}
	state.radius, state.smash = lasso_radius(room, state.centre)
	state.arcs, state.arc_count = lasso_ring(state.radius)
	angle := math.atan2(f64(enemy.position.y-state.centre.y), f64(enemy.position.x-state.centre.x))
	state.arc, state.along = lasso_locate(state.arcs[:state.arc_count], angle)
	if lasso_cell_is_solid(room, lasso_arc_cell(&state, state.arc)) {
		free, ok := lasso_nearest_free_arc(room, &state, state.arc, state.direction)
		if !ok { return false }
		state.arc, state.along = free, 0.5
	}
	enemy.position = lasso_arc_cell(&state, state.arc)
	enemy.intent, enemy.tactical_cooldown = {}, 0
	enemy.aim_ready, enemy.bomb_ready = false, false
	room.lasso = state
	// He turns to face the foe he throws at.
	dx, dy := state.caught_from.x-state.centre.x, state.caught_from.y-state.centre.y
	if abs(dx) > abs(dy) { room.player.tactical.facing = .East if dx > 0 else .West }
	else { room.player.tactical.facing = .South if dy > 0 else .North }
	record_report_event(report, {kind = .Lasso_Caught, source = PLAYER_ENTITY, target = target,
		from_position = state.caught_from, to_position = enemy.position, amount = state.radius,
		duration = state.first_hit, card_definition = .Lasso})
	return true
}

// The seconds of turn number `turns` (0: the first).
lasso_turn_seconds :: proc(turns: i32) -> f64 {
	return max(LASSO_FASTEST_TURN_SECONDS, LASSO_FIRST_TURN_SECONDS*math.pow(LASSO_TURN_SPEEDUP, f64(max(turns, 0))))
}

// The swung foe's angle round the player now (radians, [0, 2 pi)).
lasso_angle :: proc(state: ^Lasso_State) -> f64 {
	if state.arc_count <= 0 { return 0 }
	arc := state.arcs[state.arc]
	return lasso_wrap(arc.from+clamp(state.along, 0, 1)*(arc.to-arc.from))
}

// The hit number the next foe struck (or the next smash) gets.
lasso_next_hit :: proc(state: ^Lasso_State) -> i32 {
	return state.first_hit+state.hits
}

// World seconds for the spin (tactical_tick, with the world's own).
@(private)
tactical_lasso_tick :: proc(room: ^Room, seconds: f32) {
	if !tactical_lasso_active(room) || !(seconds > 0) { return }
	room.lasso.pending += f64(seconds)
}

// Seconds wait to be spun, and nothing holds the world: the controller commits
// the spin (resolve_lasso_spin) as a world command, as it does a beat.
tactical_lasso_due :: proc(room: ^Room) -> bool {
	return tactical_lasso_active(room) && room.player != nil && !room.tactical_pulse.pending &&
	       room.qte.kind == .None && room.player.tactical.cast_remaining <= 0 && room.lasso.pending > LASSO_EPSILON
}

// The seconds waiting, spun out into room.recent_events: every edge crossed,
// every foe struck, every smash and every full turn, in order. A batch that
// comes near a full log leaves the rest for the next.
resolve_lasso_spin :: proc(room: ^Room) -> bool {
	if !tactical_lasso_due(room) { return false }
	clear_event_log(room.recent_events)
	if !room.lasso.started {
		room.lasso.started = true
		lasso_enter(room)
	}
	for steps := 0; steps < LASSO_MAX_STEPS && tactical_lasso_active(room) && room.lasso.pending > LASSO_EPSILON &&
	    room.recent_events.count <= MAX_GAME_EVENTS-LASSO_EVENT_HEADROOM; steps += 1 {
		lasso_step(room)
	}
	collect_loot_in_magnet_range(room)
	if room.phase != .Combat {
		sync_deck_with_room_phase(room)
		tactical_end_combat(room)
	}
	return true
}

// One step of the spin: up to the next edge of its cell, the end of its turn
// or the seconds waiting, whichever comes first. The angular speed is the
// turn's own throughout.
@(private = "file")
lasso_step :: proc(room: ^Room) {
	s := &room.lasso
	omega := math.TAU/lasso_turn_seconds(s.turns)
	arc := s.arcs[s.arc]
	span := arc.to-arc.from
	to_edge := (1-s.along)*span if s.direction > 0 else s.along*span
	to_sweep, _, _ := lasso_next_sweep(room)
	step := min(to_edge, to_sweep, s.turn_left, omega*s.pending)
	edge := to_edge-step <= LASSO_EPSILON
	turn := s.turn_left-step <= LASSO_EPSILON
	s.along = clamp(s.along+f64(s.direction)*step/span, 0, 1)
	s.turn_left -= step
	s.pending = max(0, s.pending-step/omega)
	if turn {
		s.turns += 1
		s.turn_left = math.TAU
		s.swept_count = 0
		lasso_turn_damage(room)
		if !tactical_lasso_active(room) { return }
	}
	if edge { lasso_cross_edge(room) }
	// At most radius-1 interior cells share a direction. Resolve all contacts
	// at this angle, even if this frame ended exactly on it.
	for _ in 0..<int(LASSO_MAX_RADIUS) {
		if !tactical_lasso_active(room) { return }
		distance, id, _ := lasso_next_sweep(room)
		if distance > LASSO_EPSILON { break }
		assert(s.swept_count < len(s.swept_ids))
		s.swept_ids[s.swept_count] = id
		s.swept_count += 1
		// Contacts still build strength, but an interior push ends at the
		// ring regardless of that strength, without damage or a hit cue.
		s.hits += 1
		lasso_knock_back(room, id, s.radius, stop_on_ring = true)
	}
}

@(private = "file")
lasso_cell_on_ring :: proc(state: ^Lasso_State, cell: grid.Position) -> bool {
	offset := grid.offset(cell, -state.centre.x, -state.centre.y)
	for arc in state.arcs[:state.arc_count] { if arc.cell == offset { return true } }
	return false
}

// The next interior foe crossed by the rotating rope. Ring cells retain
// their original edge-contact rule; inside it the ray crosses cell centres.
// Equal-angle contacts run farthest first so their radial pushes can clear
// a path for the closer foe, independently of the enemy array's order.
@(private = "file")
lasso_next_sweep :: proc(room: ^Room) -> (distance: f64, id: u32, cell: grid.Position) {
	s := &room.lasso
	distance = math.TAU+1
	angle := lasso_angle(s)
	farthest := 0
	for enemy in room.enemies {
		if enemy_is_out_of_play(room, enemy.id) { continue }
		if lasso_was_swept(s, enemy.id) { continue }
		dx, dy := enemy.position.x-s.centre.x, enemy.position.y-s.centre.y
		range_squared := dx*dx+dy*dy
		if range_squared == 0 || range_squared >= int(s.radius*s.radius) { continue }
		if lasso_cell_on_ring(s, enemy.position) { continue }
		to_enemy := lasso_wrap(f64(s.direction)*(math.atan2(f64(dy), f64(dx))-angle))
		if math.TAU-to_enemy <= LASSO_EPSILON { to_enemy = 0 }
		if to_enemy < distance-LASSO_EPSILON ||
		   (abs(to_enemy-distance) <= LASSO_EPSILON && (range_squared > farthest || (range_squared == farthest && enemy.id < id))) {
			distance, id, cell, farthest = to_enemy, enemy.id, enemy.position, range_squared
		}
	}
	return
}

@(private = "file")
lasso_was_swept :: proc(state: ^Lasso_State, id: u32) -> bool {
	for struck in state.swept_ids[:state.swept_count] { if struck == id { return true } }
	return false
}

// The swung foe reaches the edge of its cell: the next cell along its way, or
// a smash into it and the bounce back when it is solid.
@(private = "file")
lasso_cross_edge :: proc(room: ^Room) {
	s := &room.lasso
	next := ((s.arc+int(s.direction))%s.arc_count+s.arc_count)%s.arc_count
	cell := lasso_arc_cell(s, next)
	if lasso_cell_is_solid(room, cell) {
		lasso_smash(room, cell)
		if !tactical_lasso_active(room) { return }
		s.direction = -s.direction
		s.along = 1 if s.direction < 0 else 0
		return
	}
	s.arc = next
	s.along = 0 if s.direction > 0 else 1
	lasso_enter(room)
}

// The swung foe over a new cell: its place on the board (the cell under it)
// follows, and a foe standing there is struck.
@(private = "file")
lasso_enter :: proc(room: ^Room) {
	s := &room.lasso
	cell := lasso_arc_cell(s, s.arc)
	swung, found := enemy_index_by_id(room, s.enemy_id)
	if !found {
		room.lasso = {}
		return
	}
	room.enemies[swung].position = cell
	if other, struck := enemy_index_at(room, cell); struck && !lasso_was_swept(s, room.enemies[other].id) {
		lasso_strike(room, room.enemies[other].id, cell)
	}
}

// The LASSO marks on the wounds a lasso's action gave (lasso_turn: a full
// turn's): no blow of the player's swings them (event.odin).
@(private = "file")
lasso_mark_events :: proc(log: ^Event_Log, first: int, turn: bool) {
	if log == nil { return }
	mark := EVENT_LASSO_BIT|(EVENT_LASSO_TURN_BIT if turn else 0)
	for &event in log.events[clamp(first, 0, log.count):log.count] {
		if event.source != PLAYER_ENTITY || event.has_status_cause { continue }
		if event.kind == .Damaged || event.kind == .Damage_Absorbed { event.area_mask |= mark }
	}
}

// Ring collision n: the swung foe and the one struck by it both take n,
// then the struck one is knocked back n cells. Interior sweeps skip damage.
@(private = "file")
lasso_strike :: proc(room: ^Room, struck_id: u32, cell: grid.Position) {
	s := &room.lasso
	n := lasso_next_hit(s)
	s.hits += 1
	swung, struck := enemy_entity(s.enemy_id), enemy_entity(struck_id)
	record_event(room.recent_events, {kind = .Lasso_Struck, source = swung, target = struck, amount = n,
		from_position = cell, to_position = cell, card_definition = .Lasso})
	action := make_action(.Trigger, PLAYER_ENTITY, entity_target(struck), .Opponent)
	added := add_effect(&action, damage_effect(struck, n))
	assert(added)
	added = add_effect(&action, damage_effect(swung, n))
	assert(added)
	report := resolve_action(room, &action)
	lasso_mark_events(&report.events, 0, false)
	append_event_log(room.recent_events, &report.events)
	if room.phase != .Combat { return }
	if _, standing := enemy_index_by_id(room, struck_id); standing { lasso_knock_back(room, struck_id, n) }
}

// The eight-way step away from `centre` toward `cell`: straight within 22.5
// degrees of an axis (tan 22.5 degrees < 0.414), diagonal otherwise.
lasso_radial_step :: proc(centre, cell: grid.Position) -> grid.Position {
	dx, dy := cell.x-centre.x, cell.y-centre.y
	ax, ay := abs(dx), abs(dy)
	if ay*1000 <= ax*414 { return {x = sign(dx), y = 0} }
	if ax*1000 <= ay*414 { return {x = 0, y = sign(dy)} }
	return {x = sign(dx), y = sign(dy)}
}

// The struck foe pushed `cells` away from the player, as far as its way is
// clear (the game's push rules, as a card's push): one movement, so every cell
// it enters acts on it. Interior sweeps also stop at the first ring cell.
@(private)
lasso_knock_back :: proc(room: ^Room, id: u32, cells: i32, stop_on_ring := false) {
	index, found := enemy_index_by_id(room, id)
	if !found { return }
	from := room.enemies[index].position
	step := lasso_radial_step(room.lasso.centre if room.lasso.active else room.player.position, from)
	if step == {} { return }
	mover := enemy_entity(id)
	destination := from
	for distance in 1..=min(int(cells), MAX_MOVEMENT_PATH_CELLS) {
		cell := grid.offset(from, step.x*distance, step.y*distance)
		query := query_entity_movement(room, mover, cell)
		if !movement_query_is_clear(&query) { break }
		destination = cell
		if stop_on_ring && lasso_cell_on_ring(&room.lasso, cell) { break }
	}
	if destination == from { return }
	action := make_action(.Trigger, PLAYER_ENTITY, entity_target(mover), .Opponent)
	added := add_effect(&action, move_effect(mover, destination))
	assert(added)
	report := resolve_action(room, &action)
	append_event_log(room.recent_events, &report.events)
}

// A smash into the solid cell `cell` (radius 1 beside a wall, or an object
// set down on the ring): hit number n on the swung foe alone.
@(private = "file")
lasso_smash :: proc(room: ^Room, cell: grid.Position) {
	s := &room.lasso
	n := lasso_next_hit(s)
	s.hits += 1
	swung := enemy_entity(s.enemy_id)
	record_event(room.recent_events, {kind = .Lasso_Struck, source = swung, target = SYSTEM_ENTITY, amount = n,
		from_position = lasso_arc_cell(s, s.arc), to_position = cell, card_definition = .Lasso})
	action := make_action(.Trigger, PLAYER_ENTITY, entity_target(swung), .Opponent)
	added := add_effect(&action, damage_effect(swung, n))
	assert(added)
	report := resolve_action(room, &action)
	lasso_mark_events(&report.events, 0, false)
	append_event_log(room.recent_events, &report.events)
}

// A full turn round the player: LASSO_TURN_DAMAGE to the swung foe (a Shield
// takes it, as any of the player's damage).
@(private = "file")
lasso_turn_damage :: proc(room: ^Room) {
	swung := enemy_entity(room.lasso.enemy_id)
	action := make_action(.Trigger, PLAYER_ENTITY, entity_target(swung), .Opponent)
	added := add_effect(&action, damage_effect(swung, LASSO_TURN_DAMAGE))
	assert(added)
	report := resolve_action(room, &action)
	lasso_mark_events(&report.events, 0, true)
	append_event_log(room.recent_events, &report.events)
}

// Where a released foe lands: on the cell under it when it is free (on the
// board, no wall, cover or blocking object, not the player's, no other foe),
// or the nearest free cell (by Chebyshev distance, row by row); not ok on a
// board with no free cell left.
@(private = "file")
lasso_landing :: proc(room: ^Room, index: int, under: grid.Position) -> (landing: grid.Position, ok: bool) {
	free :: proc(room: ^Room, index: int, cell: grid.Position) -> bool {
		if !grid.contains(&room.level_data.tiles, cell) || cell_blocks_movement(room, cell) || cell == room.player.position { return false }
		_, occupied := enemy_index_at(room, cell, index)
		return !occupied
	}
	if free(room, index, under) { return under, true }
	tiles := &room.level_data.tiles
	for distance in 1..=max(tiles.width, tiles.height) {
		for y in under.y-distance..=under.y+distance {
			for x in under.x-distance..=under.x+distance {
				if max(abs(x-under.x), abs(y-under.y)) != distance { continue }
				if free(room, index, {x = x, y = y}) { return {x = x, y = y}, true }
			}
		}
	}
	return under, false
}

// The player moved (apply_movement_effect): the rope goes, the held foe falls
// where `lasso_landing` puts it, the cell it lands on acting on it as any
// landing's does, and starts a fresh intent. The seconds in the air served out
// any recovery it was in: no daze. Between beats (the dodge) the planner gives
// it its intent at once, as it gives a foe set down mid-window its first
// (spawn_enemy); in the middle of a beat (a brute's push, the defence prompt's
// dodge) the planner's work waits for the beat's end, so it holds a wait of no
// length that the end of the beat plans afresh (finish_combat_pulse).
@(private)
release_lasso :: proc(room: ^Room, report: ^Action_Report) {
	if room == nil || report == nil || !room.lasso.active { return }
	held := room.lasso
	room.lasso = {}
	index, found := enemy_index_by_id(room, held.enemy_id)
	if !found { return }
	foe := enemy_entity(held.enemy_id)
	under := room.enemies[index].position
	landing, free := lasso_landing(room, index, under)
	record_report_event(report, {kind = .Lasso_Released, source = PLAYER_ENTITY, target = foe, from_position = under,
		to_position = landing, amount = held.turns, duration = held.hits, card_definition = .Lasso})
	if free && landing != under {
		apply_movement_effect(room, SYSTEM_ENTITY, move_effect(foe, landing, .Teleport), report)
	} else {
		trigger_cell_entry(room, foe, report)
	}
	if room.phase != .Combat { return }
	at, present := enemy_index_by_id(room, held.enemy_id)
	if !present { return }
	enemy := &room.enemies[at]
	enemy.recovery_pulses = 0
	if room.tactical_pulse.pending && room.tactical_pulse.started {
		enemy.intent, enemy.tactical_cooldown = make_wait_intent(room, enemy.position), 0
		return
	}
	enemy.intent, enemy.tactical_cooldown = {}, 0
	plan_enemy_intents(room)
}
