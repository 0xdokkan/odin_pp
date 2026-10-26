package integration
import run_session "../run"
import application "../application"


import "core:testing"
import game "../game"
import grid "../engine/grid"
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
			tile, inside := level.tile_at(&data, {x = x, y = y})
			testing.expect(t, inside && level.is_walkable(tile.kind))
		}
	}
	testing.expect(t, len(room.objects) == 0 && len(room.traps) == 0)
	// The deck: one of each card under test (Bomb Marley, Inondazione, Cannone,
	// Incendio, Buco Nero, Dinosauro, the Dado del Destino, the Lazzo, the Canna
	// da Pesca, the Pinball and the First Person Shooter); all in hand
	// (ten: more than the game's hand ever holds, all the room a hand has) but
	// the rod, which waits in Exhaust for a cleared room.
	testing.expect_value(t, player.deck.owned_count, len(run_session.MECHANICS_LAB_DECK))
	testing.expect_value(t, len(run_session.MECHANICS_LAB_DECK)-1, game.MAX_HAND_CAPACITY)
	for id in ([?]game.Card_Id{.Marley_Party, .Flood_Wave, .Field_Cannon, .Wildfire, .Devouring_Hole, .Dino_Ride, .Fate_Dice, .Lasso, .Fishing_Rod,
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

// The arena of the layers (Fase 3 of docs/piano-profondita.md): its bridge, cave and ladder keep the column's rule,
// a foe waits on each of three layers, and a step goes up the ramp onto the bridge, into the cave's mouth and up the
// ladder. F3 comes to it after the cave's arena.
@(test)
test_mechanics_lab_has_an_arena_of_layers :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player, created := game.create_player(run_session.DEMO_PLAYER_STATS)
	testing.expect(t, created)
	room, built := run_session.create_mechanics_lab_room(&data, &player, game.DEFAULT_TACTICAL_CONFIG, .Layers)
	testing.expect(t, built)
	defer game.destroy_room(&room)
	testing.expect(t, level.has_layers(&data))
	error, _ := level.check_layers(&data)
	testing.expect_value(t, error, level.Layer_Error.None)
	testing.expect_value(t, player.position, run_session.MECHANICS_LAB_LAYERS_START)
	on: [3]bool
	for foe in room.enemies { on[int(foe.position.layer)+1] = true }
	testing.expect(t, on[0] && on[1] && on[2])
	testing.expect_value(t, game.walk_step(&room, {x = 13, y = 14}, {x = 1}), grid.Position{x = 14, y = 14, layer = 1})
	testing.expect_value(t, game.walk_step(&room, {x = 34, y = 7}, {x = 1}), grid.Position{x = 35, y = 7, layer = -1})
	testing.expect_value(t, game.walk_step(&room, {x = 34, y = 4}, {x = 1}), grid.Position{x = 35, y = 4})
	testing.expect_value(t, run_session.mechanics_lab_next_arena(.Cave), run_session.Mechanics_Lab_Arena.Layers)
	testing.expect_value(t, run_session.mechanics_lab_next_arena(.Layers), run_session.Mechanics_Lab_Arena.Lifts)
}

// The seventh arena (Fase 7 of docs/piano-profondita.md): a lift up the plateau's cliff and one down its shaft, their
// platforms where the arena has them, the gate shut, a foe in the hall under the plateau; after it F3 comes back to the
// flat arena.
@(test)
test_mechanics_lab_has_an_arena_of_lifts :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player, created := game.create_player(run_session.DEMO_PLAYER_STATS)
	testing.expect(t, created)
	room, built := run_session.create_mechanics_lab_room(&data, &player, game.DEFAULT_TACTICAL_CONFIG, .Lifts)
	testing.expect(t, built)
	defer game.destroy_room(&room)
	error, _ := level.check_layers(&data)
	testing.expect_value(t, error, level.Layer_Error.None)
	testing.expect_value(t, player.position, run_session.MECHANICS_LAB_LIFTS_START)
	testing.expect(t, len(data.lifts) == 2 && room.lifts.count == 2 && len(data.gates) == 1)
	testing.expect(t, game.lift_landing_shut(&room, {x = 11, y = 10}), "the cliff's platform waits at the top")
	testing.expect(t, game.lift_landing_shut(&room, {x = 18, y = 5}), "the shaft's platform waits at the bottom")
	_, open, _ := level.gate_at(&data, {x = 24, y = 7, layer = -1})
	testing.expect(t, !open)
	in_hall := false
	for foe in room.enemies { in_hall = in_hall || foe.position.layer == -1 }
	testing.expect(t, in_hall)
	testing.expect_value(t, run_session.mechanics_lab_next_arena(.Lifts), run_session.Mechanics_Lab_Arena.Flat)
}

// The arena of the lifts lives a minute of play as the game has it: the foes free, the lab's arrivals, the player
// still. Nothing breaks the foes' beat (a foe off a lift with no intent once stopped the game), and the foe in the hall
// comes out of it, up the shaft.
@(test)
test_mechanics_lab_lifts_live_a_minute_of_play :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player, created := game.create_player(run_session.DEMO_PLAYER_STATS)
	testing.expect(t, created)
	room, built := run_session.create_mechanics_lab_room(&data, &player, game.DEFAULT_TACTICAL_CONFIG, .Lifts)
	testing.expect(t, built)
	defer game.destroy_room(&room)
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	buffer: run_session.Buffered_Gameplay_Command
	sandbox := game.begin_sandbox(7)
	hall_foe: u32
	for foe in room.enemies { if foe.position.layer == -1 { hall_foe = foe.id } }
	testing.expect(t, hall_foe != 0)
	out_of_the_hall := false
	for frame in 0..<60*60 {
		_, _ = game.sandbox_tick(&room, &sandbox, 1.0/60)
		_ = run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 1.0/60, true, {focused = true})
		if room.phase != .Combat { break }
		// Between the foes' beats (during one, those already resolved wait with none).
		if frame%30 == 0 && !room.tactical_pulse.pending && !game.validate_enemy_intents(&room) { testing.expect(t, false, "the foes' intents broke"); break }
		if index, found := game.enemy_index_by_id(&room, hall_foe); found && room.enemies[index].position.layer == grid.GROUND_LAYER &&
		   !game.enemy_is_out_of_play(&room, hall_foe) {
			out_of_the_hall = true
		}
	}
	testing.expect_value(t, room.phase, game.Room_Phase.Combat)
	testing.expect(t, out_of_the_hall, "the foe in the hall did not come out of it up the shaft")
}

// With the arena of the lifts cleared by F7, out of the fight, the platforms still go, on the controller's frames: a
// call brings the platform, a ride ends at the top, and nobody is left on a platform that never stops.
@(test)
test_mechanics_lab_lifts_go_on_out_of_the_fight :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player, created := game.create_player(run_session.DEMO_PLAYER_STATS)
	testing.expect(t, created)
	room, built := run_session.create_mechanics_lab_room(&data, &player, game.DEFAULT_TACTICAL_CONFIG, .Lifts)
	testing.expect(t, built)
	defer game.destroy_room(&room)
	_, cleared := game.sandbox_clear_for_fishing(&room)
	testing.expect(t, cleared && room.phase == .Loot)
	renderer := new(render.Renderer)
	defer free(renderer)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	buffer: run_session.Buffered_Gameplay_Command
	two_seconds :: proc(controller: ^run_session.Tactical_Controller, room: ^game.Room, renderer: ^render.Renderer,
		cards: ^run_session.Card_Interaction_State, buffer: ^run_session.Buffered_Gameplay_Command) {
		for _ in 0..<120 { _ = run_session.step_tactical_controller(controller, room, renderer, cards, buffer, 1.0/60, true, {focused = true}) }
	}
	player.position = {x = 10, y = 10}
	testing.expect_value(t, game.try_move_player(&room, .East), game.Action_Result.Blocked)
	testing.expect(t, room.lifts.platforms[0].moving, "the step called the platform")
	two_seconds(&controller, &room, renderer, &cards, &buffer)
	testing.expect(t, !room.lifts.platforms[0].moving && room.lifts.platforms[0].at == 0, "the platform came down")
	testing.expect_value(t, game.try_move_player(&room, .East), game.Action_Result.Moved)
	testing.expect(t, game.lift_player_riding(&room))
	two_seconds(&controller, &room, renderer, &cards, &buffer)
	testing.expect(t, !game.lift_player_riding(&room), "the ride ended")
	testing.expect_value(t, player.position, grid.Position{x = 11, y = 10, layer = 1})
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
		"NEMICI 3/6  /  F5 RICOMINCIA  /  F6 INTENTI: HUD + TERRENO  /  F7 PESCA  /  F3 ARENA  /  F10 MENU")
	render.set_mechanics_lab(renderer, true)
	testing.expect_value(t, string(render.mechanics_lab_banner_detail(renderer, &room)),
		"NEMICI 3/6  /  F5 RICOMINCIA  /  F6 INTENTI: HUD + TERRENO  /  F7 PESCA  /  F3 ARENA")
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
	water := game.add_position(player.position, {x = 2, y = 0})
	testing.expect_value(t, game.fish_with_rod(&room, water).result, game.Fishing_Result.Fished)
	testing.expect_value(t, game.fishing_target_error(&room, water), game.Fishing_Result.Spent)
	// F7 again: afresh, no water.
	_, cleared = game.sandbox_clear_for_fishing(&room)
	testing.expect(t, cleared)
	testing.expect_value(t, room.fishing.water_count, 0)
	testing.expect_value(t, game.fishing_casts_left(&room), i32(1))
	// The exit stays shut in the lab: walking onto it keeps the arena, and the
	// board shows it shut (no portal, no USCITA), where a cleared room's opens.
	player.position = {x = room.exit_position.x-1, y = room.exit_position.y}
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
