package game

import "core:math"
import grid "../engine/grid"

// FIRST PERSON FENCER (docs/piano-prima-persona.md, sezione 6 and Fase 4): the
// sword behind the player's eyes. He keeps to the grid, his steps quicker
// (SWORD_MOVE_SECONDS), his view turned a quarter by Q and E; the mouse is all
// the blade's. It moves the blade's point on the screen (`tip`, in screen
// heights: the centre 0, the top edge 0.5, x to the right) inside an ellipse,
// the blade running from the hilt fixed low on the right to it. There is no
// canned swing: with the left button held a swing starts when the point moves
// faster than SWORD_SWING_START heights a second, and the damage comes from how
// it moved (sword_strike_damage: speed, breadth, a clean line, where on the
// blade it cuts, which way). The blade cuts a foe when it sweeps across his
// body as the view shows it (his spine from the waist to the head, and across
// his shoulders: SWORD_BODY_POINTS): a foe a cell away fills the screen's
// middle, so the blade lying over his card is no cut, its passing through him
// is, where along the blade it passes saying `u`. Only a
// foe in the cell in front of him, or the two diagonals in front too for a
// sideways cut, and in sight (the AK's trace to him). No pause between
// cuts (the user's choice after trying it): every pass across a chest cuts,
// back and forth, once the point has gone SWORD_MIN_CUT since the swing began
// or since its last cut, and its breadth counts from there, so a twitch does
// nothing and a short stroke little. A step taken mid-swing lunges into the cut
// (SWORD_LUNGE_FACTOR); a quarter turn with Q or E the way the blade sweeps is a
// spinning cut (SWORD_SPIN_LENGTH more of breadth, SWORD_SPIN_FACTOR more).
// The right
// button held parries the blows from in front (no limit, the user's choice); a
// press within SWORD_PERFECT_PARRY seconds before the blow is a perfect parry:
// the striker staggered and wounded, a bolt sent back. Ctrl is the grapple: the
// first foe in line 2..4 cells ahead pulled to the cell in front, staggered.
// The point moves on its own clock of SWORD_STEP seconds (the frame's mouse
// spread over it), so the same gesture strikes the same at any frame rate.

// The card's seconds (the user's choice after trying it: the AK's twenty were
// too few, with neither the fists' free moves nor the AK's reach).
FENCER_SECONDS :: i32(35)

SWORD_STEP :: f32(1.0/240)
SWORD_MAX_FRAME :: f32(0.25)
// A step on the grid with the sword (the user's choice: 0.3 s).
SWORD_MOVE_SECONDS :: f32(0.3)
// The view's vertical field (degrees): the board's camera with the sword and
// the traces along the blade share it.
SWORD_FOV :: f32(70)
// Screen heights the point moves for a pixel of the mouse, before the profile's sensitivity.
SWORD_TIP_PER_PIXEL :: f32(0.0012)
// The hilt, low and a little to the right (off the screen's bottom edge, so
// the blade reaches the foes on both diagonals in front), and the ellipse the
// point stays in, round the centre.
SWORD_HILT :: [2]f32{0.35, -0.62}
SWORD_TIP_REACH :: [2]f32{0.82, 0.46}
SWORD_TIP_START :: [2]f32{0.05, 0.05}
// The swing: starts above, ends below for SWORD_SWING_STOP_SECONDS (heights a second).
SWORD_SWING_START :: f32(1)
SWORD_SWING_STOP :: f32(0.5)
SWORD_SWING_STOP_SECONDS :: f32(0.1)
// The 1€ filter on the point (Casiez, Roussel and Vogel, CHI 2012): its
// cutoff at rest (Hz), how fast it opens with the speed, the speed's own
// cutoff (Hz). The swing reads the speed, the board the smoothed point.
SWORD_FILTER_MIN_CUTOFF :: f32(1.5)
SWORD_FILTER_BETA :: f32(4)
SWORD_FILTER_D_CUTOFF :: f32(8)
// The formula (sezione 6.4).
SWORD_BASE_DAMAGE :: f32(6)
SWORD_SPEED_FULL :: f32(4)
SWORD_LENGTH_FULL :: f32(0.8)
SWORD_PERFECT_FACTOR :: f32(1.5)
SWORD_FENDENTE_FACTOR :: f32(1.25)
SWORD_TONDO_SECOND_FACTOR :: f32(0.8)
// The point's way (heights) a cut needs since the swing began or since its last cut.
SWORD_MIN_CUT :: f32(0.2)
// A step mid-swing; a quarter turn the way the blade sweeps (its way counted as
// this much more, the damage this much more).
SWORD_LUNGE_FACTOR :: f32(1.25)
SWORD_SPIN_LENGTH :: f32(0.8)
SWORD_SPIN_FACTOR :: f32(1.5)
// Below this way across a reversal the stroke goes on; above it, a new stroke starts.
SWORD_REVERSE_COSINE :: f32(-0.3)
// A foe's chest on his card, as a part of its outline's top (the marks' height,
// render); how far past its point the blade still cuts (its point's own width).
SWORD_CHEST_HEIGHT :: f32(0.6)
SWORD_POINT_SLACK :: f32(0.05)
// The parry.
SWORD_PERFECT_PARRY :: f32(0.25)
SWORD_PARRY_STAGGER_BEATS :: i32(1)
SWORD_PARRY_DAMAGE :: i32(2)
// The grapple.
SWORD_GRAPPLE_MIN :: 2
SWORD_GRAPPLE_MAX :: 4
SWORD_GRAPPLE_RECHARGE :: f32(3)
SWORD_GRAPPLE_STAGGER_BEATS :: i32(1)
// The sword's wounds carry this in Game_Event.visual_group.
SWORD_VISUAL_GROUP :: u32(0x4B_5002)

// The way a swing went, from where it started to where it cut: down (a
// fendente), up (a montante) or sideways (a tondo).
Sword_Kind :: enum u8 {None, Fendente, Tondo, Montante}

// The 1€ filter's memory: the last point, the smoothed one, the smoothed velocity.
Sword_Filter :: struct {
	last, point, velocity: [2]f32,
	ready: bool,
}

Sword_Swing :: struct {
	active: bool,
	// The stroke on now: where it started (the swing's start, its last cut or
	// its last reversal), the way the point has gone since, and how long it has
	// been slow.
	start: [2]f32,
	length, slow: f32,
	// The foes this stroke struck (a tondo takes two).
	struck: [2]u32,
	struck_count: u8,
	// A step taken mid-swing (a lunge), a quarter turn the way it sweeps (a
	// spin), and the way the point went last step (for the reversals).
	lunge, spin: bool,
	heading: [2]f32,
	// The cell he stood on as the stroke went.
	cell: grid.Position,
}

// A cut, its factors and what it did (the board colours its trail by them,
// and draws its blood across the chest it cut, `chest`, the way it went, `along`).
Sword_Strike :: struct {
	enemy_id: u32,
	kind: Sword_Kind,
	damage: i32,
	speed, breadth, line, point, way: f32,
	perfect, lunge, spin: bool,
	chest, along: [2]f32,
}

First_Person_Sword :: struct {
	// The way the view looks, a quarter at a time.
	facing: Move_Direction,
	// The blade's point as the mouse put it, and as the swing has followed it on its clock.
	tip, followed: [2]f32,
	filter: Sword_Filter,
	// The point's speed (heights a second, filtered), seconds not stepped yet.
	speed, carry: f32,
	swing: Sword_Swing,
	// The right button held, and the world seconds since it was pressed.
	guard: bool,
	guard_age: f32,
	grapple_recharge: f32,
	// Counted for the board, the lab's sounds and the tests.
	swings, strikes, parries, perfect_parries, grapples: i32,
	last: Sword_Strike,
}

// What the controller asks of the sword this frame.
First_Person_Sword_Input :: struct {
	// The mouse's move (pixels, y down) and the profile's sensitivity.
	mouse: [2]f32,
	sensitivity: f32,
	// The left button held (the blade cuts), the right held (the guard), Ctrl pressed.
	cut, guard, grapple: bool,
	// A quarter turn: -1 left (Q), +1 right (E).
	turn: i8,
	aim: First_Person_Aim,
}

first_person_sword_active :: proc(room: ^Room) -> bool {
	return tactical_first_person_active(room) && room.first_person.weapon == .Sword
}

// Taking the sword up: the view the way he faces, the point near the centre.
first_person_sword_begin :: proc(room: ^Room) {
	if room == nil || room.player == nil { return }
	s := &room.first_person.sword
	s^ = {facing = room.player.tactical.facing, tip = SWORD_TIP_START, followed = SWORD_TIP_START}
}

// The point held inside its ellipse.
sword_clamp_tip :: proc(tip: [2]f32) -> [2]f32 {
	r := SWORD_TIP_REACH
	e := (tip.x/r.x)*(tip.x/r.x)+(tip.y/r.y)*(tip.y/r.y)
	if e <= 1 { return tip }
	return tip/math.sqrt(e)
}

@(private = "file")
sword_alpha :: proc(cutoff, h: f32) -> f32 {
	tau := 1/(2*math.PI*cutoff)
	return 1/(1+tau/h)
}

// One step of the 1€ filter on the point: its filtered speed (heights a second).
sword_filter_step :: proc(f: ^Sword_Filter, point: [2]f32, h: f32) -> f32 {
	if !f.ready {
		f^ = {last = point, point = point, ready = true}
		return 0
	}
	// The velocity from the point itself (the smoothed one lags), smoothed at
	// its own cutoff; it opens the point's.
	raw := (point-f.last)/h
	f.last = point
	a := sword_alpha(SWORD_FILTER_D_CUTOFF, h)
	f.velocity += (raw-f.velocity)*a
	speed := math.sqrt(f.velocity.x*f.velocity.x+f.velocity.y*f.velocity.y)
	cutoff := SWORD_FILTER_MIN_CUTOFF+SWORD_FILTER_BETA*speed
	f.point += (point-f.point)*sword_alpha(cutoff, h)
	return speed
}

// The way a swing went from `start` to `at`.
sword_kind :: proc(start, at: [2]f32) -> Sword_Kind {
	d := at-start
	if d.x == 0 && d.y == 0 { return .None }
	if abs(d.y) > abs(d.x) { return .Fendente if d.y < 0 else .Montante }
	return .Tondo
}

// The formula (sezione 6.4) for a cut at `speed` (heights a second) after a
// stroke of `length` from `start` to `at`, `u` along the blade, the `second`
// foe of a tondo or not, a `lunge` or a `spin` (whose breadth may pass 1).
sword_strike_damage :: proc(speed, length: f32, start, at: [2]f32, u: f32, second := false, lunge := false, spin := false) -> (strike: Sword_Strike) {
	strike.kind = sword_kind(start, at)
	strike.speed = clamp((speed-SWORD_SWING_START)/(SWORD_SPEED_FULL-SWORD_SWING_START), 0, 1)
	strike.breadth = clamp(length/SWORD_LENGTH_FULL, 0.25, 1)
	d := at-start
	chord := math.sqrt(d.x*d.x+d.y*d.y)
	// A spin's turn is breadth, not a crooked line: the line counts the mouse's way alone.
	drawn := length-SWORD_SPIN_LENGTH if spin else length
	c := chord/drawn if drawn > 0 else 1
	strike.line = clamp(0.5+(c-0.4)/(0.9-0.4)*0.5, 0.5, 1)
	strike.point = clamp(1-1.6*abs(u-0.75), 0.4, 1)
	switch strike.kind {
	case .Fendente: strike.way = SWORD_FENDENTE_FACTOR
	case .Tondo: strike.way = SWORD_TONDO_SECOND_FACTOR if second else 1
	case .Montante, .None: strike.way = 1
	}
	damage := SWORD_BASE_DAMAGE*strike.speed*strike.breadth*strike.line*strike.point*strike.way
	strike.perfect = strike.speed >= 0.9 && strike.breadth >= 1 && strike.line >= 0.9 && strike.point >= 0.9
	if strike.perfect { damage *= SWORD_PERFECT_FACTOR }
	strike.lunge, strike.spin = lunge, spin
	if lunge { damage *= SWORD_LUNGE_FACTOR }
	if spin { damage *= SWORD_SPIN_FACTOR }
	strike.damage = max(i32(1), i32(math.round(damage)))
	return
}

// The aim through a point of the screen (heights) off the view along `facing`,
// level.
sword_aim_through :: proc(aim: First_Person_Aim, facing: Move_Direction, at: [2]f32) -> First_Person_Aim {
	look := aim
	half := f32(math.tan(f64(SWORD_FOV)*math.PI/360))*2
	x, y := at.x*half, at.y*half
	look.yaw = first_person_yaw(facing)+math.atan(x)
	look.pitch = math.atan2(y, math.sqrt(1+x*x))
	return look
}

// The cells a cut reaches: the one in front, and for a tondo the two diagonals in front too.
sword_reaches :: proc(room: ^Room, facing: Move_Direction, kind: Sword_Kind, cell: grid.Position) -> bool {
	p := room.player.position
	d := direction_offset(facing)
	if cell == add_position(p, d) { return true }
	if kind != .Tondo { return false }
	side := grid.Position{x = -d.y, y = d.x}
	return cell == add_position(add_position(p, d), side) || cell == add_position(add_position(p, d), {x = -side.x, y = -side.y})
}

// Where a point of `enemy`'s card is on the screen (heights) as the view along
// `facing` shows it from `aim`'s eye (his card where the board drew it, as for
// a shot): `height` up his outline (a part of its top), `across` to his card's
// right (a part of its half width there).
sword_body_on_screen :: proc(room: ^Room, aim: First_Person_Aim, facing: Move_Direction, enemy: Enemy, height: f32, across := f32(0)) -> (at: [2]f32, ok: bool) {
	eye := first_person_eye(room, room.player.position, aim)
	card, lift := first_person_card(enemy, aim)
	yaw := first_person_yaw(facing)
	forward := [2]f32{math.cos(yaw), math.sin(yaw)}
	right := [2]f32{-forward.y, forward.x}
	top := first_person_outline_top(enemy.archetype)
	rel := card+right*(across*first_person_outline_half_width(enemy.archetype, top*height))-eye
	ahead := rel.x*forward.x+rel.y*forward.y
	if ahead <= 0.05 { return }
	side := rel.x*right.x+rel.y*right.y
	eye_y := FIRST_PERSON_EYE_HEIGHT+f32(cell_height(room, room.player.position))*HEIGHT_STEP_DRAWN
	point := f32(cell_height(room, enemy.position))*HEIGHT_STEP_DRAWN+lift+top*height
	half := f32(math.tan(f64(SWORD_FOV)*math.PI/360))*2
	return {side/ahead/half, (point-eye_y)/ahead/half}, true
}

// Where `enemy`'s chest is on the screen (heights): the marks' point on his card.
sword_chest_on_screen :: proc(room: ^Room, aim: First_Person_Aim, facing: Move_Direction, enemy: Enemy) -> (at: [2]f32, ok: bool) {
	return sword_body_on_screen(room, aim, facing, enemy, SWORD_CHEST_HEIGHT)
}

// The points of a foe's body the blade can cut through, as a part of his
// outline's top and of its half width: his chest first, then his spine from
// the waist to the head and across his shoulders (the user found a sideways
// cut a little under the chest went by him: one point was too thin a mark).
@(rodata)
SWORD_BODY_POINTS := [?][2]f32{{SWORD_CHEST_HEIGHT, 0}, {0.45, 0}, {0.75, 0}, {0.3, 0}, {0.88, 0},
	{SWORD_CHEST_HEIGHT, -0.5}, {SWORD_CHEST_HEIGHT, 0.5}}

// The foe the blade cuts as it moves from `before` to `at` (the point on the
// screen), if one: a foe in reach and in sight a point of whose body
// (SWORD_BODY_POINTS) the blade has swept across, where along the blade, and
// where that point is.
@(private = "file")
sword_contact :: proc(room: ^Room, aim: First_Person_Aim, before, at: [2]f32, kind: Sword_Kind) -> (target: Entity_Ref, u: f32, chest: [2]f32, found: bool) {
	s := &room.first_person.sword
	hilt := SWORD_HILT
	cross :: proc(a, b: [2]f32) -> f32 { return a.x*b.y-a.y*b.x }
	blade := at-hilt
	reach := blade.x*blade.x+blade.y*blade.y
	if reach <= 0 { return }
	for enemy in room.enemies {
		if enemy_is_out_of_play(room, enemy.id) || !sword_reaches(room, s.facing, kind, enemy.position) { continue }
		struck := false
		for id in s.swing.struck[:s.swing.struck_count] { struck = struck || id == enemy.id }
		if struck { continue }
		for body in SWORD_BODY_POINTS {
			point, seen := sword_body_on_screen(room, aim, s.facing, enemy, body[0], body[1])
			if !seen { continue }
			was, now := cross(before-hilt, point-hilt), cross(at-hilt, point-hilt)
			if (was > 0) == (now > 0) && now != 0 { continue }
			along := ((point.x-hilt.x)*blade.x+(point.y-hilt.y)*blade.y)/reach
			if along < 0 || along > 1+SWORD_POINT_SLACK { continue }
			// In sight: the view's trace to that point meets him first.
			shot := first_person_trace(room, room.player.position, sword_aim_through(aim, s.facing, point))
			if shot.hit != .Foe || shot.target != enemy_entity(enemy.id) { continue }
			return enemy_entity(enemy.id), min(along, 1), point, true
		}
	}
	return
}

// The cut lands: the foe takes its damage from him, as any blow of his; a
// montante pushes him back a cell if it can.
@(private = "file")
sword_cut :: proc(room: ^Room, target: Entity_Ref, strike: Sword_Strike) -> bool {
	action := make_action(.Attack, PLAYER_ENTITY, entity_target(target), .Opponent)
	action.visual_group = SWORD_VISUAL_GROUP
	if !add_effect(&action, damage_effect(target, strike.damage)) { return false }
	report := resolve_action(room, &action)
	if !report.accepted { return false }
	append_event_log(room.recent_events, &report.events)
	if strike.kind == .Montante && room.phase == .Combat {
		if index, alive := enemy_index_by_id(room, target.id); alive {
			from := room.enemies[index].position
			step := grid.Position{x = sign(from.x-room.player.position.x), y = sign(from.y-room.player.position.y)}
			push := make_action(.Move, PLAYER_ENTITY, cell_target(add_position(from, step)), .Walkable_Cell)
			if add_effect(&push, move_effect(target, add_position(from, step))) {
				pushed := resolve_action(room, &push)
				if pushed.accepted { append_event_log(room.recent_events, &pushed.events) }
			}
		}
	}
	collect_loot_in_magnet_range(room)
	return true
}

// A new stroke of the swing on from `at`: its way counts afresh.
@(private = "file")
sword_restroke :: proc(w: ^Sword_Swing, at: [2]f32) {
	w.start, w.length, w.slow, w.struck_count, w.lunge, w.spin = at, 0, 0, 0, false, false
}

// One SWORD_STEP of the point at `at` (`from`: where the blade sweeps from,
// the last step's point but for a spin): the filter, the swing starting and
// ending, its strokes, a cut. Whether it struck.
@(private = "file")
sword_step :: proc(room: ^Room, input: First_Person_Sword_Input, at: [2]f32, from_spin := false) -> (struck: bool) {
	s := &room.first_person.sword
	h := SWORD_STEP
	moved := at-s.followed
	before := s.followed
	s.followed = at
	s.speed = sword_filter_step(&s.filter, at, h)
	w := &s.swing
	if !w.active {
		if input.cut && !input.guard && s.speed > SWORD_SWING_START {
			w^ = {active = true, start = at, cell = room.player.position}
			s.swings += 1
			// The view's counts: a swing is a blow thrown, a cut one that struck.
			room.first_person.shots += 1
		}
		return
	}
	if !input.cut || input.guard {
		w.active = false
		return
	}
	step := math.sqrt(moved.x*moved.x+moved.y*moved.y)
	if step > 0 {
		heading := moved/step
		// The point turned back: a new stroke from here (the return cuts too).
		if w.heading.x*heading.x+w.heading.y*heading.y < SWORD_REVERSE_COSINE && w.length > 0.02 { sword_restroke(w, before) }
		w.heading = heading
	}
	w.length += step
	// A step taken mid-swing: a lunge.
	if room.player.position != w.cell {
		w.cell = room.player.position
		w.lunge = true
	}
	if s.speed < SWORD_SWING_STOP {
		w.slow += h
		if w.slow >= SWORD_SWING_STOP_SECONDS { w.active = false; return }
	} else {
		w.slow = 0
	}
	if w.length < SWORD_MIN_CUT || s.speed < SWORD_SWING_START { return }
	kind := sword_kind(w.start, at)
	if kind == .None { return }
	if from_spin { before = at-{math.sign(w.heading.x)*2, 0} }
	target, u, chest, found := sword_contact(room, input.aim, before, at, kind)
	if !found { return }
	strike := sword_strike_damage(s.speed, w.length, w.start, at, u, w.struck_count > 0, w.lunge, w.spin)
	strike.enemy_id, strike.chest, strike.along = target.id, chest, at-w.start
	if !sword_cut(room, target, strike) { return }
	s.strikes += 1
	room.first_person.hits += 1
	s.last = strike
	w.struck[w.struck_count] = target.id
	w.struck_count += 1
	// The stroke ends with its cut (a tondo may take a second foe first): the
	// next counts its way from here, with no pause.
	if kind != .Tondo || w.struck_count >= 2 { sword_restroke(w, at) }
	return true
}

// The first foe on the line ahead, SWORD_GRAPPLE_MIN..MAX cells, in sight, with
// no wall, cover or body before it.
@(private = "file")
sword_grapple_target :: proc(room: ^Room, facing: Move_Direction) -> (index: int, distance: int, found: bool) {
	d := direction_offset(facing)
	cell := room.player.position
	for k in 1..=SWORD_GRAPPLE_MAX {
		cell = add_position(cell, d)
		if lasso_cell_is_solid(room, cell) || !tactical_cell_visible(room, cell) { return }
		if at, foe := enemy_index_at(room, cell); foe {
			if k < SWORD_GRAPPLE_MIN || enemy_is_out_of_play(room, room.enemies[at].id) { return }
			return at, k, true
		}
	}
	return
}

// The grapple: the foe pulled to the cell in front and staggered; a boss or a
// miniboss stays, and pulls him to the cell beside it instead.
@(private = "file")
sword_grapple :: proc(room: ^Room) -> bool {
	s := &room.first_person.sword
	index, distance, found := sword_grapple_target(room, s.facing)
	if !found { return false }
	enemy := room.enemies[index]
	target := enemy_entity(enemy.id)
	d := direction_offset(s.facing)
	if enemy_is_boss(enemy.archetype) {
		beside := grid.Position{x = enemy.position.x-d.x, y = enemy.position.y-d.y}
		if distance < 2 || beside == room.player.position { return false }
		pull := make_action(.Move, PLAYER_ENTITY, cell_target(beside), .Walkable_Cell)
		if !add_effect(&pull, move_effect(PLAYER_ENTITY, beside)) { return false }
		report := resolve_action(room, &pull)
		if !report.accepted { return false }
		append_event_log(room.recent_events, &report.events)
	} else {
		front := add_position(room.player.position, d)
		pull := make_action(.Move, PLAYER_ENTITY, cell_target(front), .Walkable_Cell)
		if !add_effect(&pull, move_effect(target, front)) { return false }
		report := resolve_action(room, &pull)
		if !report.accepted { return false }
		append_event_log(room.recent_events, &report.events)
		if room.phase == .Combat {
			if _, alive := enemy_index_by_id(room, enemy.id); alive {
				stagger := make_action(.Trigger, PLAYER_ENTITY, entity_target(target), .Opponent)
				if add_effect(&stagger, apply_status_effect(target, .Stagger, 1, SWORD_GRAPPLE_STAGGER_BEATS)) {
					staggered := resolve_action(room, &stagger)
					append_event_log(room.recent_events, &staggered.events)
				}
			}
		}
	}
	s.grapple_recharge = SWORD_GRAPPLE_RECHARGE
	s.grapples += 1
	return true
}

// The sword this frame (dt seconds): the turn, the guard, the grapple, then the
// point over the frame's steps, its swing and its cuts. Their events are the
// room's recent ones.
first_person_sword_move :: proc(room: ^Room, input: First_Person_Sword_Input, dt: f32) -> (result: Action_Result) {
	if !first_person_sword_active(room) { return .Invalid_Phase }
	clear_event_log(room.recent_events)
	s := &room.first_person.sword
	acted := false
	spin := false
	if input.turn != 0 {
		turn := 1 if input.turn > 0 else 3
		s.facing = Move_Direction((int(s.facing)+turn)%4)
		room.player.tactical.facing = s.facing
		acted = true
		// Turning the way the blade sweeps mid-swing: a spinning cut, the turn's
		// arc counted into the stroke, the blade swept across the new front.
		w := &s.swing
		if w.active && w.heading.x != 0 && (w.heading.x > 0) == (input.turn > 0) {
			w.length += SWORD_SPIN_LENGTH
			w.spin, spin = true, true
		}
	}
	if input.guard && !s.guard { s.guard_age = 0 }
	s.guard = input.guard
	if input.grapple && s.grapple_recharge <= 0 && sword_grapple(room) { acted = true }
	if room.phase != .Combat || !first_person_sword_active(room) { return .Combat_Ended if room.phase != .Combat else .Moved }
	sensitivity := input.sensitivity if input.sensitivity > 0 else 1
	s.tip = sword_clamp_tip(s.tip+[2]f32{input.mouse.x, -input.mouse.y}*SWORD_TIP_PER_PIXEL*sensitivity)
	frame := clamp(dt, 0, SWORD_MAX_FRAME)
	steps := int(math.floor((s.carry+frame)/SWORD_STEP))
	s.carry = s.carry+frame-f32(steps)*SWORD_STEP
	from, to := s.followed, s.tip
	struck := false
	for k in 1..=steps {
		if !first_person_sword_active(room) { break }
		if sword_step(room, input, from+(to-from)*(f32(k)/f32(steps)), spin && k == 1) { struck = true }
		if room.phase != .Combat { break }
	}
	if !acted && !struck { return .None }
	switch finish_player_combat_command(room, 0, false) {
	case .Player_Defeated: return .Player_Defeated
	case .Combat_Ended: return .Combat_Ended
	case .Combat_Continues:
	}
	return .Moved
}

// The world's seconds (tactical_first_person_tick): the guard's age, the grapple's recharge.
@(private)
first_person_sword_tick :: proc(room: ^Room, seconds: f32) {
	s := &room.first_person.sword
	s.guard_age = min(s.guard_age+seconds, 60)
	s.grapple_recharge = max(f32(0), s.grapple_recharge-seconds)
}

// THE PARRY: a blow from in front of him (the cell ahead or its diagonals, or a
// bolt flying down the line ahead) while the guard is up does nothing to him.
// Pressed within SWORD_PERFECT_PARRY seconds before it, the striker close by is
// staggered and wounded, a bolt goes back into its archer. Bombs and blasts,
// traps, hazards and statuses' bites are no blow and never come here. True
// when the blow is parried (resolve_enemy_blow).
sword_parry_blow :: proc(room: ^Room, enemy: ^Enemy, intent: ^Enemy_Intent, ranged: bool, pulse: ^Pulse_Report) -> bool {
	if !first_person_sword_active(room) || pulse == nil || enemy == nil || enemy.archetype == .Bomber { return false }
	s := &room.first_person.sword
	if !s.guard { return false }
	p := room.player.position
	way := grid.Position{x = sign(enemy.position.x-p.x), y = sign(enemy.position.y-p.y)}
	d := direction_offset(s.facing)
	side := grid.Position{x = -d.y, y = d.x}
	front := way == d || way == add_position(d, side) || way == add_position(d, {x = -side.x, y = -side.y})
	if !front { return false }
	source := enemy_entity(enemy.id)
	perfect := s.guard_age <= SWORD_PERFECT_PARRY
	first := pulse.events.count
	record_event(&pulse.events, {kind = .Attack_Deflected, source = source, target = PLAYER_ENTITY, amount = 0})
	mark_attack_events(&pulse.events, first, source, PLAYER_ENTITY, enemy.position, intent.threatened_cells[0],
		intent.threatened_cells[:intent.threatened_cell_count], ranged)
	s.parries += 1
	if !perfect { return true }
	s.perfect_parries += 1
	answer := make_action(.Trigger, PLAYER_ENTITY, entity_target(source), .Opponent)
	if ranged {
		// The bolt flies home.
		_ = add_effect(&answer, damage_effect(source, player_blow_damage(room, intent.damage)))
	} else {
		_ = add_effect(&answer, damage_effect(source, SWORD_PARRY_DAMAGE))
		_ = add_effect(&answer, apply_status_effect(source, .Stagger, 1, SWORD_PARRY_STAGGER_BEATS))
	}
	report := resolve_action(room, &answer)
	if report.accepted {
		mark_attack_events(&report.events, 0, PLAYER_ENTITY, source, room.player.position, enemy.position, {}, ranged, true)
		merge_action_report(pulse, &report)
	}
	return true
}

// The sword's own wounds.
event_is_first_person_cut :: proc(event: Game_Event) -> bool {
	return event.visual_group == SWORD_VISUAL_GROUP
}
