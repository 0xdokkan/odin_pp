package hubworld

import "core:math"

// THE HUB AS A PLACE (Fase 8 of docs/piano-griglia.md): a round plaza in which the
// robot walks among seven buildings that stand on its rim with their doors to the
// middle, as in the drawing in docs/immagini/hub-piazza.png. This package is only
// the rules (where the buildings are, how the robot moves among them, when a door
// opens, how see-through a building is): no window, no drawing, so all of it is
// tested without one. render/hub_world.odin draws it, application/campaign_hub.odin
// connects each door to the page it opens.
//
// The plan is seen from above, x to the right and z towards the camera (down the
// screen), the camera looking north (towards smaller z) at the Portal.

Building :: enum u8 { Portal, Storage, Progress, Exit, Memories, Arcade, Casino }
BUILDING_COUNT :: len(Building)

Building_Info :: struct {
	name:     string,
	subtitle: string,
	// Where it stands on the rim: degrees clockwise from north (the Portal), and the
	// distance of its middle from the plaza's.
	bearing, radius: f32,
	// Half its footprint across (x) and deep (z), and how tall it stands.
	half:   [2]f32,
	height: f32,
}

// The names are the plan's (the memories of the creator are "Frammenti" so they are
// not taken for the save slots, "Memorie"; the arcade is the "Sala giochi").
BUILDINGS :: [Building]Building_Info{
	.Portal   = {"PORTALE DEI RICORDI", "si sceglie il bioma e si parte", 0, 14.5, {3.4, 1.4}, 5.8},
	.Storage  = {"DEPOSITO", "zaino, personaggio, archivio", 52, 14, {2.5, 2.0}, 3.4},
	.Progress = {"PROGRESSI", "statistiche, segreti, record", 92, 14, {1.6, 1.6}, 7.2},
	.Exit     = {"USCITA", "salva e cambia memoria", 138, 15, {2.4, 0.7}, 4.6},
	.Memories = {"FRAMMENTI DEL CREATORE", "frammenti e finali", 180, 14, {2.6, 2.6}, 4.2},
	.Arcade   = {"SALA GIOCHI", "i cabinati dei biomi vinti", 270, 14, {2.5, 2.0}, 3.5},
	.Casino   = {"CASINO'", "6 Ranch 7, Tre in fuga, roulette, d20", 312, 14, {2.9, 2.3}, 3.8},
}

PLAZA_RADIUS :: f32(21)
ROBOT_RADIUS :: f32(0.4)
ROBOT_SPEED :: f32(5.2)
// The door: the patch of ground in front of a building's face, this wide each side
// of its middle and this deep. Walking into it opens the building once; the door
// arms again only after the robot has left the patch and DOOR_REARM_MARGIN more.
DOOR_HALF_WIDTH :: f32(1.1)
DOOR_DEPTH :: f32(1.2)
DOOR_REARM_MARGIN :: f32(0.9)
// How far from a building it begins to fade, and where it is gone entirely.
FADE_FAR :: f32(6.5)
FADE_GONE :: f32(2.0)
// A building seen from beside, away from its door, never fades below this much.
FADE_SIDE_MINIMUM :: f32(0.25)

// A wish of 2 numbers (x, z), the unit of the plan.
Vec2 :: [2]f32

World :: struct {
	position:  Vec2,
	// The robot looks to the left of the screen (the paper figure mirrors).
	facing_left: bool,
	moving:    bool,
	// Seconds the robot has walked: the figure's stride.
	stride:    f32,
	// A door is armed when it can open; one that has just opened is not until the
	// robot leaves it.
	armed:     [Building]bool,
	// A place the robot walks to by itself (a click on a building).
	target:    Vec2,
	has_target: bool,
	stuck:     f32,
	// Seconds since the hub opened, for the figures that turn and glow.
	time:      f32,
}

building_info :: proc(b: Building) -> Building_Info {
	all := BUILDINGS
	return all[b]
}

// The way the building looks, from its middle to the plaza's: its front.
building_front :: proc(b: Building) -> Vec2 {
	info := building_info(b)
	a := math.to_radians(info.bearing)
	// Out from the middle is (sin, -cos): clockwise from north, north being -z.
	return {-math.sin(a), math.cos(a)}
}

// To the building's right as seen from in front of it, looking at it.
building_right :: proc(b: Building) -> Vec2 {
	f := building_front(b)
	return {f.y, -f.x}
}

building_center :: proc(b: Building) -> Vec2 {
	info := building_info(b)
	f := building_front(b)
	return {-f.x*info.radius, -f.y*info.radius}
}

// The turn (radians, about the up axis) that takes the building's own frame (x
// across, z to its front) onto the plaza's.
building_yaw :: proc(b: Building) -> f32 {
	f := building_front(b)
	return math.atan2(f.x, f.y)
}

// The building as a station (zone.odin), whose functions do the geometry for both.
building_station :: proc(b: Building) -> Station {
	info := building_info(b)
	return {name = info.name, subtitle = info.subtitle, center = building_center(b), front = building_front(b), half = info.half, height = info.height}
}

// A point of the plaza in the building's own frame: how far to its right of its
// middle, and how far in front of it.
to_local :: proc(b: Building, p: Vec2) -> Vec2 {
	return station_to_local(building_station(b), p)
}

from_local :: proc(b: Building, local: Vec2) -> Vec2 {
	return station_from_local(building_station(b), local)
}

// The middle of the door's patch, where a click on the building sends the robot.
door_center :: proc(b: Building) -> Vec2 {
	return station_door_center(building_station(b))
}

// Whether `p` is on the building's door (grown by `margin` on every side).
in_door :: proc(b: Building, p: Vec2, margin: f32 = 0) -> bool {
	return station_in_door(building_station(b), p, margin)
}

// How far `p` is from the building's footprint (0 inside it).
distance_to_building :: proc(b: Building, p: Vec2) -> f32 {
	return station_distance(building_station(b), p)
}

// How solid the building is drawn, from 1 (whole) to 0 (gone), for a robot at `p`:
// whole from FADE_FAR away, fading as the robot comes nearer, gone from FADE_GONE
// in front of its door so the inside shows, and, beside it or behind it, never
// less than FADE_SIDE_MINIMUM so the building is still there.
building_opacity :: proc(b: Building, p: Vec2) -> f32 {
	d := distance_to_building(b, p)
	t := clamp((d-FADE_GONE)/(FADE_FAR-FADE_GONE), 0, 1)
	// Smooth at both ends.
	t = t*t*(3-2*t)
	info := building_info(b)
	l := to_local(b, p)
	// On the door's side of the face (a hair of slack for the face itself).
	before_door := abs(l.x) <= DOOR_HALF_WIDTH+1.2 && l.y >= info.half.y-0.01
	if before_door { return t }
	return max(t, FADE_SIDE_MINIMUM if d < FADE_FAR else 1)
}

// The robot at the middle of the plaza, every door armed.
place_at_centre :: proc(w: ^World) {
	w^ = {}
	for &armed in w.armed { armed = true }
}

// The robot just outside `b`'s door, looking at the plaza: back from a page or a game.
// Every door is armed, this one too: the robot is already past its patch.
place_before_building :: proc(w: ^World, b: Building) {
	place_at_centre(w)
	info := building_info(b)
	w.position = from_local(b, {0, info.half.y+DOOR_DEPTH+DOOR_REARM_MARGIN+0.6})
}

// A click on a building: the robot walks to its door by itself.
walk_to_building :: proc(w: ^World, b: Building) {
	w.target = door_center(b)
	w.has_target = true
	w.stuck = 0
}

// The building a point of the plaza belongs to, grown by `margin`: what a click lands on.
building_at :: proc(p: Vec2, margin: f32 = 0.6) -> (b: Building, found: bool) {
	best := f32(1e9)
	for candidate in Building {
		d := distance_to_building(candidate, p)
		if d <= margin && d < best { b, found, best = candidate, true, d }
	}
	return
}

// Where a ray from `origin` going `direction` (x, y up, z) first enters the building's
// box, as a distance along the ray: what the pointer is on when it is over a wall.
ray_hits_building :: proc(b: Building, origin, direction: [3]f32) -> (distance: f32, hit: bool) {
	return station_ray_hits(building_station(b), origin, direction)
}

// Pushes `p` out of the buildings and back inside the plaza.
@(private)
resolve :: proc(p: Vec2) -> Vec2 {
	at := p
	for _ in 0..<3 {
		for b in Building {
			info := building_info(b)
			l := to_local(b, at)
			ox := info.half.x+ROBOT_RADIUS-abs(l.x)
			oz := info.half.y+ROBOT_RADIUS-abs(l.y)
			if ox <= 0 || oz <= 0 { continue }
			// Out along the shallower way.
			if ox < oz { l.x += ox if l.x >= 0 else -ox } else { l.y += oz if l.y >= 0 else -oz }
			at = from_local(b, l)
		}
		if length(at) > PLAZA_RADIUS-ROBOT_RADIUS { at = at*((PLAZA_RADIUS-ROBOT_RADIUS)/length(at)) }
	}
	return at
}

// One step of the robot: `wish` is the way the keys ask for (not normalised; zero
// stands still), unless a click sent it somewhere. Returns the building whose door it
// walked into this step, once (the door arms again only after the robot has left it).
step :: proc(w: ^World, wish: Vec2, dt: f32) -> (entered: Building, did_enter: bool) {
	w.time += dt
	way := wish
	if length(way) > 0.01 {
		// A key press takes the robot back from where a click sent it.
		w.has_target = false
	} else if w.has_target {
		to := w.target-w.position
		if length(to) < 0.15 { w.has_target = false } else { way = to }
	}
	w.moving = false
	if length(way) > 0.01 {
		way = normalize(way)
		before := w.position
		w.position = resolve(w.position+way*ROBOT_SPEED*dt)
		moved := length(w.position-before)
		w.moving = moved > ROBOT_SPEED*dt*0.15
		if abs(way.x) > 0.1 { w.facing_left = way.x < 0 }
		if w.moving { w.stride += dt }
		// A click on something the robot cannot reach does not leave it pushing.
		if w.has_target {
			if moved < ROBOT_SPEED*dt*0.15 { w.stuck += dt } else { w.stuck = 0 }
			if w.stuck > 0.5 { w.has_target = false }
		}
	}
	for b in Building {
		in_zone := in_door(b, w.position)
		if in_zone && w.armed[b] && !did_enter {
			w.armed[b] = false
			entered, did_enter = b, true
			w.has_target = false
		} else if !in_door(b, w.position, DOOR_REARM_MARGIN) {
			w.armed[b] = true
		}
	}
	return
}

@(private)
dot :: proc(a, b: Vec2) -> f32 { return a.x*b.x+a.y*b.y }
@(private)
length :: proc(a: Vec2) -> f32 { return math.sqrt(a.x*a.x+a.y*a.y) }
@(private)
normalize :: proc(a: Vec2) -> Vec2 {
	l := length(a)
	if l < 0.0001 { return {} }
	return a/l
}
