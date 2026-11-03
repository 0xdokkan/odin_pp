package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

// REGINA (docs/piano-ia.md, Fase 11). The test hall (GROUND_TEST_ROWS): 13x11, the player on (6,5).

@(private = "file")
queen_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, foes: ..grid.Position) -> Room {
	spawns: [4]Enemy_Spawn
	for foe, index in foes { spawns[index] = {position = foe, health = 50, attack = 1} }
	room := ground_test_room(t, data, player, {enemies = spawns[:len(foes)]})
	player.tactical.config.windowless = true
	for &foe in room.enemies {
		foe.recovery_pulses = 999
		foe.intent = make_wait_intent(&room, foe.position)
		foe.intent.kind = .Recover
	}
	return room
}

@(private = "file")
queen_test_place :: proc(t: ^testing.T, room: ^Room, cell: grid.Position, power := QUEEN_BASE_DAMAGE) -> u32 {
	report: Action_Report
	testing.expect(t, place_queen(room, cell, power, QUEEN_SECONDS, &report))
	return room.objects[len(room.objects)-1].id
}

// One look: what the controller does on a frame of the world.
@(private = "file")
queen_test_look :: proc(room: ^Room) -> (pulse: Pulse_Report) {
	queen_strike(room, &pulse)
	return
}

@(private = "file")
queen_test_cell :: proc(t: ^testing.T, room: ^Room, id: u32) -> grid.Position {
	index, found := object_index_by_id(room, id)
	testing.expect(t, found)
	return room.objects[index].position if found else {}
}

@(test)
test_queen_is_a_rare_lab_card_of_three_energy :: proc(t: ^testing.T) {
	definition, found := card_definition_by_id(.Queen)
	testing.expect(t, found && validate_card_definition(&definition))
	testing.expect_value(t, definition.name, "Regina")
	testing.expect_value(t, definition.rarity, Card_Rarity.Rare)
	testing.expect_value(t, definition.cost, i32(3))
	testing.expect_value(t, definition.shop_base_price, i32(8))
	testing.expect_value(t, definition.reward_weight, u32(60))
	testing.expect(t, .Lab_Only in definition.traits)
	testing.expect_value(t, card_max_upgrade_level(.Queen), QUEEN_MAX_UPGRADE_LEVEL)
}

// The card through the rules, as the player plays it.
@(test)
test_queen_card_sets_her_down :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := queen_test_room(t, &data, &player, grid.Position{x = 1, y = 2})
	defer { destroy_room(&room); level.destroy(&data) }
	definitions := [?]Card_Id{.Queen}
	configure_test_deck(t, &player, definitions[:], {hand_size = 1, max_energy = 3, energy_regen_per_pulse = 1})
	testing.expect(t, begin_deck_combat(&player.deck))
	cell := grid.offset(player.position, 2, 0)
	play := play_card(&room, hand_card_id_for_definition(t, &player.deck, .Queen), cell_target(cell))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, play.cost, i32(3))
	index, found := object_index_at(&room, cell)
	testing.expect(t, found)
	if found {
		testing.expect_value(t, room.objects[index].kind, Grid_Object_Kind.Queen)
		testing.expect_value(t, room.objects[index].power, QUEEN_BASE_DAMAGE)
		testing.expect_value(t, room.objects[index].life, QUEEN_SECONDS)
	}
}

// One at a time, on a free cell.
@(test)
test_queen_one_at_a_time :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := queen_test_room(t, &data, &player, grid.Position{x = 1, y = 2})
	defer { destroy_room(&room); level.destroy(&data) }
	testing.expect(t, !emplacement_can_place(&room, .Queen, player.position))
	testing.expect(t, !emplacement_can_place(&room, .Queen, room.enemies[0].position))
	queen_test_place(t, &room, {x = 9, y = 9})
	testing.expect(t, !emplacement_can_place(&room, .Queen, {x = 3, y = 3}))
}

// Her 8 lines reach a foe, each in turn; next to him she stays where she is, else she runs to the cell before him.
@(test)
test_queen_runs_down_each_of_her_lines :: proc(t: ^testing.T) {
	centre := grid.Position{x = 6, y = 6}
	for line in QUEEN_LINES {
		data: level.Level
		player: Player
		// The north lines would meet the player: he stands aside.
		foe := grid.offset(centre, line.x*2, line.y*2)
		room := queen_test_room(t, &data, &player, foe)
		player.position = {x = 1, y = 1}
		id := queen_test_place(t, &room, centre)
		pulse := queen_test_look(&room)
		testing.expect_value(t, queen_test_cell(t, &room, id), grid.offset(centre, line.x, line.y))
		testing.expect_value(t, room.enemies[0].health, 50-QUEEN_BASE_DAMAGE)
		testing.expect_value(t, arsenal_test_count(&pulse.events, .Queen_Ran), 1)
		testing.expect_value(t, arsenal_test_count(&pulse.events, .Queen_Struck), 1)
		destroy_room(&room)
		level.destroy(&data)
	}
}

// Walls, low walls, covers, solid objects and the player stop a line; a foe off every line is safe.
@(test)
test_queen_lines_stop_at_what_stands_in_them :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := queen_test_room(t, &data, &player, grid.Position{x = 10, y = 8})
	defer { destroy_room(&room); level.destroy(&data) }
	player.position = {x = 1, y = 1}
	id := queen_test_place(t, &room, {x = 6, y = 8})
	testing.expect(t, queen_is_due(&room))
	testing.expect(t, level.set_tile(&data, {x = 8, y = 8}, {kind = .Fence}))
	testing.expect(t, !queen_is_due(&room))
	testing.expect(t, level.set_tile(&data, {x = 8, y = 8}, {kind = .Floor}))
	testing.expect(t, queen_is_due(&room))
	player.position = {x = 8, y = 8}
	testing.expect(t, !queen_is_due(&room))
	player.position = {x = 1, y = 1}
	pulse: Pulse_Report
	testing.expect(t, deploy_board_device(&room, .Tesla_Coil, {x = 8, y = 8}, 1, 0, &pulse.events))
	testing.expect(t, !queen_is_due(&room))
	testing.expect_value(t, queen_test_cell(t, &room, id), grid.Position{x = 6, y = 8})
	testing.expect_value(t, room.enemies[0].health, i32(50))
}

// Of two foes the nearest; of equals the first line in the order (north before east).
@(test)
test_queen_goes_for_the_nearest_then_the_first_line :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := queen_test_room(t, &data, &player, grid.Position{x = 10, y = 8}, grid.Position{x = 6, y = 6})
	defer { destroy_room(&room); level.destroy(&data) }
	player.position = {x = 1, y = 1}
	id := queen_test_place(t, &room, {x = 6, y = 8})
	queen_test_look(&room)
	testing.expect_value(t, room.enemies[1].health, 50-QUEEN_BASE_DAMAGE)
	testing.expect_value(t, room.enemies[0].health, i32(50))
	testing.expect_value(t, queen_test_cell(t, &room, id), grid.Position{x = 6, y = 7})
	// Equals: the same two cells away, north and east.
	equal_data: level.Level
	equal_player: Player
	equal := queen_test_room(t, &equal_data, &equal_player, grid.Position{x = 8, y = 8}, grid.Position{x = 6, y = 6})
	defer { destroy_room(&equal); level.destroy(&equal_data) }
	equal_player.position = {x = 1, y = 1}
	queen_test_place(t, &equal, {x = 6, y = 8})
	queen_test_look(&equal)
	testing.expect_value(t, equal.enemies[1].health, 50-QUEEN_BASE_DAMAGE)
}

// Then 2 world seconds before the next blow, on the foe still beside her.
@(test)
test_queen_waits_two_seconds_between_blows :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := queen_test_room(t, &data, &player, grid.Position{x = 10, y = 8})
	defer { destroy_room(&room); level.destroy(&data) }
	player.position = {x = 1, y = 1}
	queen_test_place(t, &room, {x = 6, y = 8})
	queen_test_look(&room)
	queen_test_look(&room)
	testing.expect_value(t, room.enemies[0].health, 50-QUEEN_BASE_DAMAGE)
	testing.expect(t, !tactical_flights_due(&room))
	tactical_flight_tick(&room, QUEEN_WAIT_SECONDS-0.1)
	testing.expect(t, !tactical_flights_due(&room))
	tactical_flight_tick(&room, 0.2)
	testing.expect(t, tactical_flights_due(&room))
	queen_test_look(&room)
	testing.expect_value(t, room.enemies[0].health, 50-2*QUEEN_BASE_DAMAGE)
}

// Her blow with upgrades and on the tick: 5, 6; 6 on the tick.
@(test)
test_queen_blow_with_upgrades_and_the_tick :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := queen_test_room(t, &data, &player, grid.Position{x = 1, y = 2})
	defer { destroy_room(&room); level.destroy(&data) }
	definition, _ := card_definition_by_id(.Queen)
	testing.expect_value(t, card_effect_amount(definition.effects[0], 1), i32(5))
	testing.expect_value(t, card_effect_amount(definition.effects[0], 2), i32(6))
	action := make_action(.Trigger, PLAYER_ENTITY)
	testing.expect(t, add_effect(&action, place_queen_effect(QUEEN_BASE_DAMAGE, QUEEN_SECONDS)))
	player.tactical.critical_card = true
	tactical_critical_scale(&room, &action)
	player.tactical.critical_card = false
	testing.expect_value(t, action.effects[0].amount, i32(6))
}

// Nobody passes through her cell, and nothing breaks her: no blow, no blast.
@(test)
test_queen_stops_the_steps_and_nothing_strikes_her :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := queen_test_room(t, &data, &player, grid.Position{x = 1, y = 2})
	defer { destroy_room(&room); level.destroy(&data) }
	cell := grid.Position{x = 7, y = 5}
	id := queen_test_place(t, &room, cell)
	testing.expect(t, cell_blocks_movement(&room, cell))
	testing.expect(t, !effect_is_valid(&room, damage_effect(object_entity(id), 5)))
	pulse: Pulse_Report
	testing.expect(t, spawn_bomb(&room, enemy_entity(room.enemies[0].id), {x = 8, y = 5}, &pulse.events))
	room.objects[len(room.objects)-1].detonation_pulse = room.pulse_count+1
	resolve_due_explosives(&room, &pulse)
	testing.expect_value(t, queen_test_cell(t, &room, id), cell)
	// Not the sight.
	definition, _ := grid_object_definition(.Queen)
	testing.expect(t, definition.blocks_movement && !definition.blocks_line_of_sight)
}

// 20 beats, then she goes, as she does when the fight ends.
@(test)
test_queen_ends_after_her_seconds_and_with_the_fight :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := queen_test_room(t, &data, &player, grid.Position{x = 1, y = 2})
	defer { destroy_room(&room); level.destroy(&data) }
	queen_test_place(t, &room, {x = 9, y = 9})
	for _ in 0..<QUEEN_SECONDS-1 {
		pulse: Pulse_Report
		queen_beat(&room, &pulse)
	}
	testing.expect_value(t, emplacement_count(&room, .Queen), 1)
	pulse: Pulse_Report
	queen_beat(&room, &pulse)
	testing.expect_value(t, emplacement_count(&room, .Queen), 0)
	testing.expect_value(t, arsenal_test_count(&pulse.events, .Queen_Closed), 1)
	queen_test_place(t, &room, {x = 9, y = 9})
	player.tactical.queen_wait = 1
	room.phase = .Loot
	tactical_end_combat(&room)
	testing.expect_value(t, emplacement_count(&room, .Queen), 0)
	testing.expect_value(t, player.tactical.queen_wait, f32(0))
}

@(test)
test_queen_keeps_the_room_as_it_was :: proc(t: ^testing.T) {
	testing.expect_value(t, size_of(Room), 9208)
}
