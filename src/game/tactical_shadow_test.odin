package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

shadow_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, spawns: []Enemy_Spawn = nil) -> Room {
	default_spawns := [?]Enemy_Spawn{{position = {7, 4}, health = 100, attack = 3}}
	room := create_enemy_rework_room(t, data, player, spawns if spawns != nil else default_spawns[:])
	return room
}

shadow_test_play :: proc(t: ^testing.T, room: ^Room) -> Card_Play_Report {
	card := rework_hand_card(t, room, .Shadow_Step)
	return play_card(room, card.id, entity_target(PLAYER_ENTITY))
}

shadow_test_rise :: proc(t: ^testing.T, room: ^Room) {
	for _ in 0..<100 {
		if tactical_shadow_due(room) { break }
		testing.expect(t, !tactical_tick(room, 0.25, true, false))
	}
	testing.expect(t, tactical_end_shadow(room))
}

@(test)
test_shadow_freezes_the_world_window_and_beats_and_resumes_them :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := shadow_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, !tactical_tick(&room, 0.3, true, false))
	before_window, before_fraction := player.tactical.remaining, player.tactical.clock_fraction
	before_beat, before_age := player.tactical.beat_index, player.tactical.beat_age
	enemy := room.enemies[0]
	energy := player.deck.energy
	play := shadow_test_play(t, &room)
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, player.deck.energy, energy-3)
	testing.expect_value(t, player.tactical.phase, Tactical_Phase.Shadow)
	testing.expect(t, tactical_player_intangible(&room) && !tactical_is_casting(&room) && !tactical_player_busy(&room))
	// Nothing but walking: no cards, no attacks, no waits, no dodges.
	testing.expect(t, !tactical_allows_action(&room) && !tactical_allows_cards(&room) && !tactical_allows_movement(&room))
	testing.expect_value(t, try_move_player(&room, .West), Action_Result.Invalid_Phase)
	testing.expect(t, !try_dodge_player(&room, .West))
	testing.expect_value(t, wait_player_turn(&room), Action_Result.Invalid_Phase)
	// Four real seconds pass and the world has not moved.
	for _ in 0..<15 { testing.expect(t, !tactical_tick(&room, 0.25, true, false)) }
	testing.expect(t, !tactical_shadow_due(&room))
	testing.expect(t, !tactical_tick(&room, 0.25, true, false))
	testing.expect(t, tactical_shadow_due(&room))
	testing.expect(t, !room.tactical_pulse.pending)
	testing.expect_value(t, room.pulse_count, u64(0))
	testing.expect_value(t, player.tactical.queued_beats, 0)
	testing.expect_value(t, player.tactical.remaining, before_window)
	testing.expect_value(t, player.tactical.clock_fraction, before_fraction)
	testing.expect_value(t, player.tactical.beat_index, before_beat)
	testing.expect_value(t, player.tactical.beat_age, before_age)
	testing.expect_value(t, room.enemies[0], enemy)
	testing.expect(t, tactical_end_shadow(&room))
	testing.expect_value(t, player.tactical.phase, Tactical_Phase.Decision)
	testing.expect(t, !tactical_player_intangible(&room))
	// The world goes on from 0.3 s: the next beat is 0.7 s away.
	testing.expect(t, !tactical_tick(&room, 0.69, true, false))
	testing.expect(t, !room.tactical_pulse.pending)
	testing.expect(t, !tactical_tick(&room, 0.01, true, false))
	testing.expect(t, room.tactical_pulse.pending)
	drain_tactical_test_pulse(t, &room)
	testing.expect_value(t, room.pulse_count, u64(1))
	testing.expect(t, abs(player.tactical.remaining-(before_window-0.7)) < 0.001)
}

@(test)
test_shadow_steps_use_the_step_rules_from_the_shadow_and_never_move_the_body :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {2, 4}, health = 100, attack = 3}}
	room := shadow_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	append(&room.obstacles, Obstacle{position = {4, 3}})
	testing.expect_value(t, shadow_test_play(t, &room).result, Card_Play_Result.Played)
	body := player.position
	testing.expect_value(t, try_shadow_step(&room, .West), Action_Result.Moved)
	testing.expect_value(t, player.tactical.shadow_position, grid.Position{3, 4})
	testing.expect_value(t, player.position, body)
	testing.expect_value(t, room.recent_events.count, 0)
	// A step lasts 0.4 s; a press meanwhile is refused, not kept.
	testing.expect(t, tactical_player_busy(&room))
	testing.expect_value(t, try_shadow_step(&room, .West), Action_Result.Invalid_Phase)
	testing.expect(t, !tactical_tick(&room, TACTICAL_SHADOW_STEP_SECONDS, true, false))
	testing.expect(t, !tactical_player_busy(&room))
	// Enemies block (never a bump), walls and obstacles block; the body's own
	// cell does not.
	testing.expect_value(t, try_shadow_step(&room, .West), Action_Result.Blocked)
	testing.expect_value(t, room.enemies[0].health, i32(100))
	testing.expect_value(t, try_shadow_step(&room, .East), Action_Result.Moved)
	testing.expect_value(t, player.tactical.shadow_position, body)
	testing.expect(t, !tactical_tick(&room, TACTICAL_SHADOW_STEP_SECONDS, true, false))
	testing.expect_value(t, try_shadow_step(&room, .North), Action_Result.Blocked)
	// 0.8 s into the shadow: not yet its first beat; at 0.9 s, on it.
	testing.expect_value(t, tactical_shadow_beat_target(&room), u32(0))
	testing.expect(t, !tactical_tick(&room, 0.1, true, false))
	beat := tactical_shadow_beat_target(&room)
	testing.expect_value(t, beat, u32(1))
	testing.expect_value(t, tactical_beat_target(&room), beat)
	testing.expect_value(t, try_shadow_step(&room, .South, {1, 1}, beat), Action_Result.Moved)
	testing.expect_value(t, player.tactical.shadow_position, grid.Position{5, 5})
	// Each beat rewards one diagonal; off the beat two keys step straight.
	testing.expect(t, !tactical_tick(&room, TACTICAL_SHADOW_STEP_SECONDS, true, false))
	testing.expect_value(t, tactical_shadow_beat_target(&room), u32(0))
	testing.expect_value(t, try_shadow_step(&room, .North, {1, -1}, beat), Action_Result.Moved)
	testing.expect_value(t, player.tactical.shadow_position, grid.Position{5, 4})
	testing.expect(t, !tactical_tick(&room, TACTICAL_SHADOW_STEP_SECONDS, true, false))
	testing.expect_value(t, try_shadow_step(&room, .South, {-1, 1}, 2), Action_Result.Moved)
	testing.expect_value(t, player.tactical.shadow_position, grid.Position{5, 5})
	testing.expect_value(t, player.position, body)
	testing.expect_value(t, player.tactical.shadow_steps, 5)
}

@(test)
test_shadow_makes_every_damage_path_miss_the_player :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := shadow_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	_, _ = apply_status(&room, PLAYER_ENTITY, .Shield, 2, 3)
	_, _ = apply_status(&room, PLAYER_ENTITY, .Poison, 2, 0)
	_, _ = apply_status(&room, PLAYER_ENTITY, .Burn, 2, 0)
	append(&room.traps, Trap{id = 77, position = player.position, damage = 4, armed = true})
	testing.expect_value(t, shadow_test_play(t, &room).result, Card_Play_Result.Played)
	health := player.health
	blow := make_action(.Attack, enemy_entity(room.enemies[0].id), entity_target(PLAYER_ENTITY), .Opponent)
	testing.expect(t, add_effect(&blow, damage_effect(PLAYER_ENTITY, 9)))
	report := resolve_action(&room, &blow)
	testing.expect(t, report.accepted)
	testing.expect_value(t, report.damage_dealt, i32(0))
	testing.expect_value(t, report.damage_absorbed, i32(0))
	trap := Action_Report{}
	_, _ = trigger_cell_hazard(&room, PLAYER_ENTITY, &trap)
	pulse: Pulse_Report
	tick_entity_statuses(&room, PLAYER_ENTITY, &pulse)
	// Neither his poison (no action of his: it does not even wear) nor his burn.
	tick_poison_on_action(&room, PLAYER_ENTITY, &pulse)
	burn_status(&room, PLAYER_ENTITY, &pulse)
	testing.expect_value(t, player.health, health)
	shield, shielded := status_for_entity(&room, PLAYER_ENTITY, .Shield)
	testing.expect(t, shielded && shield.potency == 2)
	poison, poisoned := status_for_entity(&room, PLAYER_ENTITY, .Poison)
	testing.expect(t, poisoned && poison.potency == 2)
	shadow_test_rise(t, &room)
	again := resolve_action(&room, &blow)
	testing.expect(t, again.accepted && again.damage_dealt > 0)
}

@(test)
test_shadow_rises_with_a_teleport_takes_loot_and_old_telegraphs_miss :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {4, 3}, health = 100, attack = 3}}
	room := shadow_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Attack)
	testing.expect_value(t, shadow_test_play(t, &room).result, Card_Play_Result.Played)
	// Dropped inside the magnet's reach of the landing only: nothing is
	// collected while the body waits in its shadow.
	append(&room.loot, Loot{position = {1, 7}, kind = .Gold, amount = 3})
	origin := player.position
	for direction in ([?]Move_Direction{.South, .South, .West, .West}) {
		testing.expect_value(t, try_shadow_step(&room, direction), Action_Result.Moved)
		testing.expect(t, !tactical_tick(&room, TACTICAL_SHADOW_STEP_SECONDS, true, false))
	}
	gold := player.gold
	shadow_test_rise(t, &room)
	testing.expect_value(t, player.position, grid.Position{2, 6})
	testing.expect_value(t, player.gold, gold+3)
	moved, emerged := 0, 0
	for event in room.recent_events.events[:room.recent_events.count] {
		if event.kind == .Moved && event.target == PLAYER_ENTITY {
			moved += 1
			testing.expect(t, event_is_teleport(event))
			testing.expect_value(t, event.from_position, origin)
			testing.expect_value(t, event.to_position, grid.Position{2, 6})
		}
		if event.kind == .Shadow_Emerged { emerged += 1 }
	}
	testing.expect_value(t, moved, 1)
	testing.expect_value(t, emerged, 1)
	// The telegraph aimed at the old cell lands on nothing.
	health := player.health
	advance_enemy_rework_seconds(t, &room, 2)
	testing.expect_value(t, player.health, health)
}

@(test)
test_shadow_from_a_stun_keeps_the_stun_and_rising_in_place_teleports_nothing :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := shadow_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	player.tactical.phase, player.tactical.remaining, player.tactical.stun_duration = .Stunned, 1.5, 2
	testing.expect(t, tactical_allows_cards(&room))
	testing.expect_value(t, shadow_test_play(t, &room).result, Card_Play_Result.Played)
	testing.expect_value(t, player.tactical.shadow_resume, Tactical_Phase.Stunned)
	origin := player.position
	shadow_test_rise(t, &room)
	testing.expect_value(t, player.tactical.phase, Tactical_Phase.Stunned)
	testing.expect_value(t, player.tactical.remaining, f32(1.5))
	testing.expect_value(t, player.position, origin)
	for event in room.recent_events.events[:room.recent_events.count] {
		testing.expect(t, event.kind != .Moved)
	}
}

@(test)
test_shadow_is_refused_while_the_world_is_busy_and_reset_by_a_new_room :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := shadow_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	tactical_spend_action_time(&room, 1)
	testing.expect(t, room.tactical_pulse.pending)
	testing.expect(t, !tactical_can_begin_shadow(&room))
	drain_tactical_test_pulse(t, &room)
	tactical_begin_card_cast(&room, 1)
	testing.expect(t, !tactical_can_begin_shadow(&room))
	testing.expect(t, !tactical_tick(&room, 1, true, false))
	drain_tactical_test_pulse(t, &room)
	player.tactical.action_remaining = 0.5
	testing.expect(t, !tactical_can_begin_shadow(&room))
	player.tactical.action_remaining = 0
	testing.expect(t, tactical_begin_shadow(&room, TACTICAL_SHADOW_SECONDS))
	testing.expect(t, !tactical_begin_shadow(&room, TACTICAL_SHADOW_SECONDS))
	begin_tactical_room(&room)
	testing.expect_value(t, player.tactical.phase, Tactical_Phase.Decision)
	testing.expect_value(t, player.tactical.shadow_remaining, f32(0))
}

@(test)
test_shadow_stops_the_sandbox_arrivals :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := shadow_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	room.endless = true
	sandbox := begin_sandbox(5)
	testing.expect(t, tactical_begin_shadow(&room, TACTICAL_SHADOW_SECONDS))
	timer := sandbox.timer
	_, spawned := sandbox_tick(&room, &sandbox, 100)
	testing.expect(t, !spawned)
	testing.expect_value(t, sandbox.timer, timer)
	testing.expect_value(t, len(room.enemies), 1)
}

// The card: Rare, three energy and no window time, four seconds that no
// upgrade lengthens, an ordinary collectible kept out of the starter deck.
@(test)
test_shadow_card_is_a_rare_untimed_self_card_without_upgrades :: proc(t: ^testing.T) {
	d, found := card_definition_by_id(.Shadow_Step)
	testing.expect(t, found && validate_card_definition(&d))
	testing.expect_value(t, d.name, "Movimento Ombra")
	testing.expect_value(t, d.rarity, Card_Rarity.Rare)
	testing.expect_value(t, d.reward_weight, u32(60))
	testing.expect_value(t, d.shop_base_price, i32(8))
	testing.expect_value(t, d.cost, i32(3))
	testing.expect(t, !d.temporary_only && !d.exhaust_on_play && !d.retain_on_refocus && !d.ethereal)
	testing.expect_value(t, d.targeting.rule, Target_Rule.Self)
	testing.expect_value(t, d.effect_count, 1)
	testing.expect_value(t, d.effects[0].kind, Effect_Kind.Enter_Shadow)
	testing.expect_value(t, f32(d.effects[0].base_amount), TACTICAL_SHADOW_SECONDS)
	testing.expect_value(t, d.effects[0].amount_per_upgrade, i32(0))

	testing.expect(t, !card_is_scopa(.Shadow_Step))
	testing.expect_value(t, tactical_card_time_cost(.Shadow_Step), f32(0))
	card := Card_Instance{id = 1, definition_id = .Shadow_Step}
	testing.expect(t, validate_card_instance(card) && !card_can_upgrade(card))
	destination, valid := card_destination_after_play(card)
	testing.expect(t, valid)
	testing.expect_value(t, destination, Card_Zone.Discard)
	// An upgrade could only lengthen the shadow: the template refuses one.
	scaled, _ := card_definition_by_id(.Shadow_Step)
	scaled.effects[0].amount_per_upgrade = 1
	testing.expect(t, !validate_card_definition(&scaled))
	player := create_test_player(t)
	for owned in player.deck.owned[:player.deck.owned_count] { testing.expect(t, owned.definition_id != .Shadow_Step) }
}

// Played in a tactical room it costs its energy and no window time; the hand
// gets its replacement at once and the sinking is recorded. Recovery and a
// running cast refuse it.
@(test)
test_shadow_card_play_draws_its_replacement_now_and_records_the_sinking :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := shadow_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	card := rework_hand_card(t, &room, .Shadow_Step)
	player.tactical.phase, player.tactical.remaining = .Recovery, 1
	testing.expect_value(t, play_card(&room, card.id, entity_target(PLAYER_ENTITY)).result, Card_Play_Result.Invalid_Phase)
	player.tactical.phase, player.tactical.remaining = .Decision, 20
	tactical_begin_card_cast(&room, 1)
	testing.expect_value(t, play_card(&room, card.id, entity_target(PLAYER_ENTITY)).result, Card_Play_Result.Invalid_Phase)
	player.tactical.cast_remaining = 0
	hand, decisions := player.deck.hand_count, player.tactical.metrics.decisions
	play := play_card(&room, card.id, entity_target(PLAYER_ENTITY))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, play.destination, Card_Zone.Discard)
	testing.expect_value(t, player.tactical.cast_remaining, f32(0))
	testing.expect_value(t, player.tactical.remaining, f32(20))
	testing.expect_value(t, player.deck.hand_count, hand)
	testing.expect_value(t, room.tactical_pulse.deferred_draws, 0)
	testing.expect_value(t, player.tactical.metrics.decisions, decisions+1)
	testing.expect_value(t, player.tactical.shadow_remaining, TACTICAL_SHADOW_SECONDS)
	entered, drawn := 0, 0
	for event in room.recent_events.events[:room.recent_events.count] {
		if event.kind == .Card_Played { testing.expect(t, !event_is_critical(event)) }
		if event.kind == .Card_Drawn { drawn += 1 }
		if event.kind == .Shadow_Entered {
			entered += 1
			testing.expect_value(t, event.from_position, player.position)
			testing.expect_value(t, event.to_position, player.position)
			testing.expect_value(t, event.duration, i32(4))
		}
	}
	testing.expect_value(t, entered, 1)
	testing.expect_value(t, drawn, 1)
}

// The card never claims the tick (tactical_card_claims_beat, used by the
// command layer), and even a critical version is the same four seconds.
@(test)
test_shadow_card_leaves_the_tick_and_gains_nothing_from_a_critical :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := shadow_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	card := rework_hand_card(t, &room, .Shadow_Step)
	testing.expect(t, !tactical_card_claims_beat(&room, card.id))
	testing.expect(t, tactical_card_claims_beat(&room, player.deck.hand[1].id))
	player.tactical.critical_next = true
	testing.expect_value(t, play_card(&room, card.id, entity_target(PLAYER_ENTITY)).result, Card_Play_Result.Played)
	testing.expect_value(t, player.tactical.shadow_duration, TACTICAL_SHADOW_SECONDS)
	testing.expect_value(t, player.tactical.shadow_remaining, TACTICAL_SHADOW_SECONDS)
}

// Rewards, wares and the armoury share one pool containing Movimento Ombra.
@(test)
test_shadow_card_is_offered_by_rewards_shops_and_armory :: proc(t: ^testing.T) {
	definition, _ := card_definition_by_id(.Shadow_Step)
	node := Run_Node{kind = .Shop, depth = 9}
	testing.expect(t, card_offer_weight(definition, &node) > 0)
	profile := M8_Profile{ring_wins = 3}
	// Spark is temporary-only and the Scopa pair is never offered.
	all: [int(Card_Id.Count)-3]Card_Id
	random := u64(1)
	testing.expect(t, generate_weighted_card_choices(&random, &node, all[:], &profile))
	offered := false
	for id in all { offered = offered || id == .Shadow_Step }
	testing.expect(t, offered)
	price, priced := shop_card_price(definition, 9)
	testing.expect(t, priced)
	testing.expect_value(t, price, i32(8+9/3))
	// Shop sampling includes the card at its Rare price.
	run, shop_node := create_shop_test_source(t, 0x5AD0)
	defer destroy_run(&run)
	source, source_found := node_at(&run, shop_node)
	testing.expect(t, source_found)
	if !source_found { return }
	wares := 0
	for seed in u64(1)..=300 {
		state := seed
		shop, built := build_shop_state_for_node(&run, source, &state)
		testing.expect(t, built)
		for offer in shop.offers[:shop.offer_count] { if offer.definition_id == .Shadow_Step { wares += 1 } }
	}
	testing.expect(t, wares > 0)

	// Room rewards can offer the same card.
	rewarded := false
	for seed in u64(0)..<u64(4000) {
		tactical_run, tactical_ok := create_run(REWARD_TEST_PLAYER_STATS, REWARD_TEST_RUN_CONFIG, seed)
		if !tactical_ok { continue }
		testing.expect_value(t, finish_room(&tactical_run, .Complete), Run_Transition.Reward)
		found := false
		for id in available_card_rewards(&tactical_run) { found = found || id == .Shadow_Step }
		destroy_run(&tactical_run)
		if !found { continue }
		rewarded = true
		break
	}
	testing.expect(t, rewarded)
}
