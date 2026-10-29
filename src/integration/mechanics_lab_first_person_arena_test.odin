package integration

import run_session "../run"
import "core:testing"
import game "../game"
import grid "../engine/grid"
import level "../level"
import render "../render"

// The first person arena (docs/piano-prima-persona.md, Fase 1), right after the
// flat one in F3's turn: its walls, niches, pillars and slanted walls, its low
// covers, the corridor of five cells, the archer up on the rise and the brute;
// its own deck, First Person Shooter in hand and the rod waiting in Exhaust.
@(test)
test_mechanics_lab_has_an_arena_for_the_first_person :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player, created := game.create_player(run_session.DEMO_PLAYER_STATS)
	testing.expect(t, created)
	room, built := run_session.create_mechanics_lab_room(&data, &player, game.DEFAULT_TACTICAL_CONFIG, .First_Person)
	testing.expect(t, built)
	defer game.destroy_room(&room)
	testing.expect(t, room.endless && room.phase == .Combat)
	testing.expect(t, data.tiles.width == run_session.MECHANICS_LAB_WIDTH && data.tiles.height == run_session.MECHANICS_LAB_HEIGHT)
	testing.expect_value(t, player.position, grid.Position{x = 11, y = 8})
	walkable :: proc(data: ^level.Level, cell: grid.Position) -> bool {
		tile, inside := level.tile_at(data, cell)
		return inside && level.is_walkable(tile.kind)
	}
	// The north wall and its niches; the pillars; the slanted walls.
	for x in 1..=21 { testing.expectf(t, walkable(&data, {x = x, y = 1}) == (x == 4 || x == 18), "(%d, 1)", x) }
	for cell in ([?]grid.Position{{x = 6, y = 4}, {x = 16, y = 4}, {x = 6, y = 11}, {x = 16, y = 11}, {x = 4, y = 6}, {x = 3, y = 7},
		{x = 2, y = 8}, {x = 18, y = 6}, {x = 19, y = 7}, {x = 20, y = 8}}) {
		testing.expectf(t, !walkable(&data, cell), "%v", cell)
	}
	// The corridor: five cells between two walls, shut to the west, open to the east.
	for x in 2..=6 {
		testing.expect(t, walkable(&data, {x = x, y = 14}) && !walkable(&data, {x = x, y = 13}) && !walkable(&data, {x = x, y = 15}))
	}
	testing.expect(t, !walkable(&data, {x = 1, y = 14}) && walkable(&data, {x = 7, y = 14}))
	// The low covers.
	testing.expect_value(t, len(room.obstacles), len(run_session.MECHANICS_LAB_FIRST_PERSON_COVERS))
	for cover in run_session.MECHANICS_LAB_FIRST_PERSON_COVERS { testing.expect(t, game.obstacle_at(&room, cover)) }
	// The rise and its step; the archer up on it, the brute.
	testing.expect(t, level.height_at(&data, {x = 9, y = 2}) == 2 && level.height_at(&data, {x = 13, y = 3}) == 2)
	testing.expect_value(t, level.height_at(&data, {x = 11, y = 4}), i32(1))
	archer, brute := false, false
	for foe in room.enemies {
		archer = archer || (foe.archetype == .Archer && foe.position == run_session.MECHANICS_LAB_FIRST_PERSON_ARCHER)
		brute = brute || (foe.archetype == .Brute && foe.position == run_session.MECHANICS_LAB_FIRST_PERSON_BRUTE)
	}
	testing.expect(t, archer && brute)
	// Its own deck: First Person Shooter, Brawler and Fencer in hand, the rod in Exhaust.
	testing.expect_value(t, player.deck.owned_count, len(run_session.MECHANICS_LAB_FIRST_PERSON_DECK))
	testing.expect_value(t, player.deck.hand_count, 3)
	held: bit_set[game.Card_Id]
	for card in player.deck.hand[:player.deck.hand_count] { held += {card.definition_id} }
	testing.expect(t, held == {.First_Person, .First_Person_Brawler, .First_Person_Fencer})
	testing.expect(t, player.deck.exhaust_count == 1 && player.deck.exhaust_pile[0].definition_id == .Fishing_Rod)
	// F3: the flat arena, then this one, then the heights.
	testing.expect_value(t, run_session.mechanics_lab_next_arena(.Flat), run_session.Mechanics_Lab_Arena.First_Person)
	testing.expect_value(t, run_session.mechanics_lab_next_arena(.First_Person), run_session.Mechanics_Lab_Arena.Heights)
	// The flat arena keeps its deck.
	flat, flat_built := run_session.create_mechanics_lab_room(&data, &player, game.DEFAULT_TACTICAL_CONFIG)
	testing.expect(t, flat_built)
	defer game.destroy_room(&flat)
	testing.expect(t, player.deck.owned_count == len(run_session.MECHANICS_LAB_DECK) && len(flat.obstacles) == 0)
}

// The first person arena lives a minute of play as the game has it: the foes
// free, the lab's arrivals, the player behind his eyes with each weapon in
// turn, the AK's trigger held now and then. Nothing breaks the foes' beat, each
// weapon is taken up, only the AK fires, and the fight goes on.
@(test)
test_mechanics_lab_first_person_lives_a_minute_of_play :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player, created := game.create_player(run_session.DEMO_PLAYER_STATS)
	testing.expect(t, created)
	room, built := run_session.create_mechanics_lab_room(&data, &player, game.DEFAULT_TACTICAL_CONFIG, .First_Person)
	testing.expect(t, built)
	defer game.destroy_room(&room)
	// Sturdy enough to last the minute among free foes.
	player.stats.max_health, player.health = 999, 999
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	buffer: run_session.Buffered_Gameplay_Command
	sandbox := game.begin_sandbox(7)
	taken: [game.First_Person_Weapon]bool
	next := game.First_Person_Weapon.AK
	ak_shots := i32(0)
	for frame in 0..<60*60 {
		if !game.tactical_first_person_active(&room) && game.tactical_begin_first_person(&room, 12, next) {
			taken[next] = true
			next = game.First_Person_Weapon((int(next)+1)%len(game.First_Person_Weapon))
		}
		weapon := room.first_person.weapon
		shots := room.first_person.shots
		// The trigger held every other second (let go between, so no press is latched).
		input := run_session.Tactical_Controller_Input{focused = true, fire = (frame/60)%2 == 1, fire_right = (frame/60)%2 == 1}
		_, _ = game.sandbox_tick(&room, &sandbox, 1.0/60)
		_ = run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 1.0/60, true, input)
		if room.phase != .Combat { break }
		// The fists punch (Fase 2); the sword and the bow have no rules yet.
		if weapon == .AK { ak_shots += room.first_person.shots-shots } else if weapon != .Fists { testing.expect(t, room.first_person.shots == shots, "a weapon with no rules fired") }
		if frame%30 == 0 && !room.tactical_pulse.pending && !game.validate_enemy_intents(&room) { testing.expect(t, false, "the foes' intents broke"); break }
	}
	testing.expect_value(t, room.phase, game.Room_Phase.Combat)
	for weapon in game.First_Person_Weapon { testing.expectf(t, taken[weapon], "%v was never taken up", weapon) }
	testing.expect(t, ak_shots > 0, "the AK never fired")
}

// The fists live a minute of play in the first person arena, the foes free and
// arriving, through the controller's keys: the body circles the room two seconds
// out of four, jumps and punches as it goes, then stands, the foes' blows on the
// cells it touches (Fase 2, passo 4 of docs/piano-prima-persona.md).
// Nothing breaks the foes' beat, the body never stands in a cell a step could not
// enter, punches land, blows reach him, and the fight goes on.
@(test)
test_mechanics_lab_fists_live_a_minute_of_play :: proc(t: ^testing.T) {
	data: level.Level
	defer level.destroy(&data)
	player, created := game.create_player(run_session.DEMO_PLAYER_STATS)
	testing.expect(t, created)
	room, built := run_session.create_mechanics_lab_room(&data, &player, game.DEFAULT_TACTICAL_CONFIG, .First_Person)
	testing.expect(t, built)
	defer game.destroy_room(&room)
	player.stats.max_health, player.health = 999, 999
	renderer := new(render.Renderer)
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	controller := run_session.Tactical_Controller{was_focused = true}
	cards: run_session.Card_Interaction_State
	buffer: run_session.Buffered_Gameplay_Command
	sandbox := game.begin_sandbox(7)
	views, hits := 0, i32(0)
	for frame in 0..<60*60 {
		if !game.tactical_first_person_active(&room) && game.tactical_begin_first_person(&room, 12, .Fists) { views += 1 }
		// Through the controller's own keys: round and round, the view turning as
		// it goes, W held, jumping and punching (a press now and then, with Shift
		// every other one), two seconds out of four for forty seconds; the others,
		// and the last twenty, standing idle (on the run he steps out of the red
		// cells before the beat and fells who comes near; standing, he is hit).
		renderer.tactical.first_person.yaw = f32(frame)*0.013
		running := frame < 40*60 && (frame/120)%2 == 0
		input := run_session.Tactical_Controller_Input{focused = true}
		if running {
			input.walk[0], input.jump = true, frame%90 == 45
			input.fire, input.shift = frame%20 == 0, frame%40 == 0
		}
		before := room.first_person.hits
		_, _ = game.sandbox_tick(&room, &sandbox, 1.0/60)
		_ = run_session.step_tactical_controller(&controller, &room, renderer, &cards, &buffer, 1.0/60, true, input)
		hits += room.first_person.hits-before
		if game.first_person_fists_active(&room) {
			tile, inside := level.tile_at(&data, room.player.position)
			testing.expect(t, inside && level.is_walkable(tile.kind) && !game.obstacle_at(&room, room.player.position), "the body stands in a cell no step enters")
		}
		if room.phase != .Combat { break }
		if frame%30 == 0 && !room.tactical_pulse.pending && !game.validate_enemy_intents(&room) { testing.expect(t, false, "the foes' intents broke"); break }
	}
	testing.expect_value(t, room.phase, game.Room_Phase.Combat)
	testing.expect(t, views >= 4, "the fists were not taken up again")
	testing.expect(t, hits > 0, "no punch landed in a minute")
	testing.expect(t, player.health < 999, "no blow reached him in a minute")
}
