package main

import "core:testing"
import rl "vendor:raylib"
import game "game"
import grid "grid"
import level "level"
import render "render"
import view "view"

// The outcome of a take, to compare two of them.
Card_Demo_Outcome :: struct {
	shown: bit_set[game.Game_Event_Kind],
	played: bool,
	player_health: i32,
	player_position: [2]int,
	foe_health: [game.CARD_DEMO_MAX_FOES]i32,
	foe_count: int,
	fps_hits: i32,
}

card_demo_outcome :: proc(demo: ^Card_Demo, renderer: ^render.Renderer) -> (outcome: Card_Demo_Outcome) {
	outcome.shown = renderer.shown_events
	outcome.played = demo.played
	outcome.player_health = demo.player.health
	outcome.player_position = {demo.player.position.x, demo.player.position.y}
	outcome.foe_count = len(demo.room.enemies)
	for enemy, index in demo.room.enemies {
		if index < len(outcome.foe_health) { outcome.foe_health[index] = enemy.health }
	}
	outcome.fps_hits = demo.fps_hits
	return
}

// A board's canvas and projection as the game's, with no GPU asset.
card_demo_test_renderer :: proc() -> ^render.Renderer {
	renderer := new(render.Renderer)
	board, _, _ := level.from_ascii([]string{"###", "#@#", "#>#", "###"})
	renderer^ = render.create(960, 540, &board)
	level.destroy(&board)
	return renderer
}

// A caption of the film's own table (CARD_DEMO_WORDS) with its key's cap (a
// step's: the one of its way): the smoke holds every one of them on its plate.
card_demo_test_known_caption :: proc(key, text: cstring) -> bool {
	for words in Card_Demo_Words {
		if text != CARD_DEMO_WORDS[words] { continue }
		if key == CARD_DEMO_WORDS_KEY[words] { return true }
		if words == .Step || words == .Bump || words == .Shadow_Step {
			for step in CARD_DEMO_STEP_KEYS { if key == step { return true } }
		}
	}
	return false
}

// A take played from its first frame to its end, never past CARD_DEMO_TAKE_LIMIT,
// the frames whose caption said nothing, and those whose caption is none of
// the film's table.
card_demo_test_take :: proc(demo: ^Card_Demo, renderer: ^render.Renderer) -> (frames, mute, unknown: int) {
	for demo.built && demo.stage != .Done && frames < 60*45 {
		card_demo_advance(demo, renderer, 1.0/60.0)
		key, text := card_demo_caption_words(demo)
		if text == nil || text == "" { mute += 1 }
		else if !card_demo_test_known_caption(key, text) { unknown += 1 }
		frames += 1
	}
	return
}

// MOSTRA EFFETTO: every Card_Id at every level it can reach has a film whose
// take plays its card as the hand plays it and runs the room through the
// take's own controller, within its time, and the board is handed every event
// its card promises (game.card_demo_expected_events, from the card's own
// definition: a new card is held to it with no word of its own), the foes it
// must hurt are hurt and the ground it leaves shows; its caption says what is
// done at every frame, in words of the film's own table (which the smoke holds
// on their plate). A second take is the first again.
@(test)
test_every_card_has_a_demo_that_shows_its_effect :: proc(t: ^testing.T) {
	renderer := card_demo_test_renderer()
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	demo := new(Card_Demo)
	defer free(demo)
	defer card_demo_close(demo)
	for id in game.Card_Id {
		if id == .Count { continue }
		for upgrade in i32(0)..=game.card_max_upgrade_level(id) {
			card := game.Card_Instance{id = 7, definition_id = id, upgrade_level = upgrade}
			if !testing.expectf(t, card_demo_open(demo, renderer, card), "%v +%d: no film", id, upgrade) { continue }
			outcomes: [2]Card_Demo_Outcome
			for take in 0..<2 {
				if take > 0 { card_demo_restart(demo, renderer) }
				if !testing.expectf(t, demo.built, "%v +%d: take %d not built", id, upgrade, take) { break }
				_, mute, unknown := card_demo_test_take(demo, renderer)
				testing.expectf(t, mute == 0, "%v +%d take %d: %d frames with no caption", id, upgrade, take, mute)
				testing.expectf(t, unknown == 0, "%v +%d take %d: %d frames with a caption off the film's table", id, upgrade, take, unknown)
				missing, shown := card_demo_shown(demo, renderer)
				expected, hurt := game.card_demo_expected_events(id)
				testing.expectf(t, shown, "%v +%d take %d: played %v, missing %v of %v, foes hurt %d of %d, pool %v, fire %v, AK hits %d", id, upgrade,
					take, demo.played, missing, expected, card_demo_foes_hurt(demo), hurt, demo.pooled, demo.burned, demo.fps_hits)
				testing.expectf(t, demo.stage == .Done && demo.take_time < CARD_DEMO_TAKE_LIMIT, "%v +%d: the take ran %.1f s", id, upgrade, demo.take_time)
				testing.expectf(t, renderer.timeline.update_failures == 0, "%v +%d: %d timeline failures", id, upgrade, renderer.timeline.update_failures)
				testing.expectf(t, demo.room.player == &demo.player && demo.room.level_data == &demo.data, "%v +%d: the room is not the film's", id, upgrade)
				outcomes[take] = card_demo_outcome(demo, renderer)
			}
			testing.expectf(t, outcomes[0] == outcomes[1], "%v +%d: the second take differs: %v / %v", id, upgrade, outcomes[0], outcomes[1])
		}
	}
}

// The window steps a film by its own frames, whatever they last: every card
// at its first and its top level shows its effect within its time at thirty
// frames a second, at a hundred and forty-four, and at frames that vary.
@(test)
test_card_demo_shows_its_effect_at_any_frame_rate :: proc(t: ^testing.T) {
	renderer := card_demo_test_renderer()
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	demo := new(Card_Demo)
	defer free(demo)
	defer card_demo_close(demo)
	rates := [?][]f32{{1.0/30.0}, {1.0/144.0}, {1.0/45.0, 1.0/90.0, 1.0/200.0, 1.0/60.0, 1.0/24.0}}
	for id in game.Card_Id {
		if id == .Count { continue }
		for upgrade in ([2]i32{0, game.card_max_upgrade_level(id)}) {
			for frames, rate in rates {
				if !testing.expectf(t, card_demo_open(demo, renderer, {definition_id = id, upgrade_level = upgrade}), "%v +%d: no film", id, upgrade) { continue }
				for frame := 0; demo.built && demo.stage != .Done && frame < 200*60; frame += 1 {
					card_demo_advance(demo, renderer, frames[frame%len(frames)])
				}
				missing, shown := card_demo_shown(demo, renderer)
				testing.expectf(t, shown && demo.stage == .Done && demo.take_time < CARD_DEMO_TAKE_LIMIT,
					"%v +%d at rate %d: played %v, missing %v, foes hurt %d, the take ran %.1f s", id, upgrade, rate, demo.played, missing,
					card_demo_foes_hurt(demo), demo.take_time)
			}
		}
	}
}

// A tactical board as MOSTRA EFFETTO's window lends it to a film
// (render.create_borrowed_renderer: its own view state, a showcase, and the
// run renderer's GPU assets, here none at all), and that run renderer; 3D as
// the run's is by default, or flat (--flat).
card_demo_test_board :: proc(board_3d := true) -> (board, main: ^render.Renderer) {
	main = card_demo_test_renderer()
	main.tactical.enabled, main.tactical.scene_3d, main.tactical.perspective = true, board_3d, board_3d
	board = render.create_borrowed_renderer(main, 960, 540, {})
	return
}

card_demo_test_board_free :: proc(board, main: ^render.Renderer) {
	render.destroy_borrowed_renderer(board)
	free(main)
}

// On a tactical board the film takes the board's own path: the glove goes
// where the board's camera shows the card and its target, the drag aims at
// the cell its floor's ray finds under the glove, the drop lands inside the
// board's area; a board with no window to draw it has no living cards (their
// clips are the drawing's). Every card shows its effect so as well, and at no
// frame does the caption's plate cover a card of the hand, the rod's slot or
// the board's bar.
@(test)
test_card_demo_plays_on_a_tactical_board :: proc(t: ^testing.T) {
	r, main := card_demo_test_board()
	defer card_demo_test_board_free(r, main)
	demo := new(Card_Demo)
	defer free(demo)
	defer card_demo_close(demo)
	for id in game.Card_Id {
		if id == .Count { continue }
		if !testing.expectf(t, card_demo_open(demo, r, {definition_id = id}), "%v: no film", id) { continue }
		testing.expect(t, card_demo_visual(r) && !r.tactical.living && r.tactical.showcase)
		covered: cstring
		covered_at: f32
		for frame := 0; demo.built && demo.stage != .Done && frame < 60*45; frame += 1 {
			card_demo_advance(demo, r, 1.0/60.0)
			if covered == nil { covered, covered_at = card_demo_plate_covers(demo, r), demo.take_time }
		}
		testing.expectf(t, covered == nil, "%v: the caption's plate covers %s at %.2f s", id, covered, covered_at)
		missing, shown := card_demo_shown(demo, r)
		testing.expectf(t, shown && demo.stage == .Done, "%v on a board: played %v, missing %v, foes hurt %d, the take ran %.1f s", id, demo.played,
			missing, card_demo_foes_hurt(demo), demo.take_time)
		testing.expectf(t, r.timeline.update_failures == 0, "%v on a board: %d timeline failures", id, r.timeline.update_failures)
	}
}

// The film loops on its own: a done take is followed by a fresh one, its
// caption back to the glove's gesture; RICOMINCIA starts it from its first
// frame; a card with no film (an unknown level) says so; closing it frees its
// room.
@(test)
test_card_demo_loops_restarts_and_closes :: proc(t: ^testing.T) {
	renderer := card_demo_test_renderer()
	defer free(renderer)
	defer render.destroy_renderer_world_playback(renderer)
	demo := new(Card_Demo)
	defer free(demo)
	defer card_demo_close(demo)
	testing.expect(t, card_demo_open(demo, renderer, {definition_id = .Guard}))
	testing.expect_value(t, card_demo_caption(demo), "DOPPIO CLIC SULLA CARTA")
	frames := 0
	for demo.takes < 2 && frames < 60*30 {
		card_demo_step(demo, renderer, 1.0/60.0)
		frames += 1
	}
	testing.expectf(t, demo.takes == 2 && demo.stage < .Effect, "the film did not loop: %d takes, stage %v", demo.takes, demo.stage)
	shield, shielded := game.status_for_entity(&demo.room, game.PLAYER_ENTITY, .Shield)
	testing.expectf(t, !shielded, "a fresh take keeps the last one's shield %v", shield)
	for _ in 0..<150 { card_demo_step(demo, renderer, 1.0/60.0) }
	testing.expect(t, demo.played)
	testing.expect_value(t, card_demo_caption(demo), string(CARD_DEMO_EFFECT_WORDS))
	card_demo_restart(demo, renderer)
	testing.expect(t, demo.stage == .Settle && demo.stage_time == 0 && !demo.played && demo.takes == 3)
	// A zero frame is a paused film.
	card_demo_step(demo, renderer, 0)
	testing.expect(t, demo.stage_time == 0)
	testing.expect(t, !card_demo_open(demo, renderer, {definition_id = .Strike, upgrade_level = game.card_max_upgrade_level(.Strike)+1}))
	testing.expect_value(t, card_demo_caption(demo), string(CARD_DEMO_NO_FILM_WORDS))
	testing.expect(t, card_demo_open(demo, renderer, {definition_id = .Arc_Bolt}))
	card_demo_close(demo)
	testing.expect(t, !demo.built && demo.room.enemies == nil && demo.data.tiles.cells == nil)
}

// Each scene's gesture is the one its card's targeting asks, with a foe to
// let it go on where it aims at one, and its foes stand on the floor.
@(test)
test_card_demo_scenes_follow_the_cards :: proc(t: ^testing.T) {
	for id in game.Card_Id {
		if id == .Count { continue }
		definition, _ := game.card_definition_by_id(id, true)
		scene := game.card_demo_scene(id)
		#partial switch definition.targeting.rule {
		case .Self, .Player, .None:
			testing.expectf(t, scene.gesture == .Double_Click, "%v: a card with nothing to aim at is played by a double click", id)
		case .Cell, .Walkable_Cell:
			if game.card_is_room_tool(id) { testing.expect(t, scene.gesture == .Rod_Slot && scene.cleared); break }
			testing.expectf(t, scene.gesture == .Drag_To_Cell || scene.gesture == .Drag_Along_Line, "%v: a cell card is dragged on a cell", id)
		case:
			testing.expectf(t, scene.gesture == .Drag_To_Foe || scene.gesture == .Drag_Along_Line, "%v: a foe card is dragged on a foe", id)
			testing.expectf(t, scene.foe_count > scene.target_foe, "%v: no foe to drag it on", id)
		}
		for foe in scene.foes[:scene.foe_count] {
			testing.expectf(t, foe.at.x > 0 && foe.at.y > 0 && foe.at.x < game.CARD_DEMO_WIDTH-1 && foe.at.y < game.CARD_DEMO_HEIGHT-1 &&
				foe.at != game.CARD_DEMO_PLAYER && foe.at != game.CARD_DEMO_EXIT, "%v: a foe off the floor at %v", id, foe.at)
		}
	}
}

// The film frames its scene: at a take's first frame every foe, object, coil
// and pool of every card's scene (at its first level and its top), and the
// cell the glove lets the card go on, stand on the stage, from their feet to
// their heads, under none of the HUD's VITA and pulse plates, the card
// inspector (shown while the glove carries the card), a card of the hand, the
// rod's slot or the caption's plate: what the take shows is in sight from its
// start, on a 3D board and on a flat one.
@(test)
test_card_demo_frames_its_scene :: proc(t: ^testing.T) {
	for board_3d in ([2]bool{true, false}) {
		r, main := card_demo_test_board(board_3d)
		defer card_demo_test_board_free(r, main)
		card_demo_test_frames_on(t, r, board_3d)
	}
}

card_demo_test_frames_on :: proc(t: ^testing.T, r: ^render.Renderer, board_3d: bool) {
	demo := new(Card_Demo)
	defer free(demo)
	defer card_demo_close(demo)
	hud := render.tactical_hud_layout(r)
	Spot :: struct { what: string, cell: grid.Position, height: f32 }
	for id in game.Card_Id {
		if id == .Count { continue }
		for level in ([2]i32{0, game.card_max_upgrade_level(id)}) {
			if !testing.expectf(t, card_demo_open(demo, r, {definition_id = id, upgrade_level = level}), "%v +%d: no film", id, level) { continue }
			testing.expect(t, r.tactical.scene_3d == board_3d)
			scene := &demo.scene
			spots: [game.CARD_DEMO_MAX_FOES+game.CARD_DEMO_MAX_OBJECTS+game.CARD_DEMO_MAX_COILS+game.CARD_DEMO_MAX_POOLS+1]Spot
			count := 0
			// A figure's head stands this high over its cell, a prop's lower (a
			// flat board draws them all on their cell).
			for foe in scene.foes[:scene.foe_count] { spots[count] = {"a foe", foe.at, 1.5}; count += 1 }
			for object in scene.objects[:scene.object_count] { spots[count] = {"an object", object.position, 1}; count += 1 }
			for coil in scene.coils[:scene.coil_count] { spots[count] = {"a coil", coil, 1}; count += 1 }
			for pool in scene.pools[:scene.pool_count] { spots[count] = {"a pool", pool, 0.05}; count += 1 }
			if scene.gesture != .Double_Click { spots[count] = {"its target", scene.target, 0.05}; count += 1 }
			Cover :: struct { what: cstring, bounds: rl.Rectangle }
			covers: [4+game.MAX_HAND_CARDS+1]Cover
			covers[0], covers[1] = {"the HUD's VITA plate", hud.vitals}, {"the HUD's pulse plate", hud.pulse}
			covers[2], covers[3] = {"the card inspector", render.tactical_card_inspector_bounds()}, {"the caption's plate", card_demo_caption_plate(demo, r)}
			cover_count := 4
			deck, phase := render.renderer_hand_deck(r, &demo.room)
			for index in 0..<deck.hand_count {
				covers[cover_count] = {"a card of the hand", render.hand_raised_card_bounds(r, index, deck.hand_count)}
				cover_count += 1
			}
			if phase == .Loot { covers[cover_count] = {"the rod's slot", render.fishing_slot_bounds(r)}; cover_count += 1 }
			for spot in spots[:count] {
				center := view.Vec2{f32(spot.cell.x)+0.5, f32(spot.cell.y)+0.5}
				for height in ([2]f32{0.05, spot.height}) {
					p := render.tactical_project(r, center, height)
					testing.expectf(t, p.x >= 4 && p.y >= 4 && p.x <= r.canvas_width-4 && p.y <= r.canvas_height-4,
						"%v +%d (3D %v): %s at %v stands off the stage (%v at %.2f)", id, level, board_3d, spot.what, spot.cell, p, height)
					for cover in covers[:cover_count] {
						testing.expectf(t, !render.point_in_rectangle(p, cover.bounds), "%v +%d (3D %v): %s at %v is under %s (%v at %.2f)", id, level,
							board_3d, spot.what, spot.cell, cover.what, p, height)
					}
				}
			}
		}
	}
}
