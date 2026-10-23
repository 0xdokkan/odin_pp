package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

flood_test_play :: proc(t: ^testing.T, room: ^Room, aim: grid.Position, upgrade: i32 = 0) -> Card_Play_Report {
	card := ground_test_card(t, room, .Flood_Wave, upgrade)
	return play_card(room, card.id, cell_target(aim))
}

flood_test_enemy :: proc(room: ^Room, index: int) -> grid.Position {
	return room.enemies[index].position
}

@(test)
test_flood_card_is_an_uncommon_aimed_wave_with_upgrades :: proc(t: ^testing.T) {
	definition, found := card_definition_by_id(.Flood_Wave)
	testing.expect(t, found && validate_card_definition(&definition))
	testing.expect_value(t, definition.name, "Inondazione")
	testing.expect_value(t, definition.rarity, Card_Rarity.Uncommon)
	testing.expect_value(t, definition.cost, i32(2))
	testing.expect_value(t, definition.targeting.rule, Target_Rule.Cell)
	testing.expect_value(t, tactical_card_time_cost(.Flood_Wave), f32(2))
	testing.expect_value(t, card_max_upgrade_level(.Flood_Wave), FLOOD_MAX_UPGRADE_LEVEL)
	node := Run_Node{kind = .Combat, depth = 2}
	// Only in the Prova meccaniche for now: never offered.
	testing.expect(t, card_is_lab_only(.Flood_Wave) && card_offer_weight(definition, &node) == 0)
	testing.expect(t, card_can_upgrade({id = 1, definition_id = .Flood_Wave, lifetime = .Permanent}))
	testing.expect(t, !card_can_upgrade({id = 1, definition_id = .Flood_Wave, upgrade_level = FLOOD_MAX_UPGRADE_LEVEL, lifetime = .Permanent}))
	// One cell of push, one more each upgrade.
	for upgrade in i32(0)..=FLOOD_MAX_UPGRADE_LEVEL {
		effect, made := instantiate_card_effect(definition.effects[0], PLAYER_ENTITY, {id = 1, definition_id = .Flood_Wave, upgrade_level = upgrade})
		testing.expect(t, made)
		testing.expect_value(t, effect.kind, Effect_Kind.Flood_Wave)
		testing.expect_value(t, effect.amount, FLOOD_BASE_PUSH+upgrade)
	}
}

// The wave goes the way of the main axis from the player to the aim; a tie goes
// along the row.
@(test)
test_flood_direction_is_the_main_axis_of_the_aim :: proc(t: ^testing.T) {
	from := grid.Position{6, 5}
	cases := [?]struct{aim: grid.Position, direction: Move_Direction, ok: bool}{
		{{7, 5}, .East, true}, {{5, 5}, .West, true}, {{6, 4}, .North, true}, {{6, 6}, .South, true},
		{{8, 6}, .East, true}, {{4, 3}, .West, true}, {{7, 8}, .South, true}, {{5, 2}, .North, true},
		{{7, 4}, .East, true}, {{5, 6}, .West, true}, {{6, 5}, .North, false},
	}
	for c in cases {
		direction, ok := flood_direction(from, c.aim)
		testing.expectf(t, ok == c.ok && (!ok || direction == c.direction), "aim %v: %v %v", c.aim, direction, ok)
	}
}

// The wave pushes each foe one cell the way it goes, none further; a wall, a
// body or the player stops a push short; nobody is hurt and nobody moves twice.
@(test)
test_flood_pushes_every_foe_one_cell_and_stops_at_blockers :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{
		{position = {3, 3}, health = 50, attack = 1}, // free: 4, 3
		{position = {11, 2}, health = 50, attack = 1}, // against the east wall
		{position = {5, 5}, health = 50, attack = 1}, // against the player (6, 5)
		{position = {8, 7}, health = 50, attack = 1},
		{position = {9, 7}, health = 50, attack = 1}, // a file: both move
		{position = {2, 8}, health = 50, attack = 1},
		{position = {3, 8}, health = 50, attack = 1}, // a file against another foe at 4,8 ...
		{position = {4, 8}, health = 50, attack = 1},
		{position = {5, 8}, health = 50, attack = 1},
		{position = {6, 8}, health = 50, attack = 1},
		{position = {7, 8}, health = 50, attack = 1},
		{position = {8, 8}, health = 50, attack = 1},
		{position = {9, 8}, health = 50, attack = 1},
		{position = {10, 8}, health = 50, attack = 1},
		{position = {11, 8}, health = 50, attack = 1}, // a whole row to the wall: none moves
	}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	health := [len(spawns)]i32{}
	for enemy, i in room.enemies { health[i] = enemy.health }
	play := flood_test_play(t, &room, {7, 5})
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, flood_test_enemy(&room, 0), grid.Position{4, 3})
	testing.expect_value(t, flood_test_enemy(&room, 1), grid.Position{11, 2})
	testing.expect_value(t, flood_test_enemy(&room, 2), grid.Position{5, 5})
	testing.expect_value(t, flood_test_enemy(&room, 3), grid.Position{9, 7})
	testing.expect_value(t, flood_test_enemy(&room, 4), grid.Position{10, 7})
	for i in 5..<len(spawns) { testing.expect_value(t, flood_test_enemy(&room, i), spawns[i].position) }
	testing.expect_value(t, player.position, grid.Position{6, 5})
	for enemy, i in room.enemies { testing.expect_value(t, enemy.health, health[i]) }
	testing.expect_value(t, player.health, i32(100))
	swept := false
	for event in room.recent_events.events[:room.recent_events.count] {
		if event.kind != .Flood_Swept { continue }
		swept = true
		testing.expect_value(t, event.from_position, grid.Position{0, 5})
		testing.expect_value(t, event.to_position, grid.Position{12, 5})
		testing.expect_value(t, event.amount, i32(1))
		testing.expect_value(t, Move_Direction(event.duration), Move_Direction.East)
	}
	testing.expect(t, swept)
}

@(test)
test_flood_goes_all_four_ways :: proc(t: ^testing.T) {
	aims := [4]grid.Position{{6, 4}, {7, 5}, {6, 6}, {5, 5}}
	offsets := [4]grid.Position{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}
	for direction in Move_Direction {
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {3, 3}, health = 50, attack = 1}, {position = {9, 7}, health = 50, attack = 1}}
		room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
		testing.expect_value(t, flood_test_play(t, &room, aims[int(direction)]).result, Card_Play_Result.Played)
		for spawn, i in spawns {
			testing.expect_value(t, room.enemies[i].position, grid.Position{spawn.position.x+offsets[int(direction)].x, spawn.position.y+offsets[int(direction)].y})
		}
		destroy_room(&room)
		level.destroy(&data)
	}
}

// Two upgrades push three cells; the tick one more. A push ends where a wall
// or a body stops it.
@(test)
test_flood_upgrades_and_the_tick_push_further :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {2, 2}, health = 50, attack = 1}, {position = {9, 8}, health = 50, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, flood_test_play(t, &room, {7, 5}, 2).result, Card_Play_Result.Played)
	testing.expect_value(t, flood_test_enemy(&room, 0), grid.Position{5, 2})
	// 9, 8 + 3 would pass the wall at 12: it stops at 11.
	testing.expect_value(t, flood_test_enemy(&room, 1), grid.Position{11, 8})
	card := ground_test_card(t, &room, .Flood_Wave, 0)
	room.player.tactical.critical_next = true
	testing.expect_value(t, play_card(&room, card.id, cell_target({5, 5})).result, Card_Play_Result.Played)
	// West two cells now: 5, 2 to 3, 2 and 11, 8 to 9, 8.
	testing.expect_value(t, flood_test_enemy(&room, 0), grid.Position{3, 2})
	testing.expect_value(t, flood_test_enemy(&room, 1), grid.Position{9, 8})
}

// Fires go out before anybody is pushed: no foe lands in one. The player's
// Incendio and the board's own Fire objects both go; nothing else of the
// board is touched.
@(test)
test_flood_puts_out_every_fire_before_the_push :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {4, 3}, health = 50, attack = 1}}
	objects := [?]Grid_Object_Spawn{{kind = .Fire, position = {9, 2}}, {kind = .Barrel, position = {9, 7}}, {kind = .Ice_Block, position = {2, 7}}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:], objects = objects[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	// A fire where the foe will land, and one far from it.
	testing.expect(t, ground_test_pour(&room, .Burn, {5, 3}, 2).accepted)
	testing.expect(t, ground_test_pour(&room, .Burn, {8, 8}, 1).accepted)
	testing.expect(t, room.ground.fire_count == 2)
	testing.expect(t, ground_burn_at(&room, {5, 3}) > 0)
	play := flood_test_play(t, &room, {7, 5})
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, room.ground.fire_count, 0)
	testing.expect_value(t, ground_burn_at(&room, {5, 3}), i32(0))
	fires, others := 0, 0
	for object in room.objects { if object.kind == .Fire { fires += 1 } else { others += 1 } }
	testing.expect_value(t, fires, 0)
	testing.expect_value(t, others, 2)
	testing.expect_value(t, flood_test_enemy(&room, 0), grid.Position{5, 3})
	_, burning := status_for_entity(&room, enemy_entity(room.enemies[0].id), .Burn)
	testing.expect(t, !burning)
	steam := 0
	for event in room.recent_events.events[:room.recent_events.count] { if event.kind == .Fire_Extinguished { steam += 1 } }
	testing.expect(t, steam >= 3)
}

// A pool, a trap or a hazard acts on the cell a pushed foe enters, and a trap
// that kills it counts as a kill in the room.
@(test)
test_flood_pushed_foes_trigger_the_cell_they_enter :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {3, 3}, health = 50, attack = 1}, {position = {3, 7}, health = 2, attack = 1}}
	traps := [?]Trap_Spawn{{position = {4, 7}, damage = 5}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:], traps = traps[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, ground_test_pour(&room, .Poison, {4, 3}, 3).accepted)
	testing.expect_value(t, flood_test_play(t, &room, {7, 5}).result, Card_Play_Result.Played)
	testing.expect_value(t, ground_test_potency(&room, enemy_entity(room.enemies[0].id), .Poison), i32(3))
	// The foe on the trap died of it.
	testing.expect_value(t, len(room.enemies), 1)
}

// The aim must be a cell round the player: his own cell and cells out of reach
// are refused and cost nothing.
@(test)
test_flood_refuses_his_own_cell_and_far_cells :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {3, 3}, health = 50, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	own := flood_test_play(t, &room, player.position)
	testing.expect_value(t, own.result, Card_Play_Result.Compile_Failed)
	far := flood_test_play(t, &room, {10, 5})
	testing.expect_value(t, far.result, Card_Play_Result.Compile_Failed)
	testing.expect_value(t, room.player.deck.energy, room.player.deck.rules.max_energy)
	testing.expect_value(t, flood_test_enemy(&room, 0), grid.Position{3, 3})
	// A wall cell a step away is still an aim: the wave goes that way.
	player.position = {1, 5}
	testing.expect_value(t, flood_test_play(t, &room, {0, 5}).result, Card_Play_Result.Played)
	testing.expect_value(t, flood_test_enemy(&room, 0), grid.Position{2, 3})
}

// Nobody out of play is moved: the Lazzo's foe and the Pinball's ball stay.
@(test)
test_flood_leaves_the_foe_out_of_play :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {3, 3}, health = 50, attack = 1}, {position = {3, 7}, health = 50, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	room.pinball = {active = true, enemy_id = room.enemies[0].id, cell = room.enemies[0].position}
	testing.expect_value(t, flood_test_play(t, &room, {7, 5}).result, Card_Play_Result.Played)
	testing.expect_value(t, flood_test_enemy(&room, 0), grid.Position{3, 3})
	testing.expect_value(t, flood_test_enemy(&room, 1), grid.Position{4, 7})
}
