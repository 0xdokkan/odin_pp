package game

import "core:testing"
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
test_napoli_is_a_rare_lab_card_with_a_fixed_d4 :: proc(t: ^testing.T) {
	definition, found := card_definition_by_id(.Napoli)
	testing.expect(t, found && validate_card_definition(&definition))
	testing.expect_value(t, definition.name, "Benvenuti a Napoli")
	testing.expect_value(t, definition.rarity, Card_Rarity.Rare)
	testing.expect_value(t, definition.cost, i32(3))
	testing.expect_value(t, definition.shop_base_price, i32(8))
	testing.expect_value(t, definition.dice_count, 1)
	testing.expect_value(t, definition.targeting.rule, Target_Rule.Self)
	// Only in the lab for now (Fase 7 decides): never offered nor collected.
	node := Run_Node{kind = .Combat, depth = 2}
	testing.expect(t, card_is_lab_only(.Napoli) && card_offer_weight(definition, &node) == 0 && !card_in_collection(.Napoli))
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
