package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

// sides 4 is the die of an unupgraded dice card.
pattern_test_dice_for_faces :: proc(t: ^testing.T, faces: [MAX_ROLL_DICE]i32, count: int, sides: i32 = 4) -> Dice_State {
	for seed in u64(1)..<u64(400_000) {
		original := make_dice_state(seed)
		staged := original
		roll, ok := roll_dice_pool(&staged, count, sides)
		if ok && roll.faces == faces { return original }
	}
	testing.expect(t, false, "could not find a deterministic pattern fixture")
	return make_dice_state(1)
}

pattern_test_expect_commit :: proc(t: ^testing.T, room: ^Room, play: ^Card_Play_Report, roll: Dice_Roll, dice: Dice_State) {
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, room.player.dice, dice)
	testing.expect_value(t, room.player.deck.energy, i32(1))
	testing.expect_value(t, room.pulse_count, u64(0))
	for kind in ([2]Game_Event_Kind{.Card_Played, .Dice_Rolled}) {
		testing.expect_value(t, spell_test_event_count(room.recent_events, kind), 1)
	}
	testing.expect_value(t, room.recent_events.events[0].kind, Game_Event_Kind.Card_Played)
	event := room.recent_events.events[1]
	testing.expect_value(t, event.kind, Game_Event_Kind.Dice_Rolled)
	testing.expect_value(t, event.dice_roll, roll)
	testing.expect_value(t, event.amount, roll.total)
	testing.expect_value(t, event.card_definition, play.card.definition_id)
	testing.expect_value(t, event.card_id, play.card.id)
	testing.expect_value(t, event.card_upgrade_level, play.card.upgrade_level)
	testing.expect_value(t, event.source, PLAYER_ENTITY)
	testing.expect_value(t, room.recent_events.dropped_count, 0)
	testing.expect_value(t, play.action_report.reaction_events_dropped, 0)
	testing.expect(t, !play.action_report.reaction_limit_reached && validate_deck_state(&room.player.deck))
}

@(test)
test_dice_patterns_count_all_successes_pairs_and_reject_invalid_inputs :: proc(t: ^testing.T) {
	success_distribution: [4]int
	pairs := 0
	for first in i32(1)..=i32(6) {
		for second in i32(1)..=i32(6) {
			roll := Dice_Roll{faces = {first, second, 0}, total = first+second, sides = 6, count = 2}
			if dice_has_pair(&roll) { pairs += 1 }
			testing.expect_value(t, dice_has_pair(&roll), first == second)
			for third in i32(1)..=i32(6) {
				roll = {faces = {first, second, third}, total = first+second+third, sides = 6, count = 3}
				before := roll
				success_distribution[dice_success_count(&roll)] += 1
				testing.expect_value(t, dice_has_pair(&roll), first == second || first == third || second == third)
				for threshold in i32(1)..=i32(6) {
					expected := int(first >= threshold)+int(second >= threshold)+int(third >= threshold)
					testing.expect_value(t, dice_success_count(&roll, threshold), expected)
				}
				testing.expect_value(t, roll, before)
			}
		}
	}
	testing.expect_value(t, success_distribution, [4]int{27, 81, 81, 27})
	testing.expect_value(t, pairs, 6)
	testing.expect_value(t, dice_success_count(nil), 0)
	testing.expect(t, !dice_has_pair(nil))
	valid := Dice_Roll{faces = {6, 6, 0}, sides = 6, count = 2, total = 12}
	testing.expect_value(t, dice_success_count(&valid, 0), 0)
	testing.expect_value(t, dice_success_count(&valid, 7), 0)
	for corruption in 0..<6 {
		roll := valid
		switch corruption {
		case 0: roll.total -= 1
		case 1: roll.count = -1
		case 2: roll.count = 4
		case 3: roll.faces[0] = 7
		case 4: roll.faces[2] = 6
		case 5: roll.sides = 0
		}
		testing.expect_value(t, dice_success_count(&roll), 0)
		testing.expect(t, !dice_has_pair(&roll))
	}
	for id in 0..<int(Card_Id.Count) {
		card_id := Card_Id(id)
		expected := 0
		if card_id == .Fate_Strike || card_id == .Shock_Floor || card_id == .Fate_Dice || card_id == .Venom_Blade ||
		   card_id == .Dino_Ride { expected = 1 }
		if card_id == .Sundering_Blow || card_id == .Twin_Venom { expected = 2 }
		if card_id == .Prismatic_Barrage { expected = 3 }
		testing.expect_value(t, card_dice_count(card_id), expected)
	}
	testing.expect_value(t, card_dice_count(.Count), 0)
}

@(test)
test_pattern_cards_are_append_only_upgrades_and_pure_to_preview_at_max_upgrade :: proc(t: ^testing.T) {
	testing.expect_value(t, int(Card_Id.Prismatic_Barrage), int(Card_Id.Sundering_Blow)+1)
	testing.expect_value(t, int(Card_Id.Twin_Venom), int(Card_Id.Prismatic_Barrage)+1)
	testing.expect_value(t, int(Card_Id.Shock_Floor), int(Card_Id.Twin_Venom)+1)
	for id in ([2]Card_Id{.Prismatic_Barrage, .Twin_Venom}) {
		definition, found := card_definition_by_id(id)
		testing.expect(t, found && validate_card_definition(&definition))
		// Only an upgrade makes them now (Fate Strike, Venom Needle: docs/registro-carte.md).
		testing.expect(t, !definition.temporary_only && definition.evolution_only && definition.reward_weight == 0 && definition.shop_base_price > 0)
		testing.expect_value(t, definition.rarity, Card_Rarity.Uncommon)
		testing.expect_value(t, definition.cost, i32(2))
		data := spell_test_level(t)
		player := spell_test_player(t, id, int(MAX_DICE_UPGRADE_LEVEL))
		enemies := [?]Enemy_Spawn{{position = {x = 4, y = 1}, health = 100, attack = 1}}
		room, ok := create_room(&data, &player, {enemies = enemies[:]})
		testing.expect(t, ok)
		before := player
		for _ in 0..<16 {
			card := player.deck.hand[0]
			preview := evaluate_card_targeting(&room, card, {anchor = {x = 4, y = 1}, has_anchor = true})
			testing.expect_value(t, preview.error, Card_Compile_Error.None)
			testing.expect(t, !preview.has_movement)
			path := query_spell_path(&room, card, entity_target(enemy_entity(1)))
			testing.expect_value(t, path.count, 1)
			testing.expect_value(t, path.positions[0], grid.Position{x = 4, y = 1})
			action, err := compile_card_action(&room, card, entity_target(enemy_entity(1)))
			testing.expect_value(t, err, Card_Compile_Error.None)
			testing.expect_value(t, action.effect_count, 2)
			damage_index := 1 if id == .Prismatic_Barrage else 0
			// Upgrades raise only the dice: the compiled minimum never grows.
			testing.expect_value(t, action.effects[damage_index].amount, i32(3) if id == .Prismatic_Barrage else i32(2))
			testing.expect_value(t, player, before)
		}
		destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_barrage_commits_each_success_count_with_shield_first_and_single_economy :: proc(t: ^testing.T) {
	for upgrade in ([3]int{0, 2, int(MAX_DICE_UPGRADE_LEVEL)}) {
		sides := card_die_sides(.Prismatic_Barrage, i32(upgrade))
		for successes in 0..=3 {
			faces := [3]i32{1, 2, 3}
			for index in 0..<successes { faces[index] = min(i32(4+index), sides) }
			data := spell_test_level(t)
			player := spell_test_player(t, .Prismatic_Barrage, upgrade)
			player.dice = pattern_test_dice_for_faces(t, faces, 3, sides)
			expected_dice := player.dice
			expected_roll, _ := roll_dice_pool(&expected_dice, 3, sides)
			enemies := [?]Enemy_Spawn{{position = {x = 3, y = 1}, health = 100, attack = 1}}
			room, ok := create_room(&data, &player, {enemies = enemies[:]})
			testing.expect(t, ok)
			room.enemies[0].intent = make_wait_intent(&room, room.enemies[0].position)
			play := play_card(&room, player.deck.hand[0].id, entity_target(enemy_entity(1)))
			pattern_test_expect_commit(t, &room, &play, expected_roll, expected_dice)
			damage := i32(successes)*PRISMATIC_HIT_DAMAGE
			testing.expect_value(t, play.action_report.damage_dealt, damage)
			testing.expect_value(t, room.enemies[0].health, i32(100)-damage)
			testing.expect_value(t, spell_test_event_count(&play.action_report.events, .Damaged), 1 if successes > 0 else 0)
			testing.expect_value(t, spell_test_event_count(&play.action_report.events, .Spell_Impact), 1 if successes > 0 else 0)
			testing.expect_value(t, spell_test_event_count(&play.action_report.events, .Spell_Launched), 1 if successes > 0 else 0)
			testing.expect_value(t, spell_test_event_count(&play.action_report.events, .Attack_Missed), 0)
			shield, found := status_for_entity(&room, PLAYER_ENTITY, .Shield)
			testing.expect_value(t, found, successes < 3)
			if found {
				testing.expect_value(t, shield.potency, i32(3-successes))
				testing.expect_value(t, shield.remaining_pulses, i32(2))
			}
			direct_start := 3 if successes > 0 else 1
			if successes < 3 {
				event := play.action_report.events.events[direct_start]
				testing.expect_value(t, event.kind, Game_Event_Kind.Status_Applied)
				testing.expect_value(t, event.status, Status_Kind.Shield)
				testing.expect_value(t, event.amount, i32(3-successes))
				testing.expect_value(t, event.duration, i32(2))
			}
			if successes > 0 {
				testing.expect_value(t, play.action_report.events.events[2].kind, Game_Event_Kind.Spell_Impact)
				testing.expect_value(t, play.action_report.events.events[2].amount, damage)
				damage_index := direct_start+1 if successes < 3 else direct_start
				testing.expect_value(t, play.action_report.events.events[damage_index].kind, Game_Event_Kind.Damaged)
			}
			destroy_room(&room)
			level.destroy(&data)
		}
	}
}

@(test)
test_twin_venom_all_face_pairs_use_highest_die_and_only_doubles_poison :: proc(t: ^testing.T) {
	for upgrade in ([3]int{0, 1, int(MAX_DICE_UPGRADE_LEVEL)}) {
		sides := card_die_sides(.Twin_Venom, i32(upgrade))
		for first in i32(1)..=sides {
			for second in i32(1)..=sides {
				data := spell_test_level(t)
				player := spell_test_player(t, .Twin_Venom, upgrade)
				player.dice = pattern_test_dice_for_faces(t, {first, second, 0}, 2, sides)
				expected_dice := player.dice
				expected_roll, _ := roll_dice_pool(&expected_dice, 2, sides)
				enemies := [?]Enemy_Spawn{{position = {x = 3, y = 1}, health = 100, attack = 1}}
				room, ok := create_room(&data, &player, {enemies = enemies[:]})
				testing.expect(t, ok)
				room.enemies[0].intent = make_wait_intent(&room, room.enemies[0].position)
				play := play_card(&room, player.deck.hand[0].id, entity_target(enemy_entity(1)))
				pattern_test_expect_commit(t, &room, &play, expected_roll, expected_dice)
				damage := 1+max(first, second)
				testing.expect_value(t, play.action_report.damage_dealt, damage)
				testing.expect_value(t, room.enemies[0].health, i32(100)-damage)
				testing.expect_value(t, spell_test_event_count(&play.action_report.events, .Damaged), 1)
				testing.expect_value(t, spell_test_event_count(&play.action_report.events, .Status_Applied), 1 if first == second else 0)
				testing.expect_value(t, play.action_report.events.events[2].kind, Game_Event_Kind.Spell_Impact)
				testing.expect_value(t, play.action_report.events.events[2].amount, damage)
				testing.expect_value(t, play.action_report.events.events[3].kind, Game_Event_Kind.Damaged)
				poison, found := status_for_entity(&room, enemy_entity(1), .Poison)
				testing.expect_value(t, found, first == second)
				if found {
					// The cast applies two stacks; the enemy has not acted yet.
					testing.expect_value(t, poison.potency, i32(2))
					event := play.action_report.events.events[4]
					testing.expect_value(t, event.kind, Game_Event_Kind.Status_Applied)
					testing.expect_value(t, event.amount, i32(2))
					testing.expect_value(t, event.duration, i32(0))
				}
				destroy_room(&room)
				level.destroy(&data)
			}
		}
	}
}

@(test)
test_pattern_spells_reject_without_mutating_rng_deck_targets_or_relics :: proc(t: ^testing.T) {
	for id in ([2]Card_Id{.Prismatic_Barrage, .Twin_Venom}) {
		data := spell_test_level(t)
		player := spell_test_player(t, id)
		testing.expect(t, acquire_relic(&player, .Venom_Vial))
		enemies := [?]Enemy_Spawn{{position = {x = 3, y = 1}, health = 40, attack = 1}, {position = {x = 5, y = 1}, health = 40, attack = 1}}
		room, ok := create_room(&data, &player, {enemies = enemies[:]})
		testing.expect(t, ok)
		for rejected_case in 0..<7 {
			player.deck.energy = 3
			player.dice = make_dice_state(123)
			clear(&room.obstacles)
			target := entity_target(enemy_entity(1))
			switch rejected_case {
			case 0: target = entity_target(PLAYER_ENTITY)
			case 1: target = entity_target(enemy_entity(2))
			case 2: player.deck.energy = 1
			case 3: append(&room.obstacles, Obstacle{position = {x = 2, y = 1}})
			case 4: player.dice.roll_count = max(u64)-u64(card_dice_count(id)-1)
			case 5: player.dice.random_state = 0
			case 6: target = entity_target(enemy_entity(99))
			}
			before := player
			play := play_card(&room, player.deck.hand[0].id, target)
			testing.expect(t, !card_play_was_committed(play.result))
			testing.expect_value(t, player, before)
			testing.expect_value(t, room.pulse_count, u64(0))
			testing.expect_value(t, room.recent_events.count, 0)
			testing.expect_value(t, room.enemies[0].health, i32(40))
		}
		destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_barrage_aggregates_damage_and_shields_before_thorns_without_false_hits :: proc(t: ^testing.T) {
	for successes in 0..=1 {
		data := spell_test_level(t)
		player := spell_test_player(t, .Prismatic_Barrage)
		player.health = 10
		player.stats.defense = 0
		player.dice = pattern_test_dice_for_faces(t, {4 if successes == 1 else 3, 1, 2}, 3)
		enemies := [?]Enemy_Spawn{{position = {x = 3, y = 1}, health = 40, attack = 1}}
		room, ok := create_room(&data, &player, {enemies = enemies[:]})
		testing.expect(t, ok)
		room.enemies[0].intent = make_wait_intent(&room, room.enemies[0].position)
		applied, _ := apply_status(&room, enemy_entity(1), .Thorns, 3, 3)
		testing.expect(t, applied)
		play := play_card(&room, player.deck.hand[0].id, entity_target(enemy_entity(1)))
		testing.expect_value(t, play.result, Card_Play_Result.Played)
		testing.expect_value(t, player.health, i32(9) if successes == 1 else i32(10))
		testing.expect_value(t, play.action_report.reactions_triggered, successes)
		testing.expect_value(t, spell_test_event_count(&play.action_report.events, .Damage_Absorbed), successes)
		testing.expect_value(t, spell_test_event_count(&play.action_report.events, .Damaged), successes*2)
		testing.expect_value(t, room.recent_events.dropped_count, 0)
		destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_pattern_spells_commit_lethal_hits_without_postmortem_poison_or_extra_pulse :: proc(t: ^testing.T) {
	for id in ([2]Card_Id{.Prismatic_Barrage, .Twin_Venom}) {
		data := spell_test_level(t)
		player := spell_test_player(t, id)
		testing.expect(t, acquire_relic(&player, .Venom_Vial))
		faces := [3]i32{4, 4, 4} if id == .Prismatic_Barrage else [3]i32{4, 4, 0}
		player.dice = pattern_test_dice_for_faces(t, faces, card_dice_count(id))
		enemies := [?]Enemy_Spawn{{position = {x = 3, y = 1}, health = 1, attack = 1}}
		room, ok := create_room(&data, &player, {enemies = enemies[:]})
		testing.expect(t, ok)
		play := play_card(&room, player.deck.hand[0].id, entity_target(enemy_entity(1)))
		testing.expect_value(t, play.result, Card_Play_Result.Combat_Ended)
		testing.expect_value(t, player.dice.roll_count, u64(card_dice_count(id)))
		testing.expect_value(t, len(room.enemies), 0)
		testing.expect_value(t, spell_test_event_count(&play.action_report.events, .Status_Applied), 0)
		testing.expect_value(t, spell_test_event_count(room.recent_events, .Dice_Rolled), 1)
		testing.expect_value(t, room.pulse_count, u64(0))
		testing.expect(t, !player.deck.combat_active && !player.relics.combat.poison_used)
		destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_pattern_spell_reaction_death_commits_rng_and_stops_further_damage_and_pulse :: proc(t: ^testing.T) {
	for id in ([2]Card_Id{.Prismatic_Barrage, .Twin_Venom}) {
		data := spell_test_level(t)
		player := spell_test_player(t, id)
		player.health = 1
		faces := [3]i32{4, 4, 4} if id == .Prismatic_Barrage else [3]i32{4, 4, 0}
		player.dice = pattern_test_dice_for_faces(t, faces, card_dice_count(id))
		enemies := [?]Enemy_Spawn{{position = {x = 3, y = 1}, health = 40, attack = 1}}
		room, ok := create_room(&data, &player, {enemies = enemies[:]})
		testing.expect(t, ok)
		applied, _ := apply_status(&room, enemy_entity(1), .Thorns, 4, 3)
		testing.expect(t, applied)
		play := play_card(&room, player.deck.hand[0].id, entity_target(enemy_entity(1)))
		testing.expect_value(t, play.result, Card_Play_Result.Player_Defeated)
		testing.expect_value(t, player.dice.roll_count, u64(card_dice_count(id)))
		testing.expect_value(t, play.action_report.reactions_triggered, 1)
		testing.expect_value(t, room.enemies[0].health, i32(31) if id == .Prismatic_Barrage else i32(35))
		dead := false
		for event in room.recent_events.events[:room.recent_events.count] {
			if dead { testing.expect(t, event.kind != .Damaged && event.kind != .Status_Applied) }
			if event.kind == .Entity_Defeated && event.target == PLAYER_ENTITY { dead = true }
		}
		testing.expect(t, dead)
		testing.expect_value(t, room.pulse_count, u64(0))
		testing.expect_value(t, room.recent_events.dropped_count, 0)
		destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_twin_venom_pair_uses_existing_poison_relic_once_and_never_bonus_economy :: proc(t: ^testing.T) {
	data := spell_test_level(t)
	defer level.destroy(&data)
	player := spell_test_player(t, .Twin_Venom)
	testing.expect(t, acquire_relic(&player, .Venom_Vial))
	enemies := [?]Enemy_Spawn{
		{position = {x = 3, y = 1}, health = 40, attack = 1},
		{position = {x = 3, y = 2}, health = 40, attack = 1},
	}
	room, ok := create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	for cast_index in 0..<2 {
		player.deck.energy = 3
		player.dice = pattern_test_dice_for_faces(t, {4, 4, 0}, 2)
		for &enemy in room.enemies { enemy.intent = make_wait_intent(&room, enemy.position) }
		target := enemy_entity(u32(cast_index+1))
		play := play_card(&room, player.deck.hand[0].id, entity_target(target))
		testing.expect_value(t, play.result, Card_Play_Result.Played)
		potency := i32(3) if cast_index == 0 else i32(2)
		testing.expect_value(t, room.enemies[cast_index].health, i32(40)-5)
		poison, found := status_for_entity(&room, target, .Poison)
		// No enemy action occurs during the cast.
		testing.expect(t, found && poison.potency == potency)
		testing.expect(t, player.relics.combat.poison_used)
		testing.expect_value(t, spell_test_event_count(&play.action_report.events, .Status_Applied), 1)
		testing.expect_value(t, play.action_report.events.events[4].amount, potency)
		testing.expect_value(t, spell_test_event_count(room.recent_events, .Card_Drawn), 0)
		testing.expect_value(t, spell_test_event_count(room.recent_events, .Pulse_Advanced), 0)
		testing.expect_value(t, player.deck.energy, i32(1))
		testing.expect_value(t, room.recent_events.dropped_count, 0)
		drain_tactical_test_pulse(t, &room)
	}
}
