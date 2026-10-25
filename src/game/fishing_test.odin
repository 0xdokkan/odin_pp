package game

import "core:testing"
import grid "../engine/grid"
import level "../level"

// A walled room, the player in its middle (5, 5) with 20 of 30 health, a wall
// at (5, 3) and the exit at (7, 7); the rod in the deck at `rod` (-1: none).
// With no spawns it is cleared from the start.
FISHING_TEST_ROWS :: [?]string{
	"###########",
	"#.........#",
	"#.........#",
	"#....#....#",
	"#.........#",
	"#....@....#",
	"#.........#",
	"#......>..#",
	"#.........#",
	"#.........#",
	"###########",
}

fishing_test_room :: proc(t: ^testing.T, data: ^level.Level, player: ^Player, spawns: []Enemy_Spawn = nil, rod := i32(0),
	content: Room_Content = {}) -> Room {
	rows := FISHING_TEST_ROWS
	parsed: level.Parse_Error
	data^, parsed, _ = level.from_ascii(rows[:])
	testing.expect_value(t, parsed, level.Parse_Error.None)
	player^ = create_test_player(t)
	player.stats.max_health, player.health = 30, 20
	config := DEFAULT_TACTICAL_CONFIG
	config.vision_size = 0
	testing.expect(t, configure_tactical(player, config))
	if rod >= 0 {
		_, added := add_owned_card(&player.deck, .Fishing_Rod, rod)
		testing.expect(t, added)
	}
	room_content := content
	room_content.enemies = spawns
	room, ok := create_room(data, player, room_content)
	testing.expect(t, ok)
	return room
}

// A room stream whose next catch is a card, or else food.
fishing_test_stream :: proc(card: bool) -> u64 {
	for seed in u64(1)..<u64(100_000) {
		random := seed
		if fishing_catch_is_card(&random) == card { return seed }
	}
	return 0
}

@(test)
test_fishing_rod_is_an_uncommon_tactical_room_tool_with_five_upgrades :: proc(t: ^testing.T) {
	testing.expect(t, validate_card_definitions())
	definition, found := card_definition_by_id(.Fishing_Rod)
	testing.expect(t, found && definition.name == "Canna da Pesca")
	testing.expect_value(t, definition.rarity, Card_Rarity.Uncommon)
	testing.expect_value(t, definition.cost, i32(0))
	testing.expect_value(t, definition.targeting.rule, Target_Rule.Walkable_Cell)
	testing.expect_value(t, definition.targeting.cast_range, Targeting_Range{.Chebyshev, 1, FISHING_RANGE})
	testing.expect_value(t, definition.targeting.shape, Target_Shape.Single)
	testing.expect(t, definition.targeting.requires_line_of_sight)
	testing.expect(t, card_is_room_tool(.Fishing_Rod))
	for id in Card_Id { testing.expect_value(t, card_is_room_tool(id), id == .Fishing_Rod) }
	testing.expect_value(t, tactical_card_time_cost(.Fishing_Rod), f32(0))
	testing.expect_value(t, card_max_upgrade_level(.Fishing_Rod), i32(5))
	// No dice card: its heal stays a d4 at every level.
	testing.expect_value(t, card_dice_count(.Fishing_Rod), 0)
	testing.expect_value(t, card_die_sides(.Fishing_Rod, 5), i32(0))
	for upgrade in i32(0)..=5 {
		card := Card_Instance{id = 1, definition_id = .Fishing_Rod, upgrade_level = upgrade}
		testing.expect_value(t, card_can_upgrade(card), upgrade < 5)
		testing.expect_value(t, card_effect_amount(definition.effects[0], upgrade), 1+upgrade)
	}
	testing.expect(t, !validate_card_instance({id = 1, definition_id = .Fishing_Rod, upgrade_level = 6}))
	node := Run_Node{kind = .Combat, depth = 4}
	testing.expect(t, card_offer_weight(definition, &node) > 0)
	// Never on the tick: no critical changes it.
	room: Room
	player: Player
	room.player = &player
	player.tactical.critical_card = true
	action := make_action(.Card, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
	action.effects[0], action.effect_count = {kind = .Fish, target = PLAYER_ENTITY, amount = 2}, 1
	tactical_critical_scale(&room, &action)
	testing.expect_value(t, action.effects[0].amount, i32(2))
	testing.expect(t, !effect_is_valid(&room, action.effects[0]))
}

// The rod waits out every fight in Exhaust: never in the hand or the draw,
// never drawn by a refill or a refocus, kept as an owned card; it is no card
// to play, and fishing is refused while the fight lasts.
@(test)
test_fishing_rod_waits_in_exhaust_and_is_never_drawn :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	spawns := [?]Enemy_Spawn{{position = {1, 1}, health = 50, attack = 1}}
	room := fishing_test_room(t, &data, &player, spawns[:])
	defer level.destroy(&data)
	defer destroy_room(&room)
	deck := &player.deck
	testing.expect(t, deck.combat_active && validate_deck_state(deck))
	testing.expect_value(t, deck.exhaust_count, 1)
	testing.expect_value(t, deck.exhaust_pile[0].definition_id, Card_Id.Fishing_Rod)
	testing.expect_value(t, deck_exhausted_count(deck), 0)
	testing.expect_value(t, deck.draw_count+deck.hand_count, deck.owned_count-1)
	rod, held := fishing_rod(deck)
	testing.expect(t, held)
	for _ in 0..<6 {
		for card in deck.hand[:deck.hand_count] { testing.expect(t, card.definition_id != .Fishing_Rod) }
		for card in deck.draw_pile[:deck.draw_count] { testing.expect(t, card.definition_id != .Fishing_Rod) }
		for card in deck.discard_pile[:deck.discard_count] { testing.expect(t, card.definition_id != .Fishing_Rod) }
		// Every card of the hand to the discard, then a refill drawing the rest
		// (the discard reshuffled in, never Exhaust).
		for deck.hand_count > 0 { _, _ = discard_hand_card(deck, 0) }
		draw_to_hand_size(deck)
		testing.expect(t, validate_deck_state(deck))
	}
	testing.expect(t, card_effect_amount_is_targeted_never(&room, rod))
	testing.expect_value(t, fish_with_rod(&room, {6, 5}).result, Fishing_Result.Not_Open)
	finish_deck_combat(deck)
	_, still_owned := owned_card_index_by_id(deck, rod.id)
	testing.expect(t, still_owned && validate_deck_state(deck))
}

// The rod is never played as a card: its targeting refuses it everywhere.
card_effect_amount_is_targeted_never :: proc(room: ^Room, rod: Card_Instance) -> bool {
	evaluation := evaluate_card_targeting(room, rod, {anchor = {6, 5}, has_anchor = true})
	_, err := compile_card_action(room, rod, cell_target({6, 5}))
	return evaluation.error == .Invalid_Phase && err == .Invalid_Phase
}

// Fishing requires a cleared room and a rod. A fight, missing rod or room
// already left refuses the interaction.
@(test)
test_fishing_opens_only_in_a_cleared_tactical_room_with_a_rod :: proc(t: ^testing.T) {

	{
		data: level.Level
		player: Player
		room := fishing_test_room(t, &data, &player, rod = -1)
		defer level.destroy(&data)
		defer destroy_room(&room)
		testing.expect(t, !fishing_room_open(&room))
		testing.expect_value(t, fishing_casts_allowed(&room), i32(0))
	}
	{
		// The last foe falls: the room is cleared and the rod opens.
		data: level.Level
		player: Player
		spawns := [?]Enemy_Spawn{{position = {5, 6}, health = 1, attack = 1}}
		room := fishing_test_room(t, &data, &player, spawns[:])
		defer level.destroy(&data)
		defer destroy_room(&room)
		testing.expect(t, !fishing_room_open(&room))
		testing.expect_value(t, try_move_player(&room, .South), Action_Result.Combat_Ended)
		testing.expect_value(t, room.phase, Room_Phase.Loot)
		testing.expect(t, fishing_room_open(&room) && !player.deck.combat_active)
		testing.expect_value(t, fish_with_rod(&room, {4, 5}).result, Fishing_Result.Fished)
	}
	{
		// Left through the exit: no more.
		data: level.Level
		player: Player
		room := fishing_test_room(t, &data, &player)
		defer level.destroy(&data)
		defer destroy_room(&room)
		testing.expect(t, fishing_room_open(&room))
		for direction in ([?]Move_Direction{.East, .East, .South}) { testing.expect_value(t, try_move_player(&room, direction), Action_Result.Moved) }
		testing.expect_value(t, try_move_player(&room, .South), Action_Result.Room_Completed)
		testing.expect(t, !fishing_room_open(&room))
		testing.expect_value(t, fish_with_rod(&room, {6, 6}).result, Fishing_Result.Not_Open)
	}
}

// Free floor within three cells (the game's Chebyshev reach) in line of sight:
// never his own cell, past a wall, the exit, a trap, cover, an object, an item
// on the floor, a pool or a fire; water already there is fished again.
@(test)
test_fishing_targets_free_cells_in_reach_and_sight :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	content := Room_Content{
		traps = []Trap_Spawn{{position = {3, 5}, damage = 1}},
		obstacles = []grid.Position{{7, 3}},
		objects = []Grid_Object_Spawn{{kind = .Barrel, position = {4, 7}}},
	}
	room := fishing_test_room(t, &data, &player, rod = 2, content = content)
	defer level.destroy(&data)
	defer destroy_room(&room)
	testing.expect_value(t, fishing_target_error(&room, {8, 5}), Fishing_Result.Fished)
	testing.expect_value(t, fishing_target_error(&room, {8, 8}), Fishing_Result.Fished)
	testing.expect_value(t, fishing_target_error(&room, {9, 5}), Fishing_Result.Out_Of_Reach)
	testing.expect_value(t, fishing_target_error(&room, {5, 1}), Fishing_Result.Out_Of_Reach)
	testing.expect_value(t, fishing_target_error(&room, {5, 5}), Fishing_Result.Out_Of_Reach)
	testing.expect_value(t, fishing_target_error(&room, {-1, 5}), Fishing_Result.Out_Of_Reach)
	// Behind the wall at (5, 3), and the wall itself.
	testing.expect_value(t, fishing_target_error(&room, {5, 2}), Fishing_Result.Blocked)
	testing.expect_value(t, fishing_target_error(&room, {5, 3}), Fishing_Result.Blocked)
	testing.expect_value(t, fishing_target_error(&room, {7, 7}), Fishing_Result.Blocked)
	testing.expect_value(t, fishing_target_error(&room, {3, 5}), Fishing_Result.Blocked)
	testing.expect_value(t, fishing_target_error(&room, {7, 3}), Fishing_Result.Blocked)
	testing.expect_value(t, fishing_target_error(&room, {4, 7}), Fishing_Result.Blocked)
	append(&room.loot, Loot{position = {6, 6}, kind = .Gold, amount = 1})
	testing.expect_value(t, fishing_target_error(&room, {6, 6}), Fishing_Result.Blocked)
	pool, _ := ground_index(&room, {4, 4})
	room.ground.pool[pool] = 2
	testing.expect_value(t, fishing_target_error(&room, {4, 4}), Fishing_Result.Blocked)
	room.ground.fires[0] = {id = 1, center = {6, 4}, burn = 1}
	room.ground.fire_count = 1
	testing.expect_value(t, fishing_target_error(&room, {6, 4}), Fishing_Result.Blocked)
	// Water already there is fished again.
	testing.expect_value(t, fish_with_rod(&room, {8, 5}).result, Fishing_Result.Fished)
	testing.expect(t, fishing_cell_is_water(&room, {8, 5}))
	testing.expect_value(t, fishing_target_error(&room, {8, 5}), Fishing_Result.Fished)
}

// 1 + the rod's level fishings a room, then no more; the same water fished
// again is no new water; the next room starts them afresh.
@(test)
test_fishing_counts_one_plus_the_rods_level_each_room :: proc(t: ^testing.T) {
	for level_index in i32(0)..=FISHING_ROD_MAX_UPGRADE_LEVEL {
		data: level.Level
		player: Player
		room := fishing_test_room(t, &data, &player, rod = level_index)
		testing.expect_value(t, fishing_casts_allowed(&room), 1+level_index)
		cells := [?]grid.Position{{6, 5}, {4, 5}, {6, 6}, {4, 6}, {5, 7}, {6, 7}}
		for index in 0..<int(1+level_index) {
			testing.expect_value(t, fishing_casts_left(&room), 1+level_index-i32(index))
			report := fish_with_rod(&room, cells[index])
			testing.expect_value(t, report.result, Fishing_Result.Fished)
			testing.expect(t, report.new_water)
		}
		testing.expect_value(t, room.fishing.water_count, int(1+level_index))
		testing.expect_value(t, fish_with_rod(&room, cells[0]).result, Fishing_Result.Spent)
		testing.expect_value(t, room.fishing.casts, 1+level_index)
		destroy_room(&room)
		level.destroy(&data)
	}
	// The same water twice, then a new room.
	data: level.Level
	player: Player
	room := fishing_test_room(t, &data, &player, rod = 1)
	defer level.destroy(&data)
	testing.expect(t, fish_with_rod(&room, {6, 5}).new_water)
	again := fish_with_rod(&room, {6, 5})
	testing.expect(t, again.result == .Fished && !again.new_water)
	testing.expect_value(t, room.fishing.water_count, 1)
	testing.expect_value(t, fishing_casts_left(&room), i32(0))
	destroy_room(&room)
	next, ok := create_room(&data, &player, {})
	testing.expect(t, ok)
	defer destroy_room(&next)
	testing.expect_value(t, fishing_casts_left(&next), i32(2))
	testing.expect_value(t, next.fishing.water_count, 0)
}

// Food: its cast, the bite and the catch, then a d4 rolled on the run's dice
// and that much life back, capped at the maximum; the d4 stays a d4 at +5.
@(test)
test_fishing_food_heals_a_d4_shown_as_a_roll :: proc(t: ^testing.T) {
	for rod in ([2]i32{0, 5}) {
		data: level.Level
		player: Player
		room := fishing_test_room(t, &data, &player, rod = rod)
		room.fishing.random = fishing_test_stream(false)
		dice_before := player.dice
		report := fish_with_rod(&room, {7, 5})
		testing.expect_value(t, report.result, Fishing_Result.Fished)
		testing.expect(t, !report.card)
		testing.expect(t, report.roll.count == 1 && report.roll.sides == FISHING_HEAL_SIDES)
		testing.expect(t, report.roll.total >= 1 && report.roll.total <= 4)
		testing.expect_value(t, player.health, 20+report.roll.total)
		testing.expect_value(t, report.healed, report.roll.total)
		testing.expect(t, player.dice.roll_count == dice_before.roll_count+1)
		events := room.recent_events.events[:room.recent_events.count]
		testing.expect_value(t, len(events), 5)
		kinds := [5]Game_Event_Kind{.Fish_Cast, .Fish_Bite, .Fish_Caught, .Dice_Rolled, .Healed}
		for kind, index in kinds { testing.expect_value(t, events[index].kind, kind) }
		testing.expect(t, events[0].from_position == player.position && events[0].to_position == {7, 5})
		testing.expect(t, events[0].card_definition == .Fishing_Rod && events[0].duration == 1 && events[0].amount == rod)
		testing.expect(t, events[1].from_position == {7, 5} && events[1].to_position == {7, 5})
		testing.expect(t, events[2].card_definition == .Fishing_Rod && events[2].duration == i32(report.food))
		testing.expect(t, events[3].dice_roll == report.roll && events[3].amount == report.roll.total && events[3].card_definition == .Fishing_Rod)
		testing.expect_value(t, player.tactical.facing, Move_Direction.East)
		destroy_room(&room)
		level.destroy(&data)
	}
	// At full health: the die still rolls, no life comes back.
	data: level.Level
	player: Player
	room := fishing_test_room(t, &data, &player)
	defer level.destroy(&data)
	defer destroy_room(&room)
	player.health = player.stats.max_health
	room.fishing.random = fishing_test_stream(false)
	report := fish_with_rod(&room, {5, 7})
	testing.expect(t, report.result == .Fished && !report.card && report.healed == 0)
	testing.expect_value(t, player.health, player.stats.max_health)
	testing.expect_value(t, room.recent_events.count, 4)
	testing.expect_value(t, player.tactical.facing, Move_Direction.South)
}

// About one catch in twenty is a card of the tactical reward pool, never the
// rod, never a Scopa card, into the run deck; a deck with no room left gets
// food instead; the same stream catches the same.
@(test)
test_fishing_catches_cards_one_in_twenty_never_the_rod :: proc(t: ^testing.T) {
	data: level.Level
	player: Player
	room := fishing_test_room(t, &data, &player, rod = 5)
	defer level.destroy(&data)
	defer destroy_room(&room)
	cards, foods := 0, 0
	for seed in u64(1)..=2000 {
		trial := room
		trial_events: Event_Log
		trial.recent_events = &trial_events
		trial_player := player
		trial.player = &trial_player
		trial.fishing = {random = seed}
		owned := trial_player.deck.owned_count
		report := fish_with_rod(&trial, {6, 5})
		testing.expect_value(t, report.result, Fishing_Result.Fished)
		if report.card {
			cards += 1
			testing.expect(t, report.added.definition_id != .Fishing_Rod && !card_is_scopa(report.added.definition_id))
			definition, _ := card_definition_by_id(report.added.definition_id)
			testing.expect(t, !definition.temporary_only)
			testing.expect_value(t, trial_player.deck.owned_count, owned+1)
			testing.expect(t, validate_deck_state(&trial_player.deck))
			testing.expect_value(t, trial.recent_events.count, 3)
			testing.expect(t, trial.recent_events.events[2].card_definition == report.added.definition_id &&
				trial.recent_events.events[2].card_id == report.added.id)
		} else {
			foods += 1
			testing.expect_value(t, trial_player.deck.owned_count, owned)
		}
	}
	testing.expectf(t, cards >= 60 && cards <= 140, "%d cards in 2000 catches", cards)
	testing.expect_value(t, cards+foods, 2000)
	// The same stream, the same catch.
	card_stream := fishing_test_stream(true)
	first_player, second_player := player, player
	first, second := room, room
	first_events, second_events: Event_Log
	first.recent_events, second.recent_events = &first_events, &second_events
	first.player, second.player = &first_player, &second_player
	first.fishing.random, second.fishing.random = card_stream, card_stream
	a, b := fish_with_rod(&first, {6, 5}), fish_with_rod(&second, {6, 5})
	testing.expect(t, a.card && b.card && a.added == b.added)
	// A full deck: food.
	full_player := player
	for full_player.deck.owned_count < MAX_OWNED_CARDS { _, _ = add_owned_card(&full_player.deck, .Strike) }
	full := room
	full_events: Event_Log
	full.recent_events = &full_events
	full.player = &full_player
	full.fishing.random = card_stream
	report := fish_with_rod(&full, {6, 5})
	testing.expect(t, report.result == .Fished && !report.card && report.roll.count == 1)
	testing.expect_value(t, full_player.deck.owned_count, MAX_OWNED_CARDS)
}

// The room's stream comes from its seed and the run's dice, never a clock: the
// same give the same, another room another; it keeps the node it stands for.
@(test)
test_fishing_streams_are_the_rooms_own :: proc(t: ^testing.T) {
	player := create_test_player(t)
	content := Room_Content{node_kind = .Elite, node_depth = 7, room_seed = 0xC0FFEE}
	a, b := begin_room_fishing(&player, content), begin_room_fishing(&player, content)
	testing.expect(t, a.random != 0 && a.random == b.random)
	testing.expect(t, a.node_kind == .Elite && a.node_depth == 7 && a.casts == 0 && a.water_count == 0)
	other := content
	other.room_seed += 1
	testing.expect(t, begin_room_fishing(&player, other).random != a.random)
	player.dice.random_state ~= 0x55
	testing.expect(t, begin_room_fishing(&player, content).random != a.random)
}

// One rod a run: while the deck holds one, no offer brings another (rewards,
// the shop, the Armory, a catch); without it, it can be offered again.
@(test)
test_one_rod_a_run_leaves_it_out_of_every_offer :: proc(t: ^testing.T) {
	deck: Deck_State
	testing.expect(t, initialize_starter_deck(&deck))
	testing.expect_value(t, card_offer_exclusions(&deck), Card_Offer_Exclusions{})
	rod, _ := add_owned_card(&deck, .Fishing_Rod)
	testing.expect_value(t, card_offer_exclusions(&deck), Card_Offer_Exclusions{.Fishing_Rod})
	testing.expect_value(t, card_offer_exclusions(&deck, rod.id), Card_Offer_Exclusions{})
	definition, _ := card_definition_by_id(.Fishing_Rod)
	node := Run_Node{kind = .Shop, depth = 9}
	testing.expect(t, card_offer_weight(definition, &node) > 0)
	testing.expect_value(t, card_offer_weight(definition, &node, nil, card_offer_exclusions(&deck)), u64(0))
	// Every other card is still offered: the whole tactical pool, but the rod.
	profile := M8_Profile{ring_wins = 3}
	storage: [int(Card_Id.Count)]Card_Id
	all := storage[:offerable_card_count(&node, &profile, {.Fishing_Rod})]
	random := u64(1)
	testing.expect(t, generate_weighted_card_choices(&random, &node, all, &profile, {.Fishing_Rod}))
	for id in all { testing.expect(t, id != .Fishing_Rod) }
	// Rewards and the shop, over runs whose deck holds the rod or not.
	offered, offered_with_rod := 0, 0
	for seed in u64(0)..<u64(160) {
		for with_rod in ([2]bool{false, true}) {
			run, run_ok := create_run(REWARD_TEST_PLAYER_STATS, REWARD_TEST_RUN_CONFIG, seed)
			testing.expect(t, run_ok)
			if with_rod { _, _ = add_owned_card(&run.player.deck, .Fishing_Rod) }
			testing.expect_value(t, finish_room(&run, .Complete), Run_Transition.Reward)
			for choice in available_card_rewards(&run) {
				if choice != .Fishing_Rod { continue }
				if with_rod { offered_with_rod += 1 } else { offered += 1 }
			}
			testing.expect(t, validate_run_state(&run))
			for &route_node in run.route_map.nodes {
				if route_node.kind != .Shop { continue }
				shop_random := u64(seed+1)
				shop, shop_ok := build_shop_state_for_node(&run, &route_node, &shop_random)
				if !shop_ok { continue }
				for offer in shop.offers[:shop.offer_count] {
					if offer.definition_id != .Fishing_Rod { continue }
					if with_rod { offered_with_rod += 1 } else { offered += 1 }
				}
			}
			destroy_run(&run)
		}
	}
	testing.expect(t, offered > 0)
	testing.expect_value(t, offered_with_rod, 0)
}

// REGRESSION: the Armory's offer is checked again after its card is taken; a
// rod it offered and the deck now holds is the one that offer gave, so the
// check must not leave it out (the event would never resolve).
@(test)
test_the_armorys_rod_is_taken_and_its_offer_still_checks :: proc(t: ^testing.T) {
	player, _ := create_player(SPECIAL_NODE_TEST_PLAYER_STATS)
	found_seed := u64(0)
	found_node := INVALID_NODE_ID
	for seed := u64(1); seed < u64(40_000) && found_seed == 0; seed += 1 {
		route_map, map_ok := generate_run_map(SPECIAL_NODE_BEHAVIOR_TEST_CONFIG, seed)
		if !map_ok { continue }
		for &route_node in route_map.nodes {
			if route_node.kind != .Event || route_node.depth != 1 { continue }
			state, ok := build_route_event_state(&player, &route_node)
			if ok && state.kind == .Forgotten_Armory && state.offered_card == .Fishing_Rod { found_seed, found_node = seed, route_node.id }
		}
		destroy_run_map(&route_map)
	}
	testing.expectf(t, found_seed != 0, "no Armory offers the rod")
	if found_seed == 0 { return }
	run, run_ok := create_run(SPECIAL_NODE_TEST_PLAYER_STATS, SPECIAL_NODE_BEHAVIOR_TEST_CONFIG, found_seed)
	testing.expect(t, run_ok)
	defer destroy_run(&run)
	testing.expect_value(t, finish_room(&run, .Complete), Run_Transition.Reward)
	testing.expect_value(t, skip_card_reward(&run), Card_Reward_Result.Skipped)
	testing.expect_value(t, enter_node(&run, found_node), Node_Entry_Result.Event)
	testing.expect_value(t, run.route_event.offered_card, Card_Id.Fishing_Rod)
	testing.expect_value(t, resolve_route_event(&run, .Primary), Special_Node_Result.Event_Resolved)
	_, held := fishing_rod(&run.player.deck)
	testing.expect(t, held && validate_run_state(&run))
	// With a rod in the deck already, that Armory offers another card.
	again, again_ok := create_run(SPECIAL_NODE_TEST_PLAYER_STATS, SPECIAL_NODE_BEHAVIOR_TEST_CONFIG, found_seed)
	testing.expect(t, again_ok)
	defer destroy_run(&again)
	_, _ = add_owned_card(&again.player.deck, .Fishing_Rod)
	testing.expect_value(t, finish_room(&again, .Complete), Run_Transition.Reward)
	testing.expect_value(t, skip_card_reward(&again), Card_Reward_Result.Skipped)
	testing.expect_value(t, enter_node(&again, found_node), Node_Entry_Result.Event)
	testing.expect(t, again.route_event.offered_card != .Fishing_Rod)
	testing.expect_value(t, resolve_route_event(&again, .Primary), Special_Node_Result.Event_Resolved)
}
