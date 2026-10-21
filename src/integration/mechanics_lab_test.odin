package integration
import run_session "../run"
import application "../application"


import "core:testing"
import game "../game"
import level "../level"
import render "../render"

@(test)
test_mechanics_lab_is_an_open_endless_arena_with_the_cards_under_test :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player, created := game.create_player(run_session.DEMO_PLAYER_STATS)
	testing.expect(t, created)
	room, built := run_session.create_mechanics_lab_room(&data, &player, game.DEFAULT_TACTICAL_CONFIG)
	testing.expect(t, built)
	defer game.destroy_room(&room)
	testing.expect(t, room.endless)
	testing.expect_value(t, room.phase, game.Room_Phase.Combat)
	testing.expect_value(t, player.tactical.config.vision_size, 0)
	// Each action lasts its cost in real time here.
	testing.expect(t, player.tactical.config.timed_actions)
	testing.expect_value(t, data.tiles.width, run_session.MECHANICS_LAB_WIDTH)
	testing.expect_value(t, data.tiles.height, run_session.MECHANICS_LAB_HEIGHT)
	// No cover: every cell inside the border is walkable floor.
	for y in 1..<run_session.MECHANICS_LAB_HEIGHT-1 {
		for x in 1..<run_session.MECHANICS_LAB_WIDTH-1 {
			tile, inside := level.tile_at(&data, {x, y})
			testing.expect(t, inside && level.is_walkable(tile.kind))
		}
	}
	testing.expect(t, len(room.objects) == 0 && len(room.traps) == 0)
	// The deck: one of each card under test (Bomb Marley, Inondazione, the six
	// of Phase 2 that stay, the Lazzo, the Canna da Pesca, the Pinball and the
	// First Person Shooter); all in hand
	// (ten: more than the game's hand ever holds, all the room a hand has) but
	// the rod, which waits in Exhaust for a cleared room.
	testing.expect_value(t, player.deck.owned_count, len(run_session.MECHANICS_LAB_DECK))
	testing.expect_value(t, len(run_session.MECHANICS_LAB_DECK)-1, game.MAX_HAND_CAPACITY)
	for id in ([?]game.Card_Id{.Bomb_Marley, .Flood, .Poison_Pool, .Wildfire, .Deflect, .Coffin, .Fate_Dice, .Lasso, .Fishing_Rod,
		.Pinball, .First_Person}) {
		copies := 0
		for card in player.deck.owned[:player.deck.owned_count] { if card.definition_id == id { copies += 1 } }
		testing.expectf(t, copies == 1, "%v: %d copies", id, copies)
	}
	testing.expect_value(t, player.deck.hand_count, game.MAX_HAND_CAPACITY)
	testing.expect_value(t, game.deck_hand_limit(&player.deck), game.MAX_HAND_CAPACITY)
	testing.expect_value(t, player.deck.exhaust_count, 1)
	testing.expect_value(t, player.deck.exhaust_pile[0].definition_id, game.Card_Id.Fishing_Rod)
	for card in player.deck.hand[:player.deck.hand_count] { testing.expect(t, card.definition_id != .Fishing_Rod) }

}

// F7 clears the arena as a room's last fall clears it: the fight ends, the
// deck is put away, nobody arrives any more and the exit stays shut; the rod
// fishes there, and F7 again starts its fishing afresh.
@(test)
test_mechanics_lab_f7_clears_the_arena_for_the_rod :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player, created := game.create_player(run_session.DEMO_PLAYER_STATS)
	testing.expect(t, created)
	room, built := run_session.create_mechanics_lab_room(&data, &player, game.DEFAULT_TACTICAL_CONFIG)
	testing.expect(t, built)
	defer game.destroy_room(&room)
	testing.expect(t, !game.fishing_room_open(&room))
	// The banner's words, which the board's labels keep clear of as they are
	// drawn (render.mechanics_lab_banner_bounds): F7 among its keys, F10 when
	// it was opened from the menu.
	renderer := new(render.Renderer)
	defer free(renderer)
	render.set_mechanics_lab(renderer, true, true)
	testing.expect_value(t, string(render.mechanics_lab_banner_detail(renderer, &room)),
		"NEMICI 3/6  /  F5 RICOMINCIA  /  F6 INTENTI: HUD + TERRENO  /  F7 PESCA  /  F10 MENU")
	render.set_mechanics_lab(renderer, true)
	testing.expect_value(t, string(render.mechanics_lab_banner_detail(renderer, &room)),
		"NEMICI 3/6  /  F5 RICOMINCIA  /  F6 INTENTI: HUD + TERRENO  /  F7 PESCA")
	enemies := len(room.enemies)
	report, cleared := game.sandbox_clear_for_fishing(&room)
	testing.expect(t, cleared)
	testing.expect_value(t, report.enemies_defeated, enemies)
	testing.expect_value(t, room.phase, game.Room_Phase.Loot)
	testing.expect_value(t, len(room.enemies), 0)
	testing.expect(t, room.endless && !player.deck.combat_active && game.validate_deck_state(&player.deck))
	testing.expect(t, game.fishing_room_open(&room))
	testing.expect_value(t, game.fishing_casts_left(&room), i32(1))
	testing.expect_value(t, string(render.mechanics_lab_banner_detail(renderer, &room)),
		"ARENA LIBERA  /  PESCA 1/1  /  F7 DA CAPO  /  F5 RICOMINCIA")
	sandbox := game.begin_sandbox(7)
	_, spawned := game.sandbox_tick(&room, &sandbox, 10)
	testing.expect(t, !spawned)
	// The rod fishes a cell beside him; the room's one fishing is then spent.
	water := game.add_position(player.position, {2, 0})
	testing.expect_value(t, game.fish_with_rod(&room, water).result, game.Fishing_Result.Fished)
	testing.expect_value(t, game.fishing_target_error(&room, water), game.Fishing_Result.Spent)
	// F7 again: afresh, no water.
	_, cleared = game.sandbox_clear_for_fishing(&room)
	testing.expect(t, cleared)
	testing.expect_value(t, room.fishing.water_count, 0)
	testing.expect_value(t, game.fishing_casts_left(&room), i32(1))
	// The exit stays shut in the lab: walking onto it keeps the arena, and the
	// board shows it shut (no portal, no USCITA), where a cleared room's opens.
	player.position = {room.exit_position.x-1, room.exit_position.y}
	testing.expect_value(t, game.try_move_player(&room, .East), game.Action_Result.Moved)
	testing.expect_value(t, room.phase, game.Room_Phase.Loot)
	testing.expect(t, !render.tactical_exit_is_open(&room, room.phase))
	room.endless = false
	testing.expect(t, render.tactical_exit_is_open(&room, room.phase) && !render.tactical_exit_is_open(&room, .Combat))
	room.endless = true
	// F5's fresh arena is a fight again, the rod back in Exhaust.
	game.destroy_room(&room)
	room, built = run_session.create_mechanics_lab_room(&data, &player, game.DEFAULT_TACTICAL_CONFIG)
	testing.expect(t, built)
	testing.expect_value(t, room.phase, game.Room_Phase.Combat)
	testing.expect(t, !game.fishing_room_open(&room) && player.deck.exhaust_count == 1)
}

@(test)
test_mechanics_lab_never_touches_the_profile_and_starts_directly :: proc(t: ^testing.T) {
	rs := run_session.roguelike_session_new()
	defer run_session.roguelike_destroy(rs)
	options := application.DEFAULT_RUNTIME_OPTIONS
	application.roguelike_parse_arguments(&options, []string{"--mechanics-lab"})
	rs.options = options.gameplay
	testing.expect(t, rs.options.mechanics_lab)
	testing.expect(t, application.roguelike_requires_direct_start(&options))
	testing.expect(t, !run_session.roguelike_profile_enabled(rs))
}
