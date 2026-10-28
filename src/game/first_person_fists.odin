package game

import "core:math"
import grid "../engine/grid"

// FIRST PERSON BRAWLER's body (docs/piano-prima-persona.md, sezione 5.3 and Fase
// 2): behind his eyes with the fists the player moves free, not cell by cell, a
// circle of FISTS_RADIUS gliding at any angle and stopping anywhere, faster than
// his steps. The cells stay behind the scenes, for the rules that know them: his
// cell (room.player.position) is the one under the body's centre, and the centre
// crossing into the next cell is a step into it, with all a step's effects (a
// pool, a fire, a trap, the terrain, a lift's platform, a gate's lever, a fall),
// but no time spent and no Veleno biting, like the AK's shots.
//
// - Ground moves in the manner of Quake's (PM_Friction, PM_Accelerate): an
//   acceleration toward the wished way and a friction with a stop speed, so he
//   reaches his speed in 0.07 s and stops in under 0.2 s (the acceleration twice
//   the friction, or the friction would hold him under his speed). In the air he
//   steers as on the ground, without the friction.
// - The circle never enters what a step could not: a wall, a cover, an object, a
//   foe's cell, a landing its lift's platform is away from (a push calls the
//   platform), a cliff more than a step up or down. Pushing against them it slides
//   along (out of the nearest point of each cell, as top-down games do).
// - SPACE jumps (height and time to the top give the gravity, as in "Building a
//   Better Jump", GDC 2016): in the air he clears a low cover, lands on a rise up to
//   FISTS_JUMP_RISE steps, and goes down a cliff, falling it (fall_damage).
// - A double tap dashes: a free push of FISTS_DASH_CELLS cells in FISTS_DASH_SECONDS
//   at any angle, stopped by what stops him, then FISTS_DASH_RECHARGE seconds.
// - On a lift's platform he rides it, the body held at its cell.
// - The punches and their critical marks step on the same clock
//   (first_person_punches.odin, first_person_marks.odin).
// - Every rule steps at FISTS_STEP seconds whatever the frame: the same seconds give
//   the same body at 30, 60 or 144 frames a second.

FISTS_RADIUS :: f32(0.3)
// Cells a second (only with the fists: a grid step is 1.25), half on slow ground.
FISTS_SPEED :: f32(5)
FISTS_SLOW_FACTOR :: f32(0.5)
FISTS_ACCELERATE :: f32(20)
FISTS_FRICTION :: f32(10)
FISTS_STOP_SPEED :: f32(2.5)
// The jump: this many steps up, so long to the top (and as long down to his floor).
FISTS_JUMP_STEPS :: f32(4.5)
FISTS_JUMP_RISE_SECONDS :: f32(0.25)
FISTS_GRAVITY :: 2*FISTS_JUMP_STEPS/(FISTS_JUMP_RISE_SECONDS*FISTS_JUMP_RISE_SECONDS)
FISTS_JUMP_SPEED :: 2*FISTS_JUMP_STEPS/FISTS_JUMP_RISE_SECONDS
// A low cover stands about 4 steps (render: FIRST_PERSON_COVER_HEIGHT over
// HEIGHT_STEP_DRAWN). A jump passes over it from halfway up it, the legs tucked:
// a jump from where a walk stopped against it must reach past it before landing.
FISTS_COVER_CLEAR :: f32(2)
// The highest rise a jump lands on.
FISTS_JUMP_RISE :: i32(4)
FISTS_DASH_CELLS :: f32(2)
FISTS_DASH_SECONDS :: f32(0.18)
FISTS_DASH_SPEED :: FISTS_DASH_CELLS/FISTS_DASH_SECONDS
FISTS_DASH_RECHARGE :: f32(1.2)
// The rules' own step, and the most of a frame they take at once.
FISTS_STEP :: f32(1.0/240)
FISTS_MAX_FRAME :: f32(0.25)

First_Person_Fists :: struct {
	// The body's centre on the board (a cell (x, y) spans x..x+1, y..y+1), its
	// velocity (cells a second) and its feet's height (steps, the floor's scale).
	body, velocity: [2]f32,
	feet, rise_speed: f32,
	airborne: bool,
	// In the air: the cell he left and the highest floor since (a fall counts from it).
	takeoff: grid.Position,
	fall_base: f32,
	// The dash: its way, its seconds left, the seconds before the next.
	dash_way: [2]f32,
	dash_left, dash_recharge: f32,
	// Frame seconds not stepped yet (under FISTS_STEP).
	carry: f32,
	// The punch out (none: the fists are ready), its seconds so far and whether
	// it has landed; the press kept for its end (first_person_punches.odin).
	punch, queued: First_Person_Punch,
	punch_clock: f32,
	punch_landed: bool,
	// The critical marks on the nearest foes, their stream, the criticals landed
	// (first_person_marks.odin).
	marks: [FISTS_MARKS]First_Person_Mark,
	random: u64,
	crits: i32,
}

// What the controller asks of the body this frame: the wished way (east, south;
// length up to 1), a jump, a dash and its way when he is not moving (his look),
// the punch pressed (first_person_punch_for) and the view it is thrown along.
First_Person_Fists_Input :: struct {
	wish: [2]f32,
	jump, dash: bool,
	look: [2]f32,
	punch: First_Person_Punch,
	aim: First_Person_Aim,
}

// Taking the fists up: the body at the centre of his cell, on its floor, still.
first_person_fists_begin :: proc(room: ^Room) {
	if room == nil || room.player == nil { return }
	p := room.player.position
	room.first_person.fists = {body = {f32(p.x)+0.5, f32(p.y)+0.5}, feet = f32(cell_height(room, p))}
	fists_marks_begin(room)
}

// The fists in hand, the view on.
first_person_fists_active :: proc(room: ^Room) -> bool {
	return tactical_first_person_active(room) && room.first_person.weapon == .Fists
}

// The body this frame (dt seconds): the jump, the dash and the punch it asks, its
// glide and its fall, the steps its centre takes into the next cells, as world
// moves of no time, and the punches landing. Their events are the room's recent
// ones.
first_person_fists_move :: proc(room: ^Room, input: First_Person_Fists_Input, dt: f32) -> (result: Action_Result) {
	if !first_person_fists_active(room) { return .Invalid_Phase }
	clear_event_log(room.recent_events)
	f := &room.first_person.fists
	if input.jump && !f.airborne && !lift_player_riding(room) {
		f.airborne, f.rise_speed, f.takeoff, f.fall_base = true, FISTS_JUMP_SPEED, room.player.position, f.feet
	}
	if input.dash && f.dash_left <= 0 && f.dash_recharge <= 0 && !lift_player_riding(room) {
		way := fists_unit(input.wish)
		if way == {} { way = fists_unit(input.look) }
		if way != {} { f.dash_way, f.dash_left, f.dash_recharge = way, FISTS_DASH_SECONDS, FISTS_DASH_RECHARGE }
	}
	fists_press(room, input.punch)
	f.carry += clamp(dt, 0, FISTS_MAX_FRAME)
	stepped := false
	for f.carry >= FISTS_STEP {
		f.carry -= FISTS_STEP
		entered, ended := fists_step(room, input.wish)
		struck := false
		if !ended {
			fists_marks_step(room, FISTS_STEP)
			struck = fists_punch_step(room, input.aim, FISTS_STEP)
			ended = room.phase != .Combat || !first_person_fists_active(room)
		}
		stepped = stepped || entered || struck
		if ended { break }
	}
	if !stepped { return .None }
	switch finish_player_combat_command(room, 0, false) {
	case .Player_Defeated: return .Player_Defeated
	case .Combat_Ended: return .Combat_Ended
	case .Combat_Continues:
	}
	return .Moved
}

// One FISTS_STEP of the body: whether its centre stepped into another cell, and
// whether the fight or the view ended.
@(private = "file")
fists_step :: proc(room: ^Room, wish: [2]f32) -> (entered, ended: bool) {
	f := &room.first_person.fists
	h := FISTS_STEP
	f.dash_recharge = max(f32(0), f.dash_recharge-h)
	// Riding a lift's platform: the body is held at its cell until it stops.
	if lift_player_riding(room) {
		p := room.player.position
		f.body, f.velocity, f.feet, f.airborne, f.dash_left = {f32(p.x)+0.5, f32(p.y)+0.5}, {}, f32(cell_height(room, p)), false, 0
		return
	}
	if f.dash_left > 0 {
		f.dash_left = max(f32(0), f.dash_left-h)
		f.velocity = f.dash_way*FISTS_DASH_SPEED
		if f.dash_left <= 0 { f.velocity = f.dash_way*FISTS_SPEED }
	} else {
		fists_accelerate(room, f, wish, h)
	}
	if f.airborne {
		f.rise_speed -= FISTS_GRAVITY*h
		f.feet += f.rise_speed*h
	}
	// The glide, then the steps of its centre and the walls it slides along.
	f.body += f.velocity*h
	entered = fists_cross(room)
	if room.phase != .Combat || !first_person_fists_active(room) { return entered, true }
	fists_slide(room)
	// Landing on his floor.
	ground := f32(cell_height(room, room.player.position))
	if f.airborne && f.feet <= ground {
		f.feet, f.rise_speed, f.airborne = ground, 0, false
		// Past a cover he walks onto the cell beyond (its step brings its own);
		// elsewhere the cell he lands on does what a step into it would.
		if !fists_land_off_cover(room) { fists_touch_down(room) }
		entered = true
	}
	if !f.airborne { f.feet = ground }
	return
}

// Into a cell in the air: his cell changes, nothing there acts on him yet (he
// flies over a trap); a drop of more than a step from the highest floor he has
// left is a fall, paid as he passes its edge.
@(private = "file")
fists_fly :: proc(room: ^Room, cell: grid.Position) -> bool {
	f := &room.first_person.fists
	from := room.player.position
	set_entity_position(room, PLAYER_ENTITY, cell)
	record_event(room.recent_events, {kind = .Moved, source = PLAYER_ENTITY, target = PLAYER_ENTITY, from_position = from, to_position = cell})
	ground := f32(cell_height(room, cell))
	f.fall_base = max(f.fall_base, ground)
	if drop := i32(math.round(f.fall_base-ground)); drop > HEIGHT_FALL_FREE {
		report: Action_Report
		trigger_fall(room, PLAYER_ENTITY, drop, &report)
		append_event_log(room.recent_events, &report.events)
		f.fall_base = ground
	}
	collect_loot_in_magnet_range(room)
	return true
}

// Landing: the cell under him acts as a step into it would (a trap, the terrain,
// a lift's platform starting), unless it is the one he jumped from.
@(private = "file")
fists_touch_down :: proc(room: ^Room) {
	f := &room.first_person.fists
	if room.player.position == f.takeoff { return }
	report: Action_Report
	trigger_cell_entry(room, PLAYER_ENTITY, &report)
	append_event_log(room.recent_events, &report.events)
	_ = lift_board(room, PLAYER_ENTITY, room.player.position)
}

// A step of the body's centre into a cell: walked on the ground, flown in the air.
@(private = "file")
fists_go :: proc(room: ^Room, cell: grid.Position, mode: Movement_Mode) -> bool {
	if room.first_person.fists.airborne { return fists_fly(room, cell) }
	return fists_enter(room, cell, mode)
}

// Whether the body touches the cell (on his own layer): its circle over any of it.
first_person_fists_touches :: proc(room: ^Room, cell: grid.Position) -> bool {
	if !first_person_fists_active(room) || cell.layer != room.player.position.layer { return false }
	b := room.first_person.fists.body
	closest := [2]f32{clamp(b.x, f32(cell.x), f32(cell.x)+1), clamp(b.y, f32(cell.y), f32(cell.y)+1)}
	d := b-closest
	return d.x*d.x+d.y*d.y < FISTS_RADIUS*FISTS_RADIUS
}

// Whether a foe's blow on its intent's cells reaches the player. Behind his eyes
// with the fists (the user's choices, Fase 2): it does when his body touches any
// of them, once however many; in the air a blow on the ground passes under him,
// one from afar (ranged: an arrow, a bomb) does not. Otherwise as ever: his cell
// among them.
enemy_blow_reaches_player :: proc(room: ^Room, intent: ^Enemy_Intent, ranged: bool) -> bool {
	if !first_person_fists_active(room) { return enemy_intent_cell_is_threatened(intent, room.player.position) }
	if room.first_person.fists.airborne && !ranged { return false }
	for index in 0..<intent.threatened_cell_count {
		cell := intent.threatened_cells[index]
		if cell == room.player.position || first_person_fists_touches(room, cell) { return true }
	}
	return false
}

// Landing with the centre over a low cover: past it if the cell beyond is open,
// else back on his side of it.
@(private = "file")
fists_land_off_cover :: proc(room: ^Room) -> (entered: bool) {
	f := &room.first_person.fists
	from := room.player.position
	cx, cy := int(math.floor(f.body.x)), int(math.floor(f.body.y))
	step := grid.Position{x = clamp(cx-from.x, -1, 1), y = clamp(cy-from.y, -1, 1)}
	if step == {} { return }
	cover, _ := layer_step(room, from, step)
	if !obstacle_at(room, cover) { return }
	beyond, open, _ := fists_neighbour(room, cover, step, f.feet, false)
	if open && fists_enter(room, beyond, fists_mode(room, from, beyond)) {
		lo := [2]f32{f32(beyond.x), f32(beyond.y)}
		f.body = {clamp(f.body.x, lo.x+FISTS_RADIUS, lo.x+1-FISTS_RADIUS), clamp(f.body.y, lo.y+FISTS_RADIUS, lo.y+1-FISTS_RADIUS)}
		return true
	}
	lo := [2]f32{f32(from.x), f32(from.y)}
	f.body = {clamp(f.body.x, lo.x+FISTS_RADIUS, lo.x+1-FISTS_RADIUS), clamp(f.body.y, lo.y+FISTS_RADIUS, lo.y+1-FISTS_RADIUS)}
	return
}

// Quake's ground friction and acceleration toward the wished way; in the air no
// friction. Slow ground halves the speed sought.
@(private = "file")
fists_accelerate :: proc(room: ^Room, f: ^First_Person_Fists, wish: [2]f32, h: f32) {
	if !f.airborne {
		speed := math.sqrt(f.velocity.x*f.velocity.x+f.velocity.y*f.velocity.y)
		if speed > 0 {
			drop := max(speed, FISTS_STOP_SPEED)*FISTS_FRICTION*h
			f.velocity *= max(speed-drop, 0)/speed
		}
	}
	way := fists_unit(wish)
	if way == {} { return }
	amount := min(f32(1), math.sqrt(wish.x*wish.x+wish.y*wish.y))
	top := FISTS_SPEED*amount*(FISTS_SLOW_FACTOR if fists_slow_ground(room) else 1)
	// A punch out holds him back to half his speed.
	if f.punch != .None { top *= FISTS_PUNCH_SPEED_FACTOR }
	current := f.velocity.x*way.x+f.velocity.y*way.y
	add := top-current
	if add <= 0 { return }
	f.velocity += way*min(FISTS_ACCELERATE*top*h, add)
}

// The expedition's slow ground under him (expedition_step_seconds doubles a step there).
@(private = "file")
fists_slow_ground :: proc(room: ^Room) -> bool {
	s := &room.player.tactical
	if !s.config.expedition { return false }
	ground := expedition_terrain(s.config.expedition_biome, room.player.position)
	return ground == .Sand || ground == .Water || ground == .Snow || ground == .Swamp
}

@(private = "file")
fists_unit :: proc(v: [2]f32) -> [2]f32 {
	length := math.sqrt(v.x*v.x+v.y*v.y)
	if length < 1e-4 { return {} }
	return v/length
}

// Whether the body may go from his cell `from` into its neighbour `step` away,
// and which cell (on whichever layer) that is; `over` when it is a low cover the
// body is high enough to pass over, but not to stand on.
fists_neighbour :: proc(room: ^Room, from, step: grid.Position, feet: f32, airborne: bool) -> (cell: grid.Position, open, over: bool) {
	cell, _ = layer_step(room, from, step)
	if _, foe := enemy_index_at(room, cell); foe { return }
	ground := cell_height(room, cell)
	if obstacle_at(room, cell) {
		over = airborne && feet >= f32(ground)+FISTS_COVER_CLEAR
		return
	}
	if cell_blocks_movement(room, cell) { return }
	// Diagonally, not between two solids.
	if step.x != 0 && step.y != 0 {
		side_x, _ := layer_step(room, from, {x = step.x})
		side_y, _ := layer_step(room, from, {y = step.y})
		if cell_blocks_movement(room, side_x) && cell_blocks_movement(room, side_y) { return }
	}
	if airborne {
		// In the air: onto what is no higher than his feet (and a jump's rise at most).
		open = f32(ground) <= feet+1e-3 && ground-cell_height(room, from) <= FISTS_JUMP_RISE
	} else {
		open = !step_height_blocked(room, from, cell)
	}
	return
}

// The centre's steps into the cells it has reached, one neighbour at a time; over
// a low cover, the step lands past it. A cell that cannot be entered stays solid
// (fists_slide pushes the body back out of it). Whether any step was taken.
@(private = "file")
fists_cross :: proc(room: ^Room) -> (entered: bool) {
	f := &room.first_person.fists
	for _ in 0..<4 {
		from := room.player.position
		cx, cy := int(math.floor(f.body.x)), int(math.floor(f.body.y))
		dx, dy := cx-from.x, cy-from.y
		if dx == 0 && dy == 0 { return }
		step := grid.Position{x = clamp(dx, -1, 1), y = clamp(dy, -1, 1)}
		cell, open, over := fists_neighbour(room, from, step, f.feet, f.airborne)
		if !open && over {
			// A leap over a cover: only once the centre is past it, onto the cell beyond.
			if abs(dx) < 2 && abs(dy) < 2 { return }
			beyond, beyond_open, _ := fists_neighbour(room, cell, step, f.feet, f.airborne)
			if !beyond_open || !fists_go(room, beyond, .Teleport) { return }
			entered = true
			continue
		}
		if !open {
			// A diagonal into a corner may still go along one side of it.
			if step.x != 0 && step.y != 0 {
				side := grid.Position{x = step.x} if abs(f.body.x-(f32(from.x)+0.5)) >= abs(f.body.y-(f32(from.y)+0.5)) else grid.Position{y = step.y}
				side_cell, side_open, _ := fists_neighbour(room, from, side, f.feet, f.airborne)
				if side_open && fists_go(room, side_cell, fists_mode(room, from, side_cell)) {
					entered = true
					continue
				}
			}
			// Pushing into a landing its platform is away from calls the platform;
			// into a gate from its lever, opens it.
			_ = lift_call(room, cell) || gate_opens(room, from, cell)
			return
		}
		if !fists_go(room, cell, fists_mode(room, from, cell)) { return }
		entered = true
		if room.phase != .Combat { return }
	}
	return
}

// A walk onto a neighbour, or a jump onto a rise a walk could not climb (a
// teleport checks only where it lands: the rise is the jump's).
@(private = "file")
fists_mode :: proc(room: ^Room, from, cell: grid.Position) -> Movement_Mode {
	return .Teleport if rise_height_blocked(room, from, cell) else .Traverse
}

// A step of the body into `cell`: a world move, with everything a step brings
// (falls, pools, fires, traps, terrain, a lift's platform), and no time.
@(private = "file")
fists_enter :: proc(room: ^Room, cell: grid.Position, mode: Movement_Mode) -> bool {
	query := query_entity_movement(room, PLAYER_ENTITY, cell, mode)
	if !movement_query_is_clear(&query) { return false }
	action := make_action(.Move, PLAYER_ENTITY, cell_target(cell), .Walkable_Cell)
	if !add_effect(&action, move_effect(PLAYER_ENTITY, cell, mode)) { return false }
	report := resolve_action(room, &action)
	if !report.accepted { return false }
	append_event_log(room.recent_events, &report.events)
	collect_loot_in_magnet_range(room)
	return true
}

// The body out of every solid cell round his own (what fists_neighbour shuts),
// out of the nearest point of each: against a wall it slides along it.
@(private = "file")
fists_slide :: proc(room: ^Room) {
	f := &room.first_person.fists
	from := room.player.position
	for _ in 0..<3 {
		moved := false
		for y in -1..=1 {
			for x in -1..=1 {
				if x == 0 && y == 0 { continue }
				cell, open, over := fists_neighbour(room, from, {x = x, y = y}, f.feet, f.airborne)
				if open || over { continue }
				// Already over a cover in the air: it does not throw him back.
				if f.airborne && obstacle_at(room, cell) && int(math.floor(f.body.x)) == cell.x && int(math.floor(f.body.y)) == cell.y { continue }
				lo := [2]f32{f32(from.x+x), f32(from.y+y)}
				closest := [2]f32{clamp(f.body.x, lo.x, lo.x+1), clamp(f.body.y, lo.y, lo.y+1)}
				d := f.body-closest
				dist2 := d.x*d.x+d.y*d.y
				if dist2 >= FISTS_RADIUS*FISTS_RADIUS { continue }
				moved = true
				if dist2 < 1e-10 {
					// The centre inside it: back toward his own cell's centre.
					centre := [2]f32{f32(from.x)+0.5, f32(from.y)+0.5}
					back := fists_unit(centre-f.body)
					f.body = closest+back*FISTS_RADIUS
				} else {
					dist := math.sqrt(dist2)
					f.body += d/dist*(FISTS_RADIUS-dist)
				}
				// What pushes the body back takes its speed into it. Pushed against a
				// landing its platform is away from, it calls the platform; against a
				// gate from its lever, it opens it (as a step into them does).
				n := fists_unit(d)
				into := f.velocity.x*n.x+f.velocity.y*n.y
				if into < 0 {
					f.velocity -= n*into
					if x == 0 || y == 0 { _ = lift_call(room, cell) || gate_opens(room, from, cell) }
				}
			}
		}
		if !moved { break }
	}
	// Never out of his own cell's column: the centre stays where the rules have him.
	lo := [2]f32{f32(from.x), f32(from.y)}
	cx, cy := int(math.floor(f.body.x)), int(math.floor(f.body.y))
	if cx != from.x || cy != from.y {
		cell, open, over := fists_neighbour(room, from, {x = clamp(cx-from.x, -1, 1), y = clamp(cy-from.y, -1, 1)}, f.feet, f.airborne)
		if !open && !over && !(f.airborne && obstacle_at(room, cell)) {
			f.body = {clamp(f.body.x, lo.x+0.001, lo.x+0.999), clamp(f.body.y, lo.y+0.001, lo.y+0.999)}
		}
	}
}
