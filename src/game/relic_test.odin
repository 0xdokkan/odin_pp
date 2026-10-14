package game

import "core:testing"
import grid "../grid"
import level "../level"

relic_test_events :: proc(log: ^Event_Log, kind: Game_Event_Kind) -> int {
	count := 0
	for event in log.events[:log.count] {
		if event.kind == kind {
			count += 1
		}
	}
	return count
}

@(test)
test_relic_offers_are_seeded_unique_and_exclude_owned :: proc(t: ^testing.T) {
	player := create_test_player(t)
	for seed in 0..<128 {
		before := player
		offers := make_relic_offers(&player, u64(seed))
		testing.expect_value(t, offers, make_relic_offers(&player, u64(seed)))
		testing.expect_value(t, offers.count, RELIC_OFFER_COUNT)
		testing.expect(t, validate_relic_offers(&player, &offers))
		testing.expect_value(t, player, before)
	}
	for definition in RELIC_DEFINITIONS {
		testing.expect(t, acquire_relic(&player, definition.id))
		offers := make_relic_offers(&player, 100)
		testing.expect(t, validate_relic_offers(&player, &offers))
		testing.expect_value(t, offers.count, min(RELIC_OFFER_COUNT, MAX_RUN_RELICS-player.relics.count))
	}
	testing.expect_value(t, make_relic_offers(&player, 100).count, 0)
}

@(test)
test_relic_acquisition_rejects_invalid_duplicate_and_corrupt_inventory_atomically :: proc(t: ^testing.T) {
	player := create_test_player(t)
	testing.expect(t, acquire_relic(&player, .Iron_Knuckle))
	before := player
	for id in ([?]Relic_Id{.None, .Count, .Iron_Knuckle}) {
		testing.expect(t, !acquire_relic(&player, id))
		testing.expect_value(t, player, before)
	}
	player.relics.owned[1] = .Iron_Knuckle
	player.relics.count = 2
	before = player
	testing.expect(t, !validate_relic_state(&player.relics))
	testing.expect(t, !acquire_relic(&player, .Guard_Sigil))
	testing.expect_value(t, player, before)
	testing.expect_value(t, make_relic_offers(&player, 3).count, 0)
}

@(test)
test_relic_guard_entry_persists_inventory_resets_usage_and_cannot_repeat :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	testing.expect(t, acquire_relic(&player, .Guard_Sigil))
	spawns := [?]Enemy_Spawn{{position = {5, 3}, health = 40, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = spawns[:]})
	testing.expect(t, ok)
	shield, found := status_for_entity(&room, PLAYER_ENTITY, .Shield)
	testing.expect(t, found)
	testing.expect_value(t, shield.potency, i32(2))
	testing.expect_value(t, shield.remaining_pulses, i32(3))
	testing.expect_value(t, relic_test_events(&room.recent_events, .Status_Applied), 1)
	apply_entry_relic(&room)
	testing.expect_value(t, shield.potency, i32(2))
	player.relics.combat.exhaust_used = true
	player.relics.combat.poison_used = true
	finish_deck_combat(&player.deck)
	destroy_room(&room)
	room, ok = create_room(&level_data, &player, {enemies = spawns[:]})
	testing.expect(t, ok)
	testing.expect(t, player_has_relic(&player, .Guard_Sigil))
	testing.expect(t, !player.relics.combat.exhaust_used && !player.relics.combat.poison_used)
	shield, found = status_for_entity(&room, PLAYER_ENTITY, .Shield)
	testing.expect(t, found && shield.potency == 2)
	finish_deck_combat(&player.deck)
	destroy_room(&room)
	room, ok = create_room(&level_data, &player, {})
	testing.expect(t, ok)
	defer destroy_room(&room)
	_, found = status_for_entity(&room, PLAYER_ENTITY, .Shield)
	testing.expect(t, !found)
	testing.expect(t, !player.relics.combat.started)
}

@(test)
test_relic_shove_ignores_blocked_push_then_shields_successful_barrel_push :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	testing.expect(t, acquire_relic(&player, .Iron_Knuckle))
	definitions := [?]Card_Id{.Shove, .Shove, .Guard}
	configure_test_deck(t, &player, definitions[:], {hand_size = 3, max_energy = 3, energy_regen_per_pulse = 1})
	spawns := [?]Enemy_Spawn{{position = {5, 3}, health = 40, attack = 1}}
	objects := [?]Grid_Object_Spawn{{kind = .Barrel, position = {2, 1}}}
	obstacles := [?]grid.Position{{3, 1}}
	room, ok := create_room(&level_data, &player, {enemies = spawns[:], objects = objects[:], obstacles = obstacles[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	id := force_card_definition_into_hand(t, &player.deck, .Shove)
	play := play_card(&room, id, entity_target(object_entity(room.objects[0].id)))
	testing.expect(t, card_play_was_committed(play.result))
	testing.expect(t, !player.relics.combat.push_used)
	testing.expect_value(t, room.objects[0].position, grid.Position{2, 1})
	clear(&room.obstacles)
	id = force_card_definition_into_hand(t, &player.deck, .Shove)
	play = play_card(&room, id, entity_target(object_entity(room.objects[0].id)))
	testing.expect(t, card_play_was_committed(play.result))
	testing.expect(t, player.relics.combat.push_used)
	testing.expect_value(t, room.objects[0].position, grid.Position{3, 1})
	testing.expect_value(t, play.action_report.statuses_applied, 1)
	shield, found := status_for_entity(&room, PLAYER_ENTITY, .Shield)
	testing.expect(t, found && shield.potency == 1 && shield.remaining_pulses == 1)
	testing.expect_value(t, room.recent_events.dropped_count, 0)
}

@(test)
test_relic_push_limit_uses_authoritative_pulse_and_ordinary_movement_events :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	testing.expect(t, acquire_relic(&player, .Iron_Knuckle))
	spawns := [?]Enemy_Spawn{{position = {2, 1}, health = 40, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	action := make_action(.Ability, PLAYER_ENTITY)
	testing.expect(t, add_effect(&action, move_effect(enemy_entity(1), {3, 1})))
	report := resolve_action(&room, &action)
	testing.expect_value(t, report.statuses_applied, 1)
	action.effects[0].destination = {4, 1}
	report = resolve_action(&room, &action)
	testing.expect_value(t, report.statuses_applied, 0)
	shield, _ := status_for_entity(&room, PLAYER_ENTITY, .Shield)
	testing.expect_value(t, shield.potency, i32(1))
	room.pulse_count += 1
	action.effects[0].destination = {5, 1}
	report = resolve_action(&room, &action)
	testing.expect_value(t, report.statuses_applied, 1)
	testing.expect_value(t, shield.potency, i32(2))
	testing.expect(t, !report.reaction_limit_reached)
}

@(test)
test_relic_swift_soles_rejects_bad_target_and_refunds_only_first_movement_card :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	testing.expect(t, acquire_relic(&player, .Swift_Soles))
	definitions := [?]Card_Id{.Dash, .Dash, .Guard}
	configure_test_deck(t, &player, definitions[:], {hand_size = 3, max_energy = 5, energy_regen_per_pulse = 0})
	spawns := [?]Enemy_Spawn{{position = {5, 3}, health = 40, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	id := force_card_definition_into_hand(t, &player.deck, .Dash)
	before := player.relics
	bad := play_card(&room, id, cell_target({0, 0}))
	testing.expect(t, !card_play_was_committed(bad.result))
	testing.expect_value(t, player.relics, before)
	play := play_card(&room, id, cell_target({3, 1}))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, player.deck.energy, i32(4))
	testing.expect_value(t, relic_test_events(&room.recent_events, .Energy_Gained), 1)
	testing.expect(t, player.relics.combat.movement_used)
	id = force_card_definition_into_hand(t, &player.deck, .Dash)
	play = play_card(&room, id, cell_target({1, 1}))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, player.deck.energy, i32(2))
	testing.expect_value(t, relic_test_events(&room.recent_events, .Energy_Gained), 0)
}

@(test)
test_relic_ash_bookmark_draws_once_after_exhaust_zone_commit :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	testing.expect(t, acquire_relic(&player, .Ash_Bookmark))
	definitions := [?]Card_Id{.Battle_Focus, .Battle_Focus, .Strike, .Guard, .Arc_Bolt, .Dash, .Thorn_Coat, .Shove, .Guard, .Strike}
	configure_test_deck(t, &player, definitions[:], {hand_size = 3, max_energy = 6, energy_regen_per_pulse = 0})
	spawns := [?]Enemy_Spawn{{position = {5, 3}, health = 40, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	id := force_card_definition_into_hand(t, &player.deck, .Battle_Focus)
	play := play_card(&room, id, entity_target(PLAYER_ENTITY))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, play.destination, Card_Zone.Exhaust)
	testing.expect_value(t, player.deck.hand_count, 6)
	testing.expect(t, player.relics.combat.exhaust_used)
	exhaust_index := -1
	bonus_index := -1
	for event, index in room.recent_events.events[:room.recent_events.count] {
		if event.kind == .Card_Moved && event.to_card_zone == .Exhaust {
			exhaust_index = index
		}
		if event.kind == .Card_Drawn && event.source == SYSTEM_ENTITY {
			bonus_index = index
		}
	}
	testing.expect(t, exhaust_index >= 0 && bonus_index > exhaust_index)
	id = force_card_definition_into_hand(t, &player.deck, .Battle_Focus)
	play = play_card(&room, id, entity_target(PLAYER_ENTITY))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, player.deck.hand_count, 8)
	testing.expect_value(t, relic_test_events(&room.recent_events, .Card_Drawn), 3)
	testing.expect(t, validate_deck_state(&player.deck))
}

@(test)
test_relic_ash_bookmark_refocus_ethereal_grants_card_beyond_normal_refill :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	testing.expect(t, acquire_relic(&player, .Ash_Bookmark))
	definitions := [?]Card_Id{.Battle_Focus, .Strike, .Guard, .Arc_Bolt, .Dash, .Thorn_Coat, .Shove, .Guard}
	configure_test_deck(t, &player, definitions[:], {hand_size = 3, max_energy = 3, energy_regen_per_pulse = 1})
	spawns := [?]Enemy_Spawn{{position = {5, 3}, health = 40, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	force_card_definition_into_hand(t, &player.deck, .Battle_Focus)
	refocus := refocus_player_hand(&room)
	testing.expect_value(t, refocus.result, Refocus_Result.Refocused)
	testing.expect_value(t, player.deck.hand_count, 4)
	testing.expect_value(t, player.deck.exhaust_count, 1)
	testing.expect(t, player.relics.combat.exhaust_used)
	testing.expect_value(t, relic_test_events(&room.recent_events, .Card_Drawn), 4)
	testing.expect(t, validate_deck_state(&player.deck))
}

@(test)
test_relic_movement_death_does_not_refund_energy_or_fire_other_bonuses :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	testing.expect(t, acquire_relic(&player, .Swift_Soles))
	testing.expect(t, acquire_relic(&player, .Mending_Thread))
	player.health = 1
	definitions := [?]Card_Id{.Dash}
	configure_test_deck(t, &player, definitions[:], {hand_size = 1, max_energy = 3, energy_regen_per_pulse = 1})
	spawns := [?]Enemy_Spawn{{position = {5, 3}, health = 40, attack = 1}}
	traps := [?]Trap_Spawn{{position = {2, 1}, damage = 5}}
	room, ok := create_room(&level_data, &player, {enemies = spawns[:], traps = traps[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	id := force_card_definition_into_hand(t, &player.deck, .Dash)
	play := play_card(&room, id, cell_target({3, 1}))
	testing.expect_value(t, play.result, Card_Play_Result.Player_Defeated)
	testing.expect(t, !player.relics.combat.movement_used)
	testing.expect_value(t, relic_test_events(&room.recent_events, .Energy_Gained), 0)
	testing.expect_value(t, relic_test_events(&room.recent_events, .Healed), 0)
	testing.expect_value(t, player.health, i32(0))
}

@(test)
test_relic_venom_vial_boosts_one_enemy_application_and_preserves_rejection :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	testing.expect(t, acquire_relic(&player, .Venom_Vial))
	definitions := [?]Card_Id{.Toxic_Wave}
	configure_test_deck(t, &player, definitions[:], {hand_size = 1, max_energy = 3, energy_regen_per_pulse = 1})
	spawns := [?]Enemy_Spawn{{position = {5, 3}, health = 40, attack = 1}, {position = {4, 3}, health = 40, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	id := force_card_definition_into_hand(t, &player.deck, .Toxic_Wave)
	player.deck.energy = 0
	bad := play_card(&room, id, {})
	testing.expect_value(t, bad.result, Card_Play_Result.Not_Enough_Energy)
	testing.expect(t, !player.relics.combat.poison_used)
	player.deck.energy = 3
	play := play_card(&room, id, {})
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	// Two stacks (the vial's one more) bit once and wore one; the other's single stack is spent.
	first, found := status_for_entity(&room, enemy_entity(1), .Poison)
	testing.expect(t, found && first.potency == 1)
	_, second_found := status_for_entity(&room, enemy_entity(2), .Poison)
	testing.expect(t, !second_found)
	testing.expect(t, player.relics.combat.poison_used)
	testing.expect_value(t, room.enemies[0].health, i32(38))
	testing.expect_value(t, room.enemies[1].health, i32(39))
}

@(test)
test_relic_mending_heals_automatically_after_last_kill_exactly_once :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	testing.expect(t, acquire_relic(&player, .Mending_Thread))
	player.health = 5
	spawns := [?]Enemy_Spawn{{position = {2, 1}, health = 2, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	result := try_move_player(&room, .East)
	testing.expect_value(t, result, Action_Result.Combat_Ended)
	testing.expect_value(t, player.health, i32(7))
	testing.expect(t, player.relics.combat.clear_used)
	testing.expect_value(t, relic_test_events(&room.recent_events, .Healed), 1)
	bonus := apply_room_clear_relics(&room)
	testing.expect(t, !bonus.accepted)
	testing.expect_value(t, player.health, i32(7))
}

@(test)
test_relic_mending_cannot_revive_simultaneous_defeat_or_reward_empty_rooms :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	testing.expect(t, acquire_relic(&player, .Mending_Thread))
	player.health = 2
	spawns := [?]Enemy_Spawn{{position = {2, 1}, health = 2, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = spawns[:]})
	testing.expect(t, ok)
	action := make_action(.Trigger, SYSTEM_ENTITY)
	testing.expect(t, add_effect(&action, damage_effect(enemy_entity(1), 2)))
	testing.expect(t, add_effect(&action, damage_effect(PLAYER_ENTITY, 10)))
	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted && report.player_defeated)
	testing.expect_value(t, player.health, i32(0))
	testing.expect_value(t, report.healing_done, i32(0))
	finish_deck_combat(&player.deck)
	destroy_room(&room)
	player.health = 2
	room, ok = create_room(&level_data, &player, {})
	testing.expect(t, ok)
	defer destroy_room(&room)
	bonus := apply_room_clear_relics(&room)
	testing.expect(t, !bonus.accepted)
	testing.expect_value(t, player.health, i32(2))
}
