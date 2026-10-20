package game

import grid "../engine/grid"
import rng "../engine/rng"

// CANNA DA PESCA: a room-end tool. It is never drawn in a fight
// (begin_deck_combat leaves it in Exhaust, the zone nothing draws from) and
// never played as a card, yet it is a card of the run deck like any other: the
// deck view shows it, a rest or a shop upgrades it, a shop removes it. Once a
// tactical room is cleared (Loot: its last foe down) the player casts it from
// its own slot on a cell within FISHING_RANGE (the game's Chebyshev reach) in
// line of sight, by the cards' own targeting rules: free walkable floor as the
// Pozza di Veleno's (no cover, no object, nobody, not his own cell) and, the
// rod's own calls, never the exit, a trap, an item on the floor, a pool or a
// fire. The cell turns to water for the rest of the room and can be fished
// again. Each fishing is a catch: food (95%: one of five, healing a d4 of the
// run's dice, capped at his maximum; the die stays a d4 at every upgrade) or a
// card (5%: one of the tactical reward pool, by the rarity weights of the
// room's node, never the rod) added to the run deck; a deck with no room left
// for it gets food instead. The room's fishings are 1 + the rod's upgrade
// level, afresh in every room. The catches come from the room's own stream,
// seeded with the room: never from a clock. A run holds one rod at most: while
// its deck has one, no offer brings another (card_offer_exclusions).

FISHING_RANGE :: 3
// The food's die: a d4, whatever the rod's level.
FISHING_HEAL_SIDES :: i32(4)
// Out of a hundred catches, the cards.
FISHING_CARD_PERCENT :: u64(5)
FISHING_ROD_MAX_UPGRADE_LEVEL :: i32(5)
// A fishing turns one cell to water at most.
MAX_FISHING_WATERS :: 1+int(FISHING_ROD_MAX_UPGRADE_LEVEL)
FISHING_SEED_SALT :: u64(0x5EED_F15B_0B0B_BE55)

Fishing_Food :: enum u8 {Fish, Apple, Bread, Cheese, Meat}

fishing_food_name :: proc(food: Fishing_Food) -> string {
	switch food {
	case .Fish: return "PESCE"
	case .Apple: return "MELA"
	case .Bread: return "PANE"
	case .Cheese: return "FORMAGGIO"
	case .Meat: return "CARNE"
	}
	return ""
}

Fishing_State :: struct {
	// The fishings made in this room.
	casts: i32,
	// The cells turned to water, in the order they were.
	water: [MAX_FISHING_WATERS]grid.Position,
	water_count: int,
	// The room's own stream for its catches (begin_room_fishing).
	random: u64,
	// The run node the room stands for: a card caught is weighed as its
	// rewards are (card_rarity_weights).
	node_kind: Node_Kind,
	node_depth: int,
}

Fishing_Result :: enum {
	Invalid,
	// No rod in the run deck, or no cleared tactical room to fish.
	Not_Open,
	// The room's fishings are all made.
	Spent,
	Out_Of_Reach,
	// Out of sight, or not a cell the rod may be cast on.
	Blocked,
	Fished,
}

Fishing_Report :: struct {
	result: Fishing_Result,
	rod: Card_Instance,
	// A card caught (`added`, now in the run deck), or the food.
	card: bool,
	added: Card_Instance,
	food: Fishing_Food,
	// The food's d4, and the life it gave back (capped at the maximum).
	roll: Dice_Roll,
	healed: i32,
	// The cell turned to water by this cast (false: fished again).
	new_water: bool,
}

// A fresh room's fishing: no cast yet, no water, and its stream from the
// room's seed and the run's dice as the room begins (create_room).
@(private)
begin_room_fishing :: proc(player: ^Player, content: Room_Content) -> (state: Fishing_State) {
	seed := content.room_seed~FISHING_SEED_SALT
	if player != nil { seed ~= player.dice.random_state }
	state.random = mix_room_seed(seed)
	if state.random == 0 { state.random = FISHING_SEED_SALT }
	state.node_kind, state.node_depth = content.node_kind, max(content.node_depth, 0)
	return
}

// The rod the run deck holds (the most upgraded, were there more), if any.
fishing_rod :: proc(deck: ^Deck_State) -> (rod: Card_Instance, ok: bool) {
	if deck == nil { return }
	for card in deck.owned[:clamp(deck.owned_count, 0, MAX_OWNED_CARDS)] {
		if card.definition_id != .Fishing_Rod { continue }
		if !ok || card.upgrade_level > rod.upgrade_level { rod, ok = card, true }
	}
	return
}

// The room's fishings with the rod the deck holds: 1 + its upgrade level (0:
// no rod).
fishing_casts_allowed :: proc(room: ^Room) -> i32 {
	if room == nil || room.player == nil { return 0 }
	rod, held := fishing_rod(&room.player.deck)
	if !held || rod.upgrade_level < 0 || rod.upgrade_level > FISHING_ROD_MAX_UPGRADE_LEVEL { return 0 }
	definition, _ := card_definition_by_id(.Fishing_Rod)
	return card_effect_amount(definition.effects[0], rod.upgrade_level)
}

fishing_casts_left :: proc(room: ^Room) -> i32 {
	if room == nil { return 0 }
	return max(0, fishing_casts_allowed(room)-room.fishing.casts)
}

// A cleared tactical room and a rod to fish it with.
fishing_room_open :: proc(room: ^Room) -> bool {
	return room != nil && room.player != nil && room.level_data != nil && room.phase == .Loot &&
	       fishing_casts_allowed(room) > 0
}

fishing_cell_is_water :: proc(room: ^Room, cell: grid.Position) -> bool {
	if room == nil { return false }
	for water in room.fishing.water[:clamp(room.fishing.water_count, 0, MAX_FISHING_WATERS)] {
		if water == cell { return true }
	}
	return false
}

// A cell the rod may be cast on: the Pozza di Veleno's free floor (walkable,
// no cover, no object of any kind, nobody on it, not the player's own cell)
// and, further, never the exit, a trap, an item lying there, a pool or a fire.
// Water already there is fished again.
@(private = "file")
fishing_cell_is_free :: proc(room: ^Room, cell: grid.Position) -> bool {
	if room == nil || room.player == nil || !base_cell_is_walkable(room, cell) || cell_blocks_movement(room, cell) ||
	   cell == room.player.position || cell == room.exit_position || ground_pool_at(room, cell) > 0 || ground_burn_at(room, cell) > 0 {
		return false
	}
	if _, found := object_index_at(room, cell); found { return false }
	if _, found := trap_index_at(room, cell); found { return false }
	if _, found := enemy_index_at(room, cell); found { return false }
	for item in room.loot { if item.position == cell { return false } }
	return true
}

// Why the rod may not fish `cell` now (Fished: it may).
fishing_target_error :: proc(room: ^Room, cell: grid.Position) -> Fishing_Result {
	if room == nil || room.player == nil || room.level_data == nil { return .Invalid }
	if !fishing_room_open(room) { return .Not_Open }
	if fishing_casts_left(room) <= 0 { return .Spent }
	definition, _ := card_definition_by_id(.Fishing_Rod)
	query := evaluate_target_query(room, PLAYER_ENTITY, definition.targeting, {anchor = cell, has_anchor = true})
	#partial switch query.error {
	case .None:
	case .Anchor_Out_Of_Range, .Anchor_Out_Of_Bounds: return .Out_Of_Reach
	case: return .Blocked
	}
	if !fishing_cell_is_free(room, cell) { return .Blocked }
	if !fishing_cell_is_water(room, cell) && room.fishing.water_count >= MAX_FISHING_WATERS { return .Blocked }
	return .Fished
}

// The catch's first draw from the room's stream: a card or food.
fishing_catch_is_card :: proc(random: ^u64) -> bool {
	return rng.below_state(random, 100) < FISHING_CARD_PERCENT
}

// The food's kind, from the stream after a catch that is no card.
fishing_catch_food :: proc(random: ^u64) -> Fishing_Food {
	return Fishing_Food(rng.below_state(random, u64(len(Fishing_Food))))
}

// One fishing of the rod at `cell`, all or nothing. Its events, in order:
// Fish_Cast, Fish_Bite, Fish_Caught, then for food its d4 (Dice_Rolled) and
// the cure.
fish_with_rod :: proc(room: ^Room, cell: grid.Position) -> (report: Fishing_Report) {
	report.result = fishing_target_error(room, cell)
	if report.result != .Fished { return }
	report.rod, _ = fishing_rod(&room.player.deck)
	random := room.fishing.random if room.fishing.random != 0 else FISHING_SEED_SALT
	deck := room.player.deck
	dice := room.player.dice
	if fishing_catch_is_card(&random) {
		node := Run_Node{kind = room.fishing.node_kind, depth = room.fishing.node_depth}
		choice: [1]Card_Id
		// Never the rod: the run holds it already.
		if generate_weighted_card_choices(&random, &node, choice[:], &room.player.m8_profile, {.Fishing_Rod}) {
			report.added, report.card = add_owned_card(&deck, choice[0])
		}
	}
	if !report.card {
		report.food = fishing_catch_food(&random)
		rolled: bool
		report.roll, rolled = roll_dice_pool(&dice, 1, FISHING_HEAL_SIDES)
		if !rolled { report.result = .Invalid; return }
	}
	clear_event_log(room.recent_events)
	origin := room.player.position
	report.new_water = !fishing_cell_is_water(room, cell)
	rod := report.rod
	thrown := Game_Event{kind = .Fish_Cast, source = PLAYER_ENTITY, target = PLAYER_ENTITY, from_position = origin, to_position = cell,
		card_id = rod.id, card_definition = .Fishing_Rod, card_upgrade_level = rod.upgrade_level, card_lifetime = rod.lifetime,
		amount = fishing_casts_left(room)-1, duration = 1 if report.new_water else 0}
	record_event(room.recent_events, thrown)
	bite := thrown
	bite.kind, bite.from_position = .Fish_Bite, cell
	record_event(room.recent_events, bite)
	caught := Game_Event{kind = .Fish_Caught, source = PLAYER_ENTITY, target = PLAYER_ENTITY, from_position = cell, to_position = origin,
		card_id = rod.id, card_definition = .Fishing_Rod, card_upgrade_level = rod.upgrade_level, duration = i32(report.food)}
	if report.card {
		caught.card_id, caught.card_definition, caught.card_upgrade_level, caught.duration = report.added.id, report.added.definition_id, 0, 0
	}
	record_event(room.recent_events, caught)
	if report.card {
		room.player.deck = deck
	} else {
		room.player.dice = dice
		// Its die over the window as the other rolls show; the cast's number
		// varies the throw of a room's catches (dice_event_visual_seed).
		record_event(room.recent_events, {kind = .Dice_Rolled, source = PLAYER_ENTITY, target = PLAYER_ENTITY, from_position = origin,
			to_position = origin, amount = report.roll.total, dice_roll = report.roll, card_id = rod.id, card_definition = .Fishing_Rod,
			card_upgrade_level = rod.upgrade_level, card_lifetime = rod.lifetime, pulse_count = room.pulse_count+u64(room.fishing.casts)})
		action := make_action(.Collect, PLAYER_ENTITY, entity_target(PLAYER_ENTITY), .Self)
		added := add_effect(&action, heal_effect(PLAYER_ENTITY, report.roll.total))
		assert(added)
		cure := resolve_action(room, &action)
		report.healed = cure.healing_done
		append_event_log(room.recent_events, &cure.events)
	}
	room.fishing.random = random
	room.fishing.casts += 1
	if report.new_water {
		room.fishing.water[room.fishing.water_count] = cell
		room.fishing.water_count += 1
	}
	// He faces the water he fishes.
	if dx, dy := cell.x-origin.x, cell.y-origin.y; abs(dx) >= abs(dy) {
		room.player.tactical.facing = .East if dx > 0 else .West
	} else {
		room.player.tactical.facing = .South if dy > 0 else .North
	}
	return
}
