package game

import "core:testing"
import grid "../grid"
import level "../level"

// The player's charges (player_charges.odin): RIFLESSO, FRECCE, DESTINO and
// LAMA, the cards that load them and what spends them.

charges_test_event :: proc(log: ^Event_Log, kind: Game_Event_Kind, source, target: Entity_Ref) -> (Game_Event, bool) {
	for event in log.events[:log.count] {
		if event.kind == kind && event.source == source && event.target == target { return event, true }
	}
	return {}, false
}

charges_test_count :: proc(log: ^Event_Log, kind: Game_Event_Kind) -> (count: int) {
	for event in log.events[:log.count] { if event.kind == kind { count += 1 } }
	return
}

charges_test_index :: proc(log: ^Event_Log, kind: Game_Event_Kind) -> int {
	for event, index in log.events[:log.count] { if event.kind == kind { return index } }
	return -1
}

// A foe of 40 health right north of the player (4, 4).
charges_test_bump_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, archetype: Enemy_Archetype = .Chaser) -> Room {
	spawns := [?]Enemy_Spawn{{position = {4, 3}, health = 40, attack = 1, archetype = archetype}}
	return create_enemy_rework_room(t, data, player, spawns[:])
}

// The Dado del Destino loaded on a die of `sides` that rolls `face` next.
charges_test_load_fate :: proc(t: ^testing.T, room: ^Room, face, sides: i32) {
	_, _ = apply_status(room, PLAYER_ENTITY, .Fate, FATE_DICE_CHARGES, 0)
	room.player.tactical.fate_sides = sides
	room.player.dice = pattern_test_dice_for_faces(t, {face, 0, 0}, 1, sides)
}

@(test)
test_charges_stack_on_the_player_alone :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {7, 1}, health = 20, attack = 1}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	foe := enemy_entity(room.enemies[0].id)
	for kind in ([4]Status_Kind{.Deflect, .Arrows, .Fate, .Venom_Blade}) {
		testing.expect(t, status_kind_stacks(kind) && status_kind_is_player_charge(kind))
		applied, _ := apply_status(&room, foe, kind, 1, 0)
		testing.expect(t, !applied)
		testing.expect(t, !effect_is_valid(&room, apply_status_effect(foe, kind, 1, 0)))
	}
	for kind in ([8]Status_Kind{.Poison, .Shield, .Thorns, .Afterimage, .Stagger, .Survey, .Burn, .Slow}) {
		testing.expect(t, !status_kind_is_player_charge(kind))
	}
	// Arrows add up; Destino loads back to its three, never above.
	_, _ = apply_status(&room, PLAYER_ENTITY, .Arrows, 3, 0)
	_, _ = apply_status(&room, PLAYER_ENTITY, .Arrows, 4, 0)
	testing.expect_value(t, player_charges(&room, .Arrows), i32(7))
	_, _ = apply_status(&room, PLAYER_ENTITY, .Fate, FATE_DICE_CHARGES, 0)
	testing.expect(t, spend_player_charge(&room, .Fate, &room.recent_events))
	testing.expect(t, spend_player_charge(&room, .Fate, &room.recent_events))
	testing.expect_value(t, player_charges(&room, .Fate), i32(1))
	_, _ = apply_status(&room, PLAYER_ENTITY, .Fate, FATE_DICE_CHARGES, 0)
	_, _ = apply_status(&room, PLAYER_ENTITY, .Fate, FATE_DICE_CHARGES, 0)
	testing.expect_value(t, player_charges(&room, .Fate), FATE_DICE_CHARGES)
	// The last charge spent ends the status, with its event; then there is none.
	_, _ = apply_status(&room, PLAYER_ENTITY, .Deflect, 1, 0)
	clear_event_log(&room.recent_events)
	testing.expect(t, spend_player_charge(&room, .Deflect, &room.recent_events))
	testing.expect_value(t, player_charges(&room, .Deflect), i32(0))
	expired, found := charges_test_event(&room.recent_events, .Status_Expired, SYSTEM_ENTITY, PLAYER_ENTITY)
	testing.expect(t, found && expired.status == .Deflect)
	testing.expect(t, !spend_player_charge(&room, .Deflect, &room.recent_events))
	// Every kind the player can carry at once: none refused for want of room.
	clear_statuses(&room.player.statuses)
	for kind in Status_Kind {
		if kind == .Slow { continue }
		applied, _ := apply_status(&room, PLAYER_ENTITY, kind, 1, 0 if status_kind_stacks(kind) else 1)
		testing.expectf(t, applied, "%v", kind)
	}
	testing.expect_value(t, room.player.statuses.count, len(Status_Kind)-1)
	// A critical play adds a charge, but Destino stays at its three.
	action := make_action(.Card, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
	_ = add_effect(&action, apply_status_effect(PLAYER_ENTITY, .Fate, FATE_DICE_CHARGES, 0))
	_ = add_effect(&action, apply_status_effect(PLAYER_ENTITY, .Deflect, 1, 0))
	room.player.tactical.critical_card = true
	tactical_critical_scale(&room, &action)
	room.player.tactical.critical_card = false
	testing.expect_value(t, action.effects[0].amount, FATE_DICE_CHARGES)
	testing.expect_value(t, action.effects[1].amount, i32(2))
	testing.expect_value(t, action.effects[1].duration, i32(0))
}

// Each loads one charge on the player; all four are tactical only, take a
// second of the window and keep the spec's energy and rarity. Deflect has no
// upgrade, Feretro gains an arrow a level, the two dice cards climb the die.
@(test)
test_charge_cards_are_tactical_self_cards_with_their_rules :: proc(t: ^testing.T) {
	ids := [4]Card_Id{.Deflect, .Coffin, .Fate_Dice, .Venom_Blade}
	kinds := [4]Status_Kind{.Deflect, .Arrows, .Fate, .Venom_Blade}
	energy := [4]i32{1, 2, 2, 1}
	rarities := [4]Card_Rarity{.Uncommon, .Uncommon, .Rare, .Common}
	names := [4]string{"Deflect", "Feretro", "Dado del Destino", "Lama Velenosa"}
	for id, index in ids {
		for tactical in ([2]bool{false, true}) {
			definition, found := card_definition_by_id(id, tactical)
			testing.expect(t, found && validate_card_definition(&definition))
			testing.expect_value(t, definition.targeting.rule, Target_Rule.Self)
			testing.expect_value(t, definition.cost, energy[index])
			testing.expect_value(t, definition.rarity, rarities[index])
			testing.expect_value(t, definition.name, names[index])
			testing.expect_value(t, definition.effect_count, 1)
			testing.expect_value(t, definition.effects[0].kind, Effect_Kind.Apply_Status)
			testing.expect_value(t, definition.effects[0].target, Card_Target_Selector.Player)
			testing.expect_value(t, definition.effects[0].status, kinds[index])
			testing.expect(t, !card_requires_spatial_target(definition))
		}
		testing.expect(t, card_requires_tactical(id) && card_loads_player_charge(id))
		testing.expect_value(t, tactical_card_time_cost(id), f32(1))
		definition, _ := card_definition_by_id(id, true)
		node := Run_Node{kind = .Combat, depth = 2}
		testing.expect(t, card_offer_weight(definition, &node) > 0)
		testing.expect_value(t, card_offer_weight(definition, &node, nil, false), u64(0))
	}
	testing.expect(t, !card_can_upgrade({id = 1, definition_id = .Deflect, lifetime = .Permanent}))
	testing.expect(t, card_can_upgrade({id = 1, definition_id = .Coffin, lifetime = .Permanent}))
	coffin, _ := card_definition_by_id(.Coffin, true)
	for upgrade in i32(0)..=3 {
		effect, made := instantiate_card_effect(coffin.effects[0], PLAYER_ENTITY, {id = 1, definition_id = .Coffin, upgrade_level = upgrade})
		testing.expect(t, made && effect.amount == 3+upgrade)
	}
	for id in ([2]Card_Id{.Fate_Dice, .Venom_Blade}) {
		testing.expect_value(t, card_dice_count(id), 1)
		testing.expect_value(t, card_max_upgrade_level(id), MAX_DICE_UPGRADE_LEVEL)
		testing.expect_value(t, card_die_sides(id, 0), i32(4))
		testing.expect_value(t, card_die_sides(id, MAX_DICE_UPGRADE_LEVEL), i32(20))
	}
	// A classic room refuses them before any payment.
	data := create_test_level(t)
	defer level.destroy(&data)
	player := create_test_player(t)
	enemies := [?]Enemy_Spawn{{position = {5, 3}, health = 8, attack = 1}}
	room, ok := create_room(&data, &player, {enemies = enemies[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	for id in ids {
		card := rework_hand_card(t, &room, id)
		deck := player.deck
		play := play_card(&room, card.id, entity_target(PLAYER_ENTITY))
		testing.expect_value(t, play.result, Card_Play_Result.Compile_Failed)
		testing.expect_value(t, play.compile_error, Card_Compile_Error.Invalid_Phase)
		testing.expect(t, player.deck == deck)
	}
	// No arrow flies in classic combat, even with arrows.
	_, _ = apply_status(&room, PLAYER_ENTITY, .Arrows, 3, 0)
	testing.expect_value(t, shoot_player_arrow(&room, enemy_entity(room.enemies[0].id)), Action_Result.Invalid_Phase)
}

// RIFLESSO on an archer's shot, a brute's cleave and a brute's charge: the
// player takes nothing and is not pushed, the attacker takes what he would
// have taken, the charge is spent and no defence is offered.
@(test)
test_deflect_returns_each_kind_of_blow_to_its_attacker :: proc(t: ^testing.T) {
	// 0: an archer's shot, 1: a brute's cleave, 2: a brute's charge.
	for case_index in 0..<3 {
		data: level.Level
		player: Player
		archetype := Enemy_Archetype.Archer if case_index == 0 else .Brute
		at := grid.Position{5, 4} if case_index == 1 else grid.Position{7, 4}
		spawns := [?]Enemy_Spawn{{position = at, health = 30, attack = 3, archetype = archetype}}
		room := create_enemy_rework_room(t, &data, &player, spawns[:])
		foe := enemy_entity(room.enemies[0].id)
		player.stats.defense = 1
		_, _ = apply_status(&room, PLAYER_ENTITY, .Deflect, 1, 0)
		if case_index == 0 {
			// The archer takes its aim first.
			aim: Pulse_Report
			resolve_enemy_intents(&room, &aim, foe.id)
			plan_enemy_intents(&room)
		}
		index, _ := enemy_index_by_id(&room, foe.id)
		expected := player_blow_damage(&room, room.enemies[index].intent.damage)
		testing.expectf(t, room.enemies[index].intent.kind == (.Charge if case_index == 2 else .Attack), "case %d: %v", case_index, room.enemies[index].intent.kind)
		testing.expect(t, !offer_defense_qte(&room, &room.enemies[index]))
		pulse: Pulse_Report
		resolve_enemy_intents(&room, &pulse, foe.id)
		testing.expect_value(t, player.health, i32(100))
		testing.expect_value(t, player.position, grid.Position{4, 4})
		testing.expect_value(t, player_charges(&room, .Deflect), i32(0))
		deflected, found := charges_test_event(&pulse.events, .Attack_Deflected, foe, PLAYER_ENTITY)
		testing.expectf(t, found && event_is_attack(deflected) && event_is_ranged_attack(deflected) == (case_index == 0), "case %d", case_index)
		testing.expect_value(t, deflected.to_position, grid.Position{4, 4})
		testing.expect_value(t, deflected.amount, expected)
		back, hit := charges_test_event(&pulse.events, .Damaged, PLAYER_ENTITY, foe)
		testing.expectf(t, hit && event_is_attack(back) && event_is_reflected(back) && event_is_ranged_attack(back) == (case_index == 0), "case %d", case_index)
		testing.expect(t, !event_is_reflected(deflected))
		testing.expect_value(t, back.amount, expected)
		testing.expect_value(t, back.from_position, grid.Position{4, 4})
		testing.expect_value(t, back.to_position, deflected.from_position)
		_, wounded := charges_test_event(&pulse.events, .Damaged, foe, PLAYER_ENTITY)
		testing.expect(t, !wounded)
		if after, alive := enemy_index_by_id(&room, foe.id); alive {
			testing.expect_value(t, room.enemies[after].health, 30-expected)
			testing.expect_value(t, back.to_position, room.enemies[after].position)
		}
		_, worn := charges_test_event(&pulse.events, .Status_Expired, SYSTEM_ENTITY, PLAYER_ENTITY)
		testing.expect(t, worn)
		// The deflected blow comes first, its answer after.
		testing.expect(t, charges_test_index(&pulse.events, .Attack_Deflected) < charges_test_index(&pulse.events, .Damaged))
		destroy_room(&room)
		level.destroy(&data)
	}
}

// Deflect takes the defence prompt's place and leaves the Shield whole; a
// trap or a bite of poison is no blow: it hurts, and the charge stays.
@(test)
test_deflect_takes_the_defence_prompts_place_and_leaves_the_guard_whole :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {5, 4}, health = 30, attack = 3, archetype = .Brute}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	_, _ = apply_status(&room, PLAYER_ENTITY, .Shield, 2, 2)
	testing.expect(t, offer_defense_qte(&room, &room.enemies[0]))
	room.qte = {}
	_, _ = apply_status(&room, PLAYER_ENTITY, .Deflect, 2, 0)
	testing.expect(t, !offer_defense_qte(&room, &room.enemies[0]))
	pulse: Pulse_Report
	resolve_enemy_intents(&room, &pulse, room.enemies[0].id)
	shield, shielded := status_for_entity(&room, PLAYER_ENTITY, .Shield)
	testing.expect(t, shielded && shield.potency == 2)
	testing.expect_value(t, player_charges(&room, .Deflect), i32(1))
	testing.expect_value(t, player.health, i32(100))
	append(&room.traps, Trap{id = 99, position = room.player.position, damage = 3, armed = true})
	before := player.health
	resolution := resolve_trap_for_entity(&room, PLAYER_ENTITY)
	testing.expect(t, resolution.triggered)
	testing.expect(t, player.health < before)
	testing.expect_value(t, player_charges(&room, .Deflect), i32(1))
	_, _ = apply_status(&room, PLAYER_ENTITY, .Poison, 2, 0)
	bite: Pulse_Report
	before = player.health
	tick_poison_on_action(&room, PLAYER_ENTITY, &bite)
	testing.expect(t, player.health < before)
	testing.expect_value(t, player_charges(&room, .Deflect), i32(1))
}

// Sunk in his shadow nothing reaches the player: no charge is spent on a blow
// that cannot touch him. A blow sent back that kills the last foe ends the
// fight there.
@(test)
test_deflect_spends_nothing_in_the_shadow_and_can_end_the_fight :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {5, 4}, health = 2, attack = 3, archetype = .Brute}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	_, _ = apply_status(&room, PLAYER_ENTITY, .Deflect, 1, 0)
	intent := room.enemies[0].intent
	testing.expect(t, tactical_begin_shadow(&room, TACTICAL_SHADOW_SECONDS))
	pulse: Pulse_Report
	resolve_enemy_intents(&room, &pulse, room.enemies[0].id)
	testing.expect_value(t, player_charges(&room, .Deflect), i32(1))
	testing.expect_value(t, player.health, i32(100))
	_, deflected := charges_test_event(&pulse.events, .Attack_Deflected, enemy_entity(room.enemies[0].id), PLAYER_ENTITY)
	testing.expect(t, !deflected)
	// Out of the shadow the same blow goes back, and kills.
	tactical_reset_shadow(&room.player.tactical)
	room.player.tactical.phase = .Decision
	room.enemies[0].intent = intent
	room.enemies[0].position = intent.origin
	foe := enemy_entity(room.enemies[0].id)
	pulse = {}
	resolve_enemy_intents(&room, &pulse, foe.id)
	_, defeated := charges_test_event(&pulse.events, .Entity_Defeated, PLAYER_ENTITY, foe)
	testing.expect(t, defeated)
	testing.expect_value(t, len(room.enemies), 0)
	testing.expect_value(t, room.phase, Room_Phase.Loot)
	testing.expect_value(t, player.health, i32(100))
}

@(test)
test_coffin_arrows_fly_to_the_foes_in_the_line_of_fire :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {7, 4}, health = 20, attack = 1}, {position = {4, 1}, health = 20, attack = 1}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	near, far := enemy_entity(room.enemies[0].id), enemy_entity(room.enemies[1].id)
	append(&room.obstacles, Obstacle{position = {4, 2}})
	// The cover came after the plans: plan again around it.
	for &enemy in room.enemies { enemy.intent, enemy.tactical_cooldown = {}, 0 }
	plan_enemy_intents(&room)
	testing.expect_value(t, shoot_player_arrow(&room, near), Action_Result.Blocked)
	_, _ = apply_status(&room, PLAYER_ENTITY, .Arrows, 3, 0)
	testing.expect(t, !player_arrow_target_is_valid(&room, far))
	testing.expect(t, player_arrow_target_is_valid(&room, near))
	testing.expect(t, !player_arrow_target_is_valid(&room, PLAYER_ENTITY))
	testing.expect_value(t, shoot_player_arrow(&room, far), Action_Result.Blocked)
	testing.expect_value(t, player_charges(&room, .Arrows), i32(3))
	dice := room.player.dice
	window := room.player.tactical.remaining
	at, _ := entity_position(&room, near)
	room.player.tactical.facing = .North
	testing.expect_value(t, shoot_player_arrow(&room, near), Action_Result.Attacked)
	testing.expect(t, room.player.dice != dice)
	testing.expect_value(t, player_charges(&room, .Arrows), i32(2))
	testing.expect_value(t, room.player.tactical.remaining, window-TACTICAL_ARROW_SECONDS)
	testing.expect_value(t, room.player.tactical.facing, Move_Direction.East)
	hit, found := charges_test_event(&room.recent_events, .Damaged, PLAYER_ENTITY, near)
	testing.expect(t, found && event_is_ranged_attack(hit) && !event_is_reflected(hit) && hit.amount == COFFIN_ARROW_DAMAGE)
	testing.expect_value(t, hit.from_position, grid.Position{4, 4})
	testing.expect_value(t, hit.to_position, at)
	applied, marked := charges_test_event(&room.recent_events, .Status_Applied, PLAYER_ENTITY, near)
	testing.expect(t, marked)
	testing.expect(t, (applied.status == .Poison && applied.amount == 2) || (applied.status == .Burn && applied.amount == 1) ||
		(applied.status == .Slow && applied.amount == 1))
	drain_tactical_test_pulse(t, &room)
	emptied := false
	for _ in 0..<2 {
		if !player_arrow_target_is_valid(&room, near) { break }
		testing.expect_value(t, shoot_player_arrow(&room, near), Action_Result.Attacked)
		// The last arrow ends the status, with its event.
		_, emptied = charges_test_event(&room.recent_events, .Status_Expired, SYSTEM_ENTITY, PLAYER_ENTITY)
		drain_tactical_test_pulse(t, &room)
	}
	testing.expect_value(t, player_charges(&room, .Arrows), i32(0))
	testing.expect(t, emptied)
	testing.expect_value(t, shoot_player_arrow(&room, near), Action_Result.Blocked)
	// The card: three arrows, plays add up; on the tick, one more.
	card := rework_hand_card(t, &room, .Coffin)
	room.player.deck.energy = room.player.deck.rules.max_energy
	play := play_card(&room, card.id, entity_target(PLAYER_ENTITY))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, player_charges(&room, .Arrows), i32(3))
}

// An arrow is an action of the open window: none in recovery, stunned or in
// the shadow, and none at a foe out of sight.
@(test)
test_coffin_arrows_need_an_open_window_and_sight :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {7, 5}, health = 20, attack = 1}, {position = {11, 5}, health = 20, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]}, vision = 7)
	defer level.destroy(&data)
	defer destroy_room(&room)
	near, hidden := enemy_entity(room.enemies[0].id), enemy_entity(room.enemies[1].id)
	_, _ = apply_status(&room, PLAYER_ENTITY, .Arrows, 5, 0)
	testing.expect(t, player_arrow_target_is_valid(&room, near))
	testing.expect(t, !tactical_cell_visible(&room, {11, 5}) && !player_arrow_target_is_valid(&room, hidden))
	testing.expect_value(t, shoot_player_arrow(&room, hidden), Action_Result.Blocked)
	for phase in ([2]Tactical_Phase{.Recovery, .Stunned}) {
		room.player.tactical.phase = phase
		testing.expect_value(t, shoot_player_arrow(&room, near), Action_Result.Invalid_Phase)
	}
	room.player.tactical.phase = .Decision
	testing.expect(t, tactical_begin_shadow(&room, TACTICAL_SHADOW_SECONDS))
	testing.expect_value(t, shoot_player_arrow(&room, near), Action_Result.Invalid_Phase)
	testing.expect_value(t, player_charges(&room, .Arrows), i32(5))
}

@(test)
test_fate_dice_rolls_its_die_at_each_loaded_bump :: proc(t: ^testing.T) {
	for face in i32(1)..=8 {
		data: level.Level
		player: Player
		room := charges_test_bump_room(t, &data, &player)
		foe := enemy_entity(room.enemies[0].id)
		charges_test_load_fate(t, &room, face, 8)
		player.health = 50
		result := try_move_player(&room, .North)
		testing.expectf(t, result == (.Combat_Ended if face >= 6 else .Attacked), "face %d: %v", face, result)
		rolled, found := charges_test_event(&room.recent_events, .Fate_Rolled, PLAYER_ENTITY, foe)
		testing.expectf(t, found && rolled.dice_roll.total == face && rolled.dice_roll.sides == 8, "face %d", face)
		testing.expect_value(t, Fate_Outcome(rolled.duration), fate_outcome(face, false))
		testing.expect_value(t, player_charges(&room, .Fate), FATE_DICE_CHARGES-1)
		hit, _ := charges_test_event(&room.recent_events, .Damaged, PLAYER_ENTITY, foe)
		switch {
		case face <= 3:
			applied, statused := charges_test_event(&room.recent_events, .Status_Applied, PLAYER_ENTITY, foe)
			kinds := [3]Status_Kind{.Poison, .Burn, .Slow}
			testing.expectf(t, statused && applied.status == kinds[face-1] && applied.amount == face, "face %d", face)
			testing.expect_value(t, rolled.amount, face)
		case face == 4:
			testing.expect_value(t, player.health, i32(50)+hit.amount)
			testing.expect_value(t, rolled.amount, hit.amount)
		case face == 5:
			testing.expect(t, event_is_critical(hit) && hit.amount == critical_bump_damage(player_basic_attack_damage(&player)))
		case:
			_, defeated := charges_test_event(&room.recent_events, .Entity_Defeated, PLAYER_ENTITY, foe)
			testing.expect(t, defeated)
		}
		// The die shows right after the blow's own events.
		for event, index in room.recent_events.events[:room.recent_events.count] {
			if event.kind != .Fate_Rolled { continue }
			testing.expect_value(t, room.recent_events.events[index-1].kind, Game_Event_Kind.Damaged)
		}
		destroy_room(&room)
		level.destroy(&data)
	}
	// The boss and the miniboss take a critical, never a kill.
	for archetype in ([2]Enemy_Archetype{.Demolitionist, .Custodian}) {
		data: level.Level
		player: Player
		room := charges_test_bump_room(t, &data, &player, archetype)
		charges_test_load_fate(t, &room, 8, 8)
		testing.expect_value(t, try_move_player(&room, .North), Action_Result.Attacked)
		testing.expect_value(t, room.enemies[0].health, i32(40)-critical_bump_damage(player_basic_attack_damage(&player)))
		rolled, _ := charges_test_event(&room.recent_events, .Fate_Rolled, PLAYER_ENTITY, enemy_entity(room.enemies[0].id))
		testing.expect_value(t, Fate_Outcome(rolled.duration), Fate_Outcome.Critical)
		destroy_room(&room)
		level.destroy(&data)
	}
	testing.expect(t, enemy_is_boss(.Demolitionist) && enemy_is_boss(.Custodian) && !enemy_is_boss(.Brute))
}

// A lethal face fells a guarded foe; a face that leaves a status shows even
// on a bump its Shield takes whole; a stolen life is what the player gets
// back, nothing at full health.
@(test)
test_fate_dice_faces_through_guards_and_full_health :: proc(t: ^testing.T) {
	{
		data: level.Level
		player: Player
		room := charges_test_bump_room(t, &data, &player)
		defer level.destroy(&data)
		defer destroy_room(&room)
		foe := enemy_entity(room.enemies[0].id)
		_, _ = apply_status(&room, foe, .Shield, 5, 3)
		charges_test_load_fate(t, &room, 7, 8)
		testing.expect_value(t, try_move_player(&room, .North), Action_Result.Combat_Ended)
		_, defeated := charges_test_event(&room.recent_events, .Entity_Defeated, PLAYER_ENTITY, foe)
		testing.expect(t, defeated)
		at := charges_test_index(&room.recent_events, .Fate_Rolled)
		testing.expect(t, at > charges_test_index(&room.recent_events, .Damaged) && at < charges_test_index(&room.recent_events, .Entity_Defeated))
	}
	{
		data: level.Level
		player: Player
		room := charges_test_bump_room(t, &data, &player)
		defer level.destroy(&data)
		defer destroy_room(&room)
		foe := enemy_entity(room.enemies[0].id)
		_, _ = apply_status(&room, foe, .Shield, 10, 3)
		charges_test_load_fate(t, &room, 2, 4)
		testing.expect_value(t, try_move_player(&room, .North), Action_Result.Attacked)
		testing.expect_value(t, room.enemies[0].health, i32(40))
		absorbed := charges_test_index(&room.recent_events, .Damage_Absorbed)
		at := charges_test_index(&room.recent_events, .Fate_Rolled)
		applied := charges_test_index(&room.recent_events, .Status_Applied)
		testing.expect(t, absorbed >= 0 && at == absorbed+1 && applied > at)
		burn, burning := status_for_entity(&room, foe, .Burn)
		testing.expect(t, burning && burn.potency == 2)
	}
	{
		data: level.Level
		player: Player
		room := charges_test_bump_room(t, &data, &player)
		defer level.destroy(&data)
		defer destroy_room(&room)
		foe := enemy_entity(room.enemies[0].id)
		charges_test_load_fate(t, &room, 4, 4)
		testing.expect_value(t, try_move_player(&room, .North), Action_Result.Attacked)
		rolled, _ := charges_test_event(&room.recent_events, .Fate_Rolled, PLAYER_ENTITY, foe)
		testing.expect_value(t, Fate_Outcome(rolled.duration), Fate_Outcome.Lifesteal)
		testing.expect_value(t, rolled.amount, i32(0))
		testing.expect_value(t, charges_test_count(&room.recent_events, .Healed), 0)
		testing.expect_value(t, player.health, player.stats.max_health)
	}
}

// Lama and Destino load the same bump: its Veleno and its face's, both; and
// without either the bump is the plain one.
@(test)
test_venom_blade_and_fate_dice_load_the_same_bump :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := charges_test_bump_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	foe := enemy_entity(room.enemies[0].id)
	_, _ = apply_status(&room, PLAYER_ENTITY, .Venom_Blade, 1, 0)
	charges_test_load_fate(t, &room, 2, 4)
	testing.expect_value(t, try_move_player(&room, .North), Action_Result.Attacked)
	poison, poisoned := status_for_entity(&room, foe, .Poison)
	burn, burning := status_for_entity(&room, foe, .Burn)
	testing.expect(t, poisoned && poison.potency == VENOM_BLADE_POISON && burning && burn.potency == 2)
	testing.expect_value(t, player_charges(&room, .Venom_Blade), i32(0))
	testing.expect_value(t, player_charges(&room, .Fate), FATE_DICE_CHARGES-1)
	_, worn := charges_test_event(&room.recent_events, .Status_Expired, SYSTEM_ENTITY, PLAYER_ENTITY)
	testing.expect(t, worn)
	testing.expect_value(t, room.enemies[0].health, i32(40)-player_basic_attack_damage(&player))
}

@(test)
test_fate_dice_card_loads_three_bumps_with_its_level_die :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := charges_test_bump_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	card := rework_hand_card(t, &room, .Fate_Dice)
	room.player.deck.hand[0].upgrade_level = 2
	for &owned in room.player.deck.owned[:room.player.deck.owned_count] { if owned.id == card.id { owned.upgrade_level = 2 } }
	// Played on the tick it leaves the beat to the next action (it has no
	// stronger version).
	testing.expect(t, !tactical_card_claims_beat(&room, card.id))
	room.player.deck.energy = room.player.deck.rules.max_energy
	dice := room.player.dice
	play := play_card(&room, card.id, entity_target(PLAYER_ENTITY))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, player_charges(&room, .Fate), FATE_DICE_CHARGES)
	testing.expect_value(t, room.player.tactical.fate_sides, i32(8))
	testing.expect_value(t, player_fate_sides(&room), i32(8))
	testing.expect_value(t, charges_test_count(&room.recent_events, .Dice_Rolled), 0)
	testing.expect(t, room.player.dice == dice)
	// No card played yet: a d4.
	room.player.tactical.fate_sides = 0
	testing.expect_value(t, player_fate_sides(&room), i32(4))
	// A new room forgets the die with the charges.
	begin_tactical_room(&room)
	testing.expect_value(t, room.player.tactical.fate_sides, i32(0))
}

@(test)
test_venom_blade_rolls_the_bumps_it_poisons :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {4, 3}, health = 60, attack = 1}, {position = {5, 3}, health = 60, attack = 1}}
	room := create_enemy_rework_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	card := rework_hand_card(t, &room, .Venom_Blade)
	room.player.dice = pattern_test_dice_for_faces(t, {3, 0, 0}, 1, 4)
	play := play_card(&room, card.id, entity_target(PLAYER_ENTITY))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, player_charges(&room, .Venom_Blade), i32(3))
	rolled_at, applied_at := -1, -1
	for event, index in room.recent_events.events[:room.recent_events.count] {
		if event.kind == .Dice_Rolled && rolled_at < 0 {
			rolled_at = index
			testing.expect_value(t, event.dice_roll.total, i32(3))
			testing.expect_value(t, event.dice_roll.sides, i32(4))
			testing.expect_value(t, event.card_definition, Card_Id.Venom_Blade)
		}
		if event.kind == .Status_Applied && event.status == .Venom_Blade { applied_at = index }
	}
	testing.expect(t, rolled_at >= 0 && applied_at > rolled_at)
	if tactical_is_casting(&room) { tactical_tick(&room, room.player.tactical.cast_remaining, true, false) }
	drain_tactical_test_pulse(t, &room)
	north := enemy_entity(room.enemies[0].id)
	for bump in 0..<4 {
		testing.expect_value(t, try_move_player(&room, .North), Action_Result.Attacked)
		applied, poisoned := charges_test_event(&room.recent_events, .Status_Applied, PLAYER_ENTITY, north)
		testing.expectf(t, poisoned == (bump < 3), "bump %d", bump)
		if poisoned { testing.expect(t, applied.status == .Poison) }
		drain_tactical_test_pulse(t, &room)
	}
	testing.expect_value(t, player_charges(&room, .Venom_Blade), i32(0))
	// A diagonal bump on the tick strikes loaded too.
	_, _ = apply_status(&room, PLAYER_ENTITY, .Venom_Blade, 1, 0)
	room.enemies[1].position = {5, 3}
	east := enemy_entity(room.enemies[1].id)
	testing.expect_value(t, try_move_player_diagonal(&room, {1, -1}), Action_Result.Attacked)
	applied, poisoned := charges_test_event(&room.recent_events, .Status_Applied, PLAYER_ENTITY, east)
	testing.expect(t, poisoned && applied.status == .Poison && applied.amount >= VENOM_BLADE_POISON)
	testing.expect_value(t, player_charges(&room, .Venom_Blade), i32(0))
}

// On the tick a charge card loads one more: a fourth arrow, a second Riflesso,
// Lama's roll and one; the Dado del Destino stays at its three.
@(test)
test_charge_cards_on_the_tick_load_one_more :: proc(t: ^testing.T) {
	ids := [4]Card_Id{.Coffin, .Deflect, .Venom_Blade, .Fate_Dice}
	kinds := [4]Status_Kind{.Arrows, .Deflect, .Venom_Blade, .Fate}
	expected := [4]i32{4, 2, 3, FATE_DICE_CHARGES}
	for id, index in ids {
		data: level.Level
		player: Player
		room := charges_test_bump_room(t, &data, &player)
		card := rework_hand_card(t, &room, id)
		room.player.dice = pattern_test_dice_for_faces(t, {2, 0, 0}, 1, 4)
		room.player.deck.energy = room.player.deck.rules.max_energy
		room.player.tactical.critical_next = true
		play := play_card(&room, card.id, entity_target(PLAYER_ENTITY))
		testing.expect_value(t, play.result, Card_Play_Result.Played)
		testing.expectf(t, player_charges(&room, kinds[index]) == expected[index], "%v: %d", id, player_charges(&room, kinds[index]))
		destroy_room(&room)
		level.destroy(&data)
	}
}
