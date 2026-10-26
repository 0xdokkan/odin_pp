package game

import "core:math"
import grid "../engine/grid"
import level "../level"

// LIFTS AND GATES IN PLAY (Fase 7 of docs/piano-profondita.md; level/layers.odin has their shafts and gates).
//
// A lift's platform waits at one end of its shaft. One who tries to step onto the landing it is away from calls it,
// and waits: it comes at LIFT_STEPS_PER_SECOND. A step onto it when it is there starts it at once with its rider, who
// is in the shaft until the platform stops at the other end, where the rider stands: meanwhile the rider does nothing,
// and nothing reaches it (the player as in Movimento Ombra, a foe as one out of play). A landing the platform is away
// from, or going from or to, is no floor to step on. Foes call it, wait and ride as the player does. All with steps:
// no key of its own (E is a diagonal and the dodge in combat).
//
// A shortcut's gate opens to a step into its bars from its lever's cell, and from nowhere else.

// How fast a platform goes, in steps a second: 1.5 seconds a layer.
LIFT_STEPS_PER_SECOND :: f32(8)
// The most lifts a room keeps the platforms of.
MAX_ROOM_LIFTS :: 8

Lift_Platform :: struct {
	// The end it rests at, or goes to.
	at:                  u8,
	moving:              bool,
	// The journey's seconds left, and its whole length.
	remaining, duration: f32,
	// Who rides it.
	rider:               Entity_Ref,
	has_rider:           bool,
}

Lift_State :: struct {
	platforms: [MAX_ROOM_LIFTS]Lift_Platform,
	count:     int,
}

// The room's platforms as its map makes them: each at its lift's resting end.
lifts_reset :: proc(room: ^Room) {
	if room == nil { return }
	room.lifts = {}
	if room.level_data == nil { return }
	for lift, i in room.level_data.lifts {
		if i >= MAX_ROOM_LIFTS { break }
		room.lifts.platforms[i] = {at = lift.rest}
		room.lifts.count += 1
	}
}

// The seconds a platform takes from one end of lift `index` to the other.
lift_journey_seconds :: proc(room: ^Room, index: int) -> f32 {
	ends := room.level_data.lifts[index].ends
	rise := abs(cell_height(room, ends[0])-cell_height(room, ends[1]))
	return max(f32(rise)/LIFT_STEPS_PER_SECOND, 0.25)
}

// The lift with a landing on `cell` whose platform the room keeps, and which end that is.
room_lift_at :: proc(room: ^Room, cell: grid.Position) -> (index, end: int, found: bool) {
	if room == nil || room.level_data == nil { return }
	index, end, found = level.lift_at(room.level_data, cell)
	if found && index >= room.lifts.count { found = false }
	return
}

// Whether `cell` is a landing its platform is not resting at (away, or going): no floor to step on.
lift_landing_shut :: proc(room: ^Room, cell: grid.Position) -> bool {
	index, end, found := room_lift_at(room, cell)
	if !found { return false }
	platform := &room.lifts.platforms[index]
	return platform.moving || int(platform.at) != end
}

// Who stands on `cell`: the player, or a foe in play.
@(private = "file")
cell_has_figure :: proc(room: ^Room, cell: grid.Position) -> bool {
	if room.player != nil && room.player.position == cell { return true }
	_, found := enemy_index_at(room, cell)
	return found
}

// One tries to step onto `cell`, a landing its platform is away from: the platform comes, empty, if it rests idle at
// the other end with nobody on it. False if `cell` is no such landing, or the platform is going or held.
lift_call :: proc(room: ^Room, cell: grid.Position) -> bool {
	index, end, found := room_lift_at(room, cell)
	if !found { return false }
	platform := &room.lifts.platforms[index]
	if platform.moving || int(platform.at) == end { return false }
	if cell_has_figure(room, room.level_data.lifts[index].ends[platform.at]) { return false }
	duration := lift_journey_seconds(room, index)
	platform^ = {at = u8(end), moving = true, remaining = duration, duration = duration}
	return true
}

// Which platform `who` rides now, if any.
lift_riding :: proc(room: ^Room, who: Entity_Ref) -> (index: int, riding: bool) {
	if room == nil { return }
	for i in 0..<room.lifts.count {
		platform := &room.lifts.platforms[i]
		if platform.moving && platform.has_rider && platform.rider == who { return i, true }
	}
	return
}

lift_player_riding :: proc(room: ^Room) -> bool {
	if room == nil || room.player == nil { return false }
	_, riding := lift_riding(room, PLAYER_ENTITY)
	return riding
}

// `who` has just stepped onto `cell`: if it is a landing with its platform resting there, the platform goes with it to
// the other end, where `who` stands from now on (in the shaft until the platform stops). A foe riding intends nothing.
lift_board :: proc(room: ^Room, who: Entity_Ref, cell: grid.Position) -> bool {
	index, end, found := room_lift_at(room, cell)
	if !found { return false }
	platform := &room.lifts.platforms[index]
	if platform.moving || int(platform.at) != end { return false }
	duration := lift_journey_seconds(room, index)
	platform^ = {at = u8(1-end), moving = true, remaining = duration, duration = duration, rider = who, has_rider = true}
	set_entity_position(room, who, room.level_data.lifts[index].ends[1-end])
	if who.kind == .Enemy {
		if i, ok := enemy_index_by_id(room, who.id); ok { room.enemies[i].intent = {} }
	}
	return true
}

// The platforms go on: one that reaches its end stops there, and its rider is off the shaft, on the landing.
lift_tick :: proc(room: ^Room, dt: f32) {
	if room == nil || !(dt > 0) { return }
	for i in 0..<room.lifts.count {
		platform := &room.lifts.platforms[i]
		if !platform.moving { continue }
		platform.remaining = max(0, platform.remaining-dt)
		if platform.remaining > 0 { continue }
		platform.moving, platform.has_rider, platform.rider = false, false, {}
	}
}

// How far platform `index` is along its journey: 0 at the end it left, 1 at the end it goes to (resting: 1).
lift_platform_progress :: proc(room: ^Room, index: int) -> f32 {
	platform := room.lifts.platforms[index]
	if !platform.moving || platform.duration <= 0 { return 1 }
	return clamp(1-platform.remaining/platform.duration, 0, 1)
}

// What the foes' way through lift `index` costs, in steps: its journey, and the step onto it.
lift_path_cost :: proc(room: ^Room, index: int) -> int {
	return int(math.ceil(lift_journey_seconds(room, index)/TACTICAL_MOVE_SECONDS))+1
}

// A step from `from` into `cell`, a shut gate: from its lever's cell it opens. False from anywhere else, or no gate.
gate_opens :: proc(room: ^Room, from, cell: grid.Position) -> bool {
	if room == nil || room.level_data == nil { return false }
	index, open, found := level.gate_at(room.level_data, cell)
	if !found || open || room.level_data.gates[index].lever != from { return false }
	return level.open_gate(room.level_data, index)
}
