package game

import "core:testing"
import grid "../grid"
import level "../level"

// sides 4 is the 2D4 of an unupgraded Sundering Blow.
shatter_test_dice_for_total :: proc(t: ^testing.T, total: i32, sides: i32 = 4) -> Dice_State {
	for seed in u64(1)..<u64(4000) {
		original := make_dice_state(seed)
		staged := original
		roll, ok := roll_dice_pool(&staged, 2, sides)
		if ok && roll.total == total { return original }
	}
	testing.expect(t, false, "could not find deterministic 2-dice fixture")
	return make_dice_state(1)
}

@(test)
test_sunder_card_is_append_only_collectible_and_previews_minimum_damage_without_rng :: proc(t: ^testing.T) {
	testing.expect_value(t, int(Card_Id.Sundering_Blow), int(Card_Id.Chain_Lightning)+1)
	testing.expect_value(t, int(Card_Id.Sundering_Blow), int(Card_Id.Prismatic_Barrage)-1)
	definition, found := card_definition_by_id(.Sundering_Blow)
	testing.expect(t, found && validate_card_definition(&definition))
	testing.expect_value(t, definition.rarity, Card_Rarity.Uncommon)
	testing.expect_value(t, definition.cost, i32(2))
	testing.expect(t, definition.reward_weight > 0 && definition.shop_base_price > 0 && !definition.temporary_only)
	data := spell_test_level(t)
	defer level.destroy(&data)
	player := spell_test_player(t, .Sundering_Blow, 2)
	enemies := [?]Enemy_Spawn{{position = {3, 1}, health = 40, attack = 1}}
	room, ok := create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	before := player
	card := player.deck.hand[0]
	for _ in 0..<16 {
		preview := evaluate_card_targeting(&room, card, {anchor = {3, 1}, has_anchor = true})
		testing.expect_value(t, preview.error, Card_Compile_Error.None)
		testing.expect(t, preview.has_movement && !preview.movement_required)
		testing.expect_value(t, preview.movement.destination, grid.Position{4, 1})
		path := query_spell_path(&room, card, entity_target(enemy_entity(1)))
		testing.expect_value(t, path.count, 1)
		action, err := compile_card_action(&room, card, entity_target(enemy_entity(1)))
		testing.expect_value(t, err, Card_Compile_Error.None)
		testing.expect_value(t, action.effect_count, 2)
		// The compiled minimum stays the base two: upgrades raise only the dice.
		testing.expect_value(t, action.effects[0].amount, i32(2))
		testing.expect_value(t, action.effects[1].kind, Effect_Kind.Move)
		testing.expect_value(t, player, before)
	}
}

@(test)
test_sunder_two_dice_commit_total_damage_and_raw_eight_threshold_with_one_pulse :: proc(t: ^testing.T) {
	for total in i32(7)..=i32(8) {
		data := spell_test_level(t)
		// Three upgrades: 2D10, and still no bonus on top of the dice.
		player := spell_test_player(t, .Sundering_Blow, 3)
		player.dice = shatter_test_dice_for_total(t, total, 10)
		expected_dice := player.dice
		expected_roll, expected_ok := roll_dice_pool(&expected_dice, 2, 10)
		testing.expect(t, expected_ok)
		enemies := [?]Enemy_Spawn{{position = {3, 1}, health = 40, attack = 1}}
		room, ok := create_room(&data, &player, {enemies = enemies[:]})
		testing.expect(t, ok)
		room.enemies[0].intent = make_wait_intent(&room, room.enemies[0].position)
		play := play_card(&room, player.deck.hand[0].id, entity_target(enemy_entity(1)))
		testing.expect_value(t, play.result, Card_Play_Result.Played)
		testing.expect_value(t, player.dice, expected_dice)
		testing.expect_value(t, player.dice.roll_count, u64(2))
		testing.expect_value(t, room.enemies[0].health, i32(40)-total)
		testing.expect_value(t, room.enemies[0].position, grid.Position{4, 1} if total == 8 else grid.Position{3, 1})
		testing.expect_value(t, spell_test_event_count(&play.action_report.events, .Moved), 1 if total == 8 else 0)
		testing.expect_value(t, spell_test_event_count(&room.recent_events, .Dice_Rolled), 1)
		testing.expect_value(t, spell_test_event_count(&room.recent_events, .Card_Played), 1)
		testing.expect_value(t, spell_test_event_count(&room.recent_events, .Card_Drawn), 1)
		testing.expect_value(t, spell_test_event_count(&room.recent_events, .Pulse_Advanced), 1)
		testing.expect_value(t, player.deck.energy, i32(2))
		testing.expect_value(t, room.recent_events.events[0].kind, Game_Event_Kind.Card_Played)
		dice_event := room.recent_events.events[1]
		testing.expect_value(t, dice_event.kind, Game_Event_Kind.Dice_Rolled)
		testing.expect_value(t, dice_event.dice_roll, expected_roll)
		testing.expect_value(t, dice_event.amount, total)
		testing.expect_value(t, dice_event.card_definition, Card_Id.Sundering_Blow)
		testing.expect_value(t, dice_event.card_upgrade_level, i32(3))
		testing.expect_value(t, room.recent_events.events[2].kind, Game_Event_Kind.Spell_Launched)
		testing.expect_value(t, room.recent_events.events[3].kind, Game_Event_Kind.Spell_Impact)
		testing.expect_value(t, room.recent_events.events[4].kind, Game_Event_Kind.Damaged)
		testing.expect_value(t, room.recent_events.dropped_count, 0)
		destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_sunder_blocked_push_preserves_damage_without_collision_damage :: proc(t: ^testing.T) {
	for wall in ([2]bool{false, true}) {
		rows := [?]string{"############", "#@.........#", "#..........#", "#..........#", "#.........>#", "############"}
		if wall { rows[1] = "#@.#.......#" }
		data, err, _ := level.from_ascii(rows[:])
		testing.expect_value(t, err, level.Parse_Error.None)
		player := spell_test_player(t, .Sundering_Blow)
		player.dice = shatter_test_dice_for_total(t, 8)
		enemies := [?]Enemy_Spawn{{position = {2, 1}, health = 40, attack = 1}}
		obstacles := [?]grid.Position{{3, 1}}
		content := Room_Content{enemies = enemies[:]}
		if !wall { content.obstacles = obstacles[:] }
		room, ok := create_room(&data, &player, content)
		testing.expect(t, ok)
		room.enemies[0].intent = make_wait_intent(&room, room.enemies[0].position)
		preview := evaluate_card_targeting(&room, player.deck.hand[0], {anchor = {2, 1}, has_anchor = true})
		testing.expect_value(t, preview.error, Card_Compile_Error.None)
		testing.expect_value(t, preview.movement.error, Movement_Error.Static_Blocker)
		play := play_card(&room, player.deck.hand[0].id, entity_target(enemy_entity(1)))
		testing.expect_value(t, play.result, Card_Play_Result.Played)
		testing.expect_value(t, play.action_report.damage_dealt, i32(8))
		testing.expect_value(t, play.action_report.skipped_effects, 1)
		testing.expect_value(t, room.enemies[0].health, i32(32))
		testing.expect_value(t, room.enemies[0].position, grid.Position{2, 1})
		testing.expect_value(t, spell_test_event_count(&play.action_report.events, .Moved), 0)
		testing.expect_value(t, player.dice.roll_count, u64(2))
		destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_sunder_rejected_target_energy_los_and_partial_pool_capacity_roll_back :: proc(t: ^testing.T) {
	data := spell_test_level(t)
	defer level.destroy(&data)
	player := spell_test_player(t, .Sundering_Blow)
	enemies := [?]Enemy_Spawn{{position = {3, 1}, health = 40, attack = 1}, {position = {5, 1}, health = 40, attack = 1}}
	room, ok := create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	for rejected_case in 0..<5 {
		player.deck.energy = 3
		player.dice = make_dice_state(123)
		clear(&room.obstacles)
		target := entity_target(enemy_entity(1))
		switch rejected_case {
		case 0: target = entity_target(PLAYER_ENTITY)
		case 1: target = entity_target(enemy_entity(2))
		case 2: player.deck.energy = 1
		case 3: append(&room.obstacles, Obstacle{position = {2, 1}})
		case 4: player.dice.roll_count = max(u64)-1
		}
		before := player
		play := play_card(&room, player.deck.hand[0].id, target)
		testing.expect(t, !card_play_was_committed(play.result))
		if rejected_case == 4 { testing.expect_value(t, play.result, Card_Play_Result.Action_Rejected) }
		testing.expect_value(t, player, before)
		testing.expect_value(t, room.pulse_count, u64(0))
		testing.expect_value(t, room.recent_events.count, 0)
		testing.expect_value(t, room.enemies[0].health, i32(40))
	}
}

@(test)
test_sunder_lethal_hit_does_not_move_removed_target_and_commits_both_dice :: proc(t: ^testing.T) {
	data := spell_test_level(t)
	defer level.destroy(&data)
	player := spell_test_player(t, .Sundering_Blow)
	player.dice = shatter_test_dice_for_total(t, 8)
	enemies := [?]Enemy_Spawn{{position = {3, 1}, health = 1, attack = 1}}
	room, ok := create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	play := play_card(&room, player.deck.hand[0].id, entity_target(enemy_entity(1)))
	testing.expect_value(t, play.result, Card_Play_Result.Combat_Ended)
	testing.expect_value(t, player.dice.roll_count, u64(2))
	testing.expect_value(t, spell_test_event_count(&room.recent_events, .Moved), 0)
	testing.expect_value(t, spell_test_event_count(&room.recent_events, .Spell_Impact), 1)
	testing.expect_value(t, spell_test_event_count(&room.recent_events, .Dice_Rolled), 1)
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect(t, !play.drew_card && !player.deck.combat_active)
	testing.expect_value(t, len(room.enemies), 0)
}

@(test)
test_sunder_reaction_death_stops_the_command_without_pulse_or_draw :: proc(t: ^testing.T) {
	data := spell_test_level(t)
	defer level.destroy(&data)
	player := spell_test_player(t, .Sundering_Blow)
	player.health = 1
	player.dice = shatter_test_dice_for_total(t, 7)
	enemies := [?]Enemy_Spawn{{position = {3, 1}, health = 40, attack = 1}}
	room, ok := create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	applied, _ := apply_status(&room, enemy_entity(1), .Thorns, 5, 3)
	testing.expect(t, applied)
	play := play_card(&room, player.deck.hand[0].id, entity_target(enemy_entity(1)))
	testing.expect_value(t, play.result, Card_Play_Result.Player_Defeated)
	testing.expect_value(t, room.enemies[0].health, i32(33))
	testing.expect_value(t, player.dice.roll_count, u64(2))
	testing.expect_value(t, play.action_report.reactions_triggered, 1)
	testing.expect_value(t, spell_test_event_count(&room.recent_events, .Spell_Impact), 1)
	testing.expect_value(t, spell_test_event_count(&room.recent_events, .Moved), 0)
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect(t, !play.drew_card)
}

@(test)
test_sunder_successful_push_triggers_existing_hazard_and_iron_knuckle_events :: proc(t: ^testing.T) {
	data := spell_test_level(t)
	defer level.destroy(&data)
	player := spell_test_player(t, .Sundering_Blow)
	player.dice = shatter_test_dice_for_total(t, 8)
	testing.expect(t, acquire_relic(&player, .Iron_Knuckle))
	enemies := [?]Enemy_Spawn{{position = {2, 1}, health = 40, attack = 1}}
	objects := [?]Grid_Object_Spawn{{kind = .Fire, position = {3, 1}}}
	room, ok := create_room(&data, &player, {enemies = enemies[:], objects = objects[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	room.enemies[0].intent = make_wait_intent(&room, room.enemies[0].position)
	play := play_card(&room, player.deck.hand[0].id, entity_target(enemy_entity(1)))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, room.enemies[0].position, grid.Position{3, 1})
	testing.expect_value(t, room.enemies[0].health, i32(30))
	testing.expect_value(t, spell_test_event_count(&play.action_report.events, .Moved), 1)
	testing.expect_value(t, spell_test_event_count(&play.action_report.events, .Hazard_Triggered), 1)
	testing.expect_value(t, spell_test_event_count(&play.action_report.events, .Status_Applied), 1)
	shield, found := status_for_entity(&room, PLAYER_ENTITY, .Shield)
	testing.expect(t, found && shield.potency == 1)
	testing.expect_value(t, room.recent_events.dropped_count, 0)
}
