package game

import "core:math"
import grid "../engine/grid"
import rng "../engine/rng"

// FIRST PERSON ARCHER (docs/piano-prima-persona.md, sezioni 7 e 8, Fase 6; the
// user's choices of 2026-10-29). The bow behind his eyes for ARCHER_SECONDS of
// the world's: he steps on the grid as with the AK, the mouse turns the view.
//
// THE DRAW. The right button held draws the bow, the charge rising to full in
// BOW_DRAW_SECONDS of the world's seconds (it stops with the world); let go, the
// arrow flies; the left button while drawing lowers the bow, the arrow kept on
// the string. Steps keep it drawn. The charge has five levels (a quarter each,
// the last one full): the bounces the arrow may make (0 to 4). The longer draw
// the user chose reaches a harder shot than a short one would: the arrow leaves
// at BOW_SPEED_MIN + BOW_SPEED_DRAW * charge cells a second (12 to 28).
//
// THE FLIGHT. The arrow is a point flying straight along the aim, on the
// world's seconds, stepped from one contact to the next (a cell's edge, the
// floor, a foe, the player) like the Pinball: no wall is crossed at any speed
// and the same room gives the same flight however its seconds are cut into
// frames. A solid thing (a wall, the room's edge, cover, a blocking object, a
// cliff face higher than the arrow) turns it as a mirror turns light: the
// component across the face changes sign (in a corner both). Each bounce is
// one of those left and BOW_BOUNCE_FACTOR faster; with none left the arrow
// sticks where it struck (BOW_STUCK_SECONDS). The floor always stops it. It
// flies out of his sight too, and strikes there. Coming back at the player it
// bounces off him as off a wall, a bounce more that costs none and never hurts
// him (the user's choice). Arrows are endless; one flying into the open is
// gone after BOW_FLIGHT_SECONDS.
//
// THE CRITICAL ZONES. BOW_ZONES targets on the faces of walls toward an open
// cell, within BOW_ZONE_RANGE cells of him and in sight, in the middle third
// of the face and at the eyes' height: an arrow bouncing there flies
// BOW_ZONE_FACTOR faster and gets a bounce more. A zone moves BOW_ZONE_MOVE_USED
// seconds after it is used, and all of them every BOW_ZONE_MOVE_EVERY.
//
// THE BLOW. The first foe the arrow meets (its card, a body of BOW_FOE_RADIUS
// round its cell's centre as high as its outline) takes 2 * speed / 12 at the
// speed it struck at, up to BOW_BOUNCE_BONUS_MAX more for its bounces (an
// eighth a bounce, the user's choice), and the arrow's status. The arrows come
// from the room's own stream, one of five (sezione 8), the nocked one and the
// next shown; a full draw gives more stacks.

ARCHER_SECONDS :: i32(30)
BOW_DRAW_SECONDS :: f32(1.6)
BOW_LEVELS :: i32(4)
BOW_SPEED_MIN :: f32(12)
BOW_SPEED_DRAW :: f32(16)
BOW_SPEED_MAX :: f32(60)
BOW_BOUNCE_FACTOR :: f32(1.25)
BOW_ZONE_FACTOR :: f32(1.6)
BOW_BOUNCE_BONUS :: f32(0.125)
BOW_BOUNCE_BONUS_MAX :: f32(0.5)
// Arrows on the board at once (flying or stuck), and how long they last.
BOW_ARROWS :: 8
BOW_FLIGHT_SECONDS :: f32(4)
BOW_STUCK_SECONDS :: f32(3)
// A foe's body and the player's, round their cells' centres, and the player's height.
BOW_FOE_RADIUS :: f32(0.4)
BOW_PLAYER_RADIUS :: f32(0.35)
BOW_PLAYER_HEIGHT :: f32(1.6)
BOW_ZONES :: 3
BOW_ZONE_RANGE :: 8
BOW_ZONE_MOVE_USED :: f32(2)
BOW_ZONE_MOVE_EVERY :: f32(12)
// How far above and below the eyes' height a zone reaches.
BOW_ZONE_HALF_HEIGHT :: f32(0.35)
// World seconds a frame flies at most (a long frame never leaps).
BOW_MAX_PENDING :: f32(0.5)
BOW_MAX_STEPS :: 256
BOW_EPSILON :: f32(1e-5)
BOW_VISUAL_GROUP :: u32(0x4B_5003)
BOW_SEED_SALT :: u64(0xA4C4_E4B0_7A11_0001)

// The five arrows, one for each of the game's harmful statuses.
Bow_Arrow_Kind :: enum u8 {Poison, Burn, Ice, Stun, Barbed}

@(rodata)
BOW_ARROW_STATUS := [Bow_Arrow_Kind]Status_Kind{.Poison = .Poison, .Burn = .Burn, .Ice = .Slow, .Stun = .Stagger, .Barbed = .Bleed}
// Stacks (Stagger: beats) for a shot not fully drawn, and fully drawn (sezione 8).
@(rodata)
BOW_ARROW_STACKS := [Bow_Arrow_Kind][2]i32{.Poison = {2, 3}, .Burn = {1, 2}, .Ice = {2, 3}, .Stun = {1, 2}, .Barbed = {1, 2}}

Bow_Arrow_State :: enum u8 {None, Flying, Stuck}

Bow_Arrow :: struct {
	kind: Bow_Arrow_Kind,
	state: Bow_Arrow_State,
	// Loosed at a full draw (more stacks).
	full: bool,
	// Once it has left the player: only then does it bounce off him.
	clear: bool,
	// Where it is and where it goes (world units: x east, y up, z south, the
	// board's y; `way` a unit vector), the cell it is in (on the player's
	// layer: bow_cell), its speed (cells a second).
	at, way: [3]f32,
	cell: [2]i32,
	speed: f32,
	// Bounces it may still make, and those made (walls, zones and the player).
	bounces_left, bounced: i16,
	// Seconds flying, or stuck.
	age: f32,
}

// A target on the face of the wall `cell` toward the open cell its `face` way,
// whose floor stands `floor` high; `move_in` seconds until it moves (0: until
// the room's own time moves it).
Bow_Zone :: struct {
	cell: [2]i32,
	face: u8,
	floor: f32,
	move_in: f32,
}

// The cells the bow keeps small (the weapons share their bytes, first_person.odin), on the player's layer.
@(private = "file")
bow_cell :: proc(room: ^Room, cell: [2]i32) -> grid.Position {
	return {x = int(cell.x), y = int(cell.y), layer = room.player.position.layer}
}

@(private = "file")
bow_cell_key :: proc(cell: grid.Position) -> [2]i32 {
	return {i32(cell.x), i32(cell.y)}
}

// The last foe an arrow struck, for the board.
Bow_Hit :: struct {
	enemy_id: u32,
	kind: Bow_Arrow_Kind,
	damage: i32,
	bounced: i16,
	speed: f32,
	point: [3]f32,
}

First_Person_Bow :: struct {
	// The right button held, the bow drawn so far (0..1), and lowered while held.
	drawing, lowered: bool,
	charge: f32,
	// The nocked arrow and the next.
	queue: [2]Bow_Arrow_Kind,
	arrows: [BOW_ARROWS]Bow_Arrow,
	zones: [BOW_ZONES]Bow_Zone,
	zone_count: i32,
	zone_clock: f32,
	// World seconds not flown yet (tactical_first_person_tick).
	pending: f32,
	// Counted for the board, the lab's sounds and the tests.
	loosed, hits, bounces, zone_bounces, player_bounces, stuck: i32,
	last: Bow_Hit,
	// Where the last bounce was, its count and whether a zone made it.
	bounce_at: [3]f32,
	bounce_zone: bool,
	bounce_number: i32,
}

// What the controller asks of the bow this frame.
First_Person_Bow_Input :: struct {
	// The right button held (drawing), the left pressed (lowering).
	draw, lower: bool,
	aim: First_Person_Aim,
}

first_person_bow_active :: proc(room: ^Room) -> bool {
	return tactical_first_person_active(room) && room.first_person.weapon == .Bow
}

// The level of a charge (0 to BOW_LEVELS, the last one full): the bounces it gives.
bow_level :: proc(charge: f32) -> i16 {
	if charge >= 1 { return i16(BOW_LEVELS) }
	return i16(clamp(i32(math.floor(max(charge, 0)*f32(BOW_LEVELS))), 0, BOW_LEVELS-1))
}

bow_launch_speed :: proc(charge: f32) -> f32 {
	return BOW_SPEED_MIN+BOW_SPEED_DRAW*clamp(charge, 0, 1)
}

// What an arrow at `speed` takes, after `bounced` bounces.
bow_damage :: proc(speed: f32, bounced: i16) -> i32 {
	bonus := min(BOW_BOUNCE_BONUS*f32(max(bounced, 0)), BOW_BOUNCE_BONUS_MAX)
	return max(1, i32(math.round(2*min(speed, BOW_SPEED_MAX)/12*(1+bonus))))
}

// The room's own stream for the arrows and zones: from its seed and the run's
// dice as the room begins (create_room), never a clock.
@(private)
bow_room_stream :: proc(player: ^Player, content: Room_Content) -> u64 {
	seed := content.room_seed~BOW_SEED_SALT
	if player != nil { seed ~= player.dice.random_state }
	random := mix_room_seed(seed)
	return random if random != 0 else BOW_SEED_SALT
}

@(private = "file")
bow_next_kind :: proc(room: ^Room) -> Bow_Arrow_Kind {
	if room.bow_random == 0 { room.bow_random = BOW_SEED_SALT }
	return Bow_Arrow_Kind(rng.below_state(&room.bow_random, u64(len(Bow_Arrow_Kind))))
}

// Taking the bow up: two arrows from the room's stream, the zones placed.
first_person_bow_begin :: proc(room: ^Room) {
	if room == nil || room.player == nil { return }
	s := &room.first_person.bow
	s^ = {}
	s.queue = {bow_next_kind(room), bow_next_kind(room)}
	bow_place_zones(room)
}

// The world's seconds for the bow (its draw, its arrows, its zones), flown by
// the frame's command (first_person_bow_move).
@(private)
first_person_bow_tick :: proc(room: ^Room, seconds: f32) {
	s := &room.first_person.bow
	s.pending = min(s.pending+seconds, BOW_MAX_PENDING)
}

// The open cells' faces of walls a zone may stand on: within BOW_ZONE_RANGE of
// the player, in his sight. `skip` zones' faces are left out.
@(private = "file")
bow_zone_candidate :: proc(room: ^Room, open: grid.Position, way: Move_Direction) -> (zone: Bow_Zone, ok: bool) {
	if lasso_cell_is_solid(room, open) || !tactical_cell_visible(room, open) { return }
	d := direction_offset(way)
	wall := add_position(open, d)
	if !lasso_cell_is_solid(room, wall) || !level_in_board(room, wall) { return }
	back := Move_Direction((int(way)+2)%4)
	return {cell = bow_cell_key(wall), face = u8(back), floor = f32(cell_height(room, open))*HEIGHT_STEP_DRAWN}, true
}

@(private = "file")
level_in_board :: proc(room: ^Room, cell: grid.Position) -> bool {
	return room != nil && room.level_data != nil && cell.x >= 0 && cell.y >= 0 && cell.x < room.level_data.tiles.width && cell.y < room.level_data.tiles.height
}

// Zone `index` placed afresh (all of them when -1) on a face the others are not on.
bow_place_zones :: proc(room: ^Room, index := -1) {
	s := &room.first_person.bow
	if index < 0 {
		s.zone_count = 0
		s.zone_clock = BOW_ZONE_MOVE_EVERY
	}
	p := room.player.position
	count := 0
	for dy in -BOW_ZONE_RANGE..=BOW_ZONE_RANGE {
		for dx in -BOW_ZONE_RANGE..=BOW_ZONE_RANGE {
			if dx*dx+dy*dy > BOW_ZONE_RANGE*BOW_ZONE_RANGE { continue }
			for way in Move_Direction {
				if _, ok := bow_zone_candidate(room, grid.Position{x = p.x+dx, y = p.y+dy, layer = p.layer}, way); ok { count += 1 }
			}
		}
	}
	if count == 0 { return }
	place :: proc(room: ^Room, count: int, slot: int) -> bool {
		s := &room.first_person.bow
		if room.bow_random == 0 { room.bow_random = BOW_SEED_SALT }
		pick := int(rng.below_state(&room.bow_random, u64(count)))
		p := room.player.position
		k := 0
		for dy in -BOW_ZONE_RANGE..=BOW_ZONE_RANGE {
			for dx in -BOW_ZONE_RANGE..=BOW_ZONE_RANGE {
				if dx*dx+dy*dy > BOW_ZONE_RANGE*BOW_ZONE_RANGE { continue }
				for way in Move_Direction {
					zone, ok := bow_zone_candidate(room, grid.Position{x = p.x+dx, y = p.y+dy, layer = p.layer}, way)
					if !ok { continue }
					if k != pick { k += 1; continue }
					for other, j in s.zones[:s.zone_count] {
						if j != slot && other.cell == zone.cell && other.face == zone.face { return false }
					}
					s.zones[slot] = zone
					return true
				}
			}
		}
		return false
	}
	if index >= 0 {
		for _ in 0..<8 { if place(room, count, index) { break } }
		s.zones[index].move_in = 0
		return
	}
	for _ in 0..<BOW_ZONES {
		placed := false
		for _ in 0..<8 {
			if place(room, count, int(s.zone_count)) { placed = true; break }
		}
		if placed { s.zone_count += 1 }
		if int(s.zone_count) >= count { break }
	}
}

// Whether a ray at `y` (world height) is stopped entering `cell`: a solid
// thing there, the column's rock, or a floor higher than it (a cliff's face).
@(private = "file")
bow_blocks :: proc(room: ^Room, cell: grid.Position, y: f32) -> bool {
	floor, inside := layer_ray_cell(room, cell, y/HEIGHT_STEP_DRAWN)
	if inside || lasso_cell_is_solid(room, floor) { return true }
	return f32(cell_height(room, floor))*HEIGHT_STEP_DRAWN > y+BOW_EPSILON
}

// Where a ray from `at` along the flat part of `way` (its x and z) first meets
// a circle of `radius` round `centre` (the board's x and y), in units along
// `way`; none behind it.
@(private = "file")
bow_circle :: proc(at, way: [3]f32, centre: [2]f32, radius: f32) -> (t: f32, ok: bool) {
	hx, hz := way.x, way.z
	a := hx*hx+hz*hz
	if a < BOW_EPSILON { return }
	ox, oz := at.x-centre.x, at.z-centre.y
	b := 2*(hx*ox+hz*oz)
	c := ox*ox+oz*oz-radius*radius
	disc := b*b-4*a*c
	if disc < 0 { return }
	root := math.sqrt(disc)
	t0 := (-b-root)/(2*a)
	if t0 >= 0 { return t0, true }
	return
}

Bow_Event :: enum u8 {None, Edge, Floor, Foe, Player, Gone}

// One step of an arrow: what it meets first within `reach` (units along its
// way) and how far: a cell's edge (`cross` the axes it crosses: x, z, or
// both at a corner), its cell's floor, a foe (`foe` its index), the player.
@(private = "file")
bow_next :: proc(room: ^Room, a: ^Bow_Arrow, reach: f32) -> (event: Bow_Event, t: f32, cross: [2]bool, foe: int) {
	big :: f32(1e30)
	t, event = reach, .None
	tx, tz := big, big
	if a.way.x > BOW_EPSILON { tx = (f32(a.cell.x+1)-a.at.x)/a.way.x }
	if a.way.x < -BOW_EPSILON { tx = (f32(a.cell.x)-a.at.x)/a.way.x }
	if a.way.z > BOW_EPSILON { tz = (f32(a.cell.y+1)-a.at.z)/a.way.z }
	if a.way.z < -BOW_EPSILON { tz = (f32(a.cell.y)-a.at.z)/a.way.z }
	here := bow_cell(room, a.cell)
	tx, tz = max(tx, 0), max(tz, 0)
	edge := min(tx, tz)
	if edge <= t {
		t, event = edge, .Edge
		cross = {abs(tx-edge) <= BOW_EPSILON, abs(tz-edge) <= BOW_EPSILON}
	}
	floor := f32(cell_height(room, here))*HEIGHT_STEP_DRAWN
	if a.way.y < -BOW_EPSILON {
		tf := max((a.at.y-floor)/-a.way.y, 0)
		if tf <= t { t, event, cross = tf, .Floor, {} }
	}
	for enemy, index in room.enemies {
		if enemy_is_out_of_play(room, enemy.id) { continue }
		centre := [2]f32{f32(enemy.position.x)+0.5, f32(enemy.position.y)+0.5}
		tc, met := bow_circle(a.at, a.way, centre, BOW_FOE_RADIUS)
		if !met || tc > t { continue }
		height := a.at.y+a.way.y*tc-f32(cell_height(room, enemy.position))*HEIGHT_STEP_DRAWN
		if height <= 0 || height > first_person_outline_top(enemy.archetype) { continue }
		t, event, cross, foe = tc, .Foe, {}, index
	}
	if a.clear {
		p := room.player.position
		tp, met := bow_circle(a.at, a.way, {f32(p.x)+0.5, f32(p.y)+0.5}, BOW_PLAYER_RADIUS)
		height := a.at.y+a.way.y*tp-f32(cell_height(room, p))*HEIGHT_STEP_DRAWN
		if met && tp <= t && height > 0 && height <= BOW_PLAYER_HEIGHT { t, event, cross = tp, .Player, {} }
	}
	return
}

// The zone on the face of `wall` toward `from` that the arrow at `at` meets, if one.
@(private = "file")
bow_zone_at :: proc(room: ^Room, wall, from: grid.Position, at: [3]f32, along_x: bool) -> int {
	s := &room.first_person.bow
	for zone, index in s.zones[:s.zone_count] {
		if zone.cell != bow_cell_key(wall) || add_position(wall, direction_offset(Move_Direction(zone.face))) != from { continue }
		along := at.z-math.floor(at.z) if along_x else at.x-math.floor(at.x)
		height := at.y-zone.floor-FIRST_PERSON_EYE_HEIGHT
		if along >= 1.0/3 && along <= 2.0/3 && abs(height) <= BOW_ZONE_HALF_HEIGHT { return index }
	}
	return -1
}

// A point of an arrow's path, for the board's guide.
Bow_Path_Point :: struct {
	at: [3]f32,
	bounce: bool,
}

// The arrow `a` flown `seconds`: its contacts in order. `live`, it strikes,
// uses the zones and counts; not, it only finds its path (the guide): it stops
// at a foe, or after `bounces` bounces, its points into `path`.
@(private = "file")
bow_fly :: proc(room: ^Room, a: ^Bow_Arrow, seconds: f32, live: bool, path: []Bow_Path_Point = nil, path_count: ^int = nil,
	bounces := i32(-1)) {
	s := &room.first_person.bow
	put :: proc(path: []Bow_Path_Point, count: ^int, at: [3]f32, bounce: bool) {
		if count == nil || count^ >= len(path) { return }
		path[count^] = {at = at, bounce = bounce}
		count^ += 1
	}
	left := seconds
	for _ in 0..<BOW_MAX_STEPS {
		if a.state != .Flying || left <= BOW_EPSILON || (live && room.phase != .Combat) { break }
		if a.age >= BOW_FLIGHT_SECONDS {
			a.state = .None
			put(path, path_count, a.at, false)
			break
		}
		span := min(left, BOW_FLIGHT_SECONDS-a.age)
		event, t, cross, foe := bow_next(room, a, a.speed*span)
		a.at += a.way*t
		spent := t/a.speed
		left -= spent
		a.age += spent
		if !a.clear {
			p := room.player.position
			dx, dz := a.at.x-(f32(p.x)+0.5), a.at.z-(f32(p.y)+0.5)
			if dx*dx+dz*dz > (BOW_PLAYER_RADIUS+0.05)*(BOW_PLAYER_RADIUS+0.05) { a.clear = true }
		}
		switch event {
		case .None, .Gone:
		case .Edge:
			step := [2]int{1 if a.way.x > 0 else -1, 1 if a.way.z > 0 else -1}
			flip := [2]bool{}
			here := bow_cell(room, a.cell)
			wall := here
			if cross.x && cross.y {
				side_x := grid.offset(here, step.x, 0)
				side_z := grid.offset(here, 0, step.y)
				corner := grid.offset(here, step.x, step.y)
				bx, bz := bow_blocks(room, side_x, a.at.y), bow_blocks(room, side_z, a.at.y)
				switch {
				case bx && bz: flip, wall = {true, true}, side_x
				case bx: flip, wall = {true, false}, side_x
				case bz: flip, wall = {false, true}, side_z
				case bow_blocks(room, corner, a.at.y): flip, wall = {true, true}, corner
				}
			} else if cross.x {
				wall = grid.offset(here, step.x, 0)
				flip.x = bow_blocks(room, wall, a.at.y)
			} else {
				wall = grid.offset(here, 0, step.y)
				flip.y = bow_blocks(room, wall, a.at.y)
			}
			if !flip.x && !flip.y {
				a.cell = bow_cell_key(grid.offset(here, step.x if cross.x else 0, step.y if cross.y else 0))
				continue
			}
			zone := bow_zone_at(room, wall, here, a.at, flip.x && !flip.y)
			if a.bounces_left <= 0 && zone < 0 {
				a.state, a.age = .Stuck, 0
				put(path, path_count, a.at, false)
				if live { s.stuck += 1 }
				break
			}
			if flip.x { a.way.x = -a.way.x }
			if flip.y { a.way.z = -a.way.z }
			if zone >= 0 {
				a.speed = min(BOW_SPEED_MAX, a.speed*BOW_ZONE_FACTOR)
				if live {
					s.zones[zone].move_in = BOW_ZONE_MOVE_USED
					s.zone_bounces += 1
				}
			} else {
				a.bounces_left -= 1
				a.speed = min(BOW_SPEED_MAX, a.speed*BOW_BOUNCE_FACTOR)
			}
			a.bounced += 1
			put(path, path_count, a.at, true)
			if live { s.bounces += 1; s.bounce_at, s.bounce_zone, s.bounce_number = a.at, zone >= 0, s.bounces }
			if bounces >= 0 && i32(a.bounced) >= bounces { a.state = .None; break }
		case .Floor:
			a.state, a.age = .Stuck, 0
			put(path, path_count, a.at, false)
			if live { s.stuck += 1 }
		case .Player:
			// Off him as off a wall, a bounce more that costs none.
			p := room.player.position
			n := [2]f32{a.at.x-(f32(p.x)+0.5), a.at.z-(f32(p.y)+0.5)}
			length := math.sqrt(n.x*n.x+n.y*n.y)
			n = n/length if length > BOW_EPSILON else [2]f32{-a.way.x, -a.way.z}
			dot := a.way.x*n.x+a.way.z*n.y
			a.way.x -= 2*dot*n.x
			a.way.z -= 2*dot*n.y
			a.speed = min(BOW_SPEED_MAX, a.speed*BOW_BOUNCE_FACTOR)
			a.bounced += 1
			a.clear = false
			put(path, path_count, a.at, true)
			if live { s.player_bounces += 1; s.bounces += 1; s.bounce_at, s.bounce_zone, s.bounce_number = a.at, false, s.bounces }
			if bounces >= 0 && i32(a.bounced) >= bounces { a.state = .None; break }
		case .Foe:
			put(path, path_count, a.at, false)
			a.state = .None
			if live { bow_strike(room, a^, foe) }
		}
	}
}

// The arrow `a` meets the foe at `index`: its damage and its status, as any
// blow of the player's.
@(private = "file")
bow_strike :: proc(room: ^Room, a: Bow_Arrow, index: int) {
	s := &room.first_person.bow
	enemy := room.enemies[index]
	target := enemy_entity(enemy.id)
	damage := bow_damage(a.speed, a.bounced)
	stacks := BOW_ARROW_STACKS[a.kind][1 if a.full else 0]
	status := BOW_ARROW_STATUS[a.kind]
	action := make_action(.Attack, PLAYER_ENTITY, entity_target(target), .Opponent)
	action.visual_group = BOW_VISUAL_GROUP
	if !add_effect(&action, damage_effect(target, damage)) { return }
	if status == .Stagger { _ = add_effect(&action, apply_status_effect(target, .Stagger, 1, stacks)) }
	else { _ = add_effect(&action, apply_status_effect(target, status, stacks, 0)) }
	report := resolve_action(room, &action)
	if !report.accepted { return }
	append_event_log(room.recent_events, &report.events)
	s.hits += 1
	room.first_person.hits += 1
	s.last = {enemy_id = enemy.id, kind = a.kind, damage = damage, bounced = a.bounced, speed = a.speed, point = a.at}
}

// The arrow a draw of `charge` looses along `aim` from his eye.
@(private = "file")
bow_arrow :: proc(room: ^Room, aim: First_Person_Aim, charge: f32, kind: Bow_Arrow_Kind) -> Bow_Arrow {
	eye := first_person_eye(room, room.player.position, aim)
	base := f32(cell_height(room, room.player.position))*HEIGHT_STEP_DRAWN
	pitch := clamp(aim.pitch, -FIRST_PERSON_PITCH_LIMIT, FIRST_PERSON_PITCH_LIMIT)
	way := [3]f32{math.cos(pitch)*math.cos(aim.yaw), math.sin(pitch), math.cos(pitch)*math.sin(aim.yaw)}
	cell := [2]i32{i32(math.floor(eye.x)), i32(math.floor(eye.y))}
	return {kind = kind, state = .Flying, full = charge >= 1, at = {eye.x, FIRST_PERSON_EYE_HEIGHT+base, eye.y}, way = way,
		cell = cell, speed = bow_launch_speed(charge), bounces_left = bow_level(charge)}
}

// The path an arrow drawn to `charge` would fly along `aim` until its
// `bounces`-th bounce (the guide: the user's choice, to the second), a foe,
// or its stop; its points into `path`, the eye first.
bow_guide :: proc(room: ^Room, aim: First_Person_Aim, charge: f32, path: []Bow_Path_Point, bounces := i32(2)) -> int {
	if !first_person_bow_active(room) || len(path) == 0 { return 0 }
	a := bow_arrow(room, aim, charge, room.first_person.bow.queue[0])
	count := 1
	path[0] = {at = a.at}
	bow_fly(room, &a, BOW_FLIGHT_SECONDS, false, path, &count, bounces)
	if a.state == .Flying { path[min(count, len(path)-1)] = {at = a.at}; count = min(count+1, len(path)) }
	return count
}

// The bow this frame: the draw (on the world's seconds waiting), a release
// looses the nocked arrow; the arrows flown those seconds, their blows into
// room.recent_events; the zones' time.
first_person_bow_move :: proc(room: ^Room, input: First_Person_Bow_Input) -> (result: Action_Result) {
	if !first_person_bow_active(room) { return .Invalid_Phase }
	clear_event_log(room.recent_events)
	s := &room.first_person.bow
	seconds := s.pending
	s.pending = 0
	acted := false
	if !input.draw { s.lowered = false }
	if input.draw && !s.lowered {
		if s.drawing { s.charge = min(f32(1), s.charge+seconds/BOW_DRAW_SECONDS) }
		s.drawing = true
		if input.lower {
			// Lowered: nothing loosed, the arrow kept, until the button is let go.
			s.drawing, s.charge, s.lowered = false, 0, true
		}
	} else if s.drawing && !input.draw {
		slot := -1
		for arrow, index in s.arrows { if arrow.state == .None { slot = index; break } }
		if slot < 0 {
			oldest := f32(-1)
			for arrow, index in s.arrows { if arrow.state == .Stuck && arrow.age > oldest { slot, oldest = index, arrow.age } }
		}
		if slot >= 0 {
			s.arrows[slot] = bow_arrow(room, input.aim, s.charge, s.queue[0])
			s.queue = {s.queue[1], bow_next_kind(room)}
			s.loosed += 1
			room.first_person.shots += 1
			acted = true
		}
		s.drawing, s.charge = false, 0
	}
	for &arrow in s.arrows {
		switch arrow.state {
		case .None:
		case .Stuck:
			arrow.age += seconds
			if arrow.age >= BOW_STUCK_SECONDS { arrow.state = .None }
		case .Flying:
			hits := s.hits
			bow_fly(room, &arrow, seconds, true)
			if s.hits != hits { acted = true }
		}
		if room.phase != .Combat { break }
	}
	if room.phase == .Combat && first_person_bow_active(room) {
		s.zone_clock -= seconds
		if s.zone_clock <= 0 { bow_place_zones(room) }
		for &zone, index in s.zones[:s.zone_count] {
			if zone.move_in <= 0 { continue }
			zone.move_in -= seconds
			if zone.move_in <= 0 { bow_place_zones(room, index) }
		}
	}
	if !acted { return .None }
	switch finish_player_combat_command(room, 0, false) {
	case .Player_Defeated: return .Player_Defeated
	case .Combat_Ended: return .Combat_Ended
	case .Combat_Continues:
	}
	return .Attacked
}

// The bow's own wounds.
event_is_first_person_arrow :: proc(event: Game_Event) -> bool {
	return event.visual_group == BOW_VISUAL_GROUP
}
