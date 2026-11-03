package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

// BENVENUTI A NAPOLI (docs/piano-napoli.md, Fase 0): the card, its d4 and the
// four faces it picks.

// The card played with its d4 showing `face`, at `upgrade`.
napoli_test_play :: proc(t: ^testing.T, room: ^Room, face: i32, upgrade: i32 = 0) -> Card_Play_Report {
	room.player.dice = pattern_test_dice_for_faces(t, {face, 0, 0}, 1, NAPOLI_DIE_SIDES)
	return arsenal_test_play(t, room, .Napoli, entity_target(PLAYER_ENTITY), upgrade)
}

// The face and number the card's Napoli_Begun says, if it says one.
napoli_test_begun :: proc(log: ^Event_Log) -> (face, amount: i32, found: bool) {
	for event in log.events[:log.count] {
		if event.kind != .Napoli_Begun { continue }
		return event.duration, event.amount, true
	}
	return
}

@(test)
test_napoli_is_a_rare_card_with_a_fixed_d4 :: proc(t: ^testing.T) {
	definition, found := card_definition_by_id(.Napoli)
	testing.expect(t, found && validate_card_definition(&definition))
	testing.expect_value(t, definition.name, "Benvenuti a Napoli")
	testing.expect_value(t, definition.rarity, Card_Rarity.Rare)
	testing.expect_value(t, definition.cost, i32(3))
	testing.expect_value(t, definition.shop_base_price, i32(8))
	testing.expect_value(t, definition.dice_count, 1)
	testing.expect_value(t, definition.targeting.rule, Target_Rule.Self)
	// In the real game since Fase 7 (the user's choice): offered, sold and collected.
	node := Run_Node{kind = .Combat, depth = 2}
	testing.expect(t, !card_is_lab_only(.Napoli) && card_offer_weight(definition, &node) > 0 && card_in_collection(.Napoli))
	// The die is a d4 whatever the level; the upgrades grow the faces' numbers.
	for upgrade in i32(0)..=MAX_DICE_UPGRADE_LEVEL {
		testing.expect_value(t, card_die_sides(.Napoli, upgrade), NAPOLI_DIE_SIDES)
	}
	testing.expect_value(t, card_max_upgrade_level(.Napoli), MAX_DICE_UPGRADE_LEVEL)
	// The faces as the d4 shows them.
	for face in i32(1)..=4 { testing.expect_value(t, int(napoli_for_face(face)), int(face)-1) }
	testing.expect_value(t, napoli_face_name(.Club), "BASTONE")
	testing.expect_value(t, napoli_face_name(.Nonno), "NONNO")
}

// The user's numbers: the club 30 s (+2 an upgrade) and 8 damage (+1), the
// table half the most health (+2), the purse 15 gold (+2), the grandpa 30
// health (+5) for a minute that never grows.
@(test)
test_napoli_faces_have_the_users_numbers :: proc(t: ^testing.T) {
	testing.expect_value(t, napoli_face_amount(.Club, 0, 22), i32(30))
	testing.expect_value(t, napoli_face_amount(.Club, 2, 22), i32(34))
	testing.expect_value(t, napoli_face_amount(.Table, 0, 22), i32(11))
	testing.expect_value(t, napoli_face_amount(.Table, 0, 32), i32(16))
	testing.expect_value(t, napoli_face_amount(.Table, 0, 21), i32(11))
	testing.expect_value(t, napoli_face_amount(.Table, 3, 22), i32(17))
	testing.expect_value(t, napoli_face_amount(.Purse, 0, 22), i32(15))
	testing.expect_value(t, napoli_face_amount(.Purse, 4, 22), i32(23))
	testing.expect_value(t, napoli_face_amount(.Nonno, 0, 22), i32(30))
	testing.expect_value(t, napoli_face_amount(.Nonno, 2, 22), i32(40))
	testing.expect_value(t, napoli_club_damage(0), i32(8))
	testing.expect_value(t, napoli_club_damage(3), i32(11))
	testing.expect_value(t, NAPOLI_CLUB_STAGGER_BEATS, i32(2))
	testing.expect_value(t, NAPOLI_NONNO_SECONDS, i32(60))
}

// Each face of the d4 picks its own branch, its number from the card's level
// and the player's most health; the roll shows before it.
@(test)
test_napoli_d4_face_picks_the_branch :: proc(t: ^testing.T) {
	expected := [4]i32{30+2*2, 11+2*2, 15+2*2, 30+5*2}
	for face in i32(1)..=4 {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {x = 9, y = 5}, health = 50, attack = 1}}
		room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
		player.stats.max_health, player.health = 22, 22
		play := napoli_test_play(t, &room, face, 2)
		testing.expect_value(t, play.result, Card_Play_Result.Played)
		testing.expect_value(t, play.energy_before-play.energy_after, i32(3))
		testing.expect_value(t, arsenal_test_count(room.recent_events, .Dice_Rolled), 1)
		testing.expect_value(t, arsenal_test_count(room.recent_events, .Napoli_Begun), 1)
		said, amount, found := napoli_test_begun(room.recent_events)
		testing.expect(t, found)
		testing.expectf(t, said == face, "face %d said %d", face, said)
		testing.expectf(t, amount == expected[face-1], "face %d: %d, not %d", face, amount, expected[face-1])
		// The die rolled first, then the branch.
		rolled, begun := -1, -1
		for event, index in room.recent_events.events[:room.recent_events.count] {
			if event.kind == .Dice_Rolled { rolled = index }
			if event.kind == .Napoli_Begun { begun = index }
		}
		testing.expect(t, rolled >= 0 && rolled < begun)
		destroy_room(&room)
		level.destroy(&data)
	}
}

// On the tick (the user's choice): the club 3 s longer, the table and the
// purse half as much again, the grandpa 10 health more.
@(test)
test_napoli_critical_play_grows_each_face :: proc(t: ^testing.T) {
	room: Room
	player: Player
	room.player = &player
	player.tactical.critical_card = true
	expected := [Napoli_Face]i32{.Club = 33, .Table = 17, .Purse = 23, .Nonno = 40}
	for face in Napoli_Face {
		action := make_action(.Card, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
		testing.expect(t, add_effect(&action, napoli_effect(face, napoli_face_amount(face, 0, 22), 0)))
		tactical_critical_scale(&room, &action)
		testing.expectf(t, action.effects[0].amount == expected[face], "%v: %d", face, action.effects[0].amount)
		testing.expect_value(t, action.effects[0].charges, i32(face)+1)
	}
	// Not on the tick: as rolled.
	player.tactical.critical_card = false
	action := make_action(.Card, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
	testing.expect(t, add_effect(&action, napoli_effect(.Purse, 15, 0)))
	tactical_critical_scale(&room, &action)
	testing.expect_value(t, action.effects[0].amount, i32(15))
}

// Never behind the player's eyes nor on a dinosaur's back: the card is not
// played and its energy and die are kept.
@(test)
test_napoli_is_not_played_in_a_view_nor_riding :: proc(t: ^testing.T) {
	for riding in ([2]bool{false, true}) {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {x = 9, y = 5}, health = 50, attack = 1}}
		room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
		if riding {
			testing.expect_value(t, arsenal_test_ride(t, &room, 2).result, Card_Play_Result.Played)
		} else {
			testing.expect(t, tactical_begin_first_person(&room, 20))
		}
		testing.expect(t, !napoli_can_begin(&room))
		dice := pattern_test_dice_for_faces(t, {3, 0, 0}, 1, NAPOLI_DIE_SIDES)
		room.player.dice = dice
		card := ground_test_card(t, &room, .Napoli)
		energy := room.player.deck.energy
		play := play_card(&room, card.id, entity_target(PLAYER_ENTITY))
		testing.expectf(t, play.result != .Played, "played while %s", "riding" if riding else "in the view")
		testing.expect_value(t, room.player.deck.energy, energy)
		testing.expect(t, room.player.dice == dice)
		destroy_room(&room)
		level.destroy(&data)
	}
}

// A room with the player at (6,5), hurt (5 of 22), and `spawns`; the card's
// face 2 played, the d4 fixed on it. The table's cell, if one was set.
napoli_test_table_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, spawns: []Enemy_Spawn, upgrade: i32 = 0) -> (room: Room, cell: grid.Position, set: bool) {
	room = ground_test_room(t, data, player, {enemies = spawns})
	player.stats.max_health, player.health = 22, 5
	play := napoli_test_play(t, &room, 2, upgrade)
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	index, found := napoli_table_index(&room)
	if found { cell, set = room.objects[index].position, true }
	return
}

// The player free to act again, the world's beats spent (as the clock leaves him).
napoli_test_free :: proc(room: ^Room) {
	s := &room.player.tactical
	s.phase, s.remaining, s.cast_remaining, s.action_remaining, s.queued_beats = .Decision, 20, 0, 0, 0
	room.tactical_pulse = {}
}

// Face 2: the grandpa sets the table on the cell next to the player farthest
// from the nearest foe (ties: north, east, south, west, then the corners); it
// stands in everyone's way and sight, nothing strikes it; a second one takes
// its place.
@(test)
test_napoli_table_is_set_away_from_the_foes :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 9, y = 5}, health = 50, attack = 1}, {position = {x = 3, y = 5}, health = 50, attack = 1}}
	room, cell, set := napoli_test_table_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, set)
	testing.expect_value(t, cell, grid.Position{x = 6, y = 4})
	testing.expect_value(t, arsenal_test_count(room.recent_events, .Object_Spawned), 1)
	// The cure waits on the table: nothing yet.
	testing.expect_value(t, player.health, i32(5))
	index, _ := napoli_table_index(&room)
	testing.expect_value(t, room.objects[index].power, i32(11))
	testing.expect_value(t, room.objects[index].life, i32(0))
	testing.expect(t, cell_blocks_movement(&room, cell) && cell_blocks_line_of_sight(&room, cell))
	definition, _ := grid_object_definition(.Napoli_Table)
	testing.expect(t, !definition.targetable && !definition.damageable && definition.max_health == 0)
	// One foe only, to the east: the west side, the south-west corner first of its two.
	data2: level.Level
	player2: Player
	east := [?]Enemy_Spawn{{position = {x = 9, y = 5}, health = 50, attack = 1}}
	room2, cell2, set2 := napoli_test_table_room(t, &data2, &player2, east[:])
	defer level.destroy(&data2)
	defer destroy_room(&room2)
	testing.expect(t, set2)
	testing.expect_value(t, cell2, grid.Position{x = 5, y = 6})
	// A second table takes the first one's place.
	napoli_test_free(&room2)
	again := napoli_test_play(t, &room2, 2)
	testing.expect_value(t, again.result, Card_Play_Result.Played)
	tables := 0
	for object in room2.objects { if object.kind == .Napoli_Table { tables += 1 } }
	testing.expect_value(t, tables, 1)
	testing.expect_value(t, arsenal_test_count(room2.recent_events, .Napoli_Table_Cleared), 1)
}

// With no free cell round him the grandpa feeds him where he stands.
@(test)
test_napoli_table_with_no_room_cures_at_once :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns: [8]Enemy_Spawn
	ways := [8]grid.Position{{x = 0, y = -1}, {x = 1, y = 0}, {x = 0, y = 1}, {x = -1, y = 0}, {x = 1, y = -1}, {x = 1, y = 1}, {x = -1, y = 1}, {x = -1, y = -1}}
	for way, i in ways { spawns[i] = {position = {x = 6+way.x, y = 5+way.y}, health = 50, attack = 1} }
	room, _, set := napoli_test_table_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, !set)
	testing.expect_value(t, player.health, i32(16))
	testing.expect_value(t, arsenal_test_count(room.recent_events, .Object_Spawned), 0)
}

// A step into the table sits him down (he stays where he was, no dodge), the
// cure in two halves on the two beats, then the table cleared.
@(test)
test_napoli_step_into_the_table_eats_in_two_beats :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 9, y = 5}, health = 50, attack = 1}, {position = {x = 3, y = 5}, health = 50, attack = 1}}
	room, cell, set := napoli_test_table_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, set && cell == grid.Position{x = 6, y = 4})
	napoli_test_free(&room)
	testing.expect_value(t, try_move_player(&room, .North), Action_Result.Used_Ability)
	testing.expect_value(t, player.position, grid.Position{x = 6, y = 5})
	testing.expect_value(t, arsenal_test_count(room.recent_events, .Napoli_Feast), 1)
	testing.expect(t, napoli_seated(&room))
	testing.expect(t, !try_dodge_player(&room, .South))
	// The meal's beats: 6 of 11, then the 5 left; the table cleared.
	pulse: Pulse_Report
	napoli_beat(&room, &pulse)
	testing.expect_value(t, player.health, i32(11))
	testing.expect(t, napoli_seated(&room))
	napoli_beat(&room, &pulse)
	testing.expect_value(t, player.health, i32(16))
	testing.expect(t, !napoli_seated(&room))
	_, standing := napoli_table_index(&room)
	testing.expect(t, !standing)
	testing.expect_value(t, arsenal_test_count(&pulse.events, .Healed), 2)
	testing.expect_value(t, arsenal_test_count(&pulse.events, .Napoli_Table_Cleared), 1)
	testing.expect_value(t, napoli_feast_bite(11, 1), i32(6))
	testing.expect_value(t, napoli_feast_bite(11, 0), i32(5))
}

// In the timed game the meal holds his body two world seconds: no step and no
// card while he eats; a blow does not stop it.
@(test)
test_napoli_feast_holds_him_two_seconds_in_the_game :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 9, y = 5}, health = 50, attack = 1}, {position = {x = 3, y = 5}, health = 50, attack = 1}}
	room, _, set := napoli_test_table_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, set)
	napoli_test_free(&room)
	player.tactical.config.timed_actions = true
	testing.expect_value(t, try_move_player(&room, .North), Action_Result.Used_Ability)
	testing.expect_value(t, player.tactical.action_remaining, NAPOLI_FEAST_SECONDS)
	testing.expect(t, tactical_player_busy(&room) && !tactical_allows_movement(&room) && !tactical_allows_cards(&room))
	blow := make_action(.Attack, enemy_entity(room.enemies[0].id))
	testing.expect(t, add_effect(&blow, damage_effect(PLAYER_ENTITY, 2)))
	testing.expect(t, resolve_action(&room, &blow).accepted)
	testing.expect(t, napoli_seated(&room))
}

// Face 3: the purse's gold at once, more with each upgrade.
@(test)
test_napoli_purse_gives_its_gold :: proc(t: ^testing.T) {
	for upgrade in ([2]i32{0, 2}) {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {x = 9, y = 5}, health = 50, attack = 1}}
		room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
		gold := player.gold
		play := napoli_test_play(t, &room, 3, upgrade)
		testing.expect_value(t, play.result, Card_Play_Result.Played)
		testing.expect_value(t, player.gold-gold, NAPOLI_PURSE_GOLD+NAPOLI_PURSE_GOLD_PER_UPGRADE*upgrade)
		testing.expect_value(t, arsenal_test_count(room.recent_events, .Gold_Gained), 1)
		destroy_room(&room)
		level.destroy(&data)
	}
}

// No table outlives the combat.
@(test)
test_napoli_table_goes_with_the_combat :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 9, y = 5}, health = 50, attack = 1}}
	room, _, set := napoli_test_table_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, set)
	room.phase = .Loot
	tactical_end_combat(&room)
	_, standing := napoli_table_index(&room)
	testing.expect(t, !standing)
}
