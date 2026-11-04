package game

import "core:math"
import "core:testing"
import grid "../engine/grid"
import level "../level"

// LANCIAFIAMME (docs/piano-ia.md, Fase 13). The test hall (GROUND_TEST_ROWS): 13x11, the player on (6,5).

@(private = "file")
flame_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, foes: ..grid.Position) -> Room {
	spawns: [4]Enemy_Spawn
	for foe, index in foes { spawns[index] = {position = foe, health = 50, attack = 1} }
	room := ground_test_room(t, data, player, {enemies = spawns[:len(foes)]})
	player.tactical.config.windowless = true
	for &foe in room.enemies {
		foe.recovery_pulses = 999
		foe.intent = make_wait_intent(&room, foe.position)
		foe.intent.kind = .Recover
	}
	testing.expect(t, tactical_begin_first_person(&room, f32(FLAMETHROWER_SECONDS), .Flamethrower))
	return room
}

// `seconds` of the world, the button as `fire` says, the mouse on `aim` (board cells).
@(private = "file")
flame_test_run :: proc(room: ^Room, seconds: f32, fire: bool, aim: [2]f32) {
	dt := f32(1.0/60.0)
	for ran := f32(0); ran < seconds && room.phase == .Combat; ran += dt {
		tactical_first_person_tick(room, dt)
		first_person_flame_move(room, {fire = fire, aimed = true, aim = aim})
	}
}

@(private = "file")
flame_test_burn :: proc(room: ^Room, index: int) -> i32 {
	status, found := status_for_entity(room, enemy_entity(room.enemies[index].id), .Burn)
	return status.potency if found else 0
}

// East of the player, in cells of the board.
@(private = "file")
FLAME_TEST_EAST := [2]f32{11.5, 5.5}

@(test)
test_flame_is_a_rare_lab_card_of_three_energy :: proc(t: ^testing.T) {
	definition, found := card_definition_by_id(.Flamethrower)
	testing.expect(t, found && validate_card_definition(&definition))
	testing.expect_value(t, definition.name, "Lanciafiamme")
	testing.expect_value(t, definition.rarity, Card_Rarity.Rare)
	testing.expect_value(t, definition.cost, i32(3))
	testing.expect_value(t, definition.shop_base_price, i32(8))
	testing.expect_value(t, definition.reward_weight, u32(60))
	testing.expect(t, .Lab_Only in definition.traits)
	testing.expect_value(t, card_effect_amount(definition.effects[0], 0), FLAMETHROWER_SECONDS)
	testing.expect_value(t, card_effect_amount(definition.effects[0], 5), FLAMETHROWER_SECONDS+10)
	testing.expect(t, FIRST_PERSON_WEAPONS[.Flamethrower].on_board && FIRST_PERSON_WEAPONS[.Flamethrower].card == .Flamethrower)
}

// The card through the rules: his seconds, no card and no bump while it lasts, the world's clock.
@(test)
test_flame_card_takes_it_up :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 7, y = 5}, health = 50, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer { destroy_room(&room); level.destroy(&data) }
	definitions := [?]Card_Id{.Flamethrower, .Strike}
	configure_test_deck(t, &player, definitions[:], {hand_size = 2, max_energy = 3, energy_regen_per_pulse = 1})
	testing.expect(t, begin_deck_combat(&player.deck))
	play := play_card(&room, hand_card_id_for_definition(t, &player.deck, .Flamethrower), entity_target(PLAYER_ENTITY))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect(t, first_person_flame_active(&room) && first_person_on_board(&room))
	testing.expect_value(t, room.first_person.remaining, f32(FLAMETHROWER_SECONDS))
	testing.expect(t, !tactical_allows_cards(&room))
	health := room.enemies[0].health
	try_move_player(&room, .East)
	testing.expect_value(t, room.enemies[0].health, health)
}

// 3 damage and a stack of Bruciatura a touch; then nothing for 2 seconds; then again.
@(test)
test_flame_strikes_once_every_two_seconds :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := flame_test_room(t, &data, &player, grid.Position{x = 8, y = 5})
	defer { destroy_room(&room); level.destroy(&data) }
	player.position = {x = 6, y = 5}
	flame_test_run(&room, 1, true, FLAME_TEST_EAST)
	testing.expect_value(t, room.enemies[0].health, 50-FLAME_DAMAGE)
	testing.expect_value(t, flame_test_burn(&room, 0), FLAME_BURN)
	flame_test_run(&room, 0.8, true, FLAME_TEST_EAST)
	testing.expect_value(t, room.enemies[0].health, 50-FLAME_DAMAGE)
	flame_test_run(&room, 0.7, true, FLAME_TEST_EAST)
	testing.expect_value(t, room.enemies[0].health, 50-2*FLAME_DAMAGE)
	testing.expect_value(t, flame_test_burn(&room, 0), 2*FLAME_BURN)
}

// Three foes in it, each his own time.
@(test)
test_flame_touches_every_foe_in_it :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := flame_test_room(t, &data, &player, grid.Position{x = 8, y = 5}, grid.Position{x = 8, y = 6}, grid.Position{x = 8, y = 4})
	defer { destroy_room(&room); level.destroy(&data) }
	flame_test_run(&room, 1, true, FLAME_TEST_EAST)
	for foe in room.enemies { testing.expect_value(t, foe.health, 50-FLAME_DAMAGE) }
}

// He turns at 720 degrees a second, no faster; turning, the flame strikes where it is seen: the pieces out go on along the
// way they left, so the tip stays behind the nozzle.
@(test)
test_flame_trails_behind_him_as_he_turns :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := flame_test_room(t, &data, &player, grid.Position{x = 8, y = 5})
	defer { destroy_room(&room); level.destroy(&data) }
	f := &room.first_person.flame
	f.yaw = math.PI/2
	// Facing south, the foe east: the flame has not yet reached him.
	flame_test_run(&room, 0.21, true, {6.5, 11.5})
	testing.expect_value(t, room.enemies[0].health, i32(50))
	// A quarter turn to the east takes an eighth of a second: the nozzle arrives first, the flame after it.
	flame_test_run(&room, 0.13, true, FLAME_TEST_EAST)
	testing.expect(t, abs(f.yaw) < 0.02)
	oldest := flame_piece_at(f, FLAME_PIECES-1)
	testing.expect(t, oldest.alive && abs(oldest.way) > 0.5)
	testing.expect_value(t, room.enemies[0].health, i32(50))
	flame_test_run(&room, 0.25, true, FLAME_TEST_EAST)
	testing.expect_value(t, room.enemies[0].health, 50-FLAME_DAMAGE)
}

// Let go, what is out runs on and still burns.
@(test)
test_flame_let_go_runs_on :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := flame_test_room(t, &data, &player, grid.Position{x = 8, y = 5})
	defer { destroy_room(&room); level.destroy(&data) }
	flame_test_run(&room, 0.1, true, FLAME_TEST_EAST)
	testing.expect_value(t, room.enemies[0].health, i32(50))
	flame_test_run(&room, 0.3, false, FLAME_TEST_EAST)
	testing.expect_value(t, room.enemies[0].health, 50-FLAME_DAMAGE)
}

// Three cells long, not one more.
@(test)
test_flame_is_three_cells_long :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := flame_test_room(t, &data, &player, grid.Position{x = 11, y = 5})
	defer { destroy_room(&room); level.destroy(&data) }
	flame_test_run(&room, 1, true, FLAME_TEST_EAST)
	testing.expect_value(t, room.enemies[0].health, i32(50))
}

// A wall or a cover stops it; a low wall does not.
@(test)
test_flame_stops_at_walls_not_at_low_walls :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := flame_test_room(t, &data, &player, grid.Position{x = 8, y = 5})
	defer { destroy_room(&room); level.destroy(&data) }
	testing.expect(t, level.set_tile(&data, {x = 7, y = 5}, {kind = .Wall}))
	flame_test_run(&room, 1, true, FLAME_TEST_EAST)
	testing.expect_value(t, room.enemies[0].health, i32(50))
	testing.expect(t, level.set_tile(&data, {x = 7, y = 5}, {kind = .Fence}))
	flame_test_run(&room, 1, true, FLAME_TEST_EAST)
	testing.expect_value(t, room.enemies[0].health, 50-FLAME_DAMAGE)
}

// A barrel touched goes off; a block of ice melts.
@(test)
test_flame_sets_off_barrels_and_melts_ice :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := flame_test_room(t, &data, &player, grid.Position{x = 1, y = 1})
	defer { destroy_room(&room); level.destroy(&data) }
	barrel := Grid_Object{id = room.next_object_id, kind = .Barrel, position = {x = 8, y = 5}, health = 1, max_health = 1}
	room.next_object_id += 1
	append(&room.objects, barrel)
	flame_test_run(&room, 0.5, true, FLAME_TEST_EAST)
	index, found := object_index_by_id(&room, barrel.id)
	testing.expect(t, found)
	if found { testing.expect(t, room.objects[index].detonation_pulse != 0) }
	ice := Grid_Object{id = room.next_object_id, kind = .Ice_Block, position = {x = 6, y = 7}, health = 4, max_health = 4}
	room.next_object_id += 1
	append(&room.objects, ice)
	flame_test_run(&room, 0.5, true, {6.5, 11.5})
	_, standing := object_index_by_id(&room, ice.id)
	testing.expect(t, !standing)
}

// The tip a second on a cell: a fire, one new a second at most, and it never touches the player.
@(test)
test_flame_lights_the_floor_where_the_tip_stays :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := flame_test_room(t, &data, &player, grid.Position{x = 1, y = 1})
	defer { destroy_room(&room); level.destroy(&data) }
	// A fifth of a second for the tip to get there, then the second it stays.
	flame_test_run(&room, 1.3, true, FLAME_TEST_EAST)
	testing.expect_value(t, room.ground.fire_count, 1)
	testing.expect_value(t, room.first_person.flame.fires, i32(1))
	flame_test_run(&room, 0.2, true, {6.5, 11.5})
	testing.expect_value(t, room.ground.fire_count, 1)
}

// His steps: at his own pace, the keys the board's.
@(test)
test_flame_steps_at_his_pace :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := flame_test_room(t, &data, &player, grid.Position{x = 1, y = 1})
	defer { destroy_room(&room); level.destroy(&data) }
	player.tactical.config.timed_actions = true
	testing.expect_value(t, tactical_player_pace(&room, true), TACTICAL_PLAYER_PACE)
	testing.expect_value(t, tactical_paced_seconds(&room, TACTICAL_MOVE_SECONDS, true), f32(0.4))
}

// The seconds with the upgrades and on the tick; the seconds run out.
@(test)
test_flame_ends_with_its_seconds :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := flame_test_room(t, &data, &player, grid.Position{x = 1, y = 1})
	defer { destroy_room(&room); level.destroy(&data) }
	tactical_first_person_tick(&room, f32(FLAMETHROWER_SECONDS)+1)
	testing.expect(t, !first_person_flame_active(&room))
	testing.expect_value(t, first_person_flame_move(&room, {fire = true}), Action_Result.Invalid_Phase)
}

// The room keeps its size, and the view's bytes are enough for it.
@(test)
test_flame_keeps_the_room_as_it_was :: proc(t: ^testing.T) {
	testing.expect(t, size_of(First_Person_Flame) <= size_of(First_Person_AK))
	testing.expect_value(t, size_of(Room), 9208)
}
