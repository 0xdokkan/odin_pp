package game

import "core:testing"
import grid "../grid"
import level "../level"

rework_hand_card :: proc(t: ^testing.T, room: ^Room, definition: Card_Id) -> Card_Instance {
	card := &room.player.deck.hand[0]
	card.definition_id = definition
	for &owned in room.player.deck.owned[:room.player.deck.owned_count] {
		if owned.id == card.id { owned.definition_id = definition }
	}
	testing.expect(t, validate_deck_state(&room.player.deck))
	return card^
}

@(test)
test_tactical_catalog_validates_without_changing_collection_lifetimes :: proc(t: ^testing.T) {
	for id in Card_Id {
		if id == .Count { continue }
		base, _ := card_definition_by_id(id)
		d, found := card_definition_by_id(id, true)
		testing.expect(t, found && d.tactical && validate_card_definition(&d), base.name)
		testing.expect_value(t, d.exhaust_on_play, base.exhaust_on_play)
		testing.expect_value(t, d.temporary_only, base.temporary_only)
		testing.expect_value(t, d.retain_on_refocus, base.retain_on_refocus)
		testing.expect_value(t, d.ethereal, base.ethereal)
		base_scales, tactical_scales := false, false
		for e in base.effects[:base.effect_count] { base_scales = base_scales || e.amount_per_upgrade > 0 }
		for e in d.effects[:d.effect_count] { tactical_scales = tactical_scales || e.amount_per_upgrade > 0 }
		testing.expect_value(t, tactical_scales, base_scales)
	}
}

@(test)
test_tactical_dash_pays_one_shields_before_hazards_and_rejects_blocked_paths :: proc(t: ^testing.T) {
	for blocked in ([?]bool{false, true}) {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {7, 1}, health = 100, attack = 1}}
		room := create_enemy_rework_room(t, &data, &player, spawns[:])
		card := rework_hand_card(t, &room, .Dash)
		append(&room.traps, Trap{id = 99, position = {5, 4}, damage = 3, armed = true})
		if blocked { append(&room.obstacles, Obstacle{position = {5, 4}}) }
		before := player.deck
		before_time := player.tactical.remaining
		player.tactical.dodge_recovery = 2
		result := play_card(&room, card.id, cell_target({6, 4}))
		if blocked {
			testing.expect(t, result.result != .Played)
			testing.expect_value(t, player.deck, before)
			testing.expect_value(t, player.position, grid.Position{4, 4})
			testing.expect_value(t, player.statuses.count, 0)
			testing.expect(t, !room.tactical_pulse.pending)
			testing.expect_value(t, player.tactical.remaining, before_time)
		} else {
			testing.expect_value(t, result.result, Card_Play_Result.Played)
			testing.expect_value(t, player.deck.energy, before.energy-1)
			testing.expect_value(t, player.position, grid.Position{6, 4})
			testing.expect_value(t, player.health, i32(99))
			testing.expect_value(t, player.tactical.dodge_recovery, 2)
			testing.expect_value(t, player.tactical.remaining, before_time-tactical_card_time_cost(.Dash))
			drain_tactical_test_pulse(t, &room)
			// One energy buys a two-second movement card, without beginning
			// a new decision window or restarting the active-dodge cooldown.
			testing.expect_value(t, room.pulse_count, u64(2))
			testing.expect_value(t, player.tactical.cycle, 0)
			testing.expect_value(t, player.tactical.dodge_recovery, 0)
		}
		destroy_room(&room)
		level.destroy(&data)
	}
}

@(test)
test_tactical_heavy_blow_cancels_attack_and_opens_a_strike_window :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {5, 4}, health = 100, attack = 3}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	card := rework_hand_card(t, &room, .Heavy_Blow)
	play := play_card(&room, card.id, entity_target(enemy_entity(1)))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, room.enemies[0].health, i32(96))
	testing.expect(t, !offer_defense_qte(&room, &room.enemies[0]))
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, player.health, i32(100))
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Recover)
	testing.expect_value(t, room.enemies[0].statuses.count, 0)
	testing.expect_value(t, room.pulse_count, u64(3))
	testing.expect_value(t, player.tactical.remaining, f32(17))
	testing.expect_value(t, room.enemies[0].recovery_pulses, i32(1))
	strike := rework_hand_card(t, &room, .Strike)
	action, err := compile_card_action(&room, strike, entity_target(enemy_entity(1)))
	testing.expect_value(t, err, Card_Compile_Error.None)
	testing.expect_value(t, action.effects[0].amount, i32(5))
	played := play_card(&room, strike.id, entity_target(enemy_entity(1)))
	testing.expect_value(t, played.result, Card_Play_Result.Played)
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, room.enemies[0].health, i32(91))
	testing.expect_value(t, player.health, i32(100))
	testing.expect_value(t, tactical_strike_bonus(&room, enemy_entity(1)), i32(0))
	testing.expect_value(t, player.tactical.remaining, f32(15))
	testing.expect_value(t, player.tactical.cycle, 0)
}

@(test)
test_tactical_toxic_wave_is_local_and_respects_occlusion :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {4, 6}, health = 100, attack = 1},
		{position = {1, 4}, health = 100, attack = 1}, {position = {6, 4}, health = 100, attack = 1}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	append(&room.obstacles, Obstacle{position = {5, 4}})
	card := Card_Instance{id = 100, definition_id = .Toxic_Wave}
	evaluation := evaluate_card_targeting(&room, card, {})
	testing.expect_value(t, evaluation.error, Card_Compile_Error.None)
	testing.expect_value(t, evaluation.required_effect_count, 1)
	action, err := compile_card_action(&room, card, {})
	testing.expect_value(t, err, Card_Compile_Error.None)
	testing.expect_value(t, action.effect_count, 1)
	testing.expect_value(t, action.effects[0].target, enemy_entity(1))
	report := resolve_action(&room, &action)
	testing.expect(t, report.accepted)
	for index in 0..<3 { testing.expect_value(t, room.enemies[index].statuses.count, 1 if index == 0 else 0) }
}

@(test)
test_tactical_splash_and_bounces_do_not_reveal_or_hit_hidden_enemies :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {6, 4}, health = 100, attack = 1}, {position = {7, 4}, health = 100, attack = 1}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	player.tactical.config.vision_size = 5
	for id in ([?]Card_Id{.Firebomb, .Caustic_Bloom}) {
		card := Card_Instance{id = 100, definition_id = id}
		d, _ := card_definition_by_id(id, true)
		query := evaluate_card_targeting(&room, card, card_target_request_at(d, {6, 4}))
		testing.expect_value(t, query.error, Card_Compile_Error.None)
		testing.expect_value(t, query.query.enemy_count, 1)
		testing.expect(t, !target_cell_set_contains(&query.query.affected, {7, 4}))
		action, err := compile_card_action(&room, card, cell_target({6, 4}))
		testing.expect_value(t, err, Card_Compile_Error.None)
		testing.expect_value(t, action.effect_count, 1)
	}
	before := player.dice
	for id in ([?]Card_Id{.Chain_Lightning, .Fate_Strike}) {
		path := query_spell_path(&room, {id = 100, definition_id = id}, entity_target(enemy_entity(1)))
		testing.expect_value(t, path.error, Card_Compile_Error.None)
		testing.expect_value(t, path.count, 1)
	}
	testing.expect_value(t, player.dice, before)
}

@(test)
test_tactical_shove_relocates_a_bomb_before_arming_its_impact :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {7, 1}, health = 100, attack = 1}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, spawn_bomb(&room, enemy_entity(1), {5, 4}, &room.recent_events))
	card := rework_hand_card(t, &room, .Shove)
	play := play_card(&room, card.id, entity_target(object_entity(room.objects[0].id)))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, room.objects[0].position, grid.Position{6, 4})
	testing.expect_value(t, player.health, i32(100))
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, player.health, i32(100))
}

@(test)
test_tactical_survey_extends_current_sight_then_expires_without_memory :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {7, 1}, health = 100, attack = 1}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	player.tactical.config.vision_size = 3
	testing.expect(t, !tactical_cell_visible(&room, {6, 4}))
	card := rework_hand_card(t, &room, .Battle_Focus)
	play := play_card(&room, card.id, entity_target(PLAYER_ENTITY))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect(t, tactical_cell_visible(&room, {6, 4}))
	append(&room.obstacles, Obstacle{position = {5, 4}})
	testing.expect(t, !tactical_cell_visible(&room, {6, 4}))
	clear(&room.obstacles)
	drain_tactical_test_pulse(t, &room)
	for _ in 0..<2 { wait_player_turn(&room); drain_tactical_test_pulse(t, &room) }
	testing.expect(t, !tactical_cell_visible(&room, {6, 4}))
	testing.expect_value(t, player.deck.exhaust_count, 1)
	// The directional 2x2 preset expands to a supported centred footprint, not
	// an invalid 4x4 label whose actual mask would contain 25 cells.
	_, _ = apply_status(&room, PLAYER_ENTITY, .Survey, 1, 3)
	for size in ([?]int{2, 3, 5, 7, 9}) {
		player.tactical.config.vision_size = size
		effective := tactical_vision_size(player.tactical.config, &player.statuses)
		testing.expect(t, valid_tactical_vision(effective))
		count := 0
		for y in 0..<9 { for x in 0..<9 { if tactical_cell_visible(&room, {x, y}) { count += 1 } } }
		// Four closed wall corners remain occluded even under Survey.
		testing.expect_value(t, count, 77 if effective == 9 else effective*effective)
	}
	player.tactical.config.vision_size = 0
	testing.expect_value(t, tactical_vision_size(player.tactical.config, &player.statuses), 0)
}
