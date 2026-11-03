package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

// NIDO DI RAGNI (docs/piano-ia.md, Fase 9).

@(private = "file")
nest_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, foe: grid.Position = {x = 9, y = 5}) -> Room {
	spawns := [?]Enemy_Spawn{{position = foe, health = 50, attack = 1}}
	room := ground_test_room(t, data, player, {enemies = spawns[:]})
	player.tactical.config.windowless = true
	return room
}

// The foe stays where it is: `walls` set down after its first plan would break it.
@(private = "file")
nest_test_hold :: proc(room: ^Room) {
	foe := &room.enemies[0]
	foe.recovery_pulses = 999
	foe.intent = make_wait_intent(room, foe.position)
	foe.intent.kind = .Recover
}

// A nest set down by the rules on `cell`.
@(private = "file")
nest_test_place :: proc(t: ^testing.T, room: ^Room, cell: grid.Position, bite := SPIDER_BITE_DAMAGE) -> u32 {
	report: Action_Report
	testing.expect(t, place_spider_nest(room, cell, bite, SPIDER_NEST_SECONDS, &report))
	return room.objects[len(room.objects)-1].id
}

// `seconds` of the world, as the controller runs them.
@(private = "file")
nest_test_run :: proc(room: ^Room, seconds: f32) {
	dt := f32(1.0/30.0)
	for ran := f32(0); ran < seconds && room.phase == .Combat; ran += dt {
		tactical_tick(room, dt, true, false)
		for room.tactical_pulse.pending && room.qte.kind == .None { if !continue_tactical_pulse(room) { break } }
		if room.qte.kind != .None { resolve_qte(room, false) }
		for tactical_flights_due(room) { if !resolve_enemy_flights(room) { break } }
	}
}

@(test)
test_nest_is_an_uncommon_lab_card_of_two_energy :: proc(t: ^testing.T) {
	definition, found := card_definition_by_id(.Spider_Nest)
	testing.expect(t, found && validate_card_definition(&definition))
	testing.expect_value(t, definition.name, "Nido di ragni")
	testing.expect_value(t, definition.rarity, Card_Rarity.Uncommon)
	testing.expect_value(t, definition.cost, i32(2))
	testing.expect_value(t, definition.shop_base_price, i32(6))
	testing.expect_value(t, definition.reward_weight, u32(70))
	testing.expect(t, .Lab_Only in definition.traits)
	testing.expect_value(t, card_energy_cost(nil, .Spider_Nest), i32(2))
}

// The card through the rules, as the player plays it: 2 energy, a nest on the cell aimed at, its first spiderling.
@(test)
test_nest_card_sets_a_nest_down :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := nest_test_room(t, &data, &player)
	defer { destroy_room(&room); level.destroy(&data) }
	definitions := [?]Card_Id{.Spider_Nest}
	configure_test_deck(t, &player, definitions[:], {hand_size = 1, max_energy = 3, energy_regen_per_pulse = 1})
	testing.expect(t, begin_deck_combat(&player.deck))
	cell := grid.offset(player.position, 2, 0)
	play := play_card(&room, hand_card_id_for_definition(t, &player.deck, .Spider_Nest), cell_target(cell))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, play.cost, i32(2))
	index, found := object_index_at(&room, cell)
	testing.expect(t, found)
	if found {
		testing.expect_value(t, room.objects[index].kind, Grid_Object_Kind.Spider_Nest)
		testing.expect_value(t, room.objects[index].power, SPIDER_BITE_DAMAGE)
		testing.expect_value(t, room.objects[index].life, SPIDER_NEST_SECONDS)
	}
	testing.expect_value(t, player.tactical.spiders.count, i32(1))
}

// A spiderling at once, then one every two beats: ten if nobody touches the nest; at nothing the nest is gone.
@(test)
test_nest_hatches_every_two_seconds_and_ends :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := nest_test_room(t, &data, &player, {x = 1, y = 1})
	defer { destroy_room(&room); level.destroy(&data) }
	room.enemies[0].recovery_pulses = 999
	cell := grid.Position{x = 9, y = 5}
	nest_test_place(t, &room, cell)
	testing.expect_value(t, player.tactical.spiders.count, i32(1))
	hatched := 1
	for _ in 0..<SPIDER_NEST_SECONDS {
		pulse: Pulse_Report
		spider_nest_beat(&room, &pulse)
		hatched += arsenal_test_count(&pulse.events, .Spider_Hatched)
		player.tactical.spiders = {}
	}
	testing.expect_value(t, hatched, 10)
	testing.expect_value(t, emplacement_count(&room, .Spider_Nest), 0)
}

// Two nests at most; on a free cell only.
@(test)
test_nest_two_at_most_on_a_free_cell :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := nest_test_room(t, &data, &player)
	defer { destroy_room(&room); level.destroy(&data) }
	testing.expect(t, !emplacement_can_place(&room, .Spider_Nest, room.enemies[0].position))
	testing.expect(t, !emplacement_can_place(&room, .Spider_Nest, player.position))
	nest_test_place(t, &room, {x = 3, y = 3})
	nest_test_place(t, &room, {x = 4, y = 3})
	testing.expect(t, !emplacement_can_place(&room, .Spider_Nest, {x = 5, y = 3}))
}

// A spiderling goes around a wall by the shortest way in steps, and bites: 2, 3 with an upgrade; then it is gone.
@(test)
test_spiderling_goes_around_the_wall_and_bites :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	foe := grid.Position{x = 10, y = 7}
	room := nest_test_room(t, &data, &player, foe)
	defer { destroy_room(&room); level.destroy(&data) }
	nest_test_hold(&room)
	// A wall between the nest and the foe, open at its north end only.
	for y in 4..=9 { testing.expect(t, level.set_tile(&data, {x = 8, y = y}, {kind = .Wall})) }
	cell := grid.Position{x = 5, y = 7}
	health := room.enemies[0].health
	nest_test_place(t, &room, cell)
	// In a straight line 5 cells, a second and a quarter; around the wall 13, a little over three seconds.
	nest_test_run(&room, 3)
	testing.expect_value(t, room.enemies[0].health, health)
	nest_test_run(&room, 0.4)
	testing.expect_value(t, room.enemies[0].health, health-SPIDER_BITE_DAMAGE)
}

// Five seconds without arriving and a spiderling dies, without biting.
@(test)
test_spiderling_dies_after_five_seconds :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := nest_test_room(t, &data, &player, {x = 9, y = 5})
	defer { destroy_room(&room); level.destroy(&data) }
	nest_test_hold(&room)
	// The foe shut in: no way to it.
	for cell in ([?]grid.Position{{x = 8, y = 5}, {x = 10, y = 5}, {x = 9, y = 4}, {x = 9, y = 6}}) {
		testing.expect(t, level.set_tile(&data, cell, {kind = .Wall}))
	}
	health := room.enemies[0].health
	nest_test_place(t, &room, {x = 3, y = 3})
	first := player.tactical.spiders.items[0]
	testing.expect_value(t, first.age, f32(0))
	nest_test_run(&room, 1.9)
	testing.expect(t, player.tactical.spiders.count >= 1)
	nest_test_run(&room, 3.4)
	testing.expect_value(t, room.enemies[0].health, health)
	for spider in player.tactical.spiders.items[:player.tactical.spiders.count] { testing.expect(t, spider.age < SPIDER_LIFE_SECONDS) }
}

// Played on the tick the bite doubles; each upgrade adds one.
@(test)
test_nest_bite_with_upgrades_and_the_tick :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := nest_test_room(t, &data, &player)
	defer { destroy_room(&room); level.destroy(&data) }
	definition, _ := card_definition_by_id(.Spider_Nest)
	testing.expect_value(t, card_effect_amount(definition.effects[0], 0), i32(2))
	testing.expect_value(t, card_effect_amount(definition.effects[0], 2), i32(4))
	action := make_action(.Trigger, PLAYER_ENTITY)
	testing.expect(t, add_effect(&action, place_spider_nest_effect(2, SPIDER_NEST_SECONDS)))
	player.tactical.critical_card = true
	tactical_critical_scale(&room, &action)
	player.tactical.critical_card = false
	testing.expect_value(t, action.effects[0].amount, i32(4))
}

// Every blow that takes the nest's cell costs it 3 seconds, once a blow; one blow over the nest and the player is one.
@(test)
test_nest_loses_three_seconds_a_blow :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := nest_test_room(t, &data, &player)
	defer { destroy_room(&room); level.destroy(&data) }
	cell := grid.Position{x = 3, y = 3}
	id := nest_test_place(t, &room, cell)
	pulse: Pulse_Report
	spider_nests_under_blow(&room, {cell, player.position}, enemy_entity(room.enemies[0].id), &pulse.events)
	index, found := object_index_by_id(&room, id)
	testing.expect(t, found)
	testing.expect_value(t, room.objects[index].life, SPIDER_NEST_SECONDS-SPIDER_NEST_BLOW_SECONDS)
	testing.expect_value(t, arsenal_test_count(&pulse.events, .Spider_Nest_Struck), 1)
	// Enough blows and it is gone.
	for _ in 0..<7 {
		more: Pulse_Report
		spider_nests_under_blow(&room, {cell}, enemy_entity(room.enemies[0].id), &more.events)
	}
	testing.expect_value(t, emplacement_count(&room, .Spider_Nest), 0)
}

// A blast over the nest costs it the same 3 seconds.
@(test)
test_nest_loses_three_seconds_to_a_blast :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := nest_test_room(t, &data, &player, {x = 1, y = 1})
	defer { destroy_room(&room); level.destroy(&data) }
	cell := grid.Position{x = 9, y = 5}
	id := nest_test_place(t, &room, cell)
	pulse: Pulse_Report
	testing.expect(t, spawn_bomb(&room, enemy_entity(room.enemies[0].id), {x = 10, y = 5}, &pulse.events))
	room.objects[len(room.objects)-1].detonation_pulse = room.pulse_count+1
	resolve_due_explosives(&room, &pulse)
	testing.expect_value(t, arsenal_test_count(&pulse.events, .Spider_Nest_Struck), 1)
	index, found := object_index_by_id(&room, id)
	testing.expect(t, found)
	testing.expect_value(t, room.objects[index].life, SPIDER_NEST_SECONDS-SPIDER_NEST_BLOW_SECONDS)
}

// THE BAIT: a foe next to the nest and not next to the player strikes the nest; next to the player, the player.
@(test)
test_nest_is_a_bait :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	foe := grid.Position{x = 9, y = 5}
	room := nest_test_room(t, &data, &player, foe)
	defer { destroy_room(&room); level.destroy(&data) }
	cell := grid.offset(foe, 1, 0)
	id := nest_test_place(t, &room, cell)
	room.enemies[0].intent, room.enemies[0].tactical_cooldown = {}, 0
	plan_enemy_intents(&room)
	testing.expect_value(t, room.enemies[0].intent.target_object, id)
	testing.expect(t, enemy_intent_cell_is_threatened(&room.enemies[0].intent, cell))
	// With the player beside it, the bait does not hold.
	player.position = grid.offset(foe, -1, 0)
	room.enemies[0].intent, room.enemies[0].tactical_cooldown = {}, 0
	plan_enemy_intents(&room)
	testing.expect_value(t, room.enemies[0].intent.target_object, u32(0))
}

// The fight over, the nests and the spiderlings go with it.
@(test)
test_nest_ends_with_the_fight :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := nest_test_room(t, &data, &player)
	defer { destroy_room(&room); level.destroy(&data) }
	nest_test_place(t, &room, {x = 3, y = 3})
	room.phase = .Loot
	tactical_end_combat(&room)
	testing.expect_value(t, emplacement_count(&room, .Spider_Nest), 0)
	testing.expect_value(t, player.tactical.spiders.count, i32(0))
}

// The spiderlings are the player's: the room does not grow.
@(test)
test_nest_keeps_the_room_as_it_was :: proc(t: ^testing.T) {
	testing.expect_value(t, size_of(Room), 9208)
}
