package run

import "core:fmt"
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
// mountain, the one with a cave's rooms, and the one with layers (F3 goes from one to the next). Right after the
// flat one, the first person cards' (docs/piano-prima-persona.md, Fase 1): pillars, niches and slanted walls to
// shoot off, low covers, a corridor of five cells, an archer up on a rise and a brute, with its own deck.
Mechanics_Lab_Arena :: enum { Flat, First_Person, Heights, Structures, Mountain, Cave, Layers, Lifts }

// The first person arena's deck: First Person Shooter, the cards of the other weapons as they come (Fasi 2, 4 e 6),
// and the Canna da Pesca for a cleared arena, as in the others.
MECHANICS_LAB_FIRST_PERSON_DECK :: [2]game.Card_Id{.First_Person, .Fishing_Rod}

// The first person arena, on the 23x17 board with the player at (11,8):
// - a wall along y = 1 with two niches in it, at (4,1) and (18,1);
// - four pillars, at (6,4), (16,4), (6,11) and (16,11), and a slanted wall in each side, three cells on a
//   diagonal: (4,6) to (2,8) and (18,6) to (20,8), for shots off a wall at more than one angle;
// - low covers (MECHANICS_LAB_FIRST_PERSON_COVERS);
// - a corridor of five cells, (2..6,14), shut at its west end and open to the east, for a grapple;
// - a rise of 2 steps at x 9..13, y 2..3, a step of 1 up to it at (11,4), where the archer waits.
MECHANICS_LAB_FIRST_PERSON_COVERS :: [3]grid.Position{{x = 8, y = 9}, {x = 14, y = 9}, {x = 11, y = 12}}
MECHANICS_LAB_FIRST_PERSON_ARCHER :: grid.Position{x = 11, y = 2}
MECHANICS_LAB_FIRST_PERSON_BRUTE :: grid.Position{x = 17, y = 9}

mechanics_lab_first_person :: proc(data: ^level.Level) -> bool {
	walls: [dynamic]grid.Position
	walls.allocator = context.temp_allocator
	for x in 1..=21 { if x != 4 && x != 18 { append(&walls, grid.Position{x = x, y = 1}) } }
	append(&walls, grid.Position{x = 6, y = 4}, grid.Position{x = 16, y = 4}, grid.Position{x = 6, y = 11}, grid.Position{x = 16, y = 11})
	append(&walls, grid.Position{x = 4, y = 6}, grid.Position{x = 3, y = 7}, grid.Position{x = 2, y = 8})
	append(&walls, grid.Position{x = 18, y = 6}, grid.Position{x = 19, y = 7}, grid.Position{x = 20, y = 8})
	for x in 1..=6 { append(&walls, grid.Position{x = x, y = 13}, grid.Position{x = x, y = 15}) }
	append(&walls, grid.Position{x = 1, y = 14})
	for cell in walls { if !level.set_tile(data, cell, {kind = .Wall}) { return false } }
	for y in 2..=3 { for x in 9..=13 { if !level.set_height(data, {x = x, y = y}, 2) { return false } } }
	return level.set_height(data, {x = 11, y = 4}, 1)
}

// The arena of structures is larger, to hold all of them with room between.
MECHANICS_LAB_STRUCTURES_WIDTH :: 41
MECHANICS_LAB_STRUCTURES_HEIGHT :: 29

// The arena of the mountain holds the whole mountain (level.MOUNTAIN_HALF cells each way from its centre)
// to the east of the player's place, with a free lane round it.
MECHANICS_LAB_MOUNTAIN_WIDTH :: 47
MECHANICS_LAB_MOUNTAIN_HEIGHT :: 25
MECHANICS_LAB_MOUNTAIN_CENTER :: grid.Position{x = 35, y = 12}

// The arena of the cave: its plan (level/cave.odin) with a ring of rock round it.
MECHANICS_LAB_CAVE_SEED :: u64(2026)
MECHANICS_LAB_CAVE_WIDTH :: level.CAVE_WIDTH+2
MECHANICS_LAB_CAVE_HEIGHT :: level.CAVE_HEIGHT+2

// The arena of the layers (Fase 3 of docs/piano-profondita.md): a road under a bridge and its ramps, a hill with a
// cave through it, a ladder up the hill's cliff (mechanics_lab_layers).
MECHANICS_LAB_LAYERS_WIDTH :: 46
MECHANICS_LAB_LAYERS_HEIGHT :: 29
MECHANICS_LAB_LAYERS_START :: grid.Position{x = 8, y = 22}
// The arena of the lifts (Fase 7 of docs/piano-profondita.md): a plateau with a lift up its cliff, a hall under it
// down a shaft, a gate across the hall's way out that opens from inside (mechanics_lab_lifts).
MECHANICS_LAB_LIFTS_WIDTH :: 32
MECHANICS_LAB_LIFTS_HEIGHT :: 20
MECHANICS_LAB_LIFTS_START :: grid.Position{x = 4, y = 15}

mechanics_lab_size :: proc(arena: Mechanics_Lab_Arena) -> (width, height: int) {
	if arena == .Layers { return MECHANICS_LAB_LAYERS_WIDTH, MECHANICS_LAB_LAYERS_HEIGHT }
	if arena == .Lifts { return MECHANICS_LAB_LIFTS_WIDTH, MECHANICS_LAB_LIFTS_HEIGHT }
	if arena == .Cave { return MECHANICS_LAB_CAVE_WIDTH, MECHANICS_LAB_CAVE_HEIGHT }
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
	{.Cottage, {x = 4, y = 3}, 0, false}, {.Hut, {x = 12, y = 3}, 0, false}, {.Temple, {x = 28, y = 3}, 0, false},
	{.Cart, {x = 4, y = 11}, 0, false}, {.Fountain, {x = 8, y = 11}, 0, false}, {.Statue, {x = 12, y = 11}, 0, false}, {.Machine, {x = 16, y = 11}, 0, false},
	{.Ruin, {x = 34, y = 13}, 0, false}, {.Pen, {x = 28, y = 17}, 0, false},
	{.Cottage, {x = 4, y = 22}, 0, false}, {.Cottage, {x = 10, y = 22}, 1, false}, {.Cottage, {x = 16, y = 22}, 2, false}, {.Cottage, {x = 22, y = 22}, 3, true},
}

// The arenas' retouches (Fase 6 of docs/piano-profondita.md): what the map editor saved for each, loaded at the start
// (mapeditor.load_all) and put over the arena the code makes. None: the arena as the code makes it.
mechanics_lab_edits: [Mechanics_Lab_Arena]level.Map_Edits

// The open arena: walls only around the edge, the player in the middle and
// the (unused) exit tucked into a corner. With `retouched`, its retouches over it (mechanics_lab_edits).
mechanics_lab_level :: proc(arena := Mechanics_Lab_Arena.Flat, retouched := true) -> (level.Level, bool) {
	width, height := mechanics_lab_size(arena)
	rows: [MECHANICS_LAB_STRUCTURES_HEIGHT]string
	cave := level.cave_plan(MECHANICS_LAB_CAVE_SEED)
	start := grid.Position{x = width/2, y = height/2}
	if arena == .Layers { start = MECHANICS_LAB_LAYERS_START }
	if arena == .Lifts { start = MECHANICS_LAB_LIFTS_START }
	for y in 0..<height {
		row := strings.builder_make(context.temp_allocator)
		for x in 0..<width {
			if arena == .Cave {
				switch {
				case x == 0 || y == 0 || x == width-1 || y == height-1: strings.write_byte(&row, '#')
				case x == width-2 && y == height-2: strings.write_byte(&row, '>')
				case x-1 == cave.arrival.x && y-1 == cave.arrival.y: strings.write_byte(&row, '@')
				case: strings.write_byte(&row, cave.rows[y-1][x-1])
				}
				continue
			}
			switch {
			case x == 0 || y == 0 || x == width-1 || y == height-1: strings.write_byte(&row, '#')
			case x == start.x && y == start.y: strings.write_byte(&row, '@')
			case x == width-2 && y == height-2: strings.write_byte(&row, '>')
			case: strings.write_byte(&row, '.')
			}
		}
		rows[y] = strings.to_string(row)
	}
	data, error, _ := level.from_ascii(rows[:height])
	if error != .None { return data, false }
	if arena == .Heights { mechanics_lab_raise(&data) }
	if arena == .First_Person && !mechanics_lab_first_person(&data) {
		level.destroy(&data)
		return {}, false
	}
	if arena == .Layers && !mechanics_lab_layers(&data) {
		level.destroy(&data)
		return {}, false
	}
	if arena == .Lifts && !mechanics_lab_lifts(&data) {
		level.destroy(&data)
		return {}, false
	}
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
	// Retouches that do not go on it (an old file's, of another size, or one painted by hand that breaks the layers'
	// rule) are left out: the arena as the code makes it.
	if retouched && level.map_edits_any(&mechanics_lab_edits[arena]) && !level.map_edits_apply_checked(&data, &mechanics_lab_edits[arena]) {
		fmt.eprintfln("mappe: the retouches of the %v arena do not go on it: left out", arena)
		level.destroy(&data)
		return mechanics_lab_level(arena, retouched = false)
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
	for x in 12..=14 { for y in 7..=9 { level.set_height(data, {x = x, y = y}, i32(x-11)) } }
	for x in 15..=19 { for y in 5..=11 { level.set_height(data, {x = x, y = y}, 4) } }
	level.set_height(data, {x = 6, y = 4}, 8)
	spiral := [9]grid.Position{{x = 3, y = 10}, {x = 4, y = 10}, {x = 5, y = 10}, {x = 5, y = 11}, {x = 5, y = 12}, {x = 4, y = 12}, {x = 3, y = 12}, {x = 3, y = 11}, {x = 4, y = 11}}
	for cell, step in spiral { level.set_height(data, cell, i32(step)+1) }
}

// The arena of the layers, on the 46x29 board with the player at (8,22):
// - a road (x 16..18) goes under a bridge on layer +1, 12 steps up, that crosses it along y 13..15 from x 14 to
//   20; two ramps of eleven steps lead onto it, up from x 3 to 13 and down from x 21 to 31;
// - a hill of 14 steps (x 35..43, y 3..11) has a cave on layer -1 through it, at 0, along y = 7, with a room of
//   3x3 in its middle (x 38..40, y 6..8): its mouths open at (34,7) and (44,7);
// - a ladder climbs the hill's west cliff, from (34,4) to (35,4).
mechanics_lab_layers :: proc(data: ^level.Level) -> bool {
	for y in 13..=15 {
		for x in 3..=13 { if !level.set_height(data, {x = x, y = y}, i32(x-2)) { return false } }
		for x in 21..=31 { if !level.set_height(data, {x = x, y = y}, i32(32-x)) { return false } }
		for x in 14..=20 {
			bridge := grid.Position{x = x, y = y, layer = 1}
			if !level.set_tile(data, bridge, {kind = .Floor}) || !level.set_height(data, bridge, level.LAYER_SPACING) { return false }
		}
	}
	for y in 3..=11 { for x in 35..=43 { if !level.set_height(data, {x = x, y = y}, 14) { return false } } }
	for x in 35..=43 { if !level.set_tile(data, {x = x, y = 7, layer = -1}, {kind = .Floor}) { return false } }
	for y in 6..=8 { for x in 38..=40 { if !level.set_tile(data, {x = x, y = y, layer = -1}, {kind = .Floor}) { return false } } }
	if !level.add_ladder(data, {x = 34, y = 4}, {x = 35, y = 4}) { return false }
	error, _ := level.check_layers(data)
	return error == .None
}

// The arena of the lifts, on the 32x20 board with the player at (4,15):
// - a plateau of 14 steps (x 12..25, y 2..12) with a lift up its west cliff, from (11,10) to a landing over it on
//   layer +1, a step from the top, its platform waiting at the top;
// - a hall on layer -1 under it, at 0 (x 16..21, y 5..9), down a shaft from (18,5) on the top, its platform waiting
//   at the bottom;
// - a tunnel from the hall east along y = 7 (x 22..25) to the open ground at (26,7), with a gate across it at
//   (24,7) that opens from the hall's side, from (23,7).
mechanics_lab_lifts :: proc(data: ^level.Level) -> bool {
	for y in 2..=12 { for x in 12..=25 { if !level.set_height(data, {x = x, y = y}, 14) { return false } } }
	for y in 5..=9 { for x in 16..=21 { if !level.set_tile(data, {x = x, y = y, layer = -1}, {kind = .Floor}) { return false } } }
	for x in 22..=25 { if !level.set_tile(data, {x = x, y = 7, layer = -1}, {kind = .Floor}) { return false } }
	cliff_top := grid.Position{x = 11, y = 10, layer = 1}
	if !level.set_tile(data, cliff_top, {kind = .Floor}) || !level.set_height(data, cliff_top, 14) { return false }
	if !level.add_lift(data, {x = 11, y = 10}, cliff_top, 1) { return false }
	if !level.add_lift(data, {x = 18, y = 5}, {x = 18, y = 5, layer = -1}, 1) { return false }
	if !level.add_gate(data, {x = 24, y = 7, layer = -1}, {x = 23, y = 7, layer = -1}) { return false }
	error, _ := level.check_layers(data)
	return error == .None
}

// Replaces `data` with the arena and builds its endless room around `player`.
create_mechanics_lab_room :: proc(data: ^level.Level, player: ^game.Player, config: game.Tactical_Config,
	which := Mechanics_Lab_Arena.Flat) -> (room: game.Room, ok: bool) {
	arena, built := mechanics_lab_level(which)
	if !built { return }
	game.finish_deck_combat(&player.deck)
	// The first person arena has its own deck, all of it in hand too (but for the Canna da Pesca).
	lab_deck, first_person_deck := MECHANICS_LAB_DECK, MECHANICS_LAB_FIRST_PERSON_DECK
	deck, rules := lab_deck[:], MECHANICS_LAB_RULES
	if which == .First_Person { deck, rules.hand_size = first_person_deck[:], len(first_person_deck)-1 }
	if !game.initialize_empty_deck(&player.deck, rules, MECHANICS_LAB_DECK_SEED) { level.destroy(&arena); return }
	for id in deck {
		if _, added := game.add_owned_card(&player.deck, id); !added { level.destroy(&arena); return }
	}
	level.destroy(data)
	data^ = arena
	player.floor_secrets = {}
	// Three first arrivals, well away from the middle.
	width, height := mechanics_lab_size(which)
	spawns := [?]game.Enemy_Spawn{
		{position = {x = 4, y = 4}, health = 12, attack = 2, archetype = .Chaser},
		// In the arena of heights the archer waits up on the plateau.
		{position = {x = width-5, y = 4} if which == .Flat else {x = width-5, y = 6}, health = 10, attack = 2, archetype = .Archer},
		{position = {x = width/2, y = height-4}, health = 18, attack = 3, archetype = .Brute},
	}
	// In the first person arena the archer waits up on the rise, the brute beside the east cover.
	if which == .First_Person {
		spawns[0].position, spawns[1].position, spawns[2].position = {x = 4, y = 10}, MECHANICS_LAB_FIRST_PERSON_ARCHER, MECHANICS_LAB_FIRST_PERSON_BRUTE
	}
	// In the arena of structures they wait in the open, away from the buildings.
	if which == .Structures {
		spawns[0].position, spawns[1].position, spawns[2].position = {x = 37, y = 3}, {x = 37, y = 10}, {x = 20, y = 26}
	}
	// In the arena of the cave the foes wait in its rooms, as the plan has them.
	if which == .Cave {
		cave := level.cave_plan(MECHANICS_LAB_CAVE_SEED)
		for g in 0..<min(3, cave.groups) { spawns[g].position = {x = cave.anchors[g].x+1, y = cave.anchors[g].y+1} }
		for g in cave.groups..<3 { spawns[g].position = grid.offset(cave.secret, 0, 1) if g == 2 else {x = cave.anchors[0].x+1, y = cave.anchors[0].y+2} }
	}
	// In the arena of the mountain the archer waits at the summit (sturdy enough to survive being pushed off),
	// the others on the open ground beside it.
	if which == .Mountain {
		summit := level.mountain_summit()
		spawns[0].position = {x = 4, y = 4}
		spawns[1].position = grid.offset(MECHANICS_LAB_MOUNTAIN_CENTER, summit.x+1, summit.y)
		spawns[1].health = 18
		spawns[2].position = {x = width/2, y = height-3}
	}
	// In the arena of the lifts: one in the hall under the plateau, one on its top, one on the open ground.
	if which == .Lifts {
		spawns[0].position = {x = 19, y = 7, layer = -1}
		spawns[1].position = {x = 22, y = 4}
		spawns[2].position = {x = 6, y = 6}
	}
	// In the arena of the layers a foe on each: in the cave's room, on the bridge's south edge (sturdy enough
	// to survive a fall off it), on the road south of the bridge.
	if which == .Layers {
		spawns[0].position = {x = 39, y = 7, layer = -1}
		spawns[1].position = {x = 19, y = 15, layer = 1}
		spawns[1].health = 18
		spawns[2].position = {x = 17, y = 19}
	}
	covers := MECHANICS_LAB_FIRST_PERSON_COVERS
	room, ok = game.create_room(data, player, {enemies = spawns[:], obstacles = covers[:] if which == .First_Person else nil})
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
