package game

import "core:testing"
import grid "../grid"
import level "../level"

status_stack_test_events :: proc(log: ^Event_Log, kind: Game_Event_Kind, cause: Status_Kind) -> (count: int) {
	for event in log.events[:log.count] {
		if event.kind == kind && event.has_status_cause && event.status_cause == cause { count += 1 }
	}
	return
}

// Bruciatura: at each window that runs out (the window number changes) its
// stacks bite, on the Timeout command itself; the world's beats never do and
// the stacks never wear.
@(test)
test_burn_bites_at_each_new_tactical_window_and_never_wears :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {1, 1}, health = 50, attack = 1}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	enemy := enemy_entity(room.enemies[0].id)
	_, _ = apply_status(&room, PLAYER_ENTITY, .Burn, 2, 0)
	_, _ = apply_status(&room, enemy, .Burn, 3, 0)
	advance_enemy_rework_seconds(t, &room, 3)
	testing.expect_value(t, player.health, i32(100))
	testing.expect_value(t, room.enemies[0].health, i32(50))
	for window in 1..=2 {
		player.tactical.remaining = 0
		testing.expect(t, tactical_expire_window(&room))
		testing.expect_value(t, player.health, i32(100-2*window))
		testing.expect_value(t, room.enemies[0].health, i32(50-3*window))
		testing.expect_value(t, status_stack_test_events(&room.recent_events, .Damaged, .Burn), 2)
		burn, found := status_for_entity(&room, enemy, .Burn)
		testing.expect(t, found && burn.potency == 3)
		testing.expect_value(t, player.tactical.cycle, window)
		// Through the recovery into the next window: no further bite.
		for _ in 0..<4 { testing.expect(t, !tactical_tick(&room, 0.25, true, false)); drain_tactical_test_pulse(t, &room, false) }
		testing.expect_value(t, player.tactical.phase, Tactical_Phase.Decision)
		testing.expect_value(t, player.health, i32(100-2*window))
	}
}

// Classic combat has no windows: Bruciatura bites at every pulse, before a
// Shield about to run out stops guarding.
@(test)
test_burn_bites_every_classic_pulse :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 10, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	enemy := enemy_entity(room.enemies[0].id)
	_, _ = apply_status(&room, enemy, .Burn, 2, 0)
	_, _ = apply_status(&room, enemy, .Shield, 1, 1)
	for pulse in 1..=3 {
		room.enemies[0].intent = make_wait_intent(&room, room.enemies[0].position)
		report := advance_combat_pulse(&room)
		// The first bite spends the last pulse of the shield's single point.
		testing.expect_value(t, room.enemies[0].health, i32(10-2*pulse+1))
		testing.expect_value(t, status_stack_test_events(&report.events, .Damage_Absorbed, .Burn), 1 if pulse == 1 else 0)
	}
	burn, found := status_for_entity(&room, enemy, .Burn)
	testing.expect(t, found && burn.potency == 2)
}

// A lethal burn at the window's end closes the fight like any blow: loot,
// deck and the tactical state are settled on the same command.
@(test)
test_lethal_burn_at_the_window_end_finishes_the_fight :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {1, 1}, health = 2, attack = 1}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	_, _ = apply_status(&room, enemy_entity(room.enemies[0].id), .Burn, 2, 0)
	player.tactical.remaining = 0
	testing.expect(t, tactical_expire_window(&room))
	testing.expect_value(t, room.phase, Room_Phase.Loot)
	testing.expect_value(t, len(room.enemies), 0)
	testing.expect(t, !player.deck.combat_active)
	testing.expect_value(t, player.tactical.phase, Tactical_Phase.Decision)
	testing.expect(t, !room.tactical_pulse.pending)
	defeated := 0
	for event in room.recent_events.events[:room.recent_events.count] { if event.kind == .Entity_Defeated { defeated += 1 } }
	testing.expect_value(t, defeated, 1)
}

// The player's own burn can end the run's fight the same way: defeat, the
// deck out of combat, no window left running.
@(test)
test_lethal_burn_on_the_player_at_the_window_end_is_a_defeat :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {1, 1}, health = 20, attack = 1}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	player.health = 2
	_, _ = apply_status(&room, PLAYER_ENTITY, .Burn, 2, 0)
	player.tactical.remaining = 0
	testing.expect(t, tactical_expire_window(&room))
	testing.expect_value(t, room.phase, Room_Phase.Defeat)
	testing.expect_value(t, player.health, i32(0))
	testing.expect(t, !player.deck.combat_active)
	testing.expect_value(t, player.tactical.phase, Tactical_Phase.Decision)
	testing.expect_value(t, room.enemies[0].health, i32(20))
}

// A bite is its stacks whatever the player's defense; only a Shield takes
// from it. A blow still meets the defense.
@(test)
test_status_bites_on_the_player_ignore_his_defense :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	player.stats.max_health, player.health = 50, 50
	testing.expect_value(t, player.stats.defense, i32(1))
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 10, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	pulse: Pulse_Report
	_, _ = apply_status(&room, PLAYER_ENTITY, .Burn, 2, 0)
	burn_status(&room, PLAYER_ENTITY, &pulse)
	testing.expect_value(t, player.health, i32(48))
	_, _ = apply_status(&room, PLAYER_ENTITY, .Poison, 3, 0)
	tick_poison_on_action(&room, PLAYER_ENTITY, &pulse)
	testing.expect_value(t, player.health, i32(45))
	_, _ = apply_status(&room, PLAYER_ENTITY, .Shield, 1, 2)
	burn_status(&room, PLAYER_ENTITY, &pulse)
	testing.expect_value(t, player.health, i32(44))
	testing.expect_value(t, status_stack_test_events(&pulse.events, .Damage_Absorbed, .Burn), 1)
	blow := make_action(.Trigger, SYSTEM_ENTITY, entity_target(PLAYER_ENTITY), .Entity)
	testing.expect(t, add_effect(&blow, damage_effect(PLAYER_ENTITY, 3)))
	testing.expect(t, resolve_action(&room, &blow).accepted)
	testing.expect_value(t, player.health, i32(42))
}

// Rallentamento: the next intent planned holds a second longer per stack,
// and once that action is carried out a stack wears. The intent already
// running when it lands keeps its time and spends nothing.
@(test)
test_slow_holds_each_planned_intent_by_its_stacks_then_wears :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {1, 1}, health = 50, attack = 1}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	enemy := enemy_entity(room.enemies[0].id)
	testing.expect_value(t, room.enemies[0].intent.kind, Enemy_Intent_Kind.Move)
	testing.expect_value(t, room.enemies[0].tactical_cooldown, f32(2))
	_, _ = apply_status(&room, enemy, .Slow, 2, 0)
	testing.expect_value(t, room.enemies[0].tactical_cooldown, f32(2))
	start := room.enemies[0].position
	advance_enemy_rework_seconds(t, &room, 2)
	testing.expect(t, room.enemies[0].position != start)
	slow, found := status_for_entity(&room, enemy, .Slow)
	testing.expect(t, found && slow.potency == 2)
	testing.expect_value(t, room.enemies[0].intent.slowed, i32(2))
	testing.expect_value(t, room.enemies[0].tactical_cooldown, f32(4))
	testing.expect_value(t, tactical_enemy_intent_seconds(&room.enemies[0]), f32(4))
	held := room.enemies[0].position
	advance_enemy_rework_seconds(t, &room, 3)
	testing.expect_value(t, room.enemies[0].position, held)
	advance_enemy_rework_seconds(t, &room, 1)
	testing.expect(t, room.enemies[0].position != held)
	slow, found = status_for_entity(&room, enemy, .Slow)
	testing.expect(t, found && slow.potency == 1)
	testing.expect_value(t, room.enemies[0].tactical_cooldown, f32(3))
	advance_enemy_rework_seconds(t, &room, 3)
	_, found = status_for_entity(&room, enemy, .Slow)
	testing.expect(t, !found)
	testing.expect_value(t, room.enemies[0].intent.slowed, i32(0))
	testing.expect_value(t, room.enemies[0].tactical_cooldown, f32(2))
}

// Classic combat has no seconds to hold: each of the enemy's actions wears a
// stack all the same, and its intents keep no slowed seconds.
@(test)
test_slow_wears_by_the_action_in_classic_combat :: proc(t: ^testing.T) {
	level_data := create_test_level(t)
	defer level.destroy(&level_data)
	player := create_test_player(t)
	enemy_spawns := [?]Enemy_Spawn{{position = {x = 5, y = 3}, health = 10, attack = 1}}
	room, ok := create_room(&level_data, &player, {enemies = enemy_spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	enemy := enemy_entity(room.enemies[0].id)
	_, _ = apply_status(&room, enemy, .Slow, 2, 0)
	for stacks in ([2]i32{1, 0}) {
		room.enemies[0].intent = make_wait_intent(&room, room.enemies[0].position)
		_ = advance_combat_pulse(&room)
		testing.expect_value(t, room.enemies[0].intent.slowed, i32(0))
		slow, found := status_for_entity(&room, enemy, .Slow)
		testing.expect_value(t, found, stacks > 0)
		if found { testing.expect_value(t, slow.potency, stacks) }
	}
	testing.expect_value(t, room.enemies[0].health, i32(10))
}

// Every committed action of the player bites (a step, a wait, a dodge, a
// card), but nothing in Movimento Ombra does: not its card, not the shadow's
// steps, not the rise.
@(test)
test_player_poison_bites_his_actions_but_not_movimento_ombra :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {7, 7}, health = 100, attack = 1}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	_, _ = apply_status(&room, PLAYER_ENTITY, .Poison, 6, 0)
	expect_poison :: proc(t: ^testing.T, room: ^Room, stacks: i32, health: i32) {
		poison, found := status_for_entity(room, PLAYER_ENTITY, .Poison)
		testing.expect(t, found && poison.potency == stacks)
		testing.expect_value(t, room.player.health, health)
	}
	testing.expect_value(t, try_move_player(&room, .North), Action_Result.Moved)
	expect_poison(t, &room, 5, 94)
	drain_tactical_test_pulse(t, &room)
	testing.expect(t, wait_player_turn(&room) != .Invalid_Phase)
	expect_poison(t, &room, 4, 89)
	drain_tactical_test_pulse(t, &room)
	shadow := rework_hand_card(t, &room, .Shadow_Step)
	testing.expect_value(t, play_card(&room, shadow.id, entity_target(PLAYER_ENTITY)).result, Card_Play_Result.Played)
	testing.expect(t, tactical_shadow_active(&room))
	expect_poison(t, &room, 4, 89)
	testing.expect_value(t, try_shadow_step(&room, .West), Action_Result.Moved)
	for _ in 0..<100 {
		if tactical_shadow_due(&room) { break }
		testing.expect(t, !tactical_tick(&room, 0.25, true, false))
	}
	testing.expect(t, tactical_end_shadow(&room))
	expect_poison(t, &room, 4, 89)
	testing.expect(t, try_dodge_player(&room, .South))
	expect_poison(t, &room, 3, 85)
}

// A dodge answered through the defence QTE is a dodge: the player's poison
// bites it as it bites the SHIFT one. A block only answers the blow.
@(test)
test_reactive_dodge_bites_poison_but_a_block_does_not :: proc(t: ^testing.T) {
	for dodge in ([2]bool{true, false}) {
		data: level.Level
		player: Player
		room := tactical_test_room(t, &data, &player, true)
		defer level.destroy(&data)
		defer destroy_room(&room)
		if !dodge { _, _ = apply_status(&room, PLAYER_ENTITY, .Shield, 1, 3) }
		testing.expect(t, wait_player_turn(&room) != .Invalid_Phase)
		_, _ = apply_status(&room, PLAYER_ENTITY, .Poison, 4, 0)
		health := player.health
		continue_tactical_pulse(&room)
		continue_tactical_pulse(&room)
		testing.expect_value(t, room.qte.kind, QTE_Kind.Defense)
		if dodge {
			testing.expect(t, select_defense(&room, .Dodge))
			testing.expect(t, qte_key(&room, .South))
			testing.expect_value(t, player.position, grid.Position{1, 2})
		} else {
			testing.expect(t, select_defense(&room, .Block))
			testing.expect(t, qte_key(&room, room.qte.keys[0]))
		}
		poison, poisoned := status_for_entity(&room, PLAYER_ENTITY, .Poison)
		testing.expect(t, poisoned && poison.potency == (3 if dodge else 4))
		testing.expect_value(t, player.health, health-4 if dodge else health)
		testing.expect_value(t, status_stack_test_events(&room.recent_events, .Damaged, .Poison), 1 if dodge else 0)
		drain_tactical_test_pulse(t, &room)
		testing.expect_value(t, player.tactical.metrics.qte_successes, u64(1))
	}
}

// A bite that kills on the reactive dodge is a defeat like any other: the
// world's pulse is settled on the same answer.
@(test)
test_lethal_poison_on_a_reactive_dodge_is_a_defeat :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := tactical_test_room(t, &data, &player, true)
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, wait_player_turn(&room) != .Invalid_Phase)
	player.health = 3
	_, _ = apply_status(&room, PLAYER_ENTITY, .Poison, 3, 0)
	continue_tactical_pulse(&room)
	continue_tactical_pulse(&room)
	testing.expect(t, select_defense(&room, .Dodge))
	testing.expect(t, qte_key(&room, .South))
	testing.expect_value(t, room.phase, Room_Phase.Defeat)
	testing.expect_value(t, player.health, i32(0))
	testing.expect(t, !room.tactical_pulse.pending)
	testing.expect(t, !player.deck.combat_active)
	testing.expect_value(t, room.enemies[0].health, i32(1000))
}

// Card templates: a stack status carries no duration and every other one
// needs its own; a reaction may apply stacks without one.
@(test)
test_status_templates_keep_stacks_without_a_duration :: proc(t: ^testing.T) {
	for id in Card_Id {
		if id == .Count { continue }
		for tactical in ([2]bool{false, true}) {
			definition, found := card_definition_by_id(id, tactical)
			testing.expect(t, found)
			for template in definition.effects[:definition.effect_count] {
				if template.kind != .Apply_Status { continue }
				if status_kind_stacks(template.status) {
					testing.expect_value(t, template.duration, i32(0))
				} else {
					testing.expect(t, template.duration > 0)
				}
			}
		}
	}
	needle, _ := card_definition_by_id(.Venom_Needle)
	testing.expect(t, validate_card_definition(&needle))
	needle.effects[1].duration = 2
	testing.expect(t, !validate_card_definition(&needle))
	needle.effects[1].duration, needle.effects[1].status = 0, .Burn
	testing.expect(t, validate_card_definition(&needle))
	needle.effects[1].status = .Shield
	testing.expect(t, !validate_card_definition(&needle))
}
