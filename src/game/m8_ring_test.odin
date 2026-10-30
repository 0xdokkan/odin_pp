package game

import "core:testing"
import level "../level"


@(test)
test_m8_ring_unlock_milestones_grant_once_and_filter_all_card_offers :: proc(t: ^testing.T) {
	data := create_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	room, ok := create_room(&data, &player, {})
	testing.expect(t, ok)
	defer destroy_room(&room)
	node := Run_Node{kind = .Elite, depth = 3}
	hook, _ := card_definition_by_id(.Grappling_Hook)
	crown, _ := card_definition_by_id(.Storm_Crown)
	testing.expect_value(t, card_offer_weight(hook, &node, &player.m8_profile), u64(0))
	testing.expect_value(t, card_offer_weight(crown, &node, &player.m8_profile), u64(0))
	for wins in 1..=4 {
		owned_before := player.deck.owned_count
		reward := record_ring_win(&room)
		testing.expect(t, reward.settled && reward.won)
		testing.expect_value(t, player.m8_profile.ring_wins, u32(wins))
		if wins == 1 || wins == 3 {
			testing.expect(t, reward.has_unlock && reward.card_added)
			testing.expect_value(t, player.deck.owned_count, owned_before+1)
			testing.expect_value(t, reward.unlocked, Card_Id.Grappling_Hook if wins == 1 else Card_Id.Storm_Crown)
		} else {
			testing.expect(t, !reward.has_unlock && !reward.card_added)
			testing.expect_value(t, player.deck.owned_count, owned_before)
		}
		testing.expect(t, card_offer_weight(hook, &node, &player.m8_profile) > 0)
		testing.expect_value(t, card_offer_weight(crown, &node, &player.m8_profile) > 0, wins >= 3)
	}
	testing.expect(t, !m8_profile_valid({M8_MAX_RING_WINS+1}))
}

@(test)
test_m8_locked_cards_never_leak_into_reward_pool :: proc(t: ^testing.T) {
	node := Run_Node{kind = .Shop, depth = 9}
	profile: M8_Profile
	for seed in u64(1)..=100 {
		random := seed
		choices: [3]Card_Id
		testing.expect(t, generate_weighted_card_choices(&random, &node, choices[:], &profile))
		for id in choices { testing.expect(t, id != .Grappling_Hook && id != .Storm_Crown) }
	}
	profile.ring_wins = 3
	// The whole pool, counted (Spark, the Scopa pair, the lab's cards, the retired ones and those only an upgrade makes
	// are never offered): the two prizes of the ring are in it.
	storage: [int(Card_Id.Count)]Card_Id
	all := storage[:offerable_card_count(&node, &profile)]
	random := u64(1)
	testing.expect(t, generate_weighted_card_choices(&random, &node, all, &profile))
	found_hook, found_crown := false, false
	for id in all { found_hook = found_hook || id == .Grappling_Hook; found_crown = found_crown || id == .Storm_Crown }
	testing.expect(t, found_hook && found_crown)
}

@(test)
test_m8_unlock_survives_full_deck_and_remains_available_in_offers :: proc(t: ^testing.T) {
	data := create_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	room, ok := create_room(&data, &player, {})
	testing.expect(t, ok)
	defer destroy_room(&room)
	for player.deck.owned_count < MAX_OWNED_CARDS {
		_, added := add_owned_card(&player.deck, .Strike)
		testing.expect(t, added)
	}
	reward := record_ring_win(&room)
	testing.expect(t, reward.settled && reward.has_unlock && !reward.card_added)
	testing.expect(t, m8_card_unlocked(.Grappling_Hook, &player.m8_profile))
	testing.expect_value(t, player.deck.owned_count, MAX_OWNED_CARDS)
}

@(test)
test_m8_storm_crown_preview_and_play_share_three_targets_and_damage :: proc(t: ^testing.T) {
	data := spell_test_level(t)
	defer level.destroy(&data)
	player := spell_test_player(t, .Storm_Crown, 2)
	enemies := [?]Enemy_Spawn{
		{position = {x = 3, y = 1}, health = 40, attack = 1},
		{position = {x = 4, y = 1}, health = 40, attack = 1},
		{position = {x = 3, y = 2}, health = 40, attack = 1},
		{position = {x = 8, y = 1}, health = 40, attack = 1},
	}
	room, ok := create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	instance := player.deck.hand[0]
	target := entity_target(enemy_entity(1))
	before := player
	path := query_spell_path(&room, instance, target)
	action, error := compile_card_action(&room, instance, target)
	testing.expect_value(t, error, Card_Compile_Error.None)
	testing.expect_value(t, path.count, 3)
	testing.expect_value(t, action.effect_count, path.count)
	for effect, index in action.effects[:action.effect_count] {
		testing.expect_value(t, effect.target, path.targets[index])
		testing.expect_value(t, effect.amount, i32(7))
	}
	testing.expect_value(t, player, before)
	testing.expect_value(t, play_card(&room, instance.id, target).result, Card_Play_Result.Played)
	for enemy, index in room.enemies { testing.expect_value(t, enemy.health, i32(33) if index < 3 else i32(40)) }
}
