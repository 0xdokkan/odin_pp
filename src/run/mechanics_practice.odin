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

// The arenas of the lab: the flat one every card is tried in, and the one with
// heights (a plateau up a stair, a pillar, a spiral hill) to try the heights in
// (F3 switches between them).
Mechanics_Lab_Arena :: enum { Flat, Heights }

// The open arena: walls only around the edge, the player in the middle and
// the (unused) exit tucked into a corner.
mechanics_lab_level :: proc(arena := Mechanics_Lab_Arena.Flat) -> (level.Level, bool) {
	rows: [MECHANICS_LAB_HEIGHT]string
	for y in 0..<MECHANICS_LAB_HEIGHT {
		row := strings.builder_make(context.temp_allocator)
		for x in 0..<MECHANICS_LAB_WIDTH {
			switch {
			case x == 0 || y == 0 || x == MECHANICS_LAB_WIDTH-1 || y == MECHANICS_LAB_HEIGHT-1: strings.write_byte(&row, '#')
			case x == MECHANICS_LAB_WIDTH/2 && y == MECHANICS_LAB_HEIGHT/2: strings.write_byte(&row, '@')
			case x == MECHANICS_LAB_WIDTH-2 && y == MECHANICS_LAB_HEIGHT-2: strings.write_byte(&row, '>')
			case: strings.write_byte(&row, '.')
			}
		}
		rows[y] = strings.to_string(row)
	}
	data, error, _ := level.from_ascii(rows[:])
	if error != .None { return data, false }
	if arena == .Heights { mechanics_lab_raise(&data) }
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
	spawns := [?]game.Enemy_Spawn{
		{position = {4, 4}, health = 12, attack = 2, archetype = .Chaser},
		// In the arena of heights the archer waits up on the plateau.
		{position = {MECHANICS_LAB_WIDTH-5, 4} if which == .Flat else {MECHANICS_LAB_WIDTH-5, 6}, health = 10, attack = 2, archetype = .Archer},
		{position = {MECHANICS_LAB_WIDTH/2, MECHANICS_LAB_HEIGHT-4}, health = 18, attack = 3, archetype = .Brute},
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
