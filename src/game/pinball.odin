package game

import "core:math"
import grid "../engine/grid"
import rng "../engine/rng"

// PINBALL. The card's two seconds are the strike (a cast, the world still):
// one foe beside the player (the eight cells round him, in sight), never a
// boss or a miniboss (Target_Too_Heavy; unlike the Lazzo, this card keeps its
// weight restriction), turns into a steel ball, and the player strikes it
// away from him: from him toward it, turned PINBALL_MIN_TURN to
// PINBALL_MAX_TURN degrees left or right by the room's own stream
// (Room.pinball_random), so that it never just bounces on one axis.
//
// For PINBALL_SECONDS of the world's own time it rolls on the board at
// PINBALL_SPEED cells a second, a disc of PINBALL_RADIUS round its centre,
// bouncing elastically off every solid thing (a wall, the room's edge, cover,
// a blocking object: lasso_cell_is_solid) and off every foe on the floor (a
// round bumper of PINBALL_BUMPER_RADIUS at its cell's centre). The roll is
// stepped from one event to the next (a contact, the edge of the cell under
// it, the end of its time), never by frames: no wall is rolled through and no
// foe is missed at any frame rate. Each straight run is measured from where
// it began, so the same room gives the same bounces however its seconds are
// cut into frames.
//
// Its value starts at the card's amount (2, +1 per upgrade, +1 on the tick).
// A foe it touches takes the value (the player's damage, the normal rules) and
// is knocked back one cell away from the ball (the eight ways) under the
// game's push rules: a wall, an obstacle or a body stops it, and pools, fires
// and traps act on the cell it enters. The ball bounces off it as off a
// bumper and the value grows by one. One hit a contact: the same foe again
// only once the ball has left it (PINBALL_LEAVE). Every touch of a solid thing
// puts the value back to the card's amount. It rolls over the player and under
// the Lazzo's foe.
//
// The ball is the foe itself, out of the world (enemy_is_out_of_play): it
// stands on no cell (enemy_index_at), takes no action, plans nothing, carries
// no status (its own go as it turns) and nothing reaches it: no damage,
// status, push or card, no arrow, pool, fire, trap or blast (effect_is_valid,
// can_apply_status). When its time is up it bursts and the foe falls where it
// is, a normal kill of the player's (its loot, the room cleared if it was the
// last). The world runs all the while and the player acts freely; only what
// stops the world (a cast, a defence prompt, a cinematic die, the shadow, a
// pause) stops the ball too. One ball at a time. No coil is set down where its
// disc lies (board_device_can_deploy); a blocking thing pushed there all the
// same is rolled through until the disc has left it.

PINBALL_RANGE :: 1
PINBALL_SECONDS :: f64(20)
PINBALL_SPEED :: f64(7)
PINBALL_RADIUS :: f64(0.45)
PINBALL_BUMPER_RADIUS :: f64(0.4)
PINBALL_CONTACT :: PINBALL_RADIUS+PINBALL_BUMPER_RADIUS
// A foe struck is struck again only once the ball has gone this much farther
// than touching it.
PINBALL_LEAVE :: f64(0.05)
// The launch's turn off the line from the player to the foe, in whole degrees.
PINBALL_MIN_TURN :: i32(15)
PINBALL_MAX_TURN :: i32(35)
PINBALL_MAX_UPGRADE_LEVEL :: i32(5)
PINBALL_EPSILON :: f64(1e-9)
// A roll batch stops this far short of a full event log: what one more step
// brings (a hit, its guard and wound, a death and its loot, a push and what
// its cell does, a burst) always fits.
PINBALL_EVENT_HEADROOM :: 96
// A guard on one batch's steps (each reaches one event at most).
PINBALL_MAX_STEPS :: 100_000
PINBALL_SEED_SALT :: u64(0xB0B1_9A11_5EED_7E57)

Pinball_Vec :: [2]f64

Pinball_State :: struct {
	active: bool,
	enemy_id: u32,
	// The straight run it is on: where the run began, its heading (a unit
	// vector, x east and y south, a cell's centre at its position) and the
	// cells rolled along it so far.
	origin, heading: Pinball_Vec,
	run: f64,
	// World seconds rolled before this run began, and those waiting to be
	// rolled (tactical_pinball_tick).
	before, pending: f64,
	// The value the next foe touched takes, and the card's amount, which every
	// solid thing puts it back to.
	value, base: i32,
	// The cell under the ball's centre: the foe's place on the board.
	cell: grid.Position,
	// The foes it is touching: struck once, again once it has left them.
	touching: [MAX_ENEMIES_PER_ROOM]u32,
	touching_count: int,
	// Foes struck and solid things touched so far.
	hits, bounces: i32,
	// The player's cell at the strike, and the launch's turn (degrees: + is
	// clockwise on a north-up board, as the angle grows with y south).
	struck_from: grid.Position,
	turn: i32,
}

@(private)
pinball_effect :: proc(target: Entity_Ref, value: i32) -> Effect {
	return {kind = .Pinball, target = target, amount = value}
}

// The foe the Pinball has turned into its ball.
enemy_is_pinball :: proc(room: ^Room, id: u32) -> bool {
	return room != nil && room.pinball.active && id != 0 && room.pinball.enemy_id == id
}

tactical_pinball_active :: proc(room: ^Room) -> bool {
	return room != nil && room.pinball.active && room.phase == .Combat
}

// The room's own stream for its launches: from its seed and the run's dice as
// the room begins (create_room), never a clock.
@(private)
pinball_room_stream :: proc(player: ^Player, content: Room_Content) -> u64 {
	seed := content.room_seed~PINBALL_SEED_SALT
	if player != nil { seed ~= player.dice.random_state }
	random := mix_room_seed(seed)
	return random if random != 0 else PINBALL_SEED_SALT
}

// The launch's turn off the line to the foe: PINBALL_MIN_TURN to
// PINBALL_MAX_TURN degrees, either way, from the room's stream.
pinball_launch_turn :: proc(random: ^u64) -> i32 {
	if random^ == 0 { random^ = PINBALL_SEED_SALT }
	left := rng.below_state(random, 2) == 0
	degrees := PINBALL_MIN_TURN+i32(rng.below_state(random, u64(PINBALL_MAX_TURN-PINBALL_MIN_TURN+1)))
	return -degrees if left else degrees
}

// The way the ball leaves `cell` when the player at `from` strikes it, turned
// `turn` degrees off the line from him to it.
pinball_launch_heading :: proc(from, cell: grid.Position, turn: i32) -> Pinball_Vec {
	angle := math.atan2(f64(cell.y-from.y), f64(cell.x-from.x))+f64(turn)*math.PI/180
	return {math.cos(angle), math.sin(angle)}
}

// The launch a strike at `cell` would give now (the room's stream as it
// stands, left untouched): what the card's aim shows.
pinball_next_launch :: proc(room: ^Room, cell: grid.Position) -> (heading: Pinball_Vec, turn: i32) {
	if room == nil || room.player == nil { return }
	random := room.pinball_random
	turn = pinball_launch_turn(&random)
	return pinball_launch_heading(room.player.position, cell, turn), turn
}

// Whether the rolling ball's disc lies over `cell`: no blocking thing is set
// down there while it does (board_device_can_deploy).
@(private)
pinball_covers_cell :: proc(room: ^Room, cell: grid.Position) -> bool {
	if !tactical_pinball_active(room) { return false }
	p := pinball_position(&room.pinball)
	closest := Pinball_Vec{clamp(p.x, f64(cell.x)-0.5, f64(cell.x)+0.5), clamp(p.y, f64(cell.y)-0.5, f64(cell.y)+0.5)}
	return pinball_length(p-closest) < PINBALL_RADIUS
}

// Why the Pinball cannot take `target` now (.None: it can): no foe on the
// floor, one out of reach, a boss's weight, or a ball already rolling.
pinball_target_error :: proc(room: ^Room, target: Target) -> Card_Compile_Error {
	if room == nil || room.player == nil || room.level_data == nil { return .Invalid_Room }
	if target.kind != .Entity || target.entity.kind != .Enemy { return .Invalid_Target }
	index, found := enemy_index_by_id(room, target.entity.id)
	if !found || enemy_is_out_of_play(room, target.entity.id) { return .Invalid_Target }
	enemy := room.enemies[index]
	if max(abs(enemy.position.x-room.player.position.x), abs(enemy.position.y-room.player.position.y)) != PINBALL_RANGE {
		return .Target_Out_Of_Range
	}
	if enemy_is_boss(enemy.archetype) { return .Target_Too_Heavy }
	if room.pinball.active { return .Target_Blocked }
	return .None
}

// The strike (apply_effect): the foe turns into the ball where it stands, its
// statuses, reactions and intent gone, and the player strikes it away; it
// rolls with the world's next seconds.
@(private)
begin_pinball :: proc(room: ^Room, target: Entity_Ref, value: i32, report: ^Action_Report) -> bool {
	if report == nil || value <= 0 || pinball_target_error(room, entity_target(target)) != .None { return false }
	index, _ := enemy_index_by_id(room, target.id)
	enemy := &room.enemies[index]
	cell := enemy.position
	from := room.player.position
	record_report_event(report, {kind = .Pinball_Made, source = PLAYER_ENTITY, target = target, from_position = cell,
		to_position = cell, amount = value, duration = i32(PINBALL_SECONDS), card_definition = .Pinball})
	// What it carried goes as it turns: the board drops its tags with the
	// card's puff.
	for status in enemy.statuses.items[:clamp(enemy.statuses.count, 0, MAX_STATUSES_PER_ENTITY)] {
		record_report_event(report, {kind = .Status_Removed, source = PLAYER_ENTITY, target = target,
			amount = status.potency, status = status.kind, duration = status.remaining_pulses})
	}
	clear_statuses(&enemy.statuses)
	remove_reaction_bindings_for_owner(room, target)
	enemy.intent, enemy.tactical_cooldown, enemy.recovery_pulses = {}, 0, 0
	enemy.aim_ready, enemy.bomb_ready = false, false
	turn := pinball_launch_turn(&room.pinball_random)
	room.pinball = {active = true, enemy_id = enemy.id, origin = {f64(cell.x), f64(cell.y)},
		heading = pinball_launch_heading(from, cell, turn), value = value, base = value, cell = cell, struck_from = from, turn = turn}
	// He turns to face the ball he strikes.
	dx, dy := cell.x-from.x, cell.y-from.y
	if abs(dx) > abs(dy) { room.player.tactical.facing = .East if dx > 0 else .West }
	else { room.player.tactical.facing = .South if dy > 0 else .North }
	record_report_event(report, {kind = .Pinball_Launched, source = PLAYER_ENTITY, target = target, from_position = from,
		to_position = cell, amount = value, duration = turn, card_definition = .Pinball})
	return true
}

// The ball's centre now.
pinball_position :: proc(s: ^Pinball_State) -> Pinball_Vec {
	return s.origin+s.heading*s.run
}

// World seconds the ball has rolled, and the ones it has left.
pinball_rolled :: proc(s: ^Pinball_State) -> f64 {
	return s.before+s.run/PINBALL_SPEED
}

pinball_seconds_left :: proc(s: ^Pinball_State) -> f64 {
	return max(0, PINBALL_SECONDS-pinball_rolled(s))
}

// World seconds for the ball (tactical_tick, with the world's own).
@(private)
tactical_pinball_tick :: proc(room: ^Room, seconds: f32) {
	if !tactical_pinball_active(room) || !(seconds > 0) { return }
	room.pinball.pending += f64(seconds)
}

// Seconds wait to be rolled, and nothing holds the world: the controller
// commits the roll (resolve_pinball_roll) as a world command, as it does a beat.
tactical_pinball_due :: proc(room: ^Room) -> bool {
	return tactical_pinball_active(room) && room.player != nil && !room.tactical_pulse.pending &&
	       room.qte.kind == .None && room.player.tactical.cast_remaining <= 0 && room.pinball.pending > PINBALL_EPSILON
}

// The seconds waiting, rolled out into room.recent_events: every foe struck,
// every solid thing touched and, at its time, the burst, in order. A batch that
// comes near a full log leaves the rest for the next.
resolve_pinball_roll :: proc(room: ^Room) -> bool {
	if !tactical_pinball_due(room) { return false }
	clear_event_log(room.recent_events)
	for steps := 0; steps < PINBALL_MAX_STEPS && tactical_pinball_active(room) && room.pinball.pending > PINBALL_EPSILON &&
	    room.recent_events.count <= MAX_GAME_EVENTS-PINBALL_EVENT_HEADROOM; steps += 1 {
		pinball_step(room)
	}
	collect_loot_in_magnet_range(room)
	if room.phase != .Combat {
		sync_deck_with_room_phase(room)
		tactical_end_combat(room)
	}
	return true
}

@(private = "file")
pinball_dot :: proc(a, b: Pinball_Vec) -> f64 {
	return a.x*b.x+a.y*b.y
}

@(private)
pinball_length :: proc(a: Pinball_Vec) -> f64 {
	return math.sqrt(pinball_dot(a, a))
}

// Where a run from `origin` along `heading` first touches the circle of
// `radius` round `centre`, no nearer than `run`: the entering distance.
@(private = "file")
pinball_circle_contact :: proc(origin, heading: Pinball_Vec, run: f64, centre: Pinball_Vec, radius: f64) -> (t: f64, ok: bool) {
	w := origin-centre
	b := pinball_dot(heading, w)
	c := pinball_dot(w, w)-radius*radius
	disc := b*b-c
	if disc < 0 { return }
	t = -b-math.sqrt(disc)
	return t, t >= run-PINBALL_EPSILON
}

// Where a run first touches the solid cell `cell` (the ball's disc on its
// square), no nearer than `run`, and the way back out of it there. A cell the
// disc already overlaps (a thing set down under the ball) is rolled through.
@(private = "file")
pinball_square_contact :: proc(origin, heading: Pinball_Vec, run: f64, cell: grid.Position) -> (t: f64, normal: Pinball_Vec, ok: bool) {
	lo := Pinball_Vec{f64(cell.x)-0.5, f64(cell.y)-0.5}
	hi := Pinball_Vec{f64(cell.x)+0.5, f64(cell.y)+0.5}
	r := PINBALL_RADIUS
	p := origin+heading*run
	closest := Pinball_Vec{clamp(p.x, lo.x, hi.x), clamp(p.y, lo.y, hi.y)}
	if pinball_length(p-closest) < r-PINBALL_EPSILON { return }
	t = max(f64)
	// Its faces, the disc's edge on them.
	for axis in 0..<2 {
		other := 1-axis
		if abs(heading[axis]) < PINBALL_EPSILON { continue }
		face := lo[axis]-r if heading[axis] > 0 else hi[axis]+r
		at := (face-origin[axis])/heading[axis]
		if at < run-PINBALL_EPSILON || at >= t { continue }
		along := origin[other]+heading[other]*at
		if along < lo[other] || along > hi[other] { continue }
		t, ok = at, true
		normal = {}
		normal[axis] = -1 if heading[axis] > 0 else 1
	}
	// Its corners: a graze that only runs along one (never into it) is none,
	// or the ball would touch it again at every step without rolling on.
	for corner in ([4]Pinball_Vec{lo, {hi.x, lo.y}, {lo.x, hi.y}, hi}) {
		at, hit := pinball_circle_contact(origin, heading, run, corner, r)
		if !hit || at >= t { continue }
		touch := origin+heading*at
		out := (touch-corner)/r
		if pinball_dot(heading, out) > -PINBALL_EPSILON { continue }
		t, ok, normal = at, true, out
	}
	return
}

// The distance along the run to the edge of the cell under the ball, and the
// ways it crosses there (both at a corner).
@(private = "file")
pinball_edge_distance :: proc(s: ^Pinball_State) -> (t: f64, step: grid.Position, ok: bool) {
	t = max(f64)
	ways := [2]int{0, 0}
	at := [2]f64{max(f64), max(f64)}
	for axis in 0..<2 {
		if abs(s.heading[axis]) < PINBALL_EPSILON { continue }
		ways[axis] = 1 if s.heading[axis] > 0 else -1
		centre := f64(s.cell.x) if axis == 0 else f64(s.cell.y)
		at[axis] = (centre+0.5*f64(ways[axis])-s.origin[axis])/s.heading[axis]
		t = min(t, at[axis])
	}
	if t == max(f64) { return }
	ok = true
	if at[0]-t <= PINBALL_EPSILON { step.x = ways[0] }
	if at[1]-t <= PINBALL_EPSILON { step.y = ways[1] }
	return
}

@(private = "file")
pinball_touching :: proc(s: ^Pinball_State, id: u32) -> bool {
	for touched in s.touching[:s.touching_count] { if touched == id { return true } }
	return false
}

// A foe on the floor the ball meets: not the ball, not the Lazzo's foe.
@(private = "file")
pinball_bumper :: proc(room: ^Room, enemy: Enemy) -> bool {
	return enemy.id != room.pinball.enemy_id && !enemy_is_out_of_play(room, enemy.id)
}

@(private = "file")
pinball_foe_centre :: proc(enemy: Enemy) -> Pinball_Vec {
	return {f64(enemy.position.x), f64(enemy.position.y)}
}

// One step of the roll: up to the next contact, the edge of the cell under the
// ball, the end of its time or of the seconds waiting, whichever comes first.
@(private = "file")
pinball_step :: proc(room: ^Room) {
	s := &room.pinball
	p := pinball_position(s)
	// The foes it has left may be struck again; a foe that came onto it (a
	// step, a push) is struck at once.
	kept := 0
	for id in s.touching[:s.touching_count] {
		index, found := enemy_index_by_id(room, id)
		if !found || !pinball_bumper(room, room.enemies[index]) ||
		   pinball_length(p-pinball_foe_centre(room.enemies[index])) > PINBALL_CONTACT+PINBALL_LEAVE { continue }
		s.touching[kept] = id
		kept += 1
	}
	s.touching_count = kept
	for enemy in room.enemies {
		if !pinball_bumper(room, enemy) || pinball_touching(s, enemy.id) { continue }
		if pinball_length(p-pinball_foe_centre(enemy)) < PINBALL_CONTACT-PINBALL_EPSILON {
			pinball_bump(room, enemy.id)
			return
		}
	}
	Next :: enum {Time, Solid, Foe, Edge}
	life := (PINBALL_SECONDS-s.before)*PINBALL_SPEED
	budget := s.run+s.pending*PINBALL_SPEED
	next, best := Next.Time, min(life, budget)
	normal: Pinball_Vec
	wall: grid.Position
	foe: u32
	for dy in -1..=1 {
		for dx in -1..=1 {
			cell := grid.offset(s.cell, dx, dy)
			if !lasso_cell_is_solid(room, cell) { continue }
			if t, n, hit := pinball_square_contact(s.origin, s.heading, s.run, cell); hit && t < best {
				next, best, normal, wall = .Solid, t, n, cell
			}
		}
	}
	for enemy in room.enemies {
		if !pinball_bumper(room, enemy) || pinball_touching(s, enemy.id) { continue }
		if t, hit := pinball_circle_contact(s.origin, s.heading, s.run, pinball_foe_centre(enemy), PINBALL_CONTACT); hit && t < best {
			next, best, foe = .Foe, t, enemy.id
		}
	}
	step: grid.Position
	if t, crossing, ok := pinball_edge_distance(s); ok && t < best { next, best, step = .Edge, t, crossing }
	best = max(best, s.run)
	s.pending = max(0, (budget-best)/PINBALL_SPEED)
	if best >= budget-PINBALL_EPSILON && next == .Time && best < life-PINBALL_EPSILON { s.pending = 0 }
	s.run = best
	switch next {
	case .Time:
		if s.run >= life-PINBALL_EPSILON { pinball_burst(room) }
	case .Solid:
		pinball_bounce(room, normal, wall)
	case .Foe:
		pinball_bump(room, foe)
	case .Edge:
		s.cell = add_position(s.cell, step)
		if index, found := enemy_index_by_id(room, s.enemy_id); found { room.enemies[index].position = s.cell }
	}
}

// A new straight run from where the ball is, along `heading`.
@(private = "file")
pinball_turn :: proc(s: ^Pinball_State, heading: Pinball_Vec) {
	s.origin = pinball_position(s)
	s.before += s.run/PINBALL_SPEED
	s.run = 0
	length := pinball_length(heading)
	s.heading = heading/length if length > PINBALL_EPSILON else -s.heading
}

// The heading mirrored off a surface whose way out is `normal`, when it
// was going into it.
@(private = "file")
pinball_reflect :: proc(heading, normal: Pinball_Vec) -> Pinball_Vec {
	into := pinball_dot(heading, normal)
	if into >= 0 { return heading }
	return heading-normal*(2*into)
}

// The ball touches the solid cell `cell`: it bounces off, and its value goes
// back to the card's amount.
@(private = "file")
pinball_bounce :: proc(room: ^Room, normal: Pinball_Vec, cell: grid.Position) {
	s := &room.pinball
	record_event(room.recent_events, {kind = .Pinball_Bounced, source = enemy_entity(s.enemy_id), target = SYSTEM_ENTITY,
		amount = s.base, duration = s.value, from_position = s.cell, to_position = cell, card_definition = .Pinball})
	s.value = s.base
	s.bounces += 1
	pinball_turn(s, pinball_reflect(s.heading, normal))
}

// The PINBALL marks on the wounds the ball gave (event.odin): no blow of the
// player's swings them.
@(private = "file")
pinball_mark_events :: proc(log: ^Event_Log, first: int) {
	if log == nil { return }
	for &event in log.events[clamp(first, 0, log.count):log.count] {
		if event.source != PLAYER_ENTITY || event.has_status_cause { continue }
		if event.kind == .Damaged || event.kind == .Damage_Absorbed { event.area_mask |= EVENT_PINBALL_BIT }
	}
}

// The eight-way step from `from` toward `to`: straight within 22.5 degrees of
// an axis (tan 22.5 degrees < 0.414), diagonal otherwise; `fallback` when they
// are one point.
@(private = "file")
pinball_eight_way :: proc(from, to, fallback: Pinball_Vec) -> grid.Position {
	d := to-from
	if pinball_length(d) < PINBALL_EPSILON { d = fallback }
	sx := 1 if d.x > 0 else (-1 if d.x < 0 else 0)
	sy := 1 if d.y > 0 else (-1 if d.y < 0 else 0)
	ax, ay := abs(d.x), abs(d.y)
	if ay <= ax*0.414 { return {x = sx, y = 0} }
	if ax <= ay*0.414 { return {x = 0, y = sy} }
	return {x = sx, y = sy}
}

// The ball touches the foe `id`: it takes the value, the player's damage; then
// it is knocked back a cell away from the ball, the ball bounces off it and the
// value grows by one.
@(private = "file")
pinball_bump :: proc(room: ^Room, id: u32) {
	s := &room.pinball
	index, found := enemy_index_by_id(room, id)
	if !found { return }
	p := pinball_position(s)
	centre := pinball_foe_centre(room.enemies[index])
	struck := enemy_entity(id)
	value := s.value
	record_event(room.recent_events, {kind = .Pinball_Bumped, source = enemy_entity(s.enemy_id), target = struck, amount = value,
		from_position = s.cell, to_position = room.enemies[index].position, card_definition = .Pinball})
	s.hits += 1
	s.value = min(value, max(i32)-1)+1
	if s.touching_count < len(s.touching) {
		s.touching[s.touching_count] = id
		s.touching_count += 1
	}
	away := centre-p
	if pinball_length(away) > PINBALL_EPSILON { pinball_turn(s, pinball_reflect(s.heading, -away/pinball_length(away))) }
	else { pinball_turn(s, -s.heading) }
	action := make_action(.Trigger, PLAYER_ENTITY, entity_target(struck), .Opponent)
	added := add_effect(&action, damage_effect(struck, value))
	assert(added)
	report := resolve_action(room, &action)
	pinball_mark_events(&report.events, 0)
	append_event_log(room.recent_events, &report.events)
	if room.phase != .Combat { return }
	pinball_knock_back(room, id, p)
}

// The foe struck pushed one cell away from the ball at `from`, when its way
// is clear (the game's push rules, as the Lazzo's): every cell it enters acts
// on it.
@(private = "file")
pinball_knock_back :: proc(room: ^Room, id: u32, from: Pinball_Vec) {
	index, found := enemy_index_by_id(room, id)
	if !found { return }
	cell := room.enemies[index].position
	step := pinball_eight_way(from, pinball_foe_centre(room.enemies[index]), room.pinball.heading*-1)
	if step == {} { return }
	mover := enemy_entity(id)
	destination := add_position(cell, step)
	query := query_entity_movement(room, mover, destination)
	if !movement_query_is_clear(&query) { return }
	action := make_action(.Trigger, PLAYER_ENTITY, entity_target(mover), .Opponent)
	added := add_effect(&action, move_effect(mover, destination))
	assert(added)
	report := resolve_action(room, &action)
	append_event_log(room.recent_events, &report.events)
}

// Its time is up: the ball bursts and the foe falls where it is, a normal kill
// of the player's.
@(private = "file")
pinball_burst :: proc(room: ^Room) {
	s := room.pinball
	room.pinball = {}
	index, found := enemy_index_by_id(room, s.enemy_id)
	if !found { return }
	foe := enemy_entity(s.enemy_id)
	record_event(room.recent_events, {kind = .Pinball_Burst, source = PLAYER_ENTITY, target = foe, amount = s.hits,
		duration = s.bounces, from_position = s.cell, to_position = s.cell, card_definition = .Pinball})
	// It carries nothing that could guard it (its statuses went as it turned):
	// whatever it has left, and any Shield over it, it falls.
	enemy := &room.enemies[index]
	lethal := max(i32(1), enemy.health)
	if shield, shielded := status_index(&enemy.statuses, .Shield); shielded {
		lethal = min(lethal, max(i32)-enemy.statuses.items[shield].potency)+enemy.statuses.items[shield].potency
	}
	action := make_action(.Trigger, PLAYER_ENTITY, entity_target(foe), .Opponent)
	added := add_effect(&action, damage_effect(foe, lethal))
	assert(added)
	report := resolve_action(room, &action)
	pinball_mark_events(&report.events, 0)
	append_event_log(room.recent_events, &report.events)
}
