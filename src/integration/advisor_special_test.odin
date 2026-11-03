package integration
import run_session "../run"

import "core:fmt"
import "core:log"
import "core:math/rand"
import "core:testing"
import "core:time"
import advisor "../advisor"
import campaign "../campaign"
import expedition "../expedition"
import game "../game"
import grid "../engine/grid"
import level "../level"

// THE SPECIAL CASES (docs/piano-ia.md, Fase 7): the copy plays every card the IA advises exactly as the game does (the
// long ones too: the Lazzo, the Pinball, Marley, the cannons, the holes, the Dinosauro, the wave, the coils); the
// shadow's steps; the arenas of heights, structures, layers and lifts; in a thousand situations the game takes every
// advice; the tables of objects, structures and cells; the measures on the largest expedition.

@(private = "file")
special_test_arena :: proc(t: ^testing.T, data: ^level.Level, player: ^game.Player, arena := run_session.Mechanics_Lab_Arena.IA) -> game.Room {
	created: bool
	player^, created = game.create_player(run_session.DEMO_PLAYER_STATS)
	testing.expect(t, created)
	room, built := run_session.create_mechanics_lab_room(data, player, game.DEFAULT_TACTICAL_CONFIG, arena)
	testing.expect(t, built)
	return room
}

// The card `id` alone in hand in the IA's arena (the Strike's place; the other cards to the discard pile), a foe
// `distance` cells east of the player.
@(private = "file")
special_test_card_room :: proc(t: ^testing.T, data: ^level.Level, player: ^game.Player, id: game.Card_Id, distance: int) -> game.Room {
	room := special_test_arena(t, data, player)
	room.enemies[0].position = game.add_position(room.player.position, {x = distance, y = 0})
	game.plan_enemy_intents(&room)
	deck := &room.player.deck
	hand := deck.hand
	count := deck.hand_count
	deck.hand_count = 0
	for card in hand[:count] {
		if card.definition_id != .Strike { deck.discard_pile[deck.discard_count] = card; deck.discard_count += 1; continue }
		changed := card
		changed.definition_id, changed.upgrade_level = id, 0
		if owned, found := game.owned_card_index_by_id(deck, card.id); found { deck.owned[owned] = changed }
		deck.hand[deck.hand_count] = changed
		deck.hand_count += 1
	}
	for &card in deck.hand[deck.hand_count:] { card = {} }
	deck.energy = deck.rules.max_energy
	return room
}

// The same move played by the game (its commands, then its frames) and by a copy (play_move, then frame_room), both
// for `seconds` of the world: the two rooms equal, field by field. Whether the game took it.
@(private = "file")
special_test_both :: proc(t: ^testing.T, room: ^game.Room, move: advisor.Move, seconds: f32, label: string) -> bool {
	snapshot: advisor.Snapshot
	rehearsal: advisor.Rehearsal
	testing.expect(t, advisor.snapshot_init(&snapshot) && advisor.rehearsal_init(&rehearsal))
	defer { advisor.rehearsal_destroy(&rehearsal); advisor.snapshot_destroy(&snapshot) }
	testing.expect(t, advisor.snapshot_take(&snapshot, room) && advisor.rehearsal_begin(&rehearsal, &snapshot))
	copy := advisor.rehearsal_room(&rehearsal)
	commands, count := run_session.advisor_move_commands(room, move)
	// No command (waiting in the shadow) is always taken.
	taken := count == 0
	for command, k in commands[:count] {
		committed := run_session.execute_gameplay_command(room, command).committed
		if k == 0 { taken = committed }
	}
	played := advisor.play(&rehearsal, move)
	testing.expectf(t, played == taken, "%s: the game took it %v, the copy %v", label, taken, played)
	for ran := f32(0); ran < seconds; ran += advisor.SIM_STEP {
		advisor_test_real_frame(room, advisor.SIM_STEP)
		advisor.frame_room(copy, advisor.SIM_STEP)
	}
	equal, where_ := advisor.rooms_equal(room, copy)
	testing.expectf(t, equal, "%s: the copy and the game differ at %s", label, where_)
	return taken
}

// Every card the IA advises, played on its best target in the IA's arena, then five seconds of the world: the copy
// and the game are the same room. The long cards play their whole time out in it.
@(test)
test_advisor_copy_plays_every_card_as_the_game :: proc(t: ^testing.T) {
	played := 0
	for id in game.Card_Id {
		if id == .Count || advisor.ADVISOR_CARDS[id].use != .Advised { continue }
		if definition, _ := game.card_definition_by_id(id); definition.temporary_only { continue }
		done := false
		for distance in ([?]int{1, 3}) {
			if done { break }
			data: level.Level
			player: game.Player
			room := special_test_card_room(t, &data, &player, id, distance)
			plays: [advisor.MAX_CANDIDATES]advisor.Move
			if count := advisor.card_plays(&room, plays[:]); count > 0 {
				done = special_test_both(t, &room, plays[0], 5, fmt.tprint(id))
				if !done { log.infof("%v: the game did not take its play at distance %d", id, distance) }
			}
			game.destroy_room(&room)
			level.destroy(&data)
		}
		if done { played += 1 } else { log.infof("%v: no play taken", id) }
	}
	log.infof("cards played by the copy as by the game: %d", played)
}

// MOVIMENTO OMBRA: the card played, the world stands still; the IA's first moves are the shadow's steps (or letting
// its seconds run), its advice a step of the shadow from the shadow's cell; the copy walks the shadow and rises from it
// as the game does.
@(test)
test_advisor_walks_the_shadow :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	room := special_test_card_room(t, &data, &player, .Shadow_Step, 3)
	defer game.destroy_room(&room)
	plays: [advisor.MAX_CANDIDATES]advisor.Move
	testing.expect(t, advisor.card_plays(&room, plays[:]) > 0)
	commands, count := run_session.advisor_move_commands(&room, plays[0])
	for command in commands[:count] { testing.expect(t, run_session.execute_gameplay_command(&room, command).committed) }
	// The card's cast, then the shadow.
	for _ in 0..<240 {
		if game.tactical_shadow_active(&room) && advisor.player_free(&room) { break }
		advisor_test_real_frame(&room, advisor.SIM_STEP)
	}
	testing.expect(t, game.tactical_shadow_active(&room))
	if !game.tactical_shadow_active(&room) { return }
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	advice := advisor.search_whole(&search, &room, 400)
	testing.expect(t, advice.valid)
	for i in 0..<search.candidate_count {
		kind := search.candidates[i].kind
		testing.expectf(t, kind == .Step || kind == .Wait, "a first move in the shadow: %v", kind)
	}
	shadow := room.player.tactical.shadow_position
	if advice.kind == .Step {
		testing.expectf(t, abs(advice.cell.x-shadow.x)+abs(advice.cell.y-shadow.y) == 1, "the shadow's step from %v to %v", shadow, advice.cell)
	}
	// The advised step, then the shadow's seconds run out and the player rises: the copy as the game.
	special_test_both(t, &room, advice.move, 8, "the shadow")
	testing.expect(t, !game.tactical_shadow_active(&room))
}

// Random games in the arenas of heights, structures, layers and lifts (steps on other layers, lifts in motion, gates,
// cliffs): after every move the copy and the game are the same room.
@(test)
test_advisor_copy_plays_the_special_arenas :: proc(t: ^testing.T) {
	state := rand.create_u64(20261107)
	generator := rand.default_random_generator(&state)
	for arena in ([?]run_session.Mechanics_Lab_Arena{.Heights, .Structures, .Layers, .Lifts}) {
		for game_index in 0..<6 {
			data: level.Level
			player: game.Player
			room := special_test_arena(t, &data, &player, arena)
			for move_index in 0..<10 {
				if room.phase != .Combat { break }
				advisor_test_real_until_free(&room, advisor.SIM_STEP)
				roll := rand.int_max(10, generator)
				move := advisor.Move{kind = .Step, direction = game.Move_Direction(rand.int_max(4, generator))}
				if roll == 0 { move = {kind = .Wait} }
				if roll == 1 { move.kind = .Dodge }
				special_test_both(t, &room, move, 1.5, "")
				if t.error_count > 0 { log.infof("%v game %d move %d: %v", arena, game_index, move_index, move); break }
			}
			game.destroy_room(&room)
			level.destroy(&data)
		}
	}
}

// IN A THOUSAND SITUATIONS (two hundred in the quick run) of random games in the IA's arena and the special ones, the
// game takes the IA's advice: its first command is never refused. The real room rolls the copy's own dice, so that the
// world runs alike up to the advised moment.
@(private = "file")
POSSIBLE_SITUATIONS :: 1000 when ODIN_TEST_FULL else 200

@(test)
test_advisor_advice_is_always_possible :: proc(t: ^testing.T) {
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	state := rand.create_u64(20261108)
	generator := rand.default_random_generator(&state)
	arenas := [?]run_session.Mechanics_Lab_Arena{.IA, .Heights, .Structures, .Layers, .Lifts}
	tried, refused := 0, 0
	for tried < POSSIBLE_SITUATIONS {
		data: level.Level
		player: game.Player
		room := special_test_arena(t, &data, &player, arenas[(tried/20)%len(arenas)])
		for _ in 0..<20 {
			if room.phase != .Combat { break }
			room.player.dice = game.make_dice_state(advisor.DICE_SEED)
			advice := advisor.search_whole(&search, &room, 60)
			if advice.valid {
				tried += 1
				// The world on to the advised moment, as the copies run it, then the advice.
				advisor_test_real_until_free(&room, advisor.SIM_STEP)
				for margin := f32(0); margin < advisor.REACTION_SECONDS && room.qte.kind == .None; margin += advisor.SIM_STEP {
					advisor_test_real_frame(&room, advisor.SIM_STEP)
				}
				commands, count := run_session.advisor_move_commands(&room, advice.move)
				// A wait in the shadow is no command: nothing to refuse.
				if count > 0 && !run_session.execute_gameplay_command(&room, commands[0]).committed {
					refused += 1
					log.infof("refused: %v %v at %v", advice.kind, advice.move.kind, advice.cell)
				}
				if count > 1 { for command in commands[1:count] { run_session.execute_gameplay_command(&room, command) } }
			}
			// Then the game goes on a little, by a random step.
			run_session.execute_gameplay_command(&room, {kind = .Move, origin_phase = .Combat, direction = game.Move_Direction(rand.int_max(4, generator))})
			for _ in 0..<15 { advisor_test_real_frame(&room, advisor.SIM_STEP) }
		}
		game.destroy_room(&room)
		level.destroy(&data)
	}
	log.infof("advice possible: %d situations, %d refused", tried, refused)
	testing.expect_value(t, refused, 0)
}

// Every object of the grid, every structure, every kind of cell has its line (the switches have no default).
@(test)
test_advisor_knows_the_board :: proc(t: ^testing.T) {
	for kind in game.Grid_Object_Kind { if kind != .Count { testing.expectf(t, advisor.object_knowledge(kind).why != "", "%v", kind) } }
	for id in level.Structure_Id { if id != .Count { testing.expectf(t, advisor.structure_knowledge(id) != "", "%v", id) } }
	for kind in level.Tile_Kind { testing.expectf(t, advisor.tile_knowledge(kind).why != "", "%v", kind) }
}

// THE LARGEST EXPEDITION (Spazio, 224x224 with its layers, four foes): the snapshot, the first round, the whole search.
@(test)
test_advisor_measures_the_largest_expedition :: proc(t: ^testing.T) {
	w := new(expedition.World)
	defer free(w)
	data: level.Level
	defer level.destroy(&data)
	player: game.Player
	testing.expect(t, expedition.generate(w, &data, campaign.Biome.Space, 42))
	created: bool
	player, created = game.create_player({100, 5, 0})
	testing.expect(t, created)
	room, built := game.create_room(&data, &player, {room_seed = 42, endless = true})
	testing.expect(t, built && game.configure_expedition_combat(&room))
	defer game.destroy_room(&room)
	room.endless = true
	for offset in ([4]grid.Position{{x = 4, y = 0}, {x = -4, y = 1}, {x = 2, y = 4}, {x = -1, y = -4}}) {
		game.spawn_enemy(&room, {position = grid.offset(player.position, offset.x, offset.y), health = 20, attack = 2, archetype = .Chaser})
	}
	search: advisor.Search
	testing.expect(t, advisor.search_init(&search))
	defer advisor.search_destroy(&search)
	start := time.tick_now()
	testing.expect(t, advisor.search_root(&search, &room))
	rooted := time.duration_milliseconds(time.tick_since(start))
	first: f64
	for !search.done && search.work < 4000 {
		advisor.search_step(&search, 1)
		if first == 0 && search.advice.valid { first = time.duration_milliseconds(time.tick_since(start)) }
	}
	total := time.duration_milliseconds(time.tick_since(start))
	log.infof("ADVISOR largest expedition %dx%d: root %.2f ms, first advice %.1f ms, %d nodes in %.0f ms (%.0f a second), round %d",
		data.tiles.width, data.tiles.height, rooted, first, search.nodes, total, f64(search.nodes)/(total/1000), search.round)
	testing.expect(t, search.advice.valid)
}
