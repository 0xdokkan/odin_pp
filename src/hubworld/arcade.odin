package hubworld

import "core:math"

// INSIDE THE ARCADE HALL (Fase 11 of docs/piano-griglia.md): a room like the casino's
// and the depot's. The robot arrives at the middle; a place for each of the twelve
// minigames stands in a half circle round it, the way out to the plaza behind. The
// cabinets the player has unlocked (by winning biomes) are lit and can be played; the
// other places hold a cabinet under a cloth with no name, so the hall gives no hint
// of which biome a game belongs to.

ARCADE_SLOTS :: 12

// The way out is the last station, after the twelve places.
ARCADE_EXIT :: ARCADE_SLOTS

ARCADE_ROOM_RADIUS :: f32(15)

// How far from the middle the places stand, and the arc they cover, in degrees either
// side of north.
ARCADE_RING_RADIUS :: f32(12.5)
ARCADE_ARC_HALF :: f32(80)

// The hall with `unlocked` cabinets lit (the first ones); the others are decor under a cloth.
arcade_room :: proc(unlocked: int) -> Room {
	room := Room{name = "LA SALA GIOCHI", radius = ARCADE_ROOM_RADIUS, count = ARCADE_SLOTS+1, exit = ARCADE_EXIT}
	lit := clamp(unlocked, 0, ARCADE_SLOTS)
	for k in 0..<ARCADE_SLOTS {
		angle := math.to_radians(-ARCADE_ARC_HALF+f32(k)*(2*ARCADE_ARC_HALF)/f32(ARCADE_SLOTS-1))
		center := Vec2{math.sin(angle), -math.cos(angle)}*ARCADE_RING_RADIUS
		room.stations[k] = {center = center, front = normalize({-center.x, -center.y}), half = {0.9, 0.75}, height = 3.0, decor = k >= lit}
	}
	// A wall of the octagon, behind the robot's arrival.
	room.stations[ARCADE_EXIT] = {name = "PIAZZA", subtitle = "torna in piazza", center = {0, 14.5}, front = {0, -1}, half = {1.5, 0.5}, height = 4.4}
	return room
}

// A colour (a hue in degrees) for the cabinet of minigame `game`, apart from the
// others' (the golden angle, so that any twelve are well separated).
arcade_hue :: proc(game: int) -> f32 {
	return f32((game*137)%360)
}

// What the hall shows of the campaign: how many cabinets are lit, which minigame each
// lit place holds, its best stars (0 to 3), and its name and record line.
Arcade_View :: struct {
	count:  int,
	game:   [ARCADE_SLOTS]int,
	stars:  [ARCADE_SLOTS]u8,
	title:  [ARCADE_SLOTS]string,
	record: [ARCADE_SLOTS]string,
}
