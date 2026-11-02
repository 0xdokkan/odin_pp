package game

import "core:math"
import "core:testing"
import grid "../engine/grid"
import level "../level"

// BENVENUTI A NAPOLI's club (first_person_club.odin; docs/piano-napoli.md,
// Fase 2): the view behind his back, its blow from above on the cell in front,
// the stagger that wears.

// A room with the player at (6,5) and `spawns`, the club taken up (8 damage),
// the player free to act.
club_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, spawns: []Enemy_Spawn) -> Room {
	room := ground_test_room(t, data, player, {enemies = spawns})
	testing.expect(t, tactical_begin_first_person(&room, 30, .Club))
	napoli_test_free(&room)
	return room
}

// One blow along `yaw`, run out at once (the room's actions are untimed: its
// seconds pass as it is begun); the player free again after it.
club_test_blow :: proc(room: ^Room, yaw: f32) -> Action_Result {
	result := first_person_club_move(room, {swing = true, yaw = yaw})
	napoli_test_free(room)
	return result
}

club_test_stagger :: proc(room: ^Room, enemy_id: u32) -> i32 {
	index, alive := enemy_index_by_id(room, enemy_id)
	if !alive { return -1 }
	at, found := status_index(&room.enemies[index].statuses, .Stagger)
	return room.enemies[index].statuses.items[at].remaining_pulses if found else 0
}

// Face 1 takes the club up: the user's 30 seconds (+2 an upgrade), 8 damage
// (+1 an upgrade), behind his back; no cards meanwhile, steps of 0.5 s.
@(test)
test_napoli_face_one_takes_up_the_club :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 9, y = 5}, health = 50, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	play := napoli_test_play(t, &room, 1, 2)
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect(t, first_person_club_active(&room))
	testing.expect_value(t, room.first_person.remaining, f32(34))
	testing.expect_value(t, room.first_person.club.damage, i32(10))
	testing.expect(t, FIRST_PERSON_WEAPONS[.Club].third_person && !FIRST_PERSON_WEAPONS[.Club].while_riding)
	testing.expect(t, card_is_first_person(.Napoli))
	begun := 0
	for event in room.recent_events.events[:room.recent_events.count] {
		if event.kind == .First_Person_Begun && event.card_definition == .Napoli && event.duration == 34 { begun += 1 }
	}
	testing.expect_value(t, begun, 1)
	testing.expect(t, !tactical_allows_cards(&room))
	testing.expect_value(t, player_move_seconds(&room), CLUB_MOVE_SECONDS)
	testing.expect_value(t, CLUB_SWING_SECONDS, f32(0.6))
}

// The eight ways by the view's yaw (east 0, south a quarter turn).
@(test)
test_club_aims_the_nearest_of_eight_ways :: proc(t: ^testing.T) {
	cases := [?]struct{yaw: f32, way: [2]i8}{
		{0, {1, 0}}, {math.PI/2, {0, 1}}, {math.PI, {-1, 0}}, {-math.PI/2, {0, -1}},
		{math.PI/4, {1, 1}}, {-math.PI/4, {1, -1}}, {3*math.PI/4, {-1, 1}}, {-3*math.PI/4, {-1, -1}},
		{0.3, {1, 0}}, {0.5, {1, 1}}, {-0.3, {1, 0}}, {2*math.PI-0.1, {1, 0}},
	}
	for c in cases {
		way := club_way(c.yaw)
		testing.expectf(t, way == c.way, "yaw %v: %v, not %v", c.yaw, way, c.way)
	}
}

// The blow strikes only the cell in front: 8 to that foe, staggered 2 beats;
// the foe beside him untouched. His body is busy all the blow.
@(test)
test_club_blow_strikes_the_cell_in_front_and_staggers :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 7, y = 5}, health = 50, attack = 1}, {position = {x = 6, y = 4}, health = 50, attack = 1}}
	room := club_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	east, north := room.enemies[0].id, room.enemies[1].id
	testing.expect_value(t, club_test_blow(&room, 0), Action_Result.Moved)
	c := &room.first_person.club
	testing.expect_value(t, c.swings, i32(1))
	testing.expect_value(t, c.strikes, i32(1))
	testing.expect_value(t, c.last.hit, Club_Hit.Foe)
	testing.expect_value(t, c.last.damage, i32(8))
	testing.expect_value(t, c.last.stagger, NAPOLI_CLUB_STAGGER_BEATS)
	testing.expect(t, !c.blow.active)
	index, _ := enemy_index_by_id(&room, east)
	testing.expect_value(t, room.enemies[index].health, i32(42))
	testing.expect_value(t, club_test_stagger(&room, east), i32(2))
	index, _ = enemy_index_by_id(&room, north)
	testing.expect_value(t, room.enemies[index].health, i32(50))
	testing.expect_value(t, club_test_stagger(&room, north), i32(0))
	// He faces the way he struck.
	testing.expect_value(t, player.tactical.facing, Move_Direction.East)
	// A diagonal reaches too: up-right is empty, the floor.
	testing.expect_value(t, club_test_blow(&room, -math.PI/4), Action_Result.Moved)
	testing.expect_value(t, c.last.hit, Club_Hit.Floor)
	testing.expect_value(t, c.last.cell, grid.Position{x = 7, y = 4})
	testing.expect_value(t, c.whiffs, i32(1))
}

// In the timed game the blow holds his body CLUB_SWING_SECONDS: no step, no new
// blow; it strikes CLUB_WINDUP_SECONDS in, not before.
@(test)
test_club_blow_is_raised_then_struck_in_its_time :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 7, y = 5}, health = 50, attack = 1}}
	room := club_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	player.tactical.config.timed_actions = true
	testing.expect_value(t, first_person_club_move(&room, {swing = true, yaw = 0}), Action_Result.Moved)
	c := &room.first_person.club
	testing.expect(t, c.blow.active && !c.blow.landed)
	testing.expect_value(t, player.tactical.action_remaining, CLUB_SWING_SECONDS)
	testing.expect(t, !tactical_allows_movement(&room))
	testing.expect_value(t, try_move_player(&room, .West), Action_Result.Invalid_Phase)
	// Raised: not struck yet; a press now begins nothing.
	tactical_first_person_tick(&room, 0.2)
	testing.expect_value(t, first_person_club_move(&room, {swing = true, yaw = math.PI}), Action_Result.None)
	testing.expect_value(t, room.enemies[0].health, i32(50))
	testing.expect_value(t, c.swings, i32(1))
	// Down on him.
	tactical_first_person_tick(&room, 0.06)
	testing.expect_value(t, first_person_club_move(&room, {}), Action_Result.Moved)
	testing.expect_value(t, room.enemies[0].health, i32(42))
	testing.expect(t, c.blow.active && c.blow.landed)
	// Back: over at 0.6 s.
	tactical_first_person_tick(&room, 0.35)
	first_person_club_move(&room, {})
	testing.expect(t, !c.blow.active)
	testing.expect_value(t, c.impacts, i32(1))
}

// The stagger wears (the user's choice): 2 beats, 1, then none on the same foe,
// the damage whole; another foe is staggered in full; 4 quiet seconds and the
// first is staggered in full again.
@(test)
test_club_stagger_has_diminishing_returns :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 7, y = 5}, health = 200, attack = 1}, {position = {x = 5, y = 5}, health = 200, attack = 1}}
	room := club_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	c := &room.first_person.club
	wanted := [4]i32{2, 1, 0, 0}
	for beats, k in wanted {
		testing.expect_value(t, club_test_blow(&room, 0), Action_Result.Moved)
		testing.expectf(t, c.last.stagger == beats, "blow %d staggered %d beats, not %d", k+1, c.last.stagger, beats)
		testing.expect(t, c.last.damage >= NAPOLI_CLUB_DAMAGE)
	}
	// The other one, fresh.
	testing.expect_value(t, club_test_blow(&room, math.PI), Action_Result.Moved)
	testing.expect_value(t, c.last.stagger, i32(2))
	// Four quiet seconds for the first one.
	tactical_first_person_tick(&room, CLUB_STAGGER_QUIET_SECONDS+0.1)
	napoli_test_free(&room)
	testing.expect_value(t, club_test_blow(&room, 0), Action_Result.Moved)
	testing.expect_value(t, c.last.stagger, i32(2))
}

// With no foe an ice block there breaks; a diagonal closed by two walls strikes
// nothing; a dodge mid-blow leaves it unstruck; the view's end too.
@(test)
test_club_strikes_things_and_never_through_corners :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 10, y = 9}, health = 50, attack = 1}}
	room := club_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	ice := Grid_Object{id = room.next_object_id, kind = .Ice_Block, position = {x = 6, y = 6}, max_health = 4, health = 4}
	room.next_object_id += 1
	append(&room.objects, ice)
	c := &room.first_person.club
	testing.expect_value(t, club_test_blow(&room, math.PI/2), Action_Result.Moved)
	testing.expect_value(t, c.last.hit, Club_Hit.Object)
	_, standing := object_index_at(&room, {x = 6, y = 6})
	testing.expect(t, !standing)
	// A corner: from (1,1) up-left is closed by the two walls beside it.
	_, reached := club_cell(&room, {x = 1, y = 1}, {-1, -1})
	testing.expect(t, !reached)
	_, reached = club_cell(&room, {x = 1, y = 1}, {1, 1})
	testing.expect(t, reached)
	// A blow raised, then the player moved (a dodge): never struck.
	player.tactical.config.timed_actions = true
	testing.expect_value(t, first_person_club_move(&room, {swing = true, yaw = 0}), Action_Result.Moved)
	impacts := c.impacts
	player.position = {x = 6, y = 4}
	tactical_first_person_tick(&room, 0.3)
	first_person_club_move(&room, {})
	testing.expect(t, !c.blow.active)
	testing.expect_value(t, c.impacts, impacts)
	// The view's seconds out mid-blow: the blow goes with it.
	napoli_test_free(&room)
	testing.expect_value(t, first_person_club_move(&room, {swing = true, yaw = 0}), Action_Result.Moved)
	tactical_first_person_tick(&room, 31)
	testing.expect(t, !tactical_first_person_active(&room) && !c.blow.active)
	testing.expect_value(t, first_person_club_move(&room, {}), Action_Result.Invalid_Phase)
	testing.expect_value(t, player_move_seconds(&room), TACTICAL_MOVE_SECONDS)
}

// The club's state fits in the view's shared bytes (the room stays under 9 KB)
// and a save keeps it.
@(test)
test_club_fits_the_view_and_is_saved :: proc(t: ^testing.T) {
	testing.expect(t, size_of(First_Person_Club) <= size_of(First_Person_Bow))
	testing.expect(t, size_of(Room) < 9*1024)
	state := First_Person_State{active = true, weapon = .Club, remaining = 12, duration = 30}
	state.club = {damage = 9, swings = 3, strikes = 2}
	state.club.blow = {active = true, way = {1, -1}, from = {x = 4, y = 3}, at = 0.1}
	state.club.memory[0] = {enemy_id = 7, count = 2, quiet = 1.5}
	loaded, ok := first_person_load(first_person_save(state))
	testing.expect(t, ok)
	testing.expect(t, loaded.weapon == .Club && loaded.club == state.club && loaded.remaining == 12)
}
