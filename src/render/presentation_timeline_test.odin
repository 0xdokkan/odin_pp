package render

import "core:testing"
import game "../game"
import grid "../grid"
import view "../view"

make_presentation_timeline_test_room :: proc(
	player: ^game.Player,
	enemies: []game.Enemy,
	loot: []game.Loot,
) -> game.Room {
	result := game.Room{player = player, phase = .Combat}
	result.enemies = make([dynamic]game.Enemy, len(enemies))
	for enemy, index in enemies {
		result.enemies[index] = enemy
	}
	result.loot = make([dynamic]game.Loot, len(loot))
	for item, index in loot {
		result.loot[index] = item
	}
	return result
}

presentation_timeline_values_are_close :: proc(a, b: f32, epsilon: f32 = 0.001) -> bool {
	return abs(a-b) <= epsilon
}

expect_presentation_position :: proc(t: ^testing.T, actual, expected: view.Vec2) {
	testing.expectf(
		t,
		presentation_timeline_values_are_close(actual.x, expected.x),
		"x: expected %v, got %v",
		expected.x,
		actual.x,
	)
	testing.expectf(
		t,
		presentation_timeline_values_are_close(actual.y, expected.y),
		"y: expected %v, got %v",
		expected.y,
		actual.y,
	)
}

advance_current_presentation_cue :: proc(t: ^testing.T, timeline: ^Presentation_Timeline) -> bool {
	cue, found := active_presentation_cue(timeline)
	testing.expect(t, found)
	if !found {
		return false
	}
	return update_event_timeline(timeline, cue.duration)
}

@(test)
test_capture_room_presentation_copies_fixed_actor_and_loot_state :: proc(t: ^testing.T) {
	player := game.Player{
		position = {x = 1, y = 2},
		stats = {max_health = 10, attack = 2, defense = 1},
		health = 8,
		gold = 7,
	}
	player.statuses.items[0] = {.Shield, 3, 2}
	player.statuses.count = 1
	testing.expect(t, game.initialize_starter_deck(&player.deck, 77))
	testing.expect(t, game.begin_deck_combat(&player.deck))
	captured_deck := player.deck
	enemies := [?]game.Enemy{
		{id = 4, archetype = .Archer, position = {x = 5, y = 2}, max_health = 6, health = 4},
		{id = 9, archetype = .Brute, position = {x = 7, y = 3}, max_health = 9, health = 9},
	}
	loot := [?]game.Loot{{position = {x = 3, y = 2}, kind = .Gold, amount = 2}}
	room := make_presentation_timeline_test_room(&player, enemies[:], loot[:])
	defer game.destroy_room(&room)
	append(&room.traps, game.Trap{id = 8, position = {x = 2, y = 2}, damage = 3, armed = true})
	room.pulse_count = 12

	presentation := capture_room_presentation(&room)

	testing.expect(t, presentation.valid)
	testing.expect_value(t, presentation.phase, game.Room_Phase.Combat)
	testing.expect_value(t, presentation.gold, i32(7))
	testing.expect_value(t, presentation.pulse_count, u64(12))
	testing.expect_value(t, presentation.enemy_count, 2)
	testing.expect_value(t, presentation.trap_count, 1)
	testing.expect_value(t, presentation.traps[0], room.traps[0])
	testing.expect_value(t, presentation.loot_count, 1)
	testing.expect(t, presentation.loot[0].visible)
	testing.expect_value(t, presentation.deck, captured_deck)
	expect_presentation_position(t, presentation.player.position, {x = 1, y = 2})
	testing.expect_value(t, presentation.player.statuses.items[0].kind, game.Status_Kind.Shield)
	player.deck.energy = 0
	testing.expect_value(t, presentation.deck, captured_deck)

	timeline := Presentation_Timeline{view = presentation}
	archer, found := presentation_actor(&timeline, game.enemy_entity(4))
	testing.expect(t, found)
	if found {
		testing.expect_value(t, archer.archetype, game.Enemy_Archetype.Archer)
		testing.expect_value(t, archer.health, i32(4))
		expect_presentation_position(t, archer.position, {x = 5, y = 2})
	}
	_, missing := presentation_actor(&timeline, game.enemy_entity(99))
	testing.expect(t, !missing)
}

@(test)
test_card_played_cue_pays_and_discards_only_the_snapshot_card :: proc(t: ^testing.T) {
	player := game.Player{stats = {max_health = 10}, health = 10}
	testing.expect(t, game.initialize_starter_deck(&player.deck, 123))
	testing.expect(t, game.begin_deck_combat(&player.deck))
	room := make_presentation_timeline_test_room(&player, nil, nil)
	defer game.destroy_room(&room)
	before := capture_room_presentation(&room)
	authoritative_deck := player.deck
	card := before.deck.hand[0]
	definition, found := game.card_definition_by_id(card.definition_id)
	testing.expect(t, found)
	events: game.Event_Log
	game.record_event(&events, {
		kind = .Card_Played,
		target = game.PLAYER_ENTITY,
		amount = definition.cost,
		card_id = card.id,
		card_definition = card.definition_id,
	})

	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, &events))
	testing.expect_value(t, timeline.view.deck, before.deck)
	update_event_timeline(&timeline, PRESENTATION_CARD_PLAY_DURATION*0.5)
	testing.expect_value(t, timeline.view.deck.energy, before.deck.energy-definition.cost)
	testing.expect_value(t, timeline.view.deck.hand_count, before.deck.hand_count-1)
	testing.expect_value(t, timeline.view.deck.discard_count, before.deck.discard_count+1)
	_, still_in_hand := game.hand_card_index_by_id(&timeline.view.deck, card.id)
	testing.expect(t, !still_in_hand)
	testing.expect_value(
		t,
		timeline.view.deck.discard_pile[timeline.view.deck.discard_count-1],
		card,
	)
	testing.expect(t, game.validate_deck_state(&timeline.view.deck))
	testing.expect_value(t, player.deck, authoritative_deck)
	testing.expect_value(t, timeline.update_failures, 0)

	bad_events := events
	bad_events.events[0].card_definition = .Strike
	if card.definition_id == .Strike {
		bad_events.events[0].card_definition = .Guard
	}
	bad_timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&bad_timeline, before, &bad_events))
	update_event_timeline(&bad_timeline, PRESENTATION_CARD_PLAY_DURATION*0.5)
	testing.expect_value(t, bad_timeline.view.deck, before.deck)
	testing.expect_value(t, bad_timeline.update_failures, 1)
}

@(test)
test_card_draw_cue_replays_reshuffle_and_rejects_event_mismatches_atomically :: proc(t: ^testing.T) {
	player := game.Player{stats = {max_health = 10}, health = 10}
	rules := game.Deck_Rules{hand_size = 2, max_energy = 3, energy_regen_per_pulse = 1}
	testing.expect(t, game.initialize_empty_deck(&player.deck, rules, 456))
	definitions := [?]game.Card_Id{.Strike, .Guard, .Toxic_Wave}
	for definition_id in definitions {
		_, added := game.add_owned_card(&player.deck, definition_id)
		testing.expect(t, added)
	}
	testing.expect(t, game.begin_deck_combat(&player.deck))
	_, discarded := game.discard_hand_card(&player.deck, 0)
	testing.expect(t, discarded)
	_, drawn := game.draw_card(&player.deck)
	testing.expect(t, drawn)
	testing.expect_value(t, player.deck.draw_count, 0)
	testing.expect_value(t, player.deck.discard_count, 1)

	room := make_presentation_timeline_test_room(&player, nil, nil)
	defer game.destroy_room(&room)
	before := capture_room_presentation(&room)
	card := before.deck.hand[0]
	definition, found := game.card_definition_by_id(card.definition_id)
	testing.expect(t, found)
	expected := before.deck
	expected.energy -= definition.cost
	hand_index, in_hand := game.hand_card_index_by_id(&expected, card.id)
	testing.expect(t, in_hand)
	_, discarded = game.discard_hand_card(&expected, hand_index)
	testing.expect(t, discarded)
	expected_drawn, drew_expected := game.draw_card(&expected)
	testing.expect(t, drew_expected)
	testing.expect_value(t, expected.discard_count, 0)
	testing.expect_value(t, expected.draw_count, 1)

	events: game.Event_Log
	game.record_event(&events, {
		kind = .Card_Played,
		target = game.PLAYER_ENTITY,
		amount = definition.cost,
		card_id = card.id,
		card_definition = card.definition_id,
	})
	game.record_event(&events, {
		kind = .Card_Drawn,
		target = game.PLAYER_ENTITY,
		card_id = expected_drawn.id,
		card_definition = expected_drawn.definition_id,
	})
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, &events))
	testing.expect(t, !advance_current_presentation_cue(t, &timeline))
	testing.expect_value(t, timeline.view.deck.draw_count, 0)
	testing.expect_value(t, timeline.view.deck.discard_count, 2)
	testing.expect(t, advance_current_presentation_cue(t, &timeline))
	testing.expect_value(t, timeline.view.deck, expected)
	testing.expect_value(t, player.deck, before.deck)
	testing.expect_value(t, timeline.update_failures, 0)

	draw_only_before := before
	_, discarded = game.discard_hand_card(&draw_only_before.deck, 0)
	testing.expect(t, discarded)
	expected_after_draw := draw_only_before.deck
	actual_drawn: game.Card_Instance
	actual_drawn, drew_expected = game.draw_card(&expected_after_draw)
	testing.expect(t, drew_expected)
	bad_draw_events: game.Event_Log
	game.record_event(&bad_draw_events, {
		kind = .Card_Drawn,
		target = game.PLAYER_ENTITY,
		card_id = actual_drawn.id+1000,
		card_definition = actual_drawn.definition_id,
	})
	bad_id_timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&bad_id_timeline, draw_only_before, &bad_draw_events))
	advance_current_presentation_cue(t, &bad_id_timeline)
	testing.expect_value(t, bad_id_timeline.view.deck, draw_only_before.deck)
	testing.expect_value(t, bad_id_timeline.update_failures, 1)

	bad_draw_events.events[0].card_id = actual_drawn.id
	bad_draw_events.events[0].card_definition = .Strike
	if actual_drawn.definition_id == .Strike {
		bad_draw_events.events[0].card_definition = .Guard
	}
	bad_definition_timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(
		&bad_definition_timeline,
		draw_only_before,
		&bad_draw_events,
	))
	advance_current_presentation_cue(t, &bad_definition_timeline)
	testing.expect_value(t, bad_definition_timeline.view.deck, draw_only_before.deck)
	testing.expect_value(t, bad_definition_timeline.update_failures, 1)
}

@(test)
test_timeline_preserves_event_fifo_and_rejects_replacement_while_busy :: proc(t: ^testing.T) {
	player := game.Player{stats = {max_health = 10}, health = 10}
	enemies := [?]game.Enemy{
		{id = 5, archetype = .Chaser, position = {x = 5, y = 2}, max_health = 6, health = 6},
	}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	before := capture_room_presentation(&room)
	events: game.Event_Log
	game.record_event(&events, {
		kind = .Card_Played,
		target = game.PLAYER_ENTITY,
		card_id = 11,
		card_definition = .Strike,
	})
	game.record_event(&events, {
		kind = .Moved,
		target = game.enemy_entity(5),
		from_position = {x = 5, y = 2},
		to_position = {x = 4, y = 2},
	})
	game.record_event(&events, {
		kind = .Damaged,
		target = game.enemy_entity(5),
		amount = 2,
	})

	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, &events))
	testing.expect_value(t, timeline.count, 3)
	expected := [?]Presentation_Cue_Kind{.Card_Played, .Move, .Damage}
	for kind, index in expected {
		cue, found := presentation_cue_at(&timeline, index)
		testing.expect(t, found)
		if found {
			testing.expect_value(t, cue.kind, kind)
		}
	}
	testing.expect(t, !begin_event_timeline(&timeline, {}, &events))
	testing.expect_value(t, timeline.count, 3)

	testing.expect(t, !advance_current_presentation_cue(t, &timeline))
	cue, found := active_presentation_cue(&timeline)
	testing.expect(t, found)
	if found {
		testing.expect_value(t, cue.kind, Presentation_Cue_Kind.Move)
		testing.expect(t, !cue.started)
	}
	clear_event_timeline(&timeline)
	testing.expect(t, !event_timeline_is_busy(&timeline))
	testing.expect_value(t, timeline.count, 0)
}

@(test)
test_all_game_events_have_stable_presentation_cue_kinds :: proc(t: ^testing.T) {
	event_kinds := [?]game.Game_Event_Kind{
		.Damaged,
		.Damage_Absorbed,
		.Healed,
		.Moved,
		.Move_Blocked,
		.Attack_Missed,
		.Gold_Gained,
		.Loot_Dropped,
		.Loot_Collected,
		.Card_Played,
		.Card_Drawn,
		.Entity_Defeated,
		.Status_Applied,
		.Status_Removed,
		.Status_Expired,
		.Reaction_Binding_Added,
		.Reaction_Binding_Exhausted,
		.Reaction_Binding_Expired,
		.Pulse_Advanced,
	}
	expected := [?]Presentation_Cue_Kind{
		.Damage,
		.Damage_Absorbed,
		.Heal,
		.Move,
		.Move_Blocked,
		.Attack_Missed,
		.Gold_Gained,
		.Loot_Dropped,
		.Loot,
		.Card_Played,
		.Card_Drawn,
		.Defeat,
		.Status_Applied,
		.Status_Removed,
		.Status_Expired,
		.Binding_Added,
		.Binding_Exhausted,
		.Binding_Expired,
		.Pulse_Advanced,
	}
	for kind, index in event_kinds {
		event := game.Game_Event{kind = kind, target = game.PLAYER_ENTITY}
		cue_kind := presentation_cue_kind(event)
		testing.expect_value(t, cue_kind, expected[index])
		testing.expect(t, presentation_cue_duration(cue_kind, event) > 0)
	}
}

@(test)
test_pulse_cue_syncs_status_energy_and_count_from_the_final_snapshot :: proc(t: ^testing.T) {
	player := game.Player{
		stats = {max_health = 10},
		health = 10,
	}
	player.statuses.items[0] = {.Shield, 3, 3}
	player.statuses.count = 1
	player.deck.energy = 0
	room := make_presentation_timeline_test_room(&player, nil, nil)
	defer game.destroy_room(&room)
	before := capture_room_presentation(&room)

	player.statuses.items[0].remaining_pulses = 2
	player.deck.energy = 1
	room.pulse_count = 1
	after := capture_room_presentation(&room)
	events: game.Event_Log
	game.record_event(&events, {
		kind = .Pulse_Advanced,
		source = game.SYSTEM_ENTITY,
		target = game.PLAYER_ENTITY,
		pulse_count = 1,
		energy = 1,
		statuses_advanced = true,
	})
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, &events, &after))
	testing.expect(t, !update_event_timeline(&timeline, PRESENTATION_PULSE_DURATION*0.5))

	testing.expect_value(t, timeline.view.pulse_count, u64(1))
	testing.expect_value(t, timeline.view.deck.energy, i32(1))
	shield_index, found := game.status_index(&timeline.view.player.statuses, .Shield)
	testing.expect(t, found)
	if found {
		testing.expect_value(
			t,
			timeline.view.player.statuses.items[shield_index].remaining_pulses,
			i32(2),
		)
	}
	testing.expect_value(t, timeline.update_failures, 0)
	testing.expect_value(t, before.player.statuses.items[0].remaining_pulses, i32(3))
}

@(test)
test_trap_stays_armed_during_movement_and_disarms_when_its_damage_starts :: proc(t: ^testing.T) {
	player := game.Player{
		position = {x = 1, y = 1},
		stats = {max_health = 10},
		health = 10,
	}
	room := make_presentation_timeline_test_room(&player, nil, nil)
	defer game.destroy_room(&room)
	append(&room.traps, game.Trap{id = 4, position = {x = 2, y = 1}, damage = 3, armed = true})
	before := capture_room_presentation(&room)
	room.traps[0].armed = false
	events: game.Event_Log
	game.record_event(&events, {
		kind = .Moved,
		target = game.PLAYER_ENTITY,
		from_position = {x = 1, y = 1},
		to_position = {x = 2, y = 1},
	})
	game.record_event(&events, {
		kind = .Damaged,
		source = game.trap_entity(4),
		target = game.PLAYER_ENTITY,
		amount = 3,
	})
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, &events))
	trap, found := presentation_trap(&timeline.view, 4)
	testing.expect(t, found)
	if found {
		testing.expect(t, trap.armed)
	}
	advance_current_presentation_cue(t, &timeline)
	trap, found = presentation_trap(&timeline.view, 4)
	if found {
		testing.expect(t, trap.armed)
	}
	update_event_timeline(&timeline, PRESENTATION_DAMAGE_DURATION*0.5)
	trap, found = presentation_trap(&timeline.view, 4)
	if found {
		testing.expect(t, !trap.armed)
	}
	testing.expect_value(t, timeline.update_failures, 0)
}

@(test)
test_dropped_loot_appears_before_the_magnetic_collection_cue :: proc(t: ^testing.T) {
	player := game.Player{
		position = {x = 1, y = 1},
		stats = {max_health = 10},
		health = 10,
	}
	room := make_presentation_timeline_test_room(&player, nil, nil)
	defer game.destroy_room(&room)
	position := grid.Position{x = 2, y = 1}
	events: game.Event_Log
	game.record_event(&events, {
		kind = .Loot_Dropped,
		source = game.enemy_entity(3),
		target = game.SYSTEM_ENTITY,
		amount = 1,
		from_position = position,
		to_position = position,
		loot_kind = .Gold,
	})
	game.record_event(&events, {
		kind = .Loot_Collected,
		source = game.PLAYER_ENTITY,
		target = game.PLAYER_ENTITY,
		amount = 1,
		from_position = position,
		to_position = player.position,
		loot_kind = .Gold,
	})
	game.record_event(&events, {
		kind = .Gold_Gained,
		target = game.PLAYER_ENTITY,
		amount = 1,
	})
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(
		&timeline,
		capture_room_presentation(&room),
		&events,
	))
	update_event_timeline(&timeline, PRESENTATION_NOTICE_DURATION*0.5)
	testing.expect_value(t, timeline.view.loot_count, 1)
	testing.expect(t, timeline.view.loot[0].visible)
	update_event_timeline(&timeline, PRESENTATION_NOTICE_DURATION*0.5)
	testing.expect(t, timeline.view.loot[0].visible)
	update_event_timeline(&timeline, PRESENTATION_LOOT_DURATION*0.5)
	testing.expect(t, !timeline.view.loot[0].visible)
	testing.expect_value(t, timeline.update_failures, 0)
}

@(test)
test_repeated_moves_remain_distinct_and_interpolate_from_committed_pose :: proc(t: ^testing.T) {
	player := game.Player{stats = {max_health = 10}, health = 10}
	enemy_ref := game.enemy_entity(7)
	enemies := [?]game.Enemy{
		{id = enemy_ref.id, archetype = .Chaser, position = {x = 5, y = 2}, max_health = 6, health = 6},
	}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	events: game.Event_Log
	game.record_event(&events, {
		kind = .Moved,
		target = enemy_ref,
		from_position = {x = 5, y = 2},
		to_position = {x = 4, y = 2},
	})
	game.record_event(&events, {
		kind = .Moved,
		target = enemy_ref,
		from_position = {x = 4, y = 2},
		to_position = {x = 3, y = 2},
	})
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, capture_room_presentation(&room), &events))
	testing.expect_value(t, timeline.count, 2)

	update_event_timeline(&timeline, PRESENTATION_ENEMY_MOVE_DURATION*0.5)
	actor, found := presentation_actor(&timeline, enemy_ref)
	testing.expect(t, found)
	if found {
		expect_presentation_position(t, actor.position, {x = 4.5, y = 2})
	}
	testing.expect(t, !update_event_timeline(&timeline, PRESENTATION_ENEMY_MOVE_DURATION*0.5))
	actor, found = presentation_actor(&timeline, enemy_ref)
	if found {
		expect_presentation_position(t, actor.position, {x = 4, y = 2})
	}
	testing.expect_value(t, timeline.count, 1)

	update_event_timeline(&timeline, PRESENTATION_ENEMY_MOVE_DURATION*0.5)
	actor, found = presentation_actor(&timeline, enemy_ref)
	if found {
		expect_presentation_position(t, actor.position, {x = 3.5, y = 2})
	}
	testing.expect(t, update_event_timeline(&timeline, PRESENTATION_ENEMY_MOVE_DURATION*0.5))
	testing.expect(t, !event_timeline_is_busy(&timeline))
	actor, found = presentation_actor(&timeline, enemy_ref)
	if found {
		expect_presentation_position(t, actor.position, {x = 3, y = 2})
	}
}

@(test)
test_damage_heal_absorb_and_status_events_update_only_the_snapshot :: proc(t: ^testing.T) {
	player := game.Player{stats = {max_health = 10}, health = 8}
	player.statuses.items[0] = {.Shield, 3, 3}
	player.statuses.count = 1
	enemy_ref := game.enemy_entity(12)
	enemies := [?]game.Enemy{
		{id = enemy_ref.id, archetype = .Archer, position = {x = 5, y = 2}, max_health = 8, health = 6},
	}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	events: game.Event_Log
	game.record_event(&events, {kind = .Damaged, target = enemy_ref, amount = 2})
	game.record_event(&events, {kind = .Healed, target = enemy_ref, amount = 1})
	game.record_event(&events, {
		kind = .Status_Applied,
		target = enemy_ref,
		amount = 2,
		status = .Poison,
		duration = 3,
	})
	game.record_event(&events, {kind = .Status_Removed, target = enemy_ref, status = .Poison})
	game.record_event(&events, {
		kind = .Damage_Absorbed,
		target = game.PLAYER_ENTITY,
		amount = 2,
		status = .Shield,
	})
	game.record_event(&events, {
		kind = .Status_Removed,
		target = game.PLAYER_ENTITY,
		status = .Shield,
	})
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, capture_room_presentation(&room), &events))

	advance_current_presentation_cue(t, &timeline)
	actor, found := presentation_actor(&timeline, enemy_ref)
	if found {
		testing.expect_value(t, actor.health, i32(4))
	}
	testing.expect_value(t, room.enemies[0].health, i32(6))

	advance_current_presentation_cue(t, &timeline)
	actor, found = presentation_actor(&timeline, enemy_ref)
	if found {
		testing.expect_value(t, actor.health, i32(5))
	}
	advance_current_presentation_cue(t, &timeline)
	actor, found = presentation_actor(&timeline, enemy_ref)
	if found {
		index, has_poison := game.status_index(&actor.statuses, .Poison)
		testing.expect(t, has_poison)
		if has_poison {
			testing.expect_value(t, actor.statuses.items[index].potency, i32(2))
			testing.expect_value(t, actor.statuses.items[index].remaining_pulses, i32(3))
		}
	}
	advance_current_presentation_cue(t, &timeline)
	actor, found = presentation_actor(&timeline, enemy_ref)
	if found {
		_, has_poison := game.status_index(&actor.statuses, .Poison)
		testing.expect(t, !has_poison)
	}
	advance_current_presentation_cue(t, &timeline)
	presented_player, player_found := presentation_actor(&timeline, game.PLAYER_ENTITY)
	if player_found {
		index, has_shield := game.status_index(&presented_player.statuses, .Shield)
		testing.expect(t, has_shield)
		if has_shield {
			testing.expect_value(t, presented_player.statuses.items[index].potency, i32(1))
		}
	}
	testing.expect(t, advance_current_presentation_cue(t, &timeline))
	presented_player, player_found = presentation_actor(&timeline, game.PLAYER_ENTITY)
	if player_found {
		_, has_shield := game.status_index(&presented_player.statuses, .Shield)
		testing.expect(t, !has_shield)
	}
	testing.expect_value(t, player.statuses.count, 1)
	testing.expect_value(t, timeline.update_failures, 0)
}

@(test)
test_defeated_enemy_survives_authoritative_removal_until_its_cue_finishes :: proc(t: ^testing.T) {
	player := game.Player{stats = {max_health = 10}, health = 10}
	enemy_ref := game.enemy_entity(3)
	enemies := [?]game.Enemy{
		{id = enemy_ref.id, archetype = .Brute, position = {x = 3, y = 2}, max_health = 2, health = 2},
	}
	room := make_presentation_timeline_test_room(&player, enemies[:], nil)
	defer game.destroy_room(&room)
	before := capture_room_presentation(&room)
	unordered_remove(&room.enemies, 0)
	testing.expect_value(t, len(room.enemies), 0)
	events: game.Event_Log
	game.record_event(&events, {kind = .Damaged, target = enemy_ref, amount = 2})
	game.record_event(&events, {kind = .Entity_Defeated, target = enemy_ref})
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, before, &events))

	advance_current_presentation_cue(t, &timeline)
	actor, found := presentation_actor(&timeline, enemy_ref)
	testing.expect(t, found)
	if found {
		testing.expect(t, actor.visible)
		testing.expect_value(t, actor.health, i32(0))
	}
	update_event_timeline(&timeline, PRESENTATION_DEFEAT_DURATION*0.5)
	actor, found = presentation_actor(&timeline, enemy_ref)
	if found {
		testing.expect(t, actor.visible)
		testing.expect(t, presentation_timeline_values_are_close(actor.opacity, 0.5))
	}
	testing.expect(t, update_event_timeline(&timeline, PRESENTATION_DEFEAT_DURATION*0.5))
	actor, found = presentation_actor(&timeline, enemy_ref)
	if found {
		testing.expect(t, !actor.visible)
		testing.expect_value(t, actor.opacity, f32(0))
	}
	testing.expect_value(t, timeline.view.phase, game.Room_Phase.Loot)
}

@(test)
test_timeline_consumes_dt_overshoot_across_multiple_cues :: proc(t: ^testing.T) {
	player := game.Player{stats = {max_health = 10}, health = 10}
	room := make_presentation_timeline_test_room(&player, nil, nil)
	defer game.destroy_room(&room)
	events: game.Event_Log
	game.record_event(&events, {kind = .Damaged, target = game.PLAYER_ENTITY, amount = 2})
	game.record_event(&events, {kind = .Healed, target = game.PLAYER_ENTITY, amount = 1})
	game.record_event(&events, {
		kind = .Card_Drawn,
		target = game.PLAYER_ENTITY,
		card_id = 9,
		card_definition = .Guard,
	})
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, capture_room_presentation(&room), &events))
	dt := PRESENTATION_DAMAGE_DURATION+PRESENTATION_HEAL_DURATION+PRESENTATION_CARD_DRAW_DURATION*0.5

	testing.expect(t, !update_event_timeline(&timeline, dt))
	testing.expect_value(t, timeline.count, 1)
	cue, found := active_presentation_cue(&timeline)
	testing.expect(t, found)
	if found {
		testing.expect_value(t, cue.kind, Presentation_Cue_Kind.Card_Drawn)
		testing.expect(t, cue.started)
		testing.expect(t, presentation_timeline_values_are_close(presentation_cue_progress(cue), 0.5))
	}
	presented_player, player_found := presentation_actor(&timeline, game.PLAYER_ENTITY)
	if player_found {
		testing.expect_value(t, presented_player.health, i32(9))
	}
	testing.expect(t, update_event_timeline(&timeline, PRESENTATION_CARD_DRAW_DURATION*0.5))
	testing.expect(t, !event_timeline_is_busy(&timeline))
}

@(test)
test_timeline_capacity_reports_event_overflow_and_clear_resets_storage :: proc(t: ^testing.T) {
	player := game.Player{stats = {max_health = 10}, health = 10}
	room := make_presentation_timeline_test_room(&player, nil, nil)
	defer game.destroy_room(&room)
	events: game.Event_Log
	for index in 0..<MAX_PRESENTATION_CUES+1 {
		game.record_event(&events, {
			kind = .Card_Drawn,
			target = game.PLAYER_ENTITY,
			card_id = u32(index+1),
			card_definition = .Strike,
		})
	}
	testing.expect_value(t, events.count, MAX_PRESENTATION_CUES)
	testing.expect_value(t, events.dropped_count, 1)
	timeline: Presentation_Timeline
	testing.expect(t, begin_event_timeline(&timeline, capture_room_presentation(&room), &events))
	testing.expect_value(t, timeline.count, MAX_PRESENTATION_CUES)
	testing.expect_value(t, timeline.dropped_count, 1)

	testing.expect(t, update_event_timeline(&timeline, f32(100)))
	testing.expect(t, !event_timeline_is_busy(&timeline))
	clear_event_timeline(&timeline)
	testing.expect_value(t, timeline, Presentation_Timeline{})
}
