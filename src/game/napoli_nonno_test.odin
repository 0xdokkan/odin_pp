package game

import "core:math"
import "core:testing"
import level "../level"

// BENVENUTI A NAPOLI's grandpa (napoli_nonno.odin; docs/piano-napoli.md, Fase 4).

// A room with the player at (6,5) and `spawns`, the grandpa taken up (30
// health, 15 gold, 8 damage), the player free to act.
nonno_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, spawns: []Enemy_Spawn) -> Room {
	room := ground_test_room(t, data, player, {enemies = spawns})
	testing.expect(t, tactical_begin_first_person(&room, f32(NAPOLI_NONNO_SECONDS), .Nonno))
	napoli_test_free(&room)
	return room
}

// `seconds` of the world and of his frames, `input` held.
nonno_test_run :: proc(room: ^Room, input: First_Person_Nonno_Input, seconds: f32) {
	frames := int(math.round(seconds*60))
	for _ in 0..<frames {
		tactical_first_person_tick(room, 1.0/60)
		napoli_nonno_move(room, input, 1.0/60)
	}
}

// Face 4: a minute as the grandpa (it never grows), his health the face's number,
// his gold and his blow the card's level's; behind his back; no cards.
@(test)
test_napoli_face_four_turns_him_into_the_grandpa :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 9, y = 9}, health = 50, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	play := napoli_test_play(t, &room, 4, 2)
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect(t, napoli_nonno_active(&room) && FIRST_PERSON_WEAPONS[.Nonno].third_person)
	n := &room.first_person.nonno
	testing.expect_value(t, room.first_person.remaining, f32(NAPOLI_NONNO_SECONDS))
	testing.expect(t, n.health == 40 && n.most == 40 && n.gold == 19 && n.club.damage == 10)
	testing.expect(t, n.draw_left == NAPOLI_NONNO_DRAW_SECONDS && !n.healed && !n.paid)
	testing.expect(t, !tactical_allows_cards(&room))
	testing.expect(t, first_person_body_active(&room) && !first_person_fists_active(&room))
	testing.expect(t, room.first_person.fists.body == [2]f32{6.5, 5.5})
}

// He walks free at 4 cells a second (never the fists' 5); the minute over he is
// back where the grandpa stood.
@(test)
test_napoli_nonno_walks_slower_and_stays_where_he_went :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 10, y = 8}, health = 50, attack = 1}}
	room := nonno_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	nonno_test_run(&room, {wish = {1, 0}}, 0.5)
	v := room.first_person.nonno.body.velocity
	speed := math.sqrt(v.x*v.x+v.y*v.y)
	testing.expectf(t, abs(speed-NAPOLI_NONNO_SPEED) < 0.05, "the grandpa walks at %v", speed)
	nonno_test_run(&room, {wish = {1, 0}}, 0.5)
	testing.expect(t, room.player.position.x >= 9)
	at := room.player.position
	room.first_person.remaining = 0.01
	tactical_first_person_tick(&room, 0.02)
	testing.expect(t, !napoli_nonno_active(&room))
	testing.expect_value(t, room.player.position, at)
}

// No blow before the club is out of his pocket; then the foe in front (within
// his reach and cone) takes it, he standing still for it; behind him, nothing.
@(test)
test_napoli_nonno_blows_after_the_pocket_on_the_foe_in_front :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 7, y = 4}, health = 50, attack = 1}, {position = {x = 5, y = 5}, health = 50, attack = 1}}
	room := nonno_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	n := &room.first_person.nonno
	front, behind := room.enemies[0].id, room.enemies[1].id
	// Looking a little north of east: the foe up and to the right is within 45
	// degrees of it and within his reach (the cell in front would be east).
	yaw := f32(-0.3)
	nonno_test_run(&room, {swing = true, yaw = yaw}, 0.5)
	testing.expect_value(t, n.club.swings, i32(0))
	nonno_test_run(&room, {}, NAPOLI_NONNO_DRAW_SECONDS+0.05)
	testing.expect_value(t, club_way(yaw), [2]i8{1, 0})
	testing.expect_value(t, napoli_nonno_aim(&room, yaw), [2]i8{1, -1})
	nonno_test_run(&room, {swing = true, yaw = yaw}, 1.0/60)
	testing.expect(t, n.club.swings == 1 && n.club.blow.active)
	// He stands still for it, the keys held.
	body := n.body.body
	nonno_test_run(&room, {wish = {1, 0}, yaw = yaw}, CLUB_SWING_SECONDS)
	testing.expect_value(t, n.body.body, body)
	index, _ := enemy_index_by_id(&room, front)
	testing.expect_value(t, room.enemies[index].health, i32(50)-NAPOLI_CLUB_DAMAGE)
	testing.expect_value(t, n.club.last.stagger, NAPOLI_CLUB_STAGGER_BEATS)
	index, _ = enemy_index_by_id(&room, behind)
	testing.expect_value(t, room.enemies[index].health, i32(50))
	// No foe in his cone: the cell in front (looking south, the floor).
	testing.expect_value(t, napoli_nonno_aim(&room, math.PI/2), [2]i8{0, 1})
}

// Q once: he cures half his most health, the player half of his; E once: the gold.
@(test)
test_napoli_nonno_q_cures_both_and_e_pays_once :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 10, y = 8}, health = 50, attack = 1}}
	room := nonno_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	n := &room.first_person.nonno
	player.stats.max_health, player.health = 22, 5
	n.health = 10
	testing.expect_value(t, napoli_nonno_move(&room, {heal = true}, 0), Action_Result.Moved)
	testing.expect(t, n.healed && n.health == 25 && player.health == 16)
	testing.expect(t, n.cured_self == 15 && n.cured_player == 11)
	testing.expect_value(t, arsenal_test_count(room.recent_events, .Napoli_Nonno_Cured), 1)
	testing.expect_value(t, arsenal_test_count(room.recent_events, .Healed), 1)
	napoli_nonno_move(&room, {heal = true}, 0)
	testing.expect(t, n.health == 25 && player.health == 16)
	gold := player.gold
	testing.expect_value(t, napoli_nonno_move(&room, {pay = true}, 0), Action_Result.Moved)
	testing.expect_value(t, player.gold-gold, NAPOLI_PURSE_GOLD)
	napoli_nonno_move(&room, {pay = true}, 0)
	testing.expect_value(t, player.gold-gold, NAPOLI_PURSE_GOLD)
}

// The foes' blows are the grandpa's: the player's health untouched; at none the
// grandpa goes at once and the player is back, as he was.
@(test)
test_napoli_nonno_takes_the_blows_and_goes_at_none :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 7, y = 5}, health = 50, attack = 1}}
	room := nonno_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	n := &room.first_person.nonno
	health := player.health
	blow :: proc(t: ^testing.T, room: ^Room, amount: i32) -> Action_Report {
		action := make_action(.Attack, enemy_entity(room.enemies[0].id))
		testing.expect(t, add_effect(&action, damage_effect(PLAYER_ENTITY, amount)))
		return resolve_action(room, &action)
	}
	report := blow(t, &room, 12)
	testing.expect(t, report.accepted && n.health == 18 && player.health == health && room.phase == .Combat)
	report = blow(t, &room, 40)
	testing.expect(t, report.accepted && !napoli_nonno_active(&room) && !room.first_person.active)
	testing.expect_value(t, player.health, health)
	testing.expect_value(t, room.phase, Room_Phase.Combat)
	left := 0
	for event in report.events.events[:report.events.count] { if event.kind == .Napoli_Nonno_Left { left += 1 } }
	testing.expect_value(t, left, 1)
	// After him the blows are the player's again.
	report = blow(t, &room, 3)
	testing.expect_value(t, player.health, health-3)
}

// The grandpa fits the view's shared bytes (the room stays under 9 KB), his body
// is the fists' own bytes, and a save keeps him.
@(test)
test_napoli_nonno_fits_the_view_and_is_saved :: proc(t: ^testing.T) {
	testing.expect(t, size_of(First_Person_Nonno) <= size_of(First_Person_Bow))
	testing.expect(t, size_of(Room) < 9*1024)
	testing.expect_value(t, offset_of(First_Person_Nonno, body), uintptr(0))
	state := First_Person_State{active = true, weapon = .Nonno, remaining = 41, duration = 60}
	state.nonno = {health = 17, most = 30, gold = 15, draw_left = 0.4, healed = true}
	state.nonno.body.body = {3.2, 4.7}
	state.nonno.club.damage = 8
	loaded, ok := first_person_load(first_person_save(state))
	testing.expect(t, ok && loaded.weapon == .Nonno && loaded.nonno == state.nonno && loaded.fists.body == [2]f32{3.2, 4.7})
}
