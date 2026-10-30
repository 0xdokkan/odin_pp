package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

// An open hall of 11x9 cells inside its walls, the player in the middle (6, 5)
// and the exit in the bottom right corner.
GROUND_TEST_ROWS :: [?]string{
	"#############",
	"#...........#",
	"#...........#",
	"#...........#",
	"#...........#",
	"#.....@.....#",
	"#...........#",
	"#...........#",
	"#...........#",
	"#..........>#",
	"#############",
}

ground_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, content: Room_Content, vision := 0) -> Room {
	rows := GROUND_TEST_ROWS
	err: level.Parse_Error
	data^, err, _ = level.from_ascii(rows[:])
	testing.expect_value(t, err, level.Parse_Error.None)
	player^ = create_test_player(t)
	player.stats.max_health, player.health, player.stats.defense = 100, 100, 0
	config := DEFAULT_TACTICAL_CONFIG
	config.vision_size = vision
	testing.expect(t, configure_tactical(player, config))
	room, ok := create_room(data, player, content)
	testing.expect(t, ok)
	return room
}

// A pool (`kind` Poison) or a fire (Burn) poured as a card pours it.
ground_test_pour :: proc(room: ^Room, kind: Status_Kind, cell: grid.Position, amount: i32 = 2) -> Action_Report {
	action := make_action(.Card, PLAYER_ENTITY, cell_target(cell), .Walkable_Cell)
	add_effect(&action, place_ground_effect(cell, kind, amount))
	return resolve_action(room, &action)
}

// `enemy` moved to `destination` by the player (a shove), or teleported there.
ground_test_shove :: proc(room: ^Room, enemy: Entity_Ref, destination: grid.Position, mode := Movement_Mode.Traverse) -> Action_Report {
	action := make_action(.Trigger, PLAYER_ENTITY, entity_target(enemy), .Opponent)
	add_effect(&action, move_effect(enemy, destination, mode))
	return resolve_action(room, &action)
}

// A new window, as the clock's Timeout opens it.
ground_test_window :: proc(t: ^testing.T, room: ^Room) -> bool {
	s := &room.player.tactical
	s.phase, s.remaining, s.queued_beats, s.cast_remaining = .Decision, 0, 0, 0
	room.tactical_pulse = {}
	expired := tactical_expire_window(room)
	testing.expect(t, expired)
	return expired
}

ground_test_statuses :: proc(log: ^Event_Log, target: Entity_Ref, kind: Status_Kind) -> (count: int, last: i32) {
	for event in log.events[:log.count] {
		if event.kind != .Status_Applied || event.target != target || event.status != kind { continue }
		count += 1
		last = event.amount
	}
	return
}

ground_test_potency :: proc(room: ^Room, entity: Entity_Ref, kind: Status_Kind) -> i32 {
	status, found := status_for_entity(room, entity, kind)
	return status.potency if found else 0
}

// The hand's first card turned into `id` at `upgrade`, ready to play.
ground_test_card :: proc(t: ^testing.T, room: ^Room, id: Card_Id, upgrade: i32 = 0) -> Card_Instance {
	s := &room.player.tactical
	s.phase, s.remaining, s.cast_remaining, s.action_remaining = .Decision, 20, 0, 0
	room.tactical_pulse = {}
	tactical_refill(room)
	room.player.deck.energy = room.player.deck.rules.max_energy
	card := &room.player.deck.hand[0]
	card.definition_id, card.upgrade_level = id, upgrade
	for &owned in room.player.deck.owned[:room.player.deck.owned_count] {
		if owned.id == card.id { owned.definition_id, owned.upgrade_level = id, upgrade }
	}
	testing.expect(t, validate_deck_state(&room.player.deck))
	return card^
}

@(test)
test_ground_cards_are_tactical_cells_with_their_rules :: proc(t: ^testing.T) {
	kinds := [2]Status_Kind{.Poison, .Burn}
	seconds := [2]f32{1, 2}
	energy := [2]i32{1, 2}
	rarities := [2]Card_Rarity{.Common, .Uncommon}
	for id, index in ([2]Card_Id{.Poison_Pool, .Wildfire}) {
		definition, found := card_definition_by_id(id)
		testing.expect(t, found && validate_card_definition(&definition))
		testing.expect_value(t, definition.cost, energy[index])
		testing.expect_value(t, definition.rarity, rarities[index])
		testing.expect_value(t, definition.targeting.rule, Target_Rule.Walkable_Cell)
		testing.expect_value(t, definition.effects[0].kind, Effect_Kind.Place_Ground)
		testing.expect_value(t, definition.effects[0].status, kinds[index])

		testing.expect(t, card_places_ground(id) && !card_is_board_device(id))
		testing.expect_value(t, tactical_card_time_cost(id), seconds[index])
		testing.expect_value(t, card_dice_count(id), 0)
		node := Run_Node{kind = .Combat, depth = 2}
		testing.expect(t, card_offer_weight(definition, &node) > 0)
		// Each upgrade gives a stack more: 2, 3, 4... and 1, 2, 3...
		for upgrade in i32(0)..=3 {
			effect, made := instantiate_card_effect(definition.effects[0], PLAYER_ENTITY, {id = 1, definition_id = id, upgrade_level = upgrade})
			testing.expect(t, made)
			testing.expect_value(t, effect.amount, (2 if id == .Poison_Pool else 1)+upgrade)
			testing.expect_value(t, effect.status, kinds[index])
		}
		testing.expect(t, card_can_upgrade({id = 1, definition_id = id, lifetime = .Permanent}))
	}

}

// A free walkable cell: no enemy, no object of any kind, not the player's, in
// range and in sight. Traps and the exit take a pool; a pool takes a fire,
// never a second pool.
@(test)
test_ground_targets_a_free_walkable_cell :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 6, y = 3}, health = 50, attack = 1}}
	objects := [?]Grid_Object_Spawn{
		{kind = .Ice_Block, position = {x = 4, y = 5}}, {kind = .Fire, position = {x = 8, y = 5}}, {kind = .Barrel, position = {x = 5, y = 7}},
		{kind = .Bomb, position = {x = 7, y = 7}}, {kind = .Shock_Floor, position = {x = 4, y = 3}}, {kind = .Tesla_Coil, position = {x = 8, y = 3}},
	}
	traps := [?]Trap_Spawn{{position = {x = 6, y = 7}, damage = 2}}
	obstacles := [?]grid.Position{{x = 7, y = 4}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:], objects = objects[:], traps = traps[:], obstacles = obstacles[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	evaluate :: proc(room: ^Room, id: Card_Id, cell: grid.Position) -> Card_Compile_Error {
		return evaluate_card_targeting(room, {id = 1, definition_id = id, lifetime = .Permanent}, {anchor = cell, has_anchor = true}).error
	}
	for id in ([2]Card_Id{.Poison_Pool, .Wildfire}) {
		testing.expect_value(t, evaluate(&room, id, {x = 6, y = 4}), Card_Compile_Error.None)
		testing.expect_value(t, evaluate(&room, id, room.enemies[0].position), Card_Compile_Error.Target_Blocked)
		for object in objects { testing.expectf(t, evaluate(&room, id, object.position) != .None, "%v on %v", id, object.kind) }
		testing.expect(t, evaluate(&room, id, player.position) != .None)
		testing.expect(t, evaluate(&room, id, {x = 7, y = 4}) != .None)
		// Out of range, behind the cover.
		testing.expect_value(t, evaluate(&room, id, {x = 10, y = 5}), Card_Compile_Error.Target_Out_Of_Range)
		testing.expect_value(t, evaluate(&room, id, {x = 8, y = 2}), Card_Compile_Error.Target_Blocked)
		// A trap takes them.
		testing.expect_value(t, evaluate(&room, id, {x = 6, y = 7}), Card_Compile_Error.None)
	}
	// The exit, from beside it; a wall, from beside it.
	player.position = {x = 9, y = 8}
	testing.expect_value(t, evaluate(&room, .Poison_Pool, room.exit_position), Card_Compile_Error.None)
	player.position = {x = 2, y = 5}
	testing.expect(t, evaluate(&room, .Poison_Pool, {x = 0, y = 5}) != .None)
	player.position = {x = 6, y = 5}
	// A pool refuses a pool; a fire burns over a pool and over a fire.
	testing.expect(t, ground_test_pour(&room, .Poison, {x = 6, y = 4}).accepted)
	testing.expect_value(t, evaluate(&room, .Poison_Pool, {x = 6, y = 4}), Card_Compile_Error.Target_Blocked)
	testing.expect_value(t, evaluate(&room, .Wildfire, {x = 6, y = 4}), Card_Compile_Error.None)
	testing.expect(t, ground_test_pour(&room, .Burn, {x = 6, y = 4}, 1).accepted)
	testing.expect_value(t, evaluate(&room, .Wildfire, {x = 6, y = 4}), Card_Compile_Error.None)
	// A thirty-third fire finds no room.
	for room.ground.fire_count < MAX_GROUND_FIRES { testing.expect(t, ground_test_pour(&room, .Burn, {x = 5, y = 4}, 1).accepted) }
	testing.expect_value(t, evaluate(&room, .Wildfire, {x = 5, y = 4}), Card_Compile_Error.Target_Blocked)
	testing.expect(t, !ground_test_pour(&room, .Burn, {x = 5, y = 4}, 1).accepted)
	testing.expect_value(t, evaluate(&room, .Poison_Pool, {x = 5, y = 4}), Card_Compile_Error.None)
	// A cell in the fog is no target.
	fogged: level.Level
	fogged_player: Player
	fog_room := ground_test_room(t, &fogged, &fogged_player, {enemies = spawns[:]}, 3)
	defer level.destroy(&fogged)
	defer destroy_room(&fog_room)
	testing.expect_value(t, evaluate(&fog_room, .Poison_Pool, {x = 6, y = 6}), Card_Compile_Error.None)
	testing.expect_value(t, evaluate(&fog_room, .Poison_Pool, {x = 6, y = 7}), Card_Compile_Error.Invalid_Target)
}

// Every cell of a pool an enemy enters gives its Veleno, whatever moves it; a
// pool's cell to the next gives it again, leaving gives nothing. The player
// walks through untouched.
@(test)
test_pool_poisons_each_cell_an_enemy_enters :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 2, y = 2}, health = 50, attack = 1}, {position = {x = 10, y = 8}, health = 50, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	foe := enemy_entity(room.enemies[0].id)
	for x in 3..=5 { testing.expect(t, ground_test_pour(&room, .Poison, {x = x, y = 2}).accepted) }
	// A shove across the three cells: 2, 4, 6, from the System.
	pushed := ground_test_shove(&room, foe, {x = 5, y = 2})
	testing.expect(t, pushed.accepted)
	count, last := ground_test_statuses(&pushed.events, foe, .Poison)
	testing.expect_value(t, count, 3)
	testing.expect_value(t, last, i32(6))
	for event in pushed.events.events[:pushed.events.count] {
		if event.kind == .Status_Applied { testing.expect_value(t, event.source, SYSTEM_ENTITY) }
	}
	testing.expect_value(t, ground_test_potency(&room, foe, .Poison), i32(6))
	// Shoved on to the dry floor: nothing more.
	off := ground_test_shove(&room, foe, {x = 6, y = 2})
	count, _ = ground_test_statuses(&off.events, foe, .Poison)
	testing.expect_value(t, count, 0)
	// A teleport lands it in the pool: one cell, one dose.
	landed := ground_test_shove(&room, foe, {x = 3, y = 2}, .Teleport)
	count, last = ground_test_statuses(&landed.events, foe, .Poison)
	testing.expect_value(t, count, 1)
	testing.expect_value(t, last, i32(8))
	// From a pool's cell into the next one.
	again := ground_test_shove(&room, foe, {x = 4, y = 2})
	count, last = ground_test_statuses(&again.events, foe, .Poison)
	testing.expect(t, count == 1 && last == 10)
	// The player wades through them all untouched.
	player.position = {x = 3, y = 3}
	walk := make_action(.Move, PLAYER_ENTITY, cell_target({x = 3, y = 1}), .Walkable_Cell)
	testing.expect(t, add_effect(&walk, move_effect(PLAYER_ENTITY, {x = 3, y = 1})))
	walked := resolve_action(&room, &walk)
	testing.expect(t, walked.accepted && player.position == grid.Position{x = 3, y = 1})
	count, _ = ground_test_statuses(&walked.events, PLAYER_ENTITY, .Poison)
	testing.expect_value(t, count, 0)
	testing.expect_value(t, ground_test_potency(&room, PLAYER_ENTITY, .Poison), i32(0))
}

// An enemy's own step into a pool is its action: the Veleno it picked up
// bites at its end, then wears a stack.
@(test)
test_pool_entered_on_an_enemy_step_bites_at_its_end :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 6, y = 1}, health = 50, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, ground_test_pour(&room, .Poison, {x = 6, y = 2}).accepted)
	enemy := &room.enemies[0]
	intent := make_wait_intent(&room, enemy.position)
	intent.kind, intent.destination, intent.path[0], intent.path_count = .Move, {x = 6, y = 2}, {x = 6, y = 2}, 1
	enemy.intent = intent
	pulse: Pulse_Report
	resolve_enemy_intents(&room, &pulse, enemy.id)
	foe := enemy_entity(room.enemies[0].id)
	testing.expect_value(t, room.enemies[0].position, grid.Position{x = 6, y = 2})
	testing.expect_value(t, room.enemies[0].health, i32(48))
	testing.expect_value(t, ground_test_potency(&room, foe, .Poison), i32(1))
	count, last := ground_test_statuses(&pulse.events, foe, .Poison)
	testing.expect(t, count == 1 && last == 2)
}

// The areas pools close fill at once, and poison whoever stands there; walls,
// cover and objects alone never close one, nor do actors; a tie of the
// largest areas fills neither.
@(test)
test_pool_fills_the_areas_it_closes :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 3, y = 3}, health = 50, attack = 1}, {position = {x = 10, y = 8}, health = 50, attack = 1}}
	// A pocket closed by walls and cover, another by cover and an ice block.
	obstacles := [?]grid.Position{{x = 10, y = 1}, {x = 11, y = 2}, {x = 1, y = 8}}
	objects := [?]Grid_Object_Spawn{{kind = .Ice_Block, position = {x = 2, y = 9}}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:], obstacles = obstacles[:], objects = objects[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	foe := enemy_entity(room.enemies[0].id)
	// Three sides around the chaser leave it open.
	for cell in ([3]grid.Position{{x = 3, y = 2}, {x = 4, y = 3}, {x = 3, y = 4}}) {
		poured := ground_test_pour(&room, .Poison, cell)
		testing.expect(t, poured.accepted)
		count, _ := ground_test_statuses(&poured.events, foe, .Poison)
		testing.expect_value(t, count, 0)
	}
	testing.expect_value(t, ground_pool_at(&room, {x = 3, y = 3}), i32(0))
	// The fourth closes it: its cell fills with the closing pool's Veleno.
	closed := ground_test_pour(&room, .Poison, {x = 2, y = 3}, 5)
	testing.expect(t, closed.accepted)
	testing.expect_value(t, ground_pool_at(&room, {x = 3, y = 3}), i32(5))
	count, last := ground_test_statuses(&closed.events, foe, .Poison)
	testing.expect(t, count == 1 && last == 5)
	for diagonal in ([4]grid.Position{{x = 2, y = 2}, {x = 4, y = 2}, {x = 2, y = 4}, {x = 4, y = 4}}) { testing.expect_value(t, ground_pool_at(&room, diagonal), i32(0)) }
	// The pockets of walls, cover and an object stay dry.
	testing.expect_value(t, ground_pool_at(&room, {x = 11, y = 1}), i32(0))
	testing.expect_value(t, ground_pool_at(&room, {x = 1, y = 9}), i32(0))
	// A corner closed against the walls fills.
	testing.expect(t, ground_test_pour(&room, .Poison, {x = 2, y = 1}).accepted)
	testing.expect_value(t, ground_pool_at(&room, {x = 1, y = 1}), i32(0))
	testing.expect(t, ground_test_pour(&room, .Poison, {x = 1, y = 2}).accepted)
	testing.expect_value(t, ground_pool_at(&room, {x = 1, y = 1}), i32(2))
	testing.expect_value(t, ground_pool_at(&room, {x = 11, y = 1}), i32(0))
	testing.expect_value(t, ground_pool_at(&room, {x = 1, y = 9}), i32(0))
}

@(test)
test_pool_walls_split_the_hall_only_past_actors_and_ties :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 2, y = 2}, health = 50, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	// A wall of pools down the middle, the player standing in its gap: actors
	// never close an area, the hall stays one.
	for y in 1..=9 {
		if y == 5 { continue }
		testing.expect(t, ground_test_pour(&room, .Poison, {x = 6, y = y}).accepted)
	}
	wet := 0
	for value in room.ground.pool { if value > 0 { wet += 1 } }
	testing.expect_value(t, wet, 8)
	// Without him the two halves are as large: neither is the outside's.
	player.position = {x = 9, y = 5}
	testing.expect(t, ground_test_pour(&room, .Poison, {x = 6, y = 5}).accepted)
	wet = 0
	for value in room.ground.pool { if value > 0 { wet += 1 } }
	testing.expect_value(t, wet, 9)
	// A pool on one side breaks the tie: the other side, now the larger,
	// is the outside; the side poured on fills whole, the player's cell with it
	// (he is never poisoned).
	testing.expect(t, ground_test_pour(&room, .Poison, {x = 8, y = 1}).accepted)
	for y in 1..=9 { for x in 7..=11 {
		testing.expectf(t, ground_pool_at(&room, {x = x, y = y}) == 2, "%v dry", grid.Position{x = x, y = y})
	} }
	testing.expect_value(t, ground_test_potency(&room, PLAYER_ENTITY, .Poison), i32(0))
	testing.expect_value(t, ground_pool_at(&room, {x = 3, y = 5}), i32(0))
	// The same pours on a twin board give the same floor.
	twin_data: level.Level
	twin_player: Player
	twin := ground_test_room(t, &twin_data, &twin_player, {enemies = spawns[:]})
	defer level.destroy(&twin_data)
	defer destroy_room(&twin)
	for y in 1..=9 { if y != 5 { ground_test_pour(&twin, .Poison, {x = 6, y = y}) } }
	twin_player.position = {x = 9, y = 5}
	ground_test_pour(&twin, .Poison, {x = 6, y = 5})
	ground_test_pour(&twin, .Poison, {x = 8, y = 1})
	for value, index in room.ground.pool { testing.expect_value(t, twin.ground.pool[index], value) }
}

// A fire's arms grow a cell at each new window, 1 to 4, then it goes out at
// the fifth; an arm stops for good at a wall, cover or a blocking object.
@(test)
test_fire_grows_as_a_plus_and_goes_out_at_the_fifth_window :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 10, y = 8}, health = 50, attack = 1}}
	obstacles := [?]grid.Position{{x = 3, y = 2}}
	objects := [?]Grid_Object_Spawn{{kind = .Ice_Block, position = {x = 5, y = 5}}, {kind = .Barrel, position = {x = 3, y = 7}}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:], obstacles = obstacles[:], objects = objects[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect(t, ground_test_pour(&room, .Burn, {x = 3, y = 5}, 1).accepted)
	fire := &room.ground.fires[0]
	testing.expect(t, room.ground.fire_count == 1 && fire.stage == 0 && fire.arms == {})
	testing.expect(t, ground_burn_at(&room, {x = 3, y = 5}) == 1 && ground_burn_at(&room, {x = 3, y = 4}) == 0)
	// North stops at the cover after two, east at the ice block after one,
	// south at the barrel after one, west at the wall after two.
	expected := [4][Move_Direction]i32{{.North = 1, .East = 1, .South = 1, .West = 1}, {.North = 2, .East = 1, .South = 1, .West = 2},
		{.North = 2, .East = 1, .South = 1, .West = 2}, {.North = 2, .East = 1, .South = 1, .West = 2}}
	for window in 0..<4 {
		testing.expect(t, ground_test_window(t, &room))
		testing.expect_value(t, room.ground.fire_count, 1)
		testing.expect_value(t, fire.stage, i32(window+1))
		testing.expect_value(t, fire.arms, expected[window])
		// Moved away, the blockers leave the stopped arms where they stopped.
		if window == 2 {
			clear(&room.obstacles)
			room.objects[0].position = {x = 9, y = 1}
		}
	}
	testing.expect_value(t, ground_burn_at(&room, {x = 3, y = 3}), i32(1))
	testing.expect_value(t, ground_burn_at(&room, {x = 3, y = 2}), i32(0))
	testing.expect_value(t, ground_burn_at(&room, {x = 1, y = 5}), i32(1))
	testing.expect(t, ground_test_window(t, &room))
	testing.expect_value(t, room.ground.fire_count, 0)
	testing.expect_value(t, ground_burn_at(&room, {x = 3, y = 5}), i32(0))
	// A free hall: four cells each way.
	testing.expect(t, ground_test_pour(&room, .Burn, {x = 6, y = 3}, 1).accepted)
	for _ in 0..<4 { ground_test_window(t, &room) }
	testing.expect_value(t, room.ground.fires[0].arms, [Move_Direction]i32{.North = 2, .East = 4, .South = 4, .West = 4})
	reach := ground_fire_reach(&room, {x = 6, y = 3})
	testing.expect_value(t, reach.arms, room.ground.fires[0].arms)
}

// A fire catching an enemy gives its Bruciatura once, however many fires
// reach it; it bites from the next window on. Entering a burning cell gives
// it each time; the player is never touched.
@(test)
test_fire_burns_the_enemies_it_catches_and_those_who_enter :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 3, y = 3}, health = 50, attack = 1}, {position = {x = 10, y = 8}, health = 50, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	foe := enemy_entity(room.enemies[0].id)
	testing.expect(t, ground_test_pour(&room, .Burn, {x = 3, y = 5}, 1).accepted)
	testing.expect(t, ground_test_pour(&room, .Burn, {x = 5, y = 3}, 2).accepted)
	testing.expect(t, ground_test_window(t, &room))
	testing.expect_value(t, ground_test_potency(&room, foe, .Burn), i32(0))
	// Both reach it at the second window: the strongest, once, and no bite yet.
	testing.expect(t, ground_test_window(t, &room))
	count, last := ground_test_statuses(room.recent_events, foe, .Burn)
	testing.expect(t, count == 1 && last == 2)
	testing.expect_value(t, ground_test_potency(&room, foe, .Burn), i32(2))
	testing.expect_value(t, room.enemies[0].health, i32(50))
	for event in room.recent_events.events[:room.recent_events.count] {
		if event.kind == .Status_Applied { testing.expect_value(t, event.source, SYSTEM_ENTITY) }
	}
	// It stays put in the fire: the next window bites, and gives no more.
	testing.expect(t, ground_test_window(t, &room))
	testing.expect_value(t, room.enemies[0].health, i32(48))
	count, _ = ground_test_statuses(room.recent_events, foe, .Burn)
	testing.expect_value(t, count, 0)
	// The other one is shoved along the burning row: a dose per cell.
	other := enemy_entity(room.enemies[1].id)
	room.enemies[1].position = {x = 8, y = 3}
	shoved := ground_test_shove(&room, other, {x = 6, y = 3})
	count, last = ground_test_statuses(&shoved.events, other, .Burn)
	testing.expect(t, count == 2 && last == 4)
	// The player walks through fire untouched.
	player.position = {x = 4, y = 5}
	walk := make_action(.Move, PLAYER_ENTITY, cell_target({x = 1, y = 5}), .Walkable_Cell)
	testing.expect(t, add_effect(&walk, move_effect(PLAYER_ENTITY, {x = 1, y = 5})))
	walked := resolve_action(&room, &walk)
	testing.expect(t, walked.accepted)
	testing.expect_value(t, ground_test_potency(&room, PLAYER_ENTITY, .Burn), i32(0))
}

// The ground is the room's: it stays through the loot, a new room has none,
// and the endless lab keeps it until it is cleared.
@(test)
test_ground_lasts_as_long_as_its_room :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 3, y = 3}, health = 5, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	testing.expect(t, ground_test_pour(&room, .Poison, {x = 6, y = 4}).accepted)
	testing.expect(t, ground_test_pour(&room, .Burn, {x = 6, y = 6}, 1).accepted)
	kill := make_action(.Ability, PLAYER_ENTITY)
	testing.expect(t, add_effect(&kill, damage_effect(enemy_entity(room.enemies[0].id), 100)))
	testing.expect(t, resolve_action(&room, &kill).accepted)
	testing.expect_value(t, room.phase, Room_Phase.Loot)
	testing.expect(t, ground_pool_at(&room, {x = 6, y = 4}) == 2 && room.ground.fire_count == 1)
	destroy_room(&room)
	finish_deck_combat(&player.deck)
	ok: bool
	room, ok = create_room(&data, &player, {enemies = spawns[:]})
	testing.expect(t, ok)
	defer destroy_room(&room)
	testing.expect(t, ground_pool_at(&room, {x = 6, y = 4}) == 0 && room.ground.fire_count == 0 && len(room.ground.pool) == len(data.tiles.cells))
	room.endless = true
	testing.expect(t, ground_test_pour(&room, .Poison, {x = 6, y = 4}).accepted)
	kill = make_action(.Ability, PLAYER_ENTITY)
	testing.expect(t, add_effect(&kill, damage_effect(enemy_entity(room.enemies[0].id), 100)))
	testing.expect(t, resolve_action(&room, &kill).accepted)
	testing.expect(t, room.phase == .Combat && ground_pool_at(&room, {x = 6, y = 4}) == 2)
	clear_ground(&room)
	testing.expect(t, ground_pool_at(&room, {x = 6, y = 4}) == 0 && room.ground.fire_count == 0 && len(room.ground.pool) == len(data.tiles.cells))
}

// Played from the hand: thrown and landing (the board shows the ground from
// the landing), the energy and the window seconds paid, the upgrade and the
// tick each a stack more.
@(test)
test_ground_cards_play_from_the_hand :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {x = 10, y = 8}, health = 50, attack = 1}}
	room := ground_test_room(t, &data, &player, {enemies = spawns[:]})
	defer level.destroy(&data)
	defer destroy_room(&room)
	card := ground_test_card(t, &room, .Poison_Pool)
	play := play_card(&room, card.id, cell_target({x = 6, y = 3}))
	testing.expect_value(t, play.result, Card_Play_Result.Played)
	testing.expect_value(t, play.energy_before-play.energy_after, i32(1))
	testing.expect_value(t, room.player.tactical.cast_duration, f32(1))
	testing.expect_value(t, ground_pool_at(&room, {x = 6, y = 3}), i32(2))
	launched, landed := false, false
	for event in room.recent_events.events[:room.recent_events.count] {
		if event.card_definition != .Poison_Pool { continue }
		if event.kind == .Spell_Launched { launched = true; testing.expect(t, event.from_position == player.position && event.to_position == grid.Position{x = 6, y = 3}) }
		if event.kind == .Spell_Impact { landed = launched; testing.expect_value(t, event.to_position, grid.Position{x = 6, y = 3}) }
	}
	testing.expect(t, launched && landed)
	// Upgraded twice: 4; on the tick: one more.
	card = ground_test_card(t, &room, .Poison_Pool, 2)
	testing.expect_value(t, play_card(&room, card.id, cell_target({x = 7, y = 3})).result, Card_Play_Result.Played)
	testing.expect_value(t, ground_pool_at(&room, {x = 7, y = 3}), i32(4))
	card = ground_test_card(t, &room, .Poison_Pool)
	room.player.tactical.critical_next = true
	testing.expect_value(t, play_card(&room, card.id, cell_target({x = 5, y = 3})).result, Card_Play_Result.Played)
	testing.expect_value(t, ground_pool_at(&room, {x = 5, y = 3}), i32(3))
	card = ground_test_card(t, &room, .Wildfire, 1)
	fire := play_card(&room, card.id, cell_target({x = 6, y = 7}))
	testing.expect_value(t, fire.result, Card_Play_Result.Played)
	testing.expect_value(t, fire.energy_before-fire.energy_after, i32(2))
	testing.expect_value(t, room.player.tactical.cast_duration, f32(2))
	testing.expect(t, room.ground.fire_count == 1 && room.ground.fires[0].burn == 2 && room.ground.fires[0].center == grid.Position{x = 6, y = 7})
	// A blocked cell costs nothing.
	card = ground_test_card(t, &room, .Poison_Pool)
	blocked := play_card(&room, card.id, cell_target(player.position))
	testing.expect_value(t, blocked.result, Card_Play_Result.Compile_Failed)
	blocked = play_card(&room, card.id, cell_target({x = 6, y = 3}))
	testing.expect_value(t, blocked.result, Card_Play_Result.Compile_Failed)
	testing.expect_value(t, blocked.compile_error, Card_Compile_Error.Target_Blocked)
	testing.expect_value(t, room.player.deck.energy, room.player.deck.rules.max_energy)
}
