package game

import "core:math"
import "core:testing"
import grid "../engine/grid"
import level "../level"

// FIRST PERSON FENCER's rules (first_person_sword.odin, Fase 4), in the AK's
// test room, the player in (6, 6) looking east.

@(private = "file")
sword_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, spawns: []Enemy_Spawn, obstacles: []grid.Position = nil) -> Room {
	room := first_person_test_room(t, data, player, spawns, obstacles)
	for foe in room.enemies { lasso_test_hold(&room, foe.id) }
	room.player.tactical.facing = .East
	testing.expect(t, tactical_begin_first_person(&room, 30, .Sword))
	return room
}

// The point put at `from` at rest, then moved to `to` in `seconds` at `hz`
// frames a second with the left button held (`cut`), then held still a moment.
@(private = "file")
sword_gesture :: proc(room: ^Room, from, to: [2]f32, seconds, hz: f32, cut := true) {
	s := &room.first_person.sword
	s.tip, s.followed, s.filter, s.swing, s.carry = from, from, {}, {}, 0
	dt := 1/hz
	_ = first_person_sword_move(room, {}, dt)
	frames := int(math.round(seconds*hz))
	step := (to-from)/f32(frames)/SWORD_TIP_PER_PIXEL
	for _ in 0..<frames { _ = first_person_sword_move(room, {mouse = {step.x, -step.y}, cut = cut}, dt) }
	for _ in 0..<int(hz*0.15) { _ = first_person_sword_move(room, {cut = cut}, dt) }
}

// The formula gives the plan's examples (sezione 6.4).
@(test)
test_sword_formula_gives_the_plans_examples :: proc(t: ^testing.T) {
	tondo :: proc(c, length: f32) -> ([2]f32, [2]f32) { return {-0.4, 0}, {-0.4+c*length, 0} }
	fendente :: proc(c, length: f32) -> ([2]f32, [2]f32) { return {0, 0.4}, {0, 0.4-c*length} }
	a, b := tondo(0.95, 0.2)
	testing.expect_value(t, sword_strike_damage(1.5, 0.2, a, b, 0.70).damage, i32(1))
	a, b = tondo(0.90, 0.7)
	testing.expect_value(t, sword_strike_damage(3.5, 0.7, a, b, 0.80).damage, i32(4))
	a, b = fendente(0.95, 0.9)
	perfect := sword_strike_damage(4.0, 0.9, a, b, 0.75)
	testing.expect(t, perfect.damage == 11 && perfect.perfect && perfect.kind == .Fendente)
	testing.expect_value(t, sword_strike_damage(4.0, 0.9, a, b, 0.30).damage, i32(3))
	a, b = tondo(0.20, 1.2)
	shaken := sword_strike_damage(5.0, 1.2, a, b, 0.75)
	testing.expect(t, shaken.damage == 3 && !shaken.perfect, "shaking the mouse beats a clean cut")
	// A tondo's second foe takes less; a montante is no stronger than a tondo.
	a, b = tondo(0.95, 0.9)
	testing.expect(t, sword_strike_damage(4, 0.9, a, b, 0.75, true).damage < sword_strike_damage(4, 0.9, a, b, 0.75).damage)
	testing.expect_value(t, sword_kind({0, -0.3}, {0, 0.3}), Sword_Kind.Montante)
	testing.expect_value(t, sword_kind({0, 0.3}, {0, -0.3}), Sword_Kind.Fendente)
	testing.expect_value(t, sword_kind({-0.3, 0}, {0.3, 0.05}), Sword_Kind.Tondo)
}

// The 1€ filter: still, no speed; a steady move, its speed without lag once
// it runs; the point never leaves its ellipse.
@(test)
test_sword_filter_and_reach :: proc(t: ^testing.T) {
	f: Sword_Filter
	for _ in 0..<60 { testing.expect_value(t, sword_filter_step(&f, {0.1, 0.1}, SWORD_STEP), f32(0)) }
	speed: f32
	point := [2]f32{0.1, 0.1}
	for _ in 0..<120 {
		point.x += 3*SWORD_STEP
		speed = sword_filter_step(&f, point, SWORD_STEP)
	}
	testing.expectf(t, abs(speed-3) < 0.1, "a steady 3 heights a second read as %v", speed)
	far := sword_clamp_tip({3, 3})
	r := SWORD_TIP_REACH
	testing.expect(t, (far.x/r.x)*(far.x/r.x)+(far.y/r.y)*(far.y/r.y) <= 1.0001)
	testing.expect_value(t, sword_clamp_tip({0.2, 0.1}), [2]f32{0.2, 0.1})
}

// The lines a cut runs along to pass the foe's chest at three quarters of the
// blade: a tondo's height, a fendente's or montante's x.
@(private = "file")
sword_lines :: proc(room: ^Room, enemy: Enemy) -> (across_y, down_x: f32) {
	chest, _ := sword_chest_on_screen(room, {}, room.first_person.sword.facing, enemy)
	hilt := SWORD_HILT
	return hilt.y+(chest.y-hilt.y)/0.75, hilt.x+(chest.x-hilt.x)/0.75
}

// The same sideways cut across the foe in front, at 30, 60 and 144 frames a
// second: one cut each, the same damage within 1; too slow, no swing; the
// button let go, no cut.
@(test)
test_sword_cut_is_the_same_at_any_frame_rate :: proc(t: ^testing.T) {
	damages: [3]i32
	for hz, run in ([3]f32{30, 60, 144}) {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {x = 7, y = 6}, health = 60, attack = 1}}
		room := sword_room(t, &data, &player, spawns[:])
		foe := &room.enemies[0]
		health := foe.health
		y, _ := sword_lines(&room, foe^)
		sword_gesture(&room, {-0.8, y}, {0.5, y}, 0.3, hz)
		damages[run] = health-foe.health
		testing.expectf(t, room.first_person.sword.strikes == 1, "%v Hz: %d cuts", hz, room.first_person.sword.strikes)
		testing.expect_value(t, room.first_person.sword.last.kind, Sword_Kind.Tondo)
		// Slowly: no swing at all.
		swings := room.first_person.sword.swings
		sword_gesture(&room, {-0.8, y}, {0.5, y}, 3, hz)
		testing.expect_value(t, room.first_person.sword.swings, swings)
		// Fast but with the button let go: no cut.
		health = foe.health
		sword_gesture(&room, {-0.8, y}, {0.5, y}, 0.3, hz, false)
		testing.expect_value(t, foe.health, health)
		destroy_room(&room)
		level.destroy(&data)
	}
	testing.expectf(t, damages[0] > 0 && abs(damages[0]-damages[1]) <= 1 && abs(damages[1]-damages[2]) <= 1 && abs(damages[0]-damages[2]) <= 1,
		"the cut at 30, 60, 144 Hz: %v", damages)
}

// Out of reach (two cells ahead), no cut; a tondo takes a foe on the diagonal
// in front, a fendente does not; a fendente hits harder than a tondo alike; a
// montante pushes the foe back a cell; the blade is no action (no window time).
@(test)
test_sword_reach_and_kinds :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 8, y = 6}, health = 60, attack = 1}, {position = {x = 7, y = 5}, health = 60, attack = 1}}
	room := sword_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	far, diagonal := &room.enemies[0], &room.enemies[1]
	remaining := room.player.tactical.remaining
	// The diagonal's chest is near the screen's edge: only the point reaches it, across at its height.
	chest, _ := sword_chest_on_screen(&room, {}, .East, diagonal^)
	sword_gesture(&room, {0.8, chest.y}, {-0.82, chest.y}, 0.3, 60)
	testing.expect(t, far.health == 60, "a cut two cells away")
	testing.expect(t, diagonal.health < 60, "the tondo missed the diagonal in front")
	testing.expect(t, room.player.tactical.remaining == remaining, "a cut took window time")
	// Down across the diagonal one: out of a fendente's reach.
	health := diagonal.health
	sword_gesture(&room, {chest.x, 0.45}, {chest.x, -0.45}, 0.25, 60)
	testing.expect_value(t, diagonal.health, health)
	// The foe in front: a fendente and a tondo alike, the fendente harder; a montante pushes him back.
	room.enemies[0].position = {x = 7, y = 6}
	room.enemies[1].position = {x = 3, y = 3}
	front := &room.enemies[0]
	front.health = 60
	y, x := sword_lines(&room, front^)
	sword_gesture(&room, {x, 0.45}, {x, -0.45}, 0.22, 60)
	down := 60-front.health
	front.health = 60
	sword_gesture(&room, {x-0.45, y}, {x+0.45, y}, 0.22, 60)
	across := 60-front.health
	testing.expectf(t, down > across && across > 0, "fendente %d, tondo %d", down, across)
	sword_gesture(&room, {x, -0.45}, {x, 0.45}, 0.22, 60)
	testing.expect(t, room.first_person.sword.last.kind == .Montante && front.position == {x = 8, y = 6}, "the montante did not push him back")
}

// Q and E turn the view a quarter; the steps are quicker with the sword.
@(test)
test_sword_turns_and_steps :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 10, y = 10}, health = 30, attack = 1}}
	room := sword_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	_ = first_person_sword_move(&room, {turn = 1}, 1.0/60)
	testing.expect_value(t, room.first_person.sword.facing, Move_Direction.South)
	_ = first_person_sword_move(&room, {turn = -1}, 1.0/60)
	_ = first_person_sword_move(&room, {turn = -1}, 1.0/60)
	testing.expect_value(t, room.first_person.sword.facing, Move_Direction.North)
	testing.expect_value(t, room.player.tactical.facing, Move_Direction.North)
	testing.expect_value(t, player_move_seconds(&room), SWORD_MOVE_SECONDS)
	room.first_person.weapon = .AK
	testing.expect_value(t, player_move_seconds(&room), TACTICAL_MOVE_SECONDS)
}

// The foe's committed blow from `from` on the player's cell, resolved as on its
// beat; the health it took.
@(private = "file")
sword_blow :: proc(room: ^Room, index: int, damage := i32(5)) -> i32 {
	foe := &room.enemies[index]
	foe.intent = make_attack_intent(room, foe.position, room.player.position, damage)
	health := room.player.health
	pulse: Pulse_Report
	resolve_enemy_intents(room, &pulse, foe.id)
	return health-room.player.health
}

// The guard parries a blow from in front, however long it is held (no limit);
// not one from the side or behind, nor with the guard down; a press just
// before it is a perfect parry: the striker staggered and wounded. No defence
// prompt with the sword.
@(test)
test_sword_parries :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 7, y = 6}, health = 40, attack = 5}, {position = {x = 5, y = 6}, health = 40, attack = 5},
		{position = {x = 7, y = 5}, health = 40, attack = 5}}
	room := sword_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	s := &room.first_person.sword
	testing.expect(t, !offer_defense_qte(&room, &room.enemies[0]), "a defence prompt with the sword")
	// Guard down: hit.
	testing.expect(t, sword_blow(&room, 0) > 0)
	// Guard up long since: parried, the striker untouched; again and again.
	_ = first_person_sword_move(&room, {guard = true}, 1.0/60)
	tactical_first_person_tick(&room, 2)
	for _ in 0..<5 { testing.expect_value(t, sword_blow(&room, 0), i32(0)) }
	testing.expect(t, room.enemies[0].health == 40 && s.parries == 5 && s.perfect_parries == 0)
	// The diagonal in front: parried. Behind: hit.
	testing.expect_value(t, sword_blow(&room, 2), i32(0))
	testing.expect(t, sword_blow(&room, 1) > 0, "a blow from behind parried")
	// Pressed just before: perfect, the striker staggered and wounded.
	_ = first_person_sword_move(&room, {}, 1.0/60)
	_ = first_person_sword_move(&room, {guard = true}, 1.0/60)
	tactical_first_person_tick(&room, 0.1)
	testing.expect_value(t, sword_blow(&room, 0), i32(0))
	testing.expect(t, s.perfect_parries == 1 && room.enemies[0].health == 40-SWORD_PARRY_DAMAGE)
	_, staggered := status_for_entity(&room, enemy_entity(room.enemies[0].id), .Stagger)
	testing.expect(t, staggered, "the perfect parry did not stagger the striker")
}

// A bolt from the archer ahead: parried; perfect, it flies back into him. A
// bomber's bomb is no blow to parry.
@(test)
test_sword_parries_bolts_not_bombs :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{archetype = .Archer, position = {x = 9, y = 6}, health = 30, attack = 4},
		{archetype = .Bomber, position = {x = 6, y = 9}, health = 30, attack = 4}}
	room := sword_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	_ = first_person_sword_move(&room, {guard = true}, 1.0/60)
	tactical_first_person_tick(&room, 0.1)
	testing.expect_value(t, sword_blow(&room, 0), i32(0))
	testing.expect(t, room.enemies[0].health < 30, "the bolt did not fly back")
	// Facing the bomber, the guard up: his bomb still lands.
	_ = first_person_sword_move(&room, {guard = true, turn = 1}, 1.0/60)
	testing.expect(t, sword_blow(&room, 1) > 0, "a bomb parried")
}

// The grapple: the first foe in line 2..4 ahead pulled to the cell in front
// and staggered, then a 3 s recharge; one beside him, or behind cover, is not
// taken; a miniboss stays and pulls him beside it.
@(test)
test_sword_grapple :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 9, y = 6}, health = 30, attack = 1}}
	room := sword_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	foe := &room.enemies[0]
	_ = first_person_sword_move(&room, {grapple = true}, 1.0/60)
	testing.expect(t, foe.position == {x = 7, y = 6}, "not pulled to the cell in front")
	_, staggered := status_for_entity(&room, enemy_entity(foe.id), .Stagger)
	testing.expect(t, staggered && foe.health == 30, "pulled but not staggered, or wounded")
	// Recharging: nothing.
	foe.position = {x = 10, y = 6}
	_ = first_person_sword_move(&room, {grapple = true}, 1.0/60)
	testing.expect(t, foe.position == {x = 10, y = 6})
	tactical_first_person_tick(&room, SWORD_GRAPPLE_RECHARGE)
	// Too far (five cells): nothing.
	foe.position = {x = 11, y = 6}
	_ = first_person_sword_move(&room, {grapple = true}, 1.0/60)
	testing.expect(t, foe.position == {x = 11, y = 6})
	// Beside him: nothing.
	foe.position = {x = 7, y = 6}
	_ = first_person_sword_move(&room, {grapple = true}, 1.0/60)
	testing.expect_value(t, room.first_person.sword.grapples, i32(1))
	// A miniboss: he goes to it.
	foe.position, foe.archetype = {x = 10, y = 6}, .Custodian
	_ = first_person_sword_move(&room, {grapple = true}, 1.0/60)
	testing.expect(t, foe.position == {x = 10, y = 6} && room.player.position == {x = 9, y = 6}, "the miniboss moved, or did not pull him")
}

// Cover in the way stops the grapple.
@(test)
test_sword_grapple_stops_at_cover :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 9, y = 6}, health = 30, attack = 1}}
	cover := [?]grid.Position{{x = 8, y = 6}}
	room := sword_room(t, &data, &player, spawns[:], cover[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	_ = first_person_sword_move(&room, {grapple = true}, 1.0/60)
	testing.expect(t, room.enemies[0].position == {x = 9, y = 6} && room.first_person.sword.grapples == 0)
}
