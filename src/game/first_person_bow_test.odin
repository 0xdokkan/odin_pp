package game

import "core:math"
import "core:testing"
import grid "../engine/grid"
import level "../level"

// FIRST PERSON ARCHER's rules (first_person_bow.odin, Fase 6), in the AK's
// test room (walls round a 13x13 board), the player in (6, 6).

// Without foes of its own a foe shut in the south-west corner behind walls
// keeps the fight on, out of the arrows' way (they fly over a cover); the
// zones taken away but when `zones`.
@(private = "file")
bow_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, spawns: []Enemy_Spawn = nil, zones := false) -> Room {
	shut := [?]Enemy_Spawn{{position = {x = 1, y = 11}, health = 60, attack = 1}}
	walls := [?]grid.Position{{x = 2, y = 11}, {x = 1, y = 10}, {x = 2, y = 10}}
	room := first_person_test_room(t, data, player, spawns if len(spawns) > 0 else shut[:], walls = nil if len(spawns) > 0 else walls[:])
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
	testing.expect(t, a.kind == nocked && a.draw == .Full && i32(a.bounces_left) == BOW_LEVELS && a.speed == 28)
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

// The nock (the user's choice, 2026-10-29): after an arrow the next draw waits
// BOW_NOCK_SECONDS; held through it, the draw starts as it is nocked.
@(test)
test_bow_nock_time :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := bow_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	s := &room.first_person.bow
	bow_shoot(&room, 0.5)
	testing.expect_value(t, s.loosed, i32(1))
	testing.expect(t, abs(s.nock-BOW_NOCK_SECONDS) < 1e-5)
	_ = bow_frame(&room, 0.1, true)
	testing.expect(t, !s.drawing, "drawn before the next arrow was nocked")
	_ = bow_frame(&room, 0, false)
	testing.expect_value(t, s.loosed, i32(1))
	_ = bow_frame(&room, 0.06, true)
	testing.expect(t, s.drawing, "held through the nock, the draw did not start")
	// Clicking as fast as the frames go: no more than one arrow a nock.
	for &arrow in s.arrows { arrow.state = .None }
	loosed := s.loosed
	for frame in 0..<120 { _ = bow_frame(&room, 1.0/60, frame%2 == 0) }
	testing.expectf(t, f32(s.loosed-loosed) <= 2/BOW_NOCK_SECONDS+1, "%d arrows in two seconds", s.loosed-loosed)
}

// The quick shot (the user's choice, 2026-10-29): let go below the first level
// it falls in an arc, takes 1, shows no guide; aimed level it misses a foe
// three cells off about one time in three (only by falling short), aimed
// higher it carries further; its fall is the same at any frame rate.
@(test)
test_bow_quick_shot_falls_and_misses :: proc(t: ^testing.T) {
	testing.expect(t, bow_quick(0) && bow_quick(0.24) && !bow_quick(0.25))
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 9, y = 6}, health = 999, attack = 1}}
	room := bow_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	s := &room.first_person.bow
	path: [8]Bow_Path_Point
	testing.expect_value(t, bow_guide(&room, {}, 0.1, path[:]), 0)
	foe := &room.enemies[0]
	SHOTS :: 300
	for shot in 0..<SHOTS {
		for &arrow in s.arrows { arrow.state = .None }
		s.nock = 0
		// The view kept on (it lasts 30 s), the foe whole and without the arrows' statuses.
		room.first_person.remaining = 30
		foe.health, foe.statuses = 999, {}
		bow_shoot(&room, 0)
		a := bow_last_arrow(&room)
		if a == nil { testing.expectf(t, false, "shot %d: none loosed (%d loosed, active %v, phase %v, nock %f)", shot, s.loosed, first_person_bow_active(&room), room.phase, s.nock); return }
		testing.expect(t, a.draw == .Quick && a.speed >= BOW_QUICK_SPEED[0]-1e-4 && a.speed <= BOW_QUICK_SPEED[1]+1e-4)
		for _ in 0..<60 { _ = bow_frame(&room, 1.0/60) }
		// It never gets past the foe: it strikes him or falls short.
		testing.expectf(t, a.state == .None || (a.state == .Stuck && abs(a.at.y) < 1e-3 && a.at.x < 9.2), "%v at %v", a.state, a.at)
	}
	testing.expectf(t, s.hits > SHOTS/2 && s.hits < SHOTS*4/5, "%d of %d struck (about two in three wanted)", s.hits, SHOTS)
	testing.expect_value(t, s.last.damage, BOW_QUICK_DAMAGE)
	// Aimed higher it carries further: every one strikes him.
	hits := s.hits
	for _ in 0..<30 {
		for &arrow in s.arrows { arrow.state = .None }
		s.nock = 0
		room.first_person.remaining = 30
		foe.health, foe.statuses = 999, {}
		bow_shoot(&room, 0, pitch = 0.2)
		for _ in 0..<60 { _ = bow_frame(&room, 1.0/60) }
	}
	testing.expectf(t, s.hits-hits >= 24, "aimed higher %d of 30 struck", s.hits-hits)
	// The same fall at any frame rate.
	ends: [3][3]f32
	for hz, index in ([3]f32{30, 120, 240}) {
		other_data: level.Level
		other_player: Player
		other := bow_room(t, &other_data, &other_player)
		bow_shoot(&other, 0, pitch = 0.3, hz = hz)
		a := bow_last_arrow(&other)
		if a != nil {
			a.speed = 7
			for _ in 0..<int(math.round(hz*0.4)) { _ = bow_frame(&other, 1/hz) }
			ends[index] = a.at
		} else { testing.fail(t) }
		level.destroy(&other_data)
		destroy_room(&other)
	}
	for end in ends[1:] {
		d := end-ends[0]
		testing.expectf(t, d.x*d.x+d.y*d.y+d.z*d.z < 1e-4, "the same fall: %v and %v", ends[0], end)
	}
	// Where an arc of its speed and fall would have it.
	want := FIRST_PERSON_EYE_HEIGHT+7*math.sin(f32(0.3))*0.4-0.5*BOW_QUICK_GRAVITY*0.4*0.4
	testing.expectf(t, abs(ends[0].y-want) < 0.05, "at %f high, not on its arc's %f", ends[0].y, want)
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
	// Drawn to the first level, its bounce taken away: it sticks.
	bow_shoot(&room, 0.3*BOW_DRAW_SECONDS)
	a := bow_last_arrow(&room)
	if !testing.expect(t, a != nil) { return }
	a.bounces_left = 0
	for _ in 0..<60 {
		_ = bow_frame(&room, 1.0/60)
		testing.expect(t, a.state == .Stuck || a.at.x <= 12+1e-4)
	}
	testing.expect(t, a.state == .Stuck && abs(a.at.x-12) < 1e-3 && abs(a.at.z-6.5) < 1e-3)
	testing.expect_value(t, s.stuck, i32(1))
	// Drawn a quarter: one bounce, back west, faster.
	a.state = .None
	s.nock = 0
	bow_shoot(&room, 0.45*BOW_DRAW_SECONDS)
	a = bow_last_arrow(&room)
	testing.expect_value(t, a.bounces_left, i16(1))
	for _ in 0..<30 { _ = bow_frame(&room, 1.0/60) }
	testing.expect(t, s.bounces >= 1 && a.way.x < 0)
	// Pitched down: into the floor.
	for &arrow in s.arrows { arrow.state = .None }
	s.nock = 0
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

// The blow (passo 3; the user's choice of 2026-10-29): a straight shot as its
// speed squared, from 4 at the first level to 14 full, each faster bounce and
// up to half again for the bounces; drawn, it deals more a second than the
// AK's six a second at every level, the draw and the nock counted; the first
// foe met takes it and the arrow's status, more of it at a full draw.
@(test)
test_bow_damage_and_statuses :: proc(t: ^testing.T) {
	testing.expect_value(t, bow_damage(16, 16, 0), i32(4))
	testing.expect_value(t, bow_damage(20, 20, 0), i32(7))
	testing.expect_value(t, bow_damage(24, 24, 0), i32(10))
	testing.expect_value(t, bow_damage(28, 28, 0), i32(14))
	testing.expect_value(t, bow_damage(28, 35, 1), i32(19))
	testing.expect_value(t, bow_damage(28, 60, 4), i32(44))
	testing.expect_value(t, bow_damage(28, 60, 9), i32(44))
	testing.expect_value(t, bow_damage(200, 200, 0), i32(63))
	ak := f32(FIRST_PERSON_SHOTS_PER_SECOND*FIRST_PERSON_SHOT_DAMAGE)
	for step in 0..=15 {
		charge := 0.25+0.05*f32(step)
		v := bow_launch_speed(charge)
		seconds := charge*BOW_DRAW_SECONDS+BOW_NOCK_SECONDS+1.0/60
		testing.expectf(t, f32(bow_damage(v, v, 0))/seconds > ak, "drawn %f: %f a second, the AK %f", charge, f32(bow_damage(v, v, 0))/seconds, ak)
	}
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
		testing.expectf(t, s.hits == 1 && foe.health == 60-bow_damage(28, 28, 0), "%v: hits %v, health %v", kind, s.hits, foe.health)
		index, found := status_index(&foe.statuses, BOW_ARROW_STATUS[kind])
		testing.expectf(t, found, "%v: no %v", kind, BOW_ARROW_STATUS[kind])
		if found && kind != .Stun {
			testing.expectf(t, foe.statuses.items[index].potency == BOW_ARROW_STACKS[kind][1], "%v: %v stacks", kind, foe.statuses.items[index].potency)
		}
		testing.expect(t, s.last.enemy_id == foe.id && s.last.damage == 14)
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
	// One on the east wall, straight ahead: an arrow with no bounce left bounces back off it.
	s.zones[0] = {cell = {12, 6}, face = u8(Move_Direction.West), floor = 0}
	bow_shoot(&room, 0.3*BOW_DRAW_SECONDS)
	a := bow_last_arrow(&room)
	if !testing.expect(t, a != nil) { return }
	a.bounces_left = 0
	launch := a.speed
	// Faster than a quick shot: caught on its way back, before the player.
	for _ in 0..<28 { _ = bow_frame(&room, 1.0/60) }
	testing.expect(t, s.zone_bounces == 1 && a.bounced >= 1 && a.way.x < 0)
	testing.expect(t, a.speed >= launch*BOW_ZONE_FACTOR-1e-3)
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

// The low things (the user found an invisible wall over them, 2026-10-29): a
// cover, a low wall and a barrel three cells east stop an arrow only as high
// as they are drawn. Level, it flies over them to the east wall; pitched
// down, it bounces off their face; falling onto a low wall or a cover, it
// sticks on its top. A zone never stands on a low one.
@(test)
test_bow_flies_over_low_things :: proc(t: ^testing.T) {
	Low :: enum {Cover, Fence, Barrel}
	east := grid.Position{x = 9, y = 6}
	for low in Low {
		data: level.Level
		player: Player
		shut := [?]Enemy_Spawn{{position = {x = 1, y = 11}, health = 60, attack = 1}}
		walls := [?]grid.Position{{x = 2, y = 11}, {x = 1, y = 10}, {x = 2, y = 10}}
		cover := [?]grid.Position{east}
		fence := [?]grid.Position{east}
		barrel := [?]Grid_Object_Spawn{{kind = .Barrel, position = east}}
		room := first_person_test_room(t, &data, &player, shut[:], cover[:] if low == .Cover else nil,
			barrel[:] if low == .Barrel else nil, walls = walls[:], fences = fence[:] if low == .Fence else nil)
		for foe in room.enemies { lasso_test_hold(&room, foe.id) }
		testing.expect(t, tactical_begin_first_person(&room, 30, .Bow))
		s := &room.first_person.bow
		for zone in s.zones[:s.zone_count] { testing.expectf(t, zone.cell != {9, 6}, "%v: a zone on it", low) }
		s.zone_count = 0
		// Level: over it, into the east wall.
		bow_shoot(&room, 0.3*BOW_DRAW_SECONDS)
		a := bow_last_arrow(&room)
		if a == nil { testing.fail(t); level.destroy(&data); destroy_room(&room); continue }
		a.bounces_left = 0
		for _ in 0..<60 { _ = bow_frame(&room, 1.0/60) }
		testing.expectf(t, a.state == .Stuck && abs(a.at.x-12) < 1e-3, "%v: level, it stopped at %v", low, a.at)
		// Pitched down: off its face, back west.
		a.state = .None
		s.nock = 0
		bow_shoot(&room, 0.3*BOW_DRAW_SECONDS, pitch = -0.29)
		a = bow_last_arrow(&room)
		if a == nil { testing.fail(t); level.destroy(&data); destroy_room(&room); continue }
		for _ in 0..<12 { _ = bow_frame(&room, 1.0/60) }
		testing.expectf(t, s.bounces == 1 && a.way.x < 0, "%v: pitched down, %d bounces, at %v", low, s.bounces, a.at)
		// Falling onto it: on its top (a barrel stands higher: on its face).
		for &arrow in s.arrows { arrow.state = .None }
		s.nock = 0
		bow_shoot(&room, 0)
		a = bow_last_arrow(&room)
		if a == nil { testing.fail(t); level.destroy(&data); destroy_room(&room); continue }
		a.speed = 11
		for _ in 0..<60 { _ = bow_frame(&room, 1.0/60) }
		top := BOW_COVER_TOP if low == .Cover else BOW_FENCE_TOP
		if low == .Barrel {
			testing.expectf(t, a.state == .Stuck && abs(a.at.x-9) < 1e-3, "barrel: the falling arrow stopped at %v", a.at)
		} else {
			testing.expectf(t, a.state == .Stuck && a.at.x > 9 && a.at.x < 10 && abs(a.at.y-top) < 1e-3, "%v: the falling arrow stopped at %v", low, a.at)
		}
		level.destroy(&data)
		destroy_room(&room)
	}
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
