package game

import "core:testing"
import level "../level"

// A small open room: the player at (1,2), a foe beside him (2,2), one three
// cells on (4,2) and one out of every short range (9,2).
@(private = "file")
card_hit_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player) -> (room: Room) {
	rows := [?]string{
		"###########",
		"#.........#",
		"#@........#",
		"#........>#",
		"###########",
	}
	parsed: level.Parse_Error
	data^, parsed, _ = level.from_ascii(rows[:])
	testing.expect_value(t, parsed, level.Parse_Error.None)
	player^ = create_test_player(t)
	spawns := [?]Enemy_Spawn{
		{position = {x = 2, y = 2}, health = 20, attack = 1},
		{position = {x = 4, y = 2}, health = 20, attack = 1},
		{position = {x = 9, y = 2}, health = 20, attack = 1},
	}
	made: bool
	room, made = create_room(data, player, {enemies = spawns[:]})
	testing.expect(t, made)
	return
}

// Every foe some valid cast of the card would affect, over the whole board.
@(private = "file")
card_hits_over_the_board :: proc(room: ^Room, card: Card_Instance) -> (all: Card_Hit_Set) {
	definition, _ := card_definition_by_id(card.definition_id)
	for y in 0..<room.level_data.tiles.height {
		for x in 0..<room.level_data.tiles.width {
			evaluation := evaluate_card_targeting(room, card, card_target_request_at(definition, {x = x, y = y}))
			hits := card_hit_enemies(room, card, &evaluation)
			for id in hits.ids[:hits.count] { card_hit_set_add(&all, id) }
		}
	}
	return
}

@(test)
test_a_single_target_card_marks_only_the_foe_in_its_reach :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := card_hit_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	strike := Card_Instance{id = 1, definition_id = .Strike, lifetime = .Permanent}
	definition, _ := card_definition_by_id(.Strike)
	near := room.enemies[0]
	// A cast on the adjacent foe hits it (and only it); on an empty cell, no one.
	on_foe := evaluate_card_targeting(&room, strike, card_target_request_at(definition, near.position))
	hits := card_hit_enemies(&room, strike, &on_foe)
	testing.expect_value(t, hits.count, 1)
	testing.expect(t, card_hit_set_contains(&hits, near.id))
	on_floor := evaluate_card_targeting(&room, strike, card_target_request_at(definition, {x = 3, y = 3}))
	hits = card_hit_enemies(&room, strike, &on_floor)
	testing.expect_value(t, hits.count, 0)
	// Over the board only the foe at a step is ever hit: the others are out of reach.
	all := card_hits_over_the_board(&room, strike)
	testing.expect_value(t, all.count, 1)
	testing.expect(t, card_hit_set_contains(&all, near.id))
}

@(test)
test_an_area_card_marks_every_foe_its_area_would_reach :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := card_hit_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	firebomb := Card_Instance{id = 2, definition_id = .Firebomb, lifetime = .Permanent}
	definition, _ := card_definition_by_id(.Firebomb)
	// Dropped between the two near foes it reaches both, not the far one.
	between := evaluate_card_targeting(&room, firebomb, card_target_request_at(definition, {x = 3, y = 2}))
	hits := card_hit_enemies(&room, firebomb, &between)
	testing.expect_value(t, between.error, Card_Compile_Error.None)
	testing.expect_value(t, hits.count, 2)
	testing.expect(t, card_hit_set_contains(&hits, room.enemies[0].id) && card_hit_set_contains(&hits, room.enemies[1].id))
	testing.expect(t, !card_hit_set_contains(&hits, room.enemies[2].id))
	all := card_hits_over_the_board(&room, firebomb)
	testing.expect(t, !card_hit_set_contains(&all, room.enemies[2].id))
}

// A Dash lists the foes on its line (the targeting finds them) but hits none:
// the mark must follow what the effects touch, not what the line covers.
@(test)
test_a_movement_card_marks_no_foe_it_does_not_touch :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := card_hit_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	dash := Card_Instance{id = 3, definition_id = .Dash, lifetime = .Permanent}
	definition, _ := card_definition_by_id(.Dash)
	valid_casts := 0
	for y in 0..<data.tiles.height {
		for x in 0..<data.tiles.width {
			evaluation := evaluate_card_targeting(&room, dash, card_target_request_at(definition, {x = x, y = y}))
			if evaluation.error == .None { valid_casts += 1 }
		}
	}
	testing.expect(t, valid_casts > 0)
	all := card_hits_over_the_board(&room, dash)
	testing.expect_value(t, all.count, 0)
}

@(test)
test_a_refused_cast_and_a_missing_room_mark_nothing :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := card_hit_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	strike := Card_Instance{id = 1, definition_id = .Strike, lifetime = .Permanent}
	refused := Card_Target_Evaluation{error = .Invalid_Target}
	hits := card_hit_enemies(&room, strike, &refused)
	testing.expect_value(t, hits.count, 0)
	hits = card_hit_enemies(nil, strike, &refused)
	testing.expect_value(t, hits.count, 0)
	hits = card_hit_enemies(&room, strike, nil)
	testing.expect_value(t, hits.count, 0)
}

// The wave sweeps every foe in play wherever it is dropped.
@(test)
test_the_flood_wave_marks_every_foe_in_play :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := card_hit_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	wave := Card_Instance{id = 4, definition_id = .Flood_Wave, lifetime = .Permanent}
	all := card_hits_over_the_board(&room, wave)
	testing.expect_value(t, all.count, len(room.enemies))
}
