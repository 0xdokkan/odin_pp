package run

import "core:strings"
import game "../game"
import level "../level"
import render "../render"

// PROVA MECCANICHE: a sandbox for trying mechanics one at a time. A large
// arena with no cover, a deck made only of the cards under test (one
// Movimento Ombra, one of each card of Phase 2: Pozza di Veleno, Incendio,
// Deflect, Feretro, Dado del Destino, Lama Velenosa, the Lazzo and the Canna
// da Pesca of Phase 3, the Pinball and the First Person Shooter of Phase 4)
// and enemies that never stop coming (game/sandbox.odin). F7 clears the arena
// at once for the rod (mechanics_lab_begin_fishing); F5 brings the fight
// back. It never touches the profile, gives no rewards and has no exit to
// walk to.
MECHANICS_LAB_WIDTH :: 23
MECHANICS_LAB_HEIGHT :: 17
MECHANICS_LAB_DECK :: [11]game.Card_Id{.Shadow_Step, .Poison_Pool, .Wildfire, .Deflect, .Coffin, .Fate_Dice, .Venom_Blade, .Lasso,
	.Pinball, .First_Person, .Fishing_Rod}
// The whole deck in hand, every card under test at once (ten: more than the
// game's hand ever holds, game.deck_hand_limit, so they overlap there,
// render.tactical_hand_card_bounds), but for the Canna da Pesca: it never
// comes to hand (it waits in Exhaust for a cleared room).
MECHANICS_LAB_RULES :: game.Deck_Rules{hand_size = len(MECHANICS_LAB_DECK)-1, max_energy = 12, energy_regen_per_pulse = 3}
#assert(len(MECHANICS_LAB_DECK)-1 <= game.MAX_HAND_CAPACITY)
MECHANICS_LAB_DECK_SEED :: u64(0x7E57_1AB)

// The open arena: walls only around the edge, the player in the middle and
// the (unused) exit tucked into a corner.
mechanics_lab_level :: proc() -> (level.Level, bool) {
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
	return data, error == .None
}

// Replaces `data` with the arena and builds its endless room around `player`.
create_mechanics_lab_room :: proc(data: ^level.Level, player: ^game.Player, config: game.Tactical_Config) -> (room: game.Room, ok: bool) {
	arena, built := mechanics_lab_level()
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
		{position = {MECHANICS_LAB_WIDTH-5, 4}, health = 10, attack = 2, archetype = .Archer},
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
	room, ok := create_mechanics_lab_room(&rs.level_data, &rs.run_state.player, rs.options.tactical)
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
