package hubworld

import "core:math"

// THE ZONES BEHIND THE PLAZA'S DOORS (Fase 9 of docs/piano-griglia.md, reused by the
// depot and the arcade hall of Fasi 10 and 11): a room the robot walks in, with a few
// stations along its walls, each with its door. Like the plaza, this is only rules, no
// window and no drawing. The way between zones is a dissolve (Fade) that switches
// from one to the other while the screen is dark.

MAX_STATIONS :: 8

// A thing in a room (or a building of the plaza) the robot can walk up to: a box on
// the floor, turned so its front looks along `front` (a unit vector, plan coordinates
// as in hubworld.odin: x to the right, z towards the camera), with its door in front.
Station :: struct {
	name:     string,
	subtitle: string,
	center:   Vec2,
	front:    Vec2,
	// Half its footprint across (x, along `station_right`) and deep (z, along `front`).
	half:     Vec2,
	height:   f32,
	// Only a solid thing to walk round (the depot's crates): no door, nothing to click.
	decor:    bool,
}

// To the station's right as seen from in front of it, looking at it.
station_right :: proc(s: Station) -> Vec2 {
	return {s.front.y, -s.front.x}
}

// The turn (radians, about the up axis) that takes the station's own frame (x across,
// z to its front) onto the plan's.
station_yaw :: proc(s: Station) -> f32 {
	return math.atan2(s.front.x, s.front.y)
}

// A point of the plan in the station's own frame: how far to its right of its middle,
// and how far in front of it.
station_to_local :: proc(s: Station, p: Vec2) -> Vec2 {
	d := p-s.center
	return {dot(d, station_right(s)), dot(d, s.front)}
}

station_from_local :: proc(s: Station, local: Vec2) -> Vec2 {
	return s.center+station_right(s)*local.x+s.front*local.y
}

// The middle of the door's patch, where a click on the station sends the robot.
station_door_center :: proc(s: Station) -> Vec2 {
	return station_from_local(s, {0, s.half.y+DOOR_DEPTH*0.5})
}

// Whether `p` is on the station's door (grown by `margin` on every side).
station_in_door :: proc(s: Station, p: Vec2, margin: f32 = 0) -> bool {
	l := station_to_local(s, p)
	return abs(l.x) <= DOOR_HALF_WIDTH+margin && l.y >= s.half.y-margin && l.y <= s.half.y+DOOR_DEPTH+margin
}

// How far `p` is from the station's footprint (0 inside it).
station_distance :: proc(s: Station, p: Vec2) -> f32 {
	l := station_to_local(s, p)
	dx := max(abs(l.x)-s.half.x, 0)
	dz := max(abs(l.y)-s.half.y, 0)
	return math.sqrt(dx*dx+dz*dz)
}

// Where a ray from `origin` going `direction` (x, y up, z) first enters the station's
// box, as a distance along the ray: what the pointer is on when it is over it.
station_ray_hits :: proc(s: Station, origin, direction: [3]f32) -> (distance: f32, hit: bool) {
	o := station_to_local(s, {origin.x, origin.z})
	right, front := station_right(s), s.front
	d := [3]f32{dot({direction.x, direction.z}, right), direction.y, dot({direction.x, direction.z}, front)}
	low := [3]f32{-s.half.x, 0, -s.half.y}
	high := [3]f32{s.half.x, s.height, s.half.y}
	start := [3]f32{o.x, origin.y, o.y}
	near, far := f32(0), f32(1e9)
	for axis in 0..<3 {
		if abs(d[axis]) < 0.00001 {
			if start[axis] < low[axis] || start[axis] > high[axis] { return 0, false }
			continue
		}
		t1, t2 := (low[axis]-start[axis])/d[axis], (high[axis]-start[axis])/d[axis]
		if t1 > t2 { t1, t2 = t2, t1 }
		near, far = max(near, t1), min(far, t2)
		if near > far { return 0, false }
	}
	return near, true
}

// A room: an octagon whose inscribed circle has this radius (the robot stays inside
// it), the stations along its walls, and which of them is the way out.
Room :: struct {
	name:     string,
	radius:   f32,
	count:    int,
	exit:     int,
	stations: [MAX_STATIONS]Station,
}

Room_World :: struct {
	position:    Vec2,
	facing_left: bool,
	moving:      bool,
	// Seconds the robot has walked: the figure's stride.
	stride:      f32,
	// A door is armed when it can open; one that has just opened is not until the
	// robot leaves it.
	armed:       [MAX_STATIONS]bool,
	// A place the robot walks to by itself (a click on a station).
	target:      Vec2,
	has_target:  bool,
	stuck:       f32,
	// Seconds since the room opened, for the figures that turn and glow.
	time:        f32,
}

// The robot at the middle of the room, every door armed.
room_place_at_centre :: proc(w: ^Room_World) {
	w^ = {}
	for &armed in w.armed { armed = true }
}

// The robot just outside station `i`'s door: back from a game. Every door is armed,
// this one too: the robot is already past its patch.
room_place_before :: proc(room: ^Room, w: ^Room_World, i: int) {
	room_place_at_centre(w)
	s := room.stations[i]
	w.position = station_from_local(s, {0, s.half.y+DOOR_DEPTH+DOOR_REARM_MARGIN+0.6})
}

// A click on a station: the robot walks to its door by itself.
room_walk_to :: proc(room: ^Room, w: ^Room_World, i: int) {
	w.target = station_door_center(room.stations[i])
	w.has_target = true
	w.stuck = 0
}

// The station a point of the room belongs to, grown by `margin`: what a click lands on.
room_station_at :: proc(room: ^Room, p: Vec2, margin: f32 = 0.6) -> (i: int, found: bool) {
	best := f32(1e9)
	for k in 0..<room.count {
		if room.stations[k].decor { continue }
		d := station_distance(room.stations[k], p)
		if d <= margin && d < best { i, found, best = k, true, d }
	}
	return
}

@(private)
room_resolve :: proc(room: ^Room, p: Vec2) -> Vec2 {
	at := p
	for _ in 0..<3 {
		for k in 0..<room.count {
			s := room.stations[k]
			l := station_to_local(s, at)
			ox := s.half.x+ROBOT_RADIUS-abs(l.x)
			oz := s.half.y+ROBOT_RADIUS-abs(l.y)
			if ox <= 0 || oz <= 0 { continue }
			if ox < oz { l.x += ox if l.x >= 0 else -ox } else { l.y += oz if l.y >= 0 else -oz }
			at = station_from_local(s, l)
		}
		if length(at) > room.radius-ROBOT_RADIUS { at = at*((room.radius-ROBOT_RADIUS)/length(at)) }
	}
	return at
}

// One step of the robot in the room: as the plaza's `step`, for stations. Returns the
// station whose door it walked into this step, once.
room_step :: proc(room: ^Room, w: ^Room_World, wish: Vec2, dt: f32) -> (entered: int, did_enter: bool) {
	w.time += dt
	way := wish
	if length(way) > 0.01 {
		w.has_target = false
	} else if w.has_target {
		to := w.target-w.position
		if length(to) < 0.15 { w.has_target = false } else { way = to }
	}
	w.moving = false
	if length(way) > 0.01 {
		way = normalize(way)
		before := w.position
		w.position = room_resolve(room, w.position+way*ROBOT_SPEED*dt)
		moved := length(w.position-before)
		w.moving = moved > ROBOT_SPEED*dt*0.15
		if abs(way.x) > 0.1 { w.facing_left = way.x < 0 }
		if w.moving { w.stride += dt }
		if w.has_target {
			if moved < ROBOT_SPEED*dt*0.15 { w.stuck += dt } else { w.stuck = 0 }
			if w.stuck > 0.5 { w.has_target = false }
		}
	}
	for k in 0..<room.count {
		if room.stations[k].decor { continue }
		in_zone := station_in_door(room.stations[k], w.position)
		if in_zone && w.armed[k] && !did_enter {
			w.armed[k] = false
			entered, did_enter = k, true
			w.has_target = false
		} else if !station_in_door(room.stations[k], w.position, DOOR_REARM_MARGIN) {
			w.armed[k] = true
		}
	}
	return
}

// THE CASINO'S HALL, as in the user's drawing (docs/immagini/hub-casino.png): the
// robot arrives at the middle; 6 Ranch 7 up to the left, Tre in fuga up to the right,
// the way out to the plaza at the right, the roulette down to the left and the d20
// duel down to the right.
Casino_Station :: enum u8 { Ranch, Run, Roulette, Dice, Plaza }

CASINO_ROOM_RADIUS :: f32(15)

casino_room :: proc() -> Room {
	room := Room{name = "IL CASINÒ", radius = CASINO_ROOM_RADIUS, count = len(Casino_Station), exit = int(Casino_Station.Plaza)}
	put :: proc(room: ^Room, which: Casino_Station, name, subtitle: string, center, half: Vec2, height: f32) {
		room.stations[which] = {name = name, subtitle = subtitle, center = center, front = normalize({-center.x, -center.y}), half = half, height = height}
	}
	put(&room, .Ranch, "6 RANCH 7", "slot del ranch", {-8.5, -8}, {2.4, 1.4}, 3.6)
	put(&room, .Run, "TRE IN FUGA", "dinosauro, Panda o moto", {8.5, -8}, {3.2, 1.6}, 3.4)
	put(&room, .Roulette, "ROULETTE EUROPEA", "un solo zero", {-8.5, 8}, {2.3, 2.3}, 1.6)
	put(&room, .Dice, "DUELLO DEL D20", "vince il dado più alto", {8.5, 8}, {2.6, 1.7}, 1.7)
	put(&room, .Plaza, "PIAZZA", "torna in piazza", {14.5, 0}, {1.5, 0.5}, 4.4)
	return room
}

// THE DISSOLVE between zones: the screen goes dark, the zone changes at the darkest
// moment (once), the screen comes back.
FADE_SECONDS :: f32(0.22)

Fade :: struct {
	time:     f32,
	active:   bool,
	switched: bool,
}

fade_begin :: proc(f: ^Fade) {
	f^ = {active = true}
}

// Advances the dissolve; true on the one step that crosses the darkest moment.
fade_step :: proc(f: ^Fade, dt: f32) -> (switch_now: bool) {
	if !f.active { return false }
	f.time += dt
	if !f.switched && f.time >= FADE_SECONDS {
		f.switched = true
		switch_now = true
	}
	if f.time >= FADE_SECONDS*2 { f.active = false }
	return
}

// How dark the screen is, 0 (clear) to 1 (black).
fade_alpha :: proc(f: Fade) -> f32 {
	if !f.active { return 0 }
	t := clamp(f.time/FADE_SECONDS, 0, 2)
	k := t if t <= 1 else 2-t
	return k*k*(3-2*k)
}

// THE CASINO'S SOUNDS: a light murmur, now and then a slot's jingle, the wheel's ticks
// while the robot is near the roulette. The rules say when; the application plays them.
Ambience_Cue :: enum u8 { Murmur, Slot, Wheel }

Ambience :: struct {
	murmur, slot, wheel: f32,
	state: u32,
}

ambience_start :: proc(seed: u32 = 1) -> Ambience {
	return {murmur = 0.4, slot = 2.5, wheel = 0, state = seed*2654435761+1}
}

// A pseudo-random number in [0, 1), deterministic for the same seed.
@(private)
ambience_random :: proc(a: ^Ambience) -> f32 {
	a.state = a.state*1664525+1013904223
	return f32(a.state>>8)/f32(1<<24)
}

ambience_step :: proc(a: ^Ambience, dt: f32, near_wheel: bool) -> (cues: bit_set[Ambience_Cue]) {
	a.murmur -= dt
	a.slot -= dt
	if a.murmur <= 0 {
		cues += {.Murmur}
		a.murmur = 3.5+ambience_random(a)*1.5
	}
	if a.slot <= 0 {
		cues += {.Slot}
		a.slot = 6+ambience_random(a)*5
	}
	if near_wheel {
		a.wheel -= dt
		if a.wheel <= 0 {
			cues += {.Wheel}
			a.wheel = 0.45
		}
	} else {
		a.wheel = 0
	}
	return
}
