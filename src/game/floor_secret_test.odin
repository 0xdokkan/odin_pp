package game

import "core:testing"
import level "../level"

// A hand of four holds every owned card, the Scopa pair included.
western_ranch_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, pair: bool) -> Room {
	spawns := [?]Enemy_Spawn{{position = {x = 7, y = 7}, health = 20, attack = 1}}
	room := create_enemy_rework_room(t, data, player, spawns[:])
	destroy_room(&room)
	testing.expect(t, initialize_empty_deck(&player.deck, {hand_size = 4, max_energy = 3, energy_regen_per_pulse = 1}, 77))
	ids := [4]Card_Id{.Strike, .Sei_Denari, .Guard, .Sette_Denari if pair else .Strike}
	for id in ids {
		_, added := add_owned_card(&player.deck, id)
		testing.expect(t, added)
	}
	ok: bool
	room, ok = create_room(data, player, {enemies = spawns[:]})
	testing.expect(t, ok)
	return room
}

@(test)
test_western_ranch_opens_with_the_pair_in_hand_once_per_floor :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	{
		// The 6 alone is just a card.
		alone := western_ranch_test_room(t, &data, &player, false)
		testing.expect_value(t, player.deck.hand_count, 4)
		testing.expect(t, !western_ranch_can_start(&alone))
		destroy_room(&alone)
		level.destroy(&data)
	}
	room := western_ranch_test_room(t, &data, &player, true)
	defer level.destroy(&data)
	defer destroy_room(&room)
	six, seven, held := western_ranch_hand(&room)
	testing.expect(t, held && six >= 0 && seven >= 0)
	testing.expect(t, western_ranch_can_start(&room))
	discard := player.deck.discard_count
	testing.expect(t, begin_western_ranch(&room))
	// Both cards fly to the sign and end in the discard pile.
	testing.expect_value(t, player.deck.hand_count, 2)
	testing.expect_value(t, player.deck.discard_count, discard+2)
	for card in player.deck.hand[:player.deck.hand_count] { testing.expect(t, !card_is_scopa(card.definition_id)) }
	testing.expect(t, .Western_Ranch in player.floor_secrets)
	// Drawing the pair again on this floor opens nothing.
	_, _, held = western_ranch_hand(&room)
	testing.expect(t, !held && !western_ranch_can_start(&room))
	begin_floor(&player)
	testing.expect(t, .Western_Ranch not_in player.floor_secrets)
}

@(test)
test_western_ranch_win_refills_health_and_pays_ten_gold :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := western_ranch_test_room(t, &data, &player, true)
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, begin_western_ranch(&room))
	player.health = 31
	gold := player.gold
	lost := settle_western_ranch(&room, false)
	testing.expect(t, !lost.won && lost.gold == 0 && lost.healed == 0)
	testing.expect_value(t, player.health, i32(31))
	testing.expect_value(t, player.gold, gold)
	won := settle_western_ranch(&room, true)
	testing.expect(t, won.won)
	testing.expect_value(t, won.healed, player.stats.max_health-31)
	testing.expect_value(t, player.health, player.stats.max_health)
	testing.expect_value(t, player.gold, gold+WESTERN_RANCH_GOLD)
}
