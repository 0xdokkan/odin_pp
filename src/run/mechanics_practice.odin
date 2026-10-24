package run

import "core:strings"
import game "../game"
import grid "../engine/grid"
import level "../level"
import render "../render"

// PROVA MECCANICHE: a sandbox for trying mechanics one at a time. A large
// arena with no cover, a deck made only of the cards under test (one of each:
// Bomb Marley, Inondazione, Cannone, Incendio, Buco Nero, Dinosauro, Dado del
// Destino, the Lazzo and the Canna da Pesca, the Pinball and the First Person
// Shooter; the Cannone laser is what the Cannone becomes at its second upgrade;
// Pozza di Veleno, Deflect and Feretro left it for the three new cards)
// and enemies that never stop coming (game/sandbox.odin). F7 clears the arena
// at once for the rod (mechanics_lab_begin_fishing); F5 brings the fight
// back. It never touches the profile, gives no rewards and has no exit to
// walk to.
MECHANICS_LAB_WIDTH :: 23
MECHANICS_LAB_HEIGHT :: 17
MECHANICS_LAB_DECK :: [11]game.Card_Id{.Marley_Party, .Flood_Wave, .Field_Cannon, .Wildfire, .Devouring_Hole, .Dino_Ride, .Fate_Dice, .Lasso,
	.Pinball, .First_Person, .Fishing_Rod}
// The whole deck in hand, every card under test at once (ten: more than the
// game's hand ever holds, game.deck_hand_limit, so they overlap there,
// render.tactical_hand_card_bounds), but for the Canna da Pesca: it never
// comes to hand (it waits in Exhaust for a cleared room).
MECHANICS_LAB_RULES :: game.Deck_Rules{hand_size = len(MECHANICS_LAB_DECK)-1, max_energy = 12, energy_regen_per_pulse = 3}
#assert(len(MECHANICS_LAB_DECK)-1 <= game.MAX_HAND_CAPACITY)
MECHANICS_LAB_DECK_SEED :: u64(0x7E57_1AB)

// The arenas of the lab: the flat one every card is tried in, the one with heights
// (a plateau up a stair, a pillar, a spiral hill) to try the heights in, the
// one with the catalog of structures, and the one with the Snow biome's spiral
// mountain (F3 goes from one to the next).
Mechanics_Lab_Arena :: enum { Flat, Heights, Structures, Mountain }

// The arena of structures is larger, to hold all of them with room between.
MECHANICS_LAB_STRUCTURES_WIDTH :: 41
MECHANICS_LAB_STRUCTURES_HEIGHT :: 29

// The arena of the mountain holds the whole mountain (level.MOUNTAIN_HALF cells each way from its centre)
// to the east of the player's place, with a free lane round it.
MECHANICS_LAB_MOUNTAIN_WIDTH :: 47
MECHANICS_LAB_MOUNTAIN_HEIGHT :: 25
MECHANICS_LAB_MOUNTAIN_CENTER :: grid.Position{35, 12}

mechanics_lab_size :: proc(arena: Mechanics_Lab_Arena) -> (width, height: int) {
	if arena == .Structures { return MECHANICS_LAB_STRUCTURES_WIDTH, MECHANICS_LAB_STRUCTURES_HEIGHT }
	if arena == .Mountain { return MECHANICS_LAB_MOUNTAIN_WIDTH, MECHANICS_LAB_MOUNTAIN_HEIGHT }
	return MECHANICS_LAB_WIDTH, MECHANICS_LAB_HEIGHT
}

// The next arena in F3's turn.
mechanics_lab_next_arena :: proc(arena: Mechanics_Lab_Arena) -> Mechanics_Lab_Arena {
	return Mechanics_Lab_Arena((int(arena)+1)%len(Mechanics_Lab_Arena))
}

// What the arena of structures holds: the three buildings, the five complex objects and
// the pen, and the cottage in each of its four turns (the last one mirrored).
Lab_Structure :: struct { id: level.Structure_Id, origin: grid.Position, rotation: u8, mirror: bool }
MECHANICS_LAB_STRUCTURES := [?]Lab_Structure{
	{.Cottage, {4, 3}, 0, false}, {.Hut, {12, 3}, 0, false}, {.Temple, {28, 3}, 0, false},
	{.Cart, {4, 11}, 0, false}, {.Fountain, {8, 11}, 0, false}, {.Statue, {12, 11}, 0, false}, {.Machine, {16, 11}, 0, false},
	{.Ruin, {34, 13}, 0, false}, {.Pen, {28, 17}, 0, false},
	{.Cottage, {4, 22}, 0, false}, {.Cottage, {10, 22}, 1, false}, {.Cottage, {16, 22}, 2, false}, {.Cottage, {22, 22}, 3, true},
}

// The open arena: walls only around the edge, the player in the middle and
// the (unused) exit tucked into a corner.
mechanics_lab_level :: proc(arena := Mechanics_Lab_Arena.Flat) -> (level.Level, bool) {
	width, height := mechanics_lab_size(arena)
	rows: [MECHANICS_LAB_STRUCTURES_HEIGHT]string
	for y in 0..<height {
		row := strings.builder_make(context.temp_allocator)
		for x in 0..<width {
			switch {
			case x == 0 || y == 0 || x == width-1 || y == height-1: strings.write_byte(&row, '#')
			case x == width/2 && y == height/2: strings.write_byte(&row, '@')
			case x == width-2 && y == height-2: strings.write_byte(&row, '>')
			case: strings.write_byte(&row, '.')
			}
		}
		rows[y] = strings.to_string(row)
	}
	data, error, _ := level.from_ascii(rows[:height])
	if error != .None { return data, false }
	if arena == .Heights { mechanics_lab_raise(&data) }
	if arena == .Mountain && !level.mountain_stamp(&data, MECHANICS_LAB_MOUNTAIN_CENTER) {
		level.destroy(&data)
		return {}, false
	}
	if arena == .Structures {
		for placed in MECHANICS_LAB_STRUCTURES {
			if _, err := level.place_structure(&data, placed.id, placed.origin, placed.rotation, placed.mirror); err != .None {
				level.destroy(&data)
				return {}, false
			}
		}
	}
	return data, true
}

// The arena of heights, on the 23x17 board with the player at (11,8):
// - a plateau of 4 steps at x 15..19, y 5..11, reached by a stair of three
//   (x 12..14, y 7..9: 1, 2, 3) from the player's side; its other sides are cliffs;
// - a pillar of 8 steps at (6,4): a wall to anyone who walks;
// - a spiral hill at x 3..5, y 10..12: a path of one step each round a top of 9,
//   with a cliff between every two turns of it.
mechanics_lab_raise :: proc(data: ^level.Level) {
	for x in 12..=14 { for y in 7..=9 { level.set_height(data, {x, y}, i32(x-11)) } }
	for x in 15..=19 { for y in 5..=11 { level.set_height(data, {x, y}, 4) } }
	level.set_height(data, {6, 4}, 8)
	spiral := [9]grid.Position{{3, 10}, {4, 10}, {5, 10}, {5, 11}, {5, 12}, {4, 12}, {3, 12}, {3, 11}, {4, 11}}
	for cell, step in spiral { level.set_height(data, cell, i32(step)+1) }
}

// Replaces `data` with the arena and builds its endless room around `player`.
create_mechanics_lab_room :: proc(data: ^level.Level, player: ^game.Player, config: game.Tactical_Config,
	which := Mechanics_Lab_Arena.Flat) -> (room: game.Room, ok: bool) {
	arena, built := mechanics_lab_level(which)
	if !built { return }
	game.finish_deck_combat(&player.deck)
	if !game.initialize_empty_deck(&player.deck, MECHANICS_LAB_RULES, MECHANICS_LAB_DECK_SEED) { level.destroy(&arena); return }
	for id in MECHANICS_LAB_DECK {
		if _, added := game.add_owned_card(&player.deck, id); !added { level.destroy(&arena); return }
	}
	level.destroy(data)
	data^ = arena
	player.floor_secrets = {}
	// Three first arrivals, well away from the middle.
	width, height := mechanics_lab_size(which)
	spawns := [?]game.Enemy_Spawn{
		{position = {4, 4}, health = 12, attack = 2, archetype = .Chaser},
		// In the arena of heights the archer waits up on the plateau.
		{position = {width-5, 4} if which == .Flat else {width-5, 6}, health = 10, attack = 2, archetype = .Archer},
		{position = {width/2, height-4}, health = 18, attack = 3, archetype = .Brute},
	}
	// In the arena of structures they wait in the open, away from the buildings.
	if which == .Structures {
		spawns[0].position, spawns[1].position, spawns[2].position = {37, 3}, {37, 10}, {20, 26}
	}
	// In the arena of the mountain the archer waits at the summit (sturdy enough to survive being pushed off),
	// the others on the open ground beside it.
	if which == .Mountain {
		summit := level.mountain_summit()
		spawns[0].position = {4, 4}
		spawns[1].position = {MECHANICS_LAB_MOUNTAIN_CENTER.x+summit.x+1, MECHANICS_LAB_MOUNTAIN_CENTER.y+summit.y}
		spawns[1].health = 18
		spawns[2].position = {width/2, height-3}
	}
	room, ok = game.create_room(data, player, {enemies = spawns[:]})
	if !ok { return }
	room.endless = true
	// No fog: every arrival is in plain sight. Each action lasts its cost in
	// real time, so its animation has room to play.
	lab := config
	lab.vision_size = 0
	lab.timed_actions = true
	if !game.configure_tactical_room(&room, lab) { game.destroy_room(&room); return {}, false }
	return room, true
}

prepare_mechanics_lab :: proc(rs: ^Roguelike_Session) -> bool {
	if rs.room_created {
		game.destroy_room(&rs.room)
		rs.room_created = false
	}
	room, ok := create_mechanics_lab_room(&rs.level_data, &rs.run_state.player, rs.options.tactical, rs.lab_arena)
	if !ok { return false }
	rs.room = room
	rs.room_created = true
	rs.sandbox = game.begin_sandbox(rs.run_seed)
	return true
}

// F7 in PROVA MECCANICHE: the arena cleared at once, as a room is when its
// last foe falls (game.sandbox_clear_for_fishing), every foe falling on the
// board; the Canna da Pesca's slot opens, with a fresh room's fishings and no
// water. F7 again starts the fishing afresh; F5 brings the fight back. Never
// while the board still shows the player's own action.
mechanics_lab_clear_for_fishing :: proc(room: ^game.Room, renderer: ^render.Renderer) -> bool {
	if room == nil || renderer == nil || render.renderer_blocks_player_input(renderer) { return false }
	before := render.capture_room_presentation(room)
	if _, cleared := game.sandbox_clear_for_fishing(room); !cleared { return false }
	// What the board still shows of the fight goes: the falls (and the loot
	// they leave in reach) are all it shows.
	render.clear_event_animations(renderer)
	after := render.capture_room_presentation(room)
	if room.recent_events.count > 0 { _ = render.begin_renderer_event_timeline(renderer, before, room.recent_events, &after) }
	return true
}

mechanics_lab_begin_fishing :: proc(rs: ^Roguelike_Session) -> bool {
	if rs.run_state.phase != .In_Room || rs.tactical_controller.paused || !mechanics_lab_clear_for_fishing(&rs.room, &rs.iso_renderer) { return false }
	clear_card_interaction(&rs.card_interaction)
	clear_gameplay_command_buffer(&rs.gameplay_buffer)
	return true
}
