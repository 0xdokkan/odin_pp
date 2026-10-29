package game

import "core:math"
import "core:testing"
import grid "../engine/grid"
import level "../level"

// FIRST PERSON ARCHER's rules (first_person_bow.odin, Fase 6), in the AK's
// test room (walls round a 13x13 board), the player in (6, 6).

// Without foes of its own a foe shut in the south-west corner behind cover
// keeps the fight on, out of the arrows' way; the zones taken away but when
// `zones`.
@(private = "file")
bow_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, spawns: []Enemy_Spawn = nil, zones := false) -> Room {
	shut := [?]Enemy_Spawn{{position = {x = 1, y = 11}, health = 60, attack = 1}}
	cover := [?]grid.Position{{x = 2, y = 11}, {x = 1, y = 10}, {x = 2, y = 10}}
	room := first_person_test_room(t, data, player, spawns if len(spawns) > 0 else shut[:], nil if len(spawns) > 0 else cover[:])
	for foe in room.enemies { lasso_test_hold(&room, foe.id) }
	testing.expect(t, tactical_begin_first_person(&room, 30, .Bow))
	if !zones { room.first_person.bow.zone_count = 0 }
	return room
}

// One frame of `seconds` of the world's with the buttons as given.
@(private = "file")
bow_frame :: proc(room: ^Room, seconds: f32, draw := false, lower := false, yaw := f32(0), pitch := f32(0)) -> Action_Result {
	tactical_first_person_tick(room, seconds)
	return first_person_bow_move(room, {draw = draw, lower = lower, aim = {yaw = yaw, pitch = pitch}})
}

// Drawn `seconds` (in frames of `hz`), then let go along `yaw`, `pitch`.
@(private = "file")
bow_shoot :: proc(room: ^Room, seconds: f32, yaw := f32(0), pitch := f32(0), hz := f32(60)) {
	frames := max(int(math.round(seconds*hz)), 0)
	_ = bow_frame(room, 0, true, yaw = yaw, pitch = pitch)
	for _ in 0..<frames { _ = bow_frame(room, 1/hz, true, yaw = yaw, pitch = pitch) }
	_ = bow_frame(room, 0, false, yaw = yaw, pitch = pitch)
}

// The arrow in flight (or stuck) last loosed.
@(private = "file")
bow_last_arrow :: proc(room: ^Room) -> ^Bow_Arrow {
	for &arrow in room.first_person.bow.arrows { if arrow.state != .None { return &arrow } }
	return nil
}

// The draw (passo 1): full in 1,6 s of the world's, five levels (0 to 4
// bounces), the speed from 12 to 28; let go looses the nocked arrow and the
// next comes up; the left button lowers it, nothing loosed until it is drawn
// again; a step keeps it drawn.
@(test)
test_bow_draw_levels_and_release :: proc(t: ^testing.T) {
	testing.expect_value(t, bow_level(0), i16(0))
	testing.expect_value(t, bow_level(0.2), i16(0))
	testing.expect_value(t, bow_level(0.3), i16(1))
	testing.expect_value(t, bow_level(0.55), i16(2))
	testing.expect_value(t, bow_level(0.8), i16(3))
	testing.expect_value(t, bow_level(0.999), i16(3))
	testing.expect_value(t, bow_level(1), i16(4))
	testing.expect_value(t, bow_launch_speed(0), f32(12))
	testing.expect_value(t, bow_launch_speed(1), f32(28))
	data: level.Level
	player: Player
	room := bow_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	s := &room.first_person.bow
	nocked, next := s.queue[0], s.queue[1]
	_ = bow_frame(&room, 0, true)
	for _ in 0..<60 { _ = bow_frame(&room, 1.0/60, true) }
	testing.expect(t, s.drawing && abs(s.charge-1.0/BOW_DRAW_SECONDS) < 1e-3)
	// A step keeps it drawn.
	_ = try_move_player(&room, .North)
	testing.expect(t, s.drawing)
	for _ in 0..<60 { _ = bow_frame(&room, 1.0/60, true) }
	testing.expect(t, s.charge == 1)
	_ = bow_frame(&room, 0, false)
	testing.expect_value(t, s.loosed, i32(1))
	a := bow_last_arrow(&room)
	if !testing.expect(t, a != nil) { return }
	testing.expect(t, a.kind == nocked && a.full && i32(a.bounces_left) == BOW_LEVELS && a.speed == 28)
	testing.expect(t, s.queue[0] == next && !s.drawing && s.charge == 0)
	// Lowered: the arrow kept, nothing loosed, no draw again until let go.
	nocked = s.queue[0]
	_ = bow_frame(&room, 0, true)
	_ = bow_frame(&room, 0.5, true)
	_ = bow_frame(&room, 0, true, lower = true)
	testing.expect(t, !s.drawing && s.charge == 0)
	_ = bow_frame(&room, 0.5, true)
	testing.expect(t, !s.drawing)
	_ = bow_frame(&room, 0, false)
	testing.expect(t, s.loosed == 1 && s.queue[0] == nocked)
	_ = bow_frame(&room, 0, true)
	testing.expect(t, s.drawing)
}

// The flight (passo 2): a quick shot into the east wall sticks on its face,
// never past it; drawn, it bounces back off it; down, it sticks in the floor.
@(test)
test_bow_arrows_stick_and_bounce_off_walls :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := bow_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	s := &room.first_person.bow
	bow_shoot(&room, 0)
	a := bow_last_arrow(&room)
	if !testing.expect(t, a != nil) { return }
	for _ in 0..<60 {
		_ = bow_frame(&room, 1.0/60)
		testing.expect(t, a.state == .Stuck || a.at.x <= 12+1e-4)
	}
	testing.expect(t, a.state == .Stuck && abs(a.at.x-12) < 1e-3 && abs(a.at.z-6.5) < 1e-3)
	testing.expect_value(t, s.stuck, i32(1))
	// Drawn a quarter: one bounce, back west, faster.
	a.state = .None
	bow_shoot(&room, 0.45*BOW_DRAW_SECONDS)
	a = bow_last_arrow(&room)
	testing.expect_value(t, a.bounces_left, i16(1))
	for _ in 0..<30 { _ = bow_frame(&room, 1.0/60) }
	testing.expect(t, s.bounces >= 1 && a.way.x < 0)
	// Pitched down: into the floor.
	for &arrow in s.arrows { arrow.state = .None }
	bow_shoot(&room, 0, pitch = -0.5)
	a = bow_last_arrow(&room)
	for _ in 0..<30 { _ = bow_frame(&room, 1.0/60) }
	testing.expect(t, a.state == .Stuck && abs(a.at.y) < 1e-3)
}

// No wall is crossed at 60 cells a second, and the flight is the same at any
// frame rate (from contact to contact, as the Pinball).
@(test)
test_bow_flight_is_the_same_at_any_frame_rate :: proc(t: ^testing.T) {
	ends: [3][3]f32
	for hz, index in ([3]f32{30, 144, 240}) {
		data: level.Level
		player: Player
		room := bow_room(t, &data, &player)
		s := &room.first_person.bow
		bow_shoot(&room, BOW_DRAW_SECONDS+0.1, yaw = 0.3)
		a := bow_last_arrow(&room)
		if a == nil { testing.fail(t); level.destroy(&data); destroy_room(&room); continue }
		a.speed, a.bounces_left = BOW_SPEED_MAX, 1000
		frames := int(hz*0.5)
		for _ in 0..<frames {
			_ = bow_frame(&room, 1/hz)
			testing.expectf(t, a.at.x >= 1-1e-3 && a.at.x <= 12+1e-3 && a.at.z >= 1-1e-3 && a.at.z <= 12+1e-3,
				"%v fps: the arrow left the room at %v", hz, a.at)
		}
		ends[index] = a.at
		testing.expect(t, s.bounces > 3)
		level.destroy(&data)
		destroy_room(&room)
	}
	for end in ends[1:] {
		d := end-ends[0]
		testing.expectf(t, d.x*d.x+d.y*d.y+d.z*d.z < 1e-4, "the same flight: %v and %v", ends[0], end)
	}
}

// Into a corner at 45 degrees it comes straight back, and off the player it
// bounces as off a wall: a bounce more, faster, that costs none and never
// hurts him.
@(test)
test_bow_corner_and_the_player_bounce :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := bow_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	s := &room.first_person.bow
	health := room.player.health
	// North-east from (6.5, 6.5): the corner of the walls at (12, 1).
	bow_shoot(&room, 0.55*BOW_DRAW_SECONDS, yaw = -math.PI/4)
	a := bow_last_arrow(&room)
	if !testing.expect(t, a != nil) { return }
	testing.expect_value(t, a.bounces_left, i16(2))
	for _ in 0..<70 { _ = bow_frame(&room, 1.0/60) }
	testing.expectf(t, s.player_bounces == 1 && a.bounced >= 2, "the corner, then the player: %v bounces, %v off him", a.bounced, s.player_bounces)
	testing.expect_value(t, room.player.health, health)
	testing.expect(t, a.speed > bow_launch_speed(0.55)*BOW_BOUNCE_FACTOR*BOW_BOUNCE_FACTOR-1e-3)
}

// The blow (passo 3): the plan's table of speeds, up to half again for the
// bounces; the first foe met takes it and the arrow's status, more of it at a
// full draw.
@(test)
test_bow_damage_and_statuses :: proc(t: ^testing.T) {
	testing.expect_value(t, bow_damage(12, 0), i32(2))
	testing.expect_value(t, bow_damage(28, 0), i32(5))
	testing.expect_value(t, bow_damage(35, 1), i32(7))
	testing.expect_value(t, bow_damage(60, 4), i32(15))
	testing.expect_value(t, bow_damage(60, 9), i32(15))
	testing.expect_value(t, bow_damage(200, 0), i32(10))
	for kind in Bow_Arrow_Kind {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {x = 9, y = 6}, health = 60, attack = 1}}
		room := bow_room(t, &data, &player, spawns[:])
		s := &room.first_person.bow
		s.queue[0] = kind
		bow_shoot(&room, BOW_DRAW_SECONDS+0.1)
		for _ in 0..<30 { _ = bow_frame(&room, 1.0/60) }
		foe := &room.enemies[0]
		testing.expectf(t, s.hits == 1 && foe.health == 60-bow_damage(28, 0), "%v: hits %v, health %v", kind, s.hits, foe.health)
		index, found := status_index(&foe.statuses, BOW_ARROW_STATUS[kind])
		testing.expectf(t, found, "%v: no %v", kind, BOW_ARROW_STATUS[kind])
		if found && kind != .Stun {
			testing.expectf(t, foe.statuses.items[index].potency == BOW_ARROW_STACKS[kind][1], "%v: %v stacks", kind, foe.statuses.items[index].potency)
		}
		testing.expect(t, s.last.enemy_id == foe.id && s.last.damage == 5)
		level.destroy(&data)
		destroy_room(&room)
	}
}

// The zones (passo 4): three on the walls' faces toward open cells round him;
// a bounce on one is faster and costs no bounce; the zone moves two seconds
// later, and all of them every twelve.
@(test)
test_bow_critical_zones :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := bow_room(t, &data, &player, zones = true)
	defer level.destroy(&data)
	defer destroy_room(&room)
	s := &room.first_person.bow
	testing.expect_value(t, s.zone_count, BOW_ZONES)
	for zone, i in s.zones[:s.zone_count] {
		cell := grid.Position{x = int(zone.cell.x), y = int(zone.cell.y)}
		testing.expect(t, lasso_cell_is_solid(&room, cell))
		open := add_position(cell, direction_offset(Move_Direction(zone.face)))
		testing.expect(t, !lasso_cell_is_solid(&room, open))
		for other in s.zones[:i] { testing.expect(t, other.cell != zone.cell || other.face != zone.face) }
	}
	// One on the east wall, straight ahead: a quick shot bounces back off it.
	s.zones[0] = {cell = {12, 6}, face = u8(Move_Direction.West), floor = 0}
	bow_shoot(&room, 0)
	a := bow_last_arrow(&room)
	if !testing.expect(t, a != nil) { return }
	for _ in 0..<40 { _ = bow_frame(&room, 1.0/60) }
	testing.expect(t, s.zone_bounces == 1 && a.bounced >= 1 && a.way.x < 0)
	testing.expect(t, a.speed >= 12*BOW_ZONE_FACTOR-1e-3)
	testing.expect(t, s.zones[0].move_in > 0)
	// The arrow taken away (back off the player it would strike the zone again).
	a.state = .None
	for _ in 0..<150 { _ = bow_frame(&room, 1.0/60) }
	testing.expect(t, s.zones[0].move_in == 0)
	// Every twelve seconds they all move.
	clock := s.zone_clock
	_ = bow_frame(&room, 0.5)
	testing.expect(t, s.zone_clock < clock)
	s.zone_clock = 0.01
	_ = bow_frame(&room, 0.1)
	testing.expect(t, s.zone_clock > BOW_ZONE_MOVE_EVERY-1)
}

// The guide (the user's choice: to the second bounce): from the eye to the
// east wall and back to the west one, a full draw's path.
@(test)
test_bow_guide_to_the_second_bounce :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := bow_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	path: [8]Bow_Path_Point
	count := bow_guide(&room, {yaw = 0.05}, 1, path[:])
	testing.expect(t, count == 3, "the eye and two bounces")
	if count >= 3 {
		testing.expect(t, path[1].bounce && abs(path[1].at.x-12) < 1e-3)
		testing.expect(t, path[2].bounce && abs(path[2].at.x-1) < 1e-3)
	}
	// The guide finds the path and nothing else: no arrow, no count.
	testing.expect(t, room.first_person.bow.bounces == 0 && bow_last_arrow(&room) == nil)
}
