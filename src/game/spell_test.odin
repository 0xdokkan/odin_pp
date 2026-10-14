package game

import "core:testing"
import grid "../grid"
import level "../level"

spell_test_level :: proc(t: ^testing.T) -> level.Level {
	rows := [?]string{"############", "#@.........#", "#..........#", "#..........#", "#.........>#", "############"}
	data, err, _ := level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	return data
}

spell_test_player :: proc(t: ^testing.T, definition: Card_Id, upgrade: int = 0) -> Player {
	player := create_test_player(t)
	definitions := [1]Card_Id{definition}
	configure_test_deck(t, &player, definitions[:], {hand_size = 1, max_energy = 3, energy_regen_per_pulse = 1})
	for _ in 0..<upgrade {
		testing.expect_value(t, upgrade_owned_card(&player.deck, player.deck.owned[0].id), Deck_Mutation_Result.Upgraded)
	}
	return player
}

spell_test_dice_for_face :: proc(t: ^testing.T, desired: i32, sides: i32) -> Dice_State {
	for seed in u64(1)..<u64(4000) {
		original := make_dice_state(seed)
		staged := original
		face, ok := roll_die(&staged, sides)
		if ok && face == desired { return original }
	}
	testing.expect(t, false, "could not find deterministic die fixture")
	return make_dice_state(1)
}

spell_test_event_count :: proc(log: ^Event_Log, kind: Game_Event_Kind) -> int {
	count := 0
	for event in log.events[:log.count] { if event.kind == kind { count += 1 } }
	return count
}

@(test)
test_spell_cards_are_collectible_upgradable_and_append_only :: proc(t: ^testing.T) {
	testing.expect_value(t, int(Card_Id.Fate_Strike), int(Card_Id.Volatile_Study)+1)
	testing.expect_value(t, int(Card_Id.Chain_Lightning), int(Card_Id.Sundering_Blow)-1)
	for id in ([2]Card_Id{.Fate_Strike, .Chain_Lightning}) {
		definition, found := card_definition_by_id(id)
		testing.expect(t, found && validate_card_definition(&definition))
		testing.expect(t, !definition.temporary_only && definition.reward_weight > 0 && definition.shop_base_price > 0)
		testing.expect_value(t, definition.cost, i32(2))
		player := spell_test_player(t, id, 1)
		testing.expect_value(t, player.deck.owned[0].upgrade_level, i32(1))
	}
}

@(test)
test_dice_stream_is_reproducible_bounded_and_separate_from_deck :: proc(t: ^testing.T) {
	player := create_test_player(t)
	player.dice = make_dice_state(0xFA7E)
	first, second := player.dice, player.dice
	seen: [6]bool
	for index in 0..<128 {
		a, a_ok := roll_die(&first, 6)
		deck_next_random(&player.deck)
		b, b_ok := roll_die(&second, 6)
		testing.expect(t, a_ok && b_ok && a >= 1 && a <= 6)
		testing.expect_value(t, a, b)
		testing.expect_value(t, first, second)
		testing.expect_value(t, first.roll_count, u64(index+1))
		seen[a-1] = true
	}
	for present in seen { testing.expect(t, present) }
	testing.expect_value(t, player.dice.roll_count, u64(0))
}

@(test)
test_spell_query_and_compile_are_pure_with_stable_distinct_nearest_targets :: proc(t: ^testing.T) {
	data := spell_test_level(t)
	defer level.destroy(&data)
	player := spell_test_player(t, .Chain_Lightning)
	enemies := [?]Enemy_Spawn{
		{position = {3, 1}, health = 40, attack = 1},
		{position = {4, 1}, health = 40, attack = 1},
		{position = {3, 2}, health = 40, attack = 1},
		{position = {8, 1}, health = 40, attack = 1},
	}
	room, ok := create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	before := player
	instance := player.deck.hand[0]
	target := entity_target(enemy_entity(1))
	for _ in 0..<16 {
		path := query_spell_path(&room, instance, target)
		testing.expect_value(t, path.error, Card_Compile_Error.None)
		testing.expect_value(t, path.count, 3)
		testing.expect_value(t, path.targets, [3]Entity_Ref{enemy_entity(1), enemy_entity(2), enemy_entity(3)})
		action, err := compile_card_action(&room, instance, target)
		testing.expect_value(t, err, Card_Compile_Error.None)
		testing.expect_value(t, action.effect_count, 3)
		for effect, index in action.effects[:action.effect_count] {
			testing.expect_value(t, effect.target, path.targets[index])
		}
		room.enemies[1], room.enemies[2] = room.enemies[2], room.enemies[1]
		testing.expect_value(t, player, before)
	}
	instance.definition_id = .Fate_Strike
	path := query_spell_path(&room, instance, target)
	testing.expect_value(t, path.count, 2)
	_, err := compile_card_action(&room, instance, target)
	testing.expect_value(t, err, Card_Compile_Error.None)
	testing.expect_value(t, player, before)
}

@(test)
test_spell_bounces_obey_range_los_and_diagonal_corner_blockers :: proc(t: ^testing.T) {
	data := spell_test_level(t)
	defer level.destroy(&data)
	player := spell_test_player(t, .Chain_Lightning)
	enemies := [?]Enemy_Spawn{
		{position = {3, 1}, health = 40, attack = 1},
		{position = {5, 1}, health = 40, attack = 1},
		{position = {3, 4}, health = 40, attack = 1},
		{position = {7, 4}, health = 40, attack = 1},
	}
	obstacles := [?]grid.Position{{4, 1}}
	room, ok := create_room(&data, &player, {enemies = enemies[:], obstacles = obstacles[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	instance := player.deck.hand[0]
	path := query_spell_path(&room, instance, entity_target(enemy_entity(1)))
	testing.expect_value(t, path.count, 2)
	testing.expect_value(t, path.targets[1], enemy_entity(3))
	far := query_spell_path(&room, instance, entity_target(enemy_entity(4)))
	testing.expect_value(t, far.error, Card_Compile_Error.Target_Out_Of_Range)
	room.enemies[1].position = {4, 2}
	room.enemies[2].position = {9, 4}
	append(&room.obstacles, Obstacle{position = {3, 2}})
	path = query_spell_path(&room, instance, entity_target(enemy_entity(1)))
	testing.expect_value(t, path.count, 1)
}

@(test)
test_fate_rejections_preserve_dice_deck_and_health_including_action_rollback :: proc(t: ^testing.T) {
	data := spell_test_level(t)
	defer level.destroy(&data)
	player := spell_test_player(t, .Fate_Strike)
	enemies := [?]Enemy_Spawn{{position = {3, 1}, health = 40, attack = 1}, {position = {9, 1}, health = 40, attack = 1}}
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
		case 2: player.deck.energy = 0
		case 3: append(&room.obstacles, Obstacle{position = {2, 1}})
		case 4: player.dice.roll_count = max(u64)
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
test_fate_every_face_of_every_die_uses_one_roll_and_only_the_top_face_bounces :: proc(t: ^testing.T) {
	for upgrade in i32(0)..=MAX_DICE_UPGRADE_LEVEL {
		sides := card_die_sides(.Fate_Strike, upgrade)
		for desired in i32(1)..=sides {
			data := spell_test_level(t)
			player := spell_test_player(t, .Fate_Strike, int(upgrade))
			player.dice = spell_test_dice_for_face(t, desired, sides)
			expected_dice := player.dice
			_, expected_ok := roll_die(&expected_dice, sides)
			testing.expect(t, expected_ok)
			enemies := [?]Enemy_Spawn{{position = {3, 1}, health = 100, attack = 1}, {position = {4, 1}, health = 100, attack = 1}}
			room, ok := create_room(&data, &player, {enemies = enemies[:]})
			testing.expect(t, ok)
			card := player.deck.hand[0]
			play := play_card(&room, card.id, entity_target(enemy_entity(1)))
			bounce := desired == sides
			testing.expect_value(t, play.result, Card_Play_Result.Played)
			testing.expect_value(t, player.dice, expected_dice)
			// Upgrades raise only the die: two plus the face, three on the bounce.
			testing.expect_value(t, room.enemies[0].health, i32(100)-(2+desired))
			testing.expect_value(t, room.enemies[1].health, i32(100)-FATE_BOUNCE_DAMAGE if bounce else i32(100))
			testing.expect_value(t, spell_test_event_count(&room.recent_events, .Dice_Rolled), 1)
			testing.expect_value(t, spell_test_event_count(&room.recent_events, .Spell_Launched), 1)
			testing.expect_value(t, spell_test_event_count(&room.recent_events, .Spell_Impact), 2 if bounce else 1)
			testing.expect_value(t, room.recent_events.events[0].kind, Game_Event_Kind.Card_Played)
			die_event := room.recent_events.events[1]
			testing.expect_value(t, die_event.kind, Game_Event_Kind.Dice_Rolled)
			testing.expect_value(t, die_event.amount, desired)
			testing.expect_value(t, die_event.dice_roll, Dice_Roll{faces = {desired, 0, 0}, sides = sides, count = 1, total = desired})
			testing.expect_value(t, die_event.card_id, card.id)
			testing.expect_value(t, die_event.card_upgrade_level, upgrade)
			testing.expect_value(t, room.pulse_count, u64(1))
			testing.expect_value(t, player.deck.energy, i32(2))
			testing.expect_value(t, spell_test_event_count(&room.recent_events, .Card_Drawn), 1)
			testing.expect_value(t, room.recent_events.dropped_count, 0)
			destroy_room(&room)
			level.destroy(&data)
		}
	}
}

@(test)
test_chain_settles_each_hit_and_reaction_in_order_with_one_card_economy :: proc(t: ^testing.T) {
	data := spell_test_level(t)
	defer level.destroy(&data)
	player := spell_test_player(t, .Chain_Lightning, 2)
	enemies := [?]Enemy_Spawn{{position = {3, 1}, health = 40, attack = 1}, {position = {4, 1}, health = 40, attack = 1}, {position = {5, 1}, health = 40, attack = 1}}
	room, ok := create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	for enemy in room.enemies {
		applied, _ := apply_status(&room, enemy_entity(enemy.id), .Thorns, 1, 3)
		testing.expect(t, applied)
	}
	dice_before := player.dice
	play := play_card(&room, player.deck.hand[0].id, entity_target(enemy_entity(1)))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, play.action_report.reactions_triggered, 3)
	testing.expect_value(t, play.action_report.events.count, 10)
	testing.expect_value(t, play.action_report.events.events[0].kind, Game_Event_Kind.Spell_Launched)
	from := grid.Position{1, 1}
	for index in 0..<3 {
		impact := play.action_report.events.events[1+index*3]
		damage := play.action_report.events.events[2+index*3]
		counter := play.action_report.events.events[3+index*3]
		testing.expect_value(t, impact.kind, Game_Event_Kind.Spell_Impact)
		testing.expect_value(t, impact.from_position, from)
		testing.expect_value(t, impact.to_position, enemies[index].position)
		testing.expect_value(t, damage.kind, Game_Event_Kind.Damaged)
		testing.expect_value(t, damage.target, enemy_entity(u32(index+1)))
		testing.expect_value(t, damage.amount, i32(5))
		testing.expect_value(t, counter.kind, Game_Event_Kind.Damaged)
		testing.expect_value(t, counter.target, PLAYER_ENTITY)
		from = impact.to_position
	}
	testing.expect_value(t, player.dice, dice_before)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect_value(t, player.deck.energy, i32(2))
	testing.expect_value(t, spell_test_event_count(&room.recent_events, .Card_Played), 1)
	testing.expect_value(t, spell_test_event_count(&room.recent_events, .Card_Drawn), 1)
}

@(test)
test_spell_bounces_stop_immediately_after_player_dies_to_first_hit_reaction :: proc(t: ^testing.T) {
	for id in ([2]Card_Id{.Chain_Lightning, .Fate_Strike}) {
		data := spell_test_level(t)
		player := spell_test_player(t, id)
		player.health = 1
		// The D4's top face: Fate would bounce if the player survived.
		player.dice = spell_test_dice_for_face(t, 4, 4)
		enemies := [?]Enemy_Spawn{{position = {3, 1}, health = 40, attack = 1}, {position = {4, 1}, health = 40, attack = 1}}
		room, ok := create_room(&data, &player, {enemies = enemies[:]})
		testing.expect(t, ok)
		applied, _ := apply_status(&room, enemy_entity(1), .Thorns, 5, 3)
		testing.expect(t, applied)
		play := play_card(&room, player.deck.hand[0].id, entity_target(enemy_entity(1)))
		testing.expect_value(t, play.result, Card_Play_Result.Player_Defeated)
		testing.expect_value(t, room.enemies[1].health, i32(40))
		testing.expect_value(t, spell_test_event_count(&room.recent_events, .Spell_Impact), 1)
		testing.expect_value(t, player.dice.roll_count, u64(1) if id == .Fate_Strike else u64(0))
		testing.expect_value(t, room.pulse_count, u64(0))
		testing.expect(t, !play.drew_card)
		testing.expect_value(t, room.recent_events.dropped_count, 0)
		destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_firebomb_announces_one_area_impact_groups_only_direct_effects_then_reactions :: proc(t: ^testing.T) {
	data := spell_test_level(t)
	defer level.destroy(&data)
	player := spell_test_player(t, .Firebomb)
	enemies := [?]Enemy_Spawn{{position = {3, 1}, health = 40, attack = 1}, {position = {4, 1}, health = 40, attack = 1}}
	room, ok := create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	for enemy in room.enemies {
		applied, _ := apply_status(&room, enemy_entity(enemy.id), .Thorns, 1, 3)
		testing.expect(t, applied)
	}
	dice_before := player.dice
	play := play_card(&room, player.deck.hand[0].id, cell_target({3, 1}))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, play.action_report.events.count, 6)
	for event, index in play.action_report.events.events[:play.action_report.events.count] {
		if index < 2 {
			testing.expect_value(t, event.visual_group, u32(0))
			testing.expect_value(t, event.from_position, grid.Position{1, 1})
			testing.expect_value(t, event.to_position, grid.Position{3, 1})
		} else if index < 4 {
			testing.expect_value(t, event.kind, Game_Event_Kind.Damaged)
			testing.expect_value(t, event.visual_group, u32(1))
			testing.expect_value(t, event.source, PLAYER_ENTITY)
		} else {
			testing.expect_value(t, event.kind, Game_Event_Kind.Damaged)
			testing.expect_value(t, event.visual_group, u32(0))
			testing.expect_value(t, event.target, PLAYER_ENTITY)
		}
	}
	testing.expect_value(t, spell_test_event_count(&room.recent_events, .Spell_Launched), 1)
	testing.expect_value(t, spell_test_event_count(&room.recent_events, .Spell_Impact), 1)
	testing.expect_value(t, player.dice, dice_before)
}
